import type { SupabaseClient } from "https://esm.sh/@supabase/supabase-js@2.38.4"

const COMPLIANCE_RPC: Record<string, { fn: string; args: (shop: string, payload: Record<string, unknown>, topic: string) => Record<string, unknown> }> = {
  "customers/data_request": {
    fn: "shopify_webhook_export_customer_data",
    args: (shop, payload) => ({ p_shop_domain: shop, p_payload: payload }),
  },
  "customers/redact": {
    fn: "shopify_webhook_redact_customer",
    args: (shop, payload) => ({ p_shop_domain: shop, p_payload: payload }),
  },
  "app/uninstalled": {
    fn: "shopify_webhook_deactivate_shop",
    args: (shop, payload, topic) => ({
      p_shop_domain: shop,
      p_topic: topic,
      p_payload: payload,
    }),
  },
  "shop/redact": {
    fn: "shopify_webhook_deactivate_shop",
    args: (shop, payload, topic) => ({
      p_shop_domain: shop,
      p_topic: topic,
      p_payload: payload,
    }),
  },
}

export function isComplianceTopic(topic: string): boolean {
  return topic in COMPLIANCE_RPC
}

export async function handleComplianceWebhook(
  supabase: SupabaseClient,
  topic: string,
  shopDomain: string,
  payload: Record<string, unknown>,
): Promise<{ success: boolean; error_message?: string; data?: unknown }> {
  const route = COMPLIANCE_RPC[topic]
  if (!route) {
    return { success: true }
  }

  const { data, error } = await supabase.rpc(route.fn, route.args(shopDomain, payload, topic))
  if (error) {
    console.error(`[shopify-webhooks] RPC ${route.fn} failed:`, error.message)
    return { success: false, error_message: error.message }
  }

  const result = data as { success?: boolean; error_message?: string }
  if (result?.success === false) {
    return { success: false, error_message: result.error_message ?? "Processing failed" }
  }

  return { success: true, data }
}
