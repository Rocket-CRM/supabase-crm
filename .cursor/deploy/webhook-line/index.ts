import { createClient } from "https://esm.sh/@supabase/supabase-js@2.46.0";
import { Inngest } from "https://esm.sh/inngest@3.54.0";
import { fanOutLineWebhook, scheduleLineWebhookFanOut } from "./line-webhook-fanout.ts";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SUPABASE_SERVICE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
const AMP_POSTBACK_SECRET = Deno.env.get("AMP_POSTBACK_SECRET") || Deno.env.get("INTERNAL_WEBHOOK_SECRET") || "";
const INNGEST_EVENT_KEY = Deno.env.get("INNGEST_EVENT_KEY") || "";
const INNGEST_EVENT_URL = INNGEST_EVENT_KEY ? `https://inn.gs/e/${INNGEST_EVENT_KEY}` : "";
const inngestCs = new Inngest({ id: "cs-platform", eventKey: INNGEST_EVENT_KEY || undefined });
const inngestAmp = new Inngest({ id: "crm-workflows", eventKey: INNGEST_EVENT_KEY || undefined });

function getSupabase() {
  return createClient(SUPABASE_URL, SUPABASE_SERVICE_KEY);
}

/** Reliable event emit for Deno Edge (SDK send is flaky without explicit key). */
async function emitInngestEvent(name: string, data: Record<string, unknown>): Promise<{ ok: boolean; error?: string }> {
  if (!INNGEST_EVENT_URL) {
    console.error("INNGEST_EVENT_KEY missing — cannot emit", name);
    return { ok: false, error: "INNGEST_EVENT_KEY missing" };
  }
  try {
    const res = await fetch(INNGEST_EVENT_URL, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ name, data }),
    });
    if (!res.ok) {
      const text = await res.text();
      console.error(`Inngest emit failed ${name}:`, res.status, text);
      return { ok: false, error: `http_${res.status}` };
    }
    return { ok: true };
  } catch (e: any) {
    console.error(`Inngest emit error ${name}:`, e?.message || e);
    return { ok: false, error: e?.message || "emit_failed" };
  }
}

async function computeHmac(body: string, channelSecret: string): Promise<string> {
  const encoder = new TextEncoder();
  const key = await crypto.subtle.importKey(
    "raw",
    encoder.encode(channelSecret),
    { name: "HMAC", hash: "SHA-256" },
    false,
    ["sign"],
  );
  const sig = await crypto.subtle.sign("HMAC", key, encoder.encode(body));
  return btoa(String.fromCharCode(...new Uint8Array(sig)));
}

async function hmacSha256Hex(message: string, secret: string): Promise<string> {
  const encoder = new TextEncoder();
  const key = await crypto.subtle.importKey(
    "raw",
    encoder.encode(secret),
    { name: "HMAC", hash: "SHA-256" },
    false,
    ["sign"],
  );
  const sig = await crypto.subtle.sign("HMAC", key, encoder.encode(message));
  return Array.from(new Uint8Array(sig)).map((b) => b.toString(16).padStart(2, "0")).join("");
}

function expandCompactUuid(compact: string): string | null {
  try {
    const padded = compact.replace(/-/g, "+").replace(/_/g, "/") + "==".slice(0, (4 - (compact.length % 4)) % 4);
    const binary = atob(padded);
    if (binary.length !== 16) return null;
    const bytes = Uint8Array.from(binary, (c) => c.charCodeAt(0));
    const hex = Array.from(bytes).map((b) => b.toString(16).padStart(2, "0")).join("");
    return `${hex.slice(0, 8)}-${hex.slice(8, 12)}-${hex.slice(12, 16)}-${hex.slice(16, 20)}-${hex.slice(20)}`;
  } catch {
    return null;
  }
}

function parseActionKeyList(raw: string): string[] | null {
  const parts = raw.split(",").map((s) => s.trim()).filter(Boolean);
  if (parts.length === 0 || parts.length > 5) return null;
  if (parts.some((p) => p.length > 64 || /[^a-zA-Z0-9._-]/.test(p))) return null;
  return parts;
}

interface AmpPostbackContext {
  version: string;
  workflow_log_id: string;
  message_node_id: string;
  action_key: string;
}

async function parseAndVerifyAmpPostback(data: string): Promise<AmpPostbackContext | null> {
  if (!data || !data.includes("src=amp")) return null;
  let params: URLSearchParams;
  try {
    params = new URLSearchParams(data);
  } catch {
    return null;
  }
  if (params.get("src") !== "amp") return null;
  const version = params.get("v") || "";
  if (version !== "1") return null;
  const r = params.get("r") || "";
  const n = params.get("n") || "";
  const a = params.get("a") || "";
  const s = params.get("s") || "";
  if (!r || !n || !a || !s) return null;
  if (!parseActionKeyList(a)) return null;
  if (!AMP_POSTBACK_SECRET) {
    console.error("AMP_POSTBACK_SECRET not configured");
    return null;
  }
  const canonical = `a=${a}&n=${n}&r=${r}&src=amp&v=1`;
  const expected = await hmacSha256Hex(canonical, AMP_POSTBACK_SECRET);
  // Accept full hex or truncated (first 16 chars) to stay under LINE 300-char limit
  if (s !== expected && s !== expected.slice(0, 16)) return null;
  const workflow_log_id = expandCompactUuid(r);
  const message_node_id = expandCompactUuid(n);
  if (!workflow_log_id || !message_node_id) return null;
  return { version, workflow_log_id, message_node_id, action_key: a };
}

interface CredentialMatch {
  merchant_id: string;
  credential_id: string;
  channel_secret: string;
  access_token: string;
  messaging_channel_id: string;
  webhook_fanout_destinations: unknown;
}

async function resolveCredentialBySignature(
  rawBody: string,
  headerSignature: string,
): Promise<CredentialMatch | null> {
  const supabase = getSupabase();
  const { data } = await supabase
    .from("merchant_credentials")
    .select("id, merchant_id, credentials")
    .eq("service_name", "line_messaging")
    .eq("is_active", true);

  if (!data || data.length === 0) return null;

  for (const row of data) {
    const creds = (row.credentials ?? {}) as Record<string, unknown>;
    const secret = typeof creds.messaging_channel_secret === "string"
      ? creds.messaging_channel_secret
      : "";
    if (!secret) continue;

    const expected = await computeHmac(rawBody, secret);
    if (expected === headerSignature) {
      return {
        merchant_id: row.merchant_id,
        credential_id: row.id,
        channel_secret: secret,
        access_token: typeof creds.messaging_channel_access_token === "string"
          ? creds.messaging_channel_access_token
          : "",
        messaging_channel_id: typeof creds.messaging_channel_id === "string"
          ? creds.messaging_channel_id
          : "",
        webhook_fanout_destinations: creds.webhook_fanout_destinations,
      };
    }
  }
  return null;
}

async function fetchLineDisplayName(userId: string, accessToken: string): Promise<string | null> {
  if (!accessToken) return null;
  try {
    const res = await fetch(`https://api.line.me/v2/bot/profile/${userId}`, {
      headers: { Authorization: `Bearer ${accessToken}` },
    });
    if (!res.ok) return null;
    const profile = await res.json();
    return profile.displayName || null;
  } catch {
    return null;
  }
}

function mapLineMessageType(lineType: string): string {
  const map: Record<string, string> = {
    text: "text",
    image: "image",
    video: "file",
    audio: "file",
    file: "file",
    sticker: "image",
    location: "text",
  };
  return map[lineType] || "text";
}

function extractMessageContent(message: any): string {
  if (message.type === "text") return message.text || "";
  if (message.type === "sticker") return `[sticker:${message.packageId}/${message.stickerId}]`;
  if (message.type === "location") return `[location:${message.title || ""} ${message.address || ""}]`;
  if (message.type === "image") return "[image]";
  if (message.type === "video") return "[video]";
  if (message.type === "audio") return "[audio]";
  if (message.type === "file") return `[file:${message.fileName || ""}]`;
  return `[${message.type}]`;
}

function parsePostbackData(data: string): Record<string, string> | null {
  if (!data || data.includes("=") === false) return null;
  try {
    const params = new URLSearchParams(data);
    const out: Record<string, string> = {};
    for (const [k, v] of params.entries()) out[k] = v;
    return Object.keys(out).length > 0 ? out : null;
  } catch {
    return null;
  }
}

function extractPostbackContent(event: any, parsed: Record<string, string> | null): string {
  if (parsed?.action) return parsed.action;
  if (parsed?.a) return parsed.a;
  return `[postback:${event.postback?.data || ""}]`;
}

async function handleAmpPostback(opts: {
  merchant_id: string;
  line_user_id: string;
  webhook_event_id: string;
  postback_data: string;
  ampCtx: AmpPostbackContext;
}): Promise<Record<string, unknown>> {
  const supabase = getSupabase();

  // Load route snapshot from originating log for selection_mode + ownership
  const { data: logRow } = await supabase
    .from("workflow_log")
    .select("id, merchant_id, workflow_id, event_data")
    .eq("id", opts.ampCtx.workflow_log_id)
    .maybeSingle();

  if (!logRow || logRow.merchant_id !== opts.merchant_id) {
    return { accepted: false, reason: "invalid_run" };
  }

  const snapshot = (logRow.event_data as any)?.route_snapshot || {};
  const selectionMode = snapshot.selection_mode || "single";
  const allowed: string[] = Array.isArray(snapshot.allowed_action_keys)
    ? snapshot.allowed_action_keys
    : Object.keys(snapshot.routes || {});

  const keys = parseActionKeyList(opts.ampCtx.action_key) ?? [];
  const keysToRun = selectionMode === "multiple" ? keys : keys.slice(0, 1);
  if (keysToRun.length === 0) return { accepted: false, reason: "invalid_action_key" };

  const results: Record<string, unknown>[] = [];
  for (const key of keysToRun) {
    if (allowed.length > 0 && !allowed.includes(key)) {
      results.push({ accepted: false, reason: "action_key_not_allowed", action_key: key });
      continue;
    }

    const webhookEventId = keysToRun.length > 1 ? `${opts.webhook_event_id}:${key}` : opts.webhook_event_id;
    const { data: result, error } = await supabase.rpc("fn_amp_record_line_postback", {
      p_merchant_id: opts.merchant_id,
      p_line_user_id: opts.line_user_id,
      p_webhook_event_id: webhookEventId,
      p_workflow_log_id: opts.ampCtx.workflow_log_id,
      p_message_node_id: opts.ampCtx.message_node_id,
      p_action_key: key,
      p_selection_mode: selectionMode,
      p_metadata: {
        postback_data: opts.postback_data,
        src: "amp",
      },
    });

    if (error) {
      console.error("fn_amp_record_line_postback error:", error);
      results.push({ accepted: false, reason: error.message, action_key: key });
      continue;
    }

    if (!result?.accepted) {
      results.push(result || { accepted: false, reason: "rejected", action_key: key });
      continue;
    }

    const payload = {
      engagement_event_id: result.engagement_event_id,
      merchant_id: result.merchant_id,
      workflow_id: result.workflow_id,
      message_node_id: result.message_node_id,
      workflow_log_id: result.workflow_log_id,
      action_key: result.action_key,
      line_user_id: result.line_user_id,
      user_id: result.user_id || null,
      selection_mode: result.selection_mode,
      route_snapshot: result.route_snapshot || snapshot,
    };

    const emitted = await emitInngestEvent("amp/content.postback", payload);
    if (!emitted.ok) {
      try {
        await inngestAmp.send({ name: "amp/content.postback", data: payload });
      } catch (e: any) {
        console.error("Inngest amp/content.postback failed (non-blocking):", e.message);
        results.push({ ...result, inngest_emitted: false, inngest_error: emitted.error || e.message, action_key: key });
        continue;
      }
    }

    results.push({ ...result, inngest_emitted: true, action_key: key });
  }

  const accepted = results.some((row) => row.accepted);
  return keysToRun.length === 1 ? { ...results[0], accepted } : { accepted, results, selection_mode: selectionMode };
}

Deno.serve(async (req: Request) => {
  if (req.method !== "POST") {
    return new Response("Method not allowed", { status: 405 });
  }

  const rawBody = await req.text();
  let body: any;
  try {
    body = JSON.parse(rawBody);
  } catch {
    return new Response(JSON.stringify({ error: "invalid_json" }), {
      status: 400,
      headers: { "Content-Type": "application/json" },
    });
  }

  const events = body.events || [];
  if (events.length === 0) {
    return new Response(JSON.stringify({ success: true, message: "no_events" }), {
      headers: { "Content-Type": "application/json" },
    });
  }

  const signature = req.headers.get("x-line-signature") || "";
  if (!signature) {
    return new Response(JSON.stringify({ error: "missing_signature" }), {
      status: 401,
      headers: { "Content-Type": "application/json" },
    });
  }

  const credential = await resolveCredentialBySignature(rawBody, signature);

  if (!credential) {
    console.error(`No credential matched LINE signature. destination=${body.destination || "none"}`);
    return new Response(JSON.stringify({ error: "unknown_channel" }), {
      status: 400,
      headers: { "Content-Type": "application/json" },
    });
  }

  scheduleLineWebhookFanOut(
    fanOutLineWebhook({
      destinations: credential.webhook_fanout_destinations,
      rawBody,
      signature,
      messagingChannelId: credential.messaging_channel_id,
    }),
  );

  const supabase = getSupabase();
  const results: any[] = [];
  const displayNameCache: Record<string, string | null> = {};

  for (const event of events) {
    const isMessage = event.type === "message";
    const isPostback = event.type === "postback";
    if (!isMessage && !isPostback) continue;

    const userId = event.source?.userId;
    if (!userId) continue;

    // AMP postback path — independent of CS
    if (isPostback) {
      const postbackData: string = event.postback?.data || "";
      const ampCtx = await parseAndVerifyAmpPostback(postbackData);
      if (ampCtx) {
        const webhookEventId = event.webhookEventId || `${body.destination || "dest"}:${event.timestamp}:${userId}:${ampCtx.action_key}`;
        try {
          const ampResult = await handleAmpPostback({
            merchant_id: credential.merchant_id,
            line_user_id: userId,
            webhook_event_id: webhookEventId,
            postback_data: postbackData,
            ampCtx,
          });
          results.push({ amp: true, ...ampResult, user_id: userId });
        } catch (e: any) {
          console.error("AMP postback error:", e);
          results.push({ amp: true, accepted: false, error: e.message, user_id: userId });
        }
        // AMP correctness must not depend on CS — skip CS for verified AMP postbacks
        continue;
      }
    }

    if (!(userId in displayNameCache)) {
      displayNameCache[userId] = await fetchLineDisplayName(userId, credential.access_token);
    }

    let content: string;
    let messageType: string;
    let eventMetadata: Record<string, unknown>;

    if (isPostback) {
      const postbackData: string = event.postback?.data || "";
      const parsed = parsePostbackData(postbackData);
      content = extractPostbackContent(event, parsed);
      messageType = "text";
      eventMetadata = {
        line_event_type: "postback",
        postback_data: postbackData,
        postback_params: event.postback?.params || null,
        postback_parsed: parsed,
        reply_token: event.replyToken,
        timestamp: event.timestamp,
        destination: body.destination,
      };
    } else {
      const message = event.message;
      content = extractMessageContent(message);
      messageType = mapLineMessageType(message.type);
      eventMetadata = {
        platform_message_id: message.id,
        line_event_type: event.type,
        reply_token: event.replyToken,
        timestamp: event.timestamp,
        destination: body.destination,
      };
    }

    try {
      const { data: result, error } = await supabase.rpc("cs_api_receive_message", {
        p_merchant_id: credential.merchant_id,
        p_platform_type: "line",
        p_platform_user_id: userId,
        p_message_content: content,
        p_message_type: messageType,
        p_platform_conversation_id: null,
        p_credential_id: credential.credential_id,
        p_display_name: displayNameCache[userId],
        p_modality: "chat",
        p_metadata: eventMetadata,
      });

      if (error) {
        console.error("cs_api_receive_message error:", error);
        results.push({ error: error.message, user_id: userId });
        continue;
      }

      const csEmit = await emitInngestEvent("cs/message.received", {
        conversation_id: result.conversation_id,
        contact_id: result.contact_id,
        message_id: result.message_id,
        merchant_id: credential.merchant_id,
        is_new_conversation: result.is_new_conversation,
        platform: "line",
        line_event_type: isPostback ? "postback" : "message",
      });
      if (!csEmit.ok) {
        try {
          await inngestCs.send({
            name: "cs/message.received",
            data: {
              conversation_id: result.conversation_id,
              contact_id: result.contact_id,
              message_id: result.message_id,
              merchant_id: credential.merchant_id,
              is_new_conversation: result.is_new_conversation,
              platform: "line",
              line_event_type: isPostback ? "postback" : "message",
            },
          });
        } catch (inngestErr: any) {
          console.error("Inngest send failed (non-blocking):", inngestErr.message);
        }
      }

      results.push({ success: true, ...result });
    } catch (e: any) {
      console.error("Event processing error:", e);
      results.push({ error: e.message, user_id: userId });
    }
  }

  return new Response(JSON.stringify({ success: true, processed: results.length, results }), {
    headers: { "Content-Type": "application/json" },
  });
});
