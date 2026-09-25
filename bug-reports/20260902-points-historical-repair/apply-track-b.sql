-- Jorakay Track B apply (hold resolutions A / B / C)
-- Merchant: 7522af2c-a7f6-4ab8-8493-6875a3b19544
-- Migration: 20260902110000_ttl_points_repair_track_b.sql
-- Prerequisite migration: 20260902100000_ttl_points_historical_repair.sql

-- Run Track A (clean cohort) FIRST via apply-track-a.sql before this script.

-- =============================================================================
-- 0) Preconditions
-- =============================================================================
SELECT sync_active FROM migration_merchant_status
WHERE merchant_uuid = '7522af2c-a7f6-4ab8-8493-6875a3b19544';
-- Must be false.

-- =============================================================================
-- 1) Load hold resolutions (457 rows from investigation)
-- =============================================================================
-- Run entire file: seed-hold-resolutions.sql
-- Expected: A=35, B=151, C=82, E=121, F=68

-- =============================================================================
-- 2) Phase B — lots only (151 users, no wallet change)
-- =============================================================================
SELECT fn_ttl_points_repair_build_hold_manifest(
  '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid,
  'B'
);
-- Save run_id from JSON as RUN_B

SELECT summary FROM ttl_points_repair_run WHERE id = 'RUN_B'::uuid;
SELECT count(*), coalesce(sum(step1_lots),0) s1, coalesce(sum(step2_excess),0) s2,
       coalesce(sum(step3_both + step3_wallet_only),0) s3
FROM ttl_points_repair_user WHERE run_id = 'RUN_B'::uuid;

-- Dry-run
SELECT fn_ttl_points_repair_apply_step1('RUN_B'::uuid, 5000, true);
SELECT fn_ttl_points_repair_apply_step2('RUN_B'::uuid, 5000, true);
SELECT fn_ttl_points_repair_apply_step3('RUN_B'::uuid, 2000, true);  -- should be 0 burns

-- LIVE (repeat each until batch returns 0)
SELECT fn_ttl_points_repair_apply_step1('RUN_B'::uuid, 500, false);
SELECT fn_ttl_points_repair_apply_step2('RUN_B'::uuid, 500, false);
-- Skip step 3 for resolution B

-- =============================================================================
-- 3) Phase A — reclassify with revised_last_ts + steps 1–3 (35 users)
-- =============================================================================
SELECT fn_ttl_points_repair_build_hold_manifest(
  '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid,
  'A'
);
-- Save run_id as RUN_A

SELECT summary FROM ttl_points_repair_run WHERE id = 'RUN_A'::uuid;

-- Dry-run
SELECT fn_ttl_points_repair_apply_step1('RUN_A'::uuid, 5000, true);
SELECT fn_ttl_points_repair_apply_step2('RUN_A'::uuid, 5000, true);
SELECT fn_ttl_points_repair_apply_step3('RUN_A'::uuid, 2000, true);

-- LIVE (repeat each until batch returns 0)
SELECT fn_ttl_points_repair_apply_step1('RUN_A'::uuid, 500, false);
SELECT fn_ttl_points_repair_apply_step2('RUN_A'::uuid, 500, false);
SELECT fn_ttl_points_repair_apply_step3('RUN_A'::uuid, 200, false);

-- =============================================================================
-- 4) Phase C — mongo sync FIRST, then repair (82 users)
-- =============================================================================
-- 4a) Export missing Mongo txs: run apply-track-b-c-gap.sql
-- 4b) Load missing GIVEN/REDEEMED into wallet_ledger (migration replay / manual)
-- 4c) Re-run hold gate for C users only; confirm revised_last_ts still valid
-- 4d) Build + apply:

SELECT fn_ttl_points_repair_build_hold_manifest(
  '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid,
  'C'
);
-- Save run_id as RUN_C

-- Dry-run then LIVE (same pattern as Phase A)
SELECT fn_ttl_points_repair_apply_step1('RUN_C'::uuid, 5000, true);
SELECT fn_ttl_points_repair_apply_step2('RUN_C'::uuid, 5000, true);
SELECT fn_ttl_points_repair_apply_step3('RUN_C'::uuid, 2000, true);

SELECT fn_ttl_points_repair_apply_step1('RUN_C'::uuid, 500, false);
SELECT fn_ttl_points_repair_apply_step2('RUN_C'::uuid, 500, false);
SELECT fn_ttl_points_repair_apply_step3('RUN_C'::uuid, 200, false);

-- =============================================================================
-- 5) Verify (Plan.md § Verify)
-- =============================================================================
WITH params AS (SELECT '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AS merchant_id),
lot AS (
  SELECT user_id, sum(deductible_balance)::numeric AS lots
  FROM wallet_ledger JOIN params p ON p.merchant_id = wallet_ledger.merchant_id
  WHERE currency = 'points' AND transaction_type = 'earn' GROUP BY 1
)
SELECT
  count(*) FILTER (WHERE w.points_balance IS DISTINCT FROM coalesce(l.lots, 0)) AS still_drift,
  count(*) FILTER (WHERE coalesce(l.lots, 0) > w.points_balance) AS lots_gt_wallet,
  count(*) FILTER (WHERE w.points_balance > coalesce(l.lots, 0)) AS wallet_gt_lots
FROM user_wallet w
JOIN params p ON p.merchant_id = w.merchant_id
LEFT JOIN lot l ON l.user_id = w.user_id;

-- F users (68) remain for manual thread — see track-b-f-prompt.md
SELECT count(*) FROM ttl_points_repair_hold_resolution
WHERE merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544' AND resolution = 'F';
