# Package

Bundle template that grants one or more rewards with quantities; assignments materialize **multi-use entitlements** in the standard redemption ledger (`qty` / `used_qty`) instead of single-shot coupons.

Owner surfaces: loyalty-admin, loyalty-user (my packages / elective picks), Open API (`api_assign_package`, `api_use_entitlement`)

## Concept

**Packages (shelved — demo-built, not launched)** — When launched, merchants would sell or grant bundled reward balances (mandatory items plus optional elective picks) that members consume use-by-use until qty or expiry. Backend and demo admin/member UI exist; the capability is not general-availability product. Portfolio status: [Shelved_Demo_Features.md](./Shelved_Demo_Features.md).

**Package template** — Catalog row plus items (mandatory vs elective groups).

**Assignment** — User receives a package with source attribution (admin, API, persona, mission, tier, …).

**Entitlement** — Ledger row with remaining uses and expiry derived from package validity rules.

**Elective pick** — Member chooses among optional items up to `elective_max_picks` per group after assignment.

Persona auto-grant: `Persona_Entitlement.md`. Legacy combined spec: `Package_Contract_Benefit.md`.

## Rules

- Inactive packages cannot be assigned (`api_assign_package` rejects).
- Mandatory items materialize at assignment; electives only after `select_elective_items`.
- Use consumes one unit via `api_use_entitlement` / `fn_use_entitlement` — not `api_mark_redemption_used` for multi-use rows.
- Validity precedence at materialization: `validity_days` → `validity_date` → `assignment.effective_to` → none.
- Admin adjust cannot set total qty below `used_qty`.
- `fn_expire_package_entitlements` exists but has **no cron** — expiry enforcement is manual/ops until scheduled.
- **Launch gate:** Not on default platform/Shopify nav; exposed via admin menu (`package-builder`) and member wallet Packages tab for configured demos only.

## Journeys

### Admin journey

| Knob | Effect |
| --- | --- |
| Package items | Rewards, qty, mandatory/elective groups |
| Validity days/date | Entitlement `use_expire_date` |
| Assign batch | Creates assignment + mandatory entitlements |

| Page | Owning repo | BFF / RPC |
| --- | --- | --- |
| Package catalog | loyalty-admin | `bff_upsert_package_with_items`, `bff_admin_get_package_*` |
| Assign to users | loyalty-admin | `bff_admin_assign_package` |
| User entitlements | loyalty-admin | `bff_admin_get_user_packages`, `bff_admin_adjust_entitlement` |

1. Define package and items.
2. Assign to members (or rely on API/persona sources).
3. Adjust totals or inspect remaining balances on support flows.

Demo-only: Package Builder lives under Marketing module sidebar (`/package-builder`); not part of standard merchant onboarding.

### Member journey

1. Open my packages (`get_user_packages`).
2. If electives exist, call `select_elective_items` within group limits.
3. Consume uses at POS/app via entitlement use API until `used_qty = qty` or expiry.

## System

Tables: `package_master`, `package_items`, `package_assignment`; runtime on `reward_redemptions_ledger` with `source_type = package_assignment`. Helpers: `fn_create_package_entitlements`, `fn_use_entitlement`, elective/member/admin BFFs in technical reference.

### Known gaps (launch checklist)

| Area | Gap |
| --- | --- |
| Ops | Schedule `fn_expire_package_entitlements` (no Render/`cron.job` entry today) |
| Product | GA plan entitlements, default nav, and merchant comms — treat as demo until explicitly launched |
| Persona | Auto-assign on persona change not wired — see [Persona_Entitlement.md](./Persona_Entitlement.md) |
| Open API | `api_assign_package` in CRM; `api_use_entitlement` not on public gateway — [Open_API.md](./Open_API.md) |
| FE / POS | Coupon views must show remaining uses; `api_mark_redemption_used` rejects multi-use rows |
| Support | No whole-assignment cancel — per-entitlement adjust only; `package_assignment.status` underused |

## Related

- **[Shelved_Demo_Features.md](./Shelved_Demo_Features.md)** — Launch status index.
- **Reward.md** — Underlying rewards and visibility rules.
- **Persona_Entitlement.md** — Auto-assign packages on persona.
- **Currency.md** — Package grants do not deduct points (`points_deducted = 0`).
- **Package_Contract_Benefit.md** — Retired combined spec; pointer only.

---

# Package — technical reference

## 1. Concept

| Concept | Definition |
|---|---|
| Package (template) | A merchant-defined SKU bundle: name, image, price, points price, validity, plus a list of items |
| Package item | One reward inside the package, with a `qty` and a mandatory/elective flag |
| Package assignment | A specific user receiving a specific package, with effective dates and a source attribution |
| Entitlement (runtime) | A `reward_redemptions_ledger` row created from a package item, tracking total grant (`qty`) and used count (`used_qty`) |

A package is **not** consumed; the entitlements created from it are. A user can hold multiple assignments of the same package.

## 2. Schema

### `package_master` — catalog
| Column | Type | Notes |
|---|---|---|
| `id` | uuid | PK |
| `merchant_id` | uuid | tenant scope |
| `name`, `description`, `image[]` | text | display |
| `validity_days` | int | rolling: entitlements expire `effective_from + N days` |
| `validity_date` | timestamptz | fixed: all entitlements expire on this date (overridden by `validity_days` if both set; precedence in `fn_create_package_entitlements` is days first) |
| `price`, `points_price` | numeric | optional |
| `active_status` | bool | inactive packages are hidden from list and rejected by `api_assign_package` |

### `package_items` — bundle contents
| Column | Notes |
|---|---|
| `package_id` | parent package |
| `reward_id` | which reward is granted |
| `qty` | grant quantity per assignment |
| `is_mandatory` | auto-materialized on assignment |
| `is_elective` | requires explicit member selection via `select_elective_items` |
| `elective_group` | groups electives for max-pick enforcement |
| `elective_max_picks` | max picks allowed within the group |
| `ranking` | display order |

### `package_assignment` — user grant
| Column | Notes |
|---|---|
| `user_id` | recipient |
| `package_id` | which package |
| `source_type` | text — admin / api / persona_assignment / purchase / mission / tier_upgrade / campaign / his_event |
| `source_id` | optional FK to the originating record |
| `effective_from` | when the entitlements start (defaults to `now()`) |
| `effective_to` | optional override expiry |
| `status` | text (active is the only value used by current BFFs) |
| `assigned_by` | text — admin / api / system |

### Runtime store: `reward_redemptions_ledger`
Package entitlements share the standard reward redemption table. Distinguishing fields:
- `source_type = 'package_assignment'` (enum value `wallet_transaction_source_type.package_assignment`)
- `package_assignment_id` set
- `qty` = total grant, `used_qty` = consumed (defaults 0)
- `points_deducted` = 0 (free from package)
- `use_expire_date` set from package validity at materialization time
- `points_calculation` JSONB carries `{mode: 'package_entitlement' | 'elective_selection', package_id, package_item_id}`

Audit trail lives in `redemption_usage_log` (action ∈ `use` / `reverse` / `adjust` / `expire`).

## 3. Function inventory

### Admin BFF (merchant JWT, admin role check)
| Function | Purpose |
|---|---|
| `bff_admin_get_package_list(p_status, p_search)` | List packages with `item_count` and `active_assignments` |
| `bff_admin_get_package_detail(p_package_id)` | Package with items and reward names/images |
| `bff_upsert_package_with_items(p_id, p_name, ..., p_items)` | Create / update package + items in one call (update-by-ID, deletes items not in keep list) |
| `bff_admin_assign_package(p_assignments)` | Batch assign one package to many users (jsonb: `{package_id, source_type, assignments:[{user_id, effective_from, effective_to}]}`) |
| `bff_admin_get_user_packages(p_user_id)` | Inspect a user's assignments + nested entitlements with remaining quantities |
| `bff_admin_adjust_entitlement(p_redemption_id, p_qty_change, p_reason)` | Adjust a single entitlement's total qty (cannot reduce below `used_qty`) |

### Member-facing
| Function | Purpose |
|---|---|
| `get_user_packages(p_status, p_language)` | `auth.uid()`-scoped list with package name + entitlements (uses `translations` for localized names) |
| `select_elective_items(p_assignment_id, p_selected_reward_ids)` | Member picks elective items from their assignment; idempotent; enforces `elective_max_picks` per `elective_group` |

### External API (service_role or merchant JWT)
| Function | Purpose |
|---|---|
| `api_assign_package(p_user_id, p_package_id, p_source_type, p_source_id, p_merchant_id)` | Creates an assignment + materializes entitlements; rejects inactive packages and unknown users |
| `api_use_entitlement(p_redemption_id, p_user_id, p_store_id, p_external_ref, p_merchant_id)` | Decrement one use from a tracked entitlement; rejects standard redemptions, cancelled, expired, or zero-remaining records |

### Internal helpers
| Function | Purpose |
|---|---|
| `fn_create_package_entitlements(p_assignment_id)` | Materializes a redemption row per **mandatory** package item; expiry derived from package validity (days then date then assignment.effective_to) |
| `fn_use_entitlement(p_redemption_id, p_qty, p_performed_by, p_source_type, p_source_ref, p_store_id, p_notes)` | Atomic FOR UPDATE decrement; sets `used_status=true` when fully consumed; logs `use` action |
| `fn_reverse_entitlement_use(p_redemption_id, p_qty, p_performed_by, p_reason)` | Undo a previous use; clears `used_status` if it had been set |
| `fn_adjust_entitlement_total(p_redemption_id, p_qty_change, p_performed_by, p_reason)` | Change total qty up or down; cannot reduce below `used_qty` |
| `fn_expire_package_entitlements()` | Marks all past-due tracked entitlements as `used_status=true` and logs `expire`. Currently has no scheduled cron — must be invoked explicitly |

## 4. Lifecycle

```
admin defines package          (bff_upsert_package_with_items)
        │
        ▼
admin / api / persona / purchase / mission / tier
        │ → creates package_assignment
        ▼
fn_create_package_entitlements(assignment_id)
        │ → for each MANDATORY item: insert reward_redemptions_ledger row
        ▼
member sees package via get_user_packages
        │
        ├── elective items present? → member calls select_elective_items
        │           → inserts ledger rows for selected rewards (idempotent, group-bounded)
        │
        ▼
each use:  api_use_entitlement → fn_use_entitlement (atomic decrement + log)
            │
            ├── used_qty < qty                  → still active
            ├── used_qty == qty                 → used_status=true (fully consumed)
            └── adjust / reverse                → bff_admin_adjust_entitlement / fn_reverse_entitlement_use

eventual:  fn_expire_package_entitlements → expires past use_expire_date entitlements
```

## 5. Mandatory vs elective

`fn_create_package_entitlements` only materializes **mandatory** items at assignment time. Elective items remain dormant until the member calls `select_elective_items`, which:
1. Verifies the assignment belongs to the calling user (`auth.uid()`) and is `status='active'`
2. Iterates each requested reward against `package_items` filtered by `is_elective=true`
3. Enforces `elective_max_picks` per `elective_group` across the requested set
4. Skips picks already materialized for the assignment (idempotency)
5. Inserts ledger rows with `points_calculation.mode = 'elective_selection'`

## 6. Validity precedence at materialization

In `fn_create_package_entitlements`:
1. If `package_master.validity_days` is set → expiry = `assignment.effective_from + N days`
2. Else if `package_master.validity_date` is set → expiry = that fixed date
3. Else if `assignment.effective_to` is set → expiry = `effective_to`
4. Else → no expiry (entitlement never expires until manually adjusted or cancelled)

`select_elective_items` follows the same precedence.

## 7. Translation

`get_user_packages` joins `translations` with `entity_type IN ('package', 'reward')` and `field_name = 'name'`, falling back to the source name when no translation exists for the requested language. Language defaults: explicit `p_language` → merchant default → `'en'`.

## 8. Integration with reward ledger

Package entitlements **share the standard `reward_redemptions_ledger` table**. Consequences:
- "My Coupons" / redemption views automatically include them — but they need to render the remaining balance, not a binary used flag.
- Any query that sums `qty` for stock or per-user limit checks must filter out `source_type IN ('package_assignment','persona_entitlement')` for user-scoped limits (per `Package_Contract_Benefit.md` §1, the patches `redeem_reward_with_points` and `api_mark_redemption_used` cover this).
- `api_mark_redemption_used` rejects multi-use entitlements with the message `"Multi-use entitlements must be consumed via api_use_entitlement"`. Frontend / POS must branch on source_type.

## 9. Caveats and known limitations

- **No scheduled cron.** `fn_expire_package_entitlements` exists but is not registered in `cron.job`. Expired entitlements remain `used_status=false` until something invokes the function.
- **No automatic persona trigger.** `Package_Contract_Benefit.md` references `trg_auto_assign_on_persona_change` on `user_accounts`; that trigger is NOT installed today. `fn_auto_assign_on_persona` only runs when called explicitly. See `Persona_Entitlement.md` §5.
- **Status field underused.** `package_assignment.status` defaults to `NULL` in many code paths and is filtered by `'active'` in admin list / member views. There is no cancellation function for an assignment as a whole — admins cancel individual entitlements via `bff_admin_adjust_entitlement` (or set `cancelled=true` directly on ledger rows).
- **`bff_admin_assign_package` per-user error swallowing.** Failed inserts in the loop increment `failed_count` but do not return per-user error reasons.

## 10. Related

- `Reward.md` — the rewards that package items reference
- `Persona_Entitlement.md` — persona-driven auto-assignment of packages
- `Currency.md` — points are not deducted by package use (`points_deducted=0`)
- `Tier.md` — tier upgrades can be wired to assign packages (no built-in trigger today)
