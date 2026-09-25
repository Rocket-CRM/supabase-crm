-- Jorakay Track B resolution F (68 manual-review holds)
-- Merchant: 7522af2c-a7f6-4ab8-8493-6875a3b19544
-- Migration: 20260902120000_ttl_points_repair_track_b_f.sql (F = revised_last_ts + steps 1–3)

-- 0) Preconditions
SELECT sync_active FROM migration_merchant_status
WHERE merchant_uuid = '7522af2c-a7f6-4ab8-8493-6875a3b19544';

-- 1) Seed F cohort (68 rows)
-- Run: seed-track-b-f.sql

-- 2) Build manifest
SELECT fn_ttl_points_repair_build_hold_manifest(
  '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid,
  'F'
);
-- Save run_id from JSON as RUN_F

-- 3) Dry-run
SELECT fn_ttl_points_repair_apply_step1('RUN_F'::uuid, 5000, true);
SELECT fn_ttl_points_repair_apply_step2('RUN_F'::uuid, 5000, true);
SELECT fn_ttl_points_repair_apply_step3('RUN_F'::uuid, 2000, true);

-- 4) LIVE (repeat each until batch returns 0)
SELECT fn_ttl_points_repair_apply_step1('RUN_F'::uuid, 500, false);
SELECT fn_ttl_points_repair_apply_step2('RUN_F'::uuid, 500, false);
SELECT fn_ttl_points_repair_apply_step3('RUN_F'::uuid, 200, false);

-- 5) Verify F cohort only
SELECT count(*) AS f_users_still_drift
FROM ttl_points_repair_user u
JOIN user_wallet w ON w.user_id = u.user_id AND w.merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'
LEFT JOIN (
  SELECT user_id, sum(deductible_balance) AS lots
  FROM wallet_ledger
  WHERE merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'
    AND currency = 'points' AND transaction_type = 'earn'
  GROUP BY 1
) l ON l.user_id = u.user_id
WHERE u.run_id = 'RUN_F'::uuid
  AND w.points_balance IS DISTINCT FROM coalesce(l.lots, 0);

-- Applied 2026-09-02: RUN_F = 5e5737b0-0f52-4399-a075-2684e6c6dc56
-- 68 users, 148,153 wallet pts removed, f_users_still_drift = 0
