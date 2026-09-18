# Signup & Login

> Per-domain reference. Read ONLY when working on this domain. For the keyword → file map, see `_index.md`.

**Keywords:** signup, login, registration, profile form, form step, next step, OTP, LINE login, profile completion, missing fields, consent, PDPA

**Source:** `Signup_Login.md`

**FE-Relevant Sections:**

| Section Heading | Lines | What it contains |
|---|---|---|
| Authentication Methods Configuration | 10–19 | `auth_methods` array possibilities |
| Function Inventory | 24–288 | All 6 functions with full input/output specs |
| `next_step` Values | 289–309 | 5 possible values with JWT availability and FE action |
| `form_step` (Frontend state) | 312–326 | Frontend navigation: `persona` → `default_field` → `custom_field` → `pdpa` |
| Frontend JavaScript Functions | 328–388 | Next/back button logic, validation, PDPA handler, field value updater |
| Scenario Matrix | 391–534 | 5 detailed scenarios covering new user, existing user, method changes, missing fields |
| Handling `next_step` | 619–664 | Complete `switch` block for frontend routing |
| `missing_data` content logic | 301–309 | What `missing_data` contains based on `next_step` and `is_signup_form_complete` |

**Supabase Functions (FE-callable):**

| Function | Parameters | Returns | Lines |
|---|---|---|---|
| `bff_get_auth_config(p_merchant_code)` | `p_merchant_code (text)` | `{ auth_methods }` | 25–41 |
| `bff_get_user_profile_template(p_language, p_mode)` | `p_language ('en'/'th'/'zh'/'ja')`, `p_mode ('new'/'edit')` | Full form template with translations, persona, PDPA | 218–256 |
| `bff_save_user_profile(p_data)` | `p_data (jsonb)` — entire form payload | `{ success, user_id, is_signup_form_complete }` | 263–287 |

**Key Business Rules (summary):**
- `bff-auth-complete` is the central hub: find/create user → validate → issue JWT → check profile completion
- `next_step` controls the entire UX flow from auth through profile completion
- `form_step` is frontend-only state for multi-section form navigation
- Profile template cached 5 min (structure only); user values always fetched live
- `is_signup_form_complete` flag + dynamic required-field checking determines if profile form is needed
- Deactivated default fields: `phone` and `line_id` (managed via auth flow, not shown in form)
- `user_accounts.skip_cdc = true` marks migration/import rows that CDC consumers must ignore for signup-triggered automations; native signups keep the default `false`

---
