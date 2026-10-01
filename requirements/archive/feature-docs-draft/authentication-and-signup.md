# Feature Guide: Authentication & Signup

## 1. Overview

Authentication and signup form a single flow from the member's perspective: open the app, prove your identity, fill in your profile, and land on the homepage. The system uses a dual architecture — members authenticate through LINE OAuth and/or Phone OTP via custom JWTs, while admins use standard Supabase Auth (email + password). This guide covers both, with emphasis on the member-facing flow since it contains the complex logic.

The entire member flow is orchestrated by a single value: `next_step`. Returned by the central edge function `bff-auth-complete`, this value tells the frontend exactly which screen to show next — whether that's a LINE login prompt, a phone verification form, a profile registration form, or a direct redirect to the homepage. Every authentication scenario, from brand-new users to returning members who need to link a new auth method, resolves through the same `next_step` state machine.

For merchants, the system solves two problems: (1) flexible identity — each merchant chooses which auth methods their members use (LINE only, phone only, or both), and (2) progressive profile completion — the signup form adapts based on what data the member is still missing, even if new required fields are added after initial registration.

## 2. Key Concepts

**Authentication Methods** — Merchant-configurable combination of identity providers. Three configurations: `["line"]` (LINE only), `["tel"]` (phone OTP only), `["line", "tel"]` (both required). Stored in `merchant_master.auth_methods`. Example: A Thai-market merchant sets `["line", "tel"]` so members must verify both LINE and phone.

**Custom JWT** — The member access token, signed with Supabase's project secret using HS256. Contains claims: `sub`, `merchant_id`, `user_id`, `phone`, `line_id`, `role`, `aud`, `iss`, `exp`. Supabase PostgREST validates this token identically to native Supabase Auth JWTs. Admin JWTs are standard Supabase Auth tokens with no custom claims.

**`next_step`** — API-driven state returned by `bff-auth-complete`. Five possible values:

| Value | Meaning | JWT issued? |
|---|---|---|
| `verify_line` | Member needs to connect LINE | Sometimes |
| `verify_tel` | Member needs to verify phone | Sometimes |
| `complete_profile_new` | New member, show full registration form | Yes |
| `complete_profile_existing` | Returning member, show missing fields | Yes |
| `complete` | All done, go to homepage | Yes |

**`form_step`** — Frontend-only state tracking which section of the multi-step profile form the member is viewing. Sequence: `persona` → `default_field` → `custom_field` → `pdpa`. Steps with no content are automatically skipped.

**`bff-auth-complete`** — The central hub edge function. Handles all auth scenarios: finds or creates users, validates OTP, links auth methods, generates JWTs, evaluates profile completion, and returns the `next_step` + `missing_data` payload. Every auth flow routes through this single function.

**Phone Normalization** — All phone numbers are converted to international format before storage or lookup. `0966564526` → `+66966564526`. `+660966564526` → `+66966564526` (removes extra 0). Applied in both `auth-send-otp` and `bff-auth-complete`.

**`is_signup_form_complete`** — Boolean flag on `user_accounts`. Set to `true` when the member submits the profile form via `bff_save_user_profile`. Controls whether `missing_data` contains the full form or only newly-added required fields.

**Auth Drawer** — Bottom-sheet popup (vaul drawer) in the member app that handles the entire auth + profile completion flow. Always mounted, opens via AuthProvider state machine. Renders auth screens or profile form steps depending on `next_step`.

**Token Expiry** — Access token: 24 hours (member), ~1 hour (admin). Refresh token: 30 days (member). Tokens stored in cookies: `loyalty_access_token` (readable by JS) and `loyalty_refresh_token` (httpOnly).

**Deactivated Default Fields** — `phone` and `line_id` fields exist in `user_field_config` but are set to `active_status = false`. These are managed by the auth flow, not shown in the signup form.

## 3. Configuration Reference

### Authentication Methods

| Setting | What it controls | Example | Default |
|---|---|---|---|
| `auth_methods` | Which identity providers members must use | `["line", "tel"]` | Merchant-specific |

Retrieved by frontend via `bff_get_auth_config(merchant_code)`.

### OTP Settings

| Setting | Value |
|---|---|
| Code length | 6 digits |
| Expiry | 10 minutes |
| Max attempts | 3 per session |
| SMS provider | 8x8 |
| Resend cooldown | 30 seconds (frontend) |

### Token Configuration

| Token | Expiry | Storage |
|---|---|---|
| Member access token | 24 hours | `loyalty_access_token` cookie (JS-readable) |
| Member refresh token | 30 days | `loyalty_refresh_token` cookie (httpOnly) |
| Admin access token | ~1 hour (Supabase default) | Supabase client (automatic) |

### Profile Form Template

| Setting | What it controls | Source |
|---|---|---|
| Default fields | Standard user fields (name, email, etc.) | `user_field_config` |
| Custom fields | Merchant-defined fields | `form_templates` + `form_fields` (template code `USER_PROFILE`) |
| Persona selection | Persona groups and avatars | `persona_groups` + `personas` |
| PDPA consents | Privacy notices and consent checkboxes | `consent_versions` |
| Field visibility by persona | Which fields appear per persona | `persona_ids` array on each field |

Template cached in Redis for 5 minutes (`merchant:{id}:user_profile_template:all_languages`). Persona filtering applied per-request based on the caller's JWT.

## 4. Admin Journey

**Repo:** `Rocket-CRM/loyalty-admin`

**Route map:**

| Page name | Current route | Data source |
|---|---|---|
| Login | `/login` | `supabase.auth.signInWithPassword()` |
| Merchant Settings | `/merchant-settings` | `merchant_master` |

### 4a. Admin Login

1. Admin navigates to the admin dashboard login page
2. Enters email + password
3. Standard Supabase Auth validates credentials
4. On success: Supabase client stores session automatically, redirects to dashboard
5. On failure: error message displayed

Admin auth uses Supabase Auth natively — no custom JWT, no LINE/OTP. The admin JWT contains `email`, `role`, and standard Supabase claims. No `merchant_id` or `phone` custom claims.

### 4b. Configure Member Auth Methods

The `auth_methods` array on `merchant_master` determines which identity providers members must use. This is configured at the merchant level. When a merchant changes from `["tel"]` to `["line", "tel"]`, existing phone-only members will be prompted to link their LINE account on next login.

### 4c. View Member Auth Status

Member records in `user_accounts` show: `tel` (phone linked), `line_id` (LINE linked), `is_signup_form_complete` (profile submitted). Admins can inspect these fields to diagnose login issues.

## 5. Member Experience

**Repo:** `Rocket-CRM/loyalty-user`

**Route map:**

| Page / Component | Current route / trigger | Data source |
|---|---|---|
| Auth Drawer (initial) | `useAuth().openAuthDrawer()` or manual trigger | `bff_get_auth_config` |
| Auth Drawer (LINE redirect) | Homepage with `?code=&state=` params | `LineCallbackHandler` → `/api/auth/line/callback` |
| Auth Drawer (profile gate) | Any non-home page, authenticated user | `AuthGate` → `checkProfileCompletion()` |
| Profile Form (within drawer) | `next_step = complete_profile_*` | `bff-auth-complete` → `missing_data` |

### 5a. Scenario 1 — New User, LINE + Phone Required

1. Member opens app → Auth Drawer appears with LINE button + phone input (based on `auth_methods`)
2. Taps LINE button → redirects to LINE OAuth
3. LINE redirects back with `?code=` → `LineCallbackHandler` exchanges code via `auth-line` → gets `line_user_id`
4. Calls `bff-auth-complete` with `line_user_id` → response: `next_step: "verify_tel"`
5. Drawer shows phone input + "Get OTP" button
6. Member enters phone → `auth-send-otp` sends SMS → `session_id` stored
7. Member enters 6-digit OTP (auto-advances between input boxes)
8. Calls `bff-auth-complete` with `line_user_id` + `tel` + `otp_code` + `session_id`
9. New user created → response: `next_step: "complete_profile_new"`, `missing_data` = full form
10. Drawer shows profile form: persona selection → default fields → custom fields → PDPA consents
11. Member fills each step, Next button validates required fields before advancing
12. On final step, Confirm → `bff_save_user_profile` saves data, sets `is_signup_form_complete = true`
13. Drawer closes → homepage renders logged-in state

### 5b. Scenario 2 — Existing User (Phone Only), Method Changed to LINE + Phone

1. Member authenticates with phone OTP → `bff-auth-complete` detects missing LINE
2. Response: `next_step: "verify_line"` with JWT issued
3. Drawer shows LINE button with "Please connect your LINE account"
4. Member taps LINE → OAuth redirect → returns with code
5. `bff-auth-complete` called with `line_user_id` + `access_token` (for linking)
6. LINE linked to existing account → response: `next_step: "complete"` (profile already complete)
7. Drawer closes → homepage

### 5c. Scenario 3 — Returning User, Complete Profile

1. Member authenticates → `bff-auth-complete` finds existing user, all methods present, profile complete
2. Response: `next_step: "complete"`, `missing_data: null`
3. Drawer auto-closes → homepage

### 5d. Scenario 4 — Existing User, New Required Fields Added

1. Member authenticates → profile was previously complete, but merchant added new required fields
2. Response: `next_step: "complete_profile_existing"`, `missing_data` = only the new missing fields
3. Drawer shows abbreviated form with "ยินดีต้อนรับกลับ!" (Welcome back!) header
4. Member fills missing fields → save → drawer closes

### 5e. Scenario 5 — Existing User (LINE Only), Never Filled Form, Method Changed to LINE + Phone

1. Member authenticates with LINE → `bff-auth-complete` detects missing phone
2. Response: `next_step: "verify_tel"` with JWT issued
3. Member verifies phone via OTP → `bff-auth-complete` links phone
4. Profile not yet complete (`is_signup_form_complete = false`) → response: `next_step: "complete_profile_existing"`, `missing_data` = full form
5. Member fills full form → save → homepage

### 5f. Entry Points

| Trigger | Location | Behavior |
|---|---|---|
| LINE redirect | `LineCallbackHandler` on homepage | Detects `?code=`, exchanges token, opens drawer if needed |
| Profile gate | `AuthGate` on non-home pages | Authenticated user missing profile → opens drawer |
| Manual | Any component via `useAuth().openAuthDrawer()` | Opens drawer fresh |

## 6. Perspectives

### 6a. For Customer Success / Support

**Elevator pitch:** "Members sign in using LINE and/or phone OTP depending on your merchant settings. The system guides them through identity verification and profile completion automatically."

**Top support questions:**

| Question | Answer |
|---|---|
| "Member can't log in" | Check `auth_methods` config — does the member have the required methods linked? Check `user_accounts` for `tel`/`line_id` values |
| "OTP not received" | SMS delivery issue (8x8 provider). Verify phone format is correct. OTP expires in 10 minutes, max 3 attempts per session |
| "Member stuck on profile form" | Check `is_signup_form_complete` flag. If `false`, they haven't submitted the form. If `true` but still prompted, new required fields were added |
| "Member sees 'Could not load registration form'" | Edge function failed to fetch profile template. Member should tap Retry button. If persistent, check `bff_get_user_profile_template` function |
| "Member linked wrong LINE account" | `line_id` is stored on `user_accounts`. Requires manual update — no self-service LINE unlink in the current system |
| "Error: 'Credentials belong to different accounts'" | Member's LINE and phone are registered to separate `user_accounts` records. Requires manual account merge |

### 6b. For Marketing

**Value proposition:** Authentication doubles as onboarding. Instead of a separate registration flow, members authenticate with LINE (one tap in Thailand's dominant messaging app) and immediately enter a guided profile completion that captures persona, preferences, and consent — all in a single bottom-sheet interaction.

**Use-case stories:**

1. **Thai retail chain** — Uses `["line", "tel"]` to capture both LINE identity (for LINE OA messaging) and phone (for SMS campaigns). Member taps LINE → verifies phone → selects persona → done. Two identity channels captured in under 60 seconds.

2. **Event-based onboarding** — Members scan QR at an event, LINE authenticates them, and the profile form pre-fills event-specific address fields via `event_code`. Walk-in to registered member in one interaction.

**Differentiators:**
- **LINE-native** — one-tap authentication for Thailand's largest messaging platform
- **Progressive profiling** — form adapts to show only what's missing, even months after initial signup
- **Persona-aware fields** — different member types see different registration fields

### 6c. For Testers

**`next_step` state machine — test all 5 transitions:**

| # | Precondition | Auth input | Expected `next_step` |
|---|---|---|---|
| 1 | No account exists, method=`["line","tel"]` | LINE only | `verify_tel` |
| 2 | Existing account with tel, method changed to `["line","tel"]` | Phone OTP | `verify_line` |
| 3 | Existing account, all methods linked, profile complete | Any valid auth | `complete` |
| 4 | Existing account, `is_signup_form_complete=true`, new required fields | Any valid auth | `complete_profile_existing` |
| 5 | Existing account, `is_signup_form_complete=false` | Any valid auth | `complete_profile_existing` |
| 6 | No account, method=`["tel"]` | Phone OTP | `complete_profile_new` |

**`missing_data` content rules:**

| Condition | Content |
|---|---|
| `complete_profile_new` (new user) | Full form: persona, all fields, PDPA |
| `complete_profile_existing`, `is_signup_form_complete=false` | Full form (never submitted) |
| `complete_profile_existing`, `is_signup_form_complete=true` | Missing required fields only |
| `complete` | `null` |

**Business rules as assertions:**

- ASSERT: Phone `0966564526` is normalized to `+66966564526` before lookup/storage
- ASSERT: OTP expires after 10 minutes; 4th attempt on same session fails
- ASSERT: `bff-auth-complete` with mismatched LINE + phone (different accounts) returns error
- ASSERT: Custom JWT contains `merchant_id`, `user_id`, `phone`, `line_id` claims
- ASSERT: Access token expires after 24 hours; refresh token after 30 days
- ASSERT: `form_step` skips steps with no content (e.g., no persona config → skip persona step)
- ASSERT: `bff_save_user_profile` sets `is_signup_form_complete = true`
- ASSERT: Profile form Next button is disabled until all required fields in current step are filled
- ASSERT: PDPA mandatory consents must be accepted before Confirm
- ASSERT: Empty `missing_data` from edge function shows error + Retry button (never auto-saves)

**Bot testing shortcut:** `bff-auth-complete` accepts `bot_secret` field. When valid, OTP validation is skipped — phone is treated as verified. Requires `BOT_SECRET` env var on the Supabase project. Returns 403 if not configured or mismatched.

**Error states to test:**

| Input | Expected error |
|---|---|
| Missing `merchant_code` | `"merchant_code is required"` |
| Invalid `merchant_code` | `"Invalid merchant_code"` |
| Missing `otp_code` or `session_id` with `tel` | `"Incomplete phone verification parameters"` |
| Wrong OTP / expired | `"Invalid or expired OTP"` |
| LINE + phone belong to different accounts | `"Credentials belong to different accounts"` |

## 7. Business Rules

**Rule:** `next_step` determines the entire flow. The frontend never decides which screen to show — it follows the API instruction.
**Example:** Member with `line_id` but no `tel`, merchant requires both → `bff-auth-complete` returns `verify_tel` → frontend shows phone input.

**Rule:** `bff-auth-complete` is the single entry point for all auth scenarios. LINE-only, phone-only, both, linking a new method, and profile completion checks all route through this function.
**Example:** Even when a member already has a JWT and needs to link LINE, the call goes through `bff-auth-complete` with the `access_token` parameter.

**Rule:** Phone numbers are normalized to `+66XXXXXXXXX` before any database lookup or insert. Prevents duplicate accounts from format differences.
**Example:** Member enters `0966564526` → stored and looked up as `+66966564526`.

**Rule:** Profile completion is two-layered: (1) `is_signup_form_complete` flag for "has ever submitted," (2) dynamic check for required fields with empty values.
**Example:** Member submitted form 3 months ago (`is_signup_form_complete=true`), merchant adds new required field → member sees only the new field on next login.

**Rule:** `phone` and `line_id` are deactivated in `user_field_config`. These identities are managed exclusively by the auth flow, not editable via the profile form.
**Example:** The signup form never shows a "phone number" field — it's captured during OTP verification.

**Rule:** When `next_step` is `verify_line` or `verify_tel` (auth method still missing), `bff-auth-complete` skips profile template evaluation entirely and returns early.
**Example:** Member authenticates with phone, needs LINE → response includes JWT but no `missing_data`. Profile check happens only after all auth methods are satisfied.

**Rule:** LINE OAuth state is persisted to `sessionStorage` before redirect. On return, `LineCallbackHandler` restores credentials to continue the flow.
**Example:** Member was mid-phone-OTP, taps LINE → phone `session_id` and `tel` saved → LINE redirect → on return, all credentials combined for `bff-auth-complete`.

**Rule:** Custom JWT secret must match Supabase's Legacy JWT Secret across all services. Mismatch causes `PGRST301` errors or "Invalid signature" failures.
**Example:** `bff-auth-complete` signs with `SUPABASE_JWT_SECRET` → PostgREST validates with same secret → external services (crm-api) must use identical secret in `JWT_SECRET` env var.

## 8. Related Features

| Feature | Connection to Authentication & Signup |
|---|---|
| Forms | Profile completion uses the Forms system (`form_templates`, `form_fields`) for custom merchant-defined fields. See `Forms.md`. |
| Tags & Persona | Persona selection during signup determines which profile fields are visible. Persona-scoped fields only appear for matching personas. See `Tag_and_Persona.md`. |
| Currency | `get_user_summary()` is merged into the auth response when `next_step=complete`, providing points balance on first load. See `Currency.md`. |
| Translation | Profile form template supports multi-language via `p_language` parameter. See `Translation_System.md`. |
