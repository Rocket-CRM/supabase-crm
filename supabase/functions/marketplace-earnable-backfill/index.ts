import { createClient } from "https://esm.sh/@supabase/supabase-js@2.46.0";
import { ShopeeAdapter } from "../inngest-marketplace-serve/adapters/shopee-adapter.ts";
import { LazadaAdapter } from "../inngest-marketplace-serve/adapters/lazada-adapter.ts";
import { TikTokAdapter } from "../inngest-marketplace-serve/adapters/tiktok-adapter.ts";
import type {
  NormalizedOrder,
  PlatformCredentials,
} from "../inngest-marketplace-serve/adapters/types.ts";

type Platform = "shopee" | "lazada" | "tiktok";

type LedgerRow = {
  id: string;
  order_sn: string;
  order_status: string;
  shop_id: string;
};

const adapters = {
  shopee: new ShopeeAdapter(),
  lazada: new LazadaAdapter(),
  tiktok: new TikTokAdapter(),
};

const supabase = createClient(
  Deno.env.get("SUPABASE_URL")!,
  Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
);

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json" },
  });
}

function authorize(request: Request): boolean {
  const expected = Deno.env.get("MARKETPLACE_BACKFILL_SECRET");
  if (!expected) return true;
  const header = request.headers.get("x-marketplace-backfill-secret") ?? "";
  return header === expected;
}

function batchLimit(platform: Platform, requested?: number): number {
  const cap = platform === "lazada" ? 5 : 20;
  return Math.min(cap, Math.max(1, requested ?? cap));
}

Deno.serve(async (request) => {
  if (request.method === "OPTIONS") {
    return new Response(null, {
      headers: {
        "Access-Control-Allow-Origin": "*",
        "Access-Control-Allow-Methods": "POST, OPTIONS",
        "Access-Control-Allow-Headers":
          "Content-Type, Authorization, x-marketplace-backfill-secret",
      },
    });
  }

  if (request.method !== "POST") return json({ error: "method_not_allowed" }, 405);
  if (!authorize(request)) return json({ error: "unauthorized" }, 401);

  const body = await request.json().catch(() => ({})) as {
    merchant_id?: string;
    platform?: Platform;
    shop_id?: string;
    after_id?: string;
    limit?: number;
    since_date?: string | null;
    dry_run?: boolean;
  };

  const platform = body.platform;
  if (!platform || !(platform in adapters)) {
    return json({ error: "invalid_platform" }, 400);
  }

  const merchantId = body.merchant_id ?? "ffe8519e-49a2-467b-a0ec-57d28ba8be49";
  const shopId = body.shop_id;
  if (!shopId) return json({ error: "shop_id_required" }, 400);

  const limit = batchLimit(platform, body.limit);
  const sinceDate = body.since_date === undefined ? "2026-08-10" : body.since_date;
  const dryRun = body.dry_run === true;

  let orderQuery = supabase
    .from("order_ledger_mkp")
    .select("id,order_sn,order_status,shop_id")
    .eq("merchant_id", merchantId)
    .eq("platform", platform)
    .eq("shop_id", shopId)
    .is("claimed_user_id", null)
    .or("synced_to_transaction.is.null,synced_to_transaction.eq.false")
    .is("earnable_amount", null)
    .order("id", { ascending: true })
    .limit(limit);

  if (sinceDate) orderQuery = orderQuery.gte("transaction_date", sinceDate);
  if (body.after_id) orderQuery = orderQuery.gt("id", body.after_id);

  const { data: ledgerRows, error: ledgerError } = await orderQuery;
  if (ledgerError) return json({ error: ledgerError.message }, 500);
  if (!ledgerRows?.length) {
    return json({
      success: true,
      platform,
      merchant_id: merchantId,
      shop_id: shopId,
      processed: 0,
      updated: 0,
      errors: 0,
      has_more: false,
      dry_run: dryRun,
    });
  }

  const rows = ledgerRows as LedgerRow[];
  const orderSns = rows.map((row) => row.order_sn);

  if (dryRun) {
    return json({
      success: true,
      platform,
      merchant_id: merchantId,
      shop_id: shopId,
      processed: rows.length,
      updated: 0,
      errors: 0,
      order_sns: orderSns,
      next_after_id: rows[rows.length - 1].id,
      has_more: rows.length === limit,
      dry_run: true,
    });
  }

  const { data: credentials, error: credentialError } = await supabase.rpc(
    "get_shop_credentials",
    { p_shop_id: shopId, p_platform: platform },
  );
  if (credentialError || !credentials) {
    return json({ error: credentialError?.message || "credentials_not_found" }, 500);
  }

  const adapter = adapters[platform];
  const apiResult = await adapter.fetchOrders(
    credentials as PlatformCredentials,
    orderSns,
  );

  const statusBySn = new Map(rows.map((row) => [row.order_sn, row.order_status]));
  const normalizedBySn = new Map<string, NormalizedOrder>();
  const normalizeErrors: { order_sn: string; error: string }[] = [];

  for (const rawOrder of apiResult.orders || []) {
    try {
      const normalized = adapter.normalizeOrder(rawOrder, credentials as PlatformCredentials);
      const ledgerStatus = statusBySn.get(normalized.order_sn);
      if (ledgerStatus) normalized.order_status = ledgerStatus;
      normalizedBySn.set(normalized.order_sn, normalized);
    } catch (error) {
      const raw = rawOrder as { order_sn?: string; id?: string; order_id?: string };
      normalizeErrors.push({
        order_sn: String(raw.order_sn || raw.id || raw.order_id || "unknown"),
        error: error instanceof Error ? error.message : String(error),
      });
    }
  }

  let updated = 0;
  const upsertErrors: { order_sn: string; error: string }[] = [];

  for (const row of rows) {
    const normalized = normalizedBySn.get(row.order_sn);
    if (!normalized) {
      upsertErrors.push({
        order_sn: row.order_sn,
        error: normalizeErrors.find((entry) => entry.order_sn === row.order_sn)?.error
          || (apiResult.skipped_order_sns || []).includes(row.order_sn)
          ? apiResult.error || "platform_order_not_returned"
          : "platform_order_not_returned",
      });
      continue;
    }

    const { error } = await supabase.rpc("upsert_marketplace_order", {
      p_order: normalized,
    });
    if (error) {
      upsertErrors.push({ order_sn: row.order_sn, error: error.message });
      continue;
    }
    updated += 1;
  }

  return json({
    success: true,
    platform,
    merchant_id: merchantId,
    shop_id: shopId,
    processed: rows.length,
    updated,
    errors: upsertErrors.length,
    api_error: apiResult.error,
    upsert_errors: upsertErrors.slice(0, 20),
    next_after_id: rows[rows.length - 1].id,
    has_more: rows.length === limit,
    dry_run: false,
  });
});
