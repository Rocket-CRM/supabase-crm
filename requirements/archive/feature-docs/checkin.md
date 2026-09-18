# Feature Guide: Check-in

## 1. Overview

Check-in is an attendance mechanic that rewards members for returning consistently. A merchant creates a check-in campaign, defines what members earn and when, and members tap a button in the app to record attendance. The system supports three evaluation shapes — **consecutive streaks** (the classic daily/weekly habit loop), **fixed-period counts** ("check in 10 times during March"), and **rolling-period counts** ("check in 5 times in any 7-day window").

Every check-in can dispatch **multiple outcomes at once** (e.g. 50 points AND a lottery ticket AND a milestone reward) — outcomes are no longer capped at one per check-in. All outcome dispatch flows through the platform's central outcome dispatcher (`fn_dispatch_outcome`), so points, tickets, free rewards, and earn factors are granted using exactly the same primitives as missions, AMP workflows, and referral.

The core engagement loop is unchanged from prior versions: member checks in → evaluation advances → matched outcomes dispatch → member sees progress toward the next milestone. What's new is the breadth of condition shapes a campaign can express, multi-outcome dispatch, and ledger-derived state (no separate streaks table — all streak/period math is computed from the immutable ledger).

## 2. Key Concepts

**Check-in Campaign** — A merchant-configured attendance program with a name, frequency, evaluation shape, eligibility filters, and a set of outcomes. A merchant can run multiple campaigns simultaneously. Example: "Daily Bonus" (daily, consecutive) and "March Sprint" (fixed-period, 10 check-ins in March).

**Frequency Type** — The cadence the member must maintain: `daily` (every calendar day) or `weekly` (within every 7-day rolling window). Affects streak continuity only.

**Condition Type** — The evaluation shape for the campaign. Stored as text on the `checkin` row; validated by `process_checkin`. Three values:
- `consecutive` — default; classic streak (daily or weekly continuity).
- `fixed_period_count` — "X check-ins between `period_start` and `period_end`".
- `rolling_period_count` — "X check-ins within any trailing `rolling_window_days` window".

**Streak** — For `consecutive` campaigns: the count of check-ins without a gap. Daily: gap > 1 day resets. Weekly: gap > 7 days resets. Computed from the ledger at read time — there is no `checkin_streaks` table anymore.

**Period Count** — For `fixed_period_count` / `rolling_period_count`: the running tally of check-ins within the configured period/window. Computed from the ledger at evaluation time.

**Outcome** — One configured reward row on `checkin_outcomes`. Each outcome has a `trigger_type` (when it fires), an `outcome_type` (what to give), and the standard dispatch payload.

**Trigger Type** — When a specific outcome fires within the campaign's evaluation:
- `every_checkin` — fires on every valid check-in (e.g. "10 points every day").
- `streak_milestone` — fires when streak is in `[streak_day_start, streak_day_end]` (e.g. "100 points on day 7").
- `period_milestone` — fires when the period count equals `period_count_target` (e.g. "reward on the 5th check-in this month"). **Fire-once per user** — re-firing is blocked by checking the ledger for prior matches.

**Outcome Type** — What the member receives. Reuses the platform's `outcome_type_enum`: `points` (wallet credit), `tickets` (lottery entries, requires ticket_type_id), `reward` (free redemption via `redeem_reward_with_points` direct mode), `earn_factor` (temporary points multiplier, default 30-day window).

**Eligibility** — Campaign-level filters mirroring `reward_master`: `allowed_tier`, `allowed_persona`, `allowed_tags`, `allowed_birthmonth`. NULL/empty = unrestricted.

**Participation Limit** — Campaign-wide caps stored in the central `transaction_limits` table (`entity_type='checkin'`). Scope: `user` (per-member cap) or `total` (campaign-wide cap). Time window: day/week/month/year/all_time.

**Time Window** — Optional daily hours during which check-in is allowed (e.g. 06:00–22:00). Evaluated in the campaign's configured timezone. Supports day-crossing windows (e.g. 22:00–02:00).

**Campaign Window** — Optional `window_start`/`window_end` (timestamptz) during which the campaign is active. Outside this range the campaign is treated as not found.

**Ledger** — The `checkin_ledger` table is the single source of truth. Every check-in is one immutable row with: user, campaign, date, streak_day, and `matched_outcomes` (jsonb array of every outcome dispatched). Streaks, longest run, totals, and next deadlines are all computed from the ledger — no derived cache table.

## 3. Configuration Reference

### Campaign Settings (`checkin` table)

| Setting | What it controls | Example | Default |
|---|---|---|---|
| Name | Campaign display name | "Daily Bonus" | Required |
| Description | Campaign description text | "Check in daily for rewards" | None |
| Frequency type | Check-in cadence | `daily` | Required |
| Timezone | Timezone for time-window evaluation | `Asia/Bangkok` | `Asia/Bangkok` |
| Enable time window | Restrict check-in to specific hours | `true` | `false` |
| Window start time / end time | Allowed daily hours (supports overnight) | 22:00 / 02:00 | — |
| Max streak days | Streak counter upper bound | 365 | 365 |
| Campaign window start/end | When the campaign is active | 2026-03-01 / 2026-03-31 | No restriction |
| Active status | Master on/off | `true` | `true` |

### Condition Type (`checkin.condition_type`, text)

| Value | Period fields used | Use case |
|---|---|---|
| `consecutive` | none | "Check in 7 days in a row" |
| `fixed_period_count` | `period_start`, `period_end`, `period_target_count` | "Check in 10 times during March" |
| `rolling_period_count` | `rolling_window_days`, `period_target_count` | "Check in 5 times in any 7-day window" |

### Eligibility (`checkin`)

| Filter | Type | Empty meaning |
|---|---|---|
| `allowed_tier` | uuid[] | all tiers |
| `allowed_persona` | uuid[] | all personas |
| `allowed_tags` | uuid[] | all tags (member must have ANY of them) |
| `allowed_birthmonth` | int[] (1–12) | all months |

### Outcomes (`checkin_outcomes`)

| Setting | What it controls | Example | Default |
|---|---|---|---|
| Outcome type | What to grant: `points`, `tickets`, `reward`, `earn_factor` | `points` | Required |
| Entity ID | Reward/ticket_type/earn_factor UUID | UUID | NULL (points need none) |
| Amount | Quantity to grant | 50 | Required |
| Trigger type | When it fires: `every_checkin`, `streak_milestone`, `period_milestone` | `every_checkin` | `every_checkin` |
| Streak day start / end | Range for `streak_milestone` | 7 / 7 | NULL (unbounded) |
| Period count target | Target for `period_milestone` | 5 | NULL |
| Priority | Tiebreaker when multiple match | 100 | 100 |
| Is milestone | UI flag for special milestone styling | `true` | `false` |
| Active status | Enable/disable this outcome | `true` | `true` |

### Participation Limits (`transaction_limits`, `entity_type='checkin'`)

| Setting | What it controls | Example |
|---|---|---|
| Scope | `user` (per-member) or `total` (campaign-wide) | `user` |
| Count | Maximum check-ins allowed in the window | 30 |
| Time unit | `day`/`week`/`month`/`year`/`all_time` | `month` |
| Window start / end | Optional absolute override | 2026-03-01 / 2026-03-31 |

## 4. Admin Journey

**Repo:** `Rocket-CRM/loyalty-admin`

**Route map:**

| Page name | Current route | BFF / data source |
|---|---|---|
| Check-in List | _TBD — not yet in FE docs_ | `bff_list_checkins()` |
| Check-in Settings (create/edit) | _TBD_ | `bff_get_checkin_details(p_mode, p_checkin_id)` (load) + `bff_upsert_checkin(p_config)` (save) |
| Check-in Outcomes | (embedded in Settings) | `checkin_outcomes` (managed via upsert's `outcomes[]` array) |

### 4a. Create a New Check-in Campaign

1. From **Check-in List**, click **"Add check-in"**
2. Fill campaign settings: name, description, frequency type
3. Pick **condition type**: `consecutive` (default), `fixed_period_count`, or `rolling_period_count`
4. If `fixed_period_count`: set `period_start`, `period_end`, `period_target_count`
5. If `rolling_period_count`: set `rolling_window_days` and `period_target_count`
6. Set timezone and (optional) time-of-day window
7. Set campaign window (optional start/end dates)
8. Configure eligibility filters (tier / persona / tags / birth month) — leave empty for unrestricted
9. Configure participation limits (per-user or campaign-wide cap, time window)
10. Save

### 4b. Configure Outcomes

1. From campaign edit view, open the **Outcomes** section
2. Click **"Add outcome"**
3. Choose trigger type:
   - `every_checkin` — fires on every valid check-in (e.g. base daily points)
   - `streak_milestone` — fires when streak lands in a range (e.g. day 7 bonus)
   - `period_milestone` — fires when period count hits target (e.g. "5th check-in of the month")
4. Choose outcome type: `points`, `tickets`, `reward`, or `earn_factor`
5. Set amount and (if applicable) entity ID
6. For `streak_milestone`: set `streak_day_start`/`streak_day_end`
7. For `period_milestone`: set `period_count_target`
8. Set priority (tiebreaker when multiple match)
9. Toggle `is_milestone` if this should get special milestone UI treatment
10. Save — repeat to stack multiple outcomes on the same check-in

### 4c. Common Admin Mistakes

- `require_condition_match = true` with no matching outcomes → check-in rejected (no reward, no streak advance)
- `period_milestone` with `period_count_target` already exceeded by the user → outcome never fires for that user
- Two `every_checkin` outcomes granting the same outcome type (e.g. two `points` outcomes) → both fire and both succeed (per-outcome dedup key prevents wallet collision)
- Setting time window end before start unintentionally → creates a day-crossing window (22:00–06:00)
- Forgetting `active_status = true` on outcomes → silently ignored
- `reward` outcome with an inactive reward ID → dispatch fails, recorded as `success:false` in `outcome_distribution_log`, but check-in still records and streak advances

## 5. Member Experience

**Repo:** `Rocket-CRM/loyalty-user`

**Route map:**

| Page / Component | Current route | Data source |
|---|---|---|
| Check-in page / widget | _TBD — not yet in FE docs_ | `get_user_checkin_status()` |
| Check-in result | _TBD_ | `process_checkin()` response |

### 5a. View Check-in Status

1. Member opens the check-in page or widget
2. App calls `get_user_checkin_status(user_id, merchant_id, checkin_id)`
3. Response includes: campaign config, `today_checked`, `current_streak`, `longest_streak`, `total_checkins`, `last_checkin_date`, `next_deadline`, `period_count`, `period_target`, and `upcoming_milestones` (for FE progress display)
4. Disable check-in button if `today_checked = true`
5. If `enable_time_window` is on and current time is outside the window → disable with "Outside check-in hours" + window times

### 5b. Perform Check-in

1. Member taps the check-in button
2. App calls `process_checkin(user_id, merchant_id, checkin_id)`
3. On success: response includes `streak_day`, `total_checkins`, `longest_streak`, `period_count`, `matched_outcomes` (array of `{outcome_id, outcome_type, entity_id, amount, success, transaction_id, distribution_id}`), and `next_deadline`
4. UI renders each matched outcome (e.g. "+50 points", "Ticket earned", "Free reward claimed")
5. If `matched_outcomes` is empty: check-in recorded, streak advanced, no reward shown

### 5c. Error States

| Error message | Cause |
|---|---|
| "Check-in campaign not found or inactive" | Campaign off, outside campaign window, or deleted |
| "Outside check-in window" | Current time outside configured hours (response includes start/end times) |
| "Already checked in today" | Duplicate check-in for today |
| "Tier requirement not met" | Member's tier not in `allowed_tier` |
| "Persona requirement not met" | Member's persona not in `allowed_persona` |
| "Tag requirement not met" | Member lacks any of the required tags |
| "Birthday month requirement not met" | Current month not in `allowed_birthmonth` |
| "Personal participation limit reached" | Per-user cap hit (response includes limit, used, remaining) |
| "Campaign participation limit reached" | Campaign-wide cap hit |

### 5d. Evaluation Behavior by Condition Type

| Condition type | What advances | What fires milestones |
|---|---|---|
| `consecutive` | streak (daily: +1 if last was yesterday; weekly: +1 if last within 7 days) | `streak_milestone` when streak in range |
| `fixed_period_count` | period_count (check-ins in `[period_start, period_end]`) | `period_milestone` when count == target |
| `rolling_period_count` | period_count (check-ins in trailing `rolling_window_days`) | `period_milestone` when count == target |

## 6. Perspectives

### 6a. For Customer Success / Support

**Elevator pitch**: "Check-in rewards members for showing up. They tap a button, build a streak or hit a count target, and earn escalating rewards — points on regular days, bigger bonuses on milestones. Three modes: classic streak, fixed-period count ('10 check-ins in March'), and rolling count ('5 in any 7 days')."

**Top support questions:**

| Question | Answer |
|---|---|
| "Member can't check in" | Check: campaign active? Within campaign window? Within time-of-day window? Already checked in today? Tier/persona/tags eligible? Participation limit hit? |
| "Streak reset unexpectedly" | Daily: missed a calendar day. Weekly: gap exceeded 7 days. Streaks compute from the ledger and reset automatically — no manual override. |
| "Checked in but got no reward" | Either no outcomes matched (e.g. `period_milestone` target not yet reached), or an outcome failed to dispatch (check `outcome_distribution_log` for `success:false`). |
| "Says they earned reward but wallet didn't update" | Look up the `transaction_id` in `matched_outcomes` → cross-reference `wallet_ledger` / `reward_redemptions_ledger` / `earn_factor_user`. If `success:false`, the dispatcher logged the error. |
| "Wants to repeat a milestone reward" | `period_milestone` and `streak_milestone` may be one-shot per user. Check the outcome's range/target and the ledger for prior matches. |

### 6b. For Marketing

**Value proposition**: Three engagement shapes cover the full loyalty spectrum — daily habit loops (consecutive), event-driven sprints (fixed-period count), and always-on rolling targets (rolling-period count). Multi-outcome dispatch lets a single check-in deliver layered value (points + ticket + bonus reward).

**Use-case stories:**

1. **Coffee chain (consecutive)** — "Daily Check-in": days 1–6 grant 5 points each; day 7 milestone grants 50 points + a free coffee. Drives 5+ app opens/week.
2. **Department store (fixed-period count)** — "March Sprint": members check in 10 times during March to unlock a 100-point bonus on the 10th check-in. Pushes traffic during a specific promotional window.
3. **Fitness brand (rolling-period count)** — "Active Member": members check in 5 times in any rolling 7-day window to maintain a 2x earn factor. Encourages consistent engagement without rigid daily pressure.
4. **Tier-differentiated (any type)** — Same campaign with `allowed_tier = [Gold, Platinum]` on premium outcomes. Gold members get the standard 10 points; Platinum gets 20 points + ticket on the same check-in (two `every_checkin` outcomes with different eligibility at outcome row level when FE supports it; today eligibility is campaign-level).

**Metrics**: daily active users, streak distribution, milestone attainment rate, multi-outcome dispatch success rate (per `outcome_distribution_log`), check-in-to-purchase conversion.

### 6c. For Testers

**Config → expected behavior:**

| Config | Expected behavior |
|---|---|
| `consecutive` daily, 2 consecutive days | `streak_day = 2` on second check-in |
| `consecutive` daily, skip a day | `streak_day` resets to 1 |
| `consecutive` weekly, check in within 7 days | streak continues |
| `consecutive` weekly, gap > 7 days | streak resets to 1 |
| `fixed_period_count`, check-in #5 with target = 5 | `period_count = 5`, `period_milestone` fires |
| `fixed_period_count`, check-in #6 with target = 5 | `period_count = 6`, milestone does NOT re-fire (fire-once) |
| `rolling_period_count`, 7-day window, 5 check-ins spread over 8 days | `period_count` reflects trailing-7-day count |
| Two `every_checkin` points outcomes (50 + 10) | Both fire, both succeed, wallet gets 60 |
| `period_milestone` target already exceeded before first check-in | Outcome never fires for that user |
| `enable_time_window`, outside window | "Outside check-in window" error |
| Day-crossing window (22:00–02:00), check in at 23:00 | Succeeds |
| Day-crossing window, check in at 10:00 | "Outside check-in window" error |
| Duplicate same-day check-in | "Already checked in today" |
| `allowed_tier` mismatch | "Tier requirement not met" |
| Participation limit reached | Limit error with `used` / `remaining` counts |

**Business rules as assertions:**

- ASSERT: Repeat same-day check-ins are allowed (no hardcoded per-day dedup); cap via `transaction_limits` (scope=user, count=1, time_unit=day) to restore one-per-day
- ASSERT: A repeat same-day check-in inserts a ledger row but never advances the streak or re-fires a `streak_milestone` on the same date
- ASSERT: Streak continuity — daily: last check-in = yesterday; weekly: last within 7 days
- ASSERT: `period_milestone` fires at most once per user (guarded by `matched_outcomes` lookup on ledger)
- ASSERT: Every dispatched outcome produces one `outcome_distribution_log` row regardless of success
- ASSERT: `next_deadline` is NULL when `enable_time_window = false`; when true, daily = next day at `window_end_time` in campaign timezone, weekly = last check-in + 7 days at `window_end_time`
- ASSERT: Per-outcome dedup key `'checkin:<checkin_id>:<outcome_id>:<user_id>'` prevents wallet collision when multiple currency outcomes share a check-in
- ASSERT: `outcome_type = 'earn_factor'` uses dispatcher default window of 30 days (configurable via `metadata.window_days`)

## 7. Business Rules

**Rule:** Repeat check-ins on the same day are allowed by default — each inserts its own ledger row, fires `every_checkin` outcomes again, but never advances the streak or re-fires a same-day `streak_milestone`. To restore one-per-day, configure a participation limit (scope=user, count=1, time_unit=day).
**Example:** Member checks in twice in one day → two ledger rows, `every_checkin` points granted twice, streak stays at the same value.

**Rule:** Streak continuity depends on frequency type. Daily: last check-in must be exactly yesterday. Weekly: last check-in must be within the past 7 days. Any larger gap resets streak to 1.
**Example:** Daily campaign, member checks in Mon–Fri, misses Sat → Sunday check-in starts streak at 1.

**Rule:** All streak/period math is computed from the ledger at evaluation time — no derived cache. This guarantees the ledger is the single source of truth.
**Example:** If a ledger row is corrected (admin backfill), the next status read reflects the corrected streak without any cache invalidation.

**Rule:** Outcome matching by `trigger_type`:
- `every_checkin` always matches
- `streak_milestone` matches when `streak_day_start <= new_streak <= streak_day_end`
- `period_milestone` matches when `period_count == period_count_target` AND no prior ledger row for the same user+outcome exists (fire-once)
**Example:** Day-7 streak with a `streak_milestone` (range 7–7) and a `period_milestone` (target 7) configured together → both fire on the same check-in if both conditions are met.

**Rule:** Multiple outcomes can fire on one check-in. Each is dispatched independently through `fn_dispatch_outcome` with a per-outcome dedup key. A failure in one outcome does not block others.
**Example:** Day-7 check-in matches `[points every_checkin, reward streak_milestone, ticket streak_milestone]` → all three dispatched. If reward dispatch fails (out of stock), points and ticket still succeed; only the reward's ledger entry has `success:false`.

**Rule:** `period_milestone` is fire-once per user. Re-firing is blocked by checking `matched_outcomes @> [{outcome_id}]` on prior ledger rows.
**Example:** User has 5 check-ins in March. Target was 5, fired on the 5th. On check-in #6, `period_count = 6` ≠ target `5` so it wouldn't match anyway. But if the target were reconfigured to 6 later, the user's existing ledger still wouldn't re-fire because the outcome_id is already in `matched_outcomes`.

**Rule:** Time-window evaluation uses the campaign's configured timezone, not UTC or member device time. Day-crossing windows (start > end) are handled.
**Example:** Campaign timezone `Asia/Bangkok`, window 22:00–02:00. Member in UTC checks in at 17:00 UTC (00:00 Bangkok) → succeeds.

**Rule:** Empty eligibility arrays = unrestricted. `allowed_tier = NULL` matches all tiers.
**Example:** Campaign with no eligibility filters → all members can check in.

**Rule:** Participation limits live in the central `transaction_limits` table with `entity_type='checkin'`. Scope `user` = per-member cap; `total` = campaign-wide cap.
**Example:** `scope=user, count=30, time_unit=month` → each member limited to 30 check-ins per month.

**Rule:** Outcome dispatch always goes through `fn_dispatch_outcome` (central dispatcher). Reward uses `p_mode='direct'` (zero points deducted). Earn factor uses 30-day default window.
**Example:** Reward outcome on day 7 grants a free coffee without burning any points.

## 8. Related Features

| Feature | Connection to Check-in |
|---|---|
| Central Outcome Dispatcher | All check-in outcomes flow through `fn_dispatch_outcome`. See `Central_Outcome_Dispatcher.md`. |
| Currency | Points and tickets are awarded via `chokepoint_post_wallet_transaction` (called by the dispatcher). See Currency guide. |
| Tier | Campaigns can be tier-gated via `allowed_tier`. |
| Rewards | The `reward` outcome type triggers a free redemption via `redeem_reward_with_points(p_mode='direct')`. |
| Earn Factor | The `earn_factor` outcome type assigns a temporary multiplier via `earn_factor_user` insert. |
| Mission | Missions and check-in share the same dispatcher; missions may also drive check-in as a completion criterion. |
| Tag & Persona | Campaigns can filter by `allowed_tags` and `allowed_persona`. |

---

## 9. Backend Architecture & FE Contract

> This section is the engineering reference. Use it to implement admin BFFs and member-facing UI.

### 9.1 Schema

#### `checkin` (campaign header)

```text
id                      uuid PK
merchant_id             uuid NOT NULL            -- RLS key
name                    text NOT NULL
description             text
frequency_type          checkin_frequency NOT NULL   -- enum: daily | weekly
timezone                text DEFAULT 'Asia/Bangkok'
enable_time_window      boolean DEFAULT false
window_start_time       time
window_end_time         time
max_streak_days         int DEFAULT 365
window_start            timestamptz             -- campaign active range start
window_end              timestamptz             -- campaign active range end
require_condition_match boolean DEFAULT false
active_status           boolean DEFAULT true

-- Eligibility (mirrors reward_master)
allowed_tier            uuid[]
allowed_persona         uuid[]
allowed_tags            uuid[]
allowed_birthmonth      int[]                   -- month numbers 1-12

-- Condition config
condition_type          text NOT NULL DEFAULT 'consecutive'   -- consecutive | fixed_period_count | rolling_period_count
period_start            timestamptz             -- for fixed_period_count
period_end              timestamptz             -- for fixed_period_count
rolling_window_days     int                     -- for rolling_period_count
period_target_count     int                     -- the "X" in count-based

created_at, updated_at  timestamptz
```

#### `checkin_outcomes` (one row per configured outcome)

```text
id                      uuid PK
merchant_id             uuid NOT NULL            -- RLS key
checkin_id              uuid NOT NULL FK → checkin (ON DELETE CASCADE)
outcome_type            outcome_type_enum NOT NULL   -- points | tickets | reward | earn_factor
entity_id               uuid                     -- reward_id | ticket_type_id | earn_factor_id | NULL for points
amount                  numeric
trigger_type            text NOT NULL DEFAULT 'every_checkin'   -- every_checkin | streak_milestone | period_milestone
streak_day_start        int                      -- for streak_milestone
streak_day_end          int                      -- for streak_milestone (NULL = unbounded)
period_count_target     int                      -- for period_milestone
priority                int DEFAULT 100          -- tiebreaker
is_milestone            boolean DEFAULT false    -- FE UI flag
active_status           boolean DEFAULT true
created_at, updated_at  timestamptz
```

#### `checkin_ledger` (immutable source of truth)

```text
id                      uuid PK
user_id                 uuid NOT NULL
merchant_id             uuid NOT NULL            -- RLS key
checkin_id              uuid NOT NULL
checkin_date            date NOT NULL
checkin_timestamp       timestamptz NOT NULL DEFAULT now()
streak_day              int NOT NULL
matched_outcomes        jsonb DEFAULT '[]'       -- array of {outcome_id, outcome_type, entity_id, amount, success, transaction_id, distribution_id}
```

Indexes: `(user_id, checkin_id, checkin_date DESC)`, `(user_id, checkin_id, checkin_timestamp DESC)` for fast streak/period computation.

#### Participation limits

Use the central `transaction_limits` table. To add a participation cap, insert:

```sql
INSERT INTO transaction_limits
  (merchant_id, entity_type, entity_id, scope, count, time_unit, time_value, active_status)
VALUES
  (:merchant_id, 'checkin', :checkin_id, 'user', 30, 'month', 1, true);
```

`scope` ∈ `{user, total}`. `time_unit` ∈ `{day, week, month, year, all_time}`.

### 9.2 Functions

#### `process_checkin(p_user_id uuid, p_merchant_id uuid, p_checkin_id uuid) → jsonb`

**Caller:** member-app check-in button. SECURITY DEFINER.

**Flow:**
1. Validate campaign (active, within window_start/end)
2. Validate time-of-day window (if enabled) — supports day-crossing
3. Dedup check (one per user per day per campaign)
4. Eligibility: tier / persona / tags / birth month
5. Participation limits (scope=user and scope=total)
6. Compute streak from ledger via `fn_compute_checkin_streak`
7. Compute new streak value (continuity check)
8. Compute period count (for fixed/rolling kinds)
9. Match outcomes by trigger_type
10. Loop matched outcomes → `fn_dispatch_outcome` per outcome (with per-outcome dedup key)
11. Insert one `checkin_ledger` row
12. Return result

**Return shape:**

```json
{
  "success": true,
  "streak_day": 7,
  "total_checkins": 7,
  "longest_streak": 7,
  "period_count": null,                    // null for consecutive; int for count-based
  "matched_outcomes": [
    {
      "outcome_id": "uuid",
      "outcome_type": "points",            // points | tickets | reward | earn_factor
      "entity_id": null,                   // uuid or null
      "amount": 50,
      "success": true,
      "transaction_id": "uuid",            // wallet_ledger_id | redemption_id
      "distribution_id": "uuid"            // outcome_distribution_log.id
    }
  ],
  "next_deadline": null                    // null unless enable_time_window; else next window_end in campaign tz
}
```

**Error returns (all `{success:false, error:...}`):**

| Error | Additional fields |
|---|---|
| `Check-in campaign not found or inactive` | — |
| `Outside check-in window` | `window_start`, `window_end` |
| `User not found` | — |
| `Tier requirement not met` | — |
| `Persona requirement not met` | — |
| `Tag requirement not met` | — |
| `Birthday month requirement not met` | — |
| `Personal participation limit reached` | `limit_scope`, `limit_count`, `used`, `remaining` |
| `Campaign participation limit reached` | `limit_scope`, `limit_count`, `used`, `remaining` |

#### `get_user_checkin_status(p_user_id uuid, p_merchant_id uuid, p_checkin_id uuid) → jsonb`

**Caller:** member-app status render. SECURITY DEFINER.

**Return shape:**

```json
{
  "success": true,
  "campaign": {
    "id": "uuid",
    "name": "Daily Bonus",
    "frequency_type": "daily",
    "condition_type": "consecutive",
    "enable_time_window": false,
    "window_start_time": null,
    "window_end_time": null,
    "active_status": true
  },
  "today_checked": true,
  "current_streak": 7,
  "longest_streak": 12,
  "total_checkins": 45,
  "last_checkin_date": "2026-06-28",
  "next_deadline": null,                   // null unless enable_time_window; else next window_end in campaign tz
  "period_count": null,                    // null for consecutive; int for count-based
  "period_target": null,                   // from checkin.period_target_count
  "upcoming_milestones": [                 // for FE progress display
    {
      "outcome_id": "uuid",
      "outcome_type": "reward",
      "trigger_type": "streak_milestone",
      "streak_day_start": 14,
      "streak_day_end": 14,
      "period_count_target": null,
      "current_streak": 7,
      "current_period_count": null
    }
  ]
}
```

#### `fn_compute_checkin_streak(p_user_id uuid, p_checkin_id uuid) → TABLE`

Internal helper. Returns `(current_streak int, longest_streak int, total_checkins int, last_checkin_date date, next_deadline timestamptz)`. Called by both `process_checkin` and `get_user_checkin_status` so streak math has one definition.

#### `bff_upsert_checkin(p_config jsonb) → jsonb` (admin)

**Caller:** loyalty-admin Check-in config form. SECURITY DEFINER. Merchant resolved from JWT via `get_current_merchant_id()` — client-supplied merchant_id is never trusted.

**Behavior:** single-RPC upsert of campaign header + full-replace of children. Validation soft-fails (returns `{success:false, error}` rather than throwing) when `name`, `frequency_type` (daily|weekly), or `condition_type` (consecutive|fixed_period_count|rolling_period_count) is missing or invalid. Children (outcomes, limits) are DELETE-all-then-INSERT on every call — rows missing from the payload are deleted, no orphan rows remain.

**Input shape:** the full envelope documented in §3 + §9.1 (campaign settings, eligibility, condition config, `outcomes[]`, `limits[]`). `id` null = create; present = update (matched on `id + merchant_id`; mismatch returns `{success:false, error:"Check-in campaign not found or access denied"}`).

**Limits caveat:** `transaction_limits` has `scope`, `count`, `time_unit`, `window_start`, `window_end`, `active_status` — there is **no `time_value` column**. A limit is expressed as `{scope, count, time_unit, [window_start, window_end], active_status}`. The reader (`process_checkin`) computes the rolling window from `time_unit` (day/week/month/year/all_time) clamped by optional absolute `window_start`/`window_end`.

**Return shape:**

```json
// Success
{ "success": true, "checkin_id": "<uuid>" }

// Failure
{ "success": false, "error": "<message>" }
```

#### `bff_get_checkin_details(p_mode text DEFAULT 'edit', p_checkin_id uuid DEFAULT NULL) → jsonb` (admin)

**Caller:** loyalty-admin edit form (load existing or new template). SECURITY DEFINER, merchant from JWT.

**Modes:**
- `p_mode = 'new'` → returns an empty template with every field shaped exactly like the `bff_upsert_checkin` input contract. Defaults: `frequency_type='daily'`, `condition_type='consecutive'`, `timezone='Asia/Bangkok'`, `max_streak_days=365`, all eligibility arrays `[]`, `outcomes=[]`, `limits=[]`. The FE can hand this back unchanged to `bff_upsert_checkin`.
- `p_mode = 'edit'` (default) → loads the parent row plus outcomes and limits for an existing campaign. Requires `p_checkin_id`. Returns `{success:false, error:"checkin_id is required for edit mode"}` if id is null, or `{success:false, error:"Check-in campaign not found or access denied"}` if the id doesn't exist or belongs to a different merchant.

**Output shape** (edit mode; new mode is the same skeleton with nulls and defaults):

```json
{
  "success": true,
  "mode": "edit",
  "id": "<uuid>",
  "merchant_id": "<uuid>",
  "name": "...",
  "description": "...",
  "frequency_type": "daily|weekly",
  "timezone": "Asia/Bangkok",
  "enable_time_window": false,
  "window_start_time": "06:00:00",
  "window_end_time": "22:00:00",
  "max_streak_days": 365,
  "window_start": "<timestamptz|null>",
  "window_end": "<timestamptz|null>",
  "require_condition_match": false,
  "active_status": true,
  "allowed_tier": ["<uuid>", ...],
  "allowed_persona": ["<uuid>", ...],
  "allowed_tags": ["<uuid>", ...],
  "allowed_birthmonth": [1, 7, 12],
  "condition_type": "consecutive|fixed_period_count|rolling_period_count",
  "period_start": "<timestamptz|null>",
  "period_end": "<timestamptz|null>",
  "rolling_window_days": 14,
  "period_target_count": 10,
  "created_at": "<timestamptz>",
  "updated_at": "<timestamptz>",
  "outcomes": [
    {
      "id": "<uuid>",
      "outcome_type": "points|tickets|reward|earn_factor",
      "entity_id": "<uuid|null>",
      "entity_name": "Free Coffee",  // joined: reward -> reward_master.name, tickets -> ticket_type.name; null for points/earn_factor (earn_factor has no name column)
      "amount": 50,
      "trigger_type": "every_checkin|streak_milestone|period_milestone",
      "streak_day_start": 7,
      "streak_day_end": 7,
      "period_count_target": 10,
      "priority": 200,
      "is_milestone": true,
      "active_status": true,
      "created_at": "<timestamptz>"
    }
  ],
  "limits": [
    {
      "id": "<uuid>",
      "entity_type": "checkin",
      "entity_id": "<uuid>",
      "scope": "user|total",
      "count": 30,
      "time_unit": "day|week|month|year|all_time",
      "window_start": "<timestamptz|null>",
      "window_end": "<timestamptz|null>",
      "active_status": true,
      "created_at": "<timestamptz>"
    }
  ]
}
```

Outcomes are returned ordered by `priority DESC, is_milestone DESC, created_at` so the FE shows the most important / milestone outcomes first.

#### `bff_list_checkins() → jsonb` (admin)

**Caller:** loyalty-admin Check-in list view. SECURITY DEFINER, merchant from JWT. No parameters.

**Return shape:**

```json
{
  "success": true,
  "data": [
    {
      "id": "<uuid>",
      "name": "Daily Bonus",
      "description": "...",
      "frequency_type": "daily|weekly",
      "condition_type": "consecutive|fixed_period_count|rolling_period_count",
      "timezone": "Asia/Bangkok",
      "enable_time_window": false,
      "window_start_time": "06:00:00",
      "window_end_time": "22:00:00",
      "window_start": "<timestamptz|null>",
      "window_end": "<timestamptz|null>",
      "max_streak_days": 365,
      "active_status": true,
      "period_target_count": 10,
      "rolling_window_days": 14,
      "created_at": "<timestamptz>",
      "updated_at": "<timestamptz>",
      "outcome_count": 2,
      "limit_count": 1,
      "total_checkins": 4218,
      "unique_users": 312,
      "last_checkin_at": "<timestamptz|null>"
    }
  ]
}
```

Rows ordered by `created_at DESC`. Summary stats (`outcome_count`, `limit_count`, `total_checkins`, `unique_users`, `last_checkin_at`) are computed via LATERAL joins so the FE table renders without a second round-trip. Returns `{success:true, data:[]}` for merchants with no campaigns (or foreign-merchant JWTs — no cross-merchant leakage).

### 9.3 Outcome Dispatch Path

All outcomes flow through `fn_dispatch_outcome(p_user_id, p_merchant_id, p_outcome_type, p_entity_id, p_amount, p_source_type, p_source_id, p_metadata, p_dedup_key)`.

| Outcome type | Dispatcher routes to | Notes |
|---|---|---|
| `points` | `chokepoint_post_wallet_transaction` (currency=points, type=earn) | Sync. Wallet updates immediately. |
| `tickets` | `chokepoint_post_wallet_transaction` (currency=ticket) | Validates ticket_type exists & active. |
| `reward` | `redeem_reward_with_points(p_mode='direct')` | Zero points deducted. Validates reward exists. |
| `earn_factor` | Direct `earn_factor_user` insert | Default 30-day window (override via `metadata.window_days`). |

`process_checkin` passes `p_source_type='checkin'`, `p_source_id=checkin_id`, and a per-outcome dedup key `'checkin:<checkin_id>:<outcome_id>:<user_id>'`.

Every dispatch — success or failure — writes one row to `outcome_distribution_log`. Failures return `{success:false, error_message}` rather than throwing, so one failed outcome doesn't abort the others.

### 9.4 Implementation Status & Gaps

| Component | Status |
|---|---|
| `checkin` / `checkin_outcomes` / `checkin_ledger` tables | ✅ Live |
| `process_checkin` rewrite | ✅ Live |
| `get_user_checkin_status` rewrite | ✅ Live |
| `fn_compute_checkin_streak` helper | ✅ Live |
| `transaction_limits` integration (`entity_type='checkin'`) | ✅ Live |
| Admin BFF `bff_upsert_checkin(p_config jsonb)` | ✅ Live — single-RPC upsert of campaign header + full-replace of `checkin_outcomes` and `transaction_limits` (entity_type='checkin'). Merchant from JWT; validates name/frequency_type/condition_type. |
| Admin BFF `bff_get_checkin_details(p_mode, p_checkin_id)` | ✅ Live — load single campaign for edit form; 'new' returns template, 'edit' loads parent + children. Round-trip safe with upsert input contract. |
| Admin BFF `bff_list_checkins()` | ✅ Live — list view with summary stats (outcome_count, limit_count, total_checkins, unique_users, last_checkin_at). |
| Member-app UI | ❌ Not documented in loyalty-user repo |
| Full `Checkin.md` requirement doc (root-level) | ❌ Does not exist; this feature guide is the canonical reference |

### 9.5 Open Product Decisions

- **Per-outcome eligibility**: today eligibility is campaign-level (`allowed_tier` on `checkin`). Some use cases want different outcomes to target different tiers on the same campaign (e.g. Gold gets 10 pts, Platinum gets 20 pts). Currently achievable by running two campaigns; native per-outcome eligibility is a future enhancement.
- **`require_condition_match` semantics under multi-outcome**: today, if any outcome matches, the check-in proceeds. If true and zero outcomes match, the check-in is rejected. This is preserved from the prior version but may need refinement once multi-outcome campaigns are common.
- **Time-of-day window for non-consecutive campaigns**: window is enforced regardless of condition_type. Confirm this is desired for fixed/rolling campaigns (some merchants may want count-based campaigns to be 24/7).
