// engagement-beacon: page-engagement events from the member app (rct token or bc + JWT).
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.46.0";
import { verify } from "https://deno.land/x/djwt@v2.8/mod.ts";
import { getMemberJwtSecret } from "../_shared/member-session.ts";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SUPABASE_SERVICE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
const supabase = createClient(SUPABASE_URL, SUPABASE_SERVICE_KEY);

const ALLOWED_EVENT_TYPES = new Set(["page_view", "page_time", "scroll_depth"]);
const MAX_EVENTS_PER_REQUEST = 20;

function isAllowedOrigin(origin: string | null): boolean {
  if (!origin) return true;
  try {
    const host = new URL(origin).hostname;
    return host === "rocket-loyalty.app" || host.endsWith(".rocket-loyalty.app") || host === "localhost";
  } catch (_e) {
    return false;
  }
}

function corsHeaders(origin: string | null): Record<string, string> {
  return {
    "Access-Control-Allow-Origin": origin ?? "*",
    "Access-Control-Allow-Methods": "POST, OPTIONS",
    "Access-Control-Allow-Headers": "content-type, authorization",
    Vary: "Origin",
  };
}

function isUuid(value: string): boolean {
  return /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(value);
}

async function verifyMemberBearer(authHeader: string | null): Promise<{ user_id: string; merchant_id: string } | null> {
  if (!authHeader?.startsWith("Bearer ")) return null;
  const secret = getMemberJwtSecret();
  if (!secret) return null;
  const token = authHeader.slice(7);
  try {
    const key = await crypto.subtle.importKey(
      "raw",
      new TextEncoder().encode(secret),
      { name: "HMAC", hash: "SHA-256" },
      false,
      ["verify"],
    );
    const payload = await verify(token, key);
    const user_id = (payload.user_id as string) || (payload.sub as string);
    const merchant_id = payload.merchant_id as string;
    if (!user_id || !merchant_id) return null;
    return { user_id, merchant_id };
  } catch (_e) {
    return null;
  }
}

async function handleTokenBeacon(body: any, userAgent: string | null, origin: string | null): Promise<Response> {
  const token = typeof body?.token === "string" ? body.token : null;
  const sessionId = typeof body?.session_id === "string" ? body.session_id.slice(0, 64) : null;
  const events = Array.isArray(body?.events) ? body.events.slice(0, MAX_EVENTS_PER_REQUEST) : [];

  if (!token || !/^[0-9a-f]{8,32}$/.test(token) || events.length === 0) {
    return new Response(JSON.stringify({ success: false, error: "token and events[] required" }), {
      status: 400,
      headers: { "Content-Type": "application/json", ...corsHeaders(origin) },
    });
  }

  const { data: link } = await supabase
    .from("amp_tracked_link")
    .select("token, merchant_id, workflow_id, node_id, resource_id, user_id")
    .eq("token", token)
    .maybeSingle();

  if (!link) {
    return new Response(JSON.stringify({ success: false, error: "Unknown token" }), {
      status: 404,
      headers: { "Content-Type": "application/json", ...corsHeaders(origin) },
    });
  }

  const rows = [];
  for (const ev of events) {
    const type = ev?.type;
    if (!ALLOWED_EVENT_TYPES.has(type)) continue;
    let value: number | null = null;
    if (typeof ev.value === "number" && isFinite(ev.value)) {
      if (type === "page_time") value = Math.min(Math.max(ev.value, 0), 86400);
      else if (type === "scroll_depth") value = Math.min(Math.max(ev.value, 0), 100);
      else value = ev.value;
    }
    rows.push({
      token: link.token,
      event_type: type,
      value,
      session_id: sessionId,
      merchant_id: link.merchant_id,
      workflow_id: link.workflow_id,
      node_id: link.node_id,
      resource_id: link.resource_id,
      user_id: link.user_id,
      user_agent: userAgent,
    });
  }

  if (rows.length === 0) {
    return new Response(JSON.stringify({ success: false, error: "No valid events" }), {
      status: 400,
      headers: { "Content-Type": "application/json", ...corsHeaders(origin) },
    });
  }

  const { error } = await supabase.from("amp_engagement_event").insert(rows);
  if (error) {
    return new Response(JSON.stringify({ success: false, error: error.message }), {
      status: 500,
      headers: { "Content-Type": "application/json", ...corsHeaders(origin) },
    });
  }

  return new Response(JSON.stringify({ success: true, inserted: rows.length }), {
    status: 200,
    headers: { "Content-Type": "application/json", ...corsHeaders(origin) },
  });
}

async function handleBroadcastBeacon(
  body: any,
  session: { user_id: string; merchant_id: string },
  userAgent: string | null,
  origin: string | null,
): Promise<Response> {
  const broadcastId = typeof body?.broadcast_id === "string" ? body.broadcast_id : null;
  const sessionId = typeof body?.session_id === "string" ? body.session_id.slice(0, 64) : null;
  const events = Array.isArray(body?.events) ? body.events : [];

  if (!broadcastId || !isUuid(broadcastId) || events.length === 0) {
    return new Response(JSON.stringify({ success: false, error: "broadcast_id and events[] required" }), {
      status: 400,
      headers: { "Content-Type": "application/json", ...corsHeaders(origin) },
    });
  }

  const { data: result, error } = await supabase.rpc("fn_amp_record_broadcast_beacon", {
    p_broadcast_id: broadcastId,
    p_user_id: session.user_id,
    p_session_id: sessionId,
    p_events: events.slice(0, MAX_EVENTS_PER_REQUEST),
    p_user_agent: userAgent,
  });

  if (error) {
    return new Response(JSON.stringify({ success: false, error: error.message }), {
      status: 500,
      headers: { "Content-Type": "application/json", ...corsHeaders(origin) },
    });
  }

  if (!result?.success) {
    const status = result?.error === "broadcast_not_found" ? 404 : result?.error === "merchant_mismatch" ? 403 : 400;
    return new Response(JSON.stringify(result), {
      status,
      headers: { "Content-Type": "application/json", ...corsHeaders(origin) },
    });
  }

  return new Response(JSON.stringify(result), {
    status: 200,
    headers: { "Content-Type": "application/json", ...corsHeaders(origin) },
  });
}

Deno.serve(async (req: Request) => {
  const origin = req.headers.get("origin");

  if (req.method === "OPTIONS") {
    return new Response(null, { status: 204, headers: corsHeaders(origin) });
  }
  if (req.method !== "POST") {
    return new Response("Method not allowed", { status: 405 });
  }
  if (!isAllowedOrigin(origin)) {
    return new Response("Forbidden", { status: 403 });
  }

  let body: any;
  try {
    body = await req.json();
  } catch (_e) {
    return new Response(JSON.stringify({ success: false, error: "Invalid JSON" }), {
      status: 400,
      headers: { "Content-Type": "application/json", ...corsHeaders(origin) },
    });
  }

  const userAgent = req.headers.get("user-agent")?.slice(0, 500) ?? null;
  const broadcastId = typeof body?.broadcast_id === "string" ? body.broadcast_id : null;

  if (broadcastId) {
    const session = await verifyMemberBearer(req.headers.get("authorization"));
    if (!session) {
      return new Response(JSON.stringify({ success: false, error: "Unauthorized" }), {
        status: 401,
        headers: { "Content-Type": "application/json", ...corsHeaders(origin) },
      });
    }
    return handleBroadcastBeacon(body, session, userAgent, origin);
  }

  return handleTokenBeacon(body, userAgent, origin);
});
