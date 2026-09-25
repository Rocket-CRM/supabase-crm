export type Frequency = "day" | "week" | "month" | "quarter"

export type AnalyticsRequest = {
  report: string
  from?: string
  to?: string
  as_of?: string
  month?: string
  frequency?: Frequency
  filters?: Record<string, unknown>
  limit?: number
  offset?: number
  sort?: string | null
}

export type ValidatedRange = {
  from: string
  to: string
  frequency: Frequency
  filters: Record<string, unknown>
  limit: number
  offset: number
  sort: string | null
}

const FREQUENCIES = new Set(["day", "week", "month", "quarter"])
const REPORT_ID =
  /^[a-z][a-z0-9_]*(\.[a-z][a-z0-9_]*)+(\.rows)?$/

export class ValidationError extends Error {
  status = 400
  constructor(message: string) {
    super(message)
  }
}

/** @deprecated alias */
export class ParamError extends ValidationError {}

/** Parse + validate analytics-query POST body. */
export function parseBody(raw: unknown): AnalyticsRequest {
  if (!raw || typeof raw !== "object") {
    throw new ValidationError("Invalid JSON body")
  }
  const b = raw as Record<string, unknown>

  if (!b.report || typeof b.report !== "string") {
    throw new ValidationError("report is required")
  }
  const report = b.report.trim()
  if (!report) throw new ValidationError("report is required")
  if (report !== "health" && !REPORT_ID.test(report)) {
    throw new ValidationError("Invalid report id")
  }

  const frequencyRaw = (b.frequency as string | undefined) || "day"
  if (!FREQUENCIES.has(frequencyRaw)) {
    throw new ValidationError("frequency must be day|week|month|quarter")
  }

  const filters =
    b.filters && typeof b.filters === "object" && !Array.isArray(b.filters)
      ? (b.filters as Record<string, unknown>)
      : {}

  let limit: number | undefined
  if (b.limit !== undefined && b.limit !== null) {
    const n = Number(b.limit)
    if (!Number.isFinite(n)) throw new ValidationError("limit must be a number")
    limit = Math.min(Math.max(Math.trunc(n), 1), 1000)
  }

  let offset: number | undefined
  if (b.offset !== undefined && b.offset !== null) {
    const n = Number(b.offset)
    if (!Number.isFinite(n)) throw new ValidationError("offset must be a number")
    offset = Math.max(Math.trunc(n), 0)
  }

  const month = typeof b.month === "string" ? b.month : undefined
  if (month !== undefined && !/^\d{4}-\d{2}$/.test(month)) {
    throw new ValidationError("month must be YYYY-MM")
  }

  const as_of =
    typeof b.as_of === "string"
      ? b.as_of
      : typeof b.p_as_of === "string"
      ? b.p_as_of
      : undefined
  if (as_of !== undefined && !/^\d{4}-\d{2}-\d{2}/.test(as_of)) {
    throw new ValidationError("as_of must be YYYY-MM-DD")
  }

  const from = optionalIso(b.from) ?? optionalIso(b.p_from)
  const to = optionalIso(b.to) ?? optionalIso(b.p_to)
  if (from && to) {
    const fromMs = Date.parse(from)
    const toMs = Date.parse(to)
    if (fromMs >= toMs) throw new ValidationError("to must be after from")
    if (toMs - fromMs > 400 * 24 * 60 * 60 * 1000) {
      throw new ValidationError("date range exceeds 400 days")
    }
  }

  return {
    report,
    from,
    to,
    as_of: as_of ? as_of.slice(0, 10) : undefined,
    month,
    frequency: frequencyRaw as Frequency,
    filters,
    limit,
    offset,
    sort: typeof b.sort === "string"
      ? b.sort
      : typeof b.p_sort === "string"
      ? b.p_sort
      : null,
  }
}

function optionalIso(v: unknown): string | undefined {
  if (typeof v !== "string" || !v) return undefined
  const d = new Date(v)
  if (Number.isNaN(d.getTime())) {
    throw new ValidationError(`Invalid timestamp: ${v}`)
  }
  return d.toISOString()
}

/** Require from/to for range reports. */
export function validateRange(req: AnalyticsRequest): ValidatedRange {
  if (!req.from || !req.to) {
    throw new ValidationError("from and to are required")
  }
  return {
    from: req.from,
    to: req.to,
    frequency: (req.frequency || "day") as Frequency,
    filters: req.filters || {},
    limit: req.limit ?? 100,
    offset: req.offset ?? 0,
    sort: req.sort ?? null,
  }
}

/** month = YYYY-MM → [from, to) ISO timestamps Asia/Bangkok */
export function monthBounds(month: string): { from: string; to: string } {
  if (!/^\d{4}-\d{2}$/.test(month)) {
    throw new ValidationError("month must be YYYY-MM")
  }
  const [y, m] = month.split("-").map(Number)
  const from = `${month}-01T00:00:00+07:00`
  const next = m === 12
    ? `${y + 1}-01-01T00:00:00+07:00`
    : `${y}-${String(m + 1).padStart(2, "0")}-01T00:00:00+07:00`
  return { from, to: next }
}
