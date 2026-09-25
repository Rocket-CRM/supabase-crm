# Shopify Plan — Architecture Summary

## Core idea

**Shopify is a dimension, not a feature group.**

A dimension is an axis of a plan. Shopify is one dimension (with siblings like Lazada, Shopee, TikTok coming). Each dimension carries its own **level** (e.g. `basic` / `advanced` / `plus`), and that level — not the plan alone — decides which features inside the dimension's feature group are on.

So the resolution chain is:

```
plan  →  dimension (Shopify)  →  level  →  feature group  →  feature
```

Three independent scoping axes, each living in exactly one place:

| Axis | Question it answers | Where it lives |
|---|---|---|
| **Feature scoping** | "Which capabilities does Shopify expose?" | `feature_config` rows under `feature_group = 'shopify'` |
| **Level scoping** ("by plan again") | "Which tier of Shopify does this plan grant?" | `level_key` on those rows |
| **Plan composition** ("dimension of a plan") | "What level of Shopify is in this merchant's plan?" | `merchant_plan_dimension` |

## Schema components

**Catalog (3 small tables)**

| Table | Role | Key columns |
|---|---|---|
| `plan_dimension` | Catalog of dimensions and the feature group each governs | `key` ('shopify'), `name`, `feature_group` ('shopify'), `active_status` |
| `plan_dimension_level` | Tiers within a dimension | `dimension_key`, `level_key` ('basic'/'advanced'/'plus'), `display_order` |
| `merchant_plan_dimension` | Which level a plan grants per dimension | `plan_id`, `dimension_key`, `level_key`, unique(`plan_id`, `dimension_key`) |

**Feature scoping — extend `feature_config` (no parallel table)**

Add two columns:

- `dimension_key` (nullable — null = legacy non-dimensional rows still work)
- `level_key` (nullable)

Everything else stays: `feature_group`, `feature_key`, `enabled`, `max_count`, `config`, `merchant_id` overrides, `plan_id`.

## Resolution flow — "is Shopify feature X on for merchant M?"

1. `merchant_master.plan_id` → the merchant's plan
2. `merchant_plan_dimension(plan, 'shopify')` → the granted **level** L
3. `feature_config` where `dimension_key='shopify' AND level_key=L AND feature_group='shopify' AND feature_key=X` → the default
4. Any `merchant_id`-scoped row **overrides** the level default (same precedence the resolver uses today)

Only change needed: `fn_merchant_feature_config` / `fn_merchant_feature_enabled` route plan → level via `merchant_plan_dimension` before reading `feature_config`. Same function names, same call sites.

## Minimal vs full version

- **Minimal** — if dimensions are always 1:1 with feature groups and levels are tiny/stable, drop `plan_dimension` and `plan_dimension_level` as tables; treat them as enum/convention. Keep only `merchant_plan_dimension` + the two new `feature_config` columns.
- **Full** — keep the catalog tables if you want the admin UI to render dimensions/levels dynamically or sell them as discrete SKUs.

## Why this shape (and not the alternatives)

- **No `shopify_*` tables.** A Shopify-specific entitlement table would duplicate `feature_config`'s plan/merchant precedence and split entitlement truth across two places.
- **No generic catch-all.** Modeling Shopify directly on `feature_config` as just another `feature_group` collapses the dimension and the feature group into one axis — you lose the "level" scoping that makes plans meaningful.
- **Dimension is first-class.** Putting the level on the dimension (not on the feature row, not on the plan) means new dimensions (Lazada, TikTok) drop in without touching the resolver or the feature group model.

## Open decisions (before any schema work)

1. **Are levels ordinal or independent?** If `plus ⊇ advanced ⊇ basic` (entitlements inherit upward), the resolver can short-circuit. If levels are independent feature bundles, each level needs its own full row set.
2. **Who assigns the Shopify level?** Something **we grant per plan** (controlled in our catalog), or **read live from the merchant's actual Shopify subscription** (Basic/Shopify/Advanced/Plus via Shopify API)? The second is a real-time dependency and changes the resolver to be I/O-bound.
3. **One dimension → one feature group, or one → many?** Assumed 1:1 for now; confirm before locking `plan_dimension.feature_group` as a single column vs. a junction.

---

*Design summary only — no schema changes made. Next step: pick the minimal-vs-full variant and answer the three open decisions, then draft the migration + resolver update.*
