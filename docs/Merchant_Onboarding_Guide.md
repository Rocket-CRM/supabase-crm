# Merchant Onboarding — `admin_init_merchant_with_owner`

**Endpoint:** `POST https://wkevmsedchftztoolkmi.supabase.co/rest/v1/rpc/admin_init_merchant_with_owner`

**Auth:** Service role key required (both `apikey` and `Authorization` headers).

**What it does:**
1. Creates a new merchant in `merchant_master`
2. Creates or links an auth user in `auth.users`
3. Creates an `admin_users` record with the **owner** role
4. Creates a default `USER_PROFILE` form template
5. Sets `merchant_id` in the auth user's metadata

---

## Parameters

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `p_merchant_name` | text | Yes | Display name for the merchant |
| `p_merchant_code` | text | Yes | Unique slug (used in URLs, must not exist) |
| `p_owner_email` | text | Yes | Owner's email address |
| `p_owner_password` | text | No | Set a permanent password. If omitted, a random one is generated. |
| `p_owner_name` | text | No | Owner's display name. Defaults to the part before `@` in email. |
| `p_owner_auth_user_id` | uuid | No | Explicitly link to a known auth user by ID (skips email lookup). |

---

## Scenarios

### 1. New user — auto-generated temp password

The simplest call. A random password is generated and returned in the response.

```bash
curl -X POST 'https://wkevmsedchftztoolkmi.supabase.co/rest/v1/rpc/admin_init_merchant_with_owner' \
  -H 'apikey: YOUR_SERVICE_ROLE_KEY' \
  -H 'Authorization: Bearer YOUR_SERVICE_ROLE_KEY' \
  -H 'Content-Type: application/json' \
  -d '{
    "p_merchant_name": "Acme Corp",
    "p_merchant_code": "acme",
    "p_owner_email": "owner@acme.com"
  }'
```

**Response:**
```json
{
  "success": true,
  "merchant_id": "uuid",
  "merchant_code": "acme",
  "merchant_name": "Acme Corp",
  "admin_user_id": "uuid",
  "owner_email": "owner@acme.com",
  "owner_auth_user_id": "uuid",
  "auth_user_created": true,
  "temporary_password": "a1b2c3d4e5f6...",
  "user_profile_form_id": "uuid"
}
```

**Login:** Use `owner@acme.com` + the `temporary_password` from the response. Change it afterwards.

---

### 2. New user — chosen permanent password

Pass `p_owner_password` to set a known password immediately.

```bash
curl -X POST 'https://wkevmsedchftztoolkmi.supabase.co/rest/v1/rpc/admin_init_merchant_with_owner' \
  -H 'apikey: YOUR_SERVICE_ROLE_KEY' \
  -H 'Authorization: Bearer YOUR_SERVICE_ROLE_KEY' \
  -H 'Content-Type: application/json' \
  -d '{
    "p_merchant_name": "Mesoestetic Thailand",
    "p_merchant_code": "mesoestetic",
    "p_owner_email": "owner@mesoestetic.co.th",
    "p_owner_password": "MySecureP@ss123",
    "p_owner_name": "Admin Mesoestetic"
  }'
```

**Response:**
```json
{
  "success": true,
  "auth_user_created": true,
  "temporary_password": "MySecureP@ss123",
  ...
}
```

**Login:** Use the password you chose. `temporary_password` in the response will match what you provided.

---

### 3. Existing user — assign new merchant to existing admin

If the email already exists in `auth.users` (e.g., the person already owns another merchant), the function **does not** create a new auth user. It just creates a new `admin_users` record linking the existing auth user to the new merchant.

```bash
curl -X POST 'https://wkevmsedchftztoolkmi.supabase.co/rest/v1/rpc/admin_init_merchant_with_owner' \
  -H 'apikey: YOUR_SERVICE_ROLE_KEY' \
  -H 'Authorization: Bearer YOUR_SERVICE_ROLE_KEY' \
  -H 'Content-Type: application/json' \
  -d '{
    "p_merchant_name": "BMW Performance",
    "p_merchant_code": "bmwperformance",
    "p_owner_email": "owner@existing-merchant.com"
  }'
```

**Response:**
```json
{
  "success": true,
  "auth_user_created": false,
  "temporary_password": null,
  ...
}
```

**Key differences:**
- `auth_user_created` is `false` — no new auth user was made
- `temporary_password` is `null` — use the existing password
- `p_owner_password` is ignored even if provided (existing user keeps their password)

**Login:** Use the same email + password as before. The admin now has access to both merchants.

---

### 4. Explicit auth user ID

If you already know the `auth.users` UUID (e.g., from the Supabase dashboard), pass it directly. Skips the email lookup entirely.

```bash
curl -X POST 'https://wkevmsedchftztoolkmi.supabase.co/rest/v1/rpc/admin_init_merchant_with_owner' \
  -H 'apikey: YOUR_SERVICE_ROLE_KEY' \
  -H 'Authorization: Bearer YOUR_SERVICE_ROLE_KEY' \
  -H 'Content-Type: application/json' \
  -d '{
    "p_merchant_name": "Partner Store",
    "p_merchant_code": "partnerstore",
    "p_owner_email": "admin@partner.com",
    "p_owner_auth_user_id": "a190a2e2-89de-4b6d-bc89-ed9b6ef84812"
  }'
```

**Login:** Use the existing credentials for that auth user. Returns error `AUTH_USER_NOT_FOUND` if the UUID doesn't exist.

---

## Decision Flowchart

```
Is p_owner_auth_user_id provided?
├─ YES → Use that auth user directly (must exist, else error)
└─ NO  → Look up auth.users by email
         ├─ Email found → Link existing user (no password change)
         └─ Email NOT found → Create new auth user
              ├─ p_owner_password provided? → Use it as permanent password
              └─ p_owner_password omitted?  → Generate random temp password
```

---

## Error Codes

| Error Code | Meaning |
|------------|---------|
| `UNAUTHORIZED` | Not called with service role key |
| `MERCHANT_CODE_EXISTS` | `p_merchant_code` already taken |
| `AUTH_USER_NOT_FOUND` | `p_owner_auth_user_id` UUID doesn't exist in auth.users |
| `SYSTEM_ERROR` | Owner role not found (system data missing) |
| `UNEXPECTED_ERROR` | Catch-all with `error_message` detail |

---

## What gets created

| Resource | Details |
|----------|---------|
| `merchant_master` row | With `name` and `merchant_code` |
| `auth.users` row | Only if email is new (or `p_owner_auth_user_id` not provided and email not found) |
| `auth.identities` row | Only if new auth user created (email provider) |
| `admin_users` row | Owner role, linked to merchant + auth user |
| `form_templates` row | Default `USER_PROFILE` form (published) |
| `user_field_config` seed | Auto-triggered by merchant_master insert |

---

## After onboarding

1. Owner logs into the admin dashboard with their email + password
2. Merchant context is resolved automatically via `get_current_merchant_id()` (reads `user_metadata.merchant_id` from JWT, or falls back to `admin_users` lookup)
3. Owner can invite additional team members from the admin dashboard
