# Purchase Transaction

Immutable purchase headers and line items are the loyalty program’s spend record: they drive earn, tier metrics, missions, limits, and reporting. All canonical writes route through one purchase chokepoint; downstream systems react when a purchase reaches a billable completed state.

Owner surfaces: loyalty-admin, loyalty-user, Open API partners, marketplace ingest (see `Marketplace.md`)

## Concept

A **purchase** is a merchant-scoped transaction that records who bought (or who sold, in B2B flows), where it happened, how much was paid, and whether loyalty should treat it as final. Purchases are **append-only at the business level**: corrections and refunds add new rows or events rather than rewriting history.

**Header** — One row per transaction: amounts, status, payment state, buyer/seller, store context, processing flags, and external references.

**Line item** — SKU-level rows under a header: quantity, pricing, optional partial pickup progress, and the same completion metadata pattern as the header when lines finish individually.

**Dual ledger** — The product model is always header + lines (`purchase_ledger` + `purchase_items_ledger`). Marketplace **order** ledgers (`order_ledger_mkp` + lines) are a separate staging area until a member (or Shopify auto-claim) promotes an order into this purchase pair.

**Credit vs debit** — Normal spend is a **credit** row; refunds and cancellations that reverse spend use **debit** rows (positive amounts interpreted as negative in aggregates). The original credit row stays intact.

**Buyer vs seller perspective** — `user_id` is the member who earns as the buyer; `seller_id` is the distributor/seller when programs attribute seller performance. Tier and mission “perspective” settings choose which id is evaluated.

**Billable completion** — Currency, tier, and mission side effects key off the header (and configured line-item events) reaching **`completed`** with `earn_currency` true, subject to earn-rule purchase-status gates and `processing_method`. Partial line pickup tracks `quantity_completed` but does not partially award points by default.

**Processing method** — Per-row routing hint for the currency pipeline: `queue` (default, async), `direct` (inline), or `skip` (no earn). Tier and mission evaluation still follow completion events unless product rules say otherwise.

**Chokepoint writer** — Every insert/update to purchase headers or lines goes through `chokepoint_post_purchase_event` with a typed event name; callers such as Open API, seller BFFs, marketplace claim, bulk import, and receipt approval delegate here instead of writing tables directly.

## Rules

### Header status (`purchase_status`)

| Value | Meaning | Earn / tier / mission |
| --- | --- | --- |
| `pending` | Created, not finalized | No |
| `processing` | In progress (e.g. payment authorized) | No |
| `completed` | Finalized billable state | Yes, when `earn_currency` is true and earn rules allow this status |
| `cancelled` | Aborted before completion | No |
| `refunded` | Reversal of a completed purchase (header-level) | Triggers reversal flows; paired debit rows per cancel/refund APIs |

**Valid transitions (typical):** `pending` → `processing` → `completed`; `pending`/`processing` → `cancelled`; `completed` → `refunded`. Do not move `completed` back to `pending` or resurrect `cancelled` into `completed`.

**Payment status** — Independent text track (`pending`, `authorized`, `paid`, `failed`, `refunded`, `voided`, …). It can diverge from header status (e.g. paid while still `processing` until ops complete the header).

### Record type

- `credit` — Purchase spend; contributes positively to sales-style metrics when status is `completed`.
- `debit` — Refund/cancel sibling; metrics and earn reversal treat amounts as negative via `record_type`, not via negative `final_amount` on credits.

### Amounts

- Line: `(quantity × unit_price) − line discount + line tax` → `line_total`.
- Header: sum of lines, then header-level discount/tax → `final_amount`. Earn rules may use `earnable_amount` when set (marketplace claim passes platform-specific earnable totals).

### Completion stamping

Any transition to `status = completed` should set `completed_at`, `completed_by_user_id`, and `completed_by_source` (e.g. `seller_self_service`, `seller_line_item_completion`, `api_external`, `system_bulk_import`, `marketplace_claim`, `parent_cascade`, `refund_flow`).

### Line items and partial pickup

- Each line has `quantity_completed` (0 ≤ value ≤ `quantity`), monotonic non-decreasing per line.
- Line `status` is derived: full quantity picked up ⇒ `completed`; otherwise stays `pending` (no separate “partial” enum).
- Header rolls up via `fn_recompute_purchase_status` when children change; parent → child force-complete uses statement trigger `trg_purchase_complete_cascade_items`.
- **Earn uses ordered quantity**, not `quantity_completed`, unless product changes that contract.

### Earn and side effects

- When the chokepoint commits a qualifying **completed** header (or configured line-item completion events), it emits `crm.events.purchase` / `crm.events.purchase_item` via `fn_chokepoint_emit_event`. Currency, tier, and mission processors consume those events (async queues / Inngest — see `Currency.md`, `Tier.md`, `Mission.md`). Legacy per-table triggers `trigger_process_purchase_currency` and friends are **retired**.
- If `earn_currency` is false or `user_id` is null, header earn is suppressed at write time.
- Earn factors may scope **per purchase** or **per line item**; purchase-status gates on earn rules default to completed-only.

### Limits

- `fn_check_purchase_limits` / `fn_preview_purchase_limits` enforce merchant rules in `transaction_limits` before accept (amount, count, window, store scope).

### Refunds and admin cancel

- `refund_purchase` and `api_cancel_purchase` / `bff_admin_cancel_purchases` create reversal behavior with optional currency reverse modes (`best_effort`, etc.).
- Proportional wallet reversal uses original `wallet_ledger` metadata from the purchase earn, not current earn rates.

### Marketplace claim (purchase outcome)

- Claim is not complete until `fn_claim_marketplace_order_service` successfully calls `api_create_purchase` with `status = completed` and a deterministic `transaction_number` (`MKP-{PLATFORM}-{order_sn}`), then marks `order_ledger_mkp.synced_to_transaction`. Webhook ingest alone does not award points.

### Referral on order settlement (purchase-adjacent)

- After a qualifying commerce order exists as a purchase (Shopify webhook / marketplace claim path), **purchase referral** attribution runs via `fn_attribute_referral` (`kind = purchase`) and, when matched, `fn_settle_referral` → referrer outcomes. Friend offer at claim time is separate from referrer settlement. See `Referral.md` and reference MD Part 1 § Purchase referral (steps 6–8). Reconciliation: `fn_reconcile_missed_referral_purchases`.

**Example (debit pattern):** A 1,500 THB credit completes and earns 15 points. A full refund inserts a debit row for 1,500 THB and reverses 15 points from wallet history tied to the original purchase id.

## Journeys

### Admin journey

| Page | Owning repo | BFF / RPC |
| --- | --- | --- |
| Purchases report | loyalty-admin | `bff_report_purchases`, `bff_report_purchases_rows` |
| Member profile — purchases | loyalty-admin | `admin_get_user_purchases` |
| Cancel purchase (e.g. receipt flow) | loyalty-admin | `bff_admin_cancel_purchases` |
| Front-line manual order | loyalty-admin | `api_create_manual_purchase_order` |
| Earn rules (purchase gates) | loyalty-admin | Earn rule BFFs (`purchase_status`, scope per purchase / line item) |

| Setting | Effect on behaviour |
| --- | --- |
| Earn rule — award on purchase status | Which header status may award (default completed) |
| Earn rule — scope purchase vs line item | One award per header vs per qualifying line |
| Earn rule — seller perspective | Currency attributed to seller member when configured |
| `transaction_limits` rows | Caps purchases per member/store/window |
| `merchant_master.marketplace_claim_from_status` | Minimum marketplace order status before claim (see `Marketplace.md`) |

1. Open **Purchases report**, set date range and filters; drill into rows via `bff_report_purchases_rows`.
2. On a member record, use purchase history search via `admin_get_user_purchases`.
3. To void a posted purchase from admin tooling, run **Cancel purchase** with reason and reversal flags (`bff_admin_cancel_purchases`).
4. Front-line staff create POS/event orders through **Manual purchase order** (`api_create_manual_purchase_order`); event promos and freebie pools validate server-side.
5. Configure when purchases earn under **Earn rules studio** (status gate and per-line scope).

### Member journey

| Page / surface | Owning repo | BFF / RPC |
| --- | --- | --- |
| Purchase history drawer | loyalty-user | `bff_get_purchase_history` |
| Marketplace order claims | loyalty-user | `claim_marketplace_order` |
| Seller pickup (Syngenta) | loyalty-user | `bff_seller_get_purchase_by_transaction_number`, `bff_seller_complete_purchase_items`, `bff_seller_complete_purchase_by_transaction_number` |

1. Member opens wallet/history; app loads `bff_get_purchase_history` (filter, paging).
2. For marketplace programs, member claims an eligible order → purchase row + earn; errors include below-threshold status or already claimed.
3. Seller persona: scan or enter `transaction_number`, load order, increment line pickup quantities until header completes → completion stamping `seller_line_item_completion` / `seller_self_service`.
4. On success, points/tickets appear per wallet history; on limit breach, create/claim returns limit errors from `fn_check_purchase_limits`.

| Error (typical) | Cause |
| --- | --- |
| Purchase limit exceeded | `transaction_limits` |
| Below claim threshold | Marketplace order status under merchant threshold |
| Already claimed | `order_ledger_mkp.synced_to_transaction` |
| Monotonic violation | Seller BFF rejects decreasing `quantity_completed` |

## System

### Data model

| Artifact | Role |
| --- | --- |
| `purchase_ledger` | Header: amounts, `purchase_status`, `payment_status`, `record_type`, buyer/seller, `store_id` (uuid FK), `store_code`, `processing_method`, `earn_currency`, `earnable_amount`, `wallet_ledger_code` (POS point-discount link), `transaction_source` / `transaction_source_id`, `dedup_key`, completion stamps, `metadata` |
| `purchase_items_ledger` | Lines: `sku_id`, quantities, amounts, line `status`, `quantity_completed`, per-line completion stamps, optional `currency_processed_at` / `currency_error` |
| `transaction_limits` | Purchase caps (shared limits facility) |
| `order_ledger_mkp` / `order_items_ledger_mkp` | Pre-claim marketplace orders (hand off to `Marketplace.md`) |
| `mkt_purchase_attribution` | Marketing attribution on purchases (`Activity_Attribution.md`) |

Indexes support merchant/date reporting, transaction number lookup, and user+status queries.

**Triggers on `purchase_ledger` (data integrity / integrations):** `trg_purchase_complete_cascade_items` (parent completed → children), `trg_jorakay_receipt_webhook` (merchant-specific). No currency/tier/mission triggers on the table.

### Functions

| Function | Role |
| --- | --- |
| `chokepoint_post_purchase_event` | Sole writer for headers/lines; events include `created`, `updated`, `completed`, `cancelled`, `refunded`, `promo_applied`, `item_quantity_completed`, `item_completion_set`, `item_cancelled`, `item_refunded`, `items_added`, `items_replaced` |
| `api_create_purchase` | Open API / internal create; delegates to chokepoint |
| `api_update_purchase` | Status/amount/line updates via chokepoint |
| `api_get_purchase` | Read header by id or transaction number |
| `api_cancel_purchase` | Partner/admin cancel with reversal options |
| `api_create_manual_purchase_order` | Admin/front-line basket create |
| `bulk_insert_purchases_with_items` | Import batches |
| `refund_purchase` | Debit/refund sibling creation |
| `fn_recompute_purchase_status` | Child line rollup to parent header |
| `trigger_cascade_purchase_complete_to_items` | Statement trigger function for parent→child complete |
| `fn_check_purchase_limits` / `fn_preview_purchase_limits` | Limit enforcement |
| `bff_report_purchases` / `bff_report_purchases_rows` | Admin analytics |
| `bff_admin_cancel_purchases` | Admin cancel wrapper |
| `bff_get_purchase_history` | Member history |
| `bff_seller_*` | Seller self-service load/complete |
| `claim_marketplace_order` / `fn_claim_marketplace_order_service` | Member claim → `api_create_purchase` + sync marketplace ledger |
| `calc_currency_for_transaction` / `calc_currency_for_purchase_item` | Earn calculation helpers (invoked from currency workers) |
| `get_eligible_earn_factors*` | Earn factor resolution for a purchase or hypothetical basket |
| `chokepoint_post_purchase_event` → `fn_chokepoint_emit_event` | Emits `crm.events.purchase` and `crm.events.purchase_item` for downstream processors |

**Removed / do not document as live:** `create_purchase_via_api`, `find_user_by_identifier`, `trigger_process_purchase_currency`, `trigger_tier_eval_on_purchase`, `trigger_mission_evaluation_realtime` on `purchase_ledger`.

### Flows

**Create (API / import):** Validate merchant + user + store + limits → `api_create_purchase` → chokepoint `created` (and `completed` when status demands) → emit purchase events → currency queue or direct processing per `processing_method` → tier/mission consumers on same event bus.

**Update / complete:** Status or line changes via chokepoint `updated` / `completed` / item events → re-emit deltas → cascade trigger when parent flips to completed.

**Marketplace claim:** `claim_marketplace_order` → `fn_claim_marketplace_order_service` validates user, claimable status, builds items payload → `api_create_purchase` (`transaction_source = marketplace_{platform}`, `completed_by_source = marketplace_claim`) → update `order_ledger_mkp.synced_to_transaction`.

**Receipt upload earn:** Approved receipts create purchases through receipt chokepoints (`Receipt_Upload_Earning.md`), not direct ledger inserts.

**Referral purchase settlement:** Order webhook / claim path creates or updates purchase context → `fn_attribute_referral` (purchase) → `fn_settle_referral` on qualify (Shopify: `shopify-webhooks` pipeline). Details in `Referral.md`.

**Cancel / refund:** Cancel APIs → chokepoint `cancelled` / `refunded` events → wallet reversal via currency chokepoint with historical metadata.

**POS point discount:** Header `wallet_ledger_code` and `discount_amount` reconcile to burned wallet row for staff orders.

### External services

- Open API edge routes call `api_*` purchase RPCs with merchant API keys (`Open_API.md`).
- Marketplace webhooks + `inngest-marketplace-serve` populate `order_ledger_mkp` before claim (`Marketplace.md`).
- Currency workers (`inngest-currency-serve`, etc.) consume `crm.events.purchase*` per `Currency.md`.

### Known gaps

- Per-line earn scope is configured in admin but product UI may still show “queued for activation” banners when scope is line-item.
- Separate fulfillment/shipping dimensions are not modeled; e-commerce platforms map into single `purchase_status` (Shopify uses shared marketplace + claim pipeline — `Shopify.md`).
- `purchase_receipt_upload` linkage and OCR flows are owned by `Receipt_Upload_Earning.md`.
- Phase 2 Kafka publish from purchase chokepoint is planned (`requirements/architecture/event-chokepoints.md`); CDC may still mirror tables until decommissioned.

## Related

- **Currency** — Wallet earn/reversal processors and `processing_method` semantics.
- **Tier** — Spend/order metrics from completed purchases.
- **Mission** — Purchase-shaped mission conditions and progress.
- **Marketplace** — Order ledger ingest and claim before purchase exists.
- **Receipt Upload Earning** — Alternate path into `purchase_ledger`.
- **Open API** — Partner create/get/cancel purchase endpoints.
- **Referral** — Purchase referral attribution and settlement on qualifying orders.
- **Activity Attribution** — `mkt_purchase_attribution` and campaign ROI.
- **Store Attribute Classification** — Store sets for earn and mission filters.
- **Event chokepoints** — `requirements/architecture/event-chokepoints.md` (purchase Phase 1 complete).
