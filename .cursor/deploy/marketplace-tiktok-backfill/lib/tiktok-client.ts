import { signTiktokRequest } from "./tiktok-sign.ts";

const BASE_URL = "https://open-api.tiktokglobalshop.com";

export interface TiktokCredentials {
  merchant_id: string;
  shop_id: string;
  access_token: string;
  shop_cipher: string;
  app_key: string;
  app_secret: string;
}

export interface TiktokSearchOrderSummary {
  id: string;
  status: string;
  create_time?: number;
  update_time?: number;
}

function appKeySecret(creds: TiktokCredentials): { appKey: string; appSecret: string } {
  const appKey = Deno.env.get("TIKTOK_APP_KEY") || creds.app_key || "";
  const appSecret = Deno.env.get("TIKTOK_APP_SECRET") || creds.app_secret || "";
  if (!appKey || !appSecret) {
    throw new Error("TIKTOK_APP_KEY / TIKTOK_APP_SECRET not configured");
  }
  if (!creds.shop_cipher) throw new Error("shop_cipher is required");
  return { appKey, appSecret };
}

async function signedFetch(
  path: string,
  creds: TiktokCredentials,
  opts: { method: "GET" | "POST"; query?: Record<string, string>; body?: Record<string, unknown> },
): Promise<Response> {
  const { appKey, appSecret } = appKeySecret(creds);
  const timestamp = Math.floor(Date.now() / 1000).toString();

  const queryParams: Record<string, string> = {
    app_key: appKey,
    shop_cipher: creds.shop_cipher,
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
  creds: TiktokCredentials,
  opts: {
    create_time_ge: number;
    create_time_lt: number;
    page_size?: number;
    page_token?: string;
  },
): Promise<{
  code: number;
  message?: string;
  orders: TiktokSearchOrderSummary[];
  next_page_token?: string;
  raw: unknown;
}> {
  const path = "/order/202309/orders/search";
  const body: Record<string, unknown> = {
    create_time_ge: opts.create_time_ge,
    create_time_lt: opts.create_time_lt,
  };

  const query: Record<string, string> = {
    page_size: String(opts.page_size ?? 50),
  };
  if (opts.page_token) query.page_token = opts.page_token;

  const response = await signedFetch(path, creds, {
    method: "POST",
    query,
    body,
  });

  const data = await response.json();
  if (!response.ok) {
    throw new Error(`TikTok search HTTP ${response.status}: ${JSON.stringify(data)}`);
  }

  const orders = (data.data?.orders ?? []).map((o: Record<string, unknown>) => ({
    id: String(o.id ?? ""),
    status: String(o.status ?? "UNKNOWN"),
    create_time: typeof o.create_time === "number" ? o.create_time : undefined,
    update_time: typeof o.update_time === "number" ? o.update_time : undefined,
  }));

  const nextPageToken =
    data.data?.next_page_token ??
    data.data?.page_token ??
    data.next_page_token ??
    undefined;

  // TikTok returns empty string when no more pages
  const token = typeof nextPageToken === "string" && nextPageToken.length > 0
    ? nextPageToken
    : undefined;

  return {
    code: data.code ?? -1,
    message: data.message,
    orders,
    next_page_token: token,
    raw: data,
  };
}

export async function getTiktokOrderDetails(
  creds: TiktokCredentials,
  orderIds: string[],
): Promise<Record<string, unknown>[]> {
  if (orderIds.length === 0) return [];

  const path = "/order/202309/orders";
  const response = await signedFetch(path, creds, {
    method: "GET",
    query: { ids: orderIds.join(",") },
  });

  const data = await response.json();
  if (!response.ok) {
    throw new Error(`TikTok detail HTTP ${response.status}: ${JSON.stringify(data)}`);
  }
  if (data.code === 98001004) return [];
  if (data.code !== 0) {
    throw new Error(`TikTok detail error ${data.code}: ${data.message}`);
  }
  return data.data?.orders ?? [];
}

/** Same shape as inngest-marketplace-serve TikTokAdapter.normalizeOrder */
export function normalizeTiktokOrder(
  tiktokOrder: Record<string, unknown>,
  creds: TiktokCredentials,
): Record<string, unknown> {
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
    platform_sku: item.seller_sku,
    item_name: String(item.product_name ?? ""),
    variant_name: item.sku_name,
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
    buyer_username: recipient?.name,
    buyer_phone: recipient?.phone_number,
    buyer_email: tiktokOrder.buyer_email,
    order_status: String(tiktokOrder.status ?? "UNKNOWN"),
    transaction_date: new Date(createTime * 1000).toISOString(),
    update_time: updateTime ? new Date(updateTime * 1000).toISOString() : new Date().toISOString(),
    currency: String(payment?.currency ?? "THB"),
    total_amount: itemsTotal,
    shipping_fee: shippingFee,
    discount_amount: parseFloat(String(payment?.platform_discount ?? "0")),
    tax_amount: parseFloat(String(payment?.tax ?? "0")),
    final_amount: finalAmount,
    payment_method: tiktokOrder.payment_method_name,
    payment_status: tiktokOrder.is_cod ? "cod" : "paid",
    items,
  };
}
