# Reward

Redeemable catalog items members buy with points — the spend side of earn-and-burn. Merchants define eligibility, dynamic points pricing, stock, promo pools, fulfillment, and optional marketplace tags; members browse, redeem asynchronously, then use or track delivery. Admin and frontline surfaces also push or link-claim rewards without catalog browse.

Owner surfaces: loyalty-admin, loyalty-user, Shopify (storefront delta via `online_store[]`)

## Concept

Earn (members collect points) and burn (members spend them) are the two capabilities without which there is no loyalty program; tiers, campaigns, and automation make a program richer but are optional. Reward is the burn side. A **reward** is anything the brand gives a member — an e-voucher, a partner coupon, a product, a printed slip — defined once with display content, pricing, availability, and fulfillment. "Coupon" is only an example of what a reward can represent; the system noun is always *reward*.

**Three ways a member gets a reward** — (1) **Catalog redeem**: the member spends points in the catalog, or staff redeem on the member's behalf on Front Line — both are a points exchange. (2) **Campaign outcome**: referral, mission, spin, tier entry, and similar programs grant the reward as a result. (3) **Push**: automation or staff send it free (lifecycle workflow, Front Line push, claim link). Route 1 uses visibility `user_only`, `admin`, or `user`; routes 2–3 require visibility `campaign`.

**Redemption** — One record per claim in the member's **wallet** (the **My Rewards** tab). A record has two independent moments: **redeemed** (claimed, points deducted, benefit not yet consumed) and **used** (benefit consumed — the member taps Use at the counter, or staff/POS mark it used). Example: a member redeems a partner e-voucher at home (redeemed), then taps Use at the partner's store and shows the code (used).

**Slip code** — Every redemption shows a code on its slip, from one of three sources: a Rocket-generated redemption code (default), a **static promo code** the admin typed once (same for every member, e.g. `SAVE10`), or a unique code from the **promo code pool**.

**Two-layer pricing** — (1) **Eligibility**: binary filters on tier, user type, persona, tags, birth month — empty means unrestricted. (2) **Dynamic points**: how many points this member pays, from condition rows matched on the same dimensions plus specificity and priority.

**Dynamic points condition** — One row mapping tier / user type / persona / tags to a points cost and priority. The engine scores matches (tier heaviest, then user type, persona, tags), prefers higher specificity, then higher priority, then **lowest points** when still tied (customer-favorable).

**Require points match** — When on, a member must match at least one condition or redemption is blocked; fallback points are ignored. When off, unmatched members pay fallback points or zero if fallback is null.

**Visibility** — Who can start a catalog redemption and whether the reward appears in member browse: `user` (catalog + frontline), `user_only` (catalog only — staff cannot gift on frontline), `admin` (frontline only), `campaign` (push / mission / link / program outcome only — never in browse catalog).

**Campaign reward slot** — When referral, tier entry, or lifecycle workflow needs a **reward-type outcome**, admin opens **Reward settings** from that parent screen with a **slot** (`source` + `target`) in the URL (mirrored in `sessionStorage` for Shopify App Bridge). The saved catalog row must use visibility `campaign`; attach links the row to the parent without duplicating reward data. Detach removes the link only — it does not delete the catalog reward.

**Fulfillment method** — `digital` (a slip with a code, shown at the counter or used online), `shipping` (brand delivers a physical item; address snapshot on redeem), `pickup` (member collects a physical item in store), `printed` (Front Line prints a thermal slip at redeem, e.g. a lucky-draw entry the member drops in a box).

**Promo code pool** — Optional unique codes, one handed out per redemption in import order. Rocket only **distributes** the code; the party that generated it — a partner such as a coffee chain, or the brand's own e-commerce platform — owns its validity and discount conditions and validates it at use. Rewards without a pool (the brand's own products, samples, shipped merch) need no unique code. Formerly called "Alien Code".

**Partner** — Optional owner attached to each import batch. Codes must be unique only within one partner (two partners can legitimately issue the same string), and partner attribution lets the brand export claimed/used codes per partner for reconciliation. Batches without a partner share one "direct" namespace.

**Variant** — Member-chosen option dimensions on one reward (e.g. colour: pink / blue), each with a required flag. The choice is stored on the redemption for fulfillment; variants carry no separate price or stock.

**Stock control** (partial) — Toggle for finite inventory; redemption is blocked once redeemed quantity reaches the stock total. Reward settings has no field for the total yet, so the toggle alone does not cap anything. Unlimited when disabled.

**Transaction limits** — Per-reward caps on redemption count or quantity by scope (`user` / merchant / transaction) and time unit, with optional absolute windows.

**Multi-quantity redemption** — Quantity 1–1000 in one request. Without promo codes: one ledger row with quantity N. With promo codes: N rows with quantity 1 and distinct codes; **all-or-nothing** if the pool cannot satisfy N.

**Redemption window** — Optional start/end for claiming. Before start the reward is listed with its dates but cannot be redeemed; after end it leaves the catalog.

**Expiration (use)** — How long a redeemed reward stays usable: `absolute_date` (every redemption expires on the same day — matches a purchased coupon batch's own expiry) or rolling from the redeem moment in `relative_days` or `relative_mins` (short use-now windows).

**Ecommerce platform reward** — A reward whose benefit is a discount redeemed on an external store. The discount and its conditions (minimum spend, eligible products) live on that platform; Rocket hands out the code. For most platforms the brand generates unique codes there and imports them into the pool; Shopify is native — the reward binds to a Shopify discount and each redemption gets a freshly minted code (see Journeys › Shopify).

**Claim link** — Tokenized URL/QR for one-time or controlled claim; respects same points engine and shipping address rules as catalog redeem.

**Redemption quote** — Server-computed preview before confirm: max selectable quantity, limit/available copy, and `blocking_reason` when redeem is not allowed (member catalog stepper and Front Line redeem modal share `fn_reward_redemption_quote`).

**Member self-use** — Per-reward switch (default on). Off means only staff, a POS scanning the slip through the API, or a Shopify order can mark the redemption used — for brands whose POS must confirm use.

### Reward groups

**Reward group** — Named bundle of rewards sharing limit rows. A reward may belong to multiple groups via **`reward_group_member`** (ordered gallery / group-tab sequence per group).

**Max distinct reward** — Per-user cap on how many **different reward types** in the group may be claimed in a window (`metric = distinct_reward`). Re-redeeming a type already chosen does not consume another distinct slot.

**Group quantity limit** — Cap on total units redeemed across all rewards in the group (`metric = quantity`, entity type reward group).

**Reward quota limit** — Cap on units of one specific reward (entity type reward). At redemption, group checks stack: reward quota → group quantity → max distinct; every group containing the reward must pass.

**Conflicting group limits** — Save is rejected when max distinct exceeds group quantity at the same user scope (cannot pick M types with fewer than M total units allowed).

### Partner reward sourcing (operational service)

Rocket may layer a **partner catalog** on top of platform rewards: digital e-vouchers procured at redeem time and physical goods via fulfillment partners, billed **pay-per-redeem** for partner SKUs. **Merchant-owned privileges** (on-site discounts, internal services) stay in the same reward tables with no third-party procurement. The Reward Strategy team curates mix and SLAs; partner connectors and billing are deal-specific — not one uniform product surface. Platform truth remains `reward_master`, ledger, stock, and limits; sourcing adds catalog import, procurement APIs, and reconciliation outside the native create/edit forms.

## Rules

- Eligibility is evaluated before points — failing any filter blocks redemption before cost is calculated.
- Dynamic pricing: higher **specificity** (more dimensions matched on a condition) always beats lower specificity regardless of priority on the weaker row.
- When specificity and priority tie, the member pays the **lowest** points among matching conditions.
- Fallback points apply only when **no** condition matches; if any condition matches, fallback is ignored.
- If require points match is true and no condition matches → redemption fails (fallback ignored). If false and no conditions and fallback null → redemption may succeed at **zero** points.
- Empty eligibility arrays mean unrestricted (all tiers, personas, etc.), not “none allowed.”
- Redemption outside the configured window → rejected; visibility and window are independent (campaign rewards may be invisible in browse but redeemable via push/link).
- Stock-controlled reward with zero remaining → rejected.
- Promo-assigned reward: pool must have enough available codes for requested quantity; reservation uses row locking — concurrent redeemers race fairly; insufficient pool → entire transaction fails with no partial codes or point deduction.
- Multi-quantity without promo codes → exactly one ledger row with quantity N; with promo codes → exactly N ledger rows with quantity 1 each.
- Transaction limits are **cumulative**: prior redemptions in the window plus requested quantity must not exceed the cap.
- Claim creates `redeemed_status` true and `used_status` false; mark-used may only set used after claimed. Fulfillment status tracks shipping independently (`pending` → `shipped` → `delivered` → `completed`, or `cancelled` / `reject`).
- Shipping fulfillment requires a saved delivery address on file before redeem or claim-link completes; otherwise address-required error.
- Expiration timestamps are set at redemption from the reward’s expire mode (relative from claim moment, not reward creation).
- Member catalog lists active rewards with visibility `user` or `user_only` whose window has not ended (persona-filtered where configured); `admin` and `campaign` never appear. A reward before its window start is listed but the quote blocks redeem.
- Cached catalog (~5 minute TTL) may lag admin changes until invalidation; stock and promo availability can appear stale briefly.
- A reward opened from the Campaign tab or a campaign slot saves as `campaign` with zero points; visibility is hidden in that editor, so a campaign reward cannot be turned back into a catalog reward from the UI.
- Promo code import: a file is rejected whole if any code repeats within the file or already exists in the pool for the same partner (nothing is added). Only one import per partner namespace runs at a time. Imports are queued; codes become assignable only after the batch finishes.
- Promo code status (derived, first match wins): **Used** (redemption used) → **Usage Expired** (claimed, unused past use expiry) → **Claimed** (assigned, not used) → **Not Yet Active** (unclaimed, before reward window start) → **Expired** (unclaimed, after window end) → **Partner Inactive** (unclaimed, partner deactivated) → **Available**.
- **Campaign slots:** only rewards with visibility `campaign` may attach; slot `source` is one of `referral` (signup/purchase × referrer/friend), `tier_entry` (tier id), or `lifecycle` (`push_reward` workflow node). Changing the linked reward on the parent screen detaches the old id only. `admin_delete_reward` is rejected ("Reward is in use", with the `fn_reward_references` summary as the description) while any slot link or redemption references the reward.
- **Reward groups:** distinct slot consumed only on first claim of a reward **type** in the window for that group; max distinct requires user scope; `max_distinct > group_quantity` at same user scope → save blocked; multi-group membership → all groups’ limits must pass.
- **Async redemption:** API acknowledges with event id immediately; ledger write is eventual. Success UI follows Realtime insert on ledger; failure follows Realtime broadcast on user channel; ~15s without either → processing message (no DB change on failure).
- Persona-aware profile gates: universal form fields always apply; persona-scoped fields apply only when the member’s persona is included — members are not blocked for another persona’s fields.

**Examples (non-obvious):**

- Gold+Student+VIP at 30 pts (three dimensions) beats Gold+Student at 40 pts even if the latter has higher priority.
- Qty 10 with seven promo codes left → fail entirely; qty 5 with codes → five ledger rows.
- Max distinct 1 in a Zone A/B/C group: Zone B blocked after Zone A claimed once; another Zone A redeem allowed if Zone A’s own quota allows.

## Journeys

### Admin journey

| Page | Owning repo | BFF / RPC |
| --- | --- | --- |
| Reward list | loyalty-admin | `bff_list_rewards_paged` (server page 25, URL-driven tab / status / category / name search, pinned first; `summary` carries active-count + quota for the banner), `admin_delete_reward`, `bff_set_reward_active`. Redeemed/used counts are no longer list columns |
| Reward settings (create/edit) | loyalty-admin | `bff_get_reward_details`, `bff_upsert_reward_with_conditions_and_limits`; header pills `bff_get_reward_redemption_stats` (redeemed / used / not used, lazy); slot attach: `bff_attach_campaign_reward`, `bff_detach_campaign_reward`, `bff_upsert_campaign_reward_atomic` |
| Reward pickers (group add modal, content-library button target, Front Line push, campaign/referral/lifecycle pickers) | loyalty-admin | `bff_list_rewards_paged` via `useRewardSearch` / `RewardSearchCombo` — debounced trigram search, page 30, load-more; no full-catalog fetch |
| Reward settings → Promo codes | loyalty-admin | `v_reward_promo_code_list` (status per code), `bff_admin_start_reward_promo_code_import` (queued batch) |
| Reward settings → Redemptions | loyalty-admin | `bff_admin_list_reward_redemptions`, `bff_admin_start_reward_redemption_export` → Inngest `admin-user-export-csv` (`import_type=reward_redemptions_export`); job on **Imports** |
| Marketplace settings | loyalty-admin | Channel OAuth / order claims (see Marketplace setup) |
| Reward group list / form | loyalty-admin | `bff_list_reward_groups`, `bff_get_reward_group_details`, `bff_upsert_reward_group_with_limits`, `bff_delete_reward_group` |
| Frontline push / claim QR | loyalty-admin | `bff_admin_push_reward`, `bff_admin_upsert_reward_claim_link`, `bff_admin_list_reward_claim_links`, `bff_admin_set_reward_claim_link_active` |

| Setting | Effect on behaviour |
| --- | --- |
| Name, category, redemption window, expire mode/TTL | Catalog display and when claim is allowed; expiry after claim |
| Eligibility (tier, persona, birth month) | Who may redeem |
| Require points match, fallback, condition rows | Who pays what points (e.g. Gold 100, Silver 200, everyone else fallback 150) |
| Transaction limits (scope per user / global × day, week, month, year, all time) | Frequency caps; several rows combine |
| Variants | Option dimensions the member must pick at redeem |
| Description headline / body | Short line under the title in lists; long body on detail. Empty headline falls back to a truncated body |
| T&C, slip text | Terms on detail; slip text is the use instruction shown on the slip after Use |
| Static promo code | One fixed code on every member's slip |
| Physical draw copy (printed only) | Header and sub-text on the Front Line thermal slip |
| Visibility, promo toggle, stock, fulfillment | Catalog presence, code assignment, inventory, delivery type |
| Ecommerce toggle, platforms, Shopify discount type + bind | `online_store[]`, `shopify_discount_type` / label, `external_id_shopify` (DiscountCodeNode) via `shopify-upsert-reward-discount` on save when Shopify marketplace is on |
| Campaign slot context (`from`, referral/tier/lifecycle params) | Forces `campaign` visibility; post-save attach to parent slot |
| Pin / featured | Sort order and “special reward” placement |
| Allow members to mark as used | Gates member `api_mark_redemption_used`; forced on for Shopify merchants in admin UI |
| Group membership on reward | Which group limits apply; drag-order in group settings writes `reward_group_member.display_order` |
| Group limits (metric, count, scope, time unit) | Max distinct vs group quantity vs per-reward quota |

1. Open **Reward list** → **Add reward** or edit a row — or land from **Referral settings**, **Tier conditions** (entry rewards), or **Lifecycle automations** with a campaign slot in the URL (`campaign-slot.ts`).
2. Complete basic info, eligibility, points matrix, limits, display, sidebar (visibility, promo, stock, fulfillment). Slot entry defaults visibility to `campaign`.
3. Optionally enable marketplace platforms; for Shopify, pick discount type (percentage, fixed amount, free shipping, free product) and save so the edge function upserts the parent discount before slot attach.
4. **Save**. Catalog rewards list under the Catalog tab; `campaign` rewards under the Campaign tab.
5. Manage list: pin, activate/deactivate, delete.
6. Promo codes (after the reward is saved with promo assignment on): **Reward settings → Promo codes** → **Upload** → batch name, optional lot code, optional partner, `.txt`/`.csv` file with one code per line → toast "codes queued" → codes appear once the batch finishes; the list filters by status and partner.
7. For **Reward groups**: **New group** → add member rewards → add limit rows (reward type = max distinct, reward quantity = group cap) → save (conflicting limits blocked inline).
8. Frontline: search member → **Push reward** (wallet, zero or priced per engine) or create **claim link** + QR. The Push Reward tab uses the Redemption Reward permission (no separate push permission); printed lucky-draw slips and staff-only mark-used run on Front Line (`Frontline_Admin_Actions.md`).

Common pitfalls: require points match with no rows; promo on with empty pool; window end in past; visibility `admin` while expecting catalog traffic; eligibility excluding all members; max distinct greater than group quantity.

### Member journey

| Page / surface | Owning repo | BFF / RPC |
| --- | --- | --- |
| Rewards catalog | loyalty-user | `api_get_rewards_full_cached` — SSR via Render `GET /v1/rewards/catalog` when `LOYALTY_CACHE_READS_VIA=render` ([`Member_App_Cached_Reads.md`](./Member_App_Cached_Reads.md)) |
| Reward detail / redeem | loyalty-user | Cached catalog + `bff_user_get_reward_redemption_quote` + redeem API (queued) |
| Redemption slip / history | loyalty-user | Realtime ledger + `bff_get_reward_history` |
| Claim link landing | loyalty-user | `bff_get_reward_claim_preview`, `bff_claim_reward_via_link` |
| Mark used | loyalty-user / API | `api_mark_redemption_used` (honours `allow_member_mark_used`) |

1. Open catalog — featured rewards first; filter by category; cards show points and availability; group badges show chosen/locked from group usage API.
2. Open detail — eligibility chips, points, window, limit/available from quote; redeem stepper max qty from quote; CTA disabled with reason when ineligible.
3. Shipping rewards: confirm or save address, then confirm redeem.
3a. Variant rewards: pick one option per required dimension.
4. Redeem → immediate ack → spinner; success via Realtime ledger insert; failure via broadcast; timeout toast if neither within ~15s.
5. Success popup: **Use now** or **See wallet** when self-use is on; when off, only **See wallet** with "show the code to staff" copy.
6. **My Rewards** (wallet) holds redeemed-unused rewards. **Use** marks the redemption used and opens the slip: code, barcode, QR, slip instruction; flash rewards show a countdown under relative-minutes expiry.
7. History tabs: claimed unused, used, expired.
8. Claim link: preview → auth if needed → address if shipping → claim → wallet entry.

| Error (member-visible) | Typical cause |
| --- | --- |
| Insufficient points | Wallet balance |
| Insufficient codes / out of stock | Pool or stock |
| Limit reached | Transaction or group limit (incl. RWD018 distinct) |
| Not eligible / window / match | Filters, dates, require points match |
| Address required | Shipping without saved address |
| Could not use reward | Mark-used failed; reward stays in wallet |

### Shopify

- **Admin — discount source:** instead of importing codes, the admin either builds the discount in Reward settings (type percentage / fixed amount / free shipping / free product, value, applies to, minimum requirement, combinations — saved to Shopify as the discount) or picks **Link an existing discount instead** from the store's Shopify discounts. Conditions stay owned by Shopify either way.
- **Admin — forced fields in the Shopify-embedded editor:** fulfillment digital, no promo pool, no stock control, visibility `user`, member self-use on; name and description autofill from the discount until edited.
- **Member:** each redemption receives a unique code minted on the bound discount (never re-minted); the member applies it at Shopify checkout, and an order using the code marks the redemption used. Browse catalog on the native app is unchanged. Product imagery for linked discounts is enriched live from Shopify (see System › Shopify).

## System

### Data model

| Artifact | Role |
| --- | --- |
| `reward_master` | Catalog row: visibility, windows, eligibility, fallback, fulfillment, stock flags, `allow_member_mark_used`, `online_store[]`, `external_id_shopify`, `shopify_discount_type`, `shopify_discount_label` |
| `reward_group_member` | Junction: reward ↔ group with `display_order` (gallery / group tab order) |
| `reward_points_conditions` | Dynamic pricing rows |
| `reward_category` | Catalog grouping |
| `reward_promo_code` / staging | Code pool and bulk import |
| `reward_stock_store` | Per-store stock when enabled |
| `reward_redemptions_ledger` | Immutable claims: codes, qty, points, redeemed/used flags, fulfillment, delivery snapshot |
| `reward_group` | Group metadata and featured flag |
| `transaction_limits` | Per-reward, per-group quantity, and distinct_reward metrics |
| `reward_claim_link` | Claim tokens and active flag |

### Functions

| Function | Role |
| --- | --- |
| `api_get_rewards_full_cached` | Member catalog with eligibility hints, groups map, cache |
| `calculate_redemption_points` / `calculate_redemption_points_fast` | Points for member + reward |
| `check_reward_eligibility_enhanced` | Gate before redeem |
| `redeem_reward_with_points` | Core sync redeem orchestration (consumer-invoked) |
| `fn_check_reward_group_limits` | Distinct and group quantity checks |
| `bff_get_reward_details` / `bff_upsert_reward_with_conditions_and_limits` | Admin load/save with conditions and limits |
| `bff_list_rewards_paged` (+ `fn_reward_admin_list_base`) | Admin list / picker page: kind (catalog / campaign / all), status, category, `p_query` trigram on `reward_master.name` (`idx_reward_master_name_trgm`), `p_with_summary` counts; no ledger join |
| `bff_get_reward_redemption_stats` | Per-reward redeemed / used / not-used from `reward_redemptions_ledger` (detail header, lazy) |
| `bff_list_rewards`, `admin_delete_reward`, `bff_set_reward_active` | Legacy full list (still live, no admin callers); list lifecycle |
| `fn_reward_redemption_quote`, `bff_user_get_reward_redemption_quote`, `bff_get_reward_redemption_quote` | Pre-redeem quote (member + Front Line) |
| `bff_admin_list_reward_redemptions`, `bff_admin_start_reward_redemption_export`, `process_reward_redemption_export_chunk` | Per-reward redemption tab + async CSV export |
| `bff_*_reward_group_*` | Group CRUD |
| `bff_admin_push_reward`, `bff_*_claim_link*`, `bff_claim_reward_via_link` | Push and link claim |
| `bff_get_reward_history` | Member history |
| `api_mark_redemption_used` | Member mark used |
| `bff_admin_start_reward_promo_code_import`, `bulk_upload_promo_codes_chunked` | Promo import: start creates a queued `bulk_import_batches` row (`import_type = reward_promo_codes`, chunk 500, one active batch per partner namespace); codes land in chunks with a per-partner duplicate check |
| `v_reward_promo_code_list` | Per-code derived status, partner, and claiming member for the Promo codes page |
| `fn_campaign_reward_slot_attach` / `fn_campaign_reward_slot_detach` | Slot link core (referral / tier entry / lifecycle) |
| `bff_attach_campaign_reward` / `bff_detach_campaign_reward` | Admin attach API |
| `bff_upsert_campaign_reward_atomic` | Reward save + slot attach in one request |
| `fn_reward_references` | Delete guard — referral outcome, tier entry line, lifecycle node, friend-offer JSON |

### Campaign reward relation layer

Unified slot JSON `{ source, target, extra? }` — no separate `campaign_reward_relation` table.

| `source` | Persisted link |
| --- | --- |
| `referral` | Signup/purchase referrer → `referral_outcomes` (`outcome_type = reward`, party `inviter`/`invitee`). Purchase friend → `referral_program.friend_offer` JSON + optional `shopify_mother_discount_id` |
| `tier_entry` | `tier_entry_rewards` row (`reward_kind = reward`) for `target.tier_id` |
| `lifecycle` | `workflow_node.node_config.reward_id` on `push_reward` action (`workflow_id` + `node_id`) |

Grant at runtime uses **Central Outcome Dispatcher** for referral/tier entry; lifecycle pushes via workflow action — not catalog browse redeem.

### Flows

**Catalog (sync, cached):** resolve merchant → filter visibility and eligibility → attach points preview and group usage → return JSON; invalidate on reward/stock/promo mutations.

**Redeem (async):** client → Render API → queue → consumer calls `redeem_reward_with_points` → eligibility → points → limits → group limits → stock → promo lock → wallet debit → ledger insert(s) → Realtime success; failures broadcast without ledger write.

**Admin save:** validate → upsert master → replace conditions and limits → related stock rows.

**Promo multi-qty:** reserve N codes in one transaction or fail entirely.

### External services

Render redemption consumer (Kafka / event pipeline per `REGISTRY_RENDER.md`) invokes DB redeem; Realtime for success/failure UI. No separate Inngest path for standard catalog redeem.

### Known gaps

- Exact marketplace connector set varies by merchant (professional services / roadmap).
- Partner procurement SLAs are commercial defaults, not platform-enforced timers.
- Member UI component inventory not fully enumerated in loyalty-user repo.
- Cached catalog staleness up to TTL after rapid stock changes.
- Stock control: Reward settings saves only the toggle; there is no admin field for `stock_total`, so the redeem-time stock check rarely has a total to enforce.
- Slip text: the slip opened right after redeem is built from the Realtime ledger row with slip text empty, so the admin's slip instruction does not show on that slip.

### Shopify

**Discount types (admin create/edit, stored on `reward_master.shopify_discount_type`):** `percentage`, `fixed_amount`, `free_shipping`, `free_product`. Save with Shopify marketplace enabled calls edge **`shopify-upsert-reward-discount`** (GraphQL DiscountCodeNode — basic codes for percentage/fixed/free product, free-shipping APIs for shipping). Referral purchase-friend slot may pass discount fields in slot `extra`; attach merges into `friend_offer`. Legacy price-rule-only binding (`external_id_shopify` without type) may still exist on older rows; enrichment treats type from Shopify when present.

When `external_id_shopify` is set, mark-used and redemption-detail BFFs may call **`shopify-get-discount-products`** (service role) for `shopify_discount_detail` (titles, images, resolved discount type). Credentials from `merchant_credentials` (`shopify_app`). On-demand only — failure omits enrichment.

### Partner reward sourcing (system boundary)

In-platform: tables and RPCs above. Service layer: partner SKU catalog import, redeem-time code procurement APIs, physical fulfillment partner shipping, monthly partner billing reports — implemented per deal, not as a single connector in core redeem path.

## Related

- **Currency** — Wallet debit and burn accounting on claim; see `Currency.md`.
- **Tier / Tag & Persona** — Eligibility and pricing dimensions; persona-aware forms; see `Tier.md`, `Tag_and_Persona.md`, `Forms.md`.
- **Referral** — Campaign reward slots for signup/purchase outcomes; see `Referral.md`.
- **Tier** — Entry-reward slots (`tier_entry`); see `Tier.md` §Entry rewards.
- **Mission / AMP** — `campaign` visibility for mission grants and lifecycle `push_reward` slots; see `Mission.md`, `AMP - Rule Based.md`.
- **Central Outcome Dispatcher** — Free rewards from check-in/missions use dispatcher; catalog redeem uses wallet path; see `Central_Outcome_Dispatcher.md`.
- **Earn Channel / Marketplace** — `online_store[]` and channel OAuth; see `Earn_Channel.md`, marketplace setup docs.
- **Translation** — Localized display fields; see `Translation_System.md`.
