-- Phase 3: expiry adjustments on earns inserted in Phase 2 only (metadata tag).
-- Already expired in old CRM terms (activity after earn): zero lot, keep wallet.
-- Should have expired (inactive): zero lot and reduce wallet by same amount.

BEGIN;

WITH params AS (
  SELECT '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AS merchant_id,
         CURRENT_DATE AS today
),
new_earns AS (
  SELECT wl.id, wl.user_id, wl.deductible_balance, wl.expiry_date, wl.created_at
  FROM wallet_ledger wl
  JOIN params p ON wl.merchant_id = p.merchant_id
  WHERE wl.transaction_type = 'earn'
    AND wl.metadata->>'jorakay_orphan_remediation' = '20260912'
),
last_old AS (
  SELECT wl.user_id, max(wl.created_at) AS last_ts
  FROM wallet_ledger wl
  JOIN params p ON wl.merchant_id = p.merchant_id
  WHERE wl.currency = 'points'
    AND wl.mongo_id IS NOT NULL
    AND wl.source_type IS DISTINCT FROM 'expiry'::wallet_transaction_source_type
    AND NOT (wl.metadata->>'jorakay_orphan_remediation' = '20260912')
  GROUP BY wl.user_id
),
classified AS (
  SELECT
    ne.id,
    ne.user_id,
    ne.deductible_balance AS lot_pts,
    CASE
      WHEN ne.expiry_date IS NULL THEN 'keep'
      WHEN lo.last_ts IS NOT NULL AND ne.created_at <= lo.last_ts THEN 'already_expired_lot_only'
      WHEN ne.expiry_date < p.today AND (lo.last_ts IS NULL OR lo.last_ts < ne.created_at) THEN 'inactive_wallet_and_lot'
      ELSE 'keep'
    END AS action
  FROM new_earns ne
  CROSS JOIN params p
  LEFT JOIN last_old lo ON lo.user_id = ne.user_id
),
zero_lots AS (
  UPDATE wallet_ledger wl
  SET deductible_balance = 0,
      expired_amount = COALESCE(wl.expired_amount, 0) + GREATEST(COALESCE(wl.deductible_balance, 0), 0),
      expiry_processed_at = COALESCE(wl.expiry_processed_at, now())
  FROM classified c
  WHERE wl.id = c.id
    AND c.action IN ('already_expired_lot_only', 'inactive_wallet_and_lot')
  RETURNING wl.id, wl.user_id, c.action,
    (SELECT lot_pts FROM classified c2 WHERE c2.id = wl.id) AS pts
),
wallet_down AS (
  UPDATE user_wallet uw
  SET points_balance = uw.points_balance - agg.pts
  FROM (
    SELECT user_id, sum(pts)::bigint AS pts
    FROM zero_lots z
    JOIN classified c ON c.id = z.id
    WHERE c.action = 'inactive_wallet_and_lot'
    GROUP BY user_id
  ) agg
  JOIN params p ON true
  WHERE uw.user_id = agg.user_id
    AND uw.merchant_id = p.merchant_id
  RETURNING uw.user_id, agg.pts
)
SELECT
  (SELECT count(*) FROM new_earns) AS new_earn_rows,
  (SELECT count(*) FROM zero_lots) AS lots_zeroed,
  (SELECT count(*) FROM wallet_down) AS wallets_reduced,
  (SELECT coalesce(sum(pts), 0) FROM wallet_down) AS wallet_down_pts;

COMMIT;
