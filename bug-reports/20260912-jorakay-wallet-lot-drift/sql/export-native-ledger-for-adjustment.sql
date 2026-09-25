-- Native (post-cutover) earns and burns for FIFO planning. See data/native-ledger-export.json

WITH users AS (
  SELECT ua.id AS user_id, ua.mongo_id AS member_mongo
  FROM user_accounts ua
  WHERE ua.merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'
    AND ua.mongo_id IN (
      '65413f78d6b1732a1ec616f1','6811e84c6fc1032760808710','65e992956fdff6649db70844',
      '65413f89d6b1732a1ec6255d','67cd2a13865b399021ce9895','67510f45a33a4dc033969a91',
      '699efc2f2ec2d76e1eae0dd6','65e54b99d3d42fdf0cf61c93','681421cab1e202f9103ec1a0',
      '669f3ec760ab0274d8e31ed4','67c917a2c336839338cc12a8','6a4869e18a5ea7b763b65992',
      '66aa305cddfe1420692eff91','65413f4fd6b1732a1ec5f415','6787827bb0d6038e49a36ed6'
    )
)
SELECT u.member_mongo, wl.user_id, wl.id AS ledger_id, wl.transaction_type,
  wl.source_type, wl.amount, wl.created_at, wl.description
FROM wallet_ledger wl
JOIN users u ON u.user_id = wl.user_id
WHERE wl.merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'
  AND wl.currency = 'points'
  AND wl.mongo_id IS NULL
  AND wl.transaction_type IN ('burn', 'earn')
ORDER BY u.member_mongo, wl.created_at;
