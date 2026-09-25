/**
 * Flat chokepoint domain event payload as written to `chokepoint_event_outbox.payload`
 * by `fn_chokepoint_emit_event`. Superset across all domains — each router validates
 * the fields its domain requires.
 */
export interface ChokepointEvent {
  event?: string;
  merchant_id?: string;
  user_id?: string | null;
  // purchase / purchase_item
  purchase_id?: string;
  item_id?: string;
  earn_currency?: boolean;
  status?: string;
  item_status?: string;
  final_amount?: number;
  total_amount?: number;
  seller_id?: string | null;
  store_id?: string | null;
  store_code?: string | null;
  // purchase_item enrichment (2026-07-08, mission SKU/product scoping)
  sku_id?: string | null;
  product_id?: string | null;
  category_id?: string | null;
  brand_id?: string | null;
  transaction_amount?: number | null;
  // wallet
  wallet_ledger_id?: string;
  currency?: string;
  component?: string;
  transaction_type?: string;
  amount?: number;
  source_type?: string;
  source_id?: string;
  description?: string;
  target_entity_id?: string | null;
  /** Ticket unit expand: chokepoint emits one event per unit with amount=1. */
  unit_index?: number | string;
  unit_total?: number | string;
  wallet_code?: string;
  // tier_change
  tier_change_ledger_id?: string;
  from_tier_id?: string | null;
  to_tier_id?: string | null;
  change_type?: string;
  change_reason?: string;
  // user
  user_event_type?: string;
  changes?: Record<string, unknown>;
  actor?: Record<string, unknown>;
  skip_cdc?: boolean;
  user_after?: Record<string, unknown>;
  // redemption
  redemption_id?: string;
  redemption_code?: string;
  reward_id?: string;
  qty?: number;
  used_qty?: number;
  used_at?: string;
  use_expire_date?: string;
  cancelled_reason?: string;
  points_deducted?: number;
  qty_change?: number;
  // common
  metadata?: Record<string, unknown>;
  occurred_at?: string;
  source?: string;
  [key: string]: unknown;
}

export function isTruthy(value: unknown): boolean {
  return value === true || value === "true" || value === 1 || value === "1";
}
