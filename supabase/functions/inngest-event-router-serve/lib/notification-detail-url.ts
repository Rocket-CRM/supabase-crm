/**
 * Loyalty-app deep-link builder — ported from crm-event-processors/src/utils/detail-url.ts
 * (production path only; local dev mode dropped in the edge runtime).
 *
 * Contract: Rocket-CRM/loyalty-user (commit 08226a3)
 * Production: https://{merchant_code}.rocket-loyalty.app/?page=…
 */

export interface DetailUrlSpec {
  page: "history" | "wallet";
  entity?: string;
  filter?: string;
  tab?: string;
  id?: string;
  action?: "use";
}

const LOYALTY_APP_HOST = Deno.env.get("LOYALTY_APP_HOST") || "rocket-loyalty.app";

function appendQuery(base: string, params: URLSearchParams): string {
  const qs = params.toString();
  return qs ? `${base}?${qs}` : base;
}

export function buildDetailUrl(merchantCode: string, spec: DetailUrlSpec): string {
  const params = new URLSearchParams();
  const base = `https://${merchantCode}.${LOYALTY_APP_HOST}/`;

  if (spec.page === "history") {
    params.set("page", "history");
    params.set("entity", spec.entity!);
    if (spec.filter) params.set("filter", spec.filter);
  } else {
    params.set("page", "wallet");
    params.set("tab", spec.tab!);
    if (spec.action) params.set("action", spec.action);
  }
  if (spec.id) params.set("id", spec.id);

  return appendQuery(base, params);
}

export function buildSignupDetailUrl(merchantCode: string): string {
  return `https://${merchantCode}.${LOYALTY_APP_HOST}/`;
}

export function detailUrlSpecForNotification(
  eventKey: string,
  subEvent: string,
  payload: Record<string, unknown>,
): DetailUrlSpec | "signup_home" | null {
  const id = (key: string): string | undefined => {
    const v = payload[key];
    return typeof v === "string" && v.length > 0 ? v : undefined;
  };

  if (eventKey === "signup" && subEvent === "signup") {
    return "signup_home";
  }

  if (eventKey === "purchase") {
    const purchaseId = id("purchase_id");
    if (!purchaseId) return null;
    return { page: "history", entity: "purchases", id: purchaseId };
  }

  if (eventKey === "purchase_item" && subEvent === "completed") {
    const purchaseId = id("purchase_id");
    if (!purchaseId) return null;
    return { page: "history", entity: "purchases", id: purchaseId };
  }

  if (eventKey === "currency") {
    if (subEvent === "expiring_soon") {
      return { page: "history", entity: "currency", filter: "points" };
    }
    const walletId = id("wallet_ledger_id");
    if (!walletId) return null;
    return { page: "history", entity: "currency", filter: "points", id: walletId };
  }

  if (eventKey === "tier") {
    const tierChangeId = id("tier_change_ledger_id");
    if (!tierChangeId) return null;
    return { page: "history", entity: "tier", id: tierChangeId };
  }

  if (eventKey === "redemption") {
    const redemptionId = id("redemption_id");
    switch (subEvent) {
      case "issued":
        if (!redemptionId) return null;
        return { page: "wallet", tab: "rewards", id: redemptionId, action: "use" };
      case "used":
        if (!redemptionId) return null;
        return { page: "history", entity: "reward", filter: "used", id: redemptionId };
      case "cancelled":
        if (!redemptionId) return null;
        return { page: "history", entity: "reward", filter: "redeemed", id: redemptionId };
      case "entitlement_used":
      case "entitlement_expired":
        if (!redemptionId) return null;
        return { page: "wallet", tab: "packages", id: redemptionId };
      case "package_granted":
        return { page: "wallet", tab: "packages" };
      case "expiring_soon":
        if (!redemptionId) return { page: "wallet", tab: "rewards" };
        return { page: "wallet", tab: "rewards", id: redemptionId };
      default:
        return null;
    }
  }

  if (eventKey === "receipt") {
    const receiptId = id("receipt_upload_id");
    if (!receiptId) return null;
    return { page: "history", entity: "upload_receipt", id: receiptId };
  }

  return null;
}

export function buildNotificationDetailUrl(
  merchantCode: string,
  eventKey: string,
  subEvent: string,
  payload: Record<string, unknown>,
): string | null {
  const spec = detailUrlSpecForNotification(eventKey, subEvent, payload);
  if (spec === null) return null;
  if (spec === "signup_home") return buildSignupDetailUrl(merchantCode);
  return buildDetailUrl(merchantCode, spec);
}
