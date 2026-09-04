/**
 * LINE push client — ported from crm-event-processors/src/clients/line.ts.
 *
 * - 2xx           -> sent
 * - 429           -> rate_limited (terminal; no retry — the rate window will reopen)
 * - 4xx 'block'   -> user_blocked (caller flips channel_line=false via user chokepoint)
 * - other 4xx     -> failed (terminal; malformed request or bad merchant token)
 * - 5xx / network -> throws — the Inngest step retries; the resolver's ALREADY_SENT
 *                    backstop guards against double-send if the previous attempt landed.
 */

export type LinePushStatus = "sent" | "user_blocked" | "rate_limited" | "failed";

export interface LinePushResult {
  status: LinePushStatus;
  httpStatus: number;
  responseBody: Record<string, unknown> | string | null;
  error?: string;
}

const LINE_PUSH_URL = Deno.env.get("LINE_PUSH_URL") || "https://api.line.me/v2/bot/message/push";
const MESSAGING_SERVICE_URL = Deno.env.get("MESSAGING_SERVICE_URL") || "";
const MESSAGING_SERVICE_API_KEY = Deno.env.get("MESSAGING_SERVICE_API_KEY") || "";

function detectUserBlocked(httpStatus: number, body: string): boolean {
  if (httpStatus < 400 || httpStatus >= 500) return false;
  const lower = body.toLowerCase();
  return lower.includes("block") || lower.includes("not a friend");
}

export async function pushLineFlex(
  channelAccessToken: string,
  lineUserId: string,
  flex: Record<string, unknown>,
  altText: string,
): Promise<LinePushResult> {
  const useProxy = !!MESSAGING_SERVICE_URL;
  const url = useProxy ? MESSAGING_SERVICE_URL : LINE_PUSH_URL;

  const headers: Record<string, string> = {
    "Content-Type": "application/json",
    Authorization: `Bearer ${channelAccessToken}`,
  };
  if (useProxy && MESSAGING_SERVICE_API_KEY) {
    headers["x-messaging-api-key"] = MESSAGING_SERVICE_API_KEY;
  }

  const body = JSON.stringify({
    to: lineUserId,
    messages: [{ type: "flex", altText, contents: flex }],
  });

  let response: Response;
  try {
    response = await fetch(url, { method: "POST", headers, body });
  } catch (e) {
    throw new Error(`[LINE] push request failed: ${(e as Error).message}`);
  }

  const text = await response.text();
  let parsed: Record<string, unknown> | string | null = null;
  if (text) {
    try {
      parsed = JSON.parse(text);
    } catch {
      parsed = text;
    }
  }

  if (response.ok) {
    return { status: "sent", httpStatus: response.status, responseBody: parsed };
  }

  if (response.status >= 500) {
    throw new Error(`[LINE] push 5xx error status=${response.status} body=${text.slice(0, 200)}`);
  }

  if (response.status === 429) {
    return { status: "rate_limited", httpStatus: response.status, responseBody: parsed, error: text.slice(0, 200) };
  }

  if (detectUserBlocked(response.status, text)) {
    return { status: "user_blocked", httpStatus: response.status, responseBody: parsed, error: text.slice(0, 200) };
  }

  return { status: "failed", httpStatus: response.status, responseBody: parsed, error: text.slice(0, 200) };
}
