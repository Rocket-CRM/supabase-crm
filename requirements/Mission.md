# Mission

Goal-based challenges where members complete qualifying actions and receive configured outcomes. Merchants define conditions, limits, and grants; progress is tracked per member in structured JSON; evaluation runs asynchronously after domain events.

Owner surfaces: loyalty-admin, loyalty-user

## Concept

A **mission** is a merchant campaign with a type, schedule, eligibility, progress rules, and one or more **outcomes** (points, tickets, rewards, earn factors, and related grant types via the central dispatcher).

**Standard mission** — Several **conditions** run in parallel; every condition must reach its target before the mission completes (logical AND). Each condition accumulates progress independently.

**Milestone mission** — Conditions are ordered **levels** (1 → 2 → 3 …). Progress **waterfalls**: overflow from completing one level applies to the next incomplete level. Each level can have its own outcomes.

**Condition** — Defines what to measure (purchase spend, points earned, form completed, referral events, etc.), how to measure it (count vs sum), filters (products, stores, amounts, forms), and the target value. Milestone levels also carry display metadata (name, badge, order) on the condition row.

**Progress record** — Per member and mission: acceptance timestamp, period counters, unclaimed completion count, and **condition progress** — one JSON document whose keys are either condition ids (standard) or `level_N` (milestone).

**Activation** — **Auto** missions evaluate for all eligible members. **Manual** missions require the member (or staff) to **join** before events count.

**Claim** — **Auto** missions grant outcomes when completion is detected. **Manual** missions increment unclaimed completions; the member must **claim** to run outcome dispatch (supports quantity and milestone level on claim).

**Reset** — Optional calendar or per-member period reset (`daily`, `weekly`, `monthly`) clears progress for another lap; milestone missions cannot use progress reset frequency. **Loop** missions allow multiple completions per period when enabled.

**Exclusivity groups** — Optional text groups on progress or claim: only one mission in a group may advance or be claimed at a time; others surface a locked state.

**Access state** — Schedule, preview window, signup window, persona filters, and claim deadline combine into whether a mission is visible, joinable, in progress, claimable, or locked — exposed to clients as stats and `button_action`.

Outcomes always flow through the same **central outcome dispatcher** used by check-in, referral, and AMP.

## Rules

- If the mission is inactive, outside its start/end window, or fails `fn_mission_access_state` (preview, signup window, persona, claim end) → list/detail hide or disable join/claim with the returned reason; staff front line may still see missions but claim respects the same gates unless admin override RPCs apply.
- **Standard:** mission completes when every condition’s `current` reaches `target` in `condition_progress`; partial progress on one condition does not complete the mission.
- **Milestone:** increments apply to the lowest incomplete level; when `current >= target`, set completion timestamp and carry overflow to the next level; evaluation returns increments keyed by level (waterfall applied in `fn_update_mission_progress`).
- **Manual activation:** until `accepted_at` is set, qualifying events do not update progress; join calls `accept_mission`.
- **Manual claim:** completion increments `unclaimed_completions`; claim calls `bff_claim_mission` (optional `p_milestone_level`, quantity) → `fn_distribute_mission_completion` / outcome dispatch; auto claim runs dispatch inside the evaluation transaction when completion is detected.
- **Purchase conditions:** header-level purchase events count toward conditions without SKU/product filters; line-scoped filters use **purchase item** events (`event_type` `purchase_item`) so header and line rules do not double-count the same condition.
- **Purchase progress** only counts when purchase status is **completed** (routers mirror legacy consumer filters).
- **Wallet conditions:** only **earn** rows count; **points_earned** vs **tickets_earned** by currency; store credit and unrelated currencies are ignored.
- **Measurement:** `count` adds one per qualifying event; `sum` adds the event amount (purchases use final/total amount on header events, line amount on item events). Binary condition types (forms, referrals) use count semantics.
- **Filters:** product/SKU/category/brand arrays and store attribute set must match when configured; min/max transaction amount enforced on purchase-shaped events; tier filters on conditions restrict which rows apply.
- **User perspective** on the mission (`customer` vs `seller`) determines whether purchase/seller fields bind to the buyer or seller on evaluation.
- **Progress reset:** when frequency is set, `fn_batch_reset_global_missions` (global mode, Render crons) or `fn_batch_reset_due_missions` (user-specific / due rows) clears period progress; milestone missions reject reset frequency at validation. **Carry over progress** and **allow progress loop** control whether partial progress survives reset and how many completions per transaction/period are allowed (`max_loops_per_transaction` caps burst loops).
- **Exclusivity:** if another mission in the same progress group already holds progress, new progress is blocked; claim exclusivity blocks claim until the group frees — UI may show `exclusivity_locked` on `button_action`.
- **`button_action` priority (list/detail):** `claim_outcome` when unclaimed > 0 and manual claim; else `join_mission` when manual activation and not accepted; else `claimed` when fully done and claimed; else `view_progress` when a progress row exists; else `view_details`. Clients must also respect `can_accept`, `can_claim`, and exclusivity flags from access state (join/claim disabled when false).
- **Deletion:** missions with front-line claim history cannot be deleted (FK guard); deactivate instead.

**Waterfall example (milestone):** Level 1 at 300/500, Level 2 at 0/2000; a +400 purchase → Level 1 completes at 500, Level 2 becomes 200/2000.

## Journeys

### Admin journey

| Page | Owning repo | BFF / RPC |
| --- | --- | --- |
| Mission list | loyalty-admin | Direct `mission` table list; `bff_set_mission_active`; delete guard |
| Mission settings (create/edit) | loyalty-admin | `bff_get_mission_details_conditions_limits`, `bff_upsert_mission`, `bff_list_rewards_for_mission_outcomes` |
| Mission reports | loyalty-admin | `bff_report_missions`, `bff_report_missions_rows` |
| Front line — Claim mission | loyalty-admin | `bff_get_user_missions`, `bff_get_mission_detail`, `accept_mission`, `bff_frontline_claim_mission`, `bff_admin_get_mission_claim_history` |

| Setting | Effect on behaviour |
| --- | --- |
| Name, code, type (standard / milestone) | Identity and evaluation strategy |
| Activation type | Auto vs manual join before progress |
| Claim type | Auto grant vs manual claim queue |
| Start / end / claim end / preview advance days | Visibility and claim deadline (`fn_mission_access_state`) |
| Eligible personas / persona groups | Who may see and join |
| Signup window start/end | New-member eligibility window |
| Progress reset frequency + reset mode | Global calendar reset vs user period anchor |
| Carry over progress / allow loop / max loops per transaction | Reset and repeat behaviour |
| Progress / claim exclusivity group | Mutual exclusion within group |
| User perspective | Customer vs seller attribution on purchases |
| Conditions | Types, targets, measurement, filters, milestone level metadata |
| Outcomes | Per level or mission-wide grants (full replace on save) |
| Progress / claim limits | Caps via `mission_limit_progress` / `mission_limit_claim` |
| Images, goal copy, T&C | Member-facing presentation |

1. Open **Mission list**; create via **Mission settings** or edit an existing row.
2. Set type, activation, claim mode, schedule, eligibility, and exclusivity fields.
3. Add **conditions** (parallel set for standard; ordered levels for milestone) with filters and targets.
4. Attach **outcomes** per level or once for standard; pick entities for ticket/reward outcomes.
5. Configure progress/claim limits if caps are required.
6. Save (`bff_upsert_mission` validates via `fn_validate_mission_upsert`, replaces children).
7. Toggle active from list when ready; use reports for completion/claim analytics.
8. On **Front line**, staff open **Claim mission** for a member: join manual missions, claim manual outcomes, print summary; history via admin claim history RPC.

Entitlement: admin nav typically requires `campaign` + `campaign.mission` feature flags.

### Member journey

| Page / surface | Owning repo | BFF / RPC |
| --- | --- | --- |
| Missions hub | loyalty-user | `bff_get_user_missions` |
| Mission detail drawer | loyalty-user | `bff_get_mission_detail`, `accept_mission`, `bff_claim_mission` |

1. Member opens **Missions**; app loads the mission list with progress summaries and `button_action` labels.
2. Tap a card → **detail drawer** with conditions, milestone levels, outcomes, and completion history.
3. If manual activation and join allowed → **Join** calls `accept_mission`; errors show access messages from RPC.
4. Progress updates after backend evaluation (not synchronous on the tap); refresh or realtime product choice reloads state.
5. If manual claim and `can_claim` → **Claim** calls `bff_claim_mission` (milestone level resolved from lowest unclaimed level); shipping may be required for physical reward outcomes.
6. Locked exclusivity or expired claim window → primary CTA disabled with locked/expired copy.

| Error (typical) | Cause |
| --- | --- |
| Not eligible / outside window | Access state or schedule |
| Must join first | Manual activation without `accepted_at` |
| Nothing to claim | No unclaimed completions |
| Exclusivity locked | Another mission in group holds progress/claim |
| Claim limit | `mission_limit_claim` exhausted |

## System

### Data model

| Artifact | Role |
| --- | --- |
| `mission` | Campaign header: type, activation, claim, schedule, eligibility, reset, exclusivity, loop flags, imagery, copy |
| `mission_conditions` | Measurable rules; milestone level, filters, measurement, targets, milestone display fields |
| `mission_outcomes` | Grant rows keyed by mission and optional milestone level |
| `mission_progress` | Per-user progress: `condition_progress` JSONB, counters, acceptance, reset timestamps |
| `mission_limit_progress` / `mission_limit_claim` | Participation caps by scope and time unit |
| `mission_log_completion` | Completion audit |
| `mission_progress_events` | Evaluation audit trail |
| `outcome_distribution_log` | Shared dispatcher audit for granted outcomes |

Legacy `current_progress` on `mission_progress` remains for compatibility; authoritative V2 state is `condition_progress`.

### Functions

| Function | Role |
| --- | --- |
| `bff_upsert_mission` / `fn_validate_mission_upsert` | Admin save with child replace |
| `bff_get_mission_details_conditions_limits` | Admin edit template |
| `bff_get_user_missions` / `bff_get_mission_detail` | Member list and detail + access + `button_action` |
| `accept_mission` | Manual join |
| `bff_claim_mission` / `bff_frontline_claim_mission` | Manual claim (member vs staff) |
| `fn_mission_access_state` | Central visibility/join/claim gating |
| `fn_evaluate_mission_conditions` | Map event → increment map |
| `fn_update_mission_progress` | Apply JSONB updates, waterfall, completion detection |
| `fn_process_mission_outcomes` / `fn_distribute_mission_completion` | Grant on auto-complete or claim |
| `fn_has_active_missions` / `fn_get_active_missions_by_condition_type` | Router fan-out lookup (replaces Redis mission cache on live path) |
| `fn_check_mission_exclusivity` | Exclusivity enforcement |
| `fn_batch_reset_global_missions` / `fn_batch_reset_due_missions` | Scheduled global reset and user-period due reset |
| `bff_report_missions` / `bff_report_missions_rows` | Admin analytics |
| `bff_set_mission_active` | List activate/deactivate |
| `trigger_emit_mission_completed_event` | Downstream signals on completion |

Cache invalidation triggers on mission/condition mutations still exist for any optional Redis pre-filter in retired consumers.

### Flows

**Progress evaluation (async, live path — post-Confluent):**

```
Purchase / wallet / (other) chokepoint writers
  → fn_chokepoint_emit_event → chokepoint_event_outbox
  → OutboxPublisher (crm-event-processors, Inngest mode)
  → Inngest crm/purchase.event | crm/purchase_item.event | crm/wallet.event
  → inngest-event-router-serve
       mission-purchase-router (completed purchases)
       mission-purchase-item-router (completed line items → scoped purchase conditions)
       mission-wallet-router (earn → points_earned / tickets_earned)
  → one mission/evaluate per active mission id
  → inngest-mission-serve
       fn_evaluate_mission_conditions → fn_update_mission_progress
       → fn_process_mission_outcomes when newly completed (auto claim)
```

**Retired path (do not document as live):** Debezium CDC → Confluent/Upstash Kafka → `MissionConsumer` on Render (`KAFKA_CONSUMERS_ENABLED` defaults false since Confluent deactivation 2026-07-07). Code retained for reference only.

**Sync member paths:** join, claim, and reads run in Postgres via BFF RPCs; no Kafka.

**Reset (scheduled):** Render crons call `fn_batch_reset_global_missions` for daily/monthly global resets; user-specific due resets via `fn_batch_reset_due_missions`.

### External services

| Service | Role |
| --- | --- |
| `crm-event-processors` (Render) | OutboxPublisher drains outbox to Inngest; mission Kafka consumer optional/off |
| `inngest-event-router-serve` (Edge) | Mission purchase / purchase-item / wallet routers |
| `inngest-mission-serve` (Edge) | `mission/evaluate` workflow → evaluation RPCs |
| Render crons `mission-daily-global-reset`, `mission-monthly-global-reset` | Global progress reset |
| Render cron `refresh-mission-conditions-mv` | Refreshes expanded conditions MV when present |

### Known gaps

- **Form and referral condition types** — Still defined in admin and evaluation RPCs, but **no chokepoint router** publishes matching events (legacy CDC-only path dead since 2026-06-04). Progress for these types does not advance in production until emitters + router events exist.
- **Redis mission cache** — Live routers query `fn_has_active_missions` / `fn_get_active_missions_by_condition_type`; Redis pre-filter in `MissionConsumer` applies only if Kafka consumers are re-enabled.
- **Purchase_Transaction.md** — Older passages describing 30s batch mission evaluation and DB triggers for auto missions are stale relative to chokepoint + Inngest path; treat this doc as authoritative for mission progress timing.

## Related

- **Purchase Transaction** — Purchase and item chokepoint events feed mission routers; see `Purchase_Transaction.md`.
- **Currency** — Wallet earn events feed points/ticket conditions; grants post via dispatcher; see `Currency.md`.
- **Forms** — Form submission condition type pending chokepoint wiring; see `Forms.md`.
- **Referral** — Referral condition types pending chokepoint wiring; see `Referral.md`.
- **Central Outcome Dispatcher** — All mission grants; see `Central_Outcome_Dispatcher.md`.
- **Check-in** — Parallel engagement mechanic sharing dispatcher patterns; see `Checkin.md`.
