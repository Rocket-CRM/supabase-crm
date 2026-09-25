-- Jorakay Track A apply (clean cohort only)
-- Migration: 20260902100000_ttl_points_historical_repair.sql
-- Merchant: 7522af2c-a7f6-4ab8-8493-6875a3b19544

-- 0) Preconditions (sync must be paused)
SELECT sync_active FROM migration_merchant_status
WHERE merchant_uuid = '7522af2c-a7f6-4ab8-8493-6875a3b19544';

-- 1) Build manifest (stores clean + held; only clean get lot/burn rows)
SELECT fn_ttl_points_repair_build_manifest('7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid);
-- Save run_id from JSON: {"run_id": "..."}

-- Inspect manifest (replace :run_id)
SELECT summary FROM ttl_points_repair_run WHERE id = 'RUN_ID'::uuid;
SELECT count(*) FILTER (WHERE is_clean) clean, count(*) FILTER (WHERE NOT is_clean) held
FROM ttl_points_repair_user WHERE run_id = 'RUN_ID'::uuid;
SELECT coalesce(sum(step1_lots),0) s1, coalesce(sum(step2_excess),0) s2,
       coalesce(sum(step3_both + step3_wallet_only),0) s3
FROM ttl_points_repair_user WHERE run_id = 'RUN_ID'::uuid AND is_clean;

-- Replace RUN_ID after manifest build

-- 2) Dry-run each step (p_dry_run := true) — no prior live step required for dry-run
SELECT fn_ttl_points_repair_apply_step1('RUN_ID'::uuid, 5000, true);
SELECT fn_ttl_points_repair_apply_step2('RUN_ID'::uuid, 5000, true);
SELECT fn_ttl_points_repair_apply_step3('RUN_ID'::uuid, 2000, true);

-- 3) LIVE apply — run each step in batches until rows_updated / burns = 0
-- Step 1 (repeat until lots_updated = 0)
SELECT fn_ttl_points_repair_apply_step1('RUN_ID'::uuid, 500, false);
-- Step 2 (repeat until pts_reduced batch = 0; users with step2_excess=0 auto-skip)
SELECT fn_ttl_points_repair_apply_step2('RUN_ID'::uuid, 500, false);
-- Step 3 (repeat until burns = 0; uses fn_repair_wallet_expiry_burn, _skip_emit)
SELECT fn_ttl_points_repair_apply_step3('RUN_ID'::uuid, 200, false);

-- 4) Verify (Plan.md § Verify)
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

-- Held users still on file for Track B
SELECT user_id, hold_reasons, step3_both + step3_wallet_only AS step3_at_risk
FROM ttl_points_repair_user
WHERE run_id = 'RUN_ID'::uuid AND NOT is_clean
ORDER BY step3_both + step3_wallet_only DESC NULLS LAST
LIMIT 50;
