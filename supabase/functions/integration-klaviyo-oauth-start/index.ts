import "jsr:@supabase/functions-js/edge-runtime.d.ts"
import { AuthError, resolveAdminMerchant } from "../_shared/integration-oauth/admin-auth.ts"
import {
  KLAVIYO_AUTHORIZE_URL,
  KLAVIYO_SCOPES,
  klaviyoCallbackUrl,
} from "../_shared/integration-oauth/klaviyo-config.ts"
import { generatePkce, randomUrlSafe, signOAuthState } from "../_shared/integration-oauth/state.ts"
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
    const clientId = Deno.env.get("KLAVIYO_CLIENT_ID")
    if (!clientId) {
      return json({ success: false, title: "Klaviyo is not configured", description: "KLAVIYO_CLIENT_ID missing" }, 500)
    }

    const { verifier, challenge } = await generatePkce()
    const state = await signOAuthState({
      merchant_id: auth.merchantId,
      integration_key: "klaviyo",
      exp: Date.now() + 10 * 60 * 1000,
      nonce: randomUrlSafe(16),
    })

    await parkOAuthPending({
      merchantId: auth.merchantId,
      integrationKey: "klaviyo",
      state,
      codeVerifier: verifier,
    })

    const url = new URL(KLAVIYO_AUTHORIZE_URL)
    url.searchParams.set("response_type", "code")
    url.searchParams.set("client_id", clientId)
    url.searchParams.set("redirect_uri", klaviyoCallbackUrl())
    url.searchParams.set("scope", KLAVIYO_SCOPES)
    url.searchParams.set("state", state)
    url.searchParams.set("code_challenge_method", "S256")
    url.searchParams.set("code_challenge", challenge)

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
    console.error("integration-klaviyo-oauth-start", message)
    return json({ success: false, title: "OAuth start failed", description: message }, 500)
  }
})
