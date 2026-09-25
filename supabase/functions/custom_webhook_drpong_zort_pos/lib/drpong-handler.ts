import { postCrmReceipt, buildCrmReceiptPayload } from "./drpong-crm-receipt.ts";
import {
  parseZortMethod,
  resolveDrpongRoute,
  type DrpongRoute,
} from "./drpong-routes.ts";
import { logCustomWebhookEvent, type CustomWebhookEventRow } from "./log-event.ts";

const FUNCTION_SLUG = "custom_webhook_drpong_zort_pos";

function json(data: unknown, status = 200): Response {
  return new Response(JSON.stringify(data), {
    status,
    headers: { "Content-Type": "application/json" },
  });
}

function sanitizeHeaders(headers: Record<string, string>): Record<string, string> {
  const copy = { ...headers };
  for (const key of ["authorization", "apikey", "x-api-key"]) {
    if (copy[key]) copy[key] = "[redacted]";
    const lower = key.toLowerCase();
    for (const headerKey of Object.keys(copy)) {
      if (headerKey.toLowerCase() === lower) {
        copy[headerKey] = "[redacted]";
      }
    }
  }
  return copy;
}

function baseLog(): CustomWebhookEventRow {
  return { function_slug: FUNCTION_SLUG, request_body: {}, auth_ok: true };
}

async function logFiltered(
  log: CustomWebhookEventRow,
  reason: string,
  started: number,
): Promise<Response> {
  log.filter_matched = false;
  log.filter_reason = reason;
  log.duration_ms = Date.now() - started;
  await logCustomWebhookEvent(log);
  return json({ accepted: false, reason }, 200);
}

export function createDrpongHandler() {
  return async (req: Request): Promise<Response> => {
    const started = Date.now();
    const log = baseLog();
    const query = new URL(req.url).search;
    const method = parseZortMethod(req);

    log.request_query = query || null;
    log.request_headers = sanitizeHeaders(Object.fromEntries(req.headers.entries()));

    if (req.method !== "POST") {
      return json({ error: "method_not_allowed" }, 405);
    }

    let parsed: unknown;
    try {
      parsed = await req.json();
    } catch {
      log.error_message = "invalid_json";
      log.duration_ms = Date.now() - started;
      await logCustomWebhookEvent(log);
      return json({ error: "invalid_json" }, 400);
    }

    if (typeof parsed !== "object" || parsed === null || Array.isArray(parsed)) {
      log.request_body = { _raw: parsed };
      return logFiltered(log, "filtered_body_shape", started);
    }

    const requestBody = parsed as Record<string, unknown>;
    log.request_body = requestBody;

    const route: DrpongRoute = resolveDrpongRoute(requestBody, method);
    if (route.action === "filter") {
      return logFiltered(log, route.reason, started);
    }

    log.filter_matched = true;
    log.filter_reason = route.action;

    if (route.action === "crm_pos") {
      log.destination_url = route.destinationUrl;
      log.destination_request_body = buildCrmReceiptPayload(requestBody) as unknown as Record<
        string,
        unknown
      >;

      try {
        const result = await postCrmReceipt(requestBody);
        log.destination_status = result.status;
        log.destination_response_body = result.body;
        log.destination_response_raw = JSON.stringify(result.body);
        log.duration_ms = Date.now() - started;
        await logCustomWebhookEvent(log);

        return json({
          accepted: true,
          route: route.action,
          crm_action: result.action,
          crm_code: result.body.code,
        });
      } catch (err) {
        log.error_message = err instanceof Error ? err.message : String(err);
        log.duration_ms = Date.now() - started;
        await logCustomWebhookEvent(log);
        return json({ error: "crm_failed", message: log.error_message }, 502);
      }
    }

    const destinationUrl = `${route.destinationUrl}${query}`;
    log.destination_url = destinationUrl;
    log.destination_request_body = requestBody;

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
      log.duration_ms = Date.now() - started;
      await logCustomWebhookEvent(log);

      return new Response(responseText, {
        status: destinationResponse.status,
        headers: {
          "Content-Type": destinationResponse.headers.get("Content-Type") ??
            "application/json",
        },
      });
    } catch (err) {
      log.error_message = err instanceof Error ? err.message : String(err);
      log.duration_ms = Date.now() - started;
      await logCustomWebhookEvent(log);
      return json({ error: "forward_failed", message: log.error_message }, 502);
    }
  };
}
