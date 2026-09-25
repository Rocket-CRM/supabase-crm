# Platform → Plan → Feature Registry — Architecture

> Supersedes `shopify-plan-dimension-architecture.md`. "Dimension" is renamed **platform**; the
> separate "level" axis is dropped (a plan *is* the tier). Design only — no schema changes applied.

## 1. The core idea: two trees, not one

Feature scoping kept getting tangled because two independent things were squeezed into one
"hierarchy." They are separate axes, and `feature_config` is their intersection.

| Axis | Question it answers | Levels | Lives in |
|---|---|---|---|
| **Taxonomy** (the registry) | *What* can be granted? | module → feature_group → feature → sub-feature | catalog tables (the registry) |
| **Scope** (the entitlement) | *Who* grants it, at what value? | platform → plan → merchant | scope columns on `feature_config` |

- The **registry** defines the taxonomy once, scope-agnostic, with each node's default.
- **`feature_config`** holds only the per-scope overrides — one row = "this *scope* sets this
  *taxonomy node* to this enabled / quota / config."

## 2. Concepts

### Scope axis

- **Platform** — a channel / product surface a merchant subscribes through: `shopify`, and later
  `lazada`, `shopee`, `tiktok`, plus the existing core surface (`core`). A platform **owns plans**.
- **Plan** — a priced tier belonging to **exactly one platform** (e.g. Shopify `free` / `starter` /
  `growth` / `premium`). A plan **grants features**. The platform is always implied by the plan.
- **Merchant** — holds **one plan per platform** (many-to-many: a merchant can be on Shopify *and*
  Lazada at once, each with its own tier). The most specific override layer.

### Taxonomy axis

- **Module** — top product area: `loyalty`, `marketing_automation`, `customer_service`.
- **Feature group** — capability cluster within a module: `reward`, `tier`, `currency`, `lifecycle`.
- **Feature** — the gated unit (a leaf, or a parent of sub-features): `max_active_rewards`,
  `per_tier_earn_rate`, `points`.
- **Sub-feature** — the most granular gated / configurable unit under a feature, used when a feature
  needs finer control: under `points` → `expiry`, `multiplier_by_product`. Optional: a feature with
  no sub-features is itself the leaf.

### Resolution context (decided)

Every entitlement lookup is **scoped to one platform** — the function takes a platform in its
payload, resolves the merchant's plan *for that platform*, and returns that plan's feature tree.
**No cross-platform overlap / union / intersection.** One call → one platform → one plan.

## 2.5. Visual representation

### The two axes meeting at `feature_config`

```
        TAXONOMY (registry — "what")                 SCOPE (entitlement — "who/how much")

        module                                       platform
          └─ feature_group                             └─ plan
               └─ feature                                   └─ merchant (override)
                    └─ sub-feature
                          \                                        /
                           \                                      /
                            └──────────►  feature_config  ◄──────┘
                                  (feature_id) + (platform_id | plan_id | merchant_id)
                                   values: enabled · limits{} · config{}
```

### Loyalty module taxonomy (current + audit additions)

```
loyalty  (module)
├─ currency
│   ├─ points            [T,C]   └─ expiry (sub) · multiplier_by_product (sub)
│   └─ tickets           [T]
├─ earn   (was "loyalty" group)
│   ├─ earn_condition    [T]
│   └─ earn_factor       [T]     └─ multiplier (sub)        ◄ promoted from config
├─ tier   (promoted to its own group)
│   ├─ conditions_by_points       [T]
│   ├─ per_tier_earn_rate         [T]
│   ├─ per_tier_burn_rate         [T]
│   └─ conditions_by_spend_orders [T]
├─ reward
│   ├─ max_active_rewards [T,Q seats? → active_rewards]
│   ├─ tier_reward_eligibility    [T]
│   └─ promo_code         [T]                              ◄ NEW feature
├─ earn_channel
│   ├─ marketplace_code   [T]
│   ├─ product_code_scan  [T]
│   └─ upload_receipt     [T,C]  └─ auto_approve (sub) · line_item_derived (sub)
├─ campaign   (loyalty — earn mechanics)
│   ├─ mission [T]  └─ recurring (sub) · progressive (sub)
│   ├─ checkin [T] · activity [T] · referral [T]
├─ store          ├─ store [T] · store_attribute [T]
├─ forms          ├─ custom_form [T] · survey [T]
├─ lifecycle  (NEW)   ├─ signup · birthday · anniversary · tier_change   [each T]
├─ persona    (NEW)   ├─ segmentation [T] · entitlements_advanced [T]
├─ member_intelligence (NEW)  └─ customer_360 [T]
├─ workspace  (NEW)   ├─ team_seats [T,Q seats] · bulk_import [T,Q rows/imports] · translation_management [T]
└─ storefront (NEW)   └─ shopify_widget [T]   (granted only at platform_id=shopify)

  legend:  T = toggle   Q = quota(s)   C = config     (sub) = sub-feature (has parent feature)
  modules marketing_automation and customer_service exist in the taxonomy but have no groups yet.
```

## 2.6. What differentiates what (platform vs plan vs billing)

Three layers each carry a *different kind* of differentiation. Keeping them separate is what stops the
model collapsing:

| Layer | Differentiates by | Owner | Example |
|---|---|---|---|
| **Platform** | which **features exist** at all | this registry (`feature_config` platform rows) | Shopify hides `persona`, `forms`, `earn_factor`, `user_type` |
| **Plan** | feature **depth / tiering** *(standalone only)* | this registry (`feature_config` plan rows) | standalone Premium adds per-tier burn rate |
| **Billing** | **order volume + pay state** | **external Shopify admin service** | Shopify Free=200/mo, Growth=unlimited; `limited` mode pauses loyalty |

**Critical consequence for Shopify:** per the Shopify admin team's billing doc, *all Shopify plans
expose the same CRM features and differ only by monthly order volume*. So on the **Shopify** platform
the **plan axis is flat on features** — Free/Essential/Standard/Growth resolve to the *same*
`feature_config`. What separates them (volume) is **not in this registry**; it lives in the external
billing service and is `AND`-ed in at resolution time (see §5). Feature *tiering* by plan is a
**standalone-platform** behavior, not a Shopify one.

> Plan-name reconciliation (open): Shopify tiers = **Free / Essential / Standard / Growth**
> (volume-only). The earlier feature matrix (**Free / Starter / Growth / Premium**) is the
> **standalone/core** platform's plan set. Two platforms, two plan sets — confirm before seeding.

## 3. The registry structure

The registry carries **definition + default only** — no plan / platform / merchant data.

**One self-referential table, `feature_registry`, holds all four levels** (adjacency list). A
`node_type` column says what each row is; `parent_id` links it to the level above. Chosen over three
typed tables because the catalog is small, stable, and read-mostly — the simplicity outweighs the
FK-enforced integrity the split would have given (replaced by one parent-type trigger, below).

### `feature_registry`
| column | applies to | notes |
|---|---|---|
| `id` (PK) | all | |
| `node_type` | all | `module` / `feature_group` / `feature` / `sub_feature` |
| `parent_id` (self FK, nullable) | all | NULL for module; else points one level up |
| `key` | all | `unique(parent_id, key)` |
| `name`, `display_order`, `active_status` | all | FE rendering |
| `is_toggleable` | leaf only | does this feature expose an on/off gate? (default true) |
| `limit_schema` (jsonb) | leaf only | declares **named numeric limits** (see §3.1). `{}` = none |
| `config_schema` (jsonb) | leaf only | declares **behavioral settings** (keys + types). `{}` = none |
| `default_enabled`, `default_limits`, `default_config` | leaf only | fallbacks when no scope row exists |

Taxonomy path = the `parent_id` chain:
`module → feature_group → feature → sub_feature`. `feature` and `sub_feature` differ only by
`node_type` (a sub-feature's parent is a feature; a feature's parent is a group).

**Integrity (replacing the lost FKs):**
- A trigger asserts `parent.node_type` is exactly the level above `node_type`
  (group→module, feature→group, sub_feature→feature; module→NULL).
- A trigger (or app discipline for FE-only v1) asserts `feature_config.feature_id` points only at a
  row whose `node_type IN ('feature','sub_feature')` — never a module/group.

**Feature vs sub-feature rule.** A sub-feature *must* have a parent of `node_type='feature'`. If a
capability has no parent feature, it is a **feature** directly under its group — the group-level
toggle (`feature_key = NULL` in `feature_config`) already serves "turn the whole group off." So
lifecycle types and `reward/promo_code` are **features**, not sub-features.

**No `platform_key`.** Platform-specificity is *not* a property of the taxonomy — it falls out of the
scope chain (**feature → plan → platform**). A platform-only feature like `shopify_widget` simply has
its `feature_config` row at platform scope (`platform_id='shopify'`); on any other platform the
resolver finds no row and the registry default (off) hides it. The registry stays platform-agnostic.

## 3.1. Limitation dimensions (how one feature carries several kinds of limit)

A feature can be limited along **three orthogonal dimensions at once**. The registry *declares* which
dimensions a feature exposes; `feature_config` *stores the values* per scope.

| Dimension | Registry declares | `feature_config` stores | Example |
|---|---|---|---|
| **Toggle** | `is_toggleable` | `enabled` (bool) | "rewards on/off" |
| **Quota(s)** | `limit_schema` — named caps with unit / default / `unlimited_allowed` | `limits` (jsonb map) | `{"active_rewards": 25}`, `{"per_import_rows": 1000, "imports_per_month": 20}` |
| **Config** | `config_schema` — keys + types | `config` (jsonb map) | `{"receipt_entry_mode": "total_only"}` |

- **`limits` is a map, not a single `max_count`** — so a feature can have *multiple* numeric limits
  (e.g. `bulk_import` = rows-per-import **and** imports-per-month). Replaces the legacy single
  `max_count` column.
- **Quota value convention**: `NULL` = unlimited, `0` = none, `N` = limit. (e.g. `team_seats`
  Free `{"seats":1}`, Growth `{"seats":5}`, Premium `{"seats":null}` = unlimited.)
- A feature uses **only the dimensions it declares** — most are toggle-only (`limit_schema={}`,
  `config_schema={}`); `max_active_rewards` is toggle + one quota; `upload_receipt` is toggle +
  config.

This keeps `feature_config` to three value columns (`enabled`, `limits`, `config`) regardless of how
many limits a feature has — the registry schema gives them meaning and drives FE rendering.

## 4. Scope tables (entitlement side)

- **`platform`** — catalog: `key`, `name`, `display_order`, `active_status`.
- **`merchant_plan`** (existing) **+ `platform_id`** — each plan declares its platform. Backfill
  existing `enterprise` / `loyalty_only` → `core`; new Shopify tiers → `shopify`.
- **`merchant_plan_assignment`** — many-to-many `(merchant_id, plan_id, platform_id)`,
  `unique(merchant_id, platform_id)` (one plan per platform per merchant). Source of truth for
  multi-platform merchants; the single `merchant_master.plan_id` becomes legacy / core pointer.
- **`feature_config`** (existing) **+ `platform_id` + `feature_id` + `limits`** — `feature_id` FK →
  `feature_registry` (replaces loose `feature_group` / `feature_key` text); `platform_id` joins the
  existing `plan_id` and `merchant_id` scope columns; `limits` (jsonb map) replaces the single
  `max_count`. Value columns are now `enabled` + `limits` + `config` (the three dimensions, §3.1).

## 5. How the registry relates to `feature_config`

The registry is the **definition + default**. `feature_config` holds **only the deltas per scope**.
A row points at a registry node (`feature_id`) and sets one scope column + only the dimensions it
overrides.

```
feature_registry (default)        "max_active_rewards: enabled=true, limits={active_rewards:5}"
        ▲ feature_id FK
        │
feature_config (scoped overrides)
   ├─ platform_id set  → platform-wide baseline   limits={active_rewards:10}
   ├─ plan_id set      → plan/tier grant          limits={active_rewards:25}
   └─ merchant_id set  → per-merchant override     limits={active_rewards:50}
```

### Plan-level vs platform-level rows

Same registry node; they differ only by which scope column is set:

| Row kind | platform_id | plan_id | merchant_id | Applies to |
|---|---|---|---|---|
| Registry default | — | — | — | global fallback (in `feature_registry`) |
| **Platform-level** | `shopify` | NULL | NULL | all Shopify tiers, unless a plan overrides |
| **Plan-level** | NULL | `shopify_growth` | NULL | the Growth tier (platform implied by plan) |
| **Merchant-level** | NULL | NULL | `merchant_X` | one merchant |

### Resolution — "feature F, platform P, merchant M" (field-merge)

1. Find M's plan for P via `merchant_plan_assignment`.
2. Gather the layer rows for F: registry default → platform-P row → that plan's row → merchant row.
3. **Merge per dimension** (each layer overrides only the keys it sets; more specific wins):
   - `enabled` = COALESCE(merchant, plan, platform, registry default)
   - `limits`  = registry default ⊕ platform ⊕ plan ⊕ merchant (deep-merge per limit key)
   - `config`  = registry default ⊕ platform ⊕ plan ⊕ merchant (deep-merge per config key)

Field-merge (not row-wins) is what makes "deltas only" real: a plan that raises one limit stores just
that key, without restating the feature's other dimensions. Merchant overrides are
**platform-agnostic** (no `platform_id` on merchant rows); a platform-only feature is already
constrained because it only has rows in that platform's chain.

### Billing state ANDs over everything (external gate)

`feature_config` answers *"is this capability granted?"*. It does **not** answer *"is the merchant
currently allowed to transact?"* — that is **billing state**, owned by the **Shopify admin service**
(verified: no `merchant_billing` / `should_process_loyalty` / `monthly_order_limit` exists in this
project). Billing mode (`normal` / `grace` / `limited`) and the monthly order-volume cap can pause the
whole loyalty module regardless of any `enabled=true` row.

**Rule for implementers:** every earn / redeem chokepoint must `AND` the external
`should_process_loyalty` (billing) signal with the resolved feature entitlement. A `limited` merchant
must not earn just because a feature row says `enabled=true`. The registry resolver and the billing
gate are two independent inputs, composed at the BFF / processing boundary — never collapsed into one.

## 6. Module → feature_group mapping

All groups below sit under the **loyalty** module. (`marketing_automation` and `customer_service`
modules exist in the taxonomy but have no groups yet.)

| feature_group | status | notes |
|---|---|---|
| `currency` | exists | points / tickets |
| `reward` | exists | + new feature `promo_code` |
| `earn` *(rename of legacy `loyalty` group)* | exists | `earn_condition`, `earn_factor` — rename avoids the group/module name collision |
| `tier` | exists *(currently a key under `loyalty`)* | promote to its own group (matrix is tier-heavy) |
| `earn_channel` | exists | marketplace_code / product_code_scan / upload_receipt |
| `store` | exists | store / store_attribute |
| `forms` | exists | custom_form / survey |
| `campaign` | exists, ungrouped | mission / checkin / activity / referral — **confirmed loyalty** (earn mechanics) |
| `lifecycle` | **new** | signup / birthday / anniversary / tier_change |
| `persona` | **new** | segmentation / entitlements_advanced |
| `member_intelligence` | **new** | customer_360 |
| `workspace` | **new** | team_seats / bulk_import / translation_management (operational, cross-cutting) |
| `storefront` | **new** | shopify_widget (granted only at `platform_id=shopify` scope) |

> Grouping for the new operational features (`workspace`, `member_intelligence`, `storefront`) is
> proposed to avoid overloading the legacy `loyalty` group; confirm against FE navigation IA.

## 6.1. Feature & sub-feature inventory (from FE audit, reclassified)

**New features** (`parent_feature_id` NULL — leaves directly under their group). Dimensions per §3.1
(T = toggle, Q = quota, C = config):

| group | feature | dimensions | FE pages |
|---|---|---|---|
| lifecycle | `signup` | T | `/lifecycle-automations*` |
| lifecycle | `birthday` | T | `/lifecycle-automations*` |
| lifecycle | `anniversary` | T | `/lifecycle-automations*` |
| lifecycle | `tier_change` | T | `/lifecycle-automations*`, `/user-tags` |
| persona | `segmentation` | T | `/persona` |
| persona | `entitlements_advanced` | T | `/persona-entitlements-advanced` |
| member_intelligence | `customer_360` | T | `/customer-360*` (single toggle; profile-action hides stay FE surface logic — see §7.2) |
| persona | `user_type` | T | standalone-only (buyer/seller); off at `platform_id=shopify` |
| workspace | `translation_management` | T | `/translation` |
| workspace | `bulk_import` | T + Q (`rows_per_import`, `imports_per_month`) | `/customers/imports`, `/imports/new/*` |
| workspace | `team_seats` | T + Q (`seats`) | `/team` |
| storefront | `shopify_widget` | T (granted at `platform_id=shopify` scope) | `/display-settings/shopify-widget` |
| reward | `promo_code` | T | `/promo-codes-lots`, `/reward-settings/[id]/promo-codes`, `/partners` |

**New sub-features** (`parent_feature_id` set — genuine parents exist):

| parent feature (group/key) | sub-feature | dimensions | replaces config key |
|---|---|---|---|
| earn / `earn_factor` | `multiplier` | T | `config.multiplier` (base/additive stay as config) |
| campaign / `mission` | `recurring` | T | `config.types[]` |
| campaign / `mission` | `progressive` | T | `config.types[]` |
| earn_channel / `upload_receipt` | `auto_approve` | T | `config.auto_approve` |
| earn_channel / `upload_receipt` | `line_item_derived` | T | `config.receipt_entry_mode` |

## 7. Worked example — feature tiering is a **standalone** behavior, not Shopify

Registry: `loyalty / reward / max_active_rewards`, dimensions T + Q,
`default_enabled=true`, `default_limits={"active_rewards":5}`.

Feature *depth* varies by plan **on the standalone/core platform only** (`feature_config` deltas):

| platform_id | plan_id | limits | resolves to |
|---|---|---|---|
| — | — | — | default → **5** |
| — | `core_starter` | `{"active_rewards":10}` | standalone Starter → **10** |
| — | `core_growth` | `{"active_rewards":25}` | standalone Growth → **25** |
| — | `core_premium` | `{"active_rewards":100}` | standalone Premium → **100** |

**On Shopify this column is flat.** All Shopify plans share identical features; they differ only by
order volume, which lives in the external billing service (§2.6). So there are **no per-Shopify-tier
`feature_config` rows** for `max_active_rewards` — every Shopify plan resolves to the default. What
makes Shopify Growth ≠ Free is `should_process_loyalty` + the volume cap, `AND`-ed in at the
processing boundary (§5), not a registry row.

## 7.1. Worked example — config dimension forced at platform scope

Not every Shopify difference is a toggle or quota. Some are **forced settings** via the `config`
dimension at platform scope. Example — Shopify forces points-only currency on lifecycle:

Registry: `loyalty / lifecycle / signup`, dimensions T + C,
`config_schema={"currency":{"type":"enum"}, "days_offset":{"type":"int"}}`.

| platform_id | plan_id | config | effect |
|---|---|---|---|
| — | — | — | standalone: merchant picks currency + offset freely |
| `shopify` | — | `{"currency":"points","days_offset":0}` | Shopify: currency locked to points, offset forced 0 |

The field stays *visible* but its value is **forced** — this is how "static/locked field" behaviors
should be modeled, instead of inventing a sub-feature per field.

## 7.2. Do NOT model these (explicit exclusions)

These belong to **frontend surface logic / infrastructure**, not the registry. Recorded so no one
promotes them to features later:

- **Field-level hides** (days-offset field, currency dropdown, ticket-type sub-field, static
  promo-code field) — use a **platform-scope `config` forced value** (§7.1) if behavior must change;
  do not create a sub-feature per visible field.
- **Lifecycle action-type allowlist** — emerges automatically from feature toggles (`persona` off →
  "Assign persona" hides; `forms` off → "Submit form" hides; `earn_factor` off → "Assign personal
  earn factor" hides). Do not model each action type.
- **App Bridge nav, sidebar, OAuth, webhooks** — infrastructure, not entitlements.
- **`shopify_store` earn-channel auto-seed** — operational, not gated.

## 7.3. Deferred (useful later, not v1)

- **`core_display`** feature for standalone display editor symmetry (so `storefront` isn't
  Shopify-only by accident). Optional — add only if cheap.
- **`customer_360` sub-features** (`edit_profile`, `delete_member`, `adjust_points`) — for now
  `customer_360` is one toggle; profile-action hides on Shopify stay FE surface logic.
- **`analytics`** feature — nav removal is sufficient today; add only if per-plan gating is wanted.

## 8. Limit / state enforcement

- **Toggle / config dimensions** (multiplier, per-tier rates, lifecycle toggles) — **FE-only for now**.
  The resolver exposes them; no hard BE validation.
- **Quota dimension** (`active_rewards`, `seats`, `rows_per_import`) — optional cheap BE check at write
  time (a single `COUNT` against an already-touched table). Recommended for the worst abuse vectors;
  not required for v1.
- **Billing / volume** (`should_process_loyalty`, monthly order cap) — **owned externally** by the
  Shopify admin service; `AND`-ed into earn/redeem at the processing boundary (§5). Not in this
  registry, not duplicated here.
- **Not built now**: write-blocking triggers, per-request middleware re-resolution.

## 9. Decisions

**Resolved**
- ✅ **`campaign` is under `loyalty`** (FE audit: earn mechanics, not marketing-automation workflows).
- ✅ **Merchant overrides are platform-agnostic** (no platform column on merchant rows).
- ✅ **`lifecycle` types and `reward/promo_code` are features, not sub-features** (no parent feature).
- ✅ **No `platform_key` on the registry** — platform-specificity falls out of the scope chain
  (feature → plan → platform); `shopify_widget` is just granted at `platform_id=shopify` scope.
- ✅ **Three limitation dimensions** per feature: toggle (`enabled`), quota(s) (`limits` jsonb map),
  config (`config` jsonb), declared in the registry (§3.1). `limits` map replaces single `max_count`.
- ✅ **Quota value convention**: NULL = unlimited, 0 = none, N = limit.
- ✅ **Field-merge resolution** (not row-wins) so each scope stores only the dimensions/keys it changes.
- ✅ **Single registry table** (`feature_registry`, adjacency list with `node_type` + `parent_id`)
  instead of three typed tables; parent-type + leaf-only integrity enforced by triggers.
- ✅ **Volume / billing stays external** (Option B) — verified absent from this DB; the registry is
  feature-only, `AND`-ed with the Shopify admin service's billing gate at the BFF/processing boundary.
- ✅ **Shopify plan axis is flat on features** — Shopify tiers differ only by volume; feature *tiering*
  by plan is a standalone-platform behavior. §7 corrected accordingly.
- ✅ **Platform-level show/hide** for `forms`, `earn_factor`(+`multiplier`), `user_type`, `persona` is
  expressed as `platform_id=shopify` rows with `enabled=false` — no new mechanism.
- ✅ **Forced settings** use a platform-scope `config` value (§7.1), not per-field sub-features.

**Resolved (2026-06-24 implementation)**
- ✅ **Plan-name reconciliation** — confirmed by user: standalone/core = **Free/Starter/Growth/Premium**
  (feature-tiered). Shopify = Free/Essential/Standard/Growth (volume-only, flat on features). Both plan
  sets seeded with platform-prefixed keys (`core_*`, `shopify_*`).
- ✅ **New-group naming** — `earn` (rename of legacy `loyalty` group), `tier` split into its own group,
  and `workspace`/`member_intelligence`/`storefront` operational groups all seeded into `feature_registry`.
- ✅ **Default location** — defaults live in `feature_registry` (`default_enabled`/`default_limits`/
  `default_config`); plans store only deltas. Resolver applies the registry default as the base layer
  in platform-aware mode.
- ✅ **Resolver applied (field-merge)** — `p_platform DEFAULT NULL` (NULL = legacy, no registry default);
  impact analysis proved byte-identical to old row-wins for all live data before applying.

**Still open**
1. **`feature_config` link migration** — `feature_id` FK is additive-nullable and not yet backfilled;
   the resolver still reads `feature_group`/`feature_key` text. During the transition, platform/plan rows
   authored for the new taxonomy use **registry group names** (`earn`/`persona`/`storefront`/`lifecycle`),
   while legacy core merchant/plan rows keep the old `loyalty` group name. Decide when to backfill
   `feature_id`, rename legacy text rows (`loyalty`→`earn`/`tier`), and switch the resolver to FK-keyed
   matching. Add the `feature_config.feature_id → node_type IN ('feature','sub_feature')` guard trigger then.
2. **`merchant_plan_assignment` backfill** — no merchant is assigned to the new `core_*`/`shopify_*` plans
   yet (existing merchants remain on `enterprise`/`loyalty_only`). Core plan deltas are dormant catalog
   until merchants are assigned and queried with an explicit platform.
3. **`enabled` is `NOT NULL`** — a delta row cannot be "limits-only"; it always asserts an `enabled` value.
   Seeded delta rows set `enabled=true` to match the registry default. Consider making `enabled` nullable
   so a scope can override only `limits`/`config` and let `enabled` fall through.

---

*Next step after these are answered: draft the migration (registry tables + `platform` + scope
columns + `merchant_plan_assignment`) and the resolver update (platform-aware
`fn_merchant_feature_config` / `_enabled`), applied via Supabase MCP.*
