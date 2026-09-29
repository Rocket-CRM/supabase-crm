# Mission

Goal-based challenges where members complete qualifying actions and receive configured outcomes. Merchants define conditions, limits, and grants; progress is tracked per member in structured JSON; evaluation runs asynchronously after domain events.

Owner surfaces: loyalty-admin, loyalty-user

## Concept

A **mission** is a campaign type that pushes a behaviour the brand wants — buy a product line, reach a spend target — within a time-boxed window. Like every campaign it is action → condition → outcome: the member's qualifying actions (purchases, point or ticket earns) build progress against the mission's conditions, and completion grants one or more **outcomes** (points, tickets, rewards, earn factors, and related grant types via the central dispatcher). Unlike a reward, which the member buys with points, a mission is earned by doing; nothing is spent.

**Standard mission** — One or more **conditions**, each accumulating progress independently. By default every condition must reach its target (AND); if any condition is set to OR, reaching the target on any one condition completes the mission.

**Milestone mission** — A staircase: conditions are ordered **levels** (1 → 2 → 3 …) and the member must finish a level before the next one counts. Progress **waterfalls**: overflow from completing one level applies to the next incomplete level. Each level can have its own outcomes, typically escalating.

**Condition** — What to measure (purchase spend, points earned, tickets earned, form completed, referral events), how (sum of amounts vs count of events), which activity counts (filters: product, SKU, category, brand, tier, store attribute set, min/max bill amount), and the target. Milestone levels also carry display metadata (name, badge, order).

**Progress record** — Per member and mission: acceptance timestamp, period counters, unclaimed completion count, and **condition progress** — current vs target per condition (standard) or per level (milestone).

**Activation** — **Auto** missions evaluate for all eligible members. **Manual** missions require the member (or staff) to **join** before events count.

**Claim** — **Auto** missions grant outcomes when completion is detected. **Manual** missions increment unclaimed completions; the member must **claim** to run outcome dispatch (supports quantity and milestone level on claim).

**Reset** — Optional calendar or per-member period reset (`daily`, `weekly`, `monthly`) clears the progress bar for another lap. Reset never changes how many completions a member has left. Milestone missions cannot use reset.

**Repeat** — Every standard mission can be completed again. Three independent settings shape repetition:
- **Progress loops per bill** — how many completions one purchase can trigger (standard missions with one sum condition only).
- **Progress limits** — how many times a member, or the whole campaign, can complete per day / week / month / year / all time. This is the only "how many times" control; new missions default to 1 per member, all time.
- **Reset** — when the bar clears.

The former **Single** and **Recurring** mission types are retired: standard + reset + progress limit covers both.

Per-bill loops control one bill; progress limits control the whole mission. **Claim limits** apply the same scopes and windows to claims.

**Exclusivity groups** — Optional labels that make missions mutually exclusive for one member. **Progress group:** once the member has joined one mission in the group, the others cannot be joined — the member picks one path. **Claim group:** the member may progress several missions in the group, but once one is claimed the others lock — the member collects only one.

**Access state** — Schedule, preview window (shown before start), signup window, persona filters, and claim deadline (may extend past end) combine into whether a mission is visible, joinable, in progress, claimable, or locked — exposed to clients as a single next action.

Outcomes always flow through the same **central outcome dispatcher** used by check-in, referral, and AMP.

## Rules

- If the mission is inactive, outside its start/end window, or fails `fn_mission_access_state` (preview, signup window, persona, claim end) → list/detail hide or disable join/claim with the returned reason; staff front line may still see missions but claim respects the same gates unless admin override RPCs apply.
- **Standard:** with all conditions `AND`, the mission completes when every condition’s `current` reaches `target` in `condition_progress`; partial progress on one condition does not complete it. If any condition row has `operator = OR`, the mission completes when any one condition reaches target (the operator is mission-wide in effect; mixed AND/OR is not evaluated per pair).
- **Milestone:** increments apply to the lowest incomplete level; when `current >= target`, set completion timestamp and carry overflow to the next level; evaluation returns increments keyed by level (waterfall applied in `fn_update_mission_progress`).
- **Manual activation:** until `accepted_at` is set, qualifying events do not update progress; join calls `accept_mission`.
- **Manual claim:** completion increments `unclaimed_completions`; claim calls `bff_claim_mission` (optional `p_milestone_level`, quantity) → `fn_distribute_mission_completion` / outcome dispatch; auto claim runs dispatch inside the evaluation transaction when completion is detected.
- **Purchase conditions:** header-level purchase events count toward conditions without SKU/product filters; line-scoped filters use **purchase item** events (`event_type` `purchase_item`) so header and line rules do not double-count the same condition.
- **Purchase progress** only counts when purchase status is **completed** (routers mirror legacy consumer filters).
- **Wallet conditions:** only **earn** rows count; **points_earned** vs **tickets_earned** by currency; store credit and unrelated currencies are ignored.
- **Measurement:** `count` adds one per qualifying event; `sum` adds the event amount (purchases use final/total amount on header events, line amount on item events). Binary condition types (forms, referrals) use count semantics.
- **Filters:** product/SKU/category/brand arrays and store attribute set must match when configured; min/max transaction amount enforced on purchase-shaped events; tier filters on conditions restrict which rows apply.
- **User perspective** on the mission (`customer` vs `seller`) determines whether purchase/seller fields bind to the buyer or seller on evaluation.
- **Progress reset:** when frequency is set, `fn_batch_reset_global_missions` (global mode, Render crons) or `fn_batch_reset_due_missions` (user-specific / due rows) clears period progress; milestone missions reject reset frequency at validation. Reset does not restore progress-limit headroom.
- **Repeat (standard):** standard missions always loop (`allow_progress_loop` = true; a save with it off returns `LOOP_REQUIRED`). After each completion the bar resets for the next lap — unless the member has used up an all-time progress limit, in which case the bar stays full on this and later events.
- **Progress loops per bill:** `max_loops_per_transaction` caps completions from one event. Allowed only on standard missions with exactly one `sum` condition (otherwise `MAX_LOOPS_SHAPE`); blank = no per-bill cap. Completions = `floor((current + amount) / target)`, capped by the per-bill cap and remaining progress-limit headroom. **Carry over progress** keeps the remainder below target for the next lap (same shape only, `CARRY_OVER_SHAPE`).
- **Progress limits:** scope `user` (per member) or `total` (campaign-wide), time unit day / week / month / year / all time; checked before every completion. Multiple rows stack; a tighter window may not exceed a wider one (`STACKED_LIMIT_EXCEEDS_WIDER`). Milestone: each completed level counts as one completion.
- **Retired types:** `single` / `recurring` remain in the enum but saves return `MISSION_TYPE_RETIRED`; all rows were migrated to `standard` (Once-configured missions got a 1 per member, all time progress limit so behaviour did not change).
- **Legacy fallback:** a non-milestone mission with loop off — only creatable outside admin (see Known gaps) — still completes at most once per member.
- **Exclusivity:** if the member has an accepted, active progress row on another mission in the same progress group → join/progress on this mission is blocked (`fn_check_mission_exclusivity`). If the member has claimed any completion of another mission in the same claim group → this mission is `exclusivity_locked` (`fn_mission_access_state`); the lock does not expire.
- **Claim limit binding:** a mission may define multiple claim-cap rows. The engine picks one **binding** row (tightest remaining headroom; when headroom ties, per-member `user` scope wins over mission-wide scopes). Member detail and failed claims expose that row’s scope, cap, and time unit so the app can show the correct exhausted copy.
- **Claim limit copy (member):** mission-wide scopes (`total`, `store`, `user_store`) use “campaign / total” exhausted wording; per-member `user` scope uses “your limit this period” wording. Partial batch claims that would exceed the binding cap return `claim_limit_exceeded` with the same binding fields.
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
| Progress loops per bill + carry over progress | Completions one bill can trigger; remainder kept for next lap (shown only for standard + one sum condition) |
| Progress limits | How many times a member / the campaign can complete (default 1 per member, all time) |
| Claim limits | Caps on claims (`mission_limit_claim`) |
| Progress / claim exclusivity group | Member can join only one mission per progress group; can claim only one per claim group |
| User perspective | Customer vs seller attribution on purchases |
| Conditions | Types, targets, sum vs count, filters, AND / OR, milestone level metadata |
| Outcomes | Per level or mission-wide grants (full replace on save) |
| Images, goal copy, T&C | Member-facing presentation |

Mission settings page order: Basic info → Conditions → Outcomes → **Progress and claims** (activation, claim type, reset, progress loops per bill, milestone skip — saved but not evaluated, see Known gaps; progress and claim limits; exclusivity groups) → Schedule & status → Audience & eligibility → Rich descriptions.

1. Open **Mission list**; create via **Mission settings** or edit an existing row.
2. Set basic info and type (standard / milestone).
3. Add **conditions** (parallel set for standard; ordered levels for milestone) with filters and targets.
4. Attach **outcomes** per level or once for standard; pick entities for ticket/reward outcomes.
5. In **Progress and claims**, set activation, claim mode, reset, progress loops per bill, progress/claim limits, and exclusivity groups.
6. Set schedule and eligibility.
7. Save (`bff_upsert_mission` validates via `fn_validate_mission_upsert`, replaces children; progress/claim limits are full-replace).
8. Toggle active from list when ready; use reports for completion/claim analytics.
9. On **Front line**, staff open **Claim mission** for a member: join manual missions, claim manual outcomes, print summary; history via admin claim history RPC.

Entitlement: admin nav typically requires `campaign` + `campaign.mission` feature flags.

### Member journey

| Page / surface | Owning repo | BFF / RPC |
| --- | --- | --- |
| Missions hub | loyalty-user | `bff_get_user_missions` |
| Mission detail drawer | loyalty-user | `bff_get_mission_detail`, `accept_mission`, `bff_claim_mission` |

1. Member opens **Missions**; app loads the mission list with progress summaries and `button_action` labels. Missions in their preview window appear before start but cannot be joined.
2. Tap a card → **detail drawer** with conditions, a progress bar toward target (e.g. 77%), milestone levels as steps completed one at a time, outcomes, and completion history. A completed mission shows a full bar and completion count (e.g. 1/1).
3. If manual activation and join allowed → **Join** calls `accept_mission`; errors show access messages from RPC.
4. Progress updates after backend evaluation (not synchronous on the tap); refresh or realtime product choice reloads state.
5. If manual claim and `can_claim` → **Claim** calls `bff_claim_mission` (milestone level resolved from lowest unclaimed level); shipping may be required for physical reward outcomes. Detail load includes binding claim-limit fields (`claim_limit_scope`, `claim_limit_max`, `claim_limit_time_unit`, `claimable_now`) from `fn_mission_claim_quota`.
6. Locked exclusivity or expired claim window → primary CTA disabled with locked/expired copy.
7. Claim blocked by caps → toast title/body reflect mission-wide vs per-member binding scope (see Rules — claim limit copy).

| Error (typical) | Cause |
| --- | --- |
| Not eligible / outside window | Access state or schedule |
| Must join first | Manual activation without `accepted_at` |
| Nothing to claim | No unclaimed completions |
| Exclusivity locked | Another mission in group holds progress/claim |
| Claim limit (`claim_limit_exceeded`) | Binding `mission_limit_claim` row exhausted or requested qty over `claimable_now`; response includes binding scope/cap/period for member copy |

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
| `bff_get_user_missions` / `bff_get_mission_detail` | Member list and detail + access + `button_action`; detail `progress` includes binding claim-limit fields from `fn_mission_claim_quota` |
| `fn_mission_claim_quota` | Resolves binding claim cap + `claimable_now` for detail and claim-limit errors |
| `accept_mission` | Manual join |
| `bff_claim_mission` / `bff_frontline_claim_mission` | Manual claim (member vs staff) |
| `fn_mission_access_state` | Central visibility/join/claim gating |
| `fn_evaluate_mission_conditions` | Map event → increment map |
| `fn_update_mission_progress` | Apply JSONB updates, waterfall, per-bill loops, completion detection |
| `fn_check_progress_limits` | Completions left under progress limits; checked before every completion |
| `fn_mission_all_time_limit_reached` | True when an all-time progress limit is used up; keeps the bar full instead of resetting |
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
- **AMP mission drafts** — `fn_amp_analysis_create_mission_draft` inserts standard missions with loop off and no progress limit, so they rely on the legacy once-per-member fallback. Once that path adopts the admin default (loop on + 1 per member, all time), the fallback in `fn_update_mission_progress` can be removed.
- **Milestone and progress limits** — one event that completes several levels records one completion per level without checking remaining limit headroom mid-burst.
- **Weekly reset** — weekly reset frequency saves, but scheduled global reset jobs exist only for daily and monthly.
- **Milestone skip** — the setting is saved and shown in Mission settings, but mission progress never evaluates it; it has no effect on which levels a member can reach.
- **Purchase_Transaction.md** — Older passages describing 30s batch mission evaluation and DB triggers for auto missions are stale relative to chokepoint + Inngest path; treat this doc as authoritative for mission progress timing.

## Related

- **Purchase Transaction** — Purchase and item chokepoint events feed mission routers; see `Purchase_Transaction.md`.
- **Currency** — Wallet earn events feed points/ticket conditions; grants post via dispatcher; see `Currency.md`.
- **Forms** — Form submission condition type pending chokepoint wiring; see `Forms.md`.
- **Referral** — Referral condition types pending chokepoint wiring; see `Referral.md`.
- **Central Outcome Dispatcher** — All mission grants; see `Central_Outcome_Dispatcher.md`.
- **Check-in** — Parallel engagement mechanic sharing dispatcher patterns; see `Checkin.md`.
