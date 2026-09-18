# Analytics (Loyalty Admin → BigQuery)

Loyalty-admin operational dashboards read pre-aggregated **serving** data in BigQuery via Edge `analytics-query` — not live Postgres scans for chart KPIs.

Owner surfaces: loyalty-admin (Home, Executive overview, Transactions, Rewards, Members, Currency analytics)

## Concept

Merchants need fast, filterable loyalty KPIs (purchases, redemptions, members, points) without hammering the operational Postgres database. Wave-1 **loyalty analytics** answers that by treating each dashboard as a **named report**: the admin UI sends a stable report id plus date filters; an Edge function resolves the signed-in merchant, runs parameterized SQL against a BigQuery **serving** dataset, and returns JSON for charts or paginated row tables.

Core objects:

- **Named report** — Stable id (e.g. home KPI strip, purchases chart, purchases row drill-down) mapped to one SQL builder; chart ids often pair with a `.rows` sibling for tables.
- **Tenant guard** — Every query is scoped to one `merchant_id` derived from the admin session; the client cannot substitute another merchant.
- **Serving layer** — Partitioned fact tables in BigQuery (`purchase_ledger`, `wallet_ledger`, redemption facts, `user_accounts`, …) plus small dimension tables synced from Postgres when joins need store/tier masters.
- **Interactive charts vs email CSV** — Charts and in-page row loads stay on the Edge → BQ path; large **email CSV** extracts reuse page filters but queue through Postgres BFFs, Inngest, and either BQ or PG chunk readers (separate pipeline, same extract ids where applicable).

Out of scope here: AMP workflow stats (`bff_amp_analytics_*`), CS QA dashboards (`cs_bff_get_analytics_*`), Metabase embeds (`Admin_Panel.md`), and member-facing analytics.

## Rules

- **No BQ-via-Postgres for wave-1 charts** — Dashboard KPIs and report pages do not call Postgres RPCs that proxy BigQuery; they call Edge `analytics-query` only.
- **Merchant resolution (admin)** — If `x-merchant-id` is present and the user is an active admin for that merchant, use it; else use `user.app_metadata.active_merchant_id` when valid; else first active `admin_users` row for the auth user. Missing merchant → 403. Same priority chain as Metabase embed.
- **JWT** — Requests without a valid admin Bearer JWT → 401. Edge deploy uses `verify_jwt: false` but validates JWT inside `resolveAuth` (same pattern as other admin edges).
- **Report id** — Must match `segment.segment[.rows]` or `health`; unknown id → 404.
- **Date range** — Range reports require `from` and `to` (ISO timestamps); `to` must be after `from`; span capped at **400 days** → 400-day violation → 400.
- **Frequency** — `day` | `week` | `month` | `quarter` (default `day`) for time-bucketed charts.
- **Pagination** — Row reports default limit 100, max **1000** per request; offset ≥ 0.
- **Points movement** — Report `currency.points_movement` requires `month` (`YYYY-MM`); optional `filters.currency` (default `points`).
- **Points snapshot** — Reports `currency.points_snapshot` / `.rows` require `as_of` (`YYYY-MM-DD`). Closing balances are ledger sums through end-of-day **Asia/Bangkok**; snapshot row “current” column reads live wallet — intentional diff vs closing.
- **Home KPIs** — Report `home.metrics` may omit `from`/`to`; server defaults to **last 30 days** through now.
- **Composite overview** — Report `overview.loyalty` runs purchases, redemptions, members, and points builders in parallel; partial failures return null for failed legs and collect error strings unless all four fail (then 500).
- **BigQuery billing guard** — Default `maximumBytesBilled` ≈ 15 GB per query; health probe uses a lower cap. BQ API errors and timeouts surface as 500 with message in envelope.
- **Email CSV export** — Allowed extract ids enforced by `fn_analytics_export_allowed`; row cap **200,000**; signed Storage link emailed to the requesting admin (7-day TTL). Does not replace in-chart CSV buttons on pages.

## Journeys

### Admin journey

| Knob | Effect |
| --- | --- |
| Date range | Bounds partitions / timestamps in report SQL (`from`, `to`) |
| Frequency | Bucket size on time-series charts |
| Report id | Selects chart, rows, composite, or health probe |
| `month` | Required for points movement report |
| `as_of` | Required for points snapshot report |
| `filters` | Report-specific (e.g. currency on points movement) |
| Email CSV extract id | Chooses BQ vs PG export engine and fact grain |

| Page | Owning repo | Entry (report id) |
| --- | --- | --- |
| Home KPI strip | loyalty-admin | `home.metrics` |
| Executive overview | loyalty-admin | `overview.loyalty` |
| Transactions (purchases) | loyalty-admin | `transactions.purchases`, `transactions.purchases.rows` |
| Rewards (redemptions) | loyalty-admin | `rewards.redemptions`, `rewards.redemptions.rows` |
| Members | loyalty-admin | `members.overview`, `members.overview.rows` |
| Currency — points overview / movement | loyalty-admin | `currency.points_overview`, `currency.points_overview.rows`, `currency.points_movement` |
| Currency — points snapshot | loyalty-admin | `currency.points_snapshot`, `currency.points_snapshot.rows` |

1. Sign in as an active merchant admin (merchant context from resolution rules above).
2. Open a report page or Home; server action POSTs to Edge `analytics-query` with report id and filters.
3. UI renders chart JSON or paginated rows; optional drill-down uses the matching `.rows` report.
4. Optional **Email CSV**: same filters → `bff_admin_start_analytics_export` → progress via `bff_admin_get_analytics_export_progress` → email with download link when batch completes.
5. Errors: 401 unauthorized, 403 no merchant, 400 validation (range, month, as_of), 404 unknown report, 500 BQ failure — shown in admin UI toast or inline error state.

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

Canonical source: `supabase/functions/analytics-query/` (deploy mirror: `.cursor/deploy/analytics-query/`). Live deploy: Supabase project `wkevmsedchftztoolkmi`, slug `analytics-query`, ACTIVE (JWT checked in-function).

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
- **Scope** — Wave-1 reports exclude marketing funnels, RFM charts, and AMP workflow analytics on the BQ path (some available via PG email extract only).

## Related

- **Admin_Panel.md** — Metabase embed dashboards and `admin_analytics_menu` superadmin config.
- **AMP_Workflows.md** — Workflow and audience analytics BFFs (`bff_amp_analytics_*`).
- **CS_Analytics.md** — CS product metrics (`cs_bff_get_analytics_*`).
- **RFM_Scoring.md** — RFM scores; PG export extract id `rfm`.
- **Currency.md** — Wallet ledger semantics behind points reports and snapshot vs live wallet.
