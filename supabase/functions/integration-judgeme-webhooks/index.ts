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

function bytesToHex(bytes: ArrayBuffer): string {
  return [...new Uint8Array(bytes)]
    .map((b) => b.toString(16).padStart(2, "0"))
    .join("")
}

async function hmacSha256Hex(secret: string, payload: string): Promise<string> {
  const key = await crypto.subtle.importKey(
    "raw",
    new TextEncoder().encode(secret),
    { name: "HMAC", hash: "SHA-256" },
    false,
    ["sign"],
  )
  const mac = await crypto.subtle.sign("HMAC", key, new TextEncoder().encode(payload))
  return bytesToHex(mac)
}

function timingSafeEqual(a: string, b: string): boolean {
  if (a.length !== b.length) return false
  let mismatch = 0
  for (let i = 0; i < a.length; i++) mismatch |= a.charCodeAt(i) ^ b.charCodeAt(i)
  return mismatch === 0
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

  const shopDomain = normalizeShopDomain(
    (payload.shop_domain as string | undefined) ??
      ((payload.shop as Record<string, unknown> | undefined)?.domain as string | undefined),
  )
  if (!shopDomain) return json({ success: true, skipped: "missing_shop" })

  const supabase = createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
  )

  const { data: cred } = await supabase
    .from("merchant_credentials")
    .select("merchant_id, credentials, is_active")
    .eq("service_name", "judgeme")
    .eq("is_active", true)
    .contains("credentials", { shop_domain: shopDomain })
    .maybeSingle()

  let row = cred
  if (!row) {
    const { data: fallback } = await supabase
      .from("merchant_credentials")
      .select("merchant_id, credentials, is_active")
      .eq("service_name", "judgeme")
      .eq("is_active", true)
    row = (fallback ?? []).find((candidate) => {
      const stored = (candidate.credentials as Record<string, string> | null)?.shop_domain
      return normalizeShopDomain(stored) === shopDomain
    }) ?? null
  }

  if (!row?.merchant_id) return json({ success: true, skipped: "unknown_shop" })

  const creds = (row.credentials ?? {}) as Record<string, string>
  const apiToken = creds.api_token?.trim() ?? creds.access_token?.trim() ?? ""
  const oauthSecret = Deno.env.get("JUDGEME_CLIENT_SECRET")?.trim() ?? ""
  const signature =
    req.headers.get("JUDGEME-HMAC-SHA256") ??
    req.headers.get("Judgeme-Hmac-Sha256") ??
    req.headers.get("x-judgeme-hmac-sha256")

  if (signature) {
    const secrets = creds.auth_type === "oauth"
      ? [oauthSecret, apiToken]
      : [apiToken, oauthSecret]
    const target = signature.toLowerCase()
    let matched = false
    for (const secret of secrets) {
      if (!secret) continue
      const expected = await hmacSha256Hex(secret, raw)
      if (timingSafeEqual(expected, target)) {
        matched = true
        break
      }
    }
    if (!matched) return json({ success: false, error: "invalid_signature" }, 401)
  }

  const eventKey =
    req.headers.get("x-judgeme-topic") ??
    (payload.key as string | undefined) ??
    (payload.webhook as Record<string, string> | undefined)?.key ??
    "review/updated"

  const { data, error } = await supabase.rpc("fn_award_judgeme_review", {
    p_merchant_id: row.merchant_id,
    p_event_key: eventKey,
    p_payload: payload,
  })
  if (error) {
    console.error("fn_award_judgeme_review", error.message)
    return json({ success: false, error: error.message }, 500)
  }

  return json({ success: true, data })
})
