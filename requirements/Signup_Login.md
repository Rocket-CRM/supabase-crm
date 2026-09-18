# Signup / Login

Member authentication (LINE, phone OTP, optional Shopify email linkage) and persona-aware profile completion before the member home. Standalone loyalty-user runs the full auth + profile loop; Shopify storefront uses server-trusted customer identity on panel open (no LINE/OTP inside the widget).

Owner surfaces: loyalty-admin, loyalty-user, rewarding-shopify (storefront widget, app proxy, customer account extensions)

## Concept

**Auth methods** — Merchant-wide list on `merchant_master.auth_methods`: `line`, `tel`, and optionally `shopify_email` (hybrid / headless paths that still use `bff-auth-complete`). The member app loads enabled methods via `bff_get_auth_config`.

**Identity proof** — LINE OAuth (`auth-line` edge) exchanges a code for `line_user_id` only; phone flow uses `auth-send-otp` plus `fn_validate_otp`. Neither edge creates a user or mints a session by itself.

**Session hub** — `bff-auth-complete` finds or creates `user_accounts`, links missing auth methods, evaluates profile completeness, returns `next_step`, and issues the **member JWT** via shared `issueMemberSession` (same issuer as Shopify proxy/extension — see `Authentication.md`).

**`next_step`** — API-level screen router from `bff-auth-complete`: verification steps (`verify_line`, `verify_tel`, `verify_shopify`) vs profile steps (`complete_profile_new`, `complete_profile_existing`) vs `complete` (home).

**Profile template** — `bff_get_user_profile_template` builds default fields, custom form fields (`USER_PROFILE` template), persona picker metadata, PDPA shells, and communication topics; persona-scoped fields filter server-side per member JWT.

**Profile completion flag** — `user_accounts.is_signup_form_complete` means the member has submitted the signup profile at least once; dynamic required-field checks can still force `complete_profile_existing` when merchants add new required fields.

**`form_step`** — Client-only section index within the profile form (`persona` → `default_field` → `custom_field` → `pdpa`); orthogonal to `next_step`.

**Validated signup codes** — Optional `external_code` rows on `user_field_config` with pools in `signup_codes` / claims in `signup_code_claims`; validated at field entry (`bff_validate_signup_code`) and consumed on save (`fn_consume_signup_code`).

**Shopify storefront identity** — Parallel path: HMAC app proxy or customer-account session token → find-or-create member → `issueMemberSession`. Theme Liquid customer id is never trusted for minting.

## Rules

- Auth method configuration is merchant-wide; the member UI must not offer disabled methods. Shopify embedded admin hides standalone auth settings (`GLOBAL_SETTINGS_SECTIONS.auth` off on Shopify surface).
- `bff-auth-complete` is the only hub that mints member sessions for LINE / OTP / `shopify_email` completion flows on loyalty-user.
- Phone numbers are normalized to E.164 (`+66…`) in `auth-send-otp` and `bff-auth-complete` before lookup or insert.
- If LINE and phone in one request resolve to **different** existing users → `409` with credentials conflict; no merge.
- OTP: 6 digits, 10-minute expiry, max 3 validation attempts per `session_id` (`fn_validate_otp` / `otp_requests`). OTP is never returned in API responses.
- **`verify_*` steps:** When a required auth method is still missing, hub returns `next_step` of `verify_line`, `verify_tel`, or `verify_shopify`, **with** `access_token` + `refresh_token`, `profile_check_skipped: true`, and `missing_data: null` — client stores the session and collects the missing proof, then calls hub again (optionally with `access_token` to link).
- **`next_step` → profile payload:**

| `next_step` | When | `missing_data` |
| --- | --- | --- |
| `complete_profile_new` | New `user_accounts` row after auth satisfied | Full template (persona, PDPA, all visible fields) |
| `complete_profile_existing` | Existing user, `is_signup_form_complete = false` | Full template |
| `complete_profile_existing` | Existing user, flag true but required consent/fields empty | Missing slices only |
| `complete` | Auth satisfied and profile/consent complete | `null` |

- Persona on template: universal fields (empty/null `persona_ids`) always shown; non-empty `persona_ids` require matching `user_accounts.persona_id` (or `p_selected_persona_id` during persona step). Empty persona on user → persona-scoped fields omitted until persona chosen.
- Default fields `phone` and `line_id` stay auth-managed (`active_status` false in config); not collected as free-text on the profile form.
- `bff_save_user_profile` upserts profile tables and sets `is_signup_form_complete` on success; must use member bearer JWT.
- **Signup codes:** Pool policy (single-use vs shareable cap), optional store binding, and persona scope enforced on validate/consume; see registry `Signup Code Validation` and `CHANGELOG` store-binding notes.
- **Shopify storefront:** Theme `customer.id` / email never mint sessions — only HMAC-verified app proxy fields or extension session tokens.
- **Shopify storefront:** At most **one** app-proxy auth call per rewards **panel open**; launcher and product points block stay identity-free.
- **Shopify storefront:** `customers/create` may link CRM early; member home in the widget still requires successful proxy (or extension) auth on panel open.
- **Shopify storefront:** Logout or proxy reporting no/different Shopify customer must clear stale Rocket session.

### Shopify

- Widget panel: Join → Shopify login URL → return → signed proxy → member home (no LINE/OTP in panel).
- Customer account UI extensions: `shopify-extension-api` + session token (sandbox cannot call app proxy).
- Landing CTAs may open widget, login, or custom URL; member overlay on landing uses cached public page RPC + member state overlay — not a substitute for widget proxy auth.

## Journeys

### Admin journey

| Page | Owning repo | BFF / RPC |
| --- | --- | --- |
| Global settings | loyalty-admin | `bff_get_general_config`, `bff_upsert_general_config` |
| Profile form settings | loyalty-admin | `bff_admin_get_user_profile_config`, `bff_admin_upsert_user_profile_config` |
| Signup codes (per external_code field) | loyalty-admin | `bff_list_signup_codes`, `bff_upload_signup_codes`, `bff_delete_signup_codes`, … |

| Setting | Effect on member signup/login |
| --- | --- |
| `auth_methods` | Which proof channels appear and which `verify_*` steps hub enforces |
| `attain_persona` | When persona is chosen relative to profile (`pre-form` vs post-form — persona metadata in template) |
| Default field cards | Visibility, required, persona scope, id_card mode / uniqueness |
| Validated code fields | External code pools, policies, store binding, manage codes upload |
| Custom field groups | `USER_PROFILE` form sections and conditional fields |

1. **Global settings** → set allowed authentication methods (standalone merchants; hidden on Shopify embedded).
2. **Profile form settings** → configure default fields, validated code pools, custom groups; save via upsert (merge `config` jsonb keys — do not wipe id_card / external_code config).
3. Optional: per validated-code field → **Manage codes** → upload/list/delete codes.
4. Persona catalog and attain timing remain under **Tier / Persona** admin when personas gate fields or signup order.

### Member journey

| Page / surface | Owning repo | BFF / RPC |
| --- | --- | --- |
| Login / signup entry | loyalty-user | `bff_get_auth_config`, `auth-line`, `auth-send-otp` |
| Auth completion | loyalty-user | `bff-auth-complete` |
| Profile completion | loyalty-user | `bff_get_user_profile_template`, `bff_save_user_profile` |
| Edit profile (later) | loyalty-user | Same template RPC with `p_mode = 'edit'` |

1. Load auth config → render LINE button and/or phone + OTP per merchant methods.
2. Complete LINE OAuth (`auth-line`) and/or OTP send + verify inputs.
3. Call `bff-auth-complete` with merchant code and proof payload (and `access_token` when linking a second method).
4. Branch on `next_step`:
   - `verify_line` / `verify_tel` / `verify_shopify` → collect missing proof (session already issued when linking).
   - `complete_profile_*` → bind `missing_data`, walk `form_step` sections, validate required fields per section.
   - `complete` → navigate to member home (`get_user_summary` merged into `user_account` on hub response).
5. On final profile section → `bff_save_user_profile` → home.
6. Optional: enter validated external code during profile → `bff_validate_signup_code` before save; consumption on save.
7. Optional: after `complete`, apply referral member code per `Referral.md` (signup referral path).

| Error / state | Typical cause |
| --- | --- |
| Credentials belong to different accounts | LINE and phone match two users |
| OTP invalid / expired | Wrong code or exhausted attempts |
| Profile save validation | Required field, PDPA, or signup code policy |
| `ID_DOCUMENT_*` | id_card mode / uniqueness from admin config |

### Shopify

| Surface | Identity | Member sees |
| --- | --- | --- |
| Storefront widget (panel open) | App proxy HMAC + `logged_in_customer_id` | Member home when Shopify customer exists |
| Storefront widget (guest) | — | Join → Shopify login → return → proxy → home |
| Customer account extensions | Session token → `shopify-extension-api` | Hub / balance / wishlist (no proxy from extension sandbox) |
| Product page block | None | Earn estimate from widget settings cache only |

**Outside the loyalty-user signup screens:** Shopper creates a Shopify account on theme/checkout → `customers/create` webhook links CRM → opens rewards panel → signed proxy → member home without Join.

| Moment | Proxy call? | Behaviour |
| --- | --- | --- |
| Page load / launcher | No | Launcher label only |
| Panel opens, cached Rocket session | Yes (parallel) | Optimistic UI; reconcile on proxy response |
| Panel opens, no session | Yes | Auto-login or Join |
| Proxy: no customer while cached | — | Clear session → Join |
| Proxy: different customer id | — | Clear and re-auth |

Landing page guest/member CTAs and hub redeem flows are documented under `Display_Settings.md` and reference MD Part 2; identity gateways summarized in **System › Shopify**.

## System

### Data model

| Table | Role |
| --- | --- |
| `merchant_master` | `auth_methods` TEXT[] |
| `user_accounts` | Member row: `tel`, `line_id`, `email`, `persona_id`, `is_signup_form_complete`, `external_user_id` (`shopify:…` when linked), acquisition fields |
| `user_address` | 1:1 address upsert on profile save |
| `user_field_config` | Default signup fields + `external_code` definitions |
| `form_templates` / `form_fields` / `form_field_groups` | Custom profile template (`USER_PROFILE`) |
| `form_submissions` / `form_responses` | Custom field answers |
| `user_consent_ledger` | PDPA accept/withdraw audit |
| `user_communication_preferences` | Topic opt-ins |
| `consent_versions` | PDPA definitions (`notice` / `optional` / `required`) |
| `otp_requests` | OTP sessions (phone, code hash, attempts, expiry) |
| `refresh_tokens` | Member refresh tokens (~30-day TTL) |
| `signup_codes` / `signup_code_claims` | Validated code pools and consumption |
| `shopify_session` / webhook tables | Shopify install context (platform — see `Shopify.md`) |

User creation and profile column updates on the member path go through `chokepoint_post_user_event` (`create` / `update`) from `bff-auth-complete` and related writers.

### Functions

| Name | Role |
| --- | --- |
| `bff_get_auth_config` | Returns enabled `auth_methods` for merchant code |
| `auth-line` | LINE code → profile ids (public edge) |
| `auth-send-otp` | Normalize phone, create OTP session, SMS via 8x8 (edge; registry notes JWT gate — see gaps) |
| `bff-auth-complete` | Hub: match/create user, link methods, profile check, `next_step`, JWT + refresh |
| `bff_get_user_profile_template` | Template + persona filter; params include `p_mode`, `p_language`, `p_merchant_code`, `p_event_code`, `p_selected_persona_id`, `p_audience` |
| `bff_save_user_profile` | Persist profile; sets `is_signup_form_complete` |
| `fn_check_profile_complete` | Server-side completeness helper |
| `mark_signup_form_complete` | Legacy/direct flag set (prefer save path) |
| `fn_validate_otp` | OTP verification |
| `fn_invalidate_user_profile_template_cache` | Bust Redis template cache (~5 min TTL per merchant) |
| `bff_validate_signup_code` / `fn_consume_signup_code` | External code validate/consume |
| `shopify_find_or_create_member` | Shopify customer → member row + acquisition |
| `shopify-proxy` | App proxy HMAC + session mint |
| `shopify-extension-api` | Session-token routes for account UI |
| `shopify_webhook_create_customer` | Early link on Shopify account creation |

Admin: `bff_admin_get_user_profile_config`, `bff_admin_upsert_user_profile_config`, signup code BFFs listed in registry.

### Flows

**Standalone member (LINE + tel configured):**

1. `auth-line` → `bff-auth-complete` with `line_user_id` only → `verify_tel` if user missing phone.
2. `auth-send-otp` → hub with line + tel + OTP → create user if needed → `complete_profile_new` with full `missing_data`.
3. Section navigation (client `form_step`) → `bff_save_user_profile` → `complete` on subsequent hub calls.

**Linking auth method on existing user:** Hub with first method issues JWT; `verify_*` for second method; second hub call with `access_token` links column without duplicate users.

**Profile re-entry:** Merchant adds required field → hub returns `complete_profile_existing` with missing-only `missing_data` when `is_signup_form_complete` is true.

**Shopify widget panel open:** `shopify-proxy` verifies proxy signature → `shopify_find_or_create_member` → `issueMemberSession` → widget APIs with member JWT. Webhook may have created row earlier; proxy still required for session.

**Template cache:** Redis key `merchant:{id}:user_profile_template:all_languages`; persona filtering applied after cache read using member JWT context.

### External services

- LINE Login OAuth (authorization code exchange in `auth-line`).
- 8x8 SMS for OTP delivery from `auth-send-otp`.

### Known gaps

- `auth-send-otp` deploy metadata may show `verify_jwt: true` while member flows treat it as anon-key callable — align deploy config with product intent.
- Per-phone OTP **request** rate limiting not documented as shipped (see `docs/CRITICAL_BUG_FIXES.md`).
- `verify_shopify` / `shopify_email` auth method is for hybrid loyalty-user flows, not the Shopify theme widget path (widget uses proxy identity only).

### Shopify

| Surface | Auth | Gateway |
| --- | --- | --- |
| UI extensions | Shopify session token | `shopify-extension-api` |
| Theme / widget panel | HMAC app proxy + `logged_in_customer_id` | `shopify-proxy` |
| Product block | None | `api_get_widget_settings_cached` |

Member JWT is minted **only** server-side after verified Shopify customer context (proxy or extension). Cross-ref `Authentication.md` (member session issuer) and `Shopify.md` (OAuth, webhooks, extension packaging). Reference MD Part 2 §2.4–2.5 for hub/landing/widget shopper detail.

## Related

- **Authentication.md** — Member vs admin JWT, `issueMemberSession`, refresh tokens, RLS merchant context.
- **Forms.md** — Field types, `USER_PROFILE` template ownership, conditional fields.
- **Referral.md** — Signup referral apply after member exists (`fn_process_referral_signup`).
- **Tag_and_Persona.md** — Persona assignment and field visibility.
- **Shopify.md** — Platform OAuth, billing, webhook receiver, extension layout.
- **Display_Settings.md** — Landing/hub/widget content (identity-free product block vs panel).
