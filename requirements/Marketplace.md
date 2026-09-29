# Marketplace (Shopee / Lazada / TikTok)

SEA marketplace orders land in a claimable ledger; members (or admins on their behalf) claim into the purchase ledger and earn. Shopify and BigCommerce use the same claim helpers but different ingest surfaces.

Owner surfaces: loyalty-admin (Marketplace Settings, ops), loyalty-user (Earn → marketplace), CS (marketplace chat credentials — separate scope)

## Concept

Marketplaces are the online third-party channel: the brand knows what it sold but not to whom, because the buyer relationship belongs to the platform. Claiming points is the lure that converts an anonymous marketplace buyer into a registered member — the member signs up, enters the order number, and the brand gains both the purchase history and a direct relationship. In the channel strategy, marketplaces usually bring the first order (acquisition); earn rates and rewards then steer repeat orders to the brand's own higher-margin channels.

Mechanically, merchants connect Shopee, Lazada, or TikTok Shop so the CRM learns every order before anyone claims it. The platform pushes lightweight status events; the CRM enriches each order with platform API detail and stores it as an unowned order (order number, buyer username, amounts, lines) — at that point the system cannot tie it to a member. A **claim** makes that link; only then do points or tickets flow. Claiming is deliberately member-initiated rather than auto-awarded: points go only to buyers who care enough to claim, instead of being given away to buyers who never notice them.

**Order ledger row** — One marketplace order per merchant: buyer hints, amounts, platform-native status, normalized status, and a **claim sync flag** (false until a purchase row exists).

**Claim** — Promotes one ledger row into the purchase ledger (+ line items), sets the sync flag, optionally runs earn, and may attach the buyer’s platform id to the member profile. Shopee/Lazada/TikTok claims are **member-initiated** (or admin-assisted). Shopify can auto-claim when the buyer matches (see hub doc).

**Buyer link** — The platform buyer id from a member's first successful claim, stamped on the member profile per platform. Later orders from the same buyer are recognisable without an order number, so they can be offered to the member as one-tap claims — backend lookup live, member UI (planned).

**Claim threshold** — Per platform, the earliest order status at which a claim succeeds. Earlier (e.g. shipped/delivered) gives members points sooner, and a refunded order's points can still be reversed by cancelling its purchase; later (completed — accepted or past the refund window) blocks the buy → redeem points → return abuse, where no balance is left to reverse. The recommended default is delivered: abusers are few and can be found and frozen.

**Shop credential** — OAuth token row keyed by platform `service_name` and `external_id` equal to the webhook shop/seller id. Order ingest ignores rows whose `scope` includes CS (marketplace IM apps).

**Ingest (live)** — Webhook edge normalizes the push, updates status on any existing ledger row immediately, then emits `marketplace/order-received` to Inngest. The marketplace serve function batches per shop, throttles API calls, fetches full order detail, and upserts the ledger. Production uses `MARKETPLACE_INGEST_MODE=inngest` (Kafka publish remains in code as legacy fallback).

**Ops backfill** — Paced list/detail into staging, then insert-only promote into the ledger (no Inngest). Used for pre-go-live gaps and status refresh on unclaimed rows.

**SKU mapping** — Line earnability and catalog joins use multi-channel product reference data when platform SKUs are mapped.

## Rules

- **No earn on webhook alone** — Wallet credit runs only after a successful claim (or Shopify auto-claim path). Shopee / Lazada / TikTok have no merchant switch for auto-award; auto-claim exists only on Shopify.
- **Buyer link** — A successful claim whose order carries a platform buyer id merges `{platform: buyer_id}` into the member's `marketplace_external_ids`. `get_user_claimable_orders` returns that member's unclaimed orders at or past the threshold whose buyer id matches; no member surface calls it yet.
- **Post-claim refunds** — A marketplace cancel/return after claim does not reverse points automatically; ops cancel the purchase (see `Purchase_Transaction.md` › Refunds and admin cancel).
- **Credential routing** — `merchant_credentials.external_id` must equal the webhook shop identifier: Shopee/TikTok `shop_id`; Lazada numeric `seller_id` (account email lives in `credentials`, not `external_id`). `get_shop_credentials` resolves `shop_id` as `COALESCE(credentials.shop_id, external_id)` and requires `service_name = platform`, `is_active`, and `scope IS NULL`.
- **Webhook status is immediate** — `update_marketplace_order_status` runs on every accepted push for an existing row. Claim eligibility does not wait for Inngest detail fetch.
- **UNPAID noise** — Shopee and TikTok webhooks drop UNPAID-equivalent events at the edge (Hookdeck-style filter). Lazada verifies push HMAC before accept.
- **Claim eligibility** — Ledger row must exist for the merchant; sync flag must be false; `order_status` must be in `get_claimable_statuses(platform, threshold)`. Threshold per platform comes from `merchant_master.marketplace_claim_from_status` JSON, with defaults when unset:

| Platform | Default threshold (`order_status` must reach) |
| --- | --- |
| shopee | `READY_TO_SHIP` |
| lazada | `pending` |
| tiktok | `AWAITING_SHIPMENT` |

- **Claimable chains** (from threshold through completed — verified live):

| Platform | Statuses at or after default threshold |
| --- | --- |
| shopee | `UNPAID`, `READY_TO_SHIP`, `PROCESSED`, `SHIPPED`, `COMPLETED` |
| lazada | `pending`, `confirmed`, `packed`, `ready_to_ship`, `shipped`, `delivered` |
| tiktok | `UNPAID`, `ON_HOLD`, `AWAITING_SHIPMENT`, `AWAITING_COLLECTION`, `IN_TRANSIT`, `DELIVERED`, `COMPLETED` |

(`map_marketplace_status` maps platform strings into normalized `status`; claim checks use platform-native `order_status`.)

- **Already claimed** — If sync flag is true → claim returns already-claimed (includes `synced_at`).
- **Auth on claim** — Members claim for self only (`claim_marketplace_order` resolves user from session). Admins must pass `p_user_id` and cannot claim for arbitrary users without admin membership on the merchant.
- **Missing ledger row** — Claim fails order-not-found (typical when Inngest has not upserted yet — member should retry after fulfillment webhook).
- **Per-shop isolation** — Inngest batching, throttle, and concurrency keys are `shop_id`; no cross-shop batches.
- **Inngest batching** — Up to 50 `marketplace/order-received` events per shop per batch, 2-minute batch timeout, throttle 30 run starts per minute per shop, concurrency 10 per shop. Status-only events update existing rows without API when possible.
- **Upsert precedence** — Detail fetch keeps the further-along of webhook vs API status (`preferAdvancedStatus` in serve).
- **Backfill promote** — `fn_promote_marketplace_backfill` insert-only on `(platform, order_sn)`; never overwrites live ledger rows. Promoted rows stay unclaimed until member claim.
- **Token refresh** — Cron `marketplace-token-refresh` refreshes OAuth tokens; Lazada refresh migrates legacy email `external_id` to seller id.
- **CS credentials** — Rows with `scope @> '{cs}'` are excluded from `get_shop_credentials` and order webhooks.

### Shopify

Shared ledger and `claim_marketplace_order` / `fn_claim_marketplace_order_service`, but OAuth, storefront widget, `shopify-webhooks`, buyer match, and auto-claim are owned by [`Shopify.md`](./Shopify.md). Default claim threshold for Shopify is `paid`.

## Journeys

### Admin journey

| Page | Owning repo | BFF / RPC / Edge |
| --- | --- | --- |
| Marketplace Settings | loyalty-admin | `get_merchant_marketplace_channels`, OAuth edges, `admin_delete_marketplace_channel` |
| Marketplace Settings → Order Claims | loyalty-admin | `bff_get_marketplace_order` (search only; admin claim via `claim_marketplace_order` + `p_user_id` is API-only) |
| Merchant global settings | loyalty-admin | `bff_get_general_config` (includes `marketplace_claim_from_status` when configured) |
| Integrations catalog | loyalty-admin | Links into Marketplace Settings OAuth |

| Setting | Effect on behaviour |
| --- | --- |
| Connect Shopee / Lazada / TikTok | Creates `merchant_credentials` with correct `external_id`; TikTok may require shop picker after OAuth |
| Order status to claim points from (Add channel, per platform) | Claim threshold — minimum platform `order_status` before claim succeeds; stored in `marketplace_claim_from_status` |
| Delete channel | `admin_delete_marketplace_channel` deactivates connection |
| Order Claims search | Support lookup: order status, amount, buyer, lines, claimed badge and points earned |
| Backfill window / `dry_run` | Historical missing orders into `stg_marketplace_backfill` then promote |

Marketplace is setup-only: once shops are connected there is no per-order admin work, because members claim self-service.

1. Open **Marketplace Settings** → **Marketplace Connections** and add a channel: pick platform, store name, and the order status to claim points from, then log in on the marketplace and return (OAuth redirect via `marketplace-{platform}-get-auth-url` → `marketplace-{platform}-exchange-token`; Lazada may use pending multi-shop flow in `marketplace_oauth_pending`).
2. Confirm platform webhooks target `webhook-marketplace-{shopee|lazada|tiktok}` (Hookdeck or direct); verify `marketplace_connect_events` and custom webhook logs show success.
3. Status options per platform come from `get_platform_order_statuses` (Shopee and TikTok end at Completed; Lazada ends at Delivered — there is no Lazada Completed option).
4. When a member reports "claim failed", search the order number in **Order Claims** — typically the order has not reached the threshold yet, or it is already claimed — and answer the member without engineering help.
5. For pre-live gaps, run **marketplace-orders-backfill** (dry-run first), then `fn_promote_marketplace_backfill` until staging drains (see System › Ops backfill).

### Member journey

| Page / surface | Owning repo | RPC |
| --- | --- | --- |
| Earn → marketplace channel | loyalty-user | `bff_get_earn_channels`, `claim_marketplace_order` |
| Order detail (when shown) | loyalty-user | `bff_get_marketplace_order` |

1. Buyer learns about points from brand material in the parcel (typically an insert with a QR code to sign up) and registers as a member; the order must reach the merchant’s claim threshold (status webhooks + Inngest detail).
2. Member opens the earn sheet, chooses the marketplace tab, selects platform, enters **order id** (platform order sn).
3. **Claim** — success creates purchase (`transaction_source = marketplace_{platform}`) and runs earn when `p_earn_currency` is true; failure surfaces localized title/description (not found, not claimable status, already claimed).
4. Member sees updated balance per [`Currency.md`](./Currency.md).
5. **Later orders (planned)** — after the first claim links the buyer id, new orders from the same buyer appear as a list the member claims with one tap, no order number needed. Until the member UI ships, every order is claimed by entering its number.

### Shopify

See [`Shopify.md`](./Shopify.md) — no duplicate OAuth/webhook journey here.

## System

### Data model

| Object | Role |
| --- | --- |
| `merchant_credentials` | OAuth tokens per shop; `service_name` = `shopee` \| `lazada` \| `tiktok`; `external_id` = webhook shop key; `scope` null for orders |
| `marketplace_oauth_pending` | Short-lived multi-shop OAuth payloads before merchant picks TikTok/Lazada shop |
| `marketplace_connect_events` | Connect/OAuth telemetry (phase, outcome, edge slug) |
| `order_ledger_mkp` | Claimable order header; `order_status` (platform), `status` (normalized), `synced_to_transaction`, buyer fields, amounts |
| `order_items_ledger_mkp` | Line items linked to ledger header |
| `stg_marketplace_backfill` | Ops staging: raw + normalized JSON, promote metadata |
| `merchant_master.marketplace_claim_from_status` | JSON map platform → minimum claim status |

### Functions

| Function | Role |
| --- | --- |
| `get_shop_credentials` | Resolve active order-scope credentials for ingest |
| `upsert_marketplace_order` | Insert/update ledger header + items from normalized JSON |
| `update_marketplace_order_status` | Webhook-fast path status advance on existing row |
| `map_marketplace_status` | Platform status → normalized status |
| `get_claimable_statuses` | Threshold → array of claim-allowed platform statuses |
| `claim_marketplace_order` | Member/admin claim entry (auth, eligibility, i18n envelope) |
| `fn_claim_marketplace_order_service` | Service-role claim core → purchase create + sync flag |
| `fn_match_marketplace_user` | Buyer id/email/phone → `user_accounts` (Shopify auto-claim) |
| `fn_marketplace_order_items_payload` | Purchase line payload from ledger items |
| `get_merchant_marketplace_channels` | Admin channel list |
| `bff_get_marketplace_order` | Admin/member order detail + CRM sync block |
| `admin_delete_marketplace_channel` | Disconnect shop |
| `fn_promote_marketplace_backfill` | Staging → ledger insert-only |
| `get_platform_order_statuses` | Admin UI status options per platform |

### Flows

**Live ingest**

1. Platform POST → `webhook-marketplace-{platform}` (JWT off).
2. Normalize `{ platform, shop_id, order_sn, order_status }`; optional UNPAID filter (Shopee/TikTok).
3. `update_marketplace_order_status` when row exists.
4. Publish Inngest event `marketplace/order-received` when `MARKETPLACE_INGEST_MODE=inngest` (production).
5. `inngest-marketplace-serve` (`process-shop-orders`): batch/throttle/concurrency per `shop_id` → `get_shop_credentials` → platform adapter (Shopee/TikTok batch get; Lazada signed `/order/get` + `/order/items/get` per order, furthest-along status in `statuses[]`) → `upsert_marketplace_order`.

**Claim**

1. `claim_marketplace_order` loads ledger row, checks sync flag and `order_status` ∈ `get_claimable_statuses`.
2. `fn_claim_marketplace_order_service` builds purchase + items, sets `synced_to_transaction`, `claimed_user_id`, may update member `marketplace_external_ids`.
3. Earn path delegates to purchase/currency chokepoints (see Purchase + Currency docs).

**OAuth / tokens**

- Auth URL + exchange-token edges per platform; `marketplace-token-refresh` cron (hourly :59).
- Lazada exchange/refresh prefers numeric `seller_id` for `external_id` and migrates legacy email keys.

**Ops backfill**

- Edge `marketplace-orders-backfill`: window limits (Shopee ≤15d, TikTok/Lazada ≤7d), `dry_run`, optional `stage_order_sns`, `refresh_existing` for unclaimed status repair.
- Promote via `fn_promote_marketplace_backfill` (documented in `.cursor/deploy/marketplace-orders-backfill/README.md`).

### External services

| Service | Role |
| --- | --- |
| Inngest (`marketplace-serve`) | Batching, throttle, retries for detail fetch |
| Hookdeck (typical) | Inbound webhook routing/filter; patterns in [`Custom_Webhooks.md`](./Custom_Webhooks.md) |
| Shopee / Lazada / TikTok Shop APIs | Order detail and OAuth |
| Render crons | `marketplace-token-refresh`, legacy `marketplace-batch-checker` (see gaps) |

### Known gaps

- **Legacy Kafka path** — Webhook code still supports `MARKETPLACE_INGEST_MODE=kafka|both`; production is **inngest**. [`Ecommerce_Marketplace_Integration.md`](./Ecommerce_Marketplace_Integration.md) and [`MARKETPLACE_SETUP.md`](./MARKETPLACE_SETUP.md) describe retired Hookdeck→Kafka→`marketplace-process-orders` architecture — do not use for new work.
- **Deployed but legacy** — `marketplace-batch-checker`, `marketplace-process-orders`, and `webhook-shopee` remain in the project; live SEA ingest uses `webhook-marketplace-*` + Inngest.
- **Claim threshold editing** — Threshold is chosen in the Add channel modal at connect time; Merchant global settings exposes only the Shopify threshold, so changing a SEA threshold later has no dedicated admin control. Unset platforms fall back to claim-RPC defaults.
- **One-tap claim list** — `get_user_claimable_orders` is live but not called by loyalty-user.
- **Admin claim on behalf** — Supported by `claim_marketplace_order` with `p_user_id`, not exposed in Order Claims UI.
- **Registry lag** — `REGISTRY_RENDER.md` may not list all `webhook-marketplace-*` slugs; edge list from Supabase is authoritative.

## Related

- **Shopify.md** — Storefront app, `shopify-webhooks`, auto-claim, widget.
- **Currency.md** — Earn after claim creates purchase.
- **Purchase_Transaction.md** — Purchase ledger shape and transaction sources.
- **Multi_Channel_Product_Reference.md** — Platform SKU → CRM product mapping for line earnability.
- **Earn_Channel.md** — Marketplace as an earn method; channel visibility and platforms list.
- **Custom_Webhooks.md** — Hookdeck filters and webhook logging.
- **CS_Channels.md** — Marketplace IM credentials (`scope` CS) vs order credentials.
- **Ecommerce_Marketplace_Integration.md** — **Superseded** for Shopee/Lazada/TikTok order ingest (Kafka batching, “auto points on webhook”, Phase-1-only Shopee). Still points at **BigCommerce Storefront API** and migrated-user storefront flows — not SEA marketplace ledger.
