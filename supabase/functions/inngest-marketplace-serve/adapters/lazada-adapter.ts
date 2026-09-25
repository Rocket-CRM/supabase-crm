import type { MarketplaceAdapter, PlatformCredentials, NormalizedOrder, NormalizedOrderItem } from "./types.ts";
import { resolveLazadaStatuses } from "../lib/status-rank.ts";

function amount(value: unknown): number {
  const parsed = Number(value);
  return Number.isFinite(parsed) ? parsed : 0;
}

function money(value: unknown): number {
  return Math.round(amount(value) * 100 + Number.EPSILON) / 100;
}

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
  const qs = new URLSearchParams(params).toString();
  const url = `https://api.lazada.co.th/rest${path}?${qs}`;
  const response = await fetch(url, { method: "GET" });
  if (!response.ok) {
    throw new Error(`Lazada HTTP ${response.status}: ${await response.text()}`);
  }
  return await response.json() as Record<string, unknown>;
}

export class LazadaAdapter implements MarketplaceAdapter {
  readonly supportsBatch = true;

  getNewOrderStatuses(): string[] {
    return ["pending"];
  }

  async buildGetOrderDetailsRequest(
    _credentials: PlatformCredentials,
    _orderSns: string[],
  ): Promise<{ url: string; options: RequestInit }> {
    throw new Error("LazadaAdapter: use fetchOrders() — unsigned /orders/get is not supported");
  }

  parseOrdersResponse(response: unknown): unknown[] {
    const rec = response as { code?: string | number; message?: string; data?: { orders?: unknown[] } };
    if (Array.isArray(response)) return response;
    if (rec?.code !== "0" && rec?.code !== 0) {
      throw new Error(`Lazada API error: ${rec.code} - ${rec.message}`);
    }
    return rec.data?.orders || [];
  }

  async fetchOrders(
    credentials: PlatformCredentials,
    orderSns: string[],
  ): Promise<{ success: boolean; orders: Record<string, unknown>[]; error: string | null; skipped_order_sns: string[] }> {
    const appKey = credentials.app_key || Deno.env.get("LAZADA_APP_KEY") || "";
    const appSecret = Deno.env.get("LAZADA_APP_SECRET") || credentials.app_secret || "";
    const accessToken = credentials.access_token;

    if (!appKey || !appSecret) {
      return {
        success: false,
        orders: [],
        error: "Lazada app_key / LAZADA_APP_SECRET not configured",
        skipped_order_sns: orderSns,
      };
    }
    if (!accessToken) {
      return { success: false, orders: [], error: "Missing Lazada access_token", skipped_order_sns: orderSns };
    }

    const orders: Record<string, unknown>[] = [];
    const skipped: string[] = [];
    const errors: string[] = [];

    for (const orderSn of orderSns) {
      try {
        const orderRes = await lazadaGet("/order/get", { order_id: orderSn }, appKey, appSecret, accessToken);
        if (orderRes.code !== "0" && orderRes.code !== 0) {
          skipped.push(orderSn);
          errors.push(`${orderSn}: ${orderRes.code} ${orderRes.message || ""}`);
          continue;
        }
        const itemsRes = await lazadaGet("/order/items/get", { order_id: orderSn }, appKey, appSecret, accessToken);
        const items = (itemsRes.code === "0" || itemsRes.code === 0) ? (itemsRes.data || []) : [];
        orders.push({ ...(orderRes.data as object || {}), items });
      } catch (err: unknown) {
        skipped.push(orderSn);
        errors.push(`${orderSn}: ${err instanceof Error ? err.message : String(err)}`);
      }
    }

    return {
      success: orders.length > 0,
      orders,
      error: orders.length === 0 ? (errors.join("; ") || "No Lazada orders fetched") : (errors.length ? errors.join("; ") : null),
      skipped_order_sns: skipped,
    };
  }

  normalizeOrder(lazadaOrder: Record<string, unknown>, credentials: PlatformCredentials): NormalizedOrder {
    const rawItems = (lazadaOrder.items as Record<string, unknown>[] | undefined) ?? [];
    const items: NormalizedOrderItem[] = rawItems.map((item) => {
      const quantity = parseInt(String(item.quantity || "1"), 10) || 1;
      const unitPrice = amount(item.item_price);
      const grossLineAmount = money(unitPrice * quantity);
      const lineTotal = money(item.paid_price);
      return {
        platform_item_id: item.order_item_id != null ? String(item.order_item_id) : "",
        variant_id: item.sku_id != null ? String(item.sku_id) : (item.sku != null ? String(item.sku) : undefined),
        platform_sku: item.shop_sku != null || item.sku != null ? String(item.shop_sku ?? item.sku) : undefined,
        item_name: String(item.name ?? ""),
        variant_name: item.variation != null ? String(item.variation) : undefined,
        quantity,
        currency: String(item.currency ?? lazadaOrder.currency ?? "THB"),
        unit_price: money(unitPrice),
        discount_amount: money(grossLineAmount - lineTotal),
        line_total: lineTotal,
        earnable_amount: lineTotal,
        financial_details: {
          source: "lazada_paid_price",
          gross_merchandise_amount: grossLineAmount,
          paid_price: lineTotal,
          voucher_amount: money(item.voucher_amount),
          voucher_seller: money(item.voucher_seller),
          voucher_platform: money(item.voucher_platform),
        },
      };
    });

    const earnableAmount = money(items.reduce((sum, item) => sum + item.earnable_amount, 0));
    const grossAmount = money(rawItems.reduce((sum, item) => {
      const quantity = parseInt(String(item.quantity || "1"), 10) || 1;
      return sum + amount(item.item_price) * quantity;
    }, 0));
    const shippingFee = money(lazadaOrder.shipping_fee);
    const status = resolveLazadaStatuses({
      statuses: lazadaOrder.statuses,
      status: lazadaOrder.status,
      items: rawItems,
    });

    const createdAt = lazadaOrder.created_at
      ? new Date(String(lazadaOrder.created_at)).toISOString()
      : new Date().toISOString();
    const updatedAt = lazadaOrder.updated_at
      ? new Date(String(lazadaOrder.updated_at)).toISOString()
      : createdAt;
    const billing = lazadaOrder.address_billing as Record<string, unknown> | undefined;
    const shipping = lazadaOrder.address_shipping as Record<string, unknown> | undefined;

    return {
      merchant_id: credentials.merchant_id,
      platform: "lazada",
      shop_id: credentials.shop_id,
      order_sn: String(lazadaOrder.order_id || lazadaOrder.order_number || ""),
      external_user_id: lazadaOrder.customer_id != null
        ? String(lazadaOrder.customer_id)
        : (lazadaOrder.buyer_id != null ? String(lazadaOrder.buyer_id) : undefined),
      buyer_username: billing?.first_name != null
        ? String(billing.first_name)
        : (lazadaOrder.customer_first_name != null ? String(lazadaOrder.customer_first_name) : undefined),
      buyer_phone: billing?.phone != null
        ? String(billing.phone)
        : (shipping?.phone != null ? String(shipping.phone) : undefined),
      buyer_email: billing?.email != null ? String(billing.email) : undefined,
      order_status: status,
      transaction_date: createdAt,
      update_time: updatedAt,
      currency: String(lazadaOrder.currency ?? items[0]?.currency ?? "THB"),
      total_amount: grossAmount,
      shipping_fee: shippingFee,
      discount_amount: money(grossAmount - earnableAmount),
      tax_amount: money(lazadaOrder.tax_amount),
      final_amount: lazadaOrder.price != null
        ? money(lazadaOrder.price)
        : money(earnableAmount + shippingFee + amount(lazadaOrder.tax_amount)),
      earnable_amount: earnableAmount,
      financial_details: {
        source: "lazada_order_and_items",
        gross_merchandise_amount: grossAmount,
        net_merchandise_amount: earnableAmount,
        voucher_amount: money(lazadaOrder.voucher),
        voucher_seller: money(lazadaOrder.voucher_seller),
        voucher_platform: money(lazadaOrder.voucher_platform),
      },
      payment_method: lazadaOrder.payment_method != null ? String(lazadaOrder.payment_method) : undefined,
      payment_status: lazadaOrder.payment_status != null ? String(lazadaOrder.payment_status) : "paid",
      items,
    };
  }
}
