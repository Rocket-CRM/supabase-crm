import type { SupabaseClient } from "https://esm.sh/@supabase/supabase-js@2.38.4"

const CUSTOMER_RPC: Record<string, { fn: string; args: (shop: string, payload: Record<string, unknown>) => Record<string, unknown> }> = {
  "customers/update": {
    fn: "shopify_webhook_sync_customer",
    args: (shop, payload) => ({ p_shop_domain: shop, p_payload: payload }),
  },
  "customers/delete": {
    fn: "shopify_webhook_delete_customer",
    args: (shop, payload) => ({ p_shop_domain: shop, p_payload: payload }),
  },
}

export function isCustomerTopic(topic: string): boolean {
  return topic in CUSTOMER_RPC
}

export async function handleCustomerWebhook(
  supabase: SupabaseClient,
  topic: string,
  shopDomain: string,
  payload: Record<string, unknown>,
): Promise<{ success: boolean; error_message?: string; data?: unknown }> {
  const route = CUSTOMER_RPC[topic]
  if (!route) {
    return { success: true }
  }

  const { data, error } = await supabase.rpc(route.fn, route.args(shopDomain, payload))
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
