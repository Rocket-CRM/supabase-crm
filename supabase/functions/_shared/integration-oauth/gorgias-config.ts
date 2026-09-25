export const GORGIAS_SCOPES =
  "openid email profile offline integrations:write"

export function sanitizeGorgiasSubdomain(
  raw: string | null | undefined,
): string | null {
  const value = raw?.trim().toLowerCase() ?? ""
  if (!value) return null
  const host = value
    .replace(/\.gorgias\.com$/, "")
    .replace(/^https?:\/\//, "")
    .split("/")[0]
  if (!/^[a-z0-9](?:[a-z0-9-]*[a-z0-9])?$/.test(host)) return null
  return host
}

export function gorgiasAuthorizeUrl(subdomain: string): string {
  return `https://${subdomain}.gorgias.com/oauth/authorize`
}

export function gorgiasTokenUrl(subdomain: string): string {
  return `https://${subdomain}.gorgias.com/oauth/token`
}

export function gorgiasApiBase(subdomain: string): string {
  return `https://${subdomain}.gorgias.com/api`
}

export function gorgiasCallbackUrl(): string {
  const supabaseUrl =
    Deno.env.get("SUPABASE_URL") ?? "https://wkevmsedchftztoolkmi.supabase.co"
  return `${supabaseUrl.replace(/\/$/, "")}/functions/v1/integration-gorgias-oauth-callback`
}

export function adminRedirectUrl(params: Record<string, string>): string {
  const origin = (
    Deno.env.get("LOYALTY_ADMIN_ORIGIN") ?? "https://portal.rocket-loyalty.com"
  ).replace(/\/$/, "")
  const qs = new URLSearchParams(params).toString()
  return `${origin}/integrations?${qs}`
}

export function gorgiasMemberUrl(): string {
  const supabaseUrl =
    Deno.env.get("SUPABASE_URL") ?? "https://wkevmsedchftztoolkmi.supabase.co"
  return `${supabaseUrl.replace(/\/$/, "")}/functions/v1/integration-gorgias-member?email={{ticket.customer.email}}`
}

export function gorgiasAdjustUrl(): string {
  const supabaseUrl =
    Deno.env.get("SUPABASE_URL") ?? "https://wkevmsedchftztoolkmi.supabase.co"
  return `${supabaseUrl.replace(/\/$/, "")}/functions/v1/integration-gorgias-adjust`
}
