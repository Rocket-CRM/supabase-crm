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
  /** Re-fetch existing unclaimed ledger rows and write current platform status. */
  refresh_existing?: boolean;
  refresh_statuses?: string[];
  /** Keyset: walk past already-refreshed rows that stayed in refresh_statuses. */
  refresh_after_transaction_date?: string;
  refresh_after_order_sn?: string;
  /** Fetch specific order SNs by detail API and upsert into ledger (insert missing). */
  fetch_order_sns?: string[];
  /** Skip list; detail + stage these SNs (max 50). Insert-only staging — not fetch_order_sns upsert. */
  stage_order_sns?: string[];
}

type RefreshCursor = { transaction_date: string; order_sn: string };

type LedgerRefreshRow = {
  order_sn: string;
  order_status: string;
  transaction_date: string;
};

function isAfterRefreshCursor(
  row: LedgerRefreshRow,
  afterDate?: string,
  afterSn?: string,
): boolean {
  if (!afterDate) return true;
  const rowMs = new Date(row.transaction_date).getTime();
  const afterMs = new Date(afterDate).getTime();
  if (Number.isNaN(rowMs) || Number.isNaN(afterMs)) return true;
  if (rowMs > afterMs) return true;
  return Boolean(afterSn) && rowMs === afterMs && String(row.order_sn) > afterSn!;
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

  const skipListWindowGuard = Boolean(body.refresh_existing || body.stage_order_sns?.length);
  // Platform window guards (list APIs only — refresh_existing / stage_order_sns skip list)
  if (!skipListWindowGuard && platform === "shopee" && (createTimeLt - createTimeGe) > 15 * 86400) {
    return json({
      error: "shopee_window_too_large",
      detail: "Shopee get_order_list allows max 15 days per call. Pass a smaller create_time window.",
      window_seconds: createTimeLt - createTimeGe,
    }, 400);
  }
  if (!skipListWindowGuard && platform !== "shopee" && (createTimeLt - createTimeGe) > 7 * 86400 + 60) {
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

  if (body.fetch_order_sns?.length) {
    if (platform !== "shopee") {
      return json({ error: "fetch_order_sns_only_shopee" }, 400);
    }
    const orderSns = body.fetch_order_sns
      .map((s) => String(s).trim())
      .filter(Boolean)
      .slice(0, 50);
    if (orderSns.length === 0) {
      return json({ error: "fetch_order_sns_empty" }, 400);
    }

    const details = await getShopeeOrderDetails(creds, orderSns);
    const foundSns = new Set(details.map((d) => String(d.order_sn ?? "")));
    const missingOnShopee = orderSns.filter((sn) => !foundSns.has(sn));
    const results: Record<string, unknown>[] = [];

    for (const raw of details) {
      const normalized = normalizeShopeeOrder(raw, creds);
      const { data, error } = await supabase.rpc("upsert_marketplace_order", {
        p_order: normalized,
      });
      if (error) {
        results.push({
          order_sn: normalized.order_sn,
          success: false,
          error: error.message,
        });
      } else {
        results.push({
          order_sn: normalized.order_sn,
          success: true,
          ...(typeof data === "object" && data !== null ? data as Record<string, unknown> : { data }),
        });
      }
    }

    return json({
      success: true,
      mode: "fetch_order_sns",
      platform,
      shop_id: shopId,
      requested: orderSns.length,
      fetched: details.length,
      missing_on_shopee: missingOnShopee,
      results,
      duration_ms: Date.now() - started,
    });
  }

  if (body.refresh_existing) {
    const refreshStatuses = body.refresh_statuses?.length
      ? body.refresh_statuses
      : (platform === "lazada"
        ? ["confirmed", "packed", "ready_to_ship", "shipped"]
        : platform === "shopee"
        ? ["READY_TO_SHIP", "PROCESSED", "SHIPPED", "TO_CONFIRM_RECEIVE"]
        : ["AWAITING_SHIPMENT", "IN_TRANSIT"]);
    const limit = Math.min(maxSave > 0 ? maxSave : 50, 200);
    const afterDate = body.refresh_after_transaction_date?.trim() || undefined;
    const afterSn = body.refresh_after_order_sn?.trim() || undefined;
    let refreshQuery = supabase
      .from("order_ledger_mkp")
      .select("order_sn, order_status, transaction_date")
      .eq("platform", platform)
      .eq("shop_id", shopId)
      .eq("merchant_id", creds.merchant_id)
      .eq("synced_to_transaction", false)
      .in("order_status", refreshStatuses)
      .order("transaction_date", { ascending: true })
      .order("order_sn", { ascending: true })
      .limit(afterDate ? limit + 50 : limit);
    if (afterDate) {
      const afterIso = new Date(afterDate).toISOString();
      if (Number.isNaN(new Date(afterDate).getTime())) {
        return json({ error: "invalid_refresh_after_transaction_date" }, 400);
      }
      refreshQuery = refreshQuery.gte("transaction_date", afterIso);
    }
    const { data: rows, error: listErr } = await refreshQuery;
    if (listErr) return json({ error: "ledger_lookup_failed", detail: listErr.message }, 500);
    const selected = ((rows ?? []) as LedgerRefreshRow[])
      .filter((r) => isAfterRefreshCursor(r, afterDate, afterSn))
      .slice(0, limit);
    const targets = selected.map((r) => String(r.order_sn));
    const last = selected[selected.length - 1];
    const nextCursor: RefreshCursor | null = last
      ? { transaction_date: last.transaction_date, order_sn: String(last.order_sn) }
      : null;
    const exhausted = selected.length < limit;
    if (dryRun) {
      return json({
        success: true,
        dry_run: true,
        refresh_existing: true,
        platform,
        shop_id: shopId,
        merchant_id: creds.merchant_id,
        refresh_statuses: refreshStatuses,
        would_refresh: targets.length,
        sample_order_sns: targets.slice(0, 20),
        next_cursor: nextCursor,
        exhausted,
        duration_ms: Date.now() - started,
      });
    }
    let updated = 0;
    let unchanged = 0;
    let fetchErrors = 0;
    const samples: unknown[] = [];
    if (targets.length === 0) {
      return json({
        success: true,
        refresh_existing: true,
        platform,
        shop_id: shopId,
        merchant_id: creds.merchant_id,
        targeted: 0,
        updated: 0,
        unchanged: 0,
        fetch_errors: 0,
        samples: [],
        next_cursor: null,
        exhausted: true,
        duration_ms: Date.now() - started,
      });
    }
    try {
      const details = platform === "lazada"
        ? await getLazadaOrderDetails(creds, targets)
        : platform === "shopee"
        ? await getShopeeOrderDetails(creds, targets)
        : await getTiktokOrderDetails(creds, targets);
      for (const raw of details) {
        const normalized = platform === "lazada"
          ? normalizeLazadaOrder(raw, creds)
          : platform === "shopee"
          ? normalizeShopeeOrder(raw, creds)
          : normalizeTiktokOrder(raw, creds);
        const { data, error } = await supabase.rpc("update_marketplace_order_status", {
          p_order_sn: normalized.order_sn,
          p_platform: platform,
          p_order_status: normalized.order_status,
          p_update_time: normalized.update_time,
        });
        if (error) {
          fetchErrors++;
          if (samples.length < 10) samples.push({ order_sn: normalized.order_sn, error: error.message });
        } else if ((data as { action?: string })?.action === "updated") {
          updated++;
        } else {
          unchanged++;
        }
      }
    } catch (err) {
      return json({
        success: false,
        refresh_existing: true,
        platform,
        shop_id: shopId,
        error: err instanceof Error ? err.message : String(err),
        next_cursor: nextCursor,
        exhausted,
        duration_ms: Date.now() - started,
      }, 502);
    }
    return json({
      success: fetchErrors === 0,
      refresh_existing: true,
      platform,
      shop_id: shopId,
      merchant_id: creds.merchant_id,
      targeted: targets.length,
      updated,
      unchanged,
      fetch_errors: fetchErrors,
      samples,
      next_cursor: nextCursor,
      exhausted,
      duration_ms: Date.now() - started,
    });
  }

  const stageSns = (body.stage_order_sns ?? [])
    .map((s) => String(s).trim())
    .filter(Boolean)
    .slice(0, 50);
  if (stageSns.length && dryRun) {
    return json({ error: "stage_order_sns_requires_dry_run_false" }, 400);
  }

  const listedIds: string[] = [];
  const seen = new Set<string>();
  let pages = 0;

  if (stageSns.length) {
    for (const sn of stageSns) {
      if (seen.has(sn)) continue;
      seen.add(sn);
      listedIds.push(sn);
    }
  } else try {
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
      would_fetch_detail: toFetch.length,
      missing_order_sns: toFetch,
      sample_new_order_sns: toFetch.slice(0, 20),
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
    mode: stageSns.length ? "stage_order_sns" : "list_detail",
  });
});
