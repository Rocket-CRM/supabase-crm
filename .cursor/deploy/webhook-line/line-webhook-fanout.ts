const PLACEHOLDER = "{messaging_channel_id}";
const MAX_DESTINATIONS = 10;

export type WebhookFanoutDestination = {
  url: string;
  enabled: boolean;
};

function hostOf(url: string): string {
  try {
    return new URL(url).host;
  } catch {
    return "invalid";
  }
}

function isHttpsUrl(url: string): boolean {
  try {
    return new URL(url).protocol === "https:";
  } catch {
    return false;
  }
}

function resolveFanoutUrl(url: string, messagingChannelId: string): string {
  return url.split(PLACEHOLDER).join(messagingChannelId || "");
}

export function parseWebhookFanoutDestinations(raw: unknown): WebhookFanoutDestination[] {
  if (!Array.isArray(raw)) return [];
  const out: WebhookFanoutDestination[] = [];
  for (const item of raw) {
    if (!item || typeof item !== "object") continue;
    const url = typeof (item as { url?: unknown }).url === "string"
      ? (item as { url: string }).url.trim()
      : "";
    if (!url) continue;
    const enabled = (item as { enabled?: unknown }).enabled !== false;
    out.push({ url, enabled });
    if (out.length >= MAX_DESTINATIONS) break;
  }
  return out;
}

export async function fanOutLineWebhook(opts: {
  destinations: unknown;
  rawBody: string;
  signature: string;
  messagingChannelId: string;
}): Promise<void> {
  const dests = parseWebhookFanoutDestinations(opts.destinations).filter((d) => d.enabled);
  if (dests.length === 0) return;

  await Promise.allSettled(
    dests.map(async (dest) => {
      const url = resolveFanoutUrl(dest.url, opts.messagingChannelId);
      if (!isHttpsUrl(url)) {
        console.error(`line webhook fan-out skipped: invalid url host=${hostOf(url)}`);
        return;
      }
      try {
        const res = await fetch(url, {
          method: "POST",
          headers: {
            "Content-Type": "application/json",
            "x-line-signature": opts.signature,
          },
          body: opts.rawBody,
        });
        if (!res.ok) {
          console.error(`line webhook fan-out failed: host=${hostOf(url)} status=${res.status}`);
        }
      } catch (e: unknown) {
        const message = e instanceof Error ? e.message : String(e);
        console.error(`line webhook fan-out error: host=${hostOf(url)} ${message}`);
      }
    }),
  );
}

export function scheduleLineWebhookFanOut(task: Promise<unknown>): void {
  const runtime = (globalThis as { EdgeRuntime?: { waitUntil?: (p: Promise<unknown>) => void } })
    .EdgeRuntime;
  if (runtime && typeof runtime.waitUntil === "function") {
    runtime.waitUntil(task);
    return;
  }
  void task;
}
