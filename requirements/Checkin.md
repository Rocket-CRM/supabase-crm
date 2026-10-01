# Check-in

Attendance campaigns that reward members for returning on a cadence. Merchants configure evaluation shape, eligibility, caps, and outcomes; members record attendance in the app; the system appends an immutable ledger row and dispatches every matched outcome through the central outcome dispatcher.

Owner surfaces: loyalty-admin, loyalty-user

## Concept

Check-in is an **attendance mechanic**: a merchant runs one or more **campaigns** at once (for example a daily habit loop and a month-long sprint). Each campaign defines how **progress** is measured, who may participate, when check-in is allowed, and what **outcomes** fire on which **triggers**. The member-facing loop is unchanged at a high level: open status → tap check-in → see progress and grants.

**Check-in campaign** — Named program with frequency, condition shape, optional time and campaign windows, eligibility filters, participation caps, and a set of outcomes.

**Frequency type** — `daily` or `weekly`. Controls **streak continuity** for consecutive campaigns only (not how calendar “today” is labeled on the ledger).

**Condition type** — How progress is evaluated: `consecutive` (classic streak), `fixed_period_count` (X check-ins between fixed dates), or `rolling_period_count` (X check-ins in any trailing window of N days).

**Streak** — For `consecutive` campaigns: consecutive check-ins without a gap. Daily: gap longer than one calendar day resets. Weekly: gap longer than seven days resets. Derived from the ledger at read/eval time, not a separate streak store.

**Period count** — For `fixed_period_count` or `rolling_period_count`: tally of check-ins inside the configured period or rolling window, computed from the ledger when processing and when showing status.

**Outcome** — One configured grant row on a campaign (points, tickets, free reward, or earn factor) with a trigger and amount.

**Trigger type** — When an outcome is eligible to fire: `every_checkin` (each valid check-in), `streak_milestone` (streak day within a configured range), or `period_milestone` (period count equals target; **fire-once per member** per outcome, enforced via prior ledger matches).

**Outcome type** — What the member receives: points, tickets (needs ticket type), reward (free redemption), or earn factor (temporary multiplier; default 30-day window via dispatcher).

**Eligibility** — Campaign-level filters on tier, persona, tags (member must have any listed tag), and birth month. Empty or unset means unrestricted.

**Participation limit** — Per-campaign cap stored in the shared participation-limits facility with entity type check-in; scope `user` (per member) or `total` (campaign-wide), over day/week/month/year/all_time (optional absolute window overrides).

**Time window** — Optional daily hours when check-in is allowed, evaluated in the campaign timezone (supports overnight windows when end time is before start time).

**Campaign window** — Optional start/end timestamps when the campaign is active; outside the range the campaign behaves as unavailable.

**Attendance ledger** — Immutable row per check-in: user, campaign, date, streak day at write time, and a JSON list of every outcome dispatch attempt (success or failure). All streak, period, milestone, and history math reads this ledger.

**Require condition match** — When enabled, a check-in is rejected if no outcome would match; when disabled, the check-in can succeed with an empty grant list while still advancing progress where rules allow.

**Per-outcome eligibility (planned)** — Today eligibility is campaign-level only; tier-differentiated grants on one campaign require separate campaigns or this future capability.

Progress is **ledger-derived**. Outcomes are **multi-dispatch**: each match is sent independently through the same dispatcher primitive used by missions, AMP, and referral.

## Rules

- If the campaign is inactive, outside its campaign window, or unknown → check-in fails with a not-found/inactive style error; status reads treat it as unavailable.
- If a daily time window is enabled and current time in the campaign timezone is outside the window → check-in fails with an outside-window error (including window bounds in the response). Overnight windows (start time after end time) use union-of-ranges semantics.
- If tier, persona, tag, or birth-month filters are set and the member does not satisfy them → check-in fails with the corresponding requirement error. Empty filters → all members pass.
- If a participation limit applies and the member or campaign has reached the cap in the configured window → check-in fails with a limit error (includes used/remaining where applicable).
- By default, **multiple check-ins on the same calendar day are allowed**; each creates its own ledger row and can fire `every_checkin` outcomes again. Streak does not advance again on the same date; same-day `streak_milestone` does not re-fire. To enforce one check-in per day, set a participation limit (scope user, count 1, time unit day).
- For `consecutive` + daily frequency: if the last ledger date is yesterday → streak increments; otherwise new streak day is 1. For `consecutive` + weekly: if last check-in within seven days → streak increments; else reset to 1.
- For `fixed_period_count`: period count is check-ins with dates in `[period_start, period_end]`. For `rolling_period_count`: period count is check-ins in the trailing `rolling_window_days` ending now.
- `every_checkin` outcomes match on every valid check-in. `streak_milestone` matches when new streak day is between configured start and end (null end = unbounded high). `period_milestone` matches when period count equals target **and** no prior ledger row for that member already recorded that outcome id in matched grants.
- Multiple outcomes may match one check-in; each dispatches through the central dispatcher with a per-outcome dedup key so duplicate currency grants do not collide. One outcome failing does not block others; failures are recorded on the ledger entry with success false.
- If **require condition match** is true and zero outcomes match → check-in is rejected (no ledger row). If false → check-in proceeds; matched list may be empty while streak/period still advance per condition type.
- Time-window **next deadline** in status responses is null when no daily window is configured; when configured, daily campaigns use next day’s window end in campaign timezone, weekly uses last check-in plus seven days at window end (via shared streak helper).
- Outcome dispatch for rewards uses direct redemption (zero points); earn factor uses dispatcher default window unless metadata overrides window days.
- Admin reversal of a ledger row is supported via admin BFF; corrected ledger data is reflected on the next status read without a separate streak cache.

## Journeys

### Admin journey

| Page | Owning repo | BFF / RPC |
| --- | --- | --- |
| Check-in list | loyalty-admin | `bff_list_checkins` |
| Check-in settings (create/edit) | loyalty-admin | `bff_get_checkin_details` (load), `bff_upsert_checkin` (save) |
| Outcomes (embedded in settings) | loyalty-admin | `outcomes[]` on upsert (full replace) |
| Front line — member Check-in tab | loyalty-admin | `get_user_checkin_status`, `process_checkin` (staff check-in on behalf of member) |
| Front line — recent check-ins / reverse | loyalty-admin | `bff_admin_get_checkin_history`, `bff_reverse_checkin` |

| Setting | Effect on behaviour |
| --- | --- |
| Name / description | Display labels for admin and member surfaces |
| Frequency type | Daily vs weekly streak continuity rules |
| Condition type | Consecutive vs fixed-period vs rolling-period evaluation |
| Period start / end / target count | Fixed-period count target and window |
| Rolling window days / target count | Rolling-period window and target |
| Timezone | Campaign window and daily time-window evaluation |
| Enable time window + start/end times | Restricts check-in to hours; supports overnight span |
| Campaign window start/end | Active range for the campaign |
| Max streak days | Upper bound on streak counter |
| Active status | Master on/off |
| Eligibility arrays | Tier, persona, tags, birth month gates |
| Require condition match | Reject check-in when no outcome would match |
| Outcome rows | Type, amount, entity, trigger, milestone range/target, priority, milestone UI flag |
| Participation limits | Per-user or campaign-wide caps by time unit (optional absolute window) |

1. Open **Check-in list** and start **Add check-in** (or edit an existing row).
2. Set campaign identity, frequency, and condition type; fill period or rolling fields when not consecutive.
3. Set timezone and optional daily time window and campaign date range.
4. Set eligibility filters or leave empty for all members.
5. Add participation limits if caps are needed (including one-per-day if desired).
6. Open **Outcomes**, add rows: pick trigger (`every_checkin`, `streak_milestone`, `period_milestone`), outcome type, amount, and entity when required; set streak range or period target; set priority and milestone flag; save (upsert replaces all outcomes and limits on each save).
7. On **Front line**, open the member **Check-in** tab to run check-in or inspect status; use **Recent check-ins** to view history and **Reverse check-in** on a ledger id when correcting attendance.

Common pitfalls: require condition match with no matching outcomes blocks all check-ins; inactive or ineligible **reward** on a reward outcome dispatches as failed but check-in still records; unintended overnight window when end time is before start time; period milestone target already passed in ledger will not fire again for that member.

### Member journey

| Page / surface | Owning repo | BFF / RPC |
| --- | --- | --- |
| Activity history (check-in filter labels) | loyalty-user | Wallet/history read path (no dedicated check-in page) |
| Check-in status / action (staff) | loyalty-admin — Front line | `get_user_checkin_status`, `process_checkin` |
| Check-in status / action (member self-service) | — | `get_user_checkin_status`, `process_checkin` (API live; member app route not shipped) |

1. Member opens the check-in surface (when a client is wired); app loads status (campaign summary, today already checked flag, current/longest streak, totals, period count/target, upcoming milestones, next deadline). **Today:** only **loyalty-admin Front line** calls these RPCs; **loyalty-user** exposes check-in wording on activity history filters only.
2. If status shows already checked today, UI typically disables the button (product choice); server still allows another same-day check-in unless a participation limit blocks it.
3. If daily time window is on and now is outside hours, UI shows outside-hours state using returned window bounds.
4. Member taps check-in; app calls process check-in.
5. On success: show streak day, totals, period count if applicable, and each matched grant (points, ticket, reward, earn factor) or explain empty grants when none matched.
6. On failure: show the error string returned (inactive campaign, outside window, eligibility, limit, require condition match with no match, forbidden for admin frontline without permission).

| Error (member-visible) | Typical cause |
| --- | --- |
| Check-in campaign not found or inactive | Off, outside campaign window, or missing |
| Outside check-in window | Outside configured daily hours |
| Tier / Persona / Tag / Birthday month requirement not met | Eligibility filter |
| Personal / Campaign participation limit reached | Cap exhausted |
| Forbidden | Admin frontline check-in without create/update permission |

## System

### Data model

| Artifact | Role |
| --- | --- |
| `checkin` | Campaign header: frequency, condition config, windows, eligibility, require condition match, active flag |
| `checkin_outcomes` | One row per configured outcome and trigger; cascades on campaign delete |
| `checkin_ledger` | Immutable attendance and matched-outcome audit per check-in |
| `transaction_limits` | Participation caps where entity type is check-in and entity id is campaign id |

Indexes on the ledger favour user+campaign+date/time ordering for streak and period aggregation.

### Functions

| Function | Role |
| --- | --- |
| `process_checkin` | Member write path: validate campaign, window, eligibility, limits; compute streak/period; match outcomes; dispatch; insert ledger |
| `get_user_checkin_status` | Member read path: campaign card, progress, milestones preview, today flag, deadlines |
| `fn_compute_checkin_streak` | Shared streak/longest/total/last-date/deadline math from ledger |
| `bff_upsert_checkin` | Admin create/update campaign with full-replace outcomes and limits (merchant from JWT) |
| `bff_get_checkin_details` | Admin load template (`new`) or campaign + children (`edit`) |
| `bff_list_checkins` | Admin list with aggregate stats per campaign |
| `bff_admin_get_checkin_history` | Admin member attendance history |
| `bff_reverse_checkin` | Admin reversal of a ledger row |
| `fn_dispatch_outcome` | Central grant primitive for every matched outcome |

Triggers: deleting a campaign invalidates earn-channel display cache for check-in sources; outcome rows maintain updated-at.

### Flows

**Check-in (sync):** resolve campaign → optional time-of-day gate → load member and tags → eligibility → participation limits → compute streak and period from ledger → evaluate outcome triggers → for each match call dispatcher with source type check-in and per-outcome dedup key → insert ledger with matched outcome payloads → return streak, counts, grants, next deadline.

**Status (sync):** load campaign → run shared streak helper and period tally → build upcoming milestones for UI → return today-checked derived from ledger date.

**Admin save:** validate required fields → upsert header → delete and reinsert all outcomes and check-in limits from payload (no orphan children).

**Outcome dispatch:** points and tickets via wallet chokepoint; reward via direct redemption; earn factor via user earn-factor row; each attempt logs to outcome distribution log.

Display on the Earn page uses earn-channel source availability for check-in channels (see Earn Channel doc).

### External services

No dedicated Render/Inngest service for check-in; grants and wallet updates run inside the database dispatcher path.

### Known gaps

- **Member self-service check-in UI** — `get_user_checkin_status` and `process_checkin` are live and used from **loyalty-admin Front line**; **loyalty-user** has no `src/app` route calling them (only history filter copy and static campaign HTML mockups under `public/campaigns/*-checkin`). Ship a member surface or document the intended embed/campaign client separately.
- **Require condition match** under heavy multi-outcome use may need product refinement (today: any match proceeds; zero matches reject when flag is true).
- **Time-of-day window** applies to all condition types; confirm merchants want hours gating on fixed/rolling count campaigns.
- Residual **per-outcome eligibility** product design tracked as planned in Concept.

## Related

- **Central Outcome Dispatcher** — All check-in grants use `fn_dispatch_outcome`; see `Central_Outcome_Dispatcher.md`.
- **Currency** — Points and tickets post through wallet chokepoints invoked by the dispatcher; see `Currency.md`.
- **Reward** — Reward outcomes trigger direct redemption; see `Reward.md`.
- **Earn Channel** — Check-in appears as an earn source when configured; see `Earn_Channel.md`.
- **Tier / Tag & Persona** — Campaign eligibility mirrors reward-style filters; see `Tier.md`, `Tag_and_Persona.md`.
- **Mission** — Shares dispatcher primitives; missions may reference check-in as completion criteria; see `Mission.md`.
