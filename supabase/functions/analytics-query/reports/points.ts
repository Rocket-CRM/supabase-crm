import { runQueryJson, type BqParam } from "../lib/bq.ts"
import { monthBounds, type ValidatedRange } from "../lib/params.ts"

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

function strFilter(filters: Record<string, unknown>, key: string): string | null {
  const v = filters[key]
  if (v == null || v === "") return null
  return String(v)
}

/** Honour Overview filters.source_type / component / transaction_type on ledger. */
function ledgerFilterSql(
  filters: Record<string, unknown>,
  alias = "wl",
): { sql: string; params: BqParam[] } {
  const sourceType = strFilter(filters, "source_type")
  const component = strFilter(filters, "component")
  const txnType = strFilter(filters, "transaction_type")
  const clauses: string[] = []
  const params: BqParam[] = []
  if (sourceType) {
    clauses.push(`CAST(${alias}.source_type AS STRING) = @source_type`)
    params.push({ name: "source_type", type: "STRING", value: sourceType })
  }
  if (component) {
    clauses.push(`CAST(${alias}.component AS STRING) = @component`)
    params.push({ name: "component", type: "STRING", value: component })
  }
  if (txnType) {
    clauses.push(`CAST(${alias}.transaction_type AS STRING) = @transaction_type`)
    params.push({ name: "transaction_type", type: "STRING", value: txnType })
  }
  return {
    sql: clauses.map((c) => `AND ${c}`).join("\n    "),
    params,
  }
}

export async function pointsOverview(
  merchantId: string,
  range: ValidatedRange,
) {
  const currency = String(range.filters.currency || "points")
  const extra = ledgerFilterSql(range.filters)
  const sql = `
WITH base AS (
  SELECT
    wl.created_at,
    COALESCE(wl.signed_amount, 0) AS signed_amount,
    CAST(wl.source_type AS STRING) AS source_type,
    CAST(wl.component AS STRING) AS component,
    CAST(wl.transaction_type AS STRING) AS transaction_type,
    wl.user_id,
    ${bucketExpr("wl.created_at")} AS bucket
  FROM ${SL}.wallet_ledger\` wl
  WHERE wl.merchant_id = @merchant_id
    AND wl.created_at >= @p_from AND wl.created_at < @p_to
    AND CAST(wl.currency AS STRING) = @currency
    ${extra.sql}
),
summary AS (
  SELECT
    COALESCE(SUM(IF(signed_amount > 0, signed_amount, 0)), 0) AS earned,
    COALESCE(ABS(SUM(IF(signed_amount < 0 AND source_type <> 'expiry', signed_amount, 0))), 0) AS burned,
    COALESCE(ABS(SUM(IF(source_type = 'expiry', signed_amount, 0))), 0) AS expired,
    COALESCE(SUM(signed_amount), 0) AS net_change
  FROM base
),
liability AS (
  SELECT
    COALESCE(SUM(points_balance), 0) AS outstanding_liability,
    COUNTIF(COALESCE(points_balance, 0) > 0) AS active_wallets
  FROM ${SL}.user_wallet\`
  WHERE merchant_id = @merchant_id
),
series AS (
  SELECT FORMAT_DATE('%Y-%m-%d', bucket) AS bucket,
    COALESCE(SUM(IF(signed_amount > 0, signed_amount, 0)), 0) AS earned,
    COALESCE(ABS(SUM(IF(signed_amount < 0 AND source_type <> 'expiry', signed_amount, 0))), 0) AS burned,
    COALESCE(ABS(SUM(IF(source_type = 'expiry', signed_amount, 0))), 0) AS expired,
    COALESCE(SUM(signed_amount), 0) AS net
  FROM base GROUP BY 1 ORDER BY 1
),
by_earn_source AS (
  SELECT source_type,
    COALESCE(SUM(signed_amount), 0) AS amount,
    COUNT(*) AS txn_count
  FROM base
  WHERE signed_amount > 0
  GROUP BY 1 ORDER BY amount DESC LIMIT 25
),
by_burn_source AS (
  SELECT source_type,
    COALESCE(ABS(SUM(signed_amount)), 0) AS amount,
    COUNT(*) AS txn_count
  FROM base
  WHERE signed_amount < 0 AND source_type <> 'expiry'
  GROUP BY 1 ORDER BY amount DESC LIMIT 25
),
by_component AS (
  SELECT component,
    COALESCE(SUM(IF(signed_amount > 0, signed_amount, 0)), 0)
      - COALESCE(ABS(SUM(IF(signed_amount < 0, signed_amount, 0))), 0) AS amount,
    COUNT(*) AS txn_count
  FROM base GROUP BY 1 ORDER BY ABS(amount) DESC LIMIT 25
),
liability_by_tier AS (
  SELECT
    ua.tier_id,
    tm.tier_name AS tier_name,
    COALESCE(SUM(uw.points_balance), 0) AS balance,
    COUNTIF(COALESCE(uw.points_balance, 0) > 0) AS wallets
  FROM ${SL}.user_wallet\` uw
  LEFT JOIN ${SL}.user_accounts\` ua
    ON ua.id = uw.user_id AND ua.merchant_id = @merchant_id
  LEFT JOIN ${RAW}.public_tier__master\` tm ON tm.id = ua.tier_id
  WHERE uw.merchant_id = @merchant_id
  GROUP BY 1, 2
  HAVING SUM(uw.points_balance) != 0
  ORDER BY balance DESC
)
SELECT TO_JSON(STRUCT(
  STRUCT(
    (SELECT earned FROM summary) AS earned,
    (SELECT burned FROM summary) AS burned,
    (SELECT burned FROM summary) AS burnt,
    (SELECT expired FROM summary) AS expired,
    (SELECT net_change FROM summary) AS net_change,
    (SELECT outstanding_liability FROM liability) AS outstanding_liability,
    (SELECT active_wallets FROM liability) AS active_wallets,
    CAST(NULL AS INT64) AS reconciliation_drift_users
  ) AS summary,
  ARRAY(SELECT AS STRUCT bucket, earned, burned, burned AS burnt, expired, net FROM series) AS series,
  ARRAY(SELECT AS STRUCT source_type, amount, txn_count FROM by_earn_source) AS by_earn_source,
  ARRAY(SELECT AS STRUCT source_type, amount, txn_count FROM by_burn_source) AS by_burn_source,
  ARRAY(SELECT AS STRUCT component, amount, txn_count FROM by_component) AS by_component,
  ARRAY(SELECT AS STRUCT tier_id, tier_name, balance, wallets FROM liability_by_tier) AS liability_by_tier
)) AS report
`
  const params: BqParam[] = [
    { name: "merchant_id", type: "STRING", value: merchantId },
    { name: "p_from", type: "TIMESTAMP", value: range.from },
    { name: "p_to", type: "TIMESTAMP", value: range.to },
    { name: "frequency", type: "STRING", value: range.frequency },
    { name: "currency", type: "STRING", value: currency },
    ...extra.params,
  ]
  const { rows } = await runQueryJson(sql, params)
  const report = rows[0]?.report
  return typeof report === "string" ? JSON.parse(report) : report
}

export async function pointsRows(
  merchantId: string,
  range: ValidatedRange,
) {
  const currency = String(range.filters.currency || "points")
  const extra = ledgerFilterSql(range.filters)
  const sql = `
WITH base AS (
  SELECT
    wl.id AS ledger_id,
    wl.created_at,
    wl.user_id AS member_id,
    ua.fullname AS member_name,
    ua.member_code,
    CAST(wl.transaction_type AS STRING) AS transaction_type,
    CAST(wl.source_type AS STRING) AS source_type,
    CAST(wl.component AS STRING) AS component,
    wl.signed_amount,
    wl.balance_after,
    wl.description,
    wl.code,
    wl.expiry_date,
    COUNT(*) OVER() AS total_count
  FROM ${SL}.wallet_ledger\` wl
  LEFT JOIN ${SL}.user_accounts\` ua ON ua.id = wl.user_id AND ua.merchant_id = @merchant_id
  WHERE wl.merchant_id = @merchant_id
    AND wl.created_at >= @p_from AND wl.created_at < @p_to
    AND CAST(wl.currency AS STRING) = @currency
    ${extra.sql}
  ORDER BY wl.created_at DESC
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
    { name: "currency", type: "STRING", value: currency },
    { name: "lim", type: "INT64", value: range.limit },
    { name: "off", type: "INT64", value: range.offset },
    ...extra.params,
  ]
  const { rows } = await runQueryJson(sql, params)
  const report = rows[0]?.report
  return typeof report === "string" ? JSON.parse(report) : report
}

/**
 * Month × tier roll-forward.
 * Partition-pruned: only users with wallet activity in the selected month;
 * brought-forward scanned only for those users.
 */
export async function pointsMovement(
  merchantId: string,
  month: string,
  currency = "points",
) {
  const { from, to } = monthBounds(month)
  const sql = `
WITH mov_user AS (
  SELECT
    user_id,
    COALESCE(SUM(IF(signed_amount > 0, signed_amount, 0)), 0) AS earned,
    COALESCE(ABS(SUM(IF(signed_amount < 0 AND CAST(source_type AS STRING) <> 'expiry', signed_amount, 0))), 0) AS burned,
    COALESCE(ABS(SUM(IF(CAST(source_type AS STRING) = 'expiry', signed_amount, 0))), 0) AS expired,
    COALESCE(SUM(IF(
      NOT (signed_amount > 0)
      AND NOT (signed_amount < 0 AND CAST(source_type AS STRING) <> 'expiry')
      AND NOT (CAST(source_type AS STRING) = 'expiry'),
      signed_amount, 0)), 0) AS other
  FROM ${SL}.wallet_ledger\`
  WHERE merchant_id = @merchant_id
    AND CAST(currency AS STRING) = @currency
    AND created_at >= @p_from AND created_at < @p_to
  GROUP BY user_id
),
bf_user AS (
  SELECT mu.user_id, COALESCE(SUM(wl.signed_amount), 0) AS brought_forward
  FROM mov_user mu
  JOIN ${SL}.wallet_ledger\` wl
    ON wl.user_id = mu.user_id
    AND wl.merchant_id = @merchant_id
    AND CAST(wl.currency AS STRING) = @currency
    AND wl.created_at < @p_from
  GROUP BY mu.user_id
),
last_tier AS (
  SELECT tc.user_id, tc.to_tier_id
  FROM ${SL}.tier_change_ledger\` tc
  WHERE tc.merchant_id = @merchant_id
    AND tc.created_at < @p_to
    AND tc.user_id IN (SELECT user_id FROM mov_user)
  QUALIFY ROW_NUMBER() OVER (
    PARTITION BY tc.user_id ORDER BY tc.created_at DESC
  ) = 1
),
tiered AS (
  SELECT
    mu.user_id,
    COALESCE(lt.to_tier_id, ua.tier_id) AS tier_id,
    COALESCE(bf.brought_forward, 0) AS brought_forward,
    mu.earned, mu.burned, mu.expired, mu.other
  FROM mov_user mu
  LEFT JOIN bf_user bf ON bf.user_id = mu.user_id
  LEFT JOIN last_tier lt ON lt.user_id = mu.user_id
  LEFT JOIN ${SL}.user_accounts\` ua
    ON ua.id = mu.user_id AND ua.merchant_id = @merchant_id
),
movement_rows AS (
  SELECT
    t.tier_id,
    COALESCE(tm.tier_name, 'No tier') AS tier_name,
    SUM(t.brought_forward) AS brought_forward,
    SUM(t.earned) AS earned,
    SUM(t.burned) AS burned,
    SUM(t.expired) AS expired,
    SUM(t.other) AS other,
    SUM(t.brought_forward) + SUM(t.earned) - SUM(t.burned)
      - SUM(t.expired) + SUM(t.other) AS ending
  FROM tiered t
  LEFT JOIN ${RAW}.public_tier__master\` tm ON tm.id = t.tier_id
  GROUP BY 1, 2
  ORDER BY ending DESC
)
SELECT TO_JSON(STRUCT(
  @month AS month,
  @currency AS currency,
  ARRAY(SELECT AS STRUCT * FROM movement_rows) AS \`rows\`
)) AS report
`
  const params: BqParam[] = [
    { name: "merchant_id", type: "STRING", value: merchantId },
    { name: "p_from", type: "TIMESTAMP", value: from },
    { name: "p_to", type: "TIMESTAMP", value: to },
    { name: "currency", type: "STRING", value: currency },
    { name: "month", type: "STRING", value: month },
  ]
  const { rows } = await runQueryJson(sql, params, "30000000000")
  const report = rows[0]?.report
  return typeof report === "string" ? JSON.parse(report) : report
}

/**
 * Snapshot as-of date — FE SnapshotReportData shape.
 * Closing / holders = ledger signed_amount through as_of EOD (Asia/Bangkok).
 * Period = calendar month of as_of through as_of EOD.
 */
export async function pointsSnapshot(
  merchantId: string,
  asOf: string,
  currency = "points",
) {
  const asOfDay = asOf.slice(0, 10)
  const [y, m] = asOfDay.split("-").map(Number)
  const periodStart = `${y}-${String(m).padStart(2, "0")}-01T00:00:00+07:00`
  const nextM = m === 12 ? 1 : m + 1
  const nextY = m === 12 ? y + 1 : y
  const periodEnd =
    `${nextY}-${String(nextM).padStart(2, "0")}-01T00:00:00+07:00`

  const sql = `
WITH bounds AS (
  SELECT
    DATE(@as_of) AS as_of_d,
    @period_start AS period_start,
    TIMESTAMP(DATE_ADD(DATE(@as_of), INTERVAL 1 DAY), 'Asia/Bangkok') AS as_of_end,
    @period_end AS period_end,
    DATE_TRUNC(DATE_SUB(DATE(@as_of), INTERVAL 11 MONTH), MONTH) AS trend_start
),
wallet AS (
  SELECT
    COUNTIF(COALESCE(as_of_balance, 0) > 0) AS holders,
    COALESCE(SUM(as_of_balance), 0) AS closing_balance
  FROM (
    SELECT
      user_id,
      SUM(signed_amount) AS as_of_balance
    FROM ${SL}.wallet_ledger\`
    CROSS JOIN bounds b
    WHERE merchant_id = @merchant_id
      AND CAST(currency AS STRING) = @currency
      AND created_at < b.as_of_end
    GROUP BY user_id
  )
),
period AS (
  SELECT
    COALESCE(SUM(IF(signed_amount > 0, signed_amount, 0)), 0) AS period_earned,
    COALESCE(ABS(SUM(IF(signed_amount < 0 AND CAST(source_type AS STRING) <> 'expiry', signed_amount, 0))), 0) AS period_burned,
    COALESCE(ABS(SUM(IF(CAST(source_type AS STRING) = 'expiry', signed_amount, 0))), 0) AS period_expired,
    COALESCE(SUM(IF(CAST(component AS STRING) = 'adjustment', signed_amount, 0)), 0) AS period_adjustments,
    COALESCE(SUM(IF(CAST(component AS STRING) = 'reversal', signed_amount, 0)), 0) AS period_reversals
  FROM ${SL}.wallet_ledger\`
  CROSS JOIN bounds b
  WHERE merchant_id = @merchant_id
    AND CAST(currency AS STRING) = @currency
    AND created_at >= b.period_start
    AND created_at < b.as_of_end
),
opening AS (
  SELECT
    (SELECT closing_balance FROM wallet)
      - (SELECT period_earned - period_burned - period_expired FROM period)
      AS opening_balance
),
-- Keep deductible_balance / expiry_date logic. Seed with null/0 expiry
-- yields all-zero buckets — FE shows an explicit empty state (do not invent).
expiry_raw AS (
  SELECT
    COALESCE(SUM(IF(expiry_date IS NOT NULL AND DATE_DIFF(DATE(expiry_date), b.as_of_d, DAY) BETWEEN 0 AND 30,
      GREATEST(COALESCE(deductible_balance, 0), 0), 0)), 0) AS in_30d,
    COALESCE(SUM(IF(expiry_date IS NOT NULL AND DATE_DIFF(DATE(expiry_date), b.as_of_d, DAY) BETWEEN 31 AND 60,
      GREATEST(COALESCE(deductible_balance, 0), 0), 0)), 0) AS in_60d,
    COALESCE(SUM(IF(expiry_date IS NOT NULL AND DATE_DIFF(DATE(expiry_date), b.as_of_d, DAY) BETWEEN 61 AND 90,
      GREATEST(COALESCE(deductible_balance, 0), 0), 0)), 0) AS in_90d,
    COALESCE(SUM(IF(expiry_date IS NOT NULL AND DATE_DIFF(DATE(expiry_date), b.as_of_d, DAY) BETWEEN 91 AND 180,
      GREATEST(COALESCE(deductible_balance, 0), 0), 0)), 0) AS in_180d,
    COALESCE(SUM(IF(expiry_date IS NOT NULL AND DATE_DIFF(DATE(expiry_date), b.as_of_d, DAY) BETWEEN 181 AND 365,
      GREATEST(COALESCE(deductible_balance, 0), 0), 0)), 0) AS in_365d,
    COALESCE(SUM(IF(expiry_date IS NOT NULL AND DATE_DIFF(DATE(expiry_date), b.as_of_d, DAY) > 365,
      GREATEST(COALESCE(deductible_balance, 0), 0), 0)), 0) AS gt_365d,
    COALESCE(SUM(IF(expiry_date IS NULL AND COALESCE(deductible_balance, 0) > 0,
      deductible_balance, 0)), 0) AS no_expiry,
    COUNTIF(expiry_date IS NOT NULL AND DATE_DIFF(DATE(expiry_date), b.as_of_d, DAY) BETWEEN 0 AND 30) AS rows_30d,
    COUNTIF(expiry_date IS NOT NULL AND DATE_DIFF(DATE(expiry_date), b.as_of_d, DAY) BETWEEN 31 AND 60) AS rows_60d,
    COUNTIF(expiry_date IS NOT NULL AND DATE_DIFF(DATE(expiry_date), b.as_of_d, DAY) BETWEEN 61 AND 90) AS rows_90d,
    COUNTIF(expiry_date IS NOT NULL AND DATE_DIFF(DATE(expiry_date), b.as_of_d, DAY) BETWEEN 91 AND 180) AS rows_180d,
    COUNTIF(expiry_date IS NOT NULL AND DATE_DIFF(DATE(expiry_date), b.as_of_d, DAY) BETWEEN 181 AND 365) AS rows_365d,
    COUNTIF(expiry_date IS NOT NULL AND DATE_DIFF(DATE(expiry_date), b.as_of_d, DAY) > 365) AS rows_gt365d,
    COUNTIF(expiry_date IS NULL AND COALESCE(deductible_balance, 0) > 0) AS rows_no_expiry
  FROM ${SL}.wallet_ledger\`
  CROSS JOIN bounds b
  WHERE merchant_id = @merchant_id
    AND CAST(currency AS STRING) = @currency
    AND CAST(transaction_type AS STRING) = 'earn'
    AND signed_amount > 0
    AND COALESCE(deductible_balance, 0) > 0
    AND expiry_processed_at IS NULL
    AND created_at >= TIMESTAMP_SUB(b.as_of_end, INTERVAL 400 DAY)
    AND created_at < b.as_of_end
    AND (expiry_date IS NULL OR DATE(expiry_date) > b.as_of_d)
),
expiry_waterfall AS (
  SELECT
    FORMAT_DATE('%Y-%m-%d', (SELECT as_of_d FROM bounds)) AS as_of,
    [
      STRUCT('<=30d' AS bucket, in_30d AS amount, rows_30d AS wallet_rows),
      STRUCT('31-60d' AS bucket, in_60d AS amount, rows_60d AS wallet_rows),
      STRUCT('61-90d' AS bucket, in_90d AS amount, rows_90d AS wallet_rows),
      STRUCT('91-180d' AS bucket, in_180d AS amount, rows_180d AS wallet_rows),
      STRUCT('181-365d' AS bucket, in_365d AS amount, rows_365d AS wallet_rows),
      STRUCT('>365d' AS bucket, gt_365d AS amount, rows_gt365d AS wallet_rows),
      STRUCT('no_expiry' AS bucket, no_expiry AS amount, rows_no_expiry AS wallet_rows)
    ] AS buckets,
    (in_30d + in_60d + in_90d + in_180d + in_365d + gt_365d + no_expiry) AS total_to_expire,
    CAST(0 AS FLOAT64) AS reconciliation_gap
  FROM expiry_raw
),
month_spine AS (
  SELECT month_start
  FROM UNNEST(GENERATE_DATE_ARRAY(
    (SELECT trend_start FROM bounds),
    DATE_TRUNC((SELECT as_of_d FROM bounds), MONTH),
    INTERVAL 1 MONTH
  )) AS month_start
),
month_mov AS (
  SELECT
    DATE_TRUNC(DATE(DATETIME(wl.created_at, 'Asia/Bangkok')), MONTH) AS month_start,
    COALESCE(SUM(IF(wl.signed_amount > 0, wl.signed_amount, 0)), 0) AS earned,
    COALESCE(ABS(SUM(IF(wl.signed_amount < 0 AND CAST(wl.source_type AS STRING) <> 'expiry', wl.signed_amount, 0))), 0) AS burned,
    COALESCE(ABS(SUM(IF(CAST(wl.source_type AS STRING) = 'expiry', wl.signed_amount, 0))), 0) AS expired
  FROM ${SL}.wallet_ledger\` wl
  CROSS JOIN bounds b
  WHERE wl.merchant_id = @merchant_id
    AND CAST(wl.currency AS STRING) = @currency
    AND wl.created_at >= TIMESTAMP(b.trend_start, 'Asia/Bangkok')
    AND wl.created_at < b.as_of_end
  GROUP BY 1
),
month_rows AS (
  SELECT
    s.month_start,
    COALESCE(m.earned, 0) AS earned,
    COALESCE(m.burned, 0) AS burned,
    COALESCE(m.expired, 0) AS expired,
    COALESCE(m.earned, 0) - COALESCE(m.burned, 0) - COALESCE(m.expired, 0) AS net
  FROM month_spine s
  LEFT JOIN month_mov m ON m.month_start = s.month_start
),
monthly_trend AS (
  SELECT
    FORMAT_DATE('%Y-%m', month_start) AS month,
    (SELECT closing_balance FROM wallet)
      - SUM(net) OVER ()
      + COALESCE(SUM(net) OVER (
          ORDER BY month_start
          ROWS BETWEEN UNBOUNDED PRECEDING AND 1 PRECEDING
        ), 0) AS opening,
    earned,
    burned,
    expired,
    (SELECT closing_balance FROM wallet)
      - SUM(net) OVER ()
      + SUM(net) OVER (
          ORDER BY month_start
          ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
        ) AS closing
  FROM month_rows
)
SELECT TO_JSON(STRUCT(
  @as_of AS as_of,
  @period_start_iso AS period_start,
  @currency AS currency,
  STRUCT(
    (SELECT opening_balance FROM opening) AS opening_balance,
    (SELECT closing_balance FROM wallet) AS closing_balance,
    (SELECT period_earned FROM period) AS period_earned,
    (SELECT period_burned FROM period) AS period_burned,
    (SELECT period_expired FROM period) AS period_expired,
    (SELECT period_adjustments FROM period) AS period_adjustments,
    (SELECT period_reversals FROM period) AS period_reversals,
    (SELECT holders FROM wallet) AS holders
  ) AS summary,
  (SELECT AS STRUCT as_of, buckets, total_to_expire, reconciliation_gap FROM expiry_waterfall) AS expiry_waterfall,
  ARRAY(SELECT AS STRUCT month, opening, earned, burned, expired, closing FROM monthly_trend ORDER BY month) AS monthly_trend
)) AS report
`
  const params: BqParam[] = [
    { name: "merchant_id", type: "STRING", value: merchantId },
    { name: "as_of", type: "STRING", value: asOfDay },
    { name: "currency", type: "STRING", value: currency },
    { name: "period_start", type: "TIMESTAMP", value: periodStart },
    { name: "period_end", type: "TIMESTAMP", value: periodEnd },
    { name: "period_start_iso", type: "STRING", value: periodStart },
  ]
  const { rows } = await runQueryJson(sql, params, "30000000000")
  const report = rows[0]?.report
  return typeof report === "string" ? JSON.parse(report) : report
}

export async function pointsSnapshotRows(
  merchantId: string,
  asOf: string,
  range: Pick<ValidatedRange, "limit" | "offset">,
  currency = "points",
) {
  const asOfDay = asOf.slice(0, 10)
  const [y, m] = asOfDay.split("-").map(Number)
  const periodStart = `${y}-${String(m).padStart(2, "0")}-01T00:00:00+07:00`

  const sql = `
WITH bounds AS (
  SELECT
    DATE(@as_of) AS as_of_d,
    @period_start AS period_start,
    TIMESTAMP(DATE_ADD(DATE(@as_of), INTERVAL 1 DAY), 'Asia/Bangkok') AS as_of_end
),
as_of_wallets AS (
  SELECT
    wl.user_id,
    SUM(wl.signed_amount) AS closing_balance
  FROM ${SL}.wallet_ledger\` wl
  CROSS JOIN bounds b
  WHERE wl.merchant_id = @merchant_id
    AND CAST(wl.currency AS STRING) = @currency
    AND wl.created_at < b.as_of_end
  GROUP BY wl.user_id
  HAVING SUM(wl.signed_amount) > 0
),
wallets AS (
  SELECT
    aw.user_id AS user_id,
    ua.member_code,
    ua.fullname AS member_name,
    ua.tier_id,
    tm.tier_name,
    aw.closing_balance,
    COALESCE(uw.points_balance, 0) AS current_wallet_balance,
    COUNT(*) OVER() AS total_count
  FROM as_of_wallets aw
  LEFT JOIN ${SL}.user_accounts\` ua ON ua.id = aw.user_id AND ua.merchant_id = @merchant_id
  LEFT JOIN ${RAW}.public_tier__master\` tm ON tm.id = ua.tier_id
  LEFT JOIN ${SL}.user_wallet\` uw
    ON uw.user_id = aw.user_id AND uw.merchant_id = @merchant_id
  ORDER BY aw.closing_balance DESC
  LIMIT @lim OFFSET @off
),
period AS (
  SELECT
    wl.user_id,
    COALESCE(SUM(IF(wl.signed_amount > 0, wl.signed_amount, 0)), 0) AS earned,
    COALESCE(ABS(SUM(IF(wl.signed_amount < 0 AND CAST(wl.source_type AS STRING) <> 'expiry', wl.signed_amount, 0))), 0) AS burned,
    COALESCE(ABS(SUM(IF(CAST(wl.source_type AS STRING) = 'expiry', wl.signed_amount, 0))), 0) AS expired,
    COALESCE(SUM(IF(CAST(wl.component AS STRING) = 'adjustment', wl.signed_amount, 0)), 0) AS adjustments,
    COALESCE(SUM(IF(CAST(wl.component AS STRING) = 'reversal', wl.signed_amount, 0)), 0) AS reversals
  FROM ${SL}.wallet_ledger\` wl
  INNER JOIN wallets w ON w.user_id = wl.user_id
  CROSS JOIN bounds b
  WHERE wl.merchant_id = @merchant_id
    AND CAST(wl.currency AS STRING) = @currency
    AND wl.created_at >= b.period_start
    AND wl.created_at < b.as_of_end
  GROUP BY wl.user_id
),
expiry AS (
  SELECT
    wl.user_id,
    COALESCE(SUM(IF(wl.expiry_date IS NOT NULL AND DATE_DIFF(DATE(wl.expiry_date), b.as_of_d, DAY) BETWEEN 0 AND 30,
      GREATEST(COALESCE(wl.deductible_balance, 0), 0), 0)), 0) AS to_expire_30d,
    COALESCE(SUM(IF(wl.expiry_date IS NOT NULL AND DATE_DIFF(DATE(wl.expiry_date), b.as_of_d, DAY) BETWEEN 31 AND 60,
      GREATEST(COALESCE(wl.deductible_balance, 0), 0), 0)), 0) AS to_expire_60d,
    COALESCE(SUM(IF(wl.expiry_date IS NOT NULL AND DATE_DIFF(DATE(wl.expiry_date), b.as_of_d, DAY) BETWEEN 61 AND 90,
      GREATEST(COALESCE(wl.deductible_balance, 0), 0), 0)), 0) AS to_expire_90d,
    COALESCE(SUM(IF(wl.expiry_date IS NOT NULL AND DATE_DIFF(DATE(wl.expiry_date), b.as_of_d, DAY) BETWEEN 91 AND 180,
      GREATEST(COALESCE(wl.deductible_balance, 0), 0), 0)), 0) AS to_expire_180d,
    COALESCE(SUM(IF(wl.expiry_date IS NOT NULL AND DATE_DIFF(DATE(wl.expiry_date), b.as_of_d, DAY) BETWEEN 181 AND 365,
      GREATEST(COALESCE(wl.deductible_balance, 0), 0), 0)), 0) AS to_expire_365d,
    COALESCE(SUM(IF(wl.expiry_date IS NOT NULL AND DATE_DIFF(DATE(wl.expiry_date), b.as_of_d, DAY) > 365,
      GREATEST(COALESCE(wl.deductible_balance, 0), 0), 0)), 0) AS to_expire_gt365d,
    COALESCE(SUM(IF(wl.expiry_date IS NULL AND COALESCE(wl.deductible_balance, 0) > 0,
      wl.deductible_balance, 0)), 0) AS to_expire_no_expiry
  FROM ${SL}.wallet_ledger\` wl
  INNER JOIN wallets w ON w.user_id = wl.user_id
  CROSS JOIN bounds b
  WHERE wl.merchant_id = @merchant_id
    AND CAST(wl.currency AS STRING) = @currency
    AND CAST(wl.transaction_type AS STRING) = 'earn'
    AND wl.signed_amount > 0
    AND COALESCE(wl.deductible_balance, 0) > 0
    AND wl.expiry_processed_at IS NULL
    AND wl.created_at >= TIMESTAMP_SUB(b.as_of_end, INTERVAL 400 DAY)
    AND wl.created_at < b.as_of_end
    AND (wl.expiry_date IS NULL OR DATE(wl.expiry_date) > b.as_of_d)
  GROUP BY wl.user_id
),
base AS (
  SELECT
    w.user_id,
    w.member_code,
    w.member_name,
    w.tier_id,
    w.tier_name,
    w.closing_balance
      - COALESCE(p.earned, 0) + COALESCE(p.burned, 0) + COALESCE(p.expired, 0)
      AS opening_balance,
    COALESCE(p.earned, 0) AS earned,
    COALESCE(p.burned, 0) AS burned,
    COALESCE(p.expired, 0) AS expired,
    COALESCE(p.adjustments, 0) AS adjustments,
    COALESCE(p.reversals, 0) AS reversals,
    w.closing_balance AS closing_balance,
    w.current_wallet_balance,
    w.closing_balance - w.current_wallet_balance AS balance_diff,
    COALESCE(e.to_expire_30d, 0) AS to_expire_30d,
    COALESCE(e.to_expire_60d, 0) AS to_expire_60d,
    COALESCE(e.to_expire_90d, 0) AS to_expire_90d,
    COALESCE(e.to_expire_180d, 0) AS to_expire_180d,
    COALESCE(e.to_expire_365d, 0) AS to_expire_365d,
    COALESCE(e.to_expire_gt365d, 0) AS to_expire_gt365d,
    COALESCE(e.to_expire_no_expiry, 0) AS to_expire_no_expiry,
    COALESCE(e.to_expire_30d, 0) + COALESCE(e.to_expire_60d, 0)
      + COALESCE(e.to_expire_90d, 0) + COALESCE(e.to_expire_180d, 0)
      + COALESCE(e.to_expire_365d, 0) + COALESCE(e.to_expire_gt365d, 0)
      + COALESCE(e.to_expire_no_expiry, 0) AS total_to_expire,
    w.total_count
  FROM wallets w
  LEFT JOIN period p ON p.user_id = w.user_id
  LEFT JOIN expiry e ON e.user_id = w.user_id
)
SELECT TO_JSON(STRUCT(
  ARRAY(SELECT AS STRUCT
    user_id, member_code, member_name, tier_id, tier_name,
    opening_balance, earned, burned, expired, adjustments, reversals,
    closing_balance, current_wallet_balance, balance_diff,
    to_expire_30d, to_expire_60d, to_expire_90d, to_expire_180d,
    to_expire_365d, to_expire_gt365d, to_expire_no_expiry, total_to_expire
  FROM base) AS \`rows\`,
  COALESCE((SELECT MAX(total_count) FROM base), 0) AS total_count
)) AS report
`
  const params: BqParam[] = [
    { name: "merchant_id", type: "STRING", value: merchantId },
    { name: "as_of", type: "STRING", value: asOfDay },
    { name: "currency", type: "STRING", value: currency },
    { name: "period_start", type: "TIMESTAMP", value: periodStart },
    { name: "lim", type: "INT64", value: range.limit },
    { name: "off", type: "INT64", value: range.offset },
  ]
  const { rows } = await runQueryJson(sql, params, "30000000000")
  const report = rows[0]?.report
  return typeof report === "string" ? JSON.parse(report) : report
}
