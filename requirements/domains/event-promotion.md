# Event Promotion

> Per-domain reference. Read ONLY when working on this domain. For the keyword -> file map, see `_index.md`.

**Keywords:** event_promo, event_promo_rule, event_promo_rule_outcome, event_promo_mapping, event_promo_claim, event promotion, merchant promo, event promo, activity_group promo, freebie, free reward, bill discount, promo claim limit, tiered_freebie_pool, freebie_pool, pool picks, p_chosen_freebies, POOL_VALIDATION_FAILED

**Source:** `Event_Promotion.md`

**Supabase Functions (FE-callable):**

| Function | Parameters | Returns |
|---|---|---|
| `bff_list_event_promos(p_event_id?)` | Optional event filter. `NULL` lists merchant-level promos; event ID lists promos directly or activity-group applicable to that event. | Promo rows with rule count, mapping count, applicable event count, claim count, mappings |
| `bff_get_event_promo_details(p_promo_id, p_mode?)` | `p_mode='new'` returns empty template; edit mode returns promo, rules with `outcomes[]`, mappings. Legacy flat rule `outcome_*` fields mirror `outcomes[0]`. | `{ promo, rules[], mappings[] }` |
| `bff_upsert_event_promo_config(p_promo_id?, p_promo, p_rules, p_mappings)` | Merchant-level promo save. **Diff-based** keyed on `event_promo_rule.id` and `event_promo_rule_outcome.id`: payload entries with `id` are UPDATED in place, without `id` are INSERTED, and DB rows missing from the payload are DELETED. Rule deletes are blocked when `event_promo_claim` rows reference them → returns `RULE_HAS_CLAIMS` with comma-joined rule names in `description`. Updates to claimed rules' non-identity fields and outcome edits/adds/removes always succeed. Missing `outcomes` synthesizes one legacy outcome; empty `outcomes` is rejected. Mappings still delete-all + reinsert. | `{ promo_id }` |
| `bff_upsert_event_promo_with_rules(p_event_id, p_promo_id?, p_promo, p_rules)` | Legacy event-level wrapper. Saves a single event mapping. | `{ promo_id }` |
| `bff_preview_event_promos(p_event_id, p_user_id, p_final_amount, p_items)` | Runs the event promo calculator for an event order preview | Freebies, bill discounts, rewards, **freebie_pools** (always present, empty array when none), total discount, adjusted amount |
| `bff_toggle_event_promo(p_promo_id, p_is_active)` | Activate/deactivate promo | Updated state |
| `bff_delete_event_promo(p_promo_id)` | Deletes only promos without claims | Error `PROMO_HAS_CLAIMS` if claims exist |
| `bff_set_event_promo_folder(p_promo_ids, p_folder_id?)` | Bulk-set `event_promo.folder_id`. Null folder uncategorises. Does not rewrite rules or mappings. | `{ updated_count, folder_id }` |
| `bff_report_event_promos(p_from, p_to, p_frequency, p_filters)` | Admin report. Filters: `promo_id`, `event_id`, `outcome_type`, `tier_id`. | Summary, time series, promo/rule/outcome breakdowns |
| `bff_report_event_promos_rows(p_from, p_to, p_filters, p_limit, p_offset, p_sort)` | Admin report drilldown. Sorts: `created_at_desc`, `created_at_asc`, `quantity_desc`, `member_name_asc`. | Claim rows and `total_count` |

**Internal Functions:**

| Function | Purpose |
|---|---|
| `fn_calc_event_promos(p_merchant_id, p_event_id, p_user_id, p_final_amount, p_items)` | Applies mapped merchant promos for the event. Evaluates rules, loops `event_promo_rule_outcome` rows in `outcome_order`, applies freebies, free rewards, bill discounts, `highest`/`all` modes, and total/per-event claim limits. **Tiered freebie pool rules** (`condition.type='tiered_freebie_pool'`) skip outcome processing and instead emit a `freebie_pools[]` entry with cap, sorted options, per-bracket `unlocked` flag, and `unit_price` resolved from `event_product_config` first then `product_sku_master.price`. Pool rules consume one claim unit and respect `eval_mode`. |
| `fn_apply_event_promos(p_merchant_id, p_transaction_id, p_user_id, p_promo_result)` | Inserts freebie purchase items, records event-aware promo claims, and applies bill discounts to `purchase_ledger`. **Also accepts `freebie_pool_picks[]` in `p_promo_result`**: inserts one `purchase_items_ledger` row per pick (`item_type='freebie'`), creates one `event_promo_claim` per pool rule with `quantity_claimed = SUM(picks)`, and merges synthetic freebie entries with `source='user_choice'` into the persisted `reward_list.freebies[]`. |
| `fn_evaluate_promo_condition(p_condition, p_items, p_final_amount)` | Evaluates condition JSON: `product_qty_threshold`, `spend_threshold`, `product_combo`, compound `AND`/`OR`. Returns `true` for `tiered_freebie_pool` (per-bracket unlock is computed inside `fn_calc_event_promos`). |

**Tables:**

| Table | Purpose |
|---|---|
| `event_promo` | Merchant-level promo definition. `event_id` is nullable legacy scope. New claim limit fields are `max_claims_per_user_total` and `max_claims_per_user_per_event`. |
| `event_promo_rule` | Ordered conditions for a promo. Legacy flat `outcome_*` fields remain for one release and mirror the first child outcome. CHECK `outcome_type ∈ {freebie, free_reward, bill_discount_pct, bill_discount_fixed, freebie_pool}`. |
| `event_promo_rule_outcome` | Ordered outcomes for a rule. Outcomes: `freebie`, `free_reward`, `bill_discount_pct`, `bill_discount_fixed`, `freebie_pool` (marker outcome paired with `condition.type='tiered_freebie_pool'`). Unique by `(rule_id, outcome_order)`. |
| `event_promo_mapping` | Scope table for where a merchant promo applies. `mapping_type='event'` uses `event_id`; `mapping_type='activity_group'` uses `activity_group`. |
| `event_promo_claim` | Claim ledger. Includes `event_id` so per-event limits can be enforced. Unique rule-level claim index supports multiple rules from the same promo in one transaction. |

**Key Business Rules:**

- Promotions are merchant-owned. Events and activity groups are applicability mappings, not promo owners.
- A promo applies to an event when the event is directly mapped or the event's `activity_group` matches a mapped activity group.
- Save activity-group mappings as activity groups, not as expanded event IDs, so future events in that group inherit the promo.
- `max_claims_per_user_total` limits the user across all mapped events for the promo.
- `max_claims_per_user_per_event` limits the user separately within each event.
- If both limits are set, both must have remaining capacity before the promo can apply.
- `eval_mode='highest'` applies the highest ordered passing rule only, then stops after that rule's outcomes.
- `eval_mode='all'` applies every passing rule until claim limits are exhausted.
- Outcomes on a qualifying rule are applied in `outcome_order`.
- Total/per-event claim limits are per-rule budgets. Freebie/free reward outcomes consume emitted quantity; bill discounts and pool rules consume one claim unit.

### Tiered Freebie Pool (user-selectable freebies)

Pool rules let the cashier pick freebies at order time from a tier-unlocked SKU set, capped by `Σ(qty × unit_price) ≤ cap_amount`. Pool definition lives in `event_promo_rule.condition_definition`:

```json
{
  "type": "tiered_freebie_pool",
  "cap":  { "basis": "invoice_total" | "fixed", "amount": null | number },
  "brackets": [ { "min_spend": number, "sku_code": string, "max_qty"?: number } ]
}
```

Outcome row is a marker: `outcome_type='freebie_pool'`, all SKU/reward/discount fields NULL, `outcome_quantity=1`, `outcome_scalable=false`.

**Save invariants** enforced by `bff_upsert_event_promo_config` (returns `INVALID_PROMO_RULE`):
- `condition.type='tiered_freebie_pool'` ⇔ outcome row is exactly one with `outcome_type='freebie_pool'`.
- `cap.basis ∈ {invoice_total, fixed}`. `fixed` requires positive `cap.amount`; `invoice_total` requires `cap.amount IS NULL`.
- `brackets` non-empty; each bracket has non-empty `sku_code` and `min_spend ≥ 0`.

**Preview output** (`bff_preview_event_promos.data.freebie_pools[]`):
- Always present; empty array when no pool rules apply.
- Each pool: `{ event_id, promo_id, promo_name, rule_id, rule_name, cap_basis, cap_amount, options[] }`.
- `cap_amount` is resolved (subtotal for `invoice_total`, literal for `fixed`).
- Each option: `{ sku_code, product_name, variant_name, unit_price, max_qty, unlocked, unlock_min_spend }`. Sorted ascending by `unlock_min_spend`. `unit_price` is `event_product_config.price` if set, else `product_sku_master.price`. `unlocked = (unit_price IS NOT NULL) AND (subtotal ≥ unlock_min_spend)`.

**Order-time picks** — `api_create_manual_purchase_order(..., p_chosen_freebies jsonb)`:
- Shape: `[ { "rule_id": uuid, "sku_code": text, "quantity": numeric }, ... ]`. Optional / `NULL` = no pool selections (back-compat).
- Server re-runs `fn_calc_event_promos` to obtain canonical pools — FE input is never trusted.
- Validates per group-by-rule: rule must exist in canonical pools; sku must appear in that pool's options with `unlocked=true` and a non-null `unit_price`; `quantity ≥ 1`; `Σ(quantity × canonical_unit_price) ≤ canonical_cap_amount`; per-user claim caps still apply.
- On failure: returns `{ success: false, code: 'POOL_VALIDATION_FAILED', description, details: { reason, rule_id, sku_code, ... } }`. The order rolls back. Subcodes in `details.reason`: `POOL_RULE_NOT_FOUND`, `POOL_SKU_NOT_IN_POOL`, `POOL_SKU_NOT_UNLOCKED`, `POOL_QTY_EXCEEDS_MAX`, `POOL_CAP_EXCEEDED`, `POOL_INVALID_PICK`, `POOL_RULE_REQUIRED`.
- On success: one `event_promo_claim` per pool rule (`quantity_claimed = SUM(picks)`), one `purchase_items_ledger` row per pick (`item_type='freebie'`, `unit_price=0`), and `purchase_ledger.reward_list.freebies[]` includes synthetic entries with `source='user_choice'` (engine-granted entries omit `source` or carry `source='engine'`).
- Pool picks do not affect bill `discount_amount` / `final_amount`; they are physical inventory, not discounts.

---
