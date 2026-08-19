import { Inngest, referenceFunction } from "https://esm.sh/inngest@3.54.0";
import { serve } from "https://esm.sh/inngest@3.54.0/edge";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.46.0";
const inngest = new Inngest({
  id: "crm-workflows"
});
const SUPABASE_URL = Deno.env.get("SUPABASE_URL");
const SUPABASE_SERVICE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
const MESSAGING_SERVICE_URL = Deno.env.get("MESSAGING_SERVICE_URL") || "https://messaging-service-li40.onrender.com";
const agentFunctionRef = referenceFunction({
  functionId: "marketing-decision-agent",
  appId: "crm-agent-service"
});

const AMP_POSTBACK_SECRET = Deno.env.get("AMP_POSTBACK_SECRET") || Deno.env.get("INTERNAL_WEBHOOK_SECRET") || "";
const INNGEST_EVENT_KEY = Deno.env.get("INNGEST_EVENT_KEY") || "";
const INNGEST_EVENT_URL = INNGEST_EVENT_KEY ? `https://inn.gs/e/${INNGEST_EVENT_KEY}` : "";

function compactUuid(uuid: string): string {
  const hex = uuid.replace(/-/g, "");
  const bytes = new Uint8Array(16);
  for (let i = 0; i < 16; i++) bytes[i] = parseInt(hex.slice(i * 2, i * 2 + 2), 16);
  let bin = "";
  for (const b of bytes) bin += String.fromCharCode(b);
  return btoa(bin).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
}

async function hmacSha256Hex(message: string, secret: string): Promise<string> {
  const encoder = new TextEncoder();
  const key = await crypto.subtle.importKey("raw", encoder.encode(secret), { name: "HMAC", hash: "SHA-256" }, false, ["sign"]);
  const sig = await crypto.subtle.sign("HMAC", key, encoder.encode(message));
  return Array.from(new Uint8Array(sig)).map((b) => b.toString(16).padStart(2, "0")).join("");
}

async function signAmpPostback(workflowLogId: string, messageNodeId: string, actionKey: string): Promise<string> {
  const r = compactUuid(workflowLogId);
  const n = compactUuid(messageNodeId);
  const a = actionKey;
  const canonical = `a=${a}&n=${n}&r=${r}&src=amp&v=1`;
  const full = await hmacSha256Hex(canonical, AMP_POSTBACK_SECRET);
  return `src=amp&v=1&r=${r}&n=${n}&a=${a}&s=${full.slice(0, 16)}`;
}

async function buildQuickReplyItems(pills: any[], workflowLogId: string, messageNodeId: string): Promise<any> {
  const items = [];
  for (const pill of pills || []) {
    const label = String(pill.label || pill.action_key || "Option").slice(0, 20);
    const actionKey = String(pill.action_key || "");
    if (!actionKey) continue;
    const data = await signAmpPostback(workflowLogId, messageNodeId, actionKey);
    const action: any = { type: "postback", label, data };
    if (pill.display_text) action.displayText = String(pill.display_text).slice(0, 300);
    items.push({ type: "action", action });
  }
  return { items };
}

function parseActionKeyList(raw: string): string[] | null {
  const parts = raw.split(",").map((s) => s.trim()).filter(Boolean);
  if (parts.length === 0 || parts.length > 5) return null;
  if (parts.some((p) => p.length > 64 || /[^a-zA-Z0-9._-]/.test(p))) return null;
  return parts;
}

function extractActionKeyFromPostbackData(data: string): string | null {
  if (!data) return null;
  try {
    if (data.includes("=")) {
      const params = new URLSearchParams(data);
      const a = params.get("a") || params.get("action") || params.get("postback_text") || "";
      const keys = parseActionKeyList(a);
      return keys ? keys.join(",") : null;
    }
    // Plain action key (rare)
    const keys = parseActionKeyList(data);
    return keys ? keys.join(",") : null;
  } catch {
    return null;
  }
}

/** Rewrite Flex/template postback `data` (e.g. Content Library src=resource) to signed AMP postbacks. */
async function signPostbacksInObject(node: any, workflowLogId: string, messageNodeId: string, stats: { signed: number; keys: string[] }): Promise<any> {
  if (node == null || typeof node !== "object") return node;
  if (Array.isArray(node)) {
    for (let i = 0; i < node.length; i++) {
      node[i] = await signPostbacksInObject(node[i], workflowLogId, messageNodeId, stats);
    }
    return node;
  }
  if (node.type === "postback" && typeof node.data === "string") {
    const actionKey = extractActionKeyFromPostbackData(node.data);
    if (actionKey) {
      node.data = await signAmpPostback(workflowLogId, messageNodeId, actionKey);
      stats.signed += 1;
      for (const key of actionKey.split(",")) {
        if (key && !stats.keys.includes(key)) stats.keys.push(key);
      }
    }
  }
  for (const key of Object.keys(node)) {
    if (node.type === "postback" && key === "data") continue;
    const v = node[key];
    if (v && typeof v === "object") {
      node[key] = await signPostbacksInObject(v, workflowLogId, messageNodeId, stats);
    }
  }
  return node;
}

async function signAmpPostbacksInMessages(messages: any[], workflowLogId: string, messageNodeId: string): Promise<{ messages: any[]; signed_count: number; action_keys: string[] }> {
  const stats = { signed: 0, keys: [] as string[] };
  const out: any[] = [];
  for (const msg of messages || []) {
    const m = { ...msg };
    if (m.type === "flex" && m.contents) {
      m.contents = await signPostbacksInObject(JSON.parse(JSON.stringify(m.contents)), workflowLogId, messageNodeId, stats);
    }
    if (m.type === "template" && m.template) {
      m.template = await signPostbacksInObject(JSON.parse(JSON.stringify(m.template)), workflowLogId, messageNodeId, stats);
    }
    // quickReply items embedded on resolved messages (non-pill path)
    if (m.quickReply?.items) {
      m.quickReply = await signPostbacksInObject(JSON.parse(JSON.stringify(m.quickReply)), workflowLogId, messageNodeId, stats);
    }
    if (m.metadata?.quickReply?.items) {
      m.metadata = { ...m.metadata, quickReply: await signPostbacksInObject(JSON.parse(JSON.stringify(m.metadata.quickReply)), workflowLogId, messageNodeId, stats) };
    }
    out.push(m);
  }
  return { messages: out, signed_count: stats.signed, action_keys: stats.keys };
}



function buildRouteSnapshot(nodes: any[], edges: any[], messageNodeId: string, workflowId: string, workflowUpdatedAt: any): any {
  const router = nodes.find((n: any) => n.node_type === "interaction_router" && (n.node_config?.message_node_id === messageNodeId || !n.node_config?.message_node_id));
  const cfg = router?.node_config || {};
  const routes: Record<string, string> = {};
  const allowed: string[] = [];
  for (const r of cfg.routes || []) {
    const key = r.action_key;
    if (!key) continue;
    allowed.push(key);
    const handle = r.handle || `route:${key}`;
    const edge = edges.find((e: any) => e.from_node_id === router?.id && (e.source_handle === handle || e.source_handle === key || e.source_handle === `route:${key}`));
    if (edge?.to_node_id) routes[key] = edge.to_node_id;
  }
  if (router && allowed.length === 0) {
    for (const e of edges.filter((x: any) => x.from_node_id === router.id)) {
      const h = e.source_handle || "";
      const key = h.startsWith("route:") ? h.slice(6) : h;
      if (key && key !== "default") { allowed.push(key); routes[key] = e.to_node_id; }
    }
  }
  return { message_node_id: messageNodeId, workflow_id: workflowId, selection_mode: cfg.selection_mode || "single", allowed_action_keys: allowed, routes, revision: workflowUpdatedAt || null };
}

function resolveLineRecipient(run_scope: string, user_id: string | null, line_user_id: string | null): any {
  if (run_scope === "broadcast") return { mode: "broadcast" };
  if (line_user_id) return { mode: "push", direct: { line_id: line_user_id } };
  if (user_id) return { mode: "push", user_id };
  return { mode: "push", user_id };
}

async function emitInngestEvent(name: string, data: any): Promise<void> {
  if (!INNGEST_EVENT_URL) { console.error("INNGEST_EVENT_KEY missing"); return; }
  await fetch(INNGEST_EVENT_URL, { method: "POST", headers: { "Content-Type": "application/json" }, body: JSON.stringify({ name, data }) });
}

function timeRangeToFrom(tr: string | null | undefined): string | null {
  if (!tr) return null;
  const m: Record<string, number> = { "7d": 7, "14d": 14, "30d": 30, "90d": 90, "180d": 180, "365d": 365, last_7_days: 7, last_30_days: 30, last_90_days: 90 };
  const days = m[tr] || (tr.endsWith("d") ? parseInt(tr) : 0);
  if (!days) return null;
  return new Date(Date.now() - days * 86400000).toISOString();
}


function getSupabase() {
  return createClient(SUPABASE_URL, SUPABASE_SERVICE_KEY);
}
function unwrapCached(raw) {
  if (!raw) return raw;
  const parsed = typeof raw === "string" ? JSON.parse(raw) : raw;
  return parsed?.data !== undefined ? parsed.data : parsed;
}
function substituteVariables(text, context) {
  if (!text) return text;
  return text.replace(/\{\{([^}]+)\}\}/g, (_match, path)=>{
    const keys = path.trim().split(".");
    let value = context;
    for (const key of keys){
      value = value?.[key];
      if (value === undefined || value === null) return "";
    }
    return String(value);
  });
}
function substituteDeep(value, context) {
  if (typeof value === "string") return substituteVariables(value, context);
  if (Array.isArray(value)) return value.map((item)=>substituteDeep(item, context));
  if (value && typeof value === "object") {
    const out = {};
    for (const [k, v] of Object.entries(value))out[k] = substituteDeep(v, context);
    return out;
  }
  return value;
}
async function buildTemplateContext(supabase, user_id, merchant_id, trigger_data) {
  let userRow = null;
  if (user_id) {
    const { data } = await supabase.from("user_accounts").select("*").eq("id", user_id).single();
    userRow = data;
  }
  let points_balance = null;
  if (userRow) {
    const { data: wallet } = await supabase.from("user_wallet").select("points_balance").eq("user_id", user_id).eq("merchant_id", merchant_id).maybeSingle();
    points_balance = wallet?.points_balance ?? null;
  }
  const user = userRow ? {
    ...userRow,
    firstname: userRow.firstname ?? "",
    lastname: userRow.lastname ?? "",
    fullname: userRow.fullname ?? [
      userRow.firstname,
      userRow.lastname
    ].filter(Boolean).join(" ").trim(),
    email: userRow.email ?? "",
    tel: userRow.tel ?? "",
    phone: userRow.tel ?? "",
    line_id: userRow.line_id ?? "",
    tier_id: userRow.tier_id ?? "",
    persona_id: userRow.persona_id ?? "",
    points_balance: points_balance ?? 0
  } : null;
  return {
    user,
    trigger: trigger_data || {},
    merchant_id,
    user_id
  };
}
function ampMessageToOutbound(msg) {
  if (msg.type === "text") {
    const out = { type: "text", content: msg.text || msg.content || "" };
    if (msg.quickReply) out.metadata = { ...(out.metadata || {}), quickReply: msg.quickReply };
    if (msg.metadata?.quickReply) out.metadata = { ...(out.metadata || {}), quickReply: msg.metadata.quickReply };
    return out;
  }
  if (msg.type === "flex") {
    const metadata = { altText: msg.altText, contents: msg.contents };
    if (msg.quickReply) metadata.quickReply = msg.quickReply;
    if (msg.metadata?.quickReply) metadata.quickReply = msg.metadata.quickReply;
    return { type: "flex", content: msg.altText || "Message", metadata };
  }
  if (msg.type === "image") return {
    type: "image",
    content: msg.originalContentUrl || "",
    metadata: { previewImageUrl: msg.previewImageUrl }
  };
  if (msg.type === "template") return {
    type: "template",
    content: msg.altText || "Message",
    metadata: { altText: msg.altText, template: msg.template }
  };
  return { type: "text", content: msg.text || msg.content || JSON.stringify(msg) };
}
let _messagingAuthKey = null;
async function getMessagingAuthKey(supabase) {
  if (_messagingAuthKey) return _messagingAuthKey;
  const { data, error } = await supabase.rpc("get_messaging_auth_key");
  if (error || !data) {
    throw new Error(`Failed to get messaging auth key: ${error?.message || "no data"}`);
  }
  _messagingAuthKey = data;
  return data;
}
async function callMessagingService(supabase, payload) {
  try {
    const authKey = await getMessagingAuthKey(supabase);
    const response = await fetch(`${MESSAGING_SERVICE_URL}/send`, {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        "Authorization": `Bearer ${authKey}`
      },
      body: JSON.stringify(payload)
    });
    return await response.json();
  } catch (e) {
    return {
      success: false,
      error: e.message
    };
  }
}
async function executeActionDirect(supabase, actionType, config, ctx) {
  const { merchant_id, user_id, workflow_id, node_id, runId, userContext } = ctx;
  const line_user_id = ctx.line_user_id || null;
  const engagement_event_id = ctx.engagement_event_id || null;
  const templateContext = await buildTemplateContext(supabase, user_id, merchant_id, userContext.trigger);
  const normalized = substituteDeep(config || {}, templateContext);
  const rpcActions = {
    award_points: ()=>({
        amount: parseInt(normalized.amount) || 0,
        description: normalized.description || "",
        dedup_key: normalized.dedup_key || null
      }),
    award_currency: ()=>{
      const currency = normalized.currency || normalized.currency_type || "points";
      return {
        amount: parseInt(normalized.amount) || 0,
        currency,
        ticket_type_id: normalized.ticket_type_id || normalized.target_entity_id || null,
        target_entity_id: normalized.target_entity_id || normalized.ticket_type_id || null,
        description: normalized.description || "",
        dedup_key: normalized.dedup_key || null
      };
    },
    award_tickets: ()=>({
        amount: parseInt(normalized.amount) || 0,
        ticket_type_id: normalized.ticket_type_id || normalized.target_entity_id || null,
        target_entity_id: normalized.target_entity_id || normalized.ticket_type_id || null,
        description: normalized.description || "",
        dedup_key: normalized.dedup_key || null
      }),
    assign_tag: ()=>({
        tag_id: normalized.tag_id
      }),
    remove_tag: ()=>({
        tag_id: normalized.tag_id
      }),
    assign_persona: ()=>({
        persona_id: normalized.persona_id
      }),
    assign_earn_factor: ()=>({
        earn_factor_id: normalized.earn_factor_id,
        days: parseInt(normalized.window_end_days) || 30
      }),
    submit_form: ()=>({
        form_id: normalized.form_id,
        field_values: normalized.field_values || {}
      }),
    add_to_audience: ()=>({
        audience_id: normalized.audience_id
      }),
    remove_from_audience: ()=>({
        audience_id: normalized.audience_id
      }),
    push_reward: ()=>({
        reward_id: normalized.reward_id,
        quantity: parseInt(normalized.quantity) || 1
      }),
    update_profile: ()=>({ fields: normalized.fields || normalized })
  };
  const at2 = normalized.action_type || actionType;
  const pb = rpcActions[at2];
  if (pb) {
    const params = { ...pb(), line_user_id, engagement_event_id, dedup_key: normalized.dedup_key || (engagement_event_id ? `${engagement_event_id}:${node_id}` : null) };
    const { data, error } = await supabase.rpc("fn_execute_amp_action", {
      p_action_type: at2,
      p_user_id: user_id,
      p_merchant_id: merchant_id,
      p_params: params,
      p_workflow_id: workflow_id,
      p_node_id: node_id,
      p_inngest_run_id: runId
    });
    if (error) return {
      success: false,
      error: error.message
    };
    return data;
  }
  return null;
}
function processMessages(messages, context) {
  return messages.map((msg)=>substituteDeep(msg, context));
}
function normalizeMessageConfig(config, context) {
  if (config.messages && Array.isArray(config.messages)) return processMessages(config.messages, context);
  if (config.json_content && typeof config.json_content === "object" && !Array.isArray(config.json_content)) {
    const substituted = substituteDeep(config.json_content, context);
    if (substituted.type === "flex" && substituted.contents) return [
      {
        type: "flex",
        altText: substituted.altText || config.subject || "Message",
        contents: substituted.contents
      }
    ];
    return [
      {
        type: "flex",
        altText: config.subject || "Message",
        contents: substituted
      }
    ];
  }
  if (config.content) return [
    {
      type: "text",
      text: substituteVariables(config.content, context)
    }
  ];
  if (config.message) return [
    {
      type: "text",
      text: substituteVariables(config.message, context)
    }
  ];
  return [];
}
async function resolveResourceMessages(supabase, resourceId, merchantId, channel, templateContext) {
  const { data: resolved, error } = await supabase.rpc("fn_resolve_resource_for_delivery", {
    p_resource_id: resourceId,
    p_merchant_id: merchantId,
    p_channel: channel
  });
  if (error || !resolved?.success) return [];
  const mode = resolved.delivery_mode;
  const altText = substituteVariables(resolved.text_fallback || resolved.resource_name || "Message", templateContext);
  const isLineChannel = channel === "line" || channel === "LINE";
  switch(mode){
    case "text":
      {
        const text = substituteVariables(resolved.text_content || resolved.text_fallback || "", templateContext);
        return text ? [
          {
            type: "text",
            text
          }
        ] : [];
      }
    case "media":
      {
        const msgs = [];
        if (isLineChannel && resolved.media_url) {
          msgs.push({
            type: "image",
            originalContentUrl: resolved.media_url,
            previewImageUrl: resolved.thumbnail_url || resolved.media_url
          });
        }
        const caption = substituteVariables(resolved.text_content || resolved.text_fallback || "", templateContext);
        if (caption) msgs.push({
          type: "text",
          text: caption
        });
        return msgs;
      }
    case "link":
      {
        const text = substituteVariables(resolved.text_fallback || resolved.resource_name || "", templateContext);
        const url = resolved.link_url || "";
        const body = url ? text ? `${text}\n${url}` : url : text;
        return body ? [
          {
            type: "text",
            text: body
          }
        ] : [];
      }
    case "platform_native":
      {
        const items = resolved.native_items;
        if (Array.isArray(items) && items.length > 0) {
          return items.map((item)=>substituteDeep(item, templateContext));
        }
        return altText ? [
          {
            type: "text",
            text: altText
          }
        ] : [];
      }
    case "rich_content":
      {
        const blocks = resolved.rich_content?.blocks;
        if (!Array.isArray(blocks) || blocks.length === 0) {
          return altText ? [
            {
              type: "text",
              text: altText
            }
          ] : [];
        }
        if (!isLineChannel) {
          return altText ? [
            {
              type: "text",
              text: altText
            }
          ] : [];
        }
        // Sequential LINE messages: text + image stay full-width.
        // Authored carousel/card blocks still render as Flex carousel.
        const { data: lineMessages, error: renderErr } = await supabase.rpc("fn_render_blocks_as_line_messages", {
          p_blocks: blocks,
          p_channel_key: resolved.channel_key || "line",
          p_alt_text: altText
        });
        if (renderErr || !Array.isArray(lineMessages) || lineMessages.length === 0) {
          return altText ? [
            {
              type: "text",
              text: altText
            }
          ] : [];
        }
        return lineMessages.map((msg)=>substituteDeep(msg, templateContext));
      }
    default:
      return altText ? [
        {
          type: "text",
          text: altText
        }
      ] : [];
  }
}
function parseDuration(config) {
  if (typeof config?.duration === "string" && /\d+[smhdw]/.test(config.duration)) return config.duration;
  if (typeof config?.duration === "number" && config?.unit) {
    const unitMap = {
      seconds: "s",
      second: "s",
      s: "s",
      minutes: "m",
      minute: "m",
      m: "m",
      hours: "h",
      hour: "h",
      h: "h",
      days: "d",
      day: "d",
      d: "d",
      weeks: "w",
      week: "w",
      w: "w"
    };
    return `${config.duration}${unitMap[config.unit] || "h"}`;
  }
  return "1h";
}
function capWaitDuration(requested, maxAllowed) {
  const toMs = (d)=>{
    const m = d.match(/(\d+)([smhdw])/);
    if (!m) return 2 * 86400000;
    const v = parseInt(m[1]);
    const u = {
      s: 1000,
      m: 60000,
      h: 3600000,
      d: 86400000,
      w: 604800000
    };
    return v * (u[m[2]] || 86400000);
  };
  return toMs(requested) <= toMs(maxAllowed) ? requested : maxAllowed;
}
async function evaluateConditionGroup(supabase, group, user_id, merchant_id, userContext, runtimeCtx) {
  const groupType = group.type || "simple";
  // Delegate to the SQL evaluator for everything except plain simple groups on regular
  // collections: aggregates (as before), form_submission / form_answer, content_engagement,
  // and audience membership (amp_audience_member has no merchant_id column and uses
  // is_member_of / is_not_member_of operators — fn_evaluate_amp_condition_group owns those
  // semantics).
  if (groupType !== "simple" || group.collection === "amp_audience_member") {
    // content_engagement node/workflow scopes count only the current enrollment;
    // the evaluator resolves it from the Inngest run id via workflow_log.
    const payload = groupType === "content_engagement" && runtimeCtx ? {
      ...group,
      _workflow_id: runtimeCtx.workflow_id,
      _inngest_run_id: runtimeCtx.runId
    } : group;
    const { data, error } = await supabase.rpc("fn_evaluate_amp_condition_group", {
      p_user_id: user_id,
      p_merchant_id: merchant_id,
      p_group: payload
    });
    if (error) {
      console.error("Condition group RPC error:", error);
      return false;
    }
    return data === true;
  }
  const collection = group.collection;
  const conditions = group.conditions || [];
  let query = supabase.from(collection).select("*");
  if (collection !== "user_accounts") query = query.eq("user_id", user_id);
  else query = query.eq("id", user_id);
  query = query.eq("merchant_id", merchant_id);
  for (const cond of conditions){
    const field = cond.field;
    const value = cond.value_type === "dynamic" ? substituteVariables(cond.value, userContext) : cond.value;
    switch(cond.operator){
      case "equals":
        query = query.eq(field, value);
        break;
      case "not_equals":
        query = query.neq(field, value);
        break;
      case "greater_than":
        query = query.gt(field, value);
        break;
      case "greater_or_equal":
      case "greater_than_or_equals":
      case "gte":
        query = query.gte(field, value);
        break;
      case "less_than":
        query = query.lt(field, value);
        break;
      case "less_or_equal":
      case "less_than_or_equals":
      case "lte":
        query = query.lte(field, value);
        break;
      case "contains":
        query = query.ilike(field, `%${value}%`);
        break;
    }
  }
  const { data, error } = await query.limit(1);
  return !error && data && data.length > 0;
}
function findNextEdge(edges, nodeId, handle, nodeType) {
  const nh = handle === "true" ? "true" : handle === "false" ? "false" : handle;
  const hm = edges.find((e)=>e.from_node_id === nodeId && (e.source_handle === nh || e.source_handle === `output-${nh}` || e.source_handle === `${nh}-output`));
  if (hm) return hm;
  const dm = edges.find((e)=>e.from_node_id === nodeId && e.source_handle === "default");
  if (dm) return dm;
  if (nodeType === "condition" || nodeType === "agent" || nodeType === "interaction_router") return null;
  return edges.find((e)=>e.from_node_id === nodeId) || null;
}
async function executeActionInline(supabase, node, config, ctx) {
  const { merchant_id, user_id, workflow_id, runId, userContext } = ctx;
  const run_scope = ctx.run_scope || (user_id ? "member" : (ctx.line_user_id ? "line" : "broadcast"));
  const line_user_id = ctx.line_user_id || null;
  const templateContext = await buildTemplateContext(supabase, user_id, merchant_id, userContext.trigger);
  const channel = config.channel;
  const actionType = config.action_type;
  let result = {
    success: false,
    error: "Unknown action"
  };
  let logActionType = actionType || "unknown";
  let logStatus = "skipped";
  let logData = {};
  let trackedTokens = [];
  // Engagement tracking: wrap http(s) URLs in outbound messages with per-recipient
  // link-redirect URLs. Tracking must never block a send — fall back to originals.
  const wrapTrackedLinks = async (messages, ch)=>{
    try {
      const { data, error } = await supabase.rpc("fn_amp_wrap_tracked_links", {
        p_messages: messages,
        p_merchant_id: merchant_id,
        p_workflow_id: workflow_id,
        p_node_id: node.id,
        p_user_id: user_id,
        p_channel: ch,
        p_resource_id: config.resource_id || null
      });
      if (!error && data?.messages) {
        trackedTokens = data.tokens || [];
        return data.messages;
      }
    } catch (_e) {}
    return messages;
  };
  if (channel === "line" || actionType === "send_line_message" || actionType === "send_line") {
    logActionType = "send_line_message";
    let ampMessages = normalizeMessageConfig(config, templateContext);
    if (ampMessages.length === 0 && config.resource_id) {
      ampMessages = await resolveResourceMessages(supabase, config.resource_id, merchant_id, "line", templateContext);
    }
    if (ampMessages.length === 0) result = {
      success: false,
      error: "No message content"
    };
    else {
      const route_snapshot = buildRouteSnapshot(ctx.nodes || [], ctx.edges || [], node.id, workflow_id, ctx.workflow_updated_at);
      const { data: prepLog } = await supabase.from("workflow_log").insert({
        merchant_id, workflow_id, user_id, line_user_id, run_scope, inngest_run_id: runId,
        event_type: "action_executed", node_id: node.id, node_type: "action", action_type: logActionType,
        status: "preparing", event_data: { channel: "line", route_snapshot }
      }).select("id").single();
      const logId = prepLog?.id;
      let signedPostbackKeys: string[] = [];
      if (logId && AMP_POSTBACK_SECRET) {
        if (Array.isArray(config.quick_replies) && config.quick_replies.length > 0) {
          const qr = await buildQuickReplyItems(config.quick_replies, logId, node.id);
          ampMessages = ampMessages.map((m: any, idx: number) => idx === 0 ? { ...m, quickReply: qr } : m);
        }
        // Content Library Flex/template buttons use src=resource — rewrite to signed AMP postbacks
        const signed = await signAmpPostbacksInMessages(ampMessages, logId, node.id);
        ampMessages = signed.messages;
        signedPostbackKeys = signed.action_keys || [];
      }
      const sendMessages = (run_scope === "broadcast" || !user_id) ? ampMessages : await wrapTrackedLinks(ampMessages, "line");
      const recipient = resolveLineRecipient(run_scope, user_id, line_user_id);
      result = await callMessagingService(supabase, {
        merchant_id,
        channel: "LINE",
        recipient,
        messages: sendMessages.map(ampMessageToOutbound),
        source: "amp_workflow",
        reference_id: workflow_id
      });
      logData = {
        channel: "line",
        resource_id: config.resource_id || null,
        resolved_messages: sendMessages,
        tracked_tokens: trackedTokens,
        signed_postback_keys: signedPostbackKeys,
        result,
        route_snapshot,
        recipient_mode: recipient.mode || "push"
      };
      if (logId) {
        await supabase.from("workflow_log").update({
          status: result.success ? "sent" : "failed",
          error_message: result.error || null,
          event_data: logData,
          external_message_id: result.platform_message_id || null
        }).eq("id", logId);
        if (trackedTokens.length > 0) await supabase.from("amp_tracked_link").update({ workflow_log_id: logId }).in("token", trackedTokens);
        return result;
      }
    }
    logStatus = result.success ? "sent" : "failed";
    if (!logData.channel) logData = {
      channel: "line",
      result
    };
  } else if (channel === "sms" || actionType === "send_sms") {
    logActionType = "send_sms";
    let message = substituteVariables(config.message || config.content || "", templateContext);
    if (!message && config.resource_id) {
      const resourceMsgs = await resolveResourceMessages(supabase, config.resource_id, merchant_id, "sms", templateContext);
      message = resourceMsgs.map((m)=>m.text || m.content || "").filter(Boolean).join("\n");
    }
    const phone = config.phone || templateContext.user?.phone || templateContext.user?.tel;
    if (!phone) result = {
      success: false,
      error: "No phone number available"
    };
    else if (!message) result = {
      success: false,
      error: "No message content"
    };
    else {
      const wrapped = await wrapTrackedLinks([
        {
          type: "text",
          text: message
        }
      ], "sms");
      message = wrapped?.[0]?.text ?? message;
      result = await callMessagingService(supabase, {
        merchant_id,
        channel: "SMS",
        recipient: {
          direct: {
            phone
          }
        },
        message: {
          type: "text",
          content: message
        },
        source: "amp_workflow",
        reference_id: workflow_id
      });
    }
    logStatus = result.success ? "sent" : "failed";
    logData = {
      channel: "sms",
      resolved_message: message,
      tracked_tokens: trackedTokens,
      result
    };
  } else if (channel === "email" || actionType === "send_email") {
    logActionType = "send_email";
    const email = config.email || templateContext.user?.email;
    let content = substituteVariables(config.content || config.html || config.message || "", templateContext);
    if (!content && config.resource_id) {
      const resourceMsgs = await resolveResourceMessages(supabase, config.resource_id, merchant_id, "email", templateContext);
      content = resourceMsgs.map((m)=>m.text || m.content || "").filter(Boolean).join("\n");
    }
    const subject = substituteVariables(config.subject || "Notification", templateContext);
    if (!email) result = {
      success: false,
      error: "No email address available"
    };
    else if (!content) result = {
      success: false,
      error: "No message content"
    };
    else result = await callMessagingService(supabase, {
      merchant_id,
      channel: "EMAIL",
      recipient: {
        direct: {
          email
        }
      },
      message: {
        type: config.html ? "html" : "text",
        content,
        subject,
        metadata: {
          from: config.from,
          from_name: config.from_name,
          reply_to: config.reply_to,
          template_id: config.template_id,
          dynamic_template_data: config.dynamic_template_data
        }
      },
      source: "amp_workflow",
      reference_id: workflow_id
    });
    logStatus = result.success ? "sent" : "failed";
    logData = {
      channel: "email",
      resolved_subject: subject,
      result
    };
  } else if (actionType === "api_call" || actionType === "webhook") {
    logActionType = "api_call";
    const url = substituteVariables(config.url || "", templateContext);
    const method = config.method || "POST";
    const headers = config.headers || {};
    const body = substituteDeep(config.body, templateContext);
    try {
      const resp = await fetch(url, {
        method,
        headers: {
          "Content-Type": "application/json",
          ...headers
        },
        body: method !== "GET" ? JSON.stringify(body) : undefined
      });
      result = {
        success: resp.ok,
        status: resp.status
      };
    } catch (e) {
      result = {
        success: false,
        error: e.message
      };
    }
    logStatus = result.success ? "executed" : "failed";
    logData = {
      url,
      method,
      status: result.status
    };
  }
  const { data: logRow } = await supabase.from("workflow_log").insert({
    merchant_id,
    workflow_id,
    user_id,
    line_user_id,
    run_scope,
    inngest_run_id: runId,
    event_type: "action_executed",
    node_id: node.id,
    node_type: "action",
    action_type: logActionType,
    status: logStatus,
    error_message: result.error || null,
    event_data: logData,
    engagement_event_id: ctx.engagement_event_id || null
  }).select("id").single();
  if (logRow?.id && trackedTokens.length > 0) {
    await supabase.from("amp_tracked_link").update({
      workflow_log_id: logRow.id
    }).in("token", trackedTokens);
  }
  return result;
}
const workflowExecutor = inngest.createFunction({
  id: "workflow-executor",
  retries: 3
}, {
  event: "amp/workflow.trigger"
}, async ({ event, step })=>{
  const ed = event.data;
  const workflow_id = ed.workflow_id;
  let user_id = ed.user_id || null;
  const merchant_id = ed.merchant_id;
  const trigger_data = ed.trigger_data || {};
  let line_user_id = ed.line_user_id || null;
  let run_scope = ed.run_scope || (line_user_id && !user_id ? "line" : (user_id ? "member" : (trigger_data.entry_type === "all_line_friends" ? "broadcast" : "member")));
  const parent_workflow_log_id = ed.parent_workflow_log_id || null;
  const engagement_event_id = ed.engagement_event_id || null;
  const start_node_id = ed.start_node_id || null;
  const supabase = getSupabase();
  const runId = event.id || `run-${Date.now()}`;

  if ((ed.dispatch_line_subjects || trigger_data.entry_type === "past_line_interaction") && !trigger_data.fanout) {
    const fan = await step.run("fanout-line-subjects", async ()=>{
      const keys = trigger_data.action_keys || trigger_data.filters?.action_keys || [];
      const { data: subjects, error } = await supabase.rpc("fn_amp_find_matching_line_subjects", {
        p_merchant_id: merchant_id,
        p_action_keys: keys,
        p_time_from: timeRangeToFrom(trigger_data.time_window || trigger_data.time_range),
        p_time_to: new Date().toISOString(),
        p_min_occurrence: trigger_data.min_occurrence_count || 1,
        p_source_workflow_id: trigger_data.source_workflow_id || null,
        p_source_node_id: trigger_data.node_id || trigger_data.source_node_id || null,
        p_source_resource_id: trigger_data.source_resource_id || null,
        p_workflow_id: workflow_id
      });
      if (error) return { ok: false, error: error.message };
      let n = 0;
      for (const s of subjects || []) {
        await emitInngestEvent("amp/workflow.trigger", {
          workflow_id, merchant_id, run_scope: "line",
          line_user_id: s.line_user_id, user_id: s.user_id || null,
          trigger_data: { ...trigger_data, entry_type: "past_line_interaction", fanout: true }
        });
        n++;
      }
      return { ok: true, dispatched: n };
    });
    return { success: true, fanout: fan };
  }
  if (trigger_data.entry_type === "all_line_friends") run_scope = "broadcast";

  const startResult = await step.run("log-start", async ()=>{
    if (line_user_id && !user_id) {
      const { data: resolved } = await supabase.rpc("fn_amp_resolve_user_by_line_id", { p_merchant_id: merchant_id, p_line_user_id: line_user_id });
      if (resolved) user_id = resolved;
    }
    // Re-enrollment gate: when allow_re_enrollment is off, skip users who already
    // have an execution_started row for this workflow. Checked BEFORE inserting this
    // run's own execution_started row. Memoized per run, so in-flight executions that
    // resume after a wait keep their original decision.
    // Postback/router continuations are not net-new enrollments — skip this gate when
    // start_node_id / parent_workflow_log_id / line_postback markers are present.
    const isContinuation = !!(
      parent_workflow_log_id ||
      start_node_id ||
      trigger_data?.source === "line_postback"
    );
    const { data: wf } = await supabase.from("workflow_master").select("config").eq("id", workflow_id).single();
    const allowReEnroll = wf?.config?.allow_re_enrollment === true || wf?.config?.allow_re_enrollment === "true";
    if (!allowReEnroll && user_id && !isContinuation) {
      const { data: alreadyEnrolled } = await supabase.rpc("fn_amp_user_already_enrolled", {
        p_workflow_id: workflow_id,
        p_user_id: user_id
      });
      if (alreadyEnrolled === true) {
        await supabase.from("workflow_log").insert({
          merchant_id,
          workflow_id,
          user_id,
          line_user_id,
          run_scope,
          inngest_run_id: runId,
          event_type: "execution_skipped",
          status: "already_enrolled",
          event_data: { reason: "re_enrollment_disabled", trigger_data },
          parent_workflow_log_id,
          engagement_event_id
        });
        return { ok: true, skip: true, user_id, line_user_id, run_scope };
      }
    }
    await supabase.from("workflow_log").insert({
      merchant_id,
      workflow_id,
      user_id,
      line_user_id,
      run_scope,
      inngest_run_id: runId,
      event_type: "execution_started",
      event_data: { trigger_data, run_scope },
      parent_workflow_log_id,
      engagement_event_id
    });
    return { ok: true, skip: false, user_id, line_user_id, run_scope };
  });
  if (startResult?.skip) return {
    success: true,
    skipped: true,
    reason: "already_enrolled"
  };
  if (startResult?.user_id !== undefined) user_id = startResult.user_id;
  if (startResult?.line_user_id !== undefined) line_user_id = startResult.line_user_id;
  if (startResult?.run_scope) run_scope = startResult.run_scope;
  const { workflow, userContext } = await step.run("load-workflow", async ()=>{
    const { data: wf } = await supabase.from("workflow_master").select("*").eq("id", workflow_id).single();
    let nodes = [];
    let edges = [];
    const { data: graphData, error: graphErr } = await supabase.rpc("fn_get_workflow_graph_cached", {
      p_workflow_id: workflow_id
    });
    if (!graphErr && graphData) {
      const graph = unwrapCached(graphData);
      nodes = graph?.nodes || [];
      edges = graph?.edges || [];
    }
    if (nodes.length === 0) {
      const { data: n } = await supabase.from("workflow_node").select("*").eq("workflow_id", workflow_id);
      const { data: e } = await supabase.from("workflow_edge").select("*").eq("workflow_id", workflow_id);
      nodes = n || [];
      edges = e || [];
    }
    const userContext = await buildTemplateContext(supabase, user_id, merchant_id, trigger_data);
    return {
      workflow: {
        ...wf,
        nodes,
        edges
      },
      userContext
    };
  });
  if (!workflow || !workflow.is_active) return {
    success: false,
    error: "Workflow inactive or not found"
  };
  const nodes = workflow.nodes;
  const edges = workflow.edges;
  const incoming = new Set(edges.map((e)=>e.to_node_id));
  let current = start_node_id ? nodes.find((n)=>n.id === start_node_id) : nodes.find((n)=>!incoming.has(n.id));
  const executed = [];
  let iter = 0;
  while(current && iter < 50){
    iter++;
    if (executed.includes(current.id)) break;
    executed.push(current.id);
    const node = current;
    let handle = "default";
    if (node.node_type === "trigger" || node.node_type === "entry") {
    // no-op
    } else if (node.node_type === "wait") {
      const dur = parseDuration(node.node_config);
      await step.run(`log-wait-${node.id}`, async ()=>{
        await supabase.from("workflow_log").insert({
          merchant_id,
          workflow_id,
          user_id,
          line_user_id,
          run_scope,
          inngest_run_id: runId,
          event_type: "node_executed",
          node_id: node.id,
          node_type: "wait",
          status: "waiting",
          event_data: {
            duration: dur
          }
        });
        return {
          ok: true
        };
      });
      await step.sleep(`sleep-${node.id}`, dur);
      await step.run(`log-wait-done-${node.id}`, async ()=>{
        await supabase.from("workflow_log").insert({
          merchant_id,
          workflow_id,
          user_id,
          line_user_id,
          run_scope,
          inngest_run_id: runId,
          event_type: "node_executed",
          node_id: node.id,
          node_type: "wait",
          status: "executed"
        });
        return {
          ok: true
        };
      });
    } else if (node.node_type === "interaction_router") {
      await step.run(`interaction-router-${node.id}`, async ()=>{
        await supabase.from("workflow_log").insert({
          merchant_id, workflow_id, user_id, line_user_id, run_scope, inngest_run_id: runId,
          event_type: "node_executed", node_id: node.id, node_type: "interaction_router",
          status: "awaiting_interaction",
          event_data: { message_node_id: node.node_config?.message_node_id, selection_mode: node.node_config?.selection_mode || "single" },
          parent_workflow_log_id, engagement_event_id
        });
        return { ok: true };
      });
      current = null;
      continue;
    } else if (node.node_type === "condition") {
      handle = await step.run(`condition-${node.id}`, async ()=>{
        const config = node.node_config;
        // All LINE Friends: empty groups are intentional — always take True path.
        if (config?.entry_type === "all_line_friends" || run_scope === "broadcast") {
          await supabase.from("workflow_log").insert({
            merchant_id,
            workflow_id,
            user_id,
            line_user_id,
            run_scope,
            inngest_run_id: runId,
            event_type: "node_executed",
            node_id: node.id,
            node_type: "condition",
            status: "executed",
            event_data: { result: "true", entry_type: config?.entry_type || "all_line_friends", run_scope }
          });
          return "true";
        }
        const groups = Array.isArray(config?.condition_groups) ? config.condition_groups : Array.isArray(config?.groups) ? config.groups : null;
        if (groups) {
          const groupsOp = config.groups_operator || "AND";
          const gr = [];
          for (const group of groups)gr.push(await evaluateConditionGroup(supabase, group, user_id, merchant_id, userContext, {
            workflow_id,
            runId
          }));
          const fr = groupsOp === "AND" ? gr.every((r)=>r) : gr.some((r)=>r);
          await supabase.from("workflow_log").insert({
            merchant_id,
            workflow_id,
            user_id,
            line_user_id,
            run_scope,
            inngest_run_id: runId,
            event_type: "node_executed",
            node_id: node.id,
            node_type: "condition",
            status: "executed",
            event_data: {
              result: fr ? "true" : "false",
              groupResults: gr,
              run_scope
            }
          });
          return fr ? "true" : "false";
        }
        const q = config?.query;
        if (!q) return "false";
        let query = supabase.from(q.table).select(q.select || "*");
        if (q.user_field) query = query.eq(q.user_field, user_id);
        if (q.merchant_field) query = query.eq(q.merchant_field, merchant_id);
        const { data } = await query;
        let result = false;
        const val = data?.[0]?.[q.field];
        if (q.operator === ">") result = val > q.value;
        else if (q.operator === ">=") result = val >= q.value;
        else if (q.operator === "<") result = val < q.value;
        else if (q.operator === "<=") result = val <= q.value;
        else if (q.operator === "==") result = val == q.value;
        else result = (data?.length || 0) > 0;
        await supabase.from("workflow_log").insert({
          merchant_id,
          workflow_id,
          user_id,
          line_user_id,
          run_scope,
          inngest_run_id: runId,
          event_type: "node_executed",
          node_id: node.id,
          node_type: "condition",
          status: "executed",
          event_data: {
            result: result ? "true" : "false",
            value: val,
            run_scope
          }
        });
        return result ? "true" : "false";
      });
    } else if (node.node_type === "action" || node.node_type === "message") {
      const actionResult = await step.run(`action-${node.id}`, async ()=>{
        const config = node.node_config || {};
        const directResult = await executeActionDirect(supabase, config.action_type || "", config, {
          merchant_id,
          user_id,
          workflow_id,
          node_id: node.id,
          runId,
          userContext,
          line_user_id,
          engagement_event_id
        });
        if (directResult !== null) return directResult;
        return await executeActionInline(supabase, node, config, {
          merchant_id,
          user_id,
          workflow_id,
          workflow_name: workflow.name || workflow_id,
          runId,
          userContext,
          run_scope,
          line_user_id,
          nodes,
          edges,
          workflow_updated_at: workflow.updated_at,
          engagement_event_id
        });
      });
      // Failed send must not walk into the next interaction_router.
      if (actionResult && actionResult.success === false) {
        current = null;
        continue;
      }
    } else if (node.node_type === "agent") {
      const agentSetup = await step.run(`agent-config-${node.id}`, async ()=>{
        const cfg = node.node_config || {};
        try {
          let agent = null;
          if (cfg.agent_config_id) {
            const { data: cachedAgent, error: agentErr } = await supabase.rpc("fn_get_agent_config_cached", {
              p_agent_id: cfg.agent_config_id
            });
            if (!agentErr && cachedAgent) {
              const parsed = unwrapCached(cachedAgent);
              agent = {
                id: parsed.id || cfg.agent_config_id,
                objective: parsed.objective,
                tone: parsed.tone,
                context_hint: parsed.context_hint,
                max_deliberation_cycles: parsed.max_deliberation_cycles,
                default_wait_duration: parsed.default_wait_duration,
                max_wait_duration: parsed.max_wait_duration,
                deliberation_timeout: parsed.deliberation_timeout,
                max_actions_per_execution: parsed.max_actions_per_execution
              };
            } else {
              const { data } = await supabase.from("amp_agent").select("id,objective,tone,context_hint,max_deliberation_cycles,default_wait_duration,max_wait_duration,deliberation_timeout,max_actions_per_execution").eq("id", cfg.agent_config_id).single();
              agent = data;
            }
          }
          await supabase.from("workflow_log").insert({
            merchant_id,
            workflow_id,
            user_id,
            line_user_id,
            run_scope,
            inngest_run_id: runId,
            event_type: "node_executed",
            node_id: node.id,
            node_type: "agent",
            status: "invoking",
            event_data: {
              agent_config_id: cfg.agent_config_id || null,
              objective: agent?.objective || cfg.objective
            }
          });
          if (agent) return {
            ready: true,
            agent_config: agent
          };
          return {
            ready: true,
            agent_config: null,
            objective: cfg.objective || "drive_engagement",
            tone: cfg.tone || "friendly"
          };
        } catch (e) {
          await supabase.from("workflow_log").insert({
            merchant_id,
            workflow_id,
            user_id,
            line_user_id,
            run_scope,
            inngest_run_id: runId,
            event_type: "node_executed",
            node_id: node.id,
            node_type: "agent",
            status: "failed",
            error_message: e.message
          });
          return {
            ready: false
          };
        }
      });
      if (agentSetup.ready) {
        const maxCycles = agentSetup.agent_config?.max_deliberation_cycles || 3;
        const maxWD = agentSetup.agent_config?.max_wait_duration || "7d";
        const defWD = agentSetup.agent_config?.default_wait_duration || "2d";
        const dh = [];
        let fd = null;
        for(let cycle = 0; cycle < maxCycles; cycle++){
          const cr = await step.invoke(`agent-${node.id}-cycle-${cycle}`, {
            function: agentFunctionRef,
            data: {
              user_id,
              merchant_id,
              workflow_id,
              agent_config: {
                ...agentSetup.agent_config || {},
                node_id: node.id
              },
              actions: null,
              outcomes: null,
              objective: agentSetup.agent_config?.objective || agentSetup.objective,
              tone: agentSetup.agent_config?.tone || agentSetup.tone,
              trigger_event: trigger_data,
              cycle,
              deliberation_history: dh
            }
          });
          const resp = cr;
          const dec = resp?.decision || (resp?.success ? "act" : "skip");
          await step.run(`log-agent-${node.id}-cycle-${cycle}`, async ()=>{
            const et = dec === "act" ? "agent_decided_act" : dec === "wait" ? "agent_decided_wait" : "agent_decided_skip";
            await supabase.from("workflow_log").insert({
              merchant_id,
              workflow_id,
              user_id,
              line_user_id,
              run_scope,
              inngest_run_id: runId,
              event_type: et,
              node_id: node.id,
              node_type: "agent",
              status: dec === "act" ? "acted" : dec === "wait" ? "waiting" : "skipped",
              event_data: {
                cycle,
                decision: dec,
                reasoning: resp?.reasoning || null,
                watching_for: resp?.watching_for || null,
                wait_duration: resp?.wait_duration || null,
                actions_taken: resp?.actions_taken || null,
                source: "agentkit"
              }
            });
            return {
              ok: true
            };
          });
          if (dec === "act") {
            fd = {
              action_taken: true,
              ...resp
            };
            break;
          }
          if (dec === "skip") {
            fd = {
              action_taken: false,
              reasoning: resp?.reasoning
            };
            break;
          }
          if (dec === "wait") {
            const wd = capWaitDuration(resp?.wait_duration || defWD, maxWD);
            dh.push({
              cycle,
              decision: "wait",
              wait_duration: wd,
              watching_for: resp?.watching_for || null,
              reasoning: resp?.reasoning || null,
              assessed_at: new Date().toISOString()
            });
            await step.sleep(`agent-${node.id}-wait-${cycle}`, wd);
          }
        }
        if (!fd) {
          fd = {
            action_taken: false,
            reasoning: "deliberation_exhausted"
          };
          await step.run(`log-agent-${node.id}-exhausted`, async ()=>{
            await supabase.from("workflow_log").insert({
              merchant_id,
              workflow_id,
              user_id,
              line_user_id,
              run_scope,
              inngest_run_id: runId,
              event_type: "agent_decided_skip",
              node_id: node.id,
              node_type: "agent",
              status: "exhausted",
              event_data: {
                total_cycles: maxCycles,
                deliberation_history: dh
              }
            });
            return {
              ok: true
            };
          });
        }
        userContext.agent = fd;
        handle = fd.action_taken ? "true" : "false";
      } else {
        handle = "false";
      }
    } else {
      await step.run(`exec-${node.id}`, async ()=>{
        await supabase.from("workflow_log").insert({
          merchant_id,
          workflow_id,
          user_id,
          line_user_id,
          run_scope,
          inngest_run_id: runId,
          event_type: "node_executed",
          node_id: node.id,
          node_type: node.node_type,
          status: "executed"
        });
        return {
          ok: true
        };
      });
    }
    const next = findNextEdge(edges, node.id, handle, node.node_type);
    current = next ? nodes.find((n)=>n.id === next.to_node_id) : null;
  }
  await step.run("log-complete", async ()=>{
    await supabase.from("workflow_log").insert({
      merchant_id,
      workflow_id,
      user_id,
      line_user_id,
      run_scope,
      inngest_run_id: runId,
      event_type: "execution_completed",
      event_data: {
        nodes_executed: executed.length,
        run_scope
      }
    });
    return {
      ok: true
    };
  });
  return {
    success: true,
    executed: executed.length
  };
});

const postbackContinue = inngest.createFunction({
  id: "amp-postback-continue",
  retries: 3
}, {
  event: "amp/content.postback"
}, async ({ event, step })=>{
  const data = event.data;
  const supabase = getSupabase();
  const snapshot = data.route_snapshot || {};
  const action_key = data.action_key;
  const target = (snapshot.routes || {})[action_key];
  const result = await step.run("continue-from-route", async ()=>{
    let user_id = data.user_id || null;
    if (!user_id && data.line_user_id) {
      const { data: resolved } = await supabase.rpc("fn_amp_resolve_user_by_line_id", {
        p_merchant_id: data.merchant_id,
        p_line_user_id: data.line_user_id
      });
      user_id = resolved || null;
    }
    if (target) {
      await emitInngestEvent("amp/workflow.trigger", {
        workflow_id: data.workflow_id,
        merchant_id: data.merchant_id,
        user_id,
        line_user_id: data.line_user_id,
        run_scope: "line",
        parent_workflow_log_id: data.workflow_log_id,
        engagement_event_id: data.engagement_event_id,
        start_node_id: target,
        trigger_data: {
          source: "line_postback",
          action_key,
          message_node_id: data.message_node_id
        }
      });
    }
    const { data: workflows } = await supabase.from("workflow_master").select("id, is_active").eq("merchant_id", data.merchant_id).eq("is_active", true).eq("domain", "amp");
    let triggered = 0;
    for (const wf of workflows || []) {
      if (wf.id === data.workflow_id) continue;
      const { data: nodes } = await supabase.from("workflow_node").select("id, node_type, node_config").eq("workflow_id", wf.id);
      const entry = (nodes || []).find((n)=>n.node_type === "condition" && n.node_config?.entry_type === "line_option_selected");
      if (!entry) continue;
      const groups = entry.node_config?.groups || [];
      const match = groups.some((g)=>g.type === "line_engagement" && Array.isArray(g.action_keys) && g.action_keys.includes(action_key));
      if (!match) continue;
      await emitInngestEvent("amp/workflow.trigger", {
        workflow_id: wf.id,
        merchant_id: data.merchant_id,
        user_id,
        line_user_id: data.line_user_id,
        run_scope: "line",
        engagement_event_id: data.engagement_event_id,
        trigger_data: {
          source: "line_option_selected",
          action_key,
          entry_type: "line_option_selected"
        }
      });
      triggered++;
    }
    return { target, triggered };
  });
  return { success: true, ...result };
});

const handler = serve({
  client: inngest,
  functions: [
    workflowExecutor,
    postbackContinue
  ],
  signingKey: Deno.env.get("INNGEST_SIGNING_KEY"),
  servePath: "/functions/v1/inngest-amp-serve"
});
Deno.serve(handler);
