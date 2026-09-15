import type { SupabaseClient } from "https://esm.sh/@supabase/supabase-js@2.38.4";

export const REFRESH_WINDOW_MS = 15 * 60 * 1000;

export type ShopifyCredentialRecord = {
  id: string;
  merchant_id: string;
  credentials: Record<string, unknown>;
};

export function toIsoFromSeconds(seconds?: number): string | null {
  if (!seconds || Number.isNaN(seconds)) return null;
  return new Date(Date.now() + seconds * 1000).toISOString();
}

export function isNearExpiry(credentials: Record<string, unknown>): boolean {
  if (credentials.token_mode !== "offline_expiring" || !credentials.refresh_token) return false;
  if (!credentials.expires_at) return true;
  const expiresAt = new Date(String(credentials.expires_at)).getTime();
  return Number.isNaN(expiresAt) || expiresAt <= Date.now() + REFRESH_WINDOW_MS;
}

export function isTokenAuthFailure(status: number, bodyText = ""): boolean {
  if (status === 401) return true;
  if (status !== 403) return false;
  const lower = bodyText.toLowerCase();
  return (
    lower.includes("invalid api key") ||
    lower.includes("access token") ||
    lower.includes("unauthorized") ||
    lower.includes("token has expired")
  );
}

export async function getFreshShopifyCredentialForMerchant(
  supabase: SupabaseClient,
  merchantId: string,
): Promise<ShopifyCredentialRecord> {
  const record = await loadActiveShopifyCredential(supabase, { merchantId });
  if (!record) throw new Error("No active Shopify credentials found for this merchant");
  return await ensureFreshShopifyCredential(supabase, record);
}

export async function loadActiveShopifyCredential(
  supabase: SupabaseClient,
  opts: { merchantId?: string; shopDomain?: string; credentialId?: string },
): Promise<ShopifyCredentialRecord | null> {
  let query = supabase
    .from("merchant_credentials")
    .select("id, merchant_id, credentials")
    .eq("service_name", "shopify_app")
    .eq("is_active", true);

  if (opts.credentialId) query = query.eq("id", opts.credentialId);
  if (opts.merchantId) query = query.eq("merchant_id", opts.merchantId);
  if (opts.shopDomain) query = query.filter("credentials->>shop_domain", "eq", opts.shopDomain);

  const { data, error } = await query.limit(1).maybeSingle();
  if (error || !data) return null;
  return {
    id: data.id,
    merchant_id: data.merchant_id,
    credentials: (data.credentials || {}) as Record<string, unknown>,
  };
}

async function reloadCredential(
  supabase: SupabaseClient,
  credentialId: string,
): Promise<ShopifyCredentialRecord> {
  const reloaded = await loadActiveShopifyCredential(supabase, { credentialId });
  if (!reloaded) throw new Error("Shopify credential disappeared during refresh");
  return reloaded;
}

async function markCredentialHealth(
  supabase: SupabaseClient,
  record: ShopifyCredentialRecord,
  status: string,
): Promise<void> {
  const nextCredentials = {
    ...record.credentials,
    health_status: status,
    last_health_check: new Date().toISOString(),
  };
  await supabase
    .from("merchant_credentials")
    .update({
      credentials: nextCredentials,
      health_status: status,
      last_health_check: new Date().toISOString(),
      updated_at: new Date().toISOString(),
    })
    .eq("id", record.id);
}

export async function refreshShopifyTokenCas(
  supabase: SupabaseClient,
  record: ShopifyCredentialRecord,
): Promise<ShopifyCredentialRecord> {
  const credentials = record.credentials || {};
  const shopDomain = credentials.shop_domain;
  const apiKey = credentials.api_key || Deno.env.get("SHOPIFY_API_KEY");
  const apiSecret = credentials.api_secret || Deno.env.get("SHOPIFY_API_SECRET");
  const oldRefreshToken = credentials.refresh_token;

  if (!shopDomain || !apiKey || !apiSecret || !oldRefreshToken) {
    await markCredentialHealth(supabase, record, "reauth_required");
    throw new Error("Shopify credential requires admin reauth");
  }

  const body = new URLSearchParams();
  body.set("client_id", String(apiKey));
  body.set("client_secret", String(apiSecret));
  body.set("grant_type", "refresh_token");
  body.set("refresh_token", String(oldRefreshToken));

  const response = await fetch(`https://${shopDomain}/admin/oauth/access_token`, {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded", Accept: "application/json" },
    body,
  });

  const data = await response.json().catch(() => ({}));
  if (!response.ok || !data.access_token || !data.refresh_token) {
    const status =
      response.status === 400 || response.status === 401 ? "reauth_required" : "refresh_failed";
    await markCredentialHealth(supabase, record, status);
    throw new Error(data.error_description || data.error || `Shopify token refresh failed (${response.status})`);
  }

  const expiresAt = toIsoFromSeconds(data.expires_in);
  const refreshTokenExpiresAt = toIsoFromSeconds(data.refresh_token_expires_in);
  const nextCredentials = {
    ...credentials,
    access_token: data.access_token,
    refresh_token: data.refresh_token,
    token_mode: "offline_expiring",
    scope: data.scope || credentials.scope || null,
    expires_at: expiresAt,
    refresh_token_expires_at: refreshTokenExpiresAt,
    health_status: "healthy",
    last_health_check: new Date().toISOString(),
    token_updated_at: new Date().toISOString(),
  };

  const { data: updated, error } = await supabase
    .from("merchant_credentials")
    .update({
      credentials: nextCredentials,
      expires_at: expiresAt,
      health_status: "healthy",
      last_health_check: new Date().toISOString(),
      updated_at: new Date().toISOString(),
    })
    .eq("id", record.id)
    .eq("credentials->>refresh_token", String(oldRefreshToken))
    .select("id, merchant_id, credentials")
    .maybeSingle();

  if (error) throw new Error(`Failed to persist Shopify token refresh: ${error.message}`);
  if (updated) {
    return {
      id: updated.id,
      merchant_id: updated.merchant_id,
      credentials: (updated.credentials || {}) as Record<string, unknown>,
    };
  }

  return await reloadCredential(supabase, record.id);
}

export async function ensureFreshShopifyCredential(
  supabase: SupabaseClient,
  record: ShopifyCredentialRecord,
): Promise<ShopifyCredentialRecord> {
  if (isNearExpiry(record.credentials || {})) {
    return await refreshShopifyTokenCas(supabase, record);
  }
  return record;
}

export async function shopifyAdminFetch(
  supabase: SupabaseClient,
  record: ShopifyCredentialRecord,
  input: string,
  init?: RequestInit,
): Promise<{ response: Response; record: ShopifyCredentialRecord; bodyText: string }> {
  let current = await ensureFreshShopifyCredential(supabase, record);

  const doFetch = (cred: ShopifyCredentialRecord) => {
    const headers = new Headers(init?.headers);
    headers.set("X-Shopify-Access-Token", String(cred.credentials.access_token));
    return fetch(input, { ...init, headers });
  };

  let response = await doFetch(current);
  let bodyText = await response.text();

  if (
    isTokenAuthFailure(response.status, bodyText) &&
    current.credentials.token_mode === "offline_expiring" &&
    current.credentials.refresh_token
  ) {
    current = await refreshShopifyTokenCas(supabase, current);
    response = await doFetch(current);
    bodyText = await response.text();
  }

  return { response, record: current, bodyText };
}

export async function shopifyAdminGraphql(
  supabase: SupabaseClient,
  record: ShopifyCredentialRecord,
  apiVersion: string,
  query: string,
  variables?: Record<string, unknown>,
): Promise<{
  body: Record<string, unknown>;
  record: ShopifyCredentialRecord;
  ok: boolean;
  status: number;
}> {
  const shopDomain = String(record.credentials.shop_domain || "");
  const { response, record: updatedRecord, bodyText } = await shopifyAdminFetch(
    supabase,
    record,
    `https://${shopDomain}/admin/api/${apiVersion}/graphql.json`,
    {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ query, variables }),
    },
  );
  let body: Record<string, unknown> = {};
  try {
    body = JSON.parse(bodyText) as Record<string, unknown>;
  } catch {
    body = { raw: bodyText };
  }
  return { body, record: updatedRecord, ok: response.ok, status: response.status };
}

export async function shopifyAdminRest(
  supabase: SupabaseClient,
  record: ShopifyCredentialRecord,
  apiVersion: string,
  path: string,
  init?: RequestInit,
): Promise<{ response: Response; record: ShopifyCredentialRecord; bodyText: string }> {
  const shopDomain = String(record.credentials.shop_domain || "");
  const normalizedPath = path.startsWith("/") ? path : `/${path}`;
  return await shopifyAdminFetch(
    supabase,
    record,
    `https://${shopDomain}/admin/api/${apiVersion}${normalizedPath}`,
    init,
  );
}
