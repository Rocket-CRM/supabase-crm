# Open API

Partner-facing REST API for merchants to integrate POS, ERP, and custom apps with Rocket loyalty — members, assets, purchases, redemptions, and wallet posts — without the admin UI.

Owner surfaces: Open API gateway (merchant integrators); loyalty-admin (API key provisioning); no member-facing Open API UI

## Concept

Open API is **server-to-server**: the merchant’s systems call HTTPS routes on a dedicated gateway; the gateway validates an API key, resolves merchant scope, and invokes CRM Postgres RPCs. Members never call these routes directly — they use the merchant’s own storefront or app.

**API key** — Long-lived merchant credential sent as `x-api-key`; validated on the CRM project via `validate_api_key`; revoked keys fail closed.

**Gateway** — Supabase Edge project `mabioklchbkanhjwgibj` (canonical host `https://open-api.rocket-loyalty.com/functions/v1`) terminates TLS and wraps CRM calls with a uniform JSON envelope. Postgres is not exposed publicly.

**Success envelope** — `{ success, data, meta }` on happy paths; errors use `{ success: false, error, code, details?, request_id }`.

**Domain routes** — Five edge functions mirror product areas: users, assets, purchases, redemptions, wallet. Maintenance plans are modeled as assets with type `MAINTENANCE_PLAN` and `covered_assets`, not a separate route family.

**Upsert** — User and asset creates accept `upsert=true` to update on conflict; `upsert=false` returns `409` when the record already exists.

**User identification** — Each mutating call accepts exactly one of internal `user_id`, `external_user_id`, `tel`, `email`, or `line_id` where the contract requires a member (wallet posts enforce this strictly).

**Purchase earn** — Bill ingest may queue currency earn (`processing_method` / chokepoint path); synchronous point credit for integrations should use wallet `earn` with a stable `dedup_key`.

**Redemption** — Point redemptions flow through `redeem_reward_with_points` behind `POST /api-redemptions`. Single-use codes use mark-used; multi-quantity package/persona entitlements use CRM `api_use_entitlement` (gateway route not in v1 OpenAPI — see Known gaps).

Machine contract: [`docs/openapi/openapi.yaml`](../docs/openapi/openapi.yaml). Compact route list: [`docs/openapi/PLATFORM_API_REFERENCE.md`](../docs/openapi/PLATFORM_API_REFERENCE.md). Merchant PDF: [`docs/openapi/Rocket-Loyalty-Open-API.pdf`](../docs/openapi/Rocket-Loyalty-Open-API.pdf).

## Rules

- Every request except `OPTIONS` must include a valid `x-api-key` → missing → `MISSING_API_KEY` (401); invalid/revoked → `INVALID_API_KEY` (401).
- Merchant scope is always derived from the key → callers cannot target another merchant’s data by passing a different `merchant_id`.
- User create with `upsert=false` and an existing match on tel/external id → `USER_EXISTS` (409). Asset create with `upsert=false` and existing external id/code → `ASSET_EXISTS` (409).
- Asset payloads validate against merchant `asset_field_definition` for the declared `asset_type_code` — not the Exclusive Parking member vehicle BFF shape (`Asset.md`).
- Open API asset types include product/equipment records and `MAINTENANCE_PLAN` rows with `covered_assets[]` linking covered equipment.
- Purchase create persists `transaction_date` when supplied; duplicate `transaction_number` behaviour follows `p_skip_duplicate_transaction_number` on `api_create_purchase`. Public v1 has **no** purchase-cancel route — reversals are ops/admin paths (`Purchase_Transaction.md`).
- Wallet `POST /transactions`: `transaction_type` `earn` or `burn`; required client `dedup_key`; same key + same payload → `200` replay; same key + different payload → `409 IDEMPOTENCY_CONFLICT`. Ticket posts require `currency=ticket` and `ticket_type_id` or `ticket_code`; store-credit / Shopify credit ticket types reject with `TICKET_TYPE_CREDIT_FORBIDDEN`.
- Wallet cannot set absolute balances — only ledger posts. Balances read from `GET /api-users/...` → `points_balance` and `ticket_balances[]`.
- Redemption `POST /api-redemptions` debits points via member redemption pipeline; `mark-used` is for standard single-use redemption codes, not incremental entitlement consumption.
- Field length limits on gateway: 255 default, 5000 for notes/description/reason-shaped fields → `VALIDATION_FAILED` (400).
- Gateway missing `CRM_SERVICE_ROLE_KEY` → `GATEWAY_CONFIG_ERROR` (500).

## Journeys

### Admin journey

| Page | Owning repo | BFF / RPC |
| --- | --- | --- |
| Settings → API Keys | loyalty-admin | `admin_get_api_keys` (list); key mint/revoke via admin provisioning flows |

| Setting | Effect on behaviour |
| --- | --- |
| API key active | Allows gateway `validate_api_key` to resolve merchant |
| Key revoked | All Open API calls fail `INVALID_API_KEY` |

1. Open **Settings → API Keys** in loyalty-admin.
2. Create or copy a key for the integration environment; store securely (shown once on mint).
3. Share canonical base URL `https://open-api.rocket-loyalty.com/functions/v1` and require `x-api-key` on every call.
4. Revoke compromised keys; integrators must rotate to a new key.

### Integrator journey

| Step | Artifact |
| --- | --- |
| Obtain API key | Admin journey above |
| Implement auth | `x-api-key` + `Content-Type: application/json` on POST/PATCH |
| Contract detail | `### HTTP endpoint reference` below; yaml for codegen |
| Smoke | `.cursor/deploy/open-api/_smoke_all.mjs` |

1. Provision key and base URL.
2. Upsert users (`POST /api-users`, optional `upsert=true`); patch by id paths or `by-external-id` / `by-tel` / etc.
3. Sync assets and optional maintenance plans (`POST /api-assets`).
4. Post purchases (`POST /api-purchases`) or wallet earn/burn when synchronous credits are required.
5. Redeem rewards and operate codes (`POST /api-redemptions`, GET/cancel/mark-used); handle error codes in **Error codes** under System.
6. List wallet history (`GET /api-wallet/transactions`) for reconciliation.

### Member journey

Members interact with the merchant’s own app or store; Open API is server-to-server only. Balances and tier shown to members use member JWT/BFF surfaces, not API keys.

## System

### Data model

| Store | Role in Open API |
| --- | --- |
| `merchant_api_keys` | Hashed keys; `validate_api_key` → `merchant_id` |
| `user_accounts` (+ addresses, profile fields) | User upsert/get/update via `api_*_user` |
| `asset` + `asset_field_definition` | Typed assets and maintenance plans |
| `purchase_ledger` / line items | Purchase ingest and reads |
| `redemption_*` / entitlements | Codes, cancel, mark-used, package entitlements |
| `user_wallet` / wallet transactions | Points and ticket ledger posts and history |

### Functions

| Gateway edge (project `mabioklchbkanhjwgibj`) | CRM RPC / fn (project `wkevmsedchftztoolkmi`) |
| --- | --- |
| `api-users` | `validate_api_key`; `api_create_or_update_user`, `api_update_user`, `api_get_user`, `api_find_user` |
| `api-assets` | `api_create_or_update_asset`, `api_update_asset`, `api_get_asset`, `api_find_asset` |
| `api-purchases` | `api_create_purchase`, `api_get_purchase`, `api_update_purchase` |
| `api-redemptions` | `redeem_reward_with_points` (POST redeem); `api_get_redemption`, `api_cancel_redemption`, `api_mark_redemption_used` |
| `api-wallet` | `api_post_wallet_transaction`, `api_get_wallet_transactions` |

Deploy sources for gateway handlers: `.cursor/deploy/open-api/` (CRM URL + service role env on gateway).

### Flows

1. Client → gateway edge with `x-api-key`.
2. Edge → CRM `validate_api_key` → `merchant_id`.
3. Edge validates JSON field lengths → maps HTTP route to CRM RPC with merchant id + body/query identifiers.
4. CRM enforces business rules → returns BFF-style payload → edge normalizes to Open API envelope + `meta.request_id` / timing headers.

Purchase create may enqueue earn processing; wallet earn is the synchronous alternative for integrators.

### External services

| Service | Role |
| --- | --- |
| Supabase project `mabioklchbkanhjwgibj` | Open API gateway — active edges: `api-users`, `api-assets`, `api-purchases`, `api-redemptions`, `api-wallet` (all `verify_jwt: false`; auth is API key only) |
| Custom domain | `open-api.rocket-loyalty.com` → gateway `/functions/v1` |
| CRM Supabase `wkevmsedchftztoolkmi` | Authoritative business logic and data |

Also deployed on gateway: `manage-delivery-schedule` (unrelated legacy edge — not part of loyalty Open API v1).

### Known gaps

- **Entitlement use** — CRM exposes `api_use_entitlement` for package/persona multi-use balances; no public gateway route or openapi path yet — do not use mark-used for those products until exposed.
- **Purchase cancel** — No public `api_cancel_purchase` route in v1 (`PLATFORM_API_REFERENCE.md` § Out of scope).
- **Ticket catalog** — No Open API to create/list ticket types; posts reference existing types only.
- **REGISTRY_RENDER.md** — Gateway services are on a separate Supabase project; use live `list_edge_functions` on `mabioklchbkanhjwgibj` plus `.cursor/deploy/open-api/` as deploy truth.

### HTTP endpoint reference

Human-readable request/response bodies, curl, and legacy field mapping follow. OpenAPI yaml remains the machine contract.

> Last verified against gateway edges + CRM `api_*` signatures: September 2026.

### Authentication with API Key

All API requests require authentication using the `x-api-key` header.

| Item | Value |
|------|-------|
| Base URL | `https://open-api.rocket-loyalty.com/functions/v1` |
| Auth Method | Custom API Key Header |
| Header | `x-api-key: {your-api-key}` |
| Expiration | None — API keys remain valid until revoked |

Generate API keys in the Rocket Loyalty admin dashboard under **Settings → API Keys**.

---

### Create or Update User

Create new users or update existing users in the Rocket Loyalty system.

| Item | Value |
|------|-------|
| Method | `POST` |
| URI | `/api-users` |
| Content-Type | `application/json` |

### Request Data Model

#### Basic Information

| Field | Required | Type | Remark |
|-------|----------|------|--------|
| `tel` | Mandatory | String | Phone number. Accepts both `0812345678` and `+66812345678` format; system auto-normalizes to `+66` E.164. |
| `fullname` | Mandatory | String | Full name |
| `firstname` | Optional | String | First name |
| `lastname` | Optional | String | Last name |
| `email` | Optional | String | Email address |
| `line_id` | Optional | String | LINE messenger ID |
| `id_card` | Optional | String | National ID card number |
| `birth_date` | Optional | Date | Format: `YYYY-MM-DD` (e.g. `1990-01-15`) |

#### External Integration

| Field | Required | Type | Remark |
|-------|----------|------|--------|
| `external_user_id` | Optional | String | Partner external user ID |

#### User Classification

| Field | Required | Type | Remark |
|-------|----------|------|--------|
| `user_type` | Optional | String | Default: `buyer`. Options: `buyer`, `seller` |
| `user_stage` | Optional | String | Customer lifecycle stage. Options: `lead`, `account`, `prospect`, `customer`, `churned` |

#### Communication Preferences

| Field | Required | Type | Remark |
|-------|----------|------|--------|
| `channel_email` | Optional | Boolean | Default: `true` |
| `channel_sms` | Optional | Boolean | Default: `false` |
| `channel_line` | Optional | Boolean | Default: `true` |
| `channel_push` | Optional | Boolean | Default: `true` |

#### Address & Custom Fields

| Field | Required | Type | Remark |
|-------|----------|------|--------|
| `addresses` | Optional | Array | User addresses (see structure below) |
| `address_mode` | Optional | String | Default: `replace`. Options: `replace`, `add` |
| `form_submissions` | Optional | Array | Custom profile fields like brand_interest (see structure below) |
| `upsert` | Optional | Boolean | Default: `false`. If `true`, updates existing user; if `false`, errors if user exists |

#### `addresses` Array Structure

| Field | Type |
|-------|------|
| `address_line_1` | String |
| `address_line_2` | String |
| `state` | String |
| `city` | String |
| `district` | String |
| `subdistrict` | String |
| `postcode` | String |

#### `form_submissions` Array Structure

| Field | Required | Type | Remark |
|-------|----------|------|--------|
| `form_template_code` | Mandatory | String | Must be `USER_PROFILE` for brand interest |
| `submission_mode` | Optional | String | Default: `create`. Options: `create`, `update` |
| `form_data` | Mandatory | Object | Field key-value pairs (see below) |

**Available `form_data` Fields:**

| Field Key | Type | Options | Remark |
|-----------|------|---------|--------|
| `brand_interest` | Array | `luxury`, `sports`, `electronics`, `fashion`, `home` | Multi-select brand preferences |

### Example Request — Create Lead with Brand Interest

```json
{
  "tel": "+66863210111",
  "fullname": "John Smith",
  "email": "john.smith@example.com",
  "external_user_id": "001BW00000B3Ait",
  "user_stage": "lead",
  "form_submissions": [
    {
      "form_template_code": "USER_PROFILE",
      "submission_mode": "create",
      "form_data": {
        "brand_interest": ["luxury", "fashion"]
      }
    }
  ]
}
```

### Example Request — Create Account Customer

```json
{
  "tel": "+66812345678",
  "fullname": "Jane Doe",
  "firstname": "Jane",
  "lastname": "Doe",
  "email": "jane.doe@example.com",
  "external_user_id": "EXT_USER_002",
  "birth_date": "1985-03-15",
  "user_stage": "account",
  "channel_email": true,
  "channel_sms": true,
  "addresses": [
    {
      "address_line_1": "123 Sukhumvit Road",
      "city": "Bangkok",
      "district": "Khlong Toei",
      "postcode": "10110"
    }
  ],
  "form_submissions": [
    {
      "form_template_code": "USER_PROFILE",
      "submission_mode": "create",
      "form_data": {
        "brand_interest": ["electronics", "sports", "home"]
      }
    }
  ],
  "upsert": true
}
```

### Example Response — 201 Created (or 200 if upsert updated)

```json
{
  "success": true,
  "data": {
    "success": true,
    "user_id": "0815c8fc-10f7-4181-8bf9-4db14e48598f",
    "external_user_id": "EXT_USER_002",
    "created": true,
    "updated": false,
    "addresses_added": 1,
    "addresses_deleted": 0,
    "form_submissions_created": 1,
    "form_submissions_updated": 0
  },
  "meta": {
    "request_id": "req_user001",
    "response_time_ms": 189
  }
}
```

### Example Response — 409 User Already Exists (when `upsert=false`)

```json
{
  "success": false,
  "error": "User already exists",
  "code": "USER_EXISTS",
  "details": "User with tel '+66812345678' already exists. Use upsert=true to update.",
  "request_id": "req_user002"
}
```

### POSTMAN curl

```bash
curl --location 'https://open-api.rocket-loyalty.com/functions/v1/api-users' \
--header 'Content-Type: application/json' \
--header 'x-api-key: YOUR_API_KEY_HERE' \
--data '{
  "tel": "+66812345678",
  "fullname": "Jane Doe",
  "firstname": "Jane",
  "lastname": "Doe",
  "email": "jane.doe@example.com",
  "external_user_id": "EXT_USER_002",
  "birth_date": "1985-03-15",
  "user_stage": "account",
  "addresses": [
    {
      "address_line_1": "123 Sukhumvit Road",
      "city": "Bangkok",
      "postcode": "10110"
    }
  ],
  "form_submissions": [
    {
      "form_template_code": "USER_PROFILE",
      "submission_mode": "create",
      "form_data": {
        "brand_interest": ["electronics", "sports", "home"]
      }
    }
  ],
  "upsert": true
}'
```

---

### Update User Details

Update existing user information. All fields are **OPTIONAL** — only provide fields you want to update.

| Item | Value |
|------|-------|
| Method | `PATCH` |
| Content-Type | `application/json` |

**URI Options:**

| URI | Lookup by |
|-----|-----------|
| `/api-users/by-external-id/{external_user_id}` | External user ID |
| `/api-users/by-email/{email}` | Email address |
| `/api-users/by-tel/{phone}` | Phone number |
| `/api-users/by-line-id/{line_id}` | LINE ID |
| `/api-users/{user_id}` | UUID |

### Request Data Model

| Field | Type | Remark |
|-------|------|--------|
| `fullname` | String | Full name |
| `firstname` | String | First name |
| `lastname` | String | Last name |
| `email` | String | Email address |
| `tel` | String | Phone number |
| `line_id` | String | LINE messenger ID |
| `id_card` | String | National ID card |
| `birth_date` | Date | Format: `YYYY-MM-DD` |
| `user_stage` | String | Customer lifecycle stage |
| `channel_email` | Boolean | Email preference |
| `channel_sms` | Boolean | SMS preference |
| `channel_line` | Boolean | LINE preference |
| `channel_push` | Boolean | Push notification preference |
| `addresses` | Array | User addresses |
| `address_mode` | String | `replace` or `add` |
| `form_submissions` | Array | Update custom fields like brand_interest |

### Example — Update User Stage (Lead → Account)

```json
{
  "user_stage": "account"
}
```

### Example — Update Brand Interest

```json
{
  "form_submissions": [
    {
      "form_template_code": "USER_PROFILE",
      "submission_mode": "update",
      "form_data": {
        "brand_interest": ["luxury", "electronics"]
      }
    }
  ]
}
```

### Example — Update Multiple Fields

```json
{
  "email": "newemail@example.com",
  "user_stage": "account",
  "form_submissions": [
    {
      "form_template_code": "USER_PROFILE",
      "submission_mode": "update",
      "form_data": {
        "brand_interest": ["sports", "fashion"]
      }
    }
  ]
}
```

### Example Response — 200 Success

```json
{
  "success": true,
  "data": {
    "success": true,
    "user_id": "0815c8fc-10f7-4181-8bf9-4db14e48598f",
    "updated_fields": ["user_stage", "form_submissions"],
    "addresses_added": 0,
    "addresses_deleted": 0,
    "form_submissions_created": 0,
    "form_submissions_updated": 1
  },
  "meta": {
    "request_id": "req_update_user001",
    "response_time_ms": 145
  }
}
```

### Example Response — 404 User Not Found

```json
{
  "success": false,
  "error": "User not found",
  "code": "USER_NOT_FOUND",
  "details": "No user found with external_user_id 'EXT_USER_999'",
  "request_id": "req_update_user002"
}
```

### POSTMAN curl — Update by External ID

```bash
curl --location --request PATCH \
  'https://open-api.rocket-loyalty.com/functions/v1/api-users/by-external-id/EXT_USER_002' \
--header 'Content-Type: application/json' \
--header 'x-api-key: YOUR_API_KEY_HERE' \
--data '{
  "user_stage": "account",
  "form_submissions": [
    {
      "form_template_code": "USER_PROFILE",
      "submission_mode": "update",
      "form_data": {
        "brand_interest": ["luxury", "electronics"]
      }
    }
  ]
}'
```

### POSTMAN curl — Update by Phone

```bash
curl --location --request PATCH \
  'https://open-api.rocket-loyalty.com/functions/v1/api-users/by-tel/%2B66812345678' \
--header 'Content-Type: application/json' \
--header 'x-api-key: YOUR_API_KEY_HERE' \
--data '{
  "user_stage": "account"
}'
```

---

### Retrieve User Information

Retrieve user profile details including custom fields, member status, and cache-backed tier progress.

| Item | Value |
|------|-------|
| Method | `GET` |

**URI Options:** (same as Update User)

| URI | Lookup by |
|-----|-----------|
| `/api-users/by-external-id/{external_user_id}` | External user ID |
| `/api-users/by-email/{email}` | Email address |
| `/api-users/by-tel/{phone}` | Phone number |
| `/api-users/by-line-id/{line_id}` | LINE ID |
| `/api-users/{user_id}` | UUID |

### Query parameters

| Parameter | Default | Description |
|-----------|---------|-------------|
| `include_tier` | `true` | When `false`, omits `member_status` and `tier` (legacy slim payload). |
| `include` | — | Comma-separated includes; must contain `tier` to return tier fields when using this param instead of `include_tier`. |

Tier **progress** (`tier.progress`) is read from the `tier_progress` cache only — no live recompute on request.

### Member status mapping

| `member_status` | Meaning |
|-----------------|---------|
| `active` | Not frozen; `is_active` is true or null |
| `suspended` | `is_freeze` is true |
| `inactive` | `is_active` is false and not frozen |

Soft-deleted members return `404 USER_NOT_FOUND`.

### Response fields (tier block)

| Field | Type | Description |
|-------|------|-------------|
| `member_status` | string | `active`, `inactive`, or `suspended` |
| `tier` | object \| null | Null when user has no tier assignment |
| `tier.tier_id` | uuid | Current tier ID |
| `tier.tier_code` | uuid | Canonical tier code (same as `tier_id`) |
| `tier.tier_name` | string | Display name |
| `tier.effective_at` | timestamptz | When current tier was achieved (ISO 8601 UTC) |
| `tier.current_tier_threshold.metric` | string | `points`, `sales`, `orders`, or `ticket` |
| `tier.current_tier_threshold.amount` | number | Threshold for current tier |
| `tier.progress` | object \| omitted | Omitted when no cache row or user is at top tier |
| `tier.progress.current_amount` | number | Cached progress toward next tier |
| `tier.progress.percent` | number | Progress percent toward next tier |
| `tier.progress.next_tier_id` | uuid | Next tier ID |
| `tier.progress.next_tier_name` | string | Next tier display name |
| `tier.progress.next_tier_threshold_amount` | number | Points/spend required for next tier |

### Example Request

```
GET https://open-api.rocket-loyalty.com/functions/v1/api-users/by-tel/+66812345678
```

### Example Response

```json
{
  "success": true,
  "data": {
    "user": {
      "user_id": "0815c8fc-10f7-4181-8bf9-4db14e48598f",
      "external_user_id": "EXT_USER_002",
      "fullname": "Jane Doe",
      "firstname": "Jane",
      "lastname": "Doe",
      "email": "jane.doe@example.com",
      "tel": "+66812345678",
      "line_id": null,
      "birth_date": "1985-03-15",
      "user_type": "buyer",
      "user_stage": "account",
      "member_status": "active",
      "tier_id": "uuid",
      "persona_id": null,
      "points_balance": 1250,
      "tier": {
        "tier_id": "uuid",
        "tier_code": "uuid",
        "tier_name": "Gold",
        "effective_at": "2025-06-01T00:00:00+00:00",
        "current_tier_threshold": {
          "metric": "points",
          "amount": 5000
        },
        "progress": {
          "metric": "points",
          "current_amount": 1250,
          "percent": 25.0,
          "next_tier_id": "uuid",
          "next_tier_name": "Platinum",
          "next_tier_threshold_amount": 10000
        }
      },
      "ticket_balances": [],
      "channel_email": true,
      "channel_sms": false,
      "channel_line": true,
      "channel_push": true,
      "addresses": [
        {
          "address_line_1": "123 Sukhumvit Road",
          "city": "Bangkok",
          "district": "Khlong Toei",
          "postcode": "10110"
        }
      ],
      "custom_fields": {
        "brand_interest": ["luxury", "fashion"]
      }
    }
  },
  "meta": {
    "request_id": "req_getuser001",
    "response_time_ms": 67
  }
}
```

When the user has no tier program assignment, `tier` is `null`. When assigned but no cache row exists yet, `tier` includes identity/threshold fields and `progress` is omitted.

### POSTMAN curl

```bash
curl --location \
  'https://open-api.rocket-loyalty.com/functions/v1/api-users/by-tel/%2B66812345678' \
  --header 'x-api-key: YOUR_API_KEY_HERE'
```

Legacy slim payload (no tier block):

```bash
curl --location \
  'https://open-api.rocket-loyalty.com/functions/v1/api-users/by-external-id/EXT_USER_002?include_tier=false' \
  --header 'x-api-key: YOUR_API_KEY_HERE'
```

---

### Create Asset

Create new Assets in the Rocket Loyalty system.

| Item | Value |
|------|-------|
| Method | `POST` |
| URI | `/api-assets` |
| Content-Type | `application/json` |

### Request Data Model

#### Core Fields

| Field | Required | Type | Remark |
|-------|----------|------|--------|
| `asset_type_code` | Mandatory | String | Must be `ASSET` |
| `name` | Mandatory | String | Asset name |
| `external_id` | Optional | String | Partner external asset ID (unique) |
| `serial_number` | Optional | String | Equipment serial number |
| `status` | Optional | String | e.g. `Purchased`, `Installed` |
| `purchase_date` | Optional | Date | Format: `YYYY-MM-DD` |
| `install_date` | Optional | Date | Format: `YYYY-MM-DD` |
| `external_user_id` | Optional | String | External user ID or phone number |
| `user_id` | Optional | UUID | Internal user ID |
| `sku_code` | Optional | String | Product SKU code |
| `purchase_transaction_number` | Optional | String | Related purchase transaction |
| `upsert` | Optional | Boolean | If `true`, updates existing asset; if `false`, errors if exists |
| `custom_fields` | Optional | Object | Merchant-defined custom fields (see examples below) |

#### Example custom fields for ASSET type

**Warranty & Usage:**

| Field | Type | Remark |
|-------|------|--------|
| `warrantyPeriodTechnogym` | Number | Warranty period in months |
| `warrantyPeriodExtended` | Number | Extended warranty period in months (example) |
| `usageEndDate` | Date | Format: `YYYY-MM-DD` |

**Product Information:**

| Field | Type | Remark |
|-------|------|--------|
| `productName` | String | Product display name |
| `productCode` | String | Partner product code (example) |
| `product2Id` | String | Partner product ID (example) |
| `articleNumber` | String | Article number |

**Optional CRM / ERP integration keys (examples):**

| Field | Type | Remark |
|-------|------|--------|
| `salesOrder` | String | Sales order number |
| `recordTypeId` | String | Partner record type (example) |
| `quantity` | Number | Quantity purchased |
| `project` | String | Partner project ID (example) |
| `opportunity` | String | Partner opportunity ID (example) |
| `opportunityProduct` | String | Partner opportunity product ID (example) |
| `accountId` | String | Partner account ID (example) |
| `contactId` | String | Partner contact ID (example) |
| `parentId` | String | Parent asset ID |

**Delivery Order:**

| Field | Type | Remark |
|-------|------|--------|
| `doNumber` | String | Delivery order number |
| `doDate` | Date | Format: `YYYY-MM-DD` |
| `cnNumber` | String | Credit note number |

**Financial & Classification:**

| Field | Type | Remark |
|-------|------|--------|
| `price` | Number | Asset price |
| `category` | String | Asset category |
| `brand` | String | Brand name |
| `location` | String | Physical location |
| `tags` | String | Classification tags |
| `notes` | String | Additional notes |
| `description` | String | Asset description |

### Example Request

```json
{
  "asset_type_code": "ASSET",
  "name": "EXCITE LIVE CLIMB LIVE 700 METEOR BLACK",
  "external_id": "02iBW0000000f6QYAQA",
  "serial_number": "1234",
  "status": "Purchased",
  "purchase_date": "2023-08-06",
  "external_user_id": "001BW00000B3Ait",
  "upsert": false,
  "custom_fields": {
    "warrantyPeriodTechnogym": null,
    "warrantyPeriodExtended": 24,
    "usageEndDate": null,
    "productName": "EXCITE LIVE CLIMB LIVE 700 METEOR BLACK",
    "productCode": "D-T01-CD03-DFEG3A10AN00EA2S",
    "product2Id": "01tBW0000001vMdYAI",
    "articleNumber": "D-T01-CD03-DFEG3A10AN00EA2S",
    "salesOrder": "233100523",
    "recordTypeId": "0126F000001WxVgQAK",
    "quantity": 1,
    "project": "a0iBW000000AOp3YAG",
    "opportunity": "006BW000006jxy9YAA",
    "opportunityProduct": "00kBW00000091ksYAA",
    "accountId": "001BW00000B3Ait",
    "contactId": null,
    "parentId": null,
    "doNumber": null,
    "doDate": null,
    "cnNumber": null,
    "price": 355300,
    "category": "Fitness Equipment",
    "brand": "Technogym",
    "location": "Warehouse A",
    "tags": null,
    "notes": null,
    "description": null
  }
}
```

### Example Response — 200 Success

```json
{
  "success": true,
  "data": {
    "asset_id": "7366abf1-59a3-4a57-b55e-8dc845213047",
    "external_id": "02iBW0000000f6QYAQA",
    "name": "EXCITE LIVE CLIMB LIVE 700 METEOR BLACK",
    "serial_number": "1234",
    "status": "Purchased",
    "purchase_date": "2023-08-06",
    "custom_fields": { "..." }
  },
  "meta": {
    "request_id": "req_abc123",
    "response_time_ms": 145
  }
}
```

### Example Response — 409 Asset Already Exists (when `upsert=false`)

```json
{
  "success": false,
  "error": "Asset already exists",
  "code": "ASSET_EXISTS",
  "details": "Asset with external_id '02iBW0000000f6QYAQA' already exists. Use upsert=true to update.",
  "request_id": "req_abc124"
}
```

### POSTMAN curl

```bash
curl --location 'https://open-api.rocket-loyalty.com/functions/v1/api-assets' \
--header 'Content-Type: application/json' \
--header 'x-api-key: YOUR_API_KEY_HERE' \
--data '{
  "asset_type_code": "ASSET",
  "name": "EXCITE LIVE CLIMB LIVE 700 METEOR BLACK",
  "external_id": "02iBW0000000f6QYAQA",
  "serial_number": "1234",
  "status": "Purchased",
  "purchase_date": "2023-08-06",
  "external_user_id": "001BW00000B3Ait",
  "custom_fields": {
    "warrantyPeriodExtended": 24,
    "productName": "EXCITE LIVE CLIMB LIVE 700 METEOR BLACK",
    "productCode": "D-T01-CD03-DFEG3A10AN00EA2S",
    "salesOrder": "233100523",
    "price": 355300,
    "category": "Fitness Equipment",
    "brand": "Technogym",
    "location": "Warehouse A"
  }
}'
```

---

### Update Existing Asset

Update existing asset information. All fields are **OPTIONAL**.

| Item | Value |
|------|-------|
| Method | `PATCH` |
| URI | `/api-assets/by-external-id/{external_id}` |
| Content-Type | `application/json` |

**Alternative URIs:**

- `/api-assets/by-serial-number/{serial_number}`
- `/api-assets/by-asset-code/{asset_code}`
- `/api-assets/{asset_id}` (UUID)

### Request Data Model

| Field | Type | Remark |
|-------|------|--------|
| `name` | String | Asset name |
| `status` | String | Asset status |
| `purchase_date` | Date | Format: `YYYY-MM-DD` |
| `install_date` | Date | Format: `YYYY-MM-DD` |
| `serial_number` | String | Equipment serial number |
| `custom_fields` | Object | Merges with existing custom fields (same 26 fields as create) |

> **Important:** Custom fields are **merged**, not replaced. To update specific fields, only include those fields in the `custom_fields` object.

### Example Request

```json
{
  "status": "Installed",
  "install_date": "2024-10-20",
  "custom_fields": {
    "location": "Gym Floor 3",
    "warrantyPeriodExtended": 36,
    "price": 400000
  }
}
```

### Example Response — 200 Success

```json
{
  "success": true,
  "data": {
    "asset_id": "7366abf1-59a3-4a57-b55e-8dc845213047",
    "external_id": "02iBW0000000f6QYAQA",
    "name": "EXCITE LIVE CLIMB LIVE 700 METEOR BLACK",
    "serial_number": "1234",
    "status": "Installed",
    "purchase_date": "2023-08-06",
    "install_date": "2024-10-20",
    "custom_fields": {
      "warrantyPeriodExtended": 36,
      "price": 400000,
      "location": "Gym Floor 3",
      "productCode": "D-T01-CD03-DFEG3A10AN00EA2S",
      "salesOrder": "233100523",
      "opportunity": "006BW000006jxy9YAA"
    },
    "updated_at": "2024-10-20T14:30:00.000Z"
  },
  "meta": {
    "request_id": "req_xyz789",
    "response_time_ms": 89
  }
}
```

### Example Response — 404 Asset Not Found

```json
{
  "success": false,
  "error": "Asset not found",
  "code": "ASSET_NOT_FOUND",
  "details": "No asset found with external_id '02iBW0000000f6QYAQA'",
  "request_id": "req_xyz790"
}
```

### POSTMAN curl

```bash
curl --location --request PATCH \
  'https://open-api.rocket-loyalty.com/functions/v1/api-assets/by-external-id/02iBW0000000f6QYAQA' \
--header 'Content-Type: application/json' \
--header 'x-api-key: YOUR_API_KEY_HERE' \
--data '{
  "status": "Installed",
  "install_date": "2024-10-20",
  "custom_fields": {
    "location": "Gym Floor 3",
    "warrantyPeriodExtended": 36,
    "price": 400000
  }
}'
```

---

### Create Maintenance Plan

Create new Maintenance Plans in the Rocket Loyalty system.

| Item | Value |
|------|-------|
| Method | `POST` |
| URI | `/api-assets` |
| Content-Type | `application/json` |

### Request Data Model

#### Core Fields

| Field | Required | Type | Remark |
|-------|----------|------|--------|
| `asset_type_code` | Mandatory | String | Must be `MAINTENANCE_PLAN` |
| `name` | Mandatory | String | Maintenance plan name |
| `external_id` | Optional | String | Partner external maintenance-plan ID (unique) |
| `status` | Optional | String | e.g. `Active`, `Expired` |
| `external_user_id` | Optional | String | External user / account reference |
| `covered_assets` | Optional | Array | Assets covered by this plan (see below) |
| `upsert` | Optional | Boolean | If `true`, updates existing; if `false`, errors if exists |
| `custom_fields` | Optional | Object | All maintenance plan fields (see below) |

#### `covered_assets` Array Structure

Each covered asset can be identified by **ONE** of:

| Field | Type | Remark |
|-------|------|--------|
| `asset_id` | UUID | Internal asset ID |
| `external_id` | String | Partner asset external ID |
| `asset_code` | String | Internal asset code |
| `serial_number` | String | Equipment serial number |

```json
"covered_assets": [
  { "external_id": "02iBW0000000f6QYAQA" },
  { "serial_number": "SN12345" }
]
```

#### Custom Fields for MAINTENANCE_PLAN Type

**Plan Identification:**

| Field | Type | Remark |
|-------|------|--------|
| `maintenancePlanNumber` | String | Unique plan number (e.g. `MP-0411`) |
| `maintenancePlanType` | String | e.g. `Contract`, `Warranty` |
| `maintenancePlanStatus` | String | e.g. `Active`, `Expired` |
| `maintenancePlanTitle` | String | Plan title/headline |

**Work Type:**

| Field | Type | Remark |
|-------|------|--------|
| `workTypeName` | String | e.g. `Services Maintenance` |
| `workTypeId` | String | Partner work type ID (example) |

**Work Order Configuration:**

| Field | Type | Remark |
|-------|------|--------|
| `workOrderGenerationStatus` | String | e.g. `NotStarted`, `InProgress` |
| `workOrderGenerationMethod` | String | e.g. `WorkOrderPerAsset` |

**Schedule & Timing:**

| Field | Type | Remark |
|-------|------|--------|
| `startDate` | Date | Format: `YYYY-MM-DD` |
| `endDate` | Date | Format: `YYYY-MM-DD` |
| `extendDate` | Date | Extension date if applicable |
| `frequency` | Number | Service frequency number |
| `frequencyType` | String | e.g. `Months`, `Days` |
| `generationTimeframe` | Number | Generation timeframe number |
| `generationTimeframeType` | String | e.g. `Months` |
| `nextSuggestedMaintenanceDate` | Date | Format: `YYYY-MM-DD` |

**Maintenance Window:**

| Field | Type | Remark |
|-------|------|--------|
| `maintenanceWindowStartDays` | Number | Window start in days |
| `maintenanceWindowEndDays` | Number | Window end in days |

**Optional CRM / ERP integration keys (examples):**

| Field | Type | Remark |
|-------|------|--------|
| `serviceContractId` | String | Partner service contract ID (example) |
| `salesOrder` | String | Sales order number |
| `recordTypeId` | String | Partner record type (example) |
| `project` | String | Partner project ID (example) |
| `opportunity` | String | Partner opportunity ID (example) |
| `accountId` | String | Partner account ID (example) |
| `contactId` | String | Partner contact ID (example) |

**Plan Relationships & Configuration:**

| Field | Type | Remark |
|-------|------|--------|
| `parentMaintenancePlan` | String | Parent plan ID for hierarchy |
| `asset` | String | Direct asset reference |
| `serialNumber` | String | Serial number reference |
| `articleNumber` | String | Article number |
| `quantity` | Number | Quantity value |
| `mpRenewal` | Boolean | Renewal flag |
| `approvalStatus` | String | e.g. `NotRequired`, `Pending` |
| `allAssetInstalled` | Boolean | All assets installed flag |
| `activeExpire` | String | Active/Expire status |
| `description` | String | Plan description |

### Example Request

```json
{
  "asset_type_code": "MAINTENANCE_PLAN",
  "name": "6-Month Service Plan",
  "external_id": "1MPBW00000001Lt4AI",
  "status": "Active",
  "external_user_id": "001BW00000B3Ait",
  "upsert": false,
  "custom_fields": {
    "maintenancePlanNumber": "MP-0411",
    "maintenancePlanType": "Contract",
    "maintenancePlanStatus": "Active",
    "workTypeName": "Services Maintenance",
    "workTypeId": "08qBW0000000CFhYAM",
    "workOrderGenerationStatus": "NotStarted",
    "workOrderGenerationMethod": "WorkOrderPerAsset",
    "startDate": "2024-02-22",
    "endDate": "2026-02-22",
    "frequency": 6,
    "frequencyType": "Months",
    "generationTimeframe": 24,
    "generationTimeframeType": "Months",
    "nextSuggestedMaintenanceDate": "2024-08-22",
    "salesOrder": "233100555",
    "recordTypeId": "0126F000001WxIOQA0",
    "project": "a0iBW000000AeaTYAS",
    "opportunity": "006BW000007ZIKbYAO",
    "accountId": "001BW00000B3Ait",
    "quantity": 0,
    "mpRenewal": false,
    "approvalStatus": "NotRequired",
    "allAssetInstalled": false,
    "activeExpire": "Active"
  },
  "covered_assets": [
    { "external_id": "02iBW0000000f6QYAQA" }
  ]
}
```

### Example Response — 200 Success

```json
{
  "success": true,
  "data": {
    "asset_id": "d83789b7-5ec2-4135-8822-f30afb11997a",
    "external_id": "1MPBW00000001Lt4AI",
    "name": "6-Month Service Plan",
    "status": "Active",
    "asset_type": "MAINTENANCE_PLAN",
    "custom_fields": { "..." },
    "covered_assets": [
      {
        "asset_id": "7366abf1-59a3-4a57-b55e-8dc845213047",
        "external_id": "02iBW0000000f6QYAQA",
        "name": "EXCITE LIVE CLIMB LIVE 700 METEOR BLACK",
        "serial_number": "1234",
        "article_number": "D-T01-CD03-DFEG3A10AN00EA2S"
      }
    ],
    "created_at": "2024-11-06T13:54:00.000Z"
  },
  "meta": {
    "request_id": "req_maint001",
    "response_time_ms": 212
  }
}
```

### POSTMAN curl

```bash
curl --location 'https://open-api.rocket-loyalty.com/functions/v1/api-assets' \
--header 'Content-Type: application/json' \
--header 'x-api-key: YOUR_API_KEY_HERE' \
--data '{
  "asset_type_code": "MAINTENANCE_PLAN",
  "name": "6-Month Service Plan",
  "external_id": "1MPBW00000001Lt4AI",
  "status": "Active",
  "external_user_id": "001BW00000B3Ait",
  "custom_fields": { "..." },
  "covered_assets": [
    { "external_id": "02iBW0000000f6QYAQA" }
  ]
}'
```

---

### Update Existing Maintenance Plan

Update existing Maintenance Plan details. All fields are **OPTIONAL**.

| Item | Value |
|------|-------|
| Method | `PATCH` |
| URI | `/api-assets/by-external-id/{external_id}` |
| Content-Type | `application/json` |

**Alternative URIs:**

- `/api-assets/by-asset-code/{asset_code}`
- `/api-assets/{asset_id}` (UUID)

### Request Data Model

| Field | Type | Remark |
|-------|------|--------|
| `name` | String | Maintenance plan name |
| `status` | String | Plan status |
| `custom_fields` | Object | Merges with existing — all 35 fields available (see Create API) |
| `covered_assets` | Array | **Replaces ALL** linked assets (not merged) |

> **Important Notes:**
> - Custom fields are **merged** (partial updates supported)
> - `covered_assets` array **replaces** the entire relationship (not merged)
> - To add assets, include both existing and new assets in the array

### Example Request

```json
{
  "status": "Active",
  "custom_fields": {
    "workTypeName": "Services Maintenance - Updated",
    "maintenancePlanStatus": "Active",
    "nextSuggestedMaintenanceDate": "2024-12-22",
    "frequency": 3,
    "frequencyType": "Months"
  },
  "covered_assets": [
    { "external_id": "02iBW0000000f6QYAQA" },
    { "serial_number": "SN67890" }
  ]
}
```

### Example Response — 200 Success

```json
{
  "success": true,
  "data": {
    "asset_id": "d83789b7-5ec2-4135-8822-f30afb11997a",
    "external_id": "1MPBW00000001Lt4AI",
    "name": "6-Month Service Plan",
    "status": "Active",
    "asset_type": "MAINTENANCE_PLAN",
    "custom_fields": {
      "maintenancePlanNumber": "MP-0411",
      "workTypeName": "Services Maintenance - Updated",
      "nextSuggestedMaintenanceDate": "2024-12-22",
      "frequency": 3,
      "frequencyType": "Months"
    },
    "covered_assets": [
      {
        "asset_id": "7366abf1-59a3-4a57-b55e-8dc845213047",
        "external_id": "02iBW0000000f6QYAQA",
        "name": "EXCITE LIVE CLIMB LIVE 700 METEOR BLACK",
        "serial_number": "1234"
      },
      {
        "asset_id": "8e6f3d06-c405-488f-961a-70bef350d5d5",
        "serial_number": "SN67890",
        "name": "BIKE PRO 500"
      }
    ],
    "updated_at": "2024-11-06T14:15:00.000Z"
  },
  "meta": {
    "request_id": "req_update001",
    "response_time_ms": 156
  }
}
```

### POSTMAN curl

```bash
curl --location --request PATCH \
  'https://open-api.rocket-loyalty.com/functions/v1/api-assets/by-external-id/1MPBW00000001Lt4AI' \
--header 'Content-Type: application/json' \
--header 'x-api-key: YOUR_API_KEY_HERE' \
--data '{
  "status": "Active",
  "custom_fields": {
    "workTypeName": "Services Maintenance - Updated",
    "frequency": 3,
    "frequencyType": "Months"
  },
  "covered_assets": [
    { "external_id": "02iBW0000000f6QYAQA" },
    { "serial_number": "SN67890" }
  ]
}'
```

---

### Retrieve Asset / Maintenance Plan by ID

Retrieve existing asset or maintenance plan details.

| Item | Value |
|------|-------|
| Method | `GET` |

**URI Options:**

| URI | Lookup by |
|-----|-----------|
| `/api-assets/by-external-id/{external_id}` | External ID |
| `/api-assets/by-serial-number/{serial_number}` | Serial number |
| `/api-assets/by-asset-code/{asset_code}` | Internal code |
| `/api-assets/{asset_id}` | UUID |

### Example — Get Asset

```
GET https://open-api.rocket-loyalty.com/functions/v1/api-assets/by-external-id/02iBW0000000f6QYAQA
```

```json
{
  "success": true,
  "data": {
    "asset": {
      "asset_id": "7366abf1-59a3-4a57-b55e-8dc845213047",
      "external_id": "02iBW0000000f6QYAQA",
      "name": "EXCITE LIVE CLIMB LIVE 700 METEOR BLACK",
      "serial_number": "1234",
      "status": "Purchased",
      "purchase_date": "2023-08-06",
      "install_date": null,
      "asset_type": "ASSET",
      "user_id": null,
      "external_user_id": "001BW00000B3Ait",
      "custom_fields": { "..." },
      "covered_by_plans": []
    }
  },
  "meta": {
    "request_id": "req_get001",
    "response_time_ms": 78
  }
}
```

### Example — Get Maintenance Plan

```
GET https://open-api.rocket-loyalty.com/functions/v1/api-assets/by-external-id/1MPBW00000001Lt4AI
```

```json
{
  "success": true,
  "data": {
    "asset": {
      "asset_id": "d83789b7-5ec2-4135-8822-f30afb11997a",
      "external_id": "1MPBW00000001Lt4AI",
      "name": "6-Month Service Plan",
      "status": "Active",
      "asset_type": "MAINTENANCE_PLAN",
      "custom_fields": { "..." },
      "covered_assets": [
        {
          "asset_id": "7366abf1-59a3-4a57-b55e-8dc845213047",
          "external_id": "02iBW0000000f6QYAQA",
          "name": "EXCITE LIVE CLIMB LIVE 700 METEOR BLACK",
          "serial_number": "1234",
          "article_number": "D-T01-CD03-DFEG3A10AN00EA2S"
        }
      ]
    }
  },
  "meta": {
    "request_id": "req_get002",
    "response_time_ms": 95
  }
}
```

### POSTMAN curl

```bash
curl --location \
  'https://open-api.rocket-loyalty.com/functions/v1/api-assets/by-external-id/1MPBW00000001Lt4AI' \
--header 'x-api-key: YOUR_API_KEY_HERE'
```

---

### Create Purchase Transaction

Create purchase transactions in the Rocket Loyalty system.

| Item | Value |
|------|-------|
| Method | `POST` |
| URI | `/api-purchases` |
| Content-Type | `application/json` |

### Request Data Model

#### User Identification

| Field | Required | Type | Remark |
|-------|----------|------|--------|
| `external_user_id` | Mandatory* | String | Buyer phone number or Partner contact ID (example) |
| `user_id` | Mandatory* | UUID | Internal user ID (*at least one required) |
| `seller_external_user_id` | Optional | String | Seller phone number or ID |
| `seller_user_id` | Optional | UUID | Internal seller ID |

#### Transaction Details

| Field | Required | Type | Remark |
|-------|----------|------|--------|
| `final_amount` | Mandatory | Number | Net amount customer pays |
| `total_amount` | Optional | Number | Defaults to `final_amount` |
| `discount_amount` | Optional | Number | Default: `0` |
| `tax_amount` | Optional | Number | Default: `0` |

#### Transaction Metadata

| Field | Required | Type | Remark |
|-------|----------|------|--------|
| `transaction_number` | Optional | String | Auto-generated if not provided |
| `transaction_date` | Optional | Timestamp | Default: `NOW()`. Accepts ISO-8601 / timestamptz text (date-only `YYYY-MM-DD` also works). Persisted on `POST /api-purchases`. |
| `external_ref` | Optional | String | External order number (old: `external_order_no`) |
| `store_code` | Optional | String | Store identifier (old: `pos_store_code`) |
| `api_source` | Optional | String | Source system name (partner identifier) |

#### Transaction Control

| Field | Required | Type | Remark |
|-------|----------|------|--------|
| `status` | Optional | String | Default: `completed`. Options: `pending`, `processing`, `completed`, `cancelled`, `refunded` |
| `payment_status` | Optional | String | Default: `pending` |
| `processing_method` | Optional | String | Default: `queue`. Options: `queue`, `direct`, `skip` |
| `earn_currency` | Optional | Boolean | Default: `true` (awards points automatically) |
| `notes` | Optional | String | Additional notes |

#### Line Items

| Field | Required | Type | Remark |
|-------|----------|------|--------|
| `items` | Optional | Array | Product line items (see below) |

#### `items` Array Structure

| Field | Required | Type | Remark |
|-------|----------|------|--------|
| `sku_code` | Mandatory | String | Product variant code (old: `variant_code`) |
| `quantity` | Mandatory | Number | Quantity purchased (old: `qty`) |
| `unit_price` | Mandatory | Number | Price per unit |
| `line_total` | Optional | Number | Auto-calculated if not provided (old: `net_sale_value`) |
| `discount_amount` | Optional | Number | Default: `0` |
| `tax_amount` | Optional | Number | Default: `0` |

> **Note:** The old system's `variant_name` is not required — the system resolves product name from `sku_code` lookup in product catalog.

### Example Request

```json
{
  "external_user_id": "+66863210111",
  "seller_external_user_id": "+66812345678",
  "store_code": "store_a1",
  "external_ref": "test_bill",
  "api_source": "partner_system",
  "transaction_date": "2024-08-02",
  "status": "completed",
  "payment_status": "paid",
  "final_amount": 3000,
  "total_amount": 3000,
  "discount_amount": 0,
  "tax_amount": 0,
  "processing_method": "queue",
  "earn_currency": true,
  "items": [
    {
      "sku_code": "12345",
      "quantity": 3,
      "unit_price": 1000,
      "line_total": 3000,
      "discount_amount": 0,
      "tax_amount": 0
    }
  ]
}
```

### Example Response — 200 Success

```json
{
  "success": true,
  "data": {
    "success": true,
    "transaction_id": "a1b2c3d4-5678-90ab-cdef-1234567890ab",
    "transaction_number": "TXN20241106000001",
    "user_id": "c573479a-fe36-48be-9f6f-a559fffe9016",
    "user_resolved": true,
    "seller_id": null,
    "store_id": null,
    "items_created": 1,
    "unknown_skus": ["12345"],
    "unknown_store": false
  },
  "meta": {
    "request_id": "req_purchase001",
    "response_time_ms": 234
  }
}
```

> **Note:** `unknown_skus` lists any SKU codes not found in the product catalog. The purchase is still created successfully. Currency will be awarded via the configured `processing_method` (default: `queue`, within 60 seconds).

### Example Response — 404 User Not Found

```json
{
  "success": false,
  "error": "User not found",
  "code": "USER_NOT_FOUND",
  "details": "No user found with external_user_id '+66863210111'. Please create user first via /api-users endpoint.",
  "request_id": "req_purchase002"
}
```

### POSTMAN curl

```bash
curl --location 'https://open-api.rocket-loyalty.com/functions/v1/api-purchases' \
--header 'Content-Type: application/json' \
--header 'x-api-key: YOUR_API_KEY_HERE' \
--data '{
  "external_user_id": "+66863210111",
  "seller_external_user_id": "+66812345678",
  "store_code": "store_a1",
  "external_ref": "test_bill",
  "api_source": "partner_system",
  "transaction_date": "2024-08-02",
  "status": "completed",
  "payment_status": "paid",
  "final_amount": 3000,
  "total_amount": 3000,
  "items": [
    {
      "sku_code": "12345",
      "quantity": 3,
      "unit_price": 1000,
      "line_total": 3000
    }
  ]
}'
```

---

### Redeem Reward

Redeem a reward for a member using points.

| Item | Value |
|------|-------|
| Method | `POST` |
| URI | `/api-redemptions` |
| Content-Type | `application/json` |

### Request Data Model

| Field | Required | Type | Remark |
|-------|----------|------|--------|
| `user_id` | Mandatory* | UUID | Rocket user id (*or resolve via users API first) |
| `reward_id` | Mandatory | UUID | Reward to redeem |
| `quantity` | Optional | Number | Default: `1` |

> Member must have sufficient `points_balance`. Purchase earn can be asynchronous — use [§13 Post Wallet Transaction](#13-post-wallet-transaction) when you need a synchronous balance credit before redeem.

### Example Request

```json
{
  "user_id": "a740f0db-28af-4427-8590-d10126d27452",
  "reward_id": "50efbf36-6b86-4e80-8739-2b5bd940367c",
  "quantity": 1
}
```

### Example Response — 200 Success

```json
{
  "success": true,
  "data": {
    "success": true,
    "message": "Reward redeemed successfully",
    "details": null,
    "data": {
      "new_balance": 250,
      "total_points_deducted": 150,
      "records_created": 1,
      "redemptions": [
        {
          "qty": 1,
          "reward_id": "50efbf36-6b86-4e80-8739-2b5bd940367c",
          "reward_name": "Example Reward",
          "redemption_id": "2d653ccc-7e4f-400e-9be9-ee6c43c4ede6",
          "redemption_code": "RW5417013002",
          "points_deducted": 150,
          "promo_code": null
        }
      ]
    }
  },
  "meta": {
    "request_id": "…",
    "response_time_ms": 120
  }
}
```

Use `data.data.redemptions[0].redemption_code` for subsequent get / cancel / mark-used calls.

### POSTMAN curl

```bash
curl --location 'https://open-api.rocket-loyalty.com/functions/v1/api-redemptions' \
--header 'Content-Type: application/json' \
--header 'x-api-key: YOUR_API_KEY_HERE' \
--data '{
  "user_id": "a740f0db-28af-4427-8590-d10126d27452",
  "reward_id": "50efbf36-6b86-4e80-8739-2b5bd940367c",
  "quantity": 1
}'
```

---

### Get / Cancel / Mark-Used Redemption

### Get redemption

| Item | Value |
|------|-------|
| Method | `GET` |
| URI | `/api-redemptions/{redemption_code}` |
| Alt | `/api-redemptions?redemption_id={uuid}` |

### Mark used

| Item | Value |
|------|-------|
| Method | `POST` |
| URI | `/api-redemptions/{redemption_code}/mark-used` |

```json
{ "notes": "Used at store A" }
```

### Cancel

| Item | Value |
|------|-------|
| Method | `POST` |
| URI | `/api-redemptions/{redemption_code}/cancel` |

```json
{ "reason": "Customer cancelled" }
```

### POSTMAN curl — mark used

```bash
curl --location --request POST \
  'https://open-api.rocket-loyalty.com/functions/v1/api-redemptions/RW5417013002/mark-used' \
--header 'Content-Type: application/json' \
--header 'x-api-key: YOUR_API_KEY_HERE' \
--data '{ "notes": "smoke" }'
```

### POSTMAN curl — cancel

```bash
curl --location --request POST \
  'https://open-api.rocket-loyalty.com/functions/v1/api-redemptions/RW5417013002/cancel' \
--header 'Content-Type: application/json' \
--header 'x-api-key: YOUR_API_KEY_HERE' \
--data '{ "reason": "customer request" }'
```

---

### Post Wallet Transaction

Post a **points** or **ticket** earn or burn ledger delta. This is not an absolute balance setter.

| Item | Value |
|------|-------|
| Method | `POST` |
| URI | `/api-wallet/transactions` |
| Content-Type | `application/json` |

`currency` defaults to `points`. Points balance remains on `GET /api-users/...` → `points_balance`. Ticket balances are on the same GET as `ticket_balances[]`. Store-credit / Shopify credit ticket types (`is_credit = true`) are rejected.

### Request Data Model

#### User identification (exactly one)

| Field | Required | Type | Remark |
|-------|----------|------|--------|
| `user_id` | One of | UUID | Rocket user id |
| `external_user_id` | One of | String | Partner external user id |
| `tel` | One of | String | Phone |
| `email` | One of | String | Email |
| `line_id` | One of | String | LINE id |

#### Transaction

| Field | Required | Type | Remark |
|-------|----------|------|--------|
| `transaction_type` | Mandatory | String | `earn` or `burn` |
| `amount` | Mandatory | Integer | Positive integer |
| `dedup_key` | Mandatory | String | 1–200 chars; unique per merchant for a given payload |
| `currency` | Optional | String | `points` (default) or `ticket` |
| `ticket_type_id` | One of when `currency=ticket` | UUID | Ticket type id for this merchant |
| `ticket_code` | One of when `currency=ticket` | String | Merchant-unique ticket code (alternative to id) |
| `description` | Optional | String | Human-readable note |
| `metadata` | Optional | Object | Partner metadata; keys beginning with `_` are reserved |

When `currency=ticket`, provide exactly one of `ticket_type_id` or `ticket_code`. Ticket types must be active and non-credit. Earn also requires the type’s validity window (if set) to include now.

Ticket writes create **one ledger row per unit**. A post of `amount: 3` writes 3 rows. History lists those unit rows.

### Idempotency

- Same `dedup_key` + same payload (including currency and ticket type) → `200` with `already_processed: true` (no second write).
- Same `dedup_key` + different amount/user/type/currency/ticket type → `409` `IDEMPOTENCY_CONFLICT`.
- Burn that would make that currency’s balance negative → `400` `INSUFFICIENT_BALANCE` (hard fail, no partial write).
- Pooled ticket type with too few unassigned codes → `400` `INSUFFICIENT_TICKET_POOL`.

### Example Request — Earn

```json
{
  "external_user_id": "EXT_USER_002",
  "transaction_type": "earn",
  "amount": 100,
  "dedup_key": "partner:order_456:earn",
  "description": "Order 456 loyalty credit",
  "metadata": {
    "order_id": "456"
  }
}
```

### Example Response — 201 Created

```json
{
  "success": true,
  "data": {
    "success": true,
    "already_processed": false,
    "wallet_ledger_id": "f0d2d7b2-ea73-43a0-b46b-91d1da9a153b",
    "user_id": "a740f0db-28af-4427-8590-d10126d27452",
    "transaction_type": "earn",
    "amount": 100,
    "currency": "points",
    "balance_after": 100,
    "points_balance": 100,
    "dedup_key": "partner:order_456:earn",
    "created_at": "2026-08-05T11:09:56.648809+00:00"
  },
  "meta": {
    "request_id": "…",
    "response_time_ms": 45
  }
}
```

### Example Response — 200 Idempotent Replay

Same body as create, with `"already_processed": true` and the original `wallet_ledger_id`.

### Example Response — 409 Conflict

```json
{
  "success": false,
  "error": "Idempotency key already used with a different payload",
  "code": "IDEMPOTENCY_CONFLICT",
  "dedup_key": "partner:order_456:earn",
  "request_id": "…"
}
```

### POSTMAN curl

```bash
curl --location 'https://open-api.rocket-loyalty.com/functions/v1/api-wallet/transactions' \
--header 'Content-Type: application/json' \
--header 'x-api-key: YOUR_API_KEY_HERE' \
--data '{
  "external_user_id": "EXT_USER_002",
  "transaction_type": "earn",
  "amount": 100,
  "dedup_key": "partner:order_456:earn",
  "description": "Order 456 loyalty credit"
}'
```

### Example Request — Earn tickets

```json
{
  "external_user_id": "EXT_USER_002",
  "transaction_type": "earn",
  "amount": 3,
  "currency": "ticket",
  "ticket_code": "RAFFLE_MAY",
  "dedup_key": "partner:order_456:raffle",
  "description": "Order 456 raffle tickets"
}
```

### Example Response — 201 Created (ticket)

```json
{
  "success": true,
  "data": {
    "success": true,
    "already_processed": false,
    "wallet_ledger_id": "f0d2d7b2-ea73-43a0-b46b-91d1da9a153b",
    "user_id": "a740f0db-28af-4427-8590-d10126d27452",
    "transaction_type": "earn",
    "amount": 3,
    "currency": "ticket",
    "ticket_type_id": "c0000000-0000-0000-0000-000000000001",
    "ticket_code": "RAFFLE_MAY",
    "balance_after": 3,
    "ticket_balance": 3,
    "dedup_key": "partner:order_456:raffle",
    "created_at": "2026-08-19T04:00:00.000000+00:00"
  },
  "meta": {
    "request_id": "…",
    "response_time_ms": 45
  }
}
```

---

### List Wallet Transactions

| Item | Value |
|------|-------|
| Method | `GET` |
| URI | `/api-wallet/transactions` |

### Query parameters

Exactly one user identifier (`user_id`, `external_user_id`, `tel`, `email`, or `line_id`), plus:

| Param | Required | Type | Remark |
|-------|----------|------|--------|
| `from` | Optional | Timestamptz | `created_at >= from` |
| `to` | Optional | Timestamptz | `created_at < to` (require `from < to` when both set) |
| `transaction_type` | Optional | String | `earn` or `burn` |
| `currency` | Optional | String | `points` (default) or `ticket`. Default stays points-only. |
| `ticket_type_id` | Optional | UUID | Filter ticket history to one type (`currency=ticket` only) |
| `ticket_code` | Optional | String | Same filter by merchant ticket code |
| `limit` | Optional | Integer | 1–100, default 50 |
| `offset` | Optional | Integer | Default 0 |

### Example Response — 200

```json
{
  "success": true,
  "data": {
    "success": true,
    "user_id": "a740f0db-28af-4427-8590-d10126d27452",
    "total_count": 2,
    "limit": 50,
    "offset": 0,
    "transactions": [
      {
        "id": "f0d2d7b2-ea73-43a0-b46b-91d1da9a153b",
        "created_at": "2026-08-05T11:09:56.648809+00:00",
        "currency": "points",
        "transaction_type": "earn",
        "component": "adjustment",
        "amount": 100,
        "signed_amount": 100,
        "source_type": "manual",
        "description": "Order 456 loyalty credit",
        "balance_before": 0,
        "balance_after": 100,
        "expiry_date": null,
        "dedup_key": "partner:order_456:earn"
      }
    ]
  },
  "meta": {
    "request_id": "…",
    "response_time_ms": 30
  }
}
```

`dedup_key` in the response is the **client** key when present — never an internal prefixed key.

### POSTMAN curl

```bash
curl --location \
  'https://open-api.rocket-loyalty.com/functions/v1/api-wallet/transactions?external_user_id=EXT_USER_002&limit=20&transaction_type=earn' \
--header 'x-api-key: YOUR_API_KEY_HERE'
```

---

### Error codes

### Common Errors

| Code | Status | Description |
|------|--------|-------------|
| `MISSING_API_KEY` | 401 | `x-api-key` header not provided |
| `INVALID_API_KEY` | 401 | API key invalid or expired |
| `USER_NOT_FOUND` | 404 | User identifier not found |
| `ASSET_NOT_FOUND` | 404 | Asset identifier not found |
| `ASSET_EXISTS` | 409 | Asset already exists (`upsert=false`) |
| `USER_EXISTS` | 409 | User already exists (`upsert=false`) |
| `VALIDATION_FAILED` | 400 | Field validation failed |
| `INSUFFICIENT_BALANCE` | 400 | Wallet burn would exceed points or that ticket type’s balance |
| `INSUFFICIENT_TICKET_POOL` | 400 | Pooled ticket type does not have enough unassigned codes |
| `INVALID_CURRENCY` | 400 | `currency` is not `points` or `ticket` |
| `TICKET_TYPE_REQUIRED` | 400 | Ticket post missing `ticket_type_id` / `ticket_code` |
| `TICKET_TYPE_NOT_FOUND` | 400 | Ticket type unknown for this merchant |
| `TICKET_TYPE_NOT_AVAILABLE` | 400 | Ticket type inactive or outside validity (earn) |
| `TICKET_TYPE_CREDIT_FORBIDDEN` | 400 | Store-credit / Shopify credit types cannot be posted |
| `IDEMPOTENCY_CONFLICT` | 409 | Wallet `dedup_key` reused with a different payload |
| `TRANSACTION_LOCKED` | 400 | Cannot modify completed transaction |
| `GATEWAY_CONFIG_ERROR` | 500 | API gateway misconfigured (ops) |

### Error Response Format

```json
{
  "success": false,
  "error": "Error message",
  "code": "ERROR_CODE",
  "details": "Additional details",
  "request_id": "uuid"
}
```

---

### Field mapping reference (legacy migrations)

### Asset Fields (Old System → New)

| Old Field Name | New Location | New Field Name | Notes |
|----------------|-------------|----------------|-------|
| `id` | `external_id` | `external_id` | Partner asset external ID |
| `name` | `name` | `name` | Asset name |
| `serialNumber` | `serial_number` | `serial_number` | Equipment serial |
| `status` | `status` | `status` | Asset status |
| `purchaseDate` | `purchase_date` | `purchase_date` | Purchase date |
| `installDate` | `install_date` | `install_date` | Installation date |
| `warrantyPeriodTechnogym` | `custom_fields` | `warrantyPeriodTechnogym` | Direct mapping |
| `warrantyPeriodExtended` | `custom_fields` | `warrantyPeriodExtended` | Direct mapping |
| `usageEndDate` | `custom_fields` | `usageEndDate` | Direct mapping |
| `productName` | `custom_fields` | `productName` | Separated from name |
| `productCode` | `custom_fields` | `productCode` | Direct mapping |
| `product2Id` | `custom_fields` | `product2Id` | Direct mapping |
| `articleNumber` | `custom_fields` | `articleNumber` | Direct mapping |
| `salesOrder` | `custom_fields` | `salesOrder` | Direct mapping |
| `recordTypeId` | `custom_fields` | `recordTypeId` | Direct mapping |
| `quantity` | `custom_fields` | `quantity` | Direct mapping |
| `project` | `custom_fields` | `project` | Direct mapping |
| `opportunity` | `custom_fields` | `opportunity` | Direct mapping |
| `opportunityProduct` | `custom_fields` | `opportunityProduct` | Direct mapping |
| `accountId` | `custom_fields` | `accountId` | Direct mapping |
| `contactId` | `custom_fields` | `contactId` | Direct mapping |
| `parentId` | `custom_fields` | `parentId` | Direct mapping |
| `doNumber` | `custom_fields` | `doNumber` | Direct mapping |
| `doDate` | `custom_fields` | `doDate` | Direct mapping |
| `cnNumber` | `custom_fields` | `cnNumber` | Direct mapping |
| `price` | `custom_fields` | `price` | Direct mapping |
| `description` | `custom_fields` | `description` | Direct mapping |

### Maintenance Plan Fields (Old → New)

| Old Field Name | New Location | New Field Name | Notes |
|----------------|-------------|----------------|-------|
| `id` | `external_id` | `external_id` | Partner maintenance-plan ID |
| `name` | `name` | `name` | Plan name |
| `status` | `status` | `status` | Plan status |
| `maintenancePlanNumber` | `custom_fields` | `maintenancePlanNumber` | Direct mapping |
| `maintenancePlanType` | `custom_fields` | `maintenancePlanType` | Direct mapping |
| `maintenancePlanStatus` | `custom_fields` | `maintenancePlanStatus` | Direct mapping |
| `maintenancePlanTitle` | `custom_fields` | `maintenancePlanTitle` | New field |
| `workTypeName` | `custom_fields` | `workTypeName` | Direct mapping |
| `workTypeId` | `custom_fields` | `workTypeId` | New field |
| `startDate` | `custom_fields` | `startDate` | Direct mapping |
| `endDate` | `custom_fields` | `endDate` | Direct mapping |
| `frequency` | `custom_fields` | `frequency` | Direct mapping |
| `frequencyType` | `custom_fields` | `frequencyType` | Direct mapping |
| `generationTimeframe` | `custom_fields` | `generationTimeframe` | Direct mapping |
| `generationTimeframeType` | `custom_fields` | `generationTimeframeType` | Direct mapping |
| `nextSuggestedMaintenanceDate` | `custom_fields` | `nextSuggestedMaintenanceDate` | Direct mapping |
| `mpRenewal` | `custom_fields` | `mpRenewal` | Direct mapping |
| `approvalStatus` | `custom_fields` | `approvalStatus` | Direct mapping |
| `allAssetInstalled` | `custom_fields` | `allAssetInstalled` | Direct mapping |
| `activeExpire` | `custom_fields` | `activeExpire` | Direct mapping |
| `maintenanceAssets` | `covered_assets` | `covered_assets` | Enhanced relationship structure |

### Bill Creation Fields (Old → New)

| Old Field Name | New Field Name | Location | Notes |
|----------------|---------------|----------|-------|
| `organization_id` | _(via API key)_ | Implicit | Merchant context from authentication |
| `third_party_name` | `api_source` | Body | Partner source system name |
| `pos_store_code` | `store_code` | Body | Direct mapping |
| `external_order_no` | `external_ref` | Body | External order reference |
| `buyer_phone_number` | `external_user_id` | Body | Phone number or user reference |
| `seller_phone_number` | `seller_external_user_id` | Body | Seller phone or reference |
| `sale_date` | `transaction_date` | Body | Transaction date |
| `variant_code_list` | `items` | Body | Array of line items |
| `variant_code_list[].variant_code` | `items[].sku_code` | Body | Product SKU code |
| `variant_code_list[].variant_name` | _(auto-resolved)_ | — | Looked up from product catalog |
| `variant_code_list[].qty` | `items[].quantity` | Body | Quantity purchased |
| `variant_code_list[].net_sale_value` | `items[].line_total` | Body | Line total amount |

### User Fields Reference

| Field Name | Type | Default | Available Values | Notes |
|------------|------|---------|-----------------|-------|
| `user_stage` | String | `lead` | `lead`, `account`, `prospect`, `customer`, `churned` | Customer lifecycle stage |
| `brand_interest` | Array | `[]` | `luxury`, `sports`, `electronics`, `fashion`, `home` | Stored in form_submissions |

---

### Data formats

### Success Response Format

All successful responses follow this structure:

```json
{
  "success": true,
  "data": { },
  "meta": {
    "request_id": "uuid",
    "response_time_ms": 250
  }
}
```

### Standard Headers

**Request Headers:**

- `x-api-key` — Your API key (required)
- `Content-Type: application/json` — for POST/PATCH

**Response Headers:**

- `X-Request-Id` — Unique request identifier for tracking
- `X-Response-Time` — Response time in milliseconds

### Data Type Conventions

| Type | Format |
|------|--------|
| Dates | `YYYY-MM-DD` (e.g. `2024-10-20`) |
| Timestamps | ISO 8601 with timezone |
| Numbers | Integers or decimals, JSON number type (no quotes) |
| Booleans | `true` or `false` (JSON boolean, not string) |
| Arrays | `["value1", "value2"]` — empty arrays `[]` allowed |
| UUIDs | `xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx` (case insensitive) |
| Phone numbers | `+66XXXXXXXXX` (E.164). Both `0XX` and `+66` accepted on input. |

## Related

- **Authentication.md** — Admin JWT and member session (not Open API keys).
- **Signup_Login.md** — Member profile fields overlapping user upsert payloads.
- **Asset.md** — Parking vehicles vs Open API asset catalog.
- **Purchase_Transaction.md** — Purchase ledger, earn chokepoint, cancel semantics.
- **Reward.md** — Redemption types and entitlement products.
- **Currency.md** — Wallet ledger, ticket types, Open API wallet side effects.
