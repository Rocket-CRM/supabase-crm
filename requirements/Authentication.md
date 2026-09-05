# Authentication System - Complete Guide

**Version:** 1.0  
**Last Updated:** December 2025  
**Project:** Supabase CRM

## Overview

The CRM uses a **dual authentication system**:
1. **End-User Authentication** - Custom auth with LINE + Phone OTP
2. **Admin Authentication** - Supabase Auth (standard email/password)

Both systems generate **Supabase-compatible JWTs** that work with RPC functions, PostgREST, and Row Level Security.

---

## Critical JWT Secret Requirement

### The Golden Rule

**Custom JWT Secret MUST Equal Supabase's Legacy JWT Secret**

```
Edge Function (bff-auth-complete):
  Signs JWTs with: SUPABASE_JWT_SECRET (Supabase's project secret)
        ↓
Supabase RPC/PostgREST:
  Validates JWTs with: Same project secret ✅
        ↓
External Services (crm-api):
  Validates JWTs with: Same project secret ✅
```

**All three must use the SAME secret** or validation fails.

### Where to Find the Secret

**Supabase Dashboard → Settings → API → JWT Settings:**

**Look for:** "Legacy JWT secret (still used)"

**This is the master secret** - all services must use this.

**Configure it as:**
- Edge Functions: Let `SUPABASE_JWT_SECRET` use it naturally (no custom override)
- External services: Set `JWT_SECRET=<supabase-legacy-jwt-secret>`

### What Happens If Mismatched

**If Edge Function uses custom secret:**
```
bff-auth-complete signs with: Custom secret
Supabase validates with: Project secret
→ MISMATCH → PGRST301 error ("No suitable key or wrong key type")
→ All Supabase RPC calls fail ❌
```

**If external service uses wrong secret:**
```
JWT signed with: Supabase secret
External service verifies with: Different secret
→ "Invalid signature" error ❌
```

---

## End-User Authentication

### Architecture

**Custom authentication system using Edge Functions:**

```
LINE OAuth + Phone OTP
        ↓
Edge Functions (auth-line, auth-send-otp, bff-auth-complete)
        ↓
Custom JWT (signed with Supabase's secret)
        ↓
Works with Supabase RPC, RLS, and external services
```

### Authentication Methods Configuration

**Merchant-configurable via `merchant_master.auth_methods`:**

| Configuration | Meaning |
|--------------|---------|
| `["line"]` | LINE login only |
| `["tel"]` | Phone OTP only |
| `["line", "tel"]` | Both LINE and Phone required |

**Frontend retrieves via:** `bff_get_auth_config(merchant_code)`

### Edge Functions

#### 1. auth-line

**Purpose:** Exchange LINE OAuth code for LINE profile (does NOT create user or issue JWT)

**Endpoint:** `/functions/v1/auth-line`

**JWT Required:** ❌ No (`verify_jwt: false`)

**Input:**
```json
{
  "code": "LINE_AUTH_CODE",
  "merchant_code": "newcrm",
  "redirect_uri": "https://..."
}
```

**Output:**
```json
{
  "success": true,
  "line_user_id": "U46fa97...",
  "display_name": "John Doe",
  "picture_url": "https://..."
}
```

---

#### 2. auth-send-otp

**Purpose:** Generate OTP and send SMS

**Endpoint:** `/functions/v1/auth-send-otp`

**JWT Required:** ❌ No

**Input:**
```json
{
  "phone": "0966564526",
  "merchant_code": "newcrm"
}
```

**Output:**
```json
{
  "success": true,
  "session_id": "uuid",
  "expires_in": 600,
  "message": "OTP sent to +66966564526"
}
```

**Phone Normalization:**
- `0966564526` → `+66966564526`
- `+660966564526` → `+66966564526` (removes extra 0)

---

#### 3. bff-auth-complete (⭐ Central Hub)

**Purpose:** Unified authentication - finds/creates users, validates credentials, generates JWTs

**Endpoint:** `/functions/v1/bff-auth-complete`

**JWT Required:** ✅ Yes (for linking methods to existing session)

**Input Scenarios:**

**A. LINE only:**
```json
{
  "merchant_code": "newcrm",
  "line_user_id": "U46fa97..."
}
```

**B. Phone only:**
```json
{
  "merchant_code": "newcrm",
  "tel": "+66966564526",
  "otp_code": "123456",
  "session_id": "uuid"
}
```

**C. Both (LINE + Phone):**
```json
{
  "merchant_code": "newcrm",
  "line_user_id": "U46fa97...",
  "tel": "+66966564526",
  "otp_code": "123456",
  "session_id": "uuid"
}
```

**D. Link method to existing session:**
```json
{
  "merchant_code": "newcrm",
  "access_token": "eyJ...",
  "tel": "+66966564526",
  "otp_code": "123456",
  "session_id": "uuid"
}
```

**Optional persona-scoped signup fields:**
```json
{
  "merchant_code": "newcrm",
  "tel": "+66966564526",
  "otp_code": "123456",
  "session_id": "uuid",
  "selected_persona_id": "uuid"
}
```

When the frontend has a persona selected before the profile is saved, pass `selected_persona_id`. `bff-auth-complete` uses it to return persona-scoped `missing_data.custom_fields_config`; otherwise it falls back to the saved `user_accounts.persona_id`.

**Output:**
```json
{
  "success": true,
  "next_step": "complete_profile_new|complete_profile_existing|complete|verify_line|verify_tel",
  "user": {
    "id": "uuid",
    "tel": "+66966564526",
    "line_id": "U46fa97...",
    "fullname": null
  },
  "access_token": "eyJ...",
  "refresh_token": "uuid",
  "expires_in": 86400,
  "is_new_user": true,
  "is_signup_form_complete": false,
  "missing": {
    "tel": false,
    "line": false,
    "consent": true,
    "profile": true,
    "address": false
  },
  "missing_data": { ... }
}
```

### User Lookup & Duplicate Handling

When `bff-auth-complete` resolves a LINE id or phone to an existing account, it queries `user_accounts` via `.maybeSingle()` with a five-level ORDER BY designed to pick a *useful* row out of legacy duplicates, not just a deterministic one:

```typescript
.order('is_signup_form_complete', { ascending: false, nullsFirst: false })
.order('persona_id',               { ascending: false, nullsFirst: false })
.order('updated_at',               { ascending: false, nullsFirst: false })
.order('created_at',               { ascending: true })
.order('id',                       { ascending: true })
.limit(1)
.maybeSingle()
```

The ordering is intentionally hierarchical:

1. **`is_signup_form_complete DESC NULLS LAST`** — among duplicates, a finished profile beats an unfinished one. This is what prevents the "registration form reappears on every login" symptom for users whose oldest row is a stale test record but who have a complete profile in a newer sibling row.
2. **`persona_id DESC NULLS LAST`** — if step 1 ties (typical for the legacy-import cohort where no row is complete yet), prefer a row that at least has a persona over one that doesn't.
3. **`updated_at DESC NULLS LAST`** — among rows that tied on steps 1 and 2 (e.g. two complete profiles on the same LINE id), the most recently active is the closest the runtime can get to a canonical row before a merge migration assigns one.
4. **`created_at ASC, id ASC`** — final deterministic tiebreaker, identical to the previous behaviour. For the legacy-only case (every row is incomplete with no persona), this preserves "oldest row wins" semantics, so JWT `sub` is stable across logins.

This applies symmetrically to the LINE finder and the tel finder. Both lookups must agree on the same row when both credentials match; if they disagree (`userByLine.id !== userByTel.id`), the function returns HTTP 409 *Credentials belong to different accounts*.

Side-effects of the ordering:

- **Idempotent across legacy duplicates.** Same end-user always receives the same JWT `sub` across sessions (the choice can only change when the underlying row state changes — e.g., a complete row appears).
- **Safe on "not found".** Zero matching rows returns `data: null` cleanly (no PGRST116 thrown), and the function falls through to the standard create/verify branches.
- **Self-stabilising.** Once a user saves their profile (via `bff_save_user_profile`, which heals the canonical row in place — see next section), that row immediately wins step 1 of the ordering on the next login, so they cannot get bounced back to the form.

**`line_user_id` is normalized before any DB read or write** (via the `normalizeLineId` helper):

| Input | Stored / queried as |
|---|---|
| `null`, `undefined`, empty string, whitespace-only | `null` |
| Literal strings `'undefined'` or `'null'` | `null` |
| Any other value | `.trim()`-ed value |

This prevents new empty-string `line_id` rows from being inserted.

**Known limitation (not yet enforced at the DB level):** `user_accounts.(merchant_id, line_id)` has **no** unique constraint. Historical duplicates exist (~2.9k groups, ~13k rows to merge). A future migration will backfill those duplicates (merge into oldest canonical, re-point ~44 declared FKs, soft-delete losers) and then add a partial unique index `ON user_accounts (merchant_id, line_id) WHERE line_id IS NOT NULL AND length(btrim(line_id)) > 0 AND line_id NOT IN ('undefined','null') AND deleted_at IS NULL`. Until that lands, the five-level `.maybeSingle()` ordering above is the runtime defence.

### Profile Save — Lookup by `id` (not `auth_user_id`)

`bff_save_user_profile` resolves the calling user with:

```sql
SELECT id INTO v_user_id FROM user_accounts
WHERE id = v_auth_user_id AND merchant_id = v_merchant_id;
```

`v_auth_user_id := auth.uid()` returns the JWT `sub` claim, which `bff-auth-complete` always sets to `user_accounts.id`. Looking up by `id` (instead of `auth_user_id`) is the only correct join here because legacy/imported `user_accounts` rows can have `auth_user_id IS NULL` — at the time of writing, **153,184 active rows** for the Syngenta merchant alone (`8f67aa08-…`) are in this state. Joining by `auth_user_id` against those rows would return zero, fall through to the INSERT branch, and create a sibling row with `is_signup_form_complete = true` while leaving the original row untouched and incomplete; the next login (which still finds the original by `line_id`) would then re-show the registration form forever.

The function additionally:

- Self-heals `auth_user_id` on the canonical row in the UPDATE branch (`auth_user_id = COALESCE(auth_user_id, v_auth_user_id)`) so any other RPC that still reads `auth_user_id` converges to the correct value as users save their profile.
- Pins the new row's `id` to `v_auth_user_id` in the (now rare) INSERT branch, so a stale JWT whose `sub` no longer points to a row recreates the same `id` rather than spawning yet another orphan.

This eliminates the "registration form keeps reappearing on second login" bug for the entire legacy-import cohort without any data migration.

### JWT Generation (Custom Claims)

**Generated in bff-auth-complete using Supabase's project JWT secret:**

```typescript
// Uses Supabase's HMAC-SHA256 project secret
const JWT_SECRET = Deno.env.get('SUPABASE_JWT_SECRET') || Deno.env.get('JWT_SECRET');

// Creates JWT with custom claims
const jwt = await create(
  { alg: 'HS256', typ: 'JWT' },
  {
    sub: user_id,
    merchant_id: merchant_id,
    user_id: user_id,
    phone: user.tel,
    line_id: user.line_id,
    role: 'authenticated',
    aud: 'authenticated',
    iss: 'supabase',
    exp: getNumericDate(24 * 60 * 60)  // 24 hours
  },
  key  // Signed with Supabase's secret
);
```

**JWT Structure:**
```json
{
  "sub": "5ce979af-1fce-4d44-8e65-2a0a08219098",
  "merchant_id": "09b45463-3812-42fb-9c7f-9d43b6fd3eb9",
  "user_id": "5ce979af-1fce-4d44-8e65-2a0a08219098",
  "phone": "+66966564526",
  "line_id": "U46fa97098b91e50011b8b556c5690e3bb",
  "role": "authenticated",
  "aud": "authenticated",
  "iss": "supabase",
  "exp": 1767005339
}
```

**Key Points:**
- Algorithm: HS256 (HMAC-SHA256)
- Signed with Supabase's project JWT secret
- Expiry: 24 hours
- Custom claims: merchant_id, user_id, phone, line_id

---

## Admin Authentication

### Uses Supabase Auth (Standard)

**Login Flow:**
```
Admin enters email + password
        ↓
Supabase Auth validates
        ↓
Returns Supabase Auth JWT
        ↓
Works with all Supabase features
```

**JWT Structure (Supabase Auth):**
```json
{
  "sub": "admin-user-id",
  "email": "admin@example.com",
  "role": "authenticated",
  "aud": "authenticated",
  "iss": "https://wkevmsedchftztoolkmi.supabase.co/auth/v1",
  "exp": 1234567890
}
```

**Differences from end-user JWTs:**
- `iss`: Full Supabase Auth URL (not just "supabase")
- Merchant claims are injected by `custom_access_token_hook` (top-level `merchant_id` / `merchant_code`, plus `user_metadata` / `app_metadata`)
- User exists in `auth.users` table (not just `user_accounts`)

### Multi-merchant admin selection

Admins may have many `admin_users` rows (one per merchant). Authoritative selection is `auth.users.raw_app_meta_data.active_merchant_id` (also mirrored into JWT `app_metadata` by `custom_access_token_hook`).

| Function | Role |
|---|---|
| `admin_set_active_merchant(p_merchant_code)` | Writes `app_metadata.active_merchant_id` + `user_metadata.merchant_id` / `merchant_code` / `merchant_name` for a membership the caller can access |
| `custom_access_token_hook` | Prefers membership matching `active_merchant_id`; emits matching `merchant_code` / `merchant_name`; falls back to newest active membership if selection vanished |
| `sync_admin_to_user_metadata` (trigger on `admin_users`) | Always syncs profile fields (`admin_name`, `admin_email`, `admin_phone`, `is_admin`, `admin_active`). Syncs merchant_* only when `active_merchant_id` is null or equals `NEW.merchant_id` — never stomps a different selected merchant |
| `sync_admin_metadata_after_login` | Prefers `active_merchant_id` membership; else newest active (`ORDER BY created_at DESC`); keeps app + user merchant metadata aligned |
| `get_current_merchant_id()` | Unchanged priority: headers → `app_metadata.active_merchant_id` → other JWT claims → lookups |

### Shopify Admin (embedded app) — `auth-shopify-admin`

Public edge function. Verifies Shopify session token → resolves/creates `admin_users` → **hand-mints** a Rocket access JWT (does **not** go through Supabase Auth sign-in, so `custom_access_token_hook` does not run).

**Minted JWT must mirror the hook's merchant claim surface** so `get_current_merchant_id()` and FE session readers resolve merchant without relying on headers alone:

| Location | Claims |
|---|---|
| Top-level | `merchant_id`, `merchant_code`, `is_admin` |
| `user_metadata` | `merchant_id`, `merchant_code`, `is_admin`, `source: shopify_admin`, … |
| `app_metadata` | `active_merchant_id`, `merchant_id`, `merchant_code`, `is_admin` |

Existing sessions keep working until re-login. Auth user row still gets `user_metadata` / `app_metadata.active_merchant_id` via `auth.admin.updateUserById` / create.

### Admin Invitations

Admin invitations are managed by `admin_manage_invitation`.

**Create requirements:**
- `p_role_id` is required.
- At least one identity is required: `p_email` or `p_phone`.
- `p_phone` is normalized with `fn_normalize_thai_phone`.
- Existing active members and pending invitations are checked by email OR normalized phone.

**Delivery behavior:**
- Email invites send the existing invitation email and return `data.delivery = "email"`.
- Phone-only invites are valid backend records and return `data.delivery = "manual_or_sms"` plus `data.invite_url`; FE or an SMS delivery path must send that URL.

**Accept behavior:**
- The invite token must be active and unexpired.
- The signed-in Supabase Auth user may accept if `auth.users.email` matches the invite email OR normalized `auth.users.phone` matches the invite phone.
- Acceptance creates the `admin_users` row for the invited merchant and role.

---

## Platform Superadmin MCP Access Tokens

Rocket internal staff use normal Supabase Auth admin accounts. A platform superadmin is an `admin_users` row whose `role_id` points to `admin_roles.role_code = 'platform_superadmin'`.

Personal MCP access keys are stored in `system_mcp_access_tokens`. The raw token is shown once in the admin UI; only its SHA-256 hash is stored. Hosted MCP services validate keys through `fn_validate_mcp_access_token(p_token_hash)` using the service role.

Functions:
- `superadmin_create_mcp_access_token(p_token_hash, p_token_prefix, p_label, p_scopes, p_allowed_tools, p_allowed_feature_slugs, p_expires_at, p_metadata)` — current `platform_superadmin` creates a personal MCP key record.
- `superadmin_list_my_mcp_access_tokens()` — current `platform_superadmin` lists their own token metadata.
- `superadmin_revoke_my_mcp_access_token(p_token_id)` — current `platform_superadmin` revokes their own key.
- `fn_validate_mcp_access_token(p_token_hash)` — service-role validation for hosted MCP servers; returns owner, scopes, allowed tools, and allowed feature slugs.

Initial scopes:
- `knowledge:read` — allows knowledge retrieval tools.
- `knowledge:write` — allows knowledge authoring tools.

---

## JWT Validation Across Services

### Supabase Services (Built-in)

**RPC Functions, PostgREST, Realtime:**

**Validates using:** Supabase's project JWT secret (automatically)

**Accepts:**
- ✅ Custom JWTs from bff-auth-complete (if signed with project secret)
- ✅ Supabase Auth JWTs (always signed with project secret)

**Configuration:** None needed - uses project secret automatically

---

### External Services (Custom - e.g., crm-api)

**Must validate JWTs manually:**

**Using jsonwebtoken package:**
```typescript
import jwt from 'jsonwebtoken';

const JWT_SECRET = process.env.JWT_SECRET;  // Supabase's project secret

// Validate JWT
const decoded = jwt.verify(token, JWT_SECRET, {
  algorithms: ['HS256']  // Match the algorithm used to sign
});

// Extract user info
const userId = decoded.user_id || decoded.sub;
const merchantId = decoded.merchant_id;
```

**Environment Variable:**
```
JWT_SECRET=<supabase-legacy-jwt-secret>
```

**Must be the SAME as Supabase's project secret!**

---

## Security Model

### Row Level Security (RLS)

**All user data filtered by merchant context:**

```sql
-- RLS Policy Example
CREATE POLICY "Users see own merchant data"
ON user_accounts
FOR ALL
USING (
  merchant_id = get_current_merchant_id()
);
```

**merchant_id extracted from:**
1. JWT claim: `merchant_id`
2. Or custom header: `x-merchant-id`

**Function:** `get_current_merchant_id()` reads from auth context

---

### Token Expiry

| Token Type | Expiry |
|------------|--------|
| End-user access token | 24 hours |
| End-user refresh token | 30 days |
| Admin access token | Supabase default (~1 hour) |

**Refresh Flow:**
```
Access token expires (24 hours)
        ↓
Client sends refresh_token
        ↓
Edge Function validates refresh token
        ↓
Issues new access_token (24 hours)
        ↓
Client stores new token
```

---

## Authentication Flow Comparison

### End-User (Custom)

```
1. User opens app
2. Call bff_get_auth_config(merchant_code)
3. Show LINE button and/or Phone input based on config
4. User authenticates (LINE OAuth, Phone OTP, or both)
5. Call bff-auth-complete with credentials
6. Receive custom JWT + refresh token
7. Store tokens in localStorage
8. Use access_token for all API calls
```

**Token Usage:**
```javascript
// All API calls
headers: {
  'Authorization': `Bearer ${access_token}`
}
```

---

### Admin (Supabase Auth)

```
1. Admin enters email + password
2. Call supabase.auth.signInWithPassword()
3. Receive Supabase Auth JWT
4. Store in Supabase client (automatic)
5. Use for admin dashboard calls
```

**Token Usage:**
```javascript
// Automatic - Supabase client handles it
const { data } = await supabase.from('table').select();
```

---

## Best Practices

### JWT Secret Management

**DO:**
- ✅ Use Supabase's Legacy JWT Secret for all custom JWTs
- ✅ Never set custom `JWT_SECRET` in Edge Functions (let it use `SUPABASE_JWT_SECRET`)
- ✅ Copy the same secret to external services (crm-api, etc.)
- ✅ Rotate via Supabase Dashboard (handles grace period)
- ✅ Keep secret in environment variables (never hardcode)

**DON'T:**
- ❌ Use different secrets for signing vs validation
- ❌ Set custom JWT_SECRET in Edge Functions (breaks Supabase RPC)
- ❌ Expose secret in frontend code
- ❌ Share secret publicly
- ❌ Use weak/short secrets

---

### Token Storage

**End-User (Frontend):**
```javascript
// Store in localStorage (or secure cookie)
localStorage.setItem('access_token', accessToken);
localStorage.setItem('refresh_token', refreshToken);

// Include in all API calls
headers: {
  'Authorization': `Bearer ${localStorage.getItem('access_token')}`
}
```

**Backend Services:**
```javascript
// Configure as environment variable
JWT_SECRET=<supabase-legacy-jwt-secret>

// Verify on each request
const decoded = jwt.verify(token, process.env.JWT_SECRET);
```

---

### Token Validation

**For Supabase RPC/PostgREST:**
- Automatic - Supabase validates using project secret
- Just send Authorization header

**For Custom Backend Services:**
```typescript
import jwt from 'jsonwebtoken';

function validateToken(authHeader: string) {
  if (!authHeader || !authHeader.startsWith('Bearer ')) {
    throw new Error('Missing Authorization header');
  }

  const token = authHeader.replace('Bearer ', '');
  
  try {
    const decoded = jwt.verify(token, process.env.JWT_SECRET, {
      algorithms: ['HS256']  // Custom JWTs use HS256
    });
    
    return {
      userId: decoded.user_id || decoded.sub,
      merchantId: decoded.merchant_id,
    };
  } catch (error) {
    throw new Error('Invalid or expired token');
  }
}
```

---

## End-User Authentication Details

### Supported Methods

**1. LINE OAuth**
- Official LINE Login integration
- Returns: LINE user ID, display name, profile picture
- Provider: LINE Platform
- Edge Function: `auth-line`

**2. Phone OTP**
- SMS-based one-time password
- 6-digit code, 10-minute expiry
- Provider: 8x8 SMS service
- Edge Functions: `auth-send-otp`

**3. Combined (LINE + Phone)**
- Merchant requires both methods
- User must complete both to authenticate
- Links both identities to single account

### Database Schema

**Primary Table:** `user_accounts`

```sql
CREATE TABLE user_accounts (
    id UUID PRIMARY KEY,
    merchant_id UUID NOT NULL,
    
    -- Auth identities
    tel TEXT,                    -- Normalized phone: +66XXXXXXXXX
    line_id TEXT,                -- LINE user ID
    auth_user_id UUID,           -- Self-referencing (id) for custom auth
    
    -- Profile
    fullname TEXT,
    email TEXT,
    persona_id UUID,
    
    -- Status
    is_signup_form_complete BOOLEAN DEFAULT false,
    
    created_at TIMESTAMPTZ DEFAULT NOW()
);
```

**Supporting Tables:**
- `otp_requests` - OTP validation records (10-min TTL)
- `refresh_tokens` - JWT refresh tokens (30-day TTL)
- `user_address` - Address data
- `form_submissions` + `form_responses` - Custom field data
- `user_consent_ledger` - PDPA consent audit log

### Authentication States

**`next_step` values from bff-auth-complete:**

| Value | Meaning | Has JWT? | Frontend Action |
|-------|---------|----------|-----------------|
| `verify_line` | Need LINE login | No | Show LINE button |
| `verify_tel` | Need phone OTP | No | Show phone + OTP form |
| `complete_profile_new` | New user, fill form | Yes | Show registration form |
| `complete_profile_existing` | Has account, fill missing fields | Yes | Show profile form |
| `complete` | All done | Yes | Navigate to home |

---

## Bot / Automated Testing Authentication

### Purpose

Allows bots and automated test runners to authenticate as end-users **without OTP or LINE OAuth**. Once the bot obtains a JWT, it can call all other APIs identically to a real user.

### How It Works

`bff-auth-complete` accepts an optional `bot_secret` field. When provided and valid:
1. OTP validation is **completely skipped**
2. The phone number (`tel`) is treated as verified
3. A real JWT is issued — identical to what a normal user would receive
4. The rest of the flow (user lookup/create, profile check, etc.) runs normally

### Configuration

**Environment Variable:** `BOT_SECRET` on the Supabase project

- If `BOT_SECRET` is **not set**, the feature is disabled. Any request with `bot_secret` returns 403.
- If `BOT_SECRET` is set, only requests with a matching `bot_secret` value bypass OTP.

### Bot Authentication Flow

```
Bot → POST bff-auth-complete
      {
        "merchant_code": "newcrm",
        "tel": "+66966564526",
        "bot_secret": "<BOT_SECRET value>"
      }
      (Authorization: Bearer <supabase-anon-key>)
      
    ← JWT + refresh_token (same as normal user)

Bot → Use JWT for all subsequent API calls
      (wallet-api, claim-codes, receipts, RPC, etc.)
```

**No need to call `auth-send-otp`** — the bot skips directly to `bff-auth-complete`.

### Input (Bot Mode)

```json
{
  "merchant_code": "newcrm",
  "tel": "+66966564526",
  "bot_secret": "<secret>"
}
```

Optionally include `line_user_id` if the merchant requires LINE auth.

### Error Responses

| Scenario | Status | Error |
|----------|--------|-------|
| `BOT_SECRET` env var not set | 403 | `Bot authentication is not configured on this project` |
| `bot_secret` value doesn't match | 403 | `Invalid bot_secret` |

### Security

- `bot_secret` is compared using constant-time comparison (prevents timing attacks)
- The feature is completely dormant when `BOT_SECRET` env var is absent
- All bot authentications are logged: `[BOT_AUTH] Bot authentication bypass for merchant=... tel=... line=...`
- `BOT_SECRET` should be a strong random string (32+ characters)
- **Never expose `BOT_SECRET` in frontend code or public repositories**

### Scope

`bot_secret` is currently used only in `bff-auth-complete` (OTP bypass). The same env var can be reused by other edge functions in the future for bot-specific behavior (rate limit bypass, test mode flags, etc.).

---

## Admin Authentication Details

### Supabase Auth (Standard)

**Login:**
```typescript
const { data, error } = await supabase.auth.signInWithPassword({
  email: 'admin@example.com',
  password: 'password'
});

const session = data.session;
// JWT automatically managed by Supabase client
```

**Users stored in:**
- `auth.users` table (Supabase Auth table)
- May also have record in `user_accounts` for profile data

**JWT Claims:** Supabase Auth base claims plus merchant/admin claims from `custom_access_token_hook` (`merchant_id`, `merchant_code`, `app_metadata.active_merchant_id`, `user_metadata.merchant_*`, `is_admin`). See §Multi-merchant admin selection.

---

## JWT Secret Configuration

### Supabase Edge Functions

**bff-auth-complete secret resolution:**

```typescript
const JWT_SECRET = Deno.env.get('SUPABASE_JWT_SECRET') || Deno.env.get('JWT_SECRET');
```

**Priority:**
1. `SUPABASE_JWT_SECRET` - Supabase's project secret (preferred)
2. `JWT_SECRET` - Custom fallback

**Recommendation:** Don't set custom `JWT_SECRET` - let it use `SUPABASE_JWT_SECRET` automatically.

---

### External Services (Render, etc.)

**Environment Variable:**
```bash
JWT_SECRET=<supabase-legacy-jwt-secret>
```

**Where to find:**
- Supabase Dashboard → Settings → API → "Legacy JWT secret"
- Must be the HS256 shared secret (not ECC)

**Validation Code:**
```typescript
import jwt from 'jsonwebtoken';

const JWT_SECRET = process.env.JWT_SECRET;

jwt.verify(token, JWT_SECRET, {
  algorithms: ['HS256']
});
```

---

## Security Considerations

### JWT Secret Must Match

**All services validating JWTs must use the SAME secret:**

| Service | Uses Secret For | Environment Variable |
|---------|----------------|---------------------|
| bff-auth-complete | Signing JWTs | `SUPABASE_JWT_SECRET` (auto) |
| Supabase RPC/PostgREST | Validating JWTs | Project secret (built-in) |
| crm-api | Validating JWTs | `JWT_SECRET` (manual) |
| crm-event-processors | Validating JWTs | `SUPABASE_SERVICE_ROLE_KEY` (RPC calls) |

**If any mismatch:**
- Signature validation fails
- "Invalid token" or "PGRST301" errors
- API calls fail

---

### Key Rotation Impact

**When you rotate Supabase's JWT secret:**

**What happens:**
1. New secret becomes active
2. Old secret moves to "Previously used keys"
3. **Both secrets remain valid** (grace period)
4. Existing tokens continue to work (Supabase validates with old secret)
5. New tokens signed with new secret

**What you must do:**
1. Update `JWT_SECRET` in ALL external services (crm-api, etc.)
2. Wait for grace period to end (all old tokens expire)
3. Or force users to login again (invalidates old tokens)

**DON'T:**
- ❌ Set custom JWT_SECRET in Edge Functions (breaks Supabase validation)
- ❌ Rotate without updating external services
- ❌ Use different secrets for signing vs validation

---

## Troubleshooting

### Error: "Invalid or expired token" (401)

**From crm-api or external service:**

**Cause:** JWT secret mismatch

**Fix:**
1. Check JWT_SECRET in service environment
2. Verify it matches Supabase's current Legacy JWT Secret
3. Redeploy service
4. Get fresh token (login again)
5. Test with new token

---

### Error: "No suitable key or wrong key type" (PGRST301)

**From Supabase RPC/PostgREST:**

**Cause:** JWT signed with secret Supabase doesn't know about

**Fix:**
1. Check Edge Function environment
2. Remove custom JWT_SECRET override
3. Let it use SUPABASE_JWT_SECRET (project secret)
4. Redeploy Edge Function
5. Login again to get new token

---

### Error: Token works with Supabase but not external service

**Cause:** External service has wrong JWT_SECRET

**Fix:**
1. Get current Legacy JWT Secret from Supabase Dashboard
2. Update external service environment variable
3. Redeploy external service
4. Test again

---

### Error: Token works with external service but not Supabase

**Cause:** Token signed with custom secret, not Supabase's

**Fix:**
1. Remove custom JWT_SECRET from Edge Function
2. Let it use Supabase's project secret
3. Login again
4. New tokens will work with both

---

## Configuration Checklist

### Supabase Project

- [ ] Legacy JWT Secret (HS256) is current key
- [ ] No custom JWT_SECRET override in Edge Functions
- [ ] Edge Functions use `SUPABASE_JWT_SECRET` naturally

### Edge Functions

- [ ] bff-auth-complete: No custom JWT_SECRET set
- [ ] auth-line: `verify_jwt: false`
- [ ] auth-send-otp: `verify_jwt: false`

### External Services

- [ ] crm-api: `JWT_SECRET` = Supabase Legacy JWT Secret
- [ ] crm-event-processors: Uses Supabase client (no JWT validation needed)

### Testing

- [ ] End-user can login via LINE + Phone
- [ ] Receive valid JWT from bff-auth-complete
- [ ] JWT works with Supabase RPC calls
- [ ] JWT works with external services (crm-api)
- [ ] No PGRST301 errors
- [ ] No "Invalid signature" errors

---

## Summary

**Authentication Architecture:**
- End-users: Custom (LINE + Phone OTP) → Custom JWTs (Supabase-compatible)
- Admins: Supabase Auth (email/password) → Standard Supabase JWTs

**Critical Requirement:**
- ALL JWTs must be signed with Supabase's Legacy JWT Secret (HS256)
- This includes custom JWTs from Edge Functions
- No custom secrets - use Supabase's project secret

**Validation:**
- Supabase: Automatic (uses project secret)
- External services: Manual (jwt.verify with same secret)

**Best Practice:**
- Don't set custom JWT_SECRET in Edge Functions
- Copy Supabase's Legacy JWT Secret to external services
- Both signing and validation use the SAME secret
- Test thoroughly after any secret rotation

---

*Document Version: 1.0*  
*System: Supabase CRM - Dual Authentication with Supabase-Compatible JWTs*























