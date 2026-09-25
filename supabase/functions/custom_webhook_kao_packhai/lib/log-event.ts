import { createClient } from "https://esm.sh/@supabase/supabase-js@2.46.0";

export interface CustomWebhookEventRow {
  function_slug: string;
  request_query?: string | null;
  request_headers?: Record<string, string> | null;
  request_body?: Record<string, unknown>;
  auth_ok?: boolean | null;
  filter_matched?: boolean | null;
  filter_reason?: string | null;
  destination_url?: string | null;
  destination_request_body?: Record<string, unknown> | null;
  destination_status?: number | null;
  destination_response_body?: unknown;
  destination_response_raw?: string | null;
  duration_ms?: number | null;
  error_message?: string | null;
  event_kind?: "forward" | "inbound" | "outbound" | "replay";
}

function getSupabase() {
  return createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
  );
}

export async function logCustomWebhookEvent(row: CustomWebhookEventRow): Promise<void> {
  // Filtered-out traffic is high-volume noise; skip DB writes to protect the pool.
  if (row.filter_matched === false) return;

  try {
    const supabase = getSupabase();
    const { error } = await supabase.from("custom_integration_events").insert({
      function_slug: row.function_slug,
      request_query: row.request_query ?? null,
      request_headers: row.request_headers ?? null,
      request_body: row.request_body ?? {},
      auth_ok: row.auth_ok ?? null,
      filter_matched: row.filter_matched ?? null,
      filter_reason: row.filter_reason ?? null,
      destination_url: row.destination_url ?? null,
      destination_request_body: row.destination_request_body ?? null,
      destination_status: row.destination_status ?? null,
      destination_response_body: typeof row.destination_response_body === "object" &&
          row.destination_response_body !== null
        ? row.destination_response_body
        : row.destination_response_body != null
        ? { value: row.destination_response_body }
        : null,
      destination_response_raw: row.destination_response_raw ?? null,
      duration_ms: row.duration_ms ?? null,
      error_message: row.error_message ?? null,
      event_kind: row.event_kind ?? "forward",
    });

    if (error) {
      console.error(`[${row.function_slug}] log insert failed:`, error.message);
    }
  } catch (err) {
    console.error(`[${row.function_slug}] log insert exception:`, err);
  }
}
