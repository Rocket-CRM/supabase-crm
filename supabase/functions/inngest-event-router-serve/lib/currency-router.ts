/**
 * Currency routers — ported verbatim from v1 of this edge function (originally from
 * CurrencyConsumer in crm-event-processors, timezone-aware calculateAwardTime version).
 *
 * - Predicate: earn_currency === true AND status in {pending, processing, completed}
 * - Dedup: legacy Redis key currency_dedup:<source>:<id>:<status> (TTL 300s) replaced by
 *   Inngest idempotency on the same business key (24h window — stronger).
 * - Emits the exact same `currency/award` payload; the award workflow is unchanged.
 */

import { NonRetriableError } from "https://esm.sh/inngest@3.54.0";
import { inngest } from "./inngest-client.ts";
import { getSupabase } from "./supabase.ts";
import type { ChokepointEvent } from "./types.ts";

const AWARDABLE_PURCHASE_STATUSES = new Set(["pending", "processing", "completed"]);

interface MerchantCurrencyConfig {
  currency_award_delay_type: string; // 'immediate' | 'rolling_minutes' | 'rolling_days' | 'scheduled'
  currency_award_delay_days: number;
  currency_award_delay_minutes: number;
  currency_award_time: string | null; // 'HH:MM:SS'
  currency_award_timezone: string;
}

// ---------------------------------------------------------------------------
// Award-time computation (ported verbatim from CurrencyConsumer.calculateAwardTime,
// timezone-aware version)
// ---------------------------------------------------------------------------

const zonedPartFormatterCache = new Map<string, Intl.DateTimeFormat>();

function getZonedDateTimeParts(date: Date, timeZone: string) {
  let formatter = zonedPartFormatterCache.get(timeZone);
  if (!formatter) {
    formatter = new Intl.DateTimeFormat("en-US", {
      timeZone,
      year: "numeric",
      month: "2-digit",
      day: "2-digit",
      hour: "2-digit",
      minute: "2-digit",
      second: "2-digit",
      hourCycle: "h23",
    });
    zonedPartFormatterCache.set(timeZone, formatter);
  }
  const values: Record<string, number> = {};
  for (const part of formatter.formatToParts(date)) {
    if (part.type !== "literal") values[part.type] = Number(part.value);
  }
  return {
    year: values.year,
    month: values.month,
    day: values.day,
    hour: values.hour,
    minute: values.minute,
    second: values.second,
  };
}

function addCalendarDays(year: number, month: number, day: number, days: number) {
  const date = new Date(Date.UTC(year, month - 1, day + days));
  return {
    year: date.getUTCFullYear(),
    month: date.getUTCMonth() + 1,
    day: date.getUTCDate(),
  };
}

function parseAwardTime(awardTime: string) {
  const [hour = 8, minute = 0, second = 0] = awardTime.split(":").map(Number);
  return {
    hour: Number.isFinite(hour) ? hour : 8,
    minute: Number.isFinite(minute) ? minute : 0,
    second: Number.isFinite(second) ? second : 0,
  };
}

function zonedWallTimeToUtc(
  year: number,
  month: number,
  day: number,
  hour: number,
  minute: number,
  second: number,
  timeZone: string,
): Date {
  const targetUtc = Date.UTC(year, month - 1, day, hour, minute, second);
  let guessUtc = targetUtc;
  for (let i = 0; i < 3; i += 1) {
    const parts = getZonedDateTimeParts(new Date(guessUtc), timeZone);
    const zonedAsUtc = Date.UTC(
      parts.year,
      parts.month - 1,
      parts.day,
      parts.hour,
      parts.minute,
      parts.second,
    );
    const offset = zonedAsUtc - targetUtc;
    guessUtc -= offset;
  }
  return new Date(guessUtc);
}

function calculateDelayedDayAwardTime(cfg: MerchantCurrencyConfig, now: Date): string {
  const delayDays = Math.max(cfg.currency_award_delay_days || 0, 0);
  if (delayDays === 0) return now.toISOString();

  if (!cfg.currency_award_time) {
    const rollingDaysDate = new Date(now);
    rollingDaysDate.setDate(rollingDaysDate.getDate() + delayDays);
    return rollingDaysDate.toISOString();
  }

  const timeZone = cfg.currency_award_timezone || "Asia/Bangkok";
  const nowParts = getZonedDateTimeParts(now, timeZone);
  const awardDateParts = addCalendarDays(nowParts.year, nowParts.month, nowParts.day, delayDays);
  const awardTimeParts = parseAwardTime(cfg.currency_award_time);

  return zonedWallTimeToUtc(
    awardDateParts.year,
    awardDateParts.month,
    awardDateParts.day,
    awardTimeParts.hour,
    awardTimeParts.minute,
    awardTimeParts.second,
    timeZone,
  ).toISOString();
}

function calculateAwardTime(cfg: MerchantCurrencyConfig): string {
  const now = new Date();
  switch (cfg.currency_award_delay_type || "immediate") {
    case "scheduled":
    case "rolling_days":
      return calculateDelayedDayAwardTime(cfg, now);
    case "rolling_minutes":
      return new Date(now.getTime() + (cfg.currency_award_delay_minutes || 0) * 60 * 1000).toISOString();
    case "immediate":
    default:
      return now.toISOString();
  }
}

// ---------------------------------------------------------------------------
// Shared award pipeline (ported from CurrencyConsumer.processCurrencyAward)
// ---------------------------------------------------------------------------

async function calcCurrencyRows(
  sourceType: string,
  sourceId: string,
  merchantId: string,
  userId: string,
): Promise<unknown[]> {
  const supabase = getSupabase();
  const { data, error } = await supabase.rpc("calc_currency_for_source", {
    p_source_type: sourceType,
    p_source_id: sourceId,
    p_merchant_id: merchantId,
    p_user_id: userId,
  });
  if (error) {
    if (error.code === "PGRST202") {
      throw new NonRetriableError(`RPC not found: ${error.message}`);
    }
    throw new Error(`calc_currency_for_source failed ${error.code || ""}: ${error.message}`);
  }
  return (data || []) as unknown[];
}

async function getMerchantCurrencyConfig(merchantId: string): Promise<MerchantCurrencyConfig> {
  const supabase = getSupabase();
  const { data, error } = await supabase
    .from("merchant_master")
    .select(
      "currency_award_delay_type, currency_award_delay_days, currency_award_delay_minutes, currency_award_time, currency_award_timezone",
    )
    .eq("id", merchantId)
    .single();
  if (error) throw new Error(`merchant config fetch failed: ${error.message}`);
  return {
    currency_award_delay_type: data.currency_award_delay_type || "immediate",
    currency_award_delay_days: data.currency_award_delay_days || 0,
    currency_award_delay_minutes: data.currency_award_delay_minutes || 0,
    currency_award_time: data.currency_award_time || null,
    currency_award_timezone: data.currency_award_timezone || "Asia/Bangkok",
  };
}

// deno-lint-ignore no-explicit-any
async function routeCurrencyAward(step: any, params: {
  sourceType: "purchase" | "purchase_item";
  sourceId: string;
  userId: string;
  merchantId: string;
}) {
  const { sourceType, sourceId, userId, merchantId } = params;

  const currencyRows = (await step.run("calc-currency", () =>
    calcCurrencyRows(sourceType, sourceId, merchantId, userId),
  )) as unknown[];

  if (!currencyRows || currencyRows.length === 0) {
    return { routed: false, reason: "no_currency_rows", sourceType, sourceId };
  }

  const awardDatetime = (await step.run("award-datetime", async () => {
    const cfg = await getMerchantCurrencyConfig(merchantId);
    return calculateAwardTime(cfg);
  })) as string;

  await step.sendEvent("send-currency-award", {
    name: "currency/award",
    data: {
      source_type: sourceType,
      source_id: sourceId,
      user_id: userId,
      merchant_id: merchantId,
      currency_rows: currencyRows,
      award_datetime: awardDatetime,
    },
  });

  return {
    routed: true,
    sourceType,
    sourceId,
    rows: currencyRows.length,
    award_datetime: awardDatetime,
  };
}

// ---------------------------------------------------------------------------
// Routers
// ---------------------------------------------------------------------------

export const currencyPurchaseRouter = inngest.createFunction(
  {
    id: "currency-purchase-router",
    retries: 4,
    concurrency: [{ limit: 10 }],
    // Legacy Redis dedup key was currency_dedup:purchase:<purchase_id>:<status>
    idempotency: 'event.data.purchase_id + ":" + event.data.status',
  },
  { event: "crm/purchase.event" },
  async ({ event, step }) => {
    const data = event.data as ChokepointEvent;

    if (
      data.earn_currency !== true ||
      typeof data.status !== "string" ||
      !AWARDABLE_PURCHASE_STATUSES.has(data.status)
    ) {
      return { routed: false, reason: "filter_not_met", event: data.event, status: data.status };
    }
    if (!data.user_id || !data.merchant_id || !data.purchase_id) {
      return { routed: false, reason: "missing_required_fields", purchase_id: data.purchase_id };
    }

    return await routeCurrencyAward(step, {
      sourceType: "purchase",
      sourceId: data.purchase_id,
      userId: data.user_id,
      merchantId: data.merchant_id,
    });
  },
);

export const currencyPurchaseItemRouter = inngest.createFunction(
  {
    id: "currency-purchase-item-router",
    retries: 4,
    concurrency: [{ limit: 10 }],
    // Legacy Redis dedup key was currency_dedup:purchase_item:<item_id>:<item_status>
    idempotency: 'event.data.item_id + ":" + event.data.item_status',
  },
  { event: "crm/purchase_item.event" },
  async ({ event, step }) => {
    const data = event.data as ChokepointEvent;

    if (
      data.earn_currency !== true ||
      typeof data.item_status !== "string" ||
      !AWARDABLE_PURCHASE_STATUSES.has(data.item_status)
    ) {
      return {
        routed: false,
        reason: "filter_not_met",
        event: data.event,
        item_status: data.item_status,
      };
    }
    if (!data.user_id || !data.merchant_id || !data.item_id) {
      return { routed: false, reason: "missing_required_fields", item_id: data.item_id };
    }

    return await routeCurrencyAward(step, {
      sourceType: "purchase_item",
      sourceId: data.item_id,
      userId: data.user_id,
      merchantId: data.merchant_id,
    });
  },
);
