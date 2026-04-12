# Prompt: Package Builder Component

## Prerequisites: Clean Slate

**Before building anything**, strip this project of any previous component code, patterns, or idiosyncrasies from prior implementations. We are rebuilding this component from scratch using:
- **Polaris Styles NPM Package** — for all design tokens, utility classes, and base styles
- **Polaris Component Structure Guidelines** (`.md` in GitHub) — for component patterns, file structure, and interaction conventions

Do not carry over old styling approaches, ad-hoc CSS, inline styles, or any non-Polaris patterns. Start fresh with Polaris as the foundation.

Study the Polaris style package and structure guide `.md` in GitHub properly and decide the structure and design of the component to be consistent with Polaris style.

## Prerequisites: Backend Initialization

**Before building any UI**, you MUST understand the backend thoroughly:

1. **Init Supabase via MCP** — connect to the Supabase project and inspect the live schema
2. **Study the feature spec carefully** — read `requirements/Package_Contract_Benefit.md` end to end. This document explains the full data model, how packages work, how they integrate with the existing reward system, and all the functions available. Do not skim it.
3. **Inspect the database functions** — use Supabase MCP to pull the full signatures and return shapes of every function you'll call. Do NOT guess parameters or response shapes. Key functions:
   - `bff_upsert_package_with_items` — create/update package with items
   - `bff_admin_get_package_list` — list packages
   - `bff_admin_get_package_detail` — single package with items + reward details
   - `reward_master` table — for pulling available rewards to add as package items
4. **Inspect the tables** — use MCP to check `package_master`, `package_items`, `reward_master` column definitions so you know exactly what fields exist

Think about the best way to structure this component based on what you learn from the schema and the spec. The spec is the source of truth for business logic.

---

## Overview

Build a **Package Builder** admin component — a management interface for creating and configuring packages (bundles of rewards with quantities). A package is a template that defines: a name, description, validity period, optional pricing, and a list of reward items with quantities and mandatory/elective configuration.

This is for use in a WeWeb project, styled using the **Polaris Styles NPM Package** and following **Polaris Component Structure Guidelines**.

---

## Layout: List + Sidebar Config

The component has a **list view** as the main panel and a **sidebar config panel** that opens when creating or editing a package.

### List View (Main Panel)

- Displays all packages for the merchant
- Each row shows: package name, item count, active assignment count, price (if set), points price (if set), status (active/inactive), created date
- **"Create Package"** button at the top — opens the sidebar in create mode
- Clicking a row opens the sidebar in edit mode with that package's data loaded
- Search/filter bar: search by name, filter by status (active/inactive/all)
- Data source: `bff_admin_get_package_list`

### Sidebar Config Panel (Create / Edit)

Opens from the right side when creating or editing. Contains all package configuration:

**Package Details Section:**
- Package name (text input, required)
- Description (textarea)
- Image (image upload or URL input — match existing patterns)
- Validity: either `validity_days` (number input — "Valid for X days from assignment") OR `validity_date` (date picker — "Valid until specific date"). Radio toggle to switch between modes. Both can be null (no expiry).
- Price (number input, nullable — monetary price for purchasable packages)
- Points price (number input, nullable — currency/points cost. Note: this is abstracted as "points" in our platform, NOT "coins")
- Active status (toggle)

**Package Items Section:**
- Table/list of rewards in this package
- Each item row shows: reward name (from reward_master), reward image, quantity, mandatory/elective toggle, elective group name, elective max picks
- **"+ Add Reward"** button — opens a reward picker (dropdown or modal that searches/selects from `reward_master`)
- Each item has: quantity input, mandatory/elective radio, and remove button
- For elective items: elective group name (text) and max picks (number) become visible
- Items are reorderable (drag or up/down arrows) — maps to `ranking` field
- Data shape matches `bff_upsert_package_with_items` p_items parameter

**Action Buttons (bottom of sidebar):**
- **Save as Draft** — saves with `active_status = false`
- **Save & Activate** — saves with `active_status = true`
- Cancel — closes sidebar without saving

**Save behavior:** calls `bff_upsert_package_with_items` with all fields. The function handles create vs update based on whether `p_id` is null or a UUID. Show the response counts (items created/updated/deleted) as a toast notification.

---

## Backend API (Supabase RPC)

All API calls go directly from the component to Supabase. The component should handle its own data fetching and mutations — the WeWeb frontend should only need to bind display things like page header/description, not data logic.

**API Key (anon key):** `eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6IndrZXZtc2VkY2hmdHp0b29sa21pIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NTA1MTM2OTgsImV4cCI6MjA2NjA4OTY5OH0.bd8ELGtX8ACmk_WCxR_tIFljwyHgD3YD4PdBDpD-kSM`

**Authorization:** Bearer `{user_access_token}` — bind as a prop from auth context.

**Base URL:** `https://wkevmsedchftztoolkmi.supabase.co`

### Endpoints

| Action | Endpoint | Method |
|---|---|---|
| List packages | `POST /rest/v1/rpc/bff_admin_get_package_list` | RPC |
| Get package detail | `POST /rest/v1/rpc/bff_admin_get_package_detail` | RPC |
| Create/update package + items | `POST /rest/v1/rpc/bff_upsert_package_with_items` | RPC |
| Get available rewards | `GET /rest/v1/reward_master?select=id,name,image,description_headline&active_status=eq.true` | REST |

> **Important:** Use Supabase MCP to inspect each function's full parameter list and return shape before building. Do not assume — verify.

---

## Key Business Logic to Understand

Read these from the spec (`requirements/Package_Contract_Benefit.md`):

- A package is a **template** — it defines what rewards are bundled. The actual issuance happens when a `package_assignment` is created (by admin, API, persona trigger, etc.)
- `package_items` are children of `package_master`. Each item references a `reward_master` record with a quantity.
- **Mandatory items** are auto-issued on assignment. **Elective items** require user selection after assignment.
- Elective items share an `elective_group` and have a `max_picks` limit within that group.
- The upsert function uses **update-by-ID** pattern: items with `id` are updated, items without `id` are created, items not in the payload are deleted. Preserve IDs when editing.

---

## Styling & Component Gap Tracking

This component depends on two shared packages:
1. **Polaris Styles NPM Package** — shared design tokens, utility classes, and base styles
2. **Polaris Component Structure Guidelines** (`.md` in GitHub) — component patterns, states, and interaction guidelines

### Rules

- **Always use** existing styles/components from Polaris first. Do not reinvent what already exists.
- **When a pattern is needed but not covered**, implement it locally but **log it as a gap**.
- At the end of the build, produce two lists:

#### 1. Polaris Styles NPM Package — Items to Add
#### 2. Polaris Component Structure Guidelines — Items to Add

### Format for Each Gap Entry
```
- **What:** [name/description of the missing pattern]
- **Where used:** [which part of this component uses it]
- **Suggested addition:** [what should be added to the package/guidelines]
```

---

## Deployment

When the component is complete:
1. **Create a new GitHub repository** in the `rocket-crm` organization called `package-builder`
2. **Push all code** to the repo
3. Ensure the repo has a proper `README.md`, `package.json`, and is ready for other developers to clone and run
