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

function statusParams(filters: Record<string, unknown>): string[] {
  const s = filters.status
  if (Array.isArray(s) && s.length) return s.map(String)
  return ["completed"]
}

export async function purchasesChart(
  merchantId: string,
  range: ValidatedRange,
) {
  const recordType = String(filtersStr(range.filters, "record_type") || "credit")
  const statuses = statusParams(range.filters)
  const sql = `
WITH base AS (
  SELECT
    pl.id AS transaction_id,
    pl.transaction_number,
    pl.transaction_date,
    pl.user_id,
    CAST(pl.status AS STRING) AS status,
    CAST(pl.record_type AS STRING) AS record_type,
    CAST(pl.final_amount AS NUMERIC) AS final_amount,
    pl.store_id,
    pl.earning_channel_id,
    pl.earn_currency,
    ${bucketExpr("pl.transaction_date")} AS bucket
  FROM ${SL}.purchase_ledger\` pl
  WHERE pl.merchant_id = @merchant_id
    AND pl.transaction_date >= @p_from
    AND pl.transaction_date < @p_to
    AND CAST(pl.status AS STRING) IN UNNEST(@statuses)
    AND CAST(pl.record_type AS STRING) = @record_type
),
base_users AS (SELECT DISTINCT user_id FROM base WHERE user_id IS NOT NULL),
new_buyer_users AS (
  SELECT bu.user_id FROM base_users bu
  WHERE NOT EXISTS (
    SELECT 1 FROM ${SL}.purchase_ledger\` pl
    WHERE pl.user_id = bu.user_id AND pl.merchant_id = @merchant_id
      AND CAST(pl.status AS STRING) = 'completed'
      AND pl.transaction_date < @p_from
  )
),
summary AS (
  SELECT
    COALESCE(SUM(IF(record_type='credit' AND status='completed', final_amount, 0)), 0) AS net_sales,
    COALESCE(ABS(SUM(IF(record_type='debit' OR status='refunded', final_amount, 0))), 0) AS refunds,
    COUNT(DISTINCT IF(record_type='credit' AND status='completed', transaction_number, NULL)) AS orders,
    COUNT(DISTINCT IF(record_type='credit' AND status='completed', user_id, NULL)) AS buyers,
    COUNTIF(earn_currency IS TRUE) AS earn_eligible_count,
    COUNT(*) AS total_count
  FROM base
),
series_raw AS (
  SELECT bucket,
    SUM(IF(record_type='credit' AND status='completed', final_amount, 0)) AS net,
    ABS(SUM(IF(record_type='debit' OR status='refunded', final_amount, 0))) AS refunds,
    COUNT(DISTINCT IF(record_type='credit' AND status='completed', transaction_number, NULL)) AS orders
  FROM base GROUP BY 1
),
series AS (
  SELECT FORMAT_DATE('%Y-%m-%d', bucket) AS bucket,
    COALESCE(net,0) AS net, COALESCE(refunds,0) AS refunds,
    COALESCE(net,0)+COALESCE(refunds,0) AS gross,
    COALESCE(orders,0) AS orders,
    IF(COALESCE(orders,0)>0, ROUND(COALESCE(net,0)/orders, 2), 0) AS aov
  FROM series_raw ORDER BY bucket
),
buyers_classified AS (
  SELECT b.bucket, b.user_id, (nbu.user_id IS NOT NULL) AS is_new
  FROM base b LEFT JOIN new_buyer_users nbu ON nbu.user_id = b.user_id
  WHERE b.record_type='credit' AND b.status='completed'
  GROUP BY 1,2,3
),
buyers_series AS (
  SELECT FORMAT_DATE('%Y-%m-%d', bucket) AS bucket,
    COUNTIF(is_new) AS new_buyers,
    COUNTIF(NOT is_new) AS returning_buyers
  FROM buyers_classified GROUP BY 1 ORDER BY 1
),
by_store AS (
  SELECT sm.id AS store_id, sm.store_name,
    SUM(IF(b.record_type='credit' AND b.status='completed', b.final_amount, 0)) AS net_sales,
    COUNT(DISTINCT IF(b.record_type='credit' AND b.status='completed', b.transaction_number, NULL)) AS orders
  FROM base b
  LEFT JOIN ${RAW}.public_store__master\` sm ON sm.id = b.store_id
  WHERE sm.id IS NOT NULL
  GROUP BY 1,2 ORDER BY net_sales DESC LIMIT 25
),
by_channel AS (
  SELECT ec.id AS earning_channel_id, ec.channel_name,
    SUM(IF(b.record_type='credit' AND b.status='completed', b.final_amount, 0)) AS net_sales,
    COUNT(DISTINCT IF(b.record_type='credit' AND b.status='completed', b.transaction_number, NULL)) AS orders
  FROM base b
  LEFT JOIN ${RAW}.public_earn__channel\` ec ON ec.id = b.earning_channel_id
  WHERE ec.id IS NOT NULL
  GROUP BY 1,2 ORDER BY net_sales DESC LIMIT 25
),
items AS (
  SELECT b.transaction_id, b.final_amount, b.record_type, b.status,
    pi.sku_id, CAST(pi.quantity AS NUMERIC) AS quantity,
    sk.sku_code, pm.name AS product_name, pm.brand_id, pm.category_id
  FROM base b
  JOIN ${SL}.purchase_items_ledger\` pi ON pi.transaction_id = b.transaction_id
  LEFT JOIN ${RAW}.public_product__sku__master\` sk ON sk.id = pi.sku_id
  LEFT JOIN ${RAW}.public_product__master\` pm ON pm.id = sk.product_id
),
txn_qty AS (
  SELECT transaction_id, NULLIF(SUM(quantity),0) AS total_qty FROM items GROUP BY 1
),
by_category AS (
  SELECT cm.id AS category_id, cm.name AS category_name,
    SUM(IF(i.record_type='credit' AND i.status='completed' AND tq.total_qty IS NOT NULL,
      i.quantity * (i.final_amount / tq.total_qty), 0)) AS net_sales,
    SUM(i.quantity) AS items
  FROM items i
  LEFT JOIN txn_qty tq ON tq.transaction_id = i.transaction_id
  LEFT JOIN ${RAW}.public_product__category__master\` cm ON cm.id = i.category_id
  WHERE cm.id IS NOT NULL
  GROUP BY 1,2 ORDER BY net_sales DESC LIMIT 25
),
by_brand AS (
  SELECT bm.id AS brand_id, bm.name AS brand_name,
    SUM(IF(i.record_type='credit' AND i.status='completed' AND tq.total_qty IS NOT NULL,
      i.quantity * (i.final_amount / tq.total_qty), 0)) AS net_sales,
    SUM(i.quantity) AS items
  FROM items i
  LEFT JOIN txn_qty tq ON tq.transaction_id = i.transaction_id
  LEFT JOIN ${RAW}.public_product__brand__master\` bm ON bm.id = i.brand_id
  WHERE bm.id IS NOT NULL
  GROUP BY 1,2 ORDER BY net_sales DESC LIMIT 25
),
by_sku AS (
  SELECT i.sku_id, i.sku_code, i.product_name,
    SUM(IF(i.record_type='credit' AND i.status='completed' AND tq.total_qty IS NOT NULL,
      i.quantity * (i.final_amount / tq.total_qty), 0)) AS net_sales,
    SUM(i.quantity) AS items
  FROM items i
  LEFT JOIN txn_qty tq ON tq.transaction_id = i.transaction_id
  WHERE i.sku_id IS NOT NULL
  GROUP BY 1,2,3 ORDER BY net_sales DESC LIMIT 25
)
SELECT TO_JSON(STRUCT(
  STRUCT(
    (SELECT net_sales FROM summary) AS net_sales,
    (SELECT net_sales + refunds FROM summary) AS gross_sales,
    (SELECT refunds FROM summary) AS refunds,
    (SELECT orders FROM summary) AS orders,
    IF((SELECT orders FROM summary)>0,
      ROUND((SELECT net_sales FROM summary)/(SELECT orders FROM summary), 2), 0) AS aov,
    (SELECT buyers FROM summary) AS buyers,
    (SELECT COUNT(*) FROM new_buyer_users) AS new_buyers,
    GREATEST((SELECT buyers FROM summary) - (SELECT COUNT(*) FROM new_buyer_users), 0) AS returning_buyers,
    (SELECT COALESCE(SUM(quantity),0) FROM items) AS items_sold,
    IF((SELECT total_count FROM summary)>0,
      ROUND((SELECT earn_eligible_count FROM summary)/(SELECT total_count FROM summary), 4), 0)
      AS earn_eligible_pct
  ) AS summary,
  ARRAY(SELECT AS STRUCT * FROM series) AS series,
  ARRAY(SELECT AS STRUCT bucket, new_buyers AS \`new\`, returning_buyers AS \`returning\` FROM buyers_series) AS buyers_series,
  ARRAY(SELECT AS STRUCT * FROM by_store) AS by_store,
  ARRAY(SELECT AS STRUCT * FROM by_channel) AS by_channel,
  ARRAY(SELECT AS STRUCT * FROM by_category) AS by_category,
  ARRAY(SELECT AS STRUCT * FROM by_brand) AS by_brand,
  ARRAY(SELECT AS STRUCT * FROM by_sku) AS by_sku
)) AS report
`
  const params: BqParam[] = [
    { name: "merchant_id", type: "STRING", value: merchantId },
    { name: "p_from", type: "TIMESTAMP", value: range.from },
    { name: "p_to", type: "TIMESTAMP", value: range.to },
    { name: "frequency", type: "STRING", value: range.frequency },
    { name: "record_type", type: "STRING", value: recordType },
    { name: "statuses", type: "ARRAY", arrayType: "STRING", value: statuses },
  ]
  const { rows } = await runQueryJson(sql, params)
  const report = rows[0]?.report
  return typeof report === "string" ? JSON.parse(report) : report
}

export async function purchasesRows(
  merchantId: string,
  range: ValidatedRange,
) {
  const recordType = String(filtersStr(range.filters, "record_type") || "credit")
  const statuses = statusParams(range.filters)
  const sql = `
WITH base AS (
  SELECT
    pl.id AS transaction_id,
    pl.transaction_number,
    pl.transaction_date,
    CAST(pl.status AS STRING) AS status,
    CAST(pl.record_type AS STRING) AS record_type,
    pl.user_id AS member_id,
    ua.fullname AS member_name,
    ua.member_code,
    sm.store_name,
    ec.channel_name,
    CAST(pl.final_amount AS NUMERIC) AS final_amount,
    CAST(pl.discount_amount AS NUMERIC) AS discount_amount,
    pl.earn_currency,
    pl.currency_processed_at,
    (SELECT COUNT(*) FROM ${SL}.purchase_items_ledger\` pi WHERE pi.transaction_id = pl.id) AS item_count,
    ua.acquisition_source,
    ua.acquisition_utm_source,
    ua.acquisition_utm_medium,
    ua.acquisition_utm_campaign,
    ua.acquisition_utm_term,
    ua.acquisition_utm_content,
    ua.acquisition_campaign_id,
    CAST(NULL AS STRING) AS attributed_campaigns,
    CAST(NULL AS STRING) AS primary_campaign_id,
    CAST(NULL AS STRING) AS primary_campaign_name,
    CAST(NULL AS NUMERIC) AS attributed_amount,
    COUNT(*) OVER() AS total_count
  FROM ${SL}.purchase_ledger\` pl
  LEFT JOIN ${SL}.user_accounts\` ua ON ua.id = pl.user_id AND ua.merchant_id = @merchant_id
  LEFT JOIN ${RAW}.public_store__master\` sm ON sm.id = pl.store_id
  LEFT JOIN ${RAW}.public_earn__channel\` ec ON ec.id = pl.earning_channel_id
  WHERE pl.merchant_id = @merchant_id
    AND pl.transaction_date >= @p_from AND pl.transaction_date < @p_to
    AND CAST(pl.status AS STRING) IN UNNEST(@statuses)
    AND CAST(pl.record_type AS STRING) = @record_type
  ORDER BY pl.transaction_date DESC
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
    { name: "record_type", type: "STRING", value: recordType },
    { name: "statuses", type: "ARRAY", arrayType: "STRING", value: statuses },
    { name: "lim", type: "INT64", value: range.limit },
    { name: "off", type: "INT64", value: range.offset },
  ]
  const { rows } = await runQueryJson(sql, params)
  const report = rows[0]?.report
  return typeof report === "string" ? JSON.parse(report) : report
}

function filtersStr(
  filters: Record<string, unknown>,
  key: string,
): string | null {
  const v = filters[key]
  if (v === null || v === undefined || v === "") return null
  return String(v)
}
