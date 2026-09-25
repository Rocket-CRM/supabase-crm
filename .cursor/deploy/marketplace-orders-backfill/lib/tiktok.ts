import type { NormalizedOrder, PlatformCredentials } from "./types.ts";
import { signTiktokRequest } from "./tiktok-sign.ts";

const BASE_URL = "https://open-api.tiktokglobalshop.com";

function appKeySecret(creds: PlatformCredentials): { appKey: string; appSecret: string } {
  const appKey = Deno.env.get("TIKTOK_APP_KEY") || creds.app_key || "";
  const appSecret = Deno.env.get("TIKTOK_APP_SECRET") || creds.app_secret || "";
  if (!appKey || !appSecret) throw new Error("TIKTOK_APP_KEY / TIKTOK_APP_SECRET not configured");
  if (!creds.shop_cipher) throw new Error("shop_cipher is required");
  return { appKey, appSecret };
}

async function signedFetch(
  path: string,
  creds: PlatformCredentials,
  opts: { method: "GET" | "POST"; query?: Record<string, string>; body?: Record<string, unknown> },
): Promise<Response> {
  const { appKey, appSecret } = appKeySecret(creds);
  const timestamp = Math.floor(Date.now() / 1000).toString();
  const queryParams: Record<string, string> = {
    app_key: appKey,
    shop_cipher: creds.shop_cipher!,
    timestamp,
    ...opts.query,
  };
  const bodyStr = opts.body ? JSON.stringify(opts.body) : undefined;
  const sign = await signTiktokRequest(path, queryParams, appSecret, bodyStr);
  queryParams.sign = sign;
  const url = `${BASE_URL}${path}?${new URLSearchParams(queryParams).toString()}`;
  return fetch(url, {
    method: opts.method,
    headers: {
      "x-tts-access-token": creds.access_token,
      "content-type": "application/json",
    },
    body: bodyStr,
  });
}

export async function searchTiktokOrders(
  creds: PlatformCredentials,
  opts: { create_time_ge: number; create_time_lt: number; page_size?: number; page_token?: string },
): Promise<{ code: number; message?: string; orders: { id: string; status: string }[]; next_page_token?: string }> {
  const path = "/order/202309/orders/search";
  const query: Record<string, string> = { page_size: String(opts.page_size ?? 50) };
  if (opts.page_token) query.page_token = opts.page_token;
  const response = await signedFetch(path, creds, {
    method: "POST",
    query,
    body: { create_time_ge: opts.create_time_ge, create_time_lt: opts.create_time_lt },
  });
  const data = await response.json();
  if (!response.ok) throw new Error(`TikTok search HTTP ${response.status}: ${JSON.stringify(data)}`);
  const orders = (data.data?.orders ?? []).map((o: Record<string, unknown>) => ({
    id: String(o.id ?? ""),
    status: String(o.status ?? "UNKNOWN"),
  }));
  const next = data.data?.next_page_token ?? data.data?.page_token;
  return {
    code: data.code ?? -1,
    message: data.message,
    orders,
    next_page_token: typeof next === "string" && next.length > 0 ? next : undefined,
  };
}

export async function getTiktokOrderDetails(
  creds: PlatformCredentials,
  orderIds: string[],
): Promise<Record<string, unknown>[]> {
  if (orderIds.length === 0) return [];
  const path = "/order/202309/orders";
  const response = await signedFetch(path, creds, {
    method: "GET",
    query: { ids: orderIds.join(",") },
  });
  const data = await response.json();
  if (!response.ok) throw new Error(`TikTok detail HTTP ${response.status}: ${JSON.stringify(data)}`);
  if (data.code === 98001004) return [];
  if (data.code !== 0) throw new Error(`TikTok detail error ${data.code}: ${data.message}`);
  return data.data?.orders ?? [];
}

export function normalizeTiktokOrder(
  tiktokOrder: Record<string, unknown>,
  creds: PlatformCredentials,
): NormalizedOrder {
  const lineItems = tiktokOrder.line_items as Record<string, unknown>[] | undefined;
  const payment = tiktokOrder.payment as Record<string, unknown> | undefined;
  const recipient = tiktokOrder.recipient_address as Record<string, unknown> | undefined;
  const itemsTotal = lineItems?.reduce((sum, item) => {
    return sum + (parseFloat(String(item.sale_price ?? "0")) * (Number(item.quantity) || 1));
  }, 0) ?? 0;
  const shippingFee = parseFloat(String(payment?.shipping_fee ?? "0"));
  const finalAmount = parseFloat(String(payment?.total_amount ?? "0")) || (itemsTotal + shippingFee);
  const items = lineItems?.map((item) => ({
    platform_item_id: String(item.id ?? ""),
    variant_id: item.sku_id != null ? String(item.sku_id) : null,
    platform_sku: item.seller_sku != null ? String(item.seller_sku) : null,
    item_name: String(item.product_name ?? ""),
    variant_name: item.sku_name != null ? String(item.sku_name) : null,
    quantity: Number(item.quantity) || 1,
    currency: String(payment?.currency ?? "THB"),
    unit_price: parseFloat(String(item.original_price ?? item.sale_price ?? "0")),
    discount_amount: (parseFloat(String(item.original_price ?? "0")) -
      parseFloat(String(item.sale_price ?? "0"))) * (Number(item.quantity) || 1),
    line_total: parseFloat(String(item.sale_price ?? "0")) * (Number(item.quantity) || 1),
  })) ?? [];
  const createTime = Number(tiktokOrder.create_time ?? 0);
  const updateTime = Number(tiktokOrder.update_time ?? 0);
  return {
    merchant_id: creds.merchant_id,
    platform: "tiktok",
    shop_id: creds.shop_id,
    order_sn: String(tiktokOrder.id ?? ""),
    external_user_id: tiktokOrder.user_id != null ? String(tiktokOrder.user_id) : null,
    buyer_username: recipient?.name != null ? String(recipient.name) : null,
    buyer_phone: recipient?.phone_number != null ? String(recipient.phone_number) : null,
    buyer_email: tiktokOrder.buyer_email != null ? String(tiktokOrder.buyer_email) : null,
    order_status: String(tiktokOrder.status ?? "UNKNOWN"),
    transaction_date: new Date(createTime * 1000).toISOString(),
    update_time: updateTime ? new Date(updateTime * 1000).toISOString() : new Date().toISOString(),
    currency: String(payment?.currency ?? "THB"),
    total_amount: itemsTotal,
    shipping_fee: shippingFee,
    discount_amount: parseFloat(String(payment?.platform_discount ?? "0")),
    tax_amount: parseFloat(String(payment?.tax ?? "0")),
    final_amount: finalAmount,
    payment_method: tiktokOrder.payment_method_name != null ? String(tiktokOrder.payment_method_name) : null,
    payment_status: tiktokOrder.is_cod ? "cod" : "paid",
    items,
  };
}
