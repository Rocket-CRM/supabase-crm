# Signup/Login System Design

## System Architecture

### Core Concept
A unified authentication system that supports LINE OAuth and phone OTP, with merchant-configurable authentication methods and dynamic profile completion checks.

---

## Authentication Methods Configuration

**Location:** `merchant_master.auth_methods` column (TEXT[])

**Possible values:**
- `["line"]` - LINE login only
- `["tel"]` - Phone OTP only  
- `["line", "tel"]` - Both required

**Frontend retrieval:** Call `bff_get_auth_config(merchant_code)`

---

## Function Inventory

### 1. `bff_get_auth_config(p_merchant_code)`
**Purpose:** Get merchant's authentication method configuration

**Input:**
```json
{
  "merchant_code": "newcrm"
}
```

**Output:**
```json
{
  "auth_methods": ["line", "tel"]
}
```

**Frontend usage:** Determine which auth UI to show (LINE button, phone input, or both)

---

### 2. `auth-line` (Edge Function)
**Purpose:** Exchange LINE OAuth code for LINE user profile (does NOT create user or issue JWT)

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

**Frontend usage:** After LINE login callback, exchange code for profile data, then pass to `bff-auth-complete`

**Security:** Public endpoint (`verify_jwt: false`), only requires anon key

---

### 3. `auth-send-otp` (Edge Function)
**Purpose:** Generate OTP and send SMS via 8x8

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
  "session_id": "uuid-uuid",
  "expires_in": 600,
  "message": "OTP sent to +66966564526"
}
```

**Phone normalization:**
- `0966564526` → `+66966564526`
- `+660966564526` → `+66966564526` (removes extra 0)
- `66966564526` → `+66966564526` (adds +)

**Frontend usage:** User enters phone → call this → store `session_id` → show OTP input

**OTP settings:**
- Length: 6 digits
- Expiry: 10 minutes
- Max attempts: 3

---

### 4. `bff-auth-complete` (Edge Function) - **THE CENTRAL HUB**
**Purpose:** Unified authentication - finds/creates users, links auth methods, checks profile completion, issues JWTs

**Input scenarios:**

**A. LINE only:**
```json
{
  "merchant_code": "newcrm",
  "line_user_id": "U46fa97..."
}
```

**B. Tel only:**
```json
{
  "merchant_code": "newcrm",
  "tel": "+66966564526",
  "otp_code": "123456",
  "session_id": "uuid"
}
```

**C. Both (LINE first, then tel):**
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

**Intermediate response (needs more verification):**
```json
{
  "success": true,
  "next_step": "verify_tel",
  "message": "Phone verification required"
}
```

**Full response (user created/found, JWT issued):**
```json
{
  "success": true,
  "next_step": "complete_profile_new",
  "user_account": {
    "id": "uuid",
    "tel": "+66966564526",
    "line_id": "U46fa97...",
    "fullname": null,
    "email": null
  },
  "access_token": "eyJ...",
  "refresh_token": "uuid-uuid",
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
  "missing_data": {
    "persona": { ... },
    "pdpa": [ ... ],
    "default_fields_config": [ ... ],
    "custom_fields_config": [ ... ],
    "selected_section": null
  }
}
```

**Logic flow:**
1. Get merchant config and auth_methods
2. Normalize tel format
3. Validate credentials (OTP if tel provided)
4. Find existing user (by LINE or tel or access_token)
5. Handle conflicts (LINE and tel belong to different users)
6. Create new user if not found
7. Link missing auth methods to existing user
8. Generate JWT with merchant context
9. **Early return optimization:** if required auth method is still missing (`verify_line` / `verify_tel`), return immediately (still includes `access_token` + `refresh_token`) and **skip** profile template evaluation
10. Check profile completion using `bff_get_user_profile_template` (only when auth methods are satisfied), calling it with the **member JWT** just minted so `fn_apply_user_profile_edit_overlay` can pre-fill saved `user_accounts` / address / custom-field values; returned field lists are **persona-filtered** for that JWT—see §5
11. Determine `next_step` based on profile completion
12. Build `missing_data` payload (full form or missing-only)
13. Generate refresh token
14. If `next_step === "complete"`, also merge `get_user_summary()` output into `user_account` (flat)
15. Return comprehensive response

**Member code (auto-assigned on create):** `bff-auth-complete` does **not** set `member_code` itself. New users are created via `chokepoint_post_user_event(event_type=create)`; when `member_code` is omitted from `p_changes`, the chokepoint derives an **8-digit** code from `user_accounts.id` + per-merchant pepper (`fn_derive_member_code`). Retry on unique violation only (`attempt` 1..5). Explicit `member_code` in `p_changes` is stored as-is. Updates never auto-fill a null `member_code`. Bulk import: blank column → same auto-assign; supplied codes validated in Pass 1 (`DUPLICATE_MEMBER_CODE_IN_BATCH`, `MEMBER_CODE_EXISTS`, `INVALID_MEMBER_CODE`).

**Member code on summary / login payload:** `get_user_summary()` returns additive `member_code` (nullable text from `user_accounts.member_code`). When `next_step === "complete"`, `bff-auth-complete` merges that summary into `user_account`, so the login response includes `member_code` for My QR and other storefront consumers.

---

### 5. `bff_get_user_profile_template(p_mode, p_language, p_merchant_code, p_event_code)`
**Purpose:** Build the user profile form schema (default fields, custom form fields, persona picker structure, PDPA/consent shell, channels/topics items) with translations, then return only the slices appropriate for the **current JWT** and **persona**.

**Where it is used (not only edit profile):**
- **Signup / post-login profile completion:** After `bff-auth-complete` has issued a session and all required auth methods are satisfied, that flow evaluates profile completion and may call this RPC (or equivalent server-side logic) so `missing_data` reflects the same template the client should render—see step 10 in `bff-auth-complete` above.
- **Edit profile (standalone screen):** The app may call this RPC directly with `p_mode = 'edit'` and the user’s bearer token so the form is pre-filled from `user_accounts` / `user_address` / `form_responses` / consents / channel flags.

**Input (Postgres parameter order):**
| Parameter | Default | Role |
|-----------|---------|------|
| `p_mode` | `'new'` | `'new'` = empty values (plus optional event pre-fill); `'edit'` = overlay stored user data for fields still present after filtering |
| `p_language` | `'en'` | Resolved UI language (with fallback to merchant default) |
| `p_merchant_code` | `null` | If set, resolves merchant via config cache; if `null`, uses session merchant context (`get_current_merchant_id()`) |
| `p_event_code` | `null` | Optional Syngenta-style event: pre-fills address admin IDs on matching default fields when `p_mode = 'new'` |

**Persona and field visibility (server-side, JWT-driven):**
- The function reads **`auth.uid()`** and loads **`user_accounts.persona_id`** for that auth user and **current merchant**.
- Each default field (`user_field_config`) and custom field (`form_fields`) carries **`persona_ids`** in the JSON.
  - **Universal field:** `persona_ids` is missing, JSON `null`, or an **empty** array → returned for every caller (subject to other flags such as `visible_to_user`).
  - **Persona-scoped field:** non-empty `persona_ids` → returned only if the user’s `persona_id` is in that list.
  - **User has no `persona_id`:** only universal fields are returned; persona-scoped fields are omitted.
- **Field groups:** If, after filtering, a group has **no** remaining fields, that **entire group is omitted** from `default_fields_config` and `custom_fields_config`.
- **Persona metadata:** The response still includes the full **`persona`** object (groups, personas, `persona_attain`, etc.) so the client can render persona selection; filtering applies to **fields**, not to hiding the persona catalog unless the product layer does so.

**Caching vs filtering:**
- Redis stores the **full** merchant template (all languages) under `merchant:{merchant_id}:user_profile_template:all_languages` for **5 minutes**.
- After cache hit or miss, the pipeline runs **`fn_extract_user_profile_language`**, then **persona field filtering**, then event pre-fill (`new` only), then **`edit`** overlays. So **persona filtering is not baked into the cache**; it depends on the caller’s JWT on every request.

**Output (shape; keys vary by merchant):**
```json
{
  "persona": {
    "merchant_config": { "persona_attain": "pre-form" },
    "selected_persona_id": null,
    "persona_groups": [ ... ]
  },
  "default_fields_config": [ ... ],
  "custom_fields_config": [ ... ],
  "pdpa": [ ... ],
  "selected_section": null,
  "mode": "new",
  "event_code": null,
  "cache_hit": true,
  "language": "th",
  "default_language": "en",
  "timestamp": "2025-12-08T00:00:00Z"
}
```

**Mode behavior:**
- `'new'`: Field `value` entries are empty unless event pre-fill applies; PDPA/channel/topic acceptance flags start unset/false as defined by the function.
- `'edit'`: Overlays the caller’s data from DB for fields that remain **after** persona filtering (same auth user / merchant).

**Important for clients:**
- Call with the **end-user’s JWT** (not only a service role with no `auth.uid()`), otherwise persona cannot be resolved and **only universal fields** are returned.
- **`phone` / `line_id`:** Still governed by merchant field config and product rules (often treated as auth-managed rather than free-text profile fields).

**Field type `external_code`:** A persona-scoped, pre-uploaded code field (e.g. company tax ID, dealer code). Each `default_fields_config` field whose `field_type = 'external_code'` exposes a `config.external_code` object: `{ pool_label, max_consumers, target_user_column }`. Frontend renders a text input + Validate button; see `bff_validate_signup_code` below. Final consumption happens inside `bff_save_user_profile` and is atomic (rolls back the entire profile save on failure).

**Related RPC:** `bff_save_user_profile` accepts the filled payload; ensure saves validate required fields in line with what this template exposed for that user’s persona.

---

### 6. `bff_save_user_profile(p_data)`
**Purpose:** Save user profile form (upserts across multiple tables)

**Input:** The entire payload from `bff_get_user_profile_template` with user-filled `value` fields

**Tables updated:**
- `user_accounts` - default fields, persona, channels, **sets `is_signup_form_complete = true`**. If a default field has `field_type = 'external_code'` and its `config.external_code.target_user_column` is set to one of `external_user_id` / `member_code` / `id_card`, the consumed code value is also written there.
- `user_address` - address fields
- `form_submissions` + `form_responses` - custom fields
- `user_consent_ledger` - PDPA consents
- `user_communication_preferences` - topics
- `signup_codes` + `signup_code_claims` - for any `external_code` field present in payload, the code is consumed atomically via `fn_consume_signup_code` (persona check → race-safe `UPDATE ... WHERE consumed_count < max_consumers RETURNING ...` → insert into claims). Failures (invalid, inactive, exhausted, persona mismatch, missing field) raise `SIGNUP_CODE:<code>:<message>` which the function converts into a structured error response and **rolls back the entire transaction**.

**Output:**
```json
{
  "success": true,
  "user_id": "uuid",
  "is_new_user": false,
  "is_signup_form_complete": true
}
```

**Error response for signup code failure:**
```json
{
  "success": false,
  "title": "Code validation failed",
  "description": "This code has reached its consumption limit",
  "data": { "error_code": "CODE_EXHAUSTED" }
}
```

Possible `error_code` values: `INVALID_CODE`, `CODE_INACTIVE`, `CODE_EXHAUSTED`, `FIELD_NOT_FOUND`, `PERSONA_MISMATCH`.

**Authentication:** Uses `auth.uid()` from bearer token

Locked default fields (`editable_by_user = false`) are write-once: the first empty→value write is kept; later member updates are stripped. Completeness (`fn_check_profile_complete`) still requires required+visible fields regardless of editability.

---

### 7. `bff_validate_signup_code(p_field_key, p_code, p_selected_persona_id?)`
**Purpose:** Validate (without consuming) a signup code for an `external_code` field. Powers the FE Validate button.

**Input:**
| Param | Type | Notes |
|---|---|---|
| `p_field_key` | `text` | Default field key on `user_field_config` (matches `field_type='external_code'`) |
| `p_code` | `text` | The code the user entered |
| `p_selected_persona_id` | `uuid` (nullable) | Required for new users whose persona isn't saved yet; mirrors the same param on `bff_get_user_profile_template` and `bff-auth-complete` |

**Output (success):**
```json
{
  "success": true,
  "title": "Code valid",
  "data": {
    "valid": true,
    "preview_metadata": { "company_name": "Acme Corp" },
    "prefill": {
      "default": { "firstname": "Acme", "external_user_id": "ACME-00123" },
      "custom":  { "company_name": "Acme Corp", "department": "Sales" }
    },
    "already_claimed": false,
    "remaining_seats": 49
  }
}
```

**Output (failure):** `success=false` with `data.error_code` ∈ `EMPTY_CODE`, `FIELD_NOT_FOUND`, `PERSONA_MISMATCH`, `INVALID_CODE`, `CODE_INACTIVE`, `CODE_EXHAUSTED`, `NO_MERCHANT`.

**Notes:**
- Read-only. Does NOT consume. Same code can be validated repeatedly without effect.
- If the code has already been claimed by the current user, returns `success=true` with `already_claimed=true` (idempotent).
- The race-safe consumption happens inside `bff_save_user_profile`, so the FE Validate is a UX nicety; the save is the final source of truth and re-checks persona scope before consuming.
- **Prefill auto-fill (FE):** when `data.prefill.default.<field_key>` or `data.prefill.custom.<field_key>` is present, the FE seeds those values into the corresponding default-field / custom-field inputs after Validate succeeds. The user can review and override before Submit. Server does **not** re-stamp these values during consume — submitted form values flow through `bff_save_user_profile` like any other user-entered values. Keys for fields that have been deleted/renamed/hidden since the code was uploaded are silently dropped from the response (admin sets the prefill schema once on the pool via `bff_set_signup_code_prefill_schema`, which is what guarantees keys were valid at upload time).
- For the full code/claim tables, admin BFFs (`bff_set_signup_code_prefill_schema`, `bff_get_signup_code_prefillable_fields`, `bff_upload_signup_codes`, `bff_list_signup_codes`, `bff_delete_signup_codes`), metadata shape (`preview` + `prefill.{default,custom}`), pool prefill schema, upload validation rules, and naming model (one `external_code` field = one pool, no separate `pools` table), see `requirements/domains/signup-code-validation.md`.

---

## `next_step` Values (API-level routing)

Returned by `bff-auth-complete` to tell frontend what to show:

| Value | Meaning | `access_token`? | Frontend action |
|-------|---------|-----------------|-----------------|
| `verify_line` | Need LINE login | No | Show LINE login button |
| `verify_tel` | Need phone OTP | No | Show phone input + OTP form |
| `complete_profile_new` | New user, fill form | Yes | Show registration form ("ยินดีต้อนรับ!") |
| `complete_profile_existing` | Existing user, fill form | Yes | Show profile form ("ยินดีต้อนรับกลับ!") |
| `complete` | All done | Yes | Navigate to home page |

### `missing_data` content logic:

| `next_step` | `is_signup_form_complete` | `missing_data` contains |
|-------------|---------------------------|-------------------------|
| `complete_profile_new` | `false` | **Full form** (persona, pdpa, all fields) |
| `complete_profile_existing` | `false` | **Full form** (never filled before) |
| `complete_profile_existing` | `true` | **Missing only** (required fields not filled) |
| `complete` | `true` | `null` |

---

## `form_step` (Frontend state for form navigation)

**Location:** Frontend variable (e.g., `variables['f214fed7-7ce4-43f6-888f-251cb10b4191']`)

**Values:** `"persona"` | `"default_field"` | `"custom_field"` | `"pdpa"`

**Purpose:** Track which section of the multi-step form user is currently viewing

**Sequence:** persona → default_field → custom_field → pdpa

**Relationship to `next_step`:**
- `next_step` = API instruction (what major screen to show)
- `form_step` = Frontend state (which form section within the profile form)

---

## Frontend JavaScript Functions

### 1. Next Button Click - Navigate to next form section
```javascript
const data = variables['45691153-f0a5-42fa-ac9a-5729a9853be2'];
const currentStep = variables['f214fed7-7ce4-43f6-888f-251cb10b4191'];

// Returns: { upsert: boolean, nextStep: string|null }
// If upsert=true → call bff_save_user_profile
// If nextStep=string → form_step updated automatically
```

### 2. Back Button Click - Navigate to previous form section
```javascript
// Returns: { isFirst: boolean, prevStep: string|null }
// If isFirst=true → hide back button
// prevStep updates form_step automatically
```

### 3. Next Button Visibility - Show/hide based on required fields filled
```javascript
// Checks:
// - persona: selected_persona_id has value
// - default_field: all is_required fields have value
// - custom_field: all is_required fields have value
// - pdpa: all is_mandatory items have isAccepted=true
// Returns: true (show) | false (hide)
```

### 4. Back Button Visibility - Show if not first step
```javascript
// Checks if there's a previous section with items
// Returns: true (show) | false (hide)
```

### 5. Validation Message Visibility - Show if required fields missing
```javascript
// Inverted logic from next button visibility
// Returns: true (show error) | false (hide)
```

### 6. PDPA Handler - Manage consent UI state
```javascript
// Parameters: type, action, section_id, option_id
// Actions:
//   - 'expand': Toggle section expansion
//   - 'accept': Toggle acceptance (notice, text_content, checkbox_options)
//   - 'accept_all': Toggle all sections and options
// Types:
//   - 'notice': No checkbox, just info
//   - 'text_content': Single checkbox
//   - 'checkbox_options': Master checkbox + individual options
```

### 7. Field Value Updater - Update field values with 5s debounce
```javascript
// Parameters: object_type, field_key, group_id, value
// Updates: persona, default_fields_config, custom_fields_config
// Debounce: 5 seconds per field to reduce DB calls
```

---

## Scenario Matrix

### Scenario 1: New user, LINE+TEL method

**Step 1:** User clicks LINE login button
- FE calls `auth-line` with code
- Gets `{ line_user_id, display_name }`

**Step 2:** User calls `bff-auth-complete` with `line_user_id` only
- No user found by LINE
- Response: `{ next_step: "verify_tel" }`

**Step 3:** User enters phone, FE calls `auth-send-otp`
- Gets `{ session_id }`
- User enters OTP

**Step 4:** User calls `bff-auth-complete` with `line_user_id`, `tel`, `otp_code`, `session_id`
- No user found by LINE or tel
- New user created with both LINE and tel
- Response: `{ next_step: "complete_profile_new", access_token, missing_data: {full form} }`

**Step 5:** User fills form sections (persona → default → custom → pdpa)
- Form navigation managed by `form_step` variable
- Next button validates required fields per section

**Step 6:** User completes last section, FE calls `bff_save_user_profile`
- `is_signup_form_complete` set to `true`
- Response: `{ success: true }`

**Step 7:** Navigate to home

---

### Scenario 2: Existing user (tel-only), method changed to LINE+TEL

**Initial state:**
- User account has `tel`, no `line_id`
- `is_signup_form_complete = true`
- Merchant changes `auth_methods` from `["tel"]` to `["line", "tel"]`

**Step 1:** User calls `bff-auth-complete` with `tel`, `otp_code`, `session_id`
- Finds existing user by tel
- Detects missing LINE (required by auth_methods)
- Response: `{ next_step: "verify_line", access_token }`

**Step 2:** User clicks LINE login, FE calls `auth-line`
- Gets `{ line_user_id }`

**Step 3:** User calls `bff-auth-complete` with `line_user_id` and `access_token`
- Validates access_token, finds existing user
- Links LINE to existing account
- Checks profile completion (already complete)
- Response: `{ next_step: "complete", access_token }`

**Step 4:** Navigate to home

---

### Scenario 3: Existing user with complete profile

**Step 1:** User authenticates (LINE or tel or both depending on auth_methods)
- `bff-auth-complete` finds existing user
- All required auth methods present
- `is_signup_form_complete = true`
- No missing required fields

**Response:**
```json
{
  "success": true,
  "next_step": "complete",
  "access_token": "...",
  "is_signup_form_complete": true,
  "missing": {
    "tel": false,
    "line": false,
    "consent": false,
    "profile": false,
    "address": false
  },
  "missing_data": null
}
```

**Frontend:** Navigate directly to home, skip form

---

### Scenario 4: Existing user, filled form before but has new required fields

**Initial state:**
- User previously completed signup form
- Merchant adds new required fields to template

**Step 1:** User authenticates
- `bff-auth-complete` finds existing user
- `is_signup_form_complete = true`
- But new required fields added to template (detected by checking empty values)

**Response:**
```json
{
  "success": true,
  "next_step": "complete_profile_existing",
  "access_token": "...",
  "is_signup_form_complete": true,
  "missing_data": {
    "pdpa": [ /* only missing mandatory consents */ ],
    "default_fields_config": [
      {
        "id": "default-fields-group",
        "fields": [ /* only missing required fields */ ]
      }
    ],
    "custom_fields_config": [ /* only groups with missing required fields */ ]
  }
}
```

**Frontend:** Show form with only missing required fields, allow user to complete

---

### Scenario 5: Existing user (LINE-only), never filled form, method changed to LINE+TEL

**Initial state:**
- User account has `line_id`, no `tel`
- `is_signup_form_complete = false`
- Merchant changes to `["line", "tel"]`

**Step 1:** User calls `bff-auth-complete` with `line_user_id`
- Finds existing user by LINE
- Detects missing tel
- Response: `{ next_step: "verify_tel", access_token }`

**Step 2:** User enters phone + OTP, calls `bff-auth-complete` with `access_token`, `tel`, `otp_code`, `session_id`
- Links tel to existing account
- Checks profile: `is_signup_form_complete = false`
- Response: `{ next_step: "complete_profile_existing", missing_data: {full form} }`

**Step 3:** User fills form, calls `bff_save_user_profile`

**Step 4:** Navigate to home

---

## Key Design Decisions

### Phone Number Normalization
All tel formats normalized to `+66XXXXXXXXX`:
- Implemented in: `auth-send-otp`, `bff-auth-complete`
- Ensures consistent lookups across `user_accounts`, `otp_requests`

### Custom Authentication (Not Supabase Auth)
- Uses custom JWT generation in `bff-auth-complete`
- `auth_user_id` = `user_id` (self-referencing)
- No foreign key to `auth.users`
- JWT claims include: `merchant_id`, `user_id`, `phone`, `line_id`

### Profile Completion Logic
- `is_signup_form_complete` flag: Has user ever submitted the form?
- Dynamic validation: Checks required fields in `user_field_config` and `form_fields`
- Full form vs. missing-only: Based on `is_signup_form_complete` status

### Caching Strategy
- **Cached (5 min TTL):** Form templates, translations, persona groups, consent versions
- **Never cached:** User data (values, selections, consent status)
- **Cache key:** `merchant:{merchant_id}:user_profile_template:all_languages`
- **Cache invalidation:** Auto-expire (5 min) or manual via `fn_invalidate_user_profile_template_cache(merchant_id)`

### Deactivated Default Fields
- `phone` - managed via auth flow, not shown in signup form
- `line_id` - managed via auth flow, not shown in signup form

---

## Frontend Implementation Guide

### Initial Page Load
```javascript
// 1. Get auth config
const config = await bff_get_auth_config({ merchant_code: "newcrm" });
// config.auth_methods → ["line", "tel"]

// 2. Show appropriate auth UI based on config
if (config.auth_methods.includes('line')) {
  // Show LINE login button
}
if (config.auth_methods.includes('tel')) {
  // Show phone input
}
```

### LINE Login Flow
```javascript
// 1. User clicks LINE button → redirect to LINE OAuth
// 2. Callback with code
const lineProfile = await auth_line({ code, merchant_code, redirect_uri });
// lineProfile.line_user_id

// 3. Call auth complete
const result = await bff_auth_complete({
  merchant_code: "newcrm",
  line_user_id: lineProfile.line_user_id
});

// 4. Handle next_step
handleNextStep(result);
```

### Phone Login Flow
```javascript
// 1. User enters phone
const otpResult = await auth_send_otp({ phone, merchant_code });
// otpResult.session_id

// 2. User enters OTP
const result = await bff_auth_complete({
  merchant_code: "newcrm",
  tel: phone,
  otp_code: otp,
  session_id: otpResult.session_id
});

// 3. Handle next_step
handleNextStep(result);
```

### Handling `next_step`
```javascript
function handleNextStep(result) {
  // Store credentials if provided
  if (result.access_token) {
    localStorage.setItem('access_token', result.access_token);
    localStorage.setItem('refresh_token', result.refresh_token);
  }

  switch (result.next_step) {
    case 'verify_line':
      // Show LINE login button
      // Store access_token if provided (for linking)
      navigateTo('/auth/line');
      break;
      
    case 'verify_tel':
      // Show phone input + OTP form
      // Store access_token if provided (for linking)
      navigateTo('/auth/phone');
      break;
      
    case 'complete_profile_new':
      // Bind result.missing_data to form variable
      variables['45691153-f0a5-42fa-ac9a-5729a9853be2'] = result.missing_data;
      // Show form with "ยินดีต้อนรับ!" header
      // Initialize form_step to first section with items
      navigateTo('/profile/complete');
      break;
      
    case 'complete_profile_existing':
      // Bind result.missing_data to form variable
      variables['45691153-f0a5-42fa-ac9a-5729a9853be2'] = result.missing_data;
      // Show form with "ยินดีต้อนรับกลับ!" header
      // If is_signup_form_complete=false → show full form
      // If is_signup_form_complete=true → show only missing fields
      navigateTo('/profile/complete');
      break;
      
    case 'complete':
      // All authentication and profile complete
      navigateTo('/home');
      break;
  }
}
```

### Form Navigation - Next Button
```javascript
// On next button click
const result = await nextButtonWorkflow();
// Returns: { upsert: boolean, nextStep: string|null }

if (result.upsert) {
  // Last step completed
  const formData = variables['45691153-f0a5-42fa-ac9a-5729a9853be2'];
  await bff_save_user_profile(formData);
  // Navigate to home
  navigateTo('/home');
} else {
  // form_step automatically updated to result.nextStep
  // UI automatically shows next section
}
```

### Form Navigation - Back Button
```javascript
// On back button click
const result = await backButtonWorkflow();
// Returns: { isFirst: boolean, prevStep: string|null }

// form_step automatically updated to prevStep
// UI automatically shows previous section
```

### Form Validation - Next Button Visibility
```javascript
// Bind to next button v-if
const canProceed = checkRequiredFieldsFilled();
// Returns true/false based on form_step and required fields

// Also check if not in auth verification flow
const nextStep = variables['b198191a-68f1-412e-906c-59b90022ebbd'];
const showButton = canProceed && nextStep !== 'verify_line' && nextStep !== 'verify_tel';
```

### Form Validation - Error Message Visibility
```javascript
// Bind to error message v-if
const showError = checkInvalidFields();
// Inverted logic from canProceed
// Returns true when required fields missing
```

---

## Database Schema Summary

### Core Tables

**user_accounts**
- Primary user table
- Columns: `id`, `merchant_id`, `tel`, `line_id`, `email`, `fullname`, `persona_id`, `channel_*`, `is_signup_form_complete`, `skip_cdc`
- Auth methods stored here: `tel`, `line_id`
- `auth_user_id` = `id` (self-referencing for custom auth)
- `skip_cdc = true` is reserved for migration/import rows so CDC consumers do not treat them as native signup events

**user_address**
- 1:1 relationship with user_accounts
- Columns: `user_id`, `addressline_1`, `city`, `district`, `subdistrict`, `postcode`, `country_code`
- UNIQUE constraint on `user_id` for UPSERT

**form_submissions + form_responses**
- Stores custom field responses
- `form_submissions`: One per user per form template
- `form_responses`: One per field per submission
- Supports `text_value`, `array_value` (jsonb[]), `object_value`

**user_consent_ledger**
- Audit log of consent actions
- Columns: `user_id`, `consent_version_id`, `action` (accepted/withdrawn)
- Append-only ledger

**user_communication_preferences**
- Topic subscriptions
- Columns: `user_id`, `topic_id`, `opted_in`
- UPSERT on conflict

**otp_requests**
- OTP validation records
- Columns: `phone`, `otp_code`, `session_id`, `attempts`, `verified`, `expires_at`
- TTL: 10 minutes

**refresh_tokens**
- JWT refresh tokens
- Columns: `user_id`, `token`, `expires_at`
- TTL: 30 days

### Configuration Tables

**merchant_master**
- `auth_methods` TEXT[] - Authentication method configuration

**user_field_config**
- Default field definitions
- `active_status = false` for `phone`, `line_id` (managed via auth)

**form_templates + form_fields + form_field_groups**
- Custom field definitions
- Template code `'USER_PROFILE'` used for signup form

**consent_versions**
- PDPA form definitions
- `interaction_type`: `'notice'` | `'optional'` | `'required'`

**communication_topics**
- Topic subscription options

---

## Security Patterns

### Row Level Security (RLS)
All user data filtered by `get_current_merchant_id()` extracted from:
1. Custom header `x-merchant-id`
2. JWT claim `merchant_id`

### Function Security
- All BFF functions: `SECURITY DEFINER`
- Permissions granted to `authenticated` role
- Public endpoints: `auth-line` (`verify_jwt: false`)
- Other edge functions: `verify_jwt: true`

### JWT Structure
```json
{
  "sub": "user_id",
  "merchant_id": "uuid",
  "user_id": "uuid",
  "phone": "+66966564526",
  "line_id": "U46fa97...",
  "role": "authenticated",
  "aud": "authenticated",
  "iss": "supabase",
  "exp": 1234567890
}
```

**Expiry:**
- Access token: 24 hours
- Refresh token: 30 days

---

## Error Handling

### Common errors from `bff-auth-complete`:

| Error | Reason |
|-------|--------|
| `"merchant_code is required"` | Missing merchant_code parameter |
| `"Invalid merchant_code"` | merchant_code not in MERCHANT_REGISTRY |
| `"Incomplete phone verification parameters"` | Missing tel, otp_code, or session_id (must provide all 3) |
| `"Invalid or expired OTP"` | OTP validation failed or max attempts exceeded |
| `"Credentials belong to different accounts"` | LINE and tel registered to different users |
| `"Failed to create account"` | Database error during user creation |

### Error handling strategy:
- Display error message to user
- Log details for debugging
- For auth errors: Return to auth screen
- For profile errors: Allow retry

---

## Data Flow Diagram

```
┌─────────────────────────────────────────────────────────────────┐
│                         FRONTEND                                │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  1. Get Auth Config                                             │
│     └─> bff_get_auth_config(merchant_code)                      │
│                                                                 │
│  2a. LINE Flow                                                  │
│      └─> LINE OAuth → auth-line(code) → line_user_id           │
│                                                                 │
│  2b. Phone Flow                                                 │
│      └─> auth-send-otp(phone) → session_id                      │
│      └─> User enters OTP                                        │
│                                                                 │
│  3. Complete Auth                                               │
│     └─> bff-auth-complete(credentials) → next_step, access_token│
│                                                                 │
│  4. Profile Form (if next_step = complete_profile_*)            │
│     └─> missing_data → form variable                            │
│     └─> form_step navigation (persona → default → custom → pdpa)│
│     └─> bff_save_user_profile(form_data)                        │
│                                                                 │
│  5. Home (if next_step = complete)                              │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
                              ↓
┌─────────────────────────────────────────────────────────────────┐
│                        EDGE FUNCTIONS                           │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  auth-line (Deno)                                               │
│  └─> LINE OAuth code exchange                                   │
│  └─> Returns LINE profile                                       │
│                                                                 │
│  auth-send-otp (Deno)                                           │
│  └─> Generate OTP                                               │
│  └─> Store in otp_requests                                      │
│  └─> Send SMS via send-sms-8x8                                  │
│                                                                 │
│  bff-auth-complete (Deno) ⭐ CENTRAL HUB                        │
│  └─> Find/create user                                           │
│  └─> Validate OTP                                               │
│  └─> Link auth methods                                          │
│  └─> Generate JWT                                               │
│  └─> Call bff_get_user_profile_template                         │
│  └─> Determine next_step                                        │
│  └─> Build missing_data payload                                 │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
                              ↓
┌─────────────────────────────────────────────────────────────────┐
│                   POSTGRES FUNCTIONS                            │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  bff_get_auth_config(merchant_code)                             │
│  └─> Returns auth_methods from merchant_master                  │
│                                                                 │
│  bff_get_user_profile_template(mode, language, merchant, event) │
│  └─> Redis: full merchant template (5 min), then per-request:     │
│  └─> Extract language → filter fields by JWT persona → optional   │
│      event pre-fill (new) → overlay user values (edit)            │
│                                                                 │
│  bff_save_user_profile(form_data)                               │
│  └─> UPSERT user_accounts                                       │
│  └─> UPSERT user_address                                        │
│  └─> UPSERT form_submissions + form_responses                   │
│  └─> INSERT user_consent_ledger                                 │
│  └─> UPSERT user_communication_preferences                      │
│  └─> Set is_signup_form_complete = true                         │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
                              ↓
┌─────────────────────────────────────────────────────────────────┐
│                        DATABASE                                 │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  merchant_master → auth_methods config                          │
│  user_accounts → identities, profile, is_signup_form_complete   │
│  user_address → addresses                                       │
│  form_* → custom fields                                         │
│  consent_versions → PDPA forms                                  │
│  user_consent_ledger → consent audit log                        │
│  communication_topics → topic options                           │
│  user_communication_preferences → subscriptions                 │
│  otp_requests → OTP validation                                  │
│  refresh_tokens → JWT refresh                                   │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
                              ↓
┌─────────────────────────────────────────────────────────────────┐
│                      REDIS CACHE                                │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  Key: merchant:{id}:user_profile_template:all_languages         │
│  TTL: 5 minutes                                                 │
│  Value: Form templates + all translations                       │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

---

## Variable Reference for Frontend

### WeWeb Global Variables

**Form data variable** (e.g., `variables['45691153-f0a5-42fa-ac9a-5729a9853be2']`)
- Stores the entire form structure from `missing_data`
- Updated by field value updater with debounce
- Passed to `bff_save_user_profile` when form complete

**Form step variable** (e.g., `variables['f214fed7-7ce4-43f6-888f-251cb10b4191']`)
- Current form section: `"persona"` | `"default_field"` | `"custom_field"` | `"pdpa"`
- Updated by next/back button workflows
- Used for conditional rendering and validation

**Next step variable** (e.g., `variables['b198191a-68f1-412e-906c-59b90022ebbd']`)
- Stores `next_step` value from `bff-auth-complete`
- Used for page routing and conditional UI

---

## Common Frontend Formulas

### Check if in auth verification flow
```javascript
!variables['b198191a-68f1-412e-906c-59b90022ebbd'] || 
contains(
  createArray("verify_line", "verify_tel", null, ""), 
  variables['b198191a-68f1-412e-906c-59b90022ebbd']
)
```

### Get field value by field_key
```javascript
// Example: Get city value
variables['45691153-f0a5-42fa-ac9a-5729a9853be2']
  ?.default_fields_config
  ?.flatMap(g => g.fields)
  ?.find(f => f.field_key === 'city')
  ?.value
```

### Combine workflow results
```javascript
{
  ...context.workflow['workflow-1-id'].result, 
  ...context.workflow['workflow-2-id'].result
}
```

---

## Signup Code System

A merchant-managed pool of one-time-or-quota codes that gate signup, prefill profile data, and (since 2026-05-14) optionally link the registering user to a specific `store_master` row.

### Schema

- `signup_codes (id, merchant_id, field_config_id, code, metadata jsonb, max_consumers, consumed_count, is_active, store_id)` — codes are scoped to a "pool" defined by a `user_field_config` row of type `external_code`. `store_id` (added 2026-05-14) is an optional FK to `store_master`; a `BEFORE INSERT/UPDATE` trigger (`trg_signup_codes_check_store_merchant`) enforces `store_master.merchant_id = signup_codes.merchant_id`.
- `signup_code_claims (id, merchant_id, code_id, user_id, claimed_at)` — one row per consumption, primary audit trail.
- `user_accounts.store_id` (added 2026-05-14) — nullable FK to `store_master`. Mirrors the cross-merchant trigger guard. Currently written only by `fn_consume_signup_code`; reset to NULL by `store_master` deletion (`ON DELETE SET NULL`).

### Pool configuration (`user_field_config.config.external_code`)

| key | values | meaning |
|---|---|---|
| `prefill_schema.default` | `text[]` | Whitelisted built-in field keys whose values codes may carry in `metadata.prefill.default` |
| `prefill_schema.custom` | `text[]` | Whitelisted `form_templates(code='USER_PROFILE')` custom field keys for `metadata.prefill.custom` |
| `target_user_column` | `external_user_id` \| `member_code` \| `id_card` \| `null` | If set, consume calls `chokepoint_post_user_event` to copy the code into the corresponding column on `user_accounts` |
| `store_binding` *(new)* | `off` (default) \| `optional` \| `required` | Controls whether codes in this pool may / must carry a `store_code` at upload time |

### Lifecycle

1. **Admin uploads codes** — `bff_upload_signup_codes(p_field_config_id, p_codes jsonb)`.
   - Each row: `{ code, store_code?, max_consumers?, is_active?, metadata?: { preview, prefill: { default, custom } } }`.
   - **Validation pass (all-or-nothing):** any `store_code` mismatch with the pool's `store_binding`, any unresolvable `store_code`, or any `KEY_NOT_IN_POOL_SCHEMA` aborts the entire upload with `STORE_VALIDATION_FAILED`. No partial writes.
   - **Write pass:** upserts by `(field_config_id, code)`. Existing prefill-schema row errors continue to be collected per-row in `data.errors[]` and skipped (existing behavior). `store_id` is overwritten from `store_code` on update.
2. **User enters code** during signup → FE calls `bff_validate_signup_code(p_field_key, p_code, p_selected_persona_id?)`.
   - Returns `data.preview_metadata` (with `data.preview_metadata.store = { id, code, name }` if bound) + `data.prefill.{default, custom}` + `data.store` (top-level convenience).
   - Pre-claim gates: `EMPTY_CODE`, `FIELD_NOT_FOUND`, `PERSONA_MISMATCH`, `INVALID_CODE`, `CODE_INACTIVE`, `CODE_EXHAUSTED`, plus (if code carries a store and caller is authenticated) `NOT_SELLER` and `STORE_CONFLICT`.
3. **Account is created / signup form submitted** → `fn_consume_signup_code(p_user_id, p_field_config_id, p_code)`.
   - Atomic `UPDATE … RETURNING` on `consumed_count`, insert into `signup_code_claims`.
   - If `signup_codes.store_id IS NOT NULL`: enforce `user_accounts.user_type = 'seller'` (else `NOT_SELLER`). Then **first-wins**: if `user_accounts.store_id IS NULL` set it to the code's store; if it equals the code's store, no-op (idempotent); else raise `STORE_CONFLICT`.
   - `already_claimed=true` short-circuit returns the existing linkage without retrying.
   - Returns `linked_store_id` so the caller can show "You're linked to store X".

### Error codes (consume-time `RAISE EXCEPTION`, format `SIGNUP_CODE:<CODE>:<message>`)

| code | when |
|---|---|
| `FIELD_NOT_FOUND` | `field_config_id` doesn't exist |
| `PERSONA_MISMATCH` | Pool has `persona_ids` and user's persona isn't in the list |
| `INVALID_CODE` | No `signup_codes` row matches `(field_config_id, code)` |
| `CODE_INACTIVE` | Row exists but `is_active = false` |
| `CODE_EXHAUSTED` | `consumed_count >= max_consumers` and user hasn't already claimed |
| `NOT_SELLER` | Code carries a `store_id` but `user_accounts.user_type <> 'seller'` |
| `STORE_CONFLICT` | Code carries a `store_id` but the seller is already linked to a different store |

### Frontend contract changes (2026-05-14)

- `bff_validate_signup_code` response gains `data.store = { id, code, name } \| null` (and the same object also appears inside `data.preview_metadata.store` for backward-compatible rendering paths).
- `bff_list_signup_codes` response items gain `store_id`, `store_code`, `store_name`. The list response also returns `data.store_binding` (the pool's mode) so the admin UI can switch between showing or hiding the store column.
- `bff_upload_signup_codes` accepts a new per-row `store_code` field and a new top-level failure shape: `success=false, data.error_code='STORE_VALIDATION_FAILED', data.errors[]` with per-row `{ row, code, store_code, error_code, message }`. Existing `data.errors[]` for prefill-schema mismatches still uses `KEY_NOT_IN_POOL_SCHEMA` and continues to skip-but-write the other rows.
- `fn_consume_signup_code` response now includes `linked_store_id uuid \| null`.

---

## Acquisition Source (first-touch attribution)

Merchants define channel codes in `acquisition_source_master`. On member signup, the loyalty app passes `acquisition_source` (URL param or local storage from prior visit) into `bff-auth-complete` and `bff_save_user_profile`; `chokepoint_post_user_event` writes `user_accounts.acquisition_source` once (first-touch, immutable after set).

### Schema — `acquisition_source_master`

| column | type | notes |
|---|---|---|
| `id` | uuid | PK |
| `merchant_id` | uuid | FK → `merchant_master` |
| `source_code` | text | Unique per merchant; URL-safe (`a-z`, `0-9`, `_`); **immutable after create** |
| `source_name` | text | Admin display label |
| `description` | text | Optional |
| `created_at` / `updated_at` | timestamptz | |

### Admin BFFs (JWT / `get_current_merchant_id()`)

| function | purpose |
|---|---|
| `bff_list_acquisition_sources()` | List all sources for merchant; each row includes `member_count` (active users with matching `user_accounts.acquisition_source`) |
| `bff_get_acquisition_source_details(p_mode, p_acquisition_source_id)` | `p_mode='new'` → empty template; `p_mode='edit'` + id → single source + `member_count` |
| `bff_upsert_acquisition_source(p_data jsonb)` | Create (`id` omitted, `source_code` + `source_name` required) or update (`id` set; `source_name`, `description` only) |
| `bff_delete_acquisition_source(p_acquisition_source_id)` | Hard delete; blocked with `SOURCE_IN_USE` when `member_count > 0` |

**Upsert payload:** `{ id?, source_code?, source_name, description? }`

**Member link pattern (frontend-built):** `{loyalty_app_base_url}?acquisition_source={source_code}` — QR export is client-side; no backend RPC.

---

This system provides a **flexible, secure, and merchant-configurable authentication flow** with dynamic profile completion and seamless auth method linking.


































