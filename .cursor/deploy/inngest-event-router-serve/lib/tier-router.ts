/**
 * Tier routers — ported from TierConsumer (crm-event-processors, chokepoint path).
 *
 * For each qualifying event we make ONE Postgres call: `process_tier_event(user, merchant)`.
 * Postgres evaluates tier status atomically (immediate upgrade / pending upgrade row /
 * clear pending / refresh tier_progress).
 *
 * Parity:
 * - Purchase events: NO status filter (legacy deduped once per purchase_id per 24h,
 *   regardless of status). Idempotency = purchase_id, matching tierPurchaseDedupKey TTL 86400.
 * - Wallet events: only transaction_type='earn'. Idempotency = wallet_ledger_id
 *   (tierWalletDedupKey TTL 86400).
 * - Per-user ordering: Kafka partitioned crm.events.wallet by user_id. Inngest does not
 *   guarantee ordering, so we cap per-user concurrency at 1 (plan §7 Key rules).
 * - Poison safety: legacy resolved the offset even on failure (process_tier_event is
 *   idempotent; a missed event is picked up by the next earn/purchase or the daily cron).
 *   Retries here are finite (3) for the same reason.
 */

import { inngest } from "./inngest-client.ts";
import { getSupabase } from "./supabase.ts";
import type { ChokepointEvent } from "./types.ts";

interface TierEventResult {
  action?: string;
  tier_id?: string;
  effective_at?: string;
  [key: string]: unknown;
}

async function processTierEvent(userId: string, merchantId: string): Promise<TierEventResult> {
  const supabase = getSupabase();
  const { data, error } = await supabase.rpc("process_tier_event", {
    p_user_id: userId,
    p_merchant_id: merchantId,
  });
  if (error) {
    throw new Error(`process_tier_event failed ${error.code || ""}: ${error.message}`);
  }
  return (data || {}) as TierEventResult;
}

const TIER_CONCURRENCY = [
  { limit: 10 },
  { key: "event.data.user_id", limit: 1 }, // per-user ordering (tier eval is order-sensitive)
];

export const tierPurchaseRouter = inngest.createFunction(
  {
    id: "tier-purchase-router",
    retries: 3,
    concurrency: TIER_CONCURRENCY,
    // Legacy Redis key tier_dedup:purchase:<purchase_id> (TTL 86400) — no status in key:
    // one tier evaluation per purchase per 24h window, whichever status event arrives first.
    idempotency: "event.data.purchase_id",
  },
  { event: "crm/purchase.event" },
  async ({ event, step }) => {
    const data = event.data as ChokepointEvent;
    if (!data.user_id || !data.merchant_id || !data.purchase_id) {
      return { routed: false, reason: "missing_required_fields" };
    }
    const result = (await step.run("process-tier-event", () =>
      processTierEvent(data.user_id!, data.merchant_id!),
    )) as TierEventResult;
    return { routed: true, action: result.action, tier_id: result.tier_id, effective_at: result.effective_at };
  },
);

export const tierWalletRouter = inngest.createFunction(
  {
    id: "tier-wallet-router",
    retries: 3,
    concurrency: TIER_CONCURRENCY,
    // Legacy Redis key tier_dedup:wallet:<wallet_ledger_id> (TTL 86400)
    idempotency: "event.data.wallet_ledger_id",
  },
  { event: "crm/wallet.event" },
  async ({ event, step }) => {
    const data = event.data as ChokepointEvent;
    // Only 'earn' transactions can affect tier qualification (legacy filter).
    if (data.transaction_type !== "earn") {
      return { routed: false, reason: "filter_not_met", transaction_type: data.transaction_type };
    }
    if (!data.user_id || !data.merchant_id || !data.wallet_ledger_id) {
      return { routed: false, reason: "missing_required_fields" };
    }
    const result = (await step.run("process-tier-event", () =>
      processTierEvent(data.user_id!, data.merchant_id!),
    )) as TierEventResult;
    return { routed: true, action: result.action, tier_id: result.tier_id, effective_at: result.effective_at };
  },
);
