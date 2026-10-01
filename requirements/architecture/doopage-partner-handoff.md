# DooPage × Rocket CS — Partner Handoff

Status: **Rocket surfaces deployed** (2026-07-24). Field maps / string-to-sign marked **provisional** until DooPage locks their API doc.

Base: `https://wkevmsedchftztoolkmi.supabase.co/functions/v1`

## What Rocket needs from DooPage

1. Company credentials for Rocket: `company_id`, `secret_key`, `api_token` (and webhook shared secret if different).
2. Final inbound webhook JSON schema + auth (Bearer vs HMAC string-to-sign).
3. OAuth authorize URL + callback query/body fields (especially how `shop_id` is returned).
4. Browser SDK `send_message` contract (params + exact string-to-sign + allowlisted FE domains).
5. Confirmation that TikTok Shop later reuses the same company + webhook.

## Rocket endpoints for DooPage

| Purpose | Method | URL |
|---|---|---|
| Inbound chat webhook | `POST` | `/webhook-doopage-cs` |
| Health | `GET` | `/webhook-doopage-cs` → `{ ok: true }` |
| Retired Shopee webhook | any | `/webhook-shopee` → **410** |

### Inbound auth (current)

```
Authorization: Bearer <DOOPAGE_WEBHOOK_TOKEN>
Content-Type: application/json
```

Optional later: set `DOOPAGE_WEBHOOK_HMAC_REQUIRED=true` and send `x-doopage-signature` = hex(HMAC-SHA256(rawBody, DOOPAGE_SECRET_KEY)) — provisional until DooPage confirms.

### Provisional inbound payload (aliases accepted)

Minimum fields Rocket maps today:

```json
{
  "shop_id": "123456789",
  "buyer_id": "buyer-platform-id",
  "buyer_name": "optional",
  "conversation_id": "optional-thread-id",
  "message_id": "unique-partner-message-id",
  "message_type": "text",
  "content": "hello"
}
```

Also accepted: `data`/`payload` envelope; camelCase aliases (`shopId`, `messageId`, …); `content: { text, type }`.

Responses:

- `401` auth failure
- `200 { accepted: true, ... }` ingested
- `200 { accepted: false, reason: "unknown_shop" }` — no orphan conversation; fix shop link
- `200 { accepted: true, duplicate: true }` — same `message_id` already stored

## Shop connect (merchant admin)

| Step | Endpoint | Body |
|---|---|---|
| Get authorize URL | `POST /doopage-cs-get-auth-url` | `{ "merchant_code", "redirect_url", "platform": "shopee" }` |
| Save shop link | `POST /doopage-cs-exchange-token` | `{ "merchant_code", "shop_id", "shop_name?" }` (+ optional `state` from OAuth) |

Stored as: `merchant_credentials(service_name='shopee', scope='{cs}', external_id=shop_id, channel_config.transport='doopage')`. Company secrets are **not** stored per merchant.

## Outbound agent reply (Browser SDK)

Rocket does **not** call DooPage `send_message` server-to-server.

1. Agent portal → `POST /cs-send-message` inserts inbox row.
2. If shop link is DooPage, response includes:

```json
{
  "success": true,
  "data": {
    "message_id": "...",
    "delivery": {
      "mode": "browser_sdk",
      "delivery_engine": "doopage_web_sdk",
      "sdk": {
        "company_id": "...",
        "api_token": "...",
        "shop_id": "...",
        "conversation_id": "...",
        "buyer_id": "...",
        "message": { "type": "text", "content": "..." },
        "timestamp": "1710000000",
        "sign": "<hex>"
      }
    }
  }
}
```

3. FE invokes DooPage Web SDK with `sdk.*`.
4. Standalone re-sign: `POST /doopage-cs-sign-send` (admin JWT) with `{ conversation_id, content, message_id? }`.

**Provisional sign:** HMAC-SHA256 hex over sorted `key=value` joined by `&` for keys `company_id`, `shop_id`, `conversation_id`, `content`, `timestamp`, secret = `DOOPAGE_SECRET_KEY`.

## Edge secrets Rocket must set

| Secret | Purpose |
|---|---|
| `DOOPAGE_WEBHOOK_TOKEN` | Inbound Bearer |
| `DOOPAGE_COMPANY_ID` | OAuth + SDK sign |
| `DOOPAGE_SECRET_KEY` | SDK / optional webhook HMAC |
| `DOOPAGE_API_TOKEN` | Passed to FE SDK if required |
| `DOOPAGE_OAUTH_AUTHORIZE_URL` | Override authorize base (optional) |
| `DOOPAGE_WEBHOOK_HMAC_REQUIRED` | `true` to require signature header |

## Explicit non-goals

- Not marketplace order ingest (`webhook-marketplace-shopee`).
- Not messaging-service `POST /send` adapter for chat text.
- Not storing DooPage company secrets in `merchant_credentials`.
