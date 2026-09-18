# Admin Panel — Roles, Permissions & UI Configuration

**Last Updated:** 2026-05-06
**Domain:** Admin Panel
**Covers:** `admin_roles`, `admin_role_permissions`, `admin_users`, `admin_menu_config`, `admin_invitations`, `admin_teams`

---

## Overview

Admin Panel controls who can log into the merchant admin dashboard, what they can see and do, and how the UI is shaped for their role. It is completely separate from the end-user (loyalty member) authentication system.

There are two layers:
- **Access control** — which resources a role can read, create, update, delete, or approve
- **UI config** — per-role settings for default landing page, sidebar visibility, hidden modules, and a custom floating bottom navigation bar

---

## Tables

### `admin_roles`

One row per role per merchant. System roles (`is_system_role = true`) are created by superadmin and cannot be deleted by merchants.

| Column | Type | Notes |
|---|---|---|
| `id` | uuid PK | `gen_random_uuid()` |
| `merchant_id` | uuid | FK to `merchant_master` |
| `role_code` | text NOT NULL | Machine-readable slug, e.g. `frontline_sales` |
| `role_name` | text NOT NULL | Display name, e.g. `Frontline Sales` |
| `is_system_role` | boolean | Default false. System roles cannot be deleted by merchant. |
| `active_status` | boolean | Default true |
| `grant_all_read` | boolean | Default false. When true, role has `read` on every resource without `admin_role_permissions` rows (writes still denied). Same short-circuit idea as `merchant_plan.grant_all_features`. |
| `merchant_assignable` | boolean | Default true. When false, role is hidden from merchant Team/invite pickers and blocked for non-platform invite create. |
| `config` | jsonb | UI layout plus `store_scoped` (see below) |
| `created_at` | timestamptz | |

#### Internal role — `demo_viewer` (Demo Viewer)

Global system role for sales demos (e.g. on `rocket-demo`):

| Field | Value |
|---|---|
| `role_code` | `demo_viewer` |
| `role_name` | `Demo Viewer` |
| `merchant_id` | `NULL` |
| `is_system_role` | `true` |
| `grant_all_read` | `true` |
| `merchant_assignable` | `false` |
| `admin_role_permissions` | empty (intentional — no per-module maintenance) |

Behaviour:

- `check_admin_permission(resource, 'read')` → true; any write/approve action → false
- `bff_get_admin_menu` shows all menu items the merchant **plan** already entitles
- `bff_get_admin_profile` returns `permissions_mode: "all_read"` and `view: true` / `edit: false` for every catalog resource
- Invite only via platform superadmin: `superadmin_invite_admin` / portal `/superadmin/invite-admin` (not merchant Team UI)
- `platform_superadmin` is also `merchant_assignable = false`

#### `config` JSONB shape

```json
{
  "default_path": "/choose-events",
  "hide_sidebar": true,
  "hidden_menu_categories": ["loyalty", "campaigns", "earning_config", "operations", "functional"],
  "hidden_menu_items": ["amp", "forms-surveys"],
  "store_scoped": true,
  "floating_menu": [
    {
      "label": "Choose Events",
      "icon": "mdi:calendar-check",
      "url": null,
      "page_path": "/choose-events"
    },
    {
      "label": "Register Grower",
      "icon": "mdi:account-plus",
      "url": null,
      "page_path": "/grower-registration"
    }
  ]
}
```

| Field | Type | Behaviour |
|---|---|---|
| `default_path` | text \| null | After login, FE redirects here instead of home. Null = normal home. |
| `hide_sidebar` | boolean | `true` = sidebar not rendered; content expands to full width. |
| `hidden_menu_categories` | text[] | Categories to exclude from sidebar. Values: `loyalty`, `campaigns`, `earning_config`, `operations`, `functional`. `settings` is never filterable by category. |
| `hidden_menu_items` | text[] | Specific `admin_menu_config.id` values to exclude regardless of category. |
| `store_scoped` | boolean | Custom-role default `true`. `false` = All stores (Team label + store-gated RPCs unrestricted). Omitted is treated as `true`. `frontline_sales` is always scoped. |
| `floating_menu` | array | Rendered as a fixed bottom bar. Each item: `label` (text), `icon` (Iconify name), `url` (external, optional), `page_path` (internal route, optional). Click prefers `page_path` over `url`. |

#### Menu category values

| `category` | Covers |
|---|---|
| `loyalty` | Rewards, Tiers, Currency, Forms, Integrations, AMP |
| `campaigns` | Missions |
| `earning_config` | Earn Methods (channels, marketplace) |
| `operations` | Receipt upload, activity approval, code activation |
| `functional` | Assets, Stores, Analytics |
| `settings` | Team, Roles, Display, Global settings, Translation — never hidden by category |

---

### `admin_role_permissions`

One row per resource per role. Multiple resources per role.

| Column | Type | Notes |
|---|---|---|
| `id` | uuid PK | |
| `role_id` | uuid NOT NULL | FK to `admin_roles` |
| `resource` | text NOT NULL | Resource code, e.g. `mission`, `reward`, `event` |
| `actions` | text[] | Values: `read`, `create`, `update`, `delete`, `approve` |
| `created_at` | timestamptz | |

`read` in `actions` controls sidebar visibility via `bff_get_admin_menu()`. A menu item is shown only if `read` exists for its resource.

#### Known resource codes

| Resource | Category | What it gates |
|---|---|---|
| `currency` | loyalty | Currency config |
| `reward` | loyalty | Reward list and builder |
| `promo_code` | loyalty | Promo code lots |
| `tier` | loyalty | Tier management |
| `persona` | loyalty | Persona management |
| `earn_channel` | earning_config | Earn channels |
| `earn_marketplace` | earning_config | Marketplace orders |
| `mission` | campaigns | Mission builder |
| `purchase_approval` | operations | Receipt upload approval |
| `activity_approval` | operations | Activity upload approval |
| `earn_code_activate` | operations | Code activation |
| `front_line` | frontline | Front Line page access |
| `frontline_upload_receipt` | frontline | Front Line: Upload Receipt tab |
| `frontline_redemption_reward` | frontline | Front Line: Redemption Reward tab |
| `frontline_burn_points_discount` | frontline | Front Line: Burn Points for Discount tab |
| `frontline_adjust_points` | frontline | Front Line: Adjust Points tab |
| `frontline_claim_mission` | frontline | Front Line: Claim Mission tab |
| `frontline_asset_group` | frontline | Front Line: Asset Group tab |
| `display` | settings | Display settings |
| `global_setting` | settings | Global settings |
| `store` | functional | Store master |
| `store_attribute` | functional | Store attributes |
| `asset` | functional | Assets |
| `analytics` | functional | Reports & Customer 360 |
| `role` | settings | Role management |
| `team` | settings | Team management |
| `invite` | settings | Invitations |
| `event` | — | Event features (Syngenta) |
| `grower_registration` | — | Grower registration (Syngenta) |
| `rice_survey` | — | Rice survey (Syngenta) |

---

### `admin_users`

One row per admin team member per merchant.

| Column | Type | Notes |
|---|---|---|
| `id` | uuid PK | |
| `auth_user_id` | uuid | FK to `auth.users` (Supabase Auth) |
| `merchant_id` | uuid | |
| `email` | text | |
| `name` | text | |
| `phone` | text | |
| `role_id` | uuid NOT NULL | FK to `admin_roles` |
| `active_status` | boolean | |
| `invited_by` | uuid | Admin user who sent invitation |
| `invited_at` | timestamptz | |
| `accepted_at` | timestamptz | |
| `shopify_user_id` | text | For Shopify-integrated merchants |
| `cs_online_status` | text | CS agent online/offline/busy |
| `cs_max_concurrent` | integer | Max simultaneous CS conversations |
| `cs_skills` | jsonb | CS routing skills |
| `created_at`, `updated_at` | timestamptz | |

---

### `admin_menu_config`

Static (superadmin-managed) table of all possible sidebar entries. Merchants do not add rows here; they control visibility through `admin_role_permissions` and `admin_roles.config`.

| Column | Type | Notes |
|---|---|---|
| `id` | text PK | Slug, e.g. `rewards`, `amp`, `campaigns` |
| `label` | text | Display label |
| `href` | text | Route path (null for parent-only grouping nodes) |
| `image` | text | Icon URL (inactive) |
| `active_image` | text | Icon URL (active state) |
| `badge` | text | Optional badge text |
| `category` | text | One of the category values above |
| `resource` | text | Matched against `admin_role_permissions.resource` |
| `parent_id` | text | Self-reference; null = top-level parent |
| `display_order` | integer | Sort order within parent |
| `active_status` | boolean | Soft-disable without deleting |
| `created_at` | timestamptz | |

---

## Functions

### `bff_get_admin_profile()` → jsonb

Returns the logged-in admin's profile. Called on login and cached by the FE.

Permission resources are sourced from `fn_admin_role_resource_catalog()`, including the `frontline` category and its tab-level resources.

**Response shape:**
```json
{
  "success": true,
  "merchant": { "merchant_id", "merchant_code", "merchant_name" },
  "admin": {
    "id", "auth_user_id", "email", "name", "phone",
    "role_id", "role_code", "role_name", "is_system_role",
    "grant_all_read",
    "active_status",
    "role_config": { "default_path", "hide_sidebar", "hidden_menu_categories", "hidden_menu_items", "floating_menu" }
  },
  "permissions": {
    "<category>": {
      "<resource_code>": { "view": bool, "edit": bool, "display_name": text }
    }
  },
  "permissions_mode": "explicit | all_read"
}
```

When `grant_all_read` is true, every catalog resource is `view: true` / `edit: false` and `permissions_mode` is `"all_read"`.

---

### `bff_get_admin_menu()` → jsonb

Returns sidebar structure filtered by:
1. `admin_role_permissions` — only resources with `read` action are shown (or `grant_all_read` short-circuit)
2. Merchant plan feature entitlement (`fn_merchant_feature_resolve` / plan `grant_all_features`)
3. `admin_roles.config.hidden_menu_categories` — whole categories excluded
4. `admin_roles.config.hidden_menu_items` — specific items excluded by id

Also returns `role_config` so FE can use it without a separate profile call.

---

### `superadmin_invite_admin(p_merchant_code, p_email, p_role_code default 'demo_viewer', p_name, p_environment)` → jsonb

Platform-superadmin-only invite. Creates `admin_invitations` for any active global system role (including non-`merchant_assignable` roles such as `demo_viewer`), emails the accept link, and returns `invite_url`. Portal UI: `/superadmin/invite-admin`.

---

### `fn_admin_role_resource_catalog()` → table

Central catalog for role-builder resources and profile permission output.

Columns: `resource_code`, `display_name`, `category`.

Includes:
- Existing loyalty, operations, settings, functional, admin, analytics, and event resources
- `frontline` category resources: `front_line`, `frontline_upload_receipt`, `frontline_redemption_reward`, `frontline_burn_points_discount`, `frontline_adjust_points`, `frontline_claim_mission`, `frontline_asset_group`

---

### Default `frontline` system role

Global system role:
- `role_code`: `frontline`
- `role_name`: `Frontline`
- `merchant_id`: `NULL`
- `is_system_role`: `true`
- `config.default_path`: `/front-line`
- `config.hide_sidebar`: `true`

Permissions:
- `front_line`: `read`
- Front Line tab resources: `read`, `create`, `update`

This role is intended for staff who should only enter the Front Line page. FE route guards must enforce tab visibility using the tab-level permissions.

---

### `bff_upsert_admin_role(p_data jsonb)` → jsonb

Create or update a role. `p_data.id = null` → insert. `p_data.id = <uuid>` → update.

**Input shape:**
```json
{
  "id": null,
  "role_code": "frontline_sales",
  "role_name": "Frontline Sales",
  "active_status": true,
  "permissions": [
    { "resource": "event", "actions": ["read", "create", "update"] }
  ],
  "config": {
    "default_path": "/choose-events",
    "hide_sidebar": true,
    "hidden_menu_categories": ["loyalty", "campaigns", "earning_config", "operations", "functional"],
    "hidden_menu_items": [],
    "floating_menu": [...]
  }
}
```

If `permissions` key is present, all existing permissions for the role are deleted and re-inserted (clean replace). If absent, permissions are untouched.

---

### `bff_get_admin_role(p_role_id uuid DEFAULT NULL)` → jsonb

- `NULL` → returns all roles for merchant with permissions + config (for role list page)
- `<uuid>` → returns single role detail for role editor form

---

## Business Rules

1. A user's sidebar is the intersection of: `admin_role_permissions` (resource access) AND NOT `hidden_menu_categories/hidden_menu_items` (role config exclusions). Both filters apply server-side in `bff_get_admin_menu()`.
2. `settings` category is never hidden by `hidden_menu_categories` — it is admin infrastructure. Individual settings items can still be hidden via `hidden_menu_items`.
3. `default_path` redirect fires once per login session. FE must guard against repeated redirects (sessionStorage flag or auth store flag).
4. Floating menu appears only when `floating_menu` array is non-empty. It overlays at the bottom regardless of sidebar state. When present and sidebar is visible, FE must add bottom padding to prevent content being obscured.
5. `hide_sidebar = true` removes the sidebar entirely — content expands to full width. Used for frontline roles that only need the floating menu.

---

## Known Role — Frontline Sales (Syngenta)

| Field | Value |
|---|---|
| `role_id` | `0a798e28-d0b7-4b09-8f8c-322c713ea89c` |
| `merchant_id` | `8f67aa08-dfce-454d-bfb1-effc4ee45f1f` (Syngenta) |
| `role_code` | `frontline_sales` |
| `default_path` | `/choose-events` |
| `hide_sidebar` | `true` |
| `hidden_menu_categories` | loyalty, campaigns, earning_config, operations, functional |
| Permissions | `event`, `grower_registration`, `rice_survey` — all with `[read, create, update]` |
| Floating menu | Choose Events (`mdi:calendar-check`), Register Grower (`mdi:account-plus`), Rice Survey (`mdi:clipboard-list`) |

## Loyalty homepage setup mastery

### `bff_get_loyalty_setup_mastery(p_language text DEFAULT NULL)` → jsonb

Admin homepage checklist. Merchant from JWT via `get_current_merchant_id()`. Read-only. Same payload for Shopify and non-Shopify.

**Language:** optional `p_language` (`en`|`th`). If null, merchant default from `merchant_languages.is_default`, else `en`. Display strings come from `fn_loyalty_setup_mastery_text` — FE must render `title` / `description` / `action_label` / `progress_label` / `priority_label`, not raw `code`.

**Steps (order):**
1. `earn_rules` — 0 sub-steps. Complete when an active points `rate` earn factor exists.
2. `rewards` — 0 sub-steps. Complete when ≥1 active `visibility=user` reward has points cost.
3. `tiers` — 2 sub-steps (`tiers.program_config`, `tiers.ladder`). Recommended; does **not** block launch.

**Response `data`:** `language`, `title`, `subtitle`, `progress_label`, `steps_total` (3), `steps_completed`, `progress_pct`, `is_launch_ready` (earn+rewards), `steps[]` (`code`, localized `title`/`description`, `status`, `action`, localized `action_label`, `action_path`, `sub_steps[]` with localized `title`/`description`/`priority_label`).

**Deep-links (suggested):** `/earn-rules`, `/rewards`, `/tiers`.

