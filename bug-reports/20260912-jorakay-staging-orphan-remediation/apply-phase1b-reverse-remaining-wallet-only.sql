-- Phase 1b: reverse ALL remaining lazy TTL wallet-only lines (no orphan-evidence gate).
-- Same mechanics as Phase 1: DELETE burn rows + credit user_wallet in one transaction.

BEGIN;

WITH params AS (
  SELECT '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AS merchant_id
),
burns AS (
  SELECT wl.user_id, sum(-wl.signed_amount)::bigint AS pts
  FROM wallet_ledger wl
  JOIN params p ON wl.merchant_id = p.merchant_id
  WHERE wl.description = 'TTL historical repair wallet-only'
  GROUP BY wl.user_id
),
wallet_up AS (
  UPDATE user_wallet uw
  SET points_balance = uw.points_balance + b.pts
  FROM burns b
  JOIN params p ON true
  WHERE uw.user_id = b.user_id
    AND uw.merchant_id = p.merchant_id
  RETURNING uw.user_id, b.pts
),
del AS (
  DELETE FROM wallet_ledger wl
  USING params p
  WHERE wl.merchant_id = p.merchant_id
    AND wl.description = 'TTL historical repair wallet-only'
  RETURNING wl.id
)
SELECT
  (SELECT count(*) FROM burns) AS reversal_users,
  (SELECT coalesce(sum(pts), 0) FROM burns) AS wallet_credited_pts,
  (SELECT count(*) FROM wallet_up) AS wallets_updated,
  (SELECT count(*) FROM del) AS ledger_rows_deleted;

COMMIT;
