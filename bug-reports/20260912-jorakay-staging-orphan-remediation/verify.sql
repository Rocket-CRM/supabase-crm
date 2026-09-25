-- Post-apply verification (jorakay)

WITH params AS (SELECT '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AS merchant_id),
lot AS (
  SELECT user_id, sum(deductible_balance)::numeric AS lots
  FROM wallet_ledger JOIN params p ON p.merchant_id = wallet_ledger.merchant_id
  WHERE currency = 'points' AND transaction_type = 'earn' GROUP BY 1
)
SELECT
  count(*) FILTER (WHERE w.points_balance IS DISTINCT FROM coalesce(l.lots, 0)) AS still_drift,
  count(*) FILTER (WHERE w.points_balance > coalesce(l.lots, 0)) AS wallet_gt_lots,
  count(*) FILTER (WHERE coalesce(l.lots, 0) > w.points_balance) AS lots_gt_wallet
FROM user_wallet w
JOIN params p ON p.merchant_id = w.merchant_id
LEFT JOIN lot l ON l.user_id = w.user_id;
