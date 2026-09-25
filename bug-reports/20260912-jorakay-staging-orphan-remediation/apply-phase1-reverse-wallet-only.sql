-- Phase 1: reverse lazy TTL wallet-only for migration-gap cohort only.
-- Ledger: DELETE repair burn rows. Wallet: credit same points in same transaction.
-- Do not run for users with wallet-only repair but no orphan staging GIVEN.

BEGIN;

WITH params AS (
  SELECT '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AS merchant_id,
         '649e9524f43a5fc2f9705850'::text AS merchant_ref
),
orphan_given_users AS (
  SELECT DISTINCT ua.id AS user_id
  FROM stg_mongo_points mp
  JOIN params pr ON mp.merchant_ref = pr.merchant_ref
  JOIN user_accounts ua
    ON ua.merchant_id = pr.merchant_id AND ua.mongo_id = mp.raw->>'userId'
  WHERE mp.raw->>'type' = 'GIVEN'
    AND COALESCE((mp.raw->>'balance')::numeric, 0) > 0
    AND NOT EXISTS (
      SELECT 1 FROM wallet_ledger wl
      WHERE wl.merchant_id = pr.merchant_id
        AND wl.mongo_id = mp.mongo_id
        AND wl.transaction_type = 'earn'
    )
),
reversal_users AS (
  SELECT DISTINCT wl.user_id
  FROM wallet_ledger wl
  JOIN params p ON wl.merchant_id = p.merchant_id
  JOIN orphan_given_users og ON og.user_id = wl.user_id
  WHERE wl.description = 'TTL historical repair wallet-only'
),
burns AS (
  SELECT wl.user_id, sum(-wl.signed_amount)::bigint AS pts
  FROM wallet_ledger wl
  JOIN params p ON wl.merchant_id = p.merchant_id
  WHERE wl.description = 'TTL historical repair wallet-only'
    AND wl.user_id IN (SELECT user_id FROM reversal_users)
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
    AND wl.user_id IN (SELECT user_id FROM reversal_users)
  RETURNING wl.id
)
SELECT
  (SELECT count(*) FROM reversal_users) AS reversal_users,
  (SELECT coalesce(sum(pts), 0) FROM burns) AS wallet_credited_pts,
  (SELECT count(*) FROM wallet_up) AS wallets_updated,
  (SELECT count(*) FROM del) AS ledger_rows_deleted;

COMMIT;
