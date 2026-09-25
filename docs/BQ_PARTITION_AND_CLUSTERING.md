# BigQuery — Partitioning & Clustering (for analytics serving)

> **Product home for loyalty-admin BQ reports:** [`requirements/Analytics.md`](../requirements/Analytics.md).

Short guidance for anyone owning `rocket-prod-analytics` tables used by loyalty-admin dashboards.

## Serving path (app)

Loyalty-admin wave-1 reports call Edge Function **`analytics-query`** (admin JWT → forced `merchant_id` → named report SQL on BigQuery).

| Layer | Dataset | Use |
|---|---|---|
| Facts | `serving_loyalty` | Partitioned/clustered ledgers (`purchase_ledger`, `wallet_ledger`, …) |
| Dims | `raw_supabase_prod` | Small masters (`public_store__master`, `public_tier__master`, …) |

Report ids: `transactions.purchases[.rows]`, `rewards.redemptions[.rows]`, `members.overview[.rows]`, `currency.points_overview[.rows]`, `currency.points_movement`, `currency.points_snapshot[.rows]`, `overview.loyalty` (composite of the four domain summaries), `home.metrics` (lean home KPI strip: `member_added` / `earn` / `redeemer` / `driven_revenue` for last 30d by default + all-time `total_members`).

Secrets: `BQ_SERVICE_ACCOUNT_JSON`, `BQ_PROJECT_ID`, `BQ_LOCATION`. Source: `supabase/functions/analytics-query/` (mirrored under `.cursor/deploy/analytics-query/`).

## Why this matters

Dashboard queries almost always look like:

> this **merchant**, in this **date range**, aggregate metrics

BigQuery does not use Postgres-style indexes. To avoid scanning entire multi‑GB replica tables on every request, fact data should be **partitioned by date** and **clustered by `merchant_id`**.

Today, Datastream landing tables under `raw_supabase_prod` (e.g. `public_purchase__ledger_0`) are **unpartitioned and unclustered**. That is fine as a landing zone; it is **not** ideal as the primary layer dashboards query at scale.

---

## Partitioning (by date)

**What it is:** Physically split a table into segments by a date (or timestamp truncated to day).

**What it does:** A filter such as `WHERE transaction_date >= @from AND transaction_date < @to` lets BigQuery **skip partitions outside that range** instead of reading the whole table.

**What we need:** Partition fact tables (or marts built from them) by the **event date** of that fact — typically day grain.

**What we do *not* need:** Separate partitions for week / month / quarter. Report “frequency” is only a `GROUP BY` in SQL. One daily (or monthly) partition key is enough.

---

## Clustering (by merchant_id)

**What it is:** Within the table (and within partitions), BigQuery keeps rows organized by chosen columns.

**What it does:** A filter such as `WHERE merchant_id = @merchant_id` can skip large chunks of data that belong to other merchants.

**What we need:** Cluster key **`merchant_id`** first on multi-tenant facts and marts. Optional extra cluster columns (e.g. `store_id`) can be added later if useful — not required for v1.

---

## Marts (optional but recommended)

A **mart** is a smaller, scheduled summary table shaped for dashboards (e.g. merchant × day totals), itself partitioned by date and clustered by `merchant_id`.

Dashboards should prefer marts for hot paths; raw replica tables remain the source of truth for rollups.

---

## Example — purchase ledger

### Raw today (landing)

- Dataset: `raw_supabase_prod`
- Table / view: `public_purchase__ledger` → `public_purchase__ledger_0`
- Contains row-level purchases (all merchants mixed)
- **Current state:** no time partitioning, no clustering

### What we expect for efficient serving

Either improve the landing table **or** (preferred if ingestion is hard to change) build a mart from it.

**Minimum expectation for any table dashboards hit heavily:**

| Setting | Expectation |
|---|---|
| Partition | By purchase event date — e.g. `DATE(transaction_date)` (daily) |
| Cluster | `merchant_id` |
| Typical query shape | `merchant_id = @merchant_id` AND `transaction_date` in range, then aggregate |

**Illustrative mart (developers choose exact name/grain):**

- Grain example: `merchant_id` × `order_date` × (optional dims such as store / channel)
- Partition: `order_date`
- Cluster: `merchant_id`
- Built by scheduled SQL from `public_purchase__ledger`

Same pattern applies to other facts (`wallet_ledger` → partition on movement date, cluster `merchant_id`; redemptions → partition on redeemed date, cluster `merchant_id`).

---

## Ask of the data platform

1. Ensure tables used for dashboard serving (marts at minimum) use **partition by date** + **cluster by `merchant_id`**.
2. If Datastream landing can be partitioned/clustered without breaking replication, do that too; if not, marts alone are acceptable.
3. Keep data in `asia-southeast1`.

Details (exact DDL, schedule, grain) are left to the implementer.
