# Analytics (Reports and Dashboards)

Loyalty-admin report pages and the Home KPI strip: what each report shows, how it is filtered, and where its data is served from (BigQuery serving layer for core domains, Postgres report functions for marketing reports, embedded Metabase for custom dashboards).

Owner surfaces: loyalty-admin (Home, Analytics module: Executive overview, Operations, Marketing & growth, Tools)

## Concept

Merchants need to see what their loyalty program is doing — how many points are earned and burned, what is redeemed, where members buy, and who is joining — without querying data themselves. Analytics packages that as a fixed set of **reports**, one per business domain, each filterable by date range and domain-specific filters. Core operational reports read a pre-aggregated analytics copy of the ledgers so heavy date-range queries never load the operational database.

**Mental model — every chart is a table plus three choices.** Each chart starts from one data table (one row per purchase, per wallet movement, per redemption, per member) and is defined by three decisions: the **metric** (what is summed or counted — usually the Y axis), the **group-by** (what rows are bucketed by — day/week/month, store, reward, source), and the **filter** (which rows are included — almost always a date range, plus fields like source or gender). The same table yields different charts by changing those three; bar, line, pie, or funnel is only a display choice. Group-by can be multi-dimensional: the earn/burn trend groups by time bucket *and* movement type. Reading or specifying any chart in these terms is the canonical way to discuss it.

Core objects:

- **Report** — One page covering one domain; a set of charts and KPI cards over the same filters, plus a row drill-down. Some reports split into tabs (Points: overview, movement, snapshot, reconciliation; Members: overview, acquisition).
- **Chart** — One card on a report: data table + metric + group-by + filter.
- **Frequency** — The time grain of the group-by on trend charts (day, week, month, quarter).
- **Row drill-down** — The underlying table behind a report's charts, paginated and filterable, so a number can be traced to its rows.
- **Accounting views** — Two points views built for finance reconciliation rather than trend insight: **movement** (for one calendar month: opening balance, earned, burned, expired, closing balance, by tier) and **snapshot** (balances and liability as of one date).
- **Executive overview** — One composite page summarising purchases, redemptions, members, and points.
- **Email CSV export** — Large extracts that reuse a report's filters but are built in the background and emailed as a download link, instead of loading in the page.
- **Analytics dashboards** — Merchant-specific embedded Metabase dashboards listed in a menu configured by superadmin; outside the fixed report set.

Every query is scoped to the signed-in admin's merchant; the client cannot choose another merchant. Out of scope here: AMP workflow analytics (AMP_Workflows.md), CS QA dashboards (CS_Analytics.md), and member-facing analytics.

## Rules

- **No BQ-via-Postgres for wave-1 charts** — Dashboard KPIs and report pages do not call Postgres RPCs that proxy BigQuery; they call Edge `analytics-query` only.
- **Merchant resolution (admin)** — If `x-merchant-id` is present and the user is an active admin for that merchant, use it; else use `user.app_metadata.active_merchant_id` when valid; else first active `admin_users` row for the auth user. Missing merchant → 403. Same priority chain as Metabase embed.
- **JWT** — Requests without a valid admin Bearer JWT → 401. Edge deploy uses `verify_jwt: false` but validates JWT inside `resolveAuth` (same pattern as other admin edges).
- **Report id** — Must match `segment.segment[.rows]` or `health`; unknown id → 404.
- **Date range** — Range reports require `from` and `to` (ISO timestamps); `to` must be after `from`; span capped at **400 days** → 400-day violation → 400.
- **Frequency** — `day` | `week` | `month` | `quarter` (default `day`) for time-bucketed charts.
- **Pagination** — Row reports default limit 100, max **1000** per request; offset ≥ 0.
- **Points movement** — Report `currency.points_movement` requires `month` (`YYYY-MM`); optional `filters.currency` (default `points`). Every wallet post in the month falls in exactly one component: **earned** (positive), **expired** (expiry source), or **burned** (any other debit). Rows group by the member's tier at month end; ending = brought forward + earned − burned − expired.
- **Points snapshot** — Reports `currency.points_snapshot` / `.rows` require `as_of` (`YYYY-MM-DD`). Closing balances are ledger sums through end-of-day **Asia/Bangkok**; snapshot row “current” column reads live wallet — intentional diff vs closing.
- **Home KPIs** — Report `home.metrics` may omit `from`/`to`; server defaults to **last 30 days** through now.
- **Composite overview** — Report `overview.loyalty` runs purchases, redemptions, members, and points builders in parallel; partial failures return null for failed legs and collect error strings unless all four fail (then 500).
- **BigQuery billing guard** — Default `maximumBytesBilled` ≈ 15 GB per query; health probe uses a lower cap. BQ API errors and timeouts surface as 500 with message in envelope.
- **Email CSV export** — Allowed extract ids enforced by `fn_analytics_export_allowed`; row cap **200,000**; signed Storage link emailed to the requesting admin (7-day TTL). Does not replace in-chart CSV buttons on pages.

## Journeys

### Admin journey

| Knob | Effect |
| --- | --- |
| Date range | Filter on every chart and the drill-down; span capped at 400 days |
| Frequency | Time-bucket group-by on trend charts (day / week / month / quarter) |
| Domain filters | Narrow rows before aggregation (e.g. Points: source, component, earn vs burn; Purchases: store, channel, product) |
| Month (Points → Movement) | Selects the calendar month to roll forward |
| As-of date (Points → Snapshot) | Selects the closing date for balances and liability |
| Email CSV | Emails the report's full rows for the current filters (up to 200,000) |

Report menu visibility follows the admin's menu permissions; a group with no permitted report is hidden.

| Menu group → page | Owning repo | Served by |
| --- | --- | --- |
| Home (KPI strip) | loyalty-admin | `analytics-query` → `home.metrics` |
| Executive overview | loyalty-admin | `analytics-query` → `overview.loyalty` |
| Operations → Points (Overview, Movement, Snapshot tabs) | loyalty-admin | `analytics-query` → `currency.points_overview[.rows]`, `currency.points_movement`, `currency.points_snapshot[.rows]`; drift drill `bff_report_points_drift_rows` |
| Operations → Points (Reconciliation tab) | loyalty-admin | `bff_report_wallet_discount_recon[_rows]` |
| Operations → Redemptions | loyalty-admin | `analytics-query` → `rewards.redemptions[.rows]` |
| Operations → Purchases | loyalty-admin | `analytics-query` → `transactions.purchases[.rows]` |
| Marketing & growth → Members (Overview tab) | loyalty-admin | `analytics-query` → `members.overview[.rows]` |
| Marketing & growth → Members (Acquisition tab), Activity engagement | loyalty-admin | `bff_report_acquisition` |
| Marketing & growth → Marketing campaign ROI | loyalty-admin | `bff_report_mkt_campaigns` |
| Marketing & growth → Funnel / journey performance | loyalty-admin | `bff_get_funnel_metrics` |
| Marketing & growth → RFM health | loyalty-admin | `bff_get_rfm_distribution`, `bff_report_rfm_segment[_rows]` |
| Marketing & growth → Audiences | loyalty-admin | `bff_report_audience`, `bff_report_audience_compare` |
| Marketing & growth → Surveys | loyalty-admin | `bff_report_surveys` |
| Tools → Analytics dashboards | loyalty-admin | `bff_get_analytics_menu` + Edge `metabase-embed` |
| Any report → Email CSV | loyalty-admin | `bff_admin_start_analytics_export`, `bff_admin_get_analytics_export_progress` |

1. Open **Home**: KPI strip for the last 30 days — members added, points earned, redeemers, driven revenue, total members.
2. Open **Executive overview** for a one-page summary of purchases, redemptions, members, and points over the chosen range.
3. Open an **Operations** report:
   - **Points → Overview** — earned, burned, expired, net change, and outstanding liability; earn/burn trend by time bucket and movement type; source mix; drill-down to wallet posts.
   - **Points → Movement** — pick a month; table of brought-forward, earned, burned, expired, and ending balance per tier, for reconciling the month against the ledger.
   - **Points → Snapshot** — pick an as-of date; closing balance, holders, and liability at end of that day, with per-member rows showing closing vs current balance.
   - **Points → Reconciliation** — checks that wallet-discount entries match the purchase ledger.
   - **Redemptions** — volume, success rate, pending fulfilment, and redemptions per reward.
   - **Purchases** — net sales, orders, average order value, buyers; breakdowns by store, channel, and product.
4. Open a **Marketing & growth** report:
   - **Members** — sign-up trend, acquisition source, age and gender breakdown, profile completion, cohort retention; **Acquisition** tab for lead-source signups, activation, and cohort revenue.
   - **Marketing campaign ROI**, **Funnel / journey performance**, **RFM health**, **Audiences**, **Activity engagement** — see the owning domain docs for their metrics.
   - **Surveys** — completed submissions, unique respondents, and the share of answers per option for each question.
5. Adjust date range, frequency, and domain filters; all charts on the page re-query together. Open the drill-down to inspect rows behind a number.
6. Optional **Email CSV**: same filters; progress shows in the page, and a download link (valid 7 days) arrives by email when the export completes.
7. Open **Tools → Analytics dashboards** to pick a merchant-specific embedded dashboard; entries without a configured dashboard show as disabled.
8. Errors show as a toast or inline error state: session expired, no merchant access, invalid range / month / as-of date, or a data-source failure.

### Member journey

None — analytics are admin-only.

## System

### Data model

BigQuery project **`rocket-prod-analytics`** (override via `BQ_PROJECT_ID` / service account JSON).

| Layer | Dataset | Role |
| --- | --- | --- |
| Serving facts | `serving_loyalty` | Hot paths: `purchase_ledger`, `wallet_ledger`, redemption ledger tables, `user_accounts`, … — partitioned by event date, clustered by `merchant_id` where applicable |
| Dimensions | `raw_supabase_prod` | Small synced masters (store, tier, …) joined from report SQL |

Postgres is not the chart store. Export pipeline reuses **`bulk_import_batches`** with `import_type = analytics_export` for batch status and Storage paths.

Platform guidance for partition/cluster design: `docs/BQ_PARTITION_AND_CLUSTERING.md`.

### Functions

| Artifact | Role |
| --- | --- |
| Edge **`analytics-query`** | POST-only router: `resolveAuth` → `parseBody` → registry handler → BQ REST |
| **`reports/registry.ts`** | Maps report id → handler (chart/rows/composite/home/health) |
| **`lib/auth.ts`** | Admin JWT + merchant resolution via `admin_users` |
| **`lib/bq.ts`** | Service-account token, parameterized queries, bytes cap |
| **`lib/params.ts`** | Body validation (range, month, as_of, frequency, pagination) |
| **`bff_admin_start_analytics_export`** | Validates extract id, creates export batch, triggers Inngest |
| **`bff_admin_get_analytics_export_progress`** | Poll batch status for UI |
| **`fn_analytics_export_allowed`** | Allow-list of extract ids |
| **`fn_analytics_export_pg_count`** / **`fn_analytics_export_pg_chunk`** | PG-backed extracts (activity, surveys, RFM, funnels, mkt, AMP) |
| **Postgres report BFFs** (`bff_report_acquisition`, `bff_report_mkt_campaigns`, `bff_get_funnel_metrics`, `bff_get_rfm_distribution`, `bff_report_rfm_segment[_rows]`, `bff_report_audience[_compare]`, `bff_report_surveys`, `bff_report_wallet_discount_recon[_rows]`, `bff_report_points_drift_rows`) | Marketing & growth reports (except Members overview) and points reconciliation/drift; query Postgres directly, not BigQuery |
| **`bff_get_analytics_menu`** + Edge **`metabase-embed`** | Analytics dashboards menu (superadmin-configured) and signed Metabase embed URL |

Canonical source: `supabase/functions/analytics-query/` in the **loyalty-admin** repo (not supabase-crm). Live deploy: Supabase project `wkevmsedchftztoolkmi`, slug `analytics-query`, ACTIVE (JWT checked in-function).

**Report catalog** (verified against registry source):

| Report id | Purpose |
| --- | --- |
| `transactions.purchases` | Purchases time-series chart |
| `transactions.purchases.rows` | Purchase row detail |
| `rewards.redemptions` | Redemptions chart (incl. coupon-used metrics where shipped) |
| `rewards.redemptions.rows` | Redemption rows |
| `members.overview` | Member acquisition / activity chart |
| `members.overview.rows` | Member rows |
| `currency.points_overview` | Points overview chart |
| `currency.points_overview.rows` | Points ledger rows |
| `currency.points_movement` | Points movement for calendar month |
| `currency.points_snapshot` | Balances as-of date (ledger EOD Bangkok) |
| `currency.points_snapshot.rows` | Snapshot rows (closing vs live wallet diff) |
| `home.metrics` | Home strip: member_added, earn, redeemer, driven_revenue, total_members |
| `overview.loyalty` | Composite of purchases + redemptions + members + points |
| `health` | Liveness + sample 7d purchase count + available report list |

### Flows

**Interactive dashboard (sync)**

```
loyalty-admin server action
  → POST Edge analytics-query (Authorization + optional x-merchant-id)
  → resolveAuth → named report handler
  → BigQuery REST (asia-southeast1 default)
  → JSON success envelope → UI chart/table
```

**Email CSV export (async)**

```
loyalty-admin Email CSV
  → bff_admin_start_analytics_export(extract_id, from, to, filters)
  → bulk_import_batches (import_type = analytics_export)
  → Inngest export/analytics-csv on admin-user-export-csv (crm-user-export)
  → BQ extract (Operations / Members facts) OR fn_analytics_export_pg_chunk loops
  → Storage bucket exports/ + messaging-service email (7-day signed URL)
```

| Extract id | Engine | Grain |
| --- | --- | --- |
| `purchases` | BQ | `purchase_ledger` transaction |
| `redemptions` | BQ | Redemption ledger row |
| `points` | BQ | `wallet_ledger` post |
| `members` | BQ | Member acquired in range |
| `activity` | PG | `activity_upload_ledger` |
| `surveys` | PG | `form_responses` answer |
| `rfm` | PG | `rfm_user_score` (optional `filters.segment`) |
| `funnels` | PG | `funnel_transition_ledger` |
| `mkt_campaigns` | PG | `mkt_purchase_attribution` |
| `amp` | PG | `workflow_log` |

Cap: 200,000 rows per export.

### External services

| Service | Role |
| --- | --- |
| Google BigQuery | Serving dataset queries; credentials via Edge secret `BQ_SERVICE_ACCOUNT_JSON` |
| Supabase Edge | Hosts `analytics-query` |
| Supabase Storage | Export CSV objects under `exports/` |
| Inngest (`crm-user-export`) | Runs `export/analytics-csv` worker on `admin-user-export-csv` |
| Messaging service | Delivers export email with signed link |

Edge env: `BQ_SERVICE_ACCOUNT_JSON`, `BQ_PROJECT_ID` (default `rocket-prod-analytics`), `BQ_LOCATION` (default `asia-southeast1`), plus standard Supabase URL/keys for auth client.

### Known gaps

- **Registry** — `REGISTRY_RENDER.md` now lists `analytics-query`; regenerate discipline applies on future edge changes.
- **Data platform** — Landing tables in `raw_supabase_prod` may be less partitioned than `serving_loyalty`; new reports should prefer serving facts for merchant+date filters.
- **Scope** — The BigQuery path covers Home, Executive overview, Points, Redemptions, Purchases, and Members overview only. Funnels, RFM, campaign ROI, audiences, activity, acquisition, and surveys run on Postgres report BFFs; AMP analytics stays in AMP_Workflows.md.
- **Registry** — `bff_report_audience` / `bff_report_audience_compare` exist live but are missing from `REGISTRY_SUPABASE.md`.

## Related

- **Admin_Panel.md** — Admin menu permissions that decide which report groups an admin sees.
- **Forms.md** — Survey templates and submissions behind the Surveys report.
- **AMP_Workflows.md** — Workflow and audience analytics BFFs (`bff_amp_analytics_*`).
- **CS_Analytics.md** — CS product metrics (`cs_bff_get_analytics_*`).
- **RFM_Scoring.md** — RFM scores; PG export extract id `rfm`.
- **Currency.md** — Wallet ledger semantics behind points reports and snapshot vs live wallet.
