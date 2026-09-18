# Platform × Plan × Feature Registry

Single entitlement catalog: what each merchant may use on each product surface (standalone Core vs Shopify embedded), expressed as taxonomy defaults plus platform/plan/merchant deltas.

Owner surfaces: loyalty-admin (nav + in-page gates), Shopify embedded admin (`bff_get_feature_entitlements`), runtime BFFs and earn/redeem chokepoints

## Concept

Rocket separates **what can be granted** (a shared capability tree) from **who grants it at what value** (platform → plan → optional merchant override). A merchant on Shopify and on standalone Core can hold **different plans on each platform**; lookups are always scoped to one platform at a time.

**Capability tree** — Module → feature group → feature → sub-feature. Each node declares whether it is toggleable, optional quota shapes, optional config shapes, and registry defaults (on/off, limits, config).

**Product surface** — A platform row (standalone `core`, Shopify `shopify`). Each surface owns its own plan ladder and platform-wide deltas.

**Plan** — A priced tier on one platform (for example Shopify Free vs Growth). Plans store display metadata, optional monthly **order quota** (display-only; billing enforcement lives outside this system), and an optional **grant-all** flag that bypasses toggle/limit checks for internal or enterprise merchants.

**Plan assignment** — Which plan a merchant holds **per platform**. Multi-platform merchants use one assignment row per `(merchant, platform)`; legacy standalone-only flows may still read a single plan from merchant master until fully migrated.

**Scope delta** — A row that overrides enabled, limits, and/or config for exactly one scope: plan, merchant, or platform. Unmentioned nodes inherit registry defaults (see Rules).

**Resolver** — Server-side merge that answers `{ enabled, limits, config }` for one node key. Admin UIs and BFFs should not re-implement merge logic.

**Grant-all plan** — When active, every node resolves enabled with unlimited quotas, while **config still merges** so operational settings (expiry mode, receipt entry mode, etc.) stay intact.

**Entitlement map BFF** — One authenticated call returns the full merged feature map for a platform plus plan metadata and Shopify upgrade hints; frontends gate nav, tabs, fields, and upgrade CTAs from this payload.

Billing state (paid vs grace vs limited order processing) is **not** stored here; earn/redeem paths must **AND** external billing checks with resolved entitlements at chokepoints.

## Rules

- Each scope delta row sets **exactly one** of plan, merchant, or platform — never more than one.
- Lookup always follows: choose platform → resolve that platform’s plan assignment → merge registry default → platform delta → plan delta → merchant delta.
- **Enabled**, **limits**, and **config** are independent dimensions: a row may change quotas without toggling off, subject to the constraint that `enabled` is currently non-null on delta rows (limits-only rows are not expressible today).
- **Feature groups** behave as containers: when no explicit toggle exists, a group-level check resolves **on** unless a leaf under it is off.
- **Leaf nodes** respect registry `default_enabled` (for example storefront widget defaults off until a platform row turns it on).
- **Grant-all** on the resolved plan → every node `enabled=true`, `limits={}` (unlimited), **config merge unchanged**.
- **Non-grant-all plans** may be authored as **off-rows only**: write `enabled=false` (and limit rows) for exclusions; everything else inherits registry defaults. Bespoke Core plan `loyalty_essentials` is the reference pattern (27 off-rows, no on-rows).
- **Legacy callers** that omit platform still resolve plan via merchant master and, since 2026-06-28, **also apply registry defaults** before plan → merchant merge.
- **Platform-aware callers** pass platform explicitly; plan comes from `merchant_plan_assignment`, not merchant master.
- **Admin menu** items with a mapped feature key render only if the merchant’s plan enables that node **or** grant-all is true **or** the item has no mapping; role permissions still apply afterward.
- **User history tabs** that map to a feature return **empty** when the plan disables that feature, even if the client requests the tab (defensive guard on the history dispatcher).
- **Direct resolver RPCs** must never be called with client-supplied merchant id; thin BFFs derive merchant from the admin token.
- Shopify **order-volume caps and subscription pay-state** are owned by the external Shopify admin service — never fold them into the resolver; chokepoints **AND** entitlement with `should_process_loyalty` (and related modes).

Example (default-on): Munasoul on `loyalty_essentials` has no `enabled=true` rows; referral stays off because an off-row exists, while currency tabs stay on because no off-row exists and the leaf defaults on.

### Shopify

- Runtime checks in Shopify earn/redeem/receipt paths use **`fn_merchant_shopify_feature_enabled`** (platform pinned to Shopify) — same taxonomy keys as Core, different plan ladder and seeded deltas.
- **Customer account hub, widget, product points, wishlist** touchpoints are available on **all** Shopify plans including Free (reference MD Part 2); entitlement keys do not block install.
- **Loyalty landing page** CMS, on-site content overview, and theme sections require **`display` / `shopify_landing_page`** (Essential+); Free plan carries an explicit off-row.
- **Referral settings page** is visible on all plans; **embedded admin section visibility** (purchase vs signup tabs, program master switch, etc.) is **surface gating** in loyalty-admin (`REFERRAL_SECTIONS`), not a separate registry node — do not conflate with plan entitlements.
- **Earn rules** sections gate on leaf keys (`earn.multiplier`, `currency.expiry`, `lifecycle.*`, `tier.per_tier_earn_rate`, …) via `EARN_SECTIONS` + `FeatureGate`; tier burn matrix and tier qualification fields use `tier.per_tier_burn_rate`, `tier.conditions_by_spend_orders`, `reward.tier_reward_eligibility` where wired.
- **Checkout points estimate** extension is **not shipped** (excluded from deploy); no entitlement row applies.

## Journeys

### Admin journey

Platform operators manage the catalog through data operations today (no admin UI for plan authoring). Merchant admins **consume** entitlements through the portal and embedded Shopify app.

| Page / operation | Owning repo | BFF / RPC |
| --- | --- | --- |
| Admin nav (standalone) | loyalty-admin | `bff_get_admin_menu` (plan filter + roles) |
| Feature map (standalone) | loyalty-admin | `bff_get_feature_entitlements('core')` |
| Feature map (Shopify embedded) | loyalty-admin | `bff_get_feature_entitlements('shopify')` |
| Earn rules sections | loyalty-admin | Entitlements + `EARN_SECTIONS` |
| Referral settings sections | loyalty-admin | Surface map `REFERRAL_SECTIONS` (Shopify delta) |
| Display settings / on-site content cards | loyalty-admin | Entitlements + `settings-visibility` card registry |
| User history tabs | loyalty-user + admin | `bff_get_user_history_menu`, `bff_get_entity_history` |
| Plan assignment (Shopify billing) | rewarding-shopify / welcome flow | `shopify_sync_merchant_plan` |

| Knob (platform ops) | Effect on behaviour |
| --- | --- |
| Insert platform | New product surface key |
| Insert plan on platform | New tier; optional `grant_all_features`, `order_quota`, `shopify_plan_handle` |
| Assign merchant plan per platform | Switches effective deltas for that surface |
| Insert plan/platform/merchant `feature_config` | Overrides enabled, limits, config for one taxonomy node |
| Map admin menu item → feature key | Hides nav entry when plan disables node |
| Grant-all on plan | Forces all toggles on and quotas unlimited; config merge preserved |

1. **Create or adjust plan** — Insert or update plan row on the target platform; set grant-all only for enterprise-style internal merchants.
2. **Seed plan deltas** — Add off-rows (and limit rows such as `max_active_rewards`) for tiers that should exclude capabilities; rely on registry defaults for the rest.
3. **Assign merchant** — Insert `merchant_plan_assignment` for each platform the merchant uses; Shopify assignment syncs from billing (`shopify_sync_merchant_plan`) — do not mirror Shopify billing into merchant master plan alone.
4. **Verify merchant admin** — Open standalone or embedded admin; confirm nav, earn sections, display cards, and upgrade CTAs match the plan (entitlements loader runs once per session on Shopify).
5. **Verify member-facing read paths** — History menu tabs and guarded entity history respect the same keys; widget/mission endpoints may still need entitlement filtering when non-grant-all plans roll out broadly.

### Member journey

Members never see “plan name” directly. They see **allowed product behaviour**: which history tabs exist, whether landing page content publishes, whether tier-specific earn rates apply on orders, whether lifecycle automations fire, and whether referral purchase flows run. When a capability is off-plan, UI hides or downgrades (Shopify upgrade CTA) and backend chokepoints reject or no-op the operation.

### Shopify

1. Merchant installs app → billing assigns `shopify_*` plan → entitlements refresh on embedded load.
2. **Free** merchant sees hub/widget/points surfaces; **landing page** routes show upgrade gate (`display.shopify_landing_page`).
3. Merchant opens **Earn from orders** — bonus multipliers hidden until `earn.multiplier`; lifecycle block hidden until any `lifecycle.*` leaf on plan; per-tier earn fields hidden until `tier.per_tier_earn_rate`.
4. Merchant opens **Referral settings** — purchase path visible; signup/program master hidden by embedded section map (not plan off-row).
5. Merchant upgrades in Shopify pricing → welcome sync → higher plan unlocks landing CMS and previously off lifecycle/tier keys per matrix below.

## System

### Data model

| Table | Role |
| --- | --- |
| `platform` | Catalog of surfaces (`core`, `shopify`). |
| `merchant_plan` | Plan tier per platform; `grant_all_features`, `order_quota`, optional Shopify handle. |
| `merchant_plan_assignment` | `(merchant_id, plan_id, platform_id)` — one plan per platform; `validate_platform` trigger. |
| `feature_registry` | Adjacency tree (`node_type` module / feature_group / feature / sub_feature); defaults and schemas; `validate_parent` trigger. |
| `feature_config` | Scoped deltas; exactly one of `plan_id` / `merchant_id` / `platform_id`; `enabled`, `limits`, `config`. |
| `admin_menu_config` | Optional `feature_group` + `feature_key` per menu item for plan gating. |

**Live taxonomy (loyalty module, verified 2026-09-17):** 14 feature groups — `campaign`, `currency`, `display`, `earn`, `earn_channel`, `forms`, `lifecycle`, `member_intelligence`, `persona`, `reward`, `store`, `storefront`, `tier`, `workspace` — plus 35 features and 7 sub-features. Empty modules `marketing_automation` and `customer_service` reserved.

**Seeded plans**

| Family | Keys |
| --- | --- |
| Core (feature-tiered) | `core_free`, `core_starter`, `core_growth`, `core_premium` |
| Shopify (volume ladder) | `shopify_free`, `shopify_essential`, `shopify_standard`, `shopify_growth` |
| Internal / bespoke | `enterprise` (grant-all), `loyalty_essentials` (Core off-rows only) |

**Core plan deltas (examples)** — `reward.max_active_rewards` limits 10 / 25 / 100 for starter / growth / premium; `workspace.team_seats` caps on growth.

**Shopify platform rows (examples)** — Hide standalone-only groups on Shopify (`forms`, persona/user_type, earn factor multiplier); enable `storefront/shopify_widget`; force lifecycle config currency to points where seeded.

### Functions

| Function | Role |
| --- | --- |
| `fn_merchant_feature_resolve` | Workhorse `{ enabled, limits, config }` merge for one node. |
| `fn_merchant_feature_enabled` / `fn_merchant_feature_config` | Thin wrappers over resolve (back-compat). |
| `fn_merchant_platform_plan` | Plan id for merchant on a platform. |
| `fn_merchant_shopify_feature_enabled` | Resolve with Shopify platform pinned (chokepoints, Shopify-only BE). |
| `bff_get_feature_entitlements(p_platform)` | Full map + plan metadata + Shopify `upgrade_targets` / `next_plan`. |
| `bff_get_admin_menu` | Role filter AND plan-feature filter. |
| `bff_get_entity_history` | Dispatches history reads; entitlement guard returns empty when off-plan. |
| `bff_get_user_history_menu` | Tab visibility via resolve (top-level + dynamic sub-filters). |
| `shopify_sync_merchant_plan` | Billing → plan assignment sync. |
| `trigger_feature_registry_validate_parent` | Enforces tree shape on registry inserts. |

### Flows

**Platform-aware merge (preferred)** — Registry default → platform scope row → plan scope row → merchant scope row. Each layer overrides only keys it sets; limits/config deep-merge; enabled = most specific non-null.

**Legacy merge (`p_platform` null)** — Plan from merchant master → merchant row; registry default applied since 2026-06-28 → then plan → merchant.

**Grant-all short-circuit** — After plan resolution, if `grant_all_features`, force enabled true and empty limits for every node before return; config merge still runs.

**Admin FE session** — Standalone: entitlements fetched with `core`. Embedded Shopify: single shared fetch with `shopify` (loader dedupes). Gating uses `enabled` only; `config` drives operational fields, not visibility.

**Member history** — Menu builder hides tabs whose mapped feature resolves off; entity history dispatcher double-checks before querying ledgers.

### BFF entitlements response (admin contract)

Success payload shape consumed by loyalty-admin (`admin-entitlements.ts`):

| Field | Meaning |
| --- | --- |
| `platform` | `core` or `shopify` |
| `plan.key` / `plan.name` | Resolved plan |
| `plan.grant_all_features` | Bypass flag |
| `plan.order_quota` | Display-only monthly cap |
| `features` | Map keyed by group and dotted leaf keys (`reward`, `reward.max_active_rewards`, …) each `{ enabled, limits, config }` |
| `upgrade_targets` | Per denied feature on Shopify: next plan handle/name/quota for upgrade CTA; null on Core |
| `next_plan` | Next ladder step on self-serve platforms |

OpenAPI for public APIs lives in **`Open_API.md`**; this BFF is admin-authenticated only.

### Shopify plan matrix (seeded deltas, verified 2026-09-17)

Order quotas (display): Free 200, Essential 500, Standard 2500, Growth 7500.

| Feature key | Free | Essential | Standard | Growth |
| --- | --- | --- | --- | --- |
| `display.shopify_landing_page` | off | on (default) | on | on |
| `reward.max_active_rewards` (`active_rewards`) | 5 | 10 | 25 | 100 |
| `earn.multiplier` | off | off | on | on |
| `currency.multiplier_by_product` | off | off | on | on |
| `currency.expiry` | off | off | on | on |
| `lifecycle.signup` / `birthday` | off | off | on | on |
| `lifecycle.anniversary` / `tier_change` | off | off | off | on |
| `tier.per_tier_earn_rate` / `per_tier_burn_rate` | off | off | on | on |
| `tier.conditions_by_spend_orders` | off | off | off | on |
| `reward.tier_reward_eligibility` | off | off | on | on |

Runtime enforcement on orders/wallet/redeem uses `fn_merchant_shopify_feature_enabled` for the same keys (see earn condition migrations). Admin UI uses `bff_get_feature_entitlements('shopify')` + section registries above.

**Surface vs plan (Shopify embedded)**

| Mechanism | What it gates |
| --- | --- |
| Plan entitlements | Landing CMS, earn/tier/lifecycle fields, active reward caps, chokepoints |
| `REFERRAL_SECTIONS` | Which referral settings blocks render (purchase-only on embedded) |
| `EARN_SECTIONS` / `FeatureGate` | Whole earn sections and individual tier/multiplier fields |
| Display card registry | Which display/on-site cards appear per surface (landing card Shopify-only) |

### Security

Resolver functions are `SECURITY DEFINER` with merchant id **parameter** — primitives, not public endpoints. BFFs call `get_current_merchant_id()` from JWT/headers/admin user lookup and abort when missing. Platform for entitlements should come from authenticated context (`core` vs `shopify`), not unchecked client override.

### Plan and platform administration

No `bff_upsert_plan` yet — operators use migrations or MCP:

- New platform → insert `platform`.
- New plan → insert `merchant_plan` with valid `platform_id`.
- Assign merchant → insert `merchant_plan_assignment` (platform must match plan’s platform).
- Deltas → insert `feature_config` with registry **group/key** text (legacy Core rows may still use older group names like `loyalty` until `feature_id` backfill).

Design reference: `.cursor/plans/platform-plan-feature-registry-architecture.md`. Registry grep: `requirements/REGISTRY_SUPABASE.md` (Platform Plan Registry domain).

### External services

Shopify Partner billing / `rewarding-shopify` welcome sync owns subscription status and order-processing modes. Entitlements answer “is this feature in contract”; billing service answers “should we process loyalty for this order volume state”. Product code must combine both at chokepoints.

### Known gaps

1. **In-page tabs** beyond admin menu rely on FE entitlements; not every settings page is backend-enforced.
2. **`bff_get_widget_settings`** and **`bff_get_user_missions`** should filter by entitlement when restricted plans roll out beyond grant-all enterprise defaults.
3. **Legacy platform-null callers** — `fn_get_effective_earn_channels`, upload-receipt BFFs still use legacy path; candidates to refactor onto `fn_merchant_feature_resolve` with explicit platform.
4. **`feature_config.feature_id` not backfilled** — text group/key matching; resolver must tolerate legacy `loyalty` group names on old Core rows.
5. **Enterprise explicit `enabled=true` rows** inert under grant-all; optional cleanup of empty toggle rows.
6. **`enabled NOT NULL` on deltas** — cannot express limits-only overrides; nullable `enabled` desired.
7. **Checkout points estimate** — not deployed; no registry node.

While all production merchants remain on grant-all `enterprise`, many gates are latent; Shopify tier seeds and Munasoul `loyalty_essentials` prove non-grant-all behaviour.

## Related

- **Shopify.md** — OAuth, billing sync, webhook plumbing; points to this doc for entitlement matrix and `fn_merchant_shopify_feature_enabled`.
- **Display_Settings.md** — Landing/hub/widget touchpoints; landing gated by `display.shopify_landing_page`.
- **Referral.md** — Purchase referral program; embedded section map vs plan keys.
- **Earn_Channel.md** — Earn channel display vs referral program gate.
- **Admin_Panel.md** — Admin menu transform and role permissions layered on plan gates.
- **Tier.md** / **Reward.md** — Product behaviour when tier/reward entitlement leaves are off.
- **reference/SHOPIFY_REFERRALS_ONSITE_INTEGRATIONS.md** — Part 2 plan gating narrative for on-site surfaces (not CRM Knowledge indexed).
