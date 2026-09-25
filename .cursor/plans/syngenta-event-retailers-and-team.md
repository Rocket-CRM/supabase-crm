# Syngenta Events — Participating Retailers + Team Invites

**Status:** Shipped 2026-05-14. Decisions locked: (1) generic naming `event_store_allowlist`, (2) owner-only management, (3) no BE transaction block — allowlist is FE-binding metadata only, (4) invite restricted to existing admin users via search picker. Final shape differs from original draft: `store_participation_mode` column was dropped — `is_scoped` is derived from `len(allowlist) > 0` and returned in `bff_list_event_stores`.

Final landed surface (registry-updated):

- Table: `event_store_allowlist (id, merchant_id, event_id, store_id, added_by_admin_user_id, created_at)`, UNIQUE `(event_id, store_id)`.
- Helper: `fn_event_caller_role(p_event_id uuid) -> text` returning `owner | coordinator | superadmin | none`.
- Retailer BFFs: `bff_list_event_stores`, `bff_search_admin_stores` (owner-only), `bff_upsert_event_stores` (owner-only).
- Team BFFs: `bff_list_event_team`, `bff_search_admin_users_for_event` (owner-only), `bff_invite_event_coordinator(p_event_id, p_admin_user_ids uuid[])` (owner-only, multi-add), `bff_remove_event_coordinator(p_event_id, p_admin_user_id)` (owner-only).
- Behavior change: `bff_list_event_products`, `bff_upsert_event_products`, `bff_list_event_orders` are now gated to `owner | coordinator | superadmin` only (previously: any merchant admin / `event:update`).

**Source request (Teerakarn / Deuce):**

1. **ร้านค้าที่เข้าร่วม (Participating Retailers)** — Salesperson can pin specific retailers to each event. Reason: hundreds of stores exist; they want to limit the retailer allowlist per event.
2. **ทีมงาน (Team)** — Reuse the existing event coordinator mechanic so the owner (salesperson) can invite other salespeople to help set up products and handle orders.

---

## Current state (verified live, not just registry)

### Event entity — `syngenta_events_master`

- Identity: `id` (uuid), `event_code` (text), `merchant_id`, `event_name`, `date_of_event`.
- **Owner** — `owner_name text`, `owner_email text[]` (array, case-insensitive match).
- **Coordinator** — `coordinator_name text`, `coordinator_email text[]` (array, case-insensitive match).
- Lifecycle: `opened`, `opened_at`, `closed_at`, `open_by`, `close_by`, `location_open jsonb`, `location_close jsonb`.
- Org / classification: `bu`, `sub_bu`, `activity_group`, `star_product`, `strategic_market`, geography (`province_id`, `district_id`, `subdistrict_id`).
- Linked form: `form_id → form_templates(id)`.

### Event coordinator mechanic — `admin_get_my_events(p_include_all bool)`

- Resolves caller via `auth.uid() → admin_users.email` scoped to current merchant.
- Filters: `LOWER(admin_email) = ANY(LOWER(owner_email))` OR `... coordinator_email`.
- Returns `my_role ∈ {owner, coordinator, both, none}`.
- This is exactly the "existing mechanic" the request refers to. Membership is **email-based**, not FK-based.

### Event products — `event_product_config`

- Cols: `id, merchant_id, event_id, sku_id?, sku_code, product_name, variant_name, price?, is_active, sort_order`.
- BFFs: `bff_list_event_products(p_event_id)`, `bff_upsert_event_products(p_event_id, p_products jsonb)`.
- **Auth gap:** upsert only checks `check_admin_permission('event','update')` + merchant scope. It does **not** verify the caller is the owner/coordinator of that specific event. Same gap on `bff_list_event_products` and `bff_list_event_orders`.

### Event orders — `bff_list_event_orders`

- Pulls `purchase_ledger` rows where `transaction_source_id = p_event_id`. So a transaction's `seller_id` (admin user) and `transaction_source_id` (the event) are the join points; there is **no** `store_id` filter on event orders today.

### Stores — `store_master` (and friends `store_attribute_*`, `admin_user_store_assignments`, `admin_invitation_store_assignments`)

- The standard retailer entity. No existing link to events.

---

## Feature 1 — Participating retailers (allowlist per event)

### Data model (proposed — needs approval)

New child table `event_store_allowlist`:

| Column | Type | Notes |
|---|---|---|
| `id` | uuid pk | `gen_random_uuid()` |
| `merchant_id` | uuid not null | scope |
| `event_id` | uuid not null | FK → `syngenta_events_master(id)` ON DELETE CASCADE |
| `store_id` | uuid not null | FK → `store_master(id)` |
| `added_by_admin_user_id` | uuid | FK → `admin_users(id)` (audit) |
| `created_at` | timestamptz default now() | |
| | | UNIQUE `(event_id, store_id)`, INDEX `(merchant_id, event_id)`, INDEX `(store_id)` |

Add to `syngenta_events_master`:

| Column | Type | Notes |
|---|---|---|
| `store_participation_mode` | text not null default `'all'` | enum-via-CHECK: `'all'` (no restriction) \| `'allowlist'` (only stores in `event_store_allowlist`) |

Rationale for the mode flag: an empty `event_store_allowlist` cannot mean "no stores allowed" (that breaks every existing event). Mode `'all'` is the safe default for backfill; `'allowlist'` is opt-in per event.

> Generic vs. Syngenta-specific: I'm using the prefix `event_*` (not `syngenta_event_*`) because (a) the existing `event_product_config` already uses that generic naming and (b) `store_master` is generic. Per `07-abstraction-principles.mdc`, prefer the generic shape. Confirm before applying.

### BFFs (new)

| Function | Purpose |
|---|---|
| `bff_list_event_stores(p_event_id uuid)` | Returns the participating store list joined to `store_master` (id, code, name, address summary, attribute summary). Includes `mode` and `total`. |
| `bff_search_eligible_stores(p_event_id uuid, p_query text, p_limit int, p_offset int)` | Browses `store_master` filtered to merchant. For each row return `is_added bool` so the FE can render "Add" vs "Remove". Supports name/code search. |
| `bff_upsert_event_stores(p_event_id uuid, p_store_ids uuid[], p_mode text)` | Sets the full allowlist (delta INSERT/DELETE) and updates `store_participation_mode`. Returns `{added, removed, mode, total}`. |

### Enforcement (downstream — confirm before adding)

When a transaction is created against an event, if `store_participation_mode = 'allowlist'`, verify the transaction's store is in `event_store_allowlist`. Need to find the transaction-creation entry point (likely an `api_*` purchase RPC) and add the check. **Do not add this in the same change** — propose as a follow-up so we can identify all writers and confirm UX (hard-block vs. warn).

### Auth (proposed)

- Manage allowlist (`bff_upsert_event_stores`): only the **event owner** (or superadmin). Coordinators can view but not edit, unless we explicitly elevate (open question).
- Read allowlist (`bff_list_event_stores`, `bff_search_eligible_stores`): owner + coordinators + superadmin.

---

## Feature 2 — Team invites (multi-coordinator)

The user said "use the existing event coordinator mechanic", so the default path is to keep the `coordinator_email text[]` model and add management RPCs around it. Two options:

### Option A — Email-array (recommended; minimal lift)

- Keep `coordinator_email text[]`.
- New BFFs:
  - `bff_invite_event_coordinator(p_event_id uuid, p_email text)` — owner-only. Lower-cases and de-dups against the array. Adds whether or not the email maps to an existing `admin_users` row (lazy resolution; once they sign up, `admin_get_my_events` will surface).
  - `bff_remove_event_coordinator(p_event_id uuid, p_email text)` — owner can remove anyone; coordinator can remove only themselves.
  - `bff_list_event_team(p_event_id uuid)` — returns owner block + array of coordinators with `{ email, admin_user_id?, fullname?, avatar?, joined_at? }`. `joined_at` is best-effort (we don't track per-entry timestamps in an array; can be NULL until we move to Option B).
- Auth gating fixes (apply alongside):
  - `bff_upsert_event_products` — add: caller must be owner OR coordinator of `p_event_id` (or superadmin).
  - `bff_list_event_products` — same restriction (or stay open if FE needs it for browsing — confirm).
  - `bff_list_event_orders` — same restriction.
- Trade-offs: no per-membership audit (when joined / who invited / status). Acceptable for MVP, matches existing mechanic.

### Option B — Link table (future hardening — flagged, not in MVP)

- New `event_team_member(event_id, admin_user_id, role enum('owner','coordinator'), invited_by, invited_at, status enum('pending','active','removed'))`.
- Migrate existing `owner_email[]` / `coordinator_email[]` → rows (best-effort match by email; unmatched stays in legacy column).
- Update `admin_get_my_events` to read from the link table first, fall back to legacy columns during transition.
- Larger blast radius — propose only after Option A ships and we have data on real usage.

### Notifications (out of scope for first cut)

Email-on-invite is a clean follow-up. Mention it but do not bundle.

---

## Cross-feature concerns

1. **Event ownership transitions.** If an owner is removed from `owner_email[]` and not replaced, the event becomes orphaned (no one can manage it except superadmin). Add a guard in any "remove owner" path: at least one owner email must remain. Today nothing edits `owner_email[]` via a BFF — confirm the FE does this through a generic event upsert before adding a guard there.
2. **Permission helper.** Add a private `fn_event_caller_role(p_event_id uuid) returns text` (`owner` / `coordinator` / `none`) so the new auth checks across product/order/team/allowlist BFFs share one source of truth instead of repeating the array-unnest.
3. **Registry + docs.** New tables, columns, and BFFs require updates to `requirements/REGISTRY_SUPABASE.md` + the relevant Syngenta domain doc + `requirements/CHANGELOG.md` (per `06-update-docs.mdc`).
4. **CRM Knowledge MCP.** No write needed for the plan; once shipped, add an `overview` + `rules` block under the Syngenta event feature so the new mechanics are queryable.

---

## Open questions (need answers before applying)

1. **Generic vs. Syngenta-prefixed tables** — `event_store_allowlist` (generic, matches `event_product_config`) or `syngenta_event_store_allowlist` (consistent with `syngenta_events_master`)? Recommend generic.
2. **Coordinator edit rights** — can coordinators add/remove participating retailers, or owner-only? Today coordinators can fully edit products (assuming the auth-gating fix); should retailers behave the same?
3. **Transaction-time enforcement of allowlist** — should we hard-block a purchase against an event when the store isn't on the allowlist, or just warn / log? Need to know the transaction-creation path before specifying.
4. **Lazy invite vs. existing-admin-only** — should `bff_invite_event_coordinator` accept any email (lazy: admin signs up later → auto-surfaces) or only emails that already exist in `admin_users` for this merchant? Lazy is simpler; existing-only catches typos.
5. **Owner-as-array or single owner** — `owner_email` is an array. Do we treat the first entry as canonical, or any element as equally authoritative? Affects "remove owner" guard.

---

## Approval checklist (do **not** apply until ticked)

- [ ] Approve Option A for Team Invites (vs. defer for Option B).
- [ ] Approve generic naming `event_store_allowlist` (vs. `syngenta_*`).
- [ ] Approve adding `store_participation_mode` to `syngenta_events_master`.
- [ ] Confirm coordinator edit rights for retailers (Q2).
- [ ] Confirm enforcement scope for transaction-time allowlist check (Q3) — or split into a follow-up plan.
- [ ] Confirm lazy invite (Q4).
- [ ] Confirm at least one BFF caller for `owner_email[]` writes so the "last-owner" guard has a home (Q1/Q5).

Once ticked, the apply order is:

1. Schema (single migration: new table + new column + indexes + CHECK).
2. Helper `fn_event_caller_role`.
3. Retailer BFFs (`bff_list_event_stores`, `bff_search_eligible_stores`, `bff_upsert_event_stores`).
4. Team BFFs (`bff_invite_event_coordinator`, `bff_remove_event_coordinator`, `bff_list_event_team`).
5. Auth-gating fixes on `bff_upsert_event_products` / `bff_list_event_products` / `bff_list_event_orders`.
6. Registry + Syngenta domain doc + CHANGELOG.
