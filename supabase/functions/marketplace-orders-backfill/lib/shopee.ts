import type { NormalizedOrder, PlatformCredentials } from "./types.ts";

const BASE_URL = "https://partner.shopeemobile.com";

async function shopeeSign(partnerId: string, path: string, timestamp: number, accessToken: string, shopId: string, partnerKey: string): Promise<string> {
  const baseString = `${partnerId}${path}${timestamp}${accessToken}${shopId}`;
  const encoder = new TextEncoder();
  const key = await crypto.subtle.importKey("raw", encoder.encode(partnerKey), { name: "HMAC", hash: "SHA-256" }, false, ["sign"]);
  const signature = await crypto.subtle.sign("HMAC", key, encoder.encode(baseString));
  return Array.from(new Uint8Array(signature)).map((b) => b.toString(16).padStart(2, "0")).join("");
}

function partnerKey(): string {
  const key = Deno.env.get("SHOPEE_PARTNER_KEY") || "";
  if (!key) throw new Error("SHOPEE_PARTNER_KEY not configured");
  return key;
}

export async function listShopeeOrders(
  creds: PlatformCredentials,
  opts: { time_from: number; time_to: number; page_size?: number; cursor?: string },
): Promise<{ order_sns: string[]; next_cursor?: string; more: boolean; raw: unknown }> {
  const partnerId = creds.partner_id;
  if (!partnerId) throw new Error("Shopee partner_id missing from credentials");
  const path = "/api/v2/order/get_order_list";
  const timestamp = Math.floor(Date.now() / 1000);
  const sign = await shopeeSign(partnerId, path, timestamp, creds.access_token, creds.shop_id, partnerKey());
  const params = new URLSearchParams({
    partner_id: partnerId,
    timestamp: String(timestamp),
    access_token: creds.access_token,
    shop_id: creds.shop_id,
    sign,
    time_range_field: "create_time",
    time_from: String(opts.time_from),
    time_to: String(opts.time_to),
    page_size: String(opts.page_size ?? 50),
  });
  if (opts.cursor) params.set("cursor", opts.cursor);

  const response = await fetch(`${BASE_URL}${path}?${params}`, {
    method: "GET",
    headers: { "Content-Type": "application/json" },
  });
  const data = await response.json();
  if (!response.ok) throw new Error(`Shopee list HTTP ${response.status}: ${JSON.stringify(data)}`);
  if (data.error) throw new Error(`Shopee list error: ${data.error} - ${data.message}`);

  const list = data.response?.order_list ?? [];
  const order_sns = list.map((o: { order_sn?: string }) => String(o.order_sn ?? "")).filter(Boolean);
  const next = data.response?.next_cursor;
  const more = Boolean(data.response?.more);
  return {
    order_sns,
    next_cursor: typeof next === "string" && next.length > 0 ? next : undefined,
    more,
    raw: data,
  };
}

export async function getShopeeOrderDetails(
  creds: PlatformCredentials,
  orderSns: string[],
): Promise<Record<string, unknown>[]> {
  if (orderSns.length === 0) return [];
  const partnerId = creds.partner_id;
  if (!partnerId) throw new Error("Shopee partner_id missing from credentials");
  const path = "/api/v2/order/get_order_detail";
  const timestamp = Math.floor(Date.now() / 1000);
  const sign = await shopeeSign(partnerId, path, timestamp, creds.access_token, creds.shop_id, partnerKey());
  const responseFields =
    "buyer_user_id,buyer_username,recipient_address,total_amount,estimated_shipping_fee,actual_shipping_fee,payment_method,item_list";
  const params = new URLSearchParams({
    partner_id: partnerId,
    timestamp: String(timestamp),
    access_token: creds.access_token,
    shop_id: creds.shop_id,
    sign,
    order_sn_list: orderSns.join(","),
    response_optional_fields: responseFields,
  });
  const response = await fetch(`${BASE_URL}${path}?${params}`, {
    method: "GET",
    headers: { "Content-Type": "application/json" },
  });
  const data = await response.json();
  if (!response.ok) throw new Error(`Shopee detail HTTP ${response.status}: ${JSON.stringify(data)}`);
  if (data.error) throw new Error(`Shopee detail error: ${data.error} - ${data.message}`);
  return data.response?.order_list ?? [];
}

export function normalizeShopeeOrder(
  shopeeOrder: Record<string, unknown>,
  creds: PlatformCredentials,
): NormalizedOrder {
  const itemList = (shopeeOrder.item_list as Record<string, unknown>[] | undefined) ?? [];
  const itemsTotal = itemList.reduce((sum, item) => {
    return sum + (Number(item.model_discounted_price) || 0) * (Number(item.model_quantity_purchased) || 1);
  }, 0);
  const shippingFee = Number(
    shopeeOrder.actual_shipping_fee ?? shopeeOrder.estimated_shipping_fee ?? 0,
  );
  const recipient = shopeeOrder.recipient_address as Record<string, unknown> | undefined;
  const items = itemList.map((item, index) => ({
    platform_item_id: `${item.item_id}_${item.model_id ?? index}`,
    variant_id: item.model_id != null ? String(item.model_id) : null,
    item_name: String(item.item_name ?? ""),
    variant_name: item.model_name != null ? String(item.model_name) : null,
    quantity: Number(item.model_quantity_purchased) || 1,
    currency: String(shopeeOrder.currency ?? "THB"),
    unit_price: Number(item.model_original_price) || 0,
    discount_amount: ((Number(item.model_original_price) || 0) - (Number(item.model_discounted_price) || 0)) *
      (Number(item.model_quantity_purchased) || 1),
    line_total: (Number(item.model_discounted_price) || 0) * (Number(item.model_quantity_purchased) || 1),
  }));
  const createTime = Number(shopeeOrder.create_time ?? 0);
  const updateTime = Number(shopeeOrder.update_time ?? 0);
  return {
    merchant_id: creds.merchant_id,
    platform: "shopee",
    shop_id: creds.shop_id,
    order_sn: String(shopeeOrder.order_sn ?? ""),
    external_user_id: shopeeOrder.buyer_user_id != null ? String(shopeeOrder.buyer_user_id) : null,
    buyer_username: shopeeOrder.buyer_username != null ? String(shopeeOrder.buyer_username) : null,
    buyer_phone: recipient?.phone != null ? String(recipient.phone) : null,
    buyer_email: recipient?.email != null ? String(recipient.email) : null,
    order_status: String(shopeeOrder.order_status ?? "UNKNOWN"),
    transaction_date: new Date(createTime * 1000).toISOString(),
    update_time: updateTime ? new Date(updateTime * 1000).toISOString() : new Date().toISOString(),
    currency: String(shopeeOrder.currency ?? "THB"),
    total_amount: itemsTotal,
    shipping_fee: shippingFee,
    discount_amount: 0,
    tax_amount: 0,
    final_amount: itemsTotal + shippingFee,
    payment_method: shopeeOrder.payment_method != null ? String(shopeeOrder.payment_method) : null,
    payment_status: shopeeOrder.pay_time ? "paid" : "unpaid",
    items,
  };
}
