# CS AI — Platform Adapter Implementation Plan

> **Purpose:** Build the MCP tool handler (routing layer) and per-platform adapters on cs-ai-service (Render) so the AI can actually call marketplace APIs for orders, products, promotions, and actions.
>
> **Prerequisite (done):** System registry (18 CS tools), per-merchant config, compiled procedures with tool references, entity extractors for platform detection — all deployed to Supabase.

---

## Architecture Recap

```
AI decides tool call + passes platform param
        │
        ▼
┌─ MCP Tool Handler (cs-ai-service /mcp) ─────────────────────┐
│  1. Validate: cs_action_config constraints for merchant      │
│  2. Credentials: merchant_credentials for platform           │
│  3. Route: adapters[platform].method()                       │
│  4. Log: cs_conversation_events                              │
└───────────────────────────┬──────────────────────────────────┘
                            │
        ┌───────────────────┼───────────────────┐
        ▼                   ▼                   ▼
   BigCommerce         Shopee              Shopify        ... etc
   adapter             adapter             adapter
   (V2/V3 REST)        (Open Platform)     (Admin REST)
```

---

## Phase 1: MCP Tool Handler (platform-agnostic routing layer)

**What:** Generic code that ALL tools share. Build once, every tool uses it.

### 1a. Tool Registration

Register all 18 CS tools as MCP tools on cs-ai-service. Each tool:
- Declares its input schema (from `workflow_action_type_config.applicable_variables`)
- Is available to the AI agent as a callable function

### 1b. Constraint Validator

Before executing any tool, check `cs_action_config` for the merchant:
- `is_enabled` — tool must be active
- `action_constraints` — check guardrails:
  - `blocked_statuses` — reject if order status is in blocked list
  - `max_amount` — reject if amount exceeds limit
  - `requires_confirmation` — return `needs_confirmation` to AI instead of executing
  - `allowed_platforms` — reject if platform not in allowed list (e.g., `create_order` only for shopify/bigcom/woocommerce)

### 1c. Credential Resolver

Read platform credentials from Supabase:
```sql
SELECT credentials FROM merchant_credentials
WHERE merchant_id = :mid AND service_name = :platform AND is_active = true
```

Each platform stores different credential shapes:
- BigCommerce: `{ store_hash, access_token, client_id }`
- Shopee: `{ partner_id, partner_key, shop_id, access_token, refresh_token }`
- Shopify: `{ shop_domain, access_token }`
- Lazada: `{ app_key, app_secret, access_token, refresh_token, country }`
- TikTok: `{ app_key, app_secret, access_token, shop_cipher }`

### 1d. Adapter Router

Simple lookup:
```typescript
const adapters = { bigcommerce, shopee, shopify, lazada, tiktok, woocommerce };
const adapter = adapters[platform];
if (!adapter) return { error: `Platform ${platform} not supported` };
```

### 1e. Action Audit Logger

After every tool execution, insert event:
```sql
INSERT INTO cs_conversation_events (conversation_id, event_type, event_data)
VALUES (:conv_id, 'action_executed', { tool, platform, params, result, latency_ms })
```

---

## Phase 2: Platform Adapters

Each adapter implements a standard interface. Not every platform supports every operation.

### Adapter Interface

```typescript
interface PlatformAdapter {
  // Data tools
  lookupOrder(creds, orderNumber): Promise<OrderResult>
  getRecentOrders(creds, customerId?, limit?): Promise<OrderListResult>
  getOrderShipping(creds, orderNumber): Promise<ShippingResult>
  searchProducts(creds, query, filters?): Promise<ProductListResult>
  checkProductStock(creds, productName): Promise<StockResult>
  getProductPrice(creds, productName): Promise<PriceResult>
  checkPromotion(creds, promoCode?, productId?): Promise<PromoResult>
  recommendProducts(creds, context, filters?): Promise<ProductListResult>

  // Action tools
  cancelOrder(creds, orderNumber, reason): Promise<ActionResult>
  processRefund(creds, orderNumber, type, amount?, reason): Promise<ActionResult>
  createOrder(creds, items, shippingAddress, customerEmail, notes?): Promise<ActionResult>
  updateOrder(creds, orderNumber, updates): Promise<ActionResult>
  applyCoupon(creds, orderNumber?, couponCode): Promise<ActionResult>
  createVoucher(creds, amount, reason): Promise<ActionResult>

  // Capability check
  supports(action: string): boolean
}
```

### 2a. BigCommerce Adapter

**API Docs:** https://developer.bigcommerce.com/docs/rest-management

**Auth pattern:** `X-Auth-Token` header, `store_hash` in URL path.

**Base URL:** `https://api.bigcommerce.com/stores/{store_hash}`

| Tool | BigCommerce API | Method | Endpoint | Key notes |
|---|---|---|---|---|
| `lookupOrder` | Orders V2 | GET | `/v2/orders/{id}` + `/v2/orders/{id}/products` | Returns order + line items. Need two calls. |
| `getRecentOrders` | Orders V2 | GET | `/v2/orders?customer_id={id}&sort=date_created:desc&limit={n}` | Filter by customer_id from platform identity |
| `getOrderShipping` | Orders V2 | GET | `/v2/orders/{id}/shipping_addresses` + `/v2/orders/{id}/shipments` | Shipments have tracking_number + carrier |
| `searchProducts` | Catalog V3 | GET | `/v3/catalog/products?keyword={q}&include=variants,images` | Supports category, brand, price filters |
| `checkProductStock` | Catalog V3 | GET | `/v3/catalog/products?keyword={name}&include=variants` | Check `inventory_level` on product/variant |
| `getProductPrice` | Catalog V3 | GET | `/v3/catalog/products?keyword={name}` | `price`, `sale_price`, `retail_price` |
| `checkPromotion` | Promotions V3 + Coupons V2 | GET | `/v3/promotions` + `/v2/coupons?code={code}` | Promotions = automatic rules. Coupons = code-based. |
| `recommendProducts` | Catalog V3 | GET | `/v3/catalog/products?categories:in={ids}&is_visible=true&sort=total_sold` | Filter by category/brand + sort by popularity. AI reasons over results. |
| `cancelOrder` | Orders V2 | PUT | `/v2/orders/{id}` body: `{"status_id": 5}` | status_id 5 = Cancelled. Check current status first. |
| `processRefund` | Orders V3 | POST | `/v3/orders/{id}/payment_actions/refunds` | Body: items array or amount. V3 only. |
| `createOrder` | Orders V2 | POST | `/v2/orders` | Requires products array, billing_address. Can include customer_id or create guest. |
| `updateOrder` | Orders V2 | PUT | `/v2/orders/{id}` | Can update: staff_notes, customer_message, shipping_addresses (separate endpoint) |
| `applyCoupon` | Coupons V2 | POST | `/v2/coupons` or manual discount via order update | BigCommerce coupons are store-level, not per-order post-creation. May need to create a manual discount. |
| `createVoucher` | Coupons V2 | POST | `/v2/coupons` | Create coupon with type, amount, code, expiry |

**BigCommerce-specific considerations:**
- Rate limit: 150 requests/30 seconds (V2), varies by plan
- V2 orders use numeric IDs, not order_sn — need to search by `?id={number}` or custom field
- Refunds are V3 only, orders are primarily V2 — two auth/URL patterns
- Order status is numeric (0=Incomplete, 1=Pending, 2=Shipped, 5=Cancelled, 10=Completed, 11=Awaiting Payment, 12=Awaiting Shipment)
- Token refresh is NOT needed — BigCommerce uses long-lived API tokens (no OAuth refresh flow for server-to-server)

**⚠️ Must study before coding:**
- [ ] Exact order creation payload (products, billing, customer)
- [ ] Refund payload structure (items-based vs amount-based)
- [ ] How to look up order by order number vs order ID (store may use custom order number)
- [ ] Multi-storefront handling (BigCommerce supports multiple storefronts per store)
- [ ] Webhook payload format for order status changes
- [ ] Coupon creation restrictions (max usage, min purchase, category restrictions)
- [ ] Pagination for product search (cursor vs page-based)

### 2b. Shopee Adapter

**API Docs:** https://open.shopee.com/documents

**Auth pattern:** `partner_id` + HMAC-SHA256 signature per request + `access_token` + `shop_id`. Token refresh required (expires ~4 hours).

**Base URL:** `https://partner.shopeemobile.com/api/v2`

| Tool | Shopee API | Method | Endpoint |
|---|---|---|---|
| `lookupOrder` | GET | `/order/get_order_detail` | Params: order_sn_list |
| `getRecentOrders` | GET | `/order/get_order_list` | Params: time_range_field, time_from, time_to |
| `getOrderShipping` | GET | `/logistics/get_tracking_info` | Params: order_sn |
| `searchProducts` | GET | `/product/get_item_list` + `/product/get_item_base_info` | Two calls: list then detail |
| `checkProductStock` | GET | `/product/get_model_list` | Variant-level stock |
| `getProductPrice` | GET | `/product/get_model_list` | Variant-level pricing |
| `checkPromotion` | GET | `/voucher/get_voucher_list` | Shop voucher list |
| `cancelOrder` | POST | `/order/cancel_order` | Only if status allows |
| `processRefund` | N/A — Shopee handles returns/refunds through their own dispute system | Seller can only accept/reject |
| `createOrder` | ❌ Not supported | Marketplace controls order creation |
| `updateOrder` | Limited — can update logistics only | |
| `createVoucher` | POST | `/voucher/add_voucher` | Shop voucher |

**Shopee-specific considerations:**
- Token refresh every ~4 hours via `/auth/token/get` (refresh_token)
- Every request needs HMAC-SHA256 signature: `partner_id + path + timestamp + access_token + shop_id`
- Rate limits per API call type (typically 10-20 req/s)
- Cannot create orders or process refunds directly — marketplace controls these
- Order status strings: UNPAID, READY_TO_SHIP, SHIPPED, TO_CONFIRM_RECEIVE, COMPLETED, CANCELLED, IN_CANCEL, TO_RETURN

**⚠️ Must study before coding:**
- [ ] Exact signature generation algorithm (common source of bugs)
- [ ] Token refresh flow and storage (update merchant_credentials on refresh)
- [ ] Which API version (currently v2.0) and regional variations
- [ ] Order cancellation restrictions per status
- [ ] Voucher creation params (discount_type, min_basket_price, usage_quantity)

### 2c. Shopify Adapter

**API Docs:** https://shopify.dev/docs/api/admin-rest

**Auth pattern:** `X-Shopify-Access-Token` header. Token is long-lived (app install grant).

**Base URL:** `https://{shop_domain}/admin/api/{version}`

| Tool | Shopify API | Method | Endpoint |
|---|---|---|---|
| `lookupOrder` | GET | `/orders/{id}.json` | Can also search by `name` (order #) |
| `getRecentOrders` | GET | `/orders.json?customer_id={id}&limit={n}&status=any` | |
| `getOrderShipping` | GET | `/orders/{id}/fulfillments.json` | Tracking from fulfillments |
| `searchProducts` | GET | `/products.json?title={q}` or GraphQL | REST is limited, GraphQL is better for search |
| `checkProductStock` | GET | `/inventory_levels.json?inventory_item_ids={ids}` | Need product → variant → inventory_item mapping |
| `getProductPrice` | GET | `/products/{id}.json` | variant.price, variant.compare_at_price |
| `checkPromotion` | GET | `/price_rules.json` + `/discount_codes.json` | Price rules = promotions. Discount codes attached to rules. |
| `cancelOrder` | POST | `/orders/{id}/cancel.json` | Body: {reason, email, restock} |
| `processRefund` | POST | `/orders/{id}/refunds.json` | Calculate first, then create |
| `createOrder` | POST | `/orders.json` | Full order creation supported |
| `updateOrder` | PUT | `/orders/{id}.json` | Limited: tags, notes, shipping_address |
| `applyCoupon` | POST | `/price_rules/{id}/discount_codes.json` | Create discount code |
| `createVoucher` | POST | `/price_rules.json` + `/discount_codes.json` | Two calls: rule then code |

**Shopify-specific considerations:**
- API versioning by date (e.g., `2024-10`). Must specify version.
- Rate limit: 2 requests/second (standard), bucket-based with leak
- Refund requires a calculate call first (`POST /orders/{id}/refunds/calculate.json`)
- Product search via REST is basic — GraphQL `products(query: "title:X")` is more powerful
- Order number (e.g., #1001) ≠ order ID — need to search `GET /orders.json?name=%231001`

**⚠️ Must study before coding:**
- [ ] API version to target (latest stable)
- [ ] Refund calculate → create two-step flow
- [ ] GraphQL vs REST trade-offs for product search
- [ ] Fulfillment/shipping data structure
- [ ] Discount code creation restrictions

### 2d. Lazada Adapter

**API Docs:** https://open.lazada.com/apps/doc

**Auth pattern:** `app_key` + HMAC-SHA256 signature + `access_token`. Token refresh required. Different base URL per country.

**Base URLs:** `https://api.lazada.{tld}/rest` (tld = co.th, sg, com.my, etc.)

| Tool | Lazada API | Method | Endpoint |
|---|---|---|---|
| `lookupOrder` | GET | `/order/get` | Params: order_id |
| `getRecentOrders` | GET | `/orders/get` | Params: created_after, sort_by |
| `getOrderShipping` | GET | `/order/document/get` | AWB/tracking info |
| `cancelOrder` | POST | `/order/cancel` | Params: order_item_id, reason_id |
| `processRefund` | Marketplace-controlled | Seller accepts/rejects return | |
| `createOrder` | ❌ Not supported | Marketplace |
| `checkPromotion` | GET | `/promotion/seller/get` | Seller promotions |
| `createVoucher` | POST | `/promotion/seller/create` | Seller voucher |

**⚠️ Must study before coding:**
- [ ] Signature generation (different from Shopee)
- [ ] Country-specific base URLs and token endpoints
- [ ] Order cancellation is per-item, not per-order
- [ ] Token refresh flow

### 2e. TikTok Shop Adapter

**API Docs:** https://partner.tiktokshop.com/docv2

**Auth pattern:** `app_key` + `app_secret` + `access_token` + `shop_cipher` for multi-shop. HMAC signature.

**Base URL:** `https://open-api.tiktokglobalshop.com`

| Tool | TikTok API | Method | Endpoint |
|---|---|---|---|
| `lookupOrder` | GET | `/order/202309/orders` | Params: order_id |
| `getRecentOrders` | POST | `/order/202309/orders/search` | Body: filters, sort |
| `getOrderShipping` | GET | `/fulfillment/202309/orders/{id}/shipping_services` | |
| `cancelOrder` | POST | `/order/202309/orders/{id}/cancel` | |
| `processRefund` | Marketplace-controlled | Seller accepts/rejects | |
| `createOrder` | ❌ Not supported | Marketplace |
| `searchProducts` | POST | `/product/202309/products/search` | |
| `checkProductStock` | GET | `/product/202309/products/{id}` | |

**⚠️ Must study before coding:**
- [ ] API version date in URL path (e.g., 202309)
- [ ] shop_cipher for multi-shop routing
- [ ] HMAC signature generation
- [ ] Token refresh flow

---

## Phase 3: Token Refresh Service

Shopee, Lazada, and TikTok require periodic token refresh. Need a background job:

- **Cron or Inngest scheduled function** that checks `merchant_credentials.expires_at`
- When token is near expiry → call platform refresh endpoint → update `credentials` JSONB + `expires_at`
- Log refresh success/failure to `health_status` column
- Run every ~1 hour for safety margin

BigCommerce and Shopify use long-lived tokens — no refresh needed.

Note: `marketplace-token-refresh` edge function already exists. Need to verify if it covers all platforms or only some.

---

## Implementation Order

| Priority | What | Why first |
|---|---|---|
| 1 | MCP tool handler (Phase 1) | Shared by all platforms. Build once. |
| 2 | BigCommerce adapter | Customer's current platform. Full API (create, cancel, refund, products, promos). |
| 3 | Shopify adapter | Full API support. Many shared concepts with BigCommerce. |
| 4 | Shopee adapter | Largest order volume (23K orders). More restrictive API (no create order). Signature auth is complex. |
| 5 | TikTok adapter | Second largest volume (1.1K orders). Similar restrictions to Shopee. |
| 6 | Lazada adapter | Per-item cancellation adds complexity. |
| 7 | WooCommerce adapter | If needed — WooCommerce REST API is straightforward. |

---

## Platform Doc Study Checklist

Before coding each adapter, read and document:

- [ ] **Auth flow** — How to authenticate, sign requests, refresh tokens
- [ ] **Order model** — Statuses, status transitions, what's cancellable/refundable
- [ ] **Order lookup** — By ID vs by order number vs by customer
- [ ] **Cancellation rules** — Which statuses allow cancel, required params, is it per-order or per-item
- [ ] **Refund flow** — Who controls it (seller or marketplace), full vs partial, calculate-then-execute
- [ ] **Product catalog** — Search capabilities, pagination, variant model
- [ ] **Promotions/Coupons** — Types, creation params, restrictions
- [ ] **Rate limits** — Per endpoint, retry strategy, backoff
- [ ] **Error codes** — Standard error format, how to surface errors to AI
- [ ] **Webhook events** — For order status changes (to keep state current if needed)

This checklist becomes the first task for each adapter: read the platform docs and fill it in before writing code.
