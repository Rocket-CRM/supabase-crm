import type { SupabaseClient } from "https://esm.sh/@supabase/supabase-js@2.38.4";

const LOG_TAG = "[shopify-webhooks:products]";

export function isProductTopic(topic: string): boolean {
  return topic === "products/update";
}

function num(v: unknown): number {
  if (v === null || v === undefined || v === "") return 0;
  const n = typeof v === "number" ? v : parseFloat(String(v));
  return Number.isFinite(n) ? n : 0;
}

function pricesDiffer(a: unknown, b: unknown): boolean {
  return Math.abs(num(a) - num(b)) > 0.001;
}

export function extractProductIds(product: Record<string, unknown>): { numeric: string; gid: string } | null {
  const numeric = product.id != null ? String(product.id) : "";
  if (!numeric) return null;
  const gid = String(product.admin_graphql_api_id || `gid://shopify/Product/${numeric}`);
  return { numeric, gid };
}

export function maxVariantPriceFromRest(product: Record<string, unknown>): number {
  const variants = (product.variants || []) as Array<Record<string, unknown>>;
  let max = 0;
  for (const v of variants) {
    max = Math.max(max, num(v.price));
  }
  return max;
}

interface FreeProductRewardRow {
  id: string;
  name: string;
  external_id_shopify: string | null;
  shopify_free_product_id: string | null;
  shopify_free_product_amount: number | null;
  shopify_free_product_sync_price: boolean | null;
  redeem_window_start: string | null;
  redeem_window_end: string | null;
}

async function invokeUpsertFreeProduct(
  merchantId: string,
  reward: FreeProductRewardRow,
  productNumericId: string,
  amount: number,
): Promise<{ ok: boolean; error?: string; body?: unknown }> {
  const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
  const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
  const response = await fetch(`${supabaseUrl}/functions/v1/shopify-upsert-reward-discount`, {
    method: "POST",
    headers: {
      Authorization: `Bearer ${serviceKey}`,
      "Content-Type": "application/json",
    },
    body: JSON.stringify({
      merchant_id: merchantId,
      reward_id: reward.id,
      type: "free_product",
      title: reward.name,
      amount: String(amount),
      applies_to: "products",
      product_ids: [productNumericId],
      starts_at: reward.redeem_window_start || new Date().toISOString(),
      ends_at: reward.redeem_window_end,
    }),
  });
  const body = await response.json().catch(() => ({}));
  if (!response.ok || !body.success) {
    return { ok: false, error: body.error || `upsert HTTP ${response.status}`, body };
  }
  return { ok: true, body };
}

export async function handleProductWebhook(
  supabase: SupabaseClient,
  merchantId: string,
  payload: Record<string, unknown>,
): Promise<{ success: boolean; error_message?: string; data?: unknown }> {
  const ids = extractProductIds(payload);
  if (!ids) {
    return { success: true, data: { skipped: true, reason: "no_product_id" } };
  }

  const maxPrice = maxVariantPriceFromRest(payload);
  if (maxPrice <= 0) {
    return { success: true, data: { skipped: true, reason: "no_variant_prices", product_id: ids.numeric } };
  }

  const { data: rewards, error } = await supabase
    .from("reward_master")
    .select(
      "id, name, external_id_shopify, shopify_free_product_id, shopify_free_product_amount, shopify_free_product_sync_price, redeem_window_start, redeem_window_end",
    )
    .eq("merchant_id", merchantId)
    .eq("shopify_discount_type", "free_product")
    .not("shopify_free_product_id", "is", null)
    .or(`shopify_free_product_id.eq.${ids.numeric},shopify_free_product_id.eq.${ids.gid}`);

  if (error) {
    console.error(`${LOG_TAG} reward lookup error:`, error);
    return { success: false, error_message: error.message };
  }

  const rows = (rewards || []) as FreeProductRewardRow[];
  if (rows.length === 0) {
    return { success: true, data: { skipped: true, reason: "no_matching_rewards", product_id: ids.numeric } };
  }

  const results: Array<Record<string, unknown>> = [];
  for (const reward of rows) {
    if (reward.shopify_free_product_sync_price === false) {
      results.push({ reward_id: reward.id, skipped: true, reason: "custom_amount" });
      continue;
    }
    if (!pricesDiffer(reward.shopify_free_product_amount, maxPrice)) {
      results.push({ reward_id: reward.id, skipped: true, reason: "price_unchanged" });
      continue;
    }
    if (!reward.external_id_shopify) {
      results.push({ reward_id: reward.id, skipped: true, reason: "no_parent_discount" });
      continue;
    }

    try {
      const upsert = await invokeUpsertFreeProduct(merchantId, reward, ids.numeric, maxPrice);
      if (!upsert.ok) {
        console.error(`${LOG_TAG} upsert failed reward=${reward.id}:`, upsert.error);
        results.push({ reward_id: reward.id, updated: false, error: upsert.error });
        continue;
      }

      const label = `Free product — ${reward.name}`;
      const { error: updateErr } = await supabase
        .from("reward_master")
        .update({
          shopify_free_product_amount: maxPrice,
          shopify_discount_label: label,
        })
        .eq("id", reward.id)
        .eq("merchant_id", merchantId);

      if (updateErr) {
        console.error(`${LOG_TAG} reward_master amount update failed reward=${reward.id}:`, updateErr);
        results.push({ reward_id: reward.id, updated: true, discount_synced: true, cache_update_failed: updateErr.message });
        continue;
      }

      results.push({
        reward_id: reward.id,
        updated: true,
        old_amount: reward.shopify_free_product_amount,
        new_amount: maxPrice,
      });
    } catch (err) {
      console.error(`${LOG_TAG} sync exception reward=${reward.id}:`, err);
      results.push({ reward_id: reward.id, updated: false, error: (err as Error).message });
    }
  }

  return { success: true, data: { product_id: ids.numeric, max_price: maxPrice, results } };
}
