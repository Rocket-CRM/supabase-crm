import "jsr:@supabase/functions-js/edge-runtime.d.ts"
import { AuthError, resolveAdminMerchant } from "../_shared/integration-oauth/admin-auth.ts"
import {
  JUDGEME_AUTHORIZE_URL,
  JUDGEME_SCOPES,
  judgemeCallbackUrl,
  sanitizeShopHandle,
} from "../_shared/integration-oauth/judgeme-config.ts"
import { resolveJudgemeShopDomain } from "../_shared/integration-oauth/judgeme-ops.ts"
import { randomUrlSafe, signOAuthState } from "../_shared/integration-oauth/state.ts"
import { parkOAuthPending, serviceClient } from "../_shared/integration-oauth/tokens.ts"

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
    const clientId = Deno.env.get("JUDGEME_CLIENT_ID")
    if (!clientId) {
      return json({
        success: false,
        title: "Judge.me is not configured",
        description: "JUDGEME_CLIENT_ID missing",
      }, 500)
    }

    const state = await signOAuthState({
      merchant_id: auth.merchantId,
      integration_key: "judgeme",
      exp: Date.now() + 10 * 60 * 1000,
      nonce: randomUrlSafe(16),
    })

    const shopDomain = await resolveJudgemeShopDomain(serviceClient(), auth.merchantId)

    await parkOAuthPending({
      merchantId: auth.merchantId,
      integrationKey: "judgeme",
      state,
      codeVerifier: randomUrlSafe(16),
      extra: {
        shop_handle: sanitizeShopHandle(shopDomain),
      },
    })

    const url = new URL(JUDGEME_AUTHORIZE_URL)
    url.searchParams.set("response_type", "code")
    url.searchParams.set("client_id", clientId)
    url.searchParams.set("redirect_uri", judgemeCallbackUrl())
    url.searchParams.set("scope", JUDGEME_SCOPES)
    url.searchParams.set("state", state)
    if (shopDomain) {
      url.searchParams.set("shop_domain", shopDomain)
    }

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
    console.error("integration-judgeme-oauth-start", message)
    return json({ success: false, title: "OAuth start failed", description: message }, 500)
  }
})
