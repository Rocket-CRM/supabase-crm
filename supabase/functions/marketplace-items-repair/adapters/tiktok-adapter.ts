import type { MarketplaceAdapter, PlatformCredentials, NormalizedOrder, NormalizedOrderItem } from "./types.ts";

type FetchOrdersResult = {
  success: boolean;
  orders: Record<string, unknown>[];
  error: string | null;
  skipped_order_sns: string[];
};

function amount(value: unknown): number {
  const parsed = Number(value);
  return Number.isFinite(parsed) ? parsed : 0;
}

function toCents(value: number): number {
  return Math.round((Number.isFinite(value) ? value : 0) * 100 + Number.EPSILON);
}

function fromCents(value: number): number {
  return value / 100;
}

function allocateToTarget(weightsInput: number[], targetAmount: number): number[] {
  if (weightsInput.length === 0) return [];
  const targetCents = Math.max(0, toCents(targetAmount));
  const weights = weightsInput.map((value) => Math.max(0, toCents(value)));
  const weightTotal = weights.reduce((sum, value) => sum + value, 0);
  if (weightTotal === 0) {
    return weights.map((_, index) => index === weights.length - 1 ? fromCents(targetCents) : 0);
  }

  let allocated = 0;
  return weights.map((weight, index) => {
    const cents = index === weights.length - 1
      ? targetCents - allocated
      : Math.min(targetCents - allocated, Math.max(0, Math.round(targetCents * weight / weightTotal)));
    allocated += cents;
    return fromCents(cents);
  });
}

export class TikTokAdapter implements MarketplaceAdapter {
  readonly supportsBatch = true;
  private readonly baseUrl = "https://open-api.tiktokglobalshop.com";

  getNewOrderStatuses(): string[] {
    return ["AWAITING_SHIPMENT"];
  }

  private async buildSignedGetRequest(
    path: string,
    credentials: PlatformCredentials,
    extraQuery: Record<string, string> = {},
  ): Promise<{ url: string; options: RequestInit }> {
    const { access_token } = credentials;
    const timestamp = Math.floor(Date.now() / 1000);
    const appKey = Deno.env.get("TIKTOK_APP_KEY") || credentials.app_key || "";
    const appSecret = Deno.env.get("TIKTOK_APP_SECRET") || credentials.app_secret || "";
    const shopCipher = credentials.shop_cipher || "";
    if (!shopCipher) throw new Error("shop_cipher is required for TikTok API calls");
    if (!appKey || !appSecret) throw new Error("TIKTOK_APP_KEY / TIKTOK_APP_SECRET not configured");
    const paramObj: Record<string, string> = {
      app_key: appKey,
      shop_cipher: shopCipher,
      timestamp: timestamp.toString(),
      ...extraQuery,
    };
    const sortedKeys = Object.keys(paramObj).sort();
    const paramString = sortedKeys.map((key) => `${key}${paramObj[key]}`).join("");
    const signString = `${path}${paramString}`;
    const wrapped = `${appSecret}${signString}${appSecret}`;
    const encoder = new TextEncoder();
    const key = await crypto.subtle.importKey(
      "raw",
      encoder.encode(appSecret),
      { name: "HMAC", hash: "SHA-256" },
      false,
      ["sign"],
    );
    const signature = await crypto.subtle.sign("HMAC", key, encoder.encode(wrapped));
    const sign = Array.from(new Uint8Array(signature)).map((b) => b.toString(16).padStart(2, "0")).join("");
    paramObj.sign = sign;
    const params = new URLSearchParams(paramObj);
    const url = `${this.baseUrl}${path}?${params.toString()}`;
    return {
      url,
      options: {
        method: "GET",
        headers: { "x-tts-access-token": access_token, "content-type": "application/json" },
      },
    };
  }

  async buildGetOrderDetailsRequest(
    credentials: PlatformCredentials,
    orderSns: string[],
  ): Promise<{ url: string; options: RequestInit }> {
    return await this.buildSignedGetRequest(
      "/order/202309/orders",
      credentials,
      { ids: orderSns.join(",") },
    );
  }

  parseOrdersResponse(response: Record<string, unknown>): unknown[] {
    if (response.code === 98001004) {
      console.warn("[TikTokAdapter] Some order IDs are invalid, returning empty list");
      return [];
    }
    if (response.code !== 0) {
      throw new Error(`TikTok API error: ${response.code} - ${response.message}`);
    }
    const data = response.data as { orders?: unknown[] } | undefined;
    return data?.orders || [];
  }

  async fetchOrders(
    credentials: PlatformCredentials,
    orderSns: string[],
  ): Promise<FetchOrdersResult> {
    const detailRequest = await this.buildGetOrderDetailsRequest(credentials, orderSns);
    const detailResponse = await fetch(detailRequest.url, detailRequest.options);
    const detailText = await detailResponse.text();
    if (!detailResponse.ok) {
      return {
        success: false,
        orders: [],
        error: `HTTP ${detailResponse.status}: ${detailText}`,
        skipped_order_sns: orderSns,
      };
    }

    let detailPayload: Record<string, unknown>;
    try {
      detailPayload = JSON.parse(detailText) as Record<string, unknown>;
    } catch {
      return {
        success: false,
        orders: [],
        error: "TikTok detail returned invalid JSON",
        skipped_order_sns: orderSns,
      };
    }
    if (detailPayload.code === 98001004) {
      return {
        success: false,
        orders: [],
        error: `Orders not found in TikTok: ${detailPayload.message ?? ""}`,
        skipped_order_sns: orderSns,
      };
    }

    let orders: Record<string, unknown>[];
    try {
      orders = this.parseOrdersResponse(detailPayload) as Record<string, unknown>[];
    } catch (err: unknown) {
      return {
        success: false,
        orders: [],
        error: err instanceof Error ? err.message : String(err),
        skipped_order_sns: orderSns,
      };
    }

    const enrichedOrders = await Promise.all(orders.map(async (order): Promise<Record<string, unknown>> => {
      const payment = order.payment as Record<string, unknown> | undefined;
      if (amount(payment?.payment_platform_discount) <= 0) {
        return { ...order, _financial_api_errors: [] };
      }

      const orderId = String(order.id ?? "");
      try {
        const path = `/order/202407/orders/${encodeURIComponent(orderId)}/price_detail`;
        const priceRequest = await this.buildSignedGetRequest(path, credentials);
        const priceResponse = await fetch(priceRequest.url, priceRequest.options);
        const priceText = await priceResponse.text();
        if (!priceResponse.ok) {
          return {
            ...order,
            _financial_api_errors: [{
              source: "tiktok_price_detail",
              http_status: priceResponse.status,
              message: priceText,
            }],
          };
        }
        const pricePayload = JSON.parse(priceText) as Record<string, unknown>;
        if (pricePayload.code !== 0) {
          return {
            ...order,
            _financial_api_errors: [{
              source: "tiktok_price_detail",
              code: pricePayload.code,
              message: pricePayload.message ?? null,
              request_id: pricePayload.request_id ?? null,
            }],
          };
        }
        const data = pricePayload.data as Record<string, unknown> | undefined;
        return {
          ...order,
          _tiktok_price_detail: (data?.price_detail as Record<string, unknown> | undefined) ?? data,
          _financial_api_errors: [],
        };
      } catch (err: unknown) {
        return {
          ...order,
          _financial_api_errors: [{
            source: "tiktok_price_detail",
            message: err instanceof Error ? err.message : String(err),
          }],
        };
      }
    }));

    const returnedOrderSns = new Set(enrichedOrders.map((order) => String(order.id ?? "")));
    return {
      success: enrichedOrders.length > 0,
      orders: enrichedOrders,
      error: enrichedOrders.length > 0 ? null : "No TikTok orders fetched",
      skipped_order_sns: orderSns.filter((orderSn) => !returnedOrderSns.has(orderSn)),
    };
  }

  normalizeOrder(tiktokOrder: Record<string, unknown>, credentials: PlatformCredentials): NormalizedOrder {
    const lineItems = (tiktokOrder.line_items as Record<string, unknown>[] | undefined) ?? [];
    const payment = tiktokOrder.payment as Record<string, unknown> | undefined;
    const shippingFee = fromCents(toCents(amount(payment?.shipping_fee)));
    const taxAmount = fromCents(toCents(amount(payment?.tax)));
    const saleLineAmounts = lineItems.map((item) => {
      const quantity = amount(item.quantity) || 1;
      return fromCents(toCents(amount(item.sale_price) * quantity));
    });
    const grossLineAmounts = lineItems.map((item) => {
      const quantity = amount(item.quantity) || 1;
      return fromCents(toCents(amount(item.original_price ?? item.sale_price) * quantity));
    });
    const saleLinesTotal = fromCents(saleLineAmounts.reduce((sum, value) => sum + toCents(value), 0));
    const checkoutTotal = payment?.total_amount != null
      ? fromCents(toCents(amount(payment.total_amount)))
      : fromCents(toCents(saleLinesTotal + shippingFee + taxAmount));
    const checkoutMerchandiseTarget = fromCents(
      Math.max(0, toCents(checkoutTotal - shippingFee - taxAmount)),
    );

    const priceDetail = tiktokOrder._tiktok_price_detail as Record<string, unknown> | undefined;
    const priceLines = (priceDetail?.line_items as Record<string, unknown>[] | undefined) ?? [];
    const priceLineById = new Map(
      priceLines.flatMap((line) => line.id == null ? [] : [[String(line.id), line] as const]),
    );
    const matchedPriceLines = lineItems.map((item) => priceLineById.get(String(item.id ?? "")));
    const hasCompletePriceDetail = lineItems.length > 0 &&
      matchedPriceLines.every((line) => line != null);
    const exactPriceLineAmounts = matchedPriceLines.map((line) => {
      if (!line) return 0;
      return fromCents(Math.max(0, toCents(
        amount(line.payment) - amount(line.shipping_sale_price) - amount(line.tax_amount ?? line.tax),
      )));
    });
    const lineAmounts = hasCompletePriceDetail
      ? exactPriceLineAmounts
      : allocateToTarget(saleLineAmounts, checkoutMerchandiseTarget);
    const earnableAmount = fromCents(lineAmounts.reduce((sum, value) => sum + toCents(value), 0));
    const grossFromPayment = payment?.original_total_product_price != null
      ? fromCents(toCents(amount(payment.original_total_product_price)))
      : undefined;
    const grossAmount = grossFromPayment ??
      fromCents(grossLineAmounts.reduce((sum, value) => sum + toCents(value), 0));
    const items: NormalizedOrderItem[] = lineItems.map((item, index) => {
      const quantity = amount(item.quantity) || 1;
      const lineTotal = lineAmounts[index] ?? 0;
      const priceLine = matchedPriceLines[index];
      return {
        platform_item_id: item.id != null ? String(item.id) : "",
        variant_id: item.sku_id != null ? String(item.sku_id) : undefined,
        platform_sku: item.seller_sku != null ? String(item.seller_sku) : undefined,
        item_name: String(item.product_name || ""),
        variant_name: item.sku_name != null ? String(item.sku_name) : undefined,
        quantity,
        currency: String(payment?.currency || "THB"),
        unit_price: fromCents(toCents(amount(item.original_price ?? item.sale_price))),
        discount_amount: fromCents(toCents((grossLineAmounts[index] ?? 0) - lineTotal)),
        line_total: lineTotal,
        earnable_amount: lineTotal,
        financial_details: {
          source: hasCompletePriceDetail ? "tiktok_price_detail" : "tiktok_checkout_allocation",
          gross_merchandise_amount: grossLineAmounts[index] ?? 0,
          sale_price_amount: saleLineAmounts[index] ?? 0,
          payment: priceLine?.payment ?? null,
          shipping_sale_price: priceLine?.shipping_sale_price ?? null,
          tax_amount: priceLine?.tax_amount ?? priceLine?.tax ?? null,
        },
      };
    });
    const addr = tiktokOrder.recipient_address as Record<string, unknown> | undefined;
    const errors = Array.isArray(tiktokOrder._financial_api_errors)
      ? tiktokOrder._financial_api_errors as unknown[]
      : [];
    return {
      merchant_id: credentials.merchant_id,
      platform: "tiktok",
      shop_id: credentials.shop_id,
      order_sn: String(tiktokOrder.id),
      external_user_id: tiktokOrder.user_id != null ? String(tiktokOrder.user_id) : undefined,
      buyer_username: addr?.name != null ? String(addr.name) : undefined,
      buyer_phone: addr?.phone_number != null ? String(addr.phone_number) : undefined,
      buyer_email: tiktokOrder.buyer_email != null ? String(tiktokOrder.buyer_email) : undefined,
      order_status: String(tiktokOrder.status),
      transaction_date: new Date(Number(tiktokOrder.create_time) * 1000).toISOString(),
      update_time: tiktokOrder.update_time
        ? new Date(Number(tiktokOrder.update_time) * 1000).toISOString()
        : new Date().toISOString(),
      currency: String(payment?.currency || "THB"),
      total_amount: grossAmount,
      shipping_fee: shippingFee,
      discount_amount: fromCents(toCents(grossAmount - earnableAmount)),
      tax_amount: taxAmount,
      final_amount: checkoutTotal,
      earnable_amount: earnableAmount,
      financial_details: {
        source: hasCompletePriceDetail ? "tiktok_price_detail" : "tiktok_checkout_allocation",
        gross_merchandise_amount: grossAmount,
        checkout_merchandise_target: checkoutMerchandiseTarget,
        payment_platform_discount: amount(payment?.payment_platform_discount),
        seller_discount: amount(payment?.seller_discount),
        buyer_paid_shipping_fee: shippingFee,
        tax_amount: taxAmount,
        api_errors: errors,
      },
      payment_method: tiktokOrder.payment_method_name != null ? String(tiktokOrder.payment_method_name) : undefined,
      payment_status: tiktokOrder.is_cod ? "cod" : "paid",
      items,
    };
  }
}
