/**
 * AMP realtime routers — ported from AmpConsumer (crm-event-processors, chokepoint path).
 *
 * Flow: chokepoint event -> filter (legacy parity) -> POST amp-dispatch-realtime-event
 * (which matches workflow_trigger via fn_get_active_triggers_cached, 600s per-merchant
 * cache, and emits `amp/workflow.trigger` per matching workflow) -> inngest-amp-serve.
 *
 * Parity with AmpConsumer chokepoint handlers:
 * - purchase: fires only when status='completed'. Legacy Redis dedup
 *   amp:purchase_ledger:<purchase_id> (300s) ran AFTER the status filter, so a
 *   non-completed event never consumed the key. Idempotency therefore includes
 *   status so 'created'/'pending' cannot block the later 'completed'.
 * - purchase_item: fires when item_status='completed' (new trigger surface,
 *   no legacy CDC equivalent). Idempotency = item_id + item_status.
 * - wallet: fires only on transaction_type='earn'. Idempotency = wallet_ledger_id
 *   (one AMP dispatch per ledger row; a row's transaction_type never changes).
 * - tier_change: fires unless skip_cdc. Idempotency = tier_change_ledger_id.
 * - user: fires only on user_event_type='create' and !skip_cdc.
 *
 * Burst handling (signup imports can arrive 10K at once):
 * - amp-user-router uses batchEvents keyed by merchant (batching is incompatible
 *   with function idempotency, so dedup is done in-handler per batch; a user
 *   'create' event is emitted once per user by the chokepoint, and the
 *   inngest-amp-serve re-enrollment gate guards workflow-level duplicates).
 * - throttle (lossless, FIFO) caps batch starts per merchant per minute.
 * - per-merchant concurrency caps simultaneous dispatcher load.
 *
 * NOT ported (CDC-only, dead since 2026-06-04): form_submissions (form_completed
 * triggers) and amp_workflow_log add_to_audience (audience-add triggers) — no
 * chokepoint topic exists for them yet. See plan §6.
 */

import { inngest } from "./inngest-client.ts";
import { isTruthy } from "./types.ts";
import type { ChokepointEvent } from "./types.ts";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
const DISPATCH_URL = `${SUPABASE_URL}/functions/v1/amp-dispatch-realtime-event`;

interface AmpDispatchPayload {
  trigger_table: string;
  trigger_operation: "INSERT";
  merchant_id: string;
  user_id: string;
  record_id: string;
  record_data: Record<string, unknown>;
}

interface AmpDispatchResult {
  triggers_found: number;
  dispatched: string[];
}

async function dispatchToAmp(payload: AmpDispatchPayload): Promise<AmpDispatchResult> {
  const res = await fetch(DISPATCH_URL, {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      Authorization: `Bearer ${SERVICE_ROLE_KEY}`,
    },
    body: JSON.stringify(payload),
  });
  if (!res.ok) {
    throw new Error(`amp-dispatch-realtime-event failed: ${res.status} ${await res.text()}`);
  }
  const body = (await res.json()) as { triggers_found?: number; dispatched?: string[] };
  return { triggers_found: body.triggers_found ?? 0, dispatched: body.dispatched ?? [] };
}

// fn-scope total cap + per-merchant cap so one merchant's burst can't starve others.
const AMP_CONCURRENCY = [
  { limit: 10 },
  { key: "event.data.merchant_id", limit: 5 },
];

export const ampPurchaseRouter = inngest.createFunction(
  {
    id: "amp-purchase-router",
    retries: 3,
    concurrency: AMP_CONCURRENCY,
    idempotency: 'event.data.purchase_id + ":" + event.data.status',
  },
  { event: "crm/purchase.event" },
  async ({ event, step }) => {
    const data = event.data as ChokepointEvent;
    if (data.status !== "completed") {
      return { routed: false, reason: "filter_not_met", status: data.status };
    }
    if (!data.user_id || !data.merchant_id || !data.purchase_id) {
      return { routed: false, reason: "missing_required_fields" };
    }
    const result = (await step.run("dispatch-amp", () =>
      dispatchToAmp({
        trigger_table: "purchase_ledger",
        trigger_operation: "INSERT",
        merchant_id: data.merchant_id!,
        user_id: data.user_id!,
        record_id: data.purchase_id!,
        record_data: { status: data.status, event: data.event, source: data.source },
      }),
    )) as AmpDispatchResult;
    return { routed: true, ...result };
  },
);

export const ampPurchaseItemRouter = inngest.createFunction(
  {
    id: "amp-purchase-item-router",
    retries: 3,
    concurrency: AMP_CONCURRENCY,
    idempotency: 'event.data.item_id + ":" + event.data.item_status',
  },
  { event: "crm/purchase_item.event" },
  async ({ event, step }) => {
    const data = event.data as ChokepointEvent;
    if (data.item_status !== "completed") {
      return { routed: false, reason: "filter_not_met", item_status: data.item_status };
    }
    if (!data.user_id || !data.merchant_id || !data.item_id) {
      return { routed: false, reason: "missing_required_fields" };
    }
    const result = (await step.run("dispatch-amp", () =>
      dispatchToAmp({
        trigger_table: "purchase_items_ledger",
        trigger_operation: "INSERT",
        merchant_id: data.merchant_id!,
        user_id: data.user_id!,
        record_id: data.item_id!,
        record_data: {
          purchase_id: data.purchase_id,
          item_status: data.item_status,
          event: data.event,
          source: data.source,
        },
      }),
    )) as AmpDispatchResult;
    return { routed: true, ...result };
  },
);

export const ampWalletRouter = inngest.createFunction(
  {
    id: "amp-wallet-router",
    retries: 3,
    concurrency: AMP_CONCURRENCY,
    idempotency: "event.data.wallet_ledger_id",
  },
  { event: "crm/wallet.event" },
  async ({ event, step }) => {
    const data = event.data as ChokepointEvent;
    if (data.transaction_type !== "earn") {
      return { routed: false, reason: "filter_not_met", transaction_type: data.transaction_type };
    }
    if (!data.user_id || !data.merchant_id || !data.wallet_ledger_id) {
      return { routed: false, reason: "missing_required_fields" };
    }
    const result = (await step.run("dispatch-amp", () =>
      dispatchToAmp({
        trigger_table: "wallet_ledger",
        trigger_operation: "INSERT",
        merchant_id: data.merchant_id!,
        user_id: data.user_id!,
        record_id: data.wallet_ledger_id!,
        record_data: {
          amount: data.amount,
          currency: data.currency,
          transaction_type: data.transaction_type,
          source_type: data.source_type,
          description: data.description,
        },
      }),
    )) as AmpDispatchResult;
    return { routed: true, ...result };
  },
);

export const ampTierRouter = inngest.createFunction(
  {
    id: "amp-tier-router",
    retries: 3,
    concurrency: AMP_CONCURRENCY,
    idempotency: "event.data.tier_change_ledger_id",
  },
  { event: "crm/tier_change.event" },
  async ({ event, step }) => {
    const data = event.data as ChokepointEvent;
    if (isTruthy(data.skip_cdc)) {
      return { routed: false, reason: "filter_not_met", skip_cdc: true };
    }
    if (!data.user_id || !data.merchant_id || !data.tier_change_ledger_id) {
      return { routed: false, reason: "missing_required_fields" };
    }
    const result = (await step.run("dispatch-amp", () =>
      dispatchToAmp({
        trigger_table: "tier_change_ledger",
        trigger_operation: "INSERT",
        merchant_id: data.merchant_id!,
        user_id: data.user_id!,
        record_id: data.tier_change_ledger_id!,
        record_data: {
          id: data.tier_change_ledger_id,
          user_id: data.user_id,
          merchant_id: data.merchant_id,
          from_tier_id: data.from_tier_id,
          to_tier_id: data.to_tier_id,
          change_type: data.change_type,
          change_reason: data.change_reason,
          metadata: data.metadata,
          skip_cdc: data.skip_cdc,
          created_at: data.occurred_at,
        },
      }),
    )) as AmpDispatchResult;
    return { routed: true, ...result };
  },
);

/**
 * Signup router — the burst-shaped source (bulk imports can create 10K users at once).
 * Batched per merchant; batching is incompatible with function idempotency, so
 * in-batch dedup by user_id + downstream re-enrollment gate cover duplicates.
 * Throughput ceiling per merchant: 100 events/batch x 60 batches/min = 6K signups/min,
 * with at most 5 batches (and 10 parallel dispatcher calls each) in flight.
 */
export const ampUserRouter = inngest.createFunction(
  {
    id: "amp-user-router",
    retries: 3,
    batchEvents: { maxSize: 100, timeout: "5s", key: "event.data.merchant_id" },
    throttle: { limit: 60, period: "60s", key: "event.data.merchant_id" },
    concurrency: [{ key: "event.data.merchant_id", limit: 5 }],
  },
  { event: "crm/user.event" },
  async ({ events, step }) => {
    const seen = new Set<string>();
    const candidates: ChokepointEvent[] = [];
    for (const e of events) {
      const d = e.data as ChokepointEvent;
      if (d.user_event_type !== "create" || isTruthy(d.skip_cdc)) continue;
      if (!d.user_id || !d.merchant_id) continue;
      if (seen.has(d.user_id)) continue;
      seen.add(d.user_id);
      candidates.push(d);
    }

    if (candidates.length === 0) {
      return { routed: false, reason: "no_qualifying_events", batch_size: events.length };
    }

    const summary = (await step.run("dispatch-batch", async () => {
      let dispatched = 0;
      let failed = 0;
      let triggersFound = 0;
      const CHUNK = 10;
      for (let i = 0; i < candidates.length; i += CHUNK) {
        const chunk = candidates.slice(i, i + CHUNK);
        const results = await Promise.allSettled(
          chunk.map((d) => {
            const after = (d.user_after || {}) as Record<string, unknown>;
            return dispatchToAmp({
              trigger_table: "user_accounts",
              trigger_operation: "INSERT",
              merchant_id: d.merchant_id!,
              user_id: d.user_id!,
              record_id: d.user_id!,
              record_data: {
                id: d.user_id,
                merchant_id: d.merchant_id,
                mongo_id: after.mongo_id,
                skip_cdc: d.skip_cdc,
                role: after.role,
                user_type: after.user_type,
                is_active: after.is_active,
                deleted_at: after.deleted_at,
                created_at: d.occurred_at,
              },
            });
          }),
        );
        for (const r of results) {
          if (r.status === "fulfilled") {
            dispatched++;
            triggersFound += r.value.triggers_found;
          } else {
            // Poison safety (legacy parity): log and continue; a lost dispatch is
            // absorbed the same way legacy absorbed a failed offset — do not fail
            // the whole batch over one user.
            failed++;
            console.error("[amp-user-router] dispatch failed:", r.reason);
          }
        }
      }
      return { dispatched, failed, triggers_found: triggersFound };
    })) as { dispatched: number; failed: number; triggers_found: number };

    return {
      routed: true,
      batch_size: events.length,
      candidates: candidates.length,
      ...summary,
    };
  },
);
