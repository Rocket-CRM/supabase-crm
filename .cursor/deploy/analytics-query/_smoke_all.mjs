/**
 * Node smoke: dynamic-import Deno TS won't work; instead shell out isn't ideal.
 * This script uses the google-auth + fetch pattern matching lib/bq.ts,
 * and inlines calls by spawning `npx tsx` if available, else runs SQL extracts.
 *
 * Simpler path: use child_process to run each report via a tiny tsx runner.
 */
import { createSign } from "node:crypto"
import { readFileSync } from "node:fs"
import { pathToFileURL } from "node:url"
import { createRequire } from "node:module"

const sa = JSON.parse(
  process.env.BQ_SERVICE_ACCOUNT_JSON ||
    readFileSync(
      "/Users/rangwan/Downloads/bq-readonly-external-rocket-prod-analytics.json",
      "utf8",
    ),
)
const PROJECT = process.env.BQ_PROJECT_ID || "rocket-prod-analytics"
const LOCATION = process.env.BQ_LOCATION || "asia-southeast1"
const MID = "10de947e-ff05-4e2b-88ff-c853e5a69cb3"
const FROM = "2026-06-01T00:00:00.000+07:00"
const TO = "2026-07-01T00:00:00.000+07:00"

let cached = null
async function token() {
  const now = Math.floor(Date.now() / 1000)
  if (cached && cached.exp > now + 60) return cached.token
  const header = Buffer.from(JSON.stringify({ alg: "RS256", typ: "JWT" })).toString("base64url")
  const claim = Buffer.from(
    JSON.stringify({
      iss: sa.client_email,
      sub: sa.client_email,
      aud: "https://oauth2.googleapis.com/token",
      iat: now,
      exp: now + 3600,
      scope: "https://www.googleapis.com/auth/bigquery",
    }),
  ).toString("base64url")
  const data = `${header}.${claim}`
  const signer = createSign("RSA-SHA256")
  signer.update(data)
  const sig = signer.sign(sa.private_key, "base64url")
  const jwt = `${data}.${sig}`
  const res = await fetch("https://oauth2.googleapis.com/token", {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({
      grant_type: "urn:ietf:params:oauth:grant-type:jwt-bearer",
      assertion: jwt,
    }),
  })
  const body = await res.json()
  if (!res.ok) throw new Error(`token: ${JSON.stringify(body)}`)
  cached = { token: body.access_token, exp: now + Number(body.expires_in || 3600) }
  return cached.token
}

function toParam(p) {
  if (p.type === "ARRAY") {
    return {
      name: p.name,
      parameterType: { type: "ARRAY", arrayType: { type: p.arrayType } },
      parameterValue: { arrayValues: p.value.map((v) => ({ value: v })) },
    }
  }
  return {
    name: p.name,
    parameterType: { type: p.type },
    parameterValue: {
      value: p.value === null || p.value === undefined ? undefined : String(p.value),
    },
  }
}

async function runQueryJson(sql, params, maximumBytesBilled = "30000000000") {
  const t = await token()
  const res = await fetch(
    `https://bigquery.googleapis.com/bigquery/v2/projects/${PROJECT}/queries`,
    {
      method: "POST",
      headers: {
        Authorization: `Bearer ${t}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({
        query: sql,
        useLegacySql: false,
        location: LOCATION,
        parameterMode: "NAMED",
        queryParameters: params.map(toParam),
        maximumBytesBilled,
        timeoutMs: 120000,
      }),
    },
  )
  const body = await res.json()
  if (!res.ok || body.error) {
    throw new Error(body.error?.message || JSON.stringify(body).slice(0, 400))
  }
  const fields = (body.schema?.fields || []).map((f) => ({ name: f.name, type: f.type }))
  const rows = (body.rows || []).map((r) => {
    const obj = {}
    r.f.forEach((cell, i) => {
      let v = cell.v
      if (fields[i].type === "JSON" && typeof v === "string") {
        try {
          v = JSON.parse(v)
        } catch {}
      }
      obj[fields[i].name] = v
    })
    return obj
  })
  return { rows, bytes: body.totalBytesProcessed }
}

function unwrap(rows) {
  const report = rows[0]?.report
  return typeof report === "string" ? JSON.parse(report) : report
}

const SL = "`rocket-prod-analytics.serving_loyalty"
const RAW = "`rocket-prod-analytics.raw_supabase_prod"

function bucketExpr(tsCol) {
  return `CASE @frequency
    WHEN 'day' THEN DATE(DATETIME(${tsCol}, 'Asia/Bangkok'))
    WHEN 'week' THEN DATE_TRUNC(DATE(DATETIME(${tsCol}, 'Asia/Bangkok')), WEEK(MONDAY))
    WHEN 'month' THEN DATE_TRUNC(DATE(DATETIME(${tsCol}, 'Asia/Bangkok')), MONTH)
    ELSE DATE_TRUNC(DATE(DATETIME(${tsCol}, 'Asia/Bangkok')), QUARTER)
  END`
}

const baseParams = (extra = []) => [
  { name: "merchant_id", type: "STRING", value: MID },
  { name: "p_from", type: "TIMESTAMP", value: FROM },
  { name: "p_to", type: "TIMESTAMP", value: TO },
  ...extra,
]

// Import SQL builders by reading the TS source is fragile — instead re-call
// the same SQL from the actual files via dynamic eval of extracted functions.
// Easiest robust approach: use tsx to execute the Deno-compatible modules after
// rewriting jsr imports. Prefer spawning the TypeScript handlers with a shim.

async function loadHandlers() {
  // Use tsx with a shim for jsr:/https: imports
  const { register } = await import("node:module")
  // Fall through: inline minimal SQL copies matching deployed handlers for smoke only
  return null
}

// --- Handlers mirrored from deployed TS (must stay in sync) ---

async function purchases() {
  const sql = `
WITH base AS (
  SELECT pl.id AS transaction_id, pl.transaction_number, pl.transaction_date, pl.user_id,
    CAST(pl.status AS STRING) AS status, CAST(pl.record_type AS STRING) AS record_type,
    CAST(pl.final_amount AS NUMERIC) AS final_amount, pl.store_id, pl.earning_channel_id, pl.earn_currency,
    ${bucketExpr("pl.transaction_date")} AS bucket
  FROM ${SL}.purchase_ledger\` pl
  WHERE pl.merchant_id = @merchant_id AND pl.transaction_date >= @p_from AND pl.transaction_date < @p_to
    AND CAST(pl.status AS STRING) IN UNNEST(@statuses) AND CAST(pl.record_type AS STRING) = @record_type
),
summary AS (
  SELECT COALESCE(SUM(final_amount),0) AS net_sales, COUNT(DISTINCT transaction_number) AS orders,
    COUNT(DISTINCT user_id) AS buyers, COUNT(*) AS total_count FROM base
),
buyers_series AS (
  SELECT FORMAT_DATE('%Y-%m-%d', bucket) AS bucket, 0 AS new_buyers, COUNT(DISTINCT user_id) AS returning_buyers
  FROM base GROUP BY 1
)
SELECT TO_JSON(STRUCT(
  (SELECT AS STRUCT * FROM summary) AS summary,
  ARRAY(SELECT AS STRUCT bucket, new_buyers AS \`new\`, returning_buyers AS \`returning\` FROM buyers_series LIMIT 3) AS buyers_series
)) AS report`
  const { rows, bytes } = await runQueryJson(sql, baseParams([
    { name: "frequency", type: "STRING", value: "day" },
    { name: "record_type", type: "STRING", value: "credit" },
    { name: "statuses", type: "ARRAY", arrayType: "STRING", value: ["completed"] },
  ]))
  return { data: unwrap(rows), bytes }
}

async function purchasesRows() {
  const sql = `
WITH base AS (
  SELECT pl.id AS transaction_id, pl.transaction_number, pl.transaction_date,
    CAST(pl.status AS STRING) AS status, CAST(pl.final_amount AS NUMERIC) AS final_amount,
    COUNT(*) OVER() AS total_count
  FROM ${SL}.purchase_ledger\` pl
  WHERE pl.merchant_id = @merchant_id AND pl.transaction_date >= @p_from AND pl.transaction_date < @p_to
    AND CAST(pl.status AS STRING) IN UNNEST(@statuses) AND CAST(pl.record_type AS STRING) = @record_type
  ORDER BY pl.transaction_date DESC LIMIT @lim OFFSET @off
)
SELECT TO_JSON(STRUCT(
  ARRAY(SELECT AS STRUCT * FROM base) AS rows,
  COALESCE((SELECT MAX(total_count) FROM base),0) AS total_count
)) AS report`
  const { rows, bytes } = await runQueryJson(sql, baseParams([
    { name: "record_type", type: "STRING", value: "credit" },
    { name: "statuses", type: "ARRAY", arrayType: "STRING", value: ["completed"] },
    { name: "lim", type: "INT64", value: 5 },
    { name: "off", type: "INT64", value: 0 },
  ]))
  return { data: unwrap(rows), bytes }
}

async function redemptions() {
  const sql = `
WITH base AS (
  SELECT r.id, r.reward_id, CAST(r.qty AS NUMERIC) AS qty, CAST(r.points_deducted AS NUMERIC) AS points_deducted,
    r.success, r.cancelled, r.fulfillment_status, r.user_id,
    ${bucketExpr("r.redeemed_at")} AS bucket
  FROM ${SL}.reward_redemptions_ledger\` r
  WHERE r.merchant_id = @merchant_id AND r.redeemed_at >= @p_from AND r.redeemed_at < @p_to
),
summary AS (
  SELECT COUNT(*) AS redemptions, COUNT(DISTINCT user_id) AS unique_redeemers,
    COALESCE(SUM(points_deducted),0) AS points_burned,
    SAFE_DIVIDE(COUNTIF(success IS TRUE), COUNT(*)) AS success_rate
  FROM base
),
by_category AS (
  SELECT rc.id AS category_id, rc.name AS category_name, SUM(b.qty) AS qty, SUM(b.points_deducted) AS points_burned
  FROM base b
  LEFT JOIN ${RAW}.public_reward__master\` rm ON rm.id = b.reward_id
  LEFT JOIN UNNEST(IFNULL(rm.category_id, CAST([] AS ARRAY<STRING>))) AS cat_id
  LEFT JOIN ${RAW}.public_reward__category\` rc ON rc.id = cat_id
  WHERE rc.id IS NOT NULL
  GROUP BY 1,2 ORDER BY points_burned DESC LIMIT 5
)
SELECT TO_JSON(STRUCT(
  (SELECT AS STRUCT * FROM summary) AS summary,
  ARRAY(SELECT AS STRUCT * FROM by_category) AS by_category
)) AS report`
  const { rows, bytes } = await runQueryJson(sql, baseParams([
    { name: "frequency", type: "STRING", value: "day" },
  ]))
  return { data: unwrap(rows), bytes }
}

async function redemptionsRows() {
  const sql = `
WITH base AS (
  SELECT r.id AS redemption_id, r.redeemed_at, CAST(r.points_deducted AS NUMERIC) AS points_deducted,
    COUNT(*) OVER() AS total_count
  FROM ${SL}.reward_redemptions_ledger\` r
  WHERE r.merchant_id = @merchant_id AND r.redeemed_at >= @p_from AND r.redeemed_at < @p_to
  ORDER BY r.redeemed_at DESC LIMIT @lim OFFSET @off
)
SELECT TO_JSON(STRUCT(
  ARRAY(SELECT AS STRUCT * FROM base) AS rows,
  COALESCE((SELECT MAX(total_count) FROM base),0) AS total_count
)) AS report`
  const { rows, bytes } = await runQueryJson(sql, baseParams([
    { name: "lim", type: "INT64", value: 5 },
    { name: "off", type: "INT64", value: 0 },
  ]))
  return { data: unwrap(rows), bytes }
}

async function members() {
  const sql = `
WITH base AS (
  SELECT ua.id AS user_id, ua.created_at, ua.is_signup_form_complete, ua.tier_id, ua.persona_id,
    ${bucketExpr("ua.created_at")} AS bucket
  FROM ${SL}.user_accounts\` ua
  WHERE ua.merchant_id = @merchant_id AND ua.deleted_at IS NULL
    AND ua.created_at >= @p_from AND ua.created_at < @p_to
),
summary AS (
  SELECT COUNT(*) AS new_signups, COUNTIF(is_signup_form_complete IS TRUE) AS form_complete,
    SAFE_DIVIDE(COUNTIF(is_signup_form_complete IS TRUE), COUNT(*)) AS form_complete_rate
  FROM base
)
SELECT TO_JSON(STRUCT((SELECT AS STRUCT * FROM summary) AS summary)) AS report`
  const { rows, bytes } = await runQueryJson(sql, baseParams([
    { name: "frequency", type: "STRING", value: "day" },
  ]))
  return { data: unwrap(rows), bytes }
}

async function membersRows() {
  const sql = `
WITH base AS (
  SELECT ua.id AS user_id, ua.member_code, ua.fullname, ua.created_at, COUNT(*) OVER() AS total_count
  FROM ${SL}.user_accounts\` ua
  WHERE ua.merchant_id = @merchant_id AND ua.deleted_at IS NULL
    AND ua.created_at >= @p_from AND ua.created_at < @p_to
  ORDER BY ua.created_at DESC LIMIT @lim OFFSET @off
)
SELECT TO_JSON(STRUCT(
  ARRAY(SELECT AS STRUCT * FROM base) AS rows,
  COALESCE((SELECT MAX(total_count) FROM base),0) AS total_count
)) AS report`
  const { rows, bytes } = await runQueryJson(sql, baseParams([
    { name: "lim", type: "INT64", value: 5 },
    { name: "off", type: "INT64", value: 0 },
  ]))
  return { data: unwrap(rows), bytes }
}

async function pointsOverview() {
  const sql = `
WITH base AS (
  SELECT COALESCE(signed_amount,0) AS signed_amount, CAST(source_type AS STRING) AS source_type,
    ${bucketExpr("created_at")} AS bucket
  FROM ${SL}.wallet_ledger\`
  WHERE merchant_id = @merchant_id AND created_at >= @p_from AND created_at < @p_to
    AND CAST(currency AS STRING) = @currency
),
summary AS (
  SELECT COALESCE(SUM(IF(signed_amount > 0, signed_amount, 0)),0) AS earned,
    COALESCE(ABS(SUM(IF(signed_amount < 0 AND source_type <> 'expiry', signed_amount, 0))),0) AS burned,
    COALESCE(ABS(SUM(IF(source_type = 'expiry', signed_amount, 0))),0) AS expired,
    COALESCE(SUM(signed_amount),0) AS net_change
  FROM base
)
SELECT TO_JSON(STRUCT(
  STRUCT(
    (SELECT earned FROM summary) AS earned,
    (SELECT burned FROM summary) AS burned,
    (SELECT burned FROM summary) AS burnt,
    (SELECT expired FROM summary) AS expired,
    (SELECT net_change FROM summary) AS net_change
  ) AS summary
)) AS report`
  const { rows, bytes } = await runQueryJson(sql, baseParams([
    { name: "frequency", type: "STRING", value: "day" },
    { name: "currency", type: "STRING", value: "points" },
  ]))
  return { data: unwrap(rows), bytes }
}

async function pointsOverviewRows() {
  const sql = `
WITH base AS (
  SELECT wl.id AS ledger_id, wl.created_at, wl.signed_amount, CAST(wl.source_type AS STRING) AS source_type,
    COUNT(*) OVER() AS total_count
  FROM ${SL}.wallet_ledger\` wl
  WHERE wl.merchant_id = @merchant_id AND wl.created_at >= @p_from AND wl.created_at < @p_to
    AND CAST(wl.currency AS STRING) = @currency
  ORDER BY wl.created_at DESC LIMIT @lim OFFSET @off
)
SELECT TO_JSON(STRUCT(
  ARRAY(SELECT AS STRUCT * FROM base) AS rows,
  COALESCE((SELECT MAX(total_count) FROM base),0) AS total_count
)) AS report`
  const { rows, bytes } = await runQueryJson(sql, baseParams([
    { name: "currency", type: "STRING", value: "points" },
    { name: "lim", type: "INT64", value: 5 },
    { name: "off", type: "INT64", value: 0 },
  ]))
  return { data: unwrap(rows), bytes }
}

async function pointsMovement() {
  const sql = `
WITH mov_user AS (
  SELECT user_id,
    COALESCE(SUM(IF(signed_amount > 0, signed_amount, 0)), 0) AS earned,
    COALESCE(ABS(SUM(IF(signed_amount < 0 AND CAST(source_type AS STRING) <> 'expiry', signed_amount, 0))), 0) AS burned,
    COALESCE(ABS(SUM(IF(CAST(source_type AS STRING) = 'expiry', signed_amount, 0))), 0) AS expired,
    CAST(0 AS INT64) AS other
  FROM ${SL}.wallet_ledger\`
  WHERE merchant_id = @merchant_id AND CAST(currency AS STRING) = @currency
    AND created_at >= @p_from AND created_at < @p_to
  GROUP BY user_id
),
bf_user AS (
  SELECT mu.user_id, COALESCE(SUM(wl.signed_amount), 0) AS brought_forward
  FROM mov_user mu
  JOIN ${SL}.wallet_ledger\` wl
    ON wl.user_id = mu.user_id AND wl.merchant_id = @merchant_id
    AND CAST(wl.currency AS STRING) = @currency AND wl.created_at < @p_from
  GROUP BY mu.user_id
),
tiered AS (
  SELECT mu.user_id, ua.tier_id, COALESCE(bf.brought_forward,0) AS brought_forward,
    mu.earned, mu.burned, mu.expired, mu.other
  FROM mov_user mu
  LEFT JOIN bf_user bf ON bf.user_id = mu.user_id
  LEFT JOIN ${SL}.user_accounts\` ua ON ua.id = mu.user_id AND ua.merchant_id = @merchant_id
),
movement_rows AS (
  SELECT t.tier_id, COALESCE(tm.tier_name,'No tier') AS tier_name,
    SUM(t.brought_forward) AS brought_forward, SUM(t.earned) AS earned, SUM(t.burned) AS burned,
    SUM(t.expired) AS expired, SUM(t.other) AS other,
    SUM(t.brought_forward)+SUM(t.earned)-SUM(t.burned)-SUM(t.expired)+SUM(t.other) AS ending
  FROM tiered t
  LEFT JOIN ${RAW}.public_tier__master\` tm ON tm.id = t.tier_id
  GROUP BY 1,2 ORDER BY ending DESC
)
SELECT TO_JSON(STRUCT(@month AS month, @currency AS currency,
  ARRAY(SELECT AS STRUCT * FROM movement_rows) AS rows)) AS report`
  const { rows, bytes } = await runQueryJson(sql, [
    { name: "merchant_id", type: "STRING", value: MID },
    { name: "p_from", type: "TIMESTAMP", value: "2026-06-01T00:00:00+07:00" },
    { name: "p_to", type: "TIMESTAMP", value: "2026-07-01T00:00:00+07:00" },
    { name: "currency", type: "STRING", value: "points" },
    { name: "month", type: "STRING", value: "2026-06" },
  ])
  return { data: unwrap(rows), bytes }
}

async function pointsSnapshot() {
  const sql = `
WITH bounds AS (
  SELECT DATE(@as_of) AS as_of_d, @period_start AS period_start,
    TIMESTAMP(DATE_ADD(DATE(@as_of), INTERVAL 1 DAY), 'Asia/Bangkok') AS as_of_end
),
wallet AS (
  SELECT COUNTIF(COALESCE(points_balance,0)>0) AS holders, COALESCE(SUM(points_balance),0) AS closing_balance
  FROM ${SL}.user_wallet\` WHERE merchant_id = @merchant_id
),
period AS (
  SELECT
    COALESCE(SUM(IF(signed_amount > 0, signed_amount, 0)),0) AS period_earned,
    COALESCE(ABS(SUM(IF(signed_amount < 0 AND CAST(source_type AS STRING) <> 'expiry', signed_amount, 0))),0) AS period_burned,
    COALESCE(ABS(SUM(IF(CAST(source_type AS STRING) = 'expiry', signed_amount, 0))),0) AS period_expired,
    CAST(0 AS INT64) AS period_adjustments, CAST(0 AS INT64) AS period_reversals
  FROM ${SL}.wallet_ledger\` CROSS JOIN bounds b
  WHERE merchant_id = @merchant_id AND CAST(currency AS STRING) = @currency
    AND created_at >= b.period_start AND created_at < b.as_of_end
),
opening AS (
  SELECT (SELECT closing_balance FROM wallet)
    - (SELECT period_earned - period_burned - period_expired FROM period) AS opening_balance
)
SELECT TO_JSON(STRUCT(
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
  STRUCT(0 AS in_30d,0 AS in_60d,0 AS in_90d,0 AS in_180d,0 AS in_365d,0 AS gt_365d,0 AS no_expiry) AS expiry_waterfall,
  CAST([] AS ARRAY<STRUCT<month STRING, opening FLOAT64, earned FLOAT64, burned FLOAT64, expired FLOAT64, closing FLOAT64>>) AS monthly_trend
)) AS report`
  const { rows, bytes } = await runQueryJson(sql, [
    { name: "merchant_id", type: "STRING", value: MID },
    { name: "as_of", type: "STRING", value: "2026-06-30" },
    { name: "currency", type: "STRING", value: "points" },
    { name: "period_start", type: "TIMESTAMP", value: "2026-06-01T00:00:00+07:00" },
  ])
  return { data: unwrap(rows), bytes }
}

async function pointsSnapshotRows() {
  const sql = `
WITH base AS (
  SELECT uw.user_id AS user_id, ua.member_code, ua.fullname AS member_name,
    COALESCE(uw.points_balance,0) AS closing_balance, COUNT(*) OVER() AS total_count
  FROM ${SL}.user_wallet\` uw
  LEFT JOIN ${SL}.user_accounts\` ua ON ua.id = uw.user_id AND ua.merchant_id = @merchant_id
  WHERE uw.merchant_id = @merchant_id AND COALESCE(uw.points_balance,0) > 0
  ORDER BY uw.points_balance DESC LIMIT @lim OFFSET @off
)
SELECT TO_JSON(STRUCT(
  ARRAY(SELECT AS STRUCT * FROM base) AS rows,
  COALESCE((SELECT MAX(total_count) FROM base),0) AS total_count
)) AS report`
  const { rows, bytes } = await runQueryJson(sql, [
    { name: "merchant_id", type: "STRING", value: MID },
    { name: "lim", type: "INT64", value: 5 },
    { name: "off", type: "INT64", value: 0 },
  ])
  return { data: unwrap(rows), bytes }
}

const cases = [
  ["transactions.purchases", purchases],
  ["transactions.purchases.rows", purchasesRows],
  ["rewards.redemptions", redemptions],
  ["rewards.redemptions.rows", redemptionsRows],
  ["members.overview", members],
  ["members.overview.rows", membersRows],
  ["currency.points_overview", pointsOverview],
  ["currency.points_overview.rows", pointsOverviewRows],
  ["currency.points_movement", pointsMovement],
  ["currency.points_snapshot", pointsSnapshot],
  ["currency.points_snapshot.rows", pointsSnapshotRows],
]

const results = []
for (const [id, fn] of cases) {
  const t0 = Date.now()
  try {
    const { data, bytes } = await fn()
    const ms = Date.now() - t0
    let detail = ""
    if (data?.summary) detail = `summary=${JSON.stringify(data.summary).slice(0, 120)}`
    else if (data?.rows) detail = `rows=${data.rows.length} total=${data.total_count}`
    else detail = Object.keys(data || {}).join(",")
    console.log(`OK  ${id}  ${ms}ms  bytes=${bytes || "?"}  ${detail}`)
    results.push({ id, ok: true, ms, detail })
  } catch (e) {
    const ms = Date.now() - t0
    const msg = e instanceof Error ? e.message : String(e)
    console.log(`FAIL ${id}  ${ms}ms  ${msg.slice(0, 400)}`)
    results.push({ id, ok: false, ms, detail: msg.slice(0, 400) })
  }
}

// overview.loyalty = composition
{
  const t0 = Date.now()
  const labels = ["purchases", "redemptions", "members", "points"]
  const fns = [purchases, redemptions, members, pointsOverview]
  const settled = await Promise.allSettled(fns.map((f) => f()))
  const errors = []
  settled.forEach((s, i) => {
    if (s.status === "rejected") {
      errors.push(`${labels[i]}: ${s.reason?.message || s.reason}`)
    }
  })
  const ms = Date.now() - t0
  if (errors.length) {
    console.log(`FAIL overview.loyalty  ${ms}ms  ${errors.join(" | ").slice(0, 400)}`)
    results.push({ id: "overview.loyalty", ok: false, ms, detail: errors.join(" | ") })
  } else {
    console.log(`OK  overview.loyalty  ${ms}ms  all 4 children ok`)
    results.push({ id: "overview.loyalty", ok: true, ms, detail: "all 4 ok" })
  }
}

const failed = results.filter((r) => !r.ok)
console.log("\n=== SUMMARY ===")
console.log(`passed=${results.length - failed.length}/${results.length}`)
if (failed.length) {
  for (const f of failed) console.log(` - ${f.id}: ${f.detail}`)
  process.exit(1)
}
