import { createClient } from "https://esm.sh/@supabase/supabase-js@2.46.0";
import { matchesFilter } from "./hookdeck-filter.ts";
import { verifyLazadaPushSignature } from "./lazada-signature.ts";
import { logCustomWebhookEvent, type CustomWebhookEventRow } from "./log-event.ts";

export type MarketplacePlatform = "tiktok" | "shopee" | "lazada";

export interface NormalizedOrderEvent {
  platform: MarketplacePlatform;
  shop_id: string;
  order_sn: string;
  order_status: string;
  timestamp: number;
}

const CORS_HEADERS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
  "Access-Control-Allow-Headers":
    "Content-Type, Authorization, x-tts-signature, x-shopify-hmac-sha256",
};

function json(data: unknown, status = 200): Response {
  return new Response(JSON.stringify(data), {
    status,
    headers: { "Content-Type": "application/json", ...CORS_HEADERS },
  });
}

function sanitizeHeaders(headers: Record<string, string>): Record<string, string> {
  const copy = { ...headers };
  for (const key of Object.keys(copy)) {
    if (key.toLowerCase() === "authorization") {
      copy[key] = "[redacted]";
    }
  }
  return copy;
}

/** Hookdeck-equivalent JSON filters per platform */
export function hookdeckFilterFor(platform: MarketplacePlatform): unknown {
  if (platform === "tiktok") {
    return { $not: { data: { order_status: "UNPAID" } } };
  }
  if (platform === "shopee") {
    return { $not: { data: { status: "UNPAID" } } };
  }
  return null;
}

export function normalizeOrderEvent(
  platform: MarketplacePlatform,
  body: Record<string, unknown>,
): NormalizedOrderEvent | null {
  if (platform === "tiktok") {
    const shopId = body.shop_id;
    const data = body.data as Record<string, unknown> | undefined;
    const orderId = data?.order_id;
    const orderStatus = data?.order_status;
    if (!shopId || orderId == null || orderId === "") return null;
    return {
      platform: "tiktok",
      shop_id: String(shopId),
      order_sn: String(orderId),
      order_status: String(orderStatus ?? "UNKNOWN"),
      timestamp: Date.now(),
    };
  }

  if (platform === "shopee") {
    const shopId = body.shop_id;
    const data = body.data as Record<string, unknown> | undefined;
    const orderSn = data?.ordersn;
    const orderStatus = data?.status;
    if (!shopId || orderSn == null || orderSn === "") return null;
    return {
      platform: "shopee",
      shop_id: String(shopId),
      order_sn: String(orderSn),
      order_status: String(orderStatus ?? "UNKNOWN"),
      timestamp: Date.now(),
    };
  }

  // Lazada sample:
  // seller_id, data.trade_order_id, data.order_status, timestamp (seconds)
  const sellerId = body.seller_id;
  const data = body.data as Record<string, unknown> | undefined;
  const tradeOrderId = data?.trade_order_id ?? data?.reverse_order_id;
  const orderStatus = data?.order_status;
  if (sellerId == null || sellerId === "" || tradeOrderId == null || tradeOrderId === "") {
    return null;
  }
  const tsSec = typeof body.timestamp === "number" ? body.timestamp : null;
  return {
    platform: "lazada",
    shop_id: String(sellerId),
    order_sn: String(tradeOrderId),
    order_status: String(orderStatus ?? "unknown").toLowerCase(),
    timestamp: tsSec != null ? tsSec * 1000 : Date.now(),
  };
}

function verifyAuth(platform: MarketplacePlatform, req: Request): boolean {
  if (platform === "lazada") {
    return true;
  }
  const shared = Deno.env.get("MARKETPLACE_WEBHOOK_SHARED_SECRET");
  if (!shared) return true;
  const auth = req.headers.get("authorization") ?? req.headers.get("x-webhook-secret") ?? "";
  return auth === shared || auth === `Bearer ${shared}`;
}

function kafkaRecordsUrl(): string {
  return (
    Deno.env.get("KAFKA_REST_RECORDS_URL") ??
    "https://pkc-ox31np.ap-southeast-7.aws.confluent.cloud/kafka/v3/clusters/lkc-6r72k2/topics/marketplace.orders/records"
  );
}

async function publishKafka(event: NormalizedOrderEvent): Promise<{ status: number; body: string }> {
  const apiKey = Deno.env.get("KAFKA_API_KEY");
  const apiSecret = Deno.env.get("KAFKA_API_SECRET");
  if (!apiKey || !apiSecret) {
    throw new Error("KAFKA_API_KEY or KAFKA_API_SECRET not configured");
  }

  // Confluent Kafka REST API v3: one record per POST (not v2 "records" array).
  const kafkaBody = {
    key: { type: "STRING", data: `shop-${event.shop_id}` },
    value: {
      type: "JSON",
      data: {
        platform: event.platform,
        shop_id: event.shop_id,
        order_sn: event.order_sn,
        order_status: event.order_status,
        timestamp: event.timestamp,
      },
    },
  };

  const credentials = btoa(`${apiKey}:${apiSecret}`);
  const response = await fetch(kafkaRecordsUrl(), {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      Authorization: `Basic ${credentials}`,
    },
    body: JSON.stringify(kafkaBody),
  });

  const text = await response.text();
  let status = response.status;
  try {
    const parsed = JSON.parse(text) as { error_code?: number };
    if (typeof parsed.error_code === "number" && parsed.error_code !== 200) {
      status = parsed.error_code >= 400 ? parsed.error_code : 502;
    }
  } catch {
    // non-JSON body (e.g. HTML 401 page)
  }
  return { status, body: text };
}

async function publishInngest(event: NormalizedOrderEvent): Promise<{ status: number; body: string }> {
  const eventKey = Deno.env.get("INNGEST_EVENT_KEY");
  if (!eventKey) {
    throw new Error("INNGEST_EVENT_KEY not configured");
  }

  const response = await fetch(`https://inn.gs/e/${eventKey}`, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({
      name: "marketplace/order-received",
      data: {
        shop_id: event.shop_id,
        order_sn: event.order_sn,
        order_status: event.order_status,
        platform: event.platform,
      },
    }),
  });

  const text = await response.text();
  return { status: response.status, body: text };
}

/** Write webhook status onto an existing ledger row. New orders stay not_found for Inngest upsert. */
async function applyLedgerStatus(event: NormalizedOrderEvent): Promise<void> {
  try {
    const supabase = createClient(
      Deno.env.get("SUPABASE_URL")!,
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
    );
    const { error } = await supabase.rpc("update_marketplace_order_status", {
      p_order_sn: event.order_sn,
      p_platform: event.platform,
      p_order_status: event.order_status,
      p_update_time: new Date(event.timestamp).toISOString(),
    });
    if (error) {
      console.error("[marketplace-ingest] status apply failed", error.message);
    }
  } catch (err) {
    console.error("[marketplace-ingest] status apply exception", err);
  }
}

async function publishNormalized(event: NormalizedOrderEvent): Promise<{
  mode: string;
  status: number;
  body: string;
}> {
  const mode = (Deno.env.get("MARKETPLACE_INGEST_MODE") ?? "kafka").toLowerCase();

  if (mode === "inngest") {
    const r = await publishInngest(event);
    return { mode: "inngest", status: r.status, body: r.body };
  }

  if (mode === "both") {
    const kafka = await publishKafka(event);
    if (kafka.status < 200 || kafka.status >= 300) {
      const inngest = await publishInngest(event);
      return { mode: "both:kafka_failed_inngest", status: inngest.status, body: inngest.body };
    }
    return { mode: "both", status: kafka.status, body: kafka.body };
  }

  const kafka = await publishKafka(event);
  return { mode: "kafka", status: kafka.status, body: kafka.body };
}

export function createMarketplaceWebhookHandler(
  platform: MarketplacePlatform,
  functionSlug: string,
) {
  return async (req: Request): Promise<Response> => {
    const started = Date.now();
    const log: CustomWebhookEventRow = { function_slug: functionSlug, request_body: {} };

    if (req.method === "OPTIONS") {
      return new Response(null, { headers: CORS_HEADERS });
    }

    if (platform === "lazada" && req.method === "GET") {
      return json({ ok: true, service: "webhook-marketplace-lazada" });
    }

    if (req.method !== "POST") {
      return json({ error: "method_not_allowed" }, 405);
    }

    log.request_query = new URL(req.url).search || null;
    log.request_headers = sanitizeHeaders(Object.fromEntries(req.headers.entries()));

    let requestBody: Record<string, unknown>;
    let rawBody = "";

    if (platform === "lazada") {
      rawBody = await req.text();
      const sig = await verifyLazadaPushSignature(
        rawBody,
        req.headers.get("authorization"),
      );
      log.auth_ok = sig.ok;
      if (!sig.ok) {
        log.error_message = sig.reason ?? "unauthorized";
        log.duration_ms = Date.now() - started;
        await logCustomWebhookEvent(log);
        return json({ error: "unauthorized", reason: sig.reason }, 401);
      }
      try {
        requestBody = rawBody ? JSON.parse(rawBody) : {};
      } catch {
        log.error_message = "invalid_json";
        log.duration_ms = Date.now() - started;
        await logCustomWebhookEvent(log);
        return json({ error: "invalid_json" }, 400);
      }
    } else {
      log.auth_ok = verifyAuth(platform, req);
      if (!log.auth_ok) {
        log.error_message = "unauthorized";
        log.duration_ms = Date.now() - started;
        await logCustomWebhookEvent(log);
        return json({ error: "unauthorized" }, 401);
      }
      try {
        requestBody = await req.json();
      } catch {
        log.error_message = "invalid_json";
        log.duration_ms = Date.now() - started;
        await logCustomWebhookEvent(log);
        return json({ error: "invalid_json" }, 400);
      }
    }

    log.request_body = requestBody;

    const filter = hookdeckFilterFor(platform);
    if (filter && !matchesFilter(requestBody, filter)) {
      log.filter_matched = false;
      log.filter_reason = "hookdeck_filter";
      log.duration_ms = Date.now() - started;
      await logCustomWebhookEvent(log);
      return json({ accepted: false, reason: "filtered" }, 200);
    }

    log.filter_matched = true;

    const normalized = normalizeOrderEvent(platform, requestBody);
    if (!normalized) {
      log.error_message = "missing_required_fields";
      log.duration_ms = Date.now() - started;
      await logCustomWebhookEvent(log);
      return json({ accepted: false, reason: "missing shop_id or order_sn" }, 200);
    }

    log.destination_request_body = normalized as unknown as Record<string, unknown>;
    log.destination_url = kafkaRecordsUrl();

    try {
      const [, published] = await Promise.all([
        applyLedgerStatus(normalized),
        publishNormalized(normalized),
      ]);
      log.destination_status = published.status;
      log.destination_response_raw = published.body;
      try {
        log.destination_response_body = JSON.parse(published.body);
      } catch {
        log.destination_response_body = { raw: published.body };
      }

      const ok = published.status >= 200 && published.status < 300;
      log.duration_ms = Date.now() - started;
      await logCustomWebhookEvent(log);

      if (!ok) {
        const failBody = {
          accepted: false,
          reason: "publish_failed",
          mode: published.mode,
          status: published.status,
        };
        // Lazada requires HTTP 2xx within 500ms or Verify fails / message retries
        if (platform === "lazada") {
          return json(failBody, 200);
        }
        return json(failBody, 502);
      }

      return json({
        accepted: true,
        platform: normalized.platform,
        shop_id: normalized.shop_id,
        order_sn: normalized.order_sn,
        order_status: normalized.order_status,
        mode: published.mode,
      });
    } catch (err) {
      log.error_message = err instanceof Error ? err.message : String(err);
      log.duration_ms = Date.now() - started;
      await logCustomWebhookEvent(log);
      const failBody = { error: "publish_failed", message: log.error_message };
      if (platform === "lazada") {
        return json(failBody, 200);
      }
      return json(failBody, 502);
    }
  };
}
