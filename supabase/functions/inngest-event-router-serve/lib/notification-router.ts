/**
 * Notification routers — thin Inngest adapters + the Deno copy of the delivery engine.
 *
 * Pipeline per event: map (event -> event_key/sub_event/source_event_id) ->
 * fn_resolve_notification_for_event RPC (single roundtrip; skip verdict or full render
 * inputs) -> enrich -> render (Flex or Email) -> LINE push or messaging-service Email -> log.
 *
 * SHARED CONTRACT — read before editing `processNotification` / `enrich`:
 * The canonical implementation is Node:
 *   crm-event-processors/src/notification/deliver-notification.ts  (engine)
 *   crm-event-processors/src/notification/types.ts                 (NotificationMapping ≡ ResolvedMapping)
 * That copy serves the clock-scan reminders (Render cron `expiry-reminder-batch`);
 * this copy serves the event routers below. Deno cannot import from the Node repo,
 * so the two are kept identical by hand: change both or neither, and keep
 * notification-flex.ts / notification-detail-url.ts / notification-line.ts in step
 * with utils/flex-template.ts / utils/detail-url.ts / clients/line.ts.
 * Follow-up option: route this through a Render internal deliver endpoint to get
 * to one implementation.
 *
 * Only event-driven adapters live here. Reminders (clock scan) are not Inngest.
 *
 * Parity / porting decisions:
 * - Legacy Redis dedup notification_dedup:<merchant>:<event_key>:<sub_event>:<source_event_id>
 *   (TTL 24h) is replaced by Inngest function idempotency on the same business key (source
 *   ids are UUIDs, so the merchant prefix is redundant).
 * - The whole resolve->push->log pipeline runs in ONE step so the merchant's
 *   channel_access_token is never persisted in Inngest step state. On a 5xx/network throw,
 *   the step retries end-to-end and the resolver's ALREADY_SENT backstop plus the
 *   notification_log unique constraint guard against double-send.
 * - The NOTIFICATION_CONSUMER_ENABLED dark-deploy gate is not ported: the pipeline was
 *   already live (resolver returns DISABLED / NO_CATALOG skips for unconfigured merchants).
 */

import { inngest } from "./inngest-client.ts";
import { getSupabase } from "./supabase.ts";
import { pushLineFlex } from "./notification-line.ts";
import { renderFlexFromTemplate, defaultAltText } from "./notification-flex.ts";
import { buildNotificationDetailUrl } from "./notification-detail-url.ts";
import {
  EmailTemplateJson,
  fetchNotificationAppearance,
  renderNotificationEmail,
  sendNotificationEmail,
} from "./notification-email.ts";
import { isTruthy } from "./types.ts";
import type { ChokepointEvent } from "./types.ts";

/** Always rendered by enrichment; not part of the admin field picker. */
const SYSTEM_RENDER_FIELDS = ["detail_url", "hero_image_url"] as const;

const PURCHASE_SUB_EVENTS = new Set(["created", "completed", "cancelled", "refunded"]);
const PURCHASE_ITEM_COMPLETE_EVENTS = new Set(["item_quantity_completed", "item_completion_set"]);
const TIER_SUB_EVENTS = new Set(["upgrade", "initial", "downgrade"]);
const REDEMPTION_SUB_EVENTS_DIRECT = new Set([
  "issued",
  "used",
  "cancelled",
  "entitlement_used",
  "entitlement_expired",
]);
const REDEMPTION_SUB_EVENT_RENAMED: Record<string, string> = {
  package_entitlement_created: "package_granted",
};
// Admin-internal / corrective verbs — never a user-facing notification.
const REDEMPTION_SUB_EVENTS_DROP = new Set([
  "unmarked_used",
  "entitlement_use_reversed",
  "entitlement_total_adjusted",
]);

export interface ResolvedMapping {
  eventKey: string;
  subEvent: string;
  sourceEventId: string;
  sourceTopic: string; // legacy Kafka topic name kept for notification_log continuity
  payload: ChokepointEvent;
  /** Delivery channel for the resolver. Defaults to 'line'. */
  channel?: string;
}

const DEFAULT_CHANNEL = "line";

const EMAIL_ENRICH_FIELDS = [
  "reward_name",
  "tier_name",
  "transaction_number",
  "status",
  "final_amount",
  "total_amount",
];

interface NotificationResolveResult {
  should_send: boolean;
  skip_reason?: string;
  channel?: string;
  line_id?: string;
  email?: string;
  channel_access_token?: string;
  flex_template?: Record<string, unknown>;
  email_template?: Record<string, unknown>;
  selected_fields?: string[];
  error?: string;
}

interface NotificationLogInput {
  merchant_id: string;
  user_id: string | null;
  event_key: string;
  sub_event: string;
  source_topic: string;
  source_event_id: string;
  channel?: string;
  line_user_id: string | null;
  status: "sent" | "failed" | "skipped";
  skip_reason?: string | null;
  flex_payload?: Record<string, unknown> | null;
  line_message_response?: Record<string, unknown> | null;
  last_error?: string | null;
}

async function recordNotificationLog(input: NotificationLogInput): Promise<void> {
  const supabase = getSupabase();
  const { error } = await supabase.from("notification_log").upsert(
    {
      merchant_id: input.merchant_id,
      user_id: input.user_id,
      event_key: input.event_key,
      sub_event: input.sub_event,
      source_topic: input.source_topic,
      source_event_id: input.source_event_id,
      channel: input.channel || "line",
      line_user_id: input.line_user_id,
      status: input.status,
      skip_reason: input.skip_reason ?? null,
      flex_payload: input.flex_payload ?? null,
      line_message_response: input.line_message_response ?? null,
      last_error: input.last_error ?? null,
    },
    { onConflict: "merchant_id,event_key,sub_event,source_event_id,channel", ignoreDuplicates: true },
  );
  if (error) {
    // Never block the pipeline on log writes — the unique constraint is the
    // idempotency anchor; a missing log row is a degraded but acceptable mode.
    console.error("[notification] recordNotificationLog failed:", error.message);
  }
}

async function chokepointDisableUserLineChannel(merchantId: string, userId: string): Promise<void> {
  const supabase = getSupabase();
  const { error } = await supabase.rpc("chokepoint_post_user_event", {
    p_event_type: "update",
    p_merchant_id: merchantId,
    p_user_id: userId,
    p_changes: { channel_line: false },
    p_skip_side_effects: false,
    p_skip_cdc: false,
    p_actor: { source: "notification-router", reason: "line_user_blocked_bot" },
  });
  if (error) {
    console.warn(
      `[notification] chokepointDisableUserLineChannel failed user=${userId} merchant=${merchantId}: ${error.message}`,
    );
  }
}

function firstHttpsUrl(value: unknown): string | null {
  if (typeof value === "string" && /^https?:\/\//i.test(value)) return value;
  if (Array.isArray(value)) {
    for (const item of value) {
      if (typeof item === "string" && /^https?:\/\//i.test(item)) return item;
    }
  }
  return null;
}

/**
 * Best-effort enrichment — only fetch what the template's selected fields need.
 * Ported from NotificationConsumer.enrich (in-memory caches dropped: edge isolates
 * are short-lived and volume is ~800 events/day).
 */
async function enrich(
  merchantId: string,
  mapping: ResolvedMapping,
  selectedFields: string[],
): Promise<Record<string, unknown>> {
  const supabase = getSupabase();
  const out: Record<string, unknown> = {};
  const selected = new Set(selectedFields || []);

  let merchantCode: string | null = null;
  let logo: string | null = null;
  let pointsSymbolImageUrl: string | null = null;
  try {
    const { data: merchant } = await supabase
      .from("merchant_master")
      .select("merchant_code")
      .eq("id", merchantId)
      .maybeSingle();
    merchantCode = (merchant?.merchant_code as string) ?? null;
    const { data: settings } = await supabase
      .from("merchant_display_settings")
      .select("logo, points_symbol_image_url")
      .eq("merchant_id", merchantId)
      .maybeSingle();
    logo = firstHttpsUrl(settings?.logo);
    pointsSymbolImageUrl = firstHttpsUrl(settings?.points_symbol_image_url);
  } catch (e) {
    console.warn(`[notification] merchant assets fetch failed for ${merchantId}:`, e);
  }

  if (mapping.eventKey === "redemption" && mapping.payload.reward_id) {
    try {
      const { data } = await supabase
        .from("reward_master")
        .select("name, image")
        .eq("id", mapping.payload.reward_id)
        .maybeSingle();
      if (selected.has("reward_name") && data?.name) out.reward_name = data.name;
      const imageUrl = firstHttpsUrl(data?.image);
      if (imageUrl) out.hero_image_url = imageUrl;
    } catch (e) {
      console.warn(`[notification] reward enrich failed:`, e);
    }
  }

  if (mapping.eventKey === "tier" && mapping.payload.to_tier_id) {
    try {
      const { data } = await supabase
        .from("tier_master")
        .select("tier_name, icon")
        .eq("id", mapping.payload.to_tier_id)
        .maybeSingle();
      if (selected.has("tier_name") && data?.tier_name) out.tier_name = data.tier_name;
      const iconUrl = firstHttpsUrl(data?.icon);
      if (iconUrl) out.hero_image_url = iconUrl;
    } catch (e) {
      console.warn(`[notification] tier enrich failed:`, e);
    }
  }

  if (mapping.eventKey === "purchase") {
    const needsLedger =
      selected.has("transaction_number") ||
      selected.has("status") ||
      selected.has("final_amount") ||
      selected.has("total_amount");
    if (needsLedger && mapping.payload.purchase_id) {
      try {
        const { data } = await supabase
          .from("purchase_ledger")
          .select("id, transaction_number, status, final_amount, total_amount")
          .eq("id", mapping.payload.purchase_id)
          .maybeSingle();
        if (data) {
          out.purchase_id = data.id;
          out.transaction_number = data.transaction_number;
          out.status = data.status;
          out.final_amount = data.final_amount;
          out.total_amount = data.total_amount;
        }
      } catch (e) {
        console.warn(`[notification] purchase enrich failed:`, e);
      }
    }
  }

  if (mapping.eventKey === "purchase_item" && mapping.payload.item_id) {
    // Always fetch item row — purchase_id is required for detail_url even when
    // the merchant field picker omits it.
    try {
      const { data } = await supabase
        .from("purchase_items_ledger")
        .select("id, transaction_id, product_name, sku_code, quantity, line_total, status")
        .eq("id", mapping.payload.item_id)
        .maybeSingle();
      if (data) {
        out.item_id = data.id;
        out.purchase_id = data.transaction_id;
        out.product_name = data.product_name;
        out.sku_code = data.sku_code;
        out.quantity = data.quantity;
        out.line_total = data.line_total;
        out.item_status = data.status;
      }
    } catch (e) {
      console.warn(`[notification] purchase_item enrich failed:`, e);
    }
  }

  if (!out.hero_image_url) {
    if (mapping.eventKey === "currency" && pointsSymbolImageUrl) {
      out.hero_image_url = pointsSymbolImageUrl;
    } else if (
      ["purchase", "purchase_item", "signup", "tier", "currency"].includes(mapping.eventKey) &&
      logo
    ) {
      out.hero_image_url = logo;
    }
  }

  if (merchantCode) {
    const merged = { ...(mapping.payload as Record<string, unknown>), ...out };
    const detailUrl = buildNotificationDetailUrl(
      merchantCode,
      mapping.eventKey,
      mapping.subEvent,
      merged,
    );
    if (detailUrl) out.detail_url = detailUrl;
  }

  return out;
}

/**
 * Full resolve -> enrich -> render -> push -> log pipeline. Runs inside a single
 * Inngest step (see file header for why). Returns a small serializable summary
 * (never the resolver verdict — it contains the merchant's LINE token).
 */
export async function processNotification(
  mapping: ResolvedMapping,
): Promise<{ outcome: string; reason?: string }> {
  const merchantId = mapping.payload.merchant_id!;
  const userId = (mapping.payload.user_id as string) || null;
  const channel = mapping.channel ?? DEFAULT_CHANNEL;

  const supabase = getSupabase();
  const { data, error } = await supabase.rpc("fn_resolve_notification_for_event", {
    p_merchant_id: merchantId,
    p_event_key: mapping.eventKey,
    p_sub_event: mapping.subEvent,
    p_user_id: userId,
    p_source_event_id: mapping.sourceEventId,
    p_channel: channel,
  });
  if (error) {
    // Throw so the step retries — the ALREADY_SENT backstop makes re-resolution safe.
    throw new Error(`fn_resolve_notification_for_event failed: ${error.message}`);
  }
  const verdict = (data || { should_send: false, skip_reason: "ERROR" }) as NotificationResolveResult;

  if (!verdict.should_send) {
    const reason = verdict.skip_reason || "UNKNOWN";
    // Suppress audit-log writes for high-volume "expected silence" cases.
    if (reason !== "DISABLED" && reason !== "NO_CATALOG" && reason !== "ALREADY_SENT") {
      await recordNotificationLog({
        merchant_id: merchantId,
        user_id: userId,
        event_key: mapping.eventKey,
        sub_event: mapping.subEvent,
        source_topic: mapping.sourceTopic,
        source_event_id: mapping.sourceEventId,
        channel,
        line_user_id: null,
        status: "skipped",
        skip_reason: reason,
        flex_payload: null,
        line_message_response: null,
        last_error: verdict.error ?? null,
      });
    }
    return { outcome: "skipped", reason };
  }

  if (channel === "email") {
    return processEmailNotification(mapping, merchantId, userId, verdict);
  }

  const template = verdict.flex_template;
  const selectedFields = verdict.selected_fields || [];
  const channelAccessToken = verdict.channel_access_token;
  const lineId = verdict.line_id;

  if (!template || !channelAccessToken || !lineId) {
    await recordNotificationLog({
      merchant_id: merchantId,
      user_id: userId,
      event_key: mapping.eventKey,
      sub_event: mapping.subEvent,
      source_topic: mapping.sourceTopic,
      source_event_id: mapping.sourceEventId,
      channel,
      line_user_id: lineId ?? null,
      status: "failed",
      skip_reason: "INVALID_RESOLVER_OUTPUT",
      flex_payload: null,
      line_message_response: null,
      last_error: "Resolver returned should_send=true but missing template/token/line_id",
    });
    return { outcome: "failed", reason: "INVALID_RESOLVER_OUTPUT" };
  }

  const enrichments = await enrich(merchantId, mapping, selectedFields);
  const renderFields = [...new Set([...selectedFields, ...SYSTEM_RENDER_FIELDS])];

  const rendered = renderFlexFromTemplate({
    template,
    payload: mapping.payload as unknown as Record<string, unknown>,
    selectedFields: renderFields,
    enrichments,
  });

  if (!rendered) {
    await recordNotificationLog({
      merchant_id: merchantId,
      user_id: userId,
      event_key: mapping.eventKey,
      sub_event: mapping.subEvent,
      source_topic: mapping.sourceTopic,
      source_event_id: mapping.sourceEventId,
      channel,
      line_user_id: lineId,
      status: "skipped",
      skip_reason: "EMPTY_RENDER",
      flex_payload: null,
      line_message_response: null,
      last_error: null,
    });
    return { outcome: "skipped", reason: "EMPTY_RENDER" };
  }

  const altText = defaultAltText(mapping.eventKey, mapping.subEvent);

  // 5xx / network errors throw out of pushLineFlex -> step retry -> re-resolve
  // (ALREADY_SENT backstop protects against double-send).
  const result = await pushLineFlex(channelAccessToken, lineId, rendered, altText);

  const lineResponse =
    typeof result.responseBody === "object" && result.responseBody !== null
      ? (result.responseBody as Record<string, unknown>)
      : { raw: result.responseBody };

  if (result.status === "sent") {
    await recordNotificationLog({
      merchant_id: merchantId,
      user_id: userId,
      event_key: mapping.eventKey,
      sub_event: mapping.subEvent,
      source_topic: mapping.sourceTopic,
      source_event_id: mapping.sourceEventId,
      channel,
      line_user_id: lineId,
      status: "sent",
      flex_payload: rendered,
      line_message_response: lineResponse,
    });
    return { outcome: "sent" };
  }

  if (result.status === "user_blocked" && userId) {
    await chokepointDisableUserLineChannel(merchantId, userId);
    await recordNotificationLog({
      merchant_id: merchantId,
      user_id: userId,
      event_key: mapping.eventKey,
      sub_event: mapping.subEvent,
      source_topic: mapping.sourceTopic,
      source_event_id: mapping.sourceEventId,
      channel,
      line_user_id: lineId,
      status: "failed",
      skip_reason: "USER_BLOCKED",
      flex_payload: rendered,
      line_message_response: lineResponse,
      last_error: result.error ?? null,
    });
    return { outcome: "failed", reason: "USER_BLOCKED" };
  }

  const failureReason = result.status === "rate_limited" ? "LINE_RATE_LIMITED" : "LINE_PUSH_FAILED";
  await recordNotificationLog({
    merchant_id: merchantId,
    user_id: userId,
    event_key: mapping.eventKey,
    sub_event: mapping.subEvent,
    source_topic: mapping.sourceTopic,
    source_event_id: mapping.sourceEventId,
    channel,
    line_user_id: lineId,
    status: "failed",
    skip_reason: failureReason,
    flex_payload: rendered,
    line_message_response: lineResponse,
    last_error: result.error ?? null,
  });
  return { outcome: "failed", reason: failureReason };
}

async function processEmailNotification(
  mapping: ResolvedMapping,
  merchantId: string,
  userId: string | null,
  verdict: NotificationResolveResult,
): Promise<{ outcome: string; reason?: string }> {
  const template = verdict.email_template as EmailTemplateJson | undefined;
  const toEmail = verdict.email;

  if (!template || !toEmail) {
    await recordNotificationLog({
      merchant_id: merchantId,
      user_id: userId,
      event_key: mapping.eventKey,
      sub_event: mapping.subEvent,
      source_topic: mapping.sourceTopic,
      source_event_id: mapping.sourceEventId,
      channel: "email",
      line_user_id: null,
      status: "failed",
      skip_reason: "INVALID_RESOLVER_OUTPUT",
      last_error: "Resolver returned should_send=true but missing email/email_template",
    });
    return { outcome: "failed", reason: "INVALID_RESOLVER_OUTPUT" };
  }

  const selectedFields = [
    ...new Set([...(verdict.selected_fields || []), ...EMAIL_ENRICH_FIELDS, ...SYSTEM_RENDER_FIELDS]),
  ];
  const enrichments = await enrich(merchantId, mapping, selectedFields);
  const lookup = {
    ...(mapping.payload as unknown as Record<string, unknown>),
    ...enrichments,
  };
  const appearance = await fetchNotificationAppearance(merchantId);
  const rendered = renderNotificationEmail({ template, lookup, appearance });

  if (!rendered) {
    await recordNotificationLog({
      merchant_id: merchantId,
      user_id: userId,
      event_key: mapping.eventKey,
      sub_event: mapping.subEvent,
      source_topic: mapping.sourceTopic,
      source_event_id: mapping.sourceEventId,
      channel: "email",
      line_user_id: null,
      status: "skipped",
      skip_reason: "EMPTY_RENDER",
    });
    return { outcome: "skipped", reason: "EMPTY_RENDER" };
  }

  const result = await sendNotificationEmail({
    merchantId,
    userId,
    toEmail,
    rendered,
    appearance,
    sourceEventId: mapping.sourceEventId,
  });

  if (result.status === "sent") {
    await recordNotificationLog({
      merchant_id: merchantId,
      user_id: userId,
      event_key: mapping.eventKey,
      sub_event: mapping.subEvent,
      source_topic: mapping.sourceTopic,
      source_event_id: mapping.sourceEventId,
      channel: "email",
      line_user_id: null,
      status: "sent",
      flex_payload: { subject: rendered.subject, html: rendered.html },
      line_message_response: result.responseBody,
    });
    return { outcome: "sent" };
  }

  await recordNotificationLog({
    merchant_id: merchantId,
    user_id: userId,
    event_key: mapping.eventKey,
    sub_event: mapping.subEvent,
    source_topic: mapping.sourceTopic,
    source_event_id: mapping.sourceEventId,
    channel: "email",
    line_user_id: null,
    status: "failed",
    skip_reason: "EMAIL_SEND_FAILED",
    flex_payload: { subject: rendered.subject },
    line_message_response: result.responseBody,
    last_error: result.error ?? null,
  });
  return { outcome: "failed", reason: "EMAIL_SEND_FAILED" };
}

// deno-lint-ignore no-explicit-any
async function runMapped(step: any, mapping: ResolvedMapping | null) {
  if (!mapping) return { routed: false, reason: "no_notification_mapping" };
  if (!mapping.payload.merchant_id) return { routed: false, reason: "missing_merchant_id" };
  const line = (await step.run("deliver-line", () =>
    processNotification({ ...mapping, channel: "line" }),
  )) as { outcome: string; reason?: string };
  const email = (await step.run("deliver-email", () =>
    processNotification({ ...mapping, channel: "email" }),
  )) as { outcome: string; reason?: string };
  return {
    routed: true,
    eventKey: mapping.eventKey,
    subEvent: mapping.subEvent,
    line,
    email,
  };
}

const NOTIFICATION_CONCURRENCY = [{ limit: 5 }];

export const notificationPurchaseRouter = inngest.createFunction(
  {
    id: "notification-purchase-router",
    retries: 3,
    concurrency: NOTIFICATION_CONCURRENCY,
    idempotency: 'event.data.purchase_id + ":" + event.data.event',
  },
  { event: "crm/purchase.event" },
  async ({ event, step }) => {
    const evt = event.data as ChokepointEvent;
    const sub = evt.event;
    if (!sub || !PURCHASE_SUB_EVENTS.has(sub) || !evt.purchase_id) {
      return { routed: false, reason: "no_notification_mapping", event: sub };
    }
    return await runMapped(step, {
      eventKey: "purchase",
      subEvent: sub,
      sourceEventId: evt.purchase_id,
      sourceTopic: "crm.events.purchase",
      payload: evt,
    });
  },
);

export const notificationPurchaseItemRouter = inngest.createFunction(
  {
    id: "notification-purchase-item-router",
    retries: 3,
    concurrency: NOTIFICATION_CONCURRENCY,
    idempotency: 'event.data.item_id + ":" + event.data.event',
  },
  { event: "crm/purchase_item.event" },
  async ({ event, step }) => {
    const evt = event.data as ChokepointEvent;
    if (
      !evt.item_id ||
      evt.item_status !== "completed" ||
      !evt.event ||
      !PURCHASE_ITEM_COMPLETE_EVENTS.has(evt.event)
    ) {
      return { routed: false, reason: "no_notification_mapping", event: evt.event };
    }
    return await runMapped(step, {
      eventKey: "purchase_item",
      subEvent: "completed",
      sourceEventId: evt.item_id,
      sourceTopic: "crm.events.purchase_item",
      payload: evt,
    });
  },
);

/**
 * Ticket earns/burns expand one chokepoint call into N wallet events (amount=1 each)
 * with unit_index / unit_total. LINE should fire once per award call with the full
 * amount — not once per ledger unit. Keep Inngest idempotency on wallet_ledger_id
 * so a non-1 unit cannot consume an award-call key before unit 1 runs.
 */
function coalesceWalletNotificationPayload(
  evt: ChokepointEvent,
): { ok: true; payload: ChokepointEvent } | { ok: false; reason: string } {
  const unitIndexRaw = evt.unit_index;
  if (unitIndexRaw !== undefined && unitIndexRaw !== null && unitIndexRaw !== "") {
    const unitIndex = Number(unitIndexRaw);
    if (!Number.isFinite(unitIndex) || unitIndex !== 1) {
      return { ok: false, reason: "ticket_unit_coalesced" };
    }
  }

  const unitTotalRaw = evt.unit_total;
  if (unitTotalRaw === undefined || unitTotalRaw === null || unitTotalRaw === "") {
    return { ok: true, payload: evt };
  }
  const unitTotal = Number(unitTotalRaw);
  if (!Number.isFinite(unitTotal) || unitTotal <= 0) {
    return { ok: true, payload: evt };
  }
  return { ok: true, payload: { ...evt, amount: unitTotal } };
}

export const notificationWalletRouter = inngest.createFunction(
  {
    id: "notification-wallet-router",
    retries: 3,
    concurrency: NOTIFICATION_CONCURRENCY,
    // Per ledger row (not award-call composite): unit_index gate no-ops siblings
    // without blocking unit 1 if a later unit is processed first.
    idempotency: "event.data.wallet_ledger_id",
  },
  { event: "crm/wallet.event" },
  async ({ event, step }) => {
    const evt = event.data as ChokepointEvent;
    const tt = evt.transaction_type;
    let sub: string | null = null;
    if (tt === "earn" && evt.component === "base") sub = "earned";
    else if (tt === "burn") sub = "burned";
    else if (tt === "expire") sub = "expired";
    if (!sub || !evt.wallet_ledger_id) {
      return { routed: false, reason: "no_notification_mapping", transaction_type: tt };
    }

    const coalesced = coalesceWalletNotificationPayload(evt);
    if (!coalesced.ok) {
      return {
        routed: false,
        reason: coalesced.reason,
        unit_index: evt.unit_index,
        unit_total: evt.unit_total,
      };
    }

    return await runMapped(step, {
      eventKey: "currency",
      subEvent: sub,
      // uuid column: unit-1 ledger id stands for the whole award call
      sourceEventId: evt.wallet_ledger_id,
      sourceTopic: "crm.events.wallet",
      payload: coalesced.payload,
    });
  },
);

export const notificationTierRouter = inngest.createFunction(
  {
    id: "notification-tier-router",
    retries: 3,
    concurrency: NOTIFICATION_CONCURRENCY,
    idempotency: "event.data.tier_change_ledger_id",
  },
  { event: "crm/tier_change.event" },
  async ({ event, step }) => {
    const evt = event.data as ChokepointEvent;
    const sub = evt.change_type;
    if (!sub || !TIER_SUB_EVENTS.has(sub) || !evt.tier_change_ledger_id) {
      return { routed: false, reason: "no_notification_mapping", change_type: sub };
    }
    return await runMapped(step, {
      eventKey: "tier",
      subEvent: sub,
      sourceEventId: evt.tier_change_ledger_id,
      sourceTopic: "crm.events.tier_change",
      payload: evt,
    });
  },
);

export const notificationUserRouter = inngest.createFunction(
  {
    id: "notification-user-router",
    retries: 3,
    concurrency: NOTIFICATION_CONCURRENCY,
    idempotency: 'event.data.user_id + ":" + event.data.event',
  },
  { event: "crm/user.event" },
  async ({ event, step }) => {
    const evt = event.data as ChokepointEvent;
    // Signup notification: fires once per user, on initial create, only when CDC
    // isn't suppressed (skip_cdc=true is used for backfill / bulk imports).
    const sub = evt.event || evt.user_event_type;
    if (sub !== "create" || isTruthy(evt.skip_cdc) || !evt.user_id) {
      return { routed: false, reason: "no_notification_mapping", event: sub };
    }
    return await runMapped(step, {
      eventKey: "signup",
      subEvent: "signup",
      sourceEventId: evt.user_id,
      sourceTopic: "crm.events.user",
      payload: evt,
    });
  },
);

export const notificationRedemptionRouter = inngest.createFunction(
  {
    id: "notification-redemption-router",
    retries: 3,
    concurrency: NOTIFICATION_CONCURRENCY,
    idempotency: 'event.data.redemption_id + ":" + event.data.event',
  },
  { event: "crm/redemption.event" },
  async ({ event, step }) => {
    const evt = event.data as ChokepointEvent;
    const raw = evt.event;
    if (!raw || !evt.redemption_id || REDEMPTION_SUB_EVENTS_DROP.has(raw)) {
      return { routed: false, reason: "no_notification_mapping", event: raw };
    }
    const sub = REDEMPTION_SUB_EVENT_RENAMED[raw] ?? raw;
    if (!REDEMPTION_SUB_EVENTS_DIRECT.has(raw) && !REDEMPTION_SUB_EVENT_RENAMED[raw]) {
      return { routed: false, reason: "no_notification_mapping", event: raw };
    }
    return await runMapped(step, {
      eventKey: "redemption",
      subEvent: sub,
      sourceEventId: evt.redemption_id,
      sourceTopic: "crm.events.redemption",
      payload: evt,
    });
  },
);

const RECEIPT_SUB_EVENTS = new Set(["submitted", "rejected"]);

export const notificationReceiptRouter = inngest.createFunction(
  {
    id: "notification-receipt-router",
    retries: 3,
    concurrency: NOTIFICATION_CONCURRENCY,
    idempotency: 'event.data.receipt_upload_id + ":" + event.data.event',
  },
  { event: "crm/receipt.event" },
  async ({ event, step }) => {
    const evt = event.data as ChokepointEvent;
    const sub = evt.event;
    if (!sub || !RECEIPT_SUB_EVENTS.has(sub) || !evt.receipt_upload_id) {
      return { routed: false, reason: "no_notification_mapping", event: sub };
    }
    return await runMapped(step, {
      eventKey: "receipt",
      subEvent: sub,
      sourceEventId: evt.receipt_upload_id as string,
      sourceTopic: "crm.events.receipt",
      payload: evt,
    });
  },
);

function mapReferralNotification(evt: ChokepointEvent): ResolvedMapping | null {
  const domainEvent = evt.event;
  const role = typeof evt.recipient_role === "string" ? evt.recipient_role : "";
  let sub: string | null = null;
  if (domainEvent === "settled" && role === "referrer") sub = "completed";
  else if (domainEvent === "settled" && role === "friend") sub = "friend_rewarded";
  else if (domainEvent === "claimed" && role === "friend") sub = "friend_rewarded";
  if (!sub) return null;

  const sourceEventId =
    domainEvent === "claimed"
      ? (evt.claim_id as string | undefined)
      : (evt.referral_ledger_id as string | undefined);
  if (!sourceEventId) return null;

  return {
    eventKey: "referral",
    subEvent: sub,
    sourceEventId,
    sourceTopic: "crm.events.referral",
    payload: evt,
  };
}

export const notificationReferralRouter = inngest.createFunction(
  {
    id: "notification-referral-router",
    retries: 3,
    concurrency: NOTIFICATION_CONCURRENCY,
    idempotency:
      'event.data.event + ":" + event.data.recipient_role + ":" + event.data.referral_ledger_id + ":" + event.data.claim_id + ":" + event.data.user_id',
  },
  { event: "crm/referral.event" },
  async ({ event, step }) => {
    const evt = event.data as ChokepointEvent;
    const mapping = mapReferralNotification(evt);
    if (!mapping) {
      return { routed: false, reason: "no_notification_mapping", event: evt.event };
    }
    return await runMapped(step, mapping);
  },
);
