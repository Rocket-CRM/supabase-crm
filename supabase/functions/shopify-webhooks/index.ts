import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.38.4";
import { handleComplianceWebhook, isComplianceTopic } from "./compliance.ts";
import { handleCustomerWebhook, isCustomerTopic } from "./customers.ts";
import { handleProductWebhook, isProductTopic } from "./products.ts";

const supabase = createClient(
  Deno.env.get("SUPABASE_URL")!,
  Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
);

const ORDER_TOPICS = new Set([
  "orders/create",
  "orders/paid",
  "orders/fulfilled",
  "orders/cancelled",
  "orders/updated",
]);

const REFUND_TOPICS = new Set(["refunds/create"]);

const REFRESH_WINDOW_MS = 5 * 60 * 1000;
const LOYALTY_INTENT_KEYS = ["_loyalty_intent_id", "loyalty_intent_id", "loyalty_intent_id__"];
const LOYALTY_INTENT_CANONICAL_KEY = LOYALTY_INTENT_KEYS[0];
const LOYALTY_DISCOUNT_TITLE = "Loyalty Redemption";
const LOYALTY_METAFIELD_NAMESPACE = "loyalty";
const LOYALTY_METAFIELD_KEY = "discount_entitlement";
const PAID_FINANCIAL_STATUSES = new Set(["paid", "partially_paid", "authorized"]);
const DEBUG_LOG_KEY = "_debug_consume_log";
const DEBUG_LOG_LIMIT = 8;
const SHOPIFY_PURCHASE_TX_PREFIX = "MKP-SHOPIFY-";

function json(data: unknown, status = 200) {
  return new Response(JSON.stringify(data), { status, headers: { "Content-Type": "application/json" } });
}

async function verifyHmac(rawBody: string, hmacHeader: string | null, secret: string): Promise<boolean> {
  if (!hmacHeader || !secret) return false;
  const key = await crypto.subtle.importKey("raw", new TextEncoder().encode(secret), { name: "HMAC", hash: "SHA-256" }, false, ["sign"]);
  const sig = await crypto.subtle.sign("HMAC", key, new TextEncoder().encode(rawBody));
  const computed = btoa(String.fromCharCode(...new Uint8Array(sig)));
  if (computed.length !== hmacHeader.length) return false;
  let diff = 0;
  for (let i = 0; i < computed.length; i++) diff |= computed.charCodeAt(i) ^ hmacHeader.charCodeAt(i);
  return diff === 0;
}

function num(v: unknown): number {
  if (v === null || v === undefined || v === "") return 0;
  const n = typeof v === "number" ? v : parseFloat(String(v));
  return Number.isFinite(n) ? n : 0;
}

function shopifyFulfillmentDelivered(order: Record<string, unknown>): boolean {
  const fulfillments = (order.fulfillments || []) as Array<Record<string, unknown>>;
  for (const f of fulfillments) {
    const ship = String(f.shipment_status || "").toLowerCase();
    if (ship === "delivered") return true;
  }
  return false;
}

function shopifyDeliveredAt(order: Record<string, unknown>): string | null {
  const fulfillments = (order.fulfillments || []) as Array<Record<string, unknown>>;
  let best: string | null = null;
  for (const f of fulfillments) {
    const ship = String(f.shipment_status || "").toLowerCase();
    const candidate =
      (f.delivered_at as string | undefined) ||
      (f.updated_at as string | undefined) ||
      (ship === "delivered" ? (f.created_at as string | undefined) : undefined);
    if (!candidate) continue;
    if (!best || candidate > best) best = candidate;
  }
  return best;
}

function shopifyMemberCompleted(order: Record<string, unknown>): boolean {
  const metafields = (order.metafields || []) as Array<Record<string, unknown>>;
  for (const mf of metafields) {
    const ns = String(mf.namespace || "");
    const key = String(mf.key || "");
    if (ns === "loyalty_store" && key === "member_received_at" && mf.value) return true;
  }
  return false;
}

/** Monotonic mkp order_status ladder for Shopify ingest. */
function deriveOrderStatus(order: Record<string, unknown>): string {
  if (order.cancelled_at) return "cancelled";
  const fin = String(order.financial_status || "").toLowerCase();
  const ful = String(order.fulfillment_status || "").toLowerCase();
  if (fin === "voided") return "cancelled";
  if (fin === "refunded") return "refunded";
  if (shopifyMemberCompleted(order)) return "completed";
  if (shopifyFulfillmentDelivered(order)) return "delivered";
  if (ful === "fulfilled") return "fulfilled";
  if (fin === "paid" || fin === "partially_refunded") return "paid";
  if (fin) return fin;
  return "pending";
}

function normalizeOrder(merchantId: string, shopDomain: string, order: Record<string, unknown>) {
  const customer = (order.customer || {}) as Record<string, unknown>;
  const shippingLines = (order.shipping_lines || []) as Array<Record<string, unknown>>;
  const lineItems = (order.line_items || []) as Array<Record<string, unknown>>;
  const shippingFee = shippingLines.reduce((s, l) => s + num(l.price), 0);
  const items = lineItems.map((li) => ({
    platform_item_id: String(li.id ?? li.product_id ?? ""),
    variant_id: li.variant_id != null ? String(li.variant_id) : null,
    platform_sku: li.sku || null,
    variant_sku: li.sku || null,
    item_name: li.title || li.name || null,
    variant_name: li.variant_title || null,
    quantity: num(li.quantity),
    currency: order.currency || "USD",
    unit_price: num(li.price),
    discount_amount: num(li.total_discount),
    line_total: num(li.price) * num(li.quantity) - num(li.total_discount),
  }));
  const customerId = customer.id;
  const firstName = customer.first_name;
  const lastName = customer.last_name;
  const paymentGateways = order.payment_gateway_names as string[] | undefined;
  return {
    merchant_id: merchantId,
    platform: "shopify",
    shop_id: shopDomain,
    order_sn: String(order.id),
    external_user_id: customerId != null ? String(customerId) : null,
    buyer_username: [firstName, lastName].filter(Boolean).join(" ") || null,
    buyer_phone: customer.phone || order.phone || null,
    buyer_email: customer.email || order.email || null,
    order_status: deriveOrderStatus(order),
    delivered_at: shopifyDeliveredAt(order),
    transaction_date: order.created_at || new Date().toISOString(),
    update_time: order.updated_at || new Date().toISOString(),
    currency: order.currency || "USD",
    total_amount: num(order.total_price),
    shipping_fee: shippingFee,
    discount_amount: num(order.total_discounts),
    tax_amount: num(order.total_tax),
    final_amount: num(order.total_price),
    payment_method: (paymentGateways || []).join(",") || null,
    payment_status: order.financial_status || null,
    discount_codes: ((order.discount_codes || []) as Array<Record<string, unknown>>)
      .map((d) => String(d.code || "").trim())
      .filter(Boolean),
    items,
  };
}

async function resolveMerchantByShop(shopDomain: string): Promise<{ credentialId: string; merchantId: string; apiSecret: string; credentials: Record<string, unknown> } | null> {
  const { data, error } = await supabase.from("merchant_credentials").select("id, merchant_id, credentials").eq("service_name", "shopify_app").eq("is_active", true).filter("credentials->>shop_domain", "eq", shopDomain).limit(1).maybeSingle();
  if (error) {
    console.error("[shopify-webhooks] resolveMerchantByShop error:", error);
    return null;
  }
  if (!data) return null;
  const credentials = (data.credentials || {}) as Record<string, unknown>;
  const apiSecret = String(credentials.api_secret || Deno.env.get("SHOPIFY_API_SECRET") || "");
  return { credentialId: data.id, merchantId: data.merchant_id, apiSecret, credentials };
}

function toIsoFromSeconds(seconds?: number): string | null {
  return !seconds || Number.isNaN(seconds) ? null : new Date(Date.now() + seconds * 1000).toISOString();
}

function isNearExpiry(credentials: Record<string, unknown>): boolean {
  if (credentials.token_mode !== "offline_expiring" || !credentials.refresh_token) return false;
  if (!credentials.expires_at) return true;
  const expiresAt = new Date(String(credentials.expires_at)).getTime();
  return Number.isNaN(expiresAt) || expiresAt <= Date.now() + REFRESH_WINDOW_MS;
}

async function refreshShopifyToken(credentialId: string, credentials: Record<string, unknown>): Promise<Record<string, unknown>> {
  const shopDomain = credentials.shop_domain;
  const apiKey = credentials.api_key || Deno.env.get("SHOPIFY_API_KEY");
  const apiSecret = credentials.api_secret || Deno.env.get("SHOPIFY_API_SECRET");
  if (!shopDomain || !apiKey || !apiSecret || !credentials.refresh_token) throw new Error("Shopify credential requires admin reauth");
  const body = new URLSearchParams();
  body.set("client_id", String(apiKey));
  body.set("client_secret", String(apiSecret));
  body.set("grant_type", "refresh_token");
  body.set("refresh_token", String(credentials.refresh_token));
  const response = await fetch(`https://${shopDomain}/admin/oauth/access_token`, { method: "POST", headers: { "Content-Type": "application/x-www-form-urlencoded", Accept: "application/json" }, body });
  const data = await response.json().catch(() => ({}));
  if (!response.ok || !data.access_token || !data.refresh_token) {
    const status = response.status === 400 || response.status === 401 ? "reauth_required" : "refresh_failed";
    await supabase.from("merchant_credentials").update({ credentials: { ...credentials, health_status: status, last_health_check: new Date().toISOString() }, health_status: status, last_health_check: new Date().toISOString(), updated_at: new Date().toISOString() }).eq("id", credentialId);
    throw new Error(data.error_description || data.error || `Shopify token refresh failed (${response.status})`);
  }
  const expiresAt = toIsoFromSeconds(data.expires_in);
  const refreshTokenExpiresAt = toIsoFromSeconds(data.refresh_token_expires_in);
  const next = { ...credentials, access_token: data.access_token, refresh_token: data.refresh_token, token_mode: "offline_expiring", scope: data.scope || credentials.scope || null, expires_at: expiresAt, refresh_token_expires_at: refreshTokenExpiresAt, health_status: "healthy", last_health_check: new Date().toISOString(), token_updated_at: new Date().toISOString() };
  await supabase.from("merchant_credentials").update({ credentials: next, expires_at: expiresAt, health_status: "healthy", last_health_check: new Date().toISOString(), updated_at: new Date().toISOString() }).eq("id", credentialId);
  return next;
}

async function shopifyGraphql(credentialId: string, credentialsIn: Record<string, unknown>, query: string, variables: Record<string, unknown>): Promise<{ body: Record<string, unknown>; credentials: Record<string, unknown>; ok: boolean; status: number }> {
  let credentials = isNearExpiry(credentialsIn) ? await refreshShopifyToken(credentialId, credentialsIn) : credentialsIn;
  const call = () => fetch(`https://${credentials.shop_domain}/admin/api/2024-04/graphql.json`, { method: "POST", headers: { "X-Shopify-Access-Token": String(credentials.access_token), "Content-Type": "application/json" }, body: JSON.stringify({ query, variables }) });
  let response = await call();
  if (response.status === 401 && credentials.token_mode === "offline_expiring" && credentials.refresh_token) {
    credentials = await refreshShopifyToken(credentialId, credentials);
    response = await call();
  }
  const body = await response.json().catch(() => ({}));
  return { body, credentials, ok: response.ok, status: response.status };
}

function extractIntentId(noteAttributes: Array<{ name?: string; value?: string }> | undefined): { intentId: string; usedKey: string } | null {
  if (!Array.isArray(noteAttributes)) return null;
  for (const key of LOYALTY_INTENT_KEYS) {
    const hit = noteAttributes.find((a) => a?.name === key);
    const v = hit?.value;
    if (v && /^[0-9a-f-]{36}$/i.test(v)) return { intentId: v, usedKey: key };
  }
  return null;
}

function findLoyaltyDiscountApplication(order: Record<string, unknown>): Record<string, unknown> | null {
  const apps = order.discount_applications;
  if (!Array.isArray(apps)) return null;
  const hit = apps.find((a) => String((a as Record<string, unknown>)?.title || "").trim().toLowerCase() === LOYALTY_DISCOUNT_TITLE.toLowerCase());
  return (hit as Record<string, unknown>) ?? null;
}

// Fixed-amount value of the applied loyalty discount, or null when the
// discount line is absent or not expressed as a fixed amount.
function getLoyaltyDiscountAmount(order: Record<string, unknown>): number | null {
  const app = findLoyaltyDiscountApplication(order);
  if (!app) return null;
  if (String(app.value_type || "").toLowerCase() !== "fixed_amount") return null;
  const amount = num(app.value);
  return amount > 0 ? amount : null;
}

async function consumeLoyaltyEntitlement(
  credentialId: string,
  credentialsIn: Record<string, unknown>,
  customerGid: string,
  orderIdStr: string,
  expectedIntentId: string | null,
  appliedDiscountAmount: number | null,
): Promise<Record<string, unknown>> {
  const readQuery = `query GetLoyaltyEntitlement($id: ID!) { customer(id: $id) { id metafield(namespace: "${LOYALTY_METAFIELD_NAMESPACE}", key: "${LOYALTY_METAFIELD_KEY}") { id value updatedAt } } }`;
  const read = await shopifyGraphql(credentialId, credentialsIn, readQuery, { id: customerGid });
  if (!read.ok || read.body?.errors) return { success: false, reason: "metafield_read_failed", raw_read: { status: read.status, body: read.body } };
  const mf = (read.body?.data as Record<string, unknown>)?.customer as Record<string, unknown> | undefined;
  const metafield = mf?.metafield as Record<string, unknown> | undefined;
  if (!metafield?.value) return { success: false, reason: "no_active_entitlement", raw_read: { status: read.status, customer: mf } };
  let parsed: Record<string, unknown>;
  try {
    parsed = JSON.parse(String(metafield.value));
  } catch {
    return { success: false, reason: "invalid_metafield_json", before: metafield.value };
  }
  if (parsed.status && parsed.status !== "active") return { success: true, reason: "already_consumed_or_inactive", before: parsed, intent_id: parsed.intent_id };
  if (expectedIntentId) {
    if (parsed.intent_id && parsed.intent_id !== expectedIntentId) return { success: false, reason: "intent_id_mismatch", before: parsed };
  } else {
    // Buy-Now fallback: Shopify strips cart attributes on "Buy it now"
    // (https://community.shopify.dev/t/-/1895), so the order carries no
    // intent_id. Match by customer (metafield is customer-scoped, one
    // entitlement per customer) + amount sanity check: the Function can apply
    // less than the entitlement (cart cheaper than discount) but never more.
    const entitlementAmount = num(parsed.amount);
    if (appliedDiscountAmount != null && entitlementAmount > 0 && appliedDiscountAmount > entitlementAmount + 0.01) {
      return { success: false, reason: "amount_mismatch", before: parsed, applied_amount: appliedDiscountAmount };
    }
  }

  const consumed = { ...parsed, status: "consumed", consumed_at: new Date().toISOString(), order_id: orderIdStr };
  const writeQuery = `mutation ConsumeLoyaltyEntitlement($input: CustomerInput!) { customerUpdate(input: $input) { customer { id metafield(namespace: "${LOYALTY_METAFIELD_NAMESPACE}", key: "${LOYALTY_METAFIELD_KEY}") { id value updatedAt } } userErrors { field message } } }`;
  const write = await shopifyGraphql(credentialId, read.credentials, writeQuery, { input: { id: customerGid, metafields: [{ namespace: LOYALTY_METAFIELD_NAMESPACE, key: LOYALTY_METAFIELD_KEY, type: "json", value: JSON.stringify(consumed) }] } });
  const customerUpdate = (write.body?.data as Record<string, unknown>)?.customerUpdate as Record<string, unknown> | undefined;
  const userErrors = customerUpdate?.userErrors as Array<Record<string, unknown>> | undefined;
  if (!write.ok || write.body?.errors || (userErrors && userErrors.length > 0)) return { success: false, reason: "metafield_write_failed", before: parsed, raw_write: { status: write.status, body: write.body } };
  return { success: true, matched_by: expectedIntentId ? "intent_id" : "customer_amount", before: parsed, after: consumed, intent_id: parsed.intent_id, raw_write: { status: write.status, written_metafield: (customerUpdate?.customer as Record<string, unknown>)?.metafield } };
}

async function markRewardCodesUsed(
  merchantId: string,
  codes: string[],
  orderSn: string | null,
): Promise<Record<string, unknown>> {
  if (!codes.length) return { skipped: true, reason: "no_discount_codes" };
  const { data, error } = await supabase.rpc("fn_mark_redemptions_used_from_discount_codes", {
    p_merchant_id: merchantId,
    p_codes: codes,
    p_order_sn: orderSn,
  });
  if (error) {
    console.error("[shopify-webhooks] mark-used rpc error:", error);
    return { success: false, reason: "mark_used_rpc_failed", error: error.message };
  }
  return (data ?? {}) as Record<string, unknown>;
}

async function writeDebug(credentialId: string, currentCredentials: Record<string, unknown>, entry: Record<string, unknown>): Promise<void> {
  try {
    const prev = Array.isArray(currentCredentials?.[DEBUG_LOG_KEY]) ? currentCredentials[DEBUG_LOG_KEY] as unknown[] : [];
    const next = [...prev, entry].slice(-DEBUG_LOG_LIMIT);
    const { data: latest } = await supabase.from("merchant_credentials").select("credentials").eq("id", credentialId).single();
    const merged = { ...((latest?.credentials || {}) as Record<string, unknown>), [DEBUG_LOG_KEY]: next };
    await supabase.from("merchant_credentials").update({ credentials: merged }).eq("id", credentialId);
  } catch (err) {
    console.error("[shopify-webhooks] writeDebug failed:", err);
  }
}

// Extract Shopify order id from a refunds/create payload.
// REST refunds carry top-level order_id; GraphQL refunds nest under refund.order.id (gid) or refund.order.id (numeric via admin REST hybrid).
function extractOrderIdFromRefund(payload: Record<string, unknown>): string | null {
  const directOrderId = payload.order_id;
  if (directOrderId != null && String(directOrderId) !== "") return String(directOrderId);
  const orderNode = payload.order as Record<string, unknown> | undefined;
  if (orderNode) {
    const orderIdFromNode = orderNode.id;
    if (orderIdFromNode != null) {
      const asStr = String(orderIdFromNode);
      // gid://shopify/Order/<id> -> strip prefix
      const gidMatch = asStr.match(/\d+$/);
      if (gidMatch) return gidMatch[0];
      return asStr;
    }
  }
  return null;
}

interface ReversalLookupRow {
  id: string;
  status: string;
  earn_currency: boolean | null;
  transaction_number: string | null;
}

async function handleRefundReversal(
  resolved: { credentialId: string; merchantId: string; credentials: Record<string, unknown> },
  payload: Record<string, unknown>,
): Promise<Record<string, unknown>> {
  const orderId = extractOrderIdFromRefund(payload);
  const refundId = payload.id != null ? String(payload.id) : null;

  if (!orderId) {
    return { reversed: false, reason: "no_order_id_in_refund", refund_id: refundId };
  }

  const transactionNumber = `${SHOPIFY_PURCHASE_TX_PREFIX}${orderId}`;
  const { data: purchaseRows, error: purchaseErr } = await supabase
    .from("purchase_ledger")
    .select("id, status, earn_currency, transaction_number")
    .eq("merchant_id", resolved.merchantId)
    .eq("transaction_number", transactionNumber)
    .order("created_at", { ascending: false })
    .limit(1);
  if (purchaseErr) {
    console.error("[shopify-webhooks] refund purchase_ledger lookup error:", purchaseErr);
    return { reversed: false, reason: "lookup_failed", error: purchaseErr.message, order_id: orderId };
  }
  const purchase = (purchaseRows?.[0] ?? null) as ReversalLookupRow | null;

  if (!purchase) {
    return { reversed: false, reason: "no_purchase_found", order_id: orderId, transaction_number: transactionNumber };
  }

  const statusLower = String(purchase.status || "").toLowerCase();
  if (statusLower === "cancelled" || statusLower === "refunded") {
    return { reversed: false, reason: "already_cancelled", order_id: orderId, purchase_id: purchase.id, status: purchase.status };
  }

  if (purchase.earn_currency === false) {
    return { reversed: false, reason: "no_currency_earned", order_id: orderId, purchase_id: purchase.id };
  }

  const reason = refundId ? `Shopify refund: ${refundId}` : `Shopify refund for order ${orderId}`;
  const { data: cancelResult, error: cancelErr } = await supabase.rpc("api_cancel_purchase", {
    p_merchant_id: resolved.merchantId,
    p_purchase_ids: [purchase.id],
    p_reason: reason,
    p_reverse_currency: true,
    p_reverse_mode: "best_effort",
  });

  if (cancelErr) {
    console.error("[shopify-webhooks] api_cancel_purchase error:", cancelErr);
    return { reversed: false, reason: "cancel_rpc_failed", error: cancelErr.message, order_id: orderId, purchase_id: purchase.id };
  }

  const envelope = (cancelResult ?? {}) as Record<string, unknown>;
  const envelopeData = (envelope.data ?? {}) as Record<string, unknown>;
  const errorCode = envelopeData.error_code as string | undefined;

  if (errorCode === "ALREADY_CANCELLED") {
    return { reversed: false, reason: "already_cancelled", order_id: orderId, purchase_id: purchase.id, raw: envelope };
  }

  if (envelope.success !== true) {
    console.error("[shopify-webhooks] api_cancel_purchase returned failure:", envelope);
    return { reversed: false, reason: "cancel_rpc_failed", order_id: orderId, purchase_id: purchase.id, raw: envelope };
  }

  const deltas = Array.isArray(envelopeData.currency_deltas) ? envelopeData.currency_deltas : [];
  const pointsReversed = deltas.reduce((acc: number, d: unknown) => {
    const row = d as Record<string, unknown>;
    return row?.currency === "points" ? acc + Number(row.applied ?? 0) : acc;
  }, 0);
  const unreversedAmount = Number(envelopeData.unreversed_amount ?? 0);

  return {
    reversed: true,
    order_id: orderId,
    refund_id: refundId,
    purchase_id: purchase.id,
    points_reversed: pointsReversed,
    unreversed_amount: unreversedAmount,
    raw: envelope,
  };
}

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") return new Response(null);
  if (req.method !== "POST") return json({ success: false, error: "method_not_allowed" }, 405);

  const shopDomain = req.headers.get("x-shopify-shop-domain") || "";
  const topic = req.headers.get("x-shopify-topic") || "";
  const hmacHeader = req.headers.get("x-shopify-hmac-sha256");
  const webhookId = req.headers.get("x-shopify-webhook-id") || null;

  let rawBody: string;
  try {
    rawBody = await req.text();
  } catch {
    return json({ success: false, error: "unreadable_body" }, 400);
  }
  if (!shopDomain || !topic || !hmacHeader) return json({ success: false, error: "missing_shopify_headers" }, 400);

  const resolved = await resolveMerchantByShop(shopDomain);
  const hmacSecret = resolved?.apiSecret || Deno.env.get("SHOPIFY_API_SECRET") || "";
  const valid = await verifyHmac(rawBody, hmacHeader, hmacSecret);
  if (!valid) {
    console.warn(`[shopify-webhooks] HMAC verify failed for shop ${shopDomain}, topic ${topic}`);
    return json({ success: false, error: "hmac_invalid" }, 401);
  }

  let payload: Record<string, unknown>;
  try {
    payload = JSON.parse(rawBody);
  } catch {
    return json({ success: false, error: "invalid_json" }, 400);
  }

  // ── Compliance + lifecycle webhooks ─────────────────────────────────────
  if (isComplianceTopic(topic)) {
    const result = await handleComplianceWebhook(supabase, topic, shopDomain, payload);
    if (!result.success) {
      return json({ error: result.error_message ?? "Processing failed" }, 500);
    }
    console.log("[shopify-webhooks] compliance processed:", topic, shopDomain);
    return json({ success: true, topic, shop: shopDomain, webhook_id: webhookId });
  }

  // ── Customer profile webhooks — keep sync (single RPC; Shopify retry on 500) ─
  if (isCustomerTopic(topic)) {
    const result = await handleCustomerWebhook(supabase, topic, shopDomain, payload);
    if (!result.success) {
      return json({ error: result.error_message ?? "Processing failed" }, 500);
    }
    console.log("[shopify-webhooks] customer processed:", topic, shopDomain, result.data ?? null);
    return json({ success: true, topic, shop: shopDomain, webhook_id: webhookId, result: result.data ?? null });
  }

  // ── Heavy topics: ack fast, finish in background (Partner Dashboard latency) ─
  // Orders / refunds / products can call RPCs + Shopify Admin API. Compliance
  // stays sync above so GDPR failures still get Shopify retries.
  const isHeavy =
    isProductTopic(topic) || REFUND_TOPICS.has(topic) || ORDER_TOPICS.has(topic);

  if (!isHeavy) {
    console.log("[shopify-webhooks] unhandled topic:", topic, shopDomain);
    return json({ success: true, topic, shop: shopDomain });
  }

  if (!resolved) {
    console.warn(`[shopify-webhooks] No merchant found for shop ${shopDomain}; rejecting ${topic}.`);
    return json({ success: false, error: "unknown_shop" }, 404);
  }

  const merchant = resolved;
  const work = (async () => {
    if (isProductTopic(topic)) {
      let productResult: { success: boolean; error_message?: string; data?: unknown };
      try {
        productResult = await handleProductWebhook(supabase, merchant.merchantId, payload);
      } catch (err) {
        console.error("[shopify-webhooks] product handler exception:", err);
        productResult = { success: false, error_message: (err as Error)?.message };
      }
      if (!productResult.success) {
        console.error("[shopify-webhooks] product failed (async):", productResult.error_message);
        return;
      }
      console.log("[shopify-webhooks] product processed:", topic, shopDomain, productResult.data ?? null);
      return;
    }

    // Refunds — docs/SHOPIFY_POINTS_REVERSAL.md
    if (REFUND_TOPICS.has(topic)) {
      let reversalResult: Record<string, unknown>;
      try {
        reversalResult = await handleRefundReversal(merchant, payload);
      } catch (err) {
        console.error("[shopify-webhooks] refund handler exception:", err);
        reversalResult = { reversed: false, reason: "handler_exception", message: (err as Error)?.message };
      }
      const debugEntry: Record<string, unknown> = {
        ts: new Date().toISOString(),
        topic,
        order_id: (payload.order_id as string | number | undefined)?.toString() ??
          (payload.order as Record<string, unknown>)?.id ?? null,
        refund_id: payload.id ?? null,
        reversal: reversalResult,
      };
      await writeDebug(merchant.credentialId, merchant.credentials, debugEntry);
      console.log(
        `[shopify-webhooks] ${topic} ${shopDomain} reversal=${
          reversalResult.reversed ? "ok" : `skip:${reversalResult.reason}`
        }`,
      );
      return;
    }

    // Orders
    const order = payload;
    let upsertResult: unknown = null;
    let matchedUserId: string | null = null;
    let claimResult: unknown = null;
    let normalized: ReturnType<typeof normalizeOrder> | null = null;

    try {
      normalized = normalizeOrder(merchant.merchantId, shopDomain, order);
      const { data: upsert, error: upsertErr } = await supabase.rpc("upsert_marketplace_order", {
        p_order: normalized,
      });
      if (upsertErr) {
        console.error("[shopify-webhooks] upsert error:", upsertErr);
        upsertResult = { success: false, error: "upsert_failed", detail: upsertErr.message };
      } else {
        upsertResult = upsert;
      }
      const { data: matched, error: matchErr } = await supabase.rpc("fn_match_marketplace_user", {
        p_merchant_id: merchant.merchantId,
        p_platform: "shopify",
        p_external_user_id: normalized.external_user_id,
        p_email: normalized.buyer_email,
        p_phone: normalized.buyer_phone,
      });
      if (matchErr) console.error("[shopify-webhooks] match error:", matchErr);
      matchedUserId = (matched as string | null) ?? null;
      if (matchedUserId) {
        const { data: claim, error: claimErr } = await supabase.rpc(
          "fn_claim_marketplace_order_service",
          {
            p_merchant_id: merchant.merchantId,
            p_platform: "shopify",
            p_order_sn: normalized.order_sn,
            p_user_id: matchedUserId,
            p_earn_currency: true,
          },
        );
        if (claimErr) {
          console.error("[shopify-webhooks] claim error:", claimErr);
          claimResult = { success: false, error: claimErr.message };
        } else claimResult = claim;
      }
    } catch (err) {
      console.error("[shopify-webhooks] capture path error:", err);
    }

    const finStatus = String(order?.financial_status || "").toLowerCase();
    const paidLike = PAID_FINANCIAL_STATUSES.has(finStatus);
    const isCancelled = !!order?.cancelled_at || finStatus === "voided" || finStatus === "refunded";
    const intent = extractIntentId(
      order?.note_attributes as Array<{ name?: string; value?: string }> | undefined,
    );
    const hasLoyaltyLine = findLoyaltyDiscountApplication(order) != null;
    const appliedLoyaltyAmount = getLoyaltyDiscountAmount(order);
    const customer = order?.customer as Record<string, unknown> | undefined;
    const customerGid: string | null =
      (customer?.admin_graphql_api_id as string) ||
      (customer?.id != null ? `gid://shopify/Customer/${customer.id}` : null);

    const debugEntry: Record<string, unknown> = {
      ts: new Date().toISOString(),
      topic,
      order_sn: normalized?.order_sn,
      financial_status: order?.financial_status,
      paid_like: paidLike,
      is_cancelled: isCancelled,
      customer_id: customer?.id ?? null,
      note_attributes: order?.note_attributes ?? null,
      discount_titles: Array.isArray(order?.discount_applications)
        ? order.discount_applications.map((a: Record<string, unknown>) => a?.title)
        : null,
      intent_extracted: intent,
      has_loyalty_line: hasLoyaltyLine,
      applied_loyalty_amount: appliedLoyaltyAmount,
      customer_gid: customerGid,
      upsert: upsertResult,
      claim: claimResult,
    };

    let consumeResult: Record<string, unknown> | null = null;
    if (isCancelled) {
      consumeResult = {
        skipped: true,
        reason: `order_cancelled_or_refunded:${finStatus || "cancelled_at"}`,
      };
    } else if (!paidLike) {
      consumeResult = { skipped: true, reason: `not_paid_yet:${finStatus || "unknown"}` };
    } else if (!hasLoyaltyLine) {
      consumeResult = { skipped: true, reason: "no_loyalty_discount_line" };
    } else if (!customerGid) {
      consumeResult = { skipped: true, reason: "no_customer" };
    } else if (!intent) {
      console.warn(
        "[shopify-webhooks] paid order with Loyalty Redemption but no intent_id — consuming via customer+amount fallback (Buy Now)",
        {
          shop: shopDomain,
          order_sn: String(order.id),
          customer_gid: customerGid,
          applied_amount: appliedLoyaltyAmount,
        },
      );
      try {
        const r = await consumeLoyaltyEntitlement(
          merchant.credentialId,
          merchant.credentials,
          customerGid,
          String(order.id),
          null,
          appliedLoyaltyAmount,
        );
        consumeResult = {
          ...r,
          matched_by: r.matched_by ?? "customer_amount",
          applied_amount: appliedLoyaltyAmount,
        };
      } catch (err) {
        console.error("[shopify-webhooks] fallback consume error:", err);
        consumeResult = {
          success: false,
          reason: "consume_exception",
          message: (err as Error)?.message,
        };
      }
    } else {
      if (intent.usedKey !== LOYALTY_INTENT_CANONICAL_KEY) {
        console.warn("[shopify-webhooks] non-canonical intent attribute key", {
          shop: shopDomain,
          order_sn: String(order.id),
          intent_id: intent.intentId,
          used_key: intent.usedKey,
        });
      }
      try {
        const r = await consumeLoyaltyEntitlement(
          merchant.credentialId,
          merchant.credentials,
          customerGid,
          String(order.id),
          intent.intentId,
          appliedLoyaltyAmount,
        );
        consumeResult = { ...r, used_key: intent.usedKey };
      } catch (err) {
        console.error("[shopify-webhooks] consume error:", err);
        consumeResult = {
          success: false,
          reason: "consume_exception",
          message: (err as Error)?.message,
        };
      }
    }
    debugEntry.consume = consumeResult;

    let markUsedResult: Record<string, unknown> | null = null;
    const orderCodes = normalized?.discount_codes ?? [];
    if (isCancelled) {
      markUsedResult = {
        skipped: true,
        reason: `order_cancelled_or_refunded:${finStatus || "cancelled_at"}`,
      };
    } else if (!paidLike) {
      markUsedResult = { skipped: true, reason: `not_paid_yet:${finStatus || "unknown"}` };
    } else if (!orderCodes.length) {
      markUsedResult = { skipped: true, reason: "no_discount_codes" };
    } else {
      try {
        markUsedResult = await markRewardCodesUsed(
          merchant.merchantId,
          orderCodes,
          normalized?.order_sn ?? String(order.id),
        );
      } catch (err) {
        console.error("[shopify-webhooks] mark-used error:", err);
        markUsedResult = {
          success: false,
          reason: "mark_used_exception",
          message: (err as Error)?.message,
        };
      }
    }
    debugEntry.mark_used = markUsedResult;

    await writeDebug(merchant.credentialId, merchant.credentials, debugEntry);

    const markUsedSummary = !markUsedResult
      ? "n/a"
      : markUsedResult.skipped
        ? `skip:${markUsedResult.reason}`
        : markUsedResult.success === false
          ? `fail:${markUsedResult.reason}`
          : "ok";
    console.log(
      `[shopify-webhooks] ${topic} ${shopDomain} order ${normalized?.order_sn} status=${normalized?.order_status} fin=${finStatus} matched=${
        matchedUserId ?? "none"
      } claim=${(claimResult as Record<string, unknown>)?.code ?? "skipped"} consume=${
        consumeResult
          ? consumeResult.success
            ? "ok"
            : consumeResult.skipped
            ? `skip:${consumeResult.reason}`
            : `fail:${consumeResult.reason}`
          : "n/a"
      } mark_used=${markUsedSummary}`,
    );
  })().catch((err) => {
    console.error("[shopify-webhooks] background work failed:", topic, shopDomain, err);
  });

  // Ack Shopify immediately; keep the isolate alive until heavy work finishes.
  const edgeRuntime = (globalThis as unknown as {
    EdgeRuntime?: { waitUntil: (promise: Promise<unknown>) => void };
  }).EdgeRuntime;
  if (edgeRuntime?.waitUntil) {
    edgeRuntime.waitUntil(work);
  } else {
    // Local / unexpected runtime without waitUntil — finish before responding.
    await work;
  }

  return json({
    success: true,
    accepted: true,
    topic,
    shop: shopDomain,
    webhook_id: webhookId,
  });
});
