#!/usr/bin/env node

/**
 * CRM MCP Server
 *
 * Role-aware MCP server for Supabase CRM access.
 * Authenticates as a named role user, loads permissions from system_mcp_role_permissions,
 * and exposes scoped tools. All DB calls use the user JWT so RLS applies automatically.
 *
 * Roles supported: tester | store_admin | store_owner
 * Schema operations are NEVER exposed regardless of role.
 */

import { Server } from "@modelcontextprotocol/sdk/server/index.js";
import { StdioServerTransport } from "@modelcontextprotocol/sdk/server/stdio.js";
import {
  CallToolRequestSchema,
  ListToolsRequestSchema,
} from "@modelcontextprotocol/sdk/types.js";
import { createClient, SupabaseClient } from "@supabase/supabase-js";

// ---------------------------------------------------------------------------
// Config
// ---------------------------------------------------------------------------

const SUPABASE_URL = process.env.SUPABASE_URL;
const SUPABASE_ANON_KEY = process.env.SUPABASE_ANON_KEY;
const SUPABASE_SERVICE_ROLE_KEY = process.env.SUPABASE_SERVICE_ROLE_KEY;
const CRM_EMAIL = process.env.CRM_EMAIL;
const CRM_PASSWORD = process.env.CRM_PASSWORD;

if (!SUPABASE_URL || !SUPABASE_ANON_KEY || !CRM_EMAIL || !CRM_PASSWORD) {
  console.error(
    "Missing required env vars: SUPABASE_URL, SUPABASE_ANON_KEY, CRM_EMAIL, CRM_PASSWORD"
  );
  process.exit(1);
}

// ---------------------------------------------------------------------------
// Types
// ---------------------------------------------------------------------------

interface RolePermission {
  table_name: string;
  allow_select: boolean;
  allow_insert: boolean;
  allow_update: boolean;
  allow_delete: boolean;
  restricted_columns: string[];
  notes: string | null;
}

interface TableContext {
  table_name: string;
  purpose: string;
  key_columns: Record<string, string>;
  relationships: Record<string, string>;
  insert_notes: string | null;
  update_notes: string | null;
  common_scenarios: string[];
  restricted_columns: string[];
}

type FilterOperator = "eq" | "neq" | "gt" | "gte" | "lt" | "lte" | "like" | "ilike" | "in" | "is";

interface QueryFilter {
  column: string;
  operator: FilterOperator;
  value: unknown;
}

// ---------------------------------------------------------------------------
// State (loaded at startup)
// ---------------------------------------------------------------------------

let supabase: SupabaseClient;
let serviceSupabase: SupabaseClient | null = null;
let roleCode: string = "unknown";
let permissions: Map<string, RolePermission> = new Map();

// ---------------------------------------------------------------------------
// Auth + permission loading
// ---------------------------------------------------------------------------

async function initializeClient(): Promise<void> {
  supabase = createClient(SUPABASE_URL!, SUPABASE_ANON_KEY!);
  if (SUPABASE_SERVICE_ROLE_KEY) {
    serviceSupabase = createClient(SUPABASE_URL!, SUPABASE_SERVICE_ROLE_KEY);
  }

  const { data: authData, error: authError } =
    await supabase.auth.signInWithPassword({
      email: CRM_EMAIL!,
      password: CRM_PASSWORD!,
    });

  if (authError || !authData.user) {
    throw new Error(`Authentication failed: ${authError?.message}`);
  }

  // Resolve merchant_id and role via SECURITY DEFINER function (bypasses recursive RLS on admin_users)
  const { data: ctx, error: ctxError } = await supabase.rpc("get_mcp_auth_context");

  if (ctxError) {
    throw new Error(`get_mcp_auth_context failed: ${ctxError.message}`);
  }
  if (!ctx || ctx.error) {
    throw new Error(
      `No admin_users record found for this account. ` +
      `Make sure ${CRM_EMAIL} exists in admin_users with active_status=true. ` +
      `Detail: ${ctx?.error ?? "null response"} auth_uid=${authData.user.id}`
    );
  }

  roleCode = ctx.role_code;

  // Load permissions for this role
  const { data: perms, error: permsError } = await supabase
    .from("system_mcp_role_permissions")
    .select("*")
    .eq("role_code", roleCode);

  if (permsError) {
    throw new Error(`Failed to load permissions: ${permsError.message}`);
  }

  for (const perm of perms ?? []) {
    permissions.set(perm.table_name, {
      table_name: perm.table_name,
      allow_select: perm.allow_select,
      allow_insert: perm.allow_insert,
      allow_update: perm.allow_update,
      allow_delete: perm.allow_delete,
      restricted_columns: perm.restricted_columns ?? [],
      notes: perm.notes,
    });
  }

  console.error(
    `[CRM MCP] Authenticated as ${CRM_EMAIL} | role: ${roleCode} | merchant: ${ctx.merchant_id} | tables: ${permissions.size} | knowledge authoring: ${serviceSupabase ? "enabled" : "disabled"}`
  );
}

// ---------------------------------------------------------------------------
// Permission helpers
// ---------------------------------------------------------------------------

function getPermission(tableName: string): RolePermission | null {
  return permissions.get(tableName) ?? null;
}

function checkPermission(
  tableName: string,
  operation: "select" | "insert" | "update" | "delete"
): { allowed: boolean; reason?: string } {
  const perm = getPermission(tableName);
  if (!perm) {
    return {
      allowed: false,
      reason: `Table '${tableName}' is not in your role's allowlist. Role: ${roleCode}`,
    };
  }
  const allowed =
    operation === "select"
      ? perm.allow_select
      : operation === "insert"
      ? perm.allow_insert
      : operation === "update"
      ? perm.allow_update
      : perm.allow_delete;

  if (!allowed) {
    return {
      allowed: false,
      reason: `Role '${roleCode}' does not have ${operation.toUpperCase()} permission on '${tableName}'.`,
    };
  }
  return { allowed: true };
}

function stripRestrictedColumns<T extends Record<string, unknown>>(
  tableName: string,
  rows: T[]
): T[] {
  const perm = getPermission(tableName);
  if (!perm || perm.restricted_columns.length === 0) return rows;
  return rows.map((row) => {
    const stripped = { ...row };
    for (const col of perm.restricted_columns) {
      delete stripped[col];
    }
    return stripped;
  }) as T[];
}

function filterInputColumns(
  tableName: string,
  data: Record<string, unknown>
): Record<string, unknown> {
  const perm = getPermission(tableName);
  if (!perm || perm.restricted_columns.length === 0) return data;
  const filtered = { ...data };
  for (const col of perm.restricted_columns) {
    delete filtered[col];
  }
  return filtered;
}

// ---------------------------------------------------------------------------
// Tool implementations
// ---------------------------------------------------------------------------

async function toolListTables(): Promise<string> {
  const rows: string[] = [];
  for (const [table, perm] of permissions.entries()) {
    const ops = [
      perm.allow_select && "SELECT",
      perm.allow_insert && "INSERT",
      perm.allow_update && "UPDATE",
      perm.allow_delete && "DELETE",
    ]
      .filter(Boolean)
      .join(", ");
    rows.push(`• ${table} [${ops}]${perm.notes ? ` — ${perm.notes}` : ""}`);
  }
  rows.sort();
  return `Role: ${roleCode}\nAccessible tables (${permissions.size}):\n\n${rows.join("\n")}`;
}

async function toolQueryTable(
  tableName: string,
  filters: QueryFilter[],
  columns: string,
  limit: number
): Promise<string> {
  const check = checkPermission(tableName, "select");
  if (!check.allowed) return `Error: ${check.reason}`;

  const safeLimit = Math.min(limit || 50, 200);
  let query = supabase.from(tableName).select(columns || "*").limit(safeLimit);

  for (const f of filters ?? []) {
    const op = f.operator as FilterOperator;
    if (op === "eq") query = query.eq(f.column, f.value);
    else if (op === "neq") query = query.neq(f.column, f.value);
    else if (op === "gt") query = query.gt(f.column, f.value);
    else if (op === "gte") query = query.gte(f.column, f.value);
    else if (op === "lt") query = query.lt(f.column, f.value);
    else if (op === "lte") query = query.lte(f.column, f.value);
    else if (op === "like") query = query.like(f.column, String(f.value));
    else if (op === "ilike") query = query.ilike(f.column, String(f.value));
    else if (op === "in") query = query.in(f.column, f.value as unknown[]);
    else if (op === "is") query = query.is(f.column, f.value);
  }

  const { data, error } = await query;
  if (error) return `Query error: ${error.message}`;
  if (!data || data.length === 0) return `No rows found in '${tableName}'.`;

  const cleaned = stripRestrictedColumns(tableName, data as unknown as Record<string, unknown>[]);
  return JSON.stringify(cleaned, null, 2);
}

async function toolInsertRow(
  tableName: string,
  rowData: Record<string, unknown>
): Promise<string> {
  const check = checkPermission(tableName, "insert");
  if (!check.allowed) return `Error: ${check.reason}`;

  const safeData = filterInputColumns(tableName, rowData);

  const { data, error } = await supabase
    .from(tableName)
    .insert(safeData)
    .select()
    .single();

  if (error) return `Insert error: ${error.message}`;
  return `Inserted successfully.\n${JSON.stringify(stripRestrictedColumns(tableName, [data as Record<string, unknown>])[0], null, 2)}`;
}

async function toolUpdateRow(
  tableName: string,
  id: string,
  updates: Record<string, unknown>
): Promise<string> {
  const check = checkPermission(tableName, "update");
  if (!check.allowed) return `Error: ${check.reason}`;

  const safeUpdates = filterInputColumns(tableName, updates);

  const { data, error } = await supabase
    .from(tableName)
    .update(safeUpdates)
    .eq("id", id)
    .select()
    .single();

  if (error) return `Update error: ${error.message}`;
  return `Updated successfully.\n${JSON.stringify(stripRestrictedColumns(tableName, [data as Record<string, unknown>])[0], null, 2)}`;
}

async function toolDeleteRow(tableName: string, id: string): Promise<string> {
  const check = checkPermission(tableName, "delete");
  if (!check.allowed) return `Error: ${check.reason}`;

  const { error } = await supabase.from(tableName).delete().eq("id", id);
  if (error) return `Delete error: ${error.message}`;
  return `Deleted row id=${id} from '${tableName}'.`;
}

async function toolGetTableContext(tableName: string): Promise<string> {
  const { data, error } = await supabase
    .from("system_mcp_table_context")
    .select("*")
    .eq("table_name", tableName)
    .single();

  if (error || !data) {
    const perm = getPermission(tableName);
    if (!perm) return `No context found for '${tableName}' and it is not in your role's allowlist.`;
    return `No detailed context documented for '${tableName}' yet.\nPermissions: SELECT=${perm.allow_select}, INSERT=${perm.allow_insert}, UPDATE=${perm.allow_update}, DELETE=${perm.allow_delete}`;
  }

  const ctx = data as TableContext;
  const lines: string[] = [
    `## ${ctx.table_name}`,
    ``,
    `**Purpose:** ${ctx.purpose}`,
    ``,
  ];

  if (ctx.key_columns && Object.keys(ctx.key_columns).length > 0) {
    lines.push(`**Key Columns:**`);
    for (const [col, desc] of Object.entries(ctx.key_columns)) {
      lines.push(`  • \`${col}\` — ${desc}`);
    }
    lines.push(``);
  }

  if (ctx.relationships && Object.keys(ctx.relationships).length > 0) {
    lines.push(`**Relationships:**`);
    for (const [rel, desc] of Object.entries(ctx.relationships)) {
      lines.push(`  • \`${rel}\` — ${desc}`);
    }
    lines.push(``);
  }

  if (ctx.insert_notes) {
    lines.push(`**Insert Notes:** ${ctx.insert_notes}`);
    lines.push(``);
  }

  if (ctx.update_notes) {
    lines.push(`**Update Notes:** ${ctx.update_notes}`);
    lines.push(``);
  }

  if (ctx.common_scenarios?.length > 0) {
    lines.push(`**Common Scenarios:**`);
    for (const s of ctx.common_scenarios) {
      lines.push(`  • ${s}`);
    }
  }

  return lines.join("\n");
}

async function toolGetMyContext(): Promise<string> {
  return [
    `**Your Session**`,
    `Role: ${roleCode}`,
    `Email: ${CRM_EMAIL}`,
    `Merchant: auto-scoped from your admin_users record (RLS handles it)`,
    ``,
    `**What You Can Do**`,
    `- list_tables: see all tables you can access`,
    `- query_table: SELECT rows with filters`,
    `- insert_row: INSERT a new row (if your role allows)`,
    `- update_row: UPDATE a row by id (if your role allows)`,
    `- delete_row: DELETE a row by id (if your role allows)`,
    `- get_table_context: get detailed docs for any table`,
    ``,
    `**Guardrails (always enforced, not in DB)**`,
    `- No schema changes (CREATE TABLE, ALTER, DROP, migrations)`,
    `- No function creation or modification`,
    `- No access to auth system tables`,
    `- Generic CRM table tools always run as your user JWT`,
    ``,
    `**Knowledge MCP**`,
    `- Read tools are available through authenticated internal_knowledge RPCs`,
    `- For mapping a buyer/marketing term (e.g. "omnichannel", "journey builder") to an internal feature slug, call resolve_feature_term first`,
    `- For paraphrased or multi-feature questions, call search_semantic (vector similarity, cross-feature)`,
    `- For keyword-precise lookups, call search_feature_knowledge (full-text)`,
    `- Authoring tools are ${serviceSupabase ? "enabled with service-role RPC access" : "disabled because SUPABASE_SERVICE_ROLE_KEY is not configured"}`,
    `- Implementation object blocks are pointers; verify exact schemas/functions from live tools before coding`,
  ].join("\n");
}

function optionalTextArray(value: unknown): string[] | null {
  if (!Array.isArray(value)) return null;
  const values = value
    .map((item) => String(item).trim())
    .filter((item) => item.length > 0);
  return values.length > 0 ? values : null;
}

function optionalString(value: unknown): string | null {
  if (value === undefined || value === null) return null;
  const text = String(value).trim();
  return text.length > 0 ? text : null;
}

function jsonResult(data: unknown): string {
  return JSON.stringify(data, null, 2);
}

async function callKnowledgeRpc(
  client: SupabaseClient,
  fnName: string,
  args?: Record<string, unknown>
): Promise<string> {
  const { data, error } = await client.rpc(fnName, args ?? {});
  if (error) return `Knowledge RPC error (${fnName}): ${error.message}`;
  return jsonResult(data);
}

function getAuthoringClient(): SupabaseClient | string {
  if (!serviceSupabase) {
    return (
      "Knowledge authoring is not enabled for this MCP server. " +
      "Configure SUPABASE_SERVICE_ROLE_KEY only for trusted upstream authoring environments."
    );
  }
  return serviceSupabase;
}

async function toolGetFeatureTree(rootSlug?: unknown): Promise<string> {
  return callKnowledgeRpc(supabase, "internal_knowledge_get_feature_tree", {
    p_root_slug: optionalString(rootSlug),
  });
}

async function toolGetFeatureContext(args: Record<string, unknown>): Promise<string> {
  return callKnowledgeRpc(supabase, "internal_knowledge_get_feature_context", {
    p_feature_slug: String(args.feature_slug),
    p_knowledge_types: optionalTextArray(args.knowledge_types),
    p_perspectives: optionalTextArray(args.perspectives),
    p_output_uses: optionalTextArray(args.output_uses),
    p_scopes: optionalTextArray(args.scopes),
    p_include_children: args.include_children === undefined ? true : Boolean(args.include_children),
    p_include_parents: args.include_parents === undefined ? false : Boolean(args.include_parents),
  });
}

async function toolSearchFeatureKnowledge(args: Record<string, unknown>): Promise<string> {
  return callKnowledgeRpc(supabase, "internal_knowledge_search_feature_knowledge", {
    p_query: String(args.query),
    p_feature_slug: optionalString(args.feature_slug),
    p_knowledge_types: optionalTextArray(args.knowledge_types),
    p_perspectives: optionalTextArray(args.perspectives),
    p_output_uses: optionalTextArray(args.output_uses),
    p_scopes: optionalTextArray(args.scopes),
    p_limit: Math.min(Number(args.limit ?? 20), 50),
  });
}

async function toolGetRelatedFeatures(featureSlug: unknown): Promise<string> {
  return callKnowledgeRpc(supabase, "internal_knowledge_get_related_features", {
    p_feature_slug: String(featureSlug),
  });
}

async function toolListKnowledgeTypeTemplates(): Promise<string> {
  return callKnowledgeRpc(supabase, "internal_knowledge_list_knowledge_type_templates");
}

async function toolResolveFeatureTerm(query: unknown): Promise<string> {
  return callKnowledgeRpc(supabase, "internal_knowledge_resolve_feature_term", {
    p_query: String(query),
  });
}

async function embedQuery(query: string): Promise<number[]> {
  const { data, error } = await supabase.functions.invoke("embed-text", {
    body: { text: query },
  });
  if (error || !data) {
    throw new Error(
      `embed-text edge function failed: ${error?.message ?? "empty response"}`
    );
  }
  if (!Array.isArray(data.embeddings) || data.embeddings.length === 0) {
    throw new Error(`embed-text returned no embeddings: ${JSON.stringify(data)}`);
  }
  return data.embeddings[0] as number[];
}

async function toolSearchSemantic(args: Record<string, unknown>): Promise<string> {
  const query = String(args.query ?? "").trim();
  if (!query) return "Error: query is required";

  let embedding: number[];
  try {
    embedding = await embedQuery(query);
  } catch (err) {
    return `Failed to embed query: ${err instanceof Error ? err.message : String(err)}`;
  }

  return callKnowledgeRpc(supabase, "internal_knowledge_search_semantic", {
    p_query_embedding: embedding,
    p_top_k: Math.min(Number(args.top_k ?? 12), 50),
    p_feature_slugs: optionalTextArray(args.feature_slugs),
    p_knowledge_types: optionalTextArray(args.knowledge_types),
    p_min_similarity:
      args.min_similarity === undefined || args.min_similarity === null
        ? null
        : Number(args.min_similarity),
  });
}

async function toolSuggestBlockMetadata(knowledgeType: unknown): Promise<string> {
  const client = getAuthoringClient();
  if (typeof client === "string") return client;
  return callKnowledgeRpc(client, "internal_knowledge_suggest_block_metadata", {
    p_knowledge_type: String(knowledgeType),
  });
}

async function toolValidateKnowledgeBlock(args: Record<string, unknown>): Promise<string> {
  const client = getAuthoringClient();
  if (typeof client === "string") return client;
  return callKnowledgeRpc(client, "internal_knowledge_validate_knowledge_block", {
    p_title: String(args.title),
    p_content: String(args.content),
    p_knowledge_type: String(args.knowledge_type),
    p_perspectives: optionalTextArray(args.perspectives),
    p_output_uses: optionalTextArray(args.output_uses),
    p_scope: optionalString(args.scope),
  });
}

async function toolCreateFeatureItem(args: Record<string, unknown>): Promise<string> {
  const client = getAuthoringClient();
  if (typeof client === "string") return client;
  return callKnowledgeRpc(client, "internal_knowledge_create_feature_item", {
    p_slug: String(args.slug),
    p_name: String(args.name),
    p_item_type: String(args.item_type),
    p_parent_id: optionalString(args.parent_id),
    p_description: optionalString(args.description),
    p_sort_order: Number(args.sort_order ?? 0),
    p_metadata: (args.metadata as Record<string, unknown>) ?? {},
  });
}

async function toolUpdateFeatureItem(args: Record<string, unknown>): Promise<string> {
  const client = getAuthoringClient();
  if (typeof client === "string") return client;
  return callKnowledgeRpc(client, "internal_knowledge_update_feature_item", {
    p_item_id: String(args.item_id),
    p_slug: optionalString(args.slug),
    p_name: optionalString(args.name),
    p_item_type: optionalString(args.item_type),
    p_parent_id: optionalString(args.parent_id),
    p_description: optionalString(args.description),
    p_sort_order: args.sort_order === undefined ? null : Number(args.sort_order),
    p_metadata: (args.metadata as Record<string, unknown> | undefined) ?? null,
    p_is_active: args.is_active === undefined ? null : Boolean(args.is_active),
  });
}

async function toolCreateKnowledgeBlock(args: Record<string, unknown>): Promise<string> {
  const client = getAuthoringClient();
  if (typeof client === "string") return client;
  return callKnowledgeRpc(client, "internal_knowledge_create_knowledge_block", {
    p_feature_item_id: String(args.feature_item_id),
    p_title: String(args.title),
    p_content: String(args.content),
    p_knowledge_type: String(args.knowledge_type),
    p_perspectives: optionalTextArray(args.perspectives) ?? ["general"],
    p_output_uses: optionalTextArray(args.output_uses) ?? ["agent_context"],
    p_scope: optionalString(args.scope) ?? "general",
    p_source_ref: optionalString(args.source_ref),
    p_metadata: (args.metadata as Record<string, unknown>) ?? {},
    p_content_format: optionalString(args.content_format) ?? "markdown",
  });
}

async function toolUpdateKnowledgeBlock(args: Record<string, unknown>): Promise<string> {
  const client = getAuthoringClient();
  if (typeof client === "string") return client;
  return callKnowledgeRpc(client, "internal_knowledge_update_knowledge_block", {
    p_block_id: String(args.block_id),
    p_feature_item_id: optionalString(args.feature_item_id),
    p_title: optionalString(args.title),
    p_content: optionalString(args.content),
    p_knowledge_type: optionalString(args.knowledge_type),
    p_perspectives: optionalTextArray(args.perspectives),
    p_output_uses: optionalTextArray(args.output_uses),
    p_scope: optionalString(args.scope),
    p_source_ref: optionalString(args.source_ref),
    p_metadata: (args.metadata as Record<string, unknown> | undefined) ?? null,
    p_content_format: optionalString(args.content_format),
    p_is_active: args.is_active === undefined ? null : Boolean(args.is_active),
  });
}

// ---------------------------------------------------------------------------
// Tool definitions (Option A: rich descriptions baked in)
// ---------------------------------------------------------------------------

const TOOL_DEFINITIONS = [
  {
    name: "get_my_context",
    description:
      "Returns your current session info: role, allowed operations, and guardrails. Call this first if you are unsure what you can do.",
    inputSchema: {
      type: "object" as const,
      properties: {},
      required: [],
    },
  },
  {
    name: "list_tables",
    description:
      "Lists all CRM tables your role can access, with allowed operations (SELECT/INSERT/UPDATE/DELETE) for each. Call this to discover which tables are available before querying or inserting.",
    inputSchema: {
      type: "object" as const,
      properties: {},
      required: [],
    },
  },
  {
    name: "get_table_context",
    description:
      "Returns detailed domain documentation for a table: its purpose in the CRM, key column descriptions, relationships to other tables, insert/update notes, and common test scenarios. Call this before inserting into an unfamiliar table or when you need to understand what a table does.",
    inputSchema: {
      type: "object" as const,
      properties: {
        table_name: {
          type: "string",
          description: "The table to get documentation for. e.g. user_accounts, purchase_ledger",
        },
      },
      required: ["table_name"],
    },
  },
  {
    name: "get_feature_tree",
    description:
      "Knowledge MCP read tool. Returns the active internal feature hierarchy. Use this to discover feature slugs before requesting context. Optional root_slug narrows the tree.",
    inputSchema: {
      type: "object" as const,
      properties: {
        root_slug: {
          type: "string",
          description: "Optional feature/domain slug to use as the tree root, e.g. rewards, loyalty, customer-service.",
        },
      },
      required: [],
    },
  },
  {
    name: "get_feature_context",
    description:
      "Knowledge MCP read tool. Returns typed reusable knowledge blocks for a feature. Use filters by project type: marketing uses overview/value_proposition/related_features; frontend uses configuration_reference/admin_journey/user_experience/testing_guidance; backend uses technical_overview/implementation_objects/technical_flow/implementation_constraints; QA uses testing_guidance/business_rules/limitations. Editorial convention: technical knowledge types attach at FEATURE level; journey types (overview/user_experience/admin_journey/business_rules) typically attach at SUB-FEATURE level. When you land on a sub-feature and need technical content, set include_parents=true to walk UP to the parent feature.",
    inputSchema: {
      type: "object" as const,
      properties: {
        feature_slug: { type: "string", description: "Feature or sub-feature slug, e.g. rewards, tier-upgrade, cs-knowledge-base, amp-workflows." },
        knowledge_types: {
          type: "array",
          items: { type: "string" },
          description: "Optional knowledge type filters, e.g. ['overview','business_rules'].",
        },
        perspectives: {
          type: "array",
          items: { type: "string" },
          description: "Optional perspective filters, e.g. ['frontend','testing'].",
        },
        output_uses: {
          type: "array",
          items: { type: "string" },
          description: "Optional output-use filters, e.g. ['frontend_context','qa_testing'].",
        },
        scopes: {
          type: "array",
          items: { type: "string" },
          description: "Optional scope filters: general, admin_fe, user_fe, be, integration.",
        },
        include_children: {
          type: "boolean",
          description: "Walk DOWN the tree and include descendant (sub-feature) blocks. Default true.",
        },
        include_parents: {
          type: "boolean",
          description: "Walk UP the tree and include ancestor (parent feature, domain) blocks. Default false. Set true when querying a sub-feature for content that lives at the parent level (typically technical content).",
        },
      },
      required: ["feature_slug"],
    },
  },
  {
    name: "search_feature_knowledge",
    description:
      "Knowledge MCP read tool. Full-text searches internal feature knowledge. Best for keyword-precise lookups. For paraphrased questions or cross-feature queries, prefer search_semantic. For mapping a buyer/marketing term to an internal slug, use resolve_feature_term first.",
    inputSchema: {
      type: "object" as const,
      properties: {
        query: { type: "string", description: "Search text, e.g. redemption points, CS knowledge base embedding." },
        feature_slug: { type: "string", description: "Optional feature slug to restrict search." },
        knowledge_types: { type: "array", items: { type: "string" } },
        perspectives: { type: "array", items: { type: "string" } },
        output_uses: { type: "array", items: { type: "string" } },
        scopes: { type: "array", items: { type: "string" } },
        limit: { type: "number", description: "Max results. Default 20, capped at 50." },
      },
      required: ["query"],
    },
  },
  {
    name: "resolve_feature_term",
    description:
      "Knowledge MCP read tool. Resolves an external/buyer-facing term (e.g. 'omnichannel', 'journey builder', 'marketing automation', 'spin wheel') to internal feature_items via curated aliases, slug, and name matching. Returns matches ordered by match strength (slug_exact > alias_exact > name_exact > partial) then by item type (domain > feature > sub_feature). Use this BEFORE get_feature_context when the user's term might not be the internal slug.",
    inputSchema: {
      type: "object" as const,
      properties: {
        query: {
          type: "string",
          description: "Term as the user said it, e.g. 'omnichannel', 'spin wheel', 'journey builder'.",
        },
      },
      required: ["query"],
    },
  },
  {
    name: "search_semantic",
    description:
      "Knowledge MCP read tool. Cross-feature semantic block retrieval. Embeds the query (OpenAI text-embedding-3-large @ 1536) and returns the top-K most similar active blocks across ALL features. Best for paraphrased questions, multi-feature questions ('how do tier-based campaigns work for VIP win-back'), or any case where the right answer spans multiple features. Follow up with get_feature_context on the highest-similarity feature for canonical detail. OpenAI key is centralised in Supabase; downstream installs do not need their own.",
    inputSchema: {
      type: "object" as const,
      properties: {
        query: {
          type: "string",
          description: "Natural-language question or topic, e.g. 'how do tier-based bonus point campaigns work for VIP win-back'.",
        },
        top_k: {
          type: "number",
          description: "Number of top matches to return. Default 12, capped at 50.",
        },
        feature_slugs: {
          type: "array",
          items: { type: "string" },
          description: "Optional. Restrict search to specific feature slugs.",
        },
        knowledge_types: {
          type: "array",
          items: { type: "string" },
          description: "Optional. Restrict to specific knowledge types, e.g. ['overview','value_proposition'].",
        },
        min_similarity: {
          type: "number",
          description: "Optional. Cosine similarity floor in [0,1]. Filters out low-similarity matches.",
        },
      },
      required: ["query"],
    },
  },
  {
    name: "get_related_features",
    description:
      "Knowledge MCP read tool. Returns hierarchy and related-feature blocks for a feature. Use this when a task spans multiple features or needs dependency context.",
    inputSchema: {
      type: "object" as const,
      properties: {
        feature_slug: { type: "string", description: "Feature slug, e.g. rewards." },
      },
      required: ["feature_slug"],
    },
  },
  {
    name: "list_knowledge_type_templates",
    description:
      "Knowledge MCP read tool. Lists authoring guidance for each knowledge_type, including expected content, scopes, and quality rules.",
    inputSchema: {
      type: "object" as const,
      properties: {},
      required: [],
    },
  },
  {
    name: "suggest_block_metadata",
    description:
      "Knowledge MCP upstream authoring tool. Returns recommended scopes and quality rules for a knowledge_type. Requires SUPABASE_SERVICE_ROLE_KEY on this MCP server.",
    inputSchema: {
      type: "object" as const,
      properties: {
        knowledge_type: { type: "string", description: "Knowledge type, e.g. testing_guidance." },
      },
      required: ["knowledge_type"],
    },
  },
  {
    name: "validate_knowledge_block",
    description:
      "Knowledge MCP upstream authoring tool. Validates a proposed block before creation/update. Requires SUPABASE_SERVICE_ROLE_KEY on this MCP server.",
    inputSchema: {
      type: "object" as const,
      properties: {
        title: { type: "string" },
        content: { type: "string" },
        knowledge_type: { type: "string" },
        perspectives: { type: "array", items: { type: "string" } },
        output_uses: { type: "array", items: { type: "string" } },
        scope: { type: "string" },
      },
      required: ["title", "content", "knowledge_type"],
    },
  },
  {
    name: "create_feature_item",
    description:
      "Knowledge MCP upstream authoring tool. Creates a domain, feature, or sub_feature item. Requires SUPABASE_SERVICE_ROLE_KEY on this MCP server. Use get_feature_tree first to avoid duplicate slugs.",
    inputSchema: {
      type: "object" as const,
      properties: {
        slug: { type: "string" },
        name: { type: "string" },
        item_type: { type: "string", enum: ["domain", "feature", "sub_feature"] },
        parent_id: { type: "string", description: "Optional parent feature item UUID." },
        description: { type: "string" },
        sort_order: { type: "number" },
        metadata: { type: "object" },
      },
      required: ["slug", "name", "item_type"],
    },
  },
  {
    name: "update_feature_item",
    description:
      "Knowledge MCP upstream authoring tool. Updates or deactivates an existing feature item. Requires SUPABASE_SERVICE_ROLE_KEY on this MCP server.",
    inputSchema: {
      type: "object" as const,
      properties: {
        item_id: { type: "string", description: "Feature item UUID." },
        slug: { type: "string" },
        name: { type: "string" },
        item_type: { type: "string", enum: ["domain", "feature", "sub_feature"] },
        parent_id: { type: "string" },
        description: { type: "string" },
        sort_order: { type: "number" },
        metadata: { type: "object" },
        is_active: { type: "boolean" },
      },
      required: ["item_id"],
    },
  },
  {
    name: "create_knowledge_block",
    description:
      "Knowledge MCP upstream authoring tool. Creates a typed Markdown/plain-text knowledge block. Requires SUPABASE_SERVICE_ROLE_KEY on this MCP server. Call validate_knowledge_block first.",
    inputSchema: {
      type: "object" as const,
      properties: {
        feature_item_id: { type: "string", description: "Feature item UUID from get_feature_tree/get_feature_context." },
        title: { type: "string" },
        content: { type: "string" },
        knowledge_type: { type: "string" },
        perspectives: { type: "array", items: { type: "string" } },
        output_uses: { type: "array", items: { type: "string" } },
        scope: { type: "string" },
        source_ref: { type: "string" },
        metadata: { type: "object" },
        content_format: { type: "string", enum: ["markdown", "plain_text"] },
      },
      required: ["feature_item_id", "title", "content", "knowledge_type"],
    },
  },
  {
    name: "update_knowledge_block",
    description:
      "Knowledge MCP upstream authoring tool. Updates or deactivates an existing knowledge block. Requires SUPABASE_SERVICE_ROLE_KEY on this MCP server. Call validate_knowledge_block when changing title/content/type metadata.",
    inputSchema: {
      type: "object" as const,
      properties: {
        block_id: { type: "string", description: "Knowledge block UUID." },
        feature_item_id: { type: "string" },
        title: { type: "string" },
        content: { type: "string" },
        knowledge_type: { type: "string" },
        perspectives: { type: "array", items: { type: "string" } },
        output_uses: { type: "array", items: { type: "string" } },
        scope: { type: "string" },
        source_ref: { type: "string" },
        metadata: { type: "object" },
        content_format: { type: "string", enum: ["markdown", "plain_text"] },
        is_active: { type: "boolean" },
      },
      required: ["block_id"],
    },
  },
  {
    name: "query_table",
    description:
      "SELECT rows from a CRM table with optional filters. Use to look up IDs before inserting related records, verify inserted data, or read current state. merchant_id is auto-scoped by RLS — do not filter on it. Max 200 rows.",
    inputSchema: {
      type: "object" as const,
      properties: {
        table_name: {
          type: "string",
          description: "Table to query. Must be in your role's allowlist.",
        },
        filters: {
          type: "array",
          description:
            "Optional filter conditions. Each filter: {column, operator, value}. Operators: eq | neq | gt | gte | lt | lte | like | ilike | in | is",
          items: {
            type: "object",
            properties: {
              column: { type: "string" },
              operator: {
                type: "string",
                enum: ["eq", "neq", "gt", "gte", "lt", "lte", "like", "ilike", "in", "is"],
              },
              value: { description: "Filter value. Use array for 'in' operator." },
            },
            required: ["column", "operator", "value"],
          },
        },
        columns: {
          type: "string",
          description: "Columns to return. Default: * (all). Example: 'id, tel, tier_id'",
        },
        limit: {
          type: "number",
          description: "Max rows to return. Default: 50. Max: 200.",
        },
      },
      required: ["table_name"],
    },
  },
  {
    name: "insert_row",
    description:
      "INSERT a new row into a CRM table. merchant_id is auto-injected by RLS from your session — do not pass it. Call get_table_context first to understand required fields, auto-populated fields, and uniqueness constraints. Only available for tables your role can INSERT.",
    inputSchema: {
      type: "object" as const,
      properties: {
        table_name: {
          type: "string",
          description: "Table to insert into.",
        },
        data: {
          type: "object",
          description:
            "Row data as key-value pairs. Do not include merchant_id (auto from session). Check get_table_context for required fields.",
        },
      },
      required: ["table_name", "data"],
    },
  },
  {
    name: "update_row",
    description:
      "UPDATE an existing row by its id column. Only updates the fields you provide. merchant_id and id cannot be changed. Only available for tables your role can UPDATE.",
    inputSchema: {
      type: "object" as const,
      properties: {
        table_name: {
          type: "string",
          description: "Table to update.",
        },
        id: {
          type: "string",
          description: "UUID of the row to update.",
        },
        updates: {
          type: "object",
          description: "Fields to update as key-value pairs. Only the fields you provide are changed.",
        },
      },
      required: ["table_name", "id", "updates"],
    },
  },
  {
    name: "delete_row",
    description:
      "DELETE a row by its id column. Only available for tables your role can DELETE (typically tester role only). Use with care — this is permanent.",
    inputSchema: {
      type: "object" as const,
      properties: {
        table_name: {
          type: "string",
          description: "Table to delete from.",
        },
        id: {
          type: "string",
          description: "UUID of the row to delete.",
        },
      },
      required: ["table_name", "id"],
    },
  },
];

// ---------------------------------------------------------------------------
// Server setup
// ---------------------------------------------------------------------------

async function main() {
  await initializeClient();

  const server = new Server(
    {
      name: "mcp-crm-server",
      version: "1.0.0",
    },
    {
      capabilities: {
        tools: {},
      },
    }
  );

  server.setRequestHandler(ListToolsRequestSchema, async () => ({
    tools: TOOL_DEFINITIONS,
  }));

  server.setRequestHandler(CallToolRequestSchema, async (request) => {
    const { name, arguments: args } = request.params;
    const a = (args ?? {}) as Record<string, unknown>;

    let result: string;

    try {
      switch (name) {
        case "get_my_context":
          result = await toolGetMyContext();
          break;
        case "list_tables":
          result = await toolListTables();
          break;
        case "get_table_context":
          result = await toolGetTableContext(String(a.table_name));
          break;
        case "get_feature_tree":
          result = await toolGetFeatureTree(a.root_slug);
          break;
        case "get_feature_context":
          result = await toolGetFeatureContext(a);
          break;
        case "search_feature_knowledge":
          result = await toolSearchFeatureKnowledge(a);
          break;
        case "resolve_feature_term":
          result = await toolResolveFeatureTerm(a.query);
          break;
        case "search_semantic":
          result = await toolSearchSemantic(a);
          break;
        case "get_related_features":
          result = await toolGetRelatedFeatures(a.feature_slug);
          break;
        case "list_knowledge_type_templates":
          result = await toolListKnowledgeTypeTemplates();
          break;
        case "suggest_block_metadata":
          result = await toolSuggestBlockMetadata(a.knowledge_type);
          break;
        case "validate_knowledge_block":
          result = await toolValidateKnowledgeBlock(a);
          break;
        case "create_feature_item":
          result = await toolCreateFeatureItem(a);
          break;
        case "update_feature_item":
          result = await toolUpdateFeatureItem(a);
          break;
        case "create_knowledge_block":
          result = await toolCreateKnowledgeBlock(a);
          break;
        case "update_knowledge_block":
          result = await toolUpdateKnowledgeBlock(a);
          break;
        case "query_table":
          result = await toolQueryTable(
            String(a.table_name),
            (a.filters as QueryFilter[]) ?? [],
            String(a.columns ?? "*"),
            Number(a.limit ?? 50)
          );
          break;
        case "insert_row":
          result = await toolInsertRow(
            String(a.table_name),
            (a.data as Record<string, unknown>) ?? {}
          );
          break;
        case "update_row":
          result = await toolUpdateRow(
            String(a.table_name),
            String(a.id),
            (a.updates as Record<string, unknown>) ?? {}
          );
          break;
        case "delete_row":
          result = await toolDeleteRow(String(a.table_name), String(a.id));
          break;
        default:
          result = `Unknown tool: ${name}`;
      }
    } catch (err) {
      result = `Unexpected error: ${err instanceof Error ? err.message : String(err)}`;
    }

    return {
      content: [{ type: "text" as const, text: result }],
    };
  });

  const transport = new StdioServerTransport();
  await server.connect(transport);
  console.error("[CRM MCP] Server running on stdio");
}

main().catch((err) => {
  console.error("[CRM MCP] Fatal:", err.message);
  process.exit(1);
});
