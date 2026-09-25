# Rocket Loyalty Open API — Platform Reference

Compact route inventory for agents and implementers.  
**Full human documentation** (field tables, request/response examples, curl): [`requirements/Open_API.md`](../../requirements/Open_API.md) › `## System` › **HTTP endpoint reference** (canonical product home; copy also at [`docs/Rocket Loyalty Open API Documentation.md`](../Rocket%20Loyalty%20Open%20API%20Documentation.md)).  
Machine-readable paths: [`openapi.yaml`](./openapi.yaml).

---

## 1. Base URL and authentication

| Item | Value |
|---|---|
| **Base URL (canonical)** | `https://open-api.rocket-loyalty.com/functions/v1` |
| **Fallback (direct)** | `https://mabioklchbkanhjwgibj.supabase.co/functions/v1` |
| Auth | `x-api-key: <merchant_api_key>` on every request except `OPTIONS` |
| Content-Type | `application/json` |

Mint / revoke keys in Admin → **Settings → API Keys**.

Success envelope:

```json
{
  "success": true,
  "data": {},
  "meta": { "request_id": "…", "response_time_ms": 12 }
}
```

Common auth errors: `MISSING_API_KEY`, `INVALID_API_KEY` (401). Gateway misconfig: `GATEWAY_CONFIG_ERROR` (500).

---

## 2. Surfaces

| Edge | Methods | Purpose |
|---|---|---|
| `api-users` | POST, GET, PATCH | Members; **points balance** = `points_balance` on GET; **ticket balances** = `ticket_balances[]` |
| `api-assets` | POST, GET, PATCH | Product / asset records |
| `api-purchases` | POST, GET, PATCH | Purchase ledger (`transaction_date` persisted on create) |
| `api-redemptions` | POST, GET + cancel / mark-used | Point redemptions |
| `api-wallet` | POST/GET `/transactions` | Points (default) and ticket ledger earn/burn + history |

---

## 3. Route cheat-sheet

### Users
- `POST /api-users`
- `GET|PATCH /api-users/{user_id}`
- `GET|PATCH /api-users/by-external-id|by-email|by-tel|by-line-id/{value}`

### Assets
- `POST /api-assets`
- `GET|PATCH /api-assets/{asset_id}`
- `GET|PATCH /api-assets/by-external-id|by-asset-code|by-serial-number/{value}`

### Purchases
- `POST /api-purchases`
- `GET /api-purchases/{transaction_number}` or `?transaction_number=` / `?transaction_id=`
- `PATCH /api-purchases/{transaction_number}`
- No public cancel route in v1. Purchase → points earn may be async; use wallet for synchronous credits.

### Redemptions
- `POST /api-redemptions` → code in `data.data.redemptions[0].redemption_code`
- `GET /api-redemptions/{redemption_code}`
- `POST /api-redemptions/{code}/cancel` · `.../mark-used`

### Wallet
- `POST /api-wallet/transactions` — `earn`/`burn`, required `dedup_key`; `currency` `points` (default) or `ticket`; ticket needs `ticket_type_id` or `ticket_code`
- `201` new / `200` replay / `409` conflict / `400` `INSUFFICIENT_BALANCE` / `INSUFFICIENT_TICKET_POOL` / ticket-type errors
- `GET /api-wallet/transactions` — history (`from`/`to`/`transaction_type`/`currency`/`ticket_type_id`/`ticket_code`/`limit`/`offset`); default currency remains points
- Exactly one user id field; no absolute balance PUT
- Balance read: `GET /api-users/...` → `points_balance` + `ticket_balances[]`
- Credit ticket types (`is_credit`) are not writable via Open API

---

## 4. Out of scope

- Absolute points / ticket balance SET  
- Store-credit / Shopify credit ticket types  
- Ticket-type catalog create/list  
- Public purchase-cancel  
- Merchant-specific forks  

---

## 5. Related

| Artefact | Role |
|---|---|
| [`Rocket-Loyalty-Open-API.pdf`](./Rocket-Loyalty-Open-API.pdf) | Merchant-sendable PDF (payloads, examples, curls). Regenerate: `node docs/openapi/generate-merchant-pdf.mjs` |
| [`Rocket Loyalty Open API Documentation.md`](../Rocket%20Loyalty%20Open%20API%20Documentation.md) | Full request/response/curl guide |
| [`openapi.yaml`](./openapi.yaml) | OpenAPI 3.1 |
| `.cursor/deploy/open-api/_smoke_all.mjs` | Smoke (`--allow-writes --wallet`) |
| `requirements/Currency.md` §Open API wallet | Backend side effects |
