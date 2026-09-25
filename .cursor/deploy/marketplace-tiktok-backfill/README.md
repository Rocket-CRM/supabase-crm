# TikTok order backfill (Search Orders API)

Paginates `POST /order/202309/orders/search`, then `GET /order/202309/orders?ids=...` and `upsert_marketplace_order`.

## Endpoint

`POST https://wkevmsedchftztoolkmi.supabase.co/functions/v1/marketplace-tiktok-backfill-orders`

Deploy: `supabase functions deploy marketplace-tiktok-backfill-orders --project-ref wkevmsedchftztoolkmi --no-verify-jwt`

## Secrets

- `TIKTOK_APP_KEY` / `TIKTOK_APP_SECRET` (same as Inngest marketplace serve)
- Optional `MARKETPLACE_BACKFILL_SECRET` — if set, require header `x-marketplace-backfill-secret`

## Body

```json
{
  "shop_id": "7495900767072258467",
  "days_back": 30,
  "dry_run": true,
  "max_pages": 5,
  "max_save": 100,
  "skip_unpaid": true
}
```

- `dry_run: true` (default) — search only, no DB writes
- `dry_run: false` — fetch details + upsert
- `max_save` — cap upserts when testing

## Munasoul test

```bash
curl -sS -X POST "$SUPABASE_URL/functions/v1/marketplace-tiktok-backfill-orders" \
  -H "Authorization: Bearer $SUPABASE_SERVICE_ROLE_KEY" \
  -H "Content-Type: application/json" \
  -d '{"shop_id":"7495900767072258467","days_back":30,"dry_run":true,"max_pages":2}'
```
