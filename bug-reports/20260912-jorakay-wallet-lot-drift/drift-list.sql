-- Jorakay wallet ≠ open lots (read-only). Merchant 7522af2c-a7f6-4ab8-8493-6875a3b19544
WITH params AS (
  SELECT '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AS merchant_id
),
lot AS (
  SELECT user_id, sum(deductible_balance)::numeric AS lots
  FROM wallet_ledger
  JOIN params p ON p.merchant_id = wallet_ledger.merchant_id
  WHERE currency = 'points' AND transaction_type = 'earn'
  GROUP BY 1
),
native AS (
  SELECT user_id, count(*) AS native_activity_rows
  FROM wallet_ledger wl
  JOIN params p ON p.merchant_id = wl.merchant_id
  WHERE wl.currency = 'points'
    AND wl.mongo_id IS NULL
    AND wl.source_type IS DISTINCT FROM 'expiry'
  GROUP BY 1
)
SELECT ua.mongo_id,
       w.user_id,
       w.points_balance AS wallet,
       coalesce(l.lots, 0) AS lots,
       w.points_balance - coalesce(l.lots, 0) AS delta,
       coalesce(n.native_activity_rows, 0) AS native_activity_rows
FROM user_wallet w
JOIN params p ON p.merchant_id = w.merchant_id
JOIN user_accounts ua ON ua.id = w.user_id
LEFT JOIN lot l ON l.user_id = w.user_id
LEFT JOIN native n ON n.user_id = w.user_id
WHERE w.points_balance IS DISTINCT FROM coalesce(l.lots, 0)
ORDER BY abs(w.points_balance - coalesce(l.lots, 0)) DESC;
