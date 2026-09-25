import { createClient } from "jsr:@supabase/supabase-js@2"
import {
  gorgiasAdjustUrl,
  gorgiasApiBase,
  gorgiasMemberUrl,
} from "./gorgias-config.ts"
import { randomUrlSafe } from "./state.ts"

type ServiceClient = ReturnType<typeof createClient>

const INBOUND_HEADER = "X-Rocket-Inbound-Secret"

function widgetTemplate() {
  return {
    type: "wrapper",
    widgets: [
      {
        type: "card",
        title: "Rocket Loyalty",
        path: "",
        meta: { displayCard: true },
        widgets: [
          { type: "text", title: "Points balance", path: "loyalty.points_balance", order: 0 },
          { type: "text", title: "Points as cash", path: "loyalty.points_as_cash", order: 1 },
          { type: "text", title: "Loyalty status", path: "loyalty.status", order: 2 },
          { type: "text", title: "VIP tier", path: "loyalty.vip_tier_name", order: 3 },
          { type: "text", title: "Referral URL", path: "loyalty.referral_url", order: 4 },
          { type: "text", title: "Points to next reward", path: "loyalty.points_to_next_reward", order: 5 },
          { type: "text", title: "Date of birth", path: "loyalty.date_of_birth", order: 6 },
          { type: "text", title: "Member joined", path: "loyalty.member_joined_date", order: 7 },
        ],
      },
    ],
  }
}

async function gorgiasFetch(
  subdomain: string,
  accessToken: string,
  path: string,
  init: RequestInit = {},
): Promise<Response> {
  const url = `${gorgiasApiBase(subdomain)}${path}`
  const headers = new Headers(init.headers)
  headers.set("Authorization", `Bearer ${accessToken}`)
  headers.set("Accept", "application/json")
  if (init.body && !headers.has("Content-Type")) {
    headers.set("Content-Type", "application/json")
  }
  return fetch(url, { ...init, headers })
}

export async function provisionGorgiasHelpdesk(input: {
  subdomain: string
  accessToken: string
  inboundSecret: string
}): Promise<{ integrationId: number; widgetId: number }> {
  const memberUrl = gorgiasMemberUrl()
  const adjustUrl = gorgiasAdjustUrl()

  const integrationRes = await gorgiasFetch(input.subdomain, input.accessToken, "/integrations", {
    method: "POST",
    body: JSON.stringify({
      name: "Rocket Loyalty",
      description: "Points, tier, referral on tickets; agents award goodwill pts",
      type: "http",
      http: {
        url: memberUrl,
        method: "GET",
        headers: {
          [INBOUND_HEADER]: input.inboundSecret,
        },
        triggers: {
          "ticket-created": true,
          "ticket-updated": true,
          "ticket-message-created": true,
        },
        request_content_type: "application/json",
        response_content_type: "application/json",
        form: {
          action: {
            url: adjustUrl,
            method: "POST",
            headers: {
              [INBOUND_HEADER]: input.inboundSecret,
              "Content-Type": "application/json",
            },
          },
          fields: [
            {
              type: "number",
              name: "points",
              label: "Points to award",
              required: true,
            },
            {
              type: "text",
              name: "reason",
              label: "Reason",
              required: false,
            },
          ],
        },
      },
    }),
  })

  const integrationText = await integrationRes.text()
  if (!integrationRes.ok) {
    throw new Error(`gorgias_integration_${integrationRes.status}:${integrationText.slice(0, 200)}`)
  }

  const integrationJson = JSON.parse(integrationText) as { id?: number }
  const integrationId = integrationJson.id
  if (!integrationId) throw new Error("gorgias_integration_missing_id")

  const widgetRes = await gorgiasFetch(input.subdomain, input.accessToken, "/widgets", {
    method: "POST",
    body: JSON.stringify({
      context: "ticket",
      type: "http",
      integration_id: integrationId,
      template: widgetTemplate(),
    }),
  })

  const widgetText = await widgetRes.text()
  if (!widgetRes.ok) {
    throw new Error(`gorgias_widget_${widgetRes.status}:${widgetText.slice(0, 200)}`)
  }

  const widgetJson = JSON.parse(widgetText) as { id?: number }
  const widgetId = widgetJson.id
  if (!widgetId) throw new Error("gorgias_widget_missing_id")

  return { integrationId, widgetId }
}

export async function deactivateGorgiasHelpdesk(input: {
  subdomain: string
  accessToken: string
  integrationId?: number | null
}): Promise<void> {
  if (!input.integrationId) return
  const res = await gorgiasFetch(
    input.subdomain,
    input.accessToken,
    `/integrations/${input.integrationId}`,
    { method: "DELETE" },
  )
  if (!res.ok && res.status !== 404) {
    const text = await res.text()
    console.error("deactivateGorgiasHelpdesk", res.status, text.slice(0, 200))
  }
}

export function newInboundSecret(): string {
  return randomUrlSafe(24)
}

export async function resolveMerchantByInboundSecret(
  supabase: ServiceClient,
  inboundSecret: string,
): Promise<{ merchantId: string; credentialId: string } | null> {
  const { data, error } = await supabase
    .from("merchant_credentials")
    .select("id, merchant_id, credentials")
    .eq("service_name", "gorgias")
    .eq("is_active", true)
    .filter("credentials->>inbound_secret", "eq", inboundSecret)
    .order("updated_at", { ascending: false })
    .limit(1)
    .maybeSingle()

  if (error || !data?.id) return null
  return { merchantId: data.merchant_id as string, credentialId: data.id as string }
}
