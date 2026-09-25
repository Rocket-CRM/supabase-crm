# Platform×Plan Feature Registry — Implementation Handoff (2026-06-24)

> **COMPLETE (2026-06-24).** Steps 0–4 below are all done and verified live on `wkevmsedchftztoolkmi`.
> See `requirements/CHANGELOG.md` (2026-06-24, top bullet) and the architecture doc's updated
> "Resolved / Still open" section. Remaining future work (not blockers): `feature_id` backfill +
> resolver switch to FK matching, `merchant_plan_assignment` backfill, making `enabled` nullable.

**Task:** Build platform×plan feature scoping for Shopify per
`.cursor/plans/platform-plan-feature-registry-architecture.md`.

## Status — DONE (migration `platform_plan_feature_registry_foundation`, verified)

Safe additive foundation applied to project `wkevmsedchftztoolkmi`:

- `platform` catalog created + seeded: `core` (Standalone / Core), `shopify`. RLS on, no policy
  (mirrors `merchant_plan`); `set_updated_at` trigger.
- `feature_registry` created — single adjacency table: `id`, `node_type`
  (module/feature_group/feature/sub_feature), `parent_id` (self FK, ON DELETE CASCADE), `key`, `name`,
  `display_order`, `is_active`, `is_toggleable`, `limit_schema` jsonb, `config_schema` jsonb,
  `default_enabled`, `default_limits` jsonb, `default_config` jsonb. Unique `(parent_id,key)` +
  partial unique `(key) WHERE parent_id IS NULL`. Trigger `validate_parent` enforces level nesting.
- `merchant_plan.platform_id` (text FK → `platform.key`) added; existing `enterprise` + `loyalty_only`
  backfilled to `core`.
- `merchant_plan_assignment` created — `(merchant_id, plan_id, platform_id)`, unique
  `(merchant_id, platform_id)`, merchant-isolation RLS, `validate_platform` trigger (assignment
  platform must equal the plan's platform).
- `feature_config` gained additive nullable `platform_id` (FK platform), `feature_id`
  (FK feature_registry), `limits` jsonb default `{}`.
- **Existing resolver untouched** — `fn_merchant_feature_config` / `fn_merchant_feature_enabled` still
  read `feature_group`/`feature_key`; all current call sites keep working.
- `requirements/CHANGELOG.md` entry added (2026-06-24).

## OPEN — do these in this fresh thread, in order

### Step 0 (BLOCKER — confirm before seeding plans)
Reconcile plan names. Hypothesis: two platforms, two plan sets —
- `shopify`: Free / Essential / Standard / Growth (differ by **order volume only**, features flat).
- `core`: Free / Starter / Growth / Premium (feature-tiered, the original matrix).
Confirm exact keys/names with the user. **No Shopify or standalone plans exist in `merchant_plan` yet
(only `enterprise`, `loyalty_only`).** Do not invent keys.

### Step 1 — Seed `feature_registry` taxonomy
From architecture doc §2.5 (tree) + §6.1 (inventory). Modules: `loyalty` (populate), plus empty
`marketing_automation`, `customer_service`. Groups under loyalty: `currency`, `reward`, `earn`
(rename of legacy `loyalty` group), `tier` (own group), `earn_channel`, `store`, `forms`, `campaign`,
`lifecycle`, `persona`, `member_intelligence`, `workspace`, `storefront`. Features + sub-features with
dimensions per §6.1 (incl. `user_type` under persona; quotas: `team_seats.seats`,
`bulk_import.{rows_per_import,imports_per_month}`, `reward.max_active_rewards.active_rewards`).
Confirm group-naming decision (earn rename / tier split) with user first (open item #2).

### Step 2 — Resolver upgrade (BREAKING — impact analysis FIRST)
Rewrite `fn_merchant_feature_config` / `fn_merchant_feature_enabled` to: accept optional
`p_platform text DEFAULT NULL` (NULL = legacy behavior), resolve the merchant's plan for that platform
via `merchant_plan_assignment`, and **field-merge** (not row-wins) registry default → platform → plan
→ merchant for `enabled` / `limits` / `config` (doc §5).
- **Impact analysis required before applying:** current resolver is row-wins `LIMIT 1`. Query whether
  any feature has BOTH a plan row and a merchant row for the same `(feature_group,feature_key)` where
  field-merge would change today's result. Keep `feature_group`/`feature_key` read path during
  transition (decision #2 = add `feature_id` alongside, do not drop text columns yet).
- Add helper `fn_merchant_platform_plan(p_merchant_id, p_platform)` if useful for the BFF.
- Note: billing/volume (`should_process_loyalty`, monthly cap) is **external** (Shopify admin service,
  not in this DB) — `AND` it at earn/redeem chokepoints, never inside the registry resolver (doc §5,§8).

### Step 3 — Seed plans + `feature_config` deltas
After Step 0: insert plan rows into `merchant_plan` with `platform_id`. Seed platform-scope
`feature_config` rows for Shopify show/hide (`platform_id='shopify', enabled=false` for `forms`,
`earn_factor`+`multiplier`, `user_type`, `persona`; `shopify_widget` enabled at shopify scope; forced
`config` like lifecycle `currency=points` per doc §7.1). Shopify plan rows stay flat on features.

### Step 4 — Close out
Regenerate `requirements/REGISTRY_SUPABASE.md` (skill `registry-regenerate`); update CHANGELOG for
resolver/seed; update any feature-guide docs.

## Critical context
- Project: `wkevmsedchftztoolkmi`. All DB via Supabase MCP.
- Design source of truth: `.cursor/plans/platform-plan-feature-registry-architecture.md`.
- Catalog tables intentionally have RLS-on/no-policy (accessed via SECURITY DEFINER), mirroring
  `merchant_plan`/`feature_config`.
- `feature_config.feature_id` should only ever point at `node_type IN ('feature','sub_feature')` —
  enforce by app discipline or add a trigger when the resolver starts using it.
