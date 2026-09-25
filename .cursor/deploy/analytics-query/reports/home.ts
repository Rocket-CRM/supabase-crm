import { runQueryJson, type BqParam } from "../lib/bq.ts"
import type { AnalyticsRequest, ValidatedRange } from "../lib/params.ts"
import { validateRange } from "../lib/params.ts"

const SL = "`rocket-prod-analytics.serving_loyalty"

/** Last 30 days ending now (ISO), used when from/to omitted. */
export function defaultLast30Days(): { from: string; to: string } {
  const to = new Date()
  const from = new Date(to.getTime() - 30 * 24 * 60 * 60 * 1000)
  return { from: from.toISOString(), to: to.toISOString() }
}

export function resolveHomeRange(req: AnalyticsRequest): ValidatedRange {
  if (req.from && req.to) return validateRange(req)
  const { from, to } = defaultLast30Days()
  return validateRange({ ...req, from, to })
}

/**
 * Lean home KPI strip: four windowed metrics + all-time total_members.
 * Report id: home.metrics
 */
export async function homeMetrics(
  merchantId: string,
  range: ValidatedRange,
) {
  const sql = `
WITH member_added AS (
  SELECT COUNT(*) AS c
  FROM ${SL}.user_accounts\` ua
  WHERE ua.merchant_id = @merchant_id
    AND ua.deleted_at IS NULL
    AND COALESCE(ua.acquired_at, ua.created_at) >= @p_from
    AND COALESCE(ua.acquired_at, ua.created_at) < @p_to
),
earn AS (
  SELECT COALESCE(SUM(IF(wl.signed_amount > 0, wl.signed_amount, 0)), 0) AS c
  FROM ${SL}.wallet_ledger\` wl
  WHERE wl.merchant_id = @merchant_id
    AND wl.created_at >= @p_from AND wl.created_at < @p_to
    AND CAST(wl.currency AS STRING) = 'points'
),
redeemer AS (
  SELECT COUNT(DISTINCT r.user_id) AS c
  FROM ${SL}.reward_redemptions_ledger\` r
  WHERE r.merchant_id = @merchant_id
    AND r.redeemed_at >= @p_from AND r.redeemed_at < @p_to
),
driven_revenue AS (
  SELECT COALESCE(SUM(
    IF(
      CAST(pl.record_type AS STRING) = 'credit'
      AND CAST(pl.status AS STRING) = 'completed',
      pl.final_amount,
      0
    )
  ), 0) AS c
  FROM ${SL}.purchase_ledger\` pl
  WHERE pl.merchant_id = @merchant_id
    AND pl.transaction_date >= @p_from
    AND pl.transaction_date < @p_to
),
total_members AS (
  SELECT COUNT(*) AS c
  FROM ${SL}.user_accounts\` ua
  WHERE ua.merchant_id = @merchant_id
    AND ua.deleted_at IS NULL
)
SELECT TO_JSON(STRUCT(
  STRUCT(
    @p_from AS \`from\`,
    @p_to AS \`to\`,
    'Last 30 days' AS label
  ) AS period,
  (SELECT c FROM member_added) AS member_added,
  (SELECT c FROM earn) AS earn,
  (SELECT c FROM redeemer) AS redeemer,
  (SELECT c FROM driven_revenue) AS driven_revenue,
  (SELECT c FROM total_members) AS total_members
)) AS report
`
  const params: BqParam[] = [
    { name: "merchant_id", type: "STRING", value: merchantId },
    { name: "p_from", type: "TIMESTAMP", value: range.from },
    { name: "p_to", type: "TIMESTAMP", value: range.to },
  ]
  const { rows } = await runQueryJson(sql, params)
  const report = rows[0]?.report
  return typeof report === "string" ? JSON.parse(report) : report
}
