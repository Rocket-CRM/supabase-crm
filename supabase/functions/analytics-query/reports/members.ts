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

export async function membersChart(
  merchantId: string,
  range: ValidatedRange,
) {
  const sql = `
WITH base AS (
  SELECT
    ua.id AS user_id,
    ua.created_at,
    COALESCE(ua.acquired_at, ua.created_at) AS acquired_ts,
    ua.is_signup_form_complete,
    ua.persona_id,
    ua.tier_id,
    ua.user_type,
    ua.birth_date,
    ua.gender,
    COALESCE(NULLIF(ua.acquisition_source, ''), 'unknown') AS acquisition_source,
    ua.channel_email, ua.channel_sms, ua.channel_line, ua.channel_push,
    ua.marketplace_external_ids,
    ${bucketExpr("COALESCE(ua.acquired_at, ua.created_at)")} AS bucket
  FROM ${SL}.user_accounts\` ua
  WHERE ua.merchant_id = @merchant_id
    AND ua.deleted_at IS NULL
    AND COALESCE(ua.acquired_at, ua.created_at) >= @p_from
    AND COALESCE(ua.acquired_at, ua.created_at) < @p_to
),
summary AS (
  SELECT
    COUNT(*) AS new_signups,
    COUNTIF(is_signup_form_complete IS TRUE) AS form_complete,
    SAFE_DIVIDE(COUNTIF(is_signup_form_complete IS TRUE), COUNT(*)) AS form_complete_rate,
    0 AS referrals_signed_up,
    0 AS active_30d,
    STRUCT(
      COUNTIF(channel_email IS TRUE) AS email,
      COUNTIF(channel_sms IS TRUE) AS sms,
      COUNTIF(channel_line IS TRUE) AS line,
      COUNTIF(channel_push IS TRUE) AS push
    ) AS channel_optin
  FROM base
),
series AS (
  SELECT FORMAT_DATE('%Y-%m-%d', bucket) AS bucket,
    COUNT(*) AS signups,
    COUNTIF(is_signup_form_complete IS TRUE) AS form_completed
  FROM base GROUP BY 1 ORDER BY 1
),
acquisition_by_period AS (
  SELECT FORMAT_DATE('%Y-%m-%d', bucket) AS bucket, COUNT(*) AS signups
  FROM base GROUP BY 1 ORDER BY 1
),
acquisition_by_source AS (
  SELECT FORMAT_DATE('%Y-%m-%d', bucket) AS bucket, acquisition_source, COUNT(*) AS signups
  FROM base GROUP BY 1,2 ORDER BY 1,3 DESC
),
age_group AS (
  SELECT
    CASE
      WHEN birth_date IS NULL THEN 'unknown'
      WHEN DATE_DIFF(CURRENT_DATE('Asia/Bangkok'), birth_date, YEAR) < 18 THEN '<18'
      WHEN DATE_DIFF(CURRENT_DATE('Asia/Bangkok'), birth_date, YEAR) BETWEEN 18 AND 24 THEN '18-24'
      WHEN DATE_DIFF(CURRENT_DATE('Asia/Bangkok'), birth_date, YEAR) BETWEEN 25 AND 34 THEN '25-34'
      WHEN DATE_DIFF(CURRENT_DATE('Asia/Bangkok'), birth_date, YEAR) BETWEEN 35 AND 44 THEN '35-44'
      WHEN DATE_DIFF(CURRENT_DATE('Asia/Bangkok'), birth_date, YEAR) BETWEEN 45 AND 54 THEN '45-54'
      ELSE '55+'
    END AS age_bucket,
    COUNT(*) AS count
  FROM base GROUP BY 1 ORDER BY count DESC
),
by_gender AS (
  SELECT COALESCE(NULLIF(LOWER(gender), ''), 'unknown') AS gender, COUNT(*) AS count
  FROM base GROUP BY 1 ORDER BY count DESC
),
by_persona AS (
  SELECT b.persona_id, pm.persona_name, COUNT(*) AS signups
  FROM base b
  LEFT JOIN ${RAW}.public_persona__master\` pm ON pm.id = b.persona_id
  GROUP BY 1,2 ORDER BY signups DESC LIMIT 25
),
by_user_type AS (
  SELECT CAST(user_type AS STRING) AS user_type, COUNT(*) AS signups
  FROM base GROUP BY 1 ORDER BY signups DESC
),
by_initial_tier AS (
  SELECT b.tier_id, tm.tier_name AS tier_name, COUNT(*) AS signups
  FROM base b
  LEFT JOIN ${RAW}.public_tier__master\` tm ON tm.id = b.tier_id
  GROUP BY 1,2 ORDER BY signups DESC LIMIT 25
),
members_by_tier AS (
  SELECT
    ua.tier_id,
    COALESCE(tm.tier_name, 'Untiered') AS tier_name,
    COUNT(*) AS members
  FROM ${SL}.user_accounts\` ua
  LEFT JOIN ${RAW}.public_tier__master\` tm ON tm.id = ua.tier_id
  WHERE ua.merchant_id = @merchant_id
    AND ua.created_at < @p_to
    AND (ua.deleted_at IS NULL OR ua.deleted_at >= @p_to)
  GROUP BY 1, 2
  ORDER BY members DESC
),
tier_stock_coverage AS (
  SELECT
    COUNT(*) AS total_members,
    COUNTIF(tcl.user_id IS NOT NULL) AS known_from_ledger,
    COUNTIF(tcl.user_id IS NULL) AS inferred_current_tier
  FROM ${SL}.user_accounts\` ua
  LEFT JOIN (
    SELECT DISTINCT user_id
    FROM ${SL}.tier_change_ledger\`
    WHERE merchant_id = @merchant_id
  ) tcl ON tcl.user_id = ua.id
  WHERE ua.merchant_id = @merchant_id
    AND ua.created_at < @p_to
    AND (ua.deleted_at IS NULL OR ua.deleted_at >= @p_to)
),
funnel AS (
  SELECT
    (SELECT COUNT(*) FROM base) AS signed_up,
    (SELECT COUNTIF(is_signup_form_complete IS TRUE) FROM base) AS form_complete,
    (SELECT COUNT(DISTINCT b.user_id) FROM base b
      WHERE EXISTS (
        SELECT 1 FROM ${SL}.purchase_ledger\` pl
        WHERE pl.user_id = b.user_id AND pl.merchant_id = @merchant_id
          AND CAST(pl.status AS STRING)='completed'
      )) AS first_purchase,
    (SELECT COUNT(DISTINCT b.user_id) FROM base b
      WHERE EXISTS (
        SELECT 1 FROM ${SL}.reward_redemptions_ledger\` rr
        WHERE rr.user_id = b.user_id AND rr.merchant_id = @merchant_id
      )) AS first_redemption
)
SELECT TO_JSON(STRUCT(
  (SELECT AS STRUCT * FROM summary) AS summary,
  ARRAY(SELECT AS STRUCT * FROM series) AS series,
  ARRAY(SELECT AS STRUCT * FROM acquisition_by_period) AS acquisition_by_period,
  ARRAY(SELECT AS STRUCT * FROM acquisition_by_source) AS acquisition_by_source,
  ARRAY(SELECT AS STRUCT * FROM age_group) AS age_group,
  ARRAY(SELECT AS STRUCT * FROM by_gender) AS by_gender,
  (SELECT AS STRUCT * FROM funnel) AS funnel,
  ARRAY(SELECT AS STRUCT * FROM by_persona) AS by_persona,
  ARRAY(SELECT AS STRUCT * FROM by_user_type) AS by_user_type,
  ARRAY(SELECT AS STRUCT * FROM by_initial_tier) AS by_initial_tier,
  ARRAY(SELECT AS STRUCT * FROM members_by_tier) AS members_by_tier,
  (SELECT AS STRUCT * FROM tier_stock_coverage) AS tier_stock_coverage,
  ARRAY(SELECT AS STRUCT CAST(NULL AS STRING) AS platform, 0 AS signups) AS by_marketplace,
  ARRAY(SELECT AS STRUCT CAST(NULL AS STRING) AS cohort, 0 AS size,
    0 AS m0, 0 AS m1, 0 AS m2, 0 AS m3, 0 AS m6, 0 AS m12) AS cohort_retention
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

export async function membersRows(
  merchantId: string,
  range: ValidatedRange,
) {
  const sql = `
WITH base AS (
  SELECT
    ua.id AS user_id,
    ua.member_code,
    ua.fullname,
    ua.created_at,
    ua.is_signup_form_complete,
    CAST(ua.user_type AS STRING) AS user_type,
    pm.persona_name,
    tm.tier_name AS tier_name,
    ua.channel_email, ua.channel_sms, ua.channel_line, ua.channel_push,
    ua.acquisition_source,
    ua.acquisition_utm_source,
    ua.acquisition_utm_medium,
    ua.acquisition_utm_campaign,
    COUNT(*) OVER() AS total_count
  FROM ${SL}.user_accounts\` ua
  LEFT JOIN ${RAW}.public_persona__master\` pm ON pm.id = ua.persona_id
  LEFT JOIN ${RAW}.public_tier__master\` tm ON tm.id = ua.tier_id
  WHERE ua.merchant_id = @merchant_id
    AND ua.deleted_at IS NULL
    AND COALESCE(ua.acquired_at, ua.created_at) >= @p_from
    AND COALESCE(ua.acquired_at, ua.created_at) < @p_to
  ORDER BY ua.created_at DESC
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
