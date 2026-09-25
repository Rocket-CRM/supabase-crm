# Central Outcome Dispatcher — Implementation Plan

**Created:** 2026-06-28
**Status:** Approved, ready for implementation
**Project ID:** `wkevmsedchftztoolkmi` (all DB work via Supabase MCP — `execute_sql`, `apply_migration`, `deploy_edge_function`)

> This plan is the seed for a fresh implementation thread. All discovery is already
> done and baked in below — **do not re-run discovery**. Start at Phase 1. Get explicit
> approval before each `apply_migration` (schema changes are prohibited without approval
> per `00-core.mdc`).

---

## 1. Goal

Build **one central outcome dispatcher** (`fn_dispatch_outcome`) that every campaign-like
feature delegates to when pushing an outcome to a user (points, tickets, reward,
earn_factor, …). Today there are **four parallel outcome subsystems**, each with its own
config table and its own dispatch logic, and they have drifted (mission uses an async edge
function for currency while AMP and check-in call the chokepoint synchronously; check-in
has two latent bugs). Consolidating removes the drift and makes future campaigns (spin
wheel, etc.) a ~20-line function instead of ~150.

**Two approved architecture decisions:**
1. **Option B** — refactor `fn_execute_amp_action` to *delegate* its outcome actions to the
   new `fn_dispatch_outcome`. Full convergence (AMP + mission + check-in share one inner
   dispatcher).
2. **Sync collapse** — mission currency grants move from the async `publish-currency-event`
   edge function onto the synchronous `chokepoint_post_wallet_transaction`, matching AMP and
   check-in.

**Hard backward-compatibility requirement (user-stated):**
> The AMP refactor MUST maintain backward compatibility with current AMP features AND with
> the front-end.

That means:
- `fn_execute_amp_action` keeps its **exact signature** (`p_action_type text, p_user_id uuid,
  p_merchant_id uuid, p_params jsonb, p_workflow_id uuid, p_node_id uuid, p_inngest_run_id
  text`).
- It keeps its **exact return shape** for every existing `p_action_type` (the FE / Inngest
  workers parse these JSON keys — see §6 for the per-action return contract that must be
  preserved verbatim).
- It keeps writing to `workflow_log` with the same columns/values.
- It keeps cost normalization (`entity_cost_normalization` → `normalized_cost`), dedup keys,
  and the exception handler.
- All `p_action_type` values it accepts today must still be accepted, including the
  non-outcome ones that stay in the AMP shell (`assign_tag`, `remove_tag`, `assign_persona`,
  `submit_form`, `add_to_audience`, `remove_from_audience`).
- Internal delegation to `fn_dispatch_outcome` is invisible to callers.

---

## 2. Discovery findings (already verified against live DB — do not re-discover)

### 2.1 Existing outcome subsystems

| Feature | Config table(s) | Outcome types | Dispatch path (current) |
|---|---|---|---|
| **AMP** | workflow nodes | points, tickets, currency, reward, earn_factor, tag, persona, form, audience | `fn_execute_amp_action` — **already the best implementation**; sync chokepoint + `redeem_reward_with_points(p_mode:='direct')` + direct earn_factor insert |
| **Mission** | `mission_outcomes` | points, tickets, reward | `fn_process_mission_outcomes` — reward via `redeem_reward_with_points(p_mode:='direct')`, **currency via async `net.http_post` → `publish-currency-event` edge fn** |
| **Check-in** | `checkin_conditions` (1 row = 1 outcome) | points, tickets, reward, earn_factor | `process_checkin` — points/tickets via chokepoint, **reward via BUGGY positional call**, earn_factor via direct insert with **hardcoded 7-day window** |
| **Event promo** | `event_promo_rule_outcome` | reward, discount_pct, discount_fixed, product(sku) | own claim/preview path — **OUT OF SCOPE**, shape doesn't fit single dispatcher |
| **Referral** | `referral_invitee_outcomes` | (enum: points/tickets/reward) + `valid_for_days` | own path — **OUT OF SCOPE for now**, candidate for later migration |

### 2.2 `fn_execute_amp_action` is already 80% of the wrapper

It is the reference implementation. Its action switch:
- `award_points` → `chokepoint_post_wallet_transaction(... 'points' ... 'amp' ... 'earn' ...)`
- `award_tickets` → same chokepoint, currency `ticket`, **validates ticket_type exists & active**
- `award_currency` → parametric on `points`/`ticket`
- `push_reward` → `redeem_reward_with_points(p_mode := 'direct', p_source_type := 'amp', p_source_id := p_workflow_id)`
- `assign_earn_factor` → `INSERT INTO earn_factor_user (earn_factor_id, user_id, merchant_id, window_end, source_type, source_id)` with `window_end := now() + coalesce(days, window_end_days, 30) days`
- `assign_tag` / `remove_tag` → `user_tags` DML
- `assign_persona` → `chokepoint_post_user_event`
- `submit_form` → `submit_form_response`
- `add_to_audience` / `remove_from_audience` → `fn_add_to_audience` / `fn_remove_from_audience`

Plus AMP-specific tail (KEEP in shell): cost normalization via `entity_cost_normalization`,
`workflow_log` insert per action, `dedup_key` threading, exception handler that logs failures.

### 2.3 Key primitive signatures (verified live)

```
chokepoint_post_wallet_transaction(
  p_user_id uuid, p_currency currency, p_source_type wallet_transaction_source_type,
  p_component currency_component, p_transaction_type currency_transaction_type,
  p_amount integer, p_transaction_id uuid, p_merchant_id uuid, p_description text,
  p_metadata jsonb, p_target_entity_id uuid [, p_dedup_key text]
) -> uuid   -- returns wallet ledger id
```
- AMP passes a trailing dedup-key arg; confirm the overload/positional in implementation.
- `p_target_entity_id` carries `ticket_type_id` for ticket currency, NULL for points.

```
redeem_reward_with_points(
  p_reward_id uuid, p_quantity integer DEFAULT 1, p_user_id uuid DEFAULT NULL,
  p_merchant_id uuid DEFAULT NULL, p_mode text DEFAULT NULL, p_source_type text DEFAULT NULL,
  p_source_id uuid DEFAULT NULL, p_event_id uuid DEFAULT NULL, p_store_id uuid DEFAULT NULL
) -> jsonb
```
- **Misleadingly named.** `p_mode := 'direct'` + non-null `p_source_type` ⇒ **zero points
  deducted**, just writes `reward_redemptions_ledger` row. This is the free-grant path.
- Default mode (`calc`) checks balance and burns points via the chokepoint.
- `p_mode := 'direct'` validates the source: for `p_source_type='mission'` it requires an
  unclaimed `mission_log_completion`; for `'manual'` a pending `manual_currency_request_ledger`;
  **for any other source_type it passes through (`v_source_valid := TRUE`)** — so `'checkin'`,
  `'amp'`, `'spin_wheel'` etc. are fine.
- Return on success: `{ success:true, title, data:{ redemptions:[...], wallet_ledger_id, ... } }`.

```
fn_execute_amp_action(
  p_action_type text, p_user_id uuid, p_merchant_id uuid, p_params jsonb DEFAULT '{}',
  p_workflow_id uuid DEFAULT NULL, p_node_id uuid DEFAULT NULL, p_inngest_run_id text DEFAULT NULL
) -> jsonb
```

Other chokepoints in the family (for reference): `chokepoint_post_purchase_event`,
`chokepoint_post_tier_change`, `chokepoint_post_user_event`, `fn_chokepoint_emit_event(p_topic,
p_partition_key, p_payload) -> bigint`.

### 2.4 Earn factor reality

- **No** `chokepoint_post_earn_factor` exists. **No** dedicated single-user push function.
- `refresh_earn_factor_users[_with_log]` = bulk backfill, not single push.
- The ONLY single-user push pattern is AMP's `assign_earn_factor` direct INSERT into
  `earn_factor_user` (with `source_type`, `source_id`, `window_end`). The dispatcher follows
  this pattern. No trigger on `earn_factor_user` (verified empty).

### 2.5 Existing `checkin` family (Phase 5 builds on this)

- `checkin` — campaign header. Cols incl: `frequency_type` (enum `checkin_frequency`:
  `daily`|`weekly`), `timezone`, `enable_time_window`, `window_start_time`/`window_end_time`,
  `max_streak_days` (default 365), `window_start`/`window_end` (timestamptz campaign bounds),
  `require_condition_match`, `active_status`.
- `checkin_conditions` — one outcome per row: `streak_day_start`, `streak_day_end`,
  `is_milestone`, `priority`, `allowed_tier_ids[]`, `allowed_user_types[]`, `outcome_entity`
  (enum `checkin_outcome_type`: `points`|`tickets`|`reward`|`earn_factor`), `entity_id`,
  `outcome_amount`.
- `checkin_streaks` — per-user state: `current_streak`, `longest_streak`, `total_checkins`,
  `last_checkin_date`, `last_checkin_timestamp`, `next_deadline`, `current_condition_id`.
- `checkin_ledger` — immutable per-day log: `checkin_date`, `streak_day`, `condition_id`,
  `outcome_entity`, `entity_id`, `outcome_amount`, `outcome_transaction_id`.
- Function `process_checkin(p_user_id, p_merchant_id, p_checkin_id) -> jsonb` — validates
  window, dedup (1/day), computes streak, matches ONE condition, dispatches ONE outcome,
  updates streak + ledger.

### 2.6 Mission family (Phase 3 touches this)

- `mission`, `mission_conditions`, `mission_outcomes` (cols: `outcome_type` enum
  `mission_outcome_type` = points|tickets|reward, `amount`, `entity_id`, `milestone_level`),
  `mission_log_completion`, `mission_log_outcome_distribution` (the per-feature audit table
  to be frozen), `mission_progress`, `mission_limit_claim`, etc.
- `fn_process_mission_outcomes(p_user_id, p_mission_id, p_merchant_id) -> boolean` — iterates
  unclaimed completions, for each iterates `mission_outcomes`, dispatches, writes
  `mission_log_outcome_distribution`, then marks completions claimed and bumps
  `mission_progress` counters.

---

## 3. Enums

**New:** `outcome_type_enum` = `points | tickets | reward | earn_factor`.
- Start minimal. `tag` / `persona` are AMP-shell concerns (stay in `fn_execute_amp_action`,
  NOT routed through the dispatcher) — do **not** add them to this enum unless a second caller
  needs them.
- Do **not** add `discount_pct` / `discount_fixed` / `product` — those are event_promo shapes,
  out of scope.

Existing enums to reuse: `currency`, `wallet_transaction_source_type`, `currency_component`,
`currency_transaction_type`, `checkin_outcome_type`, `mission_outcome_type`.

> **CHECK before Phase 1:** does `wallet_transaction_source_type` already contain `'checkin'`,
> `'mission'`, `'amp'`, `'campaign'`, `'spin_wheel'`? `fn_dispatch_outcome` casts `p_source_type`
> to this enum for the chokepoint call. Query:
> ```sql
> SELECT e.enumlabel FROM pg_type t JOIN pg_enum e ON e.enumtypid=t.oid
> WHERE t.typname='wallet_transaction_source_type' ORDER BY e.enumsortorder;
> ```
> If a needed label is missing, `ALTER TYPE ... ADD VALUE` (needs approval). AMP uses `'amp'`,
> check-in currently uses `'campaign'`, mission uses `'mission'`.

---

## 4. Phase 1 — Foundation (additive, no behavior change)

### 4.1 Table `outcome_distribution_log`

```sql
CREATE TABLE public.outcome_distribution_log (
  id                    uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id               uuid NOT NULL,
  merchant_id           uuid NOT NULL,
  source_type           text NOT NULL,          -- 'mission'|'checkin'|'amp'|'spin_wheel'|...
  source_id             uuid,                    -- campaign/mission/checkin id
  outcome_type          outcome_type_enum NOT NULL,
  entity_id             uuid,                    -- reward_id | ticket_type_id | earn_factor_id | NULL
  amount                numeric,
  wallet_ledger_id      uuid,                    -- set for points/tickets
  redemption_id         uuid,                    -- set for reward
  earn_factor_user_id   uuid,                    -- set for earn_factor
  success               boolean NOT NULL DEFAULT true,
  error_message         text,
  distribution_metadata jsonb DEFAULT '{}'::jsonb,
  distributed_at        timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX idx_odl_user_source ON public.outcome_distribution_log (user_id, source_type, source_id);
CREATE INDEX idx_odl_source ON public.outcome_distribution_log (source_type, source_id);
CREATE INDEX idx_odl_distributed_at ON public.outcome_distribution_log (distributed_at);
```
- RLS / grants: match sibling log tables (e.g. `mission_log_outcome_distribution`). Check its
  RLS before creating (likely service-role / SECURITY DEFINER write only, admin read via BFF).

### 4.2 Function `fn_dispatch_outcome`

```
fn_dispatch_outcome(
  p_user_id      uuid,
  p_merchant_id  uuid,
  p_outcome_type outcome_type_enum,
  p_entity_id    uuid,                 -- reward_id | ticket_type_id | earn_factor_id | NULL
  p_amount       numeric,
  p_source_type  text,                 -- free text, cast to wallet_transaction_source_type for currency
  p_source_id    uuid,
  p_metadata     jsonb DEFAULT '{}'::jsonb,   -- {window_days, dedup_key, description, ...}
  p_dedup_key    text DEFAULT NULL
) RETURNS jsonb   -- { success, outcome_type, transaction_id, distribution_id, error }
```
SECURITY DEFINER. Logic (lifted from `fn_execute_amp_action`, AMP-specifics stripped):

- **points**: amount>0 guard; `v_ledger_id := chokepoint_post_wallet_transaction(p_user_id,
  'points', p_source_type::wallet_transaction_source_type, 'base', 'earn', p_amount::int,
  coalesce(p_source_id, p_user_id), p_merchant_id, coalesce(metadata.description,'...'),
  metadata||{source,dedup_key}, NULL, p_dedup_key)`. `transaction_id := v_ledger_id`.
- **tickets**: amount>0 guard; resolve `ticket_type_id := p_entity_id` (or
  metadata.ticket_type_id); validate exists+active in `ticket_type` for merchant; chokepoint
  with currency `ticket`, `p_target_entity_id := ticket_type_id`. `transaction_id := ledger_id`.
- **reward**: `v_res := redeem_reward_with_points(p_reward_id := p_entity_id,
  p_quantity := coalesce(p_amount,1)::int, p_user_id := p_user_id, p_merchant_id := p_merchant_id,
  p_mode := 'direct', p_source_type := p_source_type, p_source_id := p_source_id)`. On
  `success=false` return it as-is. `redemption_id := (v_res->'data'->'redemptions'->0->>'redemption_id')::uuid`.
- **earn_factor**: `window_end := now() + (coalesce(metadata->>'window_days','30')||' days')::interval`;
  `INSERT INTO earn_factor_user (earn_factor_id, user_id, merchant_id, window_end, source_type,
  source_id) VALUES (p_entity_id, p_user_id, p_merchant_id, window_end, p_source_type, p_source_id)
  RETURNING id`. (Check `earn_factor_user` for an upsert constraint — current check-in code uses
  `ON CONFLICT (user_id, earn_factor_id) DO UPDATE SET window_end`; AMP does plain INSERT.
  Decide one; prefer the AMP plain-insert unless a unique constraint forces upsert — verify
  constraints first.)
- **Always**: insert one `outcome_distribution_log` row (success or failure, with
  `error_message` on failure). Return uniform JSON.
- No `workflow_log` write, no cost normalization here — those stay in the AMP shell.

### 4.3 Phase 1 smoke tests (no caller refactor yet)

Call `fn_dispatch_outcome` directly via `execute_sql` for each type against a known test
user/merchant; verify wallet/reward/earn_factor side effects + one `outcome_distribution_log`
row each. Extract results to text (don't dump).

---

## 5. Phase 2 — Refactor `fn_execute_amp_action` to delegate (BACKWARD COMPATIBLE)

**Signature unchanged. Return shapes unchanged. workflow_log unchanged.** Only the *internals*
of the five outcome branches change to call `fn_dispatch_outcome`, then re-wrap the result into
the **exact** legacy return shape the FE/Inngest expect.

### 5.1 Per-action return contract that MUST be preserved verbatim

These are the JSON keys current callers read — the dispatcher returns generic keys, so the AMP
shell must map back:

- `award_points` → `{ success, ledger_id, points_awarded, dedup_key }`
- `award_tickets` → `{ success, ledger_id, tickets_awarded, ticket_type_id, dedup_key }`
- `award_currency` → `{ success, ledger_id, amount, currency, ticket_type_id, dedup_key }`
- `push_reward` → returns the raw `redeem_reward_with_points` jsonb (pass-through). Preserve.
- `assign_earn_factor` → `{ success, earn_factor_id, window_end }`
- `assign_tag` → `{ success, tag_id }`  (STAYS in shell, unchanged)
- `remove_tag` → `{ success, tag_id, removed }`  (STAYS, unchanged)
- `assign_persona` → `{ success, persona_id, previous_persona_id }`  (STAYS, unchanged)
- `submit_form` → `{ success, form_id, submission }`  (STAYS, unchanged)
- `add_to_audience` / `remove_from_audience` → `{ success, audience_id, ... }`  (STAYS)
- unknown action → `{ success:false, error:'Unknown action type: X' }`  (unchanged)

Mapping approach in shell: call `fn_dispatch_outcome`, read `transaction_id` →
re-expose as `ledger_id` / build `points_awarded` etc. from the original `p_params` so the
output bytes match today's. **The `v_cost` / `v_entity_type` / `v_entity_id` variables that feed
cost normalization must still be set** exactly as before each branch (they currently are set
inside each branch — keep that, or have the shell set them from the action type + params).

### 5.2 What stays in the AMP shell (do NOT route through dispatcher)

`assign_tag`, `remove_tag`, `assign_persona`, `submit_form`, `add_to_audience`,
`remove_from_audience`, the `entity_cost_normalization` tail, the `workflow_log` insert(s), the
`dedup_key` resolution, and the exception handler.

### 5.3 Phase 2 verification (backward-compat gate)

- Capture BEFORE outputs: run `fn_execute_amp_action` for every action type on a test user,
  snapshot the returned jsonb. (Or read current behavior from `workflow_log` history.)
- After refactor, run the same calls; **diff the returned jsonb key-by-key — must be identical**
  for all action types.
- Verify `workflow_log` still gets a row per action with same `cost`/`normalized_cost`/`status`.
- Verify `outcome_distribution_log` now ALSO gets a row for the five outcome actions.
- Run at least one real AMP workflow end-to-end via Inngest path if a staging trigger exists.

---

## 6. Phase 3 — Refactor mission to dispatcher (SYNC COLLAPSE)

- In `fn_process_mission_outcomes`, replace the reward branch AND the `net.http_post →
  publish-currency-event` currency branch with one `fn_dispatch_outcome(..., p_source_type :=
  'mission', p_source_id := p_mission_id, p_metadata := {milestone_level, completion_id})` per
  `mission_outcomes` row.
- Stop writing `mission_log_outcome_distribution` (freeze as read-only history). New reads:
  `outcome_distribution_log WHERE source_type='mission' AND source_id=...`.
- Keep the claim-exclusivity check, claim-limit check (`fn_check_claim_limits`), the
  `UPDATE mission_log_completion SET is_claimed=true`, and the `mission_progress` counter bumps —
  those are mission mechanics, not outcome dispatch.
- **Behavior change (approved):** currency now synchronous via chokepoint instead of async edge
  fn. **CHANGELOG must note this.** Instrument: time `fn_process_mission_outcomes` before/after
  on a milestone mission with multiple outcomes; watch for lock-duration regressions in tight
  batch loops (`process_mission_evaluation_batch`).
- Confirm nothing else depends on `publish-currency-event` being invoked by missions (grep
  `REGISTRY_RENDER.md` for the edge fn; check if other callers remain — if mission was its only
  caller, note it as now-orphaned but DO NOT delete in this phase).

### 6.1 Phase 3 verification
Claim one standard mission and one milestone mission; verify wallet updates, reward ledger
rows, `outcome_distribution_log` rows with correct `wallet_ledger_id`/`redemption_id`, and
`mission_progress` counters advance exactly as before.

---

## 7. Phase 4 — Refactor check-in to dispatcher (fixes 2 latent bugs)

- `process_checkin` STEP 8 CASE block → one `fn_dispatch_outcome(..., p_source_type :=
  'checkin', p_source_id := p_checkin_id, p_metadata := {streak_day, condition_id,
  window_days})` call.
- **Bug fix 1 (reward):** current positional call `redeem_reward_with_points(p_user_id,
  reward_id, 1, null)` puts `null` in `p_merchant_id` → falls to `calc` mode → would try to
  burn points. Dispatcher always uses `p_mode:='direct'`. Fixed.
- **Bug fix 2 (earn_factor):** current hardcoded `now() + 7 days`. Dispatcher uses
  `metadata.window_days` (default 30). Check-in should pass an explicit window if product wants
  ≠30; otherwise default. (Confirm desired check-in earn_factor window with product — default
  30 unless told.)
- Keep STEP 1–7 (validation, dedup, streak math, condition match) and STEP 9–11 (streak update,
  ledger insert, return). The `checkin_ledger.outcome_transaction_id` can be set from the
  dispatcher's returned `transaction_id`/`redemption_id` for continuity.

### 7.1 Phase 4 verification
Process one check-in for each outcome type; verify side effects + `outcome_distribution_log`
row + `checkin_ledger`/`checkin_streaks` update unchanged.

---

## 8. Phase 5 — New check-in backend (the original feature request) — FINAL FLAT DESIGN

**Decisions locked with user (2026-06-28):**
- Dispatcher is built: `fn_dispatch_outcome(...)` — check-in calls it directly, no stub.
- Earn factor window handled by dispatcher via `p_metadata->>'window_days'` (default 30).
- **DROP `checkin_conditions` clean** (treat check-in as a new feature, no data to preserve).
- **DROP `checkin_streaks`** — compute streak / longest / total / next-deadline from `checkin_ledger` at read time.
- **No parent/child split** — eligibility + window live on `checkin`; outcomes live on `checkin_outcomes`. One table per concern.
- Eligibility modeled after `reward_master` (`allowed_tier`, `allowed_persona`, `allowed_tags`, `allowed_birthmonth` arrays).
- Participation limits reuse the central `transaction_limits` table (`entity_type='checkin'`). No new `checkin_limit_claim` table.

### 8.1 Condition kinds supported (no over-engineering)

1. **consecutive** (default) — `streak_milestone` outcomes fire when streak day is within `[streak_day_start, streak_day_end]`. `every_checkin` outcomes fire on each valid check-in.
2. **fixed_period_count** — "X check-ins within [period_start, period_end]". `period_milestone` outcomes fire when the running count within `[period_start, period_end]` hits `period_count_target`.
3. **rolling_period_count** — "X check-ins within any rolling N days". `period_milestone` outcomes fire when running count within the trailing `rolling_window_days` hits `period_count_target`.

### 8.2 Schema

**`checkin` (campaign header)** — existing columns + new:

New (eligibility, mirrors `reward_master`):
- `allowed_tier uuid[]`, `allowed_persona uuid[]`, `allowed_tags uuid[]`, `allowed_birthmonth int[]`

New (condition config):
- `condition_type text NOT NULL DEFAULT 'consecutive'`  (values: consecutive | fixed_period_count | rolling_period_count — validated in process_checkin, not via DB enum)
- `period_start timestamptz`, `period_end timestamptz` (for fixed_period_count)
- `rolling_window_days int` (for rolling_period_count)
- `period_target_count int` (the "X" in count-based)

Existing (kept): `frequency_type checkin_frequency`, `timezone`, `enable_time_window boolean`,
`window_start_time time`, `window_end_time time`, `max_streak_days int default 365`,
`window_start timestamptz`, `window_end timestamptz`, `require_condition_match boolean`,
`active_status boolean default true`, `name`, `description`, `merchant_id`, `id`, `created_at`,
`updated_at`.

> Workspace convention: `condition_type` and `trigger_type` are **text**, not DB enums. Value correctness is enforced by `process_checkin`'s switch logic. Renamed from `condition_kind` → `condition_type` (matches `*_type` suffix convention).

**New table `checkin_outcomes`** (replaces `checkin_conditions`):
- `id uuid PK`, `merchant_id uuid NOT NULL`, `checkin_id uuid NOT NULL FK→checkin`
- `outcome_type outcome_type_enum NOT NULL` (reuses the dispatcher's enum)
- `entity_id uuid` (reward_id | ticket_type_id | earn_factor_id | NULL for points)
- `amount numeric`
- `trigger_type text NOT NULL DEFAULT 'every_checkin'`  (values: every_checkin | streak_milestone | period_milestone — text, not enum)
- `streak_day_start int`, `streak_day_end int` (only for `streak_milestone`)
- `period_count_target int` (only for `period_milestone`)
- `priority int DEFAULT 100`, `is_milestone boolean DEFAULT false`, `active_status boolean DEFAULT true`
- `created_at`, `updated_at`
- RLS merchant_isolation + `set_updated_at` trigger.

**`checkin_ledger`** — unchanged. Source of truth for all streak/period computations.

**`transaction_limits`** — reuse as-is. `ALTER TYPE entity_type ADD VALUE 'checkin'` (if not
already present — VERIFY before adding). Participation limits stored with `entity_type='checkin'`,
`entity_id=checkin_id`, `scope in ('user','total')`, `metric='quantity'`, `count`, `time_unit`,
`time_value`.

**DROP**: `checkin_conditions`, `checkin_streaks`. Both clean (no migration).

### 8.3 Functions (this thread = backend only)

**Rewrite `process_checkin(p_user_id, p_merchant_id, p_checkin_id) -> jsonb`:**

1. Validate campaign (active, within `window_start`/`window_end`, time-of-day window if enabled).
2. Eligibility check vs `allowed_tier/persona/tags/birthmonth` (lift from `redeem_reward_with_points` calc-mode block).
3. Dedup: one check-in per user per day per campaign (query `checkin_ledger`).
4. **Compute streak from ledger** (replaces `checkin_streaks` read):
   - For `frequency_type='daily'`: streak = (last ledger `checkin_date` = today − 1) ? prev_streak+1 : 1.
   - For `frequency_type='weekly'`: streak = (last ledger `checkin_date` ≥ today − 7) ? prev_streak+1 : 1.
   - prev_streak computed by walking back the ledger from the most recent prior entry.
5. **Compute period count from ledger** (only for fixed/rolling kinds):
   - fixed: `count(*) FROM checkin_ledger WHERE user_id AND checkin_id AND checkin_date BETWEEN period_start AND period_end`.
   - rolling: `count(*) FROM checkin_ledger WHERE user_id AND checkin_id AND checkin_timestamp ≥ now() − rolling_window_days * interval '1 day'`.
6. **Enforce participation limits** via `transaction_limits` (mirror the reward-limit check in `redeem_reward_with_points`): scope=user counts that user's check-ins, scope=total counts all users' check-ins for the campaign.
7. **Match outcomes**:
   - All `every_checkin` outcomes fire.
   - For `consecutive`: any `streak_milestone` outcome whose `[streak_day_start, streak_day_end]` contains the new streak.
   - For `fixed_period_count` / `rolling_period_count`: any `period_milestone` outcome whose `period_count_target` equals the new count (fire-once — guard against re-fire by checking ledger).
8. **Loop matched outcomes**, call `fn_dispatch_outcome(p_user_id, p_merchant_id, outcome_type, entity_id, amount, p_source_type:='checkin', p_source_id:=p_checkin_id, p_metadata:={streak_day, period_count, condition_type})` for each. Capture `transaction_id` per outcome.
9. **Insert one `checkin_ledger` row** (streak_day, matched outcome ids + dispatched transaction ids in jsonb).
10. Return `{success, streak_day, total_checkins, longest_streak, outcomes:[...], next_checkin}` — all computed values, no `checkin_streaks` write.

**Rewrite `get_user_checkin_status(p_user_id, p_merchant_id, p_checkin_id) -> jsonb`:**
- Load campaign.
- Compute current_streak / longest_streak / total_checkins / last_checkin_date / next_deadline
  from `checkin_ledger` in one windowed query (no streaks table read).
- Return eligibility, current progress vs condition target (for FE progress bars), next-deadline.

**New helper `fn_compute_checkin_streak(p_user_id, p_checkin_id) -> table(streak int, longest int, total int, last_date date, next_deadline timestamptz)`** — pure SQL function over `checkin_ledger`; called by both `process_checkin` and `get_user_checkin_status` so the streak math has one definition.

### 8.4 Scope boundaries (this thread)

**IN:** schema migration, `process_checkin` rewrite, `get_user_checkin_status` rewrite,
`fn_compute_checkin_streak` helper, `transaction_limits` integration, registry + changelog.
**OUT:** admin BFFs (`bff_upsert_checkin*`, `bff_get_checkin_details`, `bff_list_checkins`),
FE, full `Checkin.md` requirement doc, event_promo/referral migration.

---

## 9. Phase 6 — Future features

Spin wheel and any new campaign: pick outcome row(s) → call `fn_dispatch_outcome`. No new
dispatch logic. (No work this thread.)

---

## 10. Scope boundaries

**IN scope (this thread):** Phases 1–4 (dispatcher + AMP/mission/check-in refactors), then
Phase 5 (check-in condition-type engine). All DB-only.

**OUT of scope:** event_promo migration, referral migration, deleting `publish-currency-event`,
check-in FE/BFF/admin UI, spin wheel.

**Prohibited without explicit per-step approval:** every `apply_migration`, every `ALTER TYPE`,
freezing/altering existing tables. Present the migration SQL and wait for "approved."

---

## 11. Docs & registry updates (per `06-update-docs.mdc` — same session as changes)

- `requirements/REGISTRY_SUPABASE.md`: add `outcome_distribution_log`, `fn_dispatch_outcome`,
  `outcome_type_enum`; (Phase 5) `checkin_progress`, `checkin_limit_claim`,
  `checkin_condition_outcomes`. (Note: `condition_type` and `trigger_type` are **text**, not enums — no enum type to register.) Use the registry-regenerate skill if
  doing many at once.
- `requirements/CHANGELOG.md`: one line per phase. **Flag the mission sync-collapse explicitly.**
- Requirement docs: grep-first, scoped reads only — update the Mission outcomes section,
  Check-in doc, and AMP actions doc to reference the shared dispatcher.

---

## 12. NEXT EXACT STEP for the new thread

1. Run the §3 enum check query for `wallet_transaction_source_type` labels AND verify
   `earn_factor_user` unique constraints (`SELECT conname, pg_get_constraintdef(oid) FROM
   pg_constraint WHERE conrelid='public.earn_factor_user'::regclass;`) AND read
   `mission_log_outcome_distribution` RLS to mirror for the new log table — batch these three.
2. Draft the Phase 1 migration (enum + `outcome_distribution_log` + `fn_dispatch_outcome`),
   present the SQL, and **wait for approval** before `apply_migration`.
3. Proceed phase by phase; run each phase's verification before moving on; backward-compat diff
   gate (§5.3) is a hard stop for Phase 2.

---

## 13. Critical context (UUIDs/names the new thread needs)

- Project ID: `wkevmsedchftztoolkmi`.
- Functions to read in full at implementation time (bodies already summarized above; re-fetch
  only the one being edited): `fn_execute_amp_action`, `fn_process_mission_outcomes`,
  `process_checkin`, `redeem_reward_with_points`, `chokepoint_post_wallet_transaction`.
- AMP source_type literal = `'amp'`; mission = `'mission'`; check-in currently = `'campaign'`
  (decide whether to switch check-in to `'checkin'` — needs the enum value to exist).
- AMP earn_factor default window = 30 days; check-in current (buggy) = 7 days.
- The two check-in latent bugs (reward positional call, 7-day hardcode) are FIXED automatically
  by routing through the dispatcher — call this out in CHANGELOG.
