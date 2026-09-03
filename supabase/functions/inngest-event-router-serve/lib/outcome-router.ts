/**
 * Outcome attribution routers — ported from OutcomeAttributionConsumer
 * (crm-event-processors, chokepoint path).
 *
 * Attributes outcome events (purchase completed, points earned/redeemed) to recent agent
 * actions by writing rows to `amp_outcome_attribution`. The hourly pg_cron job
 * (fn_aggregate_agent_performance) aggregates into amp_agent_performance_summary.
 *
 * Parity:
 * - Purchase: only status='completed' -> eventType purchase_completed, value final_amount||total_amount.
 * - Wallet: earn -> points_earned, redeem -> points_redeemed, value amount.
 * - Legacy Redis dedup oattr:<eventType>:<sourceId> TTL 600 replaced by function idempotency
 *   (purchase key includes status so non-completed events can't block the completed one).
 * - amp_workflow_log-sourced outcomes (email_clicked/opened, unsubscribed) were CDC-only —
 *   dead since 2026-06-04, no chokepoint topic; not ported here.
 */

import { inngest } from "./inngest-client.ts";
import { getSupabase } from "./supabase.ts";
import type { ChokepointEvent } from "./types.ts";

interface OutcomeEvent {
  eventType: string;
  sourceTable: string;
  value: number | null;
}

interface AgentAction {
  id: string;
  user_id: string;
  merchant_id: string;
  action_type: string;
  created_at: string;
  event_data: Record<string, unknown> | string;
}

interface AgentOutcome {
  id: string;
  agent_id: string;
  event_type: string;
  event_filter: Record<string, unknown> | null;
  classification: string;
  weight_column: string | null;
  attribution_window_hours: number;
  counting_method: string;
}

async function processAttribution(
  userId: string,
  outcome: OutcomeEvent,
  after: Record<string, unknown>,
): Promise<{ attributed: number }> {
  const supabase = getSupabase();

  const { data: agentActions } = await supabase
    .from("amp_workflow_log")
    .select("id,user_id,merchant_id,action_type,created_at,event_data")
    .eq("user_id", userId)
    .eq("event_type", "agent_decided_act")
    .gte("created_at", new Date(Date.now() - 30 * 24 * 3600000).toISOString())
    .order("created_at", { ascending: false })
    .limit(20);

  if (!agentActions || agentActions.length === 0) return { attributed: 0 };

  const agentIds = [
    ...new Set(
      (agentActions as AgentAction[])
        .map((a) => {
          const ed = typeof a.event_data === "string" ? JSON.parse(a.event_data) : a.event_data || {};
          return ed.agent_id as string;
        })
        .filter(Boolean),
    ),
  ];

  if (agentIds.length === 0) return { attributed: 0 };

  const { data: outcomes } = await supabase
    .from("amp_agent_outcome")
    .select(
      "id,agent_id,event_type,event_filter,classification,weight_column,attribution_window_hours,counting_method",
    )
    .in("agent_id", agentIds)
    .eq("event_type", outcome.eventType);

  if (!outcomes || outcomes.length === 0) return { attributed: 0 };

  const outcomeAt = after.created_at ? new Date(after.created_at as string) : new Date();

  const attributionRows: Record<string, unknown>[] = [];

  for (const agentOutcome of outcomes as AgentOutcome[]) {
    const matchingActions = (agentActions as AgentAction[]).filter((a) => {
      const ed = typeof a.event_data === "string" ? JSON.parse(a.event_data) : a.event_data || {};
      if (ed.agent_id !== agentOutcome.agent_id) return false;

      const actionAt = new Date(a.created_at);
      const hoursElapsed = (outcomeAt.getTime() - actionAt.getTime()) / 3600000;
      return hoursElapsed >= 0 && hoursElapsed <= agentOutcome.attribution_window_hours;
    });

    for (const action of matchingActions) {
      const actionAt = new Date(action.created_at);
      const hoursToOutcome = (outcomeAt.getTime() - actionAt.getTime()) / 3600000;

      let outcomeValue = outcome.value;
      if (agentOutcome.weight_column && after[agentOutcome.weight_column] !== undefined) {
        outcomeValue = Number(after[agentOutcome.weight_column]);
      }

      if (
        agentOutcome.counting_method === "binary" &&
        attributionRows.some(
          (r) =>
            r.agent_outcome_id === agentOutcome.id &&
            r.user_id === userId &&
            r.action_log_id === action.id,
        )
      ) {
        continue;
      }

      attributionRows.push({
        merchant_id: action.merchant_id,
        agent_id: agentOutcome.agent_id,
        agent_outcome_id: agentOutcome.id,
        user_id: userId,
        action_log_id: action.id,
        action_type: action.action_type,
        action_at: action.created_at,
        outcome_event_type: outcome.eventType,
        outcome_source_table: outcome.sourceTable,
        outcome_source_id: after.id as string,
        outcome_at: outcomeAt.toISOString(),
        outcome_value: outcomeValue,
        attribution_window_hours: agentOutcome.attribution_window_hours,
        hours_to_outcome: Math.round(hoursToOutcome * 100) / 100,
        classification: agentOutcome.classification,
      });
    }
  }

  if (attributionRows.length > 0) {
    const { error } = await supabase.from("amp_outcome_attribution").insert(attributionRows);
    if (error) {
      throw new Error(`amp_outcome_attribution insert failed: ${error.message}`);
    }
  }

  return { attributed: attributionRows.length };
}

export const outcomePurchaseRouter = inngest.createFunction(
  {
    id: "outcome-purchase-router",
    retries: 3,
    concurrency: [{ limit: 3 }],
    // Legacy Redis key oattr:purchase_completed:<purchase_id> TTL 600. Status included so a
    // 'created' event cannot idempotency-block the later 'completed'.
    idempotency: 'event.data.purchase_id + ":" + event.data.status',
  },
  { event: "crm/purchase.event" },
  async ({ event, step }) => {
    const data = event.data as ChokepointEvent;
    if (!data.user_id || !data.purchase_id) return { routed: false, reason: "missing_required_fields" };
    if (data.status !== "completed") {
      return { routed: false, reason: "filter_not_met", status: data.status };
    }

    const result = (await step.run("attribute", () =>
      processAttribution(
        data.user_id!,
        {
          eventType: "purchase_completed",
          sourceTable: "purchase_ledger",
          value: Number(data.final_amount ?? data.total_amount ?? 0),
        },
        {
          id: data.purchase_id,
          user_id: data.user_id,
          merchant_id: data.merchant_id,
          final_amount: data.final_amount,
          total_amount: data.total_amount,
          status: data.status,
          created_at: data.occurred_at,
        },
      ),
    )) as { attributed: number };

    return { routed: true, ...result };
  },
);

export const outcomeWalletRouter = inngest.createFunction(
  {
    id: "outcome-wallet-router",
    retries: 3,
    concurrency: [{ limit: 3 }],
    // Legacy Redis key oattr:<points_earned|points_redeemed>:<wallet_ledger_id> TTL 600.
    idempotency: "event.data.wallet_ledger_id",
  },
  { event: "crm/wallet.event" },
  async ({ event, step }) => {
    const data = event.data as ChokepointEvent;
    if (!data.user_id || !data.wallet_ledger_id) return { routed: false, reason: "missing_required_fields" };

    let eventType: string;
    if (data.transaction_type === "earn") eventType = "points_earned";
    else if (data.transaction_type === "redeem") eventType = "points_redeemed";
    else return { routed: false, reason: "filter_not_met", transaction_type: data.transaction_type };

    const result = (await step.run("attribute", () =>
      processAttribution(
        data.user_id!,
        {
          eventType,
          sourceTable: "wallet_ledger",
          value: Number(data.amount ?? 0),
        },
        {
          id: data.wallet_ledger_id,
          user_id: data.user_id,
          merchant_id: data.merchant_id,
          amount: data.amount,
          transaction_type: data.transaction_type,
          created_at: data.occurred_at,
        },
      ),
    )) as { attributed: number };

    return { routed: true, eventType, ...result };
  },
);
