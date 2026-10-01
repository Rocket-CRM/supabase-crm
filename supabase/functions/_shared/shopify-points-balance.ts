import type { SupabaseClient } from "https://esm.sh/@supabase/supabase-js@2.38.4";
import {
  type ShopifyCredentialRecord,
  shopifyAdminGraphql,
} from "./shopify-admin-client.ts";

/** Admin API version for metafieldsSet + compareDigest (2024-04 customerUpdate lacks CAS). */
export const LOYALTY_BALANCE_METAFIELD_API_VERSION = "2025-10";

export const LOYALTY_ENTITLEMENT_NAMESPACE = "loyalty";
export const LOYALTY_ENTITLEMENT_KEY = "discount_entitlement";
export const LOYALTY_DISCOUNT_TITLE = "Loyalty Redemption";
export const LOYALTY_CODE_PREFIX = "LOYALTY";
const RESERVATION_REUSE_MS = 2 * 60 * 1000;
const LOYALTY_RESERVATION_TITLE_PREFIX = "Loyalty points – ";

/** Mint title: `Loyalty points – {label} · {shopifyCustomerNumericId}` */
export function formatLoyaltyReservationDiscountTitle(
  label: string,
  shopifyCustomerNumericId: string,
): string {
  return `${LOYALTY_RESERVATION_TITLE_PREFIX}${label} · ${shopifyCustomerNumericId}`;
}

export function parseLoyaltyReservationDiscountTitle(
  title: string,
): { label: string; ownerNumericId: string } | null {
  const trimmed = title.trim();
  if (!trimmed.startsWith(LOYALTY_RESERVATION_TITLE_PREFIX)) return null;
  const rest = trimmed.slice(LOYALTY_RESERVATION_TITLE_PREFIX.length);
  const sep = rest.lastIndexOf("·");
  if (sep <= 0) return null;
  const label = rest.slice(0, sep).trim();
  const ownerNumericId = rest.slice(sep + 1).trim();
  if (!label || !/^\d+$/.test(ownerNumericId)) return null;
  return { label, ownerNumericId };
}

export type LoyaltyReserved = {
  code: string;
  discount_node_id: string;
  amount: number;
  reserved_at: string;
};

export type LoyaltyPointsBalance = {
  status: "active" | "consumed";
  amount: number;
  currency: string;
  reserved: LoyaltyReserved | null;
  processed_order_ids: string[];
  updated_at: string;
};

export type LoyaltyBalanceRead = {
  balance: LoyaltyPointsBalance | null;
  compareDigest: string | null;
  record: ShopifyCredentialRecord;
};

function num(v: unknown): number {
  if (v === null || v === undefined || v === "") return 0;
  const n = typeof v === "number" ? v : parseFloat(String(v));
  return Number.isFinite(n) ? n : 0;
}

export function customerGidFromId(shopifyCustomerId: string): string {
  const trimmed = shopifyCustomerId.trim();
  if (trimmed.startsWith("gid://")) return trimmed;
  return `gid://shopify/Customer/${trimmed}`;
}

export function numericCustomerId(gidOrNumeric: string): string {
  const s = gidOrNumeric.trim();
  const m = s.match(/(\d+)$/);
  return m ? m[1]! : s;
}

export function emptyBalance(currency = "THB"): LoyaltyPointsBalance {
  return {
    status: "active",
    amount: 0,
    currency,
    reserved: null,
    processed_order_ids: [],
    updated_at: new Date().toISOString(),
  };
}

export function parseLoyaltyPointsBalance(raw: unknown): LoyaltyPointsBalance | null {
  if (raw == null) return null;
  let json: Record<string, unknown>;
  if (typeof raw === "string") {
    try {
      json = JSON.parse(raw);
    } catch {
      return null;
    }
  } else if (typeof raw === "object") {
    json = raw as Record<string, unknown>;
  } else {
    return null;
  }

  const statusRaw = String(json.status || "active").toLowerCase();
  const status = statusRaw === "consumed" ? "consumed" : "active";
  const amount = status === "active" ? Math.max(0, num(json.amount)) : 0;
  const currency = String(json.currency || "THB");

  let reserved: LoyaltyReserved | null = null;
  const r = json.reserved;
  if (r && typeof r === "object") {
    const ro = r as Record<string, unknown>;
    const code = String(ro.code || "").trim();
    const nodeId = String(ro.discount_node_id || "").trim();
    const ramt = num(ro.amount);
    if (code && nodeId && ramt > 0) {
      reserved = {
        code,
        discount_node_id: nodeId,
        amount: ramt,
        reserved_at: String(ro.reserved_at || new Date().toISOString()),
      };
    }
  }

  const processed = Array.isArray(json.processed_order_ids)
    ? json.processed_order_ids.map((id) => String(id)).filter(Boolean).slice(-20)
    : [];

  return {
    status,
    amount,
    currency,
    reserved,
    processed_order_ids: processed,
    updated_at: String(json.updated_at || new Date().toISOString()),
  };
}

export function balanceGetSummary(balance: LoyaltyPointsBalance | null): {
  available: number;
  reserved_amount: number;
  currency: string;
} {
  if (!balance || balance.status !== "active") {
    return { available: 0, reserved_amount: 0, currency: balance?.currency || "THB" };
  }
  return {
    available: Math.max(0, balance.amount),
    reserved_amount: balance.reserved?.amount ?? 0,
    currency: balance.currency || "THB",
  };
}

const READ_BALANCE_QUERY = `
query ReadLoyaltyPointsBalance($id: ID!) {
  customer(id: $id) {
    id
    metafield(namespace: "${LOYALTY_ENTITLEMENT_NAMESPACE}", key: "${LOYALTY_ENTITLEMENT_KEY}") {
      value
      compareDigest
    }
  }
}`;

const METAFIELDS_SET = `
mutation SetLoyaltyPointsBalance($metafields: [MetafieldsSetInput!]!) {
  metafieldsSet(metafields: $metafields) {
    metafields { key namespace value compareDigest updatedAt }
    userErrors { field message code }
  }
}`;

export async function readLoyaltyPointsBalance(
  supabase: SupabaseClient,
  record: ShopifyCredentialRecord,
  customerGid: string,
): Promise<LoyaltyBalanceRead> {
  const { body, record: nextRecord, ok } = await shopifyAdminGraphql(
    supabase,
    record,
    LOYALTY_BALANCE_METAFIELD_API_VERSION,
    READ_BALANCE_QUERY,
    { id: customerGid },
  );
  if (!ok || body.errors) {
    throw new Error("metafield_read_failed");
  }
  const customer = (body.data as Record<string, unknown> | undefined)?.customer as
    | Record<string, unknown>
    | undefined;
  const mf = customer?.metafield as Record<string, unknown> | undefined;
  const balance = parseLoyaltyPointsBalance(mf?.value ?? null);
  const compareDigest = mf?.compareDigest != null ? String(mf.compareDigest) : null;
  return { balance, compareDigest, record: nextRecord };
}

function isCompareDigestConflict(userErrors: Array<Record<string, unknown>> | undefined): boolean {
  if (!userErrors?.length) return false;
  return userErrors.some((e) => {
    const code = String(e.code || "").toUpperCase();
    const msg = String(e.message || "").toLowerCase();
    return code.includes("COMPARE") || code.includes("STALE") || msg.includes("compare") ||
      msg.includes("stale");
  });
}

export async function writeLoyaltyPointsBalance(
  supabase: SupabaseClient,
  record: ShopifyCredentialRecord,
  customerGid: string,
  balance: LoyaltyPointsBalance,
  compareDigest: string | null,
): Promise<{ record: ShopifyCredentialRecord; compareDigest: string | null }> {
  const payload: LoyaltyPointsBalance = {
    ...balance,
    updated_at: new Date().toISOString(),
    processed_order_ids: (balance.processed_order_ids || []).slice(-20),
  };
  if (payload.status !== "active") payload.amount = 0;
  if (payload.amount <= 0 && !payload.reserved) payload.status = "consumed";

  const metafieldInput: Record<string, unknown> = {
    ownerId: customerGid,
    namespace: LOYALTY_ENTITLEMENT_NAMESPACE,
    key: LOYALTY_ENTITLEMENT_KEY,
    type: "json",
    value: JSON.stringify(payload),
  };
  if (compareDigest) metafieldInput.compareDigest = compareDigest;

  const { body, record: nextRecord, ok } = await shopifyAdminGraphql(
    supabase,
    record,
    LOYALTY_BALANCE_METAFIELD_API_VERSION,
    METAFIELDS_SET,
    { metafields: [metafieldInput] },
  );
  const result = (body.data as Record<string, unknown> | undefined)?.metafieldsSet as
    | Record<string, unknown>
    | undefined;
  const userErrors = result?.userErrors as Array<Record<string, unknown>> | undefined;
  if (!ok || body.errors || (userErrors && userErrors.length > 0)) {
    if (isCompareDigestConflict(userErrors)) {
      throw new Error("compare_digest_conflict");
    }
    throw new Error("metafield_write_failed");
  }
  const written = (result?.metafields as Array<Record<string, unknown>> | undefined)?.[0];
  const nextDigest = written?.compareDigest != null ? String(written.compareDigest) : null;
  return { record: nextRecord, compareDigest: nextDigest };
}

export async function mutateLoyaltyPointsBalance(
  supabase: SupabaseClient,
  record: ShopifyCredentialRecord,
  customerGid: string,
  mutator: (current: LoyaltyPointsBalance) => LoyaltyPointsBalance,
  maxAttempts = 3,
): Promise<{ balance: LoyaltyPointsBalance; record: ShopifyCredentialRecord }> {
  let cred = record;
  for (let attempt = 0; attempt < maxAttempts; attempt++) {
    const read = await readLoyaltyPointsBalance(supabase, cred, customerGid);
    cred = read.record;
    const base = read.balance ?? emptyBalance();
    const next = mutator({ ...base, processed_order_ids: [...(base.processed_order_ids || [])] });
    try {
      const written = await writeLoyaltyPointsBalance(
        supabase,
        cred,
        customerGid,
        next,
        read.compareDigest,
      );
      cred = written.record;
      return { balance: next, record: cred };
    } catch (err) {
      if (err instanceof Error && err.message === "compare_digest_conflict" && attempt < maxAttempts - 1) {
        continue;
      }
      throw err;
    }
  }
  throw new Error("metafield_write_failed");
}

export async function addAmountToLoyaltyBalance(
  supabase: SupabaseClient,
  record: ShopifyCredentialRecord,
  customerGid: string,
  addAmount: number,
  currency: string,
): Promise<{ balance: LoyaltyPointsBalance; record: ShopifyCredentialRecord }> {
  const delta = num(addAmount);
  if (delta <= 0) throw new Error("invalid_add_amount");
  return await mutateLoyaltyPointsBalance(supabase, record, customerGid, (current) => {
    const next = { ...current };
    if (next.status !== "active") {
      next.status = "active";
      next.amount = 0;
      next.reserved = null;
    }
    next.currency = currency || next.currency || "THB";
    next.amount = num(next.amount) + delta;
    return next;
  });
}

const DISCOUNT_USAGE_QUERY = `
query LoyaltyDiscountUsage($id: ID!) {
  codeDiscountNode(id: $id) {
    id
    codeDiscount {
      ... on DiscountCodeBasic {
        asyncUsageCount
      }
    }
  }
}`;

export type DiscountNodeUsageLookup =
  | { kind: "query_failed" }
  | { kind: "missing" }
  | { kind: "found"; usage: number };

export async function lookupDiscountNodeUsage(
  supabase: SupabaseClient,
  record: ShopifyCredentialRecord,
  discountNodeId: string,
): Promise<{ lookup: DiscountNodeUsageLookup; record: ShopifyCredentialRecord }> {
  const { body, record: nextRecord, ok } = await shopifyAdminGraphql(
    supabase,
    record,
    "2024-04",
    DISCOUNT_USAGE_QUERY,
    { id: discountNodeId },
  );
  if (!ok || body.errors) return { lookup: { kind: "query_failed" }, record: nextRecord };
  const node = (body.data as Record<string, unknown> | undefined)?.codeDiscountNode as
    | Record<string, unknown>
    | undefined;
  if (!node) return { lookup: { kind: "missing" }, record: nextRecord };
  const codeDiscount = node?.codeDiscount as Record<string, unknown> | undefined;
  return { lookup: { kind: "found", usage: num(codeDiscount?.asyncUsageCount) }, record: nextRecord };
}

const DISCOUNT_CODE_DELETE = `
mutation LoyaltyDiscountCodeDelete($id: ID!) {
  discountCodeDelete(id: $id) {
    deletedCodeDiscountId
    userErrors { field message }
  }
}`;

export async function deleteDiscountCodeNode(
  supabase: SupabaseClient,
  record: ShopifyCredentialRecord,
  discountNodeId: string,
): Promise<ShopifyCredentialRecord> {
  const { body, record: nextRecord, ok } = await shopifyAdminGraphql(
    supabase,
    record,
    "2024-04",
    DISCOUNT_CODE_DELETE,
    { id: discountNodeId },
  );
  const del = (body.data as Record<string, unknown> | undefined)?.discountCodeDelete as
    | Record<string, unknown>
    | undefined;
  const userErrors = del?.userErrors as Array<Record<string, unknown>> | undefined;
  if (!ok || body.errors || (userErrors && userErrors.length > 0)) {
    console.warn("[shopify-points-balance] discountCodeDelete failed", { discountNodeId, body });
  }
  return nextRecord;
}

const DISCOUNT_BY_CODE_QUERY = `
query LoyaltyDiscountByCode($code: String!) {
  codeDiscountNodeByCode(code: $code) {
    id
    codeDiscount {
      ... on DiscountCodeBasic {
        title
      }
    }
  }
}`;

export async function findDiscountNodeByCode(
  supabase: SupabaseClient,
  record: ShopifyCredentialRecord,
  code: string,
): Promise<{ id: string; title: string | null; record: ShopifyCredentialRecord } | null> {
  const { body, record: nextRecord, ok } = await shopifyAdminGraphql(
    supabase,
    record,
    "2024-04",
    DISCOUNT_BY_CODE_QUERY,
    { code },
  );
  if (!ok || body.errors) return null;
  const node = (body.data as Record<string, unknown> | undefined)?.codeDiscountNodeByCode as
    | Record<string, unknown>
    | undefined;
  if (!node?.id) return null;
  const codeDiscount = node.codeDiscount as Record<string, unknown> | undefined;
  const title = codeDiscount?.title != null ? String(codeDiscount.title) : null;
  return { id: String(node.id), title, record: nextRecord };
}

export type ReservationPrepResult = {
  record: ShopifyCredentialRecord;
  balance: LoyaltyPointsBalance | null;
  reuse: { code: string; amount: number } | null;
};

export async function prepareBalanceForReservation(
  supabase: SupabaseClient,
  record: ShopifyCredentialRecord,
  customerGid: string,
): Promise<ReservationPrepResult> {
  const read = await readLoyaltyPointsBalance(supabase, record, customerGid);
  let cred = read.record;
  const balance = read.balance;
  if (!balance?.reserved) {
    return { record: cred, balance, reuse: null };
  }

  const reserved = balance.reserved;
  const reservedAt = new Date(reserved.reserved_at).getTime();
  const ageMs = Number.isFinite(reservedAt) ? Date.now() - reservedAt : RESERVATION_REUSE_MS + 1;
  if (ageMs < RESERVATION_REUSE_MS) {
    return {
      record: cred,
      balance,
      reuse: { code: reserved.code, amount: reserved.amount },
    };
  }

  const { lookup, record: afterLookup } = await lookupDiscountNodeUsage(
    supabase,
    cred,
    reserved.discount_node_id,
  );
  cred = afterLookup;

  if (lookup.kind === "query_failed") {
    return {
      record: cred,
      balance,
      reuse: { code: reserved.code, amount: reserved.amount },
    };
  }

  if (lookup.kind === "missing" || (lookup.kind === "found" && lookup.usage > 0)) {
    const cleared = await mutateLoyaltyPointsBalance(supabase, cred, customerGid, (current) => {
      if (!current.reserved) return current;
      return { ...current, reserved: null };
    });
    return { record: cleared.record, balance: cleared.balance, reuse: null };
  }

  cred = await deleteDiscountCodeNode(supabase, cred, reserved.discount_node_id);
  const reclaimed = await mutateLoyaltyPointsBalance(supabase, cred, customerGid, (current) => {
    const r = current.reserved;
    if (!r) return current;
    const next = { ...current };
    next.amount = num(next.amount) + num(r.amount);
    next.reserved = null;
    if (next.status !== "active") next.status = "active";
    return next;
  });
  return { record: reclaimed.record, balance: reclaimed.balance, reuse: null };
}

export function findLoyaltyRedemptionApplication(
  order: Record<string, unknown>,
): Record<string, unknown> | null {
  const apps = order.discount_applications;
  if (!Array.isArray(apps)) return null;
  const hit = apps.find(
    (a) =>
      String((a as Record<string, unknown>)?.title || "").trim().toLowerCase() ===
        LOYALTY_DISCOUNT_TITLE.toLowerCase(),
  );
  return (hit as Record<string, unknown>) ?? null;
}

export function fixedAmountFromDiscountApplication(app: Record<string, unknown> | null): number | null {
  if (!app) return null;
  if (String(app.value_type || "").toLowerCase() !== "fixed_amount") return null;
  const amount = num(app.value);
  return amount > 0 ? amount : null;
}

export function fixedAmountForDiscountCode(
  order: Record<string, unknown>,
  code: string,
): number | null {
  const apps = order.discount_applications;
  if (!Array.isArray(apps)) return null;
  const normalized = code.trim().toUpperCase();
  for (const a of apps) {
    const app = a as Record<string, unknown>;
    const type = String(app.type || "").toLowerCase();
    const appCode = String(app.code || "").trim().toUpperCase();
    if (type === "discount_code" && appCode === normalized) {
      return fixedAmountFromDiscountApplication(app);
    }
  }
  return null;
}

export type ApplyPaidOrderInput = {
  orderId: string;
  customerGid: string | null;
  discountCodes: string[];
  order: Record<string, unknown>;
};

async function applyWidgetLineToOwnerBalance(
  supabase: SupabaseClient,
  record: ShopifyCredentialRecord,
  customerGid: string,
  orderId: string,
  widgetApplied: number,
): Promise<{ record: ShopifyCredentialRecord; result: Record<string, unknown> }> {
  let cred = record;
  const read = await readLoyaltyPointsBalance(supabase, cred, customerGid);
  cred = read.record;
  if (read.balance?.processed_order_ids?.includes(orderId)) {
    return { record: cred, result: { skipped: true, reason: "already_processed_widget", order_id: orderId } };
  }

  const result = await mutateLoyaltyPointsBalance(supabase, cred, customerGid, (current) => {
    const next = { ...(current ?? emptyBalance()) };
    if (next.processed_order_ids.includes(orderId)) return next;
    if (next.status === "active") {
      next.amount = Math.max(0, num(next.amount) - widgetApplied);
    }
    if (next.amount <= 0 && !next.reserved) next.status = "consumed";
    next.processed_order_ids = [...next.processed_order_ids, orderId].slice(-20);
    return next;
  });
  return {
    record: result.record,
    result: { success: true, path: "widget", widget_applied: widgetApplied, after: result.balance },
  };
}

async function settleOwnerReservationCode(
  supabase: SupabaseClient,
  record: ShopifyCredentialRecord,
  ownerGid: string,
  orderId: string,
  code: string,
  order: Record<string, unknown>,
  discountNodeId: string,
): Promise<{ record: ShopifyCredentialRecord; result: Record<string, unknown> }> {
  let cred = record;
  const read = await readLoyaltyPointsBalance(supabase, cred, ownerGid);
  cred = read.record;
  const normalizedCode = code.trim().toUpperCase();
  const reservedCode = read.balance?.reserved?.code?.trim().toUpperCase() ?? null;

  if (read.balance?.processed_order_ids?.includes(orderId)) {
    return { record: cred, result: { skipped: true, reason: "already_processed_owner", order_id: orderId, code } };
  }
  if (!reservedCode || reservedCode !== normalizedCode) {
    cred = await deleteDiscountCodeNode(supabase, cred, discountNodeId);
    return { record: cred, result: { skipped: true, reason: "reserved_code_mismatch", code, owner: ownerGid } };
  }

  const reservedNodeId = read.balance?.reserved?.discount_node_id ?? null;
  const result = await mutateLoyaltyPointsBalance(supabase, cred, ownerGid, (current) => {
    const next = { ...(current ?? emptyBalance()) };
    if (next.processed_order_ids.includes(orderId)) return next;
    if (next.reserved?.code?.trim().toUpperCase() !== normalizedCode) return next;

    const reserved = next.reserved!;
    const applied = fixedAmountForDiscountCode(order, code) ?? reserved.amount;
    const unused = Math.max(0, num(reserved.amount) - num(applied));
    if (next.status === "active") next.amount = num(next.amount) + unused;
    next.reserved = null;
    if (next.amount <= 0 && !next.reserved) next.status = "consumed";
    next.processed_order_ids = [...next.processed_order_ids, orderId].slice(-20);
    return next;
  });
  cred = result.record;
  if (reservedNodeId) cred = await deleteDiscountCodeNode(supabase, cred, reservedNodeId);

  return {
    record: cred,
    result: { success: true, path: "owner_reservation", code, owner: ownerGid, after: result.balance },
  };
}

export async function applyPaidOrderToLoyaltyBalance(
  supabase: SupabaseClient,
  record: ShopifyCredentialRecord,
  input: ApplyPaidOrderInput,
): Promise<Record<string, unknown>> {
  const orderId = String(input.orderId);
  let cred = record;
  const outcomes: Record<string, unknown>[] = [];

  const loyaltyApp = findLoyaltyRedemptionApplication(input.order);
  const widgetApplied = fixedAmountFromDiscountApplication(loyaltyApp);

  if (input.customerGid && widgetApplied != null) {
    try {
      const widget = await applyWidgetLineToOwnerBalance(
        supabase,
        cred,
        input.customerGid,
        orderId,
        widgetApplied,
      );
      cred = widget.record;
      outcomes.push(widget.result);
    } catch (err) {
      outcomes.push({
        success: false,
        path: "widget",
        reason: "balance_update_failed",
        message: err instanceof Error ? err.message : String(err),
      });
    }
  }

  const orderCodes = input.discountCodes.map((c) => c.trim()).filter(Boolean);
  for (const code of orderCodes) {
    if (!code.toUpperCase().startsWith(LOYALTY_CODE_PREFIX)) continue;

    const node = await findDiscountNodeByCode(supabase, cred, code);
    if (!node) continue;
    cred = node.record;

    const parsed = node.title ? parseLoyaltyReservationDiscountTitle(node.title) : null;
    if (!parsed) continue;

    const ownerGid = customerGidFromId(parsed.ownerNumericId);
    try {
      const settled = await settleOwnerReservationCode(
        supabase,
        cred,
        ownerGid,
        orderId,
        code,
        input.order,
        node.id,
      );
      cred = settled.record;
      outcomes.push(settled.result);
    } catch (err) {
      outcomes.push({
        success: false,
        path: "owner_reservation",
        code,
        reason: "balance_update_failed",
        message: err instanceof Error ? err.message : String(err),
      });
    }
  }

  if (!outcomes.length) {
    return { success: true, skipped: true, reason: "no_loyalty_discount_to_apply", order_id: orderId };
  }

  return { success: true, order_id: orderId, outcomes };
}

export async function linkShopifyCustomerToMember(
  supabase: SupabaseClient,
  merchantId: string,
  userId: string,
  shopifyCustomerId: string,
): Promise<{ ok: true } | { ok: false; error: "shopify_customer_conflict" }> {
  const numericId = numericCustomerId(shopifyCustomerId);
  const { data: conflicts, error: conflictError } = await supabase
    .from("user_accounts")
    .select("id")
    .eq("merchant_id", merchantId)
    .filter("marketplace_external_ids->>shopify", "eq", numericId)
    .neq("id", userId)
    .limit(1);
  if (conflictError || (conflicts && conflicts.length > 0)) {
    return { ok: false, error: "shopify_customer_conflict" };
  }

  const { data: row } = await supabase
    .from("user_accounts")
    .select("marketplace_external_ids")
    .eq("id", userId)
    .eq("merchant_id", merchantId)
    .maybeSingle();
  const marketplace = (row?.marketplace_external_ids || {}) as Record<string, unknown>;
  const next = { ...marketplace, shopify: numericId };
  await supabase
    .from("user_accounts")
    .update({ marketplace_external_ids: next, updated_at: new Date().toISOString() })
    .eq("id", userId)
    .eq("merchant_id", merchantId);
  return { ok: true };
}

export async function findShopifyCustomerGidByIdentity(
  supabase: SupabaseClient,
  record: ShopifyCredentialRecord,
  identity: { email?: string | null; phone?: string | null },
): Promise<{ gid: string | null; record: ShopifyCredentialRecord }> {
  const phone = identity.phone?.trim();
  const email = identity.email?.trim();
  const queries: string[] = [];
  if (phone) {
    queries.push(`phone:${phone}`);
    if (phone.startsWith("+")) queries.push(`phone:${phone.slice(1)}`);
  }
  if (email) queries.push(`email:${email}`);

  let cred = record;
  for (const q of queries) {
    const { body, record: next, ok } = await shopifyAdminGraphql(
      supabase,
      cred,
      "2024-04",
      `query ($q: String!) { customers(first: 1, query: $q) { nodes { id } } }`,
      { q },
    );
    cred = next;
    if (!ok || body.errors) continue;
    const nodes = ((body.data as Record<string, unknown>)?.customers as Record<string, unknown>)
      ?.nodes as Array<Record<string, unknown>> | undefined;
    const id = nodes?.[0]?.id;
    if (id) return { gid: String(id), record: cred };
  }
  return { gid: null, record: cred };
}
