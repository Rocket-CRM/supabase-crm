-- Jorakay orphan remediation — Phase 0 inventory (read-only)
-- Merchant: 7522af2c-a7f6-4ab8-8493-6875a3b19544 / mongo 649e9524f43a5fc2f9705850

WITH params AS (
  SELECT '649e9524f43a5fc2f9705850'::text AS merchant_ref,
         '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AS merchant_id
),
orphan_given AS (
  SELECT mp.mongo_id, mp.raw, ua.id AS user_id
  FROM stg_mongo_points mp
  JOIN params pr ON mp.merchant_ref = pr.merchant_ref
  LEFT JOIN user_accounts ua
    ON ua.merchant_id = pr.merchant_id AND ua.mongo_id = mp.raw->>'userId'
  WHERE mp.raw->>'type' = 'GIVEN'
    AND COALESCE((mp.raw->>'balance')::numeric, 0) > 0
    AND NOT EXISTS (
      SELECT 1 FROM wallet_ledger wl
      WHERE wl.merchant_id = pr.merchant_id
        AND wl.mongo_id = mp.mongo_id
        AND wl.transaction_type = 'earn'
    )
)
SELECT 'orphan_wallet_earn' AS metric, count(*)::bigint AS n,
       count(*) FILTER (WHERE user_id IS NOT NULL) AS with_user,
       count(*) FILTER (WHERE user_id IS NULL) AS no_user
FROM orphan_given
UNION ALL
SELECT 'orphan_purchase', count(*), NULL, NULL
FROM stg_sf_bills b
JOIN params p ON b.merchant_ref = p.merchant_ref
WHERE NOT EXISTS (
  SELECT 1 FROM purchase_ledger pl
  WHERE pl.merchant_id = p.merchant_id AND pl.mongo_id = b.mongo_id
)
UNION ALL
SELECT 'orphan_receipt_upload', count(*), NULL, NULL
FROM stg_mongo_receipts r
JOIN params p ON r.merchant_ref = p.merchant_ref
WHERE NOT EXISTS (
  SELECT 1 FROM purchase_receipt_upload pr
  WHERE pr.merchant_id = p.merchant_id AND pr.mongo_id = r.mongo_id
)
UNION ALL
SELECT 'wallet_only_repair_users', count(DISTINCT wl.user_id), NULL, NULL
FROM wallet_ledger wl
JOIN params p ON wl.merchant_id = p.merchant_id
WHERE wl.description = 'TTL historical repair wallet-only'
UNION ALL
SELECT 'migration_gap_reversal_users',
       count(DISTINCT wl.user_id),
       NULL,
       NULL
FROM wallet_ledger wl
JOIN params p ON wl.merchant_id = p.merchant_id
WHERE wl.description = 'TTL historical repair wallet-only'
  AND EXISTS (
    SELECT 1 FROM orphan_given og WHERE og.user_id = wl.user_id
  );
