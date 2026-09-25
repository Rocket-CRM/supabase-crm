# Spin Wheel Gamification — Implementation Plan

**Created:** 2026-06-30
**Status:** Implemented (DB backend deployed 2026-06-30)
**Project ID:** `wkevmsedchftztoolkmi` (all DB work via Supabase MCP — `execute_sql`, `apply_migration`)

---

## 1. Goal

A **spin wheel** campaign: a user spends currency (points **or** a ticket type) to take one
spin and randomly win a **prize** (a bundle of one-or-more outcomes). The admin configures the
campaign, the set of prizes, each prize's probability, and the outcomes inside each prize.

This is the **Phase 6 consumer** the Central Outcome Dispatcher plan anticipated
(`.cursor/plans/central-outcome-dispatcher-plan-20260628.md` §9): *"Spin wheel and any new
campaign: pick outcome row(s) → call `fn_dispatch_outcome`. No new dispatch logic."*

So the work is **not** building reward/currency plumbing — it's a thin campaign + a weighted
random selector that delegates every grant to the existing dispatcher.

---

## 2. Reuse (verified live against the registry)

| Need | Reuse | Status |
|---|---|---|
| Grant any outcome (points / tickets / reward / earn_factor) | `fn_dispatch_outcome(p_user_id, p_merchant_id, p_outcome_type, p_entity_id, p_amount, p_source_type, p_source_id, p_metadata, p_dedup_key) -> jsonb` | **Live** (registry L1540) |
| Per-grant audit | `outcome_distribution_log` (dispatcher writes one row per grant, `source_type='spin_wheel'`) | **Live** (L1276) |
| Spend / burn currency | `chokepoint_post_wallet_transaction(..., currency, ..., currency_transaction_type, amount, ...)` with a burn/spend type | **Live** (L450) |
| Participation limits (per user / total, per day/week) | `transaction_limits` with `entity_type='spin_wheel'` | **Live** (L800) — same pattern check-in uses |
| Eligibility (tier / persona / tags / birth month) | array columns mirroring `reward_master` (`allowed_tier`, `allowed_persona`, `allowed_tags`, `allowed_birthmonth`) | Pattern proven on check-in & rewards |
| Ticket balance read | `get_user_ticket_balance(p_user_id, p_merchant_id, p_ticket_type_id) -> integer` | **Live** (L481) |

`outcome_type_enum = points | tickets | reward | earn_factor` already exists — reuse it for the
prize outcomes. **No new dispatch logic, no new grant primitives.**

---

## 3. Terminology (to avoid collision with the dispatcher's "outcome")

- **Campaign** = `spin_wheel` (the wheel header + cost + eligibility + window).
- **Prize / segment** = `spin_wheel_segment` = one slice of the wheel. This is the "outcome
  with a 5% chance" the user described — the *bundle*. Carries the probability weight.
- **Outcome** = `spin_wheel_segment_outcome` = one grant inside a prize (10 points, OR one
  reward push, OR one ticket). A 5%-chance prize of "10 points + 2 reward pushes + 1 ticket"
  is **one segment with three outcome rows** (the reward row with `amount=2`).
- **Spin** = `spin_wheel_log` = one immutable spin event (the cost charged + the prize won).

---

## 4. Data model

### 4.1 `spin_wheel` (campaign header)

```
id                uuid PK
merchant_id       uuid NOT NULL
name              text NOT NULL
description       text

-- lifecycle / window
active_status     boolean NOT NULL DEFAULT true
window_start      timestamptz
window_end        timestamptz

-- cost to spin (one spin = one charge)
cost_currency     currency NOT NULL DEFAULT 'points'   -- 'points' | 'ticket'
cost_ticket_type_id uuid                                -- required when cost_currency='ticket'
cost_amount       integer NOT NULL DEFAULT 0            -- 0 ⇒ free spin

-- eligibility (mirror reward_master; empty/null array = no restriction)
allowed_tier        uuid[]
allowed_persona     uuid[]
allowed_tags        uuid[]
allowed_birthmonth  int[]

-- presentation (FE owns rendering; backend stays truth-only)
display_config    jsonb DEFAULT '{}'::jsonb   -- colors, center image, label overrides, i18n

created_at        timestamptz DEFAULT now()
updated_at        timestamptz DEFAULT now()
```

Participation caps are **not** columns here — they live in `transaction_limits`
(`entity_type='spin_wheel'`, `entity_id=spin_wheel_id`, `scope in ('user','total')`), exactly
as check-in does. That gives "3 spins/user/day", "1000 spins total", etc. for free.

### 4.2 `spin_wheel_segment` (the prizes / slices)

```
id              uuid PK
merchant_id     uuid NOT NULL
spin_wheel_id   uuid NOT NULL FK→spin_wheel
label           text NOT NULL                 -- "10 points + mystery box"
weight          numeric NOT NULL CHECK (weight >= 0)   -- relative probability
is_no_win       boolean NOT NULL DEFAULT false -- "better luck next time" slice (no outcomes)
display_order   int DEFAULT 0

-- optional inventory cap for limited prizes (NULL = unlimited)
stock_total     int
stock_remaining int

active_status   boolean NOT NULL DEFAULT true
display_config  jsonb DEFAULT '{}'::jsonb
created_at      timestamptz DEFAULT now()
updated_at      timestamptz DEFAULT now()
```

**Probability = relative weights**, not hard percentages. The selector normalizes
`weight / SUM(weight)` over the currently-eligible segments at spin time. Why weights, not a
"must sum to 100" column:
- Adding/removing a prize never forces a rebalance of every other row.
- Sold-out / inactive segments drop out cleanly (their weight is just excluded).
- The admin UI can still *input* percentages — store them verbatim as weights; if they sum to
  100 the displayed % equals the input. A soft advisory ("weights total 100% ✓") in the BFF,
  not a DB constraint.

### 4.3 `spin_wheel_segment_outcome` (grants inside a prize)

```
id            uuid PK
merchant_id   uuid NOT NULL
segment_id    uuid NOT NULL FK→spin_wheel_segment
outcome_type  outcome_type_enum NOT NULL    -- reuse dispatcher enum
entity_id     uuid                          -- reward_id | ticket_type_id | earn_factor_id | NULL(points)
amount        numeric                       -- points amount | ticket qty | reward qty
metadata      jsonb DEFAULT '{}'::jsonb     -- e.g. {window_days} for earn_factor
created_at    timestamptz DEFAULT now()
```

One spin → one winning segment → loop its outcome rows → one `fn_dispatch_outcome` call each.

### 4.4 `spin_wheel_log` (immutable spin event — audit + limit source)

```
id               uuid PK
merchant_id      uuid NOT NULL
spin_wheel_id    uuid NOT NULL
user_id          uuid NOT NULL
segment_id       uuid                       -- winning prize
cost_currency    currency
cost_amount      integer
cost_ledger_id   uuid                       -- wallet_ledger row for the burn
draw_metadata    jsonb DEFAULT '{}'::jsonb  -- {random_value, weight_snapshot:[...]} for dispute audit
spun_at          timestamptz NOT NULL DEFAULT now()
```

This is the source of truth for participation counting and fairness audits. Per-grant detail
already lands in `outcome_distribution_log` keyed by `source_type='spin_wheel', source_id=spin_wheel_id`.

---

## 5. Selection algorithm (weighted random, inventory-aware)

Inside the spin engine, in one transaction:

1. Candidate set = segments where `active_status` AND (`stock_remaining` IS NULL OR `> 0`).
2. `v_total := SUM(weight)` over candidates. (If 0 candidates → award the `is_no_win` segment,
   or return a clean "no prize available" without charging — see §6 ordering.)
3. `v_draw := random() * v_total`.
4. Walk cumulative weight ascending until `cumulative >= v_draw` → that's the winner.
5. If the winner has finite stock: `UPDATE ... SET stock_remaining = stock_remaining - 1
   WHERE id = winner AND stock_remaining > 0` (atomic guard; the row is locked for the txn).
   If it lost the race (0 rows updated), re-select from the remaining candidates.
6. Persist `draw_metadata = {random_value, weights:[{segment_id, weight}...]}` for auditability.

Pure-SQL, deterministic to audit, no external RNG service. Concurrency is handled by the
row-level `stock_remaining` guard within the function's single transaction.

### 5.1 The pick, in SQL (single statement, cumulative-weight cutoff)

```sql
-- v_draw is one random() captured up front so it can be logged in draw_metadata
WITH candidates AS (
  SELECT id, weight,
         SUM(weight) OVER (ORDER BY display_order, id
                           ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) AS cum,
         SUM(weight) OVER () AS total
  FROM   spin_wheel_segment
  WHERE  spin_wheel_id = p_spin_wheel_id
    AND  active_status
    AND  (stock_remaining IS NULL OR stock_remaining > 0)
)
SELECT id INTO v_segment_id
FROM   candidates
WHERE  cum >= v_draw * total      -- v_draw := random() in [0,1)
ORDER  BY cum
LIMIT  1;
```

- A segment of weight `w` wins with probability `w / total` — the cutoff falls inside its
  cumulative band. Weights need not sum to 100; normalization is implicit in `* total`.
- `v_draw` is stored in `spin_wheel_log.draw_metadata` alongside the `{segment_id, weight}`
  snapshot, so any spin can be replayed/audited exactly.
- **Inventory race:** after the pick, the atomic decrement guards it —
  `UPDATE spin_wheel_segment SET stock_remaining = stock_remaining - 1
   WHERE id = v_segment_id AND (stock_remaining IS NULL OR stock_remaining > 0)`.
  If `0 rows` (someone else took the last unit mid-transaction), loop: re-run the CTE
  excluding `v_segment_id` and re-draw. Bounded by the number of finite-stock segments.
- **Empty candidate set** (all sold out / inactive): award the `is_no_win` segment if one
  exists; otherwise return `{success:false, error:'no_prize_available'}` **before** charging
  (the balance check / charge in §6 step 4–5 only runs once a winnable set is confirmed, so the
  user is never charged when nothing can be won).

---

## 6. Spend / cost mechanic (atomic with the win)

The engine is **one SECURITY DEFINER function = one transaction**, so a failed grant rolls back
the charge automatically. Ordering inside `fn_spin_wheel`:

1. Validate campaign: exists, `active_status`, `now()` within `window_start/window_end`.
2. Eligibility: user's tier/persona/tags/birth-month vs the `allowed_*` arrays
   (lift the check pattern from `redeem_reward_with_points` calc-mode / check-in).
3. Participation limits: enforce `transaction_limits` for `entity_type='spin_wheel'`
   (scope `user` counts this user's `spin_wheel_log` rows; scope `total` counts all).
4. Balance check: points via wallet balance, tickets via `get_user_ticket_balance(...)`.
   If `cost_amount > 0` and insufficient → return `{success:false, error:'insufficient_balance'}`
   **before** charging.
5. **Charge** (verified signature): `chokepoint_post_wallet_transaction(p_user_id := p_user_id,
   p_currency := cost_currency, p_source_type := 'spin_wheel', p_component := 'base',
   p_transaction_type := 'burn', p_amount := cost_amount, p_transaction_id := v_spin_log_id,
   p_merchant_id := p_merchant_id, p_description := '...', p_metadata := {...},
   p_target_entity_id := cost_ticket_type_id /* NULL for points */, p_dedup_key := ...)`.
   Capture `cost_ledger_id` (return is the wallet ledger uuid). (Skip entirely when `cost_amount=0`.)
   `currency_transaction_type` is just `burn|earn` — spend uses **`'burn'`**; `currency` is
   **`'ticket'`** (singular) or `'points'`.
6. **Select** the winning segment (§5).
7. **Dispatch** each `spin_wheel_segment_outcome` → `fn_dispatch_outcome(..., p_source_type :=
   'spin_wheel', p_source_id := p_spin_wheel_id, p_metadata := {segment_id, spin_log_id})`.
   If any dispatch returns `success:false`, RAISE to roll back the whole txn (including the
   charge) → user is never charged for a spin they didn't receive.
8. **Insert** the `spin_wheel_log` row.
9. Return `{success, segment:{id,label}, outcomes:[...], cost:{currency,amount}, new_balance}`.

---

## 7. Functions

All three admin BFFs mirror the **check-in** trio verbatim (newest sibling campaign on this
dispatcher): `bff_list_checkins()`, `bff_get_checkin_details(p_mode, p_checkin_id)`,
`bff_upsert_checkin(p_config jsonb)`. Same naming, same single-jsonb upsert, same new/edit get,
same `fn_response_success`/`fn_response_error` envelope, `SECURITY DEFINER`,
`v_merchant_id := get_current_merchant_id()` guard (per `10-function-conventions.mdc`).

### 7.1 Admin — list page

```
bff_list_spin_wheels() -> jsonb
```
Returns `data.spin_wheels[]` for the table view, merchant-scoped, one row per campaign:
```jsonc
{ "id", "name", "active_status", "window_start", "window_end",
  "cost": { "currency", "ticket_type_id", "amount" },
  "segment_count",            // count of active segments
  "total_spins",              // count(spin_wheel_log) for the campaign
  "created_at", "updated_at" }
```
Cheap aggregates only (counts, no per-segment payload). Keep it argument-less like
`bff_list_checkins()`; add `p_limit/p_offset/p_filter` later only if the list grows
(mirrors `bff_get_reward_history` if pagination is needed).

### 7.2 Admin — config page (load)

```
bff_get_spin_wheel_details(p_mode text DEFAULT 'edit', p_spin_wheel_id uuid DEFAULT NULL) -> jsonb
```
- `p_mode='new'` → empty template: campaign NULLs + `segments: []`, `limits: []`, default
  `cost_currency:'points'`, `cost_amount:0`. Lets the form render before anything is saved.
- `p_mode='edit'` → full tree in one call (so the config page never round-trips per segment):
```jsonc
{ "data": {
  "campaign": { /* all spin_wheel columns + display_config */ },
  "segments": [
    { "id", "label", "weight", "weight_pct",     // weight_pct = normalized % for the UI
      "is_no_win", "display_order", "stock_total", "stock_remaining",
      "active_status", "display_config",
      "outcomes": [ { "id", "outcome_type", "entity_id", "amount", "metadata",
                      "entity_label" } ] }   // entity_label resolved (reward/ticket name) for display
  ],
  "limits": [ { "id", "scope", "metric", "count", "time_unit",
                "window_start", "window_end", "active_status" } ]  // transaction_limits rows
} }
```
`segments` via `jsonb_agg` with `COALESCE(..., '[]')`; `outcomes` nested per segment; `limits`
read from `transaction_limits WHERE entity_type='spin_wheel' AND entity_id=p_spin_wheel_id`.
`weight_pct` is computed (`weight / NULLIF(SUM(weight),0) * 100`) so the admin sees live odds.

### 7.3 Admin — config page (save)

```
bff_upsert_spin_wheel(p_config jsonb) -> jsonb
```
One payload, parent + children, transactional. Shape:
```jsonc
{ "id": null,                      // null → INSERT campaign, else UPDATE
  "name", "description", "active_status", "window_start", "window_end",
  "cost_currency", "cost_ticket_type_id", "cost_amount",
  "allowed_tier": [], "allowed_persona": [], "allowed_tags": [], "allowed_birthmonth": [],
  "display_config": {},
  "segments": [
    { "id": null,                  // null → INSERT, else UPDATE; track kept ids → delete orphans
      "label", "weight", "is_no_win", "display_order",
      "stock_total", "stock_remaining", "active_status", "display_config",
      "outcomes": [ { "id": null, "outcome_type", "entity_id", "amount", "metadata" } ] }
  ],
  "limits": [ { "id": null, "scope", "metric", "count", "time_unit",
                "window_start", "window_end" } ] }
```
> `transaction_limits` columns (verified): `scope` (`reward_condition_scope`), `metric`
> (`reward_limit_metric`), `count` (numeric), `time_unit` (`reward_condition_time_unit`),
> `window_start/window_end`, `active_status`. There is **no `time_value`** column — a limit is
> `count` per `time_unit` (e.g. 3 / `day`). Reuse these enums; do not invent fields.

Upsert rules (standard convention): missing `id` → INSERT, present → UPDATE, collect kept ids,
`DELETE ... WHERE id != ALL(v_kept_ids)` for segments / outcomes / limits orphaned by the save.
Returns counts (`segments_created/updated/deleted`, etc.) in `fn_response_success`.

**Validation in the upsert (advisory, not DB constraints):**
- At least one segment with `weight > 0`, else the wheel can never resolve → error.
- `cost_currency='ticket'` ⇒ `cost_ticket_type_id` required and must exist+active for merchant.
- Each outcome's `entity_id` validated against its `outcome_type` (reward exists, ticket type
  active, earn_factor exists; NULL allowed for points).
- Optional soft note when `SUM(weight) <> 100` so the admin knows whether they're in
  "percentage" mode — **not** rejected (weights are relative; see §4.2).

### 7.4 (Optional) `bff_delete_spin_wheel(p_spin_wheel_id) -> jsonb`

Soft-delete via `active_status=false` preferred over hard delete (preserves `spin_wheel_log`
history + FK integrity). Hard delete only if no spins logged.

### 7.5 Engine (the spin) — §6

```
fn_spin_wheel(p_user_id uuid, p_merchant_id uuid, p_spin_wheel_id uuid) -> jsonb
```
`SECURITY DEFINER`, one transaction. Internal `fn_*` — see §6 for the ordered flow and §5 for
the selection. The user-app initiate endpoint is a thin wrapper that resolves the
authenticated `user_id` (user session) + `merchant_id`, then calls this — same way the user app
invokes check-in. Keep the math/charge in `fn_spin_wheel`; the wrapper only injects identity.

### 7.6 User app — pre-spin read (button state)

```
get_user_spin_wheel_status(p_user_id uuid, p_merchant_id uuid, p_spin_wheel_id uuid) -> jsonb
```
Read-only, drives the wheel screen **before** the user commits a spin:
```jsonc
{ "data": {
  "campaign": { "id", "name", "display_config", "window_start", "window_end" },
  "segments": [ { "id", "label", "display_config", "weight_pct" } ],  // render order + odds (NO stock)
  "cost": { "currency", "ticket_type_id", "amount" },
  "user": { "balance", "is_eligible", "spins_remaining", "next_reset_at" },
  "can_spin": true   // eligible AND within window AND under limit AND balance >= cost
} }
```
Reveal policy (product call): show `weight_pct`, **hide** `stock_remaining` and raw weights.
`spins_remaining` derived from `transaction_limits` minus `spin_wheel_log` counts.

---

## 8. Enums / shared types to extend (verified — both adds confirmed needed, each needs approval)

- `wallet_transaction_source_type` → `ALTER TYPE ... ADD VALUE 'spin_wheel'`.
  **Confirmed missing** (current values include `...amp, ..., checkin` but no `spin_wheel`).
  The dispatcher casts `p_source_type` to this for the chokepoint, so the value must exist.
- `entity_type` → `ALTER TYPE ... ADD VALUE 'spin_wheel'` (for `transaction_limits`).
  **Confirmed missing** (current: `reward, purchase, points, earn_factor, activity, form,
  reward_group, checkin`). Check-in added `'checkin'` the same way.
- **Reuse as-is** (verified): `outcome_type_enum` (`points, tickets, reward, earn_factor`),
  `currency` (`points, ticket`), `currency_transaction_type` (`burn, earn` — spend = `'burn'`),
  `currency_component` (`base, ...`), and the limit enums `reward_condition_scope`,
  `reward_limit_metric`, `reward_condition_time_unit`.

> `ADD VALUE` cannot run inside the same transaction that then uses the new label in some
> contexts — add the two enum values in their own migration step **before** creating tables /
> functions that reference them. Sequence: (a) enum adds → (b) tables → (c) functions.

`condition_type`-style fields are **text**, not DB enums, per workspace convention — but spin
wheel doesn't need a condition_type. Keep it lean.

---

## 9. "Any other considerations?" — design decisions surfaced

1. **Atomicity / no double-charge.** Single-transaction engine: a partial outcome failure
   rolls back the spend. No refund path needed. (Recommended.)
2. **Idempotency / double-click.** FE debounce + optional `p_dedup_key` threaded to the
   chokepoint; `spin_wheel_log` is the authoritative ledger. Rate-limit via `transaction_limits`.
3. **Fairness / disputes.** Persist the RNG draw + weight snapshot in `spin_wheel_log.draw_metadata`.
   Lets support reconstruct any spin. (Recommended — cheap, high trust value.)
4. **Probability model.** Relative **weights**, normalized at spin time (not a rigid sum-to-100
   column). Scales as prizes come and go; admin can still think in %. (Recommended.)
5. **Limited prizes / inventory.** Optional per-segment `stock_remaining` with an atomic
   decrement guard; sold-out segments drop out of the draw. Note: this is *segment* stock
   (how often the slice can be won) — distinct from `reward_master`'s own redemption limits,
   which still apply when the reward is granted.
6. **No-win slice.** `is_no_win` segment with zero outcomes, so the wheel can legitimately
   land on "better luck next time" and the visual wheel always resolves.
7. **Free spins.** `cost_amount = 0` covers free wheels today. Scheduled/earned bonus spins
   (e.g. "1 free spin/day", spins as a reward type) = **future**, not this plan — avoid
   over-engineering a spin-credit wallet now.
8. **Cost in any currency.** `cost_currency` = points or a ticket type; outcomes can be any of
   the four dispatcher types — including granting *tickets*, so "spin with points, win a ticket"
   works out of the box.
9. **Reveal policy.** Decide per product whether the user read endpoint exposes true odds and
   remaining stock. Default: show normalized %, hide stock.
10. **Localization / theming.** All visual/i18n config in `display_config` jsonb; backend
    stays logic-only (truth boundary).
11. **Pity / guaranteed-win mechanics.** Out of scope; weights + inventory cover the
    near-term need. Revisit only if product asks.

---

## 10. Phasing & scope

- **Phase 1 — Schema:** enums (`'spin_wheel'` on the two enum types) + 4 tables
  (`spin_wheel`, `spin_wheel_segment`, `spin_wheel_segment_outcome`, `spin_wheel_log`) with
  RLS (`merchant_isolation`) + `set_updated_at` triggers. One migration, present SQL, await approval.
- **Phase 2 — Engine + user read:** `fn_spin_wheel` (§5/§6) + `get_user_spin_wheel_status`
  (§7.6). Smoke-test each outcome type + cost path + limit path + inventory race + empty/no-win
  set directly via `execute_sql`.
- **Phase 3 — Admin BFFs:** `bff_list_spin_wheels` (§7.1), `bff_get_spin_wheel_details` (§7.2),
  `bff_upsert_spin_wheel` (§7.3), optional `bff_delete_spin_wheel` (§7.4). Mirror the check-in trio.
- **Phase 4 — Docs/registry:** registry regenerate, `CHANGELOG.md` line, requirement doc,
  optional CRM Knowledge feature block.

**OUT of scope:** front-end, scheduled/earned free-spin credits, pity mechanics, any change to
`fn_dispatch_outcome` itself.

---

## 11. Pre-flight verification — DONE (2026-06-30, live DB)

| Check | Result |
|---|---|
| `fn_dispatch_outcome` signature | ✅ `(p_user_id, p_merchant_id, p_outcome_type outcome_type_enum, p_entity_id, p_amount numeric, p_source_type text, p_source_id, p_metadata jsonb, p_dedup_key) -> jsonb` — matches plan |
| `chokepoint_post_wallet_transaction` signature | ✅ `(p_user_id, p_currency, p_source_type, p_component, p_transaction_type, p_amount int, p_transaction_id, p_merchant_id, p_description, p_metadata, p_target_entity_id, p_dedup_key) -> uuid` |
| `get_user_ticket_balance(p_user_id, p_merchant_id, p_ticket_type_id) -> integer` | ✅ exists |
| `outcome_type_enum` | ✅ `points, tickets, reward, earn_factor` |
| `currency` | ✅ `points, ticket` (singular) |
| `currency_transaction_type` | ✅ `burn, earn` → spend = `'burn'` |
| `wallet_transaction_source_type` has `'spin_wheel'`? | ❌ **missing** → `ADD VALUE` required |
| `entity_type` has `'spin_wheel'`? | ❌ **missing** → `ADD VALUE` required |
| `transaction_limits` columns | ✅ `id, merchant_id, entity_type, entity_id, scope, metric, count, time_unit, window_start, window_end, active_status, created_at` (no `time_value`) |

Still to confirm **at implementation time** (not blocking approval):
- Points balance read helper (the one `redeem_reward_with_points` calc-mode uses) vs. relying on
  the chokepoint's own insufficient-balance guard for the spend.
- RLS/grants of a sibling campaign table (`checkin` / `checkin_outcomes`) to mirror verbatim.

## 12. Migration sequence (on approval)

1. **Enums** (own step): `ALTER TYPE wallet_transaction_source_type ADD VALUE 'spin_wheel'`;
   `ALTER TYPE entity_type ADD VALUE 'spin_wheel'`.
2. **Tables** (§4): `spin_wheel`, `spin_wheel_segment`, `spin_wheel_segment_outcome`,
   `spin_wheel_log` + RLS `merchant_isolation` + `set_updated_at` triggers (mirror check-in).
3. **Functions**: Phase 2 (`fn_spin_wheel`, `get_user_spin_wheel_status`), then Phase 3 BFFs.
4. **Docs/registry**: registry regenerate, `CHANGELOG.md` line, requirement doc.

Present each `apply_migration` SQL and wait for "approved" before running (schema changes are
prohibited without approval per `00-core.mdc`).
