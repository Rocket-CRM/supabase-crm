# Marketplace earnable backfill (unclaimed mkp orders)

Re-fetches platform order financials for **unclaimed** `order_ledger_mkp` rows where `earnable_amount` is null, then upserts via the same adapters as ingest (Shopee escrow, Lazada `paid_price`, TikTok `price_detail`). No purchase or wallet changes.

Preserves existing `order_status` so claim eligibility is unchanged.

## Endpoint

`POST https://wkevmsedchftztoolkmi.supabase.co/functions/v1/marketplace-earnable-backfill`

Deploy:

```bash
supabase functions deploy marketplace-earnable-backfill --project-ref wkevmsedchftztoolkmi --no-verify-jwt
```

## Auth

Optional `MARKETPLACE_BACKFILL_SECRET` env → header `x-marketplace-backfill-secret`.

## Body

```json
{
  "platform": "shopee",
  "shop_id": "224882570",
  "merchant_id": "ffe8519e-49a2-467b-a0ec-57d28ba8be49",
  "after_id": "uuid-cursor-from-prior-response",
  "limit": 20,
  "since_date": "2026-08-10",
  "dry_run": false
}
```

- `since_date`: defaults to `2026-08-10` (loyalty earn cutover). Pass `null` for full backlog.
- Batch caps: Shopee/TikTok 20, Lazada 5 per call.
- Response `next_after_id` + `has_more` for looped runs.

## Her Hyness shops

| Platform | shop_id |
|---|---|
| shopee | 224882570 |
| lazada | 100184574113 |
| tiktok | 7495127669839399750 |

## Loop (example)

```bash
AFTER=""
while true; do
  RESP=$(curl -s -X POST "$URL/marketplace-earnable-backfill" \
    -H "Content-Type: application/json" \
    -H "x-marketplace-backfill-secret: $SECRET" \
    -d "{\"platform\":\"shopee\",\"shop_id\":\"224882570\",\"after_id\":\"$AFTER\",\"dry_run\":false}")
  echo "$RESP"
  HAS_MORE=$(echo "$RESP" | jq -r '.has_more')
  AFTER=$(echo "$RESP" | jq -r '.next_after_id')
  [ "$HAS_MORE" != "true" ] && break
  sleep 1
done
```
