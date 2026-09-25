# AMP Lifecycle Automation

**Purpose.** Explain how AMP lifecycle automation starts workflow runs for realtime customer events and scheduled lifecycle moments such as birthdays, anniversaries, and recurring campaigns.

**Scope.** This document covers the deployed AMP dispatch layer, scheduled lifecycle helper functions, New CRM merchant validation, and QA scenarios. It does not define the workflow builder UI.

---

## Current Production Shape

AMP has two separate entry paths:

| Path | Entry point | Use case | Dispatch behavior |
|---|---|---|---|
| Realtime event | `inngest-event-router-serve` AMP routers -> `amp-dispatch-realtime-event` | A source event happens now, such as purchase completed, points earned, signup, or tier change | Router receives a chokepoint event, filters by legacy fire criteria, and calls the dispatcher, which finds matching active workflows and emits `amp/workflow.trigger` events |
| Batch lifecycle | `fn_amp_run_due_scheduled_workflows()` -> `amp-dispatch-workflow-batch` | A schedule becomes due and matching users must be resolved before launching | SQL scheduler finds due scheduled triggers and matching users, then batch launcher fans those users out to Inngest |

Legacy Edge Function slugs still exist for compatibility:

- `dispatch-workflow-trigger` is the older realtime dispatcher slug.
- `amp-batch-dispatch` is the older batch launcher slug.

Prefer the newer names in docs, configuration, and diagrams:

- `amp-dispatch-realtime-event`
- `amp-dispatch-workflow-batch`

---

## Realtime Event Path

```text
chokepoint fn -> fn_chokepoint_emit_event -> chokepoint_event_outbox
  -> OutboxPublisher (crm-event-processors, Inngest mode)
  -> Inngest event: crm/<domain>.event
  -> inngest-event-router-serve AMP routers (v3, 2026-07-08)
     - amp-purchase-router        (status = completed)
     - amp-purchase-item-router   (item_status = completed)
     - amp-wallet-router          (transaction_type = earn)
     - amp-tier-router            (!skip_cdc)
     - amp-user-router            (user_event_type = create, !skip_cdc;
                                   batched 100/5s per merchant + throttled
                                   60/min/merchant for signup-import bursts)
     - dedup: Inngest idempotency on legacy Redis keys (24h);
       amp-user-router dedups in-handler (batching excludes idempotency)
  -> Supabase Edge Function: amp-dispatch-realtime-event
     - fn_get_active_triggers_cached (per-merchant 600s cache)
     - finds active workflows for the event table and operation
     - applies trigger_conditions
  -> Inngest event: amp/workflow.trigger
  -> inngest-amp-serve executes the workflow graph
     - loyalty actions (points, tags, …) -> fn_execute_amp_action RPC
     - LINE / SMS / email message nodes -> messaging-service POST /send
       (auth: get_messaging_auth_key(); source: amp_workflow)
```

The realtime path does **not** go through `amp-dispatch-workflow-batch`. It is event-first: one source event comes in, and the dispatcher decides which workflows match.

Trigger tables served by the routers:

- `purchase_ledger` for completed purchases.
- `purchase_items_ledger` for completed items (new surface, chokepoint-only).
- `wallet_ledger` for points/currency earned.
- `user_accounts` for signup events.
- `tier_change_ledger` for tier lifecycle events.

**Dead trigger sources (CDC-only, no chokepoint topic — not firing since 2026-06-04):**

- `form_submissions` for completed forms (`form_completed` triggers).
- `amp_workflow_log` for `add_to_audience` workflow events.

Reviving them requires `fn_chokepoint_emit_event` calls at their write sites plus outbox topic allowlisting — tracked in `.cursor/plans/confluent-deactivation-refactor-20260707.md` §6.

---

## Scheduled Lifecycle Path

```text
pg_cron / scheduler wake-up
  -> fn_amp_run_due_scheduled_workflows(run_at)
     - claims due idle workflow_trigger rows where trigger_type = scheduled
     - verifies the workflow is still active
     - resolves matching users through fn_amp_find_matching_users(workflow_id)
     - writes workflow_log entries for no-user, dispatched, or failed runs
     - advances next_run_at through fn_amp_compute_next_run_at(schedule, run_at)
  -> Supabase Edge Function: amp-dispatch-workflow-batch
     - receives { workflow_id, merchant_id, user_ids[] } in chunks of up to 500 users
     - validates the workflow is active
     - emits batched amp/workflow.trigger events
  -> Inngest Cloud
  -> inngest-amp-serve executes the workflow graph per user
```

The scheduled path is schedule-first: the scheduler asks "what is due now?", then each due workflow resolves its matching users.

`bff_amp_batch_run` chunks broad matching sets before calling `amp-dispatch-workflow-batch`, and returns `matching_users`, `dispatched`, `batch_count`, `chunk_size`, and `pg_net_request_ids` without echoing the full `user_ids` array. `amp-dispatch-workflow-batch` does not discover workflows by itself. It only launches a known workflow for a known user list.

---

## Outbound messaging (LINE / SMS / email)

Rule-based workflow **message** and **action** nodes with `channel: line|sms|email` (or `action_type: send_line_message|send_sms|send_email`) are **not** sent via deprecated edge functions (`send-line-message`, `send-sms-8x8`).

Delivery path:

```text
inngest-amp-serve (executeActionInline)
  -> inline message config (content / messages / json_content), OR
     Content Library resource_id -> fn_resolve_resource_for_delivery + fn_render_blocks_as_line_flex (LINE rich_content)
  -> get_messaging_auth_key() RPC  (vault-backed; same as CS callers)
  -> messaging-service POST /send
     { merchant_id, channel, recipient, message(s), source: amp_workflow, reference_id: workflow_id }
  -> workflow_log  (action_type send_*, status sent|failed)
```

Loyalty RPC actions (points, tags, rewards, …) still use `fn_execute_amp_action` and do not go through messaging-service.

See also `requirements/Notification_Service.md` §Shared delivery service for how Notification differs today (direct LINE push; `/send` migration planned).

---

## Scheduled Trigger Contract

Scheduled lifecycle automation uses `workflow_trigger`:

| Field | Meaning |
|---|---|
| `trigger_type` | Must be `scheduled` for the SQL scheduler. |
| `trigger_conditions.schedule` | Schedule JSON used by `fn_amp_compute_next_run_at`. |
| `next_run_at` | Next due timestamp. Set by trigger logic for scheduled rows. |
| `schedule_status` | Scheduler claim state. Expected idle state is `idle`. |
| `last_run_at` | Last scheduler attempt timestamp. |
| `is_active` | Must be true, and the parent workflow must also be active. |

Supported schedule types:

| Type | Required / common config | Behavior |
|---|---|---|
| `one_off` | `run_at` | Returns the configured timestamp if it is still in the future; otherwise no next run. |
| `interval` | `interval_minutes` | Adds the interval to the current scheduler time. |
| `daily` | `timezone`, `time_of_day` | Runs at the next local daily time. |
| `weekly` | `timezone`, `time_of_day`, `weekdays` | Runs on ISO weekdays, where `1 = Monday` and `7 = Sunday`. |
| `monthly` | `timezone`, `time_of_day`, `day_of_month` | Runs on the next matching day of month. |

Example scheduled trigger condition:

```json
{
  "schedule": {
    "type": "daily",
    "timezone": "Asia/Bangkok",
    "time_of_day": "09:00"
  }
}
```

**Schedule JSON key:** `fn_amp_compute_next_run_at` reads `schedule.type`. The loyalty-admin FE historically saved `schedule_type`; the DB trigger now normalizes `schedule_type` → `type` on insert/update, and `fn_amp_compute_next_run_at` accepts either key. Prefer saving `type` from the FE going forward.

---

## Lifecycle User Matching

`fn_amp_find_matching_users(workflow_id)` resolves users from the first condition node in the workflow graph.

For lifecycle dates, the condition should use one of these operators:

- `birthday_today`
- `anniversary_today`
- `date_anniversary_today`

The date matcher compares month/day only, after converting `run_at` into the configured timezone and applying `days_offset`.

Example condition group:

```json
{
  "collection": "user_accounts",
  "timezone": "Asia/Bangkok",
  "conditions": [
    {
      "field": "birth_date",
      "operator": "birthday_today",
      "days_offset": 0
    }
  ]
}
```

Important implementation details:

- The live user date column is `user_accounts.birth_date`.
- Matching excludes users that already have `workflow_log.event_type = 'execution_started'` for the workflow.
- The current matching function does not automatically add active/deleted user guards unless they are included in the condition node.

---

## New CRM Merchant Status

Two merchant records match "New CRM":

| Merchant | ID | Code |
|---|---|---|
| New CRM | `09b45463-3812-42fb-9c7f-9d43b6fd3eb9` | `newcrm` |
| NEWCRM Test Merchant | `aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee` | `NEWCRM` |

For the `New CRM` merchant (`09b45463-3812-42fb-9c7f-9d43b6fd3eb9`), live validation found:

- Active realtime AMP triggers exist for `database`, `points_earned`, and `purchase_completed`.
- No active `scheduled` lifecycle trigger exists yet.

That means realtime lifecycle/event workflows are configured, but birthday/anniversary scheduled lifecycle automation still needs a scheduled trigger and condition-node setup before it can dispatch users.

---

## QA Coverage

Run non-destructive tests against helper functions and merchant configuration before enabling any new scheduled trigger.

Covered scenarios:

- Lifecycle date matching returns true for same month/day.
- Lifecycle date matching returns false for different month/day.
- Null source date returns false.
- Unknown lifecycle operator returns false.
- `days_offset` supports upcoming anniversary matching.
- Timezone conversion uses the local date before matching month/day.
- Daily schedule returns same-day future run time.
- Daily schedule rolls to tomorrow after time has passed.
- Weekly schedule returns same-day future run time.
- Weekly schedule rolls to the next allowed weekday after time has passed.
- Monthly schedule returns same-month future run time.
- Monthly schedule rolls to the next month after time has passed.
- Interval schedule adds configured minutes.
- Future one-off schedule returns `run_at`.
- Past one-off schedule returns null.
- New CRM merchant exists.
- New CRM has active realtime AMP triggers.
- New CRM has no active scheduled triggers yet.

Latest non-destructive test result: **18 / 18 passed**.

The scheduled dispatcher itself was not invoked during this test because `fn_amp_run_due_scheduled_workflows()` mutates state: it claims trigger rows, writes `workflow_log`, advances `next_run_at`, and may call `amp-dispatch-workflow-batch` through `pg_net`.

---

## Enablement Checklist

Before enabling a scheduled lifecycle workflow for New CRM:

1. Create or update an AMP workflow with an explicit lifecycle condition node.
2. Add a `workflow_trigger` row with `trigger_type = 'scheduled'`.
3. Put schedule config under `trigger_conditions.schedule`.
4. Confirm `next_run_at` is populated.
5. Confirm `schedule_status = 'idle'`.
6. Confirm the parent `workflow_master.is_active = true`.
7. Run the non-destructive helper tests.
8. Run one controlled scheduled dispatch only after confirming target users and expected workflow actions.

