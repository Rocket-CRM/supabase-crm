import "jsr:@supabase/functions-js/edge-runtime.d.ts"
import { createClient } from "jsr:@supabase/supabase-js@2"
import { AuthError, resolveAdminMerchant } from "./admin-auth.ts"

const JUDGE_ME_API = "https://api.judge.me/api/v1"
const WEBHOOK_KEYS = ["review/created", "review/updated"] as const

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

async function judgeMeFetch(
  path: string,
  token: string,
  shopDomain: string,
  init?: RequestInit,
): Promise<Response> {
  const url = new URL(`${JUDGE_ME_API}${path}`)
  url.searchParams.set("api_token", token)
  url.searchParams.set("shop_domain", shopDomain)
  return await fetch(url, {
    ...init,
    headers: {
      Accept: "application/json",
      "Content-Type": "application/json",
      "X-Api-Token": token,
      ...(init?.headers ?? {}),
    },
  })
}

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders })
  if (req.method !== "POST") return json({ success: false, title: "Method not allowed" }, 405)

  try {
    const auth = await resolveAdminMerchant(req)
    const body = (await req.json().catch(() => ({}))) as {
      api_token?: string
      shop_domain?: string
    }
    const apiToken = body.api_token?.trim() ?? ""
    if (!apiToken) {
      return json({
        success: false,
        title: "Token required",
        description: "Paste the Judge.me private API token from Settings → Integrations.",
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
    if (!shopDomain) {
      const { data: merchant } = await supabase
        .from("merchant_master")
        .select("merchant_code")
        .eq("id", auth.merchantId)
        .maybeSingle()
      shopDomain = normalizeShopDomain(merchant?.merchant_code)
    }
    if (!shopDomain) {
      return json({
        success: false,
        title: "Shop domain required",
        description: "Enter the store as example.myshopify.com.",
      }, 400)
    }

    const probe = await judgeMeFetch("/reviews", apiToken, shopDomain)
    if (probe.status === 401 || probe.status === 403) {
      return json({
        success: false,
        title: "Could not connect",
        description: "Judge.me rejected this token. Copy the private API token from Judge.me settings.",
      }, 400)
    }
    if (!probe.ok && probe.status !== 404) {
      const detail = (await probe.text()).slice(0, 200)
      return json({
        success: false,
        title: "Could not reach Judge.me",
        description: detail || `Judge.me returned ${probe.status}`,
      }, 400)
    }

    const webhookUrl = `${Deno.env.get("SUPABASE_URL")}/functions/v1/integration-judgeme-webhooks`
    const listed = await judgeMeFetch("/webhooks", apiToken, shopDomain)
    const listedJson = listed.ok
      ? (await listed.json()) as { webhooks?: Array<{ id?: number; key?: string; url?: string }> }
      : { webhooks: [] }
    const existing = listedJson.webhooks ?? []
    const webhookIds: number[] = []

    for (const key of WEBHOOK_KEYS) {
      const found = existing.find((row) => row.key === key && row.url === webhookUrl)
      if (found?.id) {
        webhookIds.push(found.id)
        continue
      }
      const created = await fetch(`${JUDGE_ME_API}/webhooks`, {
        method: "POST",
        headers: {
          Accept: "application/json",
          "Content-Type": "application/json",
          "X-Api-Token": apiToken,
        },
        body: JSON.stringify({
          shop_domain: shopDomain,
          api_token: apiToken,
          webhook: { key, url: webhookUrl },
        }),
      })
      if (!created.ok) {
        const detail = (await created.text()).slice(0, 200)
        return json({
          success: false,
          title: "Connected, but webhooks failed",
          description: detail || `Could not subscribe to ${key}`,
        }, 400)
      }
      const createdJson = (await created.json()) as { webhook?: { id?: number } }
      if (createdJson.webhook?.id) webhookIds.push(createdJson.webhook.id)
    }

    const credentials = {
      api_token: apiToken,
      shop_domain: shopDomain,
      webhook_ids: webhookIds,
      webhook_url: webhookUrl,
    }

    const { data: existingCred } = await supabase
      .from("merchant_credentials")
      .select("id")
      .eq("merchant_id", auth.merchantId)
      .eq("service_name", "judgeme")
      .order("updated_at", { ascending: false })
      .limit(1)
      .maybeSingle()

    if (existingCred?.id) {
      const { error } = await supabase
        .from("merchant_credentials")
        .update({
          credentials,
          is_active: true,
          health_status: "connected",
          last_health_check: new Date().toISOString(),
          updated_at: new Date().toISOString(),
        })
        .eq("id", existingCred.id)
      if (error) throw error
    } else {
      const { error } = await supabase.from("merchant_credentials").insert({
        merchant_id: auth.merchantId,
        service_name: "judgeme",
        credentials,
        environment: "production",
        is_active: true,
        health_status: "connected",
        last_health_check: new Date().toISOString(),
        updated_at: new Date().toISOString(),
      })
      if (error) throw error
    }

    return json({
      success: true,
      title: "Connected",
      description: "Judge.me reviews can now earn points. Add the earning rule on Earn from activities.",
      data: { connected: true, shop_domain: shopDomain },
    })
  } catch (err) {
    if (err instanceof AuthError) {
      return json({ success: false, title: err.message }, err.status)
    }
    const message = err instanceof Error ? err.message : String(err)
    console.error("integration-judgeme-connect", message)
    return json({ success: false, title: "Connect failed", description: message }, 500)
  }
})
