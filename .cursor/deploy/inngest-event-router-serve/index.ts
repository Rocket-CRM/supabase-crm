/**
 * inngest-event-router-serve — Chokepoint event routers (Kafka consumer replacements)
 *
 * Receives chokepoint domain events published from `chokepoint_event_outbox` by the
 * OutboxPublisher worker (crm-event-processors, Inngest mode) and fans them out to the
 * existing downstream workflows. Replaces the Kafka `crm.events.*` consumers after the
 * Confluent deactivation of 2026-07-07.
 *
 * Hosted routers (v3 — currency + tier + mission + outcome attribution + notification + AMP):
 * - currency-purchase-router / currency-purchase-item-router  (v1, unchanged)
 * - tier-purchase-router / tier-wallet-router                 -> process_tier_event RPC
 * - mission-{purchase,purchase-item,wallet}-router            -> mission/evaluate events
 *   (v6, 2026-07-08: purchase router forwards amount/seller_id; new purchase-item router
 *   feeds SKU/product/category/brand-scoped purchase conditions)
 * - outcome-purchase-router / outcome-wallet-router           -> amp_outcome_attribution
 * - notification-{purchase,purchase-item,wallet,tier,user,redemption,receipt,referral}-router -> LINE/Email
 * - amp-{purchase,purchase-item,wallet,tier,user}-router      -> amp-dispatch-realtime-event
 *   (v3, 2026-07-08: amp-user-router batched + throttled per merchant for signup bursts;
 *   trigger matching cached per merchant by fn_get_active_triggers_cached, 600s)
 *
 * Still NOT ported: CDC-only AMP sources (form_submissions, amp_workflow_log
 * add_to_audience) — need chokepoint emits at their write sites first.
 *
 * Not hosted here (by design): expiry reminders. They are a clock scan, not an
 * event, and run as Render Cron Job `expiry-reminder-batch` on
 * crm-event-processors (removed from this app 2026-09-03; re-sync the Inngest
 * app after deploy so `expiry-reminder-tick` / `expiry-reminder-merchant`
 * unregister).
 *
 * Parity notes per router are in each lib/*.ts file. Redis dedup keys from the legacy
 * consumers are replaced by Inngest function `idempotency` expressions (24h window).
 * Per-user ordering for tier evaluation is enforced with a per-user concurrency key.
 *
 * SDK pinned >= 3.54.0 (older versions disabled by Inngest — CVE-2026-42047).
 */

import { serve } from "https://esm.sh/inngest@3.54.0/edge";
import { inngest } from "./lib/inngest-client.ts";
import {
  currencyPurchaseRouter,
  currencyPurchaseItemRouter,
} from "./lib/currency-router.ts";
import { tierPurchaseRouter, tierWalletRouter } from "./lib/tier-router.ts";
import {
  missionPurchaseRouter,
  missionPurchaseItemRouter,
  missionWalletRouter,
} from "./lib/mission-router.ts";
import { outcomePurchaseRouter, outcomeWalletRouter } from "./lib/outcome-router.ts";
import {
  notificationPurchaseRouter,
  notificationPurchaseItemRouter,
  notificationWalletRouter,
  notificationTierRouter,
  notificationUserRouter,
  notificationRedemptionRouter,
  notificationReceiptRouter,
  notificationReferralRouter,
} from "./lib/notification-router.ts";
import {
  ampPurchaseRouter,
  ampPurchaseItemRouter,
  ampWalletRouter,
  ampTierRouter,
  ampUserRouter,
} from "./lib/amp-router.ts";

const handler = serve({
  client: inngest,
  functions: [
    currencyPurchaseRouter,
    currencyPurchaseItemRouter,
    tierPurchaseRouter,
    tierWalletRouter,
    missionPurchaseRouter,
    missionPurchaseItemRouter,
    missionWalletRouter,
    outcomePurchaseRouter,
    outcomeWalletRouter,
    notificationPurchaseRouter,
    notificationPurchaseItemRouter,
    notificationWalletRouter,
    notificationTierRouter,
    notificationUserRouter,
    notificationRedemptionRouter,
    notificationReceiptRouter,
    notificationReferralRouter,
    ampPurchaseRouter,
    ampPurchaseItemRouter,
    ampWalletRouter,
    ampTierRouter,
    ampUserRouter,
  ],
  signingKey: Deno.env.get("INNGEST_SIGNING_KEY"),
  servePath: "/functions/v1/inngest-event-router-serve",
});

Deno.serve(handler);
