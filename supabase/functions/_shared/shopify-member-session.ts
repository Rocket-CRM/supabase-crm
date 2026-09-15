import { verify } from 'https://deno.land/x/djwt@v2.8/mod.ts';
import { issueMemberSession } from './member-session.ts';
import {
  ensureFreshShopifyCredential,
  refreshShopifyTokenCas,
  shopifyAdminRest,
  type ShopifyCredentialRecord,
} from './shopify-admin-client.ts';

export const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
  'Access-Control-Allow-Methods': 'GET, POST, OPTIONS',
};

export const SHOPIFY_API_VERSION = '2024-04';

export type MerchantConfig = {
  merchant_id: string;
  merchant_code: string | null;
  credential_record: any;
};

export function jsonResponse(data: unknown, status = 200, extraHeaders?: Record<string, string>) {
  return new Response(JSON.stringify(data), {
    status,
    headers: { ...corsHeaders, 'Content-Type': 'application/json', ...extraHeaders },
  });
}

function toCredentialRecord(credRecord: any): ShopifyCredentialRecord {
  return {
    id: credRecord.id,
    merchant_id: credRecord.merchant_id,
    credentials: credRecord.credentials || {},
  };
}

export async function refreshShopifyToken(supabase: any, credRecord: any) {
  const refreshed = await refreshShopifyTokenCas(supabase, toCredentialRecord(credRecord));
  return { ...credRecord, ...refreshed };
}

export async function ensureValidShopifyCredentials(supabase: any, credRecord: any) {
  const fresh = await ensureFreshShopifyCredential(supabase, toCredentialRecord(credRecord));
  return { ...credRecord, ...fresh };
}

export async function fetchShopifyCustomer(shop: string, customerId: string, accessToken: string) {
  const url = `https://${shop}/admin/api/${SHOPIFY_API_VERSION}/customers/${customerId}.json`;
  const response = await fetch(url, {
    headers: { 'X-Shopify-Access-Token': accessToken, 'Content-Type': 'application/json' },
  });
  if (!response.ok) {
    const errorText = await response.text();
    const error: any = new Error(`Shopify API error: ${response.status}`);
    error.status = response.status;
    error.body = errorText;
    throw error;
  }
  const data = await response.json();
  return data.customer;
}

export function shopHostFromDest(dest: string | undefined | null): string | null {
  if (!dest) return null;
  try {
    const host = dest.includes('://') ? new URL(dest).hostname : dest;
    return host.replace(/^www\./, '').toLowerCase();
  } catch {
    return dest.replace(/^https?:\/\//, '').split('/')[0]?.toLowerCase() || null;
  }
}

export async function getMerchantByShop(supabase: any, shopDomain: string): Promise<MerchantConfig | null> {
  const host = shopHostFromDest(shopDomain);
  if (!host) return null;
  const { data: credData } = await supabase
    .from('merchant_credentials')
    .select('id, merchant_id, credentials')
    .eq('service_name', 'shopify_app')
    .eq('is_active', true);
  if (!credData || credData.length === 0) return null;
  const match = credData.find((cred: any) => shopHostFromDest(cred.credentials?.shop_domain) === host);
  if (!match) return null;
  const { data: merchant } = await supabase.from('merchant_master').select('id, merchant_code').eq('id', match.merchant_id).single();
  return { merchant_id: match.merchant_id, merchant_code: merchant?.merchant_code, credential_record: match };
}

export async function findOrCreateMember(supabase: any, merchantId: string, customer: any) {
  const shopifyId = customer?.id != null ? String(customer.id) : null;
  if (!shopifyId) throw new Error('Shopify customer id missing');

  const { data, error } = await supabase.rpc('shopify_find_or_create_member', {
    p_merchant_id: merchantId,
    p_shopify_customer_id: shopifyId,
    p_email: customer.email ?? null,
    p_phone: customer.phone ?? null,
    p_firstname: customer.first_name ?? null,
    p_lastname: customer.last_name ?? null,
  });
  if (error) throw error;

  const result = data as {
    success?: boolean;
    action?: string;
    error_message?: string;
    user?: Record<string, unknown>;
  };

  if (!result?.success) {
    throw new Error(result?.error_message || 'shopify_find_or_create_member failed');
  }
  if (result.action === 'skipped_no_email_cannot_match') {
    const err: any = new Error('Cannot create loyalty member without email');
    err.code = 'MEMBER_UNAVAILABLE';
    throw err;
  }
  if (!result.user) {
    throw new Error('shopify_find_or_create_member returned no user');
  }
  return result.user;
}

export async function mintShopifyMemberSessionToken(
  dbUser: Record<string, unknown>,
  merchantId: string,
  shopifyCustomerId: string,
): Promise<string> {
  const { access_token } = await issueMemberSession({
    userAccount: {
      id: String(dbUser.id),
      tel: (dbUser.tel as string | null | undefined) ?? null,
      line_id: (dbUser.line_id as string | null | undefined) ?? null,
      email: (dbUser.email as string | null | undefined) ?? null,
    },
    merchantId,
    channel: 'shopify',
    shopifyCustomerId,
  });
  return access_token;
}

export function customerNumericId(sub: string | undefined | null): string | null {
  if (!sub) return null;
  const match = String(sub).match(/gid:\/\/shopify\/Customer\/(\d+)/i);
  if (match) return match[1];
  if (/^\d+$/.test(String(sub))) return String(sub);
  return null;
}

export async function verifyShopifySessionToken(token: string, apiSecret: string, apiKey: string, expectedShop: string) {
  const key = await crypto.subtle.importKey(
    'raw',
    new TextEncoder().encode(apiSecret),
    { name: 'HMAC', hash: 'SHA-256' },
    false,
    ['verify'],
  );
  const payload = await verify(token, key) as Record<string, unknown>;
  const exp = Number(payload.exp || 0);
  if (!exp || exp * 1000 <= Date.now()) {
    const err: any = new Error('Token expired');
    err.code = 'INVALID_TOKEN';
    throw err;
  }
  if (String(payload.aud || '') !== String(apiKey)) {
    const err: any = new Error('Token audience mismatch');
    err.code = 'INVALID_TOKEN';
    throw err;
  }
  const destHost = shopHostFromDest(String(payload.dest || ''));
  if (!destHost || destHost !== shopHostFromDest(expectedShop)) {
    const err: any = new Error('Token destination mismatch');
    err.code = 'INVALID_TOKEN';
    throw err;
  }
  return payload;
}

export async function resolveMemberFromCustomerId(
  supabase: any,
  merchant: MerchantConfig,
  customerId: string,
) {
  let credentialRecord = await ensureValidShopifyCredentials(supabase, merchant.credential_record);
  const shop = credentialRecord.credentials?.shop_domain;
  const { response, bodyText, record: updatedRecord } = await shopifyAdminRest(
    supabase,
    toCredentialRecord(credentialRecord),
    SHOPIFY_API_VERSION,
    `/customers/${customerId}.json`,
  );
  credentialRecord = { ...credentialRecord, ...updatedRecord };
  if (!response.ok) {
    const error: any = new Error(`Shopify API error: ${response.status}`);
    error.status = response.status;
    error.body = bodyText;
    throw error;
  }
  const payload = JSON.parse(bodyText) as { customer?: Record<string, unknown> };
  const customer = payload.customer;
  if (!customer) {
    throw new Error('Shopify customer not found');
  }

  const { data: existingId } = await supabase.rpc('shopify_find_user_by_customer_id', {
    p_merchant_id: merchant.merchant_id,
    p_shopify_customer_id: String(customerId),
  });
  let dbUser: Record<string, unknown>;
  if (existingId) {
    const { data: row } = await supabase.from('user_accounts').select('*').eq('id', existingId).maybeSingle();
    dbUser = row || await findOrCreateMember(supabase, merchant.merchant_id, customer);
  } else {
    dbUser = await findOrCreateMember(supabase, merchant.merchant_id, customer);
  }
  const jwt = await mintShopifyMemberSessionToken(dbUser, merchant.merchant_id, String(customerId));
  return { dbUser, customer, jwt, shop };
}
