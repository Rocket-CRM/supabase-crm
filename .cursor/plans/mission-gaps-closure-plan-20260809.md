# Missions Gap Closure and Architecture Enhancement Plan — 2026-08-09

## Readiness status

**Ready for implementation of Part I after S0**, with the locked decisions below.  
Part II (`E1–E4`) is roadmap / separately approved work — not required to close the requester gaps.

| Gate | Status |
|---|---|
| Product decisions for gap closure | Locked in this doc |
| Live write path identified | Locked: `bff_upsert_mission(p_data jsonb)` exists |
| Stabilization before gaps | Required: complete **S0.1–S0.6** before or with early G slices as ordered |
| FE work | In scope as thin mapping only (see FE section) — no redesign |
| Destructive legacy drops (`E3`) | Explicitly **not** in first implementation thread |

### Locked product defaults (was open; now decided)

1. **`preview_advance_days` NULL** = no early preview (hidden until `start_date`).
2. **Merchant TZ** = `merchant_master.currency_award_timezone`; if null/invalid → **UTC** + log/observable error on reset/limit boundary calc.
3. **Claim vs progress exclusivity** = keep separate; “complete many, claim one” uses **claim tag only**.
4. **Signup date** = `user_accounts.created_at` converted to merchant-local **date**.
5. **Persona group in v1** = yes (`eligible_persona_group_ids`).
6. **`start_date`** = required on create/update via `bff_upsert_mission` validation (column may stay nullable for legacy rows; new writes must set it).
7. **`max_loops_per_transaction`** = when `allow_progress_loop = true`, require a positive integer (no silent unlimited). Non-looping missions keep NULL.
8. **Weekly reset storage** = do **not** add `weekly` to shared `tier_execution_frequency` (used by tiers: `realtime|daily|monthly|period_end`). Migrate `mission.progress_reset_frequency` to a **mission-owned** type/text check: `NULL | daily | weekly | monthly` only. Map existing `daily`/`monthly` values; reject/ignore any accidental non-mission labels if present.
9. **Claim after persona change** = already-earned completions remain claimable; eligibility re-check applies to join/progress only.
10. **Part II event coverage** = blocked in admin until each route ships; no speculative condition enabling.

---

## Verdict

The mission system has a sound core: mission definitions are separate from per-user progress, platform events arrive through the shared chokepoint/outbox/Inngest path, and a shared outcome dispatcher already exists. It does not need a rewrite or a generic rules engine.

The main problem is architectural drift. Standard and milestone outcomes use different paths, automatic outcome distribution has a state-ordering defect, retries are not protected at the database boundary, stacked limits are stored but not fully enforced, eligibility and schedule checks differ by entry point, and an unnecessary materialized view is kept alive by two refresh crons.

The clean direction is:

1. Stabilize the existing boundaries.
2. Remove duplicate and stale machinery.
3. Add the requested gaps as attributes and rules of the existing mission model.
4. Keep unsupported event domains as an explicit roadmap until each goal contract is defined.

This plan has two delivery parts:

- **Part I — Gap closure:** the requested schedule, eligibility, exclusivity, carry-over, reset, and frequency behavior.
- **Part II — Architecture enhancements:** correctness, simplification, event coverage, and measured scale improvements.

Correctness stabilization precedes both.

---

## Decisions already made

- **No Mission Group master.** Continue using free-text `claim_exclusivity_group` and `progress_exclusivity_group`.
- **No parallel mission configuration system.** Extend `mission`, existing child tables, and existing BFFs.
- **No generic condition/rule engine.** Mission conditions remain a bounded mission-domain contract.
- **No mission-specific event pipeline.** Preserve the shared chokepoint → outbox → Inngest route.
- **Configurable preview.** Preview lead time is not hardcoded to seven days.
- **Carry-over is loop remainder only.** It seeds the next progress bar but never survives a scheduled reset.
- **Merchant timezone is authoritative.** Reuse `merchant_master.currency_award_timezone`; use UTC only when the value is absent or invalid.
- **Unsupported event types stay blocked.** Do not let admins save missions that can never receive an event.
- **Shared outcomes are authoritative.** Points, tickets, and rewards must all pass through `fn_dispatch_outcome`.
- **Database idempotency stays minimal.** One unique event identity constraint; no new framework or subsystem.
- **Remove the mission materialized view.** Direct indexed reads are simpler and adequate; caching returns only if measurements justify it.

---

## Frame and type model

A mission is a definition that turns qualifying member events into progress, completions, and outcomes.

1. **Definition** — `mission` owns schedule, audience eligibility, activation, reset, looping, and exclusivity settings.
2. **Goal** — `mission_conditions` describes which event counts, its filters, measurement (`count` or `sum`), target, and AND/OR or milestone structure.
3. **Outcome** — `mission_outcomes` describes points, tickets, or rewards granted for a completion.
4. **Runtime state** — `mission_progress` stores one lockable progress document per user/mission.
5. **Audit records** — `mission_progress_events` records accepted increments; `mission_log_completion` records earned completions.
6. **Shared delivery** — `fn_dispatch_outcome` applies outcomes through the common wallet/reward chokepoints and records them in `outcome_distribution_log`.

This split is clean and should remain. In particular, `condition_progress jsonb` is appropriate: it avoids a high-write row per condition while retaining one transaction boundary per user/mission.

---

## Live architecture contract

### Current event path

```text
domain write
  → domain chokepoint
  → chokepoint_event_outbox
  → crm-event-processors OutboxPublisher
  → inngest-event-router-serve
  → one mission/evaluate event per candidate mission
  → inngest-mission-serve
  → fn_evaluate_mission_conditions
  → fn_update_mission_progress
  → mission_log_completion
  → claim or automatic distribution
  → fn_dispatch_outcome
```

Keep this architecture. Per-mission Inngest fan-out gives useful retry isolation, and the current scale does not justify replacing it with a large batch transaction.

### Live mission inputs

| Input | Status | Mission interpretation |
|---|---|---|
| Completed purchase header | Live | Unscoped purchase count/sum |
| Completed purchase item | Live | Product/SKU/category/brand-scoped purchase |
| Wallet earn | Live | Points or ticket earnings |
| Form submission | No live route | Admin save is blocked |
| Referral signup/purchase | No live route | Admin save is blocked |
| User signup | Chokepoint exists; no mission router | Roadmap |
| Tier change | Chokepoint exists; no mission router | Roadmap |
| Redemption | Chokepoint exists; no mission router | Roadmap |
| Activity | No mission condition contract or route | Roadmap |

### Live facts that replace stale assumptions

- `bff_upsert_mission(p_data jsonb)` is the current admin write path. The 2026-07-08 change removed its inline materialized-view refresh, not the function.
- `mission_conditions.tier_ids` is persisted by admin BFFs but is not enforced by `fn_evaluate_mission_conditions`.
- `progress_exclusivity_group` blocks a second manual acceptance. It does not stop one event from progressing multiple auto missions.
- `claim_exclusivity_group` blocks a second claim, but sibling missions continue receiving progress afterward.
- `max_loops_per_transaction` is stored but not applied by standard progress calculation.
- `mission_limit_progress` can contain stacked rows, but `fn_update_mission_progress` reads one arbitrary row.
- Global reset crons invoke `fn_batch_reset_global_missions` (one- and two-arg overloads both exist live).
- `mission.progress_reset_frequency` is typed as shared enum `tier_execution_frequency` today; live values in use are only `daily`, `monthly`, or null. **Do not extend that shared enum for weekly.**
- `mission_evaluation_queue` and its functions are legacy remnants; Inngest is the active owner.
- `requirements/domains/mission.md` **exists** as a thin domain pointer — cite it for keyword/route map only; deep rules live in `Mission.md` / feature guide.
- `Mission.md` Operational Notes still say `bff_upsert_mission` was “removed” — that note is **stale**. Live DB has the function; 2026-07-08 removed inline MV refresh only. Fix that doc line when Mission.md is updated.

---

## Cleanliness and scale review

### Keep

- Shared chokepoint/outbox transport.
- Per-mission Inngest fan-out.
- Separate definition, progress, event, completion, and outcome concepts.
- One `mission_progress` row per user/mission.
- Existing condition and outcome child tables.
- Free-text exclusivity tags.
- Existing loop and limit persistence model.

### Simplify now

1. **One outcome path.** Standard/manual claims already reach `fn_dispatch_outcome`; milestone distribution still performs direct reward work and legacy HTTP currency publishing. Converge both.
2. **One access decision.** List, detail, accept, progress, and claim currently apply different subsets of schedule and eligibility checks. Centralize the decision.
3. **One reset scheduler.** Replace frequency-specific reset crons with indexed due-time processing through `mission_progress.next_reset_at`.
4. **No materialized mission cache.** Remove `mv_mission_conditions_expanded` and its two refresh crons.
5. **No dead queue path.** Retire the queue table/functions after dependency proof.
6. **No duplicate distribution log.** Make `outcome_distribution_log` canonical; retire `mission_log_outcome_distribution` only after all readers move.

### Defer until measurements justify change

- Batch evaluation of all missions in one transaction.
- A new progress storage model.
- Partitioning mission logs.
- A mission-specific counter service.
- A new cache or materialized view.
- A separate mission timezone.

### Scale watchpoints

- Each source event fans out to each candidate mission. Measure fan-out count, router queue age, and evaluation latency before changing the model.
- `global_completion_number` currently uses a per-mission advisory lock plus `COUNT(*) + 1`. If a high-volume mission shows lock contention, first confirm the ordinal is product-required; then replace it with an O(1) counter. Do not build this preemptively.
- Add per-merchant Inngest concurrency only if one merchant can starve others.
- Retain standard indexes on `mission_progress`, `mission_progress_events`, and completion logs; add new indexes only from observed query plans.

---

## Mandatory stabilization

These are prerequisites because the requested features depend on them.

### S0.1 — Converge outcome distribution on the shared engine

**Current state**

- `fn_process_mission_outcomes` calls shared `fn_dispatch_outcome`.
- `fn_process_mission_outcomes_for_milestone` still grants rewards directly and sends points/tickets through the legacy HTTP publisher.
- `fn_dispatch_outcome` records `outcome_distribution_log`, but `bff_claim_mission` reads `mission_log_outcome_distribution`.
- Automatic completion inserts `is_claimed = true` before calling a processor that selects `is_claimed = false`, so automatic outcomes can be skipped.

**Clean target**

Create one thin completion-scoped mission wrapper, for example:

`fn_distribute_mission_completion(p_completion_log_id uuid) -> jsonb`

It should:

1. Lock one completion row.
2. Return success when that completion is already distributed.
3. Select the standard outcomes or the completion's milestone outcomes.
4. Call `fn_dispatch_outcome` once per outcome.
5. Use dedup key `mission:<completion_id>:<outcome_id>`.
6. Mark `is_claimed`, `claimed_at`, and `outcomes_distributed` only after every outcome succeeds.
7. Leave the completion retryable after any failure.

Manual and automatic claims call the same wrapper. Existing public functions may remain as compatibility wrappers during rollout.

**Do not**

- Build a second outcome queue.
- Duplicate points/tickets/reward logic in mission functions.
- Mark a completion distributed when one outcome failed.
- Drop the mission-specific log until all BFF/report dependencies are moved.

**Verification**

- Standard and milestone: points, tickets, reward, and mixed outcomes.
- Automatic and manual claim.
- Retry after one failed outcome grants successful outcomes only once.
- Claim BFF reads the canonical shared log.
- Audit existing claimed-but-undistributed completions before deciding on replay.

### S0.2 — Add minimal database idempotency

Inngest idempotency protects transport execution for a limited window. The database must reject the same source event for the same mission permanently.

**Minimal implementation**

1. Audit duplicate non-null identities in `mission_progress_events`.
2. Resolve existing duplicates deliberately; do not silently delete business history.
3. Add one partial unique index:

   `(user_id, mission_id, trigger_type, trigger_id) WHERE trigger_id IS NOT NULL`

4. In `fn_update_mission_progress`, insert the progress-event row with `ON CONFLICT DO NOTHING RETURNING id`.
5. If no row is returned, report `duplicate_event` and stop before changing progress.

No idempotency table, service, status machine, cleanup job, or generic framework is needed.

### S0.3 — Fix event classification and feedback behavior

- Wallet router must map `points` to `points_earned`, `ticket` to `tickets_earned`, and ignore unrelated currencies such as store credit.
- Mission-generated wallet outcomes use source type `mission`. Exclude them from mission progress by default to prevent accidental feedback loops; allow them only when a condition explicitly includes that earn source.
- Preserve the purchase-header versus purchase-item split so scoped conditions are not double-counted.

### S0.4 — Enforce all applicable limits

**Current problem:** stacked rows are stored, but progress evaluation reads one row.

**Target**

- Every applicable limit row must pass.
- Keep `mission_limit_progress` as qualifying-progress-event limits.
- Keep `mission_limit_claim` as outcome-claim limits.
- Support `user` and `total` scopes where current data can enforce them.
- Reject `user_store` and `store` in admin validation until the progress/claim audit records carry a trustworthy store identity.
- Use calendar boundaries for `day`, `week`, and `month`; `all_time` has no reset.
- Use the same merchant-timezone boundary helper as reset scheduling.

Do not add another limits table or a frequency engine.

### S0.5 — Remove the materialized view

`mv_mission_conditions_expanded` currently contains roughly one row per mission and is consumed only by `fn_evaluate_mission_conditions`. It is refreshed both every minute and daily, creating stale configuration and redundant operations. Active-mission discovery already queries base tables.

**Change**

1. Update `fn_evaluate_mission_conditions` to load one mission and aggregate its conditions directly from indexed `mission` and `mission_conditions` rows.
2. Compare evaluator output against the MV-backed version for standard, OR, milestone, and filtered missions.
3. Measure representative evaluation latency.
4. Remove `refresh-mission-conditions-mv-fast`.
5. Remove `refresh-mission-conditions-mv`.
6. Drop `refresh_mission_conditions_mv` and `mv_mission_conditions_expanded` after dependency verification.

Do not replace the MV with Redis or another cache. Reintroduce caching only if production measurements show direct reads are inadequate.

### S0.6 — Centralize the access-state contract

Add one small mission-domain helper used by list/detail/accept/progress/claim paths. It returns:

- `is_visible`
- `can_join`
- `can_progress`
- `can_claim`
- reason codes for the first failed gate

The helper evaluates merchant ownership, active state, preview/validity/claim windows, persona eligibility, signup window, acceptance requirement, and claim-group lock. Goal calculation remains in the evaluator.

This is a justified abstraction because the same decision has five callers. It must not become a generic policy engine.

---

# Part I — Gap closure

## G1 — Schedule: validity, preview, and claim end

### Minimal schema on `mission`

- `claim_end_date timestamptz NULL`
- `preview_advance_days integer NULL`

Constraints:

- `preview_advance_days IS NULL OR preview_advance_days >= 0`
- `claim_end_date IS NULL OR end_date IS NULL OR claim_end_date >= end_date`

Defaults / write rules:

- `NULL preview_advance_days` means no early preview.
- `NULL claim_end_date` means `end_date`.
- If both claim end and mission end are null, there is no automatic claim deadline.
- `bff_upsert_mission` requires `start_date` on create/update.

### Behavior

- **Before preview:** hidden.
- **Preview:** visible, but join and progress are disabled.
- **Validity (`start_date` through `end_date`):** join and progress are allowed when other gates pass.
- **After validity through claim end:** no new progress; earned manual completions may still be claimed.
- **After claim end:** manual claim is disabled and normal member reads omit the mission.
- **Automatic outcome retry:** an outcome earned during validity remains retryable after claim end; claim end must not destroy an already-earned automatic completion.

### Touchpoints

- `bff_upsert_mission`
- `bff_get_mission_details_conditions_limits`
- `bff_get_user_missions`
- `bff_get_mission_detail`
- `accept_mission`
- `fn_update_mission_progress`
- `bff_claim_mission`
- completion distribution wrapper

## G2 — Eligibility: persona, persona group, signup range, and tier

Eligibility answers **who may see/join/progress**. It is not a progress goal and must not be represented as another mission condition.

### Minimal schema on `mission`

- `eligible_persona_ids uuid[] NULL`
- `eligible_persona_group_ids uuid[] NULL`
- `signup_window_start date NULL`
- `signup_window_end date NULL`

Semantics:

- Null or empty persona arrays mean all personas.
- Persona IDs and group IDs are OR within their own list and AND across configured eligibility dimensions.
- Resolve persona group through `user_accounts.persona_id → persona_master.group_id`.
- Compare `user_accounts.created_at` as a merchant-local date.
- Null signup endpoints are open-ended.
- Validate referenced persona and group IDs belong to the mission merchant in `bff_upsert_mission`.

Arrays are intentional here: they match the small mission-definition cardinality and avoid an entitlement subsystem. Do not add GIN indexes unless query plans require them.

### Tier correction

`mission_conditions.tier_ids` exists but is currently ignored by evaluation. Enforce it as an event-time condition filter. Do not claim tier support until this is tested.

### Apply eligibility consistently

- Member list/detail: omit ineligible missions.
- Manual join: reject ineligible users.
- Progress update: reject if eligibility changed after acceptance.
- Claim: allow an already-earned completion even if persona later changes, unless product explicitly introduces revocation.

## G3 — Timezone-aware reset and weekly cadence

### Storage

- Continue using `mission_progress.next_reset_at`; it already has a due-row index (`idx_mission_progress_next_reset_at`).
- **Migrate** `mission.progress_reset_frequency` off shared `tier_execution_frequency` onto a mission-owned type (enum or text + check): allowed values `daily | weekly | monthly` (null = no scheduled incomplete-progress reset).
- Migration steps: add new column or alter type with explicit cast of existing `daily`/`monthly`; never `ALTER TYPE tier_execution_frequency ADD VALUE 'weekly'`.
- Do not add a mission timezone column.

### Scheduling

Replace daily/monthly frequency-specific reset crons with one frequent batched due-row job:

1. Select active `mission_progress` rows where `next_reset_at <= now()`.
2. Lock with `FOR UPDATE SKIP LOCKED`.
3. Reset incomplete progress.
4. Calculate and store the next due time.
5. Repeat in bounded batches.

Boundary rules:

- **Global daily:** next local midnight.
- **Global weekly:** Monday 00:00 local.
- **Global monthly:** first day of next month 00:00 local.
- **User-specific:** next interval from `period_started_at`, calculated in merchant timezone so DST does not drift calendar intent.

Use `merchant_master.currency_award_timezone`, with UTC fallback and an observable invalid-timezone error.

One calendar-boundary helper may serve resets and limit windows. Do not modify a shared rolling-window helper if other domains depend on its current meaning.

## G4 — Claim exclusivity: complete many, claim one

Desired behavior for missions sharing `claim_exclusivity_group`:

1. Siblings may progress and complete before any claim.
2. The first successful claim/distribution wins.
3. Other siblings become non-claimable.
4. Other siblings stop receiving new progress.
5. Existing sibling progress is retained for audit; it is not deleted.

Implementation:

- Keep the existing text tag.
- Serialize competing claims for the same user/group inside the claim transaction using the existing database transaction boundary; add only a lightweight advisory lock if race testing proves the current trigger is insufficient.
- Make `fn_update_mission_progress` the authoritative stop-progress guard.
- Derive `exclusivity_locked` and CTA state at read time.

Do not add a lock column, group table, winner-selection engine, or router-side eligibility query.

`progress_exclusivity_group` remains a separate manual-join rule. Do not merge the two concepts.

## G5 — Carry-over remainder

V1 supports carry-over only when all are true:

- `allow_progress_loop = true`
- `carry_over_progress = true`
- standard mission
- exactly one condition
- condition uses `measurement_type = 'sum'`

### Minimal schema on `mission`

- `carry_over_progress boolean NOT NULL DEFAULT false`

### Calculation

For target `T`, current progress `C`, and accepted increment `I`:

1. `total = C + I`
2. `raw_completions = floor(total / T)`
3. `completed = min(raw_completions, max_loops_per_transaction)`
4. If carry-over is enabled, next progress is `total - completed * T`, capped below `T` when the loop cap is reached.
5. If carry-over is disabled, next progress is zero after completion.
6. Scheduled reset always clears the remainder.

Persist one completion log per awarded completion or an explicitly documented aggregated row; outcome idempotency must still be completion-specific.

Reject carry-over for AND/OR multi-condition missions, count/binary goals, non-looping missions, and milestones. Milestones already have waterfall behavior.

## G6 — Frequency contract

Keep the current storage:

| Admin intent | Existing configuration |
|---|---|
| Once | `allow_progress_loop = false` |
| Multiple | `allow_progress_loop = true` |
| Limited | Loop setting plus stacked progress/claim limit rows |

Add concise `bff_upsert_mission` validation:

- Carry-over requires the G5 shape.
- Milestones cannot use scheduled progress reset or carry-over.
- Looping requires a positive `max_loops_per_transaction` (NULL unlimited is retired for loop missions).
- Every tighter configured window must not exceed a wider hard cap when the scopes match.
- Unsupported store scopes are rejected until store identity is carried by audit events.
- Condition types without live event routes are rejected.

The frontend may expose a simplified frequency control that writes these fields. Do not persist another frequency mode.

---

# Part II — Architecture enhancements

## E1 — Event coverage roadmap

Add a new mission event integration only after defining:

1. The business goal.
2. Event identity and idempotency key.
3. Count versus sum behavior.
4. Required filters.
5. Reversal/cancellation behavior.
6. Whether backfills/imports should count.

Priority:

1. **Redemption** — existing chokepoint; supports “redeem N rewards.”
2. **User signup** — existing chokepoint; separate from signup-date eligibility and requires burst controls.
3. **Tier change** — existing chokepoint; define upgrade/downgrade and target-tier filters.
4. **Form submission** — add a form chokepoint before adding a router.
5. **Referral** — add referral events before enabling the existing enum values.
6. **Activity** — define the activity ontology first; do not add a generic activity condition.

Until an integration ships, keep its condition type unavailable in admin writes.

## E2 — Mission completion event

Do not add this solely for internal mission processing. Add a `mission.completed` shared event only when another module has a concrete consumer such as notifications, AMP enrollment, or analytics that cannot rely on completion logs.

If added, emit from the completion chokepoint with completion ID as the event identity. It must not be used to distribute the mission's own outcomes.

## E3 — Legacy retirement

After live dependency checks and observation:

- Drop `mission_evaluation_queue`.
- Drop `queue_mission_evaluation_batch`.
- Drop `process_mission_evaluation_batch`.
- Drop `trigger_mission_evaluation_realtime` if no trigger references it.
- Remove the orphaned mission currency publisher path.
- Remove `fn_process_mission_outcomes_for_milestone` after all callers use the shared wrapper.
- Remove `mission_log_outcome_distribution` after BFF/report migration and retention decision.
- Remove obsolete docs that describe CDC/Kafka mission ownership.

Destructive removal is a separate approved migration after dependency evidence.

## E4 — Observability before optimization

Track:

- outbox publication delay by topic
- candidate missions per source event
- mission router queue age and retry count
- evaluator and progress-update latency
- duplicate-event rejections
- claim/distribution failures by outcome type
- due reset backlog
- advisory-lock wait time for completion numbering

Define alert thresholds from production baselines. Do not introduce batching, partitioning, or caching before the measurements identify a bottleneck.

---

## Implementation order

1. **S0.1:** outcome convergence and claimed-but-undistributed audit.
2. **S0.2–S0.4:** minimal idempotency, event classification, and stacked limits.
3. **S0.5:** direct condition reads; remove MV and duplicate refresh crons after proof.
4. **S0.6 + G1:** shared access state and schedule semantics.
5. **G2:** persona/group/signup eligibility and tier enforcement.
6. **G3:** due-time reset scheduler and weekly timezone boundaries.
7. **G4:** claim-group stop-progress behavior.
8. **G5:** single-sum carry-over and real loop cap.
9. **G6:** frequency validation/frontend mapping.
10. **E1–E4:** event integrations and cleanup as separately approved slices.

Each slice follows:

`dependency check → migration/function change → focused smoke tests (matrix below) → regression tests → docs/registry/changelog → observe → next slice`

Do not combine destructive legacy removal with product behavior changes.

---

## Smoke matrix (minimum per slice)

Run these before marking a slice done. Prefer SQL/RPC against a throwaway merchant + users; no full E2E suite required in v1.

### S0 — Stabilization

| ID | Case | Expect |
|---|---|---|
| S0.1a | Standard auto-claim: points + tickets + reward | All via `fn_dispatch_outcome`; completion marked claimed only after success; rows in `outcome_distribution_log` |
| S0.1b | Milestone manual claim one level | Same path; no direct reward ledger / legacy HTTP currency publish |
| S0.1c | Auto completion with forced mid-outcome failure, then retry | Partial success not duplicated; completion stays retryable until all outcomes succeed |
| S0.1d | Audit query: claimed completions with no distribution log | Count + sample listed before any replay decision |
| S0.2a | Same `(user, mission, trigger_type, trigger_id)` twice | Second call → `duplicate_event`; progress unchanged |
| S0.2b | `trigger_id` null events | Still process (unique index is partial); no false collision |
| S0.3a | Wallet `points` / `ticket` / store-credit events | Map to points_earned / tickets_earned / ignore |
| S0.3b | Wallet earn with source `mission` | Ignored unless condition explicitly allows that earn source |
| S0.4a | Stacked progress limits daily=1 and all_time=5 | Day 1: one qualifying event OK, second blocked; across days up to 5 then blocked |
| S0.4b | Claim limit vs progress limit | Progress can complete when claim limited; claim path enforces claim rows |
| S0.4c | Upsert with `user_store` / `store` scope | Rejected until store identity exists on audit events |
| S0.5a | Evaluator parity: standard / OR / milestone / filtered | Direct-table eval matches prior MV result on fixture set |
| S0.5b | After MV drop | No callers of `refresh_mission_conditions_mv` / MV relation |
| S0.6a | Same user+mission through list, detail, accept, progress, claim | Identical gate outcomes from shared access helper |

### G1 — Schedule

| ID | Case | Expect |
|---|---|---|
| G1a | Before preview window | Hidden from member list/detail |
| G1b | In preview (`preview_advance_days` set) | Visible; join/progress disabled |
| G1c | In validity | Join + progress allowed |
| G1d | After `end_date`, before `claim_end_date` | No new progress; manual claim of earned completion OK |
| G1e | After claim end | Omitted from normal member reads; claim disabled |
| G1f | `claim_end_date` null | Defaults to `end_date` |
| G1g | Upsert `claim_end_date` < `end_date` | Rejected |
| G1h | Upsert without `start_date` | Rejected |
| G1i | Auto outcome earned in validity, retry after claim end | Retry still distributes |

### G2 — Eligibility

| ID | Case | Expect |
|---|---|---|
| G2a | Persona match / mismatch | See+join only when match (or filter null/empty) |
| G2b | Persona group match via `persona_master.group_id` | Same |
| G2c | Persona IDs OR within list; AND with signup window | Outside signup date → hidden even if persona matches |
| G2d | Signup window uses merchant-local date of `created_at` | Boundary dates inclusive as documented in impl |
| G2e | `tier_ids` on condition | Non-matching tier event does not increment |
| G2f | Persona changes after completion earned | Claim still allowed; new progress rejected if now ineligible |
| G2g | Upsert persona/group IDs from another merchant | Rejected |

### G3 — Reset + timezone

| ID | Case | Expect |
|---|---|---|
| G3a | Merchant TZ Asia/Bangkok, weekly | `next_reset_at` = next Monday 00:00+07 |
| G3b | Merchant TZ null/invalid | UTC boundaries + observable error/log |
| G3c | Due-row job | Resets incomplete progress only; advances `next_reset_at`; `SKIP LOCKED` batch safe |
| G3d | Column type | `progress_reset_frequency` is mission-owned; `tier_execution_frequency` unchanged (no `weekly` there) |
| G3e | User-specific monthly | Boundary from `period_started_at` in merchant TZ |

### G4 — Claim exclusivity

| ID | Case | Expect |
|---|---|---|
| G4a | Two missions same claim tag; complete both | Both can reach completion |
| G4b | Claim A | B cannot claim; B receives no further progress increments |
| G4c | Concurrent claim A and B | Exactly one wins; no double distribute |
| G4d | Progress exclusivity tag alone | Unchanged manual-accept rule; not merged with claim tag |
| G4e | Member read after lock | Sibling shows non-claimable / exclusivity_locked derived state |

### G5 — Carry-over

| ID | Case | Expect |
|---|---|---|
| G5a | Target 1000, progress 0, event +3500, carry on, max_loops ≥ 3 | 3 completions; next bar progress 500 |
| G5b | Same with carry off | Completions awarded per loop rules; remainder 0 after completion handling |
| G5c | `max_loops_per_transaction = 2` on +3500 | 2 completions; remainder follows G5 formula with cap |
| G5d | Carry-over + scheduled reset due | Reset clears remainder |
| G5e | Upsert carry-over on multi-condition / milestone / count / non-loop | Rejected |

### G6 — Frequency validation

| ID | Case | Expect |
|---|---|---|
| G6a | Loop true, `max_loops_per_transaction` null | Rejected |
| G6b | Daily limit amount > all_time amount, same scope | Rejected |
| G6c | Dead condition type (form/referral) | Rejected at upsert |
| G6d | Once / multiple / limited via existing fields only | No new frequency column persisted |

### First-thread out of scope (do not smoke as done)

- E1 new event routers
- E3 DROP queue / MV / `mission_log_outcome_distribution` without separate approval
- FE pixel-perfect polish beyond field mapping + CTA states

---

## Acceptance checklist

### Architecture and simplicity

- [ ] Chokepoint/outbox/Inngest remains the single event path.
- [ ] No Mission Group master, generic rules engine, mission-specific queue, or new frequency subsystem.
- [ ] Standard and milestone outcomes use shared `fn_dispatch_outcome`.
- [ ] `outcome_distribution_log` is canonical.
- [ ] Materialized mission view and duplicate refresh crons are removed after direct-query proof.
- [ ] Database idempotency uses one partial unique identity constraint only.

### Correctness

- [ ] Retrying one source event does not increment the same mission twice.
- [ ] Automatic completions distribute outcomes before being marked claimed/distributed.
- [ ] Partial outcome failure remains retryable and does not duplicate successful outcomes.
- [ ] Wallet store-credit events are not treated as ticket earnings.
- [ ] Mission-awarded currency does not recursively progress missions unless explicitly configured.
- [ ] All applicable stacked limit rows are enforced.

### Gap closure

- [ ] Preview, validity, and claim windows produce consistent list/detail/join/progress/claim behavior.
- [ ] Persona, persona group, and signup filters are ANDed consistently.
- [ ] Tier filters are enforced at evaluation time.
- [ ] Daily, weekly, and monthly reset boundaries use merchant timezone.
- [ ] First successful claim locks sibling claims and future progress.
- [ ] Carry-over works only for the approved single-sum loop shape and reset clears it.
- [ ] `max_loops_per_transaction` is enforced.
- [ ] Frequency remains a projection of loops plus existing limits.

### Scale and operations

- [ ] Due resets process in bounded `SKIP LOCKED` batches.
- [ ] Fan-out, queue age, evaluation latency, distribution failures, and lock waits are observable.
- [ ] No cache, batch evaluator, partitioning, or counter subsystem is added without measured need.

---

## Frontend scope (thin; no redesign)

Admin (`Rocket-CRM/loyalty-admin`) and member (`Rocket-CRM/loyalty-user`) only map new fields and states — no new IA.

| Surface | Work |
|---|---|
| Admin mission settings | Fields: claim end, preview days, carry-over checkbox, persona/group multi-select, signup window, weekly reset, simplified frequency control → existing loop/limit fields |
| Admin validation | Surface upsert error codes from G6 / dead condition types |
| Member list/detail | Honor access-state helper: preview CTA disabled; hidden after claim end; exclusivity_locked siblings |
| Member claim/join | No new flows; respect reason codes |

FE can ship after the corresponding BFF contracts land (G1/G2/G4 first for member UX).

---

## Documentation updates required with implementation

- `requirements/Mission.md` — current architecture and business contracts; fix stale “upsert removed” note.
- `requirements/feature-docs/missions.md` — admin/member behavior and supported event types.
- `requirements/domains/mission.md` — refresh keyword/pointer rows if new columns/RPCs appear.
- `requirements/REGISTRY_SUPABASE.md` — regenerate after schema/function changes.
- `requirements/REGISTRY_RENDER.md` — update crons and Edge Function ownership (reset cron consolidation; MV cron removal).
- `requirements/CHANGELOG.md` — one concise entry per delivered slice.
- CRM Knowledge Missions blocks — replace stale CDC/Kafka details after deployed behavior is verified.

---

## Pre-flight for the implementing thread

1. Attach this plan.
2. Re-confirm S0.1 defect (auto `is_claimed=true` before distribute) with a focused read of `fn_update_mission_progress` / outcome processors — then implement S0.1 first.
3. Do **not** start G1 schema until S0.1–S0.2 are approved to apply (or explicitly parallelized by the user).
4. Keep `E1–E4` out of the first PR/thread unless the user expands scope.
5. Approval required before any `DROP` of MV, queue, or `mission_log_outcome_distribution`.
6. Mark each slice done only after its smoke IDs in the matrix pass (and docs/registry/changelog updated).

---

## Critical context

- Supabase project: `wkevmsedchftztoolkmi`
- Live admin write: `bff_upsert_mission(p_data jsonb)`
- Live admin read: `bff_get_mission_details_conditions_limits`
- Core evaluation: `fn_evaluate_mission_conditions`
- Core progress: `fn_update_mission_progress`
- Shared outcome engine: `fn_dispatch_outcome`
- Current event routers: `mission-purchase-router`, `mission-purchase-item-router`, `mission-wallet-router`
- Merchant timezone: `merchant_master.currency_award_timezone`
- Reset frequency column type today: `tier_execution_frequency` (migrate off in G3)
- Active reset crons: `mission-daily-global-reset`, `mission-monthly-global-reset`
- Redundant MV crons: `refresh-mission-conditions-mv`, `refresh-mission-conditions-mv-fast`
- Authoritative docs: `requirements/Mission.md`, `requirements/feature-docs/missions.md`
- Domain pointer: `requirements/domains/mission.md`
