import "jsr:@supabase/functions-js/edge-runtime.d.ts"
import { AuthError, resolveAuth } from "./lib/auth.ts"
import { runQueryJson } from "./lib/bq.ts"
import { corsHeaders, jsonResponse } from "./lib/cors.ts"
import { errorEnvelope, successEnvelope } from "./lib/envelope.ts"
import { parseBody, ValidationError } from "./lib/params.ts"
import { registry } from "./reports/registry.ts"

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders })
  }

  try {
    if (req.method !== "POST") {
      return jsonResponse(errorEnvelope("Method not allowed"), 405)
    }

    const auth = await resolveAuth(req)
    const body = parseBody(await req.json())

    if (body.report === "health") {
      const { rows, totalBytesProcessed } = await runQueryJson(
        `SELECT COUNT(*) AS c
         FROM \`rocket-prod-analytics.serving_loyalty.purchase_ledger\`
         WHERE merchant_id = @merchant_id
           AND transaction_date >= TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 7 DAY)
           AND transaction_date < CURRENT_TIMESTAMP()`,
        [{ name: "merchant_id", type: "STRING", value: auth.merchantId }],
        "2000000000",
      )
      return jsonResponse(
        successEnvelope({
          ok: true,
          merchant_id: auth.merchantId,
          serving: "rocket-prod-analytics.serving_loyalty",
          sample_7d_purchases: rows[0]?.c ?? 0,
          totalBytesProcessed,
          reports: Object.keys(registry).filter((k) => k !== "health"),
        }),
      )
    }

    const handler = registry[body.report]
    if (!handler) {
      return jsonResponse(errorEnvelope("Unknown report", body.report), 404)
    }

    const data = await handler(auth, body)
    return jsonResponse(successEnvelope(data))
  } catch (err) {
    if (err instanceof AuthError) {
      return jsonResponse(errorEnvelope(err.message), err.status)
    }
    if (err instanceof ValidationError) {
      return jsonResponse(errorEnvelope(err.message), 400)
    }
    const message = err instanceof Error ? err.message : String(err)
    console.error("analytics-query error:", message)
    return jsonResponse(errorEnvelope("Analytics query failed", message), 500)
  }
})
