-- Jorakay drift users 16–153 (excludes 15 already deep-dived). Read-only classification.
-- Merchant 7522af2c-a7f6-4ab8-8493-6875a3b19544 / Mongo 649e9524f43a5fc2f9705850
-- Export to CSV; if the editor truncates, filter: abs(delta) >= 500, then 100–499, then < 100.

WITH params AS (
  SELECT '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AS merchant_id,
         '649e9524f43a5fc2f9705850'::text AS merchant_ref
),
done AS (
  SELECT unnest(ARRAY[
    '65413f78d6b1732a1ec616f1','6811e84c6fc1032760808710','65e992956fdff6649db70844',
    '65413f89d6b1732a1ec6255d','67cd2a13865b399021ce9895','67510f45a33a4dc033969a91',
    '699efc2f2ec2d76e1eae0dd6','65e54b99d3d42fdf0cf61c93','681421cab1e202f9103ec1a0',
    '669f3ec760ab0274d8e31ed4','67c917a2c336839338cc12a8','6a4869e18a5ea7b763b65992',
    '66aa305cddfe1420692eff91','65413f4fd6b1732a1ec5f415','6787827bb0d6038e49a36ed6'
  ]) AS mongo_id
),
lot AS (
  SELECT user_id, sum(deductible_balance)::numeric AS lots
  FROM wallet_ledger wl
  JOIN params p ON wl.merchant_id = p.merchant_id
  WHERE currency = 'points' AND transaction_type = 'earn'
  GROUP BY 1
),
drift AS (
  SELECT ua.mongo_id, w.user_id, w.points_balance AS wallet, coalesce(l.lots, 0) AS lots,
         w.points_balance - coalesce(l.lots, 0) AS delta
  FROM user_wallet w
  JOIN params p ON w.merchant_id = p.merchant_id
  JOIN user_accounts ua ON ua.id = w.user_id
  LEFT JOIN lot l ON l.user_id = w.user_id
  LEFT JOIN done d ON d.mongo_id = ua.mongo_id
  WHERE w.points_balance IS DISTINCT FROM coalesce(l.lots, 0)
    AND d.mongo_id IS NULL
),
wl_stats AS (
  SELECT wl.user_id,
    coalesce(sum(wl.amount) FILTER (WHERE wl.transaction_type = 'earn'), 0)
      - coalesce(sum(wl.amount) FILTER (WHERE wl.transaction_type = 'burn'), 0) AS ledger_net,
    coalesce(sum(wl.amount) FILTER (WHERE wl.mongo_id IS NULL AND wl.transaction_type = 'earn'), 0) AS native_earn,
    coalesce(sum(wl.amount) FILTER (WHERE wl.mongo_id IS NULL AND wl.transaction_type = 'burn'
      AND wl.source_type IS DISTINCT FROM 'expiry'), 0) AS native_burn,
    coalesce(sum(wl.amount) FILTER (WHERE wl.source_type = 'expiry'), 0) AS expiry_burn,
    count(*) FILTER (WHERE wl.mongo_id IS NULL AND wl.source_type IS DISTINCT FROM 'expiry') AS native_rows,
    count(*) FILTER (WHERE wl.currency = 'points') AS points_ledger_rows,
    coalesce(sum(wl.deductible_balance) FILTER (
      WHERE wl.transaction_type = 'earn' AND wl.mongo_id IS NOT NULL
        AND coalesce((mp.raw->>'balance')::numeric, 0) = 0 AND wl.deductible_balance > 0
    ), 0) AS closed_mongo_ded_pts,
    coalesce(sum(greatest(wl.deductible_balance - coalesce((mp.raw->>'balance')::numeric, 0), 0))
      FILTER (WHERE wl.transaction_type = 'earn' AND coalesce((mp.raw->>'balance')::numeric, 0) > 0), 0) AS crm_over_stg_open,
    coalesce(sum(greatest(coalesce((mp.raw->>'balance')::numeric, 0) - wl.deductible_balance, 0))
      FILTER (WHERE wl.transaction_type = 'earn' AND coalesce((mp.raw->>'balance')::numeric, 0) > 0), 0) AS stg_open_under_crm
  FROM wallet_ledger wl
  JOIN params p ON wl.merchant_id = p.merchant_id
  JOIN drift d ON d.user_id = wl.user_id
  LEFT JOIN stg_mongo_points mp ON mp.mongo_id = wl.mongo_id AND mp.merchant_ref = p.merchant_ref
  WHERE wl.currency = 'points'
  GROUP BY wl.user_id
),
mongo_headline AS (
  SELECT d.user_id, coalesce((sc.raw->>'pointBalance')::numeric, 0) AS stg_point_balance
  FROM drift d
  JOIN stg_mongo_users su ON su.mongo_id = d.mongo_id
  LEFT JOIN stg_mongo_contacts sc ON sc.mongo_id = su.raw->>'contactId'
),
classified AS (
  SELECT d.*, mh.stg_point_balance, coalesce(ws.ledger_net, 0) AS ledger_net,
    coalesce(ws.native_earn, 0) AS native_earn, coalesce(ws.native_burn, 0) AS native_burn,
    coalesce(ws.expiry_burn, 0) AS expiry_burn, coalesce(ws.native_rows, 0) AS native_rows,
    coalesce(ws.points_ledger_rows, 0) AS points_ledger_rows,
    coalesce(ws.closed_mongo_ded_pts, 0) AS closed_mongo_ded_pts,
    coalesce(ws.crm_over_stg_open, 0) AS crm_over_stg_open,
    coalesce(ws.stg_open_under_crm, 0) AS stg_open_under_crm,
    (coalesce(mh.stg_point_balance, 0) + coalesce(ws.native_earn, 0)
      - coalesce(ws.native_burn, 0) - coalesce(ws.expiry_burn, 0)) AS target_wallet_stg,
    CASE
      WHEN coalesce(ws.points_ledger_rows, 0) = 0 AND d.wallet > 0 THEN 'NO_POINTS_LEDGER'
      WHEN abs(d.wallet - coalesce(ws.ledger_net, 0)) > 0.01 AND d.lots >= d.wallet - 1 THEN 'WALLET_UNDER_LEDGER'
      WHEN d.lots = 0 AND d.wallet > 0 AND coalesce(ws.native_rows, 0) = 0 THEN 'TTL_ZERO_LOTS_MIGRATION'
      WHEN d.lots = 0 AND d.wallet > 0 AND coalesce(ws.native_rows, 0) > 0 THEN 'ZERO_LOTS_NATIVE_ACTIVITY'
      WHEN coalesce(ws.closed_mongo_ded_pts, 0) >= greatest(abs(d.delta) * 0.5, 1) AND d.delta < 0 THEN 'CONSUMED_MONGO_STILL_OPEN_LOT'
      WHEN coalesce(ws.stg_open_under_crm, 0) >= greatest(abs(d.delta) * 0.5, 1) AND d.delta > 0 THEN 'MIGRATED_LOTS_UNDER_STG_OPEN'
      WHEN coalesce(ws.crm_over_stg_open, 0) >= greatest(abs(d.delta) * 0.5, 1) AND d.delta < 0 THEN 'MIGRATED_LOTS_OVER_STG_OPEN'
      WHEN coalesce(ws.native_burn, 0) > 0 AND d.lots > d.wallet THEN 'NATIVE_BURN_MISSING_FIFO'
      WHEN coalesce(ws.expiry_burn, 0) > 0 AND d.lots IS DISTINCT FROM d.wallet THEN 'EXPIRY_BURN_MISSING_LOT_ALLOC'
      WHEN coalesce(ws.native_rows, 0) > 0 AND d.delta > 0 THEN 'NATIVE_ACTIVITY_LOTS_LOW'
      WHEN coalesce(ws.native_rows, 0) > 0 AND d.delta < 0 THEN 'NATIVE_ACTIVITY_LOTS_HIGH'
      WHEN d.delta < 0 THEN 'LOTS_HIGH_OTHER'
      ELSE 'WALLET_HIGH_OTHER'
    END AS primary_pattern
  FROM drift d
  LEFT JOIN wl_stats ws ON ws.user_id = d.user_id
  LEFT JOIN mongo_headline mh ON mh.user_id = d.user_id
)
SELECT mongo_id, user_id, wallet, lots, delta, stg_point_balance, ledger_net,
  wallet - ledger_net AS wallet_minus_ledger_net,
  native_earn, native_burn, expiry_burn, native_rows, points_ledger_rows,
  target_wallet_stg, closed_mongo_ded_pts, crm_over_stg_open, stg_open_under_crm,
  primary_pattern,
  CASE
    WHEN primary_pattern = 'NO_POINTS_LEDGER' THEN 'INSERT earn wallet_ledger rows so sum deductible_balance = wallet'
    WHEN primary_pattern = 'WALLET_UNDER_LEDGER' THEN 'UPDATE user_wallet to ledger_net'
    WHEN closed_mongo_ded_pts > 0 OR crm_over_stg_open > 0 OR stg_open_under_crm > 0
      THEN 'UPDATE earn deductible_balance from live Mongo GIVEN.balance per mongo_id'
    WHEN native_burn > 0 OR expiry_burn > 0
      THEN 'UPDATE earn deductible FIFO to match existing burn rows'
    WHEN lots = 0 AND wallet > 0 THEN 'UPDATE earn deductibles to sum wallet (post-repair allocation)'
    ELSE 'Per-user worksheet: Mongo headline + native ledger'
  END AS fix_class
FROM classified
ORDER BY abs(delta) DESC;
