# Marketplace order webhooks (Hookdeck replacement)

Replaces Hookdeck filter + transform + Kafka publish for Shopee, TikTok Shop, and Lazada order status webhooks.

## Public endpoints

Base: `https://wkevmsedchftztoolkmi.supabase.co/functions/v1`

| Platform | URL |
|----------|-----|
| TikTok Shop | `https://wkevmsedchftztoolkmi.supabase.co/functions/v1/webhook-marketplace-tiktok` |
| Shopee | `https://wkevmsedchftztoolkmi.supabase.co/functions/v1/webhook-marketplace-shopee` |
| Lazada | `https://wkevmsedchftztoolkmi.supabase.co/functions/v1/webhook-marketplace-lazada` |

All use **POST**, `verify_jwt: false` (platform webhooks).

## Required Supabase Edge secrets

| Secret | Purpose |
|--------|---------|
| `KAFKA_API_KEY` | Confluent cluster API key |
| `KAFKA_API_SECRET` | Confluent cluster API secret |
| `KAFKA_REST_RECORDS_URL` | Optional override; default is Confluent `marketplace.orders` records URL |
| `LAZADA_APP_KEY` | Lazada Open Platform App Key (for HMAC signature on `Authorization` header) |
| `LAZADA_APP_SECRET` | Lazada App Secret — `Authorization = hex(HMAC-SHA256(appKey + rawBody, secret))` |
| `INNGEST_EVENT_KEY` | Required if `MARKETPLACE_INGEST_MODE=inngest` or `both` |
| `MARKETPLACE_INGEST_MODE` | `kafka` (default), `inngest`, or `both` |
| `MARKETPLACE_WEBHOOK_SHARED_SECRET` | Optional auth for TikTok/Shopee during cutover |

`SUPABASE_URL` and `SUPABASE_SERVICE_ROLE_KEY` are provided automatically to Edge Functions.

## Lazada payload mapping (from production sample)

```json
{
  "seller_id": "9160",
  "data": {
    "order_status": "delivered",
    "trade_order_id": "1098563686514940"
  }
}
```

→ Kafka value: `shop_id=seller_id`, `order_sn=trade_order_id`, `order_status` lowercased, `platform=lazada`.

No UNPAID filter (matches Hookdeck — Lazada Verify may send `unpaid` test payloads).

## Cutover checklist

1. Set Edge secrets above in Supabase Dashboard → Edge Functions → Secrets.
2. Point each marketplace developer console webhook URL to the new endpoint.
3. Send a test order status change; confirm row in `custom_integration_events` and Kafka consumer logs.
4. Disable Hookdeck connections (TikTok, Shopee, Lazada) after 24h stable traffic.
5. Munasoul: re-point TikTok webhook first; backfill orders since 2026-05-06 if needed.

## Observability

Each request logs to `custom_integration_events` with `function_slug` = `webhook-marketplace-{platform}`.
