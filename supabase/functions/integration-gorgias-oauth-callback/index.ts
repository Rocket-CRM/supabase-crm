import "jsr:@supabase/functions-js/edge-runtime.d.ts"
import {
  adminRedirectUrl,
  gorgiasCallbackUrl,
  gorgiasTokenUrl,
  sanitizeGorgiasSubdomain,
} from "../_shared/integration-oauth/gorgias-config.ts"
import {
  newInboundSecret,
  provisionGorgiasHelpdesk,
} from "../_shared/integration-oauth/gorgias-ops.ts"
import { verifyOAuthState } from "../_shared/integration-oauth/state.ts"
import { consumeOAuthPending, storeIntegrationTokens } from "../_shared/integration-oauth/tokens.ts"

function redirect(params: Record<string, string>) {
  return Response.redirect(adminRedirectUrl(params), 302)
}

function redirectReason(err: unknown): string {
  const message = err instanceof Error ? err.message : String(err)
  if (
    message.startsWith("token_exchange_") ||
    message.startsWith("gorgias_integration_") ||
    message.startsWith("gorgias_widget_") ||
    message.startsWith("oauth_pending_") ||
    message === "invalid_state" ||
    message === "expired_state" ||
    message === "gorgias_app_not_configured"
  ) {
    return message.slice(0, 160)
  }
  return "callback_failed"
}

function basicAuth(clientId: string, clientSecret: string): string {
  return `Basic ${btoa(`${clientId}:${clientSecret}`)}`
}

async function exchangeCode(
  subdomain: string,
  code: string,
  redirectUri: string,
) {
  const clientId = Deno.env.get("GORGIAS_CLIENT_ID")
  const clientSecret = Deno.env.get("GORGIAS_CLIENT_SECRET")
  if (!clientId || !clientSecret) throw new Error("gorgias_app_not_configured")

  const body = new URLSearchParams({
    grant_type: "authorization_code",
    code,
    redirect_uri: redirectUri,
  })

  const res = await fetch(gorgiasTokenUrl(subdomain), {
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

Deno.serve(async (req: Request) => {
  if (req.method !== "GET") {
    return new Response("Method not allowed", { status: 405 })
  }

  const url = new URL(req.url)
  const error = url.searchParams.get("error")
  if (error) {
    return redirect({ gorgias: "error", reason: error })
  }

  const code = url.searchParams.get("code")
  const state = url.searchParams.get("state")
  if (!code || !state) {
    return redirect({ gorgias: "error", reason: "missing_code" })
  }

  try {
    const payload = await verifyOAuthState(state)
    if (payload.integration_key !== "gorgias") {
      return redirect({ gorgias: "error", reason: "wrong_integration" })
    }

    const pending = await consumeOAuthPending({
      merchantId: payload.merchant_id,
      integrationKey: "gorgias",
      state,
    })

    const parked = pending.credentials.oauth_pending as
      | { account_subdomain?: string }
      | undefined
    const subdomain = sanitizeGorgiasSubdomain(parked?.account_subdomain)
    if (!subdomain) {
      return redirect({ gorgias: "error", reason: "invalid_subdomain" })
    }

    const redirectUri = gorgiasCallbackUrl()
    const tokens = await exchangeCode(subdomain, code, redirectUri)
    const inboundSecret = newInboundSecret()

    let provisionWarning: string | null = null
    let provisioned: { integrationId: number; widgetId: number } | null = null
    try {
      provisioned = await provisionGorgiasHelpdesk({
        subdomain,
        accessToken: tokens.access_token,
        inboundSecret,
      })
    } catch (err) {
      const message = err instanceof Error ? err.message : String(err)
      console.error("integration-gorgias-oauth-callback provision", message)
      provisionWarning =
        "Gorgias authorized but the ticket sidebar could not be created automatically. Disconnect and connect again, or contact support."
    }

    await storeIntegrationTokens({
      credentialId: pending.credentialId,
      accessToken: tokens.access_token,
      refreshToken: tokens.refresh_token,
      expiresIn: tokens.expires_in,
      accountName: subdomain,
      healthStatus: provisionWarning ? "degraded" : "connected",
      extra: {
        account_subdomain: subdomain,
        inbound_secret: inboundSecret,
        gorgias_integration_id: provisioned?.integrationId ?? null,
        gorgias_widget_id: provisioned?.widgetId ?? null,
        auth_type: "oauth",
        provision_warning: provisionWarning,
      },
    })

    if (provisionWarning) {
      return redirect({ gorgias: "connected", provision: "degraded" })
    }
    return redirect({ gorgias: "connected" })
  } catch (err) {
    const message = err instanceof Error ? err.message : String(err)
    console.error("integration-gorgias-oauth-callback", message)
    return redirect({ gorgias: "error", reason: redirectReason(err) })
  }
})
