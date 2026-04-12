import type { PlatformAdapter, OrderResult, OrderItem, ActionResult } from "./types.js";

const STATUS_MAP: Record<number, string> = {
  0: "incomplete", 1: "pending", 2: "shipped", 3: "partially_shipped",
  4: "refunded", 5: "cancelled", 6: "declined", 7: "awaiting_payment",
  8: "awaiting_pickup", 9: "awaiting_shipment", 10: "completed",
  11: "awaiting_fulfillment", 12: "manual_verification_required",
  13: "disputed", 14: "partially_refunded",
};

const NON_CANCELLABLE = [2, 3, 4, 5, 10]; // shipped, partially_shipped, refunded, cancelled, completed

async function bc(creds: any, method: string, path: string, body?: unknown) {
  const token = creds.access_token || creds.x_auth_token;
  const url = `https://api.bigcommerce.com/stores/${creds.store_hash}${path}`;
  const res = await fetch(url, {
    method,
    headers: { "X-Auth-Token": token, "Content-Type": "application/json", Accept: "application/json" },
    ...(body ? { body: JSON.stringify(body) } : {}),
  });
  let data: any;
  try { data = await res.json(); } catch { data = null; }
  return { ok: res.ok, status: res.status, data };
}

function toOrder(o: any, items: any[] = []): OrderResult {
  return {
    found: true, order_id: String(o.id), order_number: String(o.id), platform: "bigcommerce",
    status: STATUS_MAP[o.status_id] ?? "unknown", status_raw: String(o.status_id),
    customer: {
      name: [o.billing_address?.first_name, o.billing_address?.last_name].filter(Boolean).join(" "),
      email: o.billing_address?.email, phone: o.billing_address?.phone,
    },
    items: items.map((i: any): OrderItem => ({
      item_id: String(i.id), name: i.name, sku: i.sku,
      variant_name: i.product_options?.map((opt: any) => opt.display_value).join(", "),
      quantity: i.quantity, unit_price: parseFloat(i.base_price), line_total: parseFloat(i.base_total),
    })),
    amounts: {
      subtotal: parseFloat(o.subtotal_ex_tax ?? "0"), shipping: parseFloat(o.shipping_cost_ex_tax ?? "0"),
      discount: parseFloat(o.discount_amount ?? "0"), tax: parseFloat(o.total_tax ?? "0"),
      total: parseFloat(o.total_inc_tax ?? "0"), currency: o.currency_code ?? "USD",
    },
    dates: { created_at: o.date_created, updated_at: o.date_modified, shipped_at: o.date_shipped || undefined },
    payment_method: o.payment_method, notes: o.staff_notes || undefined,
  };
}

export const bigcommerce: PlatformAdapter = {
  platform: "bigcommerce",
  supports() { return true; },

  async lookupOrder(creds, orderNumber) {
    const orderRes = await bc(creds, "GET", `/v2/orders/${orderNumber}`);
    if (!orderRes.ok) return { found: false } as any;
    const itemsRes = await bc(creds, "GET", `/v2/orders/${orderNumber}/products`);
    return toOrder(orderRes.data, itemsRes.data ?? []);
  },

  async getRecentOrders(creds, limit = 5) {
    const res = await bc(creds, "GET", `/v2/orders?limit=${limit}&sort=date_created:desc`);
    if (!res.ok) return { orders: [], total_count: 0 };
    return { orders: (res.data ?? []).map((o: any) => toOrder(o)), total_count: (res.data ?? []).length };
  },

  async getOrderShipping(creds, orderNumber) {
    const [addrRes, shipRes] = await Promise.all([
      bc(creds, "GET", `/v2/orders/${orderNumber}/shipping_addresses`),
      bc(creds, "GET", `/v2/orders/${orderNumber}/shipments`),
    ]);
    const addr = addrRes.data?.[0] ?? {};
    return {
      order_number: orderNumber,
      shipping_address: {
        name: [addr.first_name, addr.last_name].filter(Boolean).join(" "),
        street_1: addr.street_1 ?? "", street_2: addr.street_2 || undefined,
        city: addr.city ?? "", state: addr.state ?? "", zip: addr.zip ?? "",
        country: addr.country ?? "", phone: addr.phone || undefined,
      },
      shipments: (shipRes.data ?? []).map((s: any) => ({
        tracking_number: s.tracking_number ?? "", carrier: s.shipping_provider ?? "",
        shipped_at: s.date_created, tracking_url: s.tracking_link || undefined,
      })),
    };
  },

  async searchProducts(creds, query, filters) {
    let path = `/v3/catalog/products?keyword=${encodeURIComponent(query)}&include=variants,images&limit=10`;
    if (filters) {
      if (filters.category) path += `&categories:in=${filters.category}`;
      if (filters.brand) path += `&brand_id=${filters.brand}`;
      if (filters.price_min) path += `&price:min=${filters.price_min}`;
      if (filters.price_max) path += `&price:max=${filters.price_max}`;
      if (filters.in_stock_only) path += `&availability=available`;
    }
    const res = await bc(creds, "GET", path);
    if (!res.ok) return { products: [], total_count: 0 };
    const products = (res.data?.data ?? []).map((p: any) => ({
      product_id: String(p.id), name: p.name, sku: p.sku,
      description: p.description?.replace(/<[^>]*>/g, "").slice(0, 200),
      price: p.price, sale_price: p.sale_price || undefined, currency: p.currency || "THB",
      in_stock: p.availability === "available" && p.inventory_level > 0,
      stock_level: p.inventory_level, image_url: p.images?.[0]?.url_standard,
      variants: (p.variants ?? []).map((v: any) => ({
        variant_id: String(v.id), name: v.option_values?.map((ov: any) => ov.label).join(", ") ?? String(v.id),
        sku: v.sku, price: v.price ?? p.price, stock_level: v.inventory_level, in_stock: v.inventory_level > 0,
      })),
    }));
    return { products, total_count: res.data?.meta?.pagination?.total ?? products.length };
  },

  async checkProductStock(creds, productName) {
    const result = await this.searchProducts(creds, productName);
    const p = result.products[0];
    if (!p) return { product_name: productName, in_stock: false };
    return { product_name: p.name, in_stock: p.in_stock, stock_level: p.stock_level, variants: p.variants?.map(v => ({ name: v.name, in_stock: v.in_stock, stock_level: v.stock_level })) };
  },

  async getProductPrice(creds, productName) {
    const result = await this.searchProducts(creds, productName);
    const p = result.products[0];
    if (!p) return { product_name: productName, price: 0, currency: "THB" };
    return { product_name: p.name, price: p.price, sale_price: p.sale_price, currency: p.currency, variants: p.variants?.map(v => ({ name: v.name, price: v.price })) };
  },

  async checkPromotion(creds, promoCode) {
    const [promoRes, couponRes] = await Promise.all([
      bc(creds, "GET", "/v3/promotions?status=enabled&limit=20"),
      bc(creds, "GET", promoCode ? `/v2/coupons?code=${encodeURIComponent(promoCode)}` : "/v2/coupons?limit=50"),
    ]);
    return {
      promotions: (promoRes.data?.data ?? []).map((p: any) => ({
        id: String(p.id), name: p.name, type: p.rules?.[0]?.action?.type ?? "unknown",
        start_date: p.start_date, end_date: p.end_date, is_active: p.status === "enabled",
      })),
      coupons: (couponRes.data ?? []).map((c: any) => ({
        id: String(c.id), code: c.code, type: c.type, value: parseFloat(c.amount),
        min_purchase: c.min_purchase ? parseFloat(c.min_purchase) : undefined,
        max_uses: c.max_uses, current_uses: c.current_uses, is_active: c.enabled,
      })),
    };
  },

  async cancelOrder(creds, orderNumber, reason) {
    const current = await bc(creds, "GET", `/v2/orders/${orderNumber}`);
    if (!current.ok) return { success: false, message: "Order not found", error: `Order ${orderNumber} not found` };
    if (NON_CANCELLABLE.includes(current.data.status_id)) {
      return { success: false, message: `Cannot cancel — order is ${STATUS_MAP[current.data.status_id]}`, error: `Status ${STATUS_MAP[current.data.status_id]} blocks cancellation` };
    }
    const res = await bc(creds, "PUT", `/v2/orders/${orderNumber}`, { status_id: 5, staff_notes: `Cancelled by AI: ${reason}` });
    return { success: res.ok, message: res.ok ? `Order ${orderNumber} cancelled` : "Cancel failed", error: res.ok ? undefined : JSON.stringify(res.data), data: res.ok ? { order_id: orderNumber, new_status: "cancelled" } : undefined };
  },

  async processRefund(creds, orderNumber, refundType, amount, reason) {
    const order = await bc(creds, "GET", `/v2/orders/${orderNumber}`);
    if (!order.ok) return { success: false, message: "Order not found", error: `Order ${orderNumber} not found` };
    const refundAmount = refundType === "full" ? parseFloat(order.data.total_inc_tax) : (amount ?? 0);
    if (refundAmount <= 0) return { success: false, message: "Invalid refund amount", error: "Amount must be > 0" };
    const itemsRes = await bc(creds, "GET", `/v2/orders/${orderNumber}/products`);
    const payload: any = { reason: reason ?? "Customer requested refund" };
    if (refundType === "full") {
      payload.items = (itemsRes.data ?? []).map((i: any) => ({ item_id: i.id, item_type: "PRODUCT", quantity: i.quantity, reason: reason ?? "Full refund" }));
    } else {
      payload.items = [{ item_type: "ORDER", reason: reason ?? "Partial refund" }];
      payload.payments = [{ provider_id: "custom", amount: refundAmount, offline: true }];
    }
    const res = await bc(creds, "POST", `/v3/orders/${orderNumber}/payment_actions/refunds`, payload);
    return { success: res.ok, message: res.ok ? `Refund of ${refundAmount} processed` : "Refund failed", error: res.ok ? undefined : JSON.stringify(res.data), data: res.ok ? { order_id: orderNumber, refund_amount: refundAmount, type: refundType } : undefined };
  },

  async createOrder(creds, items, shippingAddress, customerEmail, notes) {
    const parsedItems = typeof items === "string" ? JSON.parse(items) : items;
    const parsedAddr = typeof shippingAddress === "string" ? JSON.parse(shippingAddress) : shippingAddress;
    const res = await bc(creds, "POST", "/v2/orders", {
      billing_address: { ...parsedAddr, email: customerEmail },
      shipping_addresses: [{ ...parsedAddr, email: customerEmail }],
      products: parsedItems.map((i: any) => ({ product_id: parseInt(i.product_id), quantity: i.quantity, ...(i.variant_id ? { variant_id: parseInt(i.variant_id) } : {}) })),
      staff_notes: notes ?? "Created by AI agent", status_id: 11,
    });
    return { success: res.ok, message: res.ok ? `Order created: #${res.data?.id}` : "Order creation failed", error: res.ok ? undefined : JSON.stringify(res.data), data: res.ok ? { order_id: String(res.data.id) } : undefined };
  },

  async updateOrder(creds, orderNumber, updates) {
    const parsed = typeof updates === "string" ? JSON.parse(updates) : updates;
    const payload: Record<string, unknown> = {};
    if (parsed.staff_notes) payload.staff_notes = parsed.staff_notes;
    if (parsed.customer_message) payload.customer_message = parsed.customer_message;
    if (parsed.shipping_address) {
      const addrRes = await bc(creds, "GET", `/v2/orders/${orderNumber}/shipping_addresses`);
      const addrId = addrRes.data?.[0]?.id;
      if (addrId) await bc(creds, "PUT", `/v2/orders/${orderNumber}/shipping_addresses/${addrId}`, parsed.shipping_address);
    }
    if (Object.keys(payload).length > 0) {
      const res = await bc(creds, "PUT", `/v2/orders/${orderNumber}`, payload);
      return { success: res.ok, message: res.ok ? `Order ${orderNumber} updated` : "Update failed", error: res.ok ? undefined : JSON.stringify(res.data) };
    }
    return { success: true, message: `Order ${orderNumber} updated` };
  },

  async applyCoupon(creds, couponCode, orderNumber) {
    const couponRes = await bc(creds, "GET", `/v2/coupons?code=${encodeURIComponent(couponCode)}`);
    const coupon = couponRes.data?.[0];
    if (!coupon) return { success: false, message: `Coupon ${couponCode} not found`, error: "Invalid coupon code" };
    if (!coupon.enabled) return { success: false, message: `Coupon ${couponCode} is disabled`, error: "Coupon not active" };
    if (coupon.max_uses && coupon.current_uses >= coupon.max_uses) return { success: false, message: `Coupon ${couponCode} usage limit reached`, error: "Max uses exceeded" };
    return { success: true, message: `Coupon ${couponCode} is valid (${coupon.type}: ${coupon.amount}). Customer can use at checkout.`, data: { code: coupon.code, type: coupon.type, value: parseFloat(coupon.amount) } };
  },

  async createVoucher(creds, amount, reason) {
    const code = `CS-${Date.now().toString(36).toUpperCase()}`;
    const res = await bc(creds, "POST", "/v2/coupons", {
      name: `CS Goodwill - ${reason}`, type: "per_total_discount", code, amount: String(amount),
      enabled: true, max_uses: 1, max_uses_per_customer: 1,
      expires: new Date(Date.now() + 30 * 24 * 60 * 60 * 1000).toISOString(),
    });
    return { success: res.ok, message: res.ok ? `Voucher created: ${code} (${amount} off)` : "Voucher creation failed", error: res.ok ? undefined : JSON.stringify(res.data), data: res.ok ? { code, amount } : undefined };
  },
};
