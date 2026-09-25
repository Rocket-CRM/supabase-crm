# Purchases report — BigQuery POC

Mirrors [portal purchases report](https://portal.rocket-loyalty.com/reports/purchases) using `rocket-prod-analytics.raw_supabase_prod` instead of Supabase OLTP.

## Open locally

```bash
cd "poc/bq-purchases-report"
python3 -m http.server 8765
# open http://localhost:8765
```

## What the live page calls

| FE | RPC | Purpose |
|---|---|---|
| `fetchPurchases` | `bff_report_purchases(p_from, p_to, p_frequency, p_filters)` | summary + series + breakdowns |
| `fetchPurchasesRows` | `bff_report_purchases_rows(...)` | paginated table / CSV |

Source: `loyalty-admin/src/app/(admin)/reports/purchases/actions.ts`

## Parity check (Futurepark, 2026-06-01 → 2026-07-01, Asia/Bangkok)

Default filters: `status=['completed']`, `record_type='credit'`.

| Metric | Postgres | BigQuery |
|---|---:|---:|
| net_sales | 331,140,024.17 | 331,140,024.17 |
| orders | 300 | 300 |
| buyers | 34,299 | 34,299 |
| total_count | 174,761 | 174,761 |

## BQ tables used (raw)

- `public_purchase__ledger`
- `public_purchase__items__ledger` (for item rollups when present)
- `public_store__master`
- `public_earn__channel`
- `public_user__accounts` (new/returning buyers)
- product masters for category/brand/sku (when line items exist)

## Gaps vs live report

- `mkt_*` attribution tables are **not** in the current raw replica → campaign filter / attributed columns not in POC
- Drill rows (`bff_report_purchases_rows`) not rendered here
- This HTML is a static POC; production path should be Edge Function + admin JWT + forced `merchant_id`
