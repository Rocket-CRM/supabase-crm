# E-commerce Marketplace Integration (pointer)

**Status:** Stub. Product truth for Shopee / Lazada / TikTok order ingest + claim: **[`Marketplace.md`](./Marketplace.md)**.

| Need | Go to |
|---|---|
| Shopee / Lazada / TikTok live ingest, credentials, backfill, claim | [`Marketplace.md`](./Marketplace.md) |
| Shopify app (OAuth, webhooks, widget, billing, refunds, order→points) | [`Shopify.md`](./Shopify.md) |
| Multi-channel SKU / external product refs | [`Multi_Channel_Product_Reference.md`](./Multi_Channel_Product_Reference.md) |
| BigCommerce storefront API (`api_bigcommerce_*`) | `REGISTRY_SUPABASE.md` / `REGISTRY_RENDER.md` — no separate product doc yet |

**Do not** treat Kafka `marketplace.orders` or Redis stream docs as live. Live mode: `MARKETPLACE_INGEST_MODE=inngest` (webhook → Inngest → `upsert_marketplace_order`). Retired Kafka-era setup docs were removed 2026-08-09.
