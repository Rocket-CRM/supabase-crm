# Product Narrative

Derived customer-facing explanation of Rocket CX capabilities for sales, proposals, and sales-agent answers.

**Not the source of truth for feature identity.** Canonical identity, hierarchy, status, and package inclusion live in Supabase `internal_product_*`. Behavior detail lives in `requirements/**/*.md` and CRM Knowledge. This file explains what each capability enables for a buyer.

Maintenance contract: `workflows/product-feature-catalog/REFERENCE.md`.

## How to use this doc

- **Proposal / sales writing** — lift buyer-facing phrasing; do not invent capabilities that are absent from the catalog.
- **AI input** — feed sections into proposal or sales agents. Prefer matching `<!-- feature_key: … -->` markers to catalog rows.
- **Out of scope** — schemas, function names, queues, entitlement registry. Those stay in requirements / eng packs.
- **Do not put this file in `search_docs`.** Retrieve a heading with Knowledge `get_section` on path `docs/PRODUCT_NARRATIVE.md`. Reconcile uploads it for get-by-heading only.

## Structure

Public modules: **Loyalty**, **Shopify**, **Marketing Automation**, **Customer Service**.

Campaign mechanics and former App foundation capabilities are part of **Loyalty** (not separate sellable modules). Older `## Campaigns` / `## Platform` headings below are retained as narrative anchors and should be read as Loyalty sub-journeys until those sections are fully resynced.

Target template for resynced feature sections:

1. **What it enables** — buyer-facing what + why.
2. **How it works** — admin/customer journey in operating order.
3. **What differentiates it** — concrete behavior or flexibility.
4. **Key controls** — customer-relevant choices (not exhaustive enums).
5. **Example** — optional, only when it clarifies the mechanism.

Legacy sections may still use Overview / Purpose / User Journey / Configurations & Rules until their catalog row is touched.

Voice: consultative, specific, outcome-led, proposal-ready. Mark `beta` / `planned` explicitly when the catalog status is not `ga`.

---

## Loyalty

Loyalty covers acquisition → engagement → campaigns → analysis → activation: members join, earn and burn value, move through tiers and campaigns, and the brand analyzes and activates next actions. Signup, campaigns, segmentation/RFM, loyalty admin (including PDPA, languages, Member 360, and 30+ reports), and Front Line all sit in this module.

### Rewards

**Overview**

Rewards are the redeemable items in the loyalty marketplace — vouchers, physical products, digital codes, shipped items, pickup items, printed certificates, or campaign-delivered benefits. Each reward has a points cost, a fulfillment method, and a redemption window. The system separates two questions cleanly: **who may redeem** (eligibility) and **how many points they pay** (dynamic pricing). Every redemption writes to an operational ledger that drives member history, stock usage, promo-code accounting, and wallet burn reconciliation.

**Purpose**

Rewards are the "spend" half of the loyalty loop — they make earned points tangible. Without rewards, points are an abstract number. The marketplace turns currency into a member-facing catalog that brands curate by audience (tier, persona, tags, user type), distribute across channels (in-app browse, campaign push, partner storefronts), and price dynamically (different cohorts pay different points for the same reward).

**User Journey**

*Admin journey*

Admins create and maintain rewards from the reward list and reward form. The form captures content (name, description, images, translations), visibility, fulfillment method, redemption window, expiration mode, eligibility filters, points cost (with fallback or required-match behavior), promo-code assignment, stock control, store-stock allocation, online storefront identifiers, featured state, and group membership. Promo-code management supports both default shared codes and unique code pools imported in batches with partner attribution.

*Member journey*

Members browse only rewards marked `visibility = 'user'`. The catalog displays translations, images, points cost, availability, promo-code indicators, validity window, and group context. On redemption, the member sees an immediate processing path and the result arrives via realtime success-or-failure broadcast. Campaign-delivered rewards never appear in browse — members see them only after a workflow, campaign, package assignment, or admin push creates the redemption record directly.

*Edge cases*

A reward can be visible but not redeemable if the member fails eligibility, lacks balance, hits a transaction limit, or stock / promo-code availability is exhausted. Pickup and store-stock flows need an effective store to be supplied or resolved. Realtime failure broadcasts are ephemeral, so clients still need timeout and history-refresh handling.

**Configurations & Rules**

*Reward properties — every field admins set*

| Group | Field | Type / Values | Behavior |
|---|---|---|---|
| Identity | Name, description, image, translations | Text / image URL | Catalog display |
| Visibility | `user` | enum | Public catalog — only value returned by the user-facing API |
| Visibility | `admin` | enum | Admin-only redemption (e.g., at counter, on behalf of user) |
| Visibility | `campaign` | enum | Push-only — never appears in catalog; delivered via workflow, campaign, package, or admin push |
| Fulfillment | `digital` | enum | Electronic delivery — codes, vouchers, downloads |
| Fulfillment | `shipping` | enum | Physical delivery; address required |
| Fulfillment | `pickup` | enum | Collection at a designated store |
| Fulfillment | `printed` | enum | Self-print voucher / certificate |
| Online distribution | `online_store[]` | text array | Marketplace identifiers (e.g., `shopify`, `bigcommerce`, `lazada`). Merchant-defined free text, no enum. NULL or empty = not distributed to any storefront. |
| Expiration | `relative_days` | mode | Expires X days after redemption |
| Expiration | `relative_mins` | mode | Flash rewards expiring in minutes |
| Expiration | `absolute_date` | mode | Fixed expiration date for all redemptions |
| Redemption window | start / end timestamps | timestamptz | When the reward is even redeemable at all |
| Featured | boolean | flag | Catalog presentation |
| Group membership | `reward_group_ids[]` | uuid array | Reward can belong to multiple groups simultaneously |

*Eligibility dimensions — checked before pricing*

| Dimension | Field | Value | Behavior |
|---|---|---|---|
| Tier | `allowed_tier[]` | uuid array of tier IDs | Member's current tier must be in array |
| User type | `allowed_type[]` | enum array — `buyer` / `seller` | Filters by user type |
| Persona | `allowed_persona[]` | uuid array of persona IDs | Member's persona must be in array |
| Tags | `allowed_tags[]` | uuid array of tag IDs | Member must hold at least one tag in the array |
| Birth month | `allowed_birthmonth[]` | int array, 1–12 | Restricts to birthday-month rewards |
| Active status | boolean | flag | Inactive rewards never reach pricing |
| Time window | start / end | timestamptz | Outside-window blocks at eligibility stage |

A member blocked at any dimension never reaches the pricing stage.

*Dynamic pricing — four-dimension matching*

A reward can have multiple `reward_points_conditions` rows, each combining up to four dimensions: **tier**, **user type**, **persona**, and **tags**. Each row carries its own points cost and priority. At redemption:

1. The engine evaluates every active condition for the reward.
2. Each condition is scored by **specificity** (how many of the four dimensions it specifies) and **match score** (how many of those dimensions actually match the member's attributes).
3. Higher specificity wins.
4. **Priority** breaks ties.
5. When all else is equal, the **customer-favorable rule** picks the lowest points cost.
6. If no condition matches, the reward's `fallback_points` is used — *unless* `require_points_match = true`, in which case redemption is rejected.

*Redemption limits — three concepts, one table*

All redemption limits live in a single `transaction_limits` table with `entity_type` + `metric` + `scope` deciding what's being counted.

| Concept | `entity_type` | `metric` | `scope` | What `count` measures | Time units |
|---|---|---|---|---|---|
| **Reward Quota** | `reward` | `quantity` | `user` or `total` | Units of this single reward a user (or everyone) may redeem | `day` / `week` / `month` / `year` / `all_time` |
| **Group Quantity** | `reward_group` | `quantity` | `user` or `total` | Total units redeemed across all rewards in the group combined | `day` / `week` / `month` / `year` / `all_time` |
| **Max Distinct Reward** | `reward_group` | `distinct_reward` | `user` only | Number of distinct reward types a user may pick inside the group | `day` / `week` / `month` / `year` / `all_time` |

- **Scope `user`** — per-user enforcement. Independent counter per member.
- **Scope `total`** — global enforcement across all members. Functions like a campaign cap.
- **Time unit** — defines the rolling counter window. `all_time` means lifetime.
- **Window enforcement** — optional absolute date range `[window_start, window_end]` outside which the limit row does not apply (lets you stack "Q1 promo cap" alongside "lifetime cap").
- **Max Distinct counting** — a slot is consumed only when the user redeems a reward type they have not already redeemed in that group and window. Re-redeeming the same reward type does not consume another distinct slot.

*Stock control*

| Setting | Behavior |
|---|---|
| Total stock | Optional integer; atomic deduction at redemption; oversell prevented. |
| Per-store allocation | Per-reward × per-store quantity in `reward_stock_store`. |
| Used quantity | Derived, not counter-based — counted from successful redemptions where `used_status = true`, not cancelled, and effective store matches the allocation. |
| Stock toggle | Stock control can be disabled entirely (unlimited). |

*Promo code assignment*

| Mode | Behavior |
|---|---|
| Default shared code | One code reused for every redemption. |
| Unique code pool | Pre-loaded list of single-use codes; locked and assigned atomically at redemption. |
| Batch attribution | Codes carry batch ID and partner ID for billing reconciliation. |
| Multi-quantity behavior | All-or-nothing — member receives every code or none; partial allocation never happens. |

*Operating rules*

- **Eligibility runs before pricing.** Members blocked by tier / user type / persona / tag / birthday month / active status / time window never reach the pricing stage.
- **Most specific match wins.** Pricing engine scores by specificity, then priority, then customer-favorable lowest cost.
- **Redemption is atomic.** Single server transaction validates reward state, eligibility, points cost, balance, transaction limits, reward group limits, stock, promo-code availability, and optional store stock before writing ledger and wallet burn effects.
- **All configured limits must pass.** Reward quota, group quantity, and Max Distinct are checked independently — failing any one blocks redemption.
- **Cross-group evaluation.** If a reward belongs to multiple groups, each group's limits are evaluated independently.

*Limitations*

- `campaign` rewards are push-only — never appear in the browse catalog.
- `online_store[]` is free text, not a platform enum.
- `Max Distinct` is user-scoped only — total-scope distinct counting is not supported.
- Catalog summary views and caches may lag source writes depending on refresh / TTL.

#### Reward Groups

**Overview**

Reward Groups let merchants bundle multiple rewards together and enforce limits across the bundle. The feature adds **Max Distinct Reward** on top of per-reward quota and group-quantity limits. A reward can belong to multiple groups simultaneously through `reward_group_ids`, and at redemption the system evaluates every group the reward belongs to.

**Purpose**

Member choice under merchant control. A merchant offering, for example, six seat categories under one "Zone Tickets" group needs to let members choose freely between categories but cap how many distinct categories or how many total seats one member can claim. Group limits answer that without forcing the merchant to wire those rules into each reward individually.

**User Journey**

*Admin journey*

Admins create and edit groups from the Reward Group list / form. They enter group details, add member rewards, optionally mark featured, and add limit rows. The limit type chosen drives the metric: **Reward Type** creates a Max Distinct limit; **Reward Quantity** creates a Group Quantity limit. Save validates contradictory configurations before members can hit them in production.

*Member journey*

The reward catalog receives reward group IDs per reward and a group-usage map. Rewards already chosen by the member can show a "chosen" state and remain redeemable if other limits allow. Rewards not yet chosen can show a "locked" state when remaining distinct slots are zero. At redemption, the server is authoritative — the UI must treat any server denial as the source of truth and surface the returned group / limit explanation.

*Edge cases*

A reward in two groups may be allowed by one group and blocked by another. Featured groups affect catalog presentation only; they do not alter limit logic. Time windows are per limit row, so an annual distinct cap and a monthly quantity cap can coexist on the same group.

**Configurations & Rules**

*Group properties*

| Field | Type / Values | Behavior |
|---|---|---|
| Name | text | Display label |
| Code | text (optional) | Merchant-defined identifier |
| Description | text | Member-facing copy |
| Active status | boolean | Inactive groups don't enforce |
| Featured | boolean | Catalog presentation only |
| Member rewards | reward IDs | Which rewards belong to this group |
| Limit rows | one or more | See limit configuration below |

*Limit configuration*

| Limit type | Internal `metric` | Scope | What it caps | Configurable time units |
|---|---|---|---|---|
| **Reward Type** (Max Distinct) | `distinct_reward` | `user` only | Number of distinct reward types per member | `day` / `week` / `month` / `year` / `all_time` |
| **Reward Quantity** (Group Quantity) | `quantity` | `user` or `total` | Total units across all rewards in the group | `day` / `week` / `month` / `year` / `all_time` |

Each limit row also carries an optional `window_start` / `window_end` absolute date range (lets multiple limits — e.g. "5 per month" + "20 lifetime" — coexist on the same group).

*Behavior matrix*

| Max Distinct | Group Quantity (user) | Per-Reward Quota (user) | Member outcome |
|---|---|---|---|
| 1 | — | 1 per reward | One type, 1 unit. |
| 1 | — | N per reward | One type, up to N units. |
| M (>1) | — | 1 per reward | M types, 1 unit each. |
| M (>1) | — | N per reward | M types, up to N units each. |
| 1 | 1 | — | 1 unit total, locked to one type. |
| 1 | N | — | Up to N units, all of the same type. |
| M (>1) | N (≥ M) | — | N units total, across up to M types. |
| M (>1) | 1 | — | **Rejected at save** (`CONFLICTING_GROUP_LIMITS`). |

*Operating rules*

- **Max Distinct is user-scoped.** A distinct slot is consumed only when the user redeems a reward type they have not already redeemed in that group and window.
- **Repeat-redemption rule.** Re-redeeming the same reward type does not consume another distinct slot, though reward quota or group quantity may still block it.
- **All-limits-pass.** Group quantity, per-reward quota, and Max Distinct are evaluated independently — failing any one blocks redemption.
- **Cross-group.** Each group a reward belongs to is evaluated separately.

*Limitations*

- Total-scope distinct reward counting is not supported — distinct is user-scoped.
- Save-time validation rejects contradictory configurations where user-scoped Max Distinct exceeds user-scoped group quantity on the same group.

#### Promo Code Management

**Overview**

Promo Code Management governs how reward-redemption codes are issued. Two modes: **default shared codes** (one code used by every redeemer) and **unique code pools** (a finite list of single-use codes, locked and assigned at redemption). Codes can carry batch and partner attribution for reconciliation.

**Purpose**

Some rewards (e.g., a generic "10% off") work fine as a single shared code. Others (e.g., partner-provisioned e-vouchers, single-use cinema codes) require unique codes per redemption. The same reward form supports both, and admins monitor availability through summary and list views so a unique-code reward never strands members on an exhausted pool.

**User Journey**

*Admin journey*

Admins choose the code mode on the reward form. For unique-pool rewards, they import or manage codes in batches with batch identifiers and partner attribution. The reward detail view exposes summary counts (issued, available, redeemed) and a list view for code-by-code inspection.

*Member journey*

Members never see code mechanics. At successful redemption the assigned code appears in their wallet / reward history. For multi-quantity redemptions on unique pools, codes are locked and assigned all-or-nothing — the member receives either every code or none, never a partial allocation.

**Configurations & Rules**

*Mode selection*

| Mode | Configuration | Behavior |
|---|---|---|
| Default shared | Single code string on the reward record | Reused for every redemption; no exhaustion possible |
| Unique pool | Pre-loaded list of codes per reward | Each code locked + assigned atomically; pool can exhaust |

*Per-code metadata (unique pool)*

| Field | Purpose |
|---|---|
| Code string | The actual code delivered to the member |
| Batch ID | Groups codes by upload batch for ops + reporting |
| Partner ID | Attribution for partner billing reconciliation |
| Status | Available / locked / assigned / expired |
| Assigned-to fields | User ID + redemption ID once assigned |

*Operating rules*

- **Pool checks are part of the atomic redemption transaction.** Exhaustion blocks redemption with a specific error before any wallet burn occurs.
- **Lock release on failure.** Codes locked during a transaction that subsequently fails are released, not stranded.
- **Multi-quantity all-or-nothing.** A member redeeming N units either receives N distinct codes or zero — partial allocation is never written.

*Limitations*

- Partner attribution is metadata for billing / reporting; it does not gate redemption.

#### Reward Sourcing & Partner Fulfillment

**Overview**

Reward Sourcing is an operational service Rocket layers on top of the platform `rewards` feature. It gives merchants a curated partner catalog of digital vouchers, physical goods, and lifestyle / wellness brands while charging the merchant only when a member actually redeems — no prepaid inventory sitting on the merchant's balance sheet. Two reward pools coexist:

- **Partner-network rewards (pay-per-use)** — large SKU breadth from integrated partners. Digital e-vouchers issued in near-real-time; physical rewards shipped via fulfillment partners with tracking surfaced where the partner supports it.
- **Merchant-owned privileges** — discounts, service vouchers, on-site benefits configured directly in the loyalty program. Typically no third-party procurement cost; value funded by the merchant's own services or margin.

**Purpose**

Two outcomes:

1. **Risk-free reward catalog breadth.** Merchants offer dozens to hundreds of attractive partner rewards without inventory commitment. Cost is borne only on actual redemption.
2. **Strategic reward mix tied to member lifestyle.** Rocket's Reward Strategy team designs the mix per merchant — integrating partner brands with the merchant's user base's everyday lifestyle (coffee, transport, marketplaces, beauty, wellness) and the design utility of those rewards inside the program. Three strategic aims drive every mix: bring members back, cross-sell adjacent services, and stay present between touchpoints.

**User Journey**

*Admin journey*

1. **Catalog and program setup.** From the Partner Reward Catalog view, browse SKUs by category, source, and band. Select SKUs to expose in the merchant's program; each selected SKU becomes a reward record carrying ownership and procurement metadata. Map each reward to campaigns, catalog placements, or both, and set coin pricing (tier-, persona-, and tag-specific pricing follows the standard rewards pricing matrix). For inventory-bound rewards, configure stock and reorder / alert thresholds.
2. **Monitoring and reporting.** Monitor stock levels and redemption velocity per reward and per category. Run redemption reports by reward, tier, channel, and period. Trigger reorder or partner replenishment when stock crosses the threshold — automation depth depends on the partner connector.

*Member journey*

After redemption, members receive wallet entries, codes, or delivery status consistent with the reward type — instant for digital and merchant-owned, tracked for physical.

**Configurations & Rules**

*Economics*

- **Pay-per-use (partner rewards).** Merchant is charged only for rewards members actually redeem. No upfront inventory purchase for partner-sourced catalog items unless explicitly negotiated.
- **Merchant-owned privileges.** Funded as discounts or internal services. No third-party SKU procurement.

*Fulfillment SLAs (contracted defaults, not platform-enforced guarantees)*

| Reward type | Process | Typical SLA |
|---|---|---|
| Digital e-voucher | Real-time / near-real-time procurement; code or link delivered into wallet on redeem | Instant (target) |
| Physical reward | Order to fulfillment partner → pick, pack, ship; tracking surfaced where supported | 2–5 business days standard; up to ~14 days for edge cases |
| Merchant-owned | Configured in admin; issued as privilege / voucher at redeem | Instant |
| Flash / limited | Pre-loaded finite stock; high-concurrency first-come-first-served | Instant for digital; physical follows physical row |

*Partner network and onboarding*

- New partner onboarding typically ~5 business days end-to-end (contracting + technical integration + catalog configuration). Actual timelines vary by partner.
- Seasonal / campaign partners supported via scheduled start / end on catalog visibility.
- Exact partner roster and SKU count are deal-specific; use marketing-approved numbers when quoting externally.

*Reconciliation*

- Monthly per-partner reports list codes issued, redeemed, and expired.
- Billing is based on redeemed (and billable) volume per partner agreement.

*Truth boundary*

Numeric claims about partner counts, SKU breadth, or onboarding speed are deal- and partner-mix-specific — not platform guarantees. Use deal-specific figures in proposals unless a marketing-approved canonical number exists.

---

### Tiers

**Overview**

Tiers rank members into levels based on activity over a **shared program window** — points, tickets, sales, or order count. The merchant sets one **program clock** per user type (metric, calendar year vs rolling months, upgrade timing), then defines each tier as a named level with an upgrade threshold, optional maintain threshold, personas, optional burn-rate **override**, and display. Points→discount burn defaults live on **currency settings** (`merchant_master.default_burn_rate`); tiers only override when needed. The core lens is **evaluate → apply or queue → display progress**: the member qualifies for the highest amount-based rung they meet on their persona-effective ladder; immediate upgrades apply on the event path; delayed upgrades (`end_of_month`) queue in `tier_pending_upgrades` and apply on the daily batch after re-check; daily batch also runs maintain/downgrade.

**Purpose**

Tiers turn a loyalty program from a flat ledger into a status game with a concrete next goal and a shared measurement period. Example: buyer track uses rolling 12 months of points; Member has no upgrade amount (free entry), Silver 50, Gold 80, Platinum 150 — members can skip if they hit a higher threshold in the same window.

**User Journey**

*Admin journey*

1. Set **program config** for the user type (`bff_get_tier_program_config` / `bff_upsert_tier_program_config`) — required before threshold saves and before evaluation.
2. **Conditions** — name, personas, optional burn **override**, upgrade **amounts** only (`bff_upsert_tier_with_conditions`). Merchant-wide burn default is on Currency Settings.
3. **Display** — icon, color, benefits, card design (`bff_upsert_tier_display`), independent save.
4. List order follows upgrade amounts (null first). No drag-reorder ranking; no entry-tier flag.

*Member journey*

1. New member receives a free-entry rung only if their persona ladder has a tier with no upgrade amount; otherwise they start with no tier until they earn in.
2. Purchase / wallet events evaluate via Inngest tier routers → `process_tier_event`.
3. Member card shows current tier (nullable), next tier, progress, maintain deadline, display assets.
4. Points→discount at checkout uses `get_user_burn_rate` → `fn_resolve_burn_rate` (merchant default, else tier override).
5. At maintain deadlines, daily batch maintains or downgrades to the best still-qualified lower rung.

*Edge cases*

- Delayed upgrades are not current tier until applied.
- Members can skip rungs (highest qualifying amount wins).
- Refunds reduce progress via ledger sums.
- Persona-assigned tiers do not apply to members outside those personas; unassigned tiers apply to all.
- Benefit lines are display-only.

**Configurations & Rules**

*Program config — one row per merchant × user type (`tier_program_config`)*

| Field | Values | Purpose |
|---|---|---|
| `metric` | `points` / `ticket` / `sales` / `orders` | Shared measurement |
| `period_type` | `calendar_year` / `rolling` | Window shape |
| `period_start_month` | 1–12 | Required for calendar year |
| `rolling_months` | 1–36 | Required for rolling |
| `upgrade_timing` | `immediate` / `end_of_month` | When upgrade applies |
| `maintain_mode` | `lifetime` / `period` | lifetime = never auto-downgrade; period = re-check current upgrade amount each period |
| `program_start_date` | date or null | Optional clamp on window start |

*Tier master — per tier*

| Field | Purpose |
|---|---|
| `tier_name`, `user_type`, personas via `tier_persona_assignments` | Identity and ladder scope |
| `burn_rate` (optional override), `icon`, `color`, `benefits`, `card_design` | Override + display; default burn on `merchant_master.default_burn_rate` |

Ladder order and free entry are **derived** from active upgrade amounts (`v_tier_ladder` / `fn_tier_ladder_for_user`). Stored `ranking` and `entry_tier` were removed.

*Tier conditions — upgrade thresholds only*

| Field | Values | Purpose |
|---|---|---|
| `condition_type` | `upgrade` (maintain rows removed) | Entry threshold |
| `amount` | numeric | Upgrade threshold; under period mode this is also the maintain bar for members currently on this rung |
| `active_status` | boolean | Soft disable |

One active upgrade per tier. Unique active upgrade **amount** per merchant × user type. No separate maintain amount.

*Operating rules*

- Highest qualifying rung by amount wins; skip allowed.
- Free entry = null upgrade amount on the persona-effective ladder; otherwise start with no tier.
- `maintain_mode=lifetime` → no deadlines / no auto-downgrade; `period` → deadline from program clock, fail if metric < current upgrade amount.
- Single apply writer: `apply_tier_change` (with change type) via evaluation path; ledger via `chokepoint_post_tier_change`.
- Pending upgrades re-verify at effective date.
- Maintain failure → highest qualifying lower rung (or no tier if none and no free entry).
- Downgrade lock on `user_accounts` still blocks automatic downgrade when set.
- Conditions and display save independently.

*Limitations*

- Live period types are only `calendar_year` and `rolling`.
- Upgrade timing live options are `immediate` and `end_of_month`.
- Tier benefits are display-only.
- `tier_master.persona_id` is compatibility-only; multi-persona uses `tier_persona_assignments`.
- Admin FE must stop sending retired ranking / per-condition window fields (`UNSUPPORTED_FIELDS`). See `docs/TIER_PROGRAM_CONFIG_FE_BRIEF.md`.

#### Tier Upgrade

Configured by upgrade **amount** on each tier; timing from program `upgrade_timing`.

| Timing | Effect |
|---|---|
| `immediate` | Applied in the same evaluation that qualifies |
| `end_of_month` | Queued in `tier_pending_upgrades`; daily batch applies after re-check |

Skipping, one pending row per user×merchant (UPSERT), and re-verification at effective date remain. Applies go through `apply_tier_change`.

#### Tier Maintenance

Controlled by program `maintain_mode`. Under `period`, deadline comes from the program clock via `calculate_maintain_deadline`; failure downgrades to the best still-qualified lower amount rung (floor with null upgrade amount never fails maintain). Under `lifetime`, no automatic downgrade. Downgrade lock on `user_accounts` still applies when set.

#### Tier Progress

Member-facing progress from `get_user_tier_progress` / related summary APIs: current/next tier (nullable current), progress percents, deadlines, display assets. No ranking keys. Progress refreshes on qualifying events and after tier changes; daily batch reconciles maintain.

---

### Currency

**Overview**

Currency is the wallet and earning engine for loyalty points and tickets. **Points** are fungible — all points interchangeable in a single balance. **Tickets** are non-fungible — each ticket type ("Raffle Tickets", "Birthday Voucher", "VIP Access Pass", "Parking Pass", "Shopify Store Credit") tracks its own balance and cannot be exchanged for another type. Merchants configure how members earn currency through **earn factor groups** (containers that hold shared window, active, and stacking settings) and **earn factors** inside them (rates that convert purchase amount to currency, or multipliers that increase the base award). The core lens is **calculate → schedule → post**: a qualifying event runs through the calculation engine to produce currency rows, an Inngest workflow holds those rows for any configured delay, and a single chokepoint writes them to the wallet ledger.

**Purpose**

Currency is the "earn" side of the loyalty loop — the mechanism that converts member activity into tangible value they can later spend on rewards. Without it, every other loyalty feature (tiers, rewards, missions, referrals, campaigns, AMP) has nothing to award. The configuration model is deliberately broad: merchants can run a single conversion rate, a multi-currency program with tickets for events and credits for an e-commerce platform, time-bound multipliers on specific products, tier-based earning, persona-specific offers, or all of these simultaneously — without writing code. Reversals, expiry, and award timing are first-class so the financial liability matches the business model rather than being hard-coded.

**User Journey**

*Admin journey*

1. Optionally configure **ticket types** before using ticket awards (points awards need no target entity).
2. Create an **earn factor group** with shared window, active flag, and stackability.
3. Add **earn factors** to the group — rates (THB-per-unit conversion for a target currency, plus ticket type if rewarding tickets) and multipliers (decimal bonuses applied to a target currency).
4. Optionally attach **earn conditions** — product, tier, persona, store, or threshold filters. Use `exclude = true` only for product exclusions inside a conditions group.
5. Set each factor's **purchase status policy** (`allowed_purchase_statuses`) — `['completed']` by default, or include `pending` for event/booking flows that need to award before fulfilment.
6. Set the merchant's **award timing** — immediate, calendar-day delay, rolling-minute delay, or fixed time-of-day in a timezone.
7. Configure **expiry** — points expiry at merchant level, ticket expiry per ticket type.
8. Review **wallet ledger** entries, **inngest workflow log**, and per-currency expiry rows for troubleshooting.

*Member journey*

1. Member earns currency from any configured source — purchase, mission, referral, campaign, manual adjustment, AMP workflow, or activity.
2. If the merchant configured a delay, the award is held by Inngest until the calculated award time and may not appear in the balance immediately.
3. Wallet views show points and tickets separately, with per-ticket-type balances and full ledger history.
4. Expiry views surface the expiry date and remaining deductible balance per earning event.
5. Refunds or cancellations produce reversal rows that reduce balances and feed back into tier progress.
6. At redemption, points reduce the points balance directly; standard tickets reduce the per-type balance; credit tickets call out to the external platform (e.g., Shopify) and record the burn in the same ledger.

*Edge cases*

- Two rate factors for the same target currency — only the best rate (lowest THB-per-unit) wins; the other is silently ignored.
- A pending purchase event should not block a later completed event for the same purchase (deduplication keys include purchase status).
- Tickets must always carry a `target_entity_id`; points must always have `target_entity_id = NULL`.
- A delayed award can be cancelled before posting if the source transaction is refunded — Inngest cancels on `(source_type + source_id)`.
- Currency earned near a fixed-frequency expiry boundary is protected by the minimum-period setting.
- Ticket type with `is_credit = true` and no `credit_platform` set is invalid configuration.
- A reversal always uses the *original* rate and multipliers from the historical award, not current rules.

**Configurations & Rules**

*Currency types*

| Type | Storage | Fungibility | `target_entity_id` rule | Typical use |
|---|---|---|---|---|
| Points | `user_wallet.points_balance` | Fungible — single balance | Always `NULL` | General loyalty currency |
| Ticket (standard) | `user_ticket_balances` per `ticket_type_id` | Non-fungible per type | Always = `ticket_type.id` | Raffles, vouchers, access passes, parking |
| Ticket (credit) | `user_ticket_balances` per `ticket_type_id` | Non-fungible per type | Always = `ticket_type.id` | Platform credits (Shopify, WooCommerce) — redemption calls external API |

*Earn factor groups — fields*

| Field | Type / Values | Purpose |
|---|---|---|
| `name` | text | Display name (e.g., "Q2 2024 Earning Rules") |
| `active_status` | boolean | Master switch for all factors in the group |
| `window_start` / `window_end` | timestamptz | Program duration — inherited by factors unless overridden |
| `stackable` | boolean | Whether multiple multipliers in this group combine, or only best wins |

*Earn factors — every field an admin sets*

| Field | Type / Values | Purpose |
|---|---|---|
| `factor_type` | enum — `rate` / `multiplier` | What this factor does — convert amount, or multiply base |
| `target_currency` | enum — `points` / `ticket` | Which currency the factor rewards |
| `target_entity_id` | uuid → `ticket_type.id` or NULL | Required for ticket targets, must be NULL for points |
| `earn_factor_amount` | numeric | Rate: THB per 1 currency unit (lower = better). Multiplier: decimal (e.g., `2.0` = 2x) |
| `public` | boolean | `true` = all eligible members. `false` = personalized (assigned via `earn_factor_user`) |
| `allowed_purchase_statuses` | text[] | Purchase statuses that may trigger this factor. Default `['completed']`. Set `['pending','completed']` for early-earning flows |
| `window_start` / `window_end` | timestamptz | Optional override of group window |
| `active_status` | boolean | Independent on/off per factor |
| `earn_conditions_group_id` | uuid | Optional eligibility gate — may be shared across factors |

*Public vs personalized offers*

| Distribution | Configured via | Use case |
|---|---|---|
| Public | `earn_factor.public = true` | "Standard 100 THB = 1 point", "Gold members 2x permanent" |
| Personalized | `earn_factor.public = false` + row in `earn_factor_user` with `window_end` | "Birthday 5x for Sarah", "Welcome-back triple points", "VIP exclusive 10x this week" |

Public and personalized factors are evaluated together in every transaction; the best applicable combination wins.

*Property inheritance — group → factor*

| Setting | Inherited from group when factor's value is NULL | Override behavior |
|---|---|---|
| `active_status` | Yes | Factor active flag can independently turn it off |
| `window_start` / `window_end` | Yes | Factor window completely replaces group window |
| `stackable` | Inherited from group (group-level only) | — |

If neither group nor factor sets a window, the factor runs indefinitely while active.

*Earn condition entities — what a condition can filter on*

| `entity_type` | Filters on | Supports `exclude = true`? | Operator semantics |
|---|---|---|---|
| `product_sku` | Specific SKU variants | Yes | OR / AND / EACH |
| `product_product` | Product types | Yes | OR / AND / EACH |
| `product_brand` | Brands | Yes | OR / AND / EACH |
| `product_category` | Categories | Yes | OR / AND / EACH |
| `tier` | Member's current tier | No (always include) | Implicit OR |
| `persona` | Member's persona | No (always include) | Implicit OR |
| `store` | Store attributes / IDs | No (always include) | OR / AND / EACH |

`exclude = true` is only valid for product entity types. Tier, persona, and store conditions are always include-only transaction-wide gates.

*Threshold configuration — for product conditions*

| Field | Type / Values | Purpose |
|---|---|---|
| `threshold_unit` | `quantity_primary` / `quantity_secondary` / `amount` / NULL | Which measurement is checked |
| `min_threshold` | numeric | Minimum to qualify — below this the factor does not apply |
| `max_threshold` | numeric | Cap — multiplier still applies but above this is ignored (abuse protection) |
| `apply_to_excess_only` | boolean | `false` = multiplier on full matched amount. `true` = multiplier only on quantity / value above min |

| Threshold unit | Source column | Use case |
|---|---|---|
| `quantity_primary` | `purchase_items_ledger.quantity` (e.g., bags, pieces) | "Buy ≥50 bags of cement → 5x" |
| `quantity_secondary` | `purchase_items_ledger.quantity_secondary` (e.g., tonnes, pallets) | "Buy ≥2 tonnes of steel → 10x" |
| `amount` | `purchase_items_ledger.line_total` | "Spend ≥5000 THB on electronics → 3x" |

*Condition operators — when multiple entity rows in a condition*

| Operator | Behavior | Used for |
|---|---|---|
| `OR` (Aggregate) | Sum quantities/amounts across matches; check threshold on total | "Spend ≥5000 across Shoes OR Apparel" |
| `AND` (All Required) | All entities must appear; each checked individually | "Buy at least 1 of A AND 1 of B" |
| `EACH` (Independent) | Each entity evaluated independently; only those meeting threshold are included | "For each SKU bought ≥10 units, 2x" |

Tier and persona conditions always behave as implicit OR since the user has a single value.

*Multiplier calculation mode — merchant-level `multiplier_additive`*

| Mode | `multiplier_additive` | Formula | 5x on 10K base equals |
|---|---|---|---|
| Total Rate (default) | `false` | base × (M − 1) bonus, total = base × M | 50,000 total (5× base) |
| Additive | `true` | base × M bonus, total = base × (M + 1) | 60,000 total (6× base) |

Lets merchants pick the multiplier semantics that match their existing program math.

*Stacking — when multiple multipliers qualify*

| Group `stackable` | Behavior | Special exception |
|---|---|---|
| `true` | All qualifying multipliers compound (2x tier × 1.5x weekend = 3x) | — |
| `false` | Best multiplier per scope wins | One product-specific *and* one transaction-wide may coexist (different amount portions) |

The "amount-portion isolation" rule: product-specific multipliers consume the matched portion of the transaction; transaction-wide multipliers apply only to what's left. This allows simultaneous "Shoes 3x" + "Birthday 5x" without double-multiplying any THB.

*Currency components — how an award is categorised in the ledger*

| Component | Source | Sign |
|---|---|---|
| `base` | Rate factor conversion | Positive on earn |
| `bonus` | Multiplier factor uplift | Positive on earn |
| `adjustment` | Admin manual correction | Positive or negative |
| `reversal` | Refund / cancellation deduction | Negative |

`wallet_ledger.transaction_type` is `earn` or `burn`. `amount` is always positive; `signed_amount` is directional.

*Source types — what triggers a wallet award*

| Source | Trigger | Calculation path |
|---|---|---|
| `purchase` | CDC on `purchase_ledger` | `calc_currency_for_transaction` — full earn-factor evaluation |
| `referral` | CDC on `referral_ledger` | Fixed amounts from `referral_invitee_outcomes` |
| `mission` | CDC on `mission_claims` | Fixed amounts from `mission_outcomes` |
| `campaign` | API call with metadata | Fixed amount from `p_metadata` |
| `manual` | Admin action with metadata | Fixed amount from `p_metadata` |
| `amp` | AMP workflow action (`award_points` / `award_tickets` / `award_currency`) | Fixed amount; must include `dedup_key` when source can replay |

All sources flow through the same Inngest workflow and the same `chokepoint_post_wallet_transaction` writer.

*Rate selection — one rate per currency wins*

| Step | Rule |
|---|---|
| 1 | Filter all rate factors by target currency × target entity (points alone, or ticket type) |
| 2 | Sort by `earn_factor_amount` ascending (lower THB per unit = better for member) |
| 3 | Pick the lowest |
| 4 | Apply FLOOR() to ensure whole-number awards |

Two rate factors for the same `(target_currency, target_entity_id)` and same eligibility — only the cheapest applies; the other is silently dropped.

*Award timing — `merchant_master` columns*

| Column | Type | Effect |
|---|---|---|
| `currency_award_delay_days` | integer | Calendar-day delay (0 = no delay) |
| `currency_award_delay_minutes` | integer | Rolling-minute delay (0 = no delay) |
| `currency_award_time` | time | Time of day to award |
| `currency_award_timezone` | text | IANA timezone for `award_time` (e.g., `Asia/Bangkok`) |

| Precedence | Configuration | Behaviour |
|---|---|---|
| 1 | `delay_days > 0` | Award on `today + delay_days` at `award_time` |
| 2 | `delay_minutes > 0` | Award `now + delay_minutes` (ignores `award_time`) |
| 3 | `award_time` only | Same day at `award_time`, or next day if past |
| 4 | Nothing set | Immediate award |

While an award is delayed, the Inngest workflow holds it — a refund of the source purchase cancels the pending award via `cancelOn` matching `(source_type + source_id)`. No DB "pending" table needed; workflow state IS the pending state.

*Ticket type — per-type config*

| Field | Type | Purpose |
|---|---|---|
| `name` | text | Display name ("Christmas Raffle 2024") |
| `ticket_code` | text | Stable identifier per merchant |
| `is_credit` | boolean (default `false`) | Marks the type as a platform credit |
| `credit_platform` | text | `shopify`, `woocommerce`, etc. — required when `is_credit = true` |
| `metadata.ticket_to_credit_rate` | numeric | Tickets per 1 unit of platform currency (only for credit types) |
| `metadata.shopify_currency` | text | Currency for the external credit call (e.g., `THB`) |
| `metadata.code_prefix` / `code_length` / `code_charset` | text | Optional — for ticket types using unique printable codes |
| Expiry settings | per ticket type | TTL months, fixed-frequency, or absolute-date (see expiry table) |

Unique index `(merchant_id, credit_platform) WHERE is_credit = true` — at most one credit ticket type per platform per merchant. Earn path is identical for credit and standard tickets; only the redemption path branches.

*Ticket codes — unique printable codes per ticket earned*

Optional per ticket type. Used for raffles, lucky draws, and event campaigns. Pre-generated into a pool, atomically assigned when a member earns the ticket, and bidirectionally stamped on both `ticket_code` and `wallet_ledger.metadata.ticket_codes[]` for two-way lookup. Ambiguous characters (`0/O`, `1/I/L`) are excluded from the default charset.

*Currency expiry — configuration matrix*

| Scope | Configured at | Supported modes |
|---|---|---|
| Points | Merchant level (uniform for all members) | TTL, Fixed Frequency |
| Tickets | Per `ticket_type` | TTL, Fixed Frequency, Absolute Date |

| Mode | Behaviour | Example |
|---|---|---|
| TTL (Time-To-Live) | Each award expires individually `X` months after earning | "Points expire 12 months after earning" |
| Fixed Frequency | All currency in the period expires at the period end | "All Q2 points expire 30 Jun" — monthly / quarterly / semi-annual / annual cadences supported; aligns to merchant fiscal year-end month |
| Absolute Date (tickets only) | All tickets of a type expire on one specific calendar date | "All Christmas raffle tickets expire 31 Dec 2024" |

| Protection / setting | Purpose |
|---|---|
| Minimum period | Currency earned close to a fixed-period boundary is protected for at least `N` months even if the fiscal period ends sooner (e.g., points earned in November with quarterly expiry and 6-month minimum survive until June, not December) |
| Pre-expiry notification windows | Configurable for 7 / 30 / 60 days before expiry — drives merchant comms / campaigns |
| Expiry reversal | Customer-service path to restore mistakenly-expired currency |
| Deductible balance | Only the *unused* portion of an earning event can expire; redemption draws from the same pool |

*Daily expiry processing*

- Runs every day at 02:00 in the merchant's configured timezone.
- Pre-check returns in under 1 second on days with nothing to expire.
- Atomic per-row updates — wallet balance and expiry record updated in the same transaction.
- Comprehensive logging with daily success / failure summary for the finance team.

*Currency reversal — refund and cancellation handling*

| Scenario | Reversal behaviour |
|---|---|
| Full product return | All currency from that purchase reversed across every currency type awarded |
| Partial return | Proportional — 40% refund = 40% currency reversal |
| Order cancellation | If currency already awarded, full reversal; if still pending in Inngest, the pending workflow is cancelled (no DB write) |
| Disputed transaction / chargeback | Automatic reversal triggered by the payment integration |

| Principle | Effect |
|---|---|
| Historical calculation | Reversals use the *original* rates and multipliers from the historical award — current rules are ignored |
| Multi-currency | Each currency type reversed independently — points to points, each ticket type to its own balance |
| Tier impact | Reversal flows through metric sums and triggers tier re-evaluation; downgrade possible if member drops below maintenance |
| Balance protection | Default behaviour prevents the balance going negative — partial reversal records the remaining "unreversed" amount for audit |

| Reversal timing mode | Behaviour |
|---|---|
| Immediate | Currency deducted instantly on refund — preferred for digital / online |
| Batch | Reversals queued and processed periodically — preferred for high-volume retail |

*Operating rules*

- **Calculate → schedule → post.** Calculation produces currency rows; Inngest holds them for any configured delay; `chokepoint_post_wallet_transaction` is the single canonical writer for `wallet_ledger`. Direct inserts from elsewhere are forbidden.
- **Best rate wins per `(currency, target_entity_id)`.** Only one rate factor applies per currency target — multiple qualifying rates collapse to the cheapest.
- **No-condition factors apply to all purchases** (subject to active, window, and `allowed_purchase_statuses` policy).
- **Tickets need a target.** Every ticket transaction has `target_entity_id = ticket_type.id`; every points transaction has `target_entity_id = NULL`.
- **Idempotency at four levels** — Kafka offset, Redis dedup (`source_type + source_id + status` for purchases), Inngest event ID, and a DB uniqueness constraint on `(source_type, source_id, currency, component, target_entity_id)` plus optional `dedup_key`.
- **Cancellation is precise.** Refund cancels only the specific source's pending award via `cancelOn` matching `(source_type + source_id)`.
- **Conditions answer "who/what qualifies"; status answers "when."** Purchase-status policy lives on `earn_factor.allowed_purchase_statuses`, not in conditions.
- **Reversal uses history, not current rules.** Original factor IDs, rates, and multipliers are stored at award time so refunds reverse correctly even after rule changes.
- **AMP / system wallet awards are fixed amounts**, not earn-factor calculations — they must include `dedup_key` when the trigger can replay.

*Limitations*

- Purchase currency is not triggered by database triggers on `purchase_ledger`. Production path is CDC → Render `crm-event-processors` → Inngest → wallet chokepoint.
- Tickets are not interchangeable across ticket types — there is no convert-ticket-A-to-ticket-B operation.
- Absolute Date expiry is supported for tickets only, not points.
- `realtime` award timing is the natural default; "immediate" award still flows through Inngest (the workflow simply does not sleep).
- Two rate factors for the same `(target_currency, target_entity_id)` with the same eligibility — one is silently ignored. Use separate conditions groups or remove the redundant factor.
- Shared `earn_conditions_group` rows mean editing the group affects every linked factor simultaneously — the admin UI surfaces this coupling before allowing edits.

---

### Forms

**Overview**

Forms control what data the platform collects from members — during signup, on the profile page, and through standalone surveys. Two field systems work in parallel: **default profile fields** (standard data like name, email, phone, and address) stored directly on `user_accounts` and `user_address`, and **custom fields** (merchant-defined questions like "preferred outlet" or "interests") stored through `form_templates`, `form_fields`, `form_submissions`, and `form_responses`. A special published `USER_PROFILE` form surfaces custom fields inside the profile flow; any other published template behaves as a survey. The core lens is **template → render → validate → store**, with the same frontend shape supporting "new" and "edit" modes — edit mode overlays previously-saved values for default fields, custom fields, and PDPA consent.

**Purpose**

Forms is the data-collection backbone for everything downstream — segmentation, personalization, persona assignment, PDPA-adjacent profile data, and survey-based engagement. Merchants need to ask different questions of different members (a "trade pro" persona sees one set, a "consumer" persona sees another), enforce different validation, and reward completion when it matters. Survey completion rewards turn forms into a small acquisition / engagement loop, while the unified profile flow keeps signup and ongoing profile updates on one configuration surface.

**User Journey**

*Admin journey*

1. Configure **default profile fields** in `user_field_config` — label, type, placeholder, validation, required flag, visibility, editability, options, ordering, and persona filters.
2. Build **custom forms** in the form-builder: create a template, add field groups, add fields, attach options to choice fields, and define conditional logic between fields.
3. **Publish the `USER_PROFILE` template** when custom profile fields should appear in member profile flows. Other published templates behave as surveys.
4. For surveys, configure optional **submission limits** (per-user or total) and optional **completion reward** settings — currency, ticket type (if rewarding tickets), amount, and frequency.
5. Save reward config via `bff_upsert_form_reward_workflow` — this creates a hidden system AMP workflow that handles the award.
6. Monitor submissions and responses; troubleshoot via `form_submissions` and `form_responses` rows.

*Member journey*

1. Frontend calls `bff_get_user_profile_template` in new or edit mode and renders the returned `default_fields_config`, `custom_fields_config`, persona data, and PDPA sections.
2. Member edits fields; the frontend updates the local response object and debounces saves.
3. On save, `bff_save_user_profile` writes default fields, address fields, selected persona, custom field responses, consent acceptance, channels, and topics.
4. For standalone surveys, user-facing APIs list available surveys, load one by ID or code, submit answers, and return a reward outcome.
5. Reward outcomes distinguish: no reward configured, unidentified user (anonymous), already completed (limit reached), or eligible and pending processing.

*Edge cases*

- **Anonymous survey submissions** can be stored, but wallet rewards require a resolved user — per-user limits cannot apply to anonymous submitters.
- **Edit mode must preserve empty arrays** — an empty multi-select stays as `[]`, not SQL null.
- **Multi-select fields use array values** on both render and save.
- **Profile field visibility can change after persona selection** — selecting a persona may reveal or hide fields whose `persona_filters` match.
- **Conditional required fields** only become mandatory when their condition applies; if the trigger field is empty, the dependent field is not required.
- **Disabled reward saves preserve existing config** — turning off the reward should not wipe the stored configuration.
- **Ticket rewards require an active ticket type** — saving with an inactive or missing ticket type is rejected.

**Configurations & Rules**

*Two field layers*

| Layer | Where configured | Where values are stored | Visibility scope |
|---|---|---|---|
| Default fields | `user_field_config` (per merchant) | `user_accounts`, `user_address` | Standard profile fields — name, email, phone, address |
| Custom fields | `form_templates` + `form_field_groups` + `form_fields` + `form_field_options` + `form_conditions` | `form_submissions` + `form_responses` (one submission row, one response row per answered field) | Merchant-defined — appear inside `USER_PROFILE` (profile flow) or in standalone surveys |

*Default field configuration — properties on `user_field_config`*

| Property | Purpose |
|---|---|
| `label` | Display name shown to the member |
| `type` | Field type (drives renderer — text input, choice picker, etc.) |
| `placeholder` | Inline hint text |
| `validation` | Validation rules applied before save (format, length, required-when) |
| `required` | Whether the member must fill the field |
| `visibility` | Whether the field is rendered at all |
| `editability` | Whether the member can change the value after first save |
| `options` | For choice fields — the option list |
| `ordering` | Display sort order |
| `persona_filters` | Which personas the field appears for |

*Custom form structure*

| Object | Holds | Notes |
|---|---|---|
| `form_templates` | Top-level form definition (name, code, active/published status, type) | `USER_PROFILE` is the reserved template that powers the custom-fields portion of the profile flow |
| `form_field_groups` | Logical groupings of fields within a template | Drives section breaks in the rendered form |
| `form_fields` | Individual fields — label, type, validation, required flag, ordering, group | Members fill one of these per question |
| `form_field_options` | Options for choice fields (radio, select, multi-select) | Each option has a label and value |
| `form_conditions` | Conditional logic between fields | One field's value controls behavior on another |

*Conditional logic — what conditions can do*

| Action | Effect on the target field |
|---|---|
| Show | Render only when the condition matches |
| Hide | Remove from render when the condition matches |
| Enable | Make editable only when the condition matches |
| Disable | Make read-only when the condition matches |
| Require | Make mandatory only when the condition matches |

*Submissions and responses*

| Table | Holds | Lifetime |
|---|---|---|
| `form_submissions` | One row per submission event — template, user (if known), timestamp, status | Persisted indefinitely |
| `form_responses` | One row per answered field, linked to a submission | Persisted indefinitely; multi-select stored as array |

*Special form — `USER_PROFILE`*

| Behavior | Detail |
|---|---|
| Reserved code | `USER_PROFILE` is a single canonical template per merchant |
| Required for active custom profile fields | Must be **published** to serve custom fields inside the profile flow — unpublished templates do not render |
| Always unlimited | Submission limits do not apply to `USER_PROFILE`; members can edit profile any number of times |
| Powers both new and edit mode | Same template renders signup-time onboarding and ongoing profile edits — edit mode overlays saved values |

*Survey submission limits*

| Mechanism | Storage | Behavior |
|---|---|---|
| Per-survey limits | `transaction_limits` with `entity_type = 'form'` | Enforced by `submit_form_public` before insert |
| Per-user limits | Same table, scoped to user | Cannot apply to anonymous submitters |
| `USER_PROFILE` exemption | — | Unlimited, regardless of any `transaction_limits` rows |

*Survey completion reward — config surface*

| Field | Purpose |
|---|---|
| Reward enabled flag | Master on/off for the survey's completion reward |
| Currency type | Points or ticket |
| Ticket type | Required when currency is `ticket`; must reference an active `ticket_type` |
| Amount | Currency units awarded on completion |
| Frequency | How often a single member can be rewarded (once vs. on every completion — controls dedup key construction) |

| Helper | Purpose |
|---|---|
| `bff_get_form_reward_workflow_config` | Loads existing reward config for the form-builder UI |
| `bff_upsert_form_reward_workflow` | Saves config; validates currency, ticket type, amount, and frequency before persisting |

Survey reward workflows are stored as **hidden system AMP workflows** — they execute through the same AMP infrastructure but should not surface in the marketer's workflow list, so they don't clutter the workflow library or get edited by accident.

*Reward outcome states returned to the member-facing app*

| Outcome | Meaning |
|---|---|
| No reward configured | Survey has no completion reward — submission succeeded |
| Unidentified user | Anonymous submission — wallet award skipped (no user to credit) |
| Already completed | Member has hit the configured frequency / limit — no reward issued this time |
| Eligible — pending | Submission accepted; reward queued through the hidden AMP workflow |

*BFF surface*

| BFF | Used by | Purpose |
|---|---|---|
| `bff_get_user_profile_template` | Member app | Returns rendered template (default_fields_config, custom_fields_config, persona data, PDPA sections) in new or edit mode |
| `bff_save_user_profile` | Member app | Persists default + address + persona + custom responses + consent + channels + topics in one call |
| `bff_get_form_reward_workflow_config` | Admin builder | Loads existing survey reward config |
| `bff_upsert_form_reward_workflow` | Admin builder | Saves survey reward config and creates / updates the hidden AMP workflow |
| `submit_form_public` | Public survey APIs | Validates form limits, validates required + conditional fields, then persists the submission and responses |

*Operating rules*

- **Template → render → validate → store.** No data lands in `form_submissions` / `form_responses` (or in `user_accounts` for default fields) until validation passes.
- **Default fields write to user tables; custom fields write to form tables.** The two layers are stored separately even though they share a render surface.
- **Conditions are evaluated at render and at validation.** A field hidden by condition is not validated; a field made required by condition is enforced before save.
- **Published templates only.** Unpublished templates do not render, even if their fields are configured.
- **Survey reward idempotency**. "Once per user" uses one dedup key shape; "every submission" uses another — both flow through the hidden AMP workflow.
- **Multi-select fields always use arrays** in both render state and saved responses. Empty selections remain `[]`, not null.
- **Anonymous submissions are allowed for surveys** but never trigger a wallet reward.

*Limitations*

- Anonymous submitters cannot receive wallet rewards or be tracked against per-user limits.
- Survey reward workflows are intentionally hidden from the standard workflow library — they're system-managed, not user-editable through the workflow UI.
- `USER_PROFILE` is the only template that bypasses submission limits; other templates always check limits before storing.
- Per-user limits depend on user identity at submission time — a member who submits anonymously and then signs in cannot retroactively claim the reward against the earlier submission.
- Conditional logic operates between fields within a single template; cross-template conditions are not supported.

---

### PDPA Consent

**Overview**

PDPA Consent is the platform's mechanism for capturing and storing a member's data-processing consent and communication preferences. It rides on the unified profile flow: when a member fills the profile template, the same save call (`bff_save_user_profile`) persists default fields, address fields, persona, custom responses, **consent acceptance**, **channels** (which messaging channels the member opts into), and **topics** (what categories of message they consent to receive). There is no separate consent feature surface for the member — consent is part of the profile, and revoking is part of editing the profile.

**Purpose**

Loyalty platforms have to demonstrate that a member knowingly opted in before any marketing message, automated nudge, or AMP workflow can target them. PDPA Consent gives merchants a single capture point tied to the same profile flow members already use, so the act of consenting is part of the member's natural data-collection path — not a separate compliance form. Channel-level and topic-level granularity lets a member say "yes to LINE pushes, no to email" or "yes to product updates, no to surveys" without having to refuse all communication.

**User Journey**

*Admin journey*

1. Configure the PDPA section of the `USER_PROFILE` form — what consent text members see, which channels are exposed, which topic categories are exposed.
2. Capture happens automatically on every profile save; admins do not configure per-member consent.

*Member journey*

1. During signup or profile edit, the member sees the PDPA sections rendered as part of `USER_PROFILE`.
2. Member ticks or unticks consent acceptance, selects channels, selects topics.
3. On save, `bff_save_user_profile` writes consent acceptance, channels, and topics alongside the other profile data.
4. Downstream features (AMP workflows, broadcast campaigns, marketing messages) read consent state when deciding whether a member is reachable on a given channel for a given topic.

*Edge cases*

- Anonymous members cannot record consent — only an identified user can save PDPA state.
- Consent revocation is done by re-saving the profile with the relevant boxes unticked.

**Configurations & Rules**

*Captured per save*

| Field group | What it carries |
|---|---|
| Consent acceptance | The boolean / acknowledgment that the PDPA terms have been agreed to |
| Channels | Which messaging channels the member is reachable on |
| Topics | Which message categories the member opted into |

*Operating rules*

- Consent is captured through the **same `bff_save_user_profile` call** as the rest of the profile — there is no separate consent-only endpoint.
- Channel and topic granularity lets downstream sends filter the audience before dispatch.
- Profile re-save is the canonical way to revoke or modify consent.

*Limitations*

- No own knowledge-block content beyond what the Forms feature surfaces — PDPA Consent is implemented as a section of the Forms profile flow, not a standalone module.
- No admin-side per-member consent management is documented in the knowledge blocks; consent is member-initiated through the profile flow.

---

### Packages

**Overview**

Packages are merchant-defined bundles of rewards granted to a specific user as a multi-use, balance-tracked entitlement set. A package template lists one or more rewards with a per-reward quantity, where each item is either **mandatory** (auto-materialized when the package is assigned) or **elective** (the member picks within a group-and-cap constraint). When the package is assigned, the system materializes one ledger row per mandatory reward; each row tracks total grant, used count, and expiry. Members consume entitlements one use at a time at the point of service via `api_use_entitlement`. Packages exist alongside single rewards: a single reward is a one-shot coupon, while a package entitlement is a balance that draws down over time and expires by date.

**Purpose**

Packages fit business models where the value lies in a *bundle*, not a one-shot coupon. Healthcare visit packs ("5 OPD visits + 2 lab tests + 1 wellness check"), corporate welcome bundles, subscription-style perks, and tiered persona benefits all benefit from a single assignable unit that the member sees as one package on their profile but can draw down individually. The mandatory / elective split lets merchants combine "everyone gets X" with "pick 2 of these 5" so one template covers both fixed-and-flexible programs.

**User Journey**

*Admin journey*

1. **Build the catalog.** From the Packages list, admin lands on a list returned by `bff_admin_get_package_list`. Drill into a package via `bff_admin_get_package_detail`. Create / edit through one upsert — `bff_upsert_package_with_items` — which takes the package fields and the full item list; items absent from the call are deleted (update-by-ID pattern).
2. **Assign to users.** Single or batch through `bff_admin_assign_package` — payload is `{package_id, source_type, assignments:[{user_id, effective_from, effective_to}]}`. The function loops, creates one `package_assignment` row per user, and immediately calls `fn_create_package_entitlements` to materialize mandatory items into the redemption ledger.
3. **Inspect a user's packages.** `bff_admin_get_user_packages(p_user_id)` returns each assignment with nested entitlements (per-reward `qty`, `used_qty`, `remaining`, `use_expire_date`, `used_status`).
4. **Adjust an entitlement.** `bff_admin_adjust_entitlement(p_redemption_id, p_qty_change, p_reason)` raises or lowers a single ledger row's total `qty`. Cannot reduce below `used_qty`. Logged to `redemption_usage_log`.

*Member journey*

1. **My Packages.** Member calls `get_user_packages(p_status, p_language)` (auth.uid()-scoped) — returns assignments with localized package metadata and nested entitlements per reward.
2. **Pick electives.** When a package has elective items, the member sees the available pool and picks within `elective_max_picks` per `elective_group`. Submit calls `select_elective_items(p_assignment_id, p_selected_reward_ids)` — validates ownership, enforces caps, idempotent on re-pick.
3. **Use an entitlement.** At point of service, the redemption code is scanned. The integration calls `api_use_entitlement(p_redemption_id, p_user_id, p_store_id, p_external_ref, p_merchant_id)` which validates ownership, decrements `remaining` atomically, and returns the new balance.

*Edge cases*

- **Standard redemption guard** — `api_mark_redemption_used` rejects multi-use entitlements with *"Multi-use entitlements must be consumed via api_use_entitlement"*. POS / scanner integrations must branch on `source_type`.
- **Inactive packages** — `api_assign_package` rejects packages where `active_status = false`; `bff_admin_assign_package` does not enforce this and will assign even inactive packages.
- **No assignment-level cancellation** — admins zero remaining qty per row or set `cancelled = true` on individual ledger rows.
- Member errors surface as `"Entitlement expired"`, `"Insufficient remaining uses"`, `"Entitlement cancelled"`, or `"Not a multi-use entitlement"`.

**Configurations & Rules**

*Package template — fields on `package_master`*

| Field | Purpose |
|---|---|
| `name`, `description`, `image` | Display content |
| `price`, `points_price` | Cost if the package is purchasable |
| `validity_days` | Rolling expiry — entitlements expire `effective_from + N days` |
| `validity_date` | Fixed calendar expiry for all entitlements |
| `active_status` | Master switch — `api_assign_package` blocks inactive |
| `items` (via `package_items`) | The reward list with per-reward `qty`, mandatory / elective flag, `elective_group`, `elective_max_picks` |

*Item types*

| Type | Behavior at assignment |
|---|---|
| Mandatory | Auto-materialized into the ledger by `fn_create_package_entitlements` |
| Elective | Stays dormant until the member calls `select_elective_items` to pick within `elective_group` and `elective_max_picks` |

*Validity precedence at materialization* (set by `fn_create_package_entitlements`)

| Order | Setting | Resulting expiry |
|---|---|---|
| 1 | `package_master.validity_days` set | `assignment.effective_from + N days` (rolling) |
| 2 | else `package_master.validity_date` set | That fixed date |
| 3 | else `assignment.effective_to` set | `effective_to` |
| 4 | else | No expiry |

*Source taxonomy — `package_assignment.source_type` is free text*

| Value | Trigger |
|---|---|
| `admin` | Admin batch assignment |
| `api` | Public API call |
| `persona_assignment` | Persona Entitlements auto-grant |
| `purchase` | Purchase-triggered grant |
| `mission` | Mission completion |
| `tier_upgrade` | Tier transition |
| `campaign` | Campaign action |
| `his_event` | External healthcare information system event |

Ledger rows additionally encode `source_type='package_assignment'` and carry `package_assignment_id` for back-tracing.

*Quantity math*

| Concept | Field | Behavior |
|---|---|---|
| Total grant | `qty` | Set at materialization, adjustable via `bff_admin_adjust_entitlement` (cannot drop below `used_qty`) |
| Consumed | `used_qty` | Incremented on each `api_use_entitlement` call (default decrement = 1) |
| Remaining | derived `qty - used_qty` | Returned to FE |
| Fully consumed | `used_status` | Flips `true` when `used_qty = qty` |

*Operating rules*

- **Multi-use vs single-use redemption is separated**. `api_use_entitlement` for packages, `api_mark_redemption_used` for standard rewards — POS code must branch.
- **Source attribution is preserved** through the assignment lifetime for audit / reporting.
- **Item upsert is update-by-ID** — omitting an item from the payload deletes it from the package.

*Limitations*

- No admin endpoint to cancel a whole assignment in one call.
- `bff_admin_assign_package` does not check `active_status`; only `api_assign_package` does.
- Failed per-user assignments in a batch increment a `failed_count` but do not return per-user error reasons.

---

### Persona Entitlements

**Overview**

Persona Entitlements is a catalog layer that says "every user holding this persona automatically receives X." The `X` can be a package, a direct reward grant, or a standing benefit (period-based privilege like a 10% pharmacy discount). The same table powers B2B contract programs (Corporate, Insurance, VIP, Partner) and any policy where a persona class entitles members to a fixed set of perks. One persona can map to many entitlement rows; one row carries an `entitlement_type` discriminator (`package` / `reward` / `benefit`) plus the type-specific payload.

**Purpose**

Without Persona Entitlements, merchants would have to manually grant the same five packages and three standing benefits to every employee of an enrolled corporate account. The catalog flips that — once a user is given the persona, `fn_auto_assign_on_persona` walks the active entitlement rows and grants each one through the appropriate channel. It's the unified config layer behind contract-style B2B programs in healthcare and corporate verticals.

**User Journey**

*Admin journey*

1. **Configure a contract.** A contract is metadata stored on `persona_group_master` — `contract_type`, `company_name`, `contact_person`, `contact_email`, `contract_start`, `contract_end`, `contract_status`, `contract_metadata`. Admins manage the whole graph (group + child personas + entitlement rows) in one upsert via `bff_upsert_contract_with_levels(p_group_id, ..., p_levels)`.
2. **Browse contracts.** `bff_admin_get_contract_list(p_status, p_type)` for the list, `bff_admin_get_contract_detail(p_group_id)` for the level + entitlement tree.
3. **Ad-hoc benefits** (not tied to a persona) — insert through `bff_admin_assign_benefit(p_benefits)` for self-managed `user_benefit` rows.
4. **Inspect a user's benefits** — `bff_admin_get_user_benefits(p_user_id)` shows the full set with source attribution (persona / tier / marketing / admin / campaign).
5. **Cancel a benefit** — `bff_admin_cancel_benefit(p_benefit_id, p_reason)`.

*Member journey*

1. **See standing benefits** — `get_user_benefits()` returns the effective benefit set with category, benefit type, value, and source. Persona-sourced benefits validate at every read; if the contract expired or the persona was removed, they silently drop out.
2. **See persona-granted packages** — flow through the standard package pipeline. Members see them in `get_user_packages()` with `source_type='persona_assignment'`.
3. **Use persona-granted reward entitlements** — `entitlement_type='reward'` grants land directly in the redemption ledger and consume through the same `api_use_entitlement` endpoint.
4. **Eligibility check at point of service** — external integrations call `api_get_eligibility(p_user_identifier, p_identifier_type, ...)` for the resolved benefit set.

*Edge cases*

- Members never see benefit picker UI — benefits are not selectable.
- No expiry countdown for persona-sourced benefits — their validity is the contract's validity, not stored on the user row.
- Persona change does **not** automatically revoke prior package assignments or reward grants — they stay live in the ledger.

**Configurations & Rules**

*Three entitlement types — distinct grant paths*

| `entitlement_type` | Payload fields | What happens at auto-assign |
|---|---|---|
| `package` | `package_id` | Creates `package_assignment` (source_type=`persona_assignment`) → `fn_create_package_entitlements` materializes mandatory items |
| `reward` | `reward_id`, `qty` | Inserts a `reward_redemptions_ledger` row directly with source_type=`persona_entitlement`. Skips package indirection for simple cases ("5 parking passes") |
| `benefit` | `category`, `benefit_type`, `value` | Inserts a `user_benefit` row with source_type=`persona`, source_id=persona_id, copying the three fields |

*Two validity modes for benefits* (`fn_evaluate_user_benefits`)

| Source | Validity derivation |
|---|---|
| Persona-sourced | Computed at read time by joining `user_accounts → persona_master → persona_group_master`. Excluded if persona is inactive, contract is non-active, or `contract_end` is past |
| Self-managed (`tier` / `marketing` / `admin` / `campaign`) | Own `valid_from` / `valid_to` dates on the `user_benefit` row |

*Precedence — highest-value-per-category, not stackable*

`fn_resolve_benefit_precedence` reduces multiple benefits in the same `category` to the single best `value` via `DISTINCT ON (category) ORDER BY category, value DESC`. So a user with a 10% pharmacy discount from persona and a 15% pharmacy discount from a marketing benefit sees 15%, not 25%.

*Asymmetric revocation behaviour*

| What happens when persona changes / contract expires | Behaviour |
|---|---|
| Standing benefits | Stop appearing automatically (read-time validation) |
| Package assignments | Remain live in the ledger — must be explicitly cancelled per row |
| Direct reward grants | Remain live in the ledger — must be explicitly cancelled per row |

*Operating rules*

- **Active flag is the kill switch for new grants.** `fn_auto_assign_on_persona` skips rows with `active_status = false`. Disabling does not affect already-granted records.
- **Auto-assign is not idempotent.** Calling `fn_auto_assign_on_persona(user_id, persona_id)` twice creates duplicates — caller is responsible for de-dup.
- **No automatic trigger on persona change.** Roster importers, admin tools, and any flow that mutates `user_accounts.persona_id` must call `fn_auto_assign_on_persona` themselves.
- **Eligibility API is precedence-reduced** — `api_get_eligibility` returns one row per category at the highest value.

*Limitations*

- No automated revocation pipeline; ledger rows from prior personas must be cancelled manually.
- Benefits are read-time-only; there's no scheduled validity expiry job because validity is reconstructed on every read.
- Member-facing benefit selection is not supported — entitlements are automatic.

---

### Stored Value Cards

**Overview**

Stored Value Cards are prepaid monetary cards issued by merchants to members. Unlike points (earned through activities), cards carry a cash-equivalent balance loaded at creation or top-up time. Merchants define **card types** (face value, price, expiry rule, availability window, active status), import **physical cards** in batches with a 16-digit card number and 8-digit security code per card, and track every assignment, redemption, top-up, and expiry in a ledger. The core lens is **card type → card pool → assignment → balance use**.

**Purpose**

Stored Value Cards give merchants a way to issue cash-equivalent value separately from points-based loyalty — gift cards, VIP prepaid cards, B2B credit cards, partner-funded incentives. The card type abstraction means a merchant can run multiple denominations (THB 500, THB 2,000) and assignment modes (member self-activates, admin assigns) from the same import-and-pool model. Members see real-currency balances they can spend at the point of service, and merchants get a full transaction ledger for finance reconciliation.

**User Journey**

*Admin journey*

1. **Create a card type** — display details, value, price, expiry rule (TTL months or fixed date), availability window, active status.
2. **Import cards in a batch** — upload card numbers and security codes. The batch succeeds only if every card passes validation (format + uniqueness); one bad row rejects the entire batch.
3. **Review inventory** by card type, status, balance, import batch, and assignment state.
4. **Assign a card to a member manually** without requiring the security code when staff distribution is needed; the request must include the assigning admin.
5. **Use transaction history** for balance disputes, top-ups, redemptions, expiry.

*Member journey*

1. Receive a card through physical distribution, admin assignment, automatic campaign logic, or a future purchase flow.
2. **Self-activate** by entering the 16-digit card number and 8-digit security code.
3. On success, the card is assigned, expiry is calculated from the type's expiry rule, and balance becomes usable.
4. **View active cards** with card number, type, current balance, initial value, assigned date, expiry date, status.
5. **Spend** through `redeem_card`, **top up** eligible cards, **view history**.

*Edge cases*

- Deactivating a card type **blocks automatic assignment** but does not invalidate existing assigned cards.
- Wrong imported value cannot be retroactively fixed on already-imported cards.
- A past assignment window end prevents new assignments but does not affect usage of cards already assigned.
- Duplicate card numbers in a batch reject the whole batch (all-or-nothing).
- Top-up is allowed on **assigned** and **depleted** cards; depleted returns to assigned on successful top-up.

**Configurations & Rules**

*Card type — `card_type` fields*

| Field | Purpose |
|---|---|
| `name`, `description`, `terms` | Display content |
| `card_value` | Initial balance loaded onto each card of this type |
| `price` | What the card costs (if sold) |
| Expiry mode | TTL months *or* fixed expiry date |
| `ttl_months` | Used in TTL mode |
| Fixed expiry date | Used in fixed-date mode |
| Assignment availability window | Time window in which new cards can be assigned |
| `active_status` | Disables automatic assignment from this type |

*Card identifiers*

| Identifier | Format | Purpose |
|---|---|---|
| Card number | 16-digit | Public identifier — primary lookup |
| Security code | 8-digit | Activation gate for self-assignment |

*Assignment methods*

| Method | Behaviour |
|---|---|
| `automatic` | FIFO pick of the oldest available card, `FOR UPDATE SKIP LOCKED` for concurrency |
| `manual_with_code` | Member self-activates by entering card number + security code |
| `manual_without_code` | Admin assigns directly; request must include the assigning admin ID |

*Card status lifecycle*

| Status | Entered when | Allowed actions |
|---|---|---|
| `available` | After successful import | Can be assigned |
| `assigned` | After successful assignment | Can be redeemed and topped up |
| `depleted` | Balance reaches exactly zero on redemption | Can be topped up (returns to `assigned`) |
| `expired` | After expiry date | Cannot be assigned, redeemed, or topped up |

*Transaction effects*

| Action | Effect on balance | Status transition |
|---|---|---|
| Assignment | Balance set to type's `card_value` | `available` → `assigned` |
| Redemption | Reduce by amount | `assigned` → `depleted` if balance hits exactly zero |
| Top-up | Increase by amount | `depleted` → `assigned`; `assigned` stays |
| Expiry | — | Any active status → `expired` |

*Operating rules*

- **Assignment is atomic** under concurrency via `FOR UPDATE SKIP LOCKED` — no two members can claim the same card simultaneously.
- **Ledger records `balance_before` and `balance_after`** on every transaction for full audit trail.
- **Import is all-or-nothing** — any invalid or duplicate card rejects the whole batch.

*Limitations*

- No dedicated admin or member UI is documented as built yet — operations are exposed through database functions, surfaced through the future API.
- Expired cards cannot be assigned, redeemed, or topped up.
- Wrong imported `card_value` cannot be patched on already-imported cards.

---

### Tags & Personas

**Overview**

Tags and Personas are two complementary classification systems that segment members beyond tier and user type. **Personas** represent a member's primary business profile — a member has at most one persona, chosen from `persona_master` and grouped under `persona_group_master`. **Tags** are flexible many-to-many labels — VIP, At Risk, Dormant, Frequent Buyer, Influencer — assigned through `user_tags`. The core lens is **structured identity plus flexible labels**.

**Purpose**

Tiers cover loyalty hierarchy. User type covers buyer vs. seller. But merchants need a third lens for business segmentation — "this customer is an SME in the corporate group", "this user is on our churn-risk watchlist", "this contact is a brand-relations VIP" — without inflating tiers or hardcoding labels in code. Personas hold the *primary* classification (one per user), tags hold *behavioural and lifecycle* markers (many per user), and together they let other features (tiers, rewards, missions, AMP, reporting) filter eligibility and personalize behaviour without modifying core code.

**User Journey**

*Admin journey*

1. **Create persona groups** and decide whether each group should assign a `user_type` such as buyer or seller.
2. **Create personas under groups**, keeping `active_status` aligned with current segmentation choices.
3. **Create tags** for flexible labels (VIP, At Risk, Dormant, Frequent Buyer, Influencer).
4. **Assign a persona** to a user when their primary business profile is known; use tags for additional behavioural or lifecycle attributes.
5. **Remove tags or personas** when classification changes — note that persona removal does not automatically revert user type.

*Member journey*

Member-facing behaviour is usually indirect — members do not see "your persona is X" or "your tags are Y" directly. They experience the result as:

1. Targeted offers, tier eligibility, reward availability, persona-filtered profile fields, or customer-success context.
2. During profile editing, the member may select or change persona if the merchant exposes that choice through `USER_PROFILE`. Tag assignment is admin / API / analytics / automation driven, not member-facing.

*Edge cases*

- Assigning a persona from an **inactive group** is blocked.
- Assigning a tag from another merchant is blocked (merchant isolation).
- Duplicate tag assignment is **idempotent** — re-adding an existing tag returns success without creating duplicates.
- Removing a tag that wasn't assigned returns success (idempotent).
- High tag cardinality on a single user may need reporting or archival conventions to stay performant.
- A member with no persona only matches **non-persona-specific** tier rules.

**Configurations & Rules**

*Persona group — `persona_group_master`*

| Field | Purpose |
|---|---|
| `group_name` | Display name (e.g., "Corporate Members") |
| `user_type` | Optional — when set (`buyer` / `seller`), assigning a persona in this group **changes the user's user_type** |
| `config`, `metadata` | Group-level configuration |
| `active_status` | Disables new assignments from this group |

*Persona — `persona_master`*

| Field | Purpose |
|---|---|
| `persona_name` | Display name (e.g., "SME") |
| `description` | Long-form description |
| `config`, `metadata` | Persona-level configuration |
| `active_status` | Disables new assignments of this persona |
| (Belongs to one group) | Inherits user-type behaviour when the group sets it |

*Tag — `tag_master` + `user_tags`*

| Object | Holds |
|---|---|
| `tag_master` | Merchant-owned tag definitions |
| `user_tags` | Many-to-many assignments to members |

*Operating rules*

- **Each user can have at most one persona.** Switching persona is an atomic update on `user_accounts.persona_id`.
- **Group `user_type` cascades on assignment.** If the persona's group sets `user_type`, the user's `user_type` updates atomically with the persona change. Groups without `user_type` leave it unchanged.
- **Persona removal does not revert user type** — once a user becomes a seller via persona assignment, removing the persona leaves them a seller.
- **Tag add / remove are idempotent.** Duplicate adds and missing removes return success.
- **Cross-merchant assignment is blocked** at the database level.
- **Inactive groups, personas, and tags cannot be newly assigned**, but existing assignments are not retroactively cleared.

*Limitations*

- Personas are primary classification — not unlimited labels. A member cannot have two personas simultaneously.
- Tags are flat — no hierarchy, no nesting.
- No automatic persona-change triggers that re-evaluate downstream entitlements; callers must invoke the relevant pipelines (e.g., `fn_auto_assign_on_persona`) themselves.

---

### Activity-Based Earning

**Overview**

Activity-Based Earning lets members submit proof images for configured activities, then lets admins approve or reject those uploads and award loyalty currency from a matrix of award cells. It fits campaigns where the purchase ledger is *not* the source of truth — exercise, meditation, POSM (point-of-sale-material) compliance checks, volunteer work, training completion, anything proof-based. The core lens is **proof → review → currency**: a merchant defines an activity and its currency matrix, a member uploads an image, an admin verifies field values, and approval calls the wallet layer directly to write `wallet_ledger` with `source_type = 'activity'`.

**Purpose**

Most loyalty earning is automatic — a purchase fires a CDC event, currency posts. But there are reward-worthy activities the platform can't observe directly: a sales rep checking POSM compliance at a retail outlet, a member completing a wellness milestone, a partner submitting a campaign proof. Activity-Based Earning makes those eligible by letting the member submit visual proof and the merchant verify before awarding currency. The matrix model means one activity can pay differently based on multiple dimensions (e.g., display size × check type for POSM checks).

**User Journey**

*Admin journey*

1. **Create or edit an activity** — set `activity_name`, `activity_code`, dynamic `field_definitions`, `primary_dimension`, optional icon/banner assets, active status.
2. **Configure currency matrices** — one grid per secondary field, with primary-dimension values as columns and secondary values as rows. Each cell holds optional points and ticket amounts.
3. **Configure upload limits** through the shared `transaction_limits` model (per-user and total caps).
4. **Review pending uploads** from `bff_get_activity_uploads` — inspect the submitted image, fill required field values, approve or reject.
5. **On approval**, the RPC returns the awarded points and tickets. **On rejection**, capture a reason; no currency is awarded.

*Member journey*

1. Member opens an eligible activity and sees `activity_name`, description, image guidance, and any limit messaging.
2. Member uploads proof — usually an image URL produced by Supabase Storage or the app upload pipeline.
3. Frontend calls `upload_activity_image(p_activity_id, p_image_url)`.
4. On success, member sees a **pending-review** state. Currency is not awarded until admin approval.
5. After approval, points or tickets appear in wallet history with source metadata tying back to the activity upload.

*Edge cases*

- Missing required field values block approval.
- Field values outside configured options block approval.
- A user who passed limits at upload but exceeds them before approval is rejected at approval time (re-check).
- A matrix combination with no award cell — approval fails because there's nothing to award.
- Wallet posting failure must roll back the approval — partial state is not committed.
- Inactive activity, invalid image URL, or upload accepted but later rejected — member sees the failure / reason.

**Configurations & Rules**

*Activity master — fields on `activity_master`*

| Field | Purpose |
|---|---|
| `activity_code` | Stable merchant-owned identifier |
| `activity_name` | Display name |
| `field_definitions` | Dynamic fields the admin fills at approval (label, type, allowed options) |
| `primary_dimension` | The matrix's column key (e.g., `display_size`) |
| Display assets | Icon, banner |
| `active_status` | Master on/off |

*Currency matrix — `activity_currency_config`*

| Key columns | Award columns |
|---|---|
| `activity_id` + `primary_value` + `secondary_field` + `secondary_value` | optional `points`, optional `ticket_type_id` + `tickets` |

One row per (primary × secondary) cell. Admin UI renders one grid per secondary field — primary as columns, secondary as rows.

*Upload ledger — `activity_upload_ledger`*

| Field | Purpose |
|---|---|
| User, activity, image URL | Submission core |
| Status | `pending` → `approved` / `rejected` |
| Admin notes, decision reason | Captured at approval / rejection |
| Field values | The admin-filled values that drive matrix lookup |

*Upload frequency limits — shared `transaction_limits`*

| Field | Behaviour |
|---|---|
| `entity_type = 'activity'` | Scopes the limit to activity-based earning |
| Window + cap | Per-user and / or total caps over the configured window |
| Counted statuses | Includes `pending` and `approved` rows in the applicable window |

*Wallet write at approval*

| Field | Value |
|---|---|
| `source_type` | `'activity'` |
| `source_id` | `activity_upload_ledger.id` (back-pointer to the upload) |
| Currency rows | One per non-null `points` / `tickets` cell value |

*Operating rules*

- **Two-pass limit check.** Limits validated once at upload (block oversubmissions), again at approval (block over-grants when a user gets multiple uploads approved in the same window).
- **Approval is a synchronous admin RPC**, not a CDC / Inngest pipeline like purchase earning.
- **Rollback on wallet failure.** If `chokepoint_post_wallet_transaction` fails, the approval is not committed.
- **Source attribution back to upload.** Ledger rows always carry `source_type='activity'` and `source_id=activity_upload_ledger.id`.

*Limitations*

- Matrix is two-dimensional — one `primary_dimension` and one secondary field per matrix. Higher-dimensional awards are not supported.
- Image validation is **review-driven** — no OCR, no GPS validation, no auto-approval, no multi-image-per-upload in the documented behaviour.
- Activity awards are synchronous admin actions; they do not flow through the same CDC + Inngest pipeline as purchase currency.

---

### Store & Partner Classification

**Overview**

Store & Partner Classification lets merchants organize stores *and* partner-like channels (marketplaces, partner outlets) into business-rule groups. Instead of hardcoding store types, merchants define their own **Category → Attribute → optional Sub-Attribute** hierarchy, classify each store across one or more dimensions, then bundle those classifications into **attribute sets** that earn factors, missions, reporting, and channel strategies can target. The member experience is indirect — different multipliers, different mission qualifiers, different campaign outcomes show up depending on which set the transaction's store belongs to.

**Purpose**

A merchant with 200 retail stores, 5 marketplace shops, and 30 partner outlets shouldn't have to enumerate every store ID in every earn factor or mission. Classification lets them say "Premium Channels" or "All Online" or "Flagship Stores" once, and every rule downstream references the set. When a store opens, closes, or changes channel type, the rules don't need re-editing — only the classification membership changes. This also makes online (marketplace) and partner sales usable by the same store-set logic as physical locations.

**User Journey**

*Admin journey*

1. **Create or import stores** via `store_master` with `store_code`, `store_name`, location / reference fields, `active_status`.
2. **Define classification dimensions** — categories, attributes under categories, optional sub-attributes under attributes.
3. **Assign each store** to relevant attributes and sub-attributes across multiple categories (a store can carry many classification dimensions simultaneously).
4. **Create attribute sets** from attributes, sub-attributes, or specific store members — e.g., "Premium Channels", "All Online", "Flagship Stores".
5. **Reference the set** in earn factor store conditions, mission filters, campaign targeting, and reporting.
6. **For marketplace / partner channels** — model each marketplace shop or partner outlet as a store / channel record, classify under channel or partner attributes; online sales then qualify via the same store-set logic.

*Member journey*

There is no direct store-classification screen in the member app. Members experience the feature through downstream outcomes — a purchase at an online marketplace earns a different multiplier, a flagship-store purchase satisfies a mission, a channel-specific campaign applies.

*Edge cases*

- Admins must avoid **orphaned or stale assignments** when deprecating categories or attributes — references to a removed attribute fall out of the set.
- **Classification changes affect future rule evaluation** only — they do not rewrite the store code or source recorded on historical transactions.

**Configurations & Rules**

*Store master — `store_master`*

| Field | Purpose |
|---|---|
| `store_code` | Merchant-owned identifier — unique per merchant |
| `store_name` | Display name |
| Location / reference fields | Address, region, etc. (descriptive) |
| `active_status` | Master on/off |

*Classification hierarchy*

| Level | Purpose |
|---|---|
| Category | Top-level dimension (e.g., "Channel", "Region", "Business Type") |
| Attribute | A value within a category (e.g., "Channel" → "Online", "Flagship", "Distributor") |
| Sub-Attribute (optional) | A finer split of an attribute |

A single store can be assigned **across multiple categories** and carry **multiple classification dimensions** at the same time. The hierarchy is **Category → Attribute → optional Sub-Attribute**.

*Attribute sets — rule-friendly groupings*

| Member type | Behaviour |
|---|---|
| Attribute | **Broad** — every store carrying the attribute qualifies |
| Sub-Attribute | **Specific** — only stores with that exact sub-attribute assignment qualify |
| Specific store | Hard pin — the named store is always in the set |

This is the layer that decouples business logic from classification structure. Earn conditions, mission filters, and campaign targeting reference a set; the set's members can change without editing the rule.

*Operating rules*

- **Store codes are unique per merchant.** Cross-merchant store-code reuse is allowed; cross-merchant set membership is blocked.
- **Multi-category, multi-attribute simultaneously.** A flagship Bangkok airport store can be in Channel:Airport, Region:Bangkok, Format:Flagship all at once.
- **Future-only evaluation.** Classification changes affect rule evaluation going forward — historical transactions retain their recorded store context.
- **Live schema uses `is_deleted`** on classification tables; deleted classifications are excluded from set evaluation.
- **Purchase-store resolution runs before store-set earn evaluation** — the engine identifies the store first, then checks set membership.

*Limitations*

- No dedicated member-facing UI surface — the feature is admin / engineering and shows up indirectly through downstream features.
- Live schema does not expose every descriptive metadata field shown in older drafts — implementations should follow live columns rather than legacy documentation.
- Marketplace and partner channels are modelled by treating them as store records — there is no separate "partner master" concept in this layer.

---

### Purchase Transactions

**Overview**

Purchase Transactions are the loyalty platform's purchase audit layer and the main earning trigger for points, tier progress, and purchase-based missions. Transaction headers are recorded in `purchase_ledger` and optional SKU-level line items in `purchase_items_ledger`, then completed purchases are routed into the surrounding loyalty systems (Currency earning, Tier evaluation, Missions, store attribution).

The model is designed around **immutable business records** — normal purchases are credit records, refunds are represented as **separate debit records** rather than rewriting the original. This gives support, finance, and loyalty operations a full, auditable history of what happened, when, through which channel, and how reversals affected currency and tier calculations.

The feature unifies multiple purchase sources — POS, admin entry, marketplace, e-commerce, mobile, and receipt-driven — under one ledger, while preserving channel attribution via `transaction_source`, `api_source`, `external_ref`, store code, buyer, and optional seller fields. The same purchase can therefore power customer rewards, seller/distributor performance, marketplace reconciliation, and store-based earn rules without duplication.

**Purpose**

Be the single source of truth for "did the member spend, where, on what, and what loyalty effects should that produce?" — across every commerce channel a merchant operates. The dual-ledger header/line-item model lets the platform award currency from amount alone when SKU data is missing, but unlock product/category/brand-specific rules when line items are present. The credit/debit refund pattern keeps loyalty math (currency reversals, tier progress adjustments, sales metrics) auditable instead of destructively edited.

**User Journey**

*Admin journey*

- Admins interact with purchases through three primary surfaces:
  - **Receipt review** — receipt-upload operations create or approve transaction records.
  - **Member 360 purchase history** — `admin_get_user_purchases` shows transaction number, date, store, amount, item count, awarded points/tickets, payment method, status, batch id, and receipt images.
  - **Member search & creation** — admins find members by external user id, member code, or filter to "members with activity at a store"; member creation goes through the BFF flow so merchant resolution, duplicate checks, and `admin_users` authorization are server-side enforced.

*Member journey*

- Members do **not** configure purchases. They see purchase effects downstream:
  - Wallet balance updates (currency awarded).
  - Purchase history list.
  - Tier progress advances.
  - Mission progress increments.
- For queue-based processing, a transaction can appear in history before currency finishes awarding — wallet updates arrive after the queue processor completes.

*Edge cases*

- A completed purchase with `earn_currency = false` shows in history with no currency award.
- A refund appears as a separate reversal entry — never as an overwrite of the original.
- Marketplace and receipt purchases look like normal purchases after ingestion, while keeping their source identifiers (`external_ref`, `api_source`, `batch_id`) for support traceability.

**Configurations & Rules**

*Transaction record shape*

| Surface | Storage | Role |
|---|---|---|
| **Header** | `purchase_ledger` | One row per transaction — amount, status, store, source, member, processing controls |
| **Line items** | `purchase_items_ledger` | Optional SKU rows for product/category/brand matching |
| **Source attribution** | `transaction_source`, `api_source`, `external_ref` | Channel + external system reconciliation |

*Status & processing controls*

| Field | Purpose | Effect |
|---|---|---|
| `status` | Business status (`completed`, `pending`, `processing`, `cancelled`, `refunded`) | Only `completed` triggers loyalty effects |
| `payment_status` | External payment processor status (free text) | Independent from business `status` — does not gate loyalty |
| `processing_method` | Currency routing | `queue` = async wallet processing · `direct` = immediate · `skip` = no currency award |
| `earn_currency` | Boolean flag | When `false`, blocks currency processing even if the transaction completes |
| `record_type` | `credit` (normal) / `debit` (refund) | Debit reverses original without mutating it |

*Operating rules*

- **`status = 'completed'` is the trigger point** — it can award currency, queue tier evaluation, and advance purchase missions when conditions match. Pending and processing purchases do not award currency. Cancelled purchases remain historical with no loyalty impact.
- **Refunds use credit/debit pattern.** A debit row with `record_type = 'debit'` and `status = 'refunded'` reverses spend and currency impact. Sales metrics subtract debit amounts; order-count metrics exclude debit records.
- **Line items are optional but unlock product matching.** Product-specific earn factors or missions can only apply when line data is present. Without line items, only amount-based rules can fire.
- **Store-based rules** resolve the transaction's store code through `store_master` and store classifications (see *Store & Partner Classification*).
- **Channel attribution is preserved end-to-end** — `transaction_source`, `api_source`, and `external_ref` survive into Member 360, support search, and reporting.

*Limitations*

- The current purchase model uses a **single `status` field** — fulfillment is not tracked separately. Marketplace or e-commerce integrations must collapse their order/payment/fulfillment states into the CRM's one status according to merchant policy.
- Marketplace claim does not auto-reverse currency on later refund/cancel — manual handling via the purchase refund flow is required.

---

#### Marketplace Integration

**Overview**

Marketplace Integration connects external commerce platforms — **Shopee, Lazada, TikTok Shop, and Shopify** — to the loyalty purchase pipeline. Orders from connected marketplace shops sync into the CRM, get matched to members where possible, and are converted into purchase transactions when they reach the configured claim status.

The pipeline is event-driven outside the database and lands in `order_ledger_mkp` before creating or linking CRM purchase records. Once claimed, **standard purchase behavior takes over** — currency earning, tier progress, missions, store attribution, and support lookup follow the same patterns as other purchase transactions.

**Purpose**

Channel unification. A member who buys on the merchant's marketplace shop earns loyalty credit **without manual claim forms or receipt uploads**, and the merchant sees marketplace orders alongside POS, app, and other purchase sources in one history. This removes the operational tax of "I bought it on Shopee, why don't I have my points?" and gives merchants a single ledger for cross-channel loyalty performance.

**User Journey**

*Admin journey*

The feature lives in **Marketplace Settings** and has two main areas:

1. **Marketplace Connections** — Admin clicks "Add Channel" → selects platform (TikTok Shop, Lazada, Shopee, Shopify) → enters a store label → loads the platform's order statuses → chooses the **claim-from status** (the threshold at which orders become CRM purchases) → completes OAuth. Connected channels show platform, external id/shop id, environment, and active/inactive state.
2. **Order Claims** — Admin picks a platform → searches by order id or order number. The result card shows order identity, platform icon, claimed state, transaction date, amount, order status, buyer info, **earned currency when claimed**, and line items. A dashboard/history link opens the embedded reporting view.

*Member journey*

Members never configure or manually claim marketplace orders. They buy on the marketplace; the order syncs automatically; points appear after the order reaches the channel's claim-from status **and** purchase/currency processing succeeds.

*Edge cases*

- OAuth denial or token expiration leaves the channel **inactive** — sync stops until the admin reconnects.
- Marketplace orders may be present but unclaimed if the order hasn't crossed claim threshold or no CRM member matches the buyer.
- Points timing = marketplace sync time + purchase currency processing time. There is a perceptible delay vs. POS purchases.

**Configurations & Rules**

*Connection model*

- Credentials and channel configuration stored per merchant/shop in `merchant_credentials`.
- Synced order headers land in `order_ledger_mkp`.
- Each shop is processed independently — one shop's batching/cooldown/token state does not block another shop.

*Default claim-from status per platform*

| Platform | Default claim-from status | Override path |
|---|---|---|
| Shopee | `READY_TO_SHIP` | `merchant_master.marketplace_claim_from_status->>'shopee'` |
| Lazada | `pending` | `merchant_master.marketplace_claim_from_status->>'lazada'` |
| TikTok Shop | `AWAITING_SHIPMENT` | `merchant_master.marketplace_claim_from_status->>'tiktok'` |
| Shopify | `paid` | `merchant_master.marketplace_claim_from_status->>'shopify'` |

*Sync model*

| Platform | Mechanism |
|---|---|
| Shopee · Lazada · TikTok | **Marketplace batch pipeline** (event-driven outside DB) |
| Shopify | **Real-time per-order webhooks** — `orders/create`, `orders/paid`, `orders/fulfilled`, `orders/cancelled`, `orders/updated` |

*Shopify webhook specifics*

- **No merchant-visible webhook URL field.** On OAuth completion, the platform calls Shopify's Admin API to register all five order topics pointing at the CRM's `shopify-webhooks` edge function.
- Registration is **idempotent and self-heals** — re-runs on subsequent admin logins when the credential row is missing `webhook_endpoint`.
- HMAC verification rejects forged payloads with HTTP 401.

*Operating rules*

- Orders below claim-from status do **not** create purchase transactions.
- Duplicate webhooks **update** existing marketplace orders rather than insert duplicates.
- **Buyer matching** uses marketplace buyer data — phone, email, username, or external user id. No CRM member match → marketplace order is stored but unclaimed.
- Shopify webhook handler does the match synchronously and auto-claims when both (a) a member matches and (b) the order has reached claim threshold.

*Limitations*

- Marketplace status and CRM purchase status are **independent** — once claimed, later marketplace cancellation/refund does **not auto-reverse** the currency. Manual reversal via the purchase refund flow is required.

---

#### Receipt Upload Earning

**Overview**

Receipt Upload Earning is the manual-receipt path into the purchase pipeline — members (or members-via-admin) submit a photographed receipt, an admin reviews it, and approval **creates or completes a purchase transaction**. Once approved, the entry behaves like any other purchase: currency awards, tier progress, mission progress, and store attribution all follow the standard Purchase Transactions rules.

This sub-feature does not have its own configuration surface beyond Purchase Transactions itself — it's the receipt-driven entry mode of the same ledger. Receipt images are stored against the transaction header and surface in admin Member 360 history alongside the structured fields.

**Purpose**

Cover the long tail of purchases that **do not flow in via POS, e-commerce, marketplace, or any direct integration**. Where a merchant has retail partners, off-network channels, distributor networks, or simply legacy point-of-sale that can't push transaction data, receipts are the bridge. Members get credit; merchants extend loyalty into channels they don't directly own.

**User Journey**

*Admin journey*

- Admins work the receipt review queue: open a submission, view the uploaded receipt image, confirm/edit transaction date, store, amount, payment method, and SKU lines if present, then approve to create a purchase row (or reject).
- Approved receipts appear in Member 360 purchase history with the receipt image, transaction number, and a **batch id** marking them as receipt-sourced.

*Member journey*

- Members capture a receipt and submit it through the member-facing app/web flow.
- They see a pending state until admin review completes.
- On approval: wallet, history, tier progress, and mission progress all update — same downstream effects as a POS purchase.
- On rejection: the submission shows as rejected; no loyalty effects.

*Edge cases*

- Submissions for non-eligible stores or out-of-window dates can be rejected at review.
- Duplicate receipts (same image / same external reference) should be caught at review to prevent double-credit.
- Receipts approved with `earn_currency = false` (e.g. policy override) appear in history with no currency awarded.

**Configurations & Rules**

- **No standalone configuration surface** — receipt-upload behavior is governed by the same Purchase Transactions rules (status, processing_method, earn_currency, record_type).
- **Batch id** marks receipt-sourced transactions for support traceability.
- **Receipt image metadata** is stored on the purchase header and surfaces in admin tools.
- **Identity preservation** — receipt purchases keep their source identifiers (`api_source`, `external_ref`, batch id) so support and reporting can distinguish them from POS/marketplace purchases.
- **Review-gated** — unlike POS or marketplace purchases that are auto-completed, receipt purchases land in a review state and are completed only on admin approval.

*Limitations*

- Receipt upload depends on **manual admin review capacity** — throughput is bounded by reviewer count.
- OCR/auto-extraction is not part of the loyalty contract documented here; submissions are reviewed against admin discretion plus configured rules.

---

#### Event Promo Engine

**Overview**

The Event Promo Engine applies **event-order promotions synchronously while an event order is being created**. It calculates freebies and bill-level discounts before the order is finalized, then writes the resulting freebies, discounts, claims, and `reward_list` data as part of the same transaction.

This is **separate from the currency earning pipeline**. Currency is event-driven *after* a purchase/order exists; event promos are **order-time commercial incentives** — a customer can receive a freebie or discount immediately because their event order matches a product, combo, spend, or compound condition.

Promos are configured per event. Each promo contains one or more rules; each rule pairs a JSONB condition with an outcome. Evaluation mode decides whether the promo applies the highest qualifying rule or all qualifying rules.

**Purpose**

Run **buy-X-get-Y, spend-threshold-discount, combo-deal, and compound-condition promotions** at the moment of order creation, without going through the campaign automation or marketing automation engines. The use case is event commerce — pop-up sales, ticketed events, fair booths, road shows — where the merchant needs deterministic, in-cart promotional logic that produces freebies and bill discounts in real time.

**User Journey**

*Admin journey*

- Admins configure promos from **Event Promo Management**:
  1. Create a promo for an event.
  2. Choose **evaluation mode** (`highest` or `all`) and claim limits.
  3. Add **rules**, each with a condition JSON and outcome settings.
  4. Pick freebie outcomes from product SKU master data **or** enter custom freebie details (copied into the rule row, no master SKU required).
- A **preview flow** calls the promo preview BFF with event, user, amount, and items so admins can confirm what freebies/discounts would apply before saving or going live.

*Member journey*

- There is **no standalone member promo catalog** for this feature. The user receives promo effects inside the event order flow:
  - Qualifying items or spend produce **freebie rows**.
  - **Bill-level discount adjustments** show on the order.
  - A **reward list** is attached to the purchase/order.

*Edge cases*

- When multiple promos qualify, each promo is evaluated **by event sort order** (`sort_order` on the promo header).
- Within a `highest`-mode promo, **lower tiers must not stack with the highest tier** — only the top-qualifying rule applies.
- **Custom freebies** display from the rule's copied fields even when no product master SKU exists.

**Configurations & Rules**

*Storage model*

| Object | Role |
|---|---|
| `event_promo` | Event-level promo header — event, name, description, active flag, `eval_mode`, claim limits, sort order |
| `event_promo_rule` | Ordered rules per promo — condition JSONB + outcome (freebie / percentage discount / fixed discount); references master SKU or custom inline freebie text |
| `event_promo_claim` | Per-user/per-order usage tracking, enforcing claim limits |

*Supported condition types*

| Condition | Behavior |
|---|---|
| `product_qty_threshold` | Trigger when listed product crosses minimum quantity |
| `product_combo` | All listed items must hit minimums; **scalable combos** calculate set count from the limiting item and cap quantity by claim limits |
| `spend_threshold` | Trigger at total spend ≥ threshold |
| `compound` | **Recursive** — combine the above into AND/OR trees |

*Outcome types*

| Outcome | Effect |
|---|---|
| Freebie (master SKU) | Adds the SKU as a freebie row |
| Freebie (custom) | Custom freebie text/details copied into the rule row — no SKU master join required |
| Percentage discount | Bill-level discount as % |
| Fixed discount | Bill-level discount as fixed amount |

*Evaluation modes*

| Mode | Behavior |
|---|---|
| `highest` | Picks the highest `rule_order` passing rule — lower tiers do **not** stack |
| `all` | Applies every passing rule |

*Operating rules*

- Multi-promo orders evaluate each promo independently in `sort_order` sequence.
- `event_promo_claim` enforces per-user and per-order usage caps.
- Outcomes write to the event order transaction synchronously — no separate post-processing.

*Limitations*

- Event promos cover **event order freebies and bill discounts only**. They do **not** replace wallet currency earning, reward redemption, or general campaign automation.
- Outcomes are bound to event orders — non-event purchases route through Currency / Tiers / Missions instead.

---

## Marketing Automation

Marketing Automation (AMP) turns live customer context into the next message or loyalty action. It has three complementary capability groups:

- **Deterministic multi-step workflows** — marketers design exact journeys that condition on customer data and execute messages plus loyalty actions.
- **AI decisioning agents** — marketers set goals, allowed actions, outcomes, and constraints; the agent reviews customer context and chooses ACT, WAIT, or SKIP.
- **AI analysis and recommendations** — analysis surfaces that recommend what to improve next, without replacing the decisioning agent.

AI decisioning agents can sit inside workflows as agent nodes, so a deterministic journey can hand off high-judgment moments to AI.

---

### AMP Workflows

**Overview**

AMP Workflows is the **rule-based marketing automation** capability of the platform. Merchants build directed customer journeys that **react to CRM events** — evaluating conditions, waiting, branching, and executing actions. The classic example: a welcome workflow starts when a member signs up, sends a greeting, waits two days, checks whether the first purchase happened, and branches into a discount message or education content depending on the result.

The vocabulary:

- A **workflow** is a node-and-edge graph.
- An **entry node** is the first condition node with no incoming edge — its referenced collection determines what events can trigger the workflow.
- A **trigger** maps a database event to a workflow.
- **Condition nodes** branch true/false.
- **Wait nodes** pause execution (durable orchestration — they resume after the configured duration).
- **Action nodes** send messages, award currency, assign tags or personas, submit forms, manage audiences, call webhooks, or invoke an AI agent.
- **Execution logs** track each user's run.

For marketing and CS, AMP Workflows is the background engine behind **behavior-triggered lifecycle campaigns** — welcome series, post-purchase nurture, win-back, birthday, tier celebration, and audience-entry automation.

**Purpose**

Replace manual blast campaigns and one-off scripts with **always-on, event-reactive customer journeys** that the marketer can design visually and the platform can run reliably at scale. Workflows are deterministic — the marketer specifies exactly what happens — and durable — wait nodes survive restarts and resume on schedule. They unify messaging, loyalty actions, and audience management into one pipeline so the marketer doesn't need to wire integrations between separate tools.

**User Journey**

*Admin journey*

1. From **Workflow List**, click **Create workflow**.
2. **Workflow Builder** opens with an entry condition node on the canvas and a node palette.
3. Configure the **entry condition** — collection, field, operator, value. This determines which events can trigger the workflow.
4. Drag nodes from the palette: messages, loyalty actions, audience actions, integrations, waits, conditions, or **agents** (AI Decisioning agent nodes).
5. Connect nodes by dragging handles. Linear flows use `default`; conditions and agent nodes can use `true` and `false` paths.
6. Click a node to configure it in the side panel.
7. Set workflow name and description, save, then toggle **Active** when ready to process events.
8. Use **AMP Analytics** to inspect overview metrics, workflow detail, action funnel, recent executions, and per-user timeline.

*Member journey*

Members do not see a workflow surface. They experience workflows as **inbound effects** — a message arriving on LINE/WhatsApp/Email/SMS/Push, currency landing in the wallet, a tag or persona being applied (which can change reward eligibility, tier rules, etc.).

*Edge cases*

- Saving without an entry condition leaves the workflow unable to trigger.
- Activating with incomplete node configuration can cause runtime failures.
- A CDC source not connected to the pipeline makes the workflow appear inactive.
- Duplicating a workflow should create an inactive copy.
- Deactivation stops new runs but does **not** cancel already-running executions.
- A false branch with no edge should complete that path rather than guessing a next node.

**Configurations & Rules**

*Workflow object*

| Setting | Role |
|---|---|
| `name`, `code`, `description` | Identity |
| `is_active` | Activation gate — must be `true` for any lane to fire |
| `run_mode`, `scope`, `domain` | Execution context |
| **Graph (nodes + edges)** | Builder canvas — condition / wait / action / agent nodes |

*Node types*

| Node | Configuration |
|---|---|
| **Condition** | Collection · field · operator · value · match mode; branches by `source_handle` (`true`/`false`/`default`) |
| **Wait** | Duration + unit; durable pause + resume |
| **Action** | Message · loyalty action · audience action · webhook |
| **Agent** | References an AMP AI Decisioning agent |

*Trigger lanes (`workflow_trigger.trigger_type`)*

| Lane | Mechanism |
|---|---|
| `realtime` (legacy: `purchase_completed`, `points_earned`, `form_completed`, `database`, `custom`) | Fired by a **CDC event** matching the workflow's listening table/operation/conditions |
| `manual` | Launched by an admin clicking "Batch run" in the FE |
| `scheduled` | Launched on a recurring cadence by `pg_cron` once `next_run_at <= now()` |

*Scheduled trigger configuration*

For `scheduled` rows on `workflow_trigger`:

- Use sentinel values `trigger_table = 'scheduler'`, `trigger_operation = 'INSERT'` to satisfy NOT NULL/check constraints (these fields are required by the table but meaningless for cron-driven triggers).
- Define cadence in `trigger_conditions.schedule`. Supported types: `daily`, `weekly`, `monthly`, `interval`, `one_off`. Provide type-specific fields (`time_of_day`, `weekdays`, `day_of_month`, `interval_minutes`, `run_at`) plus an IANA `timezone`.
- `next_run_at`, `last_run_at`, `schedule_status` are managed by the system — do not write from the FE. Trigger `trg_amp_workflow_trigger_set_next_run_at` recomputes `next_run_at` on insert/update of the schedule, on reactivation, and after every cron run.

*Operating rules*

- The **entry node** is the first condition node with no incoming edges.
- **Triggers are auto-derived** from the entry condition's referenced collection when the workflow is saved.
- Workflows default **inactive**; activation is required before new events are processed.
- **Condition branches** follow `source_handle` `true`/`false`/`default`; if no matching edge exists, execution **ends on that path** (does not guess).
- **Wait nodes** pause with durable orchestration and resume after the configured duration.
- **Action side effects** carry `source_type = amp` and `source_id = workflow_id` for downstream auditability.
- **Deactivation** stops new executions but does **not** cancel runs already in flight.
- **Already-enrolled users** (those with a `workflow_log` row of `event_type = 'execution_started'` for this workflow) are excluded by the matcher in both the manual and scheduled lanes.

*Schedule ↔ Condition pairing rule (build-time discipline)*

`run_window` is config metadata on the trigger and is **not** consumed by the scheduler. Until the condition evaluator reads it, choose a schedule cadence that matches the entry condition's expected window:

| Use case | Schedule | Condition |
|---|---|---|
| Daily birthday | `daily` | `birthday = today` |
| Weekly digest | `weekly` | `completed activity in last 7 days` |
| Anniversary celebration | `daily` | `signup_date anniversary today` |

Mismatches (e.g., weekly schedule with a "today" condition) silently under- or over-fire — there is no scheduler-side guard.

*Catch-up semantics*

- If pg_cron is down or backed up, when the scheduler resumes it runs each due trigger **once** and recomputes `next_run_at` from `now()`.
- Missed individual occurrences are **not backfilled**.
- If a missed run matters, kick it manually via "Batch run".

*Logging — `workflow_log` events per cron tick*

| Event | Meaning |
|---|---|
| `scheduled_run_dispatched` | Matched users were posted to `amp-dispatch-workflow-batch` |
| `scheduled_run_no_users` | Matcher returned no users for this run |
| `scheduled_run_failed` | Dispatch failed (Edge Function error or `pg_net` failure) |
| `batch_run_requested` | Manual batch run found matching users |

*Limitations*

- A workflow with no configured entry condition has no trigger and will not fire.
- A condition referencing a table outside the CDC pipeline will not receive realtime events.
- Duplicate workflows targeting the same event can both run.
- A user can start a new run while a prior run remains in flight.
- `run_window` is reserved config — the matcher does not consume it yet (match cadence to condition window manually).
- The cron does not backfill missed occurrences.
- A scheduled trigger pointing at an inactive workflow advances its `next_run_at` but never dispatches.

---

### AMP AI Decisioning

**Overview**

AMP AI Decisioning is the **AI-agent capability** inside marketing automation. Marketers define an objective, allowed actions, outcomes, and guardrails; the agent then **decides per member whether to ACT, WAIT, or SKIP**. A win-back agent can observe a lapsed VIP, wait three days for organic return, then award 200 points and send a friendly LINE message if the member remains inactive.

The vocabulary:

- An **agent** is a reusable AI configuration.
- An **agent action** is a permitted operation — awarding points, assigning tags, sending messages, or managing audience membership.
- **Objective** values include `re_engage`, `drive_purchase`, `redeem_points`, `tier_upgrade`, `win_back`, `upsell`.
- **Tone** controls message style.
- **Deliberation** is the observe-wait-act loop.
- **Constraints** limit actions, points, tickets, messages, or cost by user or agent over a time window.
- **Outcomes** define attribution and performance measurement.

The sales story is **controlled personalization** — AI chooses timing and action from merchant-approved options while eligibility, budgets, cooldowns, quiet hours, blackout dates, and outcome settings keep the campaign auditable.

**Purpose**

Replace static if/then automation with **AI-driven per-member decisions** that still operate inside merchant-defined guardrails. Where AMP Workflows says "if inactive 30 days, send 100 points," AMP AI Decisioning says "re-engage lapsed customers using these actions, within these limits, optimizing this outcome — figure out for each member whether to ACT, WAIT, or SKIP." This is the layer for high-judgment moments where rules over-fire or under-fire and a human marketer can't tune individually.

**User Journey**

*Admin journey*

1. From **Agent Builder** list, click **Create Agent**.
2. **Configuration tab** — set required name, objective, tone; add description, context hint, max actions per execution, and optional deliberation settings (max cycles, default wait, max wait, total timeout).
3. **Actions tab** — add action rows. Select action type, set variable ranges, add constraints, set eligibility, and keep only usable actions enabled.
4. **Outcomes tab** — add measurable events, mark **one** primary KPI, confirm attribution window, counting method, target conversion, and optional filter.
5. **Scheduling & Guardrails tab** — configure cooldown, quiet hours, blackout dates, and natural-language constraints such as "≤ 200 points per user per month".
6. **Save** to persist the agent and children atomically; place the agent in a workflow agent node.
7. In **AMP Analytics**, open an agent detail row to inspect decision distribution, outcomes, action effectiveness, cost, constraint usage, recent decisions, and user timelines.

*Member journey*

Members do **not** see an AI screen. They see normal CRM effects — points landing, messages arriving, tags applied, personas changed, earn factors adjusted, audience membership updated. The AI decision is invisible.

*Edge cases*

- Required objective or tone missing → agent is not ready for valid configuration.
- Agent has no enabled actions → execution has no CRM operation to run and **skips**.
- Missing primary outcome → analytics has no main KPI to optimize against.
- Inactive agent selected in a workflow → the agent node should not execute actions.
- Max cycles set to 1 → the journey becomes single-shot instead of observe-wait-act.
- Tight constraints can make the agent appear inactive even when workflow triggers are firing.

**Configurations & Rules**

*Four configuration areas*

| Area | What's configured |
|---|---|
| **Configuration** | Name, description, objective, tone, context hint, max actions per execution, deliberation (max cycles, default wait, max wait, total timeout) |
| **Actions** | Specific tools the AI may use — variable ranges, per-action constraints, eligibility, enabled state |
| **Outcomes** | Attribution events, classification, counting method, primary KPI, target conversion rate, optional filters |
| **Scheduling & Guardrails** | Cooldown · quiet hours · blackout dates · natural-language constraints (e.g., "≤ X points per user per month") |

*Decision model*

| Decision | Meaning |
|---|---|
| **ACT** | Execute one or more configured actions now |
| **WAIT** | Pause; the agent must specify what it's watching for and when to reassess |
| **SKIP** | No action — record the decision and end |

*Operating rules*

- The agent only reasons over **actions explicitly configured for it**; ineligible actions are removed before deliberation.
- Each decision returns ACT, WAIT, or SKIP. WAIT must include **what the agent is watching for and when to reassess**.
- **Agent-level and action-level constraints both apply** — the stricter limit wins.
- **Constraints are enforced twice** — the AI reads constraint headroom, and action tools reject over-limit execution.
- Agent performance **aggregates across all workflows** that reference the same agent.
- **One outcome per agent may be primary.**
- **Agent scheduling controls override workflow-level scheduling** for agent nodes.

*Limitations*

- An agent with no enabled actions has nothing to execute and **skips**.
- Setting max deliberation cycles to 1 makes the agent **single-shot** rather than observe-wait-act.
- If timeout or max cycles are reached without action, deliberation ends and the **workflow routes false**.

---

### AMP AI Analysis & Recommendations

<!-- feature_key: marketing_automation.ai_analysis.recommendations -->

**What it enables**

Marketing teams get AI-assisted analysis of workflow and agent performance, with concrete recommendations on what to change next — without handing the AI the authority to ACT on customers.

**How it works**

Operators review campaign/workflow results, ask analysis questions, and receive ranked recommendations grounded in observed outcomes (who converted, who stalled, which actions underperformed). Recommendations stay advisory until a human applies them in workflows or AI decisioning config.

**What differentiates it**

Separates **analysis** from **decisioning**: the decisioning agent chooses ACT/WAIT/SKIP in-flight; analysis helps marketers improve the system of record afterward.

**Key controls**

Which workflows/agents are in scope, which outcomes matter, and whether a recommendation is accepted into a draft change.

**Example**

After a win-back workflow underperforms, analysis highlights that WAIT decisions cluster on VIP personas and recommends tightening the VIP constraint or adding a softer first touch.

---

## Customer Service

Customer Service is the omnichannel conversation engine: inbound contacts from marketplaces, messaging apps, web, email, SMS, and voice become structured conversations that agents and AI can act on.

Capability groups stay cleanly separated:

- **Non-AI operations** — connectivity/inbox, chat & voice, agent productivity, routing/chatbot workflows, service analytics
- **AI service / AOP actions** — AI service agent, AOPs, knowledge, and customer actions
- **Supervisor scoring** — supervisor AI and quality scoring for human and AI cases

Together these deliver one customer context across channels, blend human and AI labor on the same surface, and feed loyalty / marketing automation with conversation signals.

---

### Connectivity

**Overview**

Connectivity is the entry and exit layer for Customer Service. It connects external contact surfaces — marketplaces (Shopee, Lazada, TikTok Shop), messaging apps (LINE, Messenger, Instagram DM, WhatsApp), direct channels (email, web widget, SMS), and voice (Twilio + ElevenLabs) — to the internal CS data model, then resolves who the customer is before the conversation reaches agents, rules, or AI. A *channel* is the configured external surface; a *platform identity* is the external user identifier; a *contact* is the unified CS customer record; *identity resolution* links incoming platform identities to that contact; *modality* distinguishes message and voice flows. The buyer-facing promise: agents and AI see one customer context instead of scattered platform aliases.

**Purpose**

To give brands a single inbox and a single customer record across every channel a buyer might use, so no message, call, or marketplace question lands in isolation. Without this layer, agents must context-switch across native platform UIs and AI cannot reason over cross-channel history. With it, the platform owns the omnichannel + identity hub and downstream features (workspace, AI, analytics) consume a clean internal model.

**User Journey**

*Admin journey*

1. Open channel or phone number settings.
2. Add or edit a channel credential — select the platform type, give it a name, paste credential details, set channel config, and pick scope.
3. Validate that the platform webhook or phone number is connected.
4. Review channel stats to confirm inbound traffic and delivery health.
5. Link or merge contacts when platform identities are known to belong to the same customer.

*Agent journey*

1. Open a conversation and see the channel badge, platform identity, contact profile, and prior history without leaving the workspace.
2. Reply using the same channel — no need to open the platform's native tools.
3. Escalate identity mismatches for correction instead of guessing.

*Edge cases*

- Duplicate contacts require an explicit merge path (no silent auto-merge across ambiguous evidence).
- Missing platform display names must not block conversation creation.
- Voice numbers can be active for voice, SMS, or both depending on configured capabilities.
- Without identity resolution, cross-channel history and loyalty context are unavailable.

**Configurations & Rules**

*Configuration surfaces*

| Surface | What's configured |
|---|---|
| **Channel credentials** | Platform type, name, credential details, channel config, scope |
| **Phone numbers** | Voice and/or SMS capability flags, webhook routing |
| **Identity linking** | Manual contact merge from agent workspace; optional loyalty link via `cs_customers.crm_user_id` |
| **Rendering** | Channel-specific message rendering rules where capabilities differ |

*Operating rules*

- Ingestion resolves contact identity **before** creating or updating the conversation.
- A platform identity belongs to **one merchant-scoped contact**.
- Channel adapters translate platform payloads into the internal message model; workspace and AI consume the internal model only.
- Voice connectivity uses phone number and call metadata but still anchors to a conversation.
- One contact per real customer where platform identity evidence is strong enough.
- Loyalty linkage via `cs_contacts.crm_user_id` is stored only when the CS contact is confidently mapped.

*Limitations*

- Channel capabilities differ; the UI must not assume every channel supports the same media, survey, or action type.
- Repeated messages from the same platform identity append to the correct contact / conversation; new identities create contacts without overwriting unrelated customers.

---

#### Channel Connectors

**Overview**

Channel connectors are per-platform adapters that ingest inbound messages and dispatch outbound replies for every supported channel: marketplaces (Shopee, Lazada, TikTok Shop), messaging apps (LINE OA, Facebook Messenger, Instagram DM, WhatsApp), direct (email, embeddable web widget, SMS), and voice (Twilio SIP trunk routed through ElevenLabs). Example: a brand connects LINE OA by entering its LINE channel access token and channel secret in the admin panel; the platform writes a `cs_channels` row, configures the LINE webhook URL, and from that point every customer LINE message creates a real-time `cs_messages` row with delivery status tracked back to LINE.

**Purpose**

To abstract away every channel's native quirks (auth model, threading rules, signature scheme, rate limits, message format) behind one internal model — so agents, AI, and analytics see a uniform conversation surface no matter where the message came from.

**User Journey**

*Admin journey*

1. Open channel settings and choose the channel type to add (LINE OA, Shopee, WhatsApp, etc.).
2. Paste credentials and validate connection — the platform tests the webhook and credentials.
3. Configure per-channel settings: session timeout, threading interval, display name, rate-limit profile.
4. Set the channel active; messages start flowing into the unified inbox.

*Member journey*

Buyers message the brand on whichever platform they prefer; the platform handles the translation invisibly. Replies arrive on the same channel.

*Edge cases*

- Marketplace channels enforce native threading rules — the platform's `session_timeout` does not apply.
- A deactivated channel keeps history readable but blocks all new sends and receives.
- Multiple LINE OAs per merchant are allowed (e.g., brand sub-accounts) and stay isolated by `cs_channels.id`.

**Configurations & Rules**

*Default per-channel timing*

| Channel | Session timeout | Threading interval |
|---|---|---|
| LINE | 24h | 48h |
| WhatsApp | 24h | 24h |
| Email | — | 72h |
| Web chat | 30 min | — |
| Voice | always-new | — |

All values overridable per channel.

*Operating rules*

- **Webhook signature validation is mandatory** — every inbound webhook must pass HMAC validation with the channel's webhook secret before any DB write. Failure → 401 with no logged side effect.
- **Marketplace channels follow the platform's native threading** — Shopee / Lazada / TikTok provide `conversation_id` mapped 1:1 to `cs_conversations.platform_conversation_id`; their threading wins over the platform's `session_timeout`.
- **Outbound rate limits are enforced at the adapter** — if a platform caps push messages, the adapter queues and retries; the inbox shows `delivery_status='queued'`.
- **Multi-channel per merchant** is supported; each row is distinguished by `display_name`, and identity resolution scopes lookups by `cs_channels.id`, preventing cross-brand identity bleed.
- **Deactivation (`is_active=false`)** stops both ingestion and outbound while preserving history.

---

#### Phone Number Management

**Overview**

Phone number management is the admin surface for buying, porting, and configuring the voice and SMS phone numbers that power the voice channel and SMS channel. The implementation is provider-abstracted: Twilio is the first carrier, but the adapter pattern allows additional carriers without admin-UI changes. Example: a Thai brand searches for a Bangkok local number, purchases +66-2-XXX-XXXX, and the platform automatically configures the voice webhook to `webhook-twilio-voice` (routing inbound calls to the ElevenLabs AI agent) and the SMS webhook to `webhook-twilio-sms` (routing inbound SMS into the unified inbox).

**Purpose**

To make voice and SMS provisioning a one-screen self-service workflow, without forcing admins to learn the carrier's console or hand-configure webhooks. Numbers are immediately ready for both inbound channels on purchase.

**User Journey**

*Admin journey*

1. Choose account model — BYOT (own Twilio credentials) or Master (platform-managed subaccount).
2. Search available numbers by country, region, and capability.
3. Purchase the chosen number; the platform auto-configures voice and SMS webhooks.
4. Optionally re-point webhooks manually (rare) or deactivate (`is_active=false`) when no longer routed.
5. Release the number explicitly when no longer needed; deactivation alone does not release.

*Edge cases*

- BYOT bills go directly to the merchant from Twilio; Master consolidates billing through the platform.
- Number deactivation stops routing but the merchant still owns the number on Twilio until explicit release.

**Configurations & Rules**

*Account models*

| Model | Credentials | Billing |
|---|---|---|
| **BYOT (Bring Your Own Twilio)** | Merchant's own Twilio account | Twilio bills the merchant directly |
| **Master** | Platform-managed Twilio subaccount per merchant | Platform consolidates billing |

*Operating rules*

- Webhooks are auto-configured on purchase via the `cs-phone-numbers` Edge Function — both Voice URL and SMS URL point to platform webhooks.
- **One number serves both channels**: inbound voice → ElevenLabs AI agent; inbound SMS → unified inbox. The platform infers the channel from Twilio's webhook event type.
- Manual re-pointing is supported but rarely needed.
- Deactivation ≠ release. Releasing a number requires an explicit admin action with confirmation.

---

#### Unified Customer Identity

**Overview**

Unified customer identity is one record per real human, no matter how many platforms they reach out from. A row in `cs_customers` is the unified customer; rows in `cs_platform_identities` link that human to specific platform IDs (Shopee buyer_id, LINE UID, phone number, email address). Optionally linked to loyalty's `user_master.id` for cross-domain context. Example: a customer first contacts via Shopee (`buyer_id=12345`), later messages on LINE (`uid=U_abc`), and calls in (phone `+66-XX-XXX-XXXX`). The platform recognises all three as the same person via three rows in `cs_platform_identities` pointing to one `cs_customers.id`. AI sees full cross-channel history; agents see one profile.

**Purpose**

To make cross-channel history and loyalty-side context available to agents and AI without requiring buyers to authenticate or hand over a unifying identifier. Identity resolution is the boundary between platform-level chaos (different IDs everywhere) and the platform's clean internal customer model.

**User Journey**

*Admin journey*

1. Mostly invisible — resolution runs automatically at message ingestion.
2. When two `cs_customers` rows are determined to be the same human, an admin runs a merge from the agent workspace; the action is destructive and audited (moves identities, conversations, messages, memory, and events to the surviving row, writes a `cs_conversation_events` audit entry).
3. Optionally link or unlink loyalty (`cs_customers.crm_user_id`) for brands using both modules.

*Member journey*

Invisible. A buyer messages on any platform; the agent and AI already have their full history.

*Edge cases*

- Same human with multiple identities on the same platform (e.g., changed LINE account) → separate rows pointing to one customer.
- Cross-merchant isolation: the same Shopee `buyer_id` on Brand A and Brand B yields two separate `cs_customers` rows that must never be merged.
- Customer memory (`cs_customer_memory`) is scoped to the customer, not platform identity — facts apply regardless of next channel.

**Configurations & Rules**

*Operating rules*

- **Resolution runs at ingestion, before conversation creation** — webhook arrives → adapter extracts platform identity → lookup `cs_platform_identities` for `(platform_type, platform_user_id)` scoped to merchant → existing → use that customer; no match → create `cs_customers` + `cs_platform_identities` rows.
- **Identity uniqueness**: `(customer_id, platform_type, platform_user_id)`.
- **Cross-merchant isolation** enforced by `merchant_id` — never merge across merchants.
- **Loyalty linking is optional and one-way** — `cs_customers.crm_user_id` is nullable. Brands using only CS leave it null; brands using both auto-link via shared identifier (LINE UID, phone) or merge manually from the workspace.
- **Memory and identity are independent** — `cs_customer_memory` rows are keyed to `customer_id`, not platform identity.
- **Identity merge is destructive and audited** — moves `cs_platform_identities`, conversations (and their messages), `cs_customer_memory`, and `cs_conversation_events` to the surviving record; writes an audit row in `cs_conversation_events`.

---

### Agent Workspace

**Overview**

Agent Workspace is the internal operating desk for support agents and supervisors. It brings conversations, customer identity, messages, tickets, priority, assignment, notes, and AI assistance into one daily workflow — instead of forcing teams to work from separate marketplace, email, chat, and CRM screens. A *conversation* is the active service thread; an *assignment* sends ownership to an agent or team; an *internal note* is staff-only context inside the message history; a *ticket* is the structured work item linked when an issue needs lifecycle tracking. Example: a Shopee buyer asks about a damaged shipment; the agent opens the workspace, sees the resolved contact profile, reviews prior messages, creates a high-priority damage ticket, adds an internal note, and sends a customer-safe reply drafted by Live Assist.

**Purpose**

To be the omnichannel agent desktop. It improves throughput by reducing tab switching, standardizes handoffs between agents and between humans and AI, and gives every human the same context that rules and AI use — so quality and speed don't depend on which screen the agent happened to open first.

**User Journey**

*Admin journey (supervisor)*

1. Review queue counts and workload across teams and channels.
2. Reassign overloaded agents or teams.
3. Inspect escalated conversations and ticket links before intervention.

*Agent journey*

1. Open the workspace queue and filter by status, priority, team, assigned agent, modality, or search text.
2. Select a conversation; review the timeline, contact details, tags, current procedure state, and linked ticket summary.
3. Send a reply, add an internal note, update priority, assign or transfer ownership, or create / update a ticket.
4. Use Live Assist or knowledge search when an answer needs drafting or grounding.
5. Resolve, snooze, or keep the conversation open based on the actual customer state.

*Edge cases*

- A conversation with no assignee must remain visible in unassigned queues.
- Voice conversations need call metadata alongside the message timeline.
- Ticket updates should not be hidden inside the conversation timeline without a clear link.

**Configurations & Rules**

*Configuration surfaces*

| Surface | What's configured |
|---|---|
| **Queue views** | Filters on status, priority, modality, assigned agent, assigned team, tags, free-text search |
| **Reply controls** | Customer-visible messages vs staff-only notes (clearly separated) |
| **Related panels** | Customer details, related tickets, current AOP state, AI sidebar |

*Operating rules*

- Conversation status is **distinct from ticket status** — resolving one should not silently close the other.
- Assignment can target an agent, a team, both, or neither, depending on routing rules and manual ownership.
- Internal notes must remain staff-only and **never flow through channel adapters**.
- Agent availability and capacity guide routing but do **not** replace supervisor override.
- Filtering by assigned agent, team, status, priority, and modality returns consistent queues.
- Updating assignment or status writes an auditable event to `cs_conversation_events`.

*Limitations*

- The workspace renders and updates CS records — it is not the source of channel ingestion (that lives in Connectivity).
- Voice calls share conversation context but carry additional call metadata and transfer constraints.

---

#### Unified Inbox

**Overview**

The unified inbox is one queue across every chat-shaped channel — Shopee, Lazada, TikTok Shop, LINE OA, Messenger, Instagram DM, WhatsApp, email, web widget, SMS — plus internal-note threads. Voice calls render in the voice console (separate sub-feature) but link back here for handoff. Example: an agent's inbox shows 23 conversations — 8 on Shopee (with order-card previews), 6 on LINE (with rich-message badges), 5 emails (threaded by subject + 72h interval), 3 WhatsApp, 1 web widget. Filters narrow by channel, status, priority, assignee, or unread. One click opens the thread with channel-native rendering — Shopee shows product cards, LINE shows flex messages.

**Purpose**

To replace tab-juggling with a single ordered queue. Agents see every customer message in one place, ordered by priority and recency, with channel-native rendering preserved so context isn't lost in translation.

**User Journey**

*Agent journey*

1. Open the inbox; default sort is `priority desc, last_message_at desc` (per-agent override allowed).
2. Filter by channel, status, priority, assignee, or unread.
3. Click a thread to open it with channel-native rendering.
4. Reply, add an internal note (staff-only), or change conversation status.
5. Resolve, snooze, or pass to "waiting on customer".

*Edge cases*

- A new message on a resolved / closed conversation **reopens it within `threading_interval`**; beyond that, a new conversation is created and any ticket linkage carries forward.
- Conversations in `waiting on customer` status **pause SLA timers** and re-open when the customer replies.
- An agent may set a non-default sort (e.g., SLA approaching first).

**Configurations & Rules**

*Threading defaults per channel*

| Channel | Session timeout | Threading interval |
|---|---|---|
| LINE | 24h | 48h |
| WhatsApp | 24h | 24h |
| Email | — | 72h |
| Web chat | 30 min | — |
| Voice | always-new | — |
| Marketplaces (Shopee, Lazada, TikTok) | follow native | `platform_conversation_id` 1:1 |

*Operating rules*

- **Internal notes never reach the customer** — outbound dispatchers filter by `message_type='note'`; only `text`, `image`, `product_card`, `order_card`, `voice_transcript`, `file` go out.
- **Status transitions are tracked**, not only current state — every change writes to `cs_conversation_events` so analytics can compute time-in-status.
- **Default sort** is `priority desc, last_message_at desc`; per-agent overrides supported.
- Reopen window equals the channel's `threading_interval`.

---

#### Voice Console

**Overview**

The voice console is the live-call interface for inbound and outbound voice — the same `cs_conversations` table as chat with `modality='voice'`, plus voice-specific metadata in `cs_voice_calls`. Built on Twilio SIP trunks routed through ElevenLabs for STT and TTS, with the platform's own AI decisioning for response generation. Example: an inbound call arrives on +66-2-XXX-XXXX; the voice console rings, the agent answers and sees live transcript scrolling, the customer's profile resolved by phone number (linked to past conversations and loyalty tier). The agent warm-transfers to a Thai-speaking colleague — the AI generates a transfer summary visible to the receiving agent before they pick up.

**Purpose**

To put voice on the same operating surface as chat. Agents and supervisors see calls in the same workspace with the same customer context, live transcript, recording, and post-call disposition — no separate phone system to learn and no context lost on transfer.

**User Journey**

*Agent journey*

1. Accept the inbound ring or initiate an outbound call.
2. Watch the live transcript stream; see the resolved customer profile and history beside the call.
3. Add notes, mark intents, or trigger actions during the call.
4. Warm-transfer with an AI-generated summary, or send to voicemail.
5. After the call, finalize the disposition; the canonical transcript replaces the live one.

*Member journey*

A buyer calls or receives a call. If after-hours and the merchant has configured fallback, the AI agent answers, voicemail records (transcribed into the inbox), or the call routes to another team.

*Edge cases*

- Every voice call is **always a new conversation** — no threading by phone number; past calls show in the customer profile sidebar.
- Live transcript is best-effort; **post-call transcript is canonical** and replaces the live stream after `call.ended`.
- Recording is opt-in per merchant config and requires PDPA disclosure in the greeting.

**Configurations & Rules**

*Call state machine*

`ringing` → `in_progress` → `completed` | `failed` | `no_answer`

Transitions written to `cs_voice_calls.call_status` and `cs_conversation_events`.

*Operating rules*

- **Recording is opt-in** — when enabled, recording URL stored in `cs_voice_calls.recording_url`; PDPA requires the call-start greeting to include disclosure.
- **Warm transfer creates a `transferred_to` link** with an AI-generated `transfer_summary` visible to the receiving agent before they join.
- **After-hours fallback per channel config** — AI agent answers (default), goes to voicemail (transcript created as a `cs_messages` row), or routes to another timezone team.

---

#### Live Assist (Copilot)

**Overview**

Live Assist is the AI copilot embedded in the agent workspace. It augments human agents — drafts replies, summarises conversations, answers internal questions from the knowledge base, recommends actions, and translates in real time. Example: a Thai-speaking customer messages on LINE in Thai about a refund. The agent sees the message in Thai with English translation alongside, opens the copilot sidebar, and types *"what is our refund policy for items delivered more than 7 days ago"* — copilot returns the answer with citations to two knowledge articles. The agent clicks *"draft reply"*, copilot proposes three options, the agent edits one, copilot translates it back to Thai, the agent sends.

**Purpose**

To accelerate human agents without replacing them. Copilot raises throughput by pre-drafting messages and grounding answers in the knowledge base, raises quality by citing sources and translating both ways, and keeps every action under explicit human approval.

**User Journey**

*Agent journey*

1. Open a conversation; copilot summarises the thread in the sidebar.
2. Ask copilot a natural-language question (e.g., refund eligibility); see the answer with cited sources.
3. Click *"draft reply"*; choose from proposed options and edit.
4. Translate inbound messages or outbound drafts on demand.
5. Review action recommendations (e.g., "Refund eligible — confirm to issue") and confirm before execution.

*Edge cases*

- An answer with no citations is flagged as low-confidence; the agent must verify.
- Translation language detected from message content or set explicitly on the customer profile; agent UI language from session preferences.
- Multi-tenant: copilot never sees other merchants' data — RLS scopes every query to `merchant_id` from the agent's session.

**Configurations & Rules**

*Operating rules*

- **AI-drafted replies are suggestions, not auto-sends** — the agent must click send; edits and rejections are logged for quality tracking.
- **Sidebar searches knowledge articles, past conversations, and internal docs**; source filter is agent-controlled per query.
- **Every copilot answer cites its sources** — empty citations means the AI is reasoning without grounding, flagged as low-confidence in the UI.
- **Translation is bidirectional and auto-detected** for both customer language and agent UI language.
- **Action recommendations include policy pre-checks** — e.g., "Refund eligible" means the AI verified the order matches the refund policy (delivered date, amount, customer tier); the agent still confirms before execution.
- **Multi-tenant isolation enforced by RLS on every knowledge query** — `merchant_id` auto-scoped from agent session.

---

#### Routing & Assignment

**Overview**

Routing & Assignment decides who handles each conversation: which team, which agent, when, and what happens at SLA boundaries. It combines static config (teams, skills, max concurrent) with dynamic rules (round-robin, least-busy, skill-match, manual) and SLA-driven escalation. Example: a VIP customer messages on LINE in Thai about a complaint. Routing: tag=VIP → assign to VIP Team; language=Thai → require Thai skill; intent=complaint → set priority=high. Assignment method=least-busy. The conversation lands with Agent Somchai (VIP Team, Thai-skilled, 3 of max 5 concurrent) within 2 seconds of arrival. If unanswered for 10 min (SLA approaching), priority bumps to urgent and the supervisor is notified.

**Purpose**

To turn "who picks this up?" from a manual decision into a deterministic rule that respects team membership, skills, capacity, business hours, and SLAs — and to escalate predictably when those rules are missed.

**User Journey**

*Admin journey*

1. Define teams (e.g., VIP Team, Refund Team); add agents (one agent may be on multiple teams).
2. Configure agent profiles — `status`, `max_concurrent`, `skills` (`{languages, expertise}`).
3. Choose the assignment method per team: round-robin, least-busy, skill-match, or manual.
4. Set SLA targets (response, resolution) and escalation actions per breach.
5. Configure business hours per team / channel / tier and a per-country holiday calendar.
6. Define after-hours fallback (AI agent, voicemail, timezone routing).

*Agent journey*

1. Toggle availability (online / away / offline) on the workspace header.
2. Receive auto-assigned conversations within capacity; pick up unassigned queue items manually.
3. Hand off via team transfer or specific-agent transfer; SLA carries the audit trail.

*Edge cases*

- A conversation **always has at most one human assignee at a time** — assignment changes are atomic and audited.
- SLA approaching → notify assigned agent + bump priority. SLA breached → reassign to supervisor + alert via Slack/LINE Notify.
- A specific agent unavailable → reassign within team using that team's method.

**Configurations & Rules**

*Static config*

| Object | What it holds |
|---|---|
| **`cs_teams`** | Merchant-defined groupings (not org structure); references shared `admin_users`; one agent may be on multiple teams |
| **`cs_agent_profiles`** | Per-merchant `status` (online/away/offline), `max_concurrent`, `skills` jsonb (`{languages:[...], expertise:[...]}`); auto-provisioned on first inbox access |

*Assignment methods*

| Method | Behavior |
|---|---|
| **Round-robin** | Cycles assignees within the team |
| **Least-busy** | Assigns to lowest-load agent under `max_concurrent` |
| **Skill-match** | Matches required skills (language, expertise) to agent profile |
| **Manual** | Supervisor or rule-driven explicit assignment |

*SLA & escalation rules*

- **SLA timers pause on `waiting on customer` and `snoozed` statuses** and resume when the conversation re-opens; pause/resume logged in `cs_conversation_events`.
- **Business hours pause SLA timers** outside the configured schedule (per-team / per-channel / per-tier supported; holiday calendar per country).
- **Escalation is rule-driven** — SLA approaching → notify + bump priority; SLA breached → reassign supervisor + alert; agent unavailable → reassign within team.

---

### Ticket Management

**Overview**

Ticket Management is the structured work-item layer for Customer Service. It tracks issues that need ownership, type, priority, fields, SLA, status changes, parent/child relationships, and audit history beyond a single chat thread. A *ticket* is the persistent work item; *ticket type* defines the case pattern; *status* tracks the lifecycle; *priority* drives urgency; *SLA* sets response and resolution targets; a *conversation link* connects the customer discussion to the ticket. Example: a damaged-shipment conversation becomes a high-priority damage ticket with order details, assigned team, SLA deadlines, and status changes through resolution — even if the customer follows up through another channel.

**Purpose**

To run structured case management inside the CX platform without losing the conversation context that started the issue. It lets teams handle multi-step or dependent work, cross-team handoffs, and internal escalations under one ownership / SLA / audit model.

**User Journey**

*Admin journey (supervisor)*

1. Filter tickets by status, priority, type, assignee, or search.
2. Review SLA due dates and overdue work.
3. Reassign, escalate, or inspect ticket event history.

*Agent journey*

1. Open a conversation or ticket queue.
2. Create a ticket from a conversation, or open an existing ticket.
3. Fill type, priority, subject, description, assignee / team, tags, custom fields, and source.
4. Review linked contact and conversation context.
5. Progress status, add updates, and resolve or close when work is complete.

*Edge cases*

- A ticket may have **no conversation** — the create/edit flow must support internal-only cases.
- Missing mandatory context should block save only for fields actually required by the implementation.
- Reopened tickets should preserve the same ticket number and event trail.

**Configurations & Rules**

*Configuration surfaces*

| Surface | What's configured |
|---|---|
| **Ticket schema** | Type, status, priority, subject, description, contact, assignee, team, SLA policy, tags, custom fields, source |
| **SLA policy** | Response and resolution targets; whether business hours affect deadline calculation |
| **Relationships** | Parent ticket links for multi-step or dependent work |

*Operating rules*

- A ticket can exist independently from a conversation, but conversation-linked tickets must preserve context.
- **Ticket status is separate from conversation status** — resolving one does not silently close the other.
- SLA can pause or change based on status policy only when configured.
- Ticket events capture every lifecycle change for audit and analytics.
- Creating a ticket generates a ticket number; updating status or priority writes an event; SLA deadlines come from policy + business hours.

*Limitations*

- Custom field validation and approval workflows must be verified per implementation before promising advanced case schemas.
- Ticket actions that touch external systems depend on configured integrations (see Actions & Integrations).

---

### Rules-Based Automation

**Overview**

Rules-Based Automation is the deterministic automation layer for Customer Service. It handles predictable work — routing, assignment, tagging, priority updates, auto-replies, escalation, ticket creation, SLA handling, AI handoff — without spending LLM reasoning on cases that can be expressed as rules. A *workflow* is the configured automation graph; a *trigger* starts it; a *condition* decides whether it continues; an *action* changes state or sends output; `domain='cs'` separates CS workflows from loyalty workflows. Example: an inbound Shopee message arrives outside business hours; a workflow checks channel and business hours, sends an order-tracking template, tags the conversation, and leaves it for the morning queue.

**Purpose**

To be the predictable automation engine — fast, low-cost, auditable — complementary to CS AI for open-ended cases. Rules cover the cases where the decision is mechanical; CS AI covers the cases that require reasoning.

**User Journey**

*Admin journey*

1. Open the workflow builder and create a CS workflow.
2. Choose the trigger, run mode, scope, and active state.
3. Add condition nodes — channel, priority, tags, business hours, intent, customer attributes.
4. Add action nodes — assign, tag, send reply, set priority, create ticket, notify, or invoke AI where configured.
5. Test the graph with sample event data.
6. Publish and monitor workflow runs from logs / analytics.

*Agent journey*

1. The agent sees the workflow's output in the workspace — assigned owner, tag, priority, message, ticket, or AI handoff.
2. The agent can override workflow output where permissions allow.

*Edge cases*

- Disabled workflows should be visible but non-executing.
- A workflow with no matching condition should leave the conversation unchanged.
- Failed actions need visible workflow-log errors.

**Configurations & Rules**

*Configuration surfaces*

| Surface | What's configured |
|---|---|
| **Workflow definition** | `domain='cs'`, scope, run mode, triggers, condition nodes, action nodes, graph layout |
| **Triggers (CS-specific)** | Message receipt, conversation creation, status change, SLA state, customer identified |
| **Actions** | Shared action catalog where possible; CS-specific actions for assign / tag / send reply / set priority / create ticket / invoke AI / notify |

*Operating rules*

- **Use rules for deterministic logic; use CS AI for open-ended reasoning.**
- Workflow actions must respect conversation, ticket, channel, and permission constraints.
- `run_mode` controls duplicate execution and should be explicit.
- AI handoff (`cs_invoke_ai`) must pass enough context — and optional procedure intent — for safe continuation.
- A CS workflow run writes to `workflow_log`.
- Disabled workflows do not execute; CS workflow queries filter `workflow_master.domain='cs'`.

*Limitations*

- Rules only do what is configured; they do not infer missing intent beyond defined conditions.
- Shared workflow tables require explicit CS filtering to avoid mixing with loyalty automation.

---

#### Chatbot Flows

**Overview**

Chatbot flows are scripted message-channel automations — button menus, decision trees, keyword auto-replies — primarily on the web widget and LINE rich menus. Used for first-touch deflection and routing before a human or AI agent enters the conversation. Example: a visitor opens the web widget; the bot greets them with three buttons — *"Track my order"*, *"Return an item"*, *"Talk to a human"*. Click *"Track my order"* → bot prompts *"What is your order number?"* → user types `A-12345` → bot calls the `lookup_order` action → bot displays a status card + *"Anything else?"* → if *no* → conversation auto-resolves; if *yes* → bot routes to the AI agent.

**Purpose**

To deflect cheap, mechanical questions (order tracking, return policy) before they touch a human or an LLM token. Keeps response time low and cost flat while preserving an explicit human escape hatch on every flow.

**User Journey**

*Admin journey*

1. Build the flow visually — first message, branches by button / keyword, downstream nodes (calls to lookups, conditional branches, AI handoff, human escalation).
2. Configure per-channel: web widget greeting, LINE rich menu, marketplace auto-reply.
3. Activate the flow; first-touch traffic now hits it.

*Member journey*

A buyer messages on a channel where a flow is configured; sees a friendly greeting with buttons (or rich-menu / quick reply). Picks an option, follows the branches, gets an answer or hits *"Talk to a human"* to escape.

*Edge cases*

- A bot can be **turned off per channel without deleting it** (`is_active=false`); in-flight flows finish.
- **Customer can always escape to a human** — every flow includes a "Talk to a human" branch or accepts `human` / `agent` keywords.
- Button selections are stored as `cs_messages` rows with `metadata.button_id` so the flow knows which branch the buyer took.

**Configurations & Rules**

*Operating rules*

- **Chatbot flows always run BEFORE AI** — a configured flow on a channel intercepts every new conversation; AI takes over only when the flow ends or hits `cs_invoke_ai`.
- **Button options are stored as part of the message** — selection writes a `cs_messages` row with `metadata.button_id`.
- **Keyword triggers are case-insensitive and match anywhere** — patterns can include synonym lists (e.g., *"where is my order"* OR *"tracking"* OR *"shipped"*).
- **Bot decisions do not bypass identity resolution or the rules engine** — bot flow runs after identity is resolved and after upstream rules (priority, routing) execute.
- Deactivating a flow (`is_active=false`) stops new triggers; in-flight flows finish.

---

#### IVR Flows

**Overview**

IVR flows are scripted voice-channel menus — DTMF (touch-tone) and speech-recognised — that play before the AI voice agent or human picks up. Used for routing menus, language selection, callback queues, and after-hours messages. Example: a customer calls +66-2-XXX-XXXX. IVR plays *"For Thai, press 1, สำหรับภาษาไทย กด 1. For English, press 2."* Customer presses 1 → IVR plays *"Press 1 for sales, 2 for support, 3 for billing."* Press 2 → routes to the AI voice agent with `language=th` and `intent_hint=support`. Whole IVR runs in < 8 seconds; no LLM tokens until handoff.

**Purpose**

To route inbound voice traffic deterministically before any AI / human time is spent. Cheap, fast, and predictable for the universal "language + department" question that opens almost every call.

**User Journey**

*Admin journey*

1. Build the IVR using voice-specific node types (`play_audio`, `gather_dtmf`, `gather_speech`, `transfer`, `voicemail`).
2. Record or upload prompt text per language; the platform pre-renders TTS audio.
3. Configure default fallback (AI voice agent) and after-hours behavior (AI / voicemail / busy / timezone route).
4. Enable recording disclosure prompt where recording is on.

*Member journey*

A caller hears the menu, makes a selection (key press or speech), and is routed to the configured destination (team, AI agent, voicemail).

*Edge cases*

- If a caller does not make a selection within timeout → **default fallback is the AI voice agent**, picking up with a brand greeting.
- **Recording disclosure plays at IVR start when recording is enabled** — non-skippable for inbound calls (PDPA).
- DTMF and speech gathers can be combined on the same node.

**Configurations & Rules**

*Voice-node primitives*

| Node | What it does |
|---|---|
| `play_audio` | Plays a pre-rendered TTS or uploaded audio |
| `gather_dtmf` | Captures touch-tone input |
| `gather_speech` | Captures spoken input |
| `transfer` | Routes to a team, agent, or AI voice agent |
| `voicemail` | Records, transcribes, files in inbox |

*Operating rules*

- **IVR is voice-only by definition** — same rules engine, voice-specific node types.
- **Audio prompts are pre-rendered TTS per language** — avoids per-call TTS latency; re-rendered when prompt text changes.
- **Default fallback is the AI voice agent.**
- **After-hours behavior is configured per number** — AI agent (default), voicemail (auto-transcribed into the inbox), busy signal, or route to another timezone team.

---

#### Rules & Triggers

**Overview**

Rules & Triggers is the general-purpose rules engine — everything beyond chatbot and IVR. Routing rules, tagging on keyword, priority bumping, auto-escalation on SLA approach, after-hours behavior, status-change side effects. All built on the shared `workflow_master` table with `domain='cs'`. Example: rule *"VIP fast-track"* — trigger=`cs_message_received`, conditions=`customer.tags contains 'vip'` AND `business_hours='inside'`, actions=set priority=urgent + tag conversation `vip_in_progress` + notify VIP team channel via Slack. Fires the moment Connectivity ingests the first VIP message; an agent in the VIP team sees the conversation at the top of their queue with full context.

**Purpose**

To turn repeatable side effects ("when X arrives, do Y, then Z") into auditable, low-cost automation. Same grammar as loyalty workflows so admins write rules once instead of learning a separate CS-specific DSL.

**User Journey**

*Admin journey*

1. Pick a trigger (message received, status changed, SLA approaching, intent detected, customer identified, etc.).
2. Add conditions with nested boolean logic (AND / OR / NOT, parentheses).
3. Choose actions — auto-reply, assign, tag, escalate, invoke AI, notify, create ticket, etc.
4. Set `run_mode` (e.g., `once_per_trigger`) to control duplicate execution.
5. Publish; monitor `workflow_log` per node for failures.

*Edge cases*

- **Triggers fire in declaration order** — when two rules listen on `cs_message_received` for overlapping conditions, **both fire**; the platform does not pick one. Idempotency is the author's responsibility.
- **Rule changes do not affect in-flight runs** — each run snapshots the workflow definition; live edits apply to subsequent triggers only.
- A rule can **hand off to AI mid-flow** via `cs_invoke_ai` and resume on AI's return status.

**Configurations & Rules**

*Operating rules*

- **Conditions support nested boolean logic** — AND, OR, NOT, parentheses. Same grammar as loyalty workflows.
- **Actions execute sequentially within a single workflow run** — if action 2 fails, action 3 still attempts (each logged in `workflow_log`).
- **SLA-driven triggers are cron-scheduled, not event-driven** — `cs_sla_approaching` and `cs_sla_breached` evaluate every minute against open conversations.
- **`cs_invoke_ai` ends the deterministic phase**; downstream nodes after it execute only when AI returns a non-handed-off status (e.g., AI resolves → workflow continues with `cs_close`).
- Idempotency control: `run_mode='once_per_trigger'` recommended when overlapping triggers are possible.

---

### CS AI

**Overview**

CS AI is the reasoning layer for Customer Service. It uses merchant brand configuration, guardrails, procedures, knowledge search, conversation context, and available actions to draft or send support responses across chat and voice-adjacent workflows. *Brand configuration* defines voice, language, guidance, and model behavior; an *AOP (procedure)* is an intent-specific playbook; *guardrails* constrain what the AI may say or do; *knowledge search* grounds factual answers; *actions* are the permitted operations the AI can request. Example: a customer asks about an exchange; AI loads the conversation context, finds the active Returns procedure, searches the knowledge base, asks for missing details, and either drafts a response for an agent or continues autonomously if policy allows.

**Purpose**

To be the controllable conversational agent. It handles open-ended requests that rules cannot, while procedures, knowledge, actions, and Watchtower keep it governable, on-brand, and aligned with policy. One brain serves both chat and voice — same brand config, same AOPs, same knowledge base, same actions.

**User Journey**

*Admin journey*

1. Open AI settings; configure brand voice, language, guidance, model settings, and outbound behavior.
2. Create or edit guardrails by category and priority.
3. Create a procedure (AOP) with name, trigger intent, raw content, compiled steps, flexibility, and action / knowledge expectations.
4. Activate the procedure after review.
5. Test AI behavior against sample conversations — especially missing-knowledge, escalation, and prohibited-action cases.

*Agent journey*

1. Open a conversation and request a draft, summary, translation, or next-best answer.
2. Review the AI output against knowledge and procedure context.
3. Edit and send, or take over from autonomous mode when escalation is needed.

*Edge cases*

- Inactive procedures should not be selectable.
- Conflicting guardrails resolve by priority.
- Unsupported actions should be hidden rather than shown as failing options.

**Configurations & Rules**

*Configuration surfaces*

| Surface | What's configured |
|---|---|
| **Brand AI Configuration** | Voice, language(s), guidance rules, model settings, outbound behavior, guardrails |
| **Procedures (AOPs)** | Trigger intent, raw instructions, compiled steps, flexibility, action / knowledge expectations, active version |
| **Available actions** | Per-AOP whitelist + global action catalog (see Actions & Integrations) |
| **Knowledge grounding** | Knowledge sources, languages, statuses approved for AI consumption |

*Operating rules*

- AI loads conversation context before responding.
- Procedures and guardrails constrain action selection and escalation.
- AI may assist humans through drafts, or operate autonomously where configured.
- Customer-facing answers use channel-appropriate language and tone.
- Knowledge-grounded answers must search approved CS knowledge before making factual claims.
- If the contact is not linked to loyalty context, AI must not claim loyalty details.
- Missing knowledge should trigger clarification, escalation, or a safe fallback — not a guess.

*Limitations*

- AI quality depends on configured knowledge, procedures, guardrails, and action availability.
- Active procedure selection must match intent; guardrails block prohibited content.
- Knowledge search and action availability are loaded through verified functions before use.

---

#### Brand AI Configuration

**Overview**

Brand AI Configuration is the per-merchant control panel that shapes how the AI sounds, what languages it speaks, when it escalates, and which model powers it. Configured once at onboarding and refined with every Watchtower review. Example: a Thai cosmetics brand sets `persona="warm and helpful beauty consultant"`, `tone="professional but friendly, never use slang"`, `primary_language=th`, `secondary=en`, `escalation_threshold="customer expresses anger OR mentions legal action OR three failed AI attempts"`, `default_model="gpt-4o"`, `voice_id="elevenlabs:voice_xyz"`. Every chat and voice conversation inherits these defaults; specific AOPs can override per-conversation.

**Purpose**

To centralize brand-defining AI behavior in one merchant-scoped row, then let downstream layers (AOPs, conversations) override safely. Persona and tone never have to be re-stated per AOP; escalation triggers are deterministic, not LLM-judged.

**User Journey**

*Admin journey*

1. Open AI settings; fill persona, tone, primary / secondary language, default model, voice ID.
2. Define escalation thresholds as deterministic conditions (anger keywords, legal mentions, attempt count).
3. Configure action_config (which tools are reachable and per-tool limits) and outbound_config (quiet hours, cooldowns).
4. Save — versioned automatically; old versions retained for replay.

*Edge cases*

- **Voice ID is locked once chosen for an active deployment** — changing mid-stream confuses returning callers; change requires explicit operator action with a 24-hour grace window.
- AOPs can override the default model; conversation-level override is rare and agent-set during Live Assist.

**Configurations & Rules**

*Configuration shape*

| Setting | Notes |
|---|---|
| **Persona / tone** | Free-form descriptions injected into every system prompt; AI cannot override; off-tone triggers Watchtower flags |
| **Languages** | Primary + secondary; gates STT/TTS model selection on voice (e.g., `th-only` won't load an English ElevenLabs voice) |
| **Model selection** | Default model + per-pipeline-stage selection; cascades brand → AOP → conversation; each level logged |
| **Escalation thresholds** | Deterministic conditions checked between AI turns; threshold crossed → handed to human regardless of AI's intended next step |
| **Voice ID** | Locked for active deployment; change requires explicit operator action with 24h grace |
| **action_config** | Which tools the AI can reach + per-tool limits |
| **outbound_config** | Quiet hours, cooldowns |

*Operating rules*

- **Brand config is per-merchant, single-row, versioned.** New conversations always start with the latest version.
- **Persona and tone are injected into every system prompt.** AI cannot override them.
- **Model selection cascades**: brand default → AOP override → conversation override (logged at every level).

---

#### Agent Operating Procedures (AOPs)

**Overview**

An Agent Operating Procedure (AOP) is a playbook the AI follows for one class of conversation — *Returns*, *Order Status*, *Complaint*, *Exchange*. Each AOP defines the steps, the tools the AI may call, which actions require approval, and when to escalate. Example: AOP *"Returns"* — step 1: confirm order number via `lookup_order`; step 2: ask reason; step 3: if reason in `["defective","wrong_item"]` AND `order_age_days < 14` → issue refund up to 5000 THB autonomously; step 4: if amount > 5000 OR reason=`changed_mind` → create ticket type=`return` for human review; step 5: send confirmation. Tools whitelisted: `lookup_order`, `issue_refund`, `create_ticket`, `send_message`. Anger keywords trigger escalation regardless of step.

**Purpose**

To express per-intent policy as a step-by-step playbook the AI must follow — bounded tools, bounded approval thresholds, bounded escalation. Replaces "trust the LLM" with "execute this procedure, version locked, replay-able."

**User Journey**

*Admin journey*

1. Create an AOP per intent (Returns, Refunds, Complaint, etc.).
2. Write the procedure in natural language; the system compiles it into structured steps with tool references.
3. Set flexibility mode (strict / guided / agentic), per-procedure tone override, turn limits, timeouts.
4. Choose tool whitelist and per-tool approval thresholds.
5. Activate; future conversations matching the intent run under this AOP version.

*Edge cases*

- **One conversation runs under one AOP at a time** — switching AOPs is a logged event (e.g., "Order Status" detects a complaint mid-conversation → hands off to "Complaint" AOP with full prior context).
- **AI cannot call a tool the AOP doesn't permit** — attempts are logged and escalated to Watchtower.
- **Procedure resolution can be pinned by rules** — a trigger like `channel=line AND business_hours=outside` can force AOP=*After Hours Triage*; without a pin, AI auto-selects on intent classification.
- AOPs are versioned — old runs reference their version; replay reproduces the same behavior.
- AOPs support sub-procedures — *Returns* can call *Verify Order*; callee inherits caller's conversation context but uses its own tool whitelist.

**Configurations & Rules**

*Flexibility modes*

| Mode | Behavior |
|---|---|
| **Strict** | AI follows steps in order; no improvisation |
| **Guided** | AI follows steps but may skip / reorder with justification |
| **Agentic** | AI uses steps as guidance; selects tools dynamically within whitelist |

*Operating rules*

- **AOP whitelists tools** — calls outside whitelist are logged + escalated.
- **Action approval thresholds are AOP-specific** — same merchant may auto-approve refunds up to 5000 THB but loyalty points only up to 500.
- **AOPs are versioned** — old runs reference their version; replay reproduces behavior.
- **Procedure resolution can be pinned by rules** — otherwise AI auto-selects on intent classification.
- **Sub-procedures inherit caller's conversation context** but use their own tool whitelist.

---

#### Watchtower

**Overview**

Watchtower is the continuous-monitoring layer over every AI conversation — chat and voice. It samples or full-scans AI runs against criteria like hallucination, off-brand tone, low predicted CSAT, repeat-contact patterns, and tool misuse. Outputs feed a queue of flagged conversations for QA review and AOP tuning. Example: Watchtower scans an AI conversation that resolved with *"Your refund will arrive in 14 business days"*. Cross-reference with knowledge base → published policy is 7 days. Flag raised: `hallucination_severity=high`, `conversation_id=...`, AOP=`Refunds`, `model=gpt-4o`. Surfaced in QA queue with a proposed fix to the refund AOP wording.

**Purpose**

To keep AI behavior auditable and improvable without slowing the customer. Always-on monitoring catches drift, hallucination, and missed escalation; proposed fixes route to a human operator who can accept or reject — Watchtower never auto-modifies AOPs or conversations.

**User Journey**

*Admin / QA journey*

1. Configure sampling rates per AOP (high-risk default 100%, low-risk default 10%).
2. Enable / disable detectors (hallucination, off-brand tone, predicted-CSAT, tool misuse, missed escalation).
3. Review flagged conversations in the QA queue.
4. Jump from finding → conversation replay → the exact LLM turn that triggered the flag.
5. Accept or reject the proposed AOP / rule edit; the system tracks acceptance rate over time.

*Edge cases*

- Multiple detectors can flag the same conversation — each writes its own finding row.
- A real-time critical flag (severe hallucination, gross policy breach) raises an alert beyond the queue.
- Findings link to specific events in `cs_conversation_events` for precise replay.

**Configurations & Rules**

*Detectors*

| Detector | Looks for |
|---|---|
| **Hallucination** | Wording that contradicts the knowledge base |
| **Off-brand tone** | Deviation from configured persona / tone |
| **Predicted CSAT** | Low expected satisfaction signals |
| **Tool misuse** | AOP-illegal tool use, parameter abuse, missed approvals |
| **Missed escalation** | Threshold conditions crossed without handoff |

*Operating rules*

- **Watchtower runs asynchronously after each AI conversation closes** — does not block the customer; results land minutes later.
- **Sampling rate is configurable per AOP.**
- **Detectors run as separate evaluators** — one conversation can have multiple findings.
- **Findings include a proposed fix** — operator approves or rejects; system tracks fix-acceptance rate.
- **Watchtower does not modify conversations or AOPs autonomously** — operator action required; avoids feedback loops that drift the brand voice.
- **Distinct from QA scorecards** — Watchtower is always-on against custom natural-language criteria; QA scorecards are a separate human-grading surface.

---

### Knowledge Base

**Overview**

Knowledge Base is the approved content layer used by CS AI and human agents. It stores articles, custom answers, source metadata, chunk embeddings, categories, language, and status so support answers can be grounded in merchant-controlled facts. An *article* is a maintained content item; a *custom answer* is a pinned response for known questions; a *source* is where content came from; a *chunk* is a searchable piece of an article; an *embedding* enables semantic retrieval; a *citation* links an answer back to content. Example: a customer asks whether a sunscreen is reef-safe; AI searches CS knowledge, retrieves the relevant article chunk, and drafts an answer grounded in the article instead of relying on model memory.

**Purpose**

To be the grounding system. Upload or sync service facts once, then use them consistently in AI answers, agent assist, QA, and help-center material — and surface gaps when content is missing.

**User Journey**

*Admin journey*

1. Open Knowledge Base; review overview, article list, categories, sources, and custom answers.
2. Create or edit an article with title, content, category, language, source URL, status, and optional custom-answer fields.
3. Add or edit a knowledge source and trigger a sync when the source should refresh.
4. Bulk-update article status, category, or filters for maintenance.
5. Test search from a conversation or admin search box before relying on content for AI.

*Agent journey*

1. Open a conversation and search knowledge from the workspace.
2. Review the matching article or resource.
3. Use the grounded content in a customer reply or AI-assisted draft.

*Edge cases*

- Empty search should distinguish *no articles* from *filters too narrow*.
- Failed source sync needs a visible status and retry path.
- Custom-answer priority conflicts must be predictable.

**Configurations & Rules**

*Configuration surfaces*

| Surface | What's configured |
|---|---|
| **Article schema** | Title, content, category, language, status, source metadata, optional custom-answer settings |
| **Sources** | Upstream content system + sync configuration |
| **Custom answers** | Question patterns + priority for forced retrieval |
| **Embeddings** | Generated per chunk via pgvector — system-managed, not user-managed |

*Operating rules*

- **Published / active knowledge is searchable** by agents and AI; draft / inactive content is not treated as approved answer material.
- **Knowledge search respects merchant scope**, category, language, and source filters where configured.
- **Custom answers are for responses that must be returned consistently** — take precedence over normal article retrieval when patterns and priority apply.
- **Embeddings are system-generated** for chunks; users do not manage vectors manually.
- Updating an article refreshes searchable content immediately.

*Limitations*

- Stale or missing articles produce weak AI answers — the product should surface content gaps.
- Not every article is suitable for customer-facing use if it contains internal instructions.

---

### Actions & Integrations

**Overview**

Actions & Integrations is the **governed action layer** for Customer Service — the reusable set of operations humans, rules, AI, and scheduled jobs can invoke from the same customer and conversation context. It covers platform actions (create ticket, send channel reply, look up knowledge, notify another team) and approved external integrations (marketplace operations, Shopify, LINE OA, CRM bridge, custom API builder, computer-use agent). An *action* is a named operation with inputs, outputs, permissions, and audit expectations; an *integration* is the connected external system or channel capability behind that action; a *macro* is a saved sequence presented as one agent-facing command. Example: during a damaged-order conversation, an agent or AI can create a ticket, attach the conversation, notify a supervisor, and continue the customer reply flow without leaving the workspace.

**Purpose**

To be deliberately caller-agnostic. The same action catalog serves Agent Workspace buttons, Rules-Based Automation nodes, CS AI tool use, and operational jobs — while approval, rate limits, and traceability stay attached to the action itself rather than to the caller.

**User Journey**

*Admin journey*

1. Open the actions or integrations settings area; review the available action catalog.
2. Enable a platform or internal action for the merchant; confirm the channel, credential, or system capability it depends on.
3. Configure display name, description, permitted callers, required input fields, and failure message.
4. Attach approval rules or supervisor review for high-risk operations.
5. Test with sample conversation or ticket context before exposing the action to agents, workflows, or AI procedures.
6. Publish; verify it appears in workspace / workflow builder / procedure configuration only where permitted.

*Edge cases*

- Missing credentials keep the action **unavailable** rather than partially configured.
- A permission change should remove the action from pickers AND block existing invocations.
- If an upstream platform is unavailable, the UI shows the failed action state and preserves the conversation context for handoff.

**Configurations & Rules**

*Action definition surfaces*

| Surface | What's configured |
|---|---|
| **Action definition** | Name, input requirements, output behavior, caller permissions, approval policy, visible failure message |
| **Caller exposure** | Which callers (workspace / workflow / AI / scheduled) may see the action |
| **Approval policy** | Per-action threshold + supervisor-review rule (enforced regardless of caller) |
| **Integration credentials** | Stored outside LLM-visible context; channel authorization kept separate |

*Operating rules*

- **Approval is enforced at the action level, not by trusting the caller.** A high-risk operation remains gated whether triggered by a human, workflow, or AI.
- **State-changing actions need an idempotency strategy and a clear success / failure result** before the customer-facing reply is sent.
- Actions emit enough conversation, ticket, workflow, or event data for audit and analytics.
- **External calls must fail closed** when credentials, permissions, or upstream availability are missing.
- Workspace, AI, and workflow callers see the **same permitted action list**.
- Failed actions leave a trace and a user-safe fallback message.

*Limitations*

- The live schema exposes action-loading functions but no single dedicated action-definition / action-log table — verify per implementation.
- Do not describe refunds, loyalty awards, vouchers, or marketplace changes as available unless the specific integration action is configured.

---

### CSAT & Customer Feedback

**Overview**

CSAT & Customer Feedback is the satisfaction loop after or around service interactions. It collects explicit customer feedback, derives themes from comments, and feeds negative or low-confidence signals back into QA, ticketing, AI tuning, and analytics. A *survey trigger* decides when to ask; a *response model* defines emoji / star / NPS / free-text capture; *predicted CSAT* is an inferred signal when configured; *feedback extraction* turns comments into themes; *suppression* prevents survey fatigue. Example: after a return conversation is resolved, the platform sends a one-tap survey on the same channel, stores the rating and comment signal, tags the conversation, and creates a QA follow-up if the score is poor.

**Purpose**

To close the loop between support quality and operational action — every resolved case can produce a measurable satisfaction signal, not just a closed conversation. Negative feedback creates a review path; predicted-CSAT augments coverage without replacing actual responses.

**User Journey**

*Admin journey*

1. Configure when surveys send, which channels can receive them, and which customers / segments are suppressed.
2. Choose the response model (emoji / star / NPS / free-text) and write localized survey copy.
3. Set thresholds for negative feedback and the QA ticket / review creation behavior.
4. Monitor response rates, score distribution, themes, and low-score cases.
5. Drill into a low-score conversation to review messages, agent actions, AI behavior, and related ticket history.

*Member journey*

1. The conversation reaches a configured resolved or follow-up state.
2. The customer receives a short in-channel prompt.
3. The customer submits a tap, rating, NPS score, and/or free-text comment.
4. The platform thanks the customer and avoids repeat surveys during cooldown.

*Edge cases*

- Suppressed customers receive **no survey** even if a trigger fires.
- Survey links / prompts should expire safely.
- Low-response channels need clear empty / low-confidence states.

**Configurations & Rules**

*Configuration surfaces*

| Surface | What's configured |
|---|---|
| **Survey trigger** | When to send (resolved, follow-up, scheduled) |
| **Channel** | Which channels can receive the survey |
| **Response model** | Emoji, star, NPS, free-text, or combination |
| **Cooldown / suppression** | Per-customer cooldown, do-not-contact lists, segment suppression |
| **Negative-feedback threshold** | Below which a QA follow-up is created |

*Operating rules*

- **At most one survey per conversation within the configured cooldown window.**
- **Prefer the same channel as the conversation** so the customer retains context.
- **Do-not-contact and suppression lists override survey triggers.**
- **Negative feedback creates a review path** — never silently disappears into reporting.
- **Predicted CSAT and actual response KPIs are kept separate** unless explicitly configured otherwise.

*Limitations*

- Dedicated CSAT storage tables are not always verified in the live schema for this batch — check the implementation before promising specific persistence.
- Predicted CSAT should not replace actual response KPIs without clear labeling and confidence.

---

### Analytics & Logs

**Overview**

Analytics & Logs is the observability layer for Customer Service. It turns conversation events, ticket transitions, workflow runs, channel stats, knowledge usage, and operational counts into dashboards and drill-down timelines. An *event* is a durable record of something that happened; *analytics* are aggregated views over those events; *logs* are the event-level traces used for audit and debugging; *replay* reconstructs what happened in sequence. Example: a support lead sees first-response time rise on LINE, filters the dashboard by channel, opens a slow conversation, and reviews the event trail from inbound message → assignment → reply → ticket creation → resolution.

**Purpose**

To answer both *"how is support performing?"* and *"why did this case behave that way?"* without separate reporting systems per channel. Supports human operations, workflow tuning, AI oversight, and QA from one event spine.

**User Journey**

*Admin journey (manager)*

1. Open analytics and choose a time range.
2. Review high-level counts — conversations, channels, contacts, tickets, knowledge usage, workflow activity.
3. Filter by channel, team, agent, priority, status, ticket type, or search.
4. Drill from a chart or table into a conversation, ticket, source, or workflow run.
5. Use the log timeline to identify event sequence and responsible actor.

*QA journey*

1. Open a conversation or ticket with a reported issue.
2. Review messages, status changes, ticket events, and workflow logs in chronological order.
3. Record the likely root cause and route the fix to the owning feature.

*Edge cases*

- Empty states must explain whether there is no data, no permission, or filters are too narrow.
- Time-zone handling must be explicit for daily / hourly operational reports.

**Configurations & Rules**

*Operating rules*

- **Use event records as the audit trail** rather than reconstructing history from current status alone.
- **Keep raw log detail available for QA / debugging** while exposing aggregated metrics for managers.
- **Treat AI, human, rule, and system actors as comparable dimensions** — not separate reporting worlds.
- Dashboards support filtering by channel, time range, agent, team, status, priority, ticket type, and workflow where the data exists.
- Log views preserve actor type, event type, event data, and timestamp.
- KPI definitions distinguish conversation, ticket, workflow, and knowledge metrics.

*Limitations*

- A metric cannot be promised unless the source event or table exists and is populated.
- Aggregated dashboards are only as accurate as event-emission coverage.

---

#### Analytics

**Overview**

Analytics is the aggregated, dashboard-style view of CS performance — KPIs, trends, cohort comparisons, alerting on threshold breaches. Built on materialized views and pre-aggregated rollups for sub-second dashboard loads on millions of conversations. Example: the head of CS opens the morning dashboard. Top tile: *"Yesterday vs. 7-day average"* — conversations +12%, FRT -8%, CSAT 4.6 (steady), AI containment 64% (+3%). Tile flagged: AOP *"Returns"* CSAT dropped to 4.1 — click through to see the underlying conversations and the suspected cause (a wording change shipped Monday). Anomaly alerts had already fired at 6am via Slack.

**Purpose**

To make support performance and AI behavior measurable, comparable, and alertable at a glance — operational metrics, AI performance (resolution rate, hallucination rate, unresolved questions), customer insights, QA scorecards, cost per resolution. Drill from any metric to source conversations.

**User Journey**

*Admin journey*

1. Open the morning dashboard; review the *"yesterday vs. 7-day average"* tiles for conversations, FRT, CSAT, AI containment.
2. Inspect anomaly-flagged tiles (e.g., AOP CSAT drop).
3. Click through to the underlying conversation list to investigate.
4. Build a cohort filter (e.g., *VIP × Shopee × last 30 days*) for trend analysis.
5. Acknowledge / route the anomaly alert; alerts also fire via Slack on threshold breach.

*Edge cases*

- Customers always see freshness timestamps on the dashboard.
- Predicted-CSAT and actual-CSAT are reported as **distinct series** — never blended without explicit operator action.

**Configurations & Rules**

*Rollup cadence*

| Tier | Refresh |
|---|---|
| **Hot dashboards** | Every 5 minutes |
| **Long-tail dashboards** | Every hour |
| **Cohort analytics** | Nightly batch |

*Operating rules*

- **Operational and AI KPIs are pre-defined** — custom metrics are SQL-via-MCP for power users; the dashboard surface stays opinionated to avoid metric proliferation.
- **Per-merchant data isolation enforced via RLS** — aggregations never cross merchant boundaries; views filter by `merchant_id` from JWT.
- **Anomaly detection is rule-based + statistical** — static thresholds (e.g., CSAT < 4.0) plus rolling-window comparisons (today > 2σ from 14-day average). LLM-driven anomaly detection is intentionally avoided to keep the alert layer cheap and deterministic.
- **Cohort filters compose via AND** — *VIP × Shopee × last 30 days* is `tags contains vip` AND `channel=shopee` AND `created_at > now() - 30 days`.

---

#### Logs

**Overview**

Logs is the per-conversation, event-by-event view — every message, every workflow node, every LLM call, every tool invocation, every agent action, in order. Used for QA review, debugging, AI replay, and compliance audit. Example: a reviewer opens conversation #12345. The log view shows: 10:02:03 inbound message (LINE) → 10:02:03 identity resolved to customer #884 → 10:02:04 chatbot flow *"LINE Greeting"* matched, sent button menu → 10:02:31 customer tapped *"Track Order"* → 10:02:31 handed to AI, AOP=*"Order Status"* → 10:02:32 LLM call (gpt-4o, 1432 tokens, $0.0021) → 10:02:32 tool call `lookup_order(A-12345)` → returned `status="shipped"` → 10:02:34 AI sent reply with citation → 10:02:34 conversation auto-resolved.

**Purpose**

To make every customer interaction fully reconstructable — for audit, AI replay (validate prompt / AOP changes before rollout), debugging, and compliance. Same event spine feeds Analytics rollups.

**User Journey**

*QA / admin journey*

1. Open a conversation log; see every event in order with actor (human / AI / rule / system), timestamp, payload.
2. Replay an AI turn — same prompt, same retrieved knowledge chunks, same tools available — to validate prompt or AOP changes.
3. Search across logs by conversation, customer, AOP, action, or time; vector-search over LLM responses for similar behaviors.
4. Follow a `trace_id` across features (chat → ticket → callback) to reconstruct the end-to-end timeline.

*Edge cases*

- Sensitive fields (national ID, full card number) are **masked at view time** by default; un-redacted access is permission-gated and itself logged.
- Corrections are emitted as new events (`correction_applied`) referencing the original — never overwrite.

**Configurations & Rules**

*Retention policy*

| Event type | Default retention |
|---|---|
| **Conversation events** | Per-merchant policy (default 24 months) |
| **LLM call payloads** | 90 days (cost) |
| **Action call audit** | 7 years (compliance) |

Configurable per merchant for regulated industries.

*Operating rules*

- **Logs are immutable** — events are append-only; corrections are new events referencing the original. Required for audit and AI replay.
- **PII redaction at view time** — masked by default; un-redacted access permission-gated AND itself logged.
- **Replay reproduces the AI's view exactly** — same prompt, retrieved knowledge chunks, and available tools.
- **Logs are searchable** by conversation, customer, AOP, action, time; vector search over LLM responses for similar behaviors.
- **Cross-event correlation via trace IDs** — a single customer interaction (chat → ticket → callback) shares a trace ID for end-to-end timeline reconstruction across features.

---

## Campaigns

<!-- catalog_module: loyalty | group: loyalty.campaign -->

Campaign mechanics are part of **Loyalty**, not a separate public module. They are short-burst engagement activities that turn member attention into wallet spend, repeat visits, social acquisition, and habit formation. Each mechanic has its own configuration surface, but all plug into Currency, Rewards, Missions progress, and Marketing Automation for triggered communication.

The five core campaign mechanics are: **Spin Wheel**, **Mass Lucky Draw**, **Missions**, **Referral**, and **Check-in**.

---

### Spin Wheel

**Overview**

Spin Wheel is a currency-based luck mechanic. The member spends points or tickets for one spin and the outcome is randomized across a set of configurable prize tiers. Because the prize is any platform reward type — reward voucher, points credit, ticket credit, tier credit, or tag/persona assignment — Spin Wheel doubles as a marketing distribution channel for the rest of the loyalty catalog, not just a freestanding mini-game.

**Purpose**

To convert idle wallet balances into engagement moments and to surface high-value rewards as a randomized hook. Spending points/tickets per spin gives the merchant a controllable burn lever; randomized outcomes let a single campaign cover a wide payout distribution (many small prizes, a few large ones) without the operational overhead of running separate giveaways.

**User Journey**

*Admin journey*

1. Define spin cost (points and/or ticket type/amount) and total spins allowed per member (daily, campaign, or lifetime).
2. Configure prize tiers: name, probability weight, outcome type (`points`, `tickets`, `reward`, `tier_credit`, `tag_assign`, `persona_assign`), and outcome entity / amount.
3. Set the campaign window (start/end), eligibility filters (tier, persona, tag), and active status.
4. Save and verify the wheel preview matches the configured probabilities.

*Member journey*

1. Member opens the spin wheel page or widget from the homepage block.
2. App shows current wallet balance, the spin cost, remaining spins, and the wheel graphic.
3. Member taps Spin → cost is deducted from the wallet → server selects an outcome by weighted random → wheel animates to the result.
4. Outcome is applied: points/tickets credited, reward issued, tier credit added, tag/persona assigned.
5. Result + remaining spins update; member can spin again until the spin limit is hit.

*Edge cases*

- Insufficient wallet balance → spin button disabled with "Not enough points/tickets" message.
- Spin limit reached → button disabled with next-reset timing.
- Outside the campaign window or campaign inactive → wheel is hidden or shows "Coming soon" / "Ended".
- Reward outcome with depleted stock → fallback behavior must be defined per merchant (skip, substitute with points, or block the spin).

**Configurations & Rules**

| Setting | Purpose |
|---|---|
| **Spin cost** | Points and/or ticket-type amount deducted per spin |
| **Spin limits** | Per day / per campaign / lifetime caps |
| **Prize tiers** | List of weighted outcomes (probability + reward type + amount) |
| **Outcome types** | `points`, `tickets`, `reward`, `tier_credit`, `tag_assign`, `persona_assign` |
| **Eligibility** | Tier, persona, tag, user-type filters |
| **Campaign window** | Start/end dates, optional time-of-day window |
| **Active status** | Master on/off switch |

*Operating rules*

- **Probability is server-enforced** — the wheel animation is cosmetic; the outcome is decided by the backend so prize distribution can't be gamed.
- **Cost is deducted before outcome resolution** — failed/cancelled spins must refund to keep wallet integrity.
- **Outcomes flow through the same ledgers as the rest of the platform** — `wallet_ledger` for points/tickets, `reward_redemptions_ledger` for free rewards. No separate accounting.
- **Probabilities sum to 100%** — admin UI should enforce this; misconfigured weights are a common pitfall.

---

### Mass Lucky Draw

**Overview**

Mass Lucky Draw is a currency-based entry mechanic for offline-conducted prize draws. Members spend points or tickets to enter; the brand exports the participant list, runs the draw outside the platform (live event, manual selection, or third-party RNG), and announces winners separately. It is distinct from Spin Wheel in that the prize is awarded **offline by the brand**, not by the platform — the platform's job ends at collecting and exporting entries.

**Purpose**

To support high-value or compliance-sensitive prize draws where the brand wants editorial control over the draw process (e.g., notarized draws, live-streamed announcements, prizes that need physical handover or media moments). Also fits brands that run prize draws as a marketing event independent of the loyalty app.

**User Journey**

*Admin journey*

1. Create a Mass Lucky Draw campaign: name, description, image, entry cost (points or tickets), entry limits (per member, per day, per campaign), and campaign window.
2. Set eligibility filters (tier, persona, tag, user type).
3. Activate the campaign.
4. During the campaign, view live entry counts and the participant list (member ID, entry count, timestamps).
5. After the campaign closes, export the participant list (CSV) and conduct the draw outside the platform.
6. Announce winners through brand channels (push, email, in-app banner, event); optionally credit prizes manually through reward issuance or wallet adjustment.

*Member journey*

1. Member opens the lucky draw page and sees the campaign image, prize description, entry cost, their current entry count, and remaining entries.
2. Member taps Enter → cost is deducted from the wallet → entry recorded → entry counter updates.
3. Member can enter again up to the configured limit; more entries = more chances in the offline draw.
4. After the draw, the member receives an announcement (in-app, push, email) about whether they won.

*Edge cases*

- Insufficient balance → entry button disabled.
- Per-member limit reached → button disabled with the limit shown.
- Outside campaign window → page hidden or marked as closed; the participant export is available to admins post-close.
- Cancellation refund policy must be defined: if the merchant cancels the draw, entries should refund automatically; if the draw runs as planned, no refund.

**Configurations & Rules**

| Setting | Purpose |
|---|---|
| **Entry cost** | Points and/or ticket-type amount deducted per entry |
| **Entry limits** | Per member / per day / per campaign caps |
| **Eligibility** | Tier, persona, tag, user-type filters |
| **Campaign window** | Start/end dates; participant list exports after end |
| **Prize description** | Free-form for the brand to communicate what's being drawn |
| **Active status** | Master on/off |

*Operating rules*

- **Each entry is a wallet debit** — recorded as a ledger event so balance audits stay consistent.
- **Winner selection is offline** — the platform does not pick winners. Prize delivery is at the brand's discretion (manual reward issuance, manual wallet credit, or off-platform handover).
- **More entries = more chances** — the offline draw is expected to weight by entry count.
- **Export contains member ID + entry count + timestamps** — enough to run a weighted random selection externally without re-querying the platform.

---

### Missions

**Overview**

Missions are goal-based challenges that turn member actions into visible progress and completion rewards. Merchants define quests such as purchases, points earned, tickets earned, form submission, referral signup, or referral purchase, and reward members when the configured targets are met. Two patterns exist: **standard missions** track one or more conditions in parallel and complete only when all conditions reach target (e.g., "spend 5,000 THB AND earn 500 points"); **milestone missions** define sequential levels (Bronze → Silver → Gold) where progress waterfalls from the first incomplete level into the next so overflow is never wasted.

**Purpose**

To give merchants a flexible goal-and-reward framework — gamification, behavioral nudges, and progressive engagement — that plugs into every value-generating event in the platform (purchases, wallet earn, forms, referrals) without needing custom code. Missions are the primary mechanic for stretch goals ("hit 10K spend this quarter to unlock a tier badge") and seasonal pushes.

**User Journey**

*Admin journey*

1. Open Mission List and click "Create mission" to open Mission Settings in create mode.
2. Fill basic information: name, code, type (standard or milestone), description, start/end dates, active status, images.
3. Choose activation type (`auto` vs `manual` — i.e., always tracked vs requires member to join) and claim type (`auto` vs `manual` — reward distributed on completion or requires a claim tap). Configure reset frequency and reset mode when valid for the mission type.
4. Add conditions: condition type, measurement type, target value, filters, operator, amount range, form ID, earn source type, ticket type ID, tier filters as needed.
5. For milestone missions, define levels in sequence with names, badge images, display order, one condition per level, and level-linked outcomes.
6. Add outcomes (points, tickets, reward, tier credit, tag), progress limits, and claim limits.
7. Save through `bff_upsert_mission`. Edit by reopening from Mission List; delete cascades to conditions, outcomes, progress limits, claim limits.

*Member journey*

1. Member opens the mission list (homepage block or dedicated page); each card shows image, name, type badge, progress indicator, and a CTA driven by `button_action`.
2. Member opens a mission detail. Standard missions show parallel progress bars per condition; milestone missions show ordered levels, completed levels, current level, badges, and level progress.
3. If `button_action = join_mission`, member taps Join — progress starts only after `accepted_at`.
4. Qualifying purchases, wallet earn events, form submissions, and referrals update progress automatically through event processing.
5. If `button_action = claim_outcome`, member taps Claim; milestone missions can claim per level.
6. After all claims are complete, the CTA flips to `claimed` and is disabled.

*Edge cases*

- A milestone mission with reset frequency is invalid.
- AND product filters can make a condition impossible if the required products never appear in a single qualifying event.
- Manual activation requires the member app to expose a join action; without it the mission can never start.
- A mission with no configured outcomes still completes — it just grants no reward.

**Configurations & Rules**

*Basic configuration*

| Setting | Purpose |
|---|---|
| **Name / code / description / images** | Display + lookup |
| **Mission type** | `standard` (parallel AND) or `milestone` (sequential levels) |
| **Start / end dates** | Campaign window |
| **Active status** | On/off |
| **`progress_activation_type`** | `auto` (track everyone immediately) or `manual` (requires join) |
| **`claim_type`** | `auto` (distribute on completion) or `manual` (requires claim tap) |
| **Reset frequency / mode** | Repeatability cadence (daily, weekly, monthly, etc.) |
| **Progress loops / max loops per transaction** | Whether the same event can advance the mission multiple times |
| **Progress exclusivity group** | Prevent one event from progressing multiple grouped missions |
| **Claim exclusivity group** | Prevent one claim from satisfying multiple grouped missions |
| **Milestone skip behavior** | How overflow applies to next level |

*Conditions*

| Setting | Purpose |
|---|---|
| **Condition type** | Event source: purchase, wallet earn, form, referral signup, referral purchase |
| **Measurement type** | What's counted: amount, count, value |
| **Target value** | Threshold for completion |
| **Filters** | Product, tier, persona, store, etc. |
| **Operator** | AND / OR within a filter set |
| **Eligible tiers / user types** | Who can progress |

*Milestone levels*

| Setting | Purpose |
|---|---|
| **Level name / badge / display order** | Visual progression |
| **Per-level condition** | One condition per level (waterfalls when complete) |
| **Per-level outcome** | Reward granted on that level's completion |

*Outcomes & limits*

- Outcomes can grant `points`, `tickets`, `reward`, `tier_credit`, or `tag_assign`.
- Progress limits cap total runs (e.g., complete this mission a maximum of 5 times).
- Claim limits cap total claims independently of progress.

*Operating rules*

- **Standard missions use AND logic** — every condition must reach target.
- **Milestone missions progress sequentially with waterfall overflow** — a 400 purchase on a 300/500 level 1 completes it and applies 200 to level 2.
- **`auto` activation** tracks all members immediately. **`manual` activation** requires accept; events before `accepted_at` don't count.
- **`button_action` priority**: `claim_outcome` > `join_mission` > `claimed` > `view_progress` > `view_details`.
- **Empty filter arrays = unrestricted**. AND operators require all filter criteria to match in a single event.

*Limitations*

- Milestone missions cannot use reset frequency.
- A mission with no outcomes can complete without granting a reward.
- If `allow_progress_loop = false`, a reset frequency alone does not make the mission repeatable.
- Exclusivity groups intentionally block single events / claims from satisfying multiple grouped missions.

---

### Referral

**Overview**

Referral is a member-led acquisition loop. An existing member shares a permanent invite code; a new member signs up with that code, creating a tracked inviter-invitee relationship. The system rewards **invitees** directly (points, tickets, or a free reward at signup or first purchase) and rewards **inviters** indirectly through Missions configured with `referral_signup` or `referral_purchase` conditions. Acquisition incentives therefore reuse the existing wallet, reward, and mission infrastructure rather than running on a separate referral-only payment rail.

**Purpose**

To turn the existing member base into an acquisition channel without per-acquisition cash incentives. Brands can tune the cost/conversion tradeoff by choosing when the relationship "activates": at signup (cheaper for the brand, faster gratification, more noise) or at first purchase (filters out non-buyers, higher acquisition cost only for real customers). Invitee outcomes are direct (immediate value to new member); inviter rewards run through missions so the brand can stack milestones ("refer 5 buyers → unlock a special reward").

**User Journey**

*Admin journey*

1. Open Referral Settings and toggle `referral_active` on.
2. Select activation trigger: `signup` or `first_purchase`.
3. Configure inviter limits per user type (buyer, seller) with optional period caps (daily, weekly, monthly, yearly, lifetime).
4. Configure invitee outcomes: add `points`, `tickets`, or `reward` rows with amount, entity ID where required, and validity period when used.
5. Configure inviter rewards by going to Mission Settings and adding missions with `referral_signup` or `referral_purchase` conditions with target counts and mission outcomes.
6. Use Referral Ledger to view inviter, invitee, invite code, signup date, and first purchase date.

*Member journey*

1. Existing member opens the referral / invite page; the app fetches the permanent 8-character invite code (generated on first request, reused indefinitely).
2. Member shares the code or a deep link through the OS share sheet.
3. New user enters the code during signup or has it prefilled from a deep link.
4. On registration completion, the system validates the code, checks duplicate-referral state, checks inviter limits, and creates the `referral_ledger` record.
5. If activation trigger is `signup`, invitee outcomes distribute immediately and inviter mission evaluation queues. If `first_purchase`, rewards wait until the invitee completes their first purchase.
6. On the invitee's first purchase, `first_purchase_at` is set, invitee outcomes distribute (if deferred), and inviter mission evaluation queues.

*Edge cases*

- Admin frontend for Referral is not yet built; settings are configured via API/seed for now.
- Member referral screens are not yet built; the journey describes backend-supported behavior.
- Disabled referral program → invite code generation and signup with code both return errors.
- Invalid invite code → "code not found" error.
- Inviter limit exceeded → signup processing is blocked for that referral.
- Invitee already referred → rejected even if a second valid code is provided.
- Inviter has no missions configured → invitee still gets their direct outcome but inviter gets nothing.

**Configurations & Rules**

| Setting | Location | Purpose |
|---|---|---|
| **`referral_active`** | `merchant_master` | Master on/off |
| **`referral_activation_trigger`** | `merchant_master` | `signup` or `first_purchase` |
| **`referral_inviter_limits`** | Per user type | Daily / weekly / monthly / yearly / lifetime caps + priority |
| **`referral_invitee_outcomes`** | Outcome rows | `points`, `tickets`, or `reward` + amount + entity ID + validity |
| **Inviter rewards** | Mission Settings | `referral_signup` or `referral_purchase` condition types |

*Operating rules*

- **Invite codes are permanent and lazily generated** — one code per user per merchant; the same code is returned on every request.
- **One referral per invitee per merchant** — an invitee can only ever be referred by one inviter at one merchant.
- **Limits are checked at signup, not at share time** — sharing a code is free; only successful relationships count against limits.
- **Activation trigger applies to both sides** — `signup` distributes invitee rewards and queues inviter mission progress at registration; `first_purchase` defers both.
- **Outcomes flow through standard ledgers** — invitee points/tickets via `wallet_ledger` with `source_type = 'referral'`; reward outcomes via `reward_redemptions_ledger` with the same source type.

*Limitations*

- Inviters have no direct referral-specific reward path; they must have missions configured to earn anything.
- If referral is active but no invitee outcomes are configured, the relationship is still tracked but the invitee gets nothing.
- Invalid invitee reward entity IDs can fail the affected distribution silently.

---

### Check-in

**Overview**

Check-in is a habit loop that rewards members for returning on a daily or weekly cadence, turning an app open into streak progress and a concrete reward moment. A merchant configures a check-in campaign with a frequency, optional date and time windows, and condition rows that map a member's current streak day to an outcome. Outcomes can be `points`, `tickets`, a free reward, or a 7-day earn-factor multiplier.

**Purpose**

To drive daily/weekly active-user metrics and to give the brand a low-friction way to reward "showing up." Streaks create loss-aversion ("I'm on day 6, I'd hate to break it now"); milestone days (e.g., day 7) create anticipation for a larger payout. Stackable with other mechanics: the earn-factor outcome makes the next 7 days of purchases earn at a higher rate, which doubles as a soft cross-sell to purchase features.

**User Journey**

*Admin journey*

1. From Check-in List, select "Add check-in" to open Check-in Settings in create mode.
2. Fill campaign basics: name, description, `frequency_type` (`daily` or `weekly`), timezone, optional time-of-day window, optional campaign date window, `max_streak_days`, `require_condition_match`.
3. Save the campaign, then configure reward conditions from the campaign edit view.
4. Add one condition row per streak bracket: start/end streak day, milestone flag, eligibility by tier or user type, outcome entity (`points`, `tickets`, `reward`, `earn_factor`), entity ID where required, amount, priority, active status.
5. Repeat for base days and milestone days. Example: days 1–6 award 5 points; day 7 is marked as milestone and awards 50 points + a free reward.
6. Save and verify each condition is active.

*Member journey*

1. Member opens the check-in page or widget.
2. Frontend calls `get_user_checkin_status`; the response drives the button state: `checked_today` → disabled "Already checked in", `in_window = false` → disabled "Outside check-in hours", `can_checkin = true` → enabled.
3. Member taps Check In → `process_checkin` runs → response includes streak day, total check-ins, longest streak, reward details, transaction ID, and next-check-in timing.
4. UI updates streak progress and shows the reward confirmation (points credited, ticket earned, free reward claimed, or "no reward" when no condition matched and that is allowed).

*Edge cases*

- Member-facing routes for check-in are not yet fully documented in the loyalty-user repo; the journey describes backend-supported behavior.
- Daily campaigns reset the streak after a missed calendar day.
- Weekly campaigns reset when the gap exceeds 7 days.
- `require_condition_match = true` turns a no-condition-match into "No rewards available for your profile" AND blocks streak progress.
- `next_deadline` tells the member when they must check in again to preserve the streak.

**Configurations & Rules**

*Campaign settings*

| Setting | Purpose |
|---|---|
| **Name / description** | Display |
| **`frequency_type`** | `daily` or `weekly` |
| **Timezone** | Determines streak day boundaries |
| **Time-of-day window** | Optional; supports day-crossing windows (e.g., 22:00–02:00) |
| **Campaign date window** | Optional start/end dates |
| **`max_streak_days`** | Cap on streak counter (continues check-ins after but streak stops incrementing) |
| **`require_condition_match`** | If true, check-in is rejected entirely when no condition matches |
| **Active status** | On/off |

*Condition settings*

| Setting | Purpose |
|---|---|
| **Streak day range** | Start/end day of streak this condition applies to |
| **`is_milestone`** | Flag for milestone days (UI / analytics) |
| **Allowed tier IDs** | NULL = all tiers |
| **Allowed user types** | Empty = unrestricted |
| **Outcome entity** | `points`, `tickets`, `reward`, `earn_factor` |
| **Entity ID** | Reward ID or ticket type ID where required |
| **Amount** | Points / tickets count / multiplier |
| **Priority** | Tie-breaker when multiple conditions match |
| **Active status** | On/off |

*Operating rules*

- **One member can check in once per campaign per calendar day.**
- **Daily streaks** continue only when the last check-in was exactly yesterday; **weekly streaks** continue when the prior check-in was within the past 7 days.
- **Condition matching** must satisfy streak day range PLUS tier and user-type filters. If multiple conditions match, highest priority wins, then highest outcome amount.
- **Time windows** use the campaign timezone and support day-crossing.
- **Outcomes flow through standard ledgers**: `points`/`tickets` credit the wallet; `reward` triggers a free redemption through `redeem_reward_with_points`; `earn_factor` assigns a 7-day multiplier and extends the expiry when the same factor already exists.

*Limitations*

- With `require_condition_match = true`, a missing condition rejects the entire check-in — no ledger entry, no streak update.
- A reward outcome with an invalid or unavailable reward can fail while the check-in and streak still advance.
- Streaks reset automatically when the required frequency window is missed; no manual reset/override is defined.

---

## Platform

<!-- catalog_module: loyalty | foundation & acquisition (folded from App foundation; feature keys preserved) -->

Former App foundation / Platform capabilities now sit inside **Loyalty** for catalog identity: signup and login, profile completion, website signup, privacy consent, admin permissions, languages, and member-app layout. Narrative anchors below are preserved for proposals; treat them as Loyalty foundation, not a fourth public module.

---

### Authentication & Signup

**Overview**

Authentication & Signup is the member identity and onboarding flow. Members authenticate with merchant-configured LINE OAuth, phone OTP, or both; admins use standard Supabase Auth. The central state of the flow is `next_step`, returned by the `bff-auth-complete` edge function, which tells the frontend whether to verify LINE, verify phone, complete a profile, or continue to the homepage. A merchant turns on the identity methods it needs by setting `merchant_master.auth_methods` to `["line"]`, `["tel"]`, or `["line","tel"]`.

**Purpose**

To support the dominant SEA identity model (LINE in Thailand, Japan, Taiwan; phone OTP everywhere) and let merchants choose the minimum-friction onboarding that still gives them clean identity. The single `bff-auth-complete` entry point removes the combinatorial complexity of multiple auth methods × multiple device states × multiple profile-completeness states — the frontend just calls one endpoint and follows `next_step`.

**User Journey**

*Member journey*

1. Open the app → load auth config → frontend shows LINE button, phone field, or both based on `merchant_master.auth_methods`.
2. Authenticate the required identities (LINE OAuth handshake and/or phone OTP — 6 digits, 10-minute expiry, max 3 attempts per session).
3. Frontend calls `bff-auth-complete`, which resolves or creates the `user_accounts` row, links additional identities if needed, mints a custom JWT (Supabase Legacy JWT Secret), and returns `next_step`.
4. Follow `next_step`: if profile completion is required, the profile drawer renders persona, default fields, custom fields, and PDPA sections through frontend `form_step` state.
5. Once `next_step = "continue"`, land on the homepage; access tokens last 24 hours and refresh tokens last 30 days.

*Admin journey*

1. Admins log in with Supabase Auth (email + password).
2. Configure member auth methods in merchant settings by editing `merchant_master.auth_methods`.
3. Configure required profile fields (default fields via `user_field_config`; custom fields via the Forms `USER_PROFILE` template).

*Edge cases*

- A returning member may be prompted to link a newly required method (e.g., merchant adds phone as required after the member already has LINE).
- A completed member may be prompted only for newly required profile fields (gap-fill, not re-fill).
- `Credentials belong to different accounts` (e.g., a phone number tied to one account and a LINE ID tied to another) requires support intervention.
- A missing profile template should surface retry behavior rather than a hard error.

**Configurations & Rules**

| Setting | Purpose |
|---|---|
| **`merchant_master.auth_methods`** | `["line"]`, `["tel"]`, or `["line","tel"]` |
| **Phone OTP** | 6 digits, 10-minute expiry, 3 attempts max per session |
| **Member access token** | 24 hours |
| **Member refresh token** | 30 days |
| **Admin auth** | Supabase Auth (separate from members) |

*Operating rules*

- **`bff-auth-complete` is the single entry point** for LINE-only, phone-only, combined, identity linking, bot auth, and profile completion checks.
- **`next_step` is authoritative** — the frontend follows it; it dictates whether to verify LINE, verify phone, complete profile, or continue.
- **Phone numbers are normalized to `+66XXXXXXXXX`** before lookup or insert (other country formats per merchant region).
- **Profile completion checks both `is_signup_form_complete` AND current required-field gaps** — schema changes that add a new required field automatically prompt existing users to fill it on next entry.
- **Custom JWTs must be signed with the Supabase Legacy JWT Secret** so they remain compatible with Supabase RPC / PostgREST.
- **Admin auth is fully separate** — admin JWTs are standard Supabase Auth JWTs without member custom claims.

*Limitations*

- LINE OAuth requires per-merchant LINE channel configuration (channel ID, secret, redirect URLs).
- Phone OTP delivery depends on the merchant's SMS provider configuration; failures should surface a retry path, not a silent error.

---

#### Custom Fields

**Overview**

Custom Fields are merchant-defined profile fields layered on top of the platform's default `user_accounts` / `user_address` fields. They surface in the signup completion flow and the profile-edit flow alongside default fields and persona selection. They are configured through the Forms feature's special `USER_PROFILE` template — which must be published to take effect — and are stored through `form_templates`, `form_fields`, `form_submissions`, and `form_responses`. Default fields (name, phone, email, address, birthday, etc.) live in `user_field_config`; custom fields complement them without overlap.

**Purpose**

To let each merchant collect the profile data it actually needs — industry-specific (e.g., car model for a service brand, skin type for cosmetics), program-specific (member ID from a legacy system), or campaign-specific (preferred store) — without forcing the platform schema to grow per merchant. The Forms substrate handles validation, conditional logic, and storage so custom fields behave identically to default fields from the member's perspective.

**User Journey**

*Admin journey*

1. Configure default profile fields in `user_field_config`: label, type, placeholder, validation, required flag, visibility, editability, options, ordering, persona filters.
2. Build the `USER_PROFILE` template under Forms: create field groups, fields, options, and conditional logic.
3. Publish `USER_PROFILE` so the custom fields appear in member profile flows.
4. Optionally configure persona-conditional custom fields so members on different personas see different fields.

*Member journey*

1. During signup completion or profile edit, the frontend calls `bff_get_user_profile_template` (new or edit mode) and renders `default_fields_config`, `custom_fields_config`, persona data, and PDPA sections from the response.
2. Member edits fields; frontend updates the local response object and debounces saves.
3. On save, `bff_save_user_profile` writes default fields, address fields, selected persona, custom field responses, and PDPA consent.

*Edge cases*

- Required custom fields added after a member has signed up trigger the gap-fill flow on their next entry.
- A custom field that is conditionally hidden based on persona is not validated when the condition is false.
- An unpublished `USER_PROFILE` template means custom fields do not appear at all — a frequent misconfiguration.

**Configurations & Rules**

| Layer | Stored in | Purpose |
|---|---|---|
| **Default fields** | `user_field_config` → `user_accounts` / `user_address` | Platform-standard profile fields (name, phone, email, address, birthday, etc.) |
| **Custom fields** | `form_templates`, `form_fields`, `form_field_options`, `form_conditions` → `form_responses` | Merchant-specific profile fields |
| **Persona selection** | `user_accounts.persona_id` | Member's chosen persona; can drive custom-field visibility |
| **PDPA consent** | Consent records | Captured alongside profile data |

*Operating rules*

- **The `USER_PROFILE` template must be published** to serve active custom profile fields.
- **Default fields are first-class platform schema**, not Forms-driven — Forms wraps custom fields only.
- **Persona-conditional fields** are evaluated at render and at save; hidden fields are not validated.
- **Custom field validation is template-defined** — type, required, regex, min/max, etc.

---

### Translation System

**Overview**

The Translation System provides multi-language support for both dynamic entity content (reward names, form field labels, persona names) and static UI text (page headers, button labels, error messages) across the merchant member app and the admin dashboard. Supported language codes are `en`, `th`, `ja`, and `zh`; each merchant sets its own default language. Dynamic entity translations live in a single `translations` table keyed by entity type + entity ID + field; member static UI lives in `ui_translations`; admin dashboard static UI lives in a separate `ui_translation_admin` table.

**Purpose**

To let a single platform deployment serve merchants across SEA and East Asia in the language their members actually use, without forking the codebase per locale. The fallback chain (requested language → merchant default → English → raw base value) means an under-translated merchant still renders text — never a blank label or a key-name like `reward.name.title`. Splitting member vs admin UI translation lets the brand team translate the member-facing surface without exposing the much-larger admin string set.

**User Journey**

*Member journey*

1. App load resolves language from `loyalty_language` cookie → Accept-Language header → default `th`.
2. App loads all UI translations through `get_ui_translations(p_page_key = null, p_language)` and stores text in context for page components.
3. Each dynamic content fetch (reward, form, persona) returns text in the resolved language via the fallback chain.

*Language switch journey*

1. Member opens Profile and taps Change Language.
2. Member picks one of the merchant's enabled languages and saves.
3. App sets a one-year `loyalty_language` cookie.
4. App refreshes so both server-rendered and client-context text use the new language.

*Admin journey*

1. **Translation Manager** offers entity navigation, entity list, and a per-language translation grid for dynamic content.
2. **Global Settings** manages merchant language enablement and default.
3. Optional **AI Translate** assist fills missing cells while preserving existing translations.

*Edge cases*

- Missing translations fall back through the chain — the UI never blanks.
- Admin dashboard uses a separate table and API; updating member UI translations does not affect admin.
- Caches can briefly serve stale content until invalidation or TTL refresh.

**Configurations & Rules**

| Surface | Storage | Notes |
|---|---|---|
| **Dynamic content** | `translations` table (entity type + entity ID + field) | Used for reward names, form labels, persona names, etc. |
| **Member static UI** | `ui_translations` | Loaded once on app open via `get_ui_translations` |
| **Admin static UI** | `ui_translation_admin` | Separate from member UI |
| **Enabled languages** | `merchant_languages` | Per merchant; exactly one default |

*Operating rules*

- **Master table content is labeled with the merchant default language**, not hardcoded English — a Thai-first merchant stores Thai in `reward_master.name` and English in `translations`.
- **Fallback order**: requested language → merchant default → English → raw base value.
- **Member UI translations for login/signup are public** because unauthenticated pages still need text.
- **Caches are isolated** between dynamic content and static UI; invalidation paths differ.

*Limitations*

- Member and admin UI translations are separate systems and APIs.
- Static UI strings should not contain dynamic runtime variables (use templating in the rendering layer, not the translation table).
- Cache can briefly serve stale content until invalidation or TTL refresh.

---

## Admin Portal & Reports

<!-- feature_key: loyalty.analytics.reports (reports); loyalty foundation / admin ops (portal) -->

Meta summary for proposal writing: the **Admin Portal** (where the brand configures the program) and **Reports** (30+ reports the brand sees back). Use this when a customer asks what the team can configure or what reporting they get.

---

### Admin Portal — Configuration Surfaces

**Overview**

The Admin Portal is a single web dashboard, gated by Supabase Auth + a per-merchant role/permission model (`admin_roles`, `admin_role_permissions`, `admin_users`, `admin_menu_config`). The sidebar and dashboard shape are decided at login by `bff_get_admin_profile` and `bff_get_admin_menu` — a `frontline_sales` role can hide the sidebar and redirect to `/choose-events`, a `loyalty_operator` sees the loyalty configuration menus, a `cs_operator` sees the conversation workspaces, and a `super_admin` sees everything. Role-based UI shaping is intentional: most brand users only need a slice, and hiding the rest reduces error and onboarding cost.

**What the brand can configure (by domain)**

*Loyalty configuration*

| Surface | Configures |
|---|---|
| **Currency Settings** | Points expiry + award timing + **`default_burn_rate`** (points→discount); earn factor groups (rate / multiplier), purchase-status policy, public/private visibility, windows, product/tier/persona/store filters |
| **Rewards Catalog** | Reward content, images, visibility (`user` / `admin` / `campaign`), redeem windows, expiration mode, fulfillment method, eligibility filters, fallback points, promo-code behavior, stock settings, store-level stock allocations, marketplace storefronts, featured state, group membership |
| **Reward Groups** | Bundling for catalog organization and eligibility |
| **Promo Code Management** | Upload/generate, attach to rewards, single-use vs multi-use, validity windows |
| **Tiers Configuration** | Program clock per user type (metric, calendar year / rolling, upgrade timing); per-tier amounts, personas, optional burn override; display assets (icon, color, benefit lines, card design). Ladder order derived from amounts — no ranking / entry-tier flag |}
| **Missions** | Standard or milestone, conditions, outcomes, progress / claim limits, exclusivity groups, reset frequency/mode |
| **Referral Settings** | `referral_active`, activation trigger, inviter limits per user type, invitee outcomes |
| **Check-in Campaigns** | Frequency, time window, condition rows with streak ranges and outcomes |
| **Activity-Based Earning** | Activity definitions, dynamic fields, currency matrices, upload limits |
| **Stored Value Cards** | Card type, denominations, top-up rules, expiry policy |
| **Forms / Profile** | `USER_PROFILE` template (custom fields), surveys, survey rewards, default field config |
| **Tags & Personas** | Tag taxonomy, persona definitions, persona-driven UI rules |
| **Packages** | Bundle definitions for tiered offerings |
| **Persona Entitlements** | Per-persona feature access |
| **Store & Partner Classification** | Store hierarchy, partner classification, eligibility filters |
| **Purchase Transactions** | Status policy, event hooks, transaction limits |
| **Marketplace Connections** | Shopee / Lazada / TikTok / Shopify OAuth, claim-from status per platform |
| **Event Promo Engine** | Event-level promos, rules (condition JSON + outcome), freebie / discount outcomes |
| **Display Settings** | Block-based homepage and page composition (per-persona placements and overrides) |

*Marketing Automation (AMP)*

| Surface | Configures |
|---|---|
| **AMP Workflow Builder** | Visual node-based workflows, scheduled triggers, message templates, branch / wait / decision logic |
| **AMP AI Decisioning** | AI-driven segment selection, message variant testing, send-time optimization |

*Customer Service*

| Surface | Configures |
|---|---|
| **Connectivity** | Channel connectors (LINE / WhatsApp / Messenger / web chat / email / voice), phone number management, unified customer identity rules |
| **Agent Workspace** | Inbox layout, voice console, live assist, routing & assignment rules |
| **Ticket Management** | Ticket types, status workflows, SLAs |
| **Rules-Based Automation** | Chatbot flows (visual builder), IVR flows, rules & triggers (event → action) |
| **Brand AI Configuration** | Persona, tone, primary/secondary language, escalation rules, model selection |
| **Agent Operating Procedures (AOP)** | Per-intent procedures the AI follows |
| **Watchtower** | AI quality review, prompt iteration, AOP refinement |
| **Knowledge Base** | Source documents, chunking rules, citation policy |
| **Actions & Integrations** | Action catalog, channel/credential setup, approval rules, permitted callers |
| **CSAT & Feedback** | Survey channels, trigger rules, scoring schema |
| **Analytics & Logs** | Dashboard filters, KPI definitions (configurable per merchant) |

*Campaigns*

| Surface | Configures |
|---|---|
| **Spin Wheel** | Spin cost, spin limits, weighted prize tiers, eligibility, campaign window |
| **Mass Lucky Draw** | Entry cost, entry limits, eligibility, campaign window, participant export |
| **Missions** | (Same as Loyalty Missions — shared surface) |
| **Referral** | (Same as Loyalty Referral — shared surface) |
| **Check-in** | (Same as Loyalty Check-in — shared surface) |

*Platform*

| Surface | Configures |
|---|---|
| **Authentication** | `merchant_master.auth_methods` (LINE / phone / both), LINE channel credentials, SMS provider |
| **Custom Fields** | Via Forms `USER_PROFILE` template (see Forms section) |
| **Translation Manager** | Per-entity translations, AI Translate assist |
| **Global Language Settings** | Merchant enabled languages, default language |
| **Admin Roles & Permissions** | Roles, resource permissions, role UI behavior (`default_path`, `hide_sidebar`, `hidden_menu_categories`, `hidden_menu_items`, `floating_menu`) |
| **Admin Users** | Per-role user assignment |

**Operating rules**

- **Sidebar visibility is the intersection** of resource permissions and role UI exclusions — both must allow a menu entry for it to show.
- **Role config can redirect**: a role with `default_path` set forces the post-login redirect; a role with `hide_sidebar = true` runs in a chrome-less mode (typical for store associates on iPad).
- **All configuration is per-merchant** — there is no cross-merchant configuration leakage; admin auth tables enforce merchant scoping.
- **Most configuration is hot** — changes apply on next read; some surfaces (translations, display blocks) have a brief cache lag.

---

### Reports — What the Brand Sees Back

<!-- feature_key: loyalty.analytics.reports -->

**What it enables**

Brands get **30+ reports** across loyalty, marketing automation, and customer service so program, campaign, and service performance are visible without exporting raw ledgers.

**How it works**

Operators pick a time range, compare periods, and drill from KPI strips into the underlying activity. Loyalty reports cover member lifecycle and engagement; Marketing Automation covers workflow and AI outcomes; Customer Service covers volume, speed, CSAT, and AI containment.

**What differentiates it**

One admin surface spans earn/burn, campaigns, automation, and service — not a separate BI project per module.

**Key controls**

Date range, period-over-period comparison, and per-report filters (channel, campaign, segment, agent) where the report supports them.

**Overview (detail inventory)**

Reports span two distinct surfaces. **Loyalty reports** are member-lifecycle dashboards (wallet movement, tier distribution, mission uptake, reward redemption, campaign performance). **CS reports** are operational dashboards (conversation volume, FRT, CSAT, AI containment, agent productivity, knowledge usage). Both surfaces support time-range filtering and drill-down into source events / records.

**Reports by domain**

*Loyalty reports*

| Report | What it shows |
|---|---|
| **Member overview** | Active members, new signups, churn, retention by cohort |
| **Wallet movement** | Points and tickets earned, burned, expired, adjusted; by source (purchase, mission, referral, campaign, manual) |
| **Tier distribution** | Member count per tier, upgrade flow, maintenance success/failure, time-in-tier |
| **Mission uptake** | Per-mission: starts, completions, claim rate; per-milestone progress curves |
| **Reward redemption** | Per-reward: redemptions, stock burn-down, fulfillment SLA, popular vs dormant |
| **Referral funnel** | Codes generated, signups, first-purchase conversion, inviter mission completions |
| **Check-in adherence** | DAU/WAU from check-in, streak distribution, milestone-day reach rate |
| **Purchase transaction reports** | Transaction count, GMV, AOV, frequency, marketplace breakdown |
| **Activity-Based Earning reports** | Activity uploads per type, currency credited, member participation |
| **Campaign performance** | Per campaign (Spin Wheel / Mass Lucky Draw / Mission / Referral / Check-in): spend, engagement, payout, ROI |

*Marketing Automation reports*

| Report | What it shows |
|---|---|
| **Workflow performance** | Per workflow: triggers, message sends, opens, clicks, conversions, opt-outs |
| **AI decisioning outcomes** | Variant performance, send-time uplift, segment response curves |
| **Audience health** | Segment size, opt-out rate, deliverability across channels |

*Customer Service reports*

| Report | What it shows |
|---|---|
| **Conversation volume** | Conversations / messages by channel, hour, day, week |
| **First Response Time (FRT) & resolution time** | Median + percentiles; trend vs 7-day average |
| **CSAT** | Aggregate score, per-agent, per-AOP, per-channel; trend over time |
| **AI containment** | % of conversations resolved by AI alone, escalation reasons, handoff quality |
| **Agent productivity** | Per-agent: conversations handled, AHT, CSAT, knowledge usage |
| **Knowledge usage** | Top-cited articles, articles never cited, search-to-resolution rate |
| **Workflow activity** | Chatbot / IVR / rule run counts, success rates, error rates |
| **Ticket pipeline** | Tickets by status, priority, type, age; SLA breach risk |
| **Channel performance** | Per-channel: volume, response time, CSAT, AI containment |

*Operational logs (audit / replay surface)*

| Log type | What it shows |
|---|---|
| **Per-conversation event log** | Every message, workflow node, LLM call, tool call, action invocation, in order |
| **AI replay** | Re-run a past AI turn with the same prompt, retrieved chunks, and tools to validate prompt/AOP changes |
| **Wallet ledger** | Every point and ticket movement with source type, amount, balance, timestamp |
| **Reward redemption ledger** | Every reward issued with method, status, fulfillment trail |
| **Trace IDs across features** | Reconstruct a single customer interaction across chat → ticket → callback |

**Operating rules**

- **Rollups refresh on schedule, not on every event.** Hot dashboards refresh every 5 minutes, long-tail dashboards every hour, nightly batch for cohort analytics. Customers see freshness timestamps.
- **Operational and AI KPIs are pre-defined.** Custom metrics are available via SQL-via-MCP for power users; the dashboard surface stays opinionated to avoid metric proliferation.
- **Per-merchant data isolation is enforced** at the rollup and view layer — no cross-merchant leakage in any report.
- **All dashboards support drill-down** from chart / table into the underlying conversation, ticket, source event, workflow run, or ledger row.
- **Filters are consistent across CS reports**: channel, time range, agent, team, status, priority, ticket type, workflow (where the data exists).
- **Log retention defaults**: conversation events 24 months (per-merchant configurable), LLM call payloads 90 days (cost), action call audit 7 years (compliance).
- **PII redaction at view time** — masked by default; un-redacted access is permission-gated AND itself logged.

**Limitations**

- Loyalty reporting today leans on standard rollups over the ledger tables; bespoke reports (cohort retention curves with custom event definitions, multi-merchant comparisons for franchise brands) require SQL-via-MCP or a custom BI layer on top of the data warehouse.
- AI replay requires the LLM call payload to still be within the 90-day retention window.
- Cross-feature trace correlation requires all participating features to write the shared trace ID — older feature versions may not.

---
