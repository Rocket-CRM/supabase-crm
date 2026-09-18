# Reward

Redeemable catalog items members buy with points — the spend side of earn-and-burn. Merchants define eligibility, dynamic points pricing, stock, promo pools, fulfillment, and optional marketplace tags; members browse, redeem asynchronously, then use or track delivery. Admin and frontline surfaces also push or link-claim rewards without catalog browse.

Owner surfaces: loyalty-admin, loyalty-user, Shopify (storefront delta via `online_store[]`)

## Concept

A **reward** is a merchant-defined benefit (voucher, product, experience) with display content, visibility, redemption window, optional stock, and fulfillment method. **Redemption** exchanges points for that benefit and creates a ledger row with a stable code; **usage** is a separate track from **claim** (points deducted vs benefit consumed at store or online).

**Two-layer pricing** — (1) **Eligibility**: binary filters on tier, user type, persona, tags, birth month — empty means unrestricted. (2) **Dynamic points**: how many points this member pays, from condition rows matched on the same dimensions plus specificity and priority.

**Dynamic points condition** — One row mapping tier / user type / persona / tags to a points cost and priority. The engine scores matches (tier heaviest, then user type, persona, tags), prefers higher specificity, then higher priority, then **lowest points** when still tied (customer-favorable).

**Require points match** — When on, a member must match at least one condition or redemption is blocked; fallback points are ignored. When off, unmatched members pay fallback points or zero if fallback is null.

**Visibility** — Who can start a catalog redemption and whether the reward appears in member browse: `user` (catalog + frontline), `user_only` (catalog only — staff cannot gift on frontline), `admin` (frontline only), `campaign` (push / mission / link / program outcome only — never in browse catalog).

**Campaign reward slot** — When referral, tier entry, or lifecycle workflow needs a **reward-type outcome**, admin opens **Reward settings** from that parent screen with a **slot** (`source` + `target`) in the URL (mirrored in `sessionStorage` for Shopify App Bridge). The saved catalog row must use visibility `campaign`; attach links the row to the parent without duplicating reward data. Detach removes the link only — it does not delete the catalog reward.

**Fulfillment method** — `digital`, `shipping` (address snapshot on redeem), `pickup`, `printed` (thermal slip on frontline; slip copy from physical draw fields).

**Promo code pool** — Optional unique codes assigned per redemption from `reward_promo_code`; bulk import with partner attribution.

**Stock control** — Optional finite inventory via stock store; unlimited when disabled.

**Transaction limits** — Per-reward caps on redemption count or quantity by scope (`user` / merchant / transaction) and time unit, with optional absolute windows.

**Multi-quantity redemption** — Quantity 1–1000 in one request. Without promo codes: one ledger row with quantity N. With promo codes: N rows with quantity 1 and distinct codes; **all-or-nothing** if the pool cannot satisfy N.

**Redemption window** — Optional start/end; outside window the reward may still display but cannot redeem.

**Expiration (use)** — After claim: `relative_days`, `relative_mins` (flash), or `absolute_date`; computed at redemption time.

**Online store distribution** — `online_store[]` tags which external storefronts may surface the reward (merchant-defined strings, e.g. `shopify`); optional Shopify discount bind via typed discount config and `external_id_shopify`.

**Claim link** — Tokenized URL/QR for one-time or controlled claim; respects same points engine and shipping address rules as catalog redeem.

**Burn** — Points deducted from the member wallet on successful claim (see Currency).

**Redemption quote** — Server-computed preview before confirm: max selectable quantity, limit/available copy, and `blocking_reason` when redeem is not allowed (member catalog stepper and Front Line redeem modal share `fn_reward_redemption_quote`).

**Member self-use** — Per-reward `allow_member_mark_used` (default true). When false, `api_mark_redemption_used` rejects member JWT; staff mark-used paths unchanged.

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
- Catalog API for members returns only `visibility = user` (and persona-aware filtering where configured); `admin`, `campaign`, and `user_only` browse rules differ — campaign never appears in browse.
- Cached catalog (~5 minute TTL) may lag admin changes until invalidation; stock and promo availability can appear stale briefly.
- Save and Publish forces visibility to `user` regardless of dropdown at save time (not used when saving from a campaign slot — slot saves keep `campaign`).
- **Campaign slots:** only rewards with visibility `campaign` may attach; slot `source` is one of `referral` (signup/purchase × referrer/friend), `tier_entry` (tier id), or `lifecycle` (`push_reward` workflow node). Changing the linked reward on the parent screen detaches the old id only. `admin_delete_reward` is rejected while `fn_reward_references` reports an active slot link.
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
| Reward list | loyalty-admin | `api_get_rewards_full_cached`, `bff_list_rewards` (incl. redeemed/used qty), `admin_delete_reward`, `bff_set_reward_active` |
| Reward settings (create/edit) | loyalty-admin | `bff_get_reward_details`, `bff_upsert_reward_with_conditions_and_limits`; slot attach: `bff_attach_campaign_reward`, `bff_detach_campaign_reward`, `bff_upsert_campaign_reward_atomic` |
| Reward settings → Redemptions | loyalty-admin | `bff_admin_list_reward_redemptions`, `bff_admin_start_reward_redemption_export` → Inngest `admin-user-export-csv` (`import_type=reward_redemptions_export`); job on **Imports** |
| Marketplace settings | loyalty-admin | Channel OAuth / order claims (see Marketplace setup) |
| Reward group list / form | loyalty-admin | `bff_list_reward_groups`, `bff_get_reward_group_details`, `bff_upsert_reward_group_with_limits`, `bff_delete_reward_group` |
| Frontline push / claim QR | loyalty-admin | `bff_admin_push_reward`, `bff_admin_upsert_reward_claim_link`, `bff_admin_list_reward_claim_links`, `bff_admin_set_reward_claim_link_active` |

| Setting | Effect on behaviour |
| --- | --- |
| Name, category, redemption window, expire mode/TTL | Catalog display and when claim is allowed; expiry after claim |
| Eligibility arrays | Who may redeem |
| Require points match, fallback, condition rows | Who pays what points |
| Transaction limits | Per-user or global frequency caps |
| Display fields, image, T&C, slip, physical draw copy | Member and slip UI |
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
4. **Save** or **Save and Publish** (forces public `user` visibility).
5. Manage list: pin, activate/deactivate, delete; upload promo codes in bulk when promo assignment is on.
6. For **Reward groups**: **New group** → add member rewards → add limit rows (reward type = max distinct, reward quantity = group cap) → save (conflicting limits blocked inline).
7. Frontline: search member → **Push reward** (wallet, zero or priced per engine) or create **claim link** + QR.

Common pitfalls: require points match with no rows; promo on with empty pool; window end in past; visibility `admin` while expecting catalog traffic; eligibility excluding all members; max distinct greater than group quantity.

### Member journey

| Page / surface | Owning repo | BFF / RPC |
| --- | --- | --- |
| Rewards catalog | loyalty-user | `api_get_rewards_full_cached` |
| Reward detail / redeem | loyalty-user | Cached catalog + `bff_user_get_reward_redemption_quote` + redeem API (queued) |
| Redemption slip / history | loyalty-user | Realtime ledger + `bff_get_reward_history` |
| Claim link landing | loyalty-user | `bff_get_reward_claim_preview`, `bff_claim_reward_via_link` |
| Mark used | loyalty-user / API | `api_mark_redemption_used` (honours `allow_member_mark_used`) |

1. Open catalog — featured rewards first; filter by category; cards show points and availability; group badges show chosen/locked from group usage API.
2. Open detail — eligibility chips, points, window, limit/available from quote; redeem stepper max qty from quote; CTA disabled with reason when ineligible.
3. Shipping rewards: confirm or save address, then confirm redeem.
4. Redeem → immediate ack → spinner; success via Realtime ledger insert (slip / use now); failure via broadcast; timeout toast if neither within ~15s.
5. Slip shows code, barcode, QR; flash rewards show countdown when relative minutes expiry applies.
6. History tabs: claimed unused, used, expired.
7. Claim link: preview → auth if needed → address if shipping → claim → wallet entry.

| Error (member-visible) | Typical cause |
| --- | --- |
| Insufficient points | Wallet balance |
| Insufficient codes / out of stock | Pool or stock |
| Limit reached | Transaction or group limit (incl. RWD018 distinct) |
| Not eligible / window / match | Filters, dates, require points match |
| Address required | Shipping without saved address |

### Shopify

Member **browse catalog** on the native app is unchanged. When `online_store` includes `shopify`, the reward may appear in Shopify-connected surfaces per marketplace configuration; discount binding uses `external_id_shopify` (Shopify DiscountCodeNode GID from upsert on save). Storefront checkout flows route through marketplace/order-claim setup — not duplicated here. Product imagery for linked discounts on mark-used and redemption detail is enriched live from Shopify (see System › Shopify).

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
| `bff_list_rewards`, `admin_delete_reward`, `bff_set_reward_active` | Admin list lifecycle (list includes live redeemed/used qty) |
| `fn_reward_redemption_quote`, `bff_user_get_reward_redemption_quote`, `bff_get_reward_redemption_quote` | Pre-redeem quote (member + Front Line) |
| `bff_admin_list_reward_redemptions`, `bff_admin_start_reward_redemption_export`, `process_reward_redemption_export_chunk` | Per-reward redemption tab + async CSV export |
| `bff_*_reward_group_*` | Group CRUD |
| `bff_admin_push_reward`, `bff_*_claim_link*`, `bff_claim_reward_via_link` | Push and link claim |
| `bff_get_reward_history` | Member history |
| `api_mark_redemption_used` | Member mark used |
| `bulk_upload_promo_codes_chunked` | Promo import |
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

### Shopify

**Discount types (admin create/edit, stored on `reward_master.shopify_discount_type`):** `percentage`, `fixed_amount`, `free_shipping`, `free_product`. Save with Shopify marketplace enabled calls edge **`shopify-upsert-reward-discount`** (GraphQL DiscountCodeNode — basic codes for percentage/fixed/free product, free-shipping APIs for shipping). Referral purchase-friend slot may pass discount fields in slot `extra`; attach merges into `friend_offer`. Legacy price-rule-only binding (`external_id_shopify` without type) may still exist on older rows; enrichment treats type from Shopify when present.

When `external_id_shopify` is set, mark-used and redemption-detail BFFs may call **`shopify-get-discount-products`** (service role) for `shopify_discount_detail` (titles, images, resolved discount type). Credentials from `merchant_credentials` (`shopify_app`). On-demand only — failure omits enrichment.

### Partner reward sourcing (system boundary)

In-platform: tables and RPCs above. Service layer: partner SKU catalog import, redeem-time code procurement APIs, physical fulfillment partner shipping, monthly partner billing reports — implemented per deal, not as a single connector in core redeem path.

## Related

- **Currency** — Wallet debit and burn accounting on claim; see `Currency.md`.
- **Tier / Tag & Persona** — Eligibility and pricing dimensions; persona-aware forms; see `Tier.md`, `Tag_and_Persona.md`, `Forms.md`.
- **Referral** — Campaign reward slots for signup/purchase outcomes; see `Referral.md`, reference `requirements/reference/SHOPIFY_REFERRALS_ONSITE_INTEGRATIONS.md` §Campaign reward outcomes.
- **Tier** — Entry-reward slots (`tier_entry`); see `Tier.md` §Entry rewards.
- **Mission / AMP** — `campaign` visibility for mission grants and lifecycle `push_reward` slots; see `Mission.md`, `AMP - Rule Based.md`.
- **Central Outcome Dispatcher** — Free rewards from check-in/missions use dispatcher; catalog redeem uses wallet path; see `Central_Outcome_Dispatcher.md`.
- **Earn Channel / Marketplace** — `online_store[]` and channel OAuth; see `Earn_Channel.md`, marketplace setup docs.
- **Translation** — Localized display fields; see `Translation_System.md`.
