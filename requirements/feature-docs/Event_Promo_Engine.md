# Event Promo Engine

## Overview

The Event Promo Engine calculates and applies promotional outcomes (freebies and bill-level discounts) to event orders **synchronously at order creation**. It is completely separate from the currency earning pipeline (which is event-driven).

**Scope**: Promos are configured per event (`syngenta_events_master`). Each promo has one or more rules, each with a condition and an outcome.

---

## Concepts

| Term | Definition |
|---|---|
| **Promo** (`event_promo`) | A promotion associated with one event. Has evaluation mode and per-user claim limit. |
| **Rule** (`event_promo_rule`) | One condition + one outcome within a promo. Multi-rule promos represent escalating tiers. |
| **Condition** | JSONB definition of what must be true in the order to trigger the outcome. |
| **Outcome** | What the customer gets: a freebie item or a bill-level discount. |
| **Claim** (`event_promo_claim`) | Record of a promo outcome being triggered for a user on a specific order. Used for per-user limit enforcement. |

---

## Promo Structure

### `event_promo` (header)

| Column | Notes |
|---|---|
| `event_id` | FK → `syngenta_events_master.id`. NOT NULL. |
| `name`, `description` | Display fields. |
| `eval_mode` | `'highest'`: pick best (highest `rule_order`) qualifying rule only. `'all'`: apply every qualifying rule. |
| `max_claims_per_user` | INT. NULL = unlimited. For scalable combo promos, this is the cap on set count. |
| `sort_order` | Evaluation order across promos for the same event. |
| `is_active` | Standard boolean. |

### `event_promo_rule` (detail)

| Column | Notes |
|---|---|
| `promo_id` | FK → `event_promo.id` ON DELETE CASCADE. |
| `rule_order` | Ascending. Higher value = better outcome. Used by `eval_mode='highest'`. |
| `rule_name` | Display label, e.g. "≥5 pieces", "Spend 5,000 THB". |
| `condition_definition` | JSONB. See condition types below. |
| `outcome_type` | `'freebie'`, `'bill_discount_pct'`, `'bill_discount_fixed'`. |
| `outcome_sku_id` | FK → `product_sku_master.id`. NULL for custom freebies. |
| `outcome_sku_code`, `outcome_product_name`, `outcome_variant_name` | Always stored explicitly. For master: populated at config time from master. For custom: entered inline. |
| `outcome_quantity` | Fixed quantity for non-scalable rules. |
| `outcome_scalable` | Boolean. If true: quantity = floor(set_count), capped by `max_claims_per_user`. |
| `outcome_discount_pct` | For `bill_discount_pct`: percentage (e.g. `5` = 5%). |
| `outcome_discount_fixed` | For `bill_discount_fixed`: fixed THB amount. |

### `event_promo_claim` (usage tracking)

| Column | Notes |
|---|---|
| `promo_id`, `rule_id` | What fired. |
| `user_id`, `transaction_id` | Who and which order. |
| `quantity_claimed` | For scalable promos: actual set count. |
| UNIQUE(`promo_id`, `user_id`, `transaction_id`) | One claim record per promo per order per user. |

---

## Condition Types

Conditions are stored as JSONB on `event_promo_rule.condition_definition`. Four types compose recursively.

### 1. `product_qty_threshold`

Passes when a specific SKU in the order meets a minimum quantity.

```json
{
  "type": "product_qty_threshold",
  "sku_code": "PLENUM",
  "min_qty": 5
}
```

Optional `size_filter`: matched against `purchase_items_ledger.variant_name` using case-insensitive ILIKE.

```json
{
  "type": "product_qty_threshold",
  "sku_code": "REFLEX-EVO-500",
  "min_qty": 2,
  "size_filter": "500cc"
}
```

### 2. `product_combo`

Passes when ALL specified products each meet their own minimum quantity. When `scalable: true`, the outcome quantity scales with the number of sets achievable.

```json
{
  "type": "product_combo",
  "scalable": true,
  "items": [
    { "sku_code": "REFLEX-EVO-500", "min_qty": 2, "size_filter": "500cc" },
    { "sku_code": "AMURE-500",      "min_qty": 2, "size_filter": "500cc" },
    { "sku_code": "ORTIVA-500",     "min_qty": 2, "size_filter": "500cc" }
  ]
}
```

Set count = `floor(min(qty_i / min_qty_i))` across all items.

### 3. `spend_threshold`

Passes when `purchase_ledger.final_amount` meets a minimum.

```json
{ "type": "spend_threshold", "min_spend": 3500 }
```

### 4. `compound`

Recursive AND/OR over child conditions (any of the above types, nested).

```json
{
  "type": "compound",
  "operator": "AND",
  "items": [
    { "type": "product_qty_threshold", "sku_code": "ISABION", "min_qty": 1 },
    {
      "type": "compound",
      "operator": "OR",
      "items": [
        { "type": "product_qty_threshold", "sku_code": "BREXIL-MULTI", "min_qty": 1 },
        { "type": "product_qty_threshold", "sku_code": "BREXIL-CALBO", "min_qty": 1 }
      ]
    }
  ]
}
```

---

## Evaluation Algorithm

`fn_calc_event_promos(merchant_id, event_id, user_id, final_amount, items)`:

1. Load active promos for the event ordered by `sort_order`
2. For each promo:
   a. Count existing claims for this user (`event_promo_claim`). Skip promo if at `max_claims_per_user`
   b. Evaluate rules from highest `rule_order` down:
      - Call `fn_evaluate_promo_condition(condition_definition, items, final_amount)` (recursive)
      - `eval_mode='highest'`: take first passing rule, break
      - `eval_mode='all'`: collect all passing rules
   c. For passing rules: compute effective outcome quantity
      - Non-scalable: `outcome_quantity` (fixed)
      - Scalable: `floor(min_set_count)`, capped at `max_claims_per_user - already_claimed`
3. Return `{freebies[], bill_discounts[], total_bill_discount, adjusted_final_amount}`

`fn_apply_event_promos(merchant_id, transaction_id, user_id, promo_result)`:
1. Insert freebie rows into `purchase_items_ledger` with `item_type='freebie'`, `unit_price=0`
2. Update `purchase_ledger.discount_amount` and `final_amount` for bill discounts
3. Insert `event_promo_claim` rows
4. Write `purchase_ledger.reward_list` (the full result JSONB)

Both called within the same transaction as `api_create_manual_purchase_order`.

---

## Promo Examples (from Syngenta Use Case)

### Promo 1: Reflex Evo + Amure + Ortiva combo

**Config:**
- `event_promo`: `eval_mode='highest'`, `max_claims_per_user=2`
- `event_promo_rule` (1 row): condition = `product_combo` (3 items, each min_qty=2, 500cc); `outcome_scalable=true`; outcome = PTT Voucher 500 THB

**Evaluation example:**
- Customer orders reflex=2, amure=2, ortiva=2 → set_count = floor(min(1,1,1)) = 1 → 1 voucher
- Customer orders reflex=4, amure=4, ortiva=4 → set_count = 2 → 2 vouchers (at cap)
- Customer orders reflex=4, amure=4, ortiva=4 on second order → already_claimed=2, at cap → skipped

---

### Promo 2: Plenum quantity tiers

**Config:**
- `event_promo`: `eval_mode='highest'`
- Rule 1 (`rule_order=1`): condition = `product_qty_threshold` plenum min_qty=5; outcome = Vegetable Oils 5L
- Rule 2 (`rule_order=2`): condition = `product_qty_threshold` plenum min_qty=10; outcome = Cooking Oils 1L 1 Carton

**Evaluation:** Start from rule_order=2 (highest). plenum=5: rule 2 fails, rule 1 passes → Vegetable Oils. plenum=10: rule 2 passes → Cooking Oils only.

---

### Promo 3: Virtako quantity tiers

Same structure as Promo 2. Two rules with qty thresholds.

---

### Promo 4: Isabion + Brexil compound

**Config:**
- `event_promo`: `eval_mode='highest'`
- Rule 1 (`rule_order=1`): condition = `compound AND [isabion≥1, compound OR [brexil_multi≥1, brexil_calbo≥1]]`; outcome = Vegetable Oil 1L

---

### Promo 5: On-top spend tiers

**Config:**
- `event_promo`: `eval_mode='highest'`
- Rules (5 rows, rule_order 1–5):
  - rule_order=1: spend≥3,500 → หมวก
  - rule_order=2: spend≥5,000 → กระติกน้ำแข็ง
  - rule_order=3: spend≥12,000 → เก้าอี้สนาม
  - rule_order=4: spend≥24,000 → ชุดหม้อ
  - rule_order=5: spend≥35,000 → ไฟโซล่าเซลล์

**Evaluation:** 7,200 THB → rule 5 fails, rule 4 fails, rule 3 fails, rule 2 passes → กระติกน้ำแข็ง.

---

### Combined example

**Input:** reflex_evo=2, amure=2, ortiva=2, plenum=5, total_spend=7,200 THB

**Promo 1** fires: PTT Voucher × 1
**Promo 2** fires: Vegetable Oils 5L × 1 (rule 1 passes, rule 2 fails)
**Promo 5** fires: กระติกน้ำแข็ง × 1 (rule 2 passes)

**reward_list output:**
```json
{
  "freebies": [
    { "promo_name": "Promo 1: Reflex combo", "outcome_product_name": "PTT Voucher 500 THB", "outcome_quantity": 1 },
    { "promo_name": "Promo 2: Plenum", "outcome_product_name": "Vegetable Oils 5L", "outcome_quantity": 1 },
    { "promo_name": "Promo 5: On-top Spend", "outcome_product_name": "กระติกน้ำแข็ง", "outcome_quantity": 1 }
  ],
  "bill_discounts": [],
  "total_bill_discount": 0,
  "adjusted_final_amount": 7200
}
```

---

## Freebie Source: Master vs Custom

When configuring a promo rule outcome, admin picks one of two paths:

**Master product**: Select from `product_sku_master`. `outcome_sku_id` is populated. Name/variant/code copied from master into the rule row at config time.

**Custom freebie**: Enter name, code, variant inline on the rule. `outcome_sku_id = NULL`. The freebie exists only as a line item description — it does not exist in `product_sku_master` or `event_product_config`.

In both cases `outcome_sku_code`, `outcome_product_name`, and `outcome_variant_name` are always stored directly on the rule row, so freebie line items can be created without any additional joins.

---

## Admin BFF Functions

| Function | Purpose | Permission |
|---|---|---|
| `bff_upsert_event_promo_with_rules(p_promo_id, p_event_id, ..., p_rules[])` | Create/update promo + rules atomically | `manage_events` |
| `bff_get_event_promo_details(p_promo_id, p_mode)` | `'new'` = empty template, `'edit'` = promo + rules | authenticated |
| `bff_list_event_promos(p_event_id)` | List with rule count and total claims | authenticated |
| `bff_delete_event_promo(p_promo_id)` | Delete promo + cascade rules + claims | `manage_events` |
| `bff_preview_event_promos(p_event_id, p_user_id, p_amount, p_items)` | Read-only promo preview | authenticated |

All BFF functions: `SECURITY DEFINER`, `get_current_merchant_id()` first, `fn_response_success` / `fn_response_error` returns.

---

## Internal Functions

| Function | Security | Purpose |
|---|---|---|
| `fn_evaluate_promo_condition(condition_def, items, final_amount)` | INVOKER | Recursive JSONB condition evaluator |
| `fn_calc_event_promos(merchant_id, event_id, user_id, final_amount, items)` | INVOKER | Read-only promo calculation |
| `fn_apply_event_promos(merchant_id, transaction_id, user_id, promo_result)` | INVOKER | Write freebies + discounts + claims |

---

*Document Version: 1.0*
*Created: April 25, 2026*
*System: Supabase CRM — Event Promo Engine (Freebies + Bill Discounts)*
