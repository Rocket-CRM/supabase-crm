// marketplace-items-repair — items-only repair for order_ledger_mkp rows that have no
// order_items_ledger_mkp rows. Re-fetches order detail from the platform using the SAME
// adapters as the live ingest (inngest-marketplace-serve/adapters) and writes items through
// fn_mkp_repair_order_items_batch (header untouched).
//
// Deploy: copy ../../../../supabase/functions/inngest-marketplace-serve/adapters/*.ts into
// ./adapters/ next to this file, then deploy this folder as function "marketplace-items-repair".
//
// POST body:
//   { platform: "shopee"|"tiktok"|"lazada", shop_id: string,
//     tier?: "claimed"|"active"|"all" (default "claimed"),
//     partitions?: number, partition?: number   (run N workers in parallel: worker k sends partitions=N, partition=k)
//     batch_size?: number (<=50), time_budget_ms?: number (default 100000, max 120000),
//     sleep_ms?: number (default 200 between batches), dry_run?: boolean,
//     order_sns?: string[] (repair exactly these SNs, ignores tier/partition) }

import { createClient } from "https://esm.sh/@supabase/supabase-js@2.46.0";
import { ShopeeAdapter } from "./adapters/shopee-adapter.ts";
import { TikTokAdapter } from "./adapters/tiktok-adapter.ts";
import { LazadaAdapter } from "./adapters/lazada-adapter.ts";
import type { NormalizedOrder, PlatformCredentials } from "./adapters/types.ts";

type Platform = "shopee" | "tiktok" | "lazada";
type Tier = "claimed" | "active" | "all";

type FetchResult = {
  success: boolean;
  orders: Record<string, unknown>[];
  error: string | null;
  skipped_order_sns: string[];
};

type RepairAdapter = {
  fetchOrders(credentials: PlatformCredentials, orderSns: string[]): Promise<FetchResult>;
  normalizeOrder(order: Record<string, unknown>, credentials: PlatformCredentials): NormalizedOrder;
};

type Body = {
  platform: Platform;
  shop_id: string;
  tier?: Tier;
  partitions?: number;
  partition?: number;
  batch_size?: number;
  time_budget_ms?: number;
  sleep_ms?: number;
  dry_run?: boolean;
  order_sns?: string[];
};

type BatchResult = {
  success: boolean;
  repaired?: number;
  items_inserted?: number;
  failed?: number;
  failures?: unknown[];
  code?: string;
};

const adapters: Record<Platform, RepairAdapter> = {
  shopee: new ShopeeAdapter() as unknown as RepairAdapter,
  tiktok: new TikTokAdapter() as unknown as RepairAdapter,
  lazada: new LazadaAdapter() as unknown as RepairAdapter,
};

function json(data: unknown, status = 200): Response {
  return new Response(JSON.stringify(data), {
    status,
    headers: { "Content-Type": "application/json" },
  });
}

const sleep = (ms: number) => new Promise((r) => setTimeout(r, ms));

Deno.serve(async (req: Request) => {
  if (req.method !== "POST") return json({ error: "method_not_allowed" }, 405);
  const started = Date.now();

  let body: Body;
  try {
    body = await req.json();
  } catch {
    return json({ error: "invalid_json" }, 400);
  }

  const platform = body.platform;
  const shopId = String(body.shop_id ?? "").trim();
  if (!platform || !(platform in adapters)) return json({ error: "platform must be shopee|tiktok|lazada" }, 400);
  if (!shopId) return json({ error: "shop_id is required" }, 400);

  const tier: Tier = body.tier ?? "claimed";
  const partitions = Math.max(Math.trunc(body.partitions ?? 1), 1);
  const partition = Math.min(Math.max(Math.trunc(body.partition ?? 0), 0), partitions - 1);
  const batchSize = Math.min(Math.max(body.batch_size ?? 50, 1), 50);
  const timeBudget = Math.min(body.time_budget_ms ?? 100_000, 120_000);
  const sleepMs = Math.max(body.sleep_ms ?? 200, 0);
  const dryRun = body.dry_run === true;
  const explicitSns = (body.order_sns ?? []).map((s) => String(s).trim()).filter(Boolean).slice(0, 50);

  const supabase = createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
  );

  const { data: credRow, error: credErr } = await supabase.rpc("get_shop_credentials", {
    p_shop_id: shopId,
    p_platform: platform,
  });
  if (credErr || !credRow) return json({ error: "credentials_not_found", detail: credErr?.message }, 404);
  const credentials = credRow as PlatformCredentials;
  const adapter = adapters[platform];

  const totals = {
    batches: 0,
    picked: 0,
    repaired: 0,
    items_inserted: 0,
    failed_in_rpc: 0,
    not_returned_by_platform: 0,
    fetch_errors: 0,
  };
  const samples: unknown[] = [];

  while (Date.now() - started < timeBudget) {
    let orderSns: string[];
    if (explicitSns.length) {
      orderSns = explicitSns;
    } else {
      const { data: picked, error: pickErr } = await supabase.rpc("fn_mkp_items_repair_pick", {
        p_merchant_id: credentials.merchant_id,
        p_platform: platform,
        p_shop_id: shopId,
        p_tier: tier,
        p_limit: batchSize,
        p_partitions: partitions,
        p_partition: partition,
      });
      if (pickErr) return json({ error: "pick_failed", detail: pickErr.message, totals }, 500);
      orderSns = ((picked ?? []) as { order_sn: string }[]).map((r) => String(r.order_sn));
    }
    if (orderSns.length === 0) break;

    totals.batches++;
    totals.picked += orderSns.length;

    if (dryRun) {
      samples.push({ would_fetch: orderSns });
      break;
    }

    // 1) one platform round-trip for up to 50 orders (Shopee: detail + escrow batch; TikTok: detail + parallel price_detail)
    let result: FetchResult;
    try {
      result = await adapter.fetchOrders(credentials, orderSns);
    } catch (err) {
      totals.fetch_errors++;
      const message = err instanceof Error ? err.message : String(err);
      await supabase.rpc("fn_mkp_repair_order_items_batch", {
        p_orders: orderSns.map((sn) => ({ platform, order_sn: sn, merchant_id: credentials.merchant_id, items: [] })),
      }); // logs one failed attempt per SN (NO_ITEMS_IN_PAYLOAD) so a dead SN is retired after 3 tries
      if (samples.length < 20) samples.push({ fetch_error: message, order_sns: orderSns.slice(0, 5) });
      if (explicitSns.length) break;
      await sleep(sleepMs);
      continue;
    }
    if (!result.success && result.error && samples.length < 20) {
      samples.push({ fetch_error: result.error, order_sns: orderSns.slice(0, 5) });
    }

    // 2) normalise exactly like live ingest
    const normalizedOrders: NormalizedOrder[] = [];
    for (const raw of result.orders ?? []) {
      try {
        normalizedOrders.push(adapter.normalizeOrder(raw, credentials));
      } catch (err) {
        if (samples.length < 20) samples.push({ normalize_error: err instanceof Error ? err.message : String(err) });
      }
    }
    const returned = new Set(normalizedOrders.map((o) => o.order_sn));
    // SNs the platform did not return get an empty-items stub so the batch RPC logs an attempt for them
    const missing = orderSns.filter((sn) => !returned.has(sn));
    totals.not_returned_by_platform += missing.length;
    const payload = [
      ...normalizedOrders,
      ...missing.map((sn) => ({ platform, order_sn: sn, merchant_id: credentials.merchant_id, items: [] })),
    ];

    // 3) one DB round-trip for the whole batch
    const { data, error } = await supabase.rpc("fn_mkp_repair_order_items_batch", { p_orders: payload });
    if (error) {
      totals.failed_in_rpc += payload.length;
      if (samples.length < 20) samples.push({ rpc_error: error.message, order_sns: orderSns.slice(0, 5) });
    } else {
      const res = data as BatchResult;
      totals.repaired += res.repaired ?? 0;
      totals.items_inserted += res.items_inserted ?? 0;
      totals.failed_in_rpc += Math.max((res.failed ?? 0) - missing.length, 0);
      for (const f of res.failures ?? []) if (samples.length < 20) samples.push(f);
    }

    if (explicitSns.length) break;
    await sleep(sleepMs);
  }

  const { data: remaining } = await supabase.rpc("fn_mkp_items_repair_remaining", {
    p_merchant_id: credentials.merchant_id,
    p_platform: platform,
    p_shop_id: shopId,
  });

  return json({
    success: true,
    platform,
    shop_id: shopId,
    tier,
    partitions,
    partition,
    dry_run: dryRun,
    totals,
    remaining,
    samples,
    duration_ms: Date.now() - started,
  });
});
