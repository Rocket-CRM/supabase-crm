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
- No custom claims (merchant_id, phone, line_id)
- User exists in `auth.users` table (not just `user_accounts`)

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

**JWT Claims (Standard Supabase):**
```json
{
  "sub": "uuid",
  "email": "admin@example.com",
  "role": "authenticated",
  "aud": "authenticated",
  "iss": "https://wkevmsedchftztoolkmi.supabase.co/auth/v1",
  "exp": 1234567890
}
```

**No custom claims** - standard Supabase Auth format

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























