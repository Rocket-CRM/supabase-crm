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

function optionalAmount(record: Record<string, unknown> | undefined, keys: string[]): number | undefined {
  if (!record) return undefined;
  for (const key of keys) {
    if (record[key] == null || record[key] === "") continue;
    const parsed = Number(record[key]);
    if (Number.isFinite(parsed)) return parsed;
  }
  return undefined;
}

function toCents(value: number): number {
  return Math.round((Number.isFinite(value) ? value : 0) * 100 + Number.EPSILON);
}

function fromCents(value: number): number {
  return value / 100;
}

function allocateToTarget(baseAmounts: number[], targetAmount: number): number[] {
  if (baseAmounts.length === 0) return [];
  const targetCents = Math.max(0, toCents(targetAmount));
  const weights = baseAmounts.map((value) => Math.max(0, toCents(value)));
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

function shopeeErrorDetails(payload: Record<string, unknown>): Record<string, unknown> | null {
  if (!payload.error) return null;
  return {
    source: "shopee_escrow_detail_batch",
    code: payload.error,
    message: payload.message ?? null,
    request_id: payload.request_id ?? null,
  };
}

function escrowEntries(payload: Record<string, unknown>): Record<string, unknown>[] {
  const response = payload.response;
  if (Array.isArray(response)) return response as Record<string, unknown>[];
  const responseRecord = response as Record<string, unknown> | undefined;
  const candidates = [
    responseRecord?.order_income_list,
    responseRecord?.escrow_detail_list,
    payload.escrow_detail_list,
  ];
  for (const candidate of candidates) {
    if (Array.isArray(candidate)) return candidate as Record<string, unknown>[];
  }
  return [];
}

export class ShopeeAdapter implements MarketplaceAdapter {
  readonly supportsBatch = true;
  private readonly baseUrl = "https://partner.shopeemobile.com";
  private readonly partnerKey: string;

  constructor() {
    this.partnerKey = Deno.env.get("SHOPEE_PARTNER_KEY") || "";
  }

  getNewOrderStatuses(): string[] {
    return ["READY_TO_SHIP"];
  }

  private async commonQuery(
    path: string,
    credentials: PlatformCredentials,
  ): Promise<Record<string, string>> {
    const { shop_id, partner_id, access_token } = credentials;
    if (!partner_id) throw new Error("Shopee partner_id is required");
    if (!this.partnerKey) throw new Error("SHOPEE_PARTNER_KEY not configured");
    const timestamp = Math.floor(Date.now() / 1000);
    const baseString = `${partner_id}${path}${timestamp}${access_token}${shop_id}`;
    const encoder = new TextEncoder();
    const key = await crypto.subtle.importKey(
      "raw",
      encoder.encode(this.partnerKey),
      { name: "HMAC", hash: "SHA-256" },
      false,
      ["sign"],
    );
    const signature = await crypto.subtle.sign("HMAC", key, encoder.encode(baseString));
    const sign = Array.from(new Uint8Array(signature))
      .map((byte) => byte.toString(16).padStart(2, "0"))
      .join("");
    return {
      partner_id,
      timestamp: String(timestamp),
      access_token,
      shop_id,
      sign,
    };
  }

  async buildGetOrderDetailsRequest(
    credentials: PlatformCredentials,
    orderSns: string[],
  ): Promise<{ url: string; options: RequestInit }> {
    const path = "/api/v2/order/get_order_detail";
    const query = await this.commonQuery(path, credentials);
    query.order_sn_list = orderSns.join(",");
    const responseFields =
      "buyer_user_id,buyer_username,recipient_address,total_amount,estimated_shipping_fee,actual_shipping_fee,payment_method,item_list";
    query.response_optional_fields = responseFields;
    const url = `${this.baseUrl}${path}?${new URLSearchParams(query).toString()}`;
    return { url, options: { method: "GET", headers: { "Content-Type": "application/json" } } };
  }

  parseOrdersResponse(response: Record<string, unknown>): unknown[] {
    if (response.error) {
      throw new Error(`Shopee API error: ${response.error} - ${response.message}`);
    }
    const resp = response.response as { order_list?: unknown[] } | undefined;
    return resp?.order_list || [];
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
        error: "Shopee detail returned invalid JSON",
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

    let financialError: Record<string, unknown> | null = null;
    let incomeByOrderSn = new Map<string, Record<string, unknown>>();
    try {
      const path = "/api/v2/payment/get_escrow_detail_batch";
      const query = await this.commonQuery(path, credentials);
      const escrowResponse = await fetch(
        `${this.baseUrl}${path}?${new URLSearchParams(query).toString()}`,
        {
          method: "POST",
          headers: { "Content-Type": "application/json" },
          body: JSON.stringify({ order_sn_list: orderSns }),
        },
      );
      const escrowText = await escrowResponse.text();
      if (!escrowResponse.ok) {
        financialError = {
          source: "shopee_escrow_detail_batch",
          http_status: escrowResponse.status,
          message: escrowText,
        };
      } else {
        try {
          const escrowPayload = JSON.parse(escrowText) as Record<string, unknown>;
          financialError = shopeeErrorDetails(escrowPayload);
          incomeByOrderSn = new Map(
            escrowEntries(escrowPayload).flatMap((entry) => {
              const detail = (entry.escrow_detail as Record<string, unknown> | undefined) ?? entry;
              const orderSn = detail.order_sn;
              return orderSn == null ? [] : [[String(orderSn), detail] as const];
            }),
          );
        } catch {
          financialError = {
            source: "shopee_escrow_detail_batch",
            message: "Shopee escrow detail returned invalid JSON",
            response_body: escrowText,
          };
        }
      }
    } catch (err: unknown) {
      financialError = {
        source: "shopee_escrow_detail_batch",
        message: err instanceof Error ? err.message : String(err),
      };
    }

    const mergedOrders = orders.map((order): Record<string, unknown> => {
      const orderSn = String(order.order_sn ?? "");
      const escrow = incomeByOrderSn.get(orderSn);
      const errors = financialError
        ? [financialError]
        : (escrow ? [] : [{
          source: "shopee_escrow_detail_batch",
          message: "Escrow detail was unavailable for this order",
        }]);
      return {
        ...order,
        _shopee_escrow: escrow,
        _financial_api_errors: errors,
      };
    });

    const returnedOrderSns = new Set(mergedOrders.map((order) => String(order.order_sn ?? "")));
    return {
      success: mergedOrders.length > 0,
      orders: mergedOrders,
      error: mergedOrders.length > 0 ? null : "No Shopee orders fetched",
      skipped_order_sns: orderSns.filter((orderSn) => !returnedOrderSns.has(orderSn)),
    };
  }

  normalizeOrder(shopeeOrder: Record<string, unknown>, credentials: PlatformCredentials): NormalizedOrder {
    const itemList = (shopeeOrder.item_list as Record<string, unknown>[] | undefined) ?? [];
    const escrow = shopeeOrder._shopee_escrow as Record<string, unknown> | undefined;
    const orderIncome = (escrow?.order_income as Record<string, unknown> | undefined) ?? escrow;
    const incomeItems = (orderIncome?.items as Record<string, unknown>[] | undefined) ?? [];
    const incomeByIdentity = new Map<string, Record<string, unknown>>();
    for (const item of incomeItems) {
      const itemId = item.item_id != null ? String(item.item_id) : "";
      const modelId = item.model_id != null ? String(item.model_id) : "";
      if (itemId || modelId) incomeByIdentity.set(`${itemId}:${modelId}`, item);
    }
    const matchedIncomeItems = itemList.map((item, index) => {
      const key = `${item.item_id != null ? String(item.item_id) : ""}:${
        item.model_id != null ? String(item.model_id) : ""
      }`;
      return incomeByIdentity.get(key) ?? incomeItems[index];
    });

    const grossLineAmounts = itemList.map((item) => {
      const quantity = amount(item.model_quantity_purchased) || 1;
      return fromCents(toCents(amount(item.model_original_price) * quantity));
    });
    const knownLineAmounts = itemList.map((item, index) => {
      const incomeItem = matchedIncomeItems[index];
      if (!incomeItem) {
        const quantity = amount(item.model_quantity_purchased) || 1;
        return fromCents(toCents(amount(item.model_discounted_price) * quantity));
      }
      const net = amount(incomeItem.discounted_price) -
        amount(incomeItem.discount_from_voucher_seller) -
        amount(incomeItem.discount_from_voucher_shopee) -
        amount(incomeItem.discount_from_coin);
      return fromCents(Math.max(0, toCents(net)));
    });
    const knownLinesTotal = fromCents(knownLineAmounts.reduce((sum, value) => sum + toCents(value), 0));
    const detailGross = fromCents(grossLineAmounts.reduce((sum, value) => sum + toCents(value), 0));
    const incomeGross = optionalAmount(orderIncome, ["order_original_price", "original_price"]);
    const grossAmount = fromCents(toCents(incomeGross ?? detailGross));
    const buyerTotal = optionalAmount(orderIncome, ["buyer_total_amount"]);
    const buyerPaidShipping = optionalAmount(orderIncome, ["buyer_paid_shipping_fee"]);
    const sellerDiscount = optionalAmount(orderIncome, ["seller_discount", "order_seller_discount"]) ?? 0;
    const voucherSeller = optionalAmount(orderIncome, ["voucher_from_seller"]) ?? 0;
    const voucherShopee = optionalAmount(orderIncome, ["voucher_from_shopee"]) ?? 0;
    const coins = optionalAmount(orderIncome, ["coins"]) ?? 0;
    const financialTarget = buyerTotal != null
      ? buyerTotal - (buyerPaidShipping ?? 0)
      : orderIncome
      ? grossAmount - sellerDiscount - voucherSeller - voucherShopee - coins
      : knownLinesTotal;
    const lineAmounts = allocateToTarget(knownLineAmounts, financialTarget);
    const earnableAmount = fromCents(lineAmounts.reduce((sum, value) => sum + toCents(value), 0));
    const shippingFee = fromCents(toCents(
      buyerPaidShipping ??
        amount(shopeeOrder.actual_shipping_fee ?? shopeeOrder.estimated_shipping_fee),
    ));
    const errors = Array.isArray(shopeeOrder._financial_api_errors)
      ? shopeeOrder._financial_api_errors as unknown[]
      : [];
    const items: NormalizedOrderItem[] = itemList.map((item, index) => {
      const quantity = amount(item.model_quantity_purchased) || 1;
      const lineTotal = lineAmounts[index] ?? 0;
      const knownLineTotal = knownLineAmounts[index] ?? 0;
      const incomeItem = matchedIncomeItems[index];
      return {
        platform_item_id: `${item.item_id}_${item.model_id != null && String(item.model_id) !== "" ? item.model_id : index}`,
        variant_id: item.model_id != null ? String(item.model_id) : undefined,
        platform_sku: item.model_sku != null
          ? String(item.model_sku)
          : (item.item_sku != null ? String(item.item_sku) : undefined),
        item_name: String(item.item_name || ""),
        variant_name: item.model_name != null ? String(item.model_name) : undefined,
        quantity,
        currency: String(shopeeOrder.currency || "THB"),
        unit_price: amount(item.model_original_price),
        discount_amount: fromCents(toCents((grossLineAmounts[index] ?? 0) - lineTotal)),
        line_total: lineTotal,
        earnable_amount: lineTotal,
        financial_details: {
          source: incomeItem ? "shopee_escrow_detail" : "shopee_order_detail",
          gross_merchandise_amount: grossLineAmounts[index] ?? 0,
          pre_allocation_net_amount: knownLineTotal,
          allocated_bill_discount: fromCents(toCents(knownLineTotal - lineTotal)),
          discounted_price: incomeItem?.discounted_price ?? null,
          discount_from_voucher_seller: incomeItem?.discount_from_voucher_seller ?? null,
          discount_from_voucher_shopee: incomeItem?.discount_from_voucher_shopee ?? null,
          discount_from_coin: incomeItem?.discount_from_coin ?? null,
        },
      };
    });
    const addr = shopeeOrder.recipient_address as Record<string, unknown> | undefined;
    const fallbackFinal = optionalAmount(shopeeOrder, ["total_amount"]) ?? (earnableAmount + shippingFee);
    const finalAmount = fromCents(toCents(buyerTotal ?? fallbackFinal));
    return {
      merchant_id: credentials.merchant_id,
      platform: "shopee",
      shop_id: credentials.shop_id,
      order_sn: String(shopeeOrder.order_sn),
      external_user_id: shopeeOrder.buyer_user_id != null ? String(shopeeOrder.buyer_user_id) : undefined,
      buyer_username: shopeeOrder.buyer_username != null ? String(shopeeOrder.buyer_username) : undefined,
      buyer_phone: addr?.phone != null ? String(addr.phone) : undefined,
      buyer_email: addr?.email != null ? String(addr.email) : undefined,
      order_status: String(shopeeOrder.order_status),
      transaction_date: new Date(Number(shopeeOrder.create_time) * 1000).toISOString(),
      update_time: shopeeOrder.update_time
        ? new Date(Number(shopeeOrder.update_time) * 1000).toISOString()
        : new Date().toISOString(),
      currency: String(shopeeOrder.currency || "THB"),
      total_amount: grossAmount,
      shipping_fee: shippingFee,
      discount_amount: fromCents(toCents(grossAmount - earnableAmount)),
      tax_amount: 0,
      final_amount: finalAmount,
      earnable_amount: earnableAmount,
      financial_details: {
        source: orderIncome ? "shopee_escrow_detail_batch" : "shopee_order_detail_fallback",
        gross_merchandise_amount: grossAmount,
        net_merchandise_target: fromCents(toCents(financialTarget)),
        known_line_net_total: knownLinesTotal,
        buyer_total_amount: buyerTotal ?? null,
        buyer_paid_shipping_fee: buyerPaidShipping ?? null,
        seller_discount: sellerDiscount,
        voucher_from_seller: voucherSeller,
        voucher_from_shopee: voucherShopee,
        coins,
        api_errors: errors,
      },
      payment_method: shopeeOrder.payment_method != null ? String(shopeeOrder.payment_method) : undefined,
      payment_status: shopeeOrder.pay_time ? "paid" : "unpaid",
      items,
    };
  }
}
