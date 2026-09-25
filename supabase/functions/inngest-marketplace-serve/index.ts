import { Inngest } from "inngest";
import { serve } from "inngest/edge";
import { createClient } from "@supabase/supabase-js";
import { ShopeeAdapter } from "./adapters/shopee-adapter.ts";
import { TikTokAdapter } from "./adapters/tiktok-adapter.ts";
import { LazadaAdapter } from "./adapters/lazada-adapter.ts";
import type { PlatformCredentials } from "./adapters/types.ts";
import { preferAdvancedStatus } from "./lib/status-rank.ts";

const inngest = new Inngest({ id: "marketplace-serve" });

const supabase = createClient(
  Deno.env.get("SUPABASE_URL")!,
  Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
);

const adapters = {
  shopee: new ShopeeAdapter(),
  tiktok: new TikTokAdapter(),
  lazada: new LazadaAdapter(),
};

const processShopOrders = inngest.createFunction(
  {
    id: "process-shop-orders",
    batchEvents: {
      maxSize: 50,
      timeout: "2m",
      key: "event.data.shop_id",
    },
    // Excess runs FIFO-queue (rateLimit dropped them). Throttle is per RUN start;
    // one batched run can still hold up to 50 events. timeouts.start is not on
    // inngest@3.22.0 — do not bump the SDK on this live ingest path.
    throttle: {
      limit: 30,
      period: "1m",
      key: "event.data.shop_id",
    },
    concurrency: {
      limit: 10,
      key: "event.data.shop_id",
    },
    retries: 3,
  },
  { event: "marketplace/order-received" },
  async ({ events, step }) => {
    const platform = events[0].data.platform || "shopee";
    const shopId = events[0].data.shop_id;

    const adapter = adapters[platform as keyof typeof adapters];
    if (!adapter) {
      throw new Error(`No adapter found for platform: ${platform}`);
    }

    const newOrderStatuses = adapter.getNewOrderStatuses();
    const newOrderEvents = events.filter((e) => newOrderStatuses.includes(e.data.order_status));
    const statusUpdateEvents = events.filter((e) => !newOrderStatuses.includes(e.data.order_status));

    const statusUpdateResults = await step.run("update-existing-orders", async () => {
      if (statusUpdateEvents.length === 0) {
        return { updated: [] as unknown[], notFound: [] as Array<{ order_sn: string; order_status: string }> };
      }

      const updated: unknown[] = [];
      const notFound: Array<{ order_sn: string; order_status: string }> = [];

      for (const event of statusUpdateEvents) {
        const { order_sn, order_status } = event.data;
        const { data, error } = await supabase.rpc("update_marketplace_order_status", {
          p_order_sn: order_sn,
          p_platform: platform,
          p_order_status: order_status,
          p_update_time: new Date().toISOString(),
        });

        if (error) {
          notFound.push({ order_sn, order_status, error: error.message } as { order_sn: string; order_status: string });
        } else if ((data as { action?: string })?.action === "not_found") {
          notFound.push({ order_sn, order_status });
        } else {
          updated.push(data);
        }
      }

      return { updated, notFound };
    });

    const ordersNeedingApiCall = [
      ...newOrderEvents.map((e) => e.data),
      ...statusUpdateResults.notFound,
    ];

    if (ordersNeedingApiCall.length === 0) {
      return {
        success: true,
        shop_id: shopId,
        platform,
        status_updates: statusUpdateResults.updated.length,
        new_orders: 0,
        api_calls_saved: statusUpdateEvents.length,
        timestamp: new Date().toISOString(),
      };
    }

    const credentials = await step.run("get-credentials", async () => {
      const { data, error } = await supabase.rpc("get_shop_credentials", {
        p_shop_id: shopId,
        p_platform: platform,
      });
      if (error) throw new Error(`Failed to get credentials: ${error.message}`);
      return data as PlatformCredentials;
    });

    const orderSns = ordersNeedingApiCall.map((o) => o.order_sn);

    const apiResult = await step.run("call-platform-api", async () => {
      try {
        if (platform === "shopee") {
          return await (adapter as ShopeeAdapter).fetchOrders(credentials, orderSns);
        }

        if (platform === "lazada") {
          return await (adapter as LazadaAdapter).fetchOrders(credentials, orderSns);
        }

        if (platform === "tiktok") {
          return await (adapter as TikTokAdapter).fetchOrders(credentials, orderSns);
        }

        const request = await adapter.buildGetOrderDetailsRequest(credentials, orderSns);
        const response = await fetch(request.url, request.options);

        if (!response.ok) {
          const errorText = await response.text();
          return {
            success: false,
            orders: [] as unknown[],
            error: `HTTP ${response.status}: ${errorText}`,
            skipped_order_sns: orderSns,
          };
        }

        const data = await response.json();
        if (data.code === 98001004) {
          console.warn(
            `[call-platform-api] TikTok returned invalid order IDs error. Orders may not exist: ${orderSns.join(", ")}`,
          );
          return {
            success: false,
            orders: [] as unknown[],
            error: `Orders not found in TikTok: ${data.message}`,
            skipped_order_sns: orderSns,
          };
        }

        const orders = adapter.parseOrdersResponse(data);
        return { success: true, orders, error: null, skipped_order_sns: [] as string[] };
      } catch (err: unknown) {
        const message = err instanceof Error ? err.message : String(err);
        console.error(`[call-platform-api] Error:`, message);
        return {
          success: false,
          orders: [] as unknown[],
          error: message,
          skipped_order_sns: orderSns,
        };
      }
    });

    const saveResults = await step.run("save-orders", async () => {
      if (!apiResult.success || !apiResult.orders || apiResult.orders.length === 0) {
        return {
          saved: [] as unknown[],
          errors: apiResult.error ? [{ message: apiResult.error, skipped: apiResult.skipped_order_sns }] : [],
        };
      }

      const saved: unknown[] = [];
      const errors: unknown[] = [];
      const hookBySn = new Map(
        ordersNeedingApiCall.map((o) => [String(o.order_sn), String(o.order_status ?? "")]),
      );

      for (const platformOrder of apiResult.orders) {
        try {
          const normalized = adapter.normalizeOrder(platformOrder, credentials);
          const hookStatus = hookBySn.get(String(normalized.order_sn));
          if (hookStatus) {
            normalized.order_status = preferAdvancedStatus(
              platform,
              normalized.order_status,
              hookStatus,
            );
          }

          const { data: result, error } = await supabase.rpc("upsert_marketplace_order", {
            p_order: normalized,
          });

          if (error) {
            errors.push({ order_sn: normalized.order_sn, error: error.message });
          } else {
            saved.push(result);
          }
        } catch (err: unknown) {
          const rec = platformOrder as { id?: string; order_id?: string };
          errors.push({
            order_id: rec?.id || rec?.order_id,
            exception: err instanceof Error ? err.message : String(err),
          });
        }
      }

      return { saved, errors };
    });

    return {
      success: true,
      shop_id: shopId,
      platform,
      status_updates: statusUpdateResults.updated.length,
      new_orders_processed: apiResult.orders?.length || 0,
      new_orders_saved: saveResults.saved?.length || 0,
      api_calls_saved: statusUpdateResults.updated.length,
      api_error: apiResult.error,
      skipped_orders: apiResult.skipped_order_sns,
      save_errors: saveResults.errors,
      timestamp: new Date().toISOString(),
    };
  },
);

const handler = serve({
  client: inngest,
  functions: [processShopOrders],
  signingKey: Deno.env.get("INNGEST_SIGNING_KEY"),
  servePath: "/functions/v1/inngest-marketplace-serve",
});

Deno.serve(async (req: Request) => {
  return await handler(req);
});
