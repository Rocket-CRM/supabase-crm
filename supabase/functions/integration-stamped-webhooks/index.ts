import "jsr:@supabase/functions-js/edge-runtime.d.ts"
import { createClient } from "jsr:@supabase/supabase-js@2"

function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json" },
  })
}

function normalizeShopDomain(raw: string | null | undefined): string | null {
  const value = raw?.trim().toLowerCase() ?? ""
  if (!value) return null
  return value.replace(/^https?:\/\//, "").split("/")[0]
}

function timingSafeEqual(a: string, b: string): boolean {
  if (a.length !== b.length) return false
  let mismatch = 0
  for (let i = 0; i < a.length; i++) mismatch |= a.charCodeAt(i) ^ b.charCodeAt(i)
  return mismatch === 0
}

type CredRow = {
  id: string
  merchant_id: string
  credentials: Record<string, string>
  health_status: string | null
}

function matchCredential(
  rows: CredRow[],
  opts: {
    storeHash?: string | null
    shopDomain?: string | null
    shopifyShopId?: string | null
  },
): CredRow | null {
  const storeHash = opts.storeHash?.trim().toLowerCase() ?? ""
  const shopDomain = normalizeShopDomain(opts.shopDomain)
  const shopifyShopId = opts.shopifyShopId?.trim() ?? ""

  if (storeHash) {
    const hit = rows.find(
      (r) => (r.credentials?.store_hash ?? "").trim().toLowerCase() === storeHash,
    )
    if (hit) return hit
  }
  if (shopDomain) {
    const hit = rows.find(
      (r) => normalizeShopDomain(r.credentials?.shop_domain) === shopDomain,
    )
    if (hit) return hit
  }
  if (shopifyShopId) {
    const hit = rows.find(
      (r) => (r.credentials?.shopify_shop_id ?? "").trim() === shopifyShopId,
    )
    if (hit) return hit
  }
  return null
}

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") return new Response("ok")
  if (req.method !== "POST") return json({ success: false }, 405)

  const raw = await req.text()
  let payload: Record<string, unknown>
  try {
    payload = JSON.parse(raw) as Record<string, unknown>
  } catch {
    return json({ success: false, error: "invalid_json" }, 400)
  }

  const headerSecret =
    req.headers.get("X-Stamped-Webhook-Secret") ??
    req.headers.get("x-stamped-webhook-secret") ??
    req.headers.get("X-Secret-Key") ??
    req.headers.get("x-secret-key")

  if (!headerSecret?.trim()) {
    return json({ success: false, error: "missing_secret" }, 401)
  }

  const topic =
    req.headers.get("X-Stamped-Topic") ??
    req.headers.get("x-stamped-topic") ??
    "Reviews"

  const storeUrl =
    req.headers.get("X-Stamped-Store-Url") ??
    req.headers.get("x-stamped-store-url")
  const shopifyShopId =
    req.headers.get("X-Shopify-Shop-ID") ??
    req.headers.get("x-shopify-shop-id")

  const supabase = createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
  )

  const { data: credRows, error: credError } = await supabase
    .from("merchant_credentials")
    .select("id, merchant_id, credentials, health_status")
    .eq("service_name", "stamped")
    .eq("is_active", true)

  if (credError) {
    console.error("credential lookup", credError.message)
    return json({ success: false, error: credError.message }, 500)
  }

  const row = matchCredential((credRows ?? []) as CredRow[], {
    storeHash: typeof payload.storeHash === "string" ? payload.storeHash : null,
    shopDomain: storeUrl,
    shopifyShopId,
  })

  if (!row?.merchant_id) {
    return json({ success: true, skipped: "unknown_shop" })
  }

  const expected = row.credentials?.inbound_webhook_secret?.trim() ?? ""
  if (!expected || !timingSafeEqual(expected, headerSecret.trim())) {
    return json({ success: false, error: "invalid_secret" }, 401)
  }

  if (row.health_status === "degraded") {
    await supabase
      .from("merchant_credentials")
      .update({
        health_status: "connected",
        last_health_check: new Date().toISOString(),
        updated_at: new Date().toISOString(),
      })
      .eq("id", row.id)
  }

  const { data, error } = await supabase.rpc("fn_integration_stamped_award_review", {
    p_merchant_id: row.merchant_id,
    p_event_key: topic,
    p_payload: payload,
  })
  if (error) {
    console.error("fn_integration_stamped_award_review", error.message)
    return json({ success: false, error: error.message }, 500)
  }

  return json({ success: true, data })
})
