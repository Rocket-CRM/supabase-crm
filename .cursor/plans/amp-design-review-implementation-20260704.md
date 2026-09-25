# Handoff: AMP Design Review — Implementation Plan

Supabase project: `wkevmsedchftztoolkmi`. All findings below were verified read-only against live `pg_proc` / `information_schema` / `pg_indexes` on 2026-07-04. Nothing has been changed yet — every item needs explicit user approval before `apply_migration` per workspace rules.

**Good news constraint:** `amp_audience_master` and `amp_audience_member` are both **empty (0 rows)** in production — audience fixes are pre-launch with no data-migration risk. `workflow_log` has ~28k rows and is live.

---

## Item 1 — Fix `bff_get_audience_members` pagination (small, mechanical)

**Bug (confirmed):** `LIMIT p_limit OFFSET p_offset` is applied to the query *after* `jsonb_agg`, which collapses everything to one row. Page 1 returns ALL members; any `OFFSET > 0` returns zero rows → `v_members` NULL → `'[]'`.

Current broken shape:

```sql
SELECT COALESCE(jsonb_agg(jsonb_build_object(...) ORDER BY m.entered_at DESC), '[]'::jsonb)
INTO v_members
FROM amp_audience_member m
JOIN user_accounts u ON u.id = m.user_id
WHERE m.audience_id = p_audience_id
  AND (p_include_exited OR m.exited_at IS NULL)
LIMIT p_limit OFFSET p_offset;
```

**Fix:** paginate in a subquery (ORDER BY `entered_at DESC` + LIMIT/OFFSET inside), `jsonb_agg` outside. Keep the existing response contract exactly: success = `{success, audience_id, audience_name, data, total, limit, offset}`; errors = `{success, code (NO_MERCHANT_CONTEXT|NOT_FOUND|ERROR), title, description [, detail]}`. The separate `count(*)` for `total` is already correct — don't touch it. Member element keys: `user_id, full_name, phone_number, entered_at, exited_at`.

Note: index `(audience_id, entered_at DESC)` already exists and matches the sort.

## Item 2 — Fix `bff_get_amp_workflow_node_stats` FE/BE contract mismatch (small; needs one FE confirmation)

**Bug (confirmed):** backend returns `{success, workflow_id, nodes: [{node_id, node_type, node_name, unique_passed, currently_waiting}]}`. Frontend reads `data[].entered_count / completed_count / error_count`. Nothing matches; FE gets `undefined` everywhere. Backend has no error aggregate at all.

**Recommended fix (backend moves):** return `data[]` with `entered_count`, `completed_count`, `error_count` (keep the old keys too if cheap, for safety). Semantics to implement from `workflow_log`:

- `entered_count`: distinct users with `event_type IN ('node_executed','action_executed')` for that node (current `unique_passed` semantics).
- `completed_count`: distinct users with `status='executed'` (or non-waiting terminal per node) — **confirm the exact FE expectation with the loyalty-admin repo owner before coding**; the spec doc `docs/AMP_WORKFLOW_BUILDER_FE_SPEC.md` may pin it.
- `error_count`: rows/users with `status='failed'` or `error_message IS NOT NULL` for the node — currently NOT computed anywhere; define it.

Wait-state encoding (for reference): no `wait_started` event type exists; waiting = `node_type='wait' AND status='waiting'` with no later `status='executed'` for the same `(inngest_run_id, node_id)` and no terminal event for the run.

**Tenancy note:** the node-stats and node-users log queries have NO `merchant_id` filter (only the workflow-ownership guard above). Add `merchant_id` to the log filters while editing.

## Item 3 — `workflow_log` index gaps + `bff_amp_batch_run` chunking (small migrations)

**Indexes (confirmed missing):** no index contains `node_id`; no `(workflow_id, event_type)` composite. Add:

- `(workflow_id, node_id, event_type)` — serves node-stats and node-users.
- `(workflow_id, event_type)` — serves analytics CTEs and the compiler's enrollment-exclusion `EXCEPT` clause.

Existing indexes (don't duplicate): single-column btrees on `merchant_id, workflow_id, user_id, inngest_run_id, event_type, created_at DESC`; partials on `external_message_id, action_channel`; composites `(merchant_id, node_type, action_type, status) WHERE node_type='message'`, `(workflow_id, user_id, created_at) WHERE event_type='action_executed' AND cost>0`, `(merchant_id, action_type, action_channel, created_at DESC) WHERE action_type IS NOT NULL`.

**`bff_amp_batch_run` (confirmed):** `array_agg(user_id)` from `fn_amp_find_matching_users`, one unchunked `net.http_post` to `/functions/v1/amp-dispatch-workflow-batch` with body `{workflow_id, merchant_id, user_ids}`, and it **echoes the full user_ids array** back in the response. Against 3.16M `user_accounts` a broad audience breaks pg_net / the edge function. Fix: chunk the dispatch (e.g. 500–1000 ids per POST, loop `net.http_post`), drop `user_ids` from the response (keep `matching_users` count + `dispatched` + request ids). Check the `amp-dispatch-workflow-batch` edge function tolerates multiple batch calls per run (it's authorized via vault `service_role_key`, URL from vault `supabase_url`).

## Item 4 — Condition evaluation semantics (NEEDS PRODUCT/ARCH DECISION FIRST — do not code before deciding)

Two divergent evaluators exist:

- `fn_amp_find_matching_users(p_workflow_id)` — set-based SQL compiler, used by batch runs.
- `fn_evaluate_amp_condition_group(p_user_id, p_merchant_id, p_group jsonb)` — per-user, **zero DB callers** — called from the edge/Inngest layer, which owns group combination.

**Confirmed defects in the compiler:**

- Reads ONLY group 0 of the FIRST condition node (`ORDER BY position_y, position_x LIMIT 1`, then `node_config->'groups'->0` / `->'condition_groups'->0`). Groups 1..n silently ignored.
- No `all`/`any` combinator anywhere (string `match` absent from body); conditions always AND-ed.

**Confirmed semantic drift between the two paths:**

| Behavior | Compiler (batch) | Evaluator (per-user) |
|---|---|---|
| `tel` equals | normalized via `fn_normalize_thai_phone()` | plain string compare |
| Already-enrolled users | excluded via `EXCEPT … workflow_log … event_type='execution_started'` | not excluded |
| Zero-row aggregate | can never match (GROUP BY/HAVING emits no group) | `COALESCE(agg,0)` → `sum < 100` matches users with no rows |
| Aggregate `filters` operators | only equals/not_equals/contains (numeric ops degrade to equals) | also gt/gte/lt/lte |

**Shared defects (fix in both regardless of decision):**

- Unknown operators silently fall back to `equals`.
- Aggregate function name injected via `%s` with NO whitelist — SQL injection surface reachable through condition JSON. Whitelist to `sum|count|avg|min|max`.
- `collection` table name is `%I`-interpolated from JSON — consider a whitelist of allowed collections too.

**Decision needed from user:** single source of truth. Options: (a) extend the compiler to full group-tree + all/any and keep the evaluator only for event-triggered per-user checks with aligned semantics; (b) batch path iterates the per-user evaluator (slow at 3.16M users — probably not viable); (c) document the compiler as the canonical semantics and change the edge layer. Recommend (a).

## Item 5 — Export pipeline is a dead-letter box (needs scope decision)

`bff_admin_start_user_export` inserts into `bulk_import_batches` (`import_type='users_export'`, `status='pending'`, field keys in `field_selection.field_keys`, filters in `metadata.filters`) and **nothing consumes it** — no DB function besides the starter mentions `users_export`, no cron, no queue. The single real row has been pending since 2026-07-02.

Implied worker contract: poll `status='pending' AND import_type='users_export'`, read `field_selection.field_keys` + `metadata.filters`, write CSV, set `file_url`, `started_at`, `completed_at`, `status`. Check `requirements/REGISTRY_RENDER.md` for whether a Render worker/cron was planned; if a worker exists externally but isn't polling, that's a Render-side fix, not DB.

## Item 6 — Audience integrity fixes (small, pre-launch)

- **`member_count` drift:** `admin_remove_user` / `system_remove_user` hard-`DELETE FROM amp_audience_member` without decrementing `amp_audience_master.member_count` and bypass `exited_at` soft-exit. Fix: either switch those deletes to soft-exit via `fn_remove_from_audience`, or add a trigger maintaining the count. Note the partial unique index `(audience_id, user_id) WHERE exited_at IS NULL` backstops duplicate inserts.
- **Activation state split across three flags:** `audience.is_active`, `workflow.is_active`, `trigger.is_active` can disagree — live sample: workflow `1ac21f25-0837-4e61-b02c-2dd4f93f28fa` (`[System] Audience: test flat payload`) is inactive while its trigger row is `trigger_active=true`. Make `bff_activate/deactivate_audience` set all three atomically.
- `bff_activate_audience(p_run_backfill)` does not run backfill (returns "Backfill should be triggered externally") — confirm with user whether backfill should call `bff_amp_batch_run` internally or stay external.

## Item 7 — Minor / opportunistic

- `bff_amp_analytics_workflow` returns bare JSONB with no `success` envelope (inconsistent with sibling BFFs; two hand-rolled envelopes, one `fn_response_*`). Align when next touched — response-shape change, needs FE coordination.
- `bff_amp_analytics_workflow` perf: `in_flight` uses uncorrelated `NOT IN` over `workflow_log`; `avg_completion_hours` uses per-row `LATERAL MAX()`. Fine at 28k rows; rewrite with window/aggregate CTEs when the log grows. `authenticated` role has a 30s statement timeout — that's the ceiling.
- No GIN index on tag/jsonb attribute columns on `user_accounts` (3.16M rows) — tag-shaped audience conditions will seq-scan the merchant slice. Defer until such conditions ship.

---

## Suggested execution order

1. Item 1 (pagination) + Item 3 indexes — one session, mechanical, low risk.
2. Item 2 (node stats contract) — after confirming FE-expected semantics for `completed_count`/`error_count`.
3. Item 3 chunking + Item 6 integrity fixes.
4. Item 4 — get the architecture decision first, then implement.
5. Item 5 — scope decision (build worker vs. remove the button).

## Next exact step for the implementing thread

Ask the user which items are approved, then for Item 1: `execute_sql` to dump `pg_get_functiondef` of `bff_get_audience_members(uuid,int,int,boolean)`, rewrite the members query with pagination inside a subquery, and `apply_migration`. Follow `10-function-conventions.mdc` and close with `06-update-docs.mdc` (REGISTRY_SUPABASE.md + CHANGELOG.md).

## Critical identifiers

- Functions: `bff_get_audience_members`, `bff_get_amp_workflow_node_stats`, `bff_get_amp_node_users`, `bff_amp_analytics_workflow`, `bff_amp_batch_run`, `bff_admin_start_user_export`, `fn_amp_find_matching_users`, `fn_evaluate_amp_condition_group`, `fn_add_to_audience`, `fn_remove_from_audience`, `fn_execute_amp_action`, `bff_create_audience`, `bff_activate_audience`, `bff_deactivate_audience`, `bff_upsert_amp_workflow_with_graph`, `admin_remove_user`, `system_remove_user`, `fn_normalize_thai_phone`, `fn_amp_lifecycle_date_matches`.
- Tables: `amp_audience_master`, `amp_audience_member`, `workflow_log` (~28k rows), `workflow_master`, `workflow_node`, `workflow_edge`, `workflow_trigger`, `bulk_import_batches`, `user_accounts` (~3.16M rows).
- Edge function: `amp-dispatch-workflow-batch`. Cron: `amp_run_due_scheduled_workflows` (every minute) — the only AMP cron; no export/audience-refresh cron exists.
- Sample inconsistent workflow: `1ac21f25-0837-4e61-b02c-2dd4f93f28fa`.
- Full evidence: subagent transcripts under agent-transcripts `afd1ed8b-96e5-43c2-a421-a15b6f55a7d9/subagents/` (audience: `682a5200…`, analytics/export: `dea6f3a0…`).
