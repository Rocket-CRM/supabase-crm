import * as jose from "https://deno.land/x/jose@v5.2.0/index.ts"

export type BqParam =
  | { name: string; type: "STRING"; value: string | null }
  | { name: string; type: "INT64"; value: number | null }
  | { name: string; type: "BOOL"; value: boolean | null }
  | { name: string; type: "TIMESTAMP"; value: string | null }
  | { name: string; type: "DATE"; value: string | null }
  | { name: string; type: "ARRAY"; arrayType: "STRING"; value: string[] }

type SaJson = {
  client_email: string
  private_key: string
  project_id?: string
}

let cachedToken: { token: string; exp: number } | null = null

function loadSa(): SaJson {
  const raw = Deno.env.get("BQ_SERVICE_ACCOUNT_JSON")
  if (!raw) throw new Error("BQ_SERVICE_ACCOUNT_JSON secret is not set")
  return JSON.parse(raw) as SaJson
}

export function bqProjectId(): string {
  return (
    Deno.env.get("BQ_PROJECT_ID") ||
    loadSa().project_id ||
    "rocket-prod-analytics"
  )
}

export function bqLocation(): string {
  return Deno.env.get("BQ_LOCATION") || "asia-southeast1"
}

async function getAccessToken(): Promise<string> {
  const now = Math.floor(Date.now() / 1000)
  if (cachedToken && cachedToken.exp > now + 60) return cachedToken.token

  const sa = loadSa()
  const key = await jose.importPKCS8(sa.private_key, "RS256")
  const jwt = await new jose.SignJWT({
    scope: "https://www.googleapis.com/auth/bigquery",
  })
    .setProtectedHeader({ alg: "RS256", typ: "JWT" })
    .setIssuer(sa.client_email)
    .setSubject(sa.client_email)
    .setAudience("https://oauth2.googleapis.com/token")
    .setIssuedAt(now)
    .setExpirationTime(now + 3600)
    .sign(key)

  const res = await fetch("https://oauth2.googleapis.com/token", {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({
      grant_type: "urn:ietf:params:oauth:grant-type:jwt-bearer",
      assertion: jwt,
    }),
  })
  if (!res.ok) {
    const text = await res.text()
    throw new Error(`BQ token exchange failed: ${res.status} ${text}`)
  }
  const body = await res.json()
  cachedToken = {
    token: body.access_token as string,
    exp: now + Number(body.expires_in || 3600),
  }
  return cachedToken.token
}

function toQueryParameter(p: BqParam): Record<string, unknown> {
  if (p.type === "ARRAY") {
    return {
      name: p.name,
      parameterType: {
        type: "ARRAY",
        arrayType: { type: p.arrayType },
      },
      parameterValue: {
        arrayValues: p.value.map((v) => ({ value: v })),
      },
    }
  }
  return {
    name: p.name,
    parameterType: { type: p.type },
    parameterValue: {
      value: p.value === null || p.value === undefined
        ? undefined
        : String(p.value),
    },
  }
}

/** Run a parameterized query; return first row as object (for TO_JSON single-row reports). */
export async function runQueryJson(
  sql: string,
  params: BqParam[],
  maximumBytesBilled = "15000000000",
): Promise<{ rows: Record<string, unknown>[]; totalBytesProcessed?: string }> {
  const token = await getAccessToken()
  const projectId = bqProjectId()
  const location = bqLocation()

  const res = await fetch(
    `https://bigquery.googleapis.com/bigquery/v2/projects/${projectId}/queries`,
    {
      method: "POST",
      headers: {
        Authorization: `Bearer ${token}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({
        query: sql,
        useLegacySql: false,
        location,
        parameterMode: "NAMED",
        queryParameters: params.map(toQueryParameter),
        maximumBytesBilled,
        timeoutMs: 120000,
      }),
    },
  )

  const body = await res.json()
  if (!res.ok || body.error) {
    throw new Error(
      `BQ query failed: ${
        body.error?.message || JSON.stringify(body).slice(0, 500)
      }`,
    )
  }

  const fields: { name: string; type: string }[] =
    body.schema?.fields?.map((f: { name: string; type: string }) => ({
      name: f.name,
      type: f.type,
    })) || []

  const rows = (body.rows || []).map(
    (r: { f: { v: unknown }[] }) => {
      const obj: Record<string, unknown> = {}
      r.f.forEach((cell, i) => {
        obj[fields[i].name] = parseCell(cell.v, fields[i].type)
      })
      return obj
    },
  )

  return {
    rows,
    totalBytesProcessed: body.totalBytesProcessed,
  }
}

function parseCell(v: unknown, type: string): unknown {
  if (v === null || v === undefined) return null
  if (type === "INTEGER" || type === "INT64") return Number(v)
  if (type === "FLOAT" || type === "FLOAT64" || type === "NUMERIC" ||
    type === "BIGNUMERIC") {
    return Number(v)
  }
  if (type === "BOOLEAN" || type === "BOOL") return v === "true" || v === true
  if (type === "JSON") {
    try {
      return typeof v === "string" ? JSON.parse(v) : v
    } catch {
      return v
    }
  }
  return v
}
