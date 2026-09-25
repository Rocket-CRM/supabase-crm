-- Track B Phase C: export Mongo GIVEN/REDEEM after last_ts missing from wallet_ledger
-- Run BEFORE fn_ttl_points_repair_build_hold_manifest(..., 'C')

WITH params AS (
  SELECT '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AS merchant_id,
         '649e9524f43a5fc2f9705850'::text AS merchant_mongo
),
c_users AS (
  SELECT hr.user_id, hr.last_ts, ua.mongo_id
  FROM ttl_points_repair_hold_resolution hr
  JOIN user_accounts ua ON ua.id = hr.user_id
  JOIN params p ON p.merchant_id = hr.merchant_id
  WHERE hr.resolution = 'C'
),
gaps AS (
  SELECT
    cu.user_id,
    cu.mongo_id AS user_mongo_id,
    cu.last_ts,
    mp.raw->>'_id' AS mongo_txn_id,
    mp.raw->>'type' AS txn_type,
    (mp.raw->>'createdAt')::timestamptz AS mongo_created_at,
    coalesce((mp.raw->>'points')::numeric, (mp.raw->>'amount')::numeric) AS points
  FROM c_users cu
  JOIN stg_mongo_points mp ON mp.merchant_ref = (SELECT merchant_mongo FROM params)
    AND mp.raw->>'userId' = cu.mongo_id
    AND mp.raw->>'type' IN ('GIVEN', 'REDEEMED')
    AND (mp.raw->>'createdAt')::timestamptz > cu.last_ts
  WHERE NOT EXISTS (
    SELECT 1 FROM wallet_ledger wl
    WHERE wl.user_id = cu.user_id AND wl.mongo_id = mp.raw->>'_id'
  )
)
SELECT
  count(DISTINCT user_id) AS c_users_with_gaps,
  count(*) AS missing_txns,
  coalesce(sum(points) FILTER (WHERE txn_type = 'GIVEN'), 0) AS missing_given_pts,
  coalesce(sum(points) FILTER (WHERE txn_type = 'REDEEMED'), 0) AS missing_redeemed_pts
FROM gaps;

-- Detail export (uncomment for workbook):
-- SELECT * FROM gaps ORDER BY user_id, mongo_created_at;
