# Feature Guide: Tiers

## 1. Overview

Tiers rank members into levels based on their activity — purchases, points earned, or order count. A merchant defines a ladder of tiers (e.g., Silver → Gold → Platinum), sets conditions for upgrading and maintaining each level, and attaches benefits like burn-rate discounts or exclusive reward eligibility. Members progress automatically as the system evaluates their metrics against the configured conditions.

For merchants, tiers solve the segmentation problem: instead of treating all members equally, tiers let them reward high-value customers with better pricing, exclusive access, and recognition — creating a visible incentive to spend more. The system handles the full lifecycle: automatic entry-tier assignment on signup, real-time upgrade evaluation when transactions land, periodic maintain/downgrade checks on configurable schedules, and a progress tracker that shows members exactly how close they are to the next level.

Key differentiators: (1) **five evaluation window types** — rolling, fixed period, anniversary, calendar month, and calendar quarter — giving merchants flexible measurement periods; (2) **persona-based tier segmentation** — separate tier ladders per persona (e.g., "Buyer" tiers vs "Seller" tiers); (3) **OR-logic upgrade paths** — any single condition qualifying is sufficient for upgrade, allowing multiple independent routes to the same tier; (4) **burn-rate per tier** — each tier can define a points-to-monetary-discount conversion rate used at checkout.

## 2. Key Concepts

**Tier** — A named membership level with a ranking that determines its position in the hierarchy. Example: "Gold" at ranking 2 sits above "Silver" at ranking 1.

**Ranking** — A numeric value (smallint) that orders tiers from lowest to highest. Higher ranking = higher tier. The system uses ranking to determine upgrade targets and downgrade destinations.

**Entry Tier** — The tier automatically assigned to new members on signup. Exactly one tier per user_type/persona combination should be marked as entry tier. Example: "Bronze" is the entry tier for buyers.

**Upgrade Condition** — A rule that qualifies a member for a higher tier. Each condition specifies a metric, a target amount, and a time window. Multiple upgrade conditions on the same tier use OR logic — meeting any one condition triggers the upgrade. Example: "Earn 500 points in 6 months" OR "Spend ฿10,000 in 12 months" → either qualifies for Gold.

**Maintain Condition** — A rule that must be met to keep the current tier. When a maintain deadline arrives and the member fails all maintain conditions, they are downgraded. Example: "Maintain 200 points in 12 months to stay Gold."

**Metric** — The measurement unit for conditions. Four types: `points` (points earned), `ticket` (tickets earned), `sales` (purchase amount), `orders` (number of completed purchases).

**Window Type** — How the evaluation period is calculated. Five types:

- `rolling` — Look back N months from evaluation date (e.g., "last 6 months")
- `fixed_period` — From a specific MM-DD start date for N months (e.g., "Jan 1 to Jun 30 every year")
- `anniversary` — From the member's signup anniversary for N months
- `calendar_month` — Current calendar month (1st to last day)
- `calendar_quarter` — Current calendar quarter (Q1=Jan-Mar, Q2=Apr-Jun, Q3=Jul-Sep, Q4=Oct-Dec)

**Evaluation Frequency** — How often conditions are checked: `realtime` (on every qualifying transaction), `daily` (batch), `monthly` (batch), `period_end` (at window expiration).

**Burn Rate** — A numeric value on a tier that converts points to monetary discount at checkout. Example: burn_rate = 0.5 means 1 point = ฿0.50 discount. NULL means burn rate is disabled for that tier.

**Persona-Based Segmentation** — Tiers can be scoped to a specific persona via `persona_id`. This creates parallel tier ladders — a "Buyer" persona has its own Bronze/Silver/Gold, separate from a "Seller" persona's tiers. NULL persona = universal (applies to all members regardless of persona).

**Tier Progress** — A per-user record tracking: current tier, next upgrade target, percentage progress toward upgrade, metric needed, upgrade deadline, and maintain progress/deadline.

**Tier Change Ledger** — Append-only audit log of every tier change. Records the change type (`initial`, `upgrade`, `downgrade`, `manual`, `scheduled`), from/to tier, reason, and timestamp.

**Tier Locking** — Not yet implemented in the live schema. Reserved for future use where merchants can lock a member's tier to prevent automatic downgrades for a specified period.

## 3. Configuration Reference

### Tier Definition


| Setting     | What it controls                          | Example                   | Default          |
| ----------- | ----------------------------------------- | ------------------------- | ---------------- |
| Tier name   | Display name                              | "Gold"                    | Required         |
| User type   | Buyer or seller tier track                | `buyer`                   | `buyer`          |
| Persona     | Scope tier to a persona (separate ladder) | "Corporate" persona       | NULL (universal) |
| Ranking     | Position in hierarchy (higher = better)   | 2                         | 0                |
| Entry tier  | Auto-assigned on signup                   | true                      | false            |
| Burn rate   | Points-to-discount conversion             | 0.5 (1 pt = ฿0.50)        | NULL (disabled)  |
| Icon        | Tier icon URL or emoji                    | `https://cdn.../gold.svg` | None             |
| Color       | Tier color (hex)                          | `#FFD700`                 | None             |
| Benefits    | JSONB describing tier perks               | `{"free_shipping": true}` | NULL             |
| Card design | JSONB for member card styling             | `{"bg_image": "..."}`     | NULL             |


### Upgrade Conditions


| Setting                   | What it controls                             | Example       | Default   |
| ------------------------- | -------------------------------------------- | ------------- | --------- |
| Metric                    | What is measured                             | `points`      | `ticket`  |
| Amount                    | Target threshold                             | 500           | 0         |
| Window type               | Evaluation period calculation                | `rolling`     | `rolling` |
| Window months             | Period length in months                      | 6             | —         |
| Window start              | Start date for `fixed_period` (MM-DD format) | "01-01"       | —         |
| Window start field        | User date field for `anniversary`            | `create_date` | —         |
| Frequency                 | How often to evaluate                        | `realtime`    | —         |
| Upgrade evaluation timing | When upgrade takes effect                    | —             | Immediate |


### Maintain Conditions

Same fields as upgrade conditions. The system checks maintain conditions when the maintain deadline arrives for a user.

### Display Settings


| Setting     | What it controls                  | Example                                      |
| ----------- | --------------------------------- | -------------------------------------------- |
| Icon        | Image URL or emoji for tier badge | `https://cdn.../platinum.svg`                |
| Color       | Brand color for tier UI elements  | `#8B5CF6`                                    |
| Benefits    | Structured perks description      | `{"discount": "10%", "free_shipping": true}` |
| Card design | Member card visual configuration  | `{"bg_image": "...", "text_color": "#FFF"}`  |


## 4. Admin Journey

**Repo:** `Rocket-CRM/loyalty-admin`

**Route map:**


| Page name                         | Current route                    | BFF / data source                              |
| --------------------------------- | -------------------------------- | ---------------------------------------------- |
| Tier List                         | `/tier`                          | `get_merchant_tiers(p_merchant_id)`            |
| Tier Conditions Settings (create) | `/tier-conditions-settings/new`  | `get_tier_conditions_by_type(mode='new')`      |
| Tier Conditions Settings (edit)   | `/tier-conditions-settings/{id}` | `get_tier_conditions_by_type(mode='edit', id)` |


### 4a. Create a New Tier

1. From **Tier List**, click **"Add tier"** button
2. **Tier Conditions Settings** opens in create mode — empty form
3. Fill in tier name (required), select user type (buyer/seller), optionally select a persona
4. Set ranking to position this tier in the hierarchy
5. Toggle entry tier if this is the default for new members
6. Optionally set burn rate for points-to-discount conversion
7. Add upgrade conditions via repeatable rows: select metric (points/tickets/sales/orders), set target amount, choose window type and period
8. Add maintain conditions (same fields as upgrade)
9. Click **"Save"**
10. On success: redirect to **Tier List**

### 4b. Edit an Existing Tier

1. From **Tier List**, click any tier row or the edit icon
2. **Tier Conditions Settings** opens in edit mode — form pre-populated with current values and conditions
3. Modify any fields — add/remove/edit conditions
4. Save updates

### 4c. Manage Tier List

1. **Tier List** displays all tiers with columns: name, ranking, user type, persona, entry tier badge, burn rate, condition count
2. Tiers are ordered by ranking
3. **Reorder**: drag or use reorder function to change ranking positions (`reorder_tiers`)
4. **Delete**: click delete → confirmation modal. Deletion blocked if members are assigned to the tier
5. **Display settings**: configure icon, color, benefits, and card design per tier (`bff_upsert_tier_display`)

### 4d. View Tier Change History

Admin can view tier change history for members, showing upgrade/downgrade/initial/manual changes with timestamps and reasons.

### 4e. Common Admin Mistakes

- Creating multiple entry tiers for the same user_type/persona → only one is used (first found)
- Setting ranking gaps (1, 2, 5) → works but confuses the visual hierarchy
- No maintain conditions on a tier → members never get downgraded from it
- Persona-scoped tiers without matching entry tier → new members of that persona get no tier
- Setting metric to `ticket` when the merchant only uses points → zero progress for everyone
- Window type `anniversary` without understanding that each member's window starts from their signup date

## 5. Member Experience

**Repo:** `Rocket-CRM/loyalty-user`

**Route map:**


| Page / Component            | Current route                      | Data source                                         |
| --------------------------- | ---------------------------------- | --------------------------------------------------- |
| Homepage Profile Card       | `/`                                | `get_user_tier_progress(user_id, merchant_id)`      |
| Homepage tier progress pill | `/`                                | Same as Profile Card                                |
| History drawer (Tier tab)   | Bottom-sheet from Homepage/Profile | `bff_get_tier_history(p_filter, p_limit, p_offset)` |
| Burn rate at checkout       | Checkout flow                      | `get_user_burn_rate()`                              |


### 5a. View Current Tier

1. Member opens the app — **Profile Card** on homepage shows: tier name with gradient text (derived from tier color), points balance, and "X points to [Next Tier]" progress text
2. Tier color drives the visual gradient: the system converts hex to HSL and generates light→dark gradient applied to the tier name text
3. If the tier has an icon, it appears alongside the tier name

### 5b. Track Upgrade Progress

1. **Profile Card** shows progress toward next tier: "/ 100 Points to Platinum"
2. Progress data comes from `tier_progress`: `upgrade_progress_percent`, `upgrade_metric_needed`, `upgrade_deadline`
3. The system automatically picks the best upgrade path (highest `progress_percent`) when multiple conditions exist

### 5c. View Tier History

1. From Homepage or Profile, member opens **History drawer** → selects **Tier** filter
2. Each entry shows: change title (e.g., "Upgraded to Gold"), from/to tier, change type, date
3. Entries include tier icon and color for visual identification

### 5d. Use Burn Rate at Checkout

1. At checkout, the app calls `get_user_burn_rate()` to fetch the member's current conversion rate
2. Response includes: `effective_rate`, `base_rate`, `multiplier`, `is_enabled`, `tier_name`, `available_points`, `max_discount`
3. If burn rate is enabled, member sees maximum discount they can apply (available_points × effective_rate)
4. If tier has no burn rate configured, `is_enabled = false` and burn rate UI is hidden

## 6. Perspectives

### 6a. For Customer Success / Support

**Elevator pitch**: "Tiers create a visible loyalty ladder for your members. As they shop more, they automatically level up and unlock better benefits — better point-to-discount rates, exclusive rewards, and recognition. You control the rules: how many points or how much spending gets them to each level, and what happens if they don't keep up."

**Top 5 support questions:**


| Question                                     | Answer                                                                                                                                                                              |
| -------------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| "Member didn't upgrade after a big purchase" | Check the upgrade condition's window type and period — the purchase may fall outside the evaluation window. Also verify the condition's metric matches (points vs sales vs orders). |
| "Member was downgraded unexpectedly"         | The maintain deadline was reached and they didn't meet the maintain conditions. Check `tier_change_ledger` for the exact reason and `tier_evaluation_tracking` for the deadline.    |
| "New member has no tier"                     | Entry tier may not be configured for that member's user_type/persona combination. Check `tier_master` for an entry tier matching their profile.                                     |
| "Burn rate shows 0 at checkout"              | The member's current tier has `burn_rate = NULL`. Only tiers with a numeric burn rate enable the discount feature.                                                                  |
| "Tier progress shows wrong percentage"       | Progress is calculated from the best single upgrade condition path. If multiple conditions exist, the system picks the one with highest progress — not an aggregate.                |


**Bug vs misconfiguration**: If tier changes appear in the ledger but the member app doesn't reflect them → likely a UI cache issue. If no ledger entry exists when it should → check evaluation tracking status and condition windows.

### 6b. For Marketing

**Value proposition**: Tiers give members a visible reason to stay engaged. The progression from Bronze to Silver to Gold creates a game-like experience — members can see exactly how close they are to the next level and what benefits they'll unlock. For merchants, this translates to higher average order values as members chase the next tier.

**Use-case stories:**

1. **Café chain** — Three tiers: Bronze (entry), Silver (200 points in 6 months), Gold (500 points in 6 months). Gold members get burn_rate 0.5 (1 point = ฿0.50 off), Silver gets 0.25. Members actively buy more coffee to reach Gold before their window closes.
2. **B2B distributor** — Persona-based ladders: "Retailer" persona has Bronze/Silver/Gold based on sales volume, "Wholesaler" persona has Standard/Premium based on order count. Each persona sees only their relevant tier ladder.
3. **Fashion retailer** — Uses `calendar_quarter` window type to align tier evaluation with seasonal buying patterns. Members must spend ฿5,000 per quarter to maintain Gold. Creates quarterly spending urgency.
4. **Anniversary rewards** — Uses `anniversary` window type so each member's tier resets on their personal signup anniversary. More equitable than calendar-based windows for members who join mid-year.

**Metrics merchants care about**: Tier distribution (% of members at each level), upgrade rate, downgrade rate, average spend per tier, tier-driven revenue lift.

### 6c. For Testers

**Config → expected behavior:**


| Config                                     | Expected behavior                                                              |
| ------------------------------------------ | ------------------------------------------------------------------------------ |
| Entry tier = true, ranking = 1             | New members auto-assigned to this tier on signup                               |
| Upgrade: points >= 500, rolling 6 months   | Member with 500+ points in last 6 months qualifies for upgrade                 |
| Upgrade: sales >= 10000 OR orders >= 50    | Meeting EITHER condition qualifies (OR logic between conditions)               |
| Maintain: points >= 200, rolling 12 months | Member below 200 points when deadline arrives → downgrade                      |
| No maintain conditions on tier             | Member stays in this tier indefinitely (no downgrade)                          |
| `burn_rate = 0.5`                          | `get_user_burn_rate()` returns `effective_rate = 0.5`, `is_enabled = true`     |
| `burn_rate = NULL`                         | `get_user_burn_rate()` returns `effective_rate = 0`, `is_enabled = false`      |
| `persona_id` set on tier                   | Only members with matching persona are evaluated against this tier             |
| Window type = `calendar_quarter`           | Window bounds align to Q1/Q2/Q3/Q4 regardless of when condition was created    |
| Multiple tiers qualify for upgrade         | Member upgrades to highest-ranking qualifying tier (non-adjacent skip allowed) |


**Business rules as assertions:**

- ASSERT: On signup, member is assigned the entry tier for their user_type/persona
- ASSERT: Upgrade evaluates highest-ranking tiers first; first qualifying tier wins
- ASSERT: Members can skip tiers (e.g., Bronze → Platinum if they meet Platinum conditions)
- ASSERT: Downgrade goes to highest qualifying lower tier, or entry tier if none qualify
- ASSERT: Maintain conditions are only checked when `maintain_deadline <= evaluation_date`
- ASSERT: Each tier change creates exactly one `tier_change_ledger` record
- ASSERT: `tier_progress` always reflects the best single upgrade path (highest progress_percent)
- ASSERT: `burn_rate` response includes `max_discount = available_points × effective_rate`

**Change type values in `tier_change_ledger`:**


| Value       | Meaning                                           |
| ----------- | ------------------------------------------------- |
| `initial`   | First tier assignment (signup)                    |
| `upgrade`   | Automatic upgrade via condition evaluation        |
| `downgrade` | Automatic downgrade when maintain conditions fail |
| `manual`    | Admin-initiated tier change                       |
| `scheduled` | Batch-processed tier change (pg_cron)             |


**Evaluation architecture:**

- Upgrades: triggered by CDC → Render consumer (real-time on qualifying transactions)
- Maintains/downgrades: pg_cron batch processing in chunks of 1,000 users
- Deduplication: 5-minute Redis window prevents duplicate evaluations

## 7. Business Rules

**Rule:** Upgrade conditions use OR logic. If a tier has multiple upgrade conditions, qualifying for any single one triggers the upgrade.
**Example:** Gold requires "500 points in 6 months" OR "฿10,000 sales in 12 months." A member earning 500 points but only ฿3,000 in sales still qualifies via the points path.

**Rule:** The system evaluates upgrade tiers from highest ranking down. It stops at the first qualifying tier. Members can skip intermediate tiers.
**Example:** Member is Bronze (rank 1). Platinum (rank 3) condition = 1000 points. Gold (rank 2) = 500 points. Member has 1200 points → upgrades directly to Platinum, skipping Gold.

**Rule:** Downgrade evaluates only when the maintain deadline has arrived. Before the deadline, the member keeps their tier regardless of current metrics.
**Example:** Member upgraded to Gold on Jan 1, maintain window = 12 months rolling. Even if they have 0 points in June, no downgrade until the maintain deadline (recorded in `tier_evaluation_tracking.maintain_deadline`).

**Rule:** On downgrade, the member drops to the highest-ranking lower tier they qualify for. If they qualify for none, they drop to the entry tier.
**Example:** Platinum member fails maintain → system checks Gold maintain conditions → passes → downgraded to Gold (not Bronze).

**Rule:** Persona-scoped tiers are isolated. A member with persona "Retailer" is only evaluated against tiers where `persona_id` matches or is NULL.
**Example:** "Wholesaler Gold" tier exists but a "Retailer" member will never be evaluated against it.

**Rule:** Entry tier assignment happens on signup via trigger. The system finds the entry tier matching the user's `user_type` and `persona_id` (with NULL as wildcard).
**Example:** New buyer with "Corporate" persona → system looks for entry tier where `user_type='buyer'` AND (`persona_id='corporate-uuid'` OR `persona_id IS NULL`).

**Rule:** Burn rate is tier-specific, not global. Each tier independently defines its conversion rate. A member's burn rate changes immediately when their tier changes.
**Example:** Silver burn_rate = 0.25, Gold = 0.50. Member upgrades Silver→Gold → their checkout discount doubles instantly.

**Rule:** Progress tracking shows the single best upgrade path. When multiple conditions exist for the next tier, `upgrade_progress_percent` reflects whichever condition the member is closest to completing.
**Example:** Gold has "500 points" (member at 60%) and "฿10,000 sales" (member at 80%). Progress shows 80%.

**Rule:** Window date calculation varies by type. `rolling` looks back from today. `fixed_period` uses the MM-DD anchor. `anniversary` uses the member's signup date. `calendar_month` and `calendar_quarter` snap to period boundaries.
**Example:** For `calendar_quarter` evaluated on May 15: window = Apr 1 – Jun 30 (Q2).

## 8. Related Features


| Feature              | Connection to Tiers                                                                                                                                               |
| -------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Currency             | Points and tickets earned are metrics for tier conditions. Burn rate converts points to checkout discount. See Currency guide.                                    |
| Rewards              | Reward eligibility can be tier-gated; dynamic pricing can vary by tier. See Rewards guide.                                                                        |
| Tag & Persona        | Persona determines which tier ladder applies. User type (buyer/seller) partitions tiers. See `Tag_and_Persona.md`.                                                |
| Purchase Transaction | Completed purchases (`status='completed'`) trigger tier upgrade evaluation via CDC. Sales amount and order count are tier metrics. See `Purchase_Transaction.md`. |
| Mission              | Missions can use tier as an eligibility filter. Tier upgrades don't directly trigger missions. See `Mission.md`.                                                  |
| Activity Earning     | Activity-earned points/tickets contribute to tier metrics. See `Activity_Based_Earning.md`.                                                                       |
| Translation          | Tier names and benefits support multi-language via the translation system. See `Translation_System.md`.                                                           |
