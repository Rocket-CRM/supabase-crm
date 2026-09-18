# Persona Entitlement

Catalog rules: “users with persona P automatically receive package, reward grant, or standing benefit X.” Powers B2B contract perks and VIP-style policies.

Owner surfaces: loyalty-admin (persona config), system auto-assign on persona change (when invoked)

## Concept

**Persona entitlements (shelved — demo-built, not launched)** — When launched, persona assignment would automatically materialize configured packages, direct reward balances, or standing benefits (discount/access tuples) for B2B and VIP programs. Grant engine and contract RPCs exist; automatic persona-change wiring and admin Contract Builder UI do not. Portfolio: [Shelved_Demo_Features.md](./Shelved_Demo_Features.md).

**Persona** — Segment on `user_accounts.persona_id` (`Tag_and_Persona.md`).

**Entitlement row** — One of `package` | `reward` | `benefit` with type-specific columns.

**Auto-assign** — `fn_auto_assign_on_persona` materializes packages or ledger rows or `user_benefit` rows.

**Standing benefit** — Non-ledger privilege; validity derived at read from persona/contract, not stored dates.

Legacy combined spec: `Package_Contract_Benefit.md`.

## Rules

- Inactive entitlement rows are skipped on auto-assign.
- `package` type creates `package_assignment` then mandatory package entitlements.
- `reward` type inserts ledger row with `source_type = persona_entitlement` and zero points.
- `benefit` type writes `user_benefit` with `source_type = persona`; validity recomputed each read.
- **No DB trigger today** — persona change does not auto-run assign unless caller invokes `fn_auto_assign_on_persona` (see technical reference §5).
- **Launch gate:** `/persona-entitlements-advanced` is a placeholder; production grants require explicit `fn_auto_assign_on_persona` calls or contract BFF upserts for demo data.

## Journeys

### Admin journey

| Knob | Effect |
| --- | --- |
| Entitlement type | Package vs reward qty vs benefit tuple |
| Persona / group contract fields | B2B metadata on `persona_group_master` |
| Active flag | Included in auto-assign |

1. Configure persona and entitlement rows in admin.
2. On persona assignment (or batch job), run auto-assign for affected users.
3. Members consume package/reward entitlements via standard use flows; benefits via benefit readers.

Demo-only: Contract Builder page shows empty state; entitlement rows for demos are typically seeded via `bff_upsert_contract_with_levels` or ops SQL, not self-serve GA admin.

### Member journey

1. Persona assigned (signup, admin, import).
2. Auto-assign runs when triggered → packages/rewards appear in wallet/coupons.
3. Use entitlements per `Package.md` / `Reward.md` rules.

## System

`persona_entitlement`, `user_benefit`, `fn_auto_assign_on_persona`, links to `Package.md` helpers. Schema and type matrix: technical reference.

### Known gaps (launch checklist)

| Area | Gap |
| --- | --- |
| Automation | Install persona-change trigger (spec in retired `Package_Contract_Benefit.md`) or chokepoint hook calling `fn_auto_assign_on_persona` |
| Revocation | Persona change does not cancel prior package/reward ledger rows — manual cancel/adjust |
| Admin UI | Contract Builder not shipped — `/persona-entitlements-advanced` empty |
| Idempotency | Re-running auto-assign duplicates grants — caller must guard |
| Direct reward | Auto-assign `reward` branch may set immediate expiry when reward has `validity_days` — verify `prosrc` before launch |
| Benefits | Persona-sourced benefits re-evaluate at read; packages/rewards stay until cancelled |

## Related

- **[Shelved_Demo_Features.md](./Shelved_Demo_Features.md)** — Launch status index.
- **Tag_and_Persona.md** — Persona assignment.
- **Package.md** — Package materialization.
- **Tier.md** — Distinct from tier entry rewards.
- **Package_Contract_Benefit.md** — Retired combined spec; pointer only.

---

# Persona Entitlement — technical reference

## 1. Concept

| Concept | Definition |
|---|---|
| Persona | A profile assigned to a user (e.g., "Corporate Executive", "VIP Connex") via `persona_master.id` on `user_accounts.persona_id` |
| Persona group | A parent grouping of personas (`persona_group_master`); also carries B2B contract metadata (`contract_type`, `contract_start/end`, `contract_status`) |
| Persona entitlement | One row in `persona_entitlement` saying "this persona auto-grants X" |
| Auto-assign | The act of materializing all active persona_entitlement rows for a given (user, persona) pair via `fn_auto_assign_on_persona` |
| Standing benefit | A non-consumable privilege (discount, access, priority) stored in `user_benefit` and re-evaluated at read time |

## 2. Schema

### `persona_entitlement`
| Column | Type | Notes |
|---|---|---|
| `persona_id` | uuid | FK to `persona_master` |
| `entitlement_type` | text | `package` \| `reward` \| `benefit` (discriminator) |
| `package_id` | uuid | required when type = `package` |
| `reward_id` | uuid | required when type = `reward` |
| `qty` | int | required when type = `reward` |
| `category` | text | required when type = `benefit` (e.g., `opd`, `pharmacy`) |
| `benefit_type` | text | required when type = `benefit` (e.g., `discount_percent`, `flat_amount`) |
| `value` | numeric | required when type = `benefit` |
| `active_status` | bool | inactive rows are skipped by `fn_auto_assign_on_persona` |
| `ranking` | smallint | iteration order |

A CHECK constraint per the original spec enforces shape per `entitlement_type` (the bundled doc lists the constraint expression — verify with `\d+ persona_entitlement` if questioned).

### `user_benefit` — runtime store for granted benefits
| Column | Notes |
|---|---|
| `user_id` | recipient |
| `category`, `benefit_type`, `value` | copied from `persona_entitlement` (or set directly for non-persona sources) |
| `source_type` | `persona` \| `tier` \| `marketing` \| `admin` \| `campaign` |
| `source_id` | the originating record (for `persona` source: `persona_id`) |
| `valid_from`, `valid_to` | self-managed sources only — for `persona` source these are NULL and validity is derived at read time |
| `status` | `active` \| `cancelled` |

### `persona_group_master` contract columns
The same group table that defines persona organization also carries B2B contract metadata: `contract_type`, `company_name`, `contact_person`, `contact_email`, `contract_start`, `contract_end`, `contract_status`, `contract_metadata`. These are nullable — non-contract groups simply leave them NULL.

## 3. Three entitlement types

### `package`
`fn_auto_assign_on_persona` creates a `package_assignment` (source_type=`persona_assignment`, source_id=persona_entitlement.id, assigned_by=`system`) then calls `fn_create_package_entitlements` to materialize the package's mandatory items. The user can later `select_elective_items` like any other assignment.

### `reward`
Skips the package indirection. `fn_auto_assign_on_persona` inserts a single `reward_redemptions_ledger` row directly:
- `source_type = 'persona_entitlement'`
- `source_id = persona_entitlement.id`
- `qty = persona_entitlement.qty`, `used_qty = 0`
- `points_deducted = 0`
- `use_expire_date` is set only if the underlying reward has `validity_days` set (see caveat in §8).
- `points_calculation.mode = 'persona_entitlement'`

Used through the same `api_use_entitlement` / `fn_use_entitlement` runtime as package entitlements.

### `benefit`
Inserts a row in `user_benefit` with `source_type='persona'`, `source_id=persona_id`, and the (category, benefit_type, value) tuple copied from the entitlement row. Validity is **not** stored — eligibility is recomputed every read against the source persona and contract.

## 4. Auto-assign function

```
fn_auto_assign_on_persona(p_user_id uuid, p_persona_id uuid)
  ↓
  resolve merchant_id from persona_master
  ↓
  for each row in persona_entitlement
        where persona_id = p_persona_id and active_status = true
        order by ranking
    case entitlement_type
      'package'  → insert package_assignment + fn_create_package_entitlements
      'reward'   → insert reward_redemptions_ledger row
      'benefit'  → insert user_benefit row (source = persona)
  ↓
  return { packages_assigned, rewards_issued, benefits_created }
```

The function is idempotent in the sense that re-running it creates duplicate grants; callers must guard against re-invocation.

## 5. Trigger status — important

The bundled spec `Package_Contract_Benefit.md` describes a trigger `trg_auto_assign_on_persona_change` on `user_accounts` AFTER UPDATE OF `persona_id`. **That trigger is NOT installed today** — the only triggers on `user_accounts` are `set_updated_at_user_accounts` and `trg_user_accounts_check_store_merchant`.

In production today, persona entitlements only flow when something explicitly calls `fn_auto_assign_on_persona`. Roster importers, admin tools, or frontline actions that change a user's persona must invoke it manually. Cancellation of prior persona's grants on persona change is also not automated.

## 6. Standing benefits — validity at read time

`fn_evaluate_user_benefits(p_user_id)` returns active benefits and uses two validity modes:

| Mode | source_type | How |
|---|---|---|
| Persona-sourced | `persona` | JOIN `user_accounts → persona_master → persona_group_master`; benefit excluded if persona inactive, or contract not active, or contract_end past |
| Self-managed | `tier`, `marketing`, `admin`, `campaign` | Validate `user_benefit.valid_from/to` |

`fn_resolve_benefit_precedence(p_benefits)` then reduces multiple benefits in the same `category` to the highest `value` (`DISTINCT ON (category) ORDER BY category, value DESC`). Benefits are not stackable.

`api_get_eligibility(p_user_identifier, p_identifier_type, ...)` is the public surface HIS-style integrations call to fetch a user's effective benefit set.

## 7. Function inventory

### Admin BFF
| Function | Purpose |
|---|---|
| `bff_upsert_contract_with_levels(p_group_id, ..., p_levels)` | Create / update contract group + child personas + entitlement rows in one call |
| `bff_admin_get_contract_list(p_status, p_type)` | List persona groups carrying contract metadata, with level + member counts |
| `bff_admin_get_contract_detail(p_group_id)` | Full contract: levels, entitlement config |
| `bff_admin_assign_benefit(p_benefits)` | Batch insert `user_benefit` rows for ad-hoc (non-persona) standing benefits |
| `bff_admin_get_user_benefits(p_user_id)` | Inspect a user's benefit set |
| `bff_admin_cancel_benefit(p_benefit_id, p_reason)` | Cancel one `user_benefit` row |

### Member-facing
| Function | Purpose |
|---|---|
| `get_user_benefits()` | `auth.uid()`-scoped active benefit list |

### External API
| Function | Purpose |
|---|---|
| `api_get_eligibility(p_user_identifier, p_identifier_type, ...)` | Returns the user's resolved benefit set with precedence applied |
| `api_use_entitlement(...)` | Same surface as packages — used to consume `entitlement_type='reward'` direct grants |

### Internal
| Function | Purpose |
|---|---|
| `fn_auto_assign_on_persona(p_user_id, p_persona_id)` | The grant engine described in §4 |
| `fn_evaluate_user_benefits(p_user_id)` | Read-time validity resolver |
| `fn_resolve_benefit_precedence(p_benefits)` | Highest-value-per-category reducer |

## 8. Caveats

- **No automatic persona trigger** — covered in §5. This is the single biggest operational gap. Until installed, every code path that flips `user_accounts.persona_id` must call `fn_auto_assign_on_persona` itself.
- **No persona-revocation cleanup**. When a user's persona changes or the contract expires:
  - Persona-sourced **benefits** automatically stop appearing because `fn_evaluate_user_benefits` re-validates the source.
  - Persona-sourced **package assignments** and **direct reward grants** remain in the ledger as live entitlements. They must be explicitly cancelled (set `cancelled=true` on the ledger row, or use `bff_admin_adjust_entitlement` to zero remaining qty) to stop honoring them.
- **Direct-reward expiry is partial.** In `fn_auto_assign_on_persona`, the `entitlement_type='reward'` branch sets `use_expire_date = now()` when the reward has `validity_days`, instead of `now() + validity_days::interval`. This effectively expires the entitlement immediately. Either the reward must be configured with no `validity_days`, or the user-facing entitlement should be granted by wrapping the reward in a package. (Verify with the live `prosrc` if planning to rely on direct-reward grants.)
- **No idempotency in auto-assign.** Calling `fn_auto_assign_on_persona` twice for the same (user, persona) creates duplicate grants. Caller is responsible for de-duplication.
- **`bff_admin_assign_benefit` is the only ad-hoc grant path.** There is no `bff_admin_assign_reward_entitlement` — direct reward grants currently flow only through `fn_auto_assign_on_persona`.

## 9. Related

- `Tag_and_Persona.md` — persona identity, persona_master, persona_group_master
- `Package.md` — packages, package items, mandatory/elective, runtime ledger
- `Reward.md` — the rewards that direct-reward and package-item entitlements reference
- `Package_Contract_Benefit.md` — bundled deep spec covering packages + contracts + benefits
- `Tier.md` — tier-driven benefits use `user_benefit` with source_type=`tier`
