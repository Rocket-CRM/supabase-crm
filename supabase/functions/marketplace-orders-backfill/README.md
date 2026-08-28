# Marketplace orders historical backfill (staging → promote)

Paced OpenAPI list → detail → `stg_marketplace_backfill` → `fn_promote_marketplace_backfill` (insert-only into `order_ledger_mkp` + items). Skips Inngest. Skips existing go-live `(platform, order_sn)`. Leaves orders unclaimed / claim-ready.

## Endpoint

`POST https://wkevmsedchftztoolkmi.supabase.co/functions/v1/marketplace-orders-backfill`

Deploy (MCP or CLI with `--no-verify-jwt` if using custom secret only):

```bash
supabase functions deploy marketplace-orders-backfill --project-ref wkevmsedchftztoolkmi --no-verify-jwt
```

## Secrets

- Platform: `TIKTOK_APP_KEY` / `TIKTOK_APP_SECRET`, `SHOPEE_PARTNER_KEY`, `LAZADA_APP_KEY` / `LAZADA_APP_SECRET`
- Optional `MARKETPLACE_BACKFILL_SECRET` → header `x-marketplace-backfill-secret`

## Body

```json
{
  "platform": "tiktok",
  "shop_id": "7496054762932308455",
  "create_time_ge": 1767225600,
  "create_time_lt": 1767830400,
  "dry_run": true,
  "max_pages": 20,
  "max_save": 100,
  "skip_unpaid": true
}
```

- Window caps: Shopee ≤15 days; TikTok/Lazada ≤7 days per invocation.
- `dry_run: true` (default) — list + ledger skip counts; returns full `missing_order_sns`.
- `dry_run: false` — fetch detail for missing order_sns and upsert into staging.
- `stage_order_sns: ["SN…"]` — skip list; detail + stage those SNs (max 50). Use after dry-run. Not `fetch_order_sns` (that upserts ledger).
- `refresh_existing: true` — query unclaimed `refresh_statuses` → platform detail → `update_marketplace_order_status`. Not promote.
- Walk once: pass prior `next_cursor` as `refresh_after_transaction_date` + `refresh_after_order_sn`.

## Promote

```sql
SELECT public.fn_promote_marketplace_backfill(200, '<merchant_uuid>'::uuid, 'tiktok');
-- repeat until inserted+skipped_exists+errors all 0 for remaining ready rows
```

## Merchants (Sleeping Cloud / Grand Cru)

| Merchant | Platform | shop_id |
|---|---|---|
| Sleeping Cloud | shopee | 1420214577 |
| Sleeping Cloud | lazada | 101014448309 |
| Sleeping Cloud | tiktok | 7496054762932308455 |
| Grand Cru | shopee | 364905051 |
| Grand Cru | lazada | 100128462 |
| Grand Cru | tiktok | 7495742491657210722 |

Backfill from **2026-01-01 Asia/Bangkok** in paced windows (one shop at a time).
