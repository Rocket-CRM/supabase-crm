# AMP Workflows

Rule-based marketing automation: saved audiences, visual workflow graphs, simplified lifecycle automations, and the execution/analytics contracts that tie them to Inngest.

Owner surfaces: loyalty-admin (Audience Builder, Workflow List, Lifecycle Automations), loyalty-user (engagement beacon on member-app links), Render/Inngest (`inngest-amp-serve`, event routers), Supabase Edge (`amp-dispatch-realtime-event`, `amp-dispatch-workflow-batch`, `dispatch-workflow-trigger`, `link-redirect`, `engagement-beacon`)

## Concept

**AMP (Automated Marketing Platform)** in the rule-based lane lets merchants define *who* qualifies (audiences and condition nodes), *when* runs start (realtime domain events, schedules, manual batch, or audience entry), and *what* happens next (messages, waits, CRM actions, API calls, optional AI agent nodes). Execution is durable orchestration in Inngest; Postgres stores definitions, membership, and an append-only execution log.

**Workflow** — A directed graph of nodes and edges stored per merchant. Marketer-facing workflows (`scope = user`, `domain = campaign`) are built in Workflow List. The first node with no incoming edges is the entry (usually a condition). `workflow_trigger` rows declare which table/operation changes can start realtime matching; scheduled triggers add cron-driven batch runs.

**Audience** — A named segment backed by a hidden **system workflow** (`scope = system`, `domain = audience`) with the same condition grammar as campaign workflows. Membership lives in `amp_audience_member` (enter/exit timestamps, soft exit). Audiences can be **dynamic** (conditions + realtime + hourly reconciliation), **static** (snapshot at activation and explicit refresh), or **imported** (CSV membership; conditions not evaluated).

**Lifecycle automation** — A guided admin pattern for common lifecycle moments (signup, tier change, etc.): one event or schedule, ordered actions, implemented as `workflow_master` rows with dedicated BFFs (`bff_*_lifecycle_automation*`), not the full canvas.

**Execution lane** — How a user enters a run: **realtime** (outbox → Inngest routers → per-user trigger), **manual batch** (admin “Batch run” → SQL matcher → chunked dispatch), or **scheduled** (pg_cron every minute → due triggers → same matcher and dispatch). All bulk paths fan out through `amp-dispatch-workflow-batch` into per-user `amp/workflow.trigger` events.

**Condition engine** — Shared metadata (`bff_get_workflow_collections`) and evaluators compile audience/workflow criteria to SQL (batch) or per-user RPC (Inngest). Full field/operator contract: `requirements/AMP_Condition_Contract.md`.

**Engagement** — Message links wrapped per recipient; clicks and member-app page time/scroll depth feed analytics on nodes and workflows (LINE per-message open/delivery descoped).

Graph orchestration, node handlers, cache layer, and historical pipeline notes: `requirements/AMP - Rule Based.md`. AI agent nodes: `requirements/AMP - AI Decisioning.md`.

## Rules

### Workflow classification

| Dimension | Values | Effect |
| --- | --- | --- |
| `workflow_master.scope` | `user` (default), `system` | `system` workflows are infrastructure (audience engine); hidden from Workflow List. |
| `workflow_master.domain` | `campaign` (default), `audience` | Audience system workflows use `audience`. |
| `workflow_master.run_mode` | `event`, `batch`, … | How the admin UI classifies the workflow; triggers still govern realtime vs scheduled. |
| `workflow_master.config.allow_re_enrollment` | default `false` | When false, batch/scheduled matcher excludes users with `execution_started` in `workflow_log`; realtime path skips with `execution_skipped` unless the trigger is a continuation (postback/router). |

### Audience membership

- **Active member** — Row in `amp_audience_member` with `exited_at IS NULL`. `amp_audience_master.member_count` counts active members only.
- **Exit** — `admin_remove_user` / `system_remove_user` set `exited_at` and decrement `member_count`; rows are not hard-deleted.
- **Activation sync** — Activating an audience sets `amp_audience_master.is_active`, linked `workflow_master.is_active`, and `workflow_trigger.is_active` together. **Static** and **imported** audiences keep triggers inactive (no realtime enrollment from CDC).
- **Backfill on activate** — `bff_activate_audience(p_run_backfill default true)` runs `bff_amp_batch_run` for the system workflow when backfill is requested; activation succeeds even if backfill returns an error (error nested under `backfill` in the response).

### Audience types

| Type | Membership source | Realtime triggers | Ongoing sync |
| --- | --- | --- | --- |
| `dynamic` | Condition SQL + backfill | On (when active) | Hourly `fn_amp_reconcile_dynamic_audiences` resnapshot |
| `static` | Snapshot at activate + `bff_refresh_audience` | Off | Manual refresh only |
| `imported` | `bff_import_audience_members` (CSV) | Off | Import only; conditions ignored |

`bff_refresh_audience` / `fn_amp_resnapshot_audience` — For an **active** audience of any type: compile current conditions, soft-exit non-matches, insert new matches, recount `member_count`. Direct adds from resnapshot bypass enrollment logging; a later batch run may re-dispatch those users; `fn_add_to_audience` dedupe makes that harmless.

### Dynamic reconciliation

- pg_cron `amp-reconcile-dynamic-audiences` (`20 * * * *`) runs `fn_amp_reconcile_dynamic_audiences()` for each active dynamic audience → `fn_amp_resnapshot_audience`.
- Emits `workflow_log` event `audience_reconciled` per audience with `entered`, `exited`, `member_count`.

### Batch and scheduled dispatch

- `bff_amp_batch_run` → `fn_amp_find_matching_users` → `workflow_log` `batch_run_requested` → `fn_amp_dispatch_batch_chunks` (default 500 users per `pg_net` POST) → `amp-dispatch-workflow-batch` → per-user Inngest triggers.
- `fn_amp_run_due_scheduled_workflows` (pg_cron `amp_run_due_scheduled_workflows`, every minute) uses the same matcher and chunk helper; `scheduled_run_dispatched` logs carry `batch_count` and `pg_net_request_ids`.
- `amp-dispatch-workflow-batch` only validates workflow + emits events; it does not execute nodes.

### Condition evaluation (shared semantics)

- Batch matcher `fn_amp_find_matching_users` evaluates **all** groups on the first condition node; `groups_operator` `and`/`all` → INTERSECT, `or`/`any` → UNION (default AND).
- Per-user path `fn_evaluate_amp_condition_group` — group combination stays in the caller (Inngest).
- **Zero-row aggregates never match** in either path.
- `fn_amp_assert_collection` whitelists all 13 metadata collections plus pseudo-collection `amp_audience_member` (`is_member_of` / `is_not_member_of`).
- Audience entry: `fn_amp_resolve_entry_groups` synthesizes membership group when `entry_type = audience` and `groups` empty.
- **Content engagement** condition groups (click / page time / scroll) are workflow split-only — excluded from audiences, entry matching, and `bff_amp_preview_condition` (see `AMP_Condition_Contract.md` §4.5).
- Preview: `bff_amp_preview_condition` compiles only; count capped at 10,000 with `capped = true`; `statement_timeout` 30s on `authenticated`.

### Node stats and engagement

- Stats from `workflow_log` where `event_type IN ('node_executed','action_executed')`, scoped by `merchant_id`.
- `entered_count` / `unique_passed` = distinct users through node; `completed_count` = terminal success statuses (`executed`, `sent`, `delivered`); `error_count` = `failed` or `error_message` set.
- Message nodes expose `engagement` (tracked links, CTR, page metrics for member-app destinations only).
- Link wrap failures never block message send.

### Re-enrollment and continuations

- Default: one enrollment per user per workflow unless `allow_re_enrollment` is true.
- Continuations (LINE postback / router): enroll gate **skipped** when `parent_workflow_log_id`, `start_node_id`, or `trigger_data.source === 'line_postback'`.

### Admin i18n

Audience BFFs accept optional `p_language` (`en` \| `th`) for envelope titles via `fn_admin_envelope_message`.

## Journeys

| Surface | Repo | Primary RPCs / APIs |
| --- | --- | --- |
| Audience Builder | loyalty-admin | `bff_*_audience*`, `bff_get_workflow_collections`, `bff_amp_preview_condition`, `bff_import_audience_members` |
| Workflow List | loyalty-admin | `bff_get_amp_workflow_full`, `bff_upsert_amp_workflow_with_graph`, `bff_amp_batch_run`, `bff_get_amp_workflow_node_stats`, `bff_get_amp_node_users`, `bff_amp_analytics_workflow` |
| Lifecycle Automations | loyalty-admin | `bff_list/get/upsert/delete_lifecycle_automation`, `bff_get_lifecycle_action_options` |
| Member app (engagement) | loyalty-user | `engagement-beacon` edge (after `link-redirect` click with `rct` token) |

### Admin journey

| Setting / control | Effect |
| --- | --- |
| Audience type (dynamic / static / imported) | Whether conditions, realtime triggers, CSV import, or refresh drive membership |
| Activate audience + “Run backfill” | Turns on system workflow (and triggers for dynamic only); optional immediate batch population |
| Refresh audience | Re-runs condition snapshot for active audiences |
| Workflow `is_active` | Realtime triggers honored when active; batch/scheduled still require active workflow |
| `allow_re_enrollment` (workflow config) | Users can enter the same workflow on every batch/scheduled run |
| Batch run (Workflow List) | Immediate SQL match + dispatch without waiting for schedule or CDC |
| Schedule on condition/trigger node | `next_run_at` advanced by `fn_amp_compute_next_run_at`; cron picks due rows |
| Condition preview (audience or node) | Estimated audience size without saving |
| Export members / node users | `bff_admin_start_user_export` source modes — see Known gaps |
| Lifecycle event + actions | Creates/updates a linear automation without graph editor |

1. **Audience Builder** — Create audience (name, type, conditions unless imported). For imported, upload CSV via import modal → `bff_import_audience_members`. Save → `bff_create_audience` / `bff_update_audience`. Preview size → `bff_amp_preview_condition`. Activate (optional backfill) → `bff_activate_audience`. View members and 7/30-day analytics cards. Refresh or deactivate as needed.
2. **Workflow List** — List `scope=user` workflows. Open canvas → load graph → edit nodes (condition, message, wait, action, API, agent) → save `bff_upsert_amp_workflow_with_graph`. Activate workflow. Run batch manually. Inspect per-node stats, engagement tab, and user list modals. Duplicate workflow when needed (`bff_duplicate_amp_workflow`).
3. **Lifecycle Automations** — List automations → create/edit wizard (lifecycle event, tier filters where applicable, ordered actions, schedule vs database trigger) → `bff_upsert_lifecycle_automation`. Toggle active state via same upsert contract.

### Member journey

1. **Message** — Receives LINE/SMS (or other channel) from a workflow message node; URLs in the payload are tracked redirects.
2. **Click** — Browser hits `link-redirect` → click logged → redirect to destination with `rct` query param.
3. **Member app** — If destination is Rocket Loyalty app, client sends page view / time on page / scroll depth to `engagement-beacon` (contract: `docs/AMP_ENGAGEMENT_BEACON_SPEC.md`).
4. **Postback / router** — LINE button postback can resume workflow at a configured node without re-enrollment gate (continuation path).
5. **Errors** — Failed sends and node errors appear in `workflow_log` for admin analytics; member may see provider-level delivery failure only (no separate member-facing workflow status page).

## System

### Data model

| Table | Role |
| --- | --- |
| `workflow_master` | Workflow identity: `workflow_code`, `name`, `scope`, `domain`, `run_mode`, `is_active`, `config` (incl. re-enrollment), merchant scope |
| `workflow_node` | Graph nodes: `node_type`, `node_config` (conditions, messages, schedules, actions) |
| `workflow_edge` | Directed edges between nodes (handles for branching) |
| `workflow_trigger` | Realtime (`trigger_table` / `trigger_operation` / `trigger_conditions`) or scheduled (`trigger_type`, `next_run_at`, `last_run_at`, `schedule_status`) |
| `workflow_log` | Event-sourced execution log: `event_type`, `node_id`, `status`, `inngest_run_id`, `parent_workflow_log_id`, costs, LINE ids |
| `amp_audience_master` | Audience metadata, `audience_type`, `workflow_id`, `member_count`, `funnel_id` / `funnel_sort_order` when used in funnel UX |
| `amp_audience_member` | Membership rows: `entered_at`, `exited_at`, `source_workflow_id` |
| `amp_tracked_link` | Per-recipient wrapped URL tokens |
| `amp_engagement_event` | Click and page engagement events |
| `inngest_workflow_log` | Auxiliary Inngest run metadata (separate from `workflow_log`) |

Indexes on `workflow_log` include `(workflow_id, node_id, event_type)` and `(workflow_id, event_type)` for analytics queries.

### Functions

**Audience BFFs** — `bff_create/update/delete/list_audiences`, `bff_activate/deactivate_audience`, `bff_refresh_audience`, `bff_get_audience_members`, `bff_get_audience_analytics`, `bff_import_audience_members`.

**Workflow graph BFFs** — `bff_get_amp_workflow_full`, `bff_upsert_amp_workflow_with_graph`, `bff_duplicate_amp_workflow`, `bff_get_workflow_collections` (+ v2/v3/v4 extension helpers), `bff_amp_preview_condition`.

**Run and match** — `bff_amp_batch_run`, `fn_amp_find_matching_users`, `fn_amp_compile_workflow_match_sql`, `fn_amp_compile_condition_group`, `fn_amp_compile_audience_membership`, `fn_amp_eval_audience_membership`, `fn_amp_resolve_entry_groups`, `fn_amp_reconcile_dynamic_audiences`, `fn_amp_resnapshot_audience`, `fn_amp_run_due_scheduled_workflows`, `fn_amp_dispatch_batch_chunks`, `fn_amp_user_already_enrolled`, `fn_add_to_audience`.

**Analytics** — `bff_get_amp_workflow_node_stats`, `bff_get_amp_node_users`, `bff_get_amp_node_link_stats`, `bff_amp_analytics_workflow`, `bff_amp_analytics_overview`, `bff_amp_analytics_user_timeline`, `bff_get_resource_content_engagement`.

**Lifecycle** — `bff_list/get/upsert/delete_lifecycle_automation`, `bff_get_lifecycle_action_options`.

**Engagement** — `fn_amp_wrap_tracked_links`, `fn_amp_create_tracked_link`, `api_log_amp_workflow_event`.

**Graph helpers** — `fn_get_amp_workflow_entry_node`, `fn_get_amp_workflow_next_nodes`, `fn_get_workflow_graph_cached`.

**Triggers** — `trigger_amp_workflow_trigger_set_next_run_at` on `workflow_trigger` insert.

### Flows

**Realtime enrollment**

```text
Domain write → chokepoint_event_outbox → OutboxPublisher → inngest-event-router-serve (amp-*-router)
  → amp-dispatch-realtime-event → dispatch-workflow-trigger (match workflow_trigger)
  → amp/workflow.trigger → inngest-amp-serve (per user, condition eval, nodes, actions)
  → workflow_log append + api_log_amp_workflow_event
```

**Audience system workflow** — Same pipeline: CDC/outbox on referenced tables adds users via `add_to_audience`; `amp_audience_member` INSERT can trigger **campaign** workflows whose triggers reference that `audience_id`.

**Manual / scheduled batch** — `bff_amp_batch_run` or `fn_amp_run_due_scheduled_workflows` → `fn_amp_find_matching_users` (re-enrollment filter) → chunked HTTP to `amp-dispatch-workflow-batch` → N × `amp/workflow.trigger`.

**Message send** — Message node → `fn_amp_wrap_tracked_links` → messaging service; `workflow_log_id` backfilled on `amp_tracked_link` after send log insert.

**Scheduled cron** — `amp_run_due_scheduled_workflows` (`* * * * *`) → `fn_amp_run_due_scheduled_workflows()`.

**Dynamic audience cron** — `amp-reconcile-dynamic-audiences` (`20 * * * *`) → `fn_amp_reconcile_dynamic_audiences()`.

### External services

| Service | Role |
| --- | --- |
| `inngest-amp-serve` | Durable workflow executor (node handlers, enroll gate, engagement condition delegation) |
| `inngest-event-router-serve` | Routes domain events to AMP dispatch |
| Edge `amp-dispatch-realtime-event` | Realtime fan-in to trigger matching |
| Edge `amp-dispatch-workflow-batch` | Batch fan-out to Inngest |
| Edge `dispatch-workflow-trigger` | Matches triggers and starts runs |
| Edge `link-redirect` | Click tracking redirect |
| Edge `engagement-beacon` | Member-app engagement ingest |
| Upstash Redis (`amp-cache`) | Hot-path config cache — see `AMP - Cache Layer.md` |

### Known gaps

- **User export worker** — `bff_admin_start_user_export` enqueues `bulk_import_batches` with `import_type = users_export` for audience, condition preview, workflow, and workflow-node sources (`requirements/Customer_Export.md`), but no consumer processes those rows yet; jobs remain `pending`.
- **Audience CDC via Debezium** — Optional future path for `amp_audience_member` inserts documented as pending in `AMP - Rule Based.md` (live path uses outbox/Inngest).
- **Condition config debt** — Some live workflows reference virtual fields not in the contract (`birth_month`, `service_type`, `expiry_days_remaining`, `tier_eval_days_remaining`); compiler now fails loudly — configs need cleanup or contract extension.
- **Registry** — `bff_import_audience_members` exists in DB but may be missing from `REGISTRY_SUPABASE.md` until next regen.
- **Member engagement beacon** — FE integration per `docs/AMP_ENGAGEMENT_BEACON_SPEC.md` may still be partial on all member routes.

## Related

- `requirements/AMP - Rule Based.md` — Workflow graph, node types, Inngest executor, triggers, messaging funnel, pipeline architecture.
- `requirements/AMP_Condition_Contract.md` — Condition builder metadata, operators, content-engagement groups.
- `requirements/AMP - AI Decisioning.md` — Agent nodes in the same graph.
- `requirements/AMP - Cache Layer.md` — Redis cache for triggers and graph reads.
- `requirements/Customer_Export.md` — Export `p_source` shapes for audience, condition, workflow, and node users.
- `requirements/Notification_Service.md` — Channel delivery for message nodes where not inline LINE/SMS.
