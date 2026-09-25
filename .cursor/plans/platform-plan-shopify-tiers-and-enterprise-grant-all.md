# Plan — Enterprise "grant-all" + tiered plan seed + read-shape enforcement

> Companion to `requirements/Platform_Plan_Feature_Registry.md` and
> `.cursor/plans/platform-plan-feature-registry-architecture.md`.
> Status: EXECUTED 2026-06-28. Steps 1–5 + 8 done & verified; all 115 merchants granted full features
> (enterprise grant-all). Steps 6 (admin-menu plan-gating — needs a menu→feature mapping layer) and the
> remaining §4 read-shaping endpoints (`bff_get_widget_settings`, `bff_get_user_missions`) deferred —
> inert while every merchant is grant-all. See `requirements/CHANGELOG.md` (2026-06-28).

## 0. Decisions (resolved 2026-06-24)

1. **Platform: `shopify` only.** Tiered self-serve plans live on the `shopify` platform. `core` keeps
   only `enterprise` (+ `loyalty_only`). The existing dormant `core_*` plans are out of scope here
   (leave as-is; clean up separately if desired).
2. **Plan keys kept: `shopify_free / shopify_essential / shopify_standard / shopify_growth`.**
   The image's column LABELS were wrong. Correct mapping of image columns → real plans:
   - image "Free" → `shopify_free`
   - image "Starter" → `shopify_essential`
   - image "Growth" → `shopify_standard`
   - image "Premium" → `shopify_growth`
3. **Orders volume = display-only.** Store as `merchant_plan.order_quota` (200/500/2500/7500) for the
   pricing page. Enforcement stays in the external Shopify admin service (registry doc §3).
4. **"Multiplier by product" = `points/multiplier_by_product`** (a per-product POINTS multiplier),
   NOT `earn_factor/multiplier`. Confirmed distinct: the shopify platform already hides
   `earn_factor`+`multiplier` entirely, yet the tiers turn "multiplier by product" ON for higher tiers —
   so they must be different nodes. (Flag for a functional sanity-check at implementation.)

## 1. Enterprise = "all features on" via a flag (kills the ~21 config rows)

**Current:** enterprise is expressed as ~21 explicit `enabled=true` `feature_config` rows (mixed
`loyalty/*` legacy + group names). Brittle and verbose.

**Change:**
- `ALTER TABLE merchant_plan ADD COLUMN grant_all_features boolean NOT NULL DEFAULT false;`
- Set `grant_all_features = true` for `enterprise` (and `loyalty_only` if it should also be all-on — confirm).
- `fn_merchant_feature_resolve` short-circuits: if the resolved plan has `grant_all_features`, return
  `{enabled:true, limits:{} /* unlimited */, config: <registry default_config merged with any explicit rows>}`
  for every node — before the registry→platform→plan→merchant merge.
- **Axis caveat:** the flag cleanly covers the **toggle** and **limit** axes. The **config** axis
  (e.g. `points.expiry_mode`, `earn_factor` flags, `marketplace_code.channels`) is operational config,
  not entitlement. Decide whether enterprise's existing `config` rows are (a) redundant with the real
  feature tables (drop them) or (b) the source of truth (keep a minimal config-only set). Verify before
  deleting any enterprise rows.

**Cleanup (after flag is live and verified):** delete the enterprise `enabled=true` toggle rows; keep
only config rows that are confirmed authoritative.

## 2. Tiered plan seed (per image) — expressed as deltas from registry defaults

Registry defaults are `enabled=true` for all features (except `storefront/shopify_widget`=false), with
`reward/max_active_rewards` default `{active_rewards:5}`. So a tier only needs **deltas** = rows for what
it does NOT get, plus the active_rewards limit.

All rows scoped to `plan_id` on the **shopify** platform. Columns are the real plan keys:

| Node | shopify_free | shopify_essential | shopify_standard | shopify_growth |
|---|---|---|---|---|
| `merchant_plan.order_quota` (display attr, §0.3) | 200 | 500 | 2500 | 7500 |
| `reward/max_active_rewards` (limit `active_rewards`) | 5 | 10 | 25 | 100 |
| `points/multiplier_by_product` | off | off | on | on |
| `points/expiry` | off | off | on | on |
| `reward/tier_reward_eligibility` | off | off | on | on |
| `tier/per_tier_earn_rate` | off | off | on | on |
| `tier/per_tier_burn_rate` | off | off | on | on |
| `tier/conditions_by_spend_orders` | off | off | off | on |
| `lifecycle/signup` | off | off | on | on |
| `lifecycle/birthday` | off | off | on | on |
| `lifecycle/anniversary` | off | off | off | on |
| `lifecycle/tier_change` | off | off | off | on |

Always-on (no delta): `currency/points`, `earn/earn_condition`, `reward` group, `tier` group,
`tier/conditions_by_points`.

"off" = insert `feature_config` row `enabled=false` scoped to that `plan_id`. "on" = no row (inherits
default `true`). `shopify_free` active_rewards=5 row is optional (equals default).

**Interaction with existing shopify PLATFORM rows:** the platform layer already sets (for all shopify
plans) `earn_factor`+`multiplier`+`forms`+`persona`=off, `shopify_widget`=on, and lifecycle
`config.currency=points` with lifecycle features ON. Plan-level `enabled=false` overrides the platform's
lifecycle ON for free/essential (merge = most-specific non-null), while `config.currency=points` is still
inherited via key-wise merge. Net: no conflict — plan layer wins on `enabled`, platform layer supplies
`config`.

`order_quota`: `ALTER TABLE merchant_plan ADD COLUMN order_quota integer;` then set per plan above.
NULL = unlimited (enterprise). Display-only; not read by the resolver.

**Parent/child semantics to confirm:** for Free/Starter the whole `lifecycle` group is off in the image.
Decide whether to (a) write a single group-level `enabled=false` AND have consumers AND parent→child,
or (b) write each leaf `enabled=false`. Safer today: write leaf-level rows AND set the group row for the
menu. Confirm resolver does NOT auto-AND parent enabled.

## 3. Enforcement model (per user's chosen posture)

User posture: **minimal write enforcement; UI-driven restrictions; BE shapes user-app/widget reads.**

| Surface | Mechanism | Work |
|---|---|---|
| **Writes** (create reward #26, etc.) | NONE server-side — FE prevents via entitlement call | No chokepoint work |
| **Admin nav** | `bff_get_admin_menu()` filters menu/sub-menu items by entitlement (BE-driven, menus come from API) | Wire resolver into `bff_get_admin_menu` |
| **Admin in-page** (tabs/filters/sections) | Hardcoded FE — gated by a new `bff_get_feature_entitlements(p_platform)` the FE reads once | Build entitlement BFF |
| **User app / Shopify widget** | BE shapes return; FE renders blindly | See §4 |

## 4. User-app / widget read-shaping (the BE-controls-shape work)

**Primary (confirmed):** `bff_get_user_history_menu(p_surface)` returns the history tab/subtab tree.
Wire the resolver in so tabs/subtabs are filtered by entitlement (e.g. drop mission tab if
`campaign/mission` off, drop receipt tab if `earn_channel/upload_receipt` off). The downstream
`bff_get_entity_history` / per-entity history BFFs then only ever get asked for tabs that exist —
optionally add a defensive entitlement check there too.

**To audit (Decision-driven, second pass):** other user-facing composite/shell endpoints that assemble
multi-section screens — the Shopify widget shell, member home, rewards catalog, missions list, tier
display. Need to enumerate which are single composite BFFs vs FE-assembled. Candidate signals found:
`get_widget_settings_menu()`, `get_display_settings_menu()` (look admin-side). ACTION: grep user/
storefront BFFs and list the composite ones before deciding which need read-shaping.

## 5. New BFF — `bff_get_feature_entitlements(p_platform)`

- No merchant arg; uses `get_current_merchant_id()` (§4 of registry doc).
- Resolves merchant's plan for `p_platform` via `merchant_plan_assignment` (or legacy `merchant_master.plan_id`
  while assignment table is empty).
- Returns the merged entitlement tree (registry default → platform → plan → merchant, or all-true if
  `grant_all_features`).
- Drives: admin in-page FE gating + (optionally) the widget shell.

## 6. Activation dependency

`merchant_plan_assignment` is EMPTY and the tiered plans are dormant. Nothing changes for live merchants
until rows are inserted there (or until the resolver is pointed at assignments). Seeding tiers is safe
and inert until assignment + a `bff_assign_merchant_plan` exists. Sequence: flag+seed first (inert),
then read-shaping BFFs, then assignment tooling, then assign merchants.

## 7. Sequenced work (after §0 decisions)

1. `grant_all_features` column + resolver short-circuit + set enterprise true. (migration + resolver)
2. Verify enterprise resolves all-true; then clean up redundant enterprise rows.
3. Add `merchant_plan.order_quota`; seed shopify tier deltas + order_quota per §2 (keys
   `shopify_free/essential/standard/growth`). No plan rename needed.
4. Build `bff_get_feature_entitlements(p_platform)`.
5. Wire entitlement filter into `bff_get_user_history_menu`.
6. Wire entitlement filter into `bff_get_admin_menu`.
7. Audit + shape remaining user/widget composite endpoints (§4 second pass).
8. (Later) `bff_assign_merchant_plan`, then assign merchants; backfill `feature_id`.

## 8. Out of scope / explicitly NOT doing
- Write-path quota enforcement (UI-driven by decision).
- Order-volume enforcement (external Shopify admin service).
- `feature_id` backfill (separate transition task).
