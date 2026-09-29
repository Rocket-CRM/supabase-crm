/**
 * Flex Template renderer — ported verbatim from crm-event-processors/src/utils/flex-template.ts.
 *
 * Templates live in `notification_template.flex_template` as raw LINE Flex JSON with:
 *   1. `_field` markers — element dropped when the field isn't selected.
 *   2. `${field_name}` placeholders — substituted from {...payload, ...enrichments};
 *      `_field`-marked groups with unresolved tokens are dropped whole.
 */

const PLACEHOLDER_GLOBAL_RE = /\$\{([a-zA-Z0-9_]+)\}/g;
const PLACEHOLDER_TEST_RE = /\$\{[a-zA-Z0-9_]+\}/;
const FIELD_MARKER = "_field";

/** Enriched by the notification router; not part of the admin field picker. */
const SYSTEM_ENRICHED_FIELDS = new Set(["detail_url", "hero_image_url"]);

function isFieldSelected(
  fieldName: string,
  selectedFields: Set<string>,
  lookup: Record<string, unknown>,
): boolean {
  if (selectedFields.has(fieldName)) return true;
  if (!SYSTEM_ENRICHED_FIELDS.has(fieldName)) return false;
  const value = lookup[fieldName];
  return value !== null && value !== undefined && value !== "";
}

type JsonValue = string | number | boolean | null | JsonValue[] | { [key: string]: JsonValue };

function isPlainObject(value: unknown): value is Record<string, JsonValue> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

function substitute(input: string, lookup: Record<string, unknown>): string {
  return input.replace(PLACEHOLDER_GLOBAL_RE, (_match, name) => {
    const value = lookup[name];
    if (value === null || value === undefined) return _match;
    return String(value);
  });
}

function hasUnresolvedPlaceholder(value: JsonValue): boolean {
  if (typeof value === "string") return PLACEHOLDER_TEST_RE.test(value);
  if (Array.isArray(value)) return value.some(hasUnresolvedPlaceholder);
  if (isPlainObject(value)) {
    return Object.values(value).some(hasUnresolvedPlaceholder);
  }
  return false;
}

function walk(
  node: JsonValue,
  lookup: Record<string, unknown>,
  selectedFields: Set<string>,
): JsonValue | null {
  if (typeof node === "string") {
    return substitute(node, lookup);
  }

  if (typeof node === "number" || typeof node === "boolean" || node === null) {
    return node;
  }

  if (Array.isArray(node)) {
    const out: JsonValue[] = [];
    for (const child of node) {
      const rendered = walk(child, lookup, selectedFields);
      if (rendered !== null) out.push(rendered);
    }
    return out;
  }

  if (isPlainObject(node)) {
    const fieldMarker = node[FIELD_MARKER];
    if (typeof fieldMarker === "string" && !isFieldSelected(fieldMarker, selectedFields, lookup)) {
      return null;
    }

    const out: Record<string, JsonValue> = {};
    for (const [key, value] of Object.entries(node)) {
      if (key === FIELD_MARKER) continue;
      const rendered = walk(value, lookup, selectedFields);
      if (rendered !== null) {
        out[key] = rendered;
      }
    }

    if (typeof fieldMarker === "string" && hasUnresolvedPlaceholder(out as JsonValue)) {
      return null;
    }

    return out;
  }

  return node;
}

export interface RenderInput {
  template: Record<string, unknown>;
  payload: Record<string, unknown>;
  selectedFields: string[];
  enrichments?: Record<string, unknown>;
}

export function renderFlexFromTemplate(input: RenderInput): Record<string, unknown> | null {
  const lookup = { ...input.payload, ...(input.enrichments || {}) };
  const selectedSet = new Set(input.selectedFields || []);

  const rendered = walk(input.template as JsonValue, lookup, selectedSet);
  if (rendered === null) return null;
  if (!isPlainObject(rendered)) return null;

  if (hasUnresolvedPlaceholder(rendered as JsonValue)) {
    return null;
  }

  return rendered as Record<string, unknown>;
}

export function defaultAltText(eventKey: string, subEvent: string): string {
  const map: Record<string, string> = {
    "purchase.created": "We received your order",
    "purchase.completed": "Your purchase is confirmed",
    "purchase.cancelled": "Your purchase was cancelled",
    "purchase.refunded": "Your refund has been processed",
    "purchase_item.completed": "An item in your order is ready",
    "currency.earned": "You earned currency",
    "currency.burned": "You spent currency",
    "currency.expired": "Currency expired",
    "currency.expiring_soon": "Points expiring soon",
    "tier.upgrade": "Your tier has been upgraded",
    "tier.initial": "Welcome to your starting tier",
    "tier.downgrade": "Your tier has changed",
    "signup.signup": "Welcome",
    "redemption.issued": "Your reward is ready",
    "redemption.used": "Reward used",
    "redemption.cancelled": "Reward cancelled",
    "redemption.entitlement_used": "Reward usage updated",
    "redemption.entitlement_expired": "Reward has expired",
    "redemption.expiring_soon": "Reward expiring soon",
    "redemption.package_granted": "New reward package",
    "receipt.submitted": "ได้รับใบเสร็จแล้ว รอแอดมินอนุมัติ",
    "receipt.rejected": "ใบเสร็จไม่ผ่านการอนุมัติ",
    "referral.completed": "You earned a referral reward",
    "referral.friend_rewarded": "You received a referral reward",
  };

  return map[`${eventKey}.${subEvent}`] || "You have a new notification";
}
