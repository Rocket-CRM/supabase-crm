import type { NormalizedOrder, PlatformCredentials } from "./types.ts";

function bytesToHex(bytes: Uint8Array): string {
  return Array.from(bytes).map((b) => b.toString(16).padStart(2, "0")).join("").toUpperCase();
}

async function signLazada(path: string, params: Record<string, string>, appSecret: string): Promise<string> {
  const sorted = Object.keys(params).sort().map((k) => `${k}${params[k]}`).join("");
  const stringToSign = `${path}${sorted}`;
  const encoder = new TextEncoder();
  const key = await crypto.subtle.importKey(
    "raw",
    encoder.encode(appSecret),
    { name: "HMAC", hash: "SHA-256" },
    false,
    ["sign"],
  );
  const signature = await crypto.subtle.sign("HMAC", key, encoder.encode(stringToSign));
  return bytesToHex(new Uint8Array(signature));
}

const LAZADA_DETAIL_CONCURRENCY = 5;
const LAZADA_DETAIL_STAGGER_MS = 150;

function sleep(ms: number): Promise<void> {
  return new Promise((r) => setTimeout(r, ms));
}

function isLazadaRateLimit(code: unknown, message: unknown, httpStatus?: number): boolean {
  if (httpStatus === 429) return true;
  const msg = String(message ?? "").toLowerCase();
  const c = String(code ?? "").toLowerCase();
  return msg.includes("rate") || msg.includes("frequency") || msg.includes("throttl")
    || msg.includes("too many") || c.includes("limit") || c === "901";
}

function assertLazadaOk(data: Record<string, unknown>, context: string): void {
  if (data.code === "0" || data.code === 0) return;
  if (isLazadaRateLimit(data.code, data.message)) {
    throw new Error(`Lazada rate limit ${context}: ${data.code} ${data.message}`);
  }
  throw new Error(`Lazada ${context}: ${data.code} ${data.message}`);
}

async function lazadaGet(
  path: string,
  extra: Record<string, string>,
  appKey: string,
  appSecret: string,
  accessToken: string,
): Promise<Record<string, unknown>> {
  const timestamp = Date.now().toString();
  const params: Record<string, string> = {
    app_key: appKey,
    sign_method: "sha256",
    timestamp,
    access_token: accessToken,
    ...extra,
  };
  params.sign = await signLazada(path, params, appSecret);
  const url = `https://api.lazada.co.th/rest${path}?${new URLSearchParams(params)}`;
  const response = await fetch(url, { method: "GET" });
  const bodyText = await response.text();
  if (response.status === 429) {
    throw new Error(`Lazada rate limit HTTP 429 ${path}: ${bodyText.slice(0, 300)}`);
  }
  if (!response.ok) throw new Error(`Lazada HTTP ${response.status}: ${bodyText.slice(0, 300)}`);
  const data = JSON.parse(bodyText) as Record<string, unknown>;
  if (isLazadaRateLimit(data.code, data.message)) {
    throw new Error(`Lazada rate limit ${path}: ${data.code} ${data.message}`);
  }
  return data;
}

function lazadaApp(creds: PlatformCredentials): { appKey: string; appSecret: string } {
  const appKey = creds.app_key || Deno.env.get("LAZADA_APP_KEY") || "";
  const appSecret = Deno.env.get("LAZADA_APP_SECRET") || creds.app_secret || "";
  if (!appKey || !appSecret) throw new Error("Lazada app_key / LAZADA_APP_SECRET not configured");
  return { appKey, appSecret };
}

/** ISO8601 for Lazada CreatedAfter/CreatedBefore */
function toLazadaIso(unixSec: number): string {
  return new Date(unixSec * 1000).toISOString().replace(/\.\d{3}Z$/, "+0000");
}

export async function listLazadaOrders(
  creds: PlatformCredentials,
  opts: { created_after_unix: number; created_before_unix: number; offset?: number; limit?: number },
): Promise<{ order_ids: string[]; offset: number; count: number; raw: unknown }> {
  const { appKey, appSecret } = lazadaApp(creds);
  const limit = Math.min(opts.limit ?? 100, 100);
  const offset = opts.offset ?? 0;
  const data = await lazadaGet(
    "/orders/get",
    {
      created_after: toLazadaIso(opts.created_after_unix),
      created_before: toLazadaIso(opts.created_before_unix),
      offset: String(offset),
      limit: String(limit),
      sort_by: "created_at",
      sort_direction: "ASC",
    },
    appKey,
    appSecret,
    creds.access_token,
  );
  if (data.code !== "0" && data.code !== 0) {
    throw new Error(`Lazada list error: ${data.code} - ${data.message}`);
  }
  const payload = data.data as { orders?: Array<{ order_id?: string | number }>; count?: number } | undefined;
  const orders = payload?.orders ?? [];
  return {
    order_ids: orders.map((o) => String(o.order_id ?? "")).filter(Boolean),
    offset,
    count: Number(payload?.count ?? orders.length),
    raw: data,
  };
}

async function fetchLazadaOrderDetail(
  orderId: string,
  appKey: string,
  appSecret: string,
  accessToken: string,
): Promise<Record<string, unknown>> {
  const orderRes = await lazadaGet("/order/get", { order_id: orderId }, appKey, appSecret, accessToken);
  assertLazadaOk(orderRes, `order/get ${orderId}`);
  const itemsRes = await lazadaGet("/order/items/get", { order_id: orderId }, appKey, appSecret, accessToken);
  const items = (itemsRes.code === "0" || itemsRes.code === 0) ? (itemsRes.data ?? []) : [];
  return { ...(orderRes.data as object), items };
}

async function mapWithConcurrency<T, R>(
  items: T[],
  concurrency: number,
  staggerMs: number,
  fn: (item: T) => Promise<R>,
): Promise<R[]> {
  if (items.length === 0) return [];
  const results: R[] = new Array(items.length);
  let nextIndex = 0;
  async function worker(workerId: number): Promise<void> {
    if (workerId > 0 && staggerMs > 0) await sleep(workerId * staggerMs);
    while (true) {
      const i = nextIndex++;
      if (i >= items.length) break;
      results[i] = await fn(items[i]);
    }
  }
  await Promise.all(
    Array.from({ length: Math.min(concurrency, items.length) }, (_, w) => worker(w)),
  );
  return results;
}

export async function getLazadaOrderDetails(
  creds: PlatformCredentials,
  orderIds: string[],
): Promise<Record<string, unknown>[]> {
  const { appKey, appSecret } = lazadaApp(creds);
  return mapWithConcurrency(
    orderIds,
    LAZADA_DETAIL_CONCURRENCY,
    LAZADA_DETAIL_STAGGER_MS,
    (orderId) => fetchLazadaOrderDetail(orderId, appKey, appSecret, creds.access_token),
  );
}

export function normalizeLazadaOrder(
  lazadaOrder: Record<string, unknown>,
  creds: PlatformCredentials,
): NormalizedOrder {
  const rawItems = (lazadaOrder.items as Record<string, unknown>[] | undefined) ?? [];
  const items = rawItems.map((item) => ({
    platform_item_id: item.order_item_id != null ? String(item.order_item_id) : "",
    variant_id: item.sku_id != null ? String(item.sku_id) : (item.sku != null ? String(item.sku) : null),
    platform_sku: (item.shop_sku ?? item.sku) != null ? String(item.shop_sku ?? item.sku) : null,
    item_name: String(item.name ?? ""),
    variant_name: item.variation != null ? String(item.variation) : null,
    quantity: parseInt(String(item.quantity || "1"), 10) || 1,
    currency: String(item.currency ?? lazadaOrder.currency ?? "THB"),
    unit_price: parseFloat(String(item.item_price || 0)),
    discount_amount: parseFloat(String(item.voucher_amount ?? item.discount_amount ?? 0)),
    line_total: parseFloat(String(item.paid_price || 0)),
  }));
  const itemsTotal = items.reduce((sum, item) => sum + item.line_total, 0);
  const shippingFee = parseFloat(String(lazadaOrder.shipping_fee || 0));
  const statusCandidates = [
    ...(Array.isArray(lazadaOrder.statuses) ? (lazadaOrder.statuses as unknown[]).map((s) => String(s || "").toLowerCase()) : []),
    lazadaOrder.status != null ? String(lazadaOrder.status).toLowerCase() : "",
    ...rawItems.map((item) => item.status != null ? String(item.status).toLowerCase() : ""),
  ].filter(Boolean);
  const lazadaSeq = ["unpaid", "pending", "confirmed", "packed", "ready_to_ship", "shipped", "delivered"];
  const status = statusCandidates.reduce((best, s) => {
    const rb = lazadaSeq.indexOf(s);
    const ra = lazadaSeq.indexOf(best);
    return rb > ra ? s : best;
  }, statusCandidates[0] || "unknown");
  const billing = lazadaOrder.address_billing as Record<string, unknown> | undefined;
  const shipping = lazadaOrder.address_shipping as Record<string, unknown> | undefined;
  const createdAt = lazadaOrder.created_at
    ? new Date(String(lazadaOrder.created_at)).toISOString()
    : new Date().toISOString();
  const updatedAt = lazadaOrder.updated_at
    ? new Date(String(lazadaOrder.updated_at)).toISOString()
    : createdAt;

  return {
    merchant_id: creds.merchant_id,
    platform: "lazada",
    shop_id: creds.shop_id,
    order_sn: String(lazadaOrder.order_id ?? lazadaOrder.order_number ?? ""),
    external_user_id: lazadaOrder.customer_id != null
      ? String(lazadaOrder.customer_id)
      : (lazadaOrder.buyer_id != null ? String(lazadaOrder.buyer_id) : null),
    buyer_username: billing?.first_name != null
      ? String(billing.first_name)
      : (lazadaOrder.customer_first_name != null ? String(lazadaOrder.customer_first_name) : null),
    buyer_phone: billing?.phone != null
      ? String(billing.phone)
      : (shipping?.phone != null ? String(shipping.phone) : null),
    buyer_email: billing?.email != null ? String(billing.email) : null,
    order_status: status,
    transaction_date: createdAt,
    update_time: updatedAt,
    currency: String(lazadaOrder.currency ?? items[0]?.currency ?? "THB"),
    total_amount: itemsTotal || parseFloat(String(lazadaOrder.price || 0)),
    shipping_fee: shippingFee,
    discount_amount: parseFloat(String(lazadaOrder.voucher ?? lazadaOrder.voucher_platform ?? 0)),
    tax_amount: parseFloat(String(lazadaOrder.tax_amount || 0)),
    final_amount: parseFloat(String(lazadaOrder.price || itemsTotal + shippingFee)),
    payment_method: lazadaOrder.payment_method != null ? String(lazadaOrder.payment_method) : null,
    payment_status: lazadaOrder.payment_status != null ? String(lazadaOrder.payment_status) : "paid",
    items,
  };
}
