import { createClient } from "https://esm.sh/@supabase/supabase-js@2.46.0";
import { logCustomWebhookEvent } from "./lib/log-event.ts";
import { PIPEDREAM_BIGCOMMERCE_URL } from "./lib/drpong-routes.ts";

const DESTINATION_URL = PIPEDREAM_BIGCOMMERCE_URL;
const FUNCTION_SLUG = "custom_webhook_drpong_zort_replay";
const SOURCE_SLUG = "custom_webhook_drpong_zort_pos";
const DEFAULT_CHANNEL = "Web_Rocket bigcommerce";
const DEFAULT_SINCE = "2026-05-28T00:00:00Z";
const FETCH_CAP = 10000;

type ReplayRound = "waiting" | "success";

interface ReplayRequest {
  dry_run?: boolean;
  round?: ReplayRound;
  saleschannel?: string;
  since?: string;
  require_tracking?: boolean;
  limit?: number;
  offset?: number;
  order_ids?: string[];
}

interface EventRow {
  id: string;
  created_at: string;
  request_query: string | null;
  request_body: Record<string, unknown>;
}

function json(data: unknown, status = 200): Response {
  return new Response(JSON.stringify(data), {
    status,
    headers: { "Content-Type": "application/json" },
  });
}

function authorize(req: Request): boolean {
  const expected = Deno.env.get("CUSTOM_WEBHOOK_REPLAY_SECRET");
  if (!expected) return true;
  const header = req.headers.get("x-custom-webhook-replay-secret") ?? "";
  return header === expected;
}

function orderId(body: Record<string, unknown>): string {
  return String(body.id ?? "");
}

function isCorrectBigcommerceDestination(url: string | null | undefined): boolean {
  return typeof url === "string" && url.includes("eot6isanrrx84y3.m.pipedream.net");
}

async function loadAlreadySent(
  supabase: ReturnType<typeof createClient>,
  round: ReplayRound,
): Promise<Set<string>> {
  const status = round === "waiting" ? "Waiting" : "Success";
  const sent = new Set<string>();

  for (const slug of [SOURCE_SLUG, FUNCTION_SLUG]) {
    const { data } = await supabase
      .from("custom_integration_events")
      .select("request_body, destination_url")
      .eq("function_slug", slug)
      .eq("filter_matched", true)
      .filter("request_body->>status", "eq", status)
      .gte("destination_status", 200)
      .lte("destination_status", 299)
      .limit(FETCH_CAP);

    for (const row of data ?? []) {
      if (!isCorrectBigcommerceDestination(row.destination_url as string)) continue;
      const id = orderId(row.request_body as Record<string, unknown>);
      if (id) sent.add(id);
    }
  }

  return sent;
}

async function loadWaitingCandidates(
  supabase: ReturnType<typeof createClient>,
  saleschannel: string,
  since: string,
  requireTracking: boolean,
  orderIds: string[] | null,
): Promise<EventRow[]> {
  let query = supabase
    .from("custom_integration_events")
    .select("id, created_at, request_query, request_body")
    .eq("function_slug", SOURCE_SLUG)
    .eq("filter_matched", false)
    .gte("created_at", since)
    .filter("request_body->>status", "eq", "Waiting")
    .filter("request_body->>paymentstatus", "eq", "Paid")
    .filter("request_body->>saleschannel", "eq", saleschannel)
    .like("request_query", "%method=UPDATEORDER%")
    .order("created_at", { ascending: false })
    .limit(FETCH_CAP);

  if (requireTracking) {
    query = query.not("request_body->>trackingno", "eq", "");
  }

  const { data, error } = await query;
  if (error) throw new Error(error.message);

  return dedupeLatestPerOrder((data ?? []) as EventRow[], orderIds);
}

async function loadSuccessCandidates(
  supabase: ReturnType<typeof createClient>,
  saleschannel: string,
  since: string,
  orderIds: string[] | null,
): Promise<EventRow[]> {
  const { data, error } = await supabase
    .from("custom_integration_events")
    .select("id, created_at, request_query, request_body")
    .eq("function_slug", SOURCE_SLUG)
    .gte("created_at", since)
    .filter("request_body->>status", "eq", "Success")
    .filter("request_body->>paymentstatus", "eq", "Paid")
    .filter("request_body->>saleschannel", "eq", saleschannel)
    .like("request_query", "%method=UPDATEORDER%")
    .order("created_at", { ascending: false })
    .limit(FETCH_CAP);

  if (error) throw new Error(error.message);

  return dedupeLatestPerOrder((data ?? []) as EventRow[], orderIds);
}

function dedupeLatestPerOrder(
  rows: EventRow[],
  orderIds: string[] | null,
): EventRow[] {
  const seen = new Set<string>();
  const deduped: EventRow[] = [];

  for (const row of rows) {
    const oid = orderId(row.request_body);
    if (!oid) continue;
    if (orderIds && !orderIds.includes(oid)) continue;
    if (seen.has(oid)) continue;
    seen.add(oid);
    deduped.push(row);
  }

  deduped.sort((a, b) => a.created_at.localeCompare(b.created_at));
  return deduped;
}

Deno.serve(async (req) => {
  if (req.method !== "POST") {
    return json({ error: "method_not_allowed" }, 405);
  }

  if (!authorize(req)) {
    return json({ error: "unauthorized" }, 401);
  }

  const started = Date.now();
  let body: ReplayRequest;
  try {
    body = await req.json();
  } catch {
    return json({ error: "invalid_json" }, 400);
  }

  const round: ReplayRound = body.round === "success" ? "success" : "waiting";
  const dryRun = body.dry_run !== false;
  const saleschannel = body.saleschannel?.trim() || DEFAULT_CHANNEL;
  const since = body.since?.trim() || DEFAULT_SINCE;
  const requireTracking = round === "waiting" ? body.require_tracking !== false : false;
  const limit = Math.min(Math.max(body.limit ?? 500, 1), 2000);
  const offset = Math.max(body.offset ?? 0, 0);
  const orderIds = body.order_ids?.map(String).filter(Boolean) ?? null;
  const replayReason = round === "waiting" ? "replay_waiting" : "replay_success";

  const supabase = createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
  );

  try {
    const allCandidates = round === "waiting"
      ? await loadWaitingCandidates(
        supabase,
        saleschannel,
        since,
        requireTracking,
        orderIds,
      )
      : await loadSuccessCandidates(supabase, saleschannel, since, orderIds);

    const alreadySent = await loadAlreadySent(supabase, round);
    const pending = allCandidates.filter((row) => !alreadySent.has(orderId(row.request_body)));
    const candidates = pending.slice(offset, offset + limit);

    const results: Array<Record<string, unknown>> = [];
    let forwarded = 0;
    let failed = 0;

    for (const row of candidates) {
      const requestBody = row.request_body;
      const oid = orderId(requestBody);
      const query = row.request_query ?? "?method=UPDATEORDER";
      const destinationUrl = `${DESTINATION_URL}${query}`;

      if (dryRun) {
        results.push({
          source_event_id: row.id,
          order_id: oid,
          order_number: requestBody.number,
          uniquenumber: requestBody.uniquenumber,
          status: requestBody.status,
          created_at: row.created_at,
          destination_url: destinationUrl,
          action: "would_forward",
        });
        continue;
      }

      const itemStarted = Date.now();
      const log = {
        function_slug: FUNCTION_SLUG,
        request_query: query,
        request_body: {
          ...requestBody,
          _replay: {
            source_event_id: row.id,
            source_created_at: row.created_at,
            round,
          },
        },
        auth_ok: true,
        filter_matched: true,
        filter_reason: replayReason,
        event_kind: "replay" as const,
        destination_url: destinationUrl,
        destination_request_body: requestBody,
      };

      try {
        const destinationResponse = await fetch(destinationUrl, {
          method: "POST",
          headers: { "Content-Type": "application/json" },
          body: JSON.stringify(requestBody),
        });

        const responseText = await destinationResponse.text();
        let responseBody: unknown = responseText;
        try {
          responseBody = JSON.parse(responseText);
        } catch {
          // keep raw text
        }

        log.destination_status = destinationResponse.status;
        log.destination_response_raw = responseText;
        log.destination_response_body = responseBody;
        log.duration_ms = Date.now() - itemStarted;
        await logCustomWebhookEvent(log);

        const ok = destinationResponse.status >= 200 && destinationResponse.status < 300;
        if (ok) forwarded += 1;
        else failed += 1;

        results.push({
          source_event_id: row.id,
          order_id: oid,
          order_number: requestBody.number,
          status: requestBody.status,
          destination_url: destinationUrl,
          destination_status: destinationResponse.status,
          ok,
        });

        await new Promise((resolve) => setTimeout(resolve, 100));
      } catch (err) {
        failed += 1;
        log.error_message = err instanceof Error ? err.message : String(err);
        log.duration_ms = Date.now() - itemStarted;
        await logCustomWebhookEvent(log);

        results.push({
          source_event_id: row.id,
          order_id: oid,
          order_number: requestBody.number,
          error: log.error_message,
          ok: false,
        });
      }
    }

    return json({
      dry_run: dryRun,
      round,
      saleschannel,
      since,
      require_tracking: requireTracking,
      source_function: SOURCE_SLUG,
      destination_url: DESTINATION_URL,
      total_candidates: allCandidates.length,
      already_sent: allCandidates.length - pending.length,
      pending_count: pending.length,
      batch_count: candidates.length,
      forwarded,
      failed,
      limit,
      offset,
      has_more: offset + limit < pending.length,
      duration_ms: Date.now() - started,
      results,
    });
  } catch (err) {
    return json({
      error: "replay_failed",
      message: err instanceof Error ? err.message : String(err),
    }, 500);
  }
});
