import "jsr:@supabase/functions-js/edge-runtime.d.ts"
import { createClient } from "jsr:@supabase/supabase-js@2"
import { resolveMerchantByInboundSecret } from "../_shared/integration-oauth/gorgias-ops.ts"

const corsHeaders: Record<string, string> = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type, x-rocket-inbound-secret",
}

function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  })
}

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders })
  if (req.method !== "POST") return json({ ok: false, reason: "method_not_allowed" }, 405)

  const inboundSecret = req.headers.get("X-Rocket-Inbound-Secret")?.trim() ?? ""
  if (!inboundSecret) return json({ ok: false, reason: "unauthorized" }, 401)

  const payload = await req.json().catch(() => ({})) as Record<string, unknown>
  const email = String(
    payload.email ?? payload.customer_email ?? payload.ticket_customer_email ?? "",
  ).trim()
  const points = Number(payload.points ?? payload.amount ?? 0)
  const reason = String(payload.reason ?? "").trim()
  const ticketId = String(payload.ticket_id ?? payload.ticketId ?? "").trim()
  const agentEmail = String(payload.agent_email ?? payload.agentEmail ?? "").trim()

  if (!email) return json({ ok: false, reason: "missing_email" }, 400)
  if (!Number.isFinite(points) || points <= 0) {
    return json({ ok: false, reason: "invalid_points" }, 400)
  }

  const supabase = createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
  )

  const merchant = await resolveMerchantByInboundSecret(supabase, inboundSecret)
  if (!merchant) return json({ ok: false, reason: "unauthorized" }, 401)

  const { data, error } = await supabase.rpc("fn_integration_gorgias_award_points", {
    p_merchant_id: merchant.merchantId,
    p_email: email,
    p_inbound_secret: inboundSecret,
    p_points: Math.floor(points),
    p_reason: reason || null,
    p_ticket_id: ticketId || null,
    p_agent_email: agentEmail || null,
  })

  if (error) {
    console.error("integration-gorgias-adjust", error.message)
    return json({ ok: false, reason: "award_failed" }, 500)
  }

  const result = data as { ok?: boolean; reason?: string }
  if (!result?.ok) {
    return json(result ?? { ok: false, reason: "award_failed" }, 400)
  }

  return json(result)
})
