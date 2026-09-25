import { matchesFilter } from "./hookdeck-filter.ts";
import { logCustomWebhookEvent, type CustomWebhookEventRow } from "./log-event.ts";

export interface WebhookAuthConfig {
  headerName: string;
  expectedValue: string;
}

export interface WebhookTransformResult {
  body: Record<string, unknown>;
  headers: Record<string, string>;
}

export interface WebhookHandlerConfig {
  functionSlug: string;
  destinationUrl: string;
  filter?: Record<string, unknown> | null;
  auth?: WebhookAuthConfig | null;
  transform?: (
    body: Record<string, unknown>,
    req: Request,
  ) => WebhookTransformResult;
}

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

function validateApiKey(
  req: Request,
  headerName: string,
  expectedValue: string,
): boolean {
  const actual = req.headers.get(headerName) ?? req.headers.get(headerName.toLowerCase());
  return actual === expectedValue;
}

function baseLog(functionSlug: string): CustomWebhookEventRow {
  return { function_slug: functionSlug, request_body: {} };
}

export function createWebhookHandler(config: WebhookHandlerConfig) {
  return async (req: Request): Promise<Response> => {
    const started = Date.now();
    const log = baseLog(config.functionSlug);

    if (req.method !== "POST") {
      return json({ error: "method_not_allowed" }, 405);
    }

    const query = new URL(req.url).search;
    log.request_query = query || null;
    log.request_headers = sanitizeHeaders(Object.fromEntries(req.headers.entries()));

    if (config.auth) {
      log.auth_ok = validateApiKey(req, config.auth.headerName, config.auth.expectedValue);
      if (!log.auth_ok) {
        log.error_message = "unauthorized";
        log.duration_ms = Date.now() - started;
        await logCustomWebhookEvent(log);
        return json({ error: "unauthorized" }, 401);
      }
    } else {
      log.auth_ok = true;
    }

    let requestBody: Record<string, unknown>;
    try {
      requestBody = await req.json();
    } catch {
      log.error_message = "invalid_json";
      log.duration_ms = Date.now() - started;
      await logCustomWebhookEvent(log);
      return json({ error: "invalid_json" }, 400);
    }

    log.request_body = requestBody;

    if (config.filter && !matchesFilter(requestBody, config.filter)) {
      log.filter_matched = false;
      log.filter_reason = "filtered";
      log.duration_ms = Date.now() - started;
      await logCustomWebhookEvent(log);
      return json({ accepted: false, reason: "filtered" }, 200);
    }

    log.filter_matched = true;

    let outboundBody = requestBody;
    let outboundHeaders: Record<string, string> = {
      "Content-Type": "application/json",
    };

    if (config.transform) {
      const transformed = config.transform(requestBody, req);
      outboundBody = transformed.body;
      outboundHeaders = {
        "Content-Type": "application/json",
        ...transformed.headers,
      };
    }

    const destinationUrl = `${config.destinationUrl}${query}`;
    log.destination_url = destinationUrl;
    log.destination_request_body = outboundBody;

    try {
      const destinationResponse = await fetch(destinationUrl, {
        method: "POST",
        headers: outboundHeaders,
        body: JSON.stringify(outboundBody),
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
