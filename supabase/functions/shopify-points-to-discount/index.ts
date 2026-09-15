import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.38.4";
import { verify } from "https://deno.land/x/djwt@v2.8/mod.ts";
import { getMemberJwtSecret } from "../_shared/member-session.ts";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};
const REFRESH_WINDOW_MS = 5 * 60 * 1000;

interface JWTPayload { sub: string; user_id: string; merchant_id: string; shopify_customer_id: string; shop: string; [key: string]: unknown; }
interface RequestBody { points_amount: number; discount_amount: number; currency_code: string; }

function jsonResponse(data: unknown, status = 200) { return new Response(JSON.stringify(data), { status, headers: { ...corsHeaders, "Content-Type": "application/json" } }); }
function toIsoFromSeconds(seconds?: number): string | null { return !seconds || Number.isNaN(seconds) ? null : new Date(Date.now() + seconds * 1000).toISOString(); }
function isNearExpiry(credentials: Record<string, any>): boolean {
  if (credentials.token_mode !== "offline_expiring" || !credentials.refresh_token) return false;
  if (!credentials.expires_at) return true;
  const expiresAt = new Date(credentials.expires_at).getTime();
  return Number.isNaN(expiresAt) || expiresAt <= Date.now() + REFRESH_WINDOW_MS;
}

async function refreshShopifyToken(supabase: any, record: any) {
  const credentials = record.credentials || {};
  const shopDomain = credentials.shop_domain;
  const apiKey = credentials.api_key || Deno.env.get("SHOPIFY_API_KEY");
  const apiSecret = credentials.api_secret || Deno.env.get("SHOPIFY_API_SECRET");
  if (!shopDomain || !apiKey || !apiSecret || !credentials.refresh_token) throw new Error("Shopify credential requires admin reauth");

  const body = new URLSearchParams();
  body.set("client_id", apiKey);
  body.set("client_secret", apiSecret);
  body.set("grant_type", "refresh_token");
  body.set("refresh_token", credentials.refresh_token);
  const response = await fetch(`https://${shopDomain}/admin/oauth/access_token`, { method: "POST", headers: { "Content-Type": "application/x-www-form-urlencoded", "Accept": "application/json" }, body });
  const data = await response.json().catch(() => ({}));
  if (!response.ok || !data.access_token || !data.refresh_token) {
    const status = response.status === 400 || response.status === 401 ? "reauth_required" : "refresh_failed";
    await supabase.from("merchant_credentials").update({ credentials: { ...credentials, health_status: status, last_health_check: new Date().toISOString() }, health_status: status, last_health_check: new Date().toISOString(), updated_at: new Date().toISOString() }).eq("id", record.id);
    throw new Error(data.error_description || data.error || `Shopify token refresh failed (${response.status})`);
  }
  const expiresAt = toIsoFromSeconds(data.expires_in);
  const refreshTokenExpiresAt = toIsoFromSeconds(data.refresh_token_expires_in);
  const nextCredentials = { ...credentials, access_token: data.access_token, refresh_token: data.refresh_token, token_mode: "offline_expiring", scope: data.scope || credentials.scope || null, expires_at: expiresAt, refresh_token_expires_at: refreshTokenExpiresAt, health_status: "healthy", last_health_check: new Date().toISOString(), token_updated_at: new Date().toISOString() };
  await supabase.from("merchant_credentials").update({ credentials: nextCredentials, expires_at: expiresAt, health_status: "healthy", last_health_check: new Date().toISOString(), updated_at: new Date().toISOString() }).eq("id", record.id);
  return { ...record, credentials: nextCredentials };
}

async function getShopifyCredential(supabase: any, merchantId: string) {
  const { data, error } = await supabase.from("merchant_credentials").select("id, credentials").eq("merchant_id", merchantId).eq("service_name", "shopify_app").eq("is_active", true).single();
  if (error || !data) throw new Error("No active Shopify credentials found for this merchant");
  if (isNearExpiry(data.credentials || {})) return await refreshShopifyToken(supabase, data);
  return data;
}

async function shopifyGraphqlWithRefresh(supabase: any, record: any, query: string, variables: any) {
  let current = record;
  const call = () => fetch(`https://${current.credentials.shop_domain}/admin/api/2024-04/graphql.json`, { method: "POST", headers: { "X-Shopify-Access-Token": current.credentials.access_token, "Content-Type": "application/json" }, body: JSON.stringify({ query, variables }) });
  let response = await call();
  if (response.status === 401 && current.credentials?.token_mode === "offline_expiring" && current.credentials?.refresh_token) {
    current = await refreshShopifyToken(supabase, current);
    response = await call();
  }
  return { response, credential: current };
}

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") return new Response(null, { headers: corsHeaders });
  const supabase = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!);

  try {
    const authHeader = req.headers.get("Authorization");
    if (!authHeader?.startsWith("Bearer ")) return jsonResponse({ success: false, error: "Missing authorization" }, 401);

    const token = authHeader.replace("Bearer ", "");
    const secret = getMemberJwtSecret();
    if (!secret) return jsonResponse({ success: false, error: "JWT secret not configured" }, 500);
    const key = await crypto.subtle.importKey("raw", new TextEncoder().encode(secret), { name: "HMAC", hash: "SHA-256" }, false, ["verify"]);
    let payload: JWTPayload;
    try { payload = (await verify(token, key)) as unknown as JWTPayload; } catch { return jsonResponse({ success: false, error: "Invalid or expired token" }, 401); }

    const userId = payload.user_id || payload.sub;
    const merchantId = payload.merchant_id;
    const shopifyCustomerId = payload.shopify_customer_id;
    if (!userId || !merchantId || !shopifyCustomerId) return jsonResponse({ success: false, error: "Token missing required claims (user_id, merchant_id, shopify_customer_id)" }, 401);

    const body: RequestBody = await req.json();
    const { points_amount, discount_amount, currency_code } = body;
    if (!points_amount || points_amount <= 0) return jsonResponse({ success: false, error: "points_amount must be a positive number" }, 400);
    if (!discount_amount || discount_amount <= 0) return jsonResponse({ success: false, error: "discount_amount must be a positive number" }, 400);
    if (!currency_code) return jsonResponse({ success: false, error: "currency_code is required" }, 400);

    const { data: wallet, error: walletError } = await supabase.from("user_wallet").select("points_balance").eq("user_id", userId).eq("merchant_id", merchantId).maybeSingle();
    if (walletError) return jsonResponse({ success: false, error: "Failed to check points balance" }, 500);
    const balanceBefore = wallet?.points_balance || 0;
    if (balanceBefore < points_amount) return jsonResponse({ success: false, error: "Insufficient points", points_burn: { success: false, balance_before: balanceBefore, points_requested: points_amount, shortage: points_amount - balanceBefore }, shopify_metafield: { success: false, error: "Not attempted - insufficient points" } }, 400);

    const transactionId = crypto.randomUUID();
    const { data: burnResult, error: burnError } = await supabase.rpc("chokepoint_post_wallet_transaction", { p_user_id: userId, p_currency: "points", p_source_type: "reward_redemption", p_component: "base", p_transaction_type: "burn", p_amount: points_amount, p_transaction_id: transactionId, p_merchant_id: merchantId, p_description: `Points to Shopify discount: ${discount_amount} ${currency_code}`, p_metadata: { type: "shopify_points_to_discount", discount_amount, currency_code, shopify_customer_id: shopifyCustomerId } });
    if (burnError) return jsonResponse({ success: false, error: "Failed to deduct points", points_burn: { success: false, error: burnError.message, balance_before: balanceBefore }, shopify_metafield: { success: false, error: "Not attempted - points burn failed" } }, 500);

    let credRecord;
    try { credRecord = await getShopifyCredential(supabase, merchantId); } catch (err: any) {
      await reversePointsBurn(supabase, userId, merchantId, points_amount, transactionId);
      return jsonResponse({ success: false, error: "Shopify credentials not found, points refunded", points_burn: { success: true, reversed: true, reason: err.message, transaction_id: transactionId, ledger_id: burnResult, points_burned: points_amount, balance_before: balanceBefore, balance_after: balanceBefore }, shopify_metafield: { success: false, error: err.message } }, 500);
    }

    const expiresAt = new Date(Date.now() + 24 * 60 * 60 * 1000).toISOString();
    const entitlement = { intent_id: transactionId, amount: discount_amount, currency: currency_code, status: "active", expires_at: expiresAt, points_burned: points_amount };
    const graphqlQuery = `mutation customerMetafieldUpdate($input: CustomerInput!) { customerUpdate(input: $input) { customer { id metafield(namespace: "loyalty", key: "discount_entitlement") { id value } } userErrors { field message } } }`;
    const graphqlVariables = { input: { id: `gid://shopify/Customer/${shopifyCustomerId}`, metafields: [{ namespace: "loyalty", key: "discount_entitlement", type: "json", value: JSON.stringify(entitlement) }] } };

    const { response: shopifyResponse, credential } = await shopifyGraphqlWithRefresh(supabase, credRecord, graphqlQuery, graphqlVariables);
    const shopifyBody = await shopifyResponse.json().catch(() => ({}));
    const userErrors = shopifyBody?.data?.customerUpdate?.userErrors;
    const shopifyCustomer = shopifyBody?.data?.customerUpdate?.customer;
    const writtenMetafield = shopifyCustomer?.metafield;

    if (!shopifyResponse.ok || shopifyBody.errors || (userErrors && userErrors.length > 0)) {
      const errorDetail = shopifyBody.errors || userErrors || shopifyBody;
      await reversePointsBurn(supabase, userId, merchantId, points_amount, transactionId);
      return jsonResponse({ success: false, error: "Failed to create Shopify discount entitlement, points refunded", points_burn: { success: true, reversed: true, reason: "Shopify metafield write failed", transaction_id: transactionId, ledger_id: burnResult, points_burned: points_amount, balance_before: balanceBefore, balance_after: balanceBefore }, shopify_metafield: { success: false, error: errorDetail, shopify_customer_id: shopifyCustomerId, shop_domain: credential.credentials.shop_domain } }, 502);
    }

    return jsonResponse({ success: true, message: `${discount_amount} ${currency_code} discount applied. Refresh your cart to see it.`, points_burn: { success: true, reversed: false, transaction_id: transactionId, ledger_id: burnResult, points_burned: points_amount, balance_before: balanceBefore, balance_after: balanceBefore - points_amount }, shopify_metafield: { success: true, shopify_customer_id: shopifyCustomerId, shop_domain: credential.credentials.shop_domain, metafield_id: writtenMetafield?.id || null, entitlement } });
  } catch (error: any) {
    console.error("[shopify-points-to-discount] Unexpected error:", error);
    return jsonResponse({ success: false, error: error.message || "Unexpected error" }, 500);
  }
});

async function reversePointsBurn(supabase: any, userId: string, merchantId: string, pointsAmount: number, originalTransactionId: string): Promise<void> {
  try {
    const { error } = await supabase.rpc("chokepoint_post_wallet_transaction", { p_user_id: userId, p_currency: "points", p_source_type: "redemption_cancellation", p_component: "base", p_transaction_type: "earn", p_amount: pointsAmount, p_transaction_id: crypto.randomUUID(), p_merchant_id: merchantId, p_description: "Refund: Shopify discount entitlement failed", p_metadata: { type: "shopify_points_to_discount_reversal", original_transaction_id: originalTransactionId } });
    if (error) console.error("[shopify-points-to-discount] CRITICAL: Failed to reverse points burn:", error);
  } catch (err: any) {
    console.error("[shopify-points-to-discount] CRITICAL: Exception reversing points:", err);
  }
}
