# Purchase Line-Item Earning — Implementation Plan

> Handoff document. Read in full at the start of the new thread before any DB or code change.
> Lives outside the `.plan.md` ignore pattern so it remains @-referenceable.
>
> **Mandatory reading before starting work:**
> - `requirements/architecture/event-chokepoints.md` (chokepoint pattern, no-wrappers rule, Phase 1 / Phase 2 split)
> - `.cursor/rules/00-core.mdc` and the routing map (08, 09, 10, 11)
> - This file
>
> **Project ID:** `wkevmsedchftztoolkmi`. All DB work via Supabase MCP.

---

## 1. Goal

Today the loyalty currency engine awards points for the **whole purchase** when `purchase_ledger.status` reaches one of the statuses listed in `earn_factor.allowed_purchase_statuses` (default `['completed']`). Award basis is `purchase_ledger.final_amount`.

The new requirement: also support awarding **per line item** as each item completes — with status configurable per earn factor at the item level, and the parent-vs-item decision configurable per merchant or per earning channel.

This unblocks merchants whose fulfillment is item-by-item (e-commerce shipping, restaurant ticket-by-ticket, manufacturing line-by-line) where waiting for the whole order to complete delays the customer's points.

---

## 2. Current architecture — what already exists

### 2.1 Chokepoint (Phase 1 — done 2026-05-13)

`chokepoint_post_purchase_event(p_event text, p_merchant_id uuid, p_payload jsonb) → jsonb` is the **sole canonical writer** for `purchase_ledger`. Verified: regex `pg_get_functiondef(...) ~* 'INSERT|UPDATE.*(public\.)?purchase_ledger'` returns exactly one function.

Existing event taxonomy:

| Event | Mutation surface | Notes |
|---|---|---|
| `created` | INSERT parent + items (batched `rows[]` payload) | Items are inside the parent payload's `items[]` field |
| `updated` | UPDATE parent fields | Status transition, money fields, notes |
| `completed` | UPDATE parent → `completed` | Stamps `completed_at`, `completed_by_*` |
| `line_completed` | UPDATE parent `seller_id` only; if all items now done, recurses to `completed` | **Item rows are mutated by the caller BEFORE this event** (today only by `bff_seller_complete_purchase_items`) |
| `cancelled` | UPDATE parent → `cancelled` | |
| `refunded` | INSERT debit row for refund amount; if full refund, UPDATE original parent → `refunded` | Acts on the parent only |
| `promo_applied` | UPDATE parent `discount_amount`, `final_amount`, `reward_list` | |

10 in-DB callers were rewritten to route through the chokepoint (see event-chokepoints.md row for the full list). 1 edge function (`purchase-orchestrator`) was redeployed. Two preserved triggers on `purchase_ledger`:

- `trg_purchase_complete_cascade_items` — data-integrity cascade (parent `completed` → items `completed`).
- `trg_referral_purchase` — post-write side effect, does not write `purchase_ledger`.

### 2.2 Item table (`purchase_items_ledger`) — NOT yet behind the chokepoint

| Path | Direct write today? |
|---|---|
| `chokepoint_post_purchase_event('created', ...)` writes items in same statement | ✅ controlled (writes inside chokepoint) |
| `bff_seller_complete_purchase_items` does direct `UPDATE purchase_items_ledger SET status, quantity_completed, ...` in a per-item loop | ❌ **bypasses chokepoint** |
| `trigger_cascade_purchase_complete_to_items` (data-integrity trigger on parent) cascades parent completion → items | ✅ data-integrity, allowed |

No triggers on `purchase_items_ledger`.

`purchase_items_ledger` columns (relevant): `id`, `transaction_id`, `merchant_id`, `sku_id`, `sku_code`, `quantity`, `quantity_completed`, `unit_price`, `discount_amount`, `tax_amount`, `line_total`, `status` (purchase_status enum), `completed_at`, `completed_by_user_id`, `completed_by_source`, `item_type`. **No `currency_processed_at`.**

### 2.3 Currency calculation pipeline (already in place)

```
chokepoint_post_purchase_event(awarding event)
  → calc_currency_for_source(p_source_type, p_source_id, ...)
       └─ p_source_type='purchase' → calc_currency_for_transaction(purchase_id)
              └─ calc_currency_core(merchant_id, user_id, amount, store_id, items, p_purchase_status)
                     └─ filters earn_factors via allowed_purchase_statuses
                     └─ returns rows: (currency_type, component, amount, earn_factor_id, target_entity_id)
  → enqueue_wallet_transaction(...) per row
       └─ pgmq.send('wallet_queue', payload)
```

⚠️ **Gaps in the existing pipeline:**
- `wallet_queue` PGMQ queue is **not created yet** (only `q_tier_evaluation_queue` and `q_internal_knowledge_embedding_jobs` exist).
- `process_wallet_queue(p_batch_size, p_visibility)` consumer function is **not created yet** (only the wrapper `process_wallet_queue_batch()` references it).
- `chokepoint_post_purchase_event` does **not** call `calc_currency_for_source` or `enqueue_wallet_transaction` today. The publish hook is deliberately deferred ("Phase 2 publish hook is deliberately deferred" per the prior thread).

### 2.4 What used to publish, what publishes today

- **Old (deprecated):** Postgres logical replication via `crm_cdc_publication` → Debezium → Confluent Cloud → `crm-event-processors` Currency consumer (Render). The dead `trigger_process_purchase_currency` function is a relic of an even older pre-CDC attempt; it's not attached to any trigger.
- **Future (out of scope for this plan):** chokepoint publishes directly to a Kafka topic via the wallet_queue → `process_wallet_queue` worker → currency consumer. That worker + Kafka publisher will be built in a separate later thread.

For this plan, **assume no Kafka publish is wired yet**. The chokepoint will compute the awarding decision, enqueue to PGMQ, and we'll define the payload contract — but the consumer side is built later.

---

## 3. Configuration model — three layers, narrowest wins

```
purchase_ledger.award_scope             ← per-purchase override (rare; usually NULL)
   ↓ falls back to
earn_factor.award_scope                  ← per-rule
   ↓ defaulted from
earn_channel.default_award_scope         ← per-channel
   ↓ defaulted from
'purchase'                                ← system default (preserves current behavior)
```

| Layer | Field | Type | Default | Purpose |
|---|---|---|---|---|
| Earning channel | `default_award_scope` | text | `'purchase'` | Channel-level default (POS = parent, e-comm = item) |
| Earn factor | `award_scope` | text | `'purchase'` | Per-rule scope |
| Earn factor | `allowed_item_statuses` | text[] | `ARRAY['completed']` | Item-status filter when `award_scope='purchase_item'` |
| Earn factor | `allowed_purchase_statuses` | text[] | `ARRAY['completed']` (existing) | Parent-status filter when `award_scope='purchase'` |
| Purchase | `award_scope` | text | NULL → fall through | Per-order override |

CHECK constraint on every `award_scope` column: value IN (`'purchase'`, `'purchase_item'`).

---

## 4. Schema deltas

### 4.1 Enums

```sql
ALTER TYPE wallet_transaction_source_type ADD VALUE 'purchase_item';
```

(Add at end of enum to avoid renumbering. Existing values: `purchase`, `campaign`, `manual`, `reward_redemption`, `referral`, `redemption_cancellation`, `mission`, `code`, `activity`, `amp`, `package_assignment`, `persona_entitlement`, `account_removal`, `expiry`.)

### 4.2 Columns

```sql
ALTER TABLE purchase_items_ledger
  ADD COLUMN currency_processed_at timestamptz NULL,
  ADD COLUMN currency_error        text        NULL;

ALTER TABLE purchase_ledger
  ADD COLUMN award_scope text NULL CHECK (award_scope IN ('purchase','purchase_item'));

ALTER TABLE earn_factor
  ADD COLUMN award_scope text NOT NULL DEFAULT 'purchase'
    CHECK (award_scope IN ('purchase','purchase_item')),
  ADD COLUMN allowed_item_statuses text[] NOT NULL DEFAULT ARRAY['completed'];

ALTER TABLE earn_channel
  ADD COLUMN default_award_scope text NOT NULL DEFAULT 'purchase'
    CHECK (default_award_scope IN ('purchase','purchase_item'));
```

### 4.3 Indexes

```sql
CREATE INDEX IF NOT EXISTS idx_purchase_items_ledger_txn_status
  ON purchase_items_ledger (transaction_id, status);

CREATE INDEX IF NOT EXISTS idx_purchase_items_ledger_unprocessed
  ON purchase_items_ledger (merchant_id, status)
  WHERE status = 'completed' AND currency_processed_at IS NULL;
```

### 4.4 Cleanup

```sql
DROP FUNCTION IF EXISTS public.trigger_process_purchase_currency();
```

(Dead code, not attached to any trigger. Verified via `pg_trigger` introspection.)

---

## 5. Chokepoint changes

### 5.1 Consolidate item writes into the chokepoint

**Rule:** all writes to `purchase_items_ledger` go through `chokepoint_post_purchase_event`. Direct UPDATE of `purchase_items_ledger` is forbidden, mirroring the rule for the parent table.

This means:
- `bff_seller_complete_purchase_items` must stop doing its own `UPDATE purchase_items_ledger SET ...` loop and instead invoke a new chokepoint event that owns the item mutation.
- Any future caller that wants to cancel, refund, or adjust a single item routes through the chokepoint.

The data-integrity trigger `trg_purchase_complete_cascade_items` stays — it's a post-write cascade for an integrity invariant (when parent flips to `completed`, items must too). It does not own business logic.

### 5.2 New / reshaped events

Replace `line_completed` with a clearer item-completion event, plus add cancel and refund events for individual items. Keep the existing `line_completed` event alive briefly as an alias during migration; delete it once all callers move.

| Event | Status | Mutation | Awarding hook |
|---|---|---|---|
| `created` | EXISTING — extend | Insert parent + items as today; **add** awarding hook (see §6) | If channel/factor item-mode and any item starts already in `'completed'`, award those items. Else, if parent starts in `'completed'`, award parent. |
| `updated` | EXISTING — extend | Patch parent fields | If status transitioned into a value present in any `allowed_purchase_statuses` for this merchant's `purchase`-scoped factors, award parent. |
| `completed` | EXISTING — extend | Force parent → `'completed'` | Award parent (parent-mode only — item-mode purchases skip because items already self-awarded). |
| `item_quantity_completed` | NEW (replaces `line_completed`'s mutation) | Update one or more items' `status` / `quantity_completed` / `completed_at` / `completed_by_*`; rollup parent if all done | Award per item that fully transitioned to `'completed'` (item-mode only). |
| `line_completed` | EXISTING — alias to `item_quantity_completed` for one release; then drop | Forwards to the new event | Same as above |
| `cancelled` | EXISTING — extend | Parent → `'cancelled'` | No-op for now (future: reverse pending parent earn). |
| `item_cancelled` | NEW | Cancel one or more items (status → `'cancelled'`); rollup parent if all items terminal | Reverse pending item earn if any (item-mode). |
| `refunded` | EXISTING — extend | Parent-level debit row + parent → `'refunded'` if full | Reverse parent award (parent-mode). |
| `item_refunded` | NEW | Per-item debit row + item → `'refunded'`; rollup parent if all items terminal | Reverse per-item award (item-mode). |
| `promo_applied` | EXISTING — unchanged | Patch parent discount/reward_list | No awarding (mutates basis only). |

### 5.3 Awarding hook — pseudocode (place at end of each event branch)

```sql
-- Inside chokepoint_post_purchase_event after the row mutation succeeds.
-- v_purchase = the row(s) just touched. v_merchant_id is in scope.

-- 1. Resolve scope: per-purchase override > per-factor (decided downstream) > channel > 'purchase'.
v_channel_default := COALESCE(
  (SELECT default_award_scope FROM earn_channel WHERE id = v_purchase.earning_channel_id),
  'purchase'
);
v_purchase_scope := COALESCE(v_purchase.award_scope, v_channel_default);

-- 2. Decide which currency-source calls to make.
IF event IN ('created' [parent->completed branch], 'updated' [transitioned], 'completed') AND v_purchase_scope = 'purchase' THEN
  PERFORM chokepoint_enqueue_currency('purchase', v_purchase.id, v_purchase.user_id, v_merchant_id, jsonb_build_object('purchase_status', v_purchase.status));
END IF;

IF event IN ('created' [items started completed], 'item_quantity_completed') AND v_purchase_scope = 'purchase_item' THEN
  FOR each item in (items that just transitioned to 'completed' AND currency_processed_at IS NULL) LOOP
    PERFORM chokepoint_enqueue_currency('purchase_item', item.id, v_purchase.user_id, v_merchant_id, jsonb_build_object('item_status', item.status, 'parent_purchase_id', v_purchase.id));
    UPDATE purchase_items_ledger SET currency_processed_at = NOW() WHERE id = item.id;
  END LOOP;
END IF;

-- Reversal hooks for cancelled / refunded / item_cancelled / item_refunded follow the same shape but with negative-direction events.
```

`chokepoint_enqueue_currency(p_source_type, p_source_id, p_user_id, p_merchant_id, p_metadata)` is a thin internal helper that calls `calc_currency_for_source(...)` and pipes each calc result into `enqueue_wallet_transaction(...)`. It keeps the chokepoint body readable and centralizes the calc-then-enqueue pattern. **Build this helper as part of this work.**

### 5.4 New: `calc_currency_for_purchase_item(p_item_id uuid)`

Mirrors `calc_currency_for_transaction(p_transaction_id)` but scoped to a single item.

```sql
CREATE OR REPLACE FUNCTION public.calc_currency_for_purchase_item(p_item_id uuid)
RETURNS TABLE(currency_type currency, component currency_component, amount integer, earn_factor_id uuid, target_entity_id uuid)
LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
  v_user_id     uuid;
  v_merchant_id uuid;
  v_store_id    uuid;
  v_item_status text;
  v_basis       numeric;
  v_items       jsonb;
BEGIN
  SELECT pl.user_id, pli.merchant_id, COALESCE(pl.store_id, sm.id),
         pli.status::text, pli.line_total,
         jsonb_build_array(jsonb_build_object(
           'sku_code', pli.sku_code, 'quantity', pli.quantity,
           'quantity_secondary', pli.quantity_secondary,
           'unit_price', pli.unit_price, 'line_total', pli.line_total,
           'item_id', pli.id))
    INTO v_user_id, v_merchant_id, v_store_id, v_item_status, v_basis, v_items
  FROM purchase_items_ledger pli
  JOIN purchase_ledger pl ON pl.id = pli.transaction_id
  LEFT JOIN store_master sm ON pl.store_code = sm.store_code AND sm.merchant_id = pli.merchant_id
  WHERE pli.id = p_item_id;

  IF NOT FOUND THEN RETURN; END IF;

  RETURN QUERY
    SELECT cc.currency_type, cc.component, cc.amount, cc.earn_factor_id, cc.target_entity_id
    FROM calc_currency_core(v_merchant_id, v_user_id, v_basis, v_store_id, v_items, v_item_status) cc
    WHERE EXISTS (
      SELECT 1 FROM earn_factor ef
      WHERE ef.id = cc.earn_factor_id
        AND ef.award_scope = 'purchase_item'
        AND v_item_status = ANY (ef.allowed_item_statuses)
    );
END;
$$;
```

Then extend `calc_currency_for_source` with a `WHEN 'purchase_item'` branch that delegates to this new function.

`calc_currency_core` already accepts `p_purchase_status text`. **It needs no signature change** — we reuse it by passing the item's status as `p_purchase_status` and filter in the wrapper. (Alternative: add `p_award_scope` and `p_allowed_*` params to `calc_currency_core` itself for cleaner separation; document the tradeoff in the proposal step.)

`calc_currency_for_transaction` should also be tightened to filter to factors where `ef.award_scope = 'purchase' AND v_purchase_status = ANY (ef.allowed_purchase_statuses)`, otherwise an item-scoped factor would also match at the parent level.

---

## 6. Phase split for THIS plan

This work is bigger than a single Phase 1 chokepoint migration. Slice it:

### Phase A — Item write consolidation (zero behavior change)
- Add `currency_processed_at`, `currency_error` to `purchase_items_ledger`.
- Add new chokepoint events `item_quantity_completed`, `item_cancelled`, `item_refunded`. The first replaces the mutation portion of `line_completed`; the existing `line_completed` becomes a forwarder that calls `item_quantity_completed` then performs its existing rollup.
- Rewrite `bff_seller_complete_purchase_items` to call the chokepoint instead of `UPDATE`ing items directly.
- Verification: regex `pg_get_functiondef(...) ~* '(INSERT|UPDATE).*(public\.)?purchase_items_ledger'` returns **only** the chokepoint. Existing seller-completion smoke tests still pass.

### Phase B — Configuration plumbing (zero behavior change)
- Add `wallet_transaction_source_type.purchase_item` enum value.
- Add `award_scope` / `allowed_item_statuses` columns to `earn_factor` with safe defaults.
- Add `default_award_scope` to `earn_channel`.
- Add `award_scope` to `purchase_ledger`.
- Add `calc_currency_for_purchase_item(uuid)` function; extend `calc_currency_for_source` with the new branch.
- Tighten `calc_currency_for_transaction` to filter factors by `award_scope='purchase'` (so existing factors keep firing, item-scoped factors skip the parent path).
- BFF / admin form changes for editing `award_scope`, `allowed_item_statuses`, channel default — separate FE thread.

### Phase C — Awarding hook in the chokepoint (behavior change, gated by config)
- Add `chokepoint_enqueue_currency(p_source_type, p_source_id, ...)` helper.
- Wire it into the `created`, `updated`, `completed`, `item_quantity_completed` event branches per the pseudocode in §5.3.
- Wire reversal calls into `cancelled`, `refunded`, `item_cancelled`, `item_refunded`.
- Behavior remains identical for any merchant whose channels / factors are still default `'purchase'`. Only merchants who flip a channel / factor to `'purchase_item'` see new behavior.

### Phase D — Drop dead code + cleanup
- `DROP FUNCTION public.trigger_process_purchase_currency();`
- Once `bff_seller_complete_purchase_items` and any other caller of `line_completed` are migrated, delete the `line_completed` event branch from the chokepoint (keep alias for one release per the no-wrappers rule, then drop).
- Update `requirements/Purchase_Transaction.md`, `REGISTRY_SUPABASE.md`, `requirements/architecture/event-chokepoints.md` (Phase 2 status note for Purchase domain), and `requirements/CHANGELOG.md`.

### Deferred (separate later thread, NOT in this plan)
- Build out `wallet_queue` PGMQ + `process_wallet_queue` consumer function + cron schedule.
- Add Kafka publish step inside the chokepoint (instead of / in addition to the PGMQ enqueue).
- Decommission `crm_cdc_publication` for `purchase_ledger`.
- Build the standalone Kafka currency consumer in `crm-event-processors` for the new `purchase_items_ledger` events (if Kafka path is chosen instead of in-DB PGMQ).

The user has explicitly said the worker side will be built later. This plan covers Phases A–D only, and defines the publish payload contract so the later worker thread has a stable target.

---

## 7. Publish payload contract (so the later worker thread has a target)

Whether the eventual transport is in-DB PGMQ or Kafka, the chokepoint will enqueue a payload of this shape per awarding event:

```json
{
  "version": 1,
  "source_type": "purchase" | "purchase_item",
  "source_id": "<uuid>",
  "user_id": "<uuid>",
  "merchant_id": "<uuid>",
  "currency_type": "points" | "ticket",
  "component": "base" | "bonus" | "adjustment" | "reversal",
  "transaction_type": "earn" | "burn",
  "amount": <integer>,
  "target_entity_id": "<uuid|null>",
  "earn_factor_id": "<uuid|null>",
  "metadata": {
    "parent_purchase_id": "<uuid>",
    "purchase_status": "<status>",
    "item_status": "<status|null>",
    "earning_channel_id": "<uuid|null>"
  },
  "dedup_key": "purchase:<purchase_id>:<earn_factor_id>" | "purchase_item:<item_id>:<earn_factor_id>"
}
```

`dedup_key` is the wallet-side idempotency anchor — the worker / consumer must refuse to insert a `wallet_ledger` row if `dedup_key` is already present. This protects against retries at the queue layer **and** against the chokepoint's own per-item `currency_processed_at` flag drifting.

When the later thread chooses topics, suggested split: one topic per source_type (`purchase.awarding.v1`, `purchase_item.awarding.v1`).

---

## 8. Migration order (applied via `apply_migration`)

Each numbered migration is one MCP `apply_migration` call. Stop and verify between phases.

**Phase A:**
1. `add_currency_processed_at_to_purchase_items_ledger`
2. `chokepoint_purchase_event_add_item_events_v1` — adds `item_quantity_completed`, `item_cancelled`, `item_refunded` event branches; reshapes `line_completed` to forward.
3. `bff_seller_complete_purchase_items_via_chokepoint` — rewrites the BFF.
4. **Verify:** regex check; smoke test the seller completion flow with full + partial item completion.

**Phase B:**
5. `add_purchase_item_to_wallet_source_enum`
6. `add_award_scope_to_earn_factor` (also adds `allowed_item_statuses`)
7. `add_default_award_scope_to_earn_channel`
8. `add_award_scope_to_purchase_ledger`
9. `calc_currency_for_purchase_item_v1`
10. `calc_currency_for_source_add_purchase_item_branch`
11. `calc_currency_for_transaction_filter_by_award_scope`
12. **Verify:** existing factors still match (parent path unchanged); new factors with `award_scope='purchase_item'` match only at item level.

**Phase C:**
13. `chokepoint_enqueue_currency_helper_v1`
14. `chokepoint_purchase_event_add_awarding_hook_v1` — wires the helper into all relevant branches.
15. **Verify:** end-to-end smoke (matrix in §9). Confirm parent-mode merchants unchanged; item-mode merchants get one award per item completion.

**Phase D:**
16. `drop_trigger_process_purchase_currency`
17. `chokepoint_purchase_event_drop_line_completed_alias` — only after all callers verified migrated.
18. Doc updates (registry regen, CHANGELOG, Purchase_Transaction.md, event-chokepoints.md).

---

## 9. Smoke test matrix

Run inside a `DO` block with `RAISE EXCEPTION 'rollback'` at the end so nothing persists. Cover every (event × scope) cell.

| # | Setup | Action | Expected wallet effect |
|---|---|---|---|
| 1 | Channel default `purchase`, factor `purchase`/`['completed']` | `created` parent in `pending`, then `completed` event | One award against parent `final_amount` |
| 2 | Same as 1 | `created` parent already in `completed` | One award against parent (immediately) |
| 3 | Channel default `purchase`, factor `purchase`/`['processing','completed']` | `updated` parent → `processing`, then → `completed` | Two awards (one per status transition) — verify if this is intended; if not, scope dedup by `(purchase_id, earn_factor_id)` |
| 4 | Channel default `purchase_item`, factor `purchase_item`/`['completed']` | `created` parent `pending` with 3 items, then `item_quantity_completed` for item 1 | One award scoped to item 1 |
| 5 | Same as 4 | `item_quantity_completed` for items 1, 2, 3 in sequence | Three awards, one per item |
| 6 | Same as 4 | `item_quantity_completed` partial (3 of 5 units) on one item | No award yet (item still in `pending` until full) |
| 7 | Same as 4 | After all items complete, parent rolls up to `completed` via existing rollup | **No additional parent award** (item-mode skips parent path) |
| 8 | Mixed: channel default `purchase_item`, factor A `purchase_item`, factor B `purchase` | Item completion | Only factor A fires; factor B doesn't fire on parent because items don't roll up to a parent-eligible event |
| 9 | Per-purchase override `purchase_ledger.award_scope='purchase'` on a channel that defaults to `purchase_item` | Item completion | No item awards; on parent rollup, parent award fires |
| 10 | `item_refunded` after item awarded | Refund single item | Reversal entry for that item only; parent award untouched |
| 11 | `refunded` parent after parent awarded | Full refund | Reversal entry for the parent award |
| 12 | Idempotency: send `item_quantity_completed` twice for same item | Second call | No duplicate award (gated by `currency_processed_at`) |
| 13 | Idempotency: redeliver `dedup_key` to wallet writer | Second call | No duplicate `wallet_ledger` row (gated by `dedup_key`) |
| 14 | Direct write attempt: `UPDATE purchase_items_ledger ...` outside chokepoint | Should be rejected by convention; verify regex check fails | Regex returns one extra writer → fail the migration |

---

## 10. Rollback plan

Each phase is independently reversible. From newest:

- **Phase D:** restore `trigger_process_purchase_currency` from git history; restore `line_completed` event branch.
- **Phase C:** drop awarding hook; chokepoint reverts to write-only (no PGMQ enqueue). Behavior reverts to "no points awarded by item completion" — but parent-mode awarding stays off too because Phase C is what wires it. Make sure the legacy parent-award path (whatever was producing parent awards before this work — currently the dead CDC path) is back in place before rolling Phase C out, otherwise rollback breaks parent earning. **Mitigation:** keep the awarding hook behind a per-merchant feature flag (`merchant_master.award_via_chokepoint boolean default false`) that the operator can flip back to `false` to re-enable the legacy path during rollback. Add this flag in Phase C and remove it once the deferred worker thread has decommissioned the legacy path.
- **Phase B:** drop the new columns + new function; revert `calc_currency_for_transaction` filter change.
- **Phase A:** drop the new event branches; restore `bff_seller_complete_purchase_items` to direct-update form (from git history); drop new columns.

---

## 11. Discovery checklist for the new thread (Steps 1–3 of Context Lookup)

Before touching DDL, the new thread MUST run:

1. **Re-confirm the chokepoint state.** Regex check that exactly one function writes `purchase_ledger` today. If the count > 1, stop and reconcile before proceeding.
2. **Inventory item writers.** `pg_get_functiondef(...) ~* '(INSERT INTO|UPDATE) (public\.)?purchase_items_ledger'`. Expected: `chokepoint_post_purchase_event`, `bff_seller_complete_purchase_items`, `trigger_cascade_purchase_complete_to_items`. Anything else means new writers were added since this plan was written — surface them in the proposal.
3. **Confirm enum values + factor columns.** `wallet_transaction_source_type` must NOT yet contain `purchase_item`. `earn_factor` must NOT yet contain `award_scope`. If either exists, somebody started this work — stop and reconcile.
4. **Confirm earn_channel + purchase_ledger columns.** Same drill.
5. **Check wallet_queue status.** `SELECT * FROM information_schema.tables WHERE table_schema='pgmq' AND table_name='q_wallet_queue';` — if it now exists, the deferred worker thread may have moved; revisit whether Phase C should enqueue or call sync directly.
6. **Read the chokepoint's current body** to refresh the event-branch layout before adding new branches.

Run these in one batched MCP turn. Then write the Phase A proposal, **STOP, and wait for explicit human approval** before any `apply_migration`.

---

## 12. Open questions for the human (must be answered before Phase A starts)

1. **Partial-quantity awarding semantics:** §5.3 / smoke test #6 assumes "no award until item `status='completed'`." Is that the intent, or should partial completion (e.g. 3 of 5 units) earn pro-rata immediately? Pro-rata complicates basis math (`unit_price × quantity_completed`) and idempotency (per-completion-event tracking instead of per-item).
2. **Header discount handling in item mode:** assume items carry pre-allocated discounts in `purchase_items_ledger.discount_amount` and ignore parent `purchase_ledger.discount_amount`. Acceptable, or do you want pro-rata allocation in `calc_currency_for_purchase_item`?
3. **Multiple status transitions firing multiple times** (smoke test #3): if a parent passes through `processing` → `completed` and a factor allows both, do we want two awards or only one (deduped by `(purchase_id, earn_factor_id)`)? Default proposal: **dedup** — `dedup_key` on the wallet write enforces this naturally.
4. **`line_completed` deprecation window:** keep the event branch alive for one release as an alias, or delete same change set per the no-wrappers rule? The chokepoint architecture says no aliases; that's the safer path but it forces the BFF rewrite to land in the same change set as the chokepoint event reshape.
5. **Rollback safety net (`merchant_master.award_via_chokepoint` flag in §10):** include the flag, or accept that Phase C is one-way and the rollback is "manually re-enable the legacy CDC consumer"? Including the flag adds a column we may want to remove in 1–2 releases.
6. **Sync vs async wallet writing in Phase C:** the wallet_queue + worker is deferred. Two options:
   - C-sync: chokepoint calls `chokepoint_post_wallet_transaction` directly. Works today; risk = chokepoint TX balloons.
   - C-async: chokepoint only calls `enqueue_wallet_transaction` (PGMQ) and depends on the deferred worker. Cleaner but blocks on the deferred thread.
   Default proposal: **C-sync first, switch to async after the worker ships.**

Lock answers to all six before Phase A migration begins.

---

## 13. Document updates required at the end

Per `.cursor/rules/06-update-docs.mdc`:

- `requirements/REGISTRY_SUPABASE.md` — regenerate via the `registry-regenerate` skill.
- `requirements/architecture/event-chokepoints.md` — update the Purchase row's status note to mention item-write consolidation; add a note that Phase 2 publish hook is partially implemented (PGMQ enqueue) and the Kafka publish remains deferred.
- `requirements/Purchase_Transaction.md` — add a "Per-line-item earning" section documenting the configuration model, scope precedence, and idempotency anchors.
- `requirements/CHANGELOG.md` — one entry per migration phase landed (A, B, C, D).
- CRM Knowledge MCP — author / update the `rules` and `technical_reference` blocks for the `loyalty-currency-earning` (or equivalent) feature with the new configuration model. Use `15a-crm-knowledge-writes.mdc` for the write workflow.

---

## 14. Out of scope (do NOT do in this thread)

- Building `wallet_queue` PGMQ + `process_wallet_queue` + cron.
- Building / modifying the Kafka currency consumer in `crm-event-processors`.
- Decommissioning `crm_cdc_publication` (still serves wallet + form_submissions paths).
- Touching `rocket_bq_replication_publication` (BigQuery analytics path).
- FE changes for editing `award_scope` / `allowed_item_statuses` / channel defaults — separate FE thread.
- Backfill of `currency_processed_at` for historical items — items completed under the legacy parent-mode flow do not need backfill because their points were already awarded against the parent.
