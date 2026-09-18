# Order Booking

Sales staff create **pending** purchase orders at field events in loyalty-admin; fulfillment, promos, and currency earning reuse the standard purchase ledger and event promo engine.

Owner surfaces: loyalty-admin (Choose Events → New Order modal, Orders tab, order detail)

## Concept

**Event order booking** — A staff-captured sale at an event before the member has fully paid or collected goods. The business treats it as a real purchase row in the merchant ledger, not a separate “reservation” system.

**Pending purchase** — The booking state: totals and lines are fixed at submit time, but payment and pickup can finish later. Status stays in the pending/processing band until staff close the order or complete lines.

**Event catalogue** — The SKU list enabled for that event: master-catalog products (optional price override) or one-off custom lines without a master SKU.

**Promo snapshot** — Freebie lines, bill-level discounts, and optional “pick from pool” choices computed when the order is created. Results are stored on the purchase for receipts and audit.

**Line fulfillment** — Each ordered line can track how much quantity is already handed over. When every line is fully completed, the parent purchase can roll to completed and trigger the same earn pipeline as a finished retail order.

**Spot member** — When the buyer is not in CRM yet, staff can register a minimal member from a valid phone number at the booth (distinct from pre-registered event attendees).

## Rules

### Booking identity

- Every booking is a **purchase ledger header** with status starting at **pending** (or processing if line completion is partially advanced at create). There is no parallel booking table.
- Event bookings are tagged with source **event order** and a pointer to the **event master** row for that field day.
- Create path sets API source **manual order** on the purchase header.

### Customer selection (New Order modal)

- Member search is **merchant-wide** (not limited to event registration attendees). Attendee-scoped search exists elsewhere but is not the New Order customer picker.
- Unknown **9-digit phone** queries can open **spot capture**, creating a member with acquisition source **event order spot**.
- Walk-in event registration flows are out of scope on this modal.

### Catalogue and lines

- Lines always store display fields (name, variant, SKU code) on the item ledger even when a master SKU id is present; custom catalogue rows may omit SKU id.
- Item type distinguishes **ordered product** vs **promo freebie** lines.

### Promos and staff adjustments

- At create (sync): promo engine calculates eligible freebies/discounts; chosen pool picks are validated server-side (`p_chosen_freebies`). Failure codes such as **pool validation failed** reject create and force the UI to refresh previews.
- Bill discounts reduce **final amount** after line totals; freebie lines insert as separate rows.
- **Staff discount** (coupon/other, baht or percent) applies **after** promos via a dedicated apply step; amount is stamped in purchase metadata for receipts.
- **Promo claim** rows record per-user limits for event promos at booking time.

### Currency earning

- Header flags **earn currency** and **processing method queue** so grants run through the purchase chokepoint outbox (not inline at submit).
- Live **currency purchase router** awards when earn is enabled and purchase status is **pending**, **processing**, or **completed** (not gated by a column on earn condition groups).
- Points, tickets, ticket-code assignment, and conditional AMP pushes are **async** after the purchase write. Nothing wallet-related is guaranteed synchronous at booking time.
- **Preview** promos and **preview** currency RPCs are read-only and write no ledger rows.

### Purchase status model

Valid header statuses and typical transitions:

```
pending ──→ processing ──→ completed
   │            │
   └──→ cancelled   └──→ cancelled
                              │
                    completed ──→ refunded
```

- **Pending** — Booking just submitted; default for event sales.
- **Processing** — Partial line fulfillment or in-progress handling.
- **Completed** — Paid/delivered per ops rules; earn events may fire on transition.
- **Cancelled** — Order voided before completion.
- **Refunded** — Post-completion reversal path (wallet undo uses refund flows, not line-completion RPC on a completed parent).

### Line completion

- Admin may set **quantity completed** per line (absolute target, not delta). Backend derives line status from quantity.
- When all lines are fully completed, parent status can roll to **completed**, which triggers queued currency processing.
- **Completed parent** blocks further line-completion edits unless staff use the refund path (**parent completed use refund**).

### UI validation (loyalty-admin)

- When a promo **freebie pool** is shown and has at least one pickable option under the cap, staff must pick **≥1** unit before review/submit.
- Payment method **other** requires free-text **payment method other** in metadata.

## Journeys

### Admin journey

| Page / surface | Owning repo | BFF / RPC |
| --- | --- | --- |
| Choose Events list | loyalty-admin | `admin_get_my_events` |
| Event detail — **Orders** tab (list, stats) | loyalty-admin | `bff_list_event_orders`, `bff_get_event_order_stats` |
| **New Order** full-screen modal | loyalty-admin | `bff_list_event_products`, `bff_preview_event_promos`, `calc_currency_core`, `api_create_manual_purchase_order` |
| Customer search / spot member | loyalty-admin (`order-booking` components) | `bff_admin_search_members`, inline member create (spot) |
| Order detail / status / line completion | loyalty-admin | `bff_get_event_order_details`, `api_update_purchase`, `bff_admin_set_event_order_item_completion` |
| Event product catalogue (configure SKUs) | loyalty-admin (event setup / promos) | `bff_upsert_event_products`, `bff_list_event_products`, `bff_delete_event_product` |
| Event promo rules | loyalty-admin | See **Event_Promotion.md** (`event_promo_*`) |

| Setting / knob | Effect on behaviour |
| --- | --- |
| Event context | Tags purchase with event source id |
| Event catalogue | Lines available in picker; prices from config |
| Event promos | Freebies, bill discounts, pools at create |
| Chosen freebie picks | Sent as `p_chosen_freebies`; server validates caps |
| Staff discount | Metadata + post-promo amount adjustment |
| Amount paid / outstanding | Stored in metadata for slip and reconciliation |
| Pickup store / location / date | Metadata for fulfillment |
| Per-line `quantity_completed` at create | Can start partial fulfillment; 0 = all pending |
| Order status actions | Complete or cancel header via purchase update API |

1. Open **Choose Events**, select an event, go to **Orders**, and start **New Order**.
2. **Step 1 — Build cart:** Search merchant members or capture spot phone; add lines from the event catalogue; debounced **preview promos** on cart changes; preview points/tickets for display; satisfy visible freebie pool picks.
3. **Step 2 — Review:** Confirm payment method, amount paid vs outstanding, pickup fields, staff discount, notes; submit.
4. **Step 3 — Confirmation:** Show transaction number, final amounts, promo snapshot; print thermal/order receipt (includes projected earn metadata when captured).
5. On **Orders** tab, open order detail; mark header **completed** or **cancelled**, or adjust **line completion** until parent completes and earn queue runs.

Common errors surfaced to staff: **pool validation failed** (refresh cart/picks), **invalid item completion** (quantity bounds), **parent completed use refund** (use refund instead of line edits).

### Member journey

| Surface | Owning repo | BFF / RPC |
| --- | --- | --- |
| Self-serve booking | — | Not offered |
| Wallet / tickets after staff completes order | loyalty-user | Standard wallet read paths after async earn |

1. Member does not book at the booth themselves; staff owns the modal.
2. After staff submit and (when applicable) complete the order, member may see points, tickets, or pushed rewards in wallet/redemptions once async processors run (typically seconds, not at button click).

## System

### Data model

| Artifact | Role |
| --- | --- |
| `purchase_ledger` | Order header: customer, status, amounts, payment method, earn flags, `reward_list` promo snapshot, `metadata` (pickup, staff discount, amount paid, admin creator, projected earn display fields) |
| `purchase_items_ledger` | Lines: SKU reference optional, denormalized names/codes, quantities, prices, `item_type` product vs freebie, completion quantity |
| `event_product_config` | Per-event catalogue (master-backed or custom) |
| `syngenta_events_master` | Event identity (`transaction_source_id` on purchases) |
| `product_sku_master` | Master SKU reference for backed catalogue rows |
| `event_promo`, `event_promo_rule`, `event_promo_claim` | Promo definitions, evaluation, per-user claim tracking |
| `earn_factor` / earn stack | Currency rules consumed by `calc_currency_core` and purchase routers |
| `wallet_ledger`, ticket balances / code pools | Async earn destinations |

**Header fields (event booking)**

| Concern | Column / storage |
| --- | --- |
| Customer | `user_id` |
| Sales rep | `seller_id` (optional; API accepts `p_seller_id`) |
| Event link | `transaction_source`, `transaction_source_id` |
| Booking state | `status` pending/processing/… |
| Totals | `total_amount`, `final_amount` (after bill + staff discounts) |
| Earn routing | `earn_currency`, `processing_method` |
| Promo output | `reward_list` JSONB |
| Ops metadata | `metadata` JSONB |

**Line fields**

| Concern | Column |
| --- | --- |
| Product reference | `sku_id` nullable |
| Display | `sku_code`, `product_name`, `variant_name` |
| Economics | `quantity`, `unit_price`, `discount_amount`, `line_total` |
| Kind | `item_type` `product` \| `freebie` |

### Functions

| Function | Role |
| --- | --- |
| `api_create_manual_purchase_order` | Create header + lines; run promo apply; staff discount; optional `p_chosen_freebies`; event source params |
| `bff_preview_event_promos` | Read-only promo/freebie/pool projection (`p_final_amount`, items) |
| `calc_currency_core` | Read-only points/ticket projection for cart |
| `fn_calc_event_promos` / `fn_apply_event_promos` | Promo evaluation and persistence at create |
| `fn_apply_manual_staff_discount` | Post-promo staff discount on event manual orders |
| `bff_list_event_orders` | Paginated event order list |
| `bff_get_event_order_details` | Header + product + freebie lines |
| `bff_get_event_order_stats` | Aggregates for Orders tab |
| `bff_admin_set_event_order_item_completion` | Absolute per-line completion; parent rollup |
| `api_update_purchase` | Header status complete/cancel |
| `bff_upsert_event_products`, `bff_list_event_products`, `bff_delete_event_product` | Event catalogue CRUD |
| `bff_search_event_attendees` | Attendee-scoped search (not used by New Order customer combo) |
| `chokepoint_post_purchase_event` / outbox | Enqueue purchase-side async work |

`api_create_manual_purchase_order` accepts metadata keys including `outstanding_balance`, `pickup_location`, `pickup_date`, `pickup_store_id`, `amount_paid`, `payment_method_other`, `staff_discount`, and display copies `points_earned` / `tickets_earned` when the UI prefetched previews.

### Flows

**Preview (sync, read-only):** On cart changes → `bff_preview_event_promos` + `calc_currency_core` → UI shows discounts, pools, projected earn (UI currently passes **completed** purchase status into currency preview for projection display).

**Create (sync portion):** `api_create_manual_purchase_order` with `transaction_source = event_order` → insert purchase + product lines → promo calc/apply → freebie lines → `reward_list` → promo claims → staff discount → return transaction id/number and promo payload.

**Create (async):** Purchase chokepoint → `chokepoint_event_outbox` → OutboxPublisher → `inngest-event-router-serve` (**currency-purchase-router**) → `inngest-currency-serve` → `chokepoint_post_wallet_transaction` and ticket code assignment; parallel **amp-purchase-router** may create redemptions or extra currency awards when configured.

**Fulfillment:** Line completion RPC updates quantities → parent may become **completed** → same earn queue as status-driven completion.

**Status update:** `api_update_purchase` for explicit complete/cancel without line-level edits.

### External services

| Service | Role |
| --- | --- |
| `inngest-event-router-serve` | Routes purchase events (currency, AMP) |
| `inngest-currency-serve` | Wallet/ticket grants |
| `inngest-amp-serve` | Conditional push reward / extra currency actions |

See `REGISTRY_RENDER.md` for deployed router names and `Currency.md` for earn timing detail.

### Known gaps

- **Seller attribution:** `purchase_ledger.seller_id` and `p_seller_id` exist on the create API, but the Choose Events **New Order** server action does not pass seller id today (metadata may still record `created_by_admin_user_id`).
- **Earnings preview vs pending earn:** Admin preview calls `calc_currency_core` with purchase status **completed** while the created order is **pending**; displayed points/tickets are projections—live pending earn depends on router rules and merchant earn config.
- **Attendee search vs merchant search:** `bff_search_event_attendees` is implemented for event-scoped lookup but New Order intentionally uses `bff_admin_search_members`.
- **Registry lag:** `fn_apply_manual_staff_discount` is live in the database but may be absent from `REGISTRY_SUPABASE.md` until the next registry regen.

## Related

- **Syngenta_Events.md** — Event master, teams, catalogue setup, retailer allowlist.
- **Event_Promotion.md** — Event promo engine rules and admin configuration.
- **Purchase_Transaction.md** — Core purchase lifecycle, chokepoints, status semantics.
- **Currency.md** — Points/tickets earn, ticket codes, purchase routers.
