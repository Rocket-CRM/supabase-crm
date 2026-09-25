-- Jorakay Track B: hold export + summary (read-only)
WITH
params AS (
  SELECT '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AS merchant_id,
         '649e9524f43a5fc2f9705850'::text AS merchant_mongo,
         CURRENT_DATE AS today
),
last_old AS (
  SELECT wl.user_id,
         max(wl.created_at) AS last_ts,
         max(wl.created_at)::date AS last_day
  FROM wallet_ledger wl
  JOIN params p ON p.merchant_id = wl.merchant_id
  WHERE wl.currency = 'points'
    AND wl.mongo_id IS NOT NULL
    AND wl.source_type IS DISTINCT FROM 'expiry'::wallet_transaction_source_type
  GROUP BY 1
),
earn AS (
  SELECT wl.user_id,
    coalesce(sum(wl.deductible_balance) FILTER (
      WHERE lo.last_day IS NOT NULL AND wl.expiry_date IS NOT NULL AND wl.expiry_date <= lo.last_day
    ), 0) AS step1_lots,
    coalesce(sum(wl.deductible_balance) FILTER (
      WHERE lo.last_day IS NOT NULL AND wl.expiry_date IS NOT NULL
        AND wl.expiry_date > lo.last_day AND wl.expiry_date < p.today
    ), 0) AS due_after_last,
    coalesce(sum(wl.deductible_balance) FILTER (
      WHERE lo.last_day IS NULL OR wl.expiry_date IS NULL
        OR (wl.expiry_date > lo.last_day AND wl.expiry_date >= p.today)
    ), 0) AS valid_lots
  FROM wallet_ledger wl
  JOIN params p ON p.merchant_id = wl.merchant_id
  LEFT JOIN last_old lo ON lo.user_id = wl.user_id
  WHERE wl.currency = 'points' AND wl.transaction_type = 'earn'
  GROUP BY wl.user_id, lo.last_day, p.today
),
sim AS (
  SELECT w.user_id, w.points_balance AS wallet_after_1,
    coalesce(e.step1_lots, 0) AS step1_lots,
    coalesce(e.due_after_last, 0) AS due_after_last,
    coalesce(e.valid_lots, 0) AS valid_lots,
    coalesce(e.due_after_last, 0) + coalesce(e.valid_lots, 0) AS lots_after_1,
    GREATEST(coalesce(e.due_after_last, 0) + coalesce(e.valid_lots, 0) - w.points_balance, 0) AS step2_excess
  FROM params p
  JOIN user_wallet w ON w.merchant_id = p.merchant_id
  LEFT JOIN earn e ON e.user_id = w.user_id
),
sim2 AS (
  SELECT s.*,
    GREATEST(s.due_after_last - s.step2_excess, 0) AS due_after_after_2,
    GREATEST(s.step2_excess - s.due_after_last, 0) AS excess_into_valid,
    s.wallet_after_1 AS wallet_after_2
  FROM sim s
),
sim3 AS (
  SELECT s.user_id,
    s.step1_lots, s.step2_excess,
    s.due_after_after_2 AS step3_both_sides,
    GREATEST(
      (s.wallet_after_2 - s.due_after_after_2) - GREATEST(s.valid_lots - s.excess_into_valid, 0),
      0
    ) AS step3_wallet_only,
    s.due_after_after_2 + GREATEST(
      (s.wallet_after_2 - s.due_after_after_2) - GREATEST(s.valid_lots - s.excess_into_valid, 0),
      0
    ) AS step3_wallet_down,
    s.wallet_after_2 - s.due_after_after_2 - GREATEST(
      (s.wallet_after_2 - s.due_after_after_2) - GREATEST(s.valid_lots - s.excess_into_valid, 0),
      0
    ) AS final_wallet,
    GREATEST(s.valid_lots - s.excess_into_valid, 0) AS final_lots
  FROM sim2 s
),
later_newcrm_users AS (
  SELECT DISTINCT wl.user_id
  FROM wallet_ledger wl
  JOIN params p ON p.merchant_id = wl.merchant_id
  JOIN last_old lo ON lo.user_id = wl.user_id
  WHERE wl.currency = 'points'
    AND wl.source_type IS DISTINCT FROM 'expiry'
    AND wl.mongo_id IS NULL
    AND wl.created_at > lo.last_ts
),
mongo_gap_users AS (
  SELECT DISTINCT ua.id AS user_id
  FROM stg_mongo_points mp
  JOIN params par ON mp.merchant_ref = par.merchant_mongo
  JOIN user_accounts ua ON ua.mongo_id = mp.raw->>'userId'
  JOIN last_old lo ON lo.user_id = ua.id
  WHERE mp.raw->>'type' IN ('GIVEN', 'REDEEMED')
    AND (mp.raw->>'createdAt')::timestamptz > lo.last_ts
),
holds AS (
  SELECT
    w.user_id,
    lo.last_ts,
    lo.last_day,
    s3.step1_lots,
    s3.step2_excess,
    s3.step3_both_sides,
    s3.step3_wallet_only,
    s3.step3_wallet_down,
    array_remove(array[
      CASE WHEN s3.final_wallet IS DISTINCT FROM s3.final_lots OR s3.final_wallet < 0
           THEN 'sim_reconcile' END,
      CASE WHEN ln.user_id IS NOT NULL THEN 'later_newcrm' END,
      CASE WHEN mg.user_id IS NOT NULL THEN 'mongo_sync_gap' END
    ], NULL) AS hold_reasons
  FROM params p
  JOIN user_wallet w ON w.merchant_id = p.merchant_id
  LEFT JOIN last_old lo ON lo.user_id = w.user_id
  LEFT JOIN sim3 s3 ON s3.user_id = w.user_id
  LEFT JOIN later_newcrm_users ln ON ln.user_id = w.user_id
  LEFT JOIN mongo_gap_users mg ON mg.user_id = w.user_id
)
-- SUMMARY (swap final SELECT for per-user export below)
SELECT
  count(*) FILTER (WHERE coalesce(cardinality(hold_reasons), 0) = 0) AS clean_users,
  count(*) FILTER (WHERE coalesce(cardinality(hold_reasons), 0) > 0) AS held_users,
  count(*) FILTER (WHERE 'later_newcrm' = ANY(hold_reasons)) AS held_later_newcrm,
  count(*) FILTER (WHERE 'mongo_sync_gap' = ANY(hold_reasons)) AS held_mongo_sync_gap,
  count(*) FILTER (WHERE 'sim_reconcile' = ANY(hold_reasons)) AS held_sim_reconcile,
  count(*) FILTER (WHERE coalesce(cardinality(hold_reasons), 0) > 0 AND step3_wallet_down > 0) AS held_with_step3,
  coalesce(sum(step3_wallet_down) FILTER (WHERE coalesce(cardinality(hold_reasons), 0) > 0), 0) AS held_step3_wallet_down_total,
  coalesce(sum(step3_wallet_down) FILTER (WHERE 'later_newcrm' = ANY(hold_reasons)), 0) AS later_newcrm_step3_pts,
  coalesce(sum(step3_wallet_down) FILTER (WHERE 'mongo_sync_gap' = ANY(hold_reasons)), 0) AS mongo_sync_gap_step3_pts,
  coalesce(sum(step3_wallet_down) FILTER (WHERE 'sim_reconcile' = ANY(hold_reasons)), 0) AS sim_reconcile_step3_pts
FROM holds;

-- Per-user export (run separately):
-- SELECT h.user_id, ua.tel, ua.fullname, ua.mongo_id,
--        h.hold_reasons, h.last_ts, h.last_day,
--        h.step1_lots, h.step2_excess, h.step3_both_sides, h.step3_wallet_only, h.step3_wallet_down
-- FROM holds h
-- JOIN user_accounts ua ON ua.id = h.user_id
-- WHERE cardinality(h.hold_reasons) > 0
-- ORDER BY h.step3_wallet_down DESC NULLS LAST, h.user_id;
