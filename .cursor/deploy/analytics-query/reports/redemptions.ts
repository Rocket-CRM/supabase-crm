import { runQueryJson, type BqParam } from "../lib/bq.ts"
import type { ValidatedRange } from "../lib/params.ts"

const SL = "`rocket-prod-analytics.serving_loyalty"
const RAW = "`rocket-prod-analytics.raw_supabase_prod"

function bucketExpr(tsCol: string) {
  return `CASE @frequency
    WHEN 'day' THEN DATE(DATETIME(${tsCol}, 'Asia/Bangkok'))
    WHEN 'week' THEN DATE_TRUNC(DATE(DATETIME(${tsCol}, 'Asia/Bangkok')), WEEK(MONDAY))
    WHEN 'month' THEN DATE_TRUNC(DATE(DATETIME(${tsCol}, 'Asia/Bangkok')), MONTH)
    ELSE DATE_TRUNC(DATE(DATETIME(${tsCol}, 'Asia/Bangkok')), QUARTER)
  END`
}

export async function redemptionsChart(
  merchantId: string,
  range: ValidatedRange,
) {
  const sql = `
WITH base AS (
  SELECT
    r.id AS redemption_id,
    r.redeemed_at,
    r.user_id,
    r.reward_id,
    CAST(r.qty AS NUMERIC) AS qty,
    CAST(r.points_deducted AS NUMERIC) AS points_deducted,
    r.success,
    r.cancelled,
    r.fulfillment_status,
    r.source_type,
    r.redeemed_store_id,
    r.used_store_id,
    r.used_status,
    ${bucketExpr("r.redeemed_at")} AS bucket
  FROM ${SL}.reward_redemptions_ledger\` r
  WHERE r.merchant_id = @merchant_id
    AND r.redeemed_at >= @p_from AND r.redeemed_at < @p_to
),
summary AS (
  SELECT
    COUNT(*) AS redemptions,
    COUNT(DISTINCT user_id) AS unique_redeemers,
    COALESCE(SUM(points_deducted), 0) AS points_burned,
    SAFE_DIVIDE(COUNTIF(success IS TRUE), COUNT(*)) AS success_rate,
    SAFE_DIVIDE(COUNTIF(cancelled IS TRUE), COUNT(*)) AS cancel_rate,
    COUNTIF(used_status IS TRUE) AS used_count,
    SAFE_DIVIDE(COUNTIF(used_status IS TRUE), COUNT(*)) AS used_rate,
    COUNTIF(fulfillment_status = 'pending' OR fulfillment_status IS NULL) AS fulfillment_pending,
    IF(COUNT(*)>0, ROUND(COALESCE(SUM(points_deducted),0)/COUNT(*), 2), 0) AS avg_points_per_redemption
  FROM base
),
series AS (
  SELECT FORMAT_DATE('%Y-%m-%d', bucket) AS bucket,
    COUNT(*) AS redemptions,
    COALESCE(SUM(points_deducted),0) AS points_burned
  FROM base GROUP BY 1 ORDER BY 1
),
by_reward AS (
  SELECT b.reward_id, rm.name AS reward_name,
    SUM(b.qty) AS qty, SUM(b.points_deducted) AS points_burned
  FROM base b
  LEFT JOIN ${RAW}.public_reward__master\` rm ON rm.id = b.reward_id
  WHERE b.reward_id IS NOT NULL
  GROUP BY 1,2 ORDER BY points_burned DESC LIMIT 25
),
by_category AS (
  SELECT rc.id AS category_id, rc.name AS category_name,
    SUM(b.qty) AS qty, SUM(b.points_deducted) AS points_burned
  FROM base b
  LEFT JOIN ${RAW}.public_reward__master\` rm ON rm.id = b.reward_id
  -- category_id is ARRAY<STRING> on reward master
  LEFT JOIN UNNEST(IFNULL(rm.category_id, CAST([] AS ARRAY<STRING>))) AS cat_id
  LEFT JOIN ${RAW}.public_reward__category\` rc ON rc.id = cat_id
  WHERE rc.id IS NOT NULL
  GROUP BY 1,2 ORDER BY points_burned DESC LIMIT 25
),
by_tier AS (
  SELECT ua.tier_id, tm.tier_name,
    COUNT(*) AS qty, SUM(b.points_deducted) AS points_burned
  FROM base b
  LEFT JOIN ${SL}.user_accounts\` ua ON ua.id = b.user_id AND ua.merchant_id = @merchant_id
  LEFT JOIN ${RAW}.public_tier__master\` tm ON tm.id = ua.tier_id
  WHERE ua.tier_id IS NOT NULL
  GROUP BY 1,2 ORDER BY points_burned DESC LIMIT 25
),
by_fulfillment AS (
  SELECT COALESCE(fulfillment_status, 'unknown') AS status, COUNT(*) AS count
  FROM base GROUP BY 1 ORDER BY count DESC
),
by_store AS (
  SELECT sm.id AS store_id, sm.store_name,
    COUNT(*) AS qty, SUM(b.points_deducted) AS points_burned
  FROM base b
  LEFT JOIN ${RAW}.public_store__master\` sm ON sm.id = b.redeemed_store_id
  WHERE sm.id IS NOT NULL
  GROUP BY 1,2 ORDER BY points_burned DESC LIMIT 25
),
by_used_store AS (
  SELECT sm.id AS store_id, sm.store_name,
    COUNT(*) AS qty, SUM(b.points_deducted) AS points_burned
  FROM base b
  LEFT JOIN ${RAW}.public_store__master\` sm ON sm.id = b.used_store_id
  WHERE b.used_store_id IS NOT NULL AND sm.id IS NOT NULL
  GROUP BY 1,2 ORDER BY qty DESC LIMIT 25
),
by_used_channel AS (
  SELECT sa.id AS channel_id, sa.attribute_name AS channel_name,
    COUNT(*) AS qty, SUM(b.points_deducted) AS points_burned
  FROM base b
  JOIN ${RAW}.public_store_attribute_assignments\` saa
    ON saa.store_id = b.used_store_id AND saa.merchant_id = @merchant_id
  JOIN ${RAW}.public_store_attribute_categories\` sac
    ON sac.id = saa.category_id AND sac.is_store_channel IS TRUE
  JOIN ${RAW}.public_store_attributes\` sa ON sa.id = saa.attribute_id
  WHERE b.used_store_id IS NOT NULL
  GROUP BY 1,2 ORDER BY qty DESC LIMIT 25
)
SELECT TO_JSON(STRUCT(
  (SELECT AS STRUCT * FROM summary) AS summary,
  ARRAY(SELECT AS STRUCT * FROM series) AS series,
  ARRAY(SELECT AS STRUCT * FROM by_reward) AS by_reward,
  ARRAY(SELECT AS STRUCT * FROM by_category) AS by_category,
  ARRAY(SELECT AS STRUCT * FROM by_tier) AS by_tier,
  ARRAY(SELECT AS STRUCT * FROM by_fulfillment) AS by_fulfillment,
  ARRAY(SELECT AS STRUCT * FROM by_store) AS by_store,
  ARRAY(SELECT AS STRUCT * FROM by_used_store) AS by_used_store,
  ARRAY(SELECT AS STRUCT * FROM by_used_channel) AS by_used_channel
)) AS report
`
  const params: BqParam[] = [
    { name: "merchant_id", type: "STRING", value: merchantId },
    { name: "p_from", type: "TIMESTAMP", value: range.from },
    { name: "p_to", type: "TIMESTAMP", value: range.to },
    { name: "frequency", type: "STRING", value: range.frequency },
  ]
  const { rows } = await runQueryJson(sql, params)
  const report = rows[0]?.report
  return typeof report === "string" ? JSON.parse(report) : report
}

export async function redemptionsRows(
  merchantId: string,
  range: ValidatedRange,
) {
  const sql = `
WITH base AS (
  SELECT
    r.id AS redemption_id,
    r.redeemed_at,
    r.used_at,
    r.cancelled,
    r.fulfillment_status,
    r.user_id AS member_id,
    ua.fullname AS member_name,
    ua.member_code,
    tm.tier_name,
    r.reward_id,
    rm.name AS reward_name,
    CAST(r.qty AS NUMERIC) AS qty,
    CAST(r.points_deducted AS NUMERIC) AS points_deducted,
    sm.store_name AS redeemed_store_name,
    sm2.store_name AS used_store_name,
    r.source_type,
    COUNT(*) OVER() AS total_count
  FROM ${SL}.reward_redemptions_ledger\` r
  LEFT JOIN ${SL}.user_accounts\` ua ON ua.id = r.user_id AND ua.merchant_id = @merchant_id
  LEFT JOIN ${RAW}.public_tier__master\` tm ON tm.id = ua.tier_id
  LEFT JOIN ${RAW}.public_reward__master\` rm ON rm.id = r.reward_id
  LEFT JOIN ${RAW}.public_store__master\` sm ON sm.id = r.redeemed_store_id
  LEFT JOIN ${RAW}.public_store__master\` sm2 ON sm2.id = r.used_store_id
  WHERE r.merchant_id = @merchant_id
    AND r.redeemed_at >= @p_from AND r.redeemed_at < @p_to
  ORDER BY r.redeemed_at DESC
  LIMIT @lim OFFSET @off
)
SELECT TO_JSON(STRUCT(
  ARRAY(SELECT AS STRUCT * FROM base) AS \`rows\`,
  COALESCE((SELECT MAX(total_count) FROM base), 0) AS total_count
)) AS report
`
  const params: BqParam[] = [
    { name: "merchant_id", type: "STRING", value: merchantId },
    { name: "p_from", type: "TIMESTAMP", value: range.from },
    { name: "p_to", type: "TIMESTAMP", value: range.to },
    { name: "lim", type: "INT64", value: range.limit },
    { name: "off", type: "INT64", value: range.offset },
  ]
  const { rows } = await runQueryJson(sql, params)
  const report = rows[0]?.report
  return typeof report === "string" ? JSON.parse(report) : report
}
