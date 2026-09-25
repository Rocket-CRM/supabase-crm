import { createClient } from "jsr:@supabase/supabase-js@2"
import {
  JUDGE_ME_API,
  JUDGEME_WEBHOOK_KEYS,
  normalizeMyshopifyDomain,
  webhookReceiverUrl,
} from "./judgeme-config.ts"

type ServiceClient = ReturnType<typeof createClient>

export async function resolveJudgemeShopDomain(
  supabase: ServiceClient,
  merchantId: string,
  hint?: string | null,
): Promise<string | null> {
  const fromHint = normalizeMyshopifyDomain(hint)
  if (fromHint) return fromHint

  const { data: shopifyCred } = await supabase
    .from("merchant_credentials")
    .select("credentials")
    .eq("merchant_id", merchantId)
    .eq("service_name", "shopify_app")
    .eq("is_active", true)
    .order("updated_at", { ascending: false })
    .limit(1)
    .maybeSingle()
  const fromShopify = normalizeMyshopifyDomain(
    (shopifyCred?.credentials as Record<string, string> | null)?.shop_domain,
  )
  if (fromShopify) return fromShopify

  const { data: merchant } = await supabase
    .from("merchant_master")
    .select("merchant_code")
    .eq("id", merchantId)
    .maybeSingle()
  return normalizeMyshopifyDomain(merchant?.merchant_code)
}

export async function fetchJudgemeShopDomain(token: string): Promise<string | null> {
  const url = new URL(`${JUDGE_ME_API}/shops`)
  url.searchParams.set("api_token", token)
  const res = await fetch(url, {
    headers: {
      Accept: "application/json",
      "X-Api-Token": token,
    },
  })
  if (!res.ok) return null
  const json = (await res.json()) as {
    shop?: { domain?: string; shop_domain?: string }
    shops?: Array<{ domain?: string; shop_domain?: string }>
  }
  const row = json.shop ?? json.shops?.[0]
  return normalizeMyshopifyDomain(row?.shop_domain ?? row?.domain)
}

export async function registerJudgemeWebhooks(
  token: string,
  shopDomain: string,
): Promise<number[]> {
  const webhookUrl = webhookReceiverUrl()
  const listedUrl = new URL(`${JUDGE_ME_API}/webhooks`)
  listedUrl.searchParams.set("api_token", token)
  listedUrl.searchParams.set("shop_domain", shopDomain)
  const listed = await fetch(listedUrl, {
    headers: {
      Accept: "application/json",
      "X-Api-Token": token,
    },
  })
  const listedJson = listed.ok
    ? ((await listed.json()) as { webhooks?: Array<{ id?: number; key?: string; url?: string }> })
    : { webhooks: [] }
  const existing = listedJson.webhooks ?? []
  const webhookIds: number[] = []

  for (const key of JUDGEME_WEBHOOK_KEYS) {
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
        "X-Api-Token": token,
      },
      body: JSON.stringify({
        shop_domain: shopDomain,
        api_token: token,
        webhook: { key, url: webhookUrl },
      }),
    })
    if (!created.ok) {
      const detail = (await created.text()).slice(0, 200)
      throw new Error(`webhook_${key}:${detail || created.status}`)
    }
    const createdJson = (await created.json()) as { webhook?: { id?: number } }
    if (createdJson.webhook?.id) webhookIds.push(createdJson.webhook.id)
  }

  return webhookIds
}
