-- Kovet Track A apply (clean cohort only)
-- Migration: 20260902100000_ttl_points_historical_repair.sql
-- Merchant: c0db034a-cabc-44d2-87f0-e660a755237f

-- 0) Preconditions (sync must be paused)
SELECT sync_active FROM migration_merchant_status
WHERE merchant_uuid = 'c0db034a-cabc-44d2-87f0-e660a755237f';

-- 1) Build manifest (stores clean + held; only clean get lot/burn rows)
SELECT fn_ttl_points_repair_build_manifest('c0db034a-cabc-44d2-87f0-e660a755237f'::uuid);
-- Save run_id from JSON: {"run_id": "..."}

-- Inspect manifest (replace RUN_ID)
SELECT summary FROM ttl_points_repair_run WHERE id = 'RUN_ID'::uuid;
SELECT count(*) FILTER (WHERE is_clean) clean, count(*) FILTER (WHERE NOT is_clean) held
FROM ttl_points_repair_user WHERE run_id = 'RUN_ID'::uuid;
SELECT coalesce(sum(step1_lots),0) s1, coalesce(sum(step2_excess),0) s2,
       coalesce(sum(step3_both + step3_wallet_only),0) s3
FROM ttl_points_repair_user WHERE run_id = 'RUN_ID'::uuid AND is_clean;

-- 2) Dry-run each step (p_dry_run := true)
SELECT fn_ttl_points_repair_apply_step1('RUN_ID'::uuid, 5000, true);
SELECT fn_ttl_points_repair_apply_step2('RUN_ID'::uuid, 5000, true);
SELECT fn_ttl_points_repair_apply_step3('RUN_ID'::uuid, 2000, true);

-- 3) LIVE apply — repeat each until rows_updated / burns = 0
SELECT fn_ttl_points_repair_apply_step1('RUN_ID'::uuid, 500, false);
SELECT fn_ttl_points_repair_apply_step2('RUN_ID'::uuid, 500, false);
SELECT fn_ttl_points_repair_apply_step3('RUN_ID'::uuid, 200, false);

-- 4) Verify (Plan.md § Verify)
WITH params AS (SELECT 'c0db034a-cabc-44d2-87f0-e660a755237f'::uuid AS merchant_id),
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

-- Held users for Track B
SELECT user_id, hold_reasons, step3_both + step3_wallet_only AS step3_at_risk
FROM ttl_points_repair_user
WHERE run_id = 'RUN_ID'::uuid AND NOT is_clean
ORDER BY step3_both + step3_wallet_only DESC NULLS LAST;
