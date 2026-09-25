/**
 * Smoke-test every named report handler against live BQ.
 * Usage:
 *   export BQ_SERVICE_ACCOUNT_JSON="$(cat ~/Downloads/bq-readonly-external-rocket-prod-analytics.json)"
 *   deno run -A .cursor/deploy/analytics-query/_smoke_all.ts
 */
import { purchasesChart, purchasesRows } from "./reports/purchases.ts"
import { redemptionsChart, redemptionsRows } from "./reports/redemptions.ts"
import { membersChart, membersRows } from "./reports/members.ts"
import {
  pointsOverview,
  pointsRows,
  pointsMovement,
  pointsSnapshot,
  pointsSnapshotRows,
} from "./reports/points.ts"
import type { ValidatedRange } from "./lib/params.ts"

const MID = "10de947e-ff05-4e2b-88ff-c853e5a69cb3" // Futurepark
const range: ValidatedRange = {
  from: "2026-06-01T00:00:00.000+07:00",
  to: "2026-07-01T00:00:00.000+07:00",
  frequency: "day",
  filters: {},
  limit: 5,
  offset: 0,
  sort: null,
}

type Case = { id: string; run: () => Promise<unknown> }

const cases: Case[] = [
  { id: "transactions.purchases", run: () => purchasesChart(MID, range) },
  {
    id: "transactions.purchases.rows",
    run: () => purchasesRows(MID, range),
  },
  { id: "rewards.redemptions", run: () => redemptionsChart(MID, range) },
  {
    id: "rewards.redemptions.rows",
    run: () => redemptionsRows(MID, range),
  },
  { id: "members.overview", run: () => membersChart(MID, range) },
  { id: "members.overview.rows", run: () => membersRows(MID, range) },
  { id: "currency.points_overview", run: () => pointsOverview(MID, range) },
  {
    id: "currency.points_overview.rows",
    run: () => pointsRows(MID, range),
  },
  {
    id: "currency.points_movement",
    run: () => pointsMovement(MID, "2026-06", "points"),
  },
  {
    id: "currency.points_snapshot",
    run: () => pointsSnapshot(MID, "2026-06-30", "points"),
  },
  {
    id: "currency.points_snapshot.rows",
    run: () => pointsSnapshotRows(MID, "2026-06-30", range),
  },
  {
    id: "overview.loyalty",
    run: async () => {
      const settled = await Promise.allSettled([
        purchasesChart(MID, range),
        redemptionsChart(MID, range),
        membersChart(MID, range),
        pointsOverview(MID, range),
      ])
      const labels = ["purchases", "redemptions", "members", "points"]
      const errors: string[] = []
      const out: Record<string, unknown> = { errors }
      for (let i = 0; i < settled.length; i++) {
        const s = settled[i]
        if (s.status === "fulfilled") out[labels[i]] = s.value
        else {
          out[labels[i]] = null
          errors.push(
            `${labels[i]}: ${
              s.reason instanceof Error ? s.reason.message : String(s.reason)
            }`,
          )
        }
      }
      if (errors.length) throw new Error(errors.join(" | "))
      return out
    },
  },
]

function summarize(id: string, data: unknown): string {
  if (!data || typeof data !== "object") return typeof data
  const d = data as Record<string, unknown>
  if (id.endsWith(".rows")) {
    const rows = d.rows as unknown[] | undefined
    return `rows=${rows?.length ?? "?"} total=${d.total_count}`
  }
  if (id === "currency.points_movement") {
    const rows = d.rows as unknown[] | undefined
    return `tier_rows=${rows?.length ?? "?"}`
  }
  if (id === "overview.loyalty") {
    const keys = ["purchases", "redemptions", "members", "points"]
    return keys
      .map((k) => `${k}=${d[k] ? "ok" : "null"}`)
      .join(" ")
  }
  if (d.summary && typeof d.summary === "object") {
    return `summary_keys=${Object.keys(d.summary as object).join(",")}`
  }
  return `keys=${Object.keys(d).slice(0, 8).join(",")}`
}

const results: { id: string; ok: boolean; ms: number; detail: string }[] = []

for (const c of cases) {
  const t0 = Date.now()
  try {
    const data = await c.run()
    results.push({
      id: c.id,
      ok: true,
      ms: Date.now() - t0,
      detail: summarize(c.id, data),
    })
    console.log(`OK  ${c.id}  ${Date.now() - t0}ms  ${summarize(c.id, data)}`)
  } catch (e) {
    const msg = e instanceof Error ? e.message : String(e)
    results.push({
      id: c.id,
      ok: false,
      ms: Date.now() - t0,
      detail: msg.slice(0, 300),
    })
    console.log(`FAIL ${c.id}  ${Date.now() - t0}ms  ${msg.slice(0, 300)}`)
  }
}

const failed = results.filter((r) => !r.ok)
console.log("\n=== SUMMARY ===")
console.log(`passed=${results.length - failed.length} failed=${failed.length}`)
if (failed.length) {
  for (const f of failed) console.log(` - ${f.id}: ${f.detail}`)
  Deno.exit(1)
}
