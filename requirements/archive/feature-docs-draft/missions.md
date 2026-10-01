# Feature Guide: Missions

## 1. Overview

Missions are goal-based challenges that guide members through specific actions — making purchases, earning points, referring friends, submitting forms — and reward them upon completion. They are the primary gamification mechanic in the loyalty platform, turning routine behavior into structured quests with visible progress and tangible outcomes.

Two mission types serve different engagement patterns. **Standard Missions** require members to satisfy multiple conditions simultaneously (AND logic) — for example, "spend 5,000 THB AND earn 500 points" — with each condition tracking progress independently in parallel. **Milestone Missions** define sequential levels (Bronze → Silver → Gold), each with its own target and reward. Progress waterfalls through levels: overflow from completing one level automatically applies to the next, so a single large purchase can complete multiple milestones at once.

Key differentiators: (1) **event-driven progress** — purchases, point earnings, referrals, and form submissions automatically update mission progress via CDC event streaming without polling; (2) **waterfall overflow** — milestone missions never waste progress, excess from one level flows to the next; (3) **configurable activation and claiming** — merchants choose whether members opt in manually or track automatically, and whether rewards are distributed immediately or require a claim action; (4) **per-condition JSONB tracking** — granular progress stored per condition or level, enabling multi-axis challenges in a single mission.

## 2. Key Concepts

**Standard Mission** — A mission where all conditions must be met simultaneously. Each condition tracks independently in parallel. Mission completes when every condition reaches its target. Example: "Spend 5,000 THB AND earn 500 points" requires both to reach target.

**Milestone Mission** — A mission with sequential levels (1 → 2 → 3), each having a distinct target and reward. Members advance through levels in order. Example: Level 1 "Spend 500 THB" → Level 2 "Spend 2,000 THB" → Level 3 "Spend 5,000 THB".

**Condition** — A trackable requirement within a mission. Defined by a condition type (what event), measurement type (count or sum), and target value (threshold). Standard missions can have multiple conditions; milestone missions have one condition per level.

**Condition Type** — The event source that triggers progress. Six types: `purchase` (completed purchases), `points_earned` (point earn events), `tickets_earned` (ticket earn events), `form_submission` (completed forms), `referral_signup` (referred user signs up), `referral_purchase` (referred user makes first purchase).

**Measurement Type** — How events contribute to progress. `count`: each qualifying event adds +1 (e.g., "make 5 purchases"). `sum`: each event adds its value (e.g., "spend 5,000 THB"). Binary events (forms, referrals) always use count.

**Waterfall** — Milestone-specific overflow logic. When a purchase exceeds the remaining target for the current level, the excess applies to the next level. Example: Level 1 needs 200 more, purchase is 400 → Level 1 completes, 200 overflow goes to Level 2.

**Activation Type** — `auto`: progress tracks for all members immediately. `manual`: members must explicitly join the mission before progress counts.

**Claim Type** — `auto`: rewards distribute immediately upon completion. `manual`: members must tap a claim button to receive rewards.

**button_action** — A computed field returned by the BFF that tells the frontend which button to show. Priority order: `claim_outcome` (unclaimed completions exist, manual claim) → `join_mission` (not yet accepted, manual activation) → `claimed` (all complete and claimed) → `view_progress` (has progress record) → `view_details` (fallback).

**Reset Frequency** — How often progress resets. `NULL`: accumulates indefinitely. `daily`: resets at midnight. `monthly`: resets on the 1st. Milestone missions cannot have reset frequency.

**Reset Mode** — When reset frequency is set: `global` resets all users at the same calendar time. `user_specific` resets relative to each user's `period_started_at`.

**Exclusivity Group** — A string tag that prevents double-counting. `progress_exclusivity_group`: a single event only updates one mission in the group. `claim_exclusivity_group`: only one mission in the group can be claimed.

**Outcome** — The reward distributed upon completion. Types include points, tickets, or a specific reward entity (linked by `entity_id`). Milestone missions assign outcomes per level.

**Mission Status** — Derived from `is_active`, `start_date`, and `end_date`: Active (on and within window), Inactive (toggled off), Scheduled (start date in future), Expired (end date in past).

## 3. Configuration Reference

### Basic Info

| Setting | What it controls | Example | Default |
|---|---|---|---|
| Name | Mission display name | "Big Spender Challenge" | Required |
| Code | Unique identifier code | "BIG_SPENDER_Q1" | Required |
| Type | Standard or Milestone | `standard` | Required |
| Description | Admin-facing description | "Q1 spending challenge" | Empty |
| Start date | When mission becomes active | 2025-01-01 | No restriction |
| End date | When mission expires | 2025-03-31 | No restriction |
| Is active | Enable/disable toggle | true | true |
| Images | Mission display images | PNG/JPG URLs | Empty array |

### Activation & Claiming

| Setting | What it controls | Options | Default |
|---|---|---|---|
| Activation type | Auto-track or require opt-in | `auto` / `manual` | `auto` |
| Claim type | Auto-reward or require claim | `auto` / `manual` | `auto` |
| Reset frequency | How often progress resets | `NULL` / `daily` / `monthly` | `NULL` |
| Reset mode | Calendar vs per-user reset | `global` / `user_specific` | `global` |

### Progress Controls

| Setting | What it controls | Example | Default |
|---|---|---|---|
| Allow progress loop | Repeat mission after completion | true | false |
| Max loops per transaction | Cap repeats from single event | 3 | NULL (unlimited) |
| Progress exclusivity group | Prevent double-counting across missions | "q1_spending" | NULL |
| Claim exclusivity group | Only one claimable in group | "q1_prizes" | NULL |
| Milestone allow skip | Allow skipping milestone levels | false | false |

### Conditions (per condition row)

| Setting | What it controls | Example | Default |
|---|---|---|---|
| Condition type | Event source | `purchase` | Required |
| Measurement type | Count vs sum | `sum` | Required |
| Target value | Completion threshold | 5000 | Required |
| Operator | AND/OR for array filters | `AND` | `AND` |
| Product/SKU/Category/Brand IDs | Product filters | [uuid, uuid] | Empty (all) |
| Store attribute set | Location filter | uuid | NULL (all) |
| Min/Max transaction amount | Per-event amount range | 100 / 5000 | NULL |
| Form ID | Specific form (form_submission type) | uuid | NULL |
| Earn source type | Point earn source filter | ["purchase"] | Empty |
| Ticket type ID | Ticket type filter | [uuid] | Empty |
| Tier IDs | Eligible tiers | [Gold, Platinum] | Empty (all) |

### Milestones (milestone missions only)

| Setting | What it controls | Example | Default |
|---|---|---|---|
| Milestone level | Level number (sequential) | 1, 2, 3 | Required |
| Milestone name | Display name | "Bronze", "Silver" | Required |
| Badge URL | Level badge image | https://cdn.../bronze.png | NULL |
| Display order | UI ordering | 1, 2, 3 | Same as level |

### Outcomes (per outcome row)

| Setting | What it controls | Example | Default |
|---|---|---|---|
| Outcome type | Reward type | `points` / `tickets` / `reward` | Required |
| Amount | Points/tickets to grant | 500 | Required for points/tickets |
| Milestone level | Which level triggers this (milestone only) | 2 | NULL (standard) |
| Entity ID | Linked reward (reward type) | uuid | NULL |

### Limits

| Setting | What it controls | Example | Default |
|---|---|---|---|
| Scope (progress) | Who the progress limit applies to | `per_user` | — |
| Scope (claim) | Who the claim limit applies to | `per_user` | — |
| Amount | Maximum count in period | 5 | — |
| Time unit | Period of limit | `day` / `month` | — |

### Display Settings

| Setting | What it controls | Example | Default |
|---|---|---|---|
| User perspective | Member-facing description | "Complete to earn 500 pts" | NULL |
| Description goal | Goal description text | "Spend 5,000 THB this month" | NULL |
| Description T&C | Terms and conditions | Rich text | NULL |

## 4. Admin Journey

**Repo:** `Rocket-CRM/loyalty-admin`

**Route map:**

| Page name | Current route | BFF / data source |
|---|---|---|
| Mission List | `/mission-list` | `mission` table direct query |
| Mission Settings (create) | `/mission-settings/new` | `bff_get_mission_details_conditions_limits(mode='new')` |
| Mission Settings (edit) | `/mission-settings/{id}` | `bff_get_mission_details_conditions_limits(mode='edit', id)` |

### 4a. Create a New Mission

1. From **Mission List**, click **"Create mission"** button (top-right)
2. **Mission Settings** opens in create mode — empty form
3. Fill Basic Info: name (required), code (required), select type (Standard or Milestone)
4. Set activation type and claim type; configure reset frequency if needed
5. Add conditions: select condition type, measurement type, target value; add product/category/brand/store filters as needed
6. For Milestone type: define levels with names, badge images, and one condition per level
7. Add outcomes: select outcome type (points/tickets/reward), set amount, link to milestone level if applicable
8. Optionally configure progress and claim limits
9. Set start/end dates, toggle is_active
10. Click **"Save"** → calls `bff_upsert_mission` → on success: redirect to **Mission List**

### 4b. Edit an Existing Mission

1. From **Mission List**, click any mission row
2. **Mission Settings** opens in edit mode — form pre-populated with all conditions, outcomes, and limits
3. Modify any fields — all sections are editable
4. Click **"Save"** to update

### 4c. Manage the Mission List

1. **Mission List** displays an IndexTable with columns: Name, Type (badge), Status (badge), Activation (badge), Claim (badge), Start date, End date, Delete action
2. Status badges: Active (green), Inactive (neutral), Scheduled (blue), Expired (red)
3. **Delete**: click delete icon → confirmation modal ("This will permanently delete this mission and all its conditions, outcomes, and limits") → cascading delete of conditions, outcomes, limit_progress, limit_claim, then the mission
4. Empty state shows CTA: "Create your first mission to engage users with challenges and rewards"

### 4d. Common Admin Mistakes

- Setting `activation_type = manual` but not surfacing the join button in the member app → members can't participate
- Creating a milestone mission with reset frequency → constraint violation (milestones don't reset)
- Adding product filters with AND operator when products come from different purchases → condition never completes
- Setting `allow_progress_loop = false` on a daily-reset mission → mission can only complete once despite resetting
- No outcomes configured → mission completes but grants nothing

## 5. Member Experience

**Repo:** `Rocket-CRM/loyalty-user`

**Route map:**

| Page / Component | Current route | Data source |
|---|---|---|
| Homepage mission section | `/` (block-based) | `bff_get_display_blocks_cached(p_page: 'homepage')` |
| Mission list | Homepage navigation grid | `bff_get_user_missions` |
| Mission detail | Drawer or detail view | `bff_get_mission_detail(p_mission_id)` |

### 5a. Discover Missions

1. Member opens the homepage — navigation grid block includes a "Missions" icon
2. Tapping "Missions" navigates to a mission list view showing available missions
3. Each mission card shows: image, name, type badge, progress indicator, and the button_action CTA

### 5b. View Mission Detail

1. Member taps a mission card → detail view opens
2. Detail shows: mission image, name, description, goal description, terms & conditions
3. For Standard missions: progress bars for each condition (e.g., "3,500 / 5,000 THB", "420 / 500 points")
4. For Milestone missions: level progression display showing completed levels (with badges) and current level progress
5. CTA button text driven by `button_action` field

### 5c. Join a Manual Mission

1. If `activation_type = manual` and member hasn't joined: button shows "Join Mission" (`join_mission`)
2. Member taps → calls `accept_mission` → `accepted_at` timestamp set on progress record
3. Button updates to "View Progress" (`view_progress`)
4. Progress starts tracking from this point forward

### 5d. Track Progress

1. Progress updates automatically as qualifying events occur (purchases, point earnings, etc.)
2. Standard missions show parallel progress bars — each condition independently advancing
3. Milestone missions show sequential level progression — current level highlighted with progress bar
4. No manual action needed — CDC events flow through Kafka → Inngest → PostgreSQL functions

### 5e. Claim Rewards

1. If `claim_type = auto`: rewards distribute immediately upon completion — member sees notification
2. If `claim_type = manual`: button shows "Claim Reward" (`claim_outcome`)
3. Member taps → calls `bff_claim_mission` → outcomes distributed (points/tickets/rewards credited)
4. For milestone missions: each level can be claimed independently via `p_milestone_level` parameter
5. After all claims: button shows "Claimed" (`claimed`, disabled)

## 6. Perspectives

### 6a. For Customer Success / Support

**Elevator pitch**: "Missions are challenges that reward members for completing specific actions — like spending a certain amount, referring friends, or earning points. Members see their progress in real-time and collect rewards when they finish. You can think of them as quests in a game."

**Top 5 support questions:**

| Question | Answer |
|---|---|
| "Member's mission progress isn't updating" | Progress updates via event streaming (CDC → Kafka → Inngest). Check if the qualifying event actually occurred (purchase completed, points earned). If activation_type is manual, confirm the member joined first. |
| "Member completed the mission but didn't get a reward" | If claim_type is manual, member must tap the claim button. Check if claim limits or exclusivity groups are blocking. |
| "Mission shows 'Inactive' but should be running" | Check is_active toggle, start_date (future = Scheduled), and end_date (past = Expired). |
| "Progress reset unexpectedly" | Check reset_frequency (daily/monthly) and reset_mode (global vs user_specific). Progress resets are by design. |
| "Member wants to join but there's no join button" | If activation_type is auto, there's no join step — progress tracks automatically. If manual, check that button_action is rendering correctly. |

### 6b. For Marketing

**Value proposition**: Missions transform passive loyalty membership into active engagement. Instead of simply accumulating points, members pursue structured challenges with clear goals and visible progress — creating a game-like experience that drives repeat visits and higher spend.

**Use-case stories:**

1. **Monthly spending challenge** — "Spend 5,000 THB this month" with daily reset visibility. Members track daily progress, creating urgency to visit before month-end. Auto-activation ensures all members participate without friction.

2. **Onboarding quest** — Standard mission: "Make 3 purchases AND refer 1 friend AND complete your profile form." Combines multiple engagement actions into a single quest that new members complete in their first 30 days.

3. **Tiered spending milestones** — Milestone mission: Bronze (500 THB → 50 points), Silver (2,000 THB → 200 points), Gold (5,000 THB → 500 points + exclusive reward). Waterfall overflow means a single 3,000 THB purchase can complete Bronze and partially fill Silver, rewarding big spenders proportionally.

4. **Seasonal campaign** — Time-boxed mission (start/end dates) tied to a holiday promotion. Manual claim type creates a moment of delight when members tap to collect their reward.

### 6c. For Testers

**Config → expected behavior:**

| Config | Expected behavior |
|---|---|
| `activation_type = manual`, member hasn't joined | `button_action = join_mission`, no progress tracking |
| `activation_type = auto` | Progress tracks immediately for all members |
| `claim_type = manual`, mission completed | `button_action = claim_outcome` |
| `claim_type = auto`, mission completed | Outcomes distributed automatically, `button_action = claimed` |
| `reset_frequency = daily` | Progress resets at midnight (global) or relative to user (user_specific) |
| `reset_frequency = NULL`, milestone mission | Progress accumulates indefinitely (only valid option for milestones) |
| Standard mission, 2 conditions, only 1 met | Mission not complete — ALL conditions required |
| Milestone mission, Level 1 at 300/500, purchase of 400 | Level 1 completes (500/500), 200 overflow → Level 2 (200/target) |
| `allow_progress_loop = true`, completed once | Mission resets and can complete again |
| `is_active = false` | Mission not visible to members, no progress tracking |
| `start_date` in future | Status = Scheduled, not available to members |
| No outcomes configured | Mission completes but no rewards distributed |

**Business rules as assertions:**

- ASSERT: Standard mission completes only when ALL conditions reach target simultaneously
- ASSERT: Milestone waterfall applies overflow from completed level to next level in sequence
- ASSERT: `button_action` priority is claim_outcome > join_mission > claimed > view_progress > view_details
- ASSERT: Manual activation requires `accepted_at` to be set before progress counts
- ASSERT: Milestone missions cannot have reset_frequency (constraint enforced)
- ASSERT: Condition filters (product_ids, category_ids, etc.) with AND operator require all to match in a single event
- ASSERT: Delete cascades in order: conditions → outcomes → limit_progress → limit_claim → mission

**Status model:**

| Field | Values | Meaning |
|---|---|---|
| `is_active` | `true` / `false` | Master toggle for the mission |
| Mission Status (derived) | Active / Inactive / Scheduled / Expired | Computed from is_active + date window |
| `accepted_at` | NULL / timestamp | Whether member has joined (manual activation) |
| `unclaimed_completions` | integer | Pending manual claims |
| `lifetime_completions` | integer | Total completions ever |
| `condition_progress` | JSONB | Per-condition or per-level current values |

## 7. Business Rules

**Rule:** Standard missions use AND logic — all conditions must reach their targets for the mission to complete.
**Example:** Mission has "Spend 5,000 THB" (at 5,000) and "Earn 500 points" (at 420). Not complete — both must hit target.

**Rule:** Milestone missions use sequential waterfall — overflow from completing one level automatically applies to the next.
**Example:** Level 1 at 300/500, Level 2 at 0/2,000. Purchase of 400 arrives → Level 1: 500/500 (complete, overflow 200) → Level 2: 200/2,000.

**Rule:** `button_action` follows strict priority order. The first matching condition wins.
**Example:** Member has unclaimed completions AND hasn't accepted → `claim_outcome` wins over `join_mission` because it's higher priority.

**Rule:** Manual activation blocks all progress tracking until the member explicitly joins.
**Example:** Auto mission: member's purchases count immediately. Manual mission: purchases before `accepted_at` are ignored.

**Rule:** Milestone missions cannot have reset frequency — this is enforced as a database constraint.
**Example:** Creating a milestone mission with `reset_frequency = daily` → rejected.

**Rule:** Empty filter arrays mean unrestricted. `product_ids = []` means all products qualify.
**Example:** Condition with no product filters → any purchase counts toward progress.

**Rule:** The AND operator on condition filters requires all filter criteria to match within a single event.
**Example:** `product_ids = [A, B]` with AND operator → a single purchase must include both products A and B.

**Rule:** Progress loops allow repeated completions. When `allow_progress_loop = true`, progress resets after completion and the mission can be completed again.
**Example:** Daily challenge with loop enabled → member can complete and claim every day.

**Rule:** Exclusivity groups prevent double-counting. A qualifying event updates only one mission within a `progress_exclusivity_group`.
**Example:** Two missions in group "q1_spending" — a purchase event only advances whichever mission the system evaluates first.

**Rule:** Claim limits cap how many times rewards can be collected within a time period.
**Example:** Claim limit: per_user, 3/month → fourth completion in the same month does not distribute rewards.

## 8. Related Features

| Feature | Connection to Missions |
|---|---|
| Currency | Points and tickets granted as mission outcomes are credited to the member's wallet. See `Currency.md`. |
| Rewards | Missions can grant specific rewards (linked by entity_id) as completion outcomes. See `Reward.md`. |
| Referral | `referral_signup` and `referral_purchase` condition types track referral activity as mission progress. See `Referral.md`. |
| Purchase | `purchase` condition type tracks completed purchases. Product, category, brand, and store filters narrow which purchases qualify. See `Purchase_Transaction.md`. |
| Activity/Earning | `points_earned` and `tickets_earned` condition types track earn events. See `Activity_Based_Earning.md`. |
| Forms | `form_submission` condition type tracks completed form submissions. See `Forms.md`. |
| Store Classification | `store_attribute_set_id` filter on conditions restricts which store locations qualify. See `Store_Attribute_Classification.md`. |
| Tier | `tier_ids` on conditions can gate mission participation by member tier. See `Tier.md`. |
