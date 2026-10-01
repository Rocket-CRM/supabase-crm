# Authentication

> Per-domain reference. Read ONLY when working on this domain. For the keyword → file map, see `_index.md`.

**Keywords:** auth, JWT, token, login, LINE, OTP, phone, access token, refresh token, custom JWT, merchant auth, secret, PGRST301

**Source:** `Authentication.md`

**FE-Relevant Sections:**

| Section Heading | Lines | What it contains |
|---|---|---|
| Overview | 7–14 | Dual auth: end-user (LINE + Phone OTP) vs admin (Supabase Auth email/password) |
| End-User Authentication — Architecture | 69–82 | Custom auth flow: LINE/OTP → Edge Functions → custom JWT |
| Authentication Methods Configuration | 85–93 | `merchant_master.auth_methods`: `["line"]`, `["tel"]`, `["line","tel"]` |
| Edge Functions — auth-line | 97–123 | Input/output for LINE OAuth code exchange |
| Edge Functions — auth-send-otp | 126–156 | Phone normalization, OTP settings (6-digit, 10-min, 3 attempts) |
| Edge Functions — bff-auth-complete | 158–233 | Central auth hub: 4 input scenarios, full output shape with `next_step`, `missing`, `missing_data` |
| JWT Structure | 261–275 | Custom JWT claims: `sub`, `merchant_id`, `user_id`, `phone`, `line_id`, `role`, `exp` |
| Token Expiry | 388–406 | Access: 24h, Refresh: 30d, Admin: ~1h (Supabase default) |
| Authentication States | 588–597 | `next_step` values: `verify_line`, `verify_tel`, `complete_profile_new`, `complete_profile_existing`, `complete` |

**Supabase Functions (FE-callable):**

| Function | Parameters | Returns | Lines |
|---|---|---|---|
| `bff_get_auth_config(p_merchant_code)` | `p_merchant_code (text)` | `{ auth_methods: ["line","tel"] }` | (Signup_Login.md 25–41) |
| `auth-line` (Edge Function) | `{ code, merchant_code, redirect_uri }` | `{ line_user_id, display_name, picture_url }` | 97–123 |
| `auth-send-otp` (Edge Function) | `{ phone, merchant_code }` | `{ session_id, expires_in, message }` | 126–156 |
| `bff-auth-complete` (Edge Function) | `{ merchant_code, line_user_id?, tel?, otp_code?, session_id?, access_token?, selected_persona_id? }` | `{ next_step, user, access_token, refresh_token, is_new_user, missing, missing_data }` | 158–233 |
| `bff-profile-lookup` (Edge Function) | Bearer end-user access token | `{ success, user_account }`; `user_account` is backed by `get_user_summary()` and includes `mongo_id` from `user_accounts.mongo_id` | — |
| `superadmin_create_mcp_access_token` | `p_token_hash, p_token_prefix, p_label, p_scopes?, p_allowed_tools?, p_allowed_feature_slugs?, p_expires_at?, p_metadata?` | `{ id, token_prefix, scopes }` | Platform superadmin personal MCP key creation |
| `superadmin_list_my_mcp_access_tokens` | none | `{ tokens }` | Lists current platform superadmin's MCP key metadata |
| `superadmin_revoke_my_mcp_access_token` | `p_token_id uuid` | `{ id }` | Revokes current platform superadmin's MCP key |
| `fn_validate_mcp_access_token` | `p_token_hash text` | `{ valid, owner_admin_user_id, scopes, allowed_tools, allowed_feature_slugs }` | Service-role validation for hosted MCP |
| `admin_manage_invitation` | `p_action, p_email?, p_role_id?, p_token?, p_name?, p_environment?, p_invitation_id?, p_phone?, p_store_ids?` | `{ success, code, title, description?, data? }` | Admin invite create/accept/revoke. Create requires role plus email or phone. Accept matches Supabase Auth email OR normalized phone. |

**Key Business Rules (summary):**
- All custom JWTs signed with Supabase Legacy JWT Secret (HS256)
- End-user JWT includes custom claims: `merchant_id`, `user_id`, `phone`, `line_id`
- `merchant_master.auth_methods` controls which auth methods are required per merchant
- Phone normalization: `0966564526` → `+66966564526`
- `next_step` drives the entire frontend routing after authentication
- `bff-profile-lookup` returns the current member profile summary and exposes `user_account.mongo_id` for migrated users.
- `selected_persona_id` lets signup return persona-scoped custom fields before `user_accounts.persona_id` is saved
- Platform superadmin MCP keys are personal to `admin_users` with `admin_roles.role_code = 'platform_superadmin'`; raw keys are shown once and only SHA-256 hashes are stored in `system_mcp_access_tokens`.
- MCP scopes start with `knowledge:read` and `knowledge:write`; hosted MCP validates bearer tokens through `fn_validate_mcp_access_token`.
- Admin invite identity is email-or-phone. Email invites still send email; phone-only invites return `data.invite_url` with `data.delivery = 'manual_or_sms'` so FE or an SMS path can deliver the accept URL.
- `bff-auth-complete` LINE/tel lookups pick a *useful* row out of legacy duplicates via a five-level ORDER BY on `.maybeSingle()`: `is_signup_form_complete DESC NULLS LAST, persona_id DESC NULLS LAST, updated_at DESC NULLS LAST, created_at ASC, id ASC`. Step 1 prevents a stale incomplete sibling from winning over a finished profile (the "registration form reappears on every login" bug); steps 2–3 disambiguate inside the complete set; steps 4–5 preserve the original deterministic "oldest wins" behaviour for the legacy-only case so JWT `sub` stays stable. Same ordering used for both finders. `line_user_id` is normalized (`''`, `'undefined'`, `'null'`, whitespace → `null`) before any DB read/write to prevent new empty-string `line_id` rows. A future migration will backfill duplicates and add a partial unique index on `(merchant_id, line_id)`.
- `bff_save_user_profile` resolves the calling user via `WHERE id = auth.uid()` (the JWT `sub` is `user_accounts.id`). It does **not** look up by `auth_user_id`, which is `NULL` on ~153k legacy/imported Syngenta rows — joining by `auth_user_id` was the root cause of the "registration form reappears on second login" bug because it created sibling rows instead of updating the canonical row. The function self-heals `auth_user_id` (`COALESCE(auth_user_id, auth.uid())`) on every UPDATE so any other RPC still reading `auth_user_id` converges to the correct value over time.

---
