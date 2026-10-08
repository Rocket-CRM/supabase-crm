import "jsr:@supabase/functions-js/edge-runtime.d.ts"
import { createClient } from "jsr:@supabase/supabase-js@2"
import { AuthError, resolveAdminMerchant } from "./admin-auth.ts"

const STAMPED_API = "https://stamped.io/api/v2"

const corsHeaders: Record<string, string> = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type, x-merchant-id, x-merchant-code",
}

function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  })
}

function normalizeShopDomain(raw: string | null | undefined): string | null {
  const value = raw?.trim().toLowerCase() ?? ""
  if (!value) return null
  const host = value.replace(/^https?:\/\//, "").split("/")[0]
  if (!host.endsWith(".myshopify.com")) return null
  return host
}

function randomHex(bytes: number): string {
  const arr = new Uint8Array(bytes)
  crypto.getRandomValues(arr)
  return [...arr].map((b) => b.toString(16).padStart(2, "0")).join("")
}

async function stampedProbe(storeHash: string, apiKey: string): Promise<Response> {
  const url = new URL(`${STAMPED_API}/${storeHash}/dashboard/reviews`)
  url.searchParams.set("take", "1")
  url.searchParams.set("page", "1")
  return await fetch(url, {
    headers: {
      Accept: "application/json",
      "stamped-api-key": apiKey,
    },
  })
}

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders })
  if (req.method !== "POST") return json({ success: false, title: "Method not allowed" }, 405)

  try {
    const auth = await resolveAdminMerchant(req)
    const body = (await req.json().catch(() => ({}))) as {
      store_hash?: string
      private_api_key?: string
      shop_domain?: string
    }

    const storeHash = body.store_hash?.trim() ?? ""
    const apiKey = body.private_api_key?.trim() ?? ""
    if (!storeHash || !apiKey) {
      return json({
        success: false,
        title: "Credentials required",
        description: "Enter your Stamped store hash and private API key from Settings → API Keys.",
      }, 400)
    }

    const supabase = createClient(
      Deno.env.get("SUPABASE_URL")!,
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
    )

    let shopDomain = normalizeShopDomain(body.shop_domain)
    if (!shopDomain) {
      const { data: shopifyCred } = await supabase
        .from("merchant_credentials")
        .select("credentials")
        .eq("merchant_id", auth.merchantId)
        .eq("service_name", "shopify_app")
        .eq("is_active", true)
        .order("updated_at", { ascending: false })
        .limit(1)
        .maybeSingle()
      shopDomain = normalizeShopDomain(
        (shopifyCred?.credentials as Record<string, string> | null)?.shop_domain,
      )
    }

    const probe = await stampedProbe(storeHash, apiKey)
    if (probe.status === 401 || probe.status === 403) {
      return json({
        success: false,
        title: "Could not connect",
        description: "Stamped rejected these credentials. Check the store hash and private API key.",
      }, 400)
    }
    if (!probe.ok && probe.status !== 404) {
      const detail = (await probe.text()).slice(0, 200)
      return json({
        success: false,
        title: "Could not reach Stamped",
        description: detail || `Stamped returned ${probe.status}`,
      }, 400)
    }

    const inboundSecret = randomHex(32)
    const webhookUrl =
      `${Deno.env.get("SUPABASE_URL")}/functions/v1/integration-stamped-webhooks`

    const shopifyShopId = req.headers.get("x-shopify-shop-id")?.trim() || null

    const credentials = {
      store_hash: storeHash,
      private_api_key: apiKey,
      shop_domain: shopDomain,
      shopify_shop_id: shopifyShopId,
      inbound_webhook_secret: inboundSecret,
      webhook_url: webhookUrl,
    }

    const { data: existingCred } = await supabase
      .from("merchant_credentials")
      .select("id")
      .eq("merchant_id", auth.merchantId)
      .eq("service_name", "stamped")
      .order("updated_at", { ascending: false })
      .limit(1)
      .maybeSingle()

    const row = {
      credentials,
      is_active: true,
      health_status: "degraded",
      last_health_check: new Date().toISOString(),
      updated_at: new Date().toISOString(),
    }

    if (existingCred?.id) {
      const { error } = await supabase
        .from("merchant_credentials")
        .update(row)
        .eq("id", existingCred.id)
      if (error) throw error
    } else {
      const { error } = await supabase.from("merchant_credentials").insert({
        merchant_id: auth.merchantId,
        service_name: "stamped",
        ...row,
        environment: "production",
      })
      if (error) throw error
    }

    return json({
      success: true,
      title: "Connected",
      description:
        "Add the webhook in Stamped (Reviews only), then configure review earning on Earn from activities.",
      data: {
        connected: true,
        shop_domain: shopDomain,
        store_hash: storeHash,
        webhook_url: webhookUrl,
        inbound_webhook_secret: inboundSecret,
        health_status: "degraded",
      },
    })
  } catch (err) {
    if (err instanceof AuthError) {
      return json({ success: false, title: err.message }, err.status)
    }
    const message = err instanceof Error ? err.message : String(err)
    console.error("integration-stamped-connect", message)
    return json({ success: false, title: "Connect failed", description: message }, 500)
  }
})
