import "jsr:@supabase/functions-js/edge-runtime.d.ts"
import { AuthError, resolveAdminMerchant } from "../_shared/integration-oauth/admin-auth.ts"
import {
  GORGIAS_SCOPES,
  gorgiasAuthorizeUrl,
  gorgiasCallbackUrl,
  sanitizeGorgiasSubdomain,
} from "../_shared/integration-oauth/gorgias-config.ts"
import { randomUrlSafe, signOAuthState } from "../_shared/integration-oauth/state.ts"
import { parkOAuthPending } from "../_shared/integration-oauth/tokens.ts"

const corsHeaders: Record<string, string> = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type, x-merchant-id, x-merchant-code",
}

function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  })
}

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders })
  if (req.method !== "POST") return json({ success: false, title: "Method not allowed" }, 405)

  try {
    const auth = await resolveAdminMerchant(req)
    const clientId = Deno.env.get("GORGIAS_CLIENT_ID")
    if (!clientId) {
      return json({
        success: false,
        title: "Gorgias is not configured",
        description: "GORGIAS_CLIENT_ID missing",
      }, 500)
    }

    const body = await req.json().catch(() => ({})) as {
      account_subdomain?: string
    }
    const subdomain = sanitizeGorgiasSubdomain(body.account_subdomain)
    if (!subdomain) {
      return json({
        success: false,
        title: "Invalid Gorgias account",
        description: "Enter a valid Gorgias account name",
      }, 400)
    }

    const state = await signOAuthState({
      merchant_id: auth.merchantId,
      integration_key: "gorgias",
      exp: Date.now() + 10 * 60 * 1000,
      nonce: randomUrlSafe(16),
    })

    await parkOAuthPending({
      merchantId: auth.merchantId,
      integrationKey: "gorgias",
      state,
      codeVerifier: randomUrlSafe(16),
      extra: { account_subdomain: subdomain },
    })

    const redirectUri = gorgiasCallbackUrl()
    const url = new URL(gorgiasAuthorizeUrl(subdomain))
    url.searchParams.set("response_type", "code")
    url.searchParams.set("client_id", clientId)
    url.searchParams.set("redirect_uri", redirectUri)
    url.searchParams.set("scope", GORGIAS_SCOPES)
    url.searchParams.set("state", state)
    url.searchParams.set("nonce", randomUrlSafe(16))

    return json({
      success: true,
      title: null,
      description: null,
      data: { authorization_url: url.toString() },
    })
  } catch (err) {
    if (err instanceof AuthError) {
      return json({ success: false, title: err.message }, err.status)
    }
    const message = err instanceof Error ? err.message : String(err)
    console.error("integration-gorgias-oauth-start", message)
    return json({ success: false, title: "OAuth start failed", description: message }, 500)
  }
})
