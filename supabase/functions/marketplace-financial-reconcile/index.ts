import { createClient } from "https://esm.sh/@supabase/supabase-js@2.46.0";
import { ShopeeAdapter } from "../inngest-marketplace-serve/adapters/shopee-adapter.ts";
import { LazadaAdapter } from "../inngest-marketplace-serve/adapters/lazada-adapter.ts";
import { TikTokAdapter } from "../inngest-marketplace-serve/adapters/tiktok-adapter.ts";
import type {
  NormalizedOrder,
  PlatformCredentials,
} from "../inngest-marketplace-serve/adapters/types.ts";

const MERCHANT_ID = "ffe8519e-49a2-467b-a0ec-57d28ba8be49";
const SHOP_IDS = {
  shopee: "224882570",
  lazada: "100184574113",
  tiktok: "7495127669839399750",
} as const;
const SOURCE_BY_PLATFORM = {
  shopee: "marketplace_shopee",
  lazada: "marketplace_lazada",
  tiktok: "marketplace_tiktok",
} as const;
type Platform = keyof typeof SHOP_IDS;

const supabase = createClient(
  Deno.env.get("SUPABASE_URL")!,
  Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
);

const adapters = {
  shopee: new ShopeeAdapter(),
  lazada: new LazadaAdapter(),
  tiktok: new TikTokAdapter(),
};

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json" },
  });
}

function orderSn(transactionNumber: string): string {
  return transactionNumber.replace(/^MKP-[A-Z]+-/i, "");
}

function pointsFor(earnableAmount: number): number {
  return Math.floor(Math.max(0, Math.round(earnableAmount * 100)) / 5000);
}

async function fetchOrders(
  platform: Platform,
  credentials: PlatformCredentials,
  orderSns: string[],
) {
  return await adapters[platform].fetchOrders(credentials, orderSns);
}

Deno.serve(async (request) => {
  if (request.method !== "POST") return json({ error: "method_not_allowed" }, 405);

  const body = await request.json().catch(() => ({})) as {
    platform?: Platform;
    run_id?: string;
    after_id?: string;
    limit?: number;
  };
  const platform = body.platform;
  if (!platform || !(platform in SHOP_IDS)) return json({ error: "invalid_platform" }, 400);

  const runId = body.run_id || crypto.randomUUID();
  const limit = Math.min(platform === "lazada" ? 5 : 20, Math.max(1, body.limit || 20));

  let purchaseQuery = supabase
    .from("purchase_ledger")
    .select("id,user_id,transaction_number,final_amount")
    .eq("merchant_id", MERCHANT_ID)
    .eq("transaction_source", SOURCE_BY_PLATFORM[platform])
    .eq("record_type", "credit")
    .not("transaction_number", "is", null)
    .order("id", { ascending: true })
    .limit(limit);
  if (body.after_id) purchaseQuery = purchaseQuery.gt("id", body.after_id);

  const { data: purchases, error: purchaseError } = await purchaseQuery;
  if (purchaseError) return json({ error: purchaseError.message }, 500);
  if (!purchases?.length) {
    return json({ success: true, run_id: runId, platform, processed: 0, has_more: false });
  }

  const sns = purchases.map((purchase) => orderSn(String(purchase.transaction_number)));
  const purchaseBySn = new Map(
    purchases.map((purchase) => [orderSn(String(purchase.transaction_number)), purchase]),
  );

  const { data: credentials, error: credentialError } = await supabase.rpc(
    "get_shop_credentials",
    { p_shop_id: SHOP_IDS[platform], p_platform: platform },
  );
  if (credentialError || !credentials) {
    return json({ error: credentialError?.message || "credentials_not_found" }, 500);
  }

  const [apiResult, orderRowsResult, walletRowsResult] = await Promise.all([
    fetchOrders(platform, credentials as PlatformCredentials, sns),
    supabase
      .from("order_ledger_mkp")
      .select("id,order_sn")
      .eq("merchant_id", MERCHANT_ID)
      .eq("platform", platform)
      .in("order_sn", sns),
    supabase
      .from("wallet_ledger")
      .select("source_id,signed_amount")
      .eq("merchant_id", MERCHANT_ID)
      .eq("source_type", "purchase")
      .eq("transaction_type", "earn")
      .eq("currency", "points")
      .in("source_id", purchases.map((purchase) => purchase.id)),
  ]);

  const orderIdBySn = new Map(
    (orderRowsResult.data || []).map((order) => [String(order.order_sn), order.id]),
  );
  const currentPointsByPurchase = new Map<string, number>();
  for (const row of walletRowsResult.data || []) {
    currentPointsByPurchase.set(
      row.source_id,
      (currentPointsByPurchase.get(row.source_id) || 0) + Number(row.signed_amount || 0),
    );
  }

  const normalizedBySn = new Map<string, NormalizedOrder>();
  const normalizeErrors = new Map<string, string>();
  for (const rawOrder of apiResult.orders || []) {
    try {
      const normalized = adapters[platform].normalizeOrder(rawOrder, credentials as PlatformCredentials);
      normalizedBySn.set(normalized.order_sn, normalized);
    } catch (error) {
      const raw = rawOrder as { order_sn?: string; id?: string; order_id?: string };
      const sn = String(raw.order_sn || raw.id || raw.order_id || "unknown");
      normalizeErrors.set(sn, error instanceof Error ? error.message : String(error));
    }
  }

  const rows = purchases.map((purchase) => {
    const sn = orderSn(String(purchase.transaction_number));
    const normalized = normalizedBySn.get(sn);
    const currentAmount = Number(purchase.final_amount || 0);
    const currentPoints = currentPointsByPurchase.get(purchase.id) || 0;
    const proposedAmount = normalized ? Number(normalized.earnable_amount) : null;
    const proposedPoints = proposedAmount == null ? null : pointsFor(proposedAmount);

    return {
      run_id: runId,
      merchant_id: MERCHANT_ID,
      platform,
      order_sn: sn,
      order_id: orderIdBySn.get(sn) || null,
      purchase_id: purchase.id,
      current_purchase_amount: currentAmount,
      proposed_earnable_amount: proposedAmount,
      amount_delta: proposedAmount == null ? null : proposedAmount - currentAmount,
      current_points: currentPoints,
      proposed_points: proposedPoints,
      points_delta: proposedPoints == null ? null : proposedPoints - currentPoints,
      proposed_financials: normalized?.financial_details || {},
      proposed_items: (normalized?.items || []).map((item) => ({
        platform_item_id: item.platform_item_id,
        variant_id: item.variant_id,
        unit_price: item.unit_price,
        quantity: item.quantity,
        discount_amount: item.discount_amount,
        line_total: item.line_total,
        earnable_amount: item.earnable_amount,
        financial_details: item.financial_details || {},
      })),
      fetch_status: normalized ? "fetched" : "error",
      error: normalized
        ? null
        : normalizeErrors.get(sn) || (apiResult.skipped_order_sns || []).includes(sn)
        ? apiResult.error || "platform_order_not_returned"
        : "platform_order_not_returned",
    };
  });

  const { error: stageError } = await supabase
    .from("stg_marketplace_financial_reconciliation")
    .upsert(rows, { onConflict: "run_id,platform,order_sn" });
  if (stageError) return json({ error: stageError.message }, 500);

  const fetched = rows.filter((row) => row.fetch_status === "fetched");
  return json({
    success: true,
    run_id: runId,
    platform,
    processed: rows.length,
    fetched: fetched.length,
    errors: rows.length - fetched.length,
    current_amount: fetched.reduce((sum, row) => sum + Number(row.current_purchase_amount), 0),
    proposed_amount: fetched.reduce((sum, row) => sum + Number(row.proposed_earnable_amount), 0),
    current_points: fetched.reduce((sum, row) => sum + Number(row.current_points), 0),
    proposed_points: fetched.reduce((sum, row) => sum + Number(row.proposed_points), 0),
    next_after_id: purchases[purchases.length - 1].id,
    has_more: purchases.length === limit,
  });
});
