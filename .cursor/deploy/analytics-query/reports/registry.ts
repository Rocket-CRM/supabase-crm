import type { AuthContext } from "../lib/auth.ts"
import {
  monthBounds,
  validateRange,
  ValidationError,
  type AnalyticsRequest,
} from "../lib/params.ts"
import * as purchases from "./purchases.ts"
import * as redemptions from "./redemptions.ts"
import * as members from "./members.ts"
import * as points from "./points.ts"
import * as home from "./home.ts"

export type ReportHandler = (
  auth: AuthContext,
  req: AnalyticsRequest,
) => Promise<unknown>

export const registry: Record<string, ReportHandler> = {
  "transactions.purchases": async (auth, req) => {
    const range = validateRange(req)
    return purchases.purchasesChart(auth.merchantId, range)
  },
  "transactions.purchases.rows": async (auth, req) => {
    const range = validateRange(req)
    return purchases.purchasesRows(auth.merchantId, range)
  },
  "rewards.redemptions": async (auth, req) => {
    const range = validateRange(req)
    return redemptions.redemptionsChart(auth.merchantId, range)
  },
  "rewards.redemptions.rows": async (auth, req) => {
    const range = validateRange(req)
    return redemptions.redemptionsRows(auth.merchantId, range)
  },
  "members.overview": async (auth, req) => {
    const range = validateRange(req)
    return members.membersChart(auth.merchantId, range)
  },
  "members.overview.rows": async (auth, req) => {
    const range = validateRange(req)
    return members.membersRows(auth.merchantId, range)
  },
  "currency.points_overview": async (auth, req) => {
    const range = validateRange(req)
    return points.pointsOverview(auth.merchantId, range)
  },
  "currency.points_overview.rows": async (auth, req) => {
    const range = validateRange(req)
    return points.pointsRows(auth.merchantId, range)
  },
  "currency.points_movement": async (auth, req) => {
    if (!req.month) throw new ValidationError("month is required (YYYY-MM)")
    monthBounds(req.month) // validate
    const currency = String(req.filters?.currency || "points")
    return points.pointsMovement(auth.merchantId, req.month, currency)
  },
  "currency.points_snapshot": async (auth, req) => {
    if (!req.as_of) throw new ValidationError("as_of is required (YYYY-MM-DD)")
    const currency = String(req.filters?.currency || "points")
    return points.pointsSnapshot(auth.merchantId, req.as_of, currency)
  },
  "currency.points_snapshot.rows": async (auth, req) => {
    if (!req.as_of) throw new ValidationError("as_of is required (YYYY-MM-DD)")
    const limit = Math.min(Math.max(req.limit ?? 100, 1), 1000)
    const offset = Math.max(req.offset ?? 0, 0)
    return points.pointsSnapshotRows(auth.merchantId, req.as_of, {
      limit,
      offset,
    })
  },
  /** Home KPI strip: member_added / earn / redeemer / driven_revenue (window) + total_members. */
  "home.metrics": async (auth, req) => {
    const range = home.resolveHomeRange(req)
    return home.homeMetrics(auth.merchantId, range)
  },
  /** Wave-1 composite: purchases + redemptions + members + points (no mkt/RFM/funnel). */
  "overview.loyalty": async (auth, req) => {
    const range = validateRange(req)
    const mid = auth.merchantId
    const settled = await Promise.allSettled([
      purchases.purchasesChart(mid, range),
      redemptions.redemptionsChart(mid, range),
      members.membersChart(mid, range),
      points.pointsOverview(mid, range),
    ])
    const labels = ["purchases", "redemptions", "members", "points"] as const
    const errors: string[] = []
    const out: Record<string, unknown> = { errors }
    for (let i = 0; i < settled.length; i++) {
      const s = settled[i]
      const key = labels[i]
      if (s.status === "fulfilled") {
        out[key] = s.value
      } else {
        out[key] = null
        errors.push(
          `${key}: ${s.reason instanceof Error ? s.reason.message : String(s.reason)}`,
        )
      }
    }
    if (errors.length === 4) {
      throw new Error(errors.join("; "))
    }
    return out
  },
  health: async () => ({
    ok: true,
    serving: "rocket-prod-analytics.serving_loyalty",
    reports: Object.keys(registry).filter((k) => k !== "health"),
  }),
}
