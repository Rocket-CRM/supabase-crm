# AMP Workflows

Rule-based marketing automation: saved audiences, visual workflow graphs, simplified lifecycle automations, and the execution/analytics contracts that tie them to Inngest.

Owner surfaces: loyalty-admin (Audience Builder, **Targeted broadcast**, Workflow List, Reports → Audiences, Earn Rules → Lifecycle), loyalty-user (engagement beacon on member-app links), Render/Inngest (`inngest-amp-serve`, event routers), Supabase Edge (`amp-dispatch-realtime-event`, `amp-dispatch-workflow-batch`, `dispatch-workflow-trigger`, `link-redirect`, `engagement-beacon`), messaging-service (LINE push / broadcast / multicast)

## Concept

**AMP (Automated Marketing Platform)** replaces the manual loop of exporting member data, filtering a target list, and uploading it to LINE for a broadcast. Every outbound communication answers three questions, each configured in its own place: **who** receives it (Audience), **how and when** it is sent (a workflow, or a one-shot targeted broadcast), and **what** is sent (Content Library — see `Resource_Content.md`). A journey starts from a CRM event or a schedule (signup, first purchase, new tier, points threshold), then conditions, waits, and actions take over without staff involvement.

**Audience** — A named group of members defined by conditions over any CRM data (profile, purchases, currency, tier, persona, tags, form answers, …). “Segment” in client language means the same thing. Tier and persona are also groupings, but they are primary classifications that other loyalty logic reads (earn multipliers, reward eligibility); an audience is a custom grouping for marketing, and tier or persona can be one of its inputs. Audiences are **reusable**: build one once and pick it as the entry of any workflow or broadcast instead of re-entering conditions.

**Audience type** — *When* members enter. **Dynamic**: a member joins the moment their data changes to match (non-matches are removed by an hourly reconciliation), so an audience built once keeps itself current. **Static**: membership is a snapshot, updated only on refresh — manually by the admin or daily at a set time. **Imported**: membership comes from an uploaded CSV of existing members; conditions are ignored. Example: conditions “Silver tier and spend ≥ 100,000 THB in 12 months”; a member at 90,000 who buys another 10,000 at 09:00 enters a dynamic audience immediately, but a daily-refresh static audience at 23:00 that night. Dynamic costs more compute because every relevant data change is re-evaluated; the product does not gate types by plan today.

**Audience uses** — **Analyse**: per-audience reports (size, purchase rate, average order, wallet balance, trends) and a cross-audience comparison (e.g. revenue per member by audience). **Act**: a targeted broadcast or a workflow.

**Targeted broadcast** — One identical LINE message sent once to a chosen audience, all LINE friends, or LINE friends who are not yet members (a conversion play). It sits between blanket broadcast and personalization: everyone receives the same content, but only within the chosen group. Audience-based broadcasts reach members with a linked LINE account only.

**Workflow** — A directed graph of nodes run per member, for anything that needs more than one step: send, wait, branch on behaviour, send again. Node families: **flow control** (entry condition — mandatory, defines who enters; conditional split — true/false branch; time delay — minutes to months; LINE interaction router — one branch per button the member taps), **messages** (LINE, SMS — the outcome the member sees), **loyalty actions** (award currency, push reward, assign/remove tag, assign persona, grant a private earn factor for a window, submit a form response on the member's behalf), **audience actions** (add to / remove from audience), **webhook** (call a third-party URL), and **AI agent** (merchant brings its own model key; `AMP - AI Decisioning.md`). Loyalty actions only offer objects that already exist in their module (rewards, earn factors, personas, forms).

**Lifecycle automation** — A simplified, linear automation that fires on a moment in the member's life with the brand rather than on something the member did: sign-up, tier upgraded, tier downgraded, birthday, membership anniversary. Normal earning requires member action (buy, play a campaign); lifecycle automation observes these events and delivers something anyway (birthday points, a coupon on tier upgrade, a consolation coupon on downgrade, auto-assign a starter persona on sign-up). It is configured in the Earn Rules hub, not the workflow canvas, but runs on the same workflow engine with the same action set.

**Execution lane** — How a member enters a run: **realtime** (a data change matches a trigger), **manual batch** (admin runs the workflow now against everyone matching), or **scheduled** (a recurring time). All three converge on the same per-member executor.

**Condition engine** — One shared field/operator grammar for audiences, entry conditions, and splits, evaluated in bulk for batch runs and per member for realtime. Contract: `AMP_Condition_Contract.md`.

**Engagement** — Message links are wrapped per recipient; clicks and member-app page time/scroll depth feed node and workflow analytics (LINE per-message open/delivery descoped).

Graph orchestration, node handlers, cache layer, and historical pipeline notes: `requirements/AMP - Rule Based.md`. AI agent nodes: `requirements/AMP - AI Decisioning.md`.

## Rules

### Workflow classification

| Dimension | Values | Effect |
| --- | --- | --- |
| `workflow_master.scope` | `user` (default), `system` | `system` workflows are infrastructure (audience engine); hidden from Workflow List. |
| `workflow_master.domain` | `campaign` (default), `audience`, `loyalty` | Audience system workflows use `audience`; lifecycle automations use `loyalty` (`scope = user`) and are edited only through the lifecycle editor. |
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
| `static` | Snapshot at activate + `bff_refresh_audience` | Off | `refresh_schedule`: `manual` (default) or `daily` at `refresh_time` (merchant local) |
| `imported` | `bff_import_audience_members` (CSV) | Off | Import only; conditions ignored |

**CSV import** — Rows match existing members only, on `tel`, `email`, and/or `member_code`; unmatched rows are returned as `not_found` and never create members, so non-member LINE friends cannot be imported (reach them with the *LINE friends (non-members)* broadcast or entry type). Max 10,000 rows per request; mode `append` (default) or `replace` (soft-exits current members first); duplicate rows for one member are reported, not double-added.

`bff_refresh_audience` / `fn_amp_resnapshot_audience` — For an **active** audience of any type: compile current conditions, soft-exit non-matches, insert new matches, recount `member_count`, set `last_refreshed_at`. Direct adds from resnapshot bypass enrollment logging; a later batch run may re-dispatch those users; `fn_add_to_audience` dedupe makes that harmless. Whether resnapshot inserts start campaign workflows whose trigger is `audience_entered` is unverified.

### Scheduled static refresh

- `amp_audience_master`: `refresh_schedule` (`manual` | `daily`), `refresh_time`, `next_refresh_at`, `last_refreshed_at`. Set via `bff_create_audience` / `bff_update_audience` (`p_refresh_schedule`, `p_refresh_time`); `next_refresh_at` computed on save/activate, cleared on deactivate.
- pg_cron `amp_run_due_audience_refreshes` (`*/5 * * * *`) → `fn_amp_run_due_audience_refreshes()`: active daily static audiences with `next_refresh_at <= now()` (`SKIP LOCKED`) → `fn_amp_resnapshot_audience` → advance `next_refresh_at`. Timezone: `merchant_display_settings.ui_config->>'timezone'`, else `Asia/Bangkok`.
- Targeted broadcast to a static audience resnapshots first when `amp_broadcast_master.refresh_before_send` is true (default).

### Dynamic reconciliation

- pg_cron `amp-reconcile-dynamic-audiences` (`20 * * * *`) runs `fn_amp_reconcile_dynamic_audiences()` for each active dynamic audience → `fn_amp_resnapshot_audience`.
- Emits `workflow_log` event `audience_reconciled` per audience with `entered`, `exited`, `member_count`.

### Entry types

| `entry_type` | Dispatch |
| --- | --- |
| `audience` | Member runs from audience membership (synthetic membership group when `groups` empty). |
| `condition` | Member runs for users matching entry condition groups. |
| `all_line_friends` | One LINE **broadcast** run (`run_scope = broadcast`). |
| `line_option_selected` | Realtime enrollment on LINE postback (no batch). |
| `past_line_interaction` | One **push** run per matching LINE user (`run_scope = line`). |
| `all_line_friends_exclude_members` | On activate or **schedule**: page LINE follower IDs (messaging-service), drop friends linked on `user_accounts.line_id`, one **push** per remaining friend (`run_scope = line`). When `allow_re_enrollment` is off, friends who already have `execution_started` for this workflow (matched by `line_user_id`) are skipped before fan-out. Requires verified/premium LINE OA; members without linked LINE are not excluded. |

### Targeted broadcast (one-shot LINE send)

**Targeted broadcast** is a separate admin surface (`/targeted-broadcast`) for a **single identical LINE message** to an audience — not a workflow journey. Use workflows when waits, branches, or per-recipient follow-up matter.

| Audience | Delivery |
| --- | --- |
| Segment (`audience`) | Active `amp_audience_member` with linked `line_id` and `channel_line` not false → LINE **multicast** in chunks of 500 |
| All LINE friends | One LINE **broadcast** API call |
| LINE friends (non-members) | Follower list minus linked members → **multicast** in chunks of 500 |

Rules: no merge fields, no per-recipient tracked links. Member-app links carry `?bc=<broadcast_id>`; logged-in members report page engagement via `engagement-beacon` → `amp_engagement_event.broadcast_id`. Content Library postback buttons are signed with broadcast context (`b=`); taps record `fn_amp_record_broadcast_postback` and can enroll **When LINE option selected** workflows. Frozen recipient batches in `amp_broadcast_batch`; send orchestration via Inngest `amp/broadcast.send` (`inngest-amp-serve`). Scheduled sends: `fn_amp_run_due_broadcasts` (pg_cron `amp_run_due_broadcasts`, every minute).

After send: admin **Refresh LINE stats** (`bff_amp_refresh_broadcast_line_stats` → messaging-service insight APIs; broadcast mode uses stored `line_request_id`, multicast uses custom aggregation unit = broadcast id). **Create segment from clickers** → static audience via `bff_amp_create_audience_from_broadcast_clickers`.

**Send log:** once a send starts, the broadcast page shows one row per LINE call (`amp_broadcast_batch`): recipients (blank = all friends), status `pending` / `sent` / `failed`, attempts, sent time, error, LINE request ID. Filter by status; 50 per page via `bff_list_amp_broadcast_batches` (never returns `line_user_ids`). LINE accepts or rejects a whole call, so there is no per-recipient result. `bff_get_amp_broadcast_details` returns only `batch_summary` counts. The audience detail page lists sends to that segment (`bff_list_amp_broadcasts(p_audience_id, p_limit, p_offset)`); a row opens the same send log.

Admin BFFs: `bff_list/get/upsert_amp_broadcast`, `bff_list_amp_broadcast_batches`, `bff_amp_estimate_audience`, `bff_amp_send/cancel/test_send_broadcast`, `bff_amp_refresh_broadcast_line_stats`, `bff_amp_create_audience_from_broadcast_clickers`.

### Batch and scheduled dispatch

- `bff_amp_batch_run` → `fn_amp_find_matching_users` → `workflow_log` `batch_run_requested` → `fn_amp_dispatch_batch_chunks` (default 500 users per `pg_net` POST) → `amp-dispatch-workflow-batch` → per-user Inngest triggers.
- `fn_amp_run_due_scheduled_workflows` (pg_cron `amp_run_due_scheduled_workflows`, every minute) uses the member matcher and chunk helper for most entry types; **`all_line_friends`** and **`all_line_friends_exclude_members`** dispatch like manual batch run (broadcast run vs follower seed). `scheduled_run_dispatched` logs carry `batch_count` and `pg_net_request_ids` where applicable.
- `amp-dispatch-workflow-batch` only validates workflow + emits events; it does not execute nodes.

### Condition evaluation (shared semantics)

- Batch matcher `fn_amp_find_matching_users` evaluates **all** groups on the first condition node; `groups_operator` `and`/`all` → INTERSECT, `or`/`any` → UNION (default AND).
- Per-user path `fn_evaluate_amp_condition_group` — group combination stays in the caller (Inngest). **Conditional Split** nodes use the same SQL evaluator (no client-side filter subset).
- **Zero-row aggregates never match** in either path.
- **Gender** compares case-insensitively for `equals` / `not_equals` / `in` / `not_in` (`fn_amp_build_condition_clause`): stored values follow each merchant's `user_field_config` (e.g. `male`) while metadata emits `MALE` / `FEMALE` / `NOT_SPECIFIED`. NULL semantics unchanged — unset gender does not match `not_equals`.
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
| Targeted broadcast | loyalty-admin | `bff_*_amp_broadcast*`, `bff_list_amp_broadcast_batches`, `bff_amp_estimate_audience`, `bff_amp_send/cancel/test_send_broadcast`, `bff_amp_refresh_broadcast_line_stats`, `bff_amp_create_audience_from_broadcast_clickers` |
| Workflow List | loyalty-admin | `bff_get_amp_workflow_full`, `bff_upsert_amp_workflow_with_graph`, `bff_amp_batch_run`, `bff_get_amp_workflow_node_stats`, `bff_get_amp_node_users`, `bff_amp_analytics_workflow` |
| Reports → Audiences (compare + per-audience) | loyalty-admin | `bff_report_audience_compare`, `bff_report_audience` |
| Earn Rules hub → Lifecycle section (list) + lifecycle editor | loyalty-admin | `bff_list/get/upsert/delete_lifecycle_automation`, `bff_get_lifecycle_action_options` |
| Member app (engagement) | loyalty-user | `engagement-beacon` edge (`rct` from tracked links; `bc` + member JWT for broadcast attribution) |

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
| Entry type (entry condition node) | Audience, custom condition, all LINE friends, LINE friends excluding members, when a LINE option is selected, or past LINE content interaction — see Entry types |
| Interaction router: upstream message + selection mode | Router reads button keys from the chosen upstream LINE message node only (editing the resource in Content Library alone does not add keys); `single` continues on the first key tapped, `multiple` runs one branch per key |
| Broadcast recipients | Segment, all LINE friends, or LINE friends who are not members |
| Broadcast content | Content Library resource (can create one inline), custom Flex JSON, or text with quick-reply pills |
| Broadcast “Refresh segment before sending” | Re-snapshots a static audience immediately before send (default on) |
| Lifecycle event + target tier + actions | Linear automation; `to_tier_id` limits tier-change events to one destination tier; birthday and anniversary run daily at a set time with an optional day offset |

1. **Audience Builder** — Create audience (name, type, conditions unless imported). For imported, upload CSV via import modal → `bff_import_audience_members`. Edit loads the audience with its saved conditions via `bff_get_audience_details` (the list payload omits conditions). Save → `bff_create_audience` / `bff_update_audience`. Preview size → `bff_amp_preview_condition`. Activate (optional backfill) → `bff_activate_audience`. View members and 7/30-day analytics cards. Refresh or deactivate as needed. From the audience, **View analytics** opens its report; **broadcast** opens Targeted broadcast pre-filled with the segment.
2. **Reports → Audiences** — Compare all audiences against each other and against all members for a date range; open one audience for its own trends.
3. **Workflow List** — List marketer workflows. Open canvas → place the entry condition (pick a saved audience or enter conditions; preview matching members before running) → add flow-control, message, loyalty, audience, webhook, and agent nodes from the palette → save `bff_upsert_amp_workflow_with_graph`. When a LINE message carries postback buttons, put a LINE interaction router on the edge after it so taps continue the journey; a time delay only waits and does not detect clicks. To act on whether the member did something (e.g. used a pushed reward), place a time delay before a conditional split so they have time to act. Activate workflow. Run batch manually. Inspect per-node stats, engagement tab, and user list modals. Duplicate workflow when needed (`bff_duplicate_amp_workflow`).
4. **Targeted broadcast** — New broadcast → choose recipients (segment shows deliverable count of members with linked LINE) → choose content → optional test send to up to 5 member IDs → send now or schedule → watch send log; afterwards refresh LINE stats or create a static segment from clickers.
5. **Earn Rules → Lifecycle section** — The lifecycle list is embedded in the Earn Rules hub (no standalone menu entry; plan-locked where the lifecycle feature is off). Create/edit opens the lifecycle editor: choose the event, optional destination tier for tier changes, daily time and day offset for birthday/anniversary, then ordered actions (award currency, push reward, assign/remove tag, assign persona, earn factor, submit form) → `bff_upsert_lifecycle_automation`. Toggle active state via the same upsert.

### Member journey

1. **Message** — Receives LINE/SMS (or other channel) from a workflow message node, or an identical LINE message from a targeted broadcast; workflow URLs are tracked redirects, broadcast member-app links carry the broadcast id instead. Members without linked LINE (or opted out of LINE) receive nothing from LINE sends.
2. **Click** — Browser hits `link-redirect` → click logged → redirect to destination with `rct` query param.
3. **Member app** — If destination is Rocket Loyalty app, client sends page view / time on page / scroll depth to `engagement-beacon` (contract: `docs/AMP_ENGAGEMENT_BEACON_SPEC.md`).
4. **Postback / router** — Tapping a postback button (e.g. card 1 “Price”, card 2 “Promotion”) continues the member down the router branch for that key without the re-enrollment gate; the member simply receives that branch's next message or reward. A tap on a broadcast button can enroll them into a *When LINE option selected* workflow.
5. **Lifecycle** — On sign-up, tier change, birthday, or anniversary the member receives the configured currency, reward, persona, or tag with no action of their own; it appears in their wallet/history like any other grant.
6. **Errors** — Failed sends and node errors appear in `workflow_log` for admin analytics; member may see provider-level delivery failure only (no separate member-facing workflow status page).

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
| `amp_broadcast_master` | Targeted broadcast definition: audience type, `message_config`, status, counts, schedule |
| `amp_broadcast_batch` | Frozen LINE send units (≤500 `line_user_ids` per row, or empty for broadcast mode) |
| `inngest_workflow_log` | Auxiliary Inngest run metadata (separate from `workflow_log`) |

Indexes on `workflow_log` include `(workflow_id, node_id, event_type)` and `(workflow_id, event_type)` for analytics queries.

### Functions

**Audience BFFs** — `bff_create/update/delete/list_audiences`, `bff_get_audience_details` (single audience + `conditions` from the system workflow's condition node), `bff_activate/deactivate_audience`, `bff_refresh_audience`, `bff_get_audience_members`, `bff_get_audience_analytics`, `bff_import_audience_members`.

**Workflow graph BFFs** — `bff_get_amp_workflow_full`, `bff_upsert_amp_workflow_with_graph`, `bff_duplicate_amp_workflow`, `bff_get_workflow_collections` (+ v2/v3/v4 extension helpers), `bff_amp_preview_condition`.

**Run and match** — `bff_amp_batch_run`, `fn_amp_find_matching_users`, `fn_amp_compile_workflow_match_sql`, `fn_amp_compile_condition_group`, `fn_amp_compile_audience_membership`, `fn_amp_eval_audience_membership`, `fn_amp_resolve_entry_groups`, `fn_amp_reconcile_dynamic_audiences`, `fn_amp_resnapshot_audience`, `fn_amp_run_due_scheduled_workflows`, `fn_amp_dispatch_batch_chunks`, `fn_amp_user_already_enrolled`, `fn_amp_filter_enrolled_line_ids`, `fn_amp_segment_broadcast_line_ids`, `fn_add_to_audience`.

**Targeted broadcast** — `bff_list/get/upsert_amp_broadcast`, `bff_list_amp_broadcast_batches`, `bff_amp_estimate_audience`, `bff_amp_send/cancel/test_send_broadcast`, `bff_amp_refresh_broadcast_line_stats`, `bff_amp_create_audience_from_broadcast_clickers`, `fn_amp_run_due_broadcasts`, `fn_amp_record_broadcast_beacon`, `fn_amp_record_broadcast_postback`.

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

**Targeted broadcast cron** — `amp_run_due_broadcasts` (`* * * * *`) → `fn_amp_run_due_broadcasts()`.

**Dynamic audience cron** — `amp-reconcile-dynamic-audiences` (`20 * * * *`) → `fn_amp_reconcile_dynamic_audiences()`.

### External services

| Service | Role |
| --- | --- |
| `inngest-amp-serve` | Durable workflow executor; `amp/broadcast.send` for targeted broadcast |
| messaging-service | LINE push, broadcast, multicast; `GET /line/quota`, `GET /line/insight/delivery`, `GET /line/insight/aggregation`, `POST /line/followers` |
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
