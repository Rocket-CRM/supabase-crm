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
10. Check profile completion using `bff_get_user_profile_template` (only when auth methods are satisfied)
11. Determine `next_step` based on profile completion
12. Build `missing_data` payload (full form or missing-only)
13. Generate refresh token
14. If `next_step === "complete"`, also merge `get_user_summary()` output into `user_account` (flat)
15. Return comprehensive response

---

### 5. `bff_get_user_profile_template(p_language, p_mode)`
**Purpose:** Get profile form template with translations

**Input:**
- `p_language`: `'en'` | `'th'` | `'zh'` | `'ja'`
- `p_mode`: `'new'` | `'edit'`

**Output:**
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
  "cache_hit": true,
  "language": "th",
  "timestamp": "2025-12-08T00:00:00Z"
}
```

**Mode behavior:**
- `'new'`: All `value` fields are `null`, `isAccepted: false`, `selected: false`
- `'edit'`: Overlays user's actual data from DB

**Caching:**
- Static structure cached for 5 minutes in Redis
- User data fetched fresh (never cached)
- Cache key: `merchant:{merchant_id}:user_profile_template:all_languages`

**Frontend usage:** 
- Called internally by `bff-auth-complete`
- Can be called directly for profile edit page

**Deactivated fields:**
- `phone` - managed via auth flow, not shown in form
- `line_id` - managed via auth flow, not shown in form

---

### 6. `bff_save_user_profile(p_data)`
**Purpose:** Save user profile form (upserts across multiple tables)

**Input:** The entire payload from `bff_get_user_profile_template` with user-filled `value` fields

**Tables updated:**
- `user_accounts` - default fields, persona, channels, **sets `is_signup_form_complete = true`**
- `user_address` - address fields
- `form_submissions` + `form_responses` - custom fields
- `user_consent_ledger` - PDPA consents
- `user_communication_preferences` - topics

**Output:**
```json
{
  "success": true,
  "user_id": "uuid",
  "is_new_user": false,
  "is_signup_form_complete": true
}
```

**Authentication:** Uses `auth.uid()` from bearer token

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
- Columns: `id`, `merchant_id`, `tel`, `line_id`, `email`, `fullname`, `persona_id`, `channel_*`, `is_signup_form_complete`
- Auth methods stored here: `tel`, `line_id`
- `auth_user_id` = `id` (self-referencing for custom auth)

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
│  bff_get_user_profile_template(language, mode)                  │
│  └─> Get from Redis cache (if exists)                           │
│  └─> Or build from DB (form templates + translations)           │
│  └─> Store in cache (5 min TTL)                                 │
│  └─> Extract requested language                                 │
│  └─> If mode='edit': Overlay user data from DB                  │
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

This system provides a **flexible, secure, and merchant-configurable authentication flow** with dynamic profile completion and seamless auth method linking.


































