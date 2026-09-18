# Authentication

How the platform proves **who** is calling: merchant staff (admin JWT), loyalty members (member session JWT), and external systems (merchant API keys). All member and admin bearer tokens are Supabase-compatible HS256 JWTs signed with the project **Legacy JWT secret**; API keys are hashed server-side and never sent as JWTs.

Owner surfaces: loyalty-admin, loyalty-user, rewarding-shopify, Supabase Edge (auth + proxy), Open API gateway consumers

## Concept

The CRM runs **three parallel credential models**. They must not be mixed on the same call path (for example, a member JWT does not satisfy admin BFF permission checks, and an API key is not a substitute for a member session on user-facing RPCs).

**Admin credential** — Supabase Auth user in `auth.users`, linked to `admin_users` for merchant, role, and permissions. Daily sign-in is email/password (standalone portal) or Shopify App Bridge session token exchange (`auth-shopify-admin` embedded). Postgres resolves merchant context via `get_current_merchant_id()`; JWT may carry `merchant_id` and permission claims from `custom_access_token_hook`.

**Member session** — Long-lived **access JWT** minted only on the server by shared `issueMemberSession` (30-day `exp`). Issued after LINE/OTP/profile hub (`bff-auth-complete` on loyalty-user), after verified Shopify customer context (`shopify-proxy` / `shopify-extension-api`), or refreshed via `auth-refresh` + `refresh_tokens`. Claims identify `user_accounts` and `merchant_id`; `channel` records how the session was minted (`line`, `tel`, `shopify`). Shopify sessions may include `shopify_customer_id` for burn/metafield paths.

**API key** — Opaque secret per merchant in `merchant_api_keys` (stored hashed). Validated by `validate_api_key`; gateway or edge passes resolved `merchant_id` into `api_*` functions as explicit `p_merchant_id`. Used for server-to-server Open API and integration callers—not for browser member apps.

**JWT secret contract** — Every custom signer (`issueMemberSession`, legacy edge paths) must use the same secret Supabase PostgREST/RPC uses (**Legacy JWT secret** in project settings). Mismatch surfaces as `PGRST301` or signature errors on RPC.

**Superadmin** — Platform operators use `superadmin_*` RPCs across merchants; separate from merchant admin JWT (see `11-auth-conventions`).

Signup screens, `next_step`, and profile completion live in **Signup_Login.md**; this doc owns credential shape, minting gateways, and validation rules.

## Rules

- **Admin BFFs** (`bff_*`, `bff_admin_*`) MUST resolve merchant via `get_current_merchant_id()` (header chain → JWT claims → `admin_users` / `user_accounts` fallback). They MUST NOT accept `p_merchant_id` from the client as authority.
- **Member user RPCs** expect `Authorization: Bearer <member JWT>` (or session validation helpers). Identity is `user_id` / `sub` claim tied to `user_accounts`.
- **Open API** (`api_*`) expects upstream API-key validation and explicit `p_merchant_id`; key validation is `validate_api_key(p_api_key)` → merchant id + metadata.
- Member access JWTs are HS256, `aud: authenticated`, `iss: supabase`, **`exp` ≈ 30 days** from mint (`ACCESS_TOKEN_EXPIRY` in `issueMemberSession`). Refresh tokens in `refresh_tokens` also use a **30-day** TTL when issued from `bff-auth-complete`.
- Admin Supabase Auth access tokens follow Supabase session defaults (~1 hour); refresh via Supabase client. Embedded Shopify admin uses `auth-shopify-admin` to exchange App Bridge token for admin session—not member `issueMemberSession`.
- **OTP** — Plaintext OTP is never returned in API responses; max **3** attempts per `session_id` (`fn_validate_otp` / `otp_requests`). Wrong guesses increment attempts (see `CRITICAL_BUG_FIXES` auth hardening).
- **Bot auth (beta / internal)** — When project env `BOT_SECRET` is set, `bff-auth-complete` accepts matching `bot_secret` and skips OTP proof; issues the same member JWT family as a real user. When unset, `bot_secret` → 403. Never expose `BOT_SECRET` in frontends.
- **RLS / merchant scope** — Policies and helpers use `get_current_merchant_id()` from JWT `merchant_id` and/or `x-merchant-id` / `x-merchant-code` headers where applicable.
- **Shopify storefront** — Theme Liquid `customer.id` / email is **never** sufficient to mint a member JWT. Minting requires HMAC-verified app proxy query params with `logged_in_customer_id`, or a verified Shopify **session token** on `shopify-extension-api`.
- **Shopify proxy auth** — Paths ending in `/auth/signup` or `/auth/login` return 401 if `logged_in_customer_id` is absent; 403 if HMAC invalid; 404 if shop unknown.

### Shopify

- Member JWT on storefront is always server-minted after Shopify customer fetch + `findOrCreateMember`; client stores `token` from proxy JSON only.
- UI extension sandbox cannot call app proxy; extensions use session token → `shopify-extension-api` → same `issueMemberSession` primitive.
- Referral purchase **claim** and **page** on storefront use the same `shopify-proxy` HMAC gate (not member JWT for anonymous claim UI); see **Referral.md**.

## Journeys

### Admin journey

| Page | Owning repo | BFF / RPC / Edge |
| --- | --- | --- |
| Login (standalone) | loyalty-admin | Supabase Auth `signInWithPassword` |
| Login (Shopify embedded) | loyalty-admin | `auth-shopify-admin` (App Bridge session token) |
| API keys (Open API) | loyalty-admin | `bff_list_merchant_api_keys`, `bff_create_merchant_api_key`, `bff_revoke_merchant_api_key` |

| Setting / action | Effect on credentials |
| --- | --- |
| Admin user invite / role | `admin_users` + `admin_roles` / `admin_role_permissions`; JWT enriched on login via hook |
| Active merchant switch (multi-merchant admin) | `admin_set_active_merchant` → `app_metadata.active_merchant_id` in JWT |
| Create API key | New row in `merchant_api_keys`; plaintext shown once at creation |
| Revoke API key | Key invalid immediately for `validate_api_key` |

1. **Standalone** — Admin signs in with email/password → Supabase session JWT → admin BFF calls with `Authorization` + optional `x-merchant-id`.
2. **Shopify embedded** — App Bridge provides session token → `auth-shopify-admin` → Supabase-compatible admin session for iframe portal.
3. **API keys** — Operator creates/lists/revokes keys for integration partners; partners call Open API with key header (gateway validates before `api_*`).

### Member journey

| Surface | Owning repo | Mint path |
| --- | --- | --- |
| LINE / phone signup | loyalty-user | `auth-line`, `auth-send-otp` → `bff-auth-complete` → `issueMemberSession` |
| Session refresh | loyalty-user | `auth-refresh` + `refresh_tokens` / `refresh_session` |
| Shopify widget panel | rewarding-shopify | Signed `shopify-proxy` `/auth/login` or `/auth/signup` |
| Customer account extensions | rewarding-shopify | `shopify-extension-api` (session token) |

1. Load merchant auth methods (`bff_get_auth_config`) on standalone apps.
2. Prove identity (LINE code, OTP, or Shopify customer per surface).
3. Receive `access_token` (+ `refresh_token` on hub paths), store client-side.
4. Send `Authorization: Bearer` on member BFF/RPC and edge calls until expiry; refresh or re-auth per surface rules.
5. Profile and `next_step` routing — **Signup_Login.md**.

### Shopify

| Moment | Gateway | Member credential |
| --- | --- | --- |
| Widget panel open (logged-in Shopify customer) | `shopify-proxy` HMAC + `logged_in_customer_id` | `issueMemberSession` `channel: shopify` |
| Widget Join flow | Shopify login URL → return → proxy auth paths | Same |
| Hub / balance / wishlist (account UI) | `shopify-extension-api` | Session token verified in-handler → mint member JWT server-side only |
| Referral claim page POST | `shopify-proxy` `/referral/claim` | Claim RPCs; not the widget JWT path |
| Product points block | None | Anonymous widget settings cache only |

App proxy is registered in `rewarding-shopify` `shopify.app.toml` → Supabase `shopify-proxy`. Proxy also serves landing storefront paths and referral page HTML/API per **Display_Settings.md** / reference MD Part 2.

## System

### Data model

| Table | Role |
| --- | --- |
| `admin_users` | Links `auth_user_id` → `merchant_id`, role |
| `admin_roles` / `admin_role_permissions` | Permission strings for `check_admin_permission` |
| `user_accounts` | Member record; `tel`, `line_id`, `email`, `auth_user_id`, `external_user_id` (`shopify:…`) |
| `user_sessions` | Extended session records (legacy/custom paths) |
| `refresh_tokens` | Opaque refresh tokens for member `auth-refresh` |
| `otp_requests` | OTP sessions (expiry, attempts) |
| `auth_temp_storage` | Short-lived auth handoff payloads |
| `merchant_api_keys` | Hashed API keys + hint + expiry metadata |
| `merchant_master` | `auth_methods` TEXT[] for enabled member proof channels |
| `shopify_session` / `shopify_auth_nonces` | Shopify admin OAuth / install handoff (platform — **Shopify.md**) |

### Functions

| Name | Role |
| --- | --- |
| `get_current_merchant_id()` | Admin/user merchant resolution for BFF and RLS |
| `custom_access_token_hook` | Enriches admin Supabase JWT (merchant, role, permissions) |
| `check_admin_permission` / `is_current_user_admin` | Admin authorization |
| `validate_api_key` | API key → merchant context |
| `bff_get_auth_config` | Public auth method list per merchant code |
| `fn_validate_otp` | OTP verify with attempt limits |
| `validate_session` / `check_user_session_valid` / `create_extended_session` | Session token helpers |
| `refresh_session` | DB-side refresh helper (paired with edge refresh) |
| `sync_admin_profile_to_auth` / `sync_admin_users_to_auth` | Admin profile ↔ Supabase Auth |

### Flows

**Member mint (standalone)** — Client → `bff-auth-complete` → upsert/link `user_accounts` → `issueMemberSession({ channel: line|tel|shopify })` → insert `refresh_tokens` when applicable → JSON with `access_token`, `expires_in`.

**Member mint (Shopify proxy)** — Shopify theme/widget → signed GET/POST to `shopify-proxy` → verify HMAC → resolve shop → `fetchShopifyCustomer` → `findOrCreateMember` → `mintShopifyMemberSessionToken` (wraps `issueMemberSession` with `shopify_customer_id`) → `{ token }` JSON.

**Member mint (extensions)** — Extension `sessionToken.get()` → `shopify-extension-api` verifies JWT (`aud`, `exp`, `dest`) → resolve merchant + member → `issueMemberSession` for downstream CRM RPCs inside handler (`verify_jwt = false` on edge; auth inside).

**Admin** — Supabase Auth login → optional hook claims → BFF with `get_current_merchant_id()`. Embedded: `auth-shopify-admin` bridges Shopify staff identity to admin session.

**API** — Client presents API key → gateway calls `validate_api_key` → `api_*` with `p_merchant_id`.

**JWT validation** — PostgREST/RPC: project JWT secret. External services (e.g. Render `crm-api`): same Legacy secret, HS256, read `user_id` / `merchant_id` claims.

### External services

| Edge (Render registry) | Role |
| --- | --- |
| `auth-line` | LINE code → profile ids (no JWT) |
| `auth-send-otp` | SMS OTP send |
| `bff-auth-complete` | Member hub + `issueMemberSession` |
| `auth-refresh` | Refresh member access token |
| `auth-logout` | Invalidate member session |
| `auth-register` / `auth-login` / `auth-supabase-only` | Legacy/auxiliary auth paths |
| `auth-shopify-admin` | Embedded admin token exchange |
| `auth-shopify-verify` | Shopify install/verify helpers |
| `shopify-proxy` | Storefront HMAC gateway (auth, landing, referral claim) |
| `shopify-extension-api` | Customer account UI backend |
| `auth-hook-admin-sync` | Admin auth webhook sync |
| `auth-line-login` | **Tombstone** — 410 Gone (retired 2026-05-14) |

### Known gaps

- **`auth-refresh` vs `bff-auth-complete` expiry** — Documented inconsistency: refresh path may issue shorter-lived access tokens than initial `issueMemberSession` (see `docs/CRITICAL_BUG_FIXES.md`); treat as open until aligned.
- **`user_sessions` vs `refresh_tokens`** — Both exist; loyalty-user primary path is JWT + `refresh_tokens` from hub; extended session RPCs remain for older clients.
- **Headless `/store` wishlist** — Supabase JWT path noted in **Shopify.md**; not app proxy.

### Shopify

| Component | Responsibility |
| --- | --- |
| `issueMemberSession` (`_shared/member-session.ts`) | Single member JWT issuer for hub, proxy, extensions |
| `shopify-proxy` | HMAC verification, `/auth/signup`, `/auth/login`, `/referral/page`, `/referral/claim`, landing storefront paths |
| `shopify-extension-api` | Session-token auth, hub/balance/wishlist/redeem routes (representative list in reference MD Part 2 §2.5) |
| `rewarding-shopify` | App proxy URL config; widget calls proxy—not Liquid customer for auth |

Reference narrative (identity gateways, extension route table): `requirements/reference/SHOPIFY_REFERRALS_ONSITE_INTEGRATIONS.md` Part 2 §2.4–2.5. Storefront signup/login **screens** and `next_step`: **Signup_Login.md**.

## Related

- **Signup_Login.md** — Member proof methods, `next_step`, profile template, Shopify widget journey detail.
- **Shopify.md** — Merchant OAuth, webhooks, billing, embedded admin shell, app proxy registration.
- **Open_API.md** — API key usage contracts and `api_*` surface.
- **Referral.md** — Purchase claim via `shopify-proxy` (identity separate from member JWT).
- **Display_Settings.md** — Identity-free product block vs panel auth.
- **`.cursor/rules/11-auth-conventions.mdc`** — Implementation patterns for new BFF/API functions.
