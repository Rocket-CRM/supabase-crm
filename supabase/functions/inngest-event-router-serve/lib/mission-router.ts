/**
 * Mission routers — ported from MissionConsumer (crm-event-processors, chokepoint path).
 *
 * Flow: filter event -> check merchant has active missions for the condition type ->
 * emit one `mission/evaluate` per active mission (inngest-mission-serve does evaluation).
 *
 * Parity:
 * - Purchase: only status='completed' fires (legacy passesFilter). Condition type 'purchase'.
 * - Wallet: only transaction_type='earn'; condition type points_earned / tickets_earned by currency.
 * - The Redis mission cache (merchant -> condition type -> mission ids) is replaced by the
 *   same DB RPCs the cache was built from: fn_has_active_missions (cheap boolean gate) then
 *   fn_get_active_missions_by_condition_type filtered to this merchant.
 * - Legacy per-mission Redis dedup missionDedupKey(conditionType, sourceId, missionId) TTL 300s
 *   is replaced by function idempotency on the source event (one evaluation fan-out per source).
 *
 * NOT ported (were CDC-only, dead since CDC decommission 2026-06-04): form_submission and
 * referral condition types — no chokepoint topic exists for them yet.
 */

import { inngest } from "./inngest-client.ts";
import { getSupabase } from "./supabase.ts";
import type { ChokepointEvent } from "./types.ts";

interface MissionRouteParams {
  conditionType: string;
  /** Event type passed to fn_evaluate_mission_conditions. Defaults to conditionType. */
  eventType?: string;
  sourceId: string;
  userId: string;
  merchantId: string;
  eventData: Record<string, unknown>;
}

async function getActiveMissionIds(merchantId: string, conditionType: string): Promise<string[]> {
  const supabase = getSupabase();

  const { data: hasMissions, error: hasErr } = await supabase.rpc("fn_has_active_missions", {
    p_merchant_id: merchantId,
    p_condition_type: conditionType,
  });
  if (hasErr) throw new Error(`fn_has_active_missions failed: ${hasErr.message}`);
  if (!hasMissions) return [];

  const { data, error } = await supabase.rpc("fn_get_active_missions_by_condition_type");
  if (error) throw new Error(`fn_get_active_missions_by_condition_type failed: ${error.message}`);

  const row = ((data || []) as Array<{
    merchant_id: string;
    condition_type: string;
    mission_ids: string[];
  }>).find((r) => r.merchant_id === merchantId && r.condition_type === conditionType);

  return row?.mission_ids || [];
}

// deno-lint-ignore no-explicit-any
async function routeMissionEvaluations(step: any, p: MissionRouteParams) {
  const missionIds = (await step.run("get-active-missions", () =>
    getActiveMissionIds(p.merchantId, p.conditionType),
  )) as string[];

  if (!missionIds || missionIds.length === 0) {
    return { routed: false, reason: "no_active_missions", conditionType: p.conditionType };
  }

  await step.sendEvent(
    "send-mission-evaluate",
    missionIds.map((missionId) => ({
      name: "mission/evaluate",
      data: {
        user_id: p.userId,
        merchant_id: p.merchantId,
        mission_id: missionId,
        event_type: p.eventType ?? p.conditionType,
        event_data: p.eventData,
        trigger_id: p.sourceId,
      },
    })),
  );

  return { routed: true, missions: missionIds.length, conditionType: p.conditionType };
}

export const missionPurchaseRouter = inngest.createFunction(
  {
    id: "mission-purchase-router",
    retries: 3,
    concurrency: [{ limit: 5 }],
    // Status included so a 'created' event cannot idempotency-block the later 'completed'.
    idempotency: 'event.data.purchase_id + ":" + event.data.status',
  },
  { event: "crm/purchase.event" },
  async ({ event, step }) => {
    const data = event.data as ChokepointEvent;
    if (!data.user_id || !data.merchant_id || !data.purchase_id) {
      return { routed: false, reason: "missing_required_fields" };
    }
    // Legacy fires only on completed purchases; mirror exactly.
    if (data.status !== "completed") {
      return { routed: false, reason: "filter_not_met", status: data.status };
    }
    return await routeMissionEvaluations(step, {
      conditionType: "purchase",
      sourceId: data.purchase_id,
      userId: data.user_id,
      merchantId: data.merchant_id,
      eventData: {
        id: data.purchase_id,
        user_id: data.user_id,
        merchant_id: data.merchant_id,
        event: data.event,
        status: data.status,
        // Legacy MissionConsumer parity: evaluator reads 'amount' for measurement_type='sum'.
        amount: data.final_amount ?? data.total_amount,
        final_amount: data.final_amount,
        total_amount: data.total_amount,
        seller_id: data.seller_id ?? null,
        store_id: data.store_id ?? null,
        store_code: data.store_code ?? null,
      },
    });
  },
);

/**
 * Item-level purchase events feed missions whose purchase conditions are scoped by
 * sku_ids / product_ids / category_ids / brand_ids. The evaluator only matches those
 * scoped conditions on event_type='purchase_item' (header 'purchase' events skip them),
 * so header + item events never double-count the same condition.
 */
export const missionPurchaseItemRouter = inngest.createFunction(
  {
    id: "mission-purchase-item-router",
    retries: 3,
    concurrency: [{ limit: 5 }],
    idempotency: 'event.data.item_id + ":" + event.data.item_status',
  },
  { event: "crm/purchase_item.event" },
  async ({ event, step }) => {
    const data = event.data as ChokepointEvent;
    if (!data.user_id || !data.merchant_id || !data.item_id || !data.purchase_id) {
      return { routed: false, reason: "missing_required_fields" };
    }
    // Mission progress only counts completed items (mirrors header 'completed' filter).
    if (data.item_status !== "completed") {
      return { routed: false, reason: "filter_not_met", item_status: data.item_status };
    }
    return await routeMissionEvaluations(step, {
      conditionType: "purchase",
      eventType: "purchase_item",
      sourceId: data.item_id,
      userId: data.user_id,
      merchantId: data.merchant_id,
      eventData: {
        id: data.item_id,
        item_id: data.item_id,
        purchase_id: data.purchase_id,
        user_id: data.user_id,
        merchant_id: data.merchant_id,
        event: data.event,
        item_status: data.item_status,
        sku_id: data.sku_id ?? null,
        product_id: data.product_id ?? null,
        category_id: data.category_id ?? null,
        brand_id: data.brand_id ?? null,
        // Line amount drives measurement_type='sum' increments for scoped conditions.
        amount: data.amount,
        transaction_amount: data.transaction_amount ?? null,
        seller_id: data.seller_id ?? null,
      },
    });
  },
);

export const missionWalletRouter = inngest.createFunction(
  {
    id: "mission-wallet-router",
    retries: 3,
    concurrency: [{ limit: 5 }],
    idempotency: "event.data.wallet_ledger_id",
  },
  { event: "crm/wallet.event" },
  async ({ event, step }) => {
    const data = event.data as ChokepointEvent;
    if (!data.user_id || !data.merchant_id || !data.wallet_ledger_id) {
      return { routed: false, reason: "missing_required_fields" };
    }
    // Legacy fires only on earn transactions.
    if (data.transaction_type !== "earn") {
      return { routed: false, reason: "filter_not_met", transaction_type: data.transaction_type };
    }
    // S0.3: map only points/ticket; ignore store credit and other currencies.
    let conditionType: string;
    if (data.currency === "points") {
      conditionType = "points_earned";
    } else if (data.currency === "ticket" || data.currency === "tickets") {
      conditionType = "tickets_earned";
    } else {
      return { routed: false, reason: "unrelated_currency", currency: data.currency };
    }
    return await routeMissionEvaluations(step, {
      conditionType,
      sourceId: data.wallet_ledger_id,
      userId: data.user_id,
      merchantId: data.merchant_id,
      eventData: {
        id: data.wallet_ledger_id,
        user_id: data.user_id,
        merchant_id: data.merchant_id,
        currency: data.currency,
        amount: data.amount,
        transaction_type: data.transaction_type,
        target_entity_id: data.target_entity_id,
        source_type: data.source_type ?? null,
        source_id: data.source_id ?? null,
      },
    });
  },
);
