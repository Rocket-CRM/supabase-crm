import { createClient } from "jsr:@supabase/supabase-js@2"

export function serviceClient() {
  return createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
  )
}

export async function parkOAuthPending(input: {
  merchantId: string
  integrationKey: string
  state: string
  codeVerifier: string
  extra?: Record<string, unknown>
}): Promise<void> {
  const supabase = serviceClient()
  const pending = {
    state: input.state,
    code_verifier: input.codeVerifier,
    expires_at: new Date(Date.now() + 10 * 60 * 1000).toISOString(),
    ...(input.extra ?? {}),
  }

  const { data: existing } = await supabase
    .from("merchant_credentials")
    .select("id, credentials")
    .eq("merchant_id", input.merchantId)
    .eq("service_name", input.integrationKey)
    .order("updated_at", { ascending: false })
    .limit(1)
    .maybeSingle()

  if (existing?.id) {
    await supabase
      .from("merchant_credentials")
      .update({
        credentials: { ...(existing.credentials as object), oauth_pending: pending },
        updated_at: new Date().toISOString(),
      })
      .eq("id", existing.id)
    return
  }

  await supabase.from("merchant_credentials").insert({
    merchant_id: input.merchantId,
    service_name: input.integrationKey,
    credentials: { oauth_pending: pending, sync_new_members: true },
    environment: "production",
    is_active: false,
    health_status: "disconnected",
    updated_at: new Date().toISOString(),
  })
}

export async function consumeOAuthPending(input: {
  merchantId: string
  integrationKey: string
  state: string
}): Promise<{ credentialId: string; codeVerifier: string; credentials: Record<string, unknown> }> {
  const supabase = serviceClient()
  const { data: existing } = await supabase
    .from("merchant_credentials")
    .select("id, credentials")
    .eq("merchant_id", input.merchantId)
    .eq("service_name", input.integrationKey)
    .order("updated_at", { ascending: false })
    .limit(1)
    .maybeSingle()

  if (!existing?.id) throw new Error("oauth_pending_missing")
  const credentials = (existing.credentials ?? {}) as Record<string, unknown>
  const pending = credentials.oauth_pending as
    | { state?: string; code_verifier?: string; expires_at?: string }
    | undefined
  if (!pending?.code_verifier || pending.state !== input.state) {
    throw new Error("oauth_pending_mismatch")
  }
  if (pending.expires_at && Date.parse(pending.expires_at) < Date.now()) {
    throw new Error("oauth_pending_expired")
  }
  return { credentialId: existing.id, codeVerifier: pending.code_verifier, credentials }
}

export async function storeIntegrationTokens(input: {
  credentialId: string
  accessToken: string
  refreshToken?: string
  expiresIn?: number
  accountName?: string | null
  healthStatus?: "connected" | "degraded"
  extra?: Record<string, unknown>
}): Promise<void> {
  const supabase = serviceClient()
  const { data: existing } = await supabase
    .from("merchant_credentials")
    .select("credentials")
    .eq("id", input.credentialId)
    .maybeSingle()

  const prev = (existing?.credentials ?? {}) as Record<string, unknown>
  const next = { ...prev, ...input.extra }
  delete next.oauth_pending
  next.access_token = input.accessToken
  if (input.refreshToken) next.refresh_token = input.refreshToken
  if (input.accountName) next.account_name = input.accountName
  if (next.sync_new_members === undefined) next.sync_new_members = true

  const expiresAt = input.expiresIn
    ? new Date(Date.now() + input.expiresIn * 1000).toISOString()
    : null

  await supabase
    .from("merchant_credentials")
    .update({
      credentials: next,
      is_active: true,
      health_status: input.healthStatus ?? "connected",
      last_health_check: new Date().toISOString(),
      expires_at: expiresAt,
      updated_at: new Date().toISOString(),
    })
    .eq("id", input.credentialId)
}
