# Admin Panel

> Per-domain reference. Read ONLY when working on this domain. For the keyword → file map, see `_index.md`.

**Keywords:** admin_roles, admin_users, admin_role_permissions, admin_menu_config, role, permission, sidebar, menu, floating_menu, default_path, hide_sidebar, role_config, frontline, role_code, admin_invitations, admin_teams, admin_analytics_menu, platform_superadmin, is_platform_admin, superadmin, metabase_dashboard_id

**Source:** `Admin_Panel.md`

**Tables:**

| Table | Purpose |
|---|---|
| `admin_roles` | Role definitions per merchant. Contains `config JSONB` for UI settings (default_path, hide_sidebar, hidden_menu_categories, hidden_menu_items, floating_menu). System roles have `merchant_id = NULL` and `is_system_role = true` (CHECK `system_roles_must_be_global`). |
| `admin_role_permissions` | Per-role resource + actions array (read, create, update, delete, approve) |
| `admin_users` | Admin team members — linked to auth.users, holds role_id, CS profile fields |
| `admin_menu_config` | Sidebar menu item definitions — id, label, href, category, resource, parent_id, display_order |
| `admin_invitations` | Pending admin invitations. Invite identity can be email-only, phone-only, or both; at least one of `email` or normalized `phone` is required. |
| `admin_teams` | CS agent team groupings |
| `admin_analytics_menu` | Global (no merchant_id) list of Metabase dashboard menu items rendered on loyalty-admin `/analytics`. Columns: `label`, `section` (default `'Available dashboards'`), `metabase_dashboard_id text NULL` (NULL/empty → disabled placeholder item), `display_order int`, `active_status`, `created_at`, `updated_at` (trigger). Index on `(active_status, display_order)`. No RLS — access only via SECURITY DEFINER RPCs. |

**Supabase Functions (FE-callable):**

| Function | Type | Parameters | Returns |
|---|---|---|---|
| `bff_get_admin_profile` | BFF | none | Admin user info, merchant info, permissions map, `role_config` (default_path, hide_sidebar, floating_menu) |
| `bff_get_admin_menu` | BFF | none | Sidebar items filtered by role permissions + role_config hidden categories/items; also returns `role_config` |
| `bff_get_admin_role` | BFF | `p_role_id uuid DEFAULT NULL` | NULL → all roles list; with id → single role + permissions + config |
| `bff_upsert_admin_role` | BFF | `p_data jsonb` | Create or update role with permissions + config in one call |
| `bff_update_admin_menu_order` | BFF | `p_data jsonb` | Reorder menu items |
| `get_admin_available_roles` | Backend | `p_merchant_id uuid` | Lightweight role list for dropdowns |
| `get_admin_permissions` | Backend | `p_admin_user_id uuid` | Permission list for a user |
| `is_platform_admin` | Helper | none | Returns `true` when `auth.uid()` maps to an active `admin_users` row whose role is `platform_superadmin`. Returns `false` for unauthenticated or non-superadmin callers (`COALESCE(..., false)`). SECURITY DEFINER, STABLE. Single source of truth for `superadmin_*` RPC auth checks. |
| `assert_platform_admin` | Helper | none | Raises `42501` (`insufficient_privilege`) if `is_platform_admin()` is false. One-line gate at the top of every `superadmin_*` analytics RPC. Each RPC catches `insufficient_privilege` and returns `fn_response_error('Forbidden', ..., 'FORBIDDEN')`. |
| `bff_get_analytics_menu` | BFF | none | Any authenticated admin. Returns `{ items: [{id, label, section, metabase_dashboard_id, display_order}] }` — active rows only, ordered by `display_order`. Replaces the FE `DASHBOARD_MENU` hardcoded list on `/analytics`. |
| `superadmin_list_analytics_menu` | Superadmin | none | Returns all rows (active + inactive) with `created_at` / `updated_at`, ordered by `display_order`. For the superadmin CRUD console. |
| `superadmin_upsert_analytics_menu` | Superadmin | `p_id uuid DEFAULT NULL, p_label text, p_section text DEFAULT 'Available dashboards', p_metabase_dashboard_id text DEFAULT NULL, p_display_order int DEFAULT NULL, p_active_status bool DEFAULT true` | `p_id` NULL → insert (auto-assigns next `display_order` if not provided). `p_id` set → update. Empty/whitespace `p_metabase_dashboard_id` is normalized to NULL (placeholder). Returns the full saved row under `data.item`. |
| `superadmin_delete_analytics_menu` | Superadmin | `p_id uuid` | Hard delete. Returns `NOT_FOUND` if id doesn't exist. |
| `superadmin_reorder_analytics_menu` | Superadmin | `p_items jsonb` — array of `{id, display_order}` | Bulk-updates `display_order`. Returns `{updated, missing}` counts. Non-existent ids are skipped (counted in `missing`), not errored. |
| `admin_manage_invitation` | Admin | `p_action text, p_email text DEFAULT NULL, p_role_id uuid DEFAULT NULL, p_token text DEFAULT NULL, p_name text DEFAULT NULL, p_environment text DEFAULT 'production', p_invitation_id uuid DEFAULT NULL, p_phone text DEFAULT NULL, p_store_ids uuid[] DEFAULT '{}'` | Creates, accepts, or revokes admin invitations. `create` requires `p_role_id` plus email or phone. Phone is normalized through `fn_normalize_thai_phone`. Email invites send email and return `data.delivery = 'email'`; phone-only invites return `data.delivery = 'manual_or_sms'` and `data.invite_url` for FE/SMS/manual delivery. `accept` matches the signed-in Supabase Auth user by email OR normalized phone. |

**Platform Superadmin Role:**

- Reserved system role `admin_roles.role_code = 'platform_superadmin'`, `role_name = 'Platform Superadmin'`, `is_system_role = true`, `merchant_id = NULL` (follows existing system-role convention — no dedicated ops/platform merchant).
- Not granted to any user by the seed migration. Assignment is a manual post-deploy step: set `admin_users.role_id` to this role's id for chosen platform operators (optionally also `admin_users.merchant_id = NULL`).
- `superadmin_*` RPCs gate on `is_platform_admin()` and raise if false. Legacy `superadmin_*` RPCs that still use `auth.role() = 'service_role'` should migrate to this helper as they are touched.
- The five analytics menu RPCs (`superadmin_list/upsert/delete/reorder_analytics_menu` + `bff_get_analytics_menu`) are all granted to `authenticated` and `service_role`. `authenticated` callers who are not platform superadmins get `{success: false, error_code: 'FORBIDDEN'}` from the `superadmin_*` variants.
- `custom_access_token_hook(event jsonb)` (Supabase Auth JWT hook) is NULL-safe w.r.t. `admin_users.merchant_id`. For platform superadmins it emits `merchant_id: null`, `merchant_code: ""`, `is_admin: true`, `is_platform_admin: true` at claims root, `app_metadata`, and `user_metadata`. For regular merchant admins it emits the same shape with `is_platform_admin: false`. The hook uses `||` (jsonb concat) + `jsonb_build_object`, not chained `jsonb_set`, because `jsonb_set` is STRICT and collapses to SQL NULL when any input is NULL — that bug previously surfaced as "Database error querying schema" on login for any admin with NULL merchant_id.

**Key Business Rules:**
- `admin_roles.config` JSONB controls per-role UI: `default_path` (redirect on login), `hide_sidebar` (bool), `hidden_menu_categories` (text[]), `hidden_menu_items` (text[]), `floating_menu` (array of {label, icon, url, page_path})
- `bff_get_admin_menu()` applies `hidden_menu_categories` and `hidden_menu_items` server-side — FE renders what comes back, nothing extra needed
- `bff_get_admin_profile()` returns `role_config` — FE reads this once on login for redirect and floating menu
- Settings category (`admin_menu_config.category = 'settings'`) is never filtered by `hidden_menu_categories` — only `hidden_menu_items` applies there
- Floating menu icons use Iconify format (`mdi:calendar-check`, `mdi:account-plus`, etc.)
- Permissions are stored as `resource` + `actions text[]` pairs; `read` controls sidebar visibility; `create/update/delete/approve` control edit access
- `admin_analytics_menu` is global (not per-merchant). All 21 seed rows share `section = 'Available dashboards'`; rows 1–6 carry Metabase IDs (`176` Users, `177` Purchases, `136` Redemptions, `134` Wallet transactions, `178` Assets, `199` Packages); rows 7–21 have `metabase_dashboard_id = NULL` (rendered as disabled placeholders in the FE until a dashboard is wired).
- Admin invitations can be accepted by a Supabase Auth user whose email matches `admin_invitations.email` or whose normalized Auth phone matches `admin_invitations.phone`. Phone-only invites are now valid backend records; the caller must deliver the returned `invite_url` outside the email path.

---
