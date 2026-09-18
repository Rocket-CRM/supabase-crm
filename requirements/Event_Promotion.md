# Event Promotion

Merchant-level promotions for **event orders**: map to specific events or activity groups, evaluate cart rules, and grant freebies, bill discounts, and free rewards with per-user claim limits.

Owner surfaces: loyalty-admin (**Event promotions**, event order preview), Postgres calculators on order commit (**Order_Booking.md**)

## Concept

**Event promo** — Merchant-owned definition (`event_promo`) with name, `eval_mode`, claim caps, optional admin folder, and active flag. Legacy `event_id` on the promo row is not the primary scope — applicability lives in mappings.

**Mapping** — Links a promo to either one `event_id` or one `activity_group` string so new events in a group inherit promos without remapping.

**Rule** — Ordered condition (`condition_definition` JSON) with one or more **outcomes** (freebie, `bill_discount_pct`, `bill_discount_fixed`, `free_reward`).

**Claim ledger** — `event_promo_claim` records consumption per user, event, promo, and **rule** (supports `eval_mode=all` with multiple rules per transaction).

**Folder** — Optional list grouping (`event_promo_folder`) for admin UI only; calculator ignores `folder_id`.

## Rules

- Promo applies when the order’s event has a direct event mapping **or** its `activity_group` matches a group mapping.
- **Claim limits** — `max_claims_per_user_total` and `max_claims_per_user_per_event` are enforced as **per-rule budgets**; exhausted rules skip remaining outcomes on that rule.
- **`eval_mode=highest`** — First passing rule by `rule_order` wins (single rule applied).
- **`eval_mode=all`** — Every passing rule applies until limits exhausted; multiple `rule_id` claims per transaction allowed.
- **Outcomes** — Applied in `outcome_order`; freebie/reward outcomes consume quantity units; bill discounts consume one unit.
- **Scalable freebies** — When `outcome_scalable=true`, quantity uses `fn_calc_promo_set_count` × `outcome_quantity`, clamped by limits; `compound` conditions do not scale; `tiered_freebie_pool` uses a separate path.
- **Deactivate vs delete** — Promos with claims must be deactivated (`bff_toggle_event_promo`); hard delete only when no claims.
- **Rule delete protection** — Cannot remove a rule `id` from upsert payload if `event_promo_claim` references that `rule_id` (`RULE_HAS_CLAIMS`).
- **Mappings** — Rebuilt on full config save (delete-all + reinsert); rules/outcomes use diff upsert to preserve claim FKs.

## Journeys

### Admin journey

| Knob | Effect |
| --- | --- |
| Mappings (event / activity group) | Which orders see the promo |
| Rules + outcomes | Qualification and rewards |
| `eval_mode` | Highest rule vs all passing rules |
| Claim caps | Total and per-event budgets per rule |
| `is_active` | Live vs disabled |
| Folder | List organization only |

| Page | Owning repo | BFF / RPC |
| --- | --- | --- |
| Event promotions (merchant list) | loyalty-admin | `bff_list_event_promos(NULL)`, folder BFFs |
| Promo editor | loyalty-admin | `bff_get_event_promo_details`, `bff_upsert_event_promo_config` |
| Event-scoped list (legacy) | loyalty-admin | `bff_list_event_promos(p_event_id)` |
| Order preview | loyalty-admin | `bff_preview_event_promos` |

1. Open **Event promotions** — list shows mappings, rule counts, claim counts, folder.
2. Create promo — set mappings (events and/or activity groups), rules with outcomes, limits, `eval_mode`.
3. Save via `bff_upsert_event_promo_config` (diff on rule/outcome ids; mapping rewrite).
4. Toggle active or deactivate instead of delete when claims exist.
5. Optional: organize folders (`bff_list_event_promo_folders`, upsert/delete folder, `bff_set_event_promo_folder`).
6. During event order build, **preview** calls calculator before submit.

### Member journey

Member journey: **none** as a dedicated surface — benefits appear as discounted lines, freebies, or rewards on the **event order** checkout path (admin-operated sales flow). Members do not self-serve promo configuration.

## System

### Data model

| Table | Role |
| --- | --- |
| `event_promo` | Promo master (`eval_mode`, limits, `folder_id`, `is_active`; legacy `event_id` nullable) |
| `event_promo_folder` | Admin folders; unique `(merchant_id, name)` |
| `event_promo_rule` | Ordered rules + legacy flat `outcome_*` mirror |
| `event_promo_rule_outcome` | Ordered outcomes per rule |
| `event_promo_mapping` | `event` or `activity_group` scope |
| `event_promo_claim` | Claim ledger (`event_id`, `rule_id`, transaction link) |

### Functions

| Function | Role |
| --- | --- |
| `bff_list_event_promos(p_event_id)` | `NULL` = merchant list; event id = applicable promos |
| `bff_list_event_promo_folders` / `bff_upsert_event_promo_folder` / `bff_delete_event_promo_folder` / `bff_set_event_promo_folder` | Folder CRUD and bulk assign |
| `bff_get_event_promo_details` | `new` template or `{ promo, rules[], mappings[] }` with `outcomes[]` |
| `bff_upsert_event_promo_config` | Primary save; diff rules/outcomes; mapping rewrite |
| `bff_upsert_event_promo_with_rules` | Legacy single-event wrapper + one event mapping |
| `bff_preview_event_promos` | Calculator preview for UI |
| `bff_toggle_event_promo` / `bff_delete_event_promo` | Active flag; delete if no claims |
| `bff_report_event_promos` / `bff_report_event_promos_rows` | Reporting |
| `fn_calc_event_promos` | Match promos, evaluate rules, apply outcomes and limits |
| `fn_calc_promo_set_count` | Scalable quantity helper |
| `fn_evaluate_promo_condition` | Boolean condition evaluation |
| `fn_apply_event_promos` | Persist claims, freebie lines, ledger discounts |

**Upsert error codes (representative):** `RULE_HAS_CLAIMS`, `INVALID_RULE_ID`, `INVALID_OUTCOME_ID`, `PROMO_HAS_CLAIMS`, `INVALID_MAPPINGS`, `INVALID_PROMO_RULE`, mapping validation codes.

**Permission:** folder assign requires `check_admin_permission('event', 'update')`.

### Flows

```
Order preview → bff_preview_event_promos → fn_calc_event_promos
Order commit → fn_apply_event_promos (claims + purchase_ledger / line items)
```

Activity-group inheritance: new events with matching `activity_group` pick up promos without editing mappings.

### Known gaps

- `event_promo_folder` BFFs exist live but are omitted from `REGISTRY_SUPABASE.md` grep snapshot — verify registry on regen.
- Legacy `bff_upsert_event_promo_with_rules` still used for event-tethered flows; merchant-level editor prefers `bff_upsert_event_promo_config`.

## Related

- **Order_Booking.md** — Event order lines, preview, and commit hooks for promos.
- **Syngenta_Events.md** — Event catalog and activity groups when promos map to groups.
- **Purchase_Transaction.md** — Bill discounts written to `purchase_ledger` on apply.
