import { createClient } from "https://esm.sh/@supabase/supabase-js@2.46.0";
import {
  getTiktokOrderDetails,
  normalizeTiktokOrder,
  searchTiktokOrders,
  type TiktokCredentials,
} from "./lib/tiktok-client.ts";

const API_BATCH = 50;

interface BackfillRequest {
  shop_id: string;
  /** Fetch specific order IDs (skips search pagination) */
  order_sns?: string[];
  /** Unix seconds; overrides days_back when both ends set */
  create_time_ge?: number;
  create_time_lt?: number;
  days_back?: number;
  dry_run?: boolean;
  max_pages?: number;
  /** Cap orders upserted (after detail fetch); 0 = no cap */
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

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response(null, {
      headers: {
        "Access-Control-Allow-Origin": "*",
        "Access-Control-Allow-Methods": "POST, OPTIONS",
        "Access-Control-Allow-Headers": "Content-Type, Authorization, x-marketplace-backfill-secret",
      },
    });
  }

  if (req.method !== "POST") {
    return json({ error: "method_not_allowed" }, 405);
  }

  if (!authorize(req)) {
    return json({ error: "unauthorized" }, 401);
  }

  const started = Date.now();
  let body: BackfillRequest;
  try {
    body = await req.json();
  } catch {
    return json({ error: "invalid_json" }, 400);
  }

  const shopId = body.shop_id?.trim();
  if (!shopId) return json({ error: "shop_id is required" }, 400);

  const dryRun = body.dry_run !== false;
  const maxPages = Math.min(body.max_pages ?? 200, 500);
  const maxSave = body.max_save ?? 0;
  const skipUnpaid = body.skip_unpaid !== false;

  const now = Math.floor(Date.now() / 1000);
  const createTimeLt = body.create_time_lt ?? now;
  const createTimeGe = body.create_time_ge ??
    (now - (body.days_back ?? 30) * 86400);

  const supabase = createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
  );

  const { data: credRow, error: credErr } = await supabase.rpc("get_shop_credentials", {
    p_shop_id: shopId,
    p_platform: "tiktok",
  });

  if (credErr || !credRow) {
    return json({ error: "credentials_not_found", detail: credErr?.message }, 404);
  }

  const creds: TiktokCredentials = {
    merchant_id: String(credRow.merchant_id),
    shop_id: shopId,
    access_token: String(credRow.access_token),
    shop_cipher: String(credRow.shop_cipher ?? ""),
    app_key: String(credRow.app_key ?? ""),
    app_secret: String(credRow.app_secret ?? ""),
  };

  const lookupIds = (body.order_sns ?? []).map((s) => s.trim()).filter(Boolean);
  if (lookupIds.length > 0) {
    try {
      const details = await getTiktokOrderDetails(creds, lookupIds);
      const orders = details.map((raw) => {
        const createTime = Number(raw.create_time ?? 0);
        const updateTime = Number(raw.update_time ?? 0);
        return {
          order_sn: String(raw.id ?? ""),
          status: String(raw.status ?? "UNKNOWN"),
          create_time_unix: createTime || null,
          update_time_unix: updateTime || null,
          create_time_utc: createTime ? new Date(createTime * 1000).toISOString() : null,
          update_time_utc: updateTime ? new Date(updateTime * 1000).toISOString() : null,
        };
      });
      const found = new Set(orders.map((o) => o.order_sn));
      const missing = lookupIds.filter((id) => !found.has(id));

      const saved: unknown[] = [];
      const saveErrors: unknown[] = [];
      if (!dryRun) {
        for (const raw of details) {
          try {
            const normalized = normalizeTiktokOrder(raw, creds);
            const { data: result, error } = await supabase.rpc("upsert_marketplace_order", {
              p_order: normalized,
            });
            if (error) saveErrors.push({ order_sn: normalized.order_sn, error: error.message });
            else saved.push(result);
          } catch (e) {
            saveErrors.push({ order_id: raw.id, error: e instanceof Error ? e.message : String(e) });
          }
        }
      }

      return json({
        success: saveErrors.length === 0,
        mode: "lookup",
        dry_run: dryRun,
        shop_id: shopId,
        orders,
        missing_order_sns: missing,
        orders_saved: saved.length,
        save_errors: saveErrors.slice(0, 20),
        duration_ms: Date.now() - started,
      });
    } catch (err) {
      return json({
        success: false,
        mode: "lookup",
        error: err instanceof Error ? err.message : String(err),
        duration_ms: Date.now() - started,
      }, 502);
    }
  }

  const allSummaries: { id: string; status: string }[] = [];
  const seenIds = new Set<string>();
  let pageToken: string | undefined;
  let pages = 0;
  let searchCode = 0;
  let savedCount = 0;
  const saveErrors: unknown[] = [];

  async function saveOrderIds(ids: string[]): Promise<void> {
    if (dryRun || ids.length === 0) return;
    for (let i = 0; i < ids.length; i += API_BATCH) {
      const chunk = ids.slice(i, i + API_BATCH);
      const details = await getTiktokOrderDetails(creds, chunk);
      for (const raw of details) {
        try {
          const normalized = normalizeTiktokOrder(raw, creds);
          const { error } = await supabase.rpc("upsert_marketplace_order", {
            p_order: normalized,
          });
          if (error) saveErrors.push({ order_sn: normalized.order_sn, error: error.message });
          else savedCount++;
        } catch (e) {
          saveErrors.push({ order_id: raw.id, error: e instanceof Error ? e.message : String(e) });
        }
      }
      await new Promise((r) => setTimeout(r, 400));
    }
  }

  try {
    for (pages = 0; pages < maxPages; pages++) {
      const page = await searchTiktokOrders(creds, {
        create_time_ge: createTimeGe,
        create_time_lt: createTimeLt,
        page_size: 50,
        page_token: pageToken,
      });

      searchCode = page.code;

      if (page.code !== 0) {
        return json({
          success: false,
          phase: "search",
          shop_id: shopId,
          tiktok_code: page.code,
          tiktok_message: page.message,
          pages_completed: pages,
          orders_saved: savedCount,
          duration_ms: Date.now() - started,
        }, 502);
      }

      const pageIds: string[] = [];
      for (const o of page.orders) {
        if (skipUnpaid && o.status === "UNPAID") continue;
        if (!o.id || seenIds.has(o.id)) continue;
        seenIds.add(o.id);
        allSummaries.push({ id: o.id, status: o.status });
        pageIds.push(o.id);
      }

      if (!dryRun && pageIds.length > 0) {
        await saveOrderIds(pageIds);
      }

      pageToken = page.next_page_token;
      if (!pageToken || page.orders.length === 0) break;
      await new Promise((r) => setTimeout(r, 400));
    }
  } catch (err) {
    return json({
      success: false,
      phase: dryRun ? "search" : "search_or_save",
      shop_id: shopId,
      error: err instanceof Error ? err.message : String(err),
      pages_completed: pages,
      orders_found: seenIds.size,
      orders_saved: savedCount,
      duration_ms: Date.now() - started,
    }, 502);
  }

  const uniqueIds = [...seenIds];

  if (dryRun) {
    return json({
      success: true,
      dry_run: true,
      shop_id: shopId,
      merchant_id: creds.merchant_id,
      window: { create_time_ge: createTimeGe, create_time_lt: createTimeLt },
      pages_searched: pages + 1,
      orders_found: uniqueIds.length,
      sample_order_ids: uniqueIds.slice(0, 20),
      sample_statuses: allSummaries.slice(0, 20),
      tiktok_code: searchCode,
      duration_ms: Date.now() - started,
    });
  }

  return json({
    success: saveErrors.length === 0,
    dry_run: false,
    shop_id: shopId,
    merchant_id: creds.merchant_id,
    window: { create_time_ge: createTimeGe, create_time_lt: createTimeLt },
    pages_searched: pages + 1,
    orders_found: uniqueIds.length,
    orders_saved: savedCount,
    save_errors: saveErrors.slice(0, 50),
    duration_ms: Date.now() - started,
  });
});
