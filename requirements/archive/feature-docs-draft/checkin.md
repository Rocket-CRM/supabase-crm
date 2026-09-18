# Feature Guide: Check-in

## 1. Overview

Check-in is a daily or weekly attendance mechanic that rewards members for returning consistently. A merchant creates a check-in campaign, defines what members earn at each streak milestone, and members tap a button in the app to record attendance. The system tracks consecutive check-ins as a streak and matches the current streak day to a condition row that determines the reward — points, tickets, a free reward, or an earn-rate multiplier.

The core engagement loop: member checks in → streak increments → condition determines today's reward → member sees progress toward the next milestone. Missing a check-in resets the streak to day 1. This creates a lightweight, habit-forming touchpoint that drives daily app opens without requiring a purchase. Merchants can gate conditions by tier or user type, making check-in rewards progressively more valuable for higher-tier members.

Two frequency modes exist: **daily** (must check in on consecutive calendar days) and **weekly** (must check in within rolling 7-day windows). Both support optional time-of-day windows and campaign date ranges. Four outcome types cover the reward spectrum: direct points, lottery tickets, free reward redemptions, and temporary earn-factor multipliers.

## 2. Key Concepts

**Check-in Campaign** — A merchant-configured attendance program with a name, frequency, and set of reward conditions. A merchant can run multiple campaigns simultaneously. Example: "Daily Bonus" (daily frequency) and "Weekend Special" (weekly frequency).

**Frequency Type** — How often a member must check in to maintain their streak: `daily` (every calendar day) or `weekly` (within every 7-day rolling window).

**Streak** — The count of consecutive check-ins without a gap. Resets to 1 when the member misses the required frequency window. Example: Member checks in 5 consecutive days → streak = 5. Misses day 6 → next check-in resets streak to 1.

**Streak Day** — The current position in the streak, starting at 1. Used to match against condition rows. On each check-in, streak_day increments if continuity holds, or resets to 1 if broken.

**Max Streak Days** — Upper bound on streak counting (default: 365). After reaching this cap, the streak value stops incrementing but check-ins continue recording.

**Condition** — A row defining what a member earns at a specific streak range. Each condition specifies: streak day range (`streak_day_start` to `streak_day_end`), eligibility filters (tier, user type), outcome type, and outcome amount. Example: "Days 1–6: earn 10 points; Day 7 (milestone): earn 50 points."

**Milestone** — A condition flagged as `is_milestone = true`, typically representing a significant streak achievement (e.g., day 7, day 30). Used by the frontend to highlight special rewards in the streak calendar.

**Outcome Entity** — What the member receives: `points` (currency credit), `tickets` (lottery entries), `reward` (free redemption of a specific reward), or `earn_factor` (temporary points multiplier). Each references an `entity_id` where applicable.

**Time Window** — Optional daily hours during which check-in is allowed (e.g., 06:00–22:00). Evaluated in the campaign's configured timezone. Supports day-crossing windows (e.g., 22:00–02:00).

**Campaign Window** — Optional start/end dates (`window_start`, `window_end`) during which the campaign is active. Outside this range, the campaign is treated as not found.

**Require Condition Match** — When `true`, a check-in without a matching condition is rejected entirely (no streak update, no ledger entry). When `false`, the check-in records and the streak advances even without a reward.

## 3. Configuration Reference

### Campaign Settings

| Setting | What it controls | Example | Default |
|---|---|---|---|
| Name | Campaign display name | "Daily Bonus" | Required |
| Description | Campaign description text | "Check in daily for rewards" | None |
| Frequency type | Check-in cadence | `daily` | Required |
| Timezone | Timezone for time window evaluation | `Asia/Bangkok` | `Asia/Bangkok` |
| Enable time window | Restrict check-in to specific hours | `true` | `false` |
| Window start time | Earliest allowed check-in time | `06:00` | — |
| Window end time | Latest allowed check-in time | `22:00` | — |
| Max streak days | Streak counter upper bound | 365 | 365 |
| Campaign start (`window_start`) | Date campaign becomes active | 2025-01-01 | No restriction |
| Campaign end (`window_end`) | Date campaign deactivates | 2025-12-31 | No restriction |
| Require condition match | Block check-in if no condition matches | `true` | `false` |
| Active status | Master on/off for the campaign | `true` | `true` |

### Condition Settings

| Setting | What it controls | Example | Default |
|---|---|---|---|
| Condition name | Label for admin reference | "Day 7 Bonus" | None |
| Streak day start | First streak day this condition applies | 7 | Required |
| Streak day end | Last streak day (null = open-ended) | 7 | None (unbounded) |
| Is milestone | Flag for milestone UI treatment | `true` | `false` |
| Allowed tier IDs | Which tiers earn this reward | [Gold ID, Platinum ID] | Empty = all tiers |
| Allowed user types | Which user types qualify | [member, corporate] | Empty = all types |
| Outcome entity | Reward type: `points`, `tickets`, `reward`, `earn_factor` | `points` | Required |
| Entity ID | ID of the linked entity (ticket type, reward, earn factor) | UUID | null (not needed for points) |
| Outcome amount | Quantity awarded | 50 | null |
| Priority | Tiebreaker when multiple conditions match | 150 | 100 |
| Active status | Enable/disable this condition | `true` | `true` |

## 4. Admin Journey

**Repo:** `Rocket-CRM/loyalty-admin`

**Route map:**

| Page name | Current route | BFF / data source |
|---|---|---|
| Check-in List | _TBD — not yet in FE docs_ | `checkin` table direct query |
| Check-in Settings (create) | _TBD_ | — |
| Check-in Settings (edit) | _TBD_ | — |

> Note: Admin frontend pages for check-in are not yet documented in the loyalty-admin repo. The journey below is inferred from the database schema. Routes will be added when the admin UI is implemented.

### 4a. Create a New Check-in Campaign

1. From **Check-in List**, click **"Add check-in"**
2. **Check-in Settings** opens — empty form
3. Fill campaign settings: name (required), description, frequency type (daily/weekly)
4. Set timezone if different from default
5. Optionally enable time window → set start/end times (supports overnight windows like 22:00–02:00)
6. Optionally set campaign window (start/end dates) to limit when the campaign runs
7. Set max streak days if the campaign should cap at a value other than 365
8. Configure `require_condition_match` — if enabled, members who don't match any condition are blocked from checking in
9. Save the campaign

### 4b. Configure Conditions (Reward Tiers)

1. From campaign edit view, navigate to the conditions section
2. Click **"Add condition"** to define a streak-day reward
3. Set streak day range: start (required) and optional end. Example: start=1, end=6 for "days 1 through 6"
4. Toggle `is_milestone` for special days (day 7, day 30) — controls frontend highlight treatment
5. Set eligibility: select allowed tiers and user types (leave empty for unrestricted)
6. Choose outcome entity: `points`, `tickets`, `reward`, or `earn_factor`
7. For `points`: set outcome amount (e.g., 50 points). Entity ID not needed.
8. For `tickets`: entity_id = ticket type UUID, outcome amount = 1 (always one ticket)
9. For `reward`: entity_id = reward UUID. Triggers a free redemption via `redeem_reward_with_points`
10. For `earn_factor`: entity_id = earn factor UUID. Assigns a 7-day multiplier
11. Set priority (higher wins when multiple conditions match the same streak day and eligibility)
12. Save condition — repeat for each streak bracket

### 4c. Common Admin Mistakes

- Setting `require_condition_match = true` with no conditions → every check-in attempt is rejected
- Creating overlapping streak day ranges with no tier/type differentiation → highest-priority condition wins silently; admin may not realize which fires
- Setting time window end before start without intending an overnight window → actually creates a day-crossing window (22:00 to 06:00), which may be unintended
- Forgetting to set `active_status = true` on conditions → conditions are ignored
- Using `reward` outcome entity with an invalid or inactive reward ID → redemption fails silently at check-in time
- Setting campaign `window_end` in the past → campaign treated as not found

## 5. Member Experience

**Repo:** `Rocket-CRM/loyalty-user`

**Route map:**

| Page / Component | Current route | Data source |
|---|---|---|
| Check-in page / widget | _TBD — not yet in FE docs_ | `get_user_checkin_status()` |
| Check-in result | _TBD_ | `process_checkin()` response |

> Note: Member-facing screens for check-in are not yet documented in the loyalty-user repo. The journey below is inferred from the database functions.

### 5a. View Check-in Status

1. Member opens the check-in page or widget
2. App calls `get_user_checkin_status(user_id, merchant_id, checkin_id)`
3. Response shows: `can_checkin` (boolean), `checked_today`, `in_window`, `current_streak`, `longest_streak`, `total_checkins`, `last_checkin` date, `next_deadline`, and time window if enabled
4. If `checked_today = true`: check-in button is disabled, showing "Already checked in"
5. If `in_window = false`: check-in button disabled, showing "Outside check-in hours" with window start/end times
6. If `can_checkin = true`: check-in button is active

### 5b. Perform Check-in

1. Member taps the check-in button
2. App calls `process_checkin(user_id, merchant_id, checkin_id)`
3. On success: response includes `streak_day`, `total_checkins`, `longest_streak`, reward details (type, amount, entity_id, transaction_id), and `next_checkin` date
4. Member sees streak progress update and reward animation/confirmation
5. If a condition matched: reward is displayed (e.g., "+50 points", "Ticket earned", "Free reward claimed")
6. If no condition matched and `require_condition_match = false`: check-in succeeds with no reward

### 5c. Error States

1. "Check-in campaign not found or inactive" — campaign is off, outside window dates, or deleted
2. "Outside check-in window" — current time is outside the allowed hours (includes start/end times in response)
3. "Already checked in today" — duplicate prevention (one per campaign per calendar day)
4. "No rewards available for your profile" — `require_condition_match = true` and no condition matches the member's streak day, tier, or user type

### 5d. Streak Behavior

1. **Daily frequency**: streak continues if last check-in was exactly yesterday. Any gap resets to day 1.
2. **Weekly frequency**: streak continues if last check-in was within the past 7 days. Gaps longer than 7 days reset to day 1.
3. Streak progress is visible via `current_streak` (active run), `longest_streak` (personal best), and `total_checkins` (lifetime count).
4. `next_deadline` shows when the member must check in by to maintain the streak.

## 6. Perspectives

### 6a. For Customer Success / Support

**Elevator pitch**: "Check-in rewards your members for showing up. They tap a button daily or weekly, build a streak, and earn escalating rewards — points on regular days, bigger bonuses on milestone days. It drives daily app opens without requiring a purchase."

**Top 5 support questions:**

| Question | Answer |
|---|---|
| "Member can't check in" | Check: is the campaign active? Is it within campaign window dates? Is the time window enabled and currently open? Has the member already checked in today? |
| "Member's streak reset unexpectedly" | Daily: member missed a calendar day. Weekly: gap exceeded 7 days. Streaks reset automatically — there is no manual override. |
| "Member checked in but got no reward" | If `require_condition_match = false`, check-ins succeed without a reward when no condition matches. Check if conditions cover the member's current streak day and tier. |
| "Member says reward amount is wrong" | Multiple conditions may overlap. The system picks the highest-priority match. Check which condition fired by looking at the ledger's `condition_id`. |
| "Check-in button shows wrong time window" | Time is evaluated in the campaign's configured timezone, not the member's device timezone. Verify the campaign timezone setting. |

### 6b. For Marketing

**Value proposition**: Check-in is the simplest daily engagement hook in the platform. Members build a habit of opening the app each day, and merchants reward consistency with escalating benefits — making each consecutive day more valuable than the last.

**Use-case stories:**

1. **Coffee chain** — "Daily Check-in" campaign: days 1–6 earn 5 points, day 7 milestone earns 50 points + a free coffee reward. Average member opens the app 5.2 days/week to maintain their streak.

2. **Department store** — Tier-differentiated check-in: Gold members earn 10 points/day, Platinum members earn 20 points/day on the same campaign. Day-30 milestone grants a lottery ticket for a seasonal prize draw.

3. **Fitness brand** — Weekly check-in for casual engagement: one check-in per week maintains the streak. Day-4 milestone (4 weeks) grants a 2x earn factor for 7 days, incentivizing purchases during the multiplier window.

4. **Limited-time event** — Campaign with `window_start/end` set to a festival week. Time window 10:00–14:00 for lunch-hour engagement. Milestones at day 3 and day 7 drive repeat visits during the event period.

**Metrics merchants care about**: Daily active users (check-in as proxy for app opens), streak distribution (how many members reach day 7, 14, 30), check-in-to-purchase conversion rate, streak recovery rate (how often broken streaks restart vs. members dropping off).

### 6c. For Testers

**Config → expected behavior:**

| Config | Expected behavior |
|---|---|
| `frequency_type = daily`, check in 2 consecutive days | `streak_day` = 2 on second check-in |
| `frequency_type = daily`, skip a day, check in | `streak_day` resets to 1 |
| `frequency_type = weekly`, check in within 7 days | Streak continues (increments) |
| `frequency_type = weekly`, gap > 7 days | Streak resets to 1 |
| `enable_time_window = true`, outside window | "Outside check-in window" error with start/end times |
| Day-crossing window (22:00–02:00), check in at 23:00 | Check-in succeeds (within window) |
| Day-crossing window (22:00–02:00), check in at 10:00 | "Outside check-in window" error |
| Same member, same campaign, same day, second attempt | "Already checked in today" error |
| `require_condition_match = true`, no matching condition | Check-in rejected entirely |
| `require_condition_match = false`, no matching condition | Check-in succeeds, streak advances, no reward |
| Two conditions match same streak day, different priorities | Higher priority wins |
| Campaign `active_status = false` | "Campaign not found or inactive" error |
| Campaign outside `window_start/window_end` dates | "Campaign not found or inactive" error |
| Streak reaches `max_streak_days` | Streak stops incrementing but check-ins still record |
| Outcome `points`: amount = 50 | 50 points credited to wallet, transaction description includes campaign name |
| Outcome `tickets`: entity_id = ticket_type_id | 1 ticket added to wallet for that ticket type |
| Outcome `reward`: entity_id = reward_id | Free redemption triggered via `redeem_reward_with_points` |
| Outcome `earn_factor`: entity_id = factor_id | Earn factor assigned with 7-day expiry |

**Business rules as assertions:**

- ASSERT: One check-in per user per campaign per calendar day (unique constraint on `user_id + merchant_id + checkin_id + checkin_date`)
- ASSERT: Streak resets to 1 when daily gap > 1 day or weekly gap > 7 days
- ASSERT: `longest_streak` = MAX of all `current_streak` values ever recorded
- ASSERT: `total_checkins` increments by 1 on every successful check-in
- ASSERT: Condition matching evaluates `streak_day_start <= streak_day <= streak_day_end` AND tier AND user_type, ordered by priority DESC then outcome_amount DESC
- ASSERT: `next_deadline` for daily = end of tomorrow; for weekly = now + 7 days
- ASSERT: Points outcome calls `post_wallet_transaction` with source_type = `campaign`
- ASSERT: Earn factor outcome sets `window_end` = now + 7 days

**Duplicate prevention:** Enforced at both the application level (check before insert) and database level (unique index on `checkin_ledger(user_id, merchant_id, checkin_id, checkin_date)`).

## 7. Business Rules

**Rule:** One check-in per member per campaign per calendar day. Enforced by a unique constraint — even if called concurrently, only one succeeds.
**Example:** Member taps check-in twice rapidly → first call succeeds, second returns "Already checked in today."

**Rule:** Streak continuity depends on frequency type. Daily: last check-in must be exactly yesterday. Weekly: last check-in must be within the past 7 days. Any larger gap resets the streak to 1.
**Example:** Daily campaign, member checks in Mon–Fri, misses Sat → Sunday check-in starts streak at 1, not 6.

**Rule:** Condition matching uses streak day range plus eligibility filters. The system finds conditions where `streak_day_start <= current_streak_day <= streak_day_end` AND the member's tier and user type pass the filters. Highest priority wins; ties broken by highest outcome amount.
**Example:** Day 7, two conditions: "Day 7 milestone (priority 200, 50 pts)" and "Days 1–30 base (priority 100, 10 pts)" → milestone wins.

**Rule:** When `require_condition_match = true` and no condition matches, the entire check-in is rejected — no ledger entry, no streak update.
**Example:** New campaign with no conditions yet + require_condition_match enabled → all check-in attempts fail.

**Rule:** Time window evaluation uses the campaign's configured timezone, not UTC or the member's device timezone. Day-crossing windows (start > end) are handled correctly.
**Example:** Campaign timezone = Asia/Bangkok, window = 22:00–02:00. Member in UTC checks in at 17:00 UTC (00:00 Bangkok) → succeeds.

**Rule:** Empty eligibility arrays on conditions mean unrestricted. `allowed_tier_ids = NULL` matches all tiers.
**Example:** Condition with no tier filter → Bronze through Diamond all receive the reward.

**Rule:** Outcome type `reward` triggers a full reward redemption via `redeem_reward_with_points`. If the reward is out of stock or the member is ineligible for the reward, the redemption portion fails but the check-in and streak still advance.
**Example:** Day 7 condition grants a free coffee reward. Coffee reward is out of stock → check-in records, streak updates, but no reward received.

**Rule:** Outcome type `earn_factor` grants a temporary multiplier with a fixed 7-day expiry from check-in time. If the member already has the same factor, the expiry is extended (upsert).
**Example:** Member earns 2x factor on day 14, already has it from day 7 → expiry resets to 7 days from now.

## 8. Related Features

| Feature | Connection to Check-in |
|---|---|
| Currency | Points and tickets are awarded through wallet transactions (`post_wallet_transaction`). See Currency guide. |
| Tier | Conditions can be tier-gated via `allowed_tier_ids`. Higher tiers can earn better check-in rewards. See Tier guide. |
| Rewards | The `reward` outcome type triggers a free redemption of a specific reward. See Rewards guide. |
| Activity/Earning | The `earn_factor` outcome type assigns a temporary points multiplier from the earn system. See Activity guide. |
| Mission | Missions may include check-in as a completion criterion (e.g., "Check in 7 days"). See Mission guide. |
| Tag & Persona | Conditions currently filter by tier and user type; persona/tag filtering could extend this. See Tag & Persona guide. |
