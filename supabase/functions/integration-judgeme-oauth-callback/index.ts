import "jsr:@supabase/functions-js/edge-runtime.d.ts"
import { createClient } from "jsr:@supabase/supabase-js@2"
import {
  JUDGEME_TOKEN_URL,
  JUDGEME_WEBHOOK_KEYS,
  adminRedirectUrl,
  judgemeCallbackUrl,
  sanitizeShopHandle,
  shopifyAdminAppUrl,
  webhookReceiverUrl,
} from "../_shared/integration-oauth/judgeme-config.ts"
import {
  fetchJudgemeShopDomain,
  registerJudgemeWebhooks,
  resolveJudgemeShopDomain,
} from "../_shared/integration-oauth/judgeme-ops.ts"
import { verifyOAuthState } from "../_shared/integration-oauth/state.ts"
import { consumeOAuthPending, storeIntegrationTokens } from "../_shared/integration-oauth/tokens.ts"

function redirectReason(err: unknown): string {
  const message = err instanceof Error ? err.message : String(err)
  if (
    message.startsWith("token_exchange_") ||
    message.startsWith("oauth_pending_") ||
    message === "invalid_state" ||
    message === "expired_state"
  ) {
    return message.slice(0, 160)
  }
  return "callback_failed"
}

function redirect(
  params: Record<string, string>,
  shopHandle?: string | null,
) {
  const handle = sanitizeShopHandle(shopHandle)
  if (handle) {
    return Response.redirect(
      shopifyAdminAppUrl(handle, "/integrations/judgeme", params),
      302,
    )
  }
  return Response.redirect(adminRedirectUrl(params), 302)
}

async function exchangeCode(code: string, state: string) {
  const clientId = Deno.env.get("JUDGEME_CLIENT_ID")
  const clientSecret = Deno.env.get("JUDGEME_CLIENT_SECRET")
  if (!clientId || !clientSecret) throw new Error("judgeme_app_not_configured")

  const res = await fetch(JUDGEME_TOKEN_URL, {
    method: "POST",
    headers: {
      Accept: "application/json",
      "Content-Type": "application/json",
    },
    body: JSON.stringify({
      client_id: clientId,
      client_secret: clientSecret,
      code,
      redirect_uri: judgemeCallbackUrl(),
      state,
      grant_type: "authorization_code",
    }),
  })
  const text = await res.text()
  if (!res.ok) throw new Error(`token_exchange_${res.status}:${text.slice(0, 200)}`)
  return JSON.parse(text) as {
    access_token: string
    token_type?: string
    scope?: string
  }
}

Deno.serve(async (req: Request) => {
  if (req.method !== "GET") {
    return new Response("Method not allowed", { status: 405 })
  }

  const url = new URL(req.url)
  const state = url.searchParams.get("state")

  async function shopHandleFromState(): Promise<string | null> {
    if (!state) return null
    try {
      const payload = await verifyOAuthState(state)
      const supabase = createClient(
        Deno.env.get("SUPABASE_URL")!,
        Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
      )
      return sanitizeShopHandle(
        await resolveJudgemeShopDomain(supabase, payload.merchant_id),
      )
    } catch {
      return null
    }
  }

  const error = url.searchParams.get("error")
  if (error) {
    return redirect({ judgeme: "error", reason: error }, await shopHandleFromState())
  }

  const code = url.searchParams.get("code")
  if (!code || !state) {
    return redirect({ judgeme: "error", reason: "missing_code" }, await shopHandleFromState())
  }

  try {
    const payload = await verifyOAuthState(state)
    if (payload.integration_key !== "judgeme") {
      return redirect({ judgeme: "error", reason: "wrong_integration" })
    }
    const pending = await consumeOAuthPending({
      merchantId: payload.merchant_id,
      integrationKey: "judgeme",
      state,
    })
    const parked = pending.credentials.oauth_pending as
      | { shop_handle?: string }
      | undefined
    const shopHandle = sanitizeShopHandle(parked?.shop_handle)
    const tokens = await exchangeCode(code, state)
    const supabase = createClient(
      Deno.env.get("SUPABASE_URL")!,
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
    )
    const shopDomain =
      (await resolveJudgemeShopDomain(supabase, payload.merchant_id)) ??
      (await fetchJudgemeShopDomain(tokens.access_token))
    if (!shopDomain) {
      return redirect({ judgeme: "error", reason: "shop_domain_required" }, shopHandle)
    }

    const webhookIds = await registerJudgemeWebhooks(tokens.access_token, shopDomain)
      .catch((err) => {
        const message = err instanceof Error ? err.message : String(err)
        console.error("integration-judgeme-oauth-callback webhooks", message)
        return [] as number[]
      })
    const webhookWarning =
      webhookIds.length < JUDGEME_WEBHOOK_KEYS.length
        ? "Some Judge.me review webhooks could not be registered. Disconnect and connect again, or contact support."
        : null

    await storeIntegrationTokens({
      credentialId: pending.credentialId,
      accessToken: tokens.access_token,
      extra: {
        api_token: tokens.access_token,
        shop_domain: shopDomain,
        webhook_ids: webhookIds,
        webhook_url: webhookReceiverUrl(),
        auth_type: "oauth",
        scope: tokens.scope ?? null,
        webhook_warning: webhookWarning,
      },
    })
    if (webhookWarning) {
      return redirect({ judgeme: "connected", webhook: "degraded" }, shopHandle)
    }
    return redirect({ judgeme: "connected" }, shopHandle)
  } catch (err) {
    const message = err instanceof Error ? err.message : String(err)
    console.error("integration-judgeme-oauth-callback", message)
    return redirect(
      { judgeme: "error", reason: redirectReason(err) },
      await shopHandleFromState(),
    )
  }
})
