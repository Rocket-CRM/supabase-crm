# Ausiris RFP Gap Features — Implementation Summary

**Date:** 2026-07-13 / 2026-07-14  
**Project:** Supabase `wkevmsedchftztoolkmi` + loyalty-admin (`~/Documents/rocket/loyalty-admin`)  
**Plan:** `.cursor/plans/ausiris_rfp_backend_+_admin_b88cada1.plan.md` (do not treat this file as a substitute for the plan — this is what shipped)

This document consolidates everything built in the Ausiris RFP gap thread: schema, functions, crons, condition wiring, admin BFFs, loyalty-admin pages, Customer 360, and close-out docs. Per-domain detail lives in the linked requirement docs; this file is the end-to-end map.

---

## What shipped (five features)

| Feature | Purpose | Domain doc |
|---|---|---|
| Activity log + typed field registry | CDP-style member events with typed properties, UTM stamp, campaign resolution | `requirements/Activity_Attribution.md` |
| Acquisition attribution | Write-once UTM/campaign on `user_accounts` | same |
| Marketing campaigns + ROI | Campaign master, identifiers, U-shape (etc.) purchase attribution, ROI view | same |
| RFM scoring | Daily R/F/M quintiles + segment labels as a condition collection | `requirements/RFM_Scoring.md` |
| Funnels | Ordered journey stages as bound audiences + transition metrics | `requirements/Funnel.md` |

**Scale:** 11 new tables, 2 altered tables, ~18 new functions, 3 catalog/compiler edits, 2 pg_cron jobs, 4 new admin pages + Customer 360 / sidebar updates.

---

## Backend

### Phase 1 — Activity log + typed field registry

**Tables**

- `activity_type_master` — platform-standard (`merchant_id NULL`) + merchant custom. Seeds: `page_view`, `link_click`, `campaign_touch`.
- `activity_field_def` — typed registry: scope `activity_property` \| `attribution`; types string/number/boolean/date/timestamp/enum/entity_ref; `expose_to_conditions`.
- `activity_ledger` — user events with `properties`, dedicated UTM columns, `attribution`, `mkt_campaign_id`, `source`, `external_ref`. Purchases are **not** duplicated here.

**Write path**

- `fn_log_user_activity` — single chokepoint: validate type, type-check fields, resolve campaign identifier → stamp `mkt_campaign_id`, write ledger, write-once acquisition.
- `api_log_user_activity` — API-key wrapper for external integrators.

**Admin BFFs:** `bff_list_activity_types`, `bff_upsert_activity_type`, `bff_upsert_attribution_field`.

**AMP condition wiring**

- Whitelist: `activity_ledger` in `fn_amp_assert_collection`.
- Default time field: `occurred_at`.
- Catalog: `bff_get_workflow_collections` merges v4 extensions (dynamic activity types + exposed fields).
- Compiler: `prop__<type>__<key>` / `attr__<type>__<key>` → `fn_amp_build_json_field_clause`.

**Accepted gap:** `fn_amp_find_matching_users` realtime batch matching does not evaluate the new collections; hourly reconcile covers correctness.

### Phase 2 — Acquisition (UTM + campaign)

Write-once columns on `user_accounts` (no separate table):

- `acquisition_utm_source/medium/campaign/term/content`
- `acquisition_campaign_id` → `mkt_campaign`
- `acquisition_attribution` jsonb
- `acquired_at`

Written only when still NULL (same immutability as existing `acquisition_source`). Acquisition fields appended to the existing `user_accounts` condition collection.

Campaign keys at purchase time → logged as `campaign_touch` activities (not by altering `purchase_ledger`).

### Phase 3 — Marketing campaigns + ROI

**Tables**

- `mkt_campaign` — name, channel, status (`draft|active|paused|ended`), budget, window.
- `mkt_campaign_identifier` — children: `key_type` × `key_value` (+ `key_name` required when `key_type=custom`), unique per merchant on `(key_type, COALESCE(key_name,''), key_value)` (utm_campaign / voucher_code / line_param / link_token / custom).
- `mkt_purchase_attribution` — computed splits; unique `(purchase_id, campaign_id, model)`; recompute-safe.
- `mkt_config` — one row/merchant: `attribution_model` (default `u_shape`), `attribution_lookback_days` (30), watermark.

**Models:** u_shape (40/40/20-middle; 1 touch = 100%, 2 = 50/50), first_touch, last_touch, linear.

**Compute / report**

- Cron `mkt-attribution-compute` — `0 18 * * *` UTC → `fn_mkt_compute_purchase_attribution()`.
- View `v_mkt_campaign_roi` — attributed revenue vs budget + acquisition-cohort metrics.

**BFFs:** `bff_list_mkt_campaigns`, `bff_get_mkt_campaign_details`, `bff_upsert_mkt_campaign`, `bff_get_mkt_campaign_roi`, `bff_get_mkt_config`, `bff_upsert_mkt_config`, **`bff_report_mkt_campaigns`** (date-ranged detail + cross-campaign report; see analytics plan Phase 1).

### Phase 4 — RFM scoring

**Tables**

- `rfm_config` — recency source (purchase \| activity), window months, optional band thresholds, segment_map.
- `rfm_user_score` — 1:1 per user (not jsonb on `user_accounts`, to avoid CDC churn); R/F/M 1–5, segment, raws, `computed_at`.

**Compute**

- Cron `rfm-daily-compute` — `30 17 * * *` UTC → `fn_rfm_compute_scores()`.
- NTILE quintiles over **active** members only (`frequency > 0`); inactive → score 1.
- Default segment map includes catch-all **Regulars**.

**Condition collection:** `rfm_user_score` (whitelist + catalog); independent of audience feature — audiences just consume it.

**BFFs:** `bff_get_rfm_settings`, `bff_upsert_rfm_settings` (`p_run_now`), `bff_get_rfm_distribution`.

### Phase 5 — Funnels as special audiences

**Schema**

- `funnel_master`
- `amp_audience_master.funnel_id`, `funnel_sort_order` (stage = bound audience)
- `funnel_transition_ledger` (from/to stage, for conversion metrics)

**Reconcile**

- `fn_funnel_reconcile` — latest-stage-wins; soft-exit others; write transitions.
- Funnel-bound audiences skipped by normal dynamic resnapshot; `fn_funnel_reconcile_all` on the hourly AMP reconcile path.
- No monotonic mode in v1.

**BFFs:** `bff_list_funnels`, `bff_get_funnel_details`, `bff_upsert_funnel` (stages as children via audience create/update), `bff_delete_funnel`, `bff_get_funnel_metrics`.

### Customer 360 BFF

`bff_admin_get_member_360` extended with:

- `rfm` — segment + R/F/M + raws (when scored)
- `acquisition` — UTM + campaign + acquired_at
- `activity_stream` — merged `activity_ledger` events (`event_type = 'activity'`)
- `activity_counts.activity`

### Admin menu (DB)

| id | href | category | FE module → section |
|---|---|---|---|
| `marketing-campaigns` | `/marketing-campaigns` | loyalty | Marketing → Campaigns |
| `funnels` | `/funnels` | loyalty | Marketing → Campaigns |
| `rfm-settings` | `/rfm-settings` | loyalty | Marketing → Configure |
| `activity-types` | `/activity-types` | loyalty | Marketing → Configure |

All four consolidated under the Marketing module (2026-07-14): `rfm-settings` and
`activity-types` moved from `category='settings'` to `'loyalty'` (display_order 127/128)
so they render in the Marketing sidebar instead of Loyalty → Module Settings.

Permissions mirrored from roles that already have audience-builder access.

---

## Frontend (loyalty-admin)

Workspace: ported to the main checkout `~/Documents/rocket/loyalty-admin` (2026-07-14) — the original `~/Documents/rocket/loyalty-admin` copy is superseded. Patterns: server `page.tsx` → server actions (RPC) → client components; Polaris; `ActionResult` + toast; `loading.tsx` / `error.tsx`.

### New pages

| Route | What it does |
|---|---|
| `/marketing-campaigns` | List with ROI columns; form (fields + identifier child editor + performance panel); attribution settings modal (`mkt_config`) |
| `/funnels` | List; builder with ordered/reorderable stages, each stage reuses `ConditionGroupCard` + collections catalog; metrics table (entered / converted / rate / left) with 7/30/90d window |
| `/rfm-settings` | Enable, recency source, window, segment-map editor; distribution panel; Save & recompute now |
| `/activity-types` | Standard + custom types; typed property field registry (expose-to-conditions); attribution-field editor card (`bff_upsert_attribution_field`) |

### Modified

| Surface | Change |
|---|---|
| `/audience-builder` + workflow conditions | No structural FE change — new collections/fields appear via `bff_get_workflow_collections` |
| Customer 360 `ProfileSidebar` | RFM badge, acquisition line, Activity filter tab |
| `src/lib/sidebar-config.ts` | All four page ids in `MARKETING_IDS`; Marketing sections: Campaigns (campaigns + funnels), Configure (RFM + activity types) |

### Key FE files

```
src/app/(admin)/marketing-campaigns/{page,actions,campaigns-page-client,campaign-list,campaign-form,campaign-performance}.tsx
src/app/(admin)/funnels/{page,actions,funnels-page-client,funnel-list,funnel-builder}.tsx
src/app/(admin)/rfm-settings/{page,actions,rfm-settings-content}.tsx
src/app/(admin)/activity-types/{page,actions,activity-types-content,attribution-fields-card}.tsx
src/app/(admin)/customer-360/[userId]/{profile-sidebar,customer-360-detail}.tsx
src/lib/amp-conditions.ts   ← shared persisted-conditions ↔ AmpGroup conversion (audiences + funnel stages)
src/lib/sidebar-config.ts
```

---

## Crons (REGISTRY_RENDER)

| Job | Schedule (UTC) | Command |
|---|---|---|
| `mkt-attribution-compute` | `0 18 * * *` | `fn_mkt_compute_purchase_attribution()` |
| `rfm-daily-compute` | `30 17 * * *` | `fn_rfm_compute_scores()` |

Funnel reconcile rides the existing hourly `fn_amp_reconcile_dynamic_audiences` path (no third cron).

---

## Close-out artifacts

| Artifact | Role |
|---|---|
| `requirements/Activity_Attribution.md` | Activity log, acquisition, campaigns, ROI |
| `requirements/RFM_Scoring.md` | RFM config, compute, BFFs |
| `requirements/Funnel.md` | Funnel stages, reconcile, metrics |
| `requirements/domains/_index.md` | Three new domain pointer rows |
| `requirements/REGISTRY_SUPABASE.md` | Regenerated; sections Activity Log & Attribution / RFM / Funnel |
| `requirements/REGISTRY_RENDER.md` | Two new `C:` cron lines |
| `requirements/CHANGELOG.md` | 2026-07-13 bullet |
| `scripts/regen_registry_supabase.sql` | Domain patterns for the three new groups |

---

## Design decisions (locked)

1. **Feature-group-first naming** — e.g. `rfm_user_score`, `mkt_campaign`, not `user_rfm_score`.
2. **Acquisition on `user_accounts`** — one row per user, write-once; not a separate table; not derived at query time from ledger (backfills must not rewrite).
3. **Campaign identifiers as children** — many key types/values per campaign; uniqueness enforced across campaigns.
4. **Attribution model merchant-wide** in `mkt_config` — one purchase can credit multiple campaigns; model cannot vary per campaign.
5. **Default attribution model: U-shape** — balances first (acquisition) and last (convert) touch.
6. **RFM as separate table** — daily rewrite of `user_accounts` would flood CDC/Inngest; typed columns for condition indexes.
7. **Funnels = audiences with `funnel_id`** — reuse condition language and audience internals; latest-stage-wins only in v1.
8. **Purchases stay on `purchase_ledger`** — campaign presence at purchase → `campaign_touch` activity.

---

## Smoke / verification notes (from implementation)

- RFM: NTILE over active buyers only; catch-all Regulars → no NULL segments after recompute.
- Funnel BFFs: merchant context via JWT / simulated `x-merchant-id` header in SQL tests.
- FE actions: funnel list field is `member_count` (not `total_members`); ROI detail uses `campaign_id` from `v_mkt_campaign_roi`.
- Full `loyalty-admin` `tsc`/build blocked in-session by private GitHub npm registry (`@rocket-crm`); per-file syntax pass was clean — run `npm run build` where registry auth works.

---

## How to operate day-to-day

1. **Define activity types / fields** → `/activity-types` (or API via `api_log_user_activity`).
2. **Create campaigns + identifiers** → `/marketing-campaigns`; set U-shape lookback in Attribution settings.
3. **Log activities** → `fn_log_user_activity` / API; first attributed event stamps acquisition.
4. **ROI** → nightly attribution cron; list lifetime ROI columns; open campaign → **Performance** panel for date-ranged KPIs / drills (`bff_report_mkt_campaigns`). Cross-campaign: `/reports/marketing-campaigns`. Exec snapshot: `/reports/exec-overview`.
5. **RFM** → `/rfm-settings`; optional recompute now; use `rfm_user_score` in audiences/workflows; health report `/reports/rfm`.
6. **Funnels** → `/funnels` with stage conditions; metrics after reconcile (hourly or on save when active); report `/reports/funnels`.
7. **Acquisition / activity** → `/reports/acquisition`, `/reports/activity` (`bff_report_acquisition`).
8. **Member view** → Customer 360 RFM badge, acquisition, funnel stage, attributed campaigns, Activity tab.

---

## Analytics serving (2026-07-14)

Native loyalty-admin reports (no Metabase). Plan: `.cursor/plans/ausiris-analytics-dashboard-plan-20260714.md`.

| Item | Status |
|------|--------|
| A1–A5 campaign / acquisition / funnel / RFM reports | Shipped |
| A6 Exec overview `/reports/exec-overview` | Shipped (composes existing BFFs) |
| A7 Activity engagement `/reports/activity` | Shipped (`bff_report_acquisition` sections) |
| B4 Customer 360 polish | Shipped (BE + FE) |
| B5/B6 purchases/members report columns | Shipped (`bff_report_purchases*` / `bff_report_members*` + FE) |
