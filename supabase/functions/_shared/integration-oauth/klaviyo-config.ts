export const KLAVIYO_API_REVISION = "2026-01-15"
export const KLAVIYO_AUTHORIZE_URL = "https://www.klaviyo.com/oauth/authorize"
export const KLAVIYO_TOKEN_URL = "https://a.klaviyo.com/oauth/token"
export const KLAVIYO_API_BASE = "https://a.klaviyo.com"
export const KLAVIYO_SCOPES =
  "accounts:read profiles:read profiles:write lists:read lists:write events:write"

export function klaviyoCallbackUrl(): string {
  const supabaseUrl = Deno.env.get("SUPABASE_URL") ?? "https://wkevmsedchftztoolkmi.supabase.co"
  return `${supabaseUrl.replace(/\/$/, "")}/functions/v1/integration-klaviyo-oauth-callback`
}

export function adminRedirectUrl(params: Record<string, string>): string {
  const origin = (Deno.env.get("LOYALTY_ADMIN_ORIGIN") ?? "https://portal.rocket-loyalty.com")
    .replace(/\/$/, "")
  const qs = new URLSearchParams(params).toString()
  return `${origin}/integrations?${qs}`
}
