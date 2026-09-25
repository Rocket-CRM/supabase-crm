# Daily audience refresh + Targeted broadcast + LINE friend audiences — end-to-end plan (2026-09-25)

Status: planned, not started. Supabase project `wkevmsedchftztoolkmi`.

## Goal

1. **Daily audience refresh** — a segment that is not real-time: membership recomputed once a day at a merchant-chosen time (or manually), no realtime triggers.
2. **Targeted broadcast** — push LINE content once to a segment or LINE friend audience.
3. **LINE friend audiences in workflows** — for multi-step journeys.

Same audiences in two places, different jobs:

| Audience | Targeted broadcast (one message) | Workflow (journey) |
|---|---|---|
| A segment (AMP audience) | Multicast to linked members, 500 per call | As today — one run per member |
| All LINE friends | One LINE broadcast call | One shared run for everyone; waits apply to all, no per-friend branching |
| LINE friends who aren't members | Follower list minus linked members → multicast, 500 per call | One run per friend — waits, branches, button follow-ups work per friend |

Rule for admins: **one message → broadcast; anything that happens after → workflow.** The workflow builder says so on both friend entries and links to broadcast.

Broadcast rules: identical content for all recipients, no merge fields, no per-recipient tracked links, one send tag on member-app links, no postback buttons in v1. Bypasses the workflow engine (one sender run per send, not per recipient).

## Current state (verified 2026-09-25)

- Audience types (`amp_audience_master.audience_type`, default `'dynamic'`): `dynamic` (realtime triggers + hourly pg_cron `amp-reconcile-dynamic-audiences` → `fn_amp_reconcile_dynamic_audiences()` → `fn_amp_resnapshot_audience`), `static` (snapshot at activate + manual `bff_refresh_audience(p_audience_id, p_language)`), `imported` (CSV only). No scheduled refresh for static.
- `amp_audience_master` live columns: `id, merchant_id, name, description, workflow_id, is_active, member_count, created_at, updated_at, audience_type, funnel_id, funnel_sort_order`. No schedule or `last_refreshed_at` column.
- `fn_amp_resnapshot_audience(p_audience_id)` works for any active audience: compile conditions, soft-exit non-matches, insert new matches, recount; emits `workflow_log` `audience_reconciled` (`entered`, `exited`, `member_count`). Direct adds bypass enrollment logging (`requirements/AMP_Workflows.md#Rules > Audience types`).
- No DB triggers on `amp_audience_member`; workflows keyed to audience entry are driven via CDC/outbox. Whether resnapshot inserts start those workflows is **unverified** — see Phase 1a check.
- `All LINE Friends` (`all_line_friends`): `bff_amp_batch_run` → `amp-dispatch-workflow-batch` emits one Inngest event → one `run_scope=broadcast` run in `inngest-amp-serve` → messaging-service `recipient.mode="broadcast"` → LINE `/v2/bot/message/broadcast`.
- `All LINE Friends (exclude members)` (`all_line_friends_exclude_members`): one seed run in `inngest-amp-serve` (~L895–929) pages LINE `/v2/bot/followers/ids` via messaging-service `POST /line/followers`, filters with `fn_amp_filter_non_member_line_ids` (migration `20260923251000_amp_line_friends_exclude_members.sql`), then emits one Inngest run per friend (`run_scope=line`, chunks of 500) → per-friend LINE push.
- Neither friend entry type runs on schedule: `fn_amp_run_due_scheduled_workflows` has no branch for them. UI copy in `loyalty-admin/.../workflow-list/lib/workflow-validation.ts` (~L52–56) says “scheduled runs don't apply” for exclude-members.
- Exclude-members fan-out has no re-enrollment dedupe by `line_user_id` (inferred). `past_line_interaction` dedupes in `fn_amp_find_matching_line_subjects`.
- No tracked links / merge fields on either friend path (`fn_amp_wrap_tracked_links` skipped when broadcast or no `user_id`, `inngest-amp-serve` ~L692).
- messaging-service `SendMode = "push" | "broadcast"` only (`src/adapters/types.ts`, `src/adapters/line.ts`, `src/index.ts` `/send`, `resolve-recipient.ts`). No retry/rate-limit handling. Credentials via `getCredentials(merchant_id, "LINE")` → `merchant_credentials` `service_name='line_messaging'`.
- No LINE quota API calls anywhere. No follower/unfollow table. Blocked detection only via notification path setting `channel_line=false`.
- Workflow LINE message `node_config` (`loyalty-admin/src/lib/workflow/line-message-config.ts`): Content Library `resource_id`, custom Flex `json_content`, or text + `quick_replies`. Send-time resolve: `fn_resolve_resource_for_delivery` (`inngest-amp-serve` ~L439).
- Reusable admin UI: `LineMessageConfigFields` uses `ContentResourcePickerModal` + `LinePreview`; preview RPC `bff_preview_resource_line_flex`. No test-send exists for LINE.
- AMP-signed postbacks require a `workflow_log` row (`inngest-amp-serve` ~L35–41, ~L682–690; `webhook-line` ~L239–253).
- `line_option_selected` entry: `postbackContinue` scans workflows with `domain='amp'` (`inngest-amp-serve` ~L1536) but workflows are saved as `domain='campaign'` (`workflow-list-page.tsx` ~L112) — likely never enrolls.
- Attribution today is per-recipient: `fn_amp_create_tracked_link` keyed by `user_id`; `link-redirect` → `amp_engagement_event`; beacon keyed by `rct` token. No `rct` handling in `loyalty-user/src`.
- Scheduling pattern to mirror: `workflow_trigger` + `fn_amp_run_due_scheduled_workflows` (pg_cron `amp_run_due_scheduled_workflows`, every minute; `next_run_at`, `schedule_status`, `FOR UPDATE SKIP LOCKED`, `fn_amp_compute_next_run_at`).
- Admin routes: `/audience-builder` (list/builder/detail), `/workflow-list` (canvas). Entry dropdown `ENTRY_OPTIONS` in `condition-config.tsx` (~L36–43); summaries `workflow-nodes.tsx` (~L150). AMP nav order in `menu-transforms.ts` (~L103–108); menu data from admin profile menu (see `20260706_flatten_amp_admin_menu.sql`).

## Phase 1a — Daily audience refresh

Static audiences get a refresh schedule: **Manual** (today) or **Daily at HH:MM** (merchant local time). Realtime stays off. Dynamic audiences keep realtime + hourly; imported audiences have no conditions, so no schedule.

### Backend — Supabase

- Columns on `amp_audience_master`: `refresh_schedule text NOT NULL DEFAULT 'manual'` (`manual` | `daily`, check constraint), `refresh_time time` (local), `next_refresh_at timestamptz` (partial index where `refresh_schedule = 'daily' AND is_active`), `last_refreshed_at timestamptz` (set by every refresh path: activate snapshot, manual, scheduled, hourly dynamic).
- `fn_amp_run_due_audience_refreshes()` — pick active daily static audiences with `next_refresh_at <= now()` (`FOR UPDATE SKIP LOCKED`), call `fn_amp_resnapshot_audience`, set `last_refreshed_at`, advance `next_refresh_at` (reuse the timezone logic in `fn_amp_compute_next_run_at`). One audience failing must not block the rest; log failure to `workflow_log` like `audience_reconciled`.
- pg_cron every 5 minutes → `fn_amp_run_due_audience_refreshes()`.
- Extend the audience create/update BFFs (`bff_create_audience`, `bff_update_audience` — verify current signatures) with `p_refresh_schedule`, `p_refresh_time`; compute `next_refresh_at` on save/activate; clear on deactivate. Audit via existing BFF logging.
- `bff_list_audiences` / audience detail return `refresh_schedule`, `refresh_time`, `last_refreshed_at`, `next_refresh_at`.
- **Check before build:** do members added by `fn_amp_resnapshot_audience` start workflows whose entry is “joins this audience”? If not, a daily audience can't kick off journeys for new entrants. Decide whether resnapshot should emit entry events for new members (preferred: yes, so daily refresh drives journeys).

Scale: one SQL pass per audience per day — 24× lighter than the hourly dynamic reconcile already running. Cost is driven by condition complexity (long purchase/activity history scans), not frequency.

### Frontend — loyalty-admin (`/audience-builder`)

- Static audience builder: “Refresh” control — Manual / Daily at [time]. Help text: “Members are recalculated once a day; real-time updates are off.”
- List + detail: show “Last refreshed” and “Next refresh”; keep the manual “Refresh now” button for all active audiences.

### Interaction with broadcast

- Compose shows the audience's last refreshed time.
- Static audiences: “Refresh segment before sending” checkbox (default on). Sender calls `fn_amp_resnapshot_audience` before building recipients.

## Phase 1b — Targeted broadcast

### Backend — Supabase

Tables (new; `workflow_log` / `notification_log` don't fit):

- `amp_broadcast_master` — `name`, `audience_type` (`audience` | `all_line_friends` | `line_friends_non_members`), `audience_id` (nullable), `message_config jsonb` (same shape as workflow LINE node: `resource_id` or `json_content`), `resolved_messages jsonb` (frozen at send), `status` enum (`draft`, `scheduled`, `sending`, `sent`, `partially_failed`, `failed`, `cancelled`), `scheduled_at`, `sent_at`, `recipient_count`, `sent_count`, `failed_count`, `created_by`, standard columns, merchant RLS.
- `amp_broadcast_batch` — one row per LINE call: `broadcast_id`, `batch_no` (unique with `broadcast_id`), `line_user_ids text[]` (≤500; empty for broadcast mode), `status`, `attempt_count`, `error`, `sent_at`. This is the frozen recipient list and the resume point.

RPCs (standard BFF skeleton: `get_current_merchant_id()`, `fn_log_admin_action`, `fn_response_*`; run `scripts/admin_audit_coverage.sql`):

- `bff_list_amp_broadcasts`, `bff_get_amp_broadcast_details(p_id, p_mode)`, `bff_upsert_amp_broadcast`.
- `bff_amp_estimate_audience(p_audience_type, p_audience_id)` — segment: total members + members with linked `line_id` and `channel_line` not false; friend audiences: LINE follower count (exact count known only at send). Also used by the workflow entry panel.
- `bff_amp_send_broadcast(p_id, p_scheduled_at)` — validate, atomic status move draft → scheduled / sending (no double send), audit, send-now emits sender event via existing pg_net pattern.
- `bff_amp_cancel_broadcast` — until sending starts.
- `bff_amp_test_send_broadcast(p_id, p_user_ids)` — push to ≤5 members.
- `fn_amp_run_due_broadcasts` + pg_cron every minute (mirror scheduled-workflow pattern).

Recipients — segment: active `amp_audience_member` (`exited_at IS NULL`) joined to `user_accounts.line_id`, excluding `channel_line = false`. Static segments are not auto-refreshed; compose shows “last refreshed”.

### Backend — sender (Inngest, in `inngest-amp-serve`)

`amp/broadcast.send`, idempotent on broadcast id:

1. Resolve content once (`fn_resolve_resource_for_delivery`) → `resolved_messages`. Append `?bc=<broadcast_id>` to member-app links (inert until Phase 2).
2. Build recipients (skip if batch rows exist): if the audience is static and “refresh before sending” is on, run `fn_amp_resnapshot_audience` first; then segment query, or shared friend-list builder for both friend audiences (all friends → one broadcast-mode batch).
3. Send each batch as a step. Fan out one child run per ~50 batches (Inngest step cap per run — verify current limit). Concurrency 1 per merchant. Retry with backoff on LINE 429.
4. Roll up counts; set final status.

### Backend — shared friend-list builder (in `inngest-amp-serve`)

One helper used by broadcast and workflows (extract from the current exclude-members seed run): page followers via messaging-service; optionally drop linked members via `fn_amp_filter_non_member_line_ids`; yield chunks.

### Backend — messaging-service

- `multicast` mode: `recipient.line_user_ids` (≤500) → LINE `/v2/bot/message/multicast`; same credential resolution.
- Pass `X-Line-Retry-Key` = batch id (safe retries). On multicast pass `customAggregationUnits` = broadcast id (verify LINE monthly unit limits).
- Return 429 as a distinct error.
- `GET /line/quota` → LINE quota + consumption.

### Frontend — loyalty-admin

- Nav: “Targeted broadcast” under AMP, after Audience builder (menu data migration).
- `/targeted-broadcast` — IndexTable: name, audience, status, scheduled/sent, recipients, sent/failed.
- `/targeted-broadcast/new`, `/targeted-broadcast/[id]` — compose + review when draft/scheduled; results after send.
- Compose:
  1. Audience — segment picker or the two friend options; counts; “last refreshed” for static segments; note that members without linked LINE won't receive it.
  2. Content — extract Content Library picker + `LinePreview` from `LineMessageConfigFields` into one shared component used by broadcast and the workflow message node. Sources: Content Library and custom Flex. Block postback buttons / quick replies with a clear message (Phase 2).
  3. Test send.
  4. Review — estimate, LINE quota remaining and this send's usage, “list is frozen when you press Send”, Send now / Schedule.
  5. Confirm with the count in the button (“Send to 48,210 members”).
- Results — status, recipients, sent/failed.
- Audience detail (`/audience-builder`) — “Send message” (opens `/targeted-broadcast/new?audience=<id>`) + “Recent sends to this segment” card.
- Follow `30-fe-admin`: Server Components by default, Server Actions for mutations, toast every mutation, Polaris only.

## Phase 1c — LINE friend audiences in workflows

Both entry types stay in the workflow builder; fix how they run.

Backend:

- Exclude members: seed run uses the shared friend-list builder. Still one run per friend (correct for journeys).
- Re-enrollment off → drop friends who already entered this workflow (by `line_user_id` in `workflow_log`) before fan-out — same rule as `past_line_interaction`.
- Scheduled runs: add both friend entry types to `fn_amp_run_due_scheduled_workflows`, dispatching exactly like manual batch run (all friends → one shared run; exclude members → seed run). With re-enrollment off, scheduled exclude-members reaches only new friends.
- A friend who becomes a member mid-journey continues (no re-check) — v1 decision.

Frontend (`condition-config.tsx`, `workflow-validation.ts`, `workflow-nodes.tsx`):

- Keep both entry options.
- Remove “scheduled runs don't apply” copy.
- All LINE friends: warn that member-data branches don't apply in a shared run, and that each scheduled run reaches every friend again.
- Both: hint “Sending a single message? Use Targeted broadcast” with link.
- Show `bff_amp_estimate_audience` count in the entry panel.

## Phase 2 — measurement and follow-up

- Per-member attribution: member app reads `bc` + LINE login session → engagement event with broadcast id + member id (`loyalty-user` + `engagement-beacon`).
- LINE stats on broadcast results (request-id insight for broadcast; aggregation-unit stats for multicast).
- “Create segment from clickers” on broadcast results.
- Postback buttons in broadcasts: sign against broadcast id; `webhook-line` accepts it; tap enrolls via “When LINE option selected”. Prerequisite: fix the `domain='amp'` vs `'campaign'` filter in `postbackContinue`.

## Out of v1

Multi-segment / exclusions, frequency caps, approval flow, merge fields in broadcast, email/SMS.

## Separate fix (not in this plan)

Workflow LINE sends ignore `channel_line = false`; broadcast respects it.

## Execution notes

- Local clones under `~/Documents/rocket/`: `loyalty-admin`, `messaging-service`; backend via Supabase MCP (Edge deploy via MCP, check `verify_jwt`).
- Commit per owning repo; push only when asked.
- Order: daily audience refresh (schema + cron + BFFs + audience-builder UI — ships alone) → messaging-service multicast + quota → broadcast schema + RPCs → sender + shared friend-list builder → workflow friend-entry fixes → broadcast admin UI.
- Closeout once after Phase 1 (`06-product-doc-closeout`): `requirements/AMP_Workflows.md` (audience refresh schedule, friend entries, scheduled support, re-enrollment rule) + new Targeted broadcast section.
