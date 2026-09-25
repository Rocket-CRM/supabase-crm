export const JUDGEME_AUTHORIZE_URL = "https://app.judge.me/oauth/authorize"
export const JUDGEME_TOKEN_URL = "https://judge.me/oauth/token"
export const JUDGE_ME_API = "https://api.judge.me/api/v1"
export const JUDGEME_SCOPES =
  "public read_shops read_reviews write_reviews read_reviewers write_settings"
export const JUDGEME_WEBHOOK_KEYS = [
  "review/created",
  "review/updated",
] as const

export function judgemeCallbackUrl(): string {
  const supabaseUrl = Deno.env.get("SUPABASE_URL") ?? "https://wkevmsedchftztoolkmi.supabase.co"
  return `${supabaseUrl.replace(/\/$/, "")}/functions/v1/integration-judgeme-oauth-callback`
}

export function adminRedirectUrl(params: Record<string, string>): string {
  const origin = (Deno.env.get("LOYALTY_ADMIN_ORIGIN") ?? "https://portal.rocket-loyalty.com")
    .replace(/\/$/, "")
  const qs = new URLSearchParams(params).toString()
  return `${origin}/integrations?${qs}`
}

export function shopifyAdminAppUrl(
  shopHandle: string,
  path: string,
  params: Record<string, string>,
): string {
  const appHandle = Deno.env.get("SHOPIFY_APP_HANDLE") ?? "rocket-loyalty-crm"
  const qs = new URLSearchParams(params).toString()
  const suffix = path.startsWith("/") ? path : `/${path}`
  return `https://admin.shopify.com/store/${shopHandle}/apps/${appHandle}${suffix}?${qs}`
}

export function sanitizeShopHandle(raw: string | null | undefined): string | null {
  const value = raw?.trim().toLowerCase() ?? ""
  if (!value) return null
  const handle = value.replace(/\.myshopify\.com$/, "").replace(/^https?:\/\//, "").split("/")[0]
  if (!/^[a-z0-9][a-z0-9-]*$/.test(handle)) return null
  return handle
}

export function webhookReceiverUrl(): string {
  const supabaseUrl = Deno.env.get("SUPABASE_URL") ?? "https://wkevmsedchftztoolkmi.supabase.co"
  return `${supabaseUrl.replace(/\/$/, "")}/functions/v1/integration-judgeme-webhooks`
}

export function normalizeMyshopifyDomain(raw: string | null | undefined): string | null {
  const value = raw?.trim().toLowerCase() ?? ""
  if (!value) return null
  const host = value.replace(/^https?:\/\//, "").split("/")[0]
  if (!host.endsWith(".myshopify.com")) return null
  return host
}
