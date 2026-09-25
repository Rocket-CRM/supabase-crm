import { createClient } from "https://esm.sh/@supabase/supabase-js@2.46.0";
import type { NormalizedOrder, Platform, PlatformCredentials } from "./lib/types.ts";
import {
  getLazadaOrderDetails,
  listLazadaOrders,
  normalizeLazadaOrder,
} from "./lib/lazada.ts";
import {
  getShopeeOrderDetails,
  listShopeeOrders,
  normalizeShopeeOrder,
} from "./lib/shopee.ts";
import {
  getTiktokOrderDetails,
  normalizeTiktokOrder,
  searchTiktokOrders,
} from "./lib/tiktok.ts";

interface BackfillRequest {
  platform: Platform;
  shop_id: string;
  /** Unix seconds; overrides days_back when set with create_time_lt */
  create_time_ge?: number;
  create_time_lt?: number;
  days_back?: number;
  /** dry_run: list only, no staging writes / no detail fetch */
  dry_run?: boolean;
  max_pages?: number;
  /** Cap detail fetches / staging writes (0 = no cap) */
  max_save?: number;
  skip_unpaid?: boolean;
}

function json(data: unknown, status = 200): Response {
  return new Response(JSON.stringify(data), {
    status,
    headers: { "Content-Type": "application/json" },
  });
}

function authorize(req: Request): boolean {
  const expected = Deno.env.get("MARKETPLACE_BACKFILL_SECRET");
  if (!expected) return true;
  const header = req.headers.get("x-marketplace-backfill-secret") ?? "";
  return header === expected;
}

function sleep(ms: number): Promise<void> {
  return new Promise((r) => setTimeout(r, ms));
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response(null, {
      headers: {
        "Access-Control-Allow-Origin": "*",
        "Access-Control-Allow-Methods": "POST, OPTIONS",
        "Access-Control-Allow-Headers":
          "Content-Type, Authorization, x-marketplace-backfill-secret",
      },
    });
  }

  if (req.method !== "POST") return json({ error: "method_not_allowed" }, 405);
  if (!authorize(req)) return json({ error: "unauthorized" }, 401);

  const started = Date.now();
  let body: BackfillRequest;
  try {
    body = await req.json();
  } catch {
    return json({ error: "invalid_json" }, 400);
  }

  const platform = body.platform;
  const shopId = body.shop_id?.trim();
  if (!platform || !["shopee", "lazada", "tiktok"].includes(platform)) {
    return json({ error: "platform must be shopee|lazada|tiktok" }, 400);
  }
  if (!shopId) return json({ error: "shop_id is required" }, 400);

  const dryRun = body.dry_run !== false;
  const maxPages = Math.min(body.max_pages ?? 50, 200);
  const maxSave = body.max_save ?? 0;
  const skipUnpaid = body.skip_unpaid !== false;

  const now = Math.floor(Date.now() / 1000);
  const createTimeLt = body.create_time_lt ?? now;
  const createTimeGe = body.create_time_ge ??
    (now - (body.days_back ?? 7) * 86400);

  // Platform window guards
  if (platform === "shopee" && (createTimeLt - createTimeGe) > 15 * 86400) {
    return json({
      error: "shopee_window_too_large",
      detail: "Shopee get_order_list allows max 15 days per call. Pass a smaller create_time window.",
      window_seconds: createTimeLt - createTimeGe,
    }, 400);
  }
  if (platform !== "shopee" && (createTimeLt - createTimeGe) > 7 * 86400 + 60) {
    return json({
      error: "window_too_large",
      detail: "Use ≤7-day chunks for TikTok/Lazada backfill to stay under pagination/rate limits.",
      window_seconds: createTimeLt - createTimeGe,
    }, 400);
  }

  const supabase = createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
  );

  const { data: credRow, error: credErr } = await supabase.rpc("get_shop_credentials", {
    p_shop_id: shopId,
    p_platform: platform,
  });
  if (credErr || !credRow) {
    return json({ error: "credentials_not_found", detail: credErr?.message }, 404);
  }

  const creds: PlatformCredentials = {
    merchant_id: String(credRow.merchant_id),
    shop_id: String(credRow.shop_id ?? shopId),
    partner_id: credRow.partner_id != null ? String(credRow.partner_id) : undefined,
    access_token: String(credRow.access_token),
    shop_cipher: credRow.shop_cipher != null ? String(credRow.shop_cipher) : undefined,
    app_key: credRow.app_key != null ? String(credRow.app_key) : undefined,
    app_secret: credRow.app_secret != null ? String(credRow.app_secret) : undefined,
  };

  const listedIds: string[] = [];
  const seen = new Set<string>();
  let pages = 0;

  try {
    if (platform === "tiktok") {
      let pageToken: string | undefined;
      for (pages = 0; pages < maxPages; pages++) {
        const page = await searchTiktokOrders(creds, {
          create_time_ge: createTimeGe,
          create_time_lt: createTimeLt,
          page_size: 50,
          page_token: pageToken,
        });
        if (page.code !== 0) {
          return json({
            success: false,
            phase: "list",
            platform,
            shop_id: shopId,
            tiktok_code: page.code,
            tiktok_message: page.message,
            pages_completed: pages,
            duration_ms: Date.now() - started,
          }, 502);
        }
        for (const o of page.orders) {
          if (skipUnpaid && o.status === "UNPAID") continue;
          if (!o.id || seen.has(o.id)) continue;
          seen.add(o.id);
          listedIds.push(o.id);
        }
        pageToken = page.next_page_token;
        if (!pageToken || page.orders.length === 0) break;
        await sleep(800);
      }
    } else if (platform === "shopee") {
      let cursor: string | undefined;
      for (pages = 0; pages < maxPages; pages++) {
        const page = await listShopeeOrders(creds, {
          time_from: createTimeGe,
          time_to: createTimeLt,
          page_size: 50,
          cursor,
        });
        for (const sn of page.order_sns) {
          if (!sn || seen.has(sn)) continue;
          seen.add(sn);
          listedIds.push(sn);
        }
        if (!page.more || !page.next_cursor) break;
        cursor = page.next_cursor;
        await sleep(1200);
      }
    } else {
      // lazada
      let offset = 0;
      for (pages = 0; pages < maxPages; pages++) {
        const page = await listLazadaOrders(creds, {
          created_after_unix: createTimeGe,
          created_before_unix: createTimeLt,
          offset,
          limit: 100,
        });
        for (const id of page.order_ids) {
          if (!id || seen.has(id)) continue;
          seen.add(id);
          listedIds.push(id);
        }
        if (page.order_ids.length === 0) break;
        offset += page.order_ids.length;
        if (offset >= 5000) break;
        if (offset >= page.count && page.count > 0) break;
        await sleep(1200);
      }
    }
  } catch (err) {
    return json({
      success: false,
      phase: "list",
      platform,
      shop_id: shopId,
      error: err instanceof Error ? err.message : String(err),
      pages_completed: pages,
      orders_listed: listedIds.length,
      duration_ms: Date.now() - started,
    }, 502);
  }

  // Skip order_sns already in ledger (go-live)
  const existing = new Set<string>();
  for (let i = 0; i < listedIds.length; i += 200) {
    const chunk = listedIds.slice(i, i + 200);
    const { data: rows, error } = await supabase
      .from("order_ledger_mkp")
      .select("order_sn")
      .eq("platform", platform)
      .in("order_sn", chunk);
    if (error) {
      return json({ error: "ledger_lookup_failed", detail: error.message }, 500);
    }
    for (const r of rows ?? []) existing.add(String(r.order_sn));
  }

  const toFetch = listedIds.filter((id) => !existing.has(id));
  const capped = maxSave > 0 ? toFetch.slice(0, maxSave) : toFetch;

  if (dryRun) {
    return json({
      success: true,
      dry_run: true,
      platform,
      shop_id: shopId,
      merchant_id: creds.merchant_id,
      window: { create_time_ge: createTimeGe, create_time_lt: createTimeLt },
      pages_searched: pages + (platform === "tiktok" ? 1 : 0),
      orders_listed: listedIds.length,
      already_in_ledger: existing.size,
      would_fetch_detail: capped.length,
      sample_new_order_sns: capped.slice(0, 20),
      sample_existing_order_sns: [...existing].slice(0, 20),
      duration_ms: Date.now() - started,
    });
  }

  let staged = 0;
  let stageErrors = 0;
  const errorSamples: unknown[] = [];

  async function stageOrder(raw: Record<string, unknown>, normalized: NormalizedOrder): Promise<void> {
    if (!normalized.order_sn || !normalized.items?.length) {
      stageErrors++;
      errorSamples.push({ order_sn: normalized.order_sn, error: "missing order_sn or items" });
      return;
    }
    const { error } = await supabase.from("stg_marketplace_backfill").upsert({
      merchant_id: creds.merchant_id,
      platform,
      shop_id: creds.shop_id,
      order_sn: normalized.order_sn,
      create_time: normalized.transaction_date,
      raw,
      normalized,
      window_start: new Date(createTimeGe * 1000).toISOString(),
      window_end: new Date(createTimeLt * 1000).toISOString(),
      fetch_status: "ready",
      error: null,
      updated_at: new Date().toISOString(),
    }, { onConflict: "platform,order_sn" });
    if (error) {
      stageErrors++;
      if (errorSamples.length < 20) {
        errorSamples.push({ order_sn: normalized.order_sn, error: error.message });
      }
    } else {
      staged++;
    }
  }

  // Mark skipped_exists in staging for audit (optional, capped)
  for (const sn of [...existing].slice(0, 500)) {
    await supabase.from("stg_marketplace_backfill").upsert({
      merchant_id: creds.merchant_id,
      platform,
      shop_id: creds.shop_id,
      order_sn: sn,
      window_start: new Date(createTimeGe * 1000).toISOString(),
      window_end: new Date(createTimeLt * 1000).toISOString(),
      fetch_status: "skipped_exists",
      promoted_at: new Date().toISOString(),
      promote_action: "skipped_exists",
      raw: {},
      updated_at: new Date().toISOString(),
    }, { onConflict: "platform,order_sn" });
  }

  try {
    if (platform === "tiktok") {
      for (let i = 0; i < capped.length; i += 50) {
        const chunk = capped.slice(i, i + 50);
        const details = await getTiktokOrderDetails(creds, chunk);
        for (const raw of details) {
          await stageOrder(raw, normalizeTiktokOrder(raw, creds));
        }
        await sleep(800);
      }
    } else if (platform === "shopee") {
      for (let i = 0; i < capped.length; i += 50) {
        const chunk = capped.slice(i, i + 50);
        const details = await getShopeeOrderDetails(creds, chunk);
        for (const raw of details) {
          await stageOrder(raw, normalizeShopeeOrder(raw, creds));
        }
        await sleep(1200);
      }
    } else {
      for (let i = 0; i < capped.length; i += 5) {
        const chunk = capped.slice(i, i + 5);
        const details = await getLazadaOrderDetails(creds, chunk);
        for (const raw of details) {
          await stageOrder(raw, normalizeLazadaOrder(raw, creds));
        }
        await sleep(1000);
      }
    }
  } catch (err) {
    return json({
      success: false,
      phase: "detail_or_stage",
      platform,
      shop_id: shopId,
      error: err instanceof Error ? err.message : String(err),
      orders_listed: listedIds.length,
      already_in_ledger: existing.size,
      staged,
      stage_errors: stageErrors,
      duration_ms: Date.now() - started,
    }, 502);
  }

  return json({
    success: stageErrors === 0,
    dry_run: false,
    platform,
    shop_id: shopId,
    merchant_id: creds.merchant_id,
    window: { create_time_ge: createTimeGe, create_time_lt: createTimeLt },
    orders_listed: listedIds.length,
    already_in_ledger: existing.size,
    detail_fetched_target: capped.length,
    staged,
    stage_errors: stageErrors,
    error_samples: errorSamples,
    duration_ms: Date.now() - started,
    next_step: "Call RPC fn_promote_marketplace_backfill(p_batch_size, merchant_id, platform) until drained",
  });
});
