# Ausiris — Analytics & Dashboard Serving Plan

**Date:** 2026-07-14  
**Status:** **Phases 1–7 + B5/B6 shipped 2026-07-14** — A1–A7 + B4–B6 live.  
**Context:** Close the reporting UI deferred from Ausiris RFP gap features (`docs/AUSIRIS_RFP_GAP_FEATURES_IMPLEMENTATION.md`). Data model, crons, and inline KPIs already shipped; this plan covers **serving** analytics to admins.

**Related:** `.cursor/plans/ausiris-rfp-gap-features-plan-20260713.md` (explicitly deferred “ROI / exec dashboard UI”).

---

## Locked decisions

| Decision | Choice |
|----------|--------|
| Delivery surface | **Native loyalty-admin only** (Polaris + `bff_*`). No Metabase for this work — treat Metabase analytics menu as legacy. |
| Scope | Reporting / dashboards that prove campaign ROI, acquisition, funnels, RFM — plus campaign detail depth and light 360 polish. |
| Campaign ↔ activity model | Keep stamp-on-event (see §BE). Do **not** add static campaign ↔ activity-type joins. |
| Config vs report | Keep existing config pages (`/marketing-campaigns`, `/funnels`, `/rfm-settings`); add or deepen **report/detail** surfaces for decide-and-export. |
| ROI on partial date ranges | **No ROI ratio for partial ranges.** ROI (vs budget) is shown only when the selected range covers the campaign's full window (or campaign has ended). For partial ranges show attributed revenue + budget side-by-side, no ratio. No budget proration in v1. |
| Acquisition revenue semantics | **Cohort-based:** members *acquired in-period* → all their completed-purchase revenue to date. Same definition in A1 and A3. (In-period revenue from all-time acquirees is a different question — not v1.) |
| Report freshness | Every analytics surface shows "data as of" — attribution watermark from `mkt_config` (A1/A2), `computed_at` (A5/B3), reconcile time (A4). |
| CSV export | Synchronous BFF-paginated download for v1 report tables (bounded pages). Do not invent a new async path; if any export needs full-dataset scale, ride the customer-export-worker pattern (`.cursor/plans/customer-export-worker-plan-20260705.md`) as a follow-up. |
| Serving path | **Consolidated BFFs — no direct PostgREST from FE.** Direct table/view queries with the admin token were considered and rejected: merchant resolution (multi-merchant header/JWT chain) and `check_admin_permission()` live inside functions, RLS is a safety net not the primary boundary, and PostgREST aggregates are disabled while these pages are almost entirely aggregation. Cap: **max one report BFF per page; ~3 new BFFs total** (see §C BFF budget) — extend existing functions everywhere else. |

---

## What already shipped (do not rebuild)

### Data / compute

- Marketing campaigns + identifiers + `mkt_purchase_attribution` + `v_mkt_campaign_roi`
- Crons: `mkt-attribution-compute`, `rfm-daily-compute`, funnel reconcile on AMP path
- BFFs: list/get/upsert campaigns, `bff_get_mkt_campaign_roi`, funnel metrics, RFM distribution, extended `bff_admin_get_member_360`

### Config UI (inline metrics only)

| Page | Has today |
|------|-----------|
| `/marketing-campaigns` | List with ROI columns; edit form; identifier editor; **Performance** KPI strip (from list-row ROI) |
| `/funnels` | Builder + stage metrics table (7/30/90d) |
| `/rfm-settings` | Config + distribution panel |
| Customer 360 | RFM badge, acquisition line, Activity tab/stream |

### Customer 360 — status: **done for v1**

Already wired BE + FE:

- RFM segment + R/F/M
- Acquisition (campaign / UTM / legacy source + date)
- Activity filter + `activity_ledger` stream

Optional polish (Phase B, not blockers) listed under §Enhancements.

---

## Gap vs RFP

Admins can **configure** campaigns / funnels / RFM and see snapshots. They still cannot fully **serve** date-ranged compare, drill tables, and export for:

1. Campaign ROI (cross-campaign and deep per-campaign)
2. Lead source / acquisition performance
3. Funnel journey conversion (report-grade)
4. RFM health for marketing action

---

## A. New / deepened pages (build list)

### A1. Marketing Campaign performance detail *(highest priority)*

**Problem:** Click-in is an edit form + lifetime KPI strip. `bff_get_mkt_campaign_details` returns only campaign + identifiers. No date range, charts, or attributed purchase/member/activity lists.

**Target:** Same click-in (form + **Performance** section/tab) or dedicated `/marketing-campaigns/[id]` — either is fine; prefer deepening the existing form first to avoid IA churn.

| Layer | Spec |
|-------|------|
| Filters | Date range (required), optional attribution model display (merchant default) |
| KPIs | Attributed revenue, attributed purchases, acquired members, acquisition revenue (cohort — see Locked decisions), ROI vs budget (full-window ranges only — see Locked decisions) |
| Freshness | "Data as of" from `mkt_config` attribution watermark |
| Charts | Attributed revenue over time; optional touch volume stamped to campaign |
| Tables | (1) Attributed purchases (2) Acquired members (3) Recent activities with `mkt_campaign_id` = this campaign |
| Actions | CSV export per table; link row → Customer 360 / purchase |
| BE | `bff_report_mkt_campaigns` detail mode (see §C BFF budget) — one function, `section`-switched: ranged ROI summary + paginated drill rows (purchases / members / activities). Do not overload `bff_get_mkt_campaign_details` with analytics — keep edit get lean. |

### A2. Marketing Campaign ROI report (cross-campaign)

**Route (suggested):** `/reports/marketing-campaigns`  
**Nav:** Marketing or Reports module (native sidebar — not Metabase menu).

| Layer | Spec |
|-------|------|
| KPIs | Total attributed revenue, budget sum, blended ROI, purchases, acquired members. **Double-count guard:** multi-touch splits one purchase across campaigns — header purchase count must be `count(DISTINCT purchase_id)` over the attribution set, never a sum of per-campaign counts. Revenue sums are safe (splits sum to purchase amount). |
| Charts | Revenue vs budget by campaign; ROI by channel; revenue over time |
| Table | Campaign, channel, status, window, budget, attributed revenue, purchases, acquired members, acquisition revenue, ROI |
| Filters | Date, channel, status |
| Drill | Open A1 detail |
| BE | Same `bff_report_mkt_campaigns`, cross-campaign mode (no `campaign_id` filter) — see §C BFF budget |

### A3. Acquisition / Lead Source report

**Route:** `/reports/acquisition`

| Layer | Spec |
|-------|------|
| KPIs | New members with attribution, % attributed, top source, first-purchase conversion, acquisition revenue |
| Charts | Signups by UTM source/medium/campaign; campaign mix; time-to-first-purchase |
| Table | Source dims + campaign, new members, activated, revenue, AOV |
| Drill | Member list → 360 |
| BE | `bff_report_acquisition` (see §C BFF budget) — profile acquisition fields + purchases |

### A4. Funnel / Journey performance report

**Route:** `/reports/funnels`  
Keep `/funnels` as builder; this page is compare / export.

| Layer | Spec |
|-------|------|
| KPIs | In-funnel members, headline conversion, drop-off |
| Charts | Stage funnel; conversion rates; transitions over time |
| Table | Stage, current, entered, converted, rate, left |
| Filters | Funnel, date/window (custom, not only 7/30/90) |
| BE | **Extend** `bff_get_funnel_metrics` (list mode + custom window + optional series) — no new BFF; see §C BFF budget |

### A5. RFM Health report

**Route:** `/reports/rfm`  
Keep `/rfm-settings` as config.

| Layer | Spec |
|-------|------|
| KPIs | Scored members, risk pool size, avg R/F/M |
| Charts | Segment distribution; optional R×F heatmap; segment → revenue |
| Table | Segment, count, %, avg spend/orders, revenue share |
| Window semantics | Segment membership is **as-of latest compute** (`computed_at`); revenue joins use the **report date range**. Two different windows by design — label both in the UI. |
| Actions | Open as audience / export |
| BE | **Extend** `bff_get_rfm_distribution` (segment × revenue rollup, `computed_at`, coverage) — no new BFF; see §C BFF budget |

### A6. CDP Exec Overview *(in scope — approved 2026-07-14)*

Single native page composing cards from A2–A5 BFFs (new members + attribution coverage, top campaigns by ROI, default funnel conversion, RFM risk pool). No Metabase.

### A7. Activity engagement report *(in scope — approved 2026-07-14)*

Volume by activity type, members with activity but no purchase. Supports CDP story; lower RFP urgency than A1–A5.

---

## B. Enhancements to existing surfaces

| # | Surface | Enhancement | Priority |
|---|---------|-------------|----------|
| B1 | `/marketing-campaigns` list | Period context for ROI columns if list becomes period-aware; “Open performance” deep-link; CSV | With A1/A2 |
| B2 | `/funnels` metrics | Custom date range; CSV; small stage chart | With A4 |
| B3 | `/rfm-settings` distribution | Click segment → export/audience; show `computed_at` + coverage % | With A5 |
| B4 | Customer 360 | Show attributed campaigns on recent purchases; show campaign stamp on activity rows; optional current funnel stage; links to campaign/RFM | Phase B |
| B5 | Purchases report (`bff_report_purchases`) | Filters/columns: attributed campaign, UTM dims | Phase B |
| B6 | Members report (`bff_report_members`) | Columns: acquisition, RFM segment, funnel stage | Phase B |
| B7 | Audience / segment performance (if/when built from loyalty reports brief) | Treat RFM segments + funnel stages as segment types | Later |
| B8 | Naming / IA | Clearly separate **Marketing campaigns (mkt_*)** from **AMP workflow “campaigns”** and loyalty `campaign_master` | **Phase 1** — A1/A2 put “campaign” in a second nav location; settle copy before, not after |

**Explicitly out:** Wiring or expanding Metabase `admin_analytics_menu` entries for these features.

---

## C. Backend matter — campaign ↔ activities

### Current model (correct — keep)

1. Campaign has **many identifiers** (`mkt_campaign_identifier`: key_type × key_value, unique per merchant).
2. `fn_log_user_activity` resolves identifier → stamps **`activity_ledger.mkt_campaign_id`** (at most **one campaign per activity event**).
3. Purchases get rows in **`mkt_purchase_attribution`** (multi-touch may split one purchase across campaigns).

| Question | Answer |
|----------|--------|
| Can one campaign link to multiple activities? | **Yes** — many activity **events** over time. |
| Should it? | **Yes** — required for omnichannel ROI and journey measurement. |
| Bound to specific activity **types**? | **No** — any type carrying a matching identifier is stamped. |
| One activity event → many campaigns? | **No** (single stamp). |

### Do not build

- Static M:N table campaign ↔ activity_type for v1.
- Requiring admins to “attach” activity types to a campaign for attribution to work.

Reporting may **filter** by activity type later without changing the stamp model.

### BE work — BFF budget (consolidated)

**Rule: max one report BFF per page; extend existing functions everywhere else. Net-new functions: 2.**

All new report BFFs follow the existing report signature (`bff_report_purchases` precedent): `(p_from timestamptz, p_to timestamptz, p_frequency text, p_filters jsonb)` — with `p_filters` carrying `section` (kpis \| series \| table \| drill_purchases \| drill_members \| drill_activities), campaign/funnel scoping, and pagination. One function serves KPIs, charts, tables, and CSV pages for its page.

| Function | Status | Serves |
|----------|--------|--------|
| `bff_report_mkt_campaigns` | **New** | A1 **and** A2 — `p_filters.campaign_id` set = detail mode (drill sections); unset = cross-campaign table/KPIs. Period math: `mkt_purchase_attribution` → `purchase_ledger` on purchase date (verified live: `v_mkt_campaign_roi` is lifetime vs full budget — hence the partial-range ROI rule in Locked decisions). |
| `bff_report_acquisition` | **New** | A3 — profile acquisition fields + purchases |
| `bff_get_funnel_metrics` | **Extend** | A4/B2 — add custom window (from/to), multi-funnel list mode, optional time series. Additive params with defaults; existing `/funnels` callers unaffected. |
| `bff_get_rfm_distribution` | **Extend** | A5/B3 — add optional segment × revenue rollup + `computed_at`/coverage. Additive params. |
| `bff_report_purchases` / `bff_report_members` | **Extend** | B5/B6 — new filter keys + columns via existing `p_filters` jsonb; no signature change. |
| `bff_admin_get_member_360` | **Extend** | B4 — attributed campaigns on purchases, campaign stamp on activity rows. |

A6 Exec Overview (if approved) composes the functions above — **no new BFF**.

No change to identifier resolution or attribution cron logic unless period math forces a clearer watermark/API contract.

---

## D. Build order (recommended)

| Phase | Items | Outcome |
|-------|--------|---------|
| **1** | A1 campaign performance detail + supporting BFFs | RFP demo: open campaign → prove ROI with drill tables |
| **2** | A2 cross-campaign ROI report | Compare campaigns / channels |
| **3** | A3 acquisition report | Lead source story |
| **4** | A4 funnel report + B2 | Journey conversion serve |
| **5** | A5 RFM health + B3 | Risk / value segments actionable |
| **6** | B4–B6 | 360 + existing reports enriched |
| **7** | A6 + A7 (approved, in scope) | Exec overview / activity engagement — A6 composes existing report BFFs (no new BFF); A7 may need one activity rollup section added to an existing report BFF, not a new function |

---

## E. Out of scope

- Metabase dashboards or menu wiring for Ausiris
- New attribution models / recompute engine changes (unless required for period-correct ROI)
- Churn product (use RFM + existing workflows)
- Replacing all legacy Metabase loyalty boards
- Full loyalty-reports marketing brief (10 reports) — only the Ausiris-related slices above

---

## F. Approval checklist — **APPROVED 2026-07-14**

- [x] Native-only (no Metabase) for this plan  
- [x] A1 deepen existing campaign click-in (vs new `[id]` route)  
- [x] Phase 1 = A1 only (plus B8 naming/copy), then A2… as sequenced  
- [x] Customer 360 v1 accepted as done; B4 is polish  
- [x] Campaign ↔ multi-activity via stamps (no activity-type link table)  
- [x] ROI shown only for full-window date ranges; no budget proration (Locked decisions)  
- [x] Acquisition revenue = cohort semantics (acquired in-period → lifetime revenue)  
- [x] CSV = synchronous BFF-paginated download for v1  
- [x] Serving via consolidated BFFs (2 net-new: `bff_report_mkt_campaigns`, `bff_report_acquisition`); no direct PostgREST from FE  
- [x] A6 Exec Overview and A7 Activity engagement **both included** (Phase 7)  

**Next exact step after approval:** Spec A1 BFF contracts (request/response JSON) + FE Performance section wireframe, then implement BE → FE.

---

## G. Implementation handoff notes (for the fresh thread)

- **Two workspaces:** BE = this Supabase project (`wkevmsedchftztoolkmi`, all DB work via Supabase MCP `apply_migration` / `execute_sql`); FE = `~/Documents/rocket/loyalty-admin` (Next.js: server `page.tsx` → server actions calling RPC → client components; Polaris; `ActionResult` + toast; `loading.tsx` / `error.tsx`).
- **Signature precedent:** new report BFFs copy `bff_report_purchases(p_from timestamptz, p_to timestamptz, p_frequency text, p_filters jsonb)`.
- **Conventions to load in the implementation thread:** `10-function-conventions.mdc` (BFF skeleton), `11-auth-conventions.mdc` (`get_current_merchant_id()`, permission checks), `09-db-conventions.mdc` if any view/index is added.
- **Nav:** new `/reports/*` pages need `admin_menu` rows + role permissions (mirror the marketing-campaigns rows added in the RFP gap build) + `src/lib/sidebar-config.ts`.
- **Known FE caveat:** full `loyalty-admin` `tsc`/build was blocked in a prior session by the private npm registry (`@rocket-crm`) — run `npm run build` where registry auth works; per-file syntax checks otherwise.
- **What shipped already** (do not rebuild): see §"What already shipped" + `docs/AUSIRIS_RFP_GAP_FEATURES_IMPLEMENTATION.md`.
