# Event Chokepoint Pattern

> **Source of truth for the event chokepoint migration.**
> Every per-domain implementation thread MUST read this file before proposing or making any changes.
>
> Platform bus (outbox → Inngest + integration cursors): `requirements/CRM_Event_Driven_Architecture.md`. This file documents the **chokepoint writer** convention and Phase 1 migration per domain.

---

## Why this exists

Today, every event downstream of the CRM (currency awards, tier evaluation, mission progress, AMP workflows, etc.) flows through a single Debezium replication slot reading the `crm_cdc_publication`. When WAL volume spikes, that slot falls behind, Debezium stalls, and downstream consumers go dark for everything at once.

The chokepoint pattern moves event emission from incidental (a side effect of CDC reading WAL) to deliberate (an explicit step inside a single canonical writer per domain). Once every chain has a chokepoint, we can publish events directly from Postgres, decommission CDC for these tables, and remove the WAL bottleneck.

---

## The pattern

For each major data chain there is **exactly ONE function** that writes the canonical ledger row. This function is the **chokepoint**.

- All other code paths (BFFs, edge functions, triggers, imports, cron jobs, admin tools) MUST call the chokepoint function.
- Direct INSERT or UPDATE on the ledger table from anywhere else is **forbidden**.
- The chokepoint is an explicit writer that the caller invokes. It is **NOT** a database trigger that fires AFTER another write. The chokepoint owns the write itself.

---

## Naming convention

New top-level prefix: `chokepoint_`. Sits alongside existing `bff_*`, `api_*`, `fn_*`, `trigger_*` prefixes (see `.cursor/rules/10-function-conventions.mdc`). After Phase 1 lands, that rules file should be updated to register `chokepoint_` formally.

| Domain | Chokepoint function | Ledger table | Phase 1 status |
|---|---|---|---|
| Wallet | `chokepoint_post_wallet_transaction` | `wallet_ledger` | **IMPLEMENTED 2026-05-13** — 15 in-DB callers rewritten, 2 edge functions redeployed (`inngest-currency-serve`, `shopify-points-to-discount`), old `post_wallet_transaction` dropped, all 4 wallet_ledger triggers preserved (no behavior change). |
| Tier | `chokepoint_post_tier_change` | `tier_change_ledger` | **IMPLEMENTED 2026-05-13** — 3 in-DB writers rewritten in one atomic migration (`apply_tier_upgrade`, `ensure_tier_progress`, trigger function `after_user_signup_tier_setup`); no edge function or Render worker redeploy required (all callers were in-DB or routed via DB delegators); zero triggers on `tier_change_ledger` (nothing to relocate); `after_user_signup_tier` and `trg_auto_assign_on_persona_change` triggers on `user_accounts` preserved unchanged. Pre-flight discovery proved `evaluate_user_tier_status` was a pure recommendation engine (NOT a writer) — the brief's "single existing writer" assumption was corrected. Verification: `pg_get_functiondef(...) ~* 'INSERT INTO (public\\.)?tier_change_ledger'` now returns exactly one function (the chokepoint). |
| Purchase | `chokepoint_post_purchase_event` | `purchase_ledger`, `purchase_items_ledger` | **IMPLEMENTED 2026-05-13** — initial parent-only chokepoint with 7 events (`created`, `updated`, `completed`, `line_completed`, `cancelled`, `refunded`, `promo_applied`). **EXTENDED 2026-05-14 (purchase-line-item-earning)** — chokepoint extended to be sole writer of `purchase_items_ledger` as well. The `line_completed` event was **deleted atomically** (no alias, no wrapper) and replaced with 5 new item-mutation events: `item_quantity_completed` (idempotent quantity-completed increment with parent rollup to `completed` when all items terminal), `item_cancelled`, `item_refunded`, `items_added`, `items_replaced`. The 4 direct-write callers were rewritten in the same change set: `bff_seller_complete_purchase_items` (uses `item_quantity_completed`), `api_update_purchase` ×2 overloads (use `items_replaced` instead of inline DELETE+INSERT, with `new_total_amount` returned from the event), `claim_marketplace_order` (now passes items into `api_create_purchase` and lets the `created` branch handle them — no `items_added` needed for this path), `fn_apply_event_promos` (uses `items_added` for both engine-granted freebies and pool-pick items). The data-integrity trigger `trg_purchase_complete_cascade_items` is preserved. The dead `trigger_process_purchase_currency` function was dropped. Verification: writer regex on `purchase_items_ledger` now returns exactly two functions — the chokepoint (canonical writer) and `trigger_cascade_purchase_complete_to_items` (data-integrity trigger function); end-to-end 10-test smoke harness inside a roll-back DO block exercises all 5 new events, the rollup behavior, status guards (`items_replaced` rejected on completed parent), quantity overflow rejection, and confirms `line_completed` returns "Unsupported event". Phase 2 (Kafka publish) plan written at `.cursor/plans/chokepoint-kafka-publisher.md` and is deliberately deferred to a parallel thread. |
| User account | `chokepoint_post_user_event` | `user_accounts` | **IMPLEMENTED 2026-05-14** — 18 in-DB writers rewritten in one rolling migration set (`mark_signup_form_complete`, `fn_seller_resolve_user_type`, `bff_change_user_tel`, `bff_admin_change_member_mobile`, `assign_persona`, `claim_marketplace_order`, `fn_consume_signup_code`, `bff_admin_rollback_user_import`, `fn_execute_amp_action` `assign_persona` branch, `apply_tier_upgrade`, `ensure_tier_progress`, `admin_remove_user`, `bff_admin_create_member`, `bff_admin_update_member_profile`, `bff_save_user_profile`, `bulk_upsert_customers_from_import`, `api_create_or_update_user`, `api_update_user`) plus 2 edge functions redeployed (`auth-register`, `bff-auth-complete` — last preserved `verify_jwt=false`); `auth-line-login` tombstoned with HTTP 410 (zero active callers confirmed via GitHub audit). The four logic-bearing triggers and their backing functions were dropped and their logic ported into the chokepoint: `assign_entry_tier_on_signup` + `assign_entry_tier` trigger (entry-tier resolution moved into the `create` branch); `fn_sync_user_type_from_persona` + `trg_sync_user_type_from_persona` (persona→user_type derivation moved into `create` and `update` branches); `after_user_signup_tier_setup` + `after_user_signup_tier` (initial `tier_progress` row + cascade to `chokepoint_post_tier_change` for the initial-tier ledger entry moved into the `create` post-write block); `trigger_auto_assign_on_persona_change` + `trg_auto_assign_on_persona_change` (persona-change benefit cancellation + `fn_auto_assign_on_persona` + `process_tier_event` moved into the `update` post-write block). The data-integrity trigger `set_updated_at_user_accounts` (BEFORE UPDATE) was preserved. The chokepoint takes a 9-arg signature with a 4-event taxonomy (`create` / `update` / `soft_delete` / `hard_delete`) and a whitelist `p_changes jsonb` payload; it explicitly cascades to `chokepoint_post_tier_change` on tier flips (no double-write), inherits CDC suppression via `p_skip_cdc`, and replaces the `app.skip_side_effects` GUC with an explicit `p_skip_side_effects` argument. `soft_delete` auto-scrubs PII unconditionally (caller payload cannot un-scrub). Cleanup hardening: dropped two permissive RLS policies (`user_accounts_merchant_insert`, `user_accounts_merchant_update`) and revoked `INSERT`/`UPDATE`/`DELETE` from `anon` and `authenticated`, so non-chokepoint writes are now blocked by both convention and grants. Verification: `pg_get_functiondef(...) ~* 'INSERT INTO\|UPDATE\|DELETE FROM (public\\.)?user_accounts'` returns exactly one function (the chokepoint), only `set_updated_at_user_accounts` remains as a trigger, and an end-to-end chokepoint round-trip smoke test executes cleanly. Phase 2 (Kafka publish, CDC decommission) deliberately deferred. |

The chokepoint name replaces the existing function name. Old name is **deleted** in the same change set.

---

## Two-phase migration

**Phase 1 — chokepoint creation + caller restructuring (the current round of work).**

- Create the `chokepoint_*` function (often by renaming an existing single-writer function and reshaping its signature).
- Reroute every caller to use the chokepoint name.
- Delete the old function name. **No wrappers, no aliases, no parallel chokepoints.**
- Verify in staging that ledger row counts and shapes are unchanged, and that downstream behavior (CDC, AMP consumers, etc.) is unaffected.

**Phase 2 — Kafka publish inside each chokepoint (separate, later concern).**

- Once all four chains have stable chokepoints, add the publish step inside each chokepoint.
- Decommission the table from `crm_cdc_publication` once Kafka consumer parity is verified.
- Out of scope for the Phase 1 threads. Do not bundle Phase 2 into a Phase 1 change set.

---

## Non-negotiable rules

1. **One chokepoint per domain. No wrappers, no aliases, no parallel chokepoints.** The old function name must be deleted as part of the same change set that introduces the new one. Callers update atomically.
2. **The chokepoint is an explicit writer, not a trigger.** Callers invoke it directly. Triggers may exist on the ledger table for data-integrity concerns (timestamp stamping, validation, dedup keys) but must NOT do the actual ledger insert and must NOT contain business logic that the chokepoint should own.
3. **Direct ledger inserts/updates from anywhere else are forbidden.** Every writer in the codebase routes through the chokepoint. This includes BFFs, edge functions, RPCs, admin tools, bulk imports, marketplace claims, cron jobs, and any future code path.
4. **No work begins without explicit approval.** Each domain thread runs Steps 1–3 of the Context Lookup Procedure (`.cursor/rules/00-core.mdc`), presents findings, and waits for the human to approve the proposal before any DB change.
5. **No Kafka publish in Phase 1.** Adding the publish step is Phase 2. Phase 1 is about establishing the chokepoint and restructuring callers — nothing more.
6. **Migration ordering matters.** Wallet first (smallest blast radius), then Tier, then Purchase, then User accounts. Do not start a downstream domain until the upstream one is verified in staging.

---

## Phase 1 work order in every domain thread

1. **Inventory writers.** Find every code path that currently inserts or updates the ledger table. Use Grep on the workspace, live MCP queries on `pg_proc`, `pg_trigger`, edge function source, and the `requirements/domains/<domain>.md` file.
2. **Inventory triggers.** List every trigger on the ledger table. Classify each as **data-integrity** (keep) or **logic-bearing** (must be relocated into the chokepoint or replaced by an explicit chokepoint call from the caller).
3. **Propose the chokepoint.** Present:
   - The chokepoint function signature.
   - The full list of callers that need to change, with their current entry points.
   - The full list of triggers that need to change, with the proposed disposition for each.
   - The migration order (which caller migrates first, what the verification looks like at each step).
   Then **STOP and wait for approval**.
4. **Build the chokepoint** (after approval). Rename or create the function. Update all callers in the same change set. Delete the old function name.
5. **Verify** in staging. Ledger row counts, row shapes, downstream behavior, and CDC behavior must be unchanged. Phase 1 success criterion: no observable difference except that all writes now route through the chokepoint name.

---

## Out of scope for Phase 1

- **Kafka publish** — Phase 2.
- **Decommissioning `crm_cdc_publication`** — Phase 2. Leave the publication and the `skip_cdc` columns alone for now.
- **AMP scheduled workflow events** — different transport (`fn_amp_run_due_scheduled_workflows`); not a ledger chokepoint.
- **CS conversation events** — separate transport via Inngest; out of scope for this migration.
- **BigQuery replication** (`rocket_bq_replication_publication`) — analytics path, not operational; do not touch.
- **New event types or schema changes to ledger tables** — out of scope. Phase 1 preserves existing behavior exactly.

---

## After Phase 1 completes

- Update `.cursor/rules/10-function-conventions.mdc` to register the `chokepoint_` prefix as a first-class function naming convention.
- Update `requirements/CRM_Event_Driven_Architecture.md` to reflect that the four chains have chokepoints (still emitting via CDC for now).
- Append entries to `requirements/CHANGELOG.md` per `.cursor/rules/06-update-docs.mdc`.

## Project ID

`wkevmsedchftztoolkmi`. Use Supabase MCP for all DB work.
