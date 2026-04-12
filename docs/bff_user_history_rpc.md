# User history BFF RPCs — backend integration

How a backend or API layer should call **`bff_get_user_history_menu`** and **`bff_get_entity_history`** over Supabase **PostgREST** (`/rest/v1/rpc/...`), including auth, merchant context, parameters, response shapes, and example `curl` calls.

**Related:** Field-by-field examples per entity → `docs/bff_entity_history_field_reference.csv`.

---

## Prerequisites

| Requirement | Why |
|-------------|-----|
| **Supabase project URL** | Host for `POST /rest/v1/rpc/<function_name>` |
| **`apikey`** | Usually the **anon** public key (or the key your gateway uses for REST) |
| **`Authorization: Bearer <JWT>`** | End-user access token so `auth.uid()` resolves to the **member** whose history you are loading |
| **Merchant context** | Both functions use `get_current_merchant_id()`. If that returns `NULL`, history calls return no rows or `{ success: false, ... }` for the menu |

**Merchant context** is resolved inside Postgres (priority order):

1. Header **`x-merchant-id`** (common for WeWeb / multi-tenant frontends)
2. JWT claim **`merchant_id`**
3. Else lookup via **`admin_users`** or **`user_accounts`** for `auth.uid()`

**Backend responsibility:** Forward the **same headers and JWT** your app already uses for other BFF RPCs (especially **`x-merchant-id`** when the stack relies on it).

---

## 1. `bff_get_user_history_menu()`

### Purpose

Returns the **config-driven menu** of history sections (labels, icons, tab keys, sub-filters). It does **not** return timeline rows. Call it once when building the history hub UI, then call `bff_get_entity_history` per selected section.

The menu function is **merchant-scoped** (`get_current_merchant_id()`); it does **not** use `auth.uid()`. History rows from `bff_get_entity_history` **do** use `auth.uid()` — always send the **member’s JWT** for history calls.

### HTTP

```http
POST /rest/v1/rpc/bff_get_user_history_menu
```

**Body:** empty JSON object `{}` (no parameters).

### Response shape (JSON object)

Top-level JSONB from Postgres:

| Field | Type | Meaning |
|-------|------|---------|
| `success` | boolean | `true` if menu built |
| `menu_items` | array | Ordered list of enabled menu entries |
| `error` | string | Present when `success` is `false` (e.g. no merchant / no plan) |

Each **`menu_items[]`** element typically includes:

- `key` — matches `p_entity` for history (`reward`, `tier`, `currency`, `upload_receipt`, `campaigns`, `purchases`)
- `label` — display name
- `enabled`, `display_order`
- `filter_field`, `default_filter`, `sub_filters` — drive which **`p_filter`** values the client should send for that section

### Example `curl`

```bash
export SUPABASE_URL="https://<PROJECT_REF>.supabase.co"
export SUPABASE_ANON_KEY="<your_anon_key>"
export USER_JWT="<end_user_access_token>"
export MERCHANT_ID="<merchant_uuid>"

curl -sS -X POST "${SUPABASE_URL}/rest/v1/rpc/bff_get_user_history_menu" \
  -H "apikey: ${SUPABASE_ANON_KEY}" \
  -H "Authorization: Bearer ${USER_JWT}" \
  -H "Content-Type: application/json" \
  -H "x-merchant-id: ${MERCHANT_ID}" \
  -d '{}'
```

### Example success snippet

```json
{
  "success": true,
  "menu_items": [
    {
      "key": "reward",
      "label": "Rewards",
      "enabled": true,
      "display_order": 1,
      "filter_field": "status",
      "default_filter": "redeemed",
      "sub_filters": [
        { "key": "redeemed", "label": "My Rewards", "display_order": 1 },
        { "key": "used", "label": "Used", "display_order": 2 },
        { "key": "expired", "label": "Expired", "display_order": 3 }
      ],
      "icon": "https://api.iconify.design/solar/gift-bold.svg?color=%236366F1",
      "icon_bg": "#6366F126"
    }
  ]
}
```

---

## 2. `bff_get_entity_history`

### Purpose

Returns **one row per history item** for the signed-in user (`auth.uid()`), scoped to the current merchant. The backend chooses **`p_entity`** (and usually **`p_filter`**) from the menu item the user selected.

### HTTP

```http
POST /rest/v1/rpc/bff_get_entity_history
```

### Request body (JSON parameters)

| Parameter | Type | Default | Required | Notes |
|-----------|------|---------|----------|--------|
| `p_entity` | text | — | **Yes** | `reward` \| `tier` \| `currency` \| `upload_receipt` \| `campaigns` \| `purchases` |
| `p_filter` | text | `NULL` | Depends on entity | Sub-tab / subtype; see table below |
| `p_limit` | int | 50 | No | Page size |
| `p_offset` | int | 0 | No | Pagination offset |
| `p_language` | text | `NULL` | No | Passed through for **reward** name translation; other entities ignore it in current SQL |

### `p_entity` → which `p_filter` values matter

| `p_entity` | Typical `p_filter` | Meaning |
|------------|--------------------|---------|
| `reward` | `redeemed`, `used`, `expired`, `pending` | Align with menu / redemption state |
| `tier` | usually omit or `NULL` | No sub-filter branch in SQL |
| `currency` | `points` or `ticket` | Which wallet currency stream |
| `upload_receipt` | usually omit | No sub-filter branch |
| `campaigns` | `mission`, `referral`, `checkin`, `activity` | Picks underlying ledger |
| `purchases` | usually omit | No sub-filter branch |

Invalid `p_entity` returns **no rows** (empty JSON array `[]`).

### Response shape (JSON array)

PostgREST returns a **JSON array of row objects** (not wrapped in `{ "data": ... }` in raw HTTP).

Each row has the same **column names** (snake_case):

| Column | Type (logical) | Handling notes |
|--------|----------------|----------------|
| `id` | uuid | Stable id for keys / deep links |
| `title` | text | Primary line |
| `description` | text | Secondary line; may be null |
| `status` | text | Domain status (earn/burn, redeemed, mission progress, etc.) |
| `filter` | text | Subtype key for UI chips (e.g. `mission`, `points`); use with tabs |
| `icon` | text (URL) | Small pictogram |
| `icon_bg` | text (color) | Usually `#RRGGBBAA` — background **tint** behind the icon |
| `image` | text (URL) | Prefer for photo-style tiles; often same as `icon` if no asset |
| `results` | jsonb (array) | “Amount chips”: `{ type, amount, label, icon, sign }` |
| `dates` | jsonb (array) | `{ key, label, value }` for timestamps |
| `details` | jsonb (array) | `{ key, label, value }` for extra facts |
| `action` | jsonb or null | **Mostly null**; **reward** rows may return `{ "type": "use_reward", "label": "Use" }` |
| `metadata` | jsonb (object) | Ids and raw fields for navigation or APIs |

**Rendering recipe:** Draw **`title` / `description` / `status`**; place **`icon`** (or **`image`**) on a circle filled with **`icon_bg`**; render **`results`** as badges; list **`dates`** and **`details`** as label–value rows; if **`action`** is non-null, show a primary button; use **`metadata`** for “view detail” routes without exposing everything in copy.

### Example `curl` — rewards (redeemed tab)

```bash
curl -sS -X POST "${SUPABASE_URL}/rest/v1/rpc/bff_get_entity_history" \
  -H "apikey: ${SUPABASE_ANON_KEY}" \
  -H "Authorization: Bearer ${USER_JWT}" \
  -H "Content-Type: application/json" \
  -H "x-merchant-id: ${MERCHANT_ID}" \
  -d '{
    "p_entity": "reward",
    "p_filter": "redeemed",
    "p_limit": 20,
    "p_offset": 0,
    "p_language": "th"
  }'
```

### Example `curl` — currency (points)

```bash
curl -sS -X POST "${SUPABASE_URL}/rest/v1/rpc/bff_get_entity_history" \
  -H "apikey: ${SUPABASE_ANON_KEY}" \
  -H "Authorization: Bearer ${USER_JWT}" \
  -H "Content-Type: application/json" \
  -H "x-merchant-id: ${MERCHANT_ID}" \
  -d '{
    "p_entity": "currency",
    "p_filter": "points",
    "p_limit": 50,
    "p_offset": 0
  }'
```

### Example `curl` — campaigns (missions)

```bash
curl -sS -X POST "${SUPABASE_URL}/rest/v1/rpc/bff_get_entity_history" \
  -H "apikey: ${SUPABASE_ANON_KEY}" \
  -H "Authorization: Bearer ${USER_JWT}" \
  -H "Content-Type: application/json" \
  -H "x-merchant-id: ${MERCHANT_ID}" \
  -d '{
    "p_entity": "campaigns",
    "p_filter": "mission",
    "p_limit": 30,
    "p_offset": 0
  }'
```

### Example `curl` — purchases

```bash
curl -sS -X POST "${SUPABASE_URL}/rest/v1/rpc/bff_get_entity_history" \
  -H "apikey: ${SUPABASE_ANON_KEY}" \
  -H "Authorization: Bearer ${USER_JWT}" \
  -H "Content-Type: application/json" \
  -H "x-merchant-id: ${MERCHANT_ID}" \
  -d '{
    "p_entity": "purchases",
    "p_limit": 50,
    "p_offset": 0
  }'
```

### Example row (illustrative)

```json
{
  "id": "a1b2c3d4-e5f6-7890-abcd-ef1234567890",
  "title": "Free Coffee",
  "description": "PROMO2026",
  "status": "redeemed",
  "filter": "redeemed",
  "icon": "https://api.iconify.design/solar/gift-bold.svg?color=%236366F1",
  "icon_bg": "#6366F126",
  "image": "https://cdn.example.com/rewards/coffee.png",
  "results": [
    {
      "type": "points",
      "amount": -500,
      "label": "500",
      "icon": "https://api.iconify.design/tabler/circle-letter-p-filled.svg?color=%23DAA520",
      "sign": "negative"
    }
  ],
  "dates": [
    { "key": "redeemed_at", "label": "Redeemed", "value": "2026-03-18T14:30:00+00:00" },
    { "key": "created_at", "label": "Created", "value": "2026-03-18T14:25:00+00:00" }
  ],
  "details": [
    { "key": "qty", "label": "Quantity", "value": "1" }
  ],
  "action": { "type": "use_reward", "label": "Use" },
  "metadata": {
    "reward_id": "…",
    "fulfillment_method": "…",
    "online_store": null,
    "external_ref_id": null
  }
}
```

---

## Suggested backend flow

1. **Authenticate** the member; obtain **user JWT**.
2. Resolve **merchant id** the same way as the rest of your BFF (header / claim / session).
3. **`bff_get_user_history_menu`** → build tabs and sub-filters from `menu_items`.
4. On tab change: map `menu_items[].key` → **`p_entity`**; map selected sub-tab → **`p_filter`** using `default_filter` / `sub_filters` from the menu item.
5. **`bff_get_entity_history`** with pagination (`p_limit`, `p_offset`).
6. Map each row to UI using the column handling table above; parse **`results`**, **`dates`**, **`details`**, **`metadata`** as JSON.

---

## Troubleshooting

| Symptom | Likely cause |
|---------|----------------|
| Menu `{ "success": false, "error": "No merchant context" }` | Missing / wrong **`x-merchant-id`** or JWT merchant claim; user not in **`user_accounts`** for that merchant |
| Menu `{ "success": false, "error": "No plan assigned" }` | Merchant has no **`plan_id`** in **`merchant_master`** |
| History always `[]` | Wrong merchant; wrong user JWT; **`p_entity`** typo; **`p_filter`** mismatch (e.g. `campaigns` without `mission` / `referral` / …) |
| Rewards not translated | Pass **`p_language`** (e.g. `th`); ensure **`translations`** rows exist for rewards |

---

## Non-curl clients

- **Supabase JS:** `supabase.rpc('bff_get_user_history_menu', {})` and `supabase.rpc('bff_get_entity_history', { p_entity: 'reward', p_filter: 'redeemed', p_limit: 20, p_offset: 0, p_language: 'en' })` with the same global headers (e.g. `x-merchant-id`) configured on the client.
