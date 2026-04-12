# Prompt: Contract & Persona Entitlement Builder Component

## Prerequisites: Clean Slate

**Before building anything**, strip this project of any previous component code, patterns, or idiosyncrasies from prior implementations. We are rebuilding this component from scratch using:
- **Polaris Styles NPM Package** — for all design tokens, utility classes, and base styles
- **Polaris Component Structure Guidelines** (`.md` in GitHub) — for component patterns, file structure, and interaction conventions

Do not carry over old styling approaches, ad-hoc CSS, inline styles, or any non-Polaris patterns. Start fresh with Polaris as the foundation.

Study the Polaris style package and structure guide `.md` in GitHub properly and decide the structure and design of the component to be consistent with Polaris style.

## Prerequisites: Backend Initialization

**Before building any UI**, you MUST understand the backend thoroughly:

1. **Init Supabase via MCP** — connect to the Supabase project and inspect the live schema
2. **Study the feature spec carefully** — read `requirements/Package_Contract_Benefit.md` end to end. This is critical. It explains:
   - How contracts are metadata on `persona_group_master` (not a separate table)
   - How persona levels (persona_master) sit inside persona groups
   - How `persona_entitlement` is a single unified table defining what each persona level auto-grants (packages, rewards, or benefits) using an `entitlement_type` discriminator
   - How benefits work (standing privileges, never consumed, two validity modes)
   - The full contract flow from setup to user assignment to expiry
3. **Inspect the database functions** — use Supabase MCP to pull the full signatures and return shapes of every function you'll call. Do NOT guess. Key functions:
   - `bff_upsert_contract_with_levels` — the main composite upsert (persona group + levels + entitlements per level in one call)
   - `bff_admin_get_contract_list` — list contracts
   - `bff_admin_get_contract_detail` — single contract with levels and entitlements
   - `bff_admin_get_package_list` — for selecting packages to assign as entitlements
   - `reward_master` table — for selecting rewards to assign as entitlements
4. **Inspect the tables** — use MCP to check `persona_group_master` (with contract columns), `persona_master`, `persona_entitlement`, `package_master`, `reward_master` column definitions

Think about the best way to structure this component based on what you learn. The spec is the source of truth for business logic.

---

## Overview

Build a **Contract & Persona Entitlement Builder** admin component — a management interface for configuring persona groups as contracts, defining persona levels within them, and assigning entitlements (packages, rewards, standing benefits) to each level.

This is a more sophisticated version of persona management. A "contract" is a persona group with added governance (company name, dates, status) and each persona level within it can be configured with entitlements that auto-issue when a user is assigned to that level.

This is for use in a WeWeb project, styled using the **Polaris Styles NPM Package** and following **Polaris Component Structure Guidelines**.

---

## Layout Concept

Think carefully about the best layout for this. Here's the data hierarchy to inform your decision:

```
Persona Group (contract)        ← top level, has contract metadata
  └── Persona Level             ← child, each group has 1-N levels
        └── Entitlements        ← grandchild, each level has 0-N entitlements
              (type: package | reward | benefit)
```

One suggested approach (but think about whether there's a better way):
- **Left panel / list:** All persona groups (contracts) with summary info
- **Main panel:** When a group is selected, shows the group's contract details + its persona levels
- **Each level** is expandable/collapsible, showing its entitlements inside
- Editing happens inline or in a sidebar/modal

The key challenge: this is a 3-level nested structure (group → levels → entitlements). Design the UX so that configuring all three levels feels natural, not deeply nested.

### Workflow States

Contracts should support a workflow:
- **Draft** — being configured, not active
- **Active** — live, users can be assigned
- **Suspended** — temporarily paused
- **Expired** — past contract end date

Buttons: **Save as Draft**, **Submit for Approval** (sets to pending), **Approve** (sets to active). Think about where these fit in the UI.

---

## Contract (Persona Group) Configuration

When creating or editing a contract, the admin configures:

**Contract Details:**
- Group name (text, required)
- Contract type (dropdown: corporate, insurance, vip, partner)
- Company name (text)
- Contact person (text)
- Contact email (text)
- Contract start date (date picker)
- Contract end date (date picker)
- Contract status (display — managed by workflow buttons, not direct edit)
- Active status (toggle)

**Data source:** These are columns on `persona_group_master`.

---

## Persona Levels Configuration

Within each contract, the admin manages persona levels (e.g., "Executive", "General", "Other"):

**Per Level:**
- Persona name (text, required)
- Active status (toggle)
- Member count (display only — how many users are assigned to this level)

**Add/remove levels** within the contract. Existing levels preserve their IDs (update-by-ID pattern — critical for not breaking user assignments).

---

## Entitlements Configuration (Per Level)

This is the most important part. Each persona level has a list of entitlements from the `persona_entitlement` table. Each entitlement has an `entitlement_type` that determines what it grants:

### Type: `package`
- Assigns a package (from `package_master`) that auto-issues when user gets this persona
- Fields: package picker (dropdown/search from `bff_admin_get_package_list`)
- Display: package name, item count

### Type: `reward`
- Directly auto-issues a reward (from `reward_master`) with a quantity — skips package indirection
- Fields: reward picker (dropdown/search from `reward_master`), quantity (number input)
- Display: reward name, qty
- Use case: "Executive gets 5 parking passes" without needing to create a package

### Type: `benefit`
- Defines a standing benefit (non-consumable privilege) that applies while the user has this persona
- Fields: category (text/dropdown — e.g., opd, pharmacy, parking, dental), benefit type (dropdown — discount_percent, discount_fixed, free_access, priority), value (number)
- Display: "25% discount on OPD" / "Free parking access"

**UI for entitlements list:** Each level shows its entitlements as a configurable list. The admin can:
- **Add entitlement** — button that lets them pick the type first, then fill the type-specific fields
- **Edit** existing entitlements inline
- **Remove** entitlements
- **Reorder** entitlements (ranking field)

All entitlements follow update-by-ID pattern: items with `id` are updated, items without `id` are created, items not in the payload are deleted.

---

## Save Behavior

The entire contract (group + levels + entitlements per level) saves in **one atomic call** to `bff_upsert_contract_with_levels`. This is a composite upsert that handles all three levels:

**Payload shape:**
```json
{
  "p_group_id": null,
  "p_group_name": "Company ABC",
  "p_contract_type": "corporate",
  "p_company_name": "ABC Corporation Ltd.",
  "p_contact_person": "Jane Smith",
  "p_contact_email": "jane@abc.com",
  "p_contract_start": "2026-01-01",
  "p_contract_end": "2027-12-31",
  "p_contract_status": "draft",
  "p_active_status": true,
  "p_levels": [
    {
      "persona": { "id": null, "persona_name": "Executive", "active_status": true },
      "entitlements": [
        { "id": null, "entitlement_type": "package", "package_id": "uuid-of-package" },
        { "id": null, "entitlement_type": "reward", "reward_id": "uuid-of-reward", "qty": 5 },
        { "id": null, "entitlement_type": "benefit", "category": "opd", "benefit_type": "discount_percent", "value": 25 }
      ]
    },
    {
      "persona": { "id": null, "persona_name": "General", "active_status": true },
      "entitlements": [
        { "id": null, "entitlement_type": "benefit", "category": "opd", "benefit_type": "discount_percent", "value": 10 }
      ]
    }
  ]
}
```

Note: `p_group_id` null = create, UUID = update. Same for persona `id` and entitlement `id`. The function returns operation counts (levels_created, levels_updated, entitlements_created, etc.).

---

## Backend API (Supabase RPC)

All API calls go directly from the component to Supabase. The component should handle its own data fetching and mutations — the WeWeb frontend should only need to bind display things like page header/description, not data logic.

**API Key (anon key):** `eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6IndrZXZtc2VkY2hmdHp0b29sa21pIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NTA1MTM2OTgsImV4cCI6MjA2NjA4OTY5OH0.bd8ELGtX8ACmk_WCxR_tIFljwyHgD3YD4PdBDpD-kSM`

**Authorization:** Bearer `{user_access_token}` — bind as a prop from auth context.

**Base URL:** `https://wkevmsedchftztoolkmi.supabase.co`

### Endpoints

| Action | Endpoint | Method |
|---|---|---|
| List contracts | `POST /rest/v1/rpc/bff_admin_get_contract_list` | RPC |
| Get contract detail | `POST /rest/v1/rpc/bff_admin_get_contract_detail` | RPC |
| Create/update contract + levels + entitlements | `POST /rest/v1/rpc/bff_upsert_contract_with_levels` | RPC |
| List packages (for entitlement picker) | `POST /rest/v1/rpc/bff_admin_get_package_list` | RPC |
| Get available rewards (for entitlement picker) | `GET /rest/v1/reward_master?select=id,name,image,description_headline&active_status=eq.true` | REST |

> **Important:** Use Supabase MCP to inspect each function's full parameter list and return shape before building. Do not assume — verify.

---

## Key Business Logic to Understand

Read these from the spec (`requirements/Package_Contract_Benefit.md`):

- A **contract is NOT a separate table** — it's metadata columns on `persona_group_master`. The upsert function handles this.
- **Persona levels** are `persona_master` rows with `group_id` pointing to the persona group. Users are assigned to a persona via `user_accounts.persona_id`.
- **`persona_entitlement`** is a single table with 3 types (package, reward, benefit). A CHECK constraint ensures the right fields are set per type. Study the constraint.
- When a user is assigned to a persona level, a trigger fires `fn_auto_assign_on_persona` which reads `persona_entitlement` and auto-creates the relevant records (package assignments, redemption rows, benefit rows).
- **Benefits with source_type='persona'** validate at read time — no expiry dates stored on the benefit. The system JOINs back to check if the persona and contract are still active.
- The upsert uses **update-by-ID** for both levels and entitlements — preserving IDs is critical because users may be assigned to these personas. Deleting and recreating would break assignments.

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
1. **Create a new GitHub repository** in the `rocket-crm` organization called `contract-entitlement-builder`
2. **Push all code** to the repo
3. Ensure the repo has a proper `README.md`, `package.json`, and is ready for other developers to clone and run
