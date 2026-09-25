const SEQUENCES: Record<string, string[]> = {
  lazada: ["unpaid", "pending", "confirmed", "packed", "ready_to_ship", "shipped", "delivered"],
  shopee: ["UNPAID", "READY_TO_SHIP", "PROCESSED", "SHIPPED", "TO_CONFIRM_RECEIVE", "COMPLETED"],
  tiktok: [
    "UNPAID",
    "ON_HOLD",
    "AWAITING_SHIPMENT",
    "AWAITING_COLLECTION",
    "IN_TRANSIT",
    "DELIVERED",
    "COMPLETED",
  ],
};

const TERMINAL = new Set([
  "canceled",
  "cancelled",
  "returned",
  "CANCELLED",
  "RETURNED",
  "TO_RETURN",
  "IN_CANCEL",
]);

/** Prefer the further-along marketplace status so API ingest cannot regress a webhook. */
export function preferAdvancedStatus(platform: string, current: string, incoming: string): string {
  if (!incoming) return current;
  if (!current) return incoming;
  if (TERMINAL.has(incoming)) return incoming;
  const seq = SEQUENCES[platform] ?? [];
  const left = platform === "lazada" ? current.toLowerCase() : current;
  const right = platform === "lazada" ? incoming.toLowerCase() : incoming;
  const ra = seq.indexOf(left);
  const rb = seq.indexOf(right);
  if (rb > ra) return platform === "lazada" ? right : incoming;
  if (ra >= 0 && rb < 0) return current;
  if (ra < 0 && rb >= 0) return platform === "lazada" ? right : incoming;
  return incoming;
}

export function resolveLazadaStatuses(order: {
  statuses?: unknown;
  status?: unknown;
  items?: Array<{ status?: unknown }>;
}): string {
  const candidates: string[] = [];
  if (Array.isArray(order.statuses)) {
    for (const s of order.statuses) candidates.push(String(s ?? "").toLowerCase());
  }
  if (order.status != null) candidates.push(String(order.status).toLowerCase());
  for (const item of order.items ?? []) {
    if (item?.status != null) candidates.push(String(item.status).toLowerCase());
  }
  if (candidates.length === 0) return "unknown";
  let best = candidates[0];
  for (const s of candidates) best = preferAdvancedStatus("lazada", best, s);
  return best;
}
