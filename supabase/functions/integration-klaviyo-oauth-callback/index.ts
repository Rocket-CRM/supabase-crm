import "jsr:@supabase/functions-js/edge-runtime.d.ts"
import {
  KLAVIYO_API_BASE,
  KLAVIYO_API_REVISION,
  KLAVIYO_TOKEN_URL,
  adminRedirectUrl,
  klaviyoCallbackUrl,
} from "../_shared/integration-oauth/klaviyo-config.ts"
import { verifyOAuthState } from "../_shared/integration-oauth/state.ts"
import { consumeOAuthPending, storeIntegrationTokens } from "../_shared/integration-oauth/tokens.ts"

function redirect(params: Record<string, string>) {
  return Response.redirect(adminRedirectUrl(params), 302)
}

function basicAuth(clientId: string, clientSecret: string): string {
  return `Basic ${btoa(`${clientId}:${clientSecret}`)}`
}

async function exchangeCode(code: string, codeVerifier: string) {
  const clientId = Deno.env.get("KLAVIYO_CLIENT_ID")
  const clientSecret = Deno.env.get("KLAVIYO_CLIENT_SECRET")
  if (!clientId || !clientSecret) throw new Error("klaviyo_app_not_configured")

  const body = new URLSearchParams({
    grant_type: "authorization_code",
    code,
    code_verifier: codeVerifier,
    redirect_uri: klaviyoCallbackUrl(),
  })
  const res = await fetch(KLAVIYO_TOKEN_URL, {
    method: "POST",
    headers: {
      Authorization: basicAuth(clientId, clientSecret),
      "Content-Type": "application/x-www-form-urlencoded",
    },
    body,
  })
  const text = await res.text()
  if (!res.ok) throw new Error(`token_exchange_${res.status}:${text.slice(0, 200)}`)
  return JSON.parse(text) as {
    access_token: string
    refresh_token?: string
    expires_in?: number
  }
}

async function fetchAccountName(accessToken: string): Promise<string | null> {
  const res = await fetch(`${KLAVIYO_API_BASE}/api/accounts/`, {
    headers: {
      Authorization: `Bearer ${accessToken}`,
      revision: KLAVIYO_API_REVISION,
      Accept: "application/vnd.api+json",
    },
  })
  if (!res.ok) return null
  const json = await res.json() as {
    data?: Array<{ attributes?: { company_name?: string } }>
  }
  return json.data?.[0]?.attributes?.company_name ?? null
}

Deno.serve(async (req: Request) => {
  if (req.method !== "GET") {
    return new Response("Method not allowed", { status: 405 })
  }

  const url = new URL(req.url)
  const error = url.searchParams.get("error")
  if (error) {
    return redirect({ klaviyo: "error", reason: error })
  }

  const code = url.searchParams.get("code")
  const state = url.searchParams.get("state")
  if (!code || !state) {
    return redirect({ klaviyo: "error", reason: "missing_code" })
  }

  try {
    const payload = await verifyOAuthState(state)
    if (payload.integration_key !== "klaviyo") {
      return redirect({ klaviyo: "error", reason: "wrong_integration" })
    }
    const pending = await consumeOAuthPending({
      merchantId: payload.merchant_id,
      integrationKey: "klaviyo",
      state,
    })
    const tokens = await exchangeCode(code, pending.codeVerifier)
    const accountName = await fetchAccountName(tokens.access_token)
    await storeIntegrationTokens({
      credentialId: pending.credentialId,
      accessToken: tokens.access_token,
      refreshToken: tokens.refresh_token,
      expiresIn: tokens.expires_in,
      accountName,
      extra: { sync_new_members: pending.credentials.sync_new_members ?? true },
    })
    return redirect({ klaviyo: "connected" })
  } catch (err) {
    const message = err instanceof Error ? err.message : String(err)
    console.error("integration-klaviyo-oauth-callback", message)
    return redirect({ klaviyo: "error", reason: "callback_failed" })
  }
})
