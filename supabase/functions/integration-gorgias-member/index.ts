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
  if (req.method !== "GET") return json({ error: "method_not_allowed" }, 405)

  const inboundSecret = req.headers.get("X-Rocket-Inbound-Secret")?.trim() ?? ""
  if (!inboundSecret) return json({ error: "unauthorized" }, 401)

  const url = new URL(req.url)
  const email = url.searchParams.get("email")?.trim() ?? ""
  if (!email) return json({ loyalty: {} })

  const supabase = createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
  )

  const merchant = await resolveMerchantByInboundSecret(supabase, inboundSecret)
  if (!merchant) return json({ error: "unauthorized" }, 401)

  const { data, error } = await supabase.rpc("fn_integration_gorgias_resolve_by_email", {
    p_merchant_id: merchant.merchantId,
    p_email: email,
    p_inbound_secret: inboundSecret,
  })

  if (error) {
    console.error("integration-gorgias-member", error.message)
    return json({ error: "lookup_failed" }, 500)
  }

  return json(data ?? { loyalty: {} })
})
