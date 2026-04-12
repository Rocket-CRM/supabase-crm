# Critical Bug Fixes Log

---

## 2026-03-01 — Wallet Deduplication & Data Integrity

**Triggered by**: Ajinomoto wallet balance vs. ledger mismatch report
**Scope**: Database functions, triggers, constraints, and 6 Inngest edge functions

### Root Cause Analysis

Investigation of the Ajinomoto wallet discrepancy (1,423 of 1,865 wallets mismatched) revealed three systemic bugs and one cleanup issue across the currency/wallet system.

### Bug 1 — Duplicate Ledger Entries from Bulk Import (Inngest Retry)

**Impact**: 1,422 phantom ledger entries inflating Ajinomoto ledger by ~455M points (wallets correct, ledger wrong)

**Root cause**: The `inngest-bulk-import-currency-serve` edge function processed all rows in a single Inngest step. When the Supabase Edge Function hit its 60-second timeout, the database RPC completed successfully but Inngest never received the acknowledgment. Inngest retried, and the step re-executed — writing a second set of ledger entries.

The `dedup_key` mechanism that should have prevented this was broken in two ways:
1. The trigger formula `tier_{user_id}_{merchant_id}` was too coarse — identical for every transaction of a user
2. The index on `dedup_key` was non-unique — duplicates were silently accepted

### Bug 2 — Purchase Currency Awarded Multiple Times (CDC Replay)

**Impact**: 4 users over-awarded by ~4.36M points in actual wallet balance

**Root cause**: The CDC consumer (Kafka on Render) replayed `purchase_ledger` INSERT events when it lost its LSN checkpoint position, re-emitting `currency/award` Inngest events for already-processed purchases. The `inngest-currency-serve` edge function had no idempotency key and no check for whether a purchase had already been awarded.

Evidence: Same purchase triggered 4-6 separate Inngest workflow runs across different days (Feb 16-23), each with a unique `workflow_run_id`, all completing successfully.

### Bug 3 — Balance Overwrite in Manual Import (Historical, Already Fixed)

**Impact**: 25 users lost 1,000 points each (25K total)

**Root cause**: A previous version of `post_wallet_transaction` SET the wallet balance instead of ADDING to it during a second manual import batch on Feb 9. The function has since been corrected (current version correctly uses `balance_before + signed_amount`).

**Status**: Code already fixed. Data remediation pending.

### Cleanup — Duplicate Purchase Import Edge Function

**Impact**: Potential double-execution on every purchase import

Two edge functions (`inngest-bulk-import-serve` and `inngest-bulk-import-purchase-serve`) with identical business logic both listened to the `import/bulk-purchases` event under different Inngest app IDs, causing both to fire for every purchase import.

---

## Fixes Deployed

### Database Layer

| Change | Migration | Description |
|--------|-----------|-------------|
| `set_dedup_key` trigger rewritten | `fix_dedup_key_trigger_and_post_wallet` | Only generates key when caller doesn't provide one. New formula: `{source_type}_{source_id}_{user_id}_{merchant_id}_{component}_{transaction_type}` |
| `post_wallet_transaction` updated | `fix_dedup_key_trigger_and_post_wallet` | New `p_dedup_key` parameter — callers pass explicit keys for multi-entry scenarios (e.g., multiple bonus lines from one purchase) |
| Old function overload removed | `drop_old_post_wallet_transaction_overload` | Removed ambiguous 11-parameter version, keeping only the 12-parameter version with `p_dedup_key` |
| Existing dedup_keys backfilled | `backfill_dedup_keys_and_add_unique_constraint` | All `tier_*` keys replaced with new formula + sequence number for uniqueness |
| UNIQUE constraint on `dedup_key` | `backfill_dedup_keys_and_add_unique_constraint` | `idx_wallet_ledger_dedup_key` converted from regular index to UNIQUE — physically prevents duplicate wallet transactions |
| `wallet_health_check()` function | `add_wallet_health_check_function` | One-call monitoring: returns any merchant with wallet balance vs. ledger drift |

### Edge Functions (Inngest)

| Function | Version | Changes |
|----------|---------|---------|
| `inngest-currency-serve` | v41 | Added `idempotency` key (`source_type-source_id-user_id`), "already awarded" ledger check before processing, explicit `dedup_key` per award step (`{source_type}_{source_id}_{user_id}_award_{index}`) |
| `inngest-bulk-import-currency-serve` | v13 | Added `idempotency` (`batch_id`), chunked from single step → 100 rows/step with progress tracking |
| `inngest-bulk-import-customers-serve` | v11 | Added `idempotency` (`batch_id`), chunked from single step → 100 rows/step with progress tracking |
| `inngest-bulk-import-purchase-serve` | v12 | Added `idempotency` (`batch_id`), chunked from single step → 50 purchases/step with progress tracking |
| `inngest-bulk-import-redemptions-serve` | v4 | Added `idempotency` (`batch_id`). Already had chunking (500/step) |
| `inngest-bulk-import-serve` | v27 → deleted | Neutralized (no-op returning 410), then deleted from dashboard. Was duplicate of purchase-serve |

### Protection Layers (Defense in Depth)

```
Layer 1: Inngest idempotency key
  → Drops duplicate events within 24-hour window (zero compute cost)

Layer 2: Application-level check (currency-award only)  
  → Queries wallet_ledger for existing earn entries before calculating

Layer 3: Caller-provided dedup_key
  → Each award step passes a unique key like purchase_xxx_user_xxx_award_0

Layer 4: UNIQUE constraint on wallet_ledger.dedup_key
  → Database physically rejects any duplicate INSERT
```

---

## Remaining Work

### Data Remediation (Phase 1 — not yet executed)

- **1,422 phantom ledger entries** (Ajinomoto): Delete duplicate entries from manual batch `ebecfaa8` second run
- **4 over-awarded users** (Ajinomoto): Correct wallet balances from purchase re-processing
- **25 users missing 1,000 points** (Ajinomoto): Manual adjustment +1,000 each
- **New CRM**: 14 wallets with balance but missing ledger entries (separate investigation needed)

### Monitoring

Run `SELECT * FROM wallet_health_check();` periodically to detect any future drift. Returns merchants with discrepant wallets, count, and total drift amount.

---

## Inngest Serve Functions Inventory

| Edge Function | Inngest App | Functions | Events |
|---|---|---|---|
| `inngest-serve` | `crm-workflows` | `workflow-executor` | `amp/workflow.trigger` |
| `inngest-currency-serve` | `crm-currency-system` | `currency-award`, `currency-reversal` | `currency/award`, `currency/reverse` |
| `inngest-tier-serve` | `crm-tier-service` | `tier-upgrade` | `tier/upgrade` |
| `inngest-mission-serve` | `crm-mission-service` | `mission-evaluate`, `mission-accept`, `mission-rolling-reset`, `mission-claim` | `mission/*` |
| `inngest-marketplace-serve` | `marketplace-serve` | `process-shop-orders` | `marketplace/order-received` |
| `inngest-bulk-import-currency-serve` | `crm-bulk-import-currency` | `bulk-import-currency` | `import/bulk-currency` |
| `inngest-bulk-import-customers-serve` | `crm-bulk-import-system` | `bulk-import-customers` | `import/bulk-customers` |
| `inngest-bulk-import-purchase-serve` | `crm-bulk-import-purchases` | `bulk-import-purchases-v2` | `import/bulk-purchases` |
| `inngest-bulk-import-redemptions-serve` | `crm-bulk-import-redemptions` | `bulk-import-redemptions` | `import/bulk-redemptions` |

**Not using Inngest**: Code import (Render direct-to-PG service at `code-import.onrender.com`)

---

## 2026-03-02 — Currency/Wallet Feature Audit Fixes

**Triggered by**: Full read-only code review of Currency.md requirements vs. actual implementation
**Scope**: 7 database function rewrites, 1 edge function redeploy, 1 column DROP, 1 schema metadata update

### Issues Discovered

| # | Function | Severity | Issue |
|---|----------|----------|-------|
| 1 | `process_currency_expiry` | **Critical** | Balance never decremented. `expired_amount = deductible_balance` was SET before the balance subtraction query ran, making `deductible_balance - expired_amount = 0` for every row. Expiry was logging success but users kept full access to expired currency. |
| 2 | `post_wallet_transaction` | **High** | Race condition on first wallet creation. Two concurrent transactions for a new user both got NULL from SELECT FOR UPDATE (no row to lock), both ran INSERT ON CONFLICT DO NOTHING, then both UPDATE'd based on `balance_before=0` — one transaction's balance silently lost. |
| 5 | `inngest-currency-serve` (reversal) | **High** | No proportional reversal. 50% refund reversed 100% of currency. Event carried no `refund_percentage` field and workflow never looked up historical metadata. |
| 6 | `calc_currency_core` | **Med** | Non-stackable amount isolation missing. Requirements say product-specific multipliers consume their portion and transaction-wide multipliers apply to remainder. Code picked best multiplier per item — a 5x transaction-wide overrode a 3x product-specific on shoes instead of each applying to its own portion. |
| 7 | `get_eligible_earn_factors_core` | **Med** | Not using materialized views. Queried raw `earn_factor` + `earn_factor_group` with live join despite MVs being refreshed every 5 min by pg_cron. |
| 8 | `post_wallet_transaction` + 7 readers | **Med** | Dual-write drift. Points balance written to both `user_wallet` and `user_accounts.points_balance`. But expiry, ticket transactions, and redemptions only updated `user_wallet`, causing permanent drift. |
| 9 | `should_run_expiry_today` | **Low** | Hardcoded `v_month IN (3, 6, 9, 12)` for quarterly expiry regardless of merchant fiscal year. |

### Fixes Deployed

#### Database Functions

| Migration | Function | What Changed |
|-----------|----------|--------------|
| `fix_process_currency_expiry_balance_deduction` | `process_currency_expiry` | Captures deduction amounts into temp table BEFORE marking records expired. Balance subtraction now reads pre-captured values. |
| `fix_post_wallet_transaction_race_condition` | `post_wallet_transaction` | INSERT ON CONFLICT DO NOTHING runs BEFORE SELECT FOR UPDATE. Row always exists when lock is acquired — no race window. |
| `fix_post_wallet_transaction_keep_dual_write` | `post_wallet_transaction` | Intermediate version keeping dual-write while readers were audited. |
| `fix_remove_dual_write_user_accounts_points_balance` | `post_wallet_transaction` | Dual-write to `user_accounts.points_balance` removed. All 7 reader functions confirmed to already use `user_wallet`. |
| `fix_should_run_expiry_today_fiscal_quarters` | `should_run_expiry_today` | Quarterly check uses `((month - fiscal_year_end_month + 12) % 3) = 0` per merchant instead of hardcoded calendar quarters. |
| `fix_get_eligible_earn_factors_core_use_mv` | `get_eligible_earn_factors_core` | Public factors from `mv_earn_factors_complete`, personalized offers from `mv_earn_factor_users`. Eliminates live join on hot path. |
| `fix_calc_currency_core_nonstackable_amount_isolation` | `calc_currency_core` | Non-stackable groups: product-specific multipliers process first, mark items consumed. Transaction-wide multipliers apply only to unconsumed remainder. Stackable groups unchanged. |
| `fix_bff_get_workflow_collections_remove_points_balance` | `bff_get_workflow_collections` | Removed `points_balance` from `user_accounts` field metadata since column was dropped. |
| `drop_user_accounts_points_balance_column` | Schema DDL | `ALTER TABLE user_accounts DROP COLUMN points_balance`. All consumers already use `user_wallet`. |

#### Edge Functions

| Function | Version | What Changed |
|----------|---------|--------------|
| `inngest-currency-serve` | v42 | Reversal workflow now accepts `refund_percentage` (0–100) and `original_source_id`. Computes proportional reversal: `FLOOR(original_amount × proportion)`. Ticket balance check added (was only checking points). Full metadata trail in ledger. Backward compatible — omitting `refund_percentage` defaults to 100% full reversal. |

### Verification

- MV refresh confirmed operational: `mv_earn_factors_complete` every 5 min, `mv_earn_factor_users` every 1 min (pg_cron jobs 2 & 3)
- `user_accounts.points_balance` column confirmed dropped. Zero broken function references.
- All 14 functions that previously referenced `points_balance` verified — every one already reads from `user_wallet`

### Not Fixed (Deferred)

| # | Issue | Reason |
|---|-------|--------|
| 3 | `evaluate_earn_conditions_core` missing `exclude` flag handling | Owner fixing separately |
| 4 | `dedup_key` not always provided by non-Inngest callers | Mechanism is correct (unique index on `dedup_key`). Action: ensure other callers provide it. No schema change needed. |
| 10 | `inngest-currency-serve` timezone via static offset map (no DST) | Low risk — current merchants use Asia/Bangkok (no DST). Monitor when expanding to DST regions. |
| 11 | `reverse_points`/`reverse_tickets` hardcoded `source_type='manual'` | Low impact — these are admin-facing convenience wrappers. Core reversal path via Inngest workflow uses correct source_type. |
| 12 | `bulk_import_currency` shared `source_id` across batch rows | Low risk — each row goes through `post_wallet_transaction` which has its own dedup protection. |

### Reversal Contract (New)

To trigger a proportional reversal, the `currency/reverse` Inngest event now accepts:

```json
{
  "source_type": "purchase",
  "source_id": "refund-record-uuid",
  "user_id": "user-uuid",
  "merchant_id": "merchant-uuid",
  "refund_percentage": 50,
  "original_source_id": "original-purchase-uuid"
}
```

- `refund_percentage` (number, 0–100) — omit or pass 100 for full reversal
- `original_source_id` (UUID) — the original purchase/source ID if `source_id` is a new refund record

---

## 2026-03-01 — Mission System Audit & Fixes

**Triggered by**: Full feature audit of Mission system against `requirements/Mission.md`
**Scope**: 7 database functions, 1 Edge Function (`inngest-mission-serve` v28 → v30), 9 migrations

### Summary

Code review of the entire mission pipeline (CDC → Kafka → Inngest → PostgreSQL → BFF) uncovered 15 issues across the evaluation, progress tracking, outcome distribution, and frontend API layers. 12 were fixed in this session.

### Bug 1 — Edge Function Double-Decrement on Manual Claim (Critical)

**Impact**: Every manual mission claim drove `unclaimed_completions` negative and double-marked completions as claimed

**Root cause**: The `missionClaim` workflow in `inngest-mission-serve` called `fn_process_mission_outcomes` (which internally decrements `unclaimed_completions` and marks `mission_log_completion.is_claimed = true`), then did both operations again manually. Net effect: `unclaimed_completions` decremented twice per claim, going permanently negative.

**Fix**: Removed redundant update and completion-marking from the Edge Function. The DB function handles both atomically.

### Bug 2 — Cross-Tenant Data Leak in bff_get_user_missions (Critical)

**Impact**: An admin from Merchant A could view all user missions for Merchant B

**Root cause**: The admin authorization check only validated `auth_user_id` and `role` but did not filter by `merchant_id`. Any admin from any tenant passed the check.

**Fix**: Moved `get_current_merchant_id()` to the top of the function and added `AND merchant_id = v_merchant_id` to the admin EXISTS query.

### Bug 3 — earn_source_type Filter Ignored (High)

**Impact**: Missions targeting "points earned from purchases" also counted admin-granted points, form rewards, referral bonuses, etc.

**Root cause**: The `points_earned` branch in `fn_evaluate_mission_conditions` matched all wallet earn events regardless of source. The `earn_source_type` column (`text[]`) was in the materialized view but never checked.

**Fix**: Added array-aware filter matching the event's `source_type` against the condition's `earn_source_type[]` array, following the same pattern as the existing `ticket_type_id` filter.

### Bug 4 — OR Condition Logic Not Implemented (Medium)

**Impact**: Missions with `operator = 'OR'` conditions (any-one-completes) behaved identically to AND (all-must-complete)

**Root cause**: `fn_update_mission_progress` always used AND completion logic. The `operator` field was only used in BFF display functions for percentage calculation but never in the actual completion detection.

**Fix**: Added OR completion path — if any condition in the mission has `operator = 'OR'`, the mission completes when ANY single condition reaches its target.

### Bug 5 — trigger_mission_evaluation_realtime Broken Signature (Medium)

**Impact**: The trigger threw a runtime error on every invocation (effectively dead code)

**Root cause**: Called `fn_evaluate_mission_conditions` with wrong parameter order and types (user_id where merchant_id should be, table name as UUID, etc.). Also discarded the evaluation result without passing it to `fn_update_mission_progress`.

**Fix**: Corrected parameter order, added table-to-event-type mapping (`purchase_ledger` → `purchase`, `form_submissions` → `form_submission`), chained `fn_update_mission_progress` after evaluation, and added `accepted_at IS NOT NULL` check.

### Bug 6 — Race Condition in fn_process_mission_outcomes (Medium)

**Impact**: Concurrent manual claims could process the same completion record twice, awarding duplicate rewards

**Root cause**: The completion cursor had no row-level locking, and the final UPDATE used a subquery that could race with concurrent executions.

**Fix**: Added `FOR UPDATE` to the completion cursor. Replaced the subquery-based final UPDATE with a collected array of processed IDs (`v_processed_ids`), eliminating the race window entirely.

### Bug 7 — claim_mission_outcomes No Auth Check (Medium)

**Impact**: If exposed via RPC, any caller could claim missions on behalf of any user across any merchant

**Root cause**: The function accepted `p_user_id` without validating caller identity, admin status, or merchant scope.

**Fix**: Added `SECURITY DEFINER`, `auth.uid()` caller validation, self-or-admin authorization, and merchant context check via `get_current_merchant_id()`.

### Bug 8 — accept_mission Did Not Initialize condition_progress (Low)

**Impact**: After accepting a manual mission, the detail page showed no progress breakdown until the first qualifying event

**Root cause**: The function only set `accepted_at` and `current_target_value` (from a single condition, not the sum). `condition_progress` JSONB was left NULL. The Inngest `mission/accept` workflow initialized it properly, but the direct DB function did not.

**Fix**: Now calls `fn_initialize_condition_progress` before insert, calculates target as `SUM(target_value)` across all conditions, and on conflict preserves existing non-empty progress.

### Bug 9 — fn_batch_reset_global_missions Timeout Risk (Medium)

**Impact**: Global resets for merchants with thousands of users could timeout Supabase's statement limit, causing zero resets

**Root cause**: Single transaction iterating ALL matching records with no batch limit, no per-record error handling, and no idempotency.

**Fix (DB)**: Rewrote with `p_batch_size` parameter (default 1000), `FOR UPDATE SKIP LOCKED` for safe parallelism, per-record `BEGIN/EXCEPTION` blocks, and `period_started_at < period_boundary` idempotency filter so already-reset records are skipped.

**Fix (Inngest)**: Added `mission/batch-reset` workflow (Workflow 5) to `inngest-mission-serve`. Processes one batch per invocation, re-queues itself if `has_more = true`. Each invocation has independent retry budget (5 retries). A daily cron sends one event; the workflow self-chains until complete.

### Additional Fixes

| Function | Fix |
|---|---|
| `fn_update_mission_progress` | Standard condition progress now capped at target via `LEAST()` — prevents cosmetic >100% display |
| `fn_update_mission_progress` | `pg_advisory_xact_lock` serializes `global_completion_number` assignment per mission — prevents duplicate numbers under concurrent completions |
| `fn_update_mission_progress` | Corrected INSERT into `mission_progress` — removed `merchant_id` column reference that does not exist on the table (would have caused runtime failure) |

---

## Fixes Deployed

### Database Migrations (this session)

| Migration | Functions Changed |
|---|---|
| `fix_bff_get_user_missions_admin_scope` | `bff_get_user_missions` |
| `fix_claim_mission_outcomes_auth` | `claim_mission_outcomes` |
| `fix_trigger_mission_evaluation_realtime` | `trigger_mission_evaluation_realtime` |
| `fix_fn_update_mission_progress_multi` | `fn_update_mission_progress` |
| `fix_fn_process_mission_outcomes_locking` | `fn_process_mission_outcomes` |
| `fix_fn_evaluate_mission_conditions_earn_source_type` | `fn_evaluate_mission_conditions` |
| `fix_fn_update_mission_progress_remove_merchant_id` | `fn_update_mission_progress` (corrected previous migration) |
| `fix_fn_batch_reset_global_missions_batched` | `fn_batch_reset_global_missions` |
| `fix_accept_mission_init_progress` | `accept_mission` |

### Edge Function

| Function | Version | Changes |
|---|---|---|
| `inngest-mission-serve` | v28 → v30 | v29: Removed double-decrement in `missionClaim`. v30: Added `missionBatchReset` workflow (self-chaining batch processor for global resets) |

### Updated Inngest Serve Inventory

| Edge Function | Inngest App | Functions | Events |
|---|---|---|---|
| `inngest-mission-serve` | `crm-mission-service` | `mission-evaluate`, `mission-accept`, `mission-rolling-reset`, `mission-claim`, `mission-batch-reset` | `mission/*` |

### Not Fixed (Deferred)

| Issue | Reason |
|---|---|
| `fn_process_mission_outcomes` fire-and-forget currency via `net.http_post` | Architectural — requires compensation mechanism or sync wallet call; not a quick fix |
| `bff_claim_mission` does not enforce `claim_type = 'manual'` | Low risk — auto-claim missions rarely have stale unclaimed records |
| `bff_claim_mission` outcome summary uses 1-minute time window | Low risk — only affects response display, not actual distribution |

---

## 2026-03-02 — Reward Redemption System Audit & Fixes

**Triggered by**: Feature audit of the Reward system against `requirements/Reward.md` (v3.1)
**Scope**: 8 database functions + 1 schema change across 8 migrations

### Audit Findings

A read-only code review of the full reward/redemption function surface (12 functions) against the requirements document uncovered 14 issues. 9 were fixed in this session (8 function-level, 1 schema-level). The issues ranged from silently unenforced business rules to a security vulnerability.

### Bug 1 — Transaction Limits Never Enforced (Critical)

**Impact**: All configured redemption limits (per-user daily/weekly/monthly caps, global totals) were silently ignored

**Root cause**: The `transaction_limits` table was populated by `bff_upsert_reward_with_conditions_and_limits` when merchants configured limits through the admin UI, but `redeem_reward_with_points` never queried it. Users could redeem unlimited times regardless of configured limits.

**Fix**: Added a limit enforcement block to `redeem_reward_with_points` (mode='calc') that iterates all active limits for the reward, calculates time windows (`day`/`week`/`month`/`year`/`all_time`), respects explicit `window_start`/`window_end` bounds, counts existing redemptions using `SUM(qty)` (correctly handles multi-qty), excludes cancelled redemptions, and returns remaining count in the error response.

### Bug 2 — Stock Control Not Enforced for Non-Promo Rewards (Critical)

**Impact**: Rewards with `stock_control = true` but no promo codes could be redeemed infinitely

**Root cause**: The only stock mechanism was implicit — promo code pool size. For rewards without promo codes, `stock_control = true` had no effect. No `stock_total` column existed.

**Fix**: 
1. Added `stock_total INTEGER` column to `reward_master`
2. Added stock enforcement block to `redeem_reward_with_points`: when `stock_control = true` AND `assign_promocode = false`, checks `SUM(qty)` of non-cancelled redemptions against `stock_total`

### Bug 3 — `api_cancel_redemption` Auth Bypass (Critical)

**Impact**: Any caller able to reach the RPC endpoint could cancel any merchant's redemptions by passing an arbitrary `p_merchant_id`

**Root cause**: Function accepted `p_merchant_id` as a trusted parameter without deriving it from JWT context. Being `SECURITY DEFINER`, RLS was bypassed.

**Fix**: Function now derives merchant from `get_current_merchant_id()` (JWT) first. Falls back to trusting `p_merchant_id` only for `service_role` callers. Rejects all other unauthenticated calls. Validates `p_merchant_id` matches JWT context when both are present.

### Bug 4 — Missing Birthday Month Eligibility Check (Medium)

**Impact**: Rewards configured with `allowed_birthmonth` restrictions were redeemable by all users regardless of birth month

**Root cause**: Neither `redeem_reward_with_points` nor `check_reward_eligibility_enhanced` checked the `allowed_birthmonth` array against `user_accounts.birth_date`.

**Fix**: Added birth month validation to both functions. Extracts month from `v_user.birth_date`, compares against `v_reward.allowed_birthmonth` array.

### Bug 5 — `check_reward_eligibility_enhanced` Missing SECURITY DEFINER (Medium)

**Impact**: Inconsistent security posture — function ran with caller's permissions instead of definer's, unlike all other reward functions

**Fix**: Added `SECURITY DEFINER` to function declaration.

### Bug 6 — Inactive Rewards Visible in Catalog Cache (Medium)

**Impact**: Deactivated rewards (`active_status = false`) appeared in the customer-facing reward catalog

**Root cause**: `api_get_rewards_full_cached` filtered on `visibility` but not `active_status`.

**Fix**: Added `AND r.active_status = true` to all three query locations (main reward query, total count, per-category count).

### Bug 7 — Persona-Type Consistency Missing in Fast Points Calculator (Low)

**Impact**: Edge case where `calculate_redemption_points_fast` (used in production) could match a condition with a persona incompatible with the user's type

**Root cause**: The "full" version (`calculate_redemption_points`) called `validate_persona_type_consistency()` but the "fast" version skipped it.

**Fix**: Added the same `validate_persona_type_consistency` check to `calculate_redemption_points_fast` after finding a best match.

### Bug 8 — Promo Code Upload Duplicate Check Too Narrow (Low)

**Impact**: Codes from different sources (partners) with the same promo_code + merchant_id would bypass dedup in staging but fail on INSERT due to the actual UNIQUE constraint

**Root cause**: `bulk_upload_promo_codes_validated` duplicate check matched on `merchant_id + source_id + promo_code`, but the actual constraint is `UNIQUE(promo_code, merchant_id)`.

**Fix**: Removed `source_id` from the duplicate-marking UPDATE, aligning with the real constraint.

### Cleanup — Idempotency Dead Code (Low)

**Impact**: The `redeem_reward_with_points` idempotency check contained a stale `LIKE` pattern (`id::text LIKE p_event_id::text || '-%'`) from the old multi-qty UUID suffix approach removed in the Feb 16 fix.

**Fix**: Removed the LIKE clause. Idempotency check now uses exact `id = p_event_id` match only.

### Performance — Cache Query N+1 Optimization

**Impact**: On cache miss, `api_get_rewards_full_cached` fired 5 correlated subqueries per reward into the `translations` table (50 rewards = 250 subqueries)

**Fix**: Replaced the 5N correlated subqueries with a single CTE (`reward_trans`) that aggregates all reward translations in one pass, then LEFT JOINs to the main query. Cache structure unchanged.

---

## Fixes Deployed

### Database Layer

| Migration | Functions Modified | Description |
|---|---|---|
| `fix_cancel_redemption_auth` | `api_cancel_redemption` | JWT-first auth with service_role fallback; rejects unauthenticated callers |
| `fix_eligibility_enhanced` | `check_reward_eligibility_enhanced` | Added `SECURITY DEFINER` + `allowed_birthmonth` validation |
| `add_stock_total_column` | — (schema) | `ALTER TABLE reward_master ADD COLUMN stock_total INTEGER` |
| `fix_redeem_reward_core` | `redeem_reward_with_points` | Transaction limit enforcement, stock control, birthmonth check, idempotency cleanup |
| `fix_rewards_cache_active_status` | `api_get_rewards_full_cached` | `active_status = true` filter in all query locations |
| `fix_points_calc_fast_persona` | `calculate_redemption_points_fast` | Persona-type consistency validation added |
| `fix_promo_upload_dedup` | `bulk_upload_promo_codes_validated` | Duplicate check aligned with actual UNIQUE constraint |
| `optimize_rewards_cache_translations` | `api_get_rewards_full_cached` | 5N correlated subqueries → 1 CTE + LEFT JOIN |

### Behavioral Changes to Monitor

1. **Limits now enforce.** Merchants with configured `transaction_limits` will see them take effect immediately. Users who were previously exceeding limits (silently allowed) will now be blocked.
2. **Inactive rewards disappear from catalog.** Any reward with `active_status = false` will no longer appear in the customer-facing catalog after cache expiry (max 5 minutes).
3. **Birthday rewards now work.** Any reward with `allowed_birthmonth` set will enforce birth month matching.
4. **Cancel endpoint is secured.** External callers without valid JWT context can no longer cancel redemptions for arbitrary merchants.

### Not Modified (by design)

- `bff_upsert_reward_with_conditions_and_limits` — The `stock_total` column exists but the admin upsert function doesn't set it yet. Can be set via direct SQL or added in a follow-up.
- `admin_delete_reward` — Orphaned promo codes/redemptions after deletion (audit trail by design, low risk).
- `generate_random_redemption_code` — Random code generation with 10-retry ceiling (statistically safe at current scale).
- `allowed_type` eligibility — Intentionally removed from schema; requirements doc needs sync.

---

## 2026-03-01 — Authentication OTP Security Fixes

**Triggered by**: Feature audit of Authentication & Signup system
**Scope**: Two Supabase Edge Functions (`auth-send-otp`, `bff-auth-complete`)

### Root Cause Analysis

A read-only audit of the full auth stack (edge functions, DB functions, requirement docs) revealed two critical security vulnerabilities in the OTP verification flow that, combined, allowed unlimited brute-force of 6-digit OTP codes.

### Bug 1 — OTP Code Leaked in API Response on SMS Failure

**Impact**: Complete OTP bypass — attacker receives the OTP code directly without SMS

**Root cause**: `auth-send-otp` included `otp_code: otpCode` in the JSON response body when the downstream SMS provider (8x8) returned a failure. A `// DEV ONLY - remove in production` comment was present but the line was live in production since initial deployment.

**Attack scenario**: An attacker could trigger OTP generation for any phone number. If SMS delivery failed (natural failure or induced), the response contained the plaintext OTP. The attacker could then submit that OTP to `bff-auth-complete` and authenticate as the phone number's owner.

### Bug 2 — OTP Brute-Force Protection Non-Functional

**Impact**: Unlimited OTP guessing — the 3-attempt limit was decorative

**Root cause**: `bff-auth-complete` validated OTPs by querying `otp_requests` with both `session_id` AND `otp_code` in the WHERE clause. When the submitted code was wrong, the query returned zero rows. The code then branched to the error response **without incrementing the `attempts` counter** on the OTP record. The `attempts < 3` check existed but could never trigger because wrong guesses never incremented the counter.

Contrast with `fn_validate_otp` (DB function) which correctly fetches by `session_id` only, compares the code in PL/pgSQL, and increments attempts on mismatch.

**Attack scenario**: An attacker with a valid `session_id` could submit all 1,000,000 possible 6-digit codes without any rate limit or lockout. Combined with no per-phone OTP request throttling in `auth-send-otp`, this made phone-based authentication trivially breakable.

---

### Fixes Deployed

| Function | Version | Changes |
|----------|---------|---------|
| `auth-send-otp` | v100 → v101 | Removed `otp_code` from the SMS-failure response body. OTP is now never returned to the caller regardless of SMS delivery outcome. |
| `bff-auth-complete` | v64 → v65 | Restructured OTP validation: fetches OTP record by `session_id` only (not `otp_code`), checks `attempts >= 3` first (rejects immediately if exhausted), compares `otp_code` in application code, and **increments `attempts` on mismatch** before returning the error. Response now includes `attempts_remaining` count on failure. |

### What Changed in `bff-auth-complete` OTP Flow

**Before (broken):**
```
1. Query: SELECT * FROM otp_requests WHERE session_id=X AND otp_code=Y AND verified=false
2. If no rows (wrong code) → return error (attempts NOT incremented) ❌
3. If found and attempts < 3 → mark verified
```

**After (fixed):**
```
1. Query: SELECT * FROM otp_requests WHERE session_id=X AND verified=false
2. If no rows → return "Invalid or expired OTP"
3. If attempts >= 3 → return "Maximum OTP attempts exceeded"
4. Compare otp_code and phone in application code
5. If match → mark verified ✅
6. If mismatch → INCREMENT attempts, return error with attempts_remaining ✅
```

### What Was NOT Changed

- Already-verified OTP reuse window (5-minute grace for re-calling `bff-auth-complete`) — preserved unchanged
- All user creation, JWT generation, profile completion, and persona filtering logic — untouched
- `auth-line` edge function — no changes needed
- Database functions (`fn_validate_otp`, `bff_get_auth_config`, etc.) — no changes needed

### Remaining Auth Issues (from audit, not yet fixed)

| Issue | Severity | Status |
|-------|----------|--------|
| Access token expiry 30 days vs spec'd 24 hours | High | Unfixed — needs product decision on intended value |
| `auth-refresh` issues 15-min tokens vs 30-day from `bff-auth-complete` | High | Unfixed — inconsistent, breaks sessions after first refresh |
| No per-phone rate limit on OTP requests in `auth-send-otp` | High | Unfixed — SMS bombing still possible |
| Legacy `auth-register` / `auth-login` use hardcoded merchant registry | Med | Unfixed — new merchants can't use these endpoints |
| `auth-line-login` duplicates + bypasses standard auth flow | Med | Unfixed — alternate path skips profile completion |
| `auth-send-otp` has `verify_jwt: true` but spec says public | Med | Unfixed — works via anon key but contradicts spec |

---

## 2026-03-02 — Purchase Transaction System Audit & Fixes

**Triggered by**: Feature audit of Purchase Transaction system
**Scope**: Database functions (`refund_purchase`, `api_create_purchase`), legacy DB triggers, architecture validation

### Audit Summary

Full read-only audit of all purchase-related database functions, edge functions, and triggers against `Purchase_Transaction.md` and `Purchase_Import_System.md` requirements. Cross-referenced CDC pipeline coverage against DB trigger bindings.

### Finding 1 — Currency/Tier/Mission Triggers: Confirmed CDC Handles All Three

**Status**: No action needed

The audit initially flagged three "missing" trigger bindings on `purchase_ledger`:
- `trigger_process_purchase_currency` — function exists, not bound as trigger
- `trigger_tier_eval_on_purchase` — function doesn't exist
- `queue_mission_evaluation_batch` — function exists, not bound as trigger

**Resolution**: All three are intentionally handled by CDC → Kafka → Render Consumer → Inngest:
- **Currency**: Architecture v2.0 per `Currency.md` — CDC → CurrencyConsumer → `currency/award`
- **Tier**: Architecture v4.0 per `Tier.md` — CDC → TierConsumer → `tier/upgrade`. Trigger explicitly deprecated (Tier.md lines 1390-1400)
- **Mission**: Architecture V2 per `Mission.md` — CDC → MissionConsumer → `mission/evaluate`

### Finding 2 — `set_dedup_key` Trigger Misapplied to `purchase_ledger`

**Impact**: Potential blocking of all purchase inserts where `dedup_key` is NULL

**Root cause**: The `set_dedup_key` trigger rewrite deployed on 2026-03-01 (wallet dedup fix) was bound to `purchase_ledger` as `set_dedup_key_on_purchase`. The function references `NEW.source_type`, `NEW.source_id`, `NEW.component` — columns that exist on `wallet_ledger` but **not** on `purchase_ledger`. The `dedup_key` column on `purchase_ledger` has no default, so any INSERT without an explicit `dedup_key` would error when the trigger attempts to access non-existent columns.

**Status**: Workaround applied — `api_create_purchase` and `refund_purchase` now set `dedup_key` explicitly to bypass the trigger's NULL branch. Trigger itself still active pending removal decision. Purchases already have `transaction_number` uniqueness and don't need wallet-style dedup keys.

### Finding 3 — `refund_purchase` Function: Multiple Logic Bugs

**Impact**: Refunds not properly recorded, no currency reversal, no audit trail

**Root cause**: Function had six issues:

| Issue | Before | After |
|-------|--------|-------|
| `record_type` | Not set (defaulted to `'credit'`) | Explicitly set to `'debit'` |
| Original status validation | None | Must be `'completed'` to refund |
| `p_reason` parameter | Captured but never stored | Stored in `notes` field |
| Original transaction update | Not updated | Set to `status = 'refunded'` on full refund |
| `external_ref` | Not set | Links to original transaction ID for traceability |
| Store context | Not copied | `store_id` and `store_code` copied from original |
| `processing_method` | `'direct'` | `'skip'` (no currency calc on refund record) |

### Finding 4 — `api_create_purchase` Inserted Items with NULL `sku_id`

**Impact**: Line items with unresolved SKU codes persisted with `sku_id = NULL`, breaking product-level currency calculations

**Root cause**: The function used `LEFT JOIN` to `product_sku_master`, inserting items even when the SKU code wasn't found. Unknown SKUs were reported as warnings but still written to `purchase_items_ledger` with `NULL` sku_id.

### Finding 5 — Legacy Mission Trigger Was a No-Op

**Impact**: Wasted CPU on every purchase INSERT, no functional effect

**Root cause**: `trg_mission_eval_realtime_purchase` (AFTER INSERT on `purchase_ledger`) called `PERFORM fn_evaluate_mission_conditions(...)` which evaluates conditions but `PERFORM` discards the result. No progress update, no outcome processing. CDC → Kafka → Inngest handles the full mission evaluation pipeline.

---

### Fixes Deployed

| Change | Migration | Description |
|--------|-----------|-------------|
| `refund_purchase` rewritten | `fix_refund_purchase` | Sets `record_type='debit'`, validates original is `completed`, stores reason in `notes`, links via `external_ref`, copies store context, updates original to `refunded` on full refund, sets `processing_method='skip'` |
| `api_create_purchase` fixed | `fix_api_create_purchase_skip_unknown_skus` | Changed `LEFT JOIN` to `INNER JOIN` on SKU lookup — items with unresolved SKU codes are now skipped (not inserted with NULL). Unknown SKUs still reported in response `unknown_skus` array. Both functions also set `dedup_key` explicitly to work around the misapplied trigger. |
| Legacy mission trigger dropped | `drop_legacy_mission_trigger_on_purchase` | Removed `trg_mission_eval_realtime_purchase` from `purchase_ledger`. Mission evaluation fully handled by CDC pipeline. |

### What Was NOT Changed

- `trigger_process_purchase_currency` function — legacy artifact, not bound as trigger, CDC handles currency
- `trigger_tier_eval_on_purchase` — deprecated per Tier.md, CDC handles tier evaluation
- `queue_mission_evaluation_batch` function — not bound, CDC handles auto-mission evaluation
- `set_dedup_key_on_purchase` trigger — still active, workaround in place (pending removal decision)
- `trg_referral_purchase` trigger — legitimate, correctly processes referral rewards
- `purchase-orchestrator` edge function — has multiple issues (wrong RPC names, non-existent columns) but is a separate fix scope
- `bulk_insert_purchases_with_items` — no changes, works correctly for import path
- `calc_currency_core` / `calc_currency_for_transaction` — clean implementations, no issues found

---

## 2026-03-02 — Tier System Feature Audit & Fixes

**Triggered by**: Full read-only audit of 27 database functions + 4 edge functions against `requirements/Tier.md` v4.3
**Scope**: 8 database functions, 1 edge function, 11 issues resolved across 6 migrations + 1 edge function deployment

### Summary

A comprehensive audit of the tier system uncovered 17 issues. 11 were fixed in this session. The most critical was a broken function overload that caused every delayed tier upgrade via Inngest to silently fail.

### Bug 1 — Broken `apply_tier_upgrade` Overload (Critical)

**Impact**: Every delayed tier upgrade via Inngest silently failed or wrote stale data

**Root cause**: Two overloads of `apply_tier_upgrade` existed — a 3-argument "old" version and a 4-argument "fixed" version. The 3-arg version wrote to non-existent `user_accounts` columns (`tier_achieved_at`, `tier_maintain_deadline`) and called `calculate_maintain_deadline` as if it returned a scalar DATE, but the function returns a TABLE. The Inngest `inngest-tier-serve` edge function called with exactly 3 arguments, so PostgreSQL always resolved to the broken overload.

**Fix**: Dropped the 3-arg overload. All callers (including Inngest) now resolve to the fixed 4-arg version (which has `DEFAULT NULL` for the 4th parameter).

### Bug 2 — Upgrade Progress Direction Inverted (Critical)

**Impact**: All users saw upgrade progress toward the tier BELOW them instead of above

**Root cause**: `ensure_tier_progress` queried `ranking < v_current_ranking` to find the "next tier", but higher ranking = higher tier. This returned the next lower tier.

**Fix**: Changed to `ranking > COALESCE(v_current_ranking, 0) ORDER BY ranking ASC`.

### Bug 3 — Hardcoded Rolling Windows for Progress (High)

**Impact**: Progress percentages wrong for all non-rolling window types (calendar_month, calendar_quarter, fixed_period, anniversary)

**Root cause**: `ensure_tier_progress` always used pre-calculated 6mo/12mo rolling metrics, ignoring the actual `window_type` of each condition.

**Fix**: Replaced with per-condition calls to `calculate_tier_window_dates` + `calculate_tier_metric_value`, respecting each condition's actual window configuration.

### Bug 4 — Ticket Metric Enum Mismatch (High)

**Impact**: Ticket-based tier conditions always evaluated to 0

**Root cause**: `calculate_tier_metric_value` used `'tickets'` (plural) in both the CASE match and `currency` filter, but the metric enum and wallet_ledger use `'ticket'` (singular). The branch never matched.

**Fix**: Changed `'tickets'` to `'ticket'` in both locations.

### Bug 5 — Multi-Path Tier Qualification Broken (High)

**Impact**: Users who qualified via an alternate condition (e.g., sales instead of points) were not upgraded

**Root cause**: `evaluate_user_tier_status` used `DISTINCT ON (tm.ranking)` to pick one condition per tier. If that arbitrary condition failed, the tier was skipped — even if another condition would have passed.

**Fix**: Removed `DISTINCT ON`. All conditions now checked per tier ranking. First qualifying condition at highest tier wins, with early-exit optimization for lower tiers.

### Bug 6 — Premature Mid-Period Downgrades (High)

**Impact**: Users could be downgraded before their maintenance window closed

**Root cause**: `evaluate_user_tier_status` evaluated maintain conditions on every call regardless of deadline. During real-time CDC evaluations mid-month, calendar_month users could fail a partial-period check.

**Fix**: Maintain conditions now only evaluated when `tier_evaluation_tracking.maintain_deadline <= p_evaluation_date`. If no deadline or not yet reached, no downgrade evaluation occurs.

### Bug 7 — Double Evaluation in Real-Time Path (Medium)

**Impact**: Each CDC event produced two tier evaluations and potentially duplicate ledger entries

**Root cause**: `tier-bulk-process` edge function called `evaluate_user_tier_status`, applied a direct UPDATE + ledger INSERT, then called `ensure_tier_progress` which did the same.

**Fix**: Simplified real-time path to a single `ensure_tier_progress` call (handles everything atomically). Deployed as `tier-bulk-process` v35.

### Bug 8 — `get_tier_system_summary` Runtime Crash (Medium)

**Impact**: Admin health monitoring endpoint threw a runtime error on every call

**Root cause**: Called `check_tier_queue_health()` which does not exist (never created; references deprecated PGMQ queue from v2 architecture).

**Fix**: Replaced with direct queries against `tier_evaluation_tracking` for pending evaluations and completion counts.

### Bug 9 — `set_entry_tier` Blocked Universal Tiers (Medium)

**Impact**: Could not set a universal tier (user_type=NULL) as the entry tier via API

**Root cause**: (1) `IF v_user_type IS NULL` was used as "not found" check, but universal tiers legitimately have NULL user_type. (2) `WHERE user_type = v_user_type` never matches NULL (SQL `NULL = NULL` yields NULL, not TRUE).

**Fix**: (1) Changed to `IF NOT FOUND`. (2) Changed to `IS NOT DISTINCT FROM` for NULL-safe comparison on both `user_type` and `persona_id`.

### Bug 10 — Hardcoded Points Conversion in Bulk Metrics (Medium)

**Impact**: `calculate_tier_metrics_bulk` returned incorrect point totals (fabricated spending/100 + wallet)

**Root cause**: Hardcoded `v_points_conversion_rate := 100` — a "100 THB = 1 point" formula that does not exist in business logic. Points are tracked independently in `wallet_ledger`.

**Fix**: Removed conversion. Points now come solely from `wallet_ledger` where `transaction_type='earn' AND currency='points'`. Also aligned purchase_ledger filtering (uses `created_at`, matches core function's order counting logic).

### Additional Fix — Maintain Progress Uncapped

**Impact**: Users who exceeded maintenance thresholds could not see their "tier security" margin

**Root cause**: `ensure_tier_progress` capped `maintain_progress` at 100%, contradicting requirements that allow >100% for display purposes.

**Fix**: Removed cap. Upgrade progress remains capped at 100%.

---

### Fixes Deployed — Database Migrations

| Migration | Functions Changed | Issues |
|-----------|-------------------|--------|
| `fix_tier_audit_issues_1_5` | `apply_tier_upgrade` (DROP 3-arg), `calculate_tier_metric_value` | #1, #5 |
| `fix_evaluate_user_tier_status_issues_6_7` | `evaluate_user_tier_status` | #6, #7 |
| `fix_ensure_tier_progress_issues_2_3` | `ensure_tier_progress` | #2, #3, #4 |
| `fix_get_tier_system_summary_issue_13` | `get_tier_system_summary` | #13 |
| `fix_set_entry_tier_issue_15` | `set_entry_tier` | #15 |
| `fix_calculate_tier_metrics_bulk_issue_11` | `calculate_tier_metrics_bulk` | #11 |

### Fixes Deployed — Edge Functions

| Function | Version | Changes |
|----------|---------|---------|
| `tier-bulk-process` | v34 -> v35 | Real-time path simplified to single `ensure_tier_progress` call; removed redundant evaluate + direct UPDATE + ledger INSERT |

### Remaining Tier Issues (from audit, not yet fixed)

| Issue | Severity | Status |
|-------|----------|--------|
| `event-router` edge function still active (v3 QStash pipeline) — duplicate evaluations if Render Consumer also running | Med | Unfixed — disable Confluent HTTP Sink connector to resolve |
| `tier-batch-initiator` uses QStash instead of direct RPC | Low | Unfixed — functional but adds unnecessary QStash hop |
| `calculate_tier_progress` is a dead shell function (always returns 0%) | Low | Unfixed — dead code, harmless |
| `bff_upsert_tier_with_conditions` cannot clear persona_id to NULL | Low | Unfixed — COALESCE fallback prevents dissociating tier from persona |
| `calculate_metric_for_window` filtering differs from `calculate_tier_metric_value` | Low | Unfixed — only affects backward-compat summary fields in response |
