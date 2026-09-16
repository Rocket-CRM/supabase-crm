/**
 * Shopify redemption code delivery — consumes issue_requested from crm.events.redemption outbox.
 * Issues member codes under the parent DiscountCodeNode via shopify-issue-reward-code.
 * Confirmation is external_ref_id on reward_redemptions_ledger (fires issued via trigger).
 */

import { inngest } from "./inngest-client.ts";
import { getSupabase } from "./supabase.ts";
import type { ChokepointEvent } from "./types.ts";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SUPABASE_SERVICE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;

async function recordDeliveryFailure(
  supabase: ReturnType<typeof getSupabase>,
  redemptionId: string,
  errorMessage: string,
) {
  const { data: row } = await supabase
    .from("reward_redemptions_ledger")
    .select("shopify_code_delivery_attempts")
    .eq("id", redemptionId)
    .maybeSingle();

  await supabase
    .from("reward_redemptions_ledger")
    .update({
      shopify_code_delivery_status: "failed",
      shopify_code_delivery_failed_at: new Date().toISOString(),
      shopify_code_delivery_last_error: errorMessage.slice(0, 2000),
      shopify_code_delivery_attempts: (row?.shopify_code_delivery_attempts ?? 0) + 1,
    })
    .eq("id", redemptionId);
}

export const shopifyRedemptionIssueRouter = inngest.createFunction(
  {
    id: "shopify-redemption-issue-router",
    retries: 5,
    concurrency: { limit: 15 },
    idempotency: 'event.data.redemption_id + ":issue_requested"',
  },
  { event: "crm/redemption.event" },
  async ({ event, step }) => {
    const evt = event.data as ChokepointEvent;
    if (evt.event !== "issue_requested" || !evt.redemption_id) {
      return { routed: false, reason: "not_issue_requested" };
    }

    const result = await step.run("issue-shopify-code", async () => {
      const supabase = getSupabase();
      const { data: row, error } = await supabase
        .from("reward_redemptions_ledger")
        .select(
          "id, merchant_id, reward_id, code, external_ref_id, shopify_code_delivery_status, cancelled, success",
        )
        .eq("id", evt.redemption_id)
        .maybeSingle();

      if (error || !row) {
        throw new Error(`Redemption not found: ${error?.message || evt.redemption_id}`);
      }
      if (row.cancelled || row.success === false) {
        return { skipped: true, reason: "inactive_redemption" };
      }
      if (row.external_ref_id || row.shopify_code_delivery_status === "synced") {
        return { skipped: true, reason: "already_synced" };
      }
      if (!row.code) {
        throw new Error("Redemption has no code to issue");
      }

      const { data: reward, error: rewardError } = await supabase
        .from("reward_master")
        .select("external_id_shopify")
        .eq("id", row.reward_id)
        .eq("merchant_id", row.merchant_id)
        .maybeSingle();

      if (rewardError || !reward?.external_id_shopify) {
        await recordDeliveryFailure(
          supabase,
          row.id,
          rewardError?.message || "Reward has no linked Shopify parent discount",
        );
        throw new Error("Reward missing external_id_shopify — re-link reward discount in admin");
      }

      const response = await fetch(`${SUPABASE_URL}/functions/v1/shopify-issue-reward-code`, {
        method: "POST",
        headers: {
          Authorization: `Bearer ${SUPABASE_SERVICE_KEY}`,
          "Content-Type": "application/json",
        },
        body: JSON.stringify({
          merchant_id: row.merchant_id,
          reward_id: row.reward_id,
          discount_id: reward.external_id_shopify,
          code: row.code,
          redemption_id: row.id,
        }),
      });

      const body = (await response.json().catch(() => ({}))) as {
        success?: boolean;
        path?: string;
        external_ref_id?: string;
        redeem_code_gid?: string;
        code_verified?: boolean;
        error?: string;
      };

      const externalRef = body.external_ref_id || body.redeem_code_gid;
      const verified =
        body.success === true &&
        body.path !== "graphql_no_gid" &&
        (Boolean(externalRef) || body.code_verified === true);

      if (!response.ok || !verified) {
        const msg = body.error || `shopify-issue-reward-code HTTP ${response.status}`;
        await recordDeliveryFailure(supabase, row.id, msg);
        throw new Error(msg);
      }

      return { issued: true, path: body.path, external_ref_id: externalRef };
    });

    return { routed: true, redemption_id: evt.redemption_id, result };
  },
);
