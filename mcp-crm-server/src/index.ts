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
let roleCode: string = "unknown";
let permissions: Map<string, RolePermission> = new Map();

// ---------------------------------------------------------------------------
// Auth + permission loading
// ---------------------------------------------------------------------------

async function initializeClient(): Promise<void> {
  supabase = createClient(SUPABASE_URL!, SUPABASE_ANON_KEY!);

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
    `[CRM MCP] Authenticated as ${CRM_EMAIL} | role: ${roleCode} | merchant: ${ctx.merchant_id} | tables: ${permissions.size}`
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
    `- No service role key ever used — all queries run as your user JWT`,
  ].join("\n");
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
