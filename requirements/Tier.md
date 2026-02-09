# Tier Management System - Complete Business Description

**Version**: 4.2  
**Last Updated**: February 2026  
**Architecture**: CDC → Render Consumer → Inngest (Upgrades) + pg_cron Batch (Maintains)  
**New in 4.2**: Persona-based tier segmentation with independent optional dimensions  
**New in 4.1**: Calendar Month & Calendar Quarter window types + Critical bug fixes

## Overview

### Core Tiering Concept
Our tier management system is fundamentally based on **"earn over a period"** philosophy. Users progress through loyalty tiers by demonstrating consistent earning behavior across defined time windows. The system recognizes two primary earning categories:

#### Currency Earning
- **Points**: Digital loyalty currency earned through purchases, campaigns, or manual adjustments
- **Tickets**: Special event currency for exclusive rewards and experiences
- **Source**: Tracked in `wallet_ledger` where `transaction_type = 'earn'`

#### Purchase Earning  
- **Sales Amount**: Total monetary value of transactions demonstrating spending commitment
- **Number of Orders**: Transaction frequency showing engagement consistency
- **Source**: Tracked in `purchase_ledger` with credit/debit record handling

### Tier Progression Philosophy
Users advance through tiers by meeting **upgrade conditions** (earning thresholds to achieve higher tiers) and maintain their status by meeting **maintenance conditions** (minimum earning requirements to retain current tier). 

**Multiple Conditions Per Tier**: Each tier can have multiple conditions, providing different paths to achieve the same tier. For example, Gold tier might be achievable through either "1,500 points in 6 months" OR "100,000 THB sales in 6 months". This flexibility allows merchants to reward different types of customer behavior.

The system supports:

- **Non-Adjacent Progression**: Users can skip intermediate tiers if they qualify for higher ones
- **Multi-Path Qualification**: Multiple earning paths to the same tier (e.g., points OR sales OR orders)
- **Time Window Flexibility**: Rolling, fixed-period, or anniversary-based evaluation periods
- **Real-time vs Scheduled**: Immediate upgrades or batched evaluations based on business needs

The tier management system enables merchants to create and manage customer loyalty tiers with automatic upgrades, downgrades, and progress tracking. The system consists of four main tables: `tier_master`, `tier_conditions`, `tier_progress`, and integrates with `user_accounts`, `wallet_ledger`, and `purchase_ledger`.

## Core Tables and Structure

### 1. tier_master Table
This table defines the available tiers for each merchant. Key fields include:

| Field | Type | Purpose |
|-------|------|---------|
| `id` | uuid | Unique identifier for the tier |
| `merchant_id` | uuid | Links to the merchant who owns this tier |
| `tier_name` | text | Display name of the tier (e.g., "Gold", "Platinum") |
| `user_type` | enum | Optional user type filter ('buyer' or 'seller'). Works independently with persona_id |
| `persona_id` | uuid | **NEW v4.2**: Optional persona filter. References persona_master. NULL means applies to all personas |
| `ranking` | smallint | Numerical rank used for tier hierarchy (higher rank = higher tier) |
| `entry_tier` | boolean | Indicates if this is the default tier for new users. Only one entry tier allowed per merchant/user_type/persona combination |
| `created_at` | timestamptz | Timestamp of tier creation |

### 2. tier_conditions Table
This table defines the conditions required to upgrade to or maintain each tier. A single tier can have multiple conditions, providing different paths to achieve the same tier. Key fields include:

| Field | Type | Purpose |
|-------|------|---------|
| `id` | bigint | Unique identifier for the condition |
| `merchant_id` | uuid | Links to the merchant |
| `tier_id` | uuid | References the tier in tier_master this condition applies to |
| `condition_type` | enum | Either 'upgrade' (to achieve tier) or 'maintain' (to keep tier) |
| `metric` | enum | What to measure - 'points', 'ticket', 'sales', or 'orders' |
| `amount` | numeric | Target amount required for the metric |
| `window_months` | smallint | Duration of the evaluation window in months |
| `window_type` | enum | How to calculate the window: 'calendar_month', 'calendar_quarter', 'rolling', 'fixed_period', or 'anniversary' |
| `window_start` | varchar | For fixed_period only: defines start date (e.g., "01-01", "03-15"). NULL for calendar/rolling/anniversary types |
| `window_start_field` | enum | For anniversary type only: specifies which date field from user_accounts to use (e.g., 'create_date') |
| `frequency` | enum | When to execute tier calculations (see detailed explanation below) |
| `upgrade_evaluation_timing` | text | **For upgrade conditions only**: When to apply the upgrade - NULL/'immediate', 'end_of_month', 'fixed_date', or 'rolling_days' |
| `upgrade_evaluation_value` | text | **For upgrade conditions only**: Configuration value for timing - NULL for immediate/end_of_month, 'MM-DD' for fixed_date, or number of days for rolling_days |
| `active_status` | boolean | Whether this condition is currently active |
| `created_at` | timestamptz | Timestamp of condition creation |

#### Upgrade Timing Configuration

The `upgrade_evaluation_timing` field controls when a tier upgrade takes effect after a user qualifies:

| Timing | Value Example | Behavior |
|--------|---------------|----------|
| NULL or 'immediate' | NULL | Upgrade applied immediately when user qualifies |
| 'end_of_month' | NULL | Upgrade scheduled for end of current month |
| 'fixed_date' | '01-01' (MM-DD) | Upgrade scheduled for next occurrence of specified date |
| 'rolling_days' | '7' | Upgrade scheduled for X days after qualification |

**Important**: When upgrade is delayed (not immediate), the system:
1. Publishes to Inngest - **the workflow state IS the pending state** (no database table or Redis cache needed)
2. Inngest workflow `sleepUntil()` waits for effective date
3. **Re-evaluates** user's tier status at the effective date (not just delays application)
4. Applies upgrade only if user still qualifies at that time
5. Can be cancelled via `cancelOn` if user loses qualification before effective date (matches `user_id + merchant_id`)

### 3. tier_progress Table
This table maintains one record per user showing their current tier status and progress toward upgrades or maintenance requirements. **This is purely for display purposes** - actual tier evaluation state is tracked in `tier_evaluation_tracking`. Fields include:

| Field | Type | Purpose |
|-------|------|---------|
| `id` | uuid | Unique identifier |
| `user_id` | uuid | References auth.users |
| `merchant_id` | uuid | Links to the merchant |
| `current_tier_id` | uuid | User's current tier from tier_master |
| `next_tier_id` | uuid | Next achievable tier |
| `upgrade_metric_needed` | enum | Which metric is being tracked for upgrade |
| `upgrade_progress_percent` | numeric | Percentage progress toward upgrade (always shows highest progress among multiple conditions) |
| `upgrade_deadline` | date | Date by which upgrade conditions must be met |
| `maintain_metric_needed` | enum | Which metric is being tracked for maintenance |
| `maintain_progress` | numeric | Current progress toward maintenance requirement |
| `maintain_deadline` | date | Date by which maintenance conditions must be met (copied from tier_evaluation_tracking) |
| `created_at` | timestamptz | Timestamp of record creation |

### 3a. Pending Upgrade State Management (Inngest-Based)

> **Architecture Note**: The system does NOT use a `pending_tier_upgrades` database table OR Redis cache for pending state. **Inngest workflow state IS the pending state**. This is the simplest architecture - no state synchronization needed.

**Pending State Tracked Via**:

| Component | Purpose |
|-----------|---------|
| **Inngest Workflow** | Durable state storage - sleeps until effective date, contains all upgrade context |

**Inngest Workflow State Contains**:
- `user_id`, `merchant_id`: Who is being upgraded
- `to_tier_id`, `to_tier_ranking`: Target tier details
- `effective_at`: When to apply the upgrade
- `from_tier_id`: Original tier for audit trail

**Key Benefits**:
- No database table to maintain or synchronize
- No Redis cache needed for pending state
- Inngest provides observability dashboard for pending workflows
- `cancelOn` provides automatic cancellation matching by `user_id + merchant_id`
- User can only have one pending tier upgrade at a time

**Workflow Integration**:
- Consumer publishes `tier/upgrade-cancelled` first (cancels any existing pending) → then `tier/upgrade` event
- Workflow `sleepUntil(effective_at)` → Inngest persists state
- At effective date, workflow wakes and re-evaluates
- `cancelOn` listens for `tier/upgrade-cancelled` with matching `user_id + merchant_id` (no `to_tier_id` needed)

**Superseding Logic**:
- When new qualification happens: cancel any existing pending → create new (if delayed) or apply (if immediate)
- Consumer always publishes `tier/upgrade-cancelled` before processing new qualification
- Inngest ignores cancel events if no matching workflow exists

### 3b. tier_evaluation_tracking Table (Critical for Maintenance)
This table tracks the actual evaluation state and scheduling for tier maintenance. **This is the authoritative source for maintenance deadlines**. Fields include:

| Field | Type | Purpose |
|-------|------|---------|
| `user_id` | uuid | References auth.users (part of composite PK) |
| `merchant_id` | uuid | Links to the merchant (part of composite PK) |
| `tier_achieved_at` | timestamptz | When user achieved their current tier |
| `maintain_deadline` | date | Calculated deadline for maintenance evaluation |
| `maintain_window_type` | enum | Type of window (rolling/fixed_period) for maintenance |
| `maintain_condition_ids` | uuid[] | Array of condition IDs being tracked |
| `last_queued_at` | timestamptz | Last time user was queued for evaluation |
| `last_processed_at` | timestamptz | Last time evaluation was completed |
| `processing_status` | text | Current processing state |
| `updated_at` | timestamptz | Last update timestamp |

### 4. user_accounts Table (tier-relevant fields)

| Field | Type | Purpose |
|-------|------|---------|
| `id` | uuid | User identifier (references auth.users) |
| `merchant_id` | uuid | Links to merchant |
| `user_type` | enum | 'buyer' or 'seller' - determines which tiers apply |
| `tier_id` | uuid | Current tier assignment |
| `tier_lock_downgrade` | boolean | Prevents automatic downgrades when true |
| `tier_locked_downgrade_until` | timestamptz | Expiry time for downgrade lock |
| `created_at` | timestamptz | Account creation date (used for anniversary calculations) |

## Business Logic and Concepts

### Window Type vs Frequency: Understanding the Distinction

**Two Independent Dimensions**:
1. **Window Type** (`window_type`): Defines WHAT period of data to evaluate
2. **Frequency** (`frequency`): Defines WHEN to perform the evaluation

This distinction is especially important for maintenance conditions:
- **Window Type** determines the maintenance deadline (when the window expires)
- **Frequency** determines how often to check if the deadline has been met

### Window Type - Evaluation Period Definition
The `window_type` field in `tier_conditions` defines HOW the evaluation period is calculated for checking if a user meets tier requirements. There are five types:

#### 1. Calendar Month (window_type = 'calendar_month') **[NEW]**

Uses the current calendar month as the evaluation period:
- **Does NOT require** `window_start` or `window_months` (set to NULL)
- The evaluation period is always the current calendar month (Jan 1-31, Feb 1-28/29, etc.)
- Automatically handles different month lengths (28/29/30/31 days)
- **Example**: `window_type='calendar_month'`, `amount=5000`, `metric='sales'`:
  - Evaluated on January 15: Checks sales from January 1-31
  - Evaluated on February 15: Checks sales from February 1-28 (or 29 in leap years)
  - Evaluated on December 31: Checks sales from December 1-31
- **Use Case**: Monthly spending tiers, monthly engagement campaigns

**Harsh Deadline Behavior (Maintain Conditions)**:
- User upgrades **mid-month** (e.g., March 15) → Deadline = **end of current month** (March 31) - only 16 days to maintain!
- User evaluated **on month-end** (e.g., March 31) → Deadline **auto-advances** to next month (April 30)
- Creates urgency for immediate engagement

#### 2. Calendar Quarter (window_type = 'calendar_quarter') **[NEW]**

Uses the current calendar quarter as the evaluation period:
- **Does NOT require** `window_start` or `window_months` (set to NULL)
- The evaluation period is always the current calendar quarter:
  - **Q1**: January 1 - March 31 (90 days)
  - **Q2**: April 1 - June 30 (91 days)
  - **Q3**: July 1 - September 30 (92 days)
  - **Q4**: October 1 - December 31 (92 days)
- **Example**: `window_type='calendar_quarter'`, `amount=15000`, `metric='sales'`:
  - Evaluated on February 15 (Q1): Checks sales from January 1 - March 31
  - Evaluated on May 15 (Q2): Checks sales from April 1 - June 30
  - Evaluated on November 30 (Q4): Checks sales from October 1 - December 31
- **Use Case**: Quarterly sales targets, seasonal campaigns, fiscal quarter alignment

**Harsh Deadline Behavior (Maintain Conditions)**:
- User upgrades **mid-quarter** (e.g., May 15 in Q2) → Deadline = **end of current quarter** (June 30) - only 45 days!
- User evaluated **on quarter-end** (e.g., June 30) → Deadline **auto-advances** to next quarter (September 30)
- Year transitions automatically (Q4 Dec 31 → Q1 Mar 31 next year)

#### 3. Fixed Period (window_type = 'fixed_period')

Uses a fixed period that repeats based on the configured `window_start` and `window_months`:
- Requires `window_start` to be set (e.g., "01-01", "04-01", "07-15")
- The evaluation period runs from the `window_start` date for the duration of `window_months`
- The period is NOT necessarily a calendar year - it depends on configuration:
  - Calendar year only if `window_start='01-01'` and `window_months=12`
  - Could be custom periods like `window_start='03-15'` and `window_months=6` (March 15 to September 14)
- **Note**: For standard calendar quarters, use `calendar_quarter` type instead

**Example 1**: Annual period - `window_type='fixed_period'`, `amount=1000`, `metric='points'`, `window_start='01-01'`, `window_months=12`:
- Evaluates points earned from January 1st to December 31st

**Example 2**: Custom 6-month period - `window_type='fixed_period'`, `amount=100`, `metric='orders'`, `window_start='06-15'`, `window_months=6`:
- Evaluates June 15 to December 14 each year

#### 4. Rolling Window (window_type = 'rolling')

Uses a dynamic lookback period from the calculation trigger date:
- Does NOT use `window_start` (ignored for rolling type)
- Requires `window_months` to define the lookback duration
- The evaluation period is always the past X months from the moment of calculation
- **Example**: If `window_type='rolling'`, `amount=1000`, `metric='points'`, `window_months=6`:
  - On August 22nd calculation: System checks points earned from February 22nd to August 22nd
  - On September 15th calculation: System checks points earned from March 15th to September 15th
  - Each calculation uses a different window based on WHEN it's triggered
- The window "rolls" forward with each evaluation

#### 5. Anniversary (window_type = 'anniversary')

Uses a user-specific date as the starting point:
- Requires `window_start_field` to be set (e.g., 'create_date')
- The system reads the specified date field from the `user_accounts` table for each individual user
- The generic `window_start` field is IGNORED for anniversary type
- **Example**: If `window_type='anniversary'`, `window_start_field='create_date'`, `window_months=12`:
  - For a user who joined March 15, 2024: Evaluates March 15, 2025 to March 14, 2026
  - For a user who joined June 1, 2024: Evaluates June 1, 2024 to May 31, 2025
  - Each user has their own personalized evaluation period

### Frequency - Execution Timing Configuration
The `frequency` field determines WHEN the tier calculations are actually executed. This is completely independent from the window type - the window defines what period to evaluate, while frequency defines when to perform that evaluation.

**Critical Distinction for Maintenance Conditions**:
- **Window Type**: Defines the evaluation window and determines the maintenance deadline
  - Rolling: Dynamic deadline (tier_achieved_at + window_months)
  - Fixed Period: Aligned deadline (next period end date)
- **Frequency**: Defines when the system checks if the deadline has been met
  - Daily/Monthly: Regular checks before deadline
  - Period End: Single check at the deadline

#### 1. Realtime (frequency = 'realtime')

- Calculations trigger immediately on qualifying events
- **Trigger Events**:
  - Any change in currency (new record in `wallet_ledger` for points, tickets, etc.)
  - Any new purchase (new record in `purchase_ledger`)
- **IMPORTANT**: Only valid for 'upgrade' conditions, NOT for 'maintain' conditions
  - Maintain conditions cannot use realtime (logical paradox - nothing triggers evaluation if user isn't transacting)
- **Example Scenario (Upgrade Only)**:
  - `window_type='fixed_period'`, `window_months=12`, `window_start='01-01'`, `frequency='realtime'`
  - User earns their 1000th point on July 15th
  - System immediately evaluates points from January 1 to December 31 (full year window)
  - If the 1000 points threshold is met, user upgrades immediately on July 15th
  - They don't have to wait until year-end despite the fixed annual period

#### 2. Periodic Frequencies (frequency = 'daily', 'monthly', 'period_end')

Calculations run via scheduled cron jobs rather than event triggers:

**Cron Architecture (Two-tier system)**:

**First Daily Cron (Scanner)**:
- Runs every day with early exit logic
- Scans ALL `tier_conditions` records
- Checks if any condition's frequency matches the current date:
  - For daily: Matches every day
  - For monthly: Matches on configured day of month
  - For period_end: Calculates if today is the end of any condition's evaluation window
- If no matches found: Early exit (minimal resource usage)
- If matches found: Triggers the second cron for those specific conditions

**Second Cron (Evaluator)**:
- Only runs when triggered by first cron
- Processes actual tier calculations for matched conditions
- Evaluates all users under the merchant for upgrade/downgrade eligibility
- Performs batch tier changes and updates `tier_progress` records
- More resource-intensive but only runs when needed

**Period End Special Case**:
- `frequency='period_end'` requires calculating when each window actually ends
- For upgrade conditions:
  - fixed_period: Ends on (window_start + window_months - 1 day)
  - anniversary: Different end date for each user based on their anniversary date
  - rolling: Not typically used with period_end
- For maintain conditions:
  - ONLY valid with fixed_period window type
  - Evaluates all users at the same calendar period end

### Critical Distinction: Window vs Frequency
The independence of these two dimensions enables flexible business rules, but with important constraints for maintenance conditions:

#### Valid Combinations for UPGRADE Conditions
All window_type and frequency combinations are valid for upgrades (with logical constraints):

##### Calendar Month + Period End: Monthly spending targets **[NEW]**
- **Example**: "Earn 5,000 baht in any calendar month to reach Silver"
- **Window**: Current calendar month (Jan 1-31, Feb 1-28/29, etc.)
- **Execution**: Evaluation only at month-end (cannot use realtime/daily - would evaluate incomplete month)
- **Frequency**: MUST use 'period_end' (evaluates on 31st, 28th, 30th depending on month)

##### Calendar Quarter + Period End: Quarterly targets **[NEW]**
- **Example**: "Earn 15,000 baht in any calendar quarter to reach Gold"  
- **Window**: Current calendar quarter (Q1: Jan-Mar, Q2: Apr-Jun, Q3: Jul-Sep, Q4: Oct-Dec)
- **Execution**: Evaluation only at quarter-end (Mar 31, Jun 30, Sep 30, Dec 31)
- **Frequency**: MUST use 'period_end'

##### Fixed Period + Realtime: Annual targets with immediate rewards
- **Example**: "Earn 10,000 points this year to reach Gold"
- **Window**: January 1 - December 31 (fixed)
- **Execution**: Upgrade happens immediately when 10,000 points reached (could be March, July, etc.)

##### Rolling + Daily: Recent activity with batched processing
- **Example**: "Earn 5,000 points in any 6-month period"
- **Window**: Always the previous 6 months from calculation date
- **Execution**: Check happens once per day via cron

##### Anniversary + Period End: Annual review on membership anniversary
- **Example**: "Spend $10,000 in your membership year"
- **Window**: User's join date + 12 months
- **Execution**: Evaluation only happens at the end of each user's membership year

#### Valid Combinations for MAINTAIN Conditions
Maintain conditions have specific constraints to ensure logical consistency:

##### ✅ Calendar Month + Period End: Monthly recurring maintenance **[NEW]**
- **Example**: "Maintain 3,000 baht spending each calendar month"
- **Window**: Current calendar month (always complete month: Jan 1-31, Feb 1-28, etc.)
- **Deadline**: **Harsh** - End of current month when tier achieved, then auto-advances monthly
- **Execution**: Checked at end of each month
- **Example Timeline**: 
  - User upgrades March 15 → Deadline March 31 (only 16 days to maintain!)
  - Passes March 31 check → Deadline auto-advances to April 30
  - Passes April 30 check → Deadline auto-advances to May 31
- **Key Insight**: Immediate pressure to maintain, continuous monthly evaluation

##### ✅ Calendar Quarter + Period End: Quarterly recurring maintenance **[NEW]**
- **Example**: "Maintain 10,000 baht spending each calendar quarter"
- **Window**: Current calendar quarter (Q1-Q4)
- **Deadline**: **Harsh** - End of current quarter when tier achieved, then auto-advances quarterly
- **Execution**: Checked at end of each quarter (Mar 31, Jun 30, Sep 30, Dec 31)
- **Example Timeline**:
  - User upgrades May 15 (mid-Q2) → Deadline June 30 (only 45 days!)
  - Passes June 30 check → Deadline auto-advances to Sep 30 (Q3)
  - Passes Sep 30 check → Deadline auto-advances to Dec 31 (Q4)
- **Key Insight**: Quarterly business cycle alignment with harsh deadlines

##### ✅ Rolling + Daily/Monthly: Dynamic deadlines with regular checks
- **Example**: "Maintain 5,000 points earned in the last 6 months"
- **Window**: 6 months from tier achievement date (different for each user)
- **Deadline**: tier_achieved_at + 6 months (stored in tier_evaluation_tracking)
- **Execution**: Checked daily/monthly leading up to deadline
- **Key Insight**: Each user has their own deadline, but checks happen on a regular schedule

##### ✅ Calendar Month + Period End: Monthly synchronized evaluation **[NEW]**
- **Example**: "Maintain 3,000 baht spending each calendar month"
- **Window**: Current calendar month (Jan 1-31, Feb 1-28, etc.)
- **Deadline**: End of current month when achieved (harsh), auto-advances monthly
- **Execution**: Evaluation at end of each month (31st, 28th, 30th)
- **Key Insight**: Simple monthly recurring checks with harsh immediate deadlines

##### ✅ Calendar Quarter + Period End: Quarterly synchronized evaluation **[NEW]**
- **Example**: "Maintain 10,000 baht spending each calendar quarter"
- **Window**: Current calendar quarter (Q1-Q4)
- **Deadline**: End of current quarter when achieved (harsh), auto-advances quarterly
- **Execution**: Evaluation at quarter-end (Mar 31, Jun 30, Sep 30, Dec 31)
- **Key Insight**: Quarterly business cycle alignment with harsh deadlines

##### ✅ Fixed Period + Period End: Aligned deadlines with synchronized evaluation
- **Example**: "Maintain 10,000 points earned this calendar year"
- **Window**: Custom period based on window_start + window_months
- **Deadline**: End of period (e.g., December 31 for annual)
- **Execution**: Single evaluation at period end
- **Key Insight**: All users evaluated together at the same time

##### ❌ Invalid Combinations for Maintain:
- **Realtime + Any Window**: Cannot evaluate maintenance in realtime (paradox - no trigger if user inactive)
- **Fixed Period + Daily/Monthly**: Illogical - fixed periods should evaluate at period end
- **Calendar Month/Quarter + Non-Period-End**: Must use period_end frequency
- **Anniversary + Any Frequency**: Not supported for maintain conditions

### Buyer vs Seller Logic
The `user_type` field in both `tier_master` and `user_accounts` determines tier applicability:

**Buyer type users**:
- For sales/orders metrics: System counts `purchase_ledger` records where `user_id` matches the user
- For points/tickets metrics: System counts `wallet_ledger` records for the user

**Seller type users**:
- For sales/orders metrics: System counts `purchase_ledger` records where `seller_id` matches the user
- For points/tickets metrics: System counts `wallet_ledger` records for the user

### Persona-Based Tier Segmentation (v4.2)

**NEW**: Tiers can now filter by persona in addition to user_type. Both dimensions are **optional and independent**, enabling flexible customer segmentation.

#### Independent Optional Dimensions

The tier system supports four filtering modes:

| user_type | persona_id | Applies to | Example |
|-----------|-----------|------------|---------|
| 'buyer' | NULL | **All buyers** regardless of persona | "Gold Buyer" tier |
| 'seller' | NULL | **All sellers** regardless of persona | "Platinum Seller" tier |
| NULL | 'sme-uuid' | **All users with SME persona** (buyers AND sellers) | "SME VIP" tier |
| 'buyer' | 'corp-uuid' | **Only buyers with Corporation persona** | "Corporate Buyer Elite" tier |
| NULL | NULL | **Universal tier** applying to all users | "Welcome Bronze" tier |

#### Tier Matching Logic

When evaluating which tiers apply to a user:

```sql
WHERE tm.merchant_id = p_merchant_id
  AND (tm.user_type = v_user_type OR tm.user_type IS NULL)  -- NULL = all types
  AND (tm.persona_id = v_user_persona_id OR tm.persona_id IS NULL)  -- NULL = all personas
```

**Key Behavior**:
- **NULL is a wildcard** that matches everything
- A user with persona 'SME' will match:
  - Tiers with `persona_id = 'SME'` (persona-specific)
  - Tiers with `persona_id = NULL` (applies to all personas)
- A user without persona (persona_id = NULL) will match:
  - **Only** tiers with `persona_id = NULL` (general tiers)
  - Will NOT match persona-specific tiers

#### Example Tier Configurations

**Scenario 1: Multi-tier loyalty program with persona specialization**
- "Bronze" (user_type='buyer', persona_id=NULL) → All buyers
- "Silver" (user_type='buyer', persona_id=NULL) → All buyers
- "Gold" (user_type='buyer', persona_id=NULL) → All buyers
- "SME Platinum" (user_type='buyer', persona_id='sme-uuid') → Additional tier for SME buyers
- "Enterprise Diamond" (user_type='buyer', persona_id='enterprise-uuid') → Additional tier for Enterprise buyers

**Scenario 2: Dealer tiers across buyer/seller types**
- "Tier 1 Dealer Elite" (user_type=NULL, persona_id='tier1-dealer-uuid') → All Tier 1 Dealers (buyers AND sellers)
- "Tier 2 Dealer Premium" (user_type=NULL, persona_id='tier2-dealer-uuid') → All Tier 2 Dealers (buyers AND sellers)

**Scenario 3: Universal entry tier**
- "Welcome Bronze" (user_type=NULL, persona_id=NULL) → Every user in the merchant, regardless of type or persona

#### Entry Tier Considerations

Entry tiers can be defined per segment combination:
- Entry tier for all buyers: `user_type='buyer', persona_id=NULL, entry_tier=true`
- Entry tier for SME buyers: `user_type='buyer', persona_id='sme-uuid', entry_tier=true`
- Entry tier for all users: `user_type=NULL, persona_id=NULL, entry_tier=true`

The system will assign the most specific matching entry tier when a user signs up or is created.

### Calculation Sources
Based on the `metric` field in `tier_conditions`:

| Metric | Data Source | Calculation Logic |
|--------|-------------|-------------------|
| `points` | `wallet_ledger` | `SUM(amount) WHERE currency='points' AND transaction_type='earn'` |
| `ticket` | `wallet_ledger` | `SUM(amount) WHERE currency='ticket' AND transaction_type='earn'` |
| `sales` | `purchase_ledger` | `SUM(final_amount)` with credit/debit handling |
| `orders` | `purchase_ledger` | `COUNT(*) WHERE final_amount > 0` (excludes refunds) |

### Ranking System
The `ranking` field in `tier_master` serves dual purposes:

- **Upgrade conflicts**: When a user qualifies for multiple tiers simultaneously, assign the highest-ranked tier
- **Downgrade targeting**: When downgrading, find the highest-ranked tier below the current tier that the user qualifies for

**IMPORTANT**: Tier progression is NOT adjacent - users can skip tiers if they qualify for higher ones.

### Downgrade Logic and Maintenance Deadline Tracking

#### Downgrade Triggers
- There is no explicit 'downgrade' condition type
- Downgrade occurs when: User fails to meet 'maintain' conditions for their current tier by the maintenance deadline
- System automatically downgrades to the highest tier below current tier that the user qualifies for
- If no lower tier conditions are met, user returns to entry tier

#### Maintenance Deadline Management
The system tracks maintenance deadlines through the `tier_evaluation_tracking` table:

**For Calendar Month** **[NEW]**:
- Deadline = End of **current** month when tier achieved (harsh), then auto-advances monthly
- Example: User upgrades to Silver on March 15, 2026 with calendar_month maintain
- First Deadline: March 31, 2026 (only 16 days to maintain!)
- After passing March 31 check: Deadline auto-advances to April 30, 2026
- After passing April 30 check: Deadline auto-advances to May 31, 2026
- Pattern: Continuous monthly evaluation with harsh initial deadline
- Evaluation: System checks if user earned required amount in that calendar month (e.g., March 1-31)

**For Calendar Quarter** **[NEW]**:
- Deadline = End of **current** quarter when tier achieved (harsh), then auto-advances quarterly
- Example: User upgrades to Gold on May 15, 2026 (Q2) with calendar_quarter maintain
- First Deadline: June 30, 2026 (only 45 days to maintain!)
- After passing June 30 check: Deadline auto-advances to September 30, 2026 (Q3)
- After passing September 30 check: Deadline auto-advances to December 31, 2026 (Q4)
- Pattern: Quarterly evaluation aligned with business cycles
- Evaluation: System checks if user earned required amount in that quarter (e.g., Q2: April 1 - June 30)

**For Rolling Windows**:
- Deadline = tier_achieved_at + window_months
- Example: User upgrades to Gold on March 15, 2024 with 6-month rolling maintain condition
- Deadline: September 15, 2024
- Evaluation: System checks if user earned required amount between March 15 - September 15
- After passing: Deadline auto-advances to March 15, 2025 (adds another 6 months)

**For Fixed Periods**:
- Deadline = Next occurrence of (window_start + window_months)
- Example: User upgrades to Gold on July 20, 2024 with annual maintain (01-01, 12 months)
- Deadline: December 31, 2024
- Evaluation: System checks if user earned required amount between January 1 - December 31, 2024
- After passing: Deadline auto-advances to December 31, 2025

**Deadline Auto-Advancement (Universal)**:
- After EVERY maintain evaluation, system recalculates next deadline via `calculate_maintain_deadline(tier_id, evaluation_date)`
- This works for ALL window types - no special logic needed per type
- Stored in `tier_evaluation_tracking.maintain_deadline` for cron job filtering

**Key Architecture Point**: 
- Upgrade conditions check source tables directly (wallet_ledger, purchase_ledger)
- Maintain conditions use tier_evaluation_tracking to determine WHEN to check
- Both use the same evaluation functions (`evaluate_user_tier_status`) for the actual calculation

### Progress Tracking
The `tier_progress` table maintains real-time progress information:

- **One record per user per merchant**: Each user has exactly one progress record that tracks their current status
- Updated on each qualifying transaction (purchase or currency change)
- **Best Path Selection**: When multiple upgrade paths exist (multiple conditions per tier), the system automatically selects and displays the condition with the highest `progress_percent`
- **Dynamic Path Switching**: As different conditions progress at different rates, the displayed "best path" may switch between conditions (e.g., from points-based to sales-based progress). This switching behavior is intentional and beneficial - it ensures users always see their most promising opportunity to advance
- **User Experience**: Shows the most achievable path ("Earn 500 more points by Dec 31 to reach Gold" vs "Spend 20,000 more THB by Dec 31 to reach Gold")
- Used for reminder notifications and engagement campaigns

Progress updates occur through:
- Real-time triggers: On new records in `purchase_ledger` or `wallet_ledger`
- Daily reconciliation cron: Ensures data accuracy and catches any missed updates

### Reversal Handling
Reversals (refunds, point deductions) trigger immediate re-evaluation:

- System checks if the user's current tier conditions relate to the reversed metric
- If related, performs immediate tier evaluation
- For purchase refunds: Creates negative `final_amount` debit records in `purchase_ledger`
- For point reversals: Creates records with `component='reversal'` in `wallet_ledger`
- Calculations sum all records including negative values (no record modification)

### Tier Locking
Manual tier assignments can include downgrade protection:

- `tier_lock_downgrade=true` prevents automatic downgrades
- `tier_locked_downgrade_until` sets expiry for the lock
- Upgrades still process normally during lock period
- Prevents immediate downgrade of manually promoted users

### Initial Setup

- On user signup: Create `tier_progress` record with entry-level tier
- Entry tier must be designated in the system (see requirements below)

---

## Technical Implementation

### Architectural Overview

#### Event-Driven CDC + Render Consumer + Inngest Architecture (v4.0)

The tier system employs a sophisticated **event-driven architecture** using **Change Data Capture (CDC)** with a **Render-hosted Kafka consumer** for event processing and **Inngest** for workflow orchestration. This architecture separates **upgrade processing** (real-time via Kafka consumer) from **maintain/downgrade processing** (batch via pg_cron).

##### Architecture Evolution

| Version | Architecture | Limitations |
|---------|-------------|-------------|
| v1.0 | Synchronous triggers | Slow transactions |
| v2.0 | PGMQ + 30-sec processor | Sequential processing bottleneck |
| v3.0 | CDC → QStash → Bulk Edge Functions | Limited workflow control |
| **v4.0** | CDC → Render Consumer → Inngest | **Current: Flexible upgrade timing + Scalable batch** |

##### Core Architectural Principles

**1. Change Data Capture (CDC) Layer**
- **Confluent CDC Connector**: Debezium-based PostgreSQL source connector
- **Tables Monitored**: `purchase_ledger`, `wallet_ledger`
- **Event Types**: INSERT, UPDATE operations (DELETE skipped for tier evaluation)
- **Kafka Topics**: Durable message storage with replay capability

**2. Render Consumer (Tier Evaluation)**
- **Purpose**: Consumes CDC events from Kafka, evaluates tier status, orchestrates upgrades
- **Deduplication Strategy**: Redis-based, 5-minute window per user+merchant (dedup only, not pending state)
- **No Pending State Tracking**: Inngest workflow state IS the pending state
- **Dual Processing Path**:
  - **Immediate upgrades**: Cancel any pending → apply directly via `apply_tier_upgrade()` RPC
  - **Delayed upgrades**: Cancel any pending → publish to Inngest (workflow state IS the pending state)

**3. Inngest Workflow Orchestration (Delayed Upgrades)**
- **Purpose**: Manages delayed tier upgrades with precise timing
- **Key Features**:
  - `sleepUntil()`: Pauses workflow until effective date - **Inngest IS the pending state**
  - `cancelOn`: Automatically cancels workflow via event matching (no database lookup needed)
  - **Point-in-Time Evaluation**: Re-evaluates user at effective date, not qualification date
- **Workflow**: `tier-upgrade` function in `inngest-tier-serve` Edge Function
- **No Pending Table**: Workflow state replaces need for `pending_tier_upgrades` table

**4. Batch Processing (Maintains/Downgrades)**
- **pg_cron Jobs**: Daily/monthly evaluation of maintenance conditions
- **Chunked Processing**: 1,000 users per chunk for scalability
- **Database Functions**: `evaluate_and_apply_chunk()` handles bulk operations

##### Why This Architecture?

**Previous Architecture (QStash-only) Limitations**:
- No native workflow orchestration for delayed upgrades
- Limited control over upgrade timing
- Evaluation timing locked to qualification time

**CDC + Render + Inngest Benefits**:
- **Flexible Upgrade Timing**: Immediate, end-of-month, fixed-date, or rolling-days
- **Point-in-Time Evaluation**: Delayed upgrades re-evaluate at effective date
- **Cancellation Support**: Pending upgrades cancelled if user no longer qualifies
- **Separation of Concerns**: Upgrades via consumer, maintains via batch
- **Observability**: Full visibility into pending upgrades and workflow status

##### Key Architecture Pattern

```mermaid
graph TB
    subgraph DataSources[Data Sources]
        PL[purchase_ledger]
        WL[wallet_ledger]
    end
    
    subgraph CDC[Change Data Capture]
        PL --> Debezium[Confluent CDC Connector]
        WL --> Debezium
        Debezium --> Kafka[Kafka Topics]
    end
    
    subgraph RenderConsumer[Render Consumer - crm-event-processors]
        Kafka --> Consumer[Kafka Consumer]
        Consumer --> Redis[Redis Dedup Only]
        Redis --> EvalRPC[evaluate_user_tier_status RPC]
        EvalRPC --> CancelFirst[Cancel any pending via Inngest]
        CancelFirst --> Decision{Upgrade Type?}
        Decision -->|Immediate| DirectApply[apply_tier_upgrade RPC]
        Decision -->|Delayed| InngestPublish[Publish tier/upgrade to Inngest]
    end
    
    subgraph InngestWorkflow[Inngest - Delayed Upgrades]
        InngestPublish --> TierUpgrade[tier-upgrade workflow]
        TierUpgrade --> Sleep[sleepUntil effective_at<br/>Inngest IS the pending state]
        Sleep --> ReEval[Re-evaluate tier status]
        ReEval --> ApplyOrCancel{Still qualifies?}
        ApplyOrCancel -->|Yes| ApplyUpgrade[apply_tier_upgrade RPC]
        ApplyOrCancel -->|No| WorkflowEnds[Workflow ends naturally]
    end
    
    subgraph Database[Supabase Database]
        DirectApply --> UA[user_accounts UPDATE]
        ApplyUpgrade --> UA
        DirectApply --> TCL[tier_change_ledger INSERT]
        ApplyUpgrade --> TCL
    end
    
    subgraph BatchProcessing[Batch - Maintains/Downgrades]
        Cron[pg_cron Daily] --> BatchEval[evaluate_and_apply_chunk RPC]
        BatchEval --> UA
        BatchEval --> TCL
    end
    
    subgraph Cancellation[Cancellation Flow]
        CancelFirst -->|Always cancel first| CancelEvent[Publish tier/upgrade-cancelled]
        CancelEvent --> InngestCancel[Inngest cancelOn: user_id + merchant_id]
        InngestCancel -->|Cancels any sleeping workflow| TierUpgrade
    end
```

**Critical Design Features**:

1. **CDC-Driven Upgrades**: Database changes automatically trigger tier evaluations via Kafka consumer
2. **Flexible Upgrade Timing**: Support for immediate, end-of-month, fixed-date, and rolling-days delays
3. **Point-in-Time Evaluation**: Delayed upgrades re-evaluate user's status at effective date
4. **Automatic Cancellation**: If user loses qualification before effective date, Inngest `cancelOn` terminates workflow
5. **Separation of Concerns**: 
   - **Upgrades**: Render consumer + Inngest (real-time + delayed)
   - **Maintains/Downgrades**: pg_cron batch processing
6. **No Pending Table or Redis Needed**: Inngest workflow state IS the pending state
7. **Full Observability**: Inngest dashboard for workflow status (Redis only for dedup)

##### Upgrade Processing Flow

| Scenario | Flow |
|----------|------|
| **Immediate Upgrade** | Consumer → `evaluate_user_tier_status()` → Cancel any pending → `apply_tier_upgrade()` → Done |
| **Delayed Upgrade** | Consumer → `evaluate_user_tier_status()` → Cancel any pending → Publish to Inngest → `sleepUntil()` → Re-evaluate → Apply or End |
| **Cancellation** | Consumer detects user no longer qualifies → Publish `tier/upgrade-cancelled` (user_id + merchant_id) → Inngest `cancelOn` terminates workflow |
| **Superseding** | Handled automatically: Cancel any existing pending → Publish new upgrade event (if delayed) or apply (if immediate) |

##### Maintain/Downgrade Processing Flow

| Processing Type | Trigger | Function |
|-----------------|---------|----------|
| **Daily Maintain Check** | pg_cron at 2 AM | `evaluate_and_apply_chunk()` |
| **End-of-Period Check** | pg_cron at period end | `evaluate_and_apply_chunk()` |
| **Downgrade** | Failed maintain conditions | `evaluate_and_apply_chunk()` → Downgrade to highest qualifying lower tier |

## System Flow Diagrams

### Primary User Journey Flow

```mermaid
graph TD
    A[👤 New User Signup] --> B[assign_entry_tier_on_signup]
    B --> C[🥉 Bronze Tier Assigned]
    C --> D[after_user_signup_tier_setup]
    D --> E[📊 tier_progress Created]
    D --> F[📝 tier_change_ledger Entry]
    
    G[💳 Purchase Completed] --> H[trigger_tier_eval_on_purchase]
    I[💰 Points Earned] --> J[trigger_tier_eval_on_wallet]
    
    H --> K[safe_trigger_tier_eval]
    J --> K
    K --> L[queue_tier_evaluation]
    
    L --> M{Deduplication Check<br/>30 second window}
    M -->|Already Queued| N[❌ Skip Silently]
    M -->|New Request| O[📬 pgmq.send<br/>tier_evaluation_queue]
    O --> P[tier_evaluation_tracking<br/>status = queued]
    
    Q[🕐 process-tier-queue<br/>Every 30 seconds] --> R[process_tier_evaluation_batch<br/>batch_size: 2000]
    S[🕑 daily-tier-evaluation<br/>2 AM daily] --> T[Queue users with<br/>frequency = daily]
    U[🗓️ monthly-tier-evaluation<br/>3 AM monthly] --> V[Queue users with<br/>frequency = monthly]
    W[⏰ period-end-tier-evaluation<br/>4 AM daily] --> X[Queue users with<br/>deadlines today]
    
    T --> O
    V --> O
    X --> O
    
    R --> Y[pgmq.read messages]
    Y --> Z[evaluate_user_tier_status<br/>🎯 CORE FUNCTION]
    
    Z --> AA[calculate_tier_metric_value<br/>🎯 CORE FUNCTION]
    AA --> BB{Metric Type}
    BB -->|points/tickets| CC[wallet_ledger<br/>transaction_type = earn]
    BB -->|sales| DD[purchase_ledger<br/>credit/debit logic]
    BB -->|orders| EE[purchase_ledger<br/>COUNT final_amount > 0]
    
    CC --> FF[calculate_tier_window_dates<br/>🎯 CORE FUNCTION]
    DD --> FF
    EE --> FF
    FF --> GG{Window Type}
    GG -->|rolling| HH[Last N months from today]
    GG -->|fixed_period| II[Calendar periods MM-DD]
    GG -->|anniversary| JJ[User signup anniversary]
    
    HH --> KK[🧠 Tier Decision Logic<br/>CAN SKIP TIERS]
    II --> KK
    JJ --> KK
    
    KK --> LL{Evaluation Result}
    LL -->|upgrade| MM[🚀 HIGHEST qualified tier<br/>Can skip intermediate]
    LL -->|downgrade| NN[⬇️ HIGHEST qualifying lower<br/>or entry tier]
    LL -->|maintain| OO[➡️ Keep current tier]
    LL -->|assign_entry| PP[🆕 Assign Bronze tier]
    
    MM --> QQ[ensure_tier_progress<br/>🎯 CORE FUNCTION]
    NN --> QQ
    OO --> QQ
    PP --> QQ
    
    QQ --> RR{Tier Change Required?}
    RR -->|Yes| SS[📝 tier_change_ledger INSERT]
    RR -->|Yes| TT[🔄 user_accounts.tier_id UPDATE]
    RR -->|No| UU[📊 tier_progress UPDATE only]
    
    SS --> VV[📦 pgmq.archive message]
    TT --> VV
    UU --> VV
    
    style A fill:#e3f2fd
    style C fill:#8d6e63,color:#fff
    style O fill:#f3e5f5
    style Z fill:#e8f5e8
    style QQ fill:#e1f5fe
    style MM fill:#4caf50,color:#fff
    style NN fill:#f44336,color:#fff
    style OO fill:#ff9800,color:#fff
    style PP fill:#2196f3,color:#fff
```

### Tier Progression Logic & Data Architecture

```mermaid
graph LR
    subgraph "🏆 Tier Hierarchy - NON-ADJACENT PROGRESSION"
        T1[🥉 Bronze<br/>Entry Tier<br/>No Requirements]
        T2[🥈 Silver<br/>500 pts/6mo OR 10 tickets/6mo<br/>300 pts/12mo maintain]
        T3[🥇 Gold<br/>1500 pts/6mo OR 100k sales/6mo<br/>1000 pts/12mo maintain]
        T4[💎 Platinum<br/>5000 pts/6mo OR 20 orders/6mo<br/>3000 pts/12mo maintain]
        T5[💍 Diamond<br/>10000 pts/6mo OR 500k sales/12mo<br/>7500 pts/12mo maintain]
        
        T1 -.->|Can skip to| T3
        T1 -.->|Can skip to| T4
        T1 -.->|Can skip to| T5
        T1 --> T2
        T2 --> T3
        T2 -.->|Can skip to| T4
        T2 -.->|Can skip to| T5
        T3 --> T4
        T3 -.->|Can skip to| T5
        T4 --> T5
    end
    
    subgraph "📊 Data Sources"
        DS1[wallet_ledger<br/>💰 Points/Tickets<br/>WHERE transaction_type = earn<br/>SUM amount]
        DS2[purchase_ledger<br/>🛒 Sales: SUM final_amount<br/>📦 Orders: COUNT final_amount > 0<br/>Handles credit/debit records]
        DS3[user_accounts<br/>👤 Current Tier Assignment<br/>🔒 Tier Lock Status<br/>📅 Anniversary Dates]
    end
    
    subgraph "⏰ Window Calculation Engine"
        W1[🔄 Rolling<br/>Last N months from today<br/>Dynamic evaluation period]
        W2[📅 Fixed Period<br/>MM-DD format start dates<br/>Calendar-based periods]
        W3[🎂 Anniversary<br/>User-specific periods<br/>Based on signup date]
    end
    
    subgraph "🧮 Core Evaluation Engine"
        E1[evaluate_user_tier_status<br/>🎯 CORE ORCHESTRATOR<br/>Master decision engine]
        E2[calculate_tier_metrics_bulk<br/>🎯 CORE OPTIMIZER<br/>Batch processing engine]
        E3[calculate_tier_metric_value<br/>🎯 CORE CALCULATOR<br/>Individual metric engine]
        
        E1 --> E3
        E2 --> E3
    end
    
    subgraph "🔄 Processing Outcomes"
        P1[🚀 UPGRADE<br/>HIGHEST qualified tier<br/>Can skip intermediate tiers]
        P2[⬇️ DOWNGRADE<br/>HIGHEST qualifying lower tier<br/>or entry tier fallback]
        P3[➡️ MAINTAIN<br/>Keep current tier<br/>Update progress only]
        P4[🆕 ASSIGN_ENTRY<br/>New user without tier<br/>Assign entry_tier = true]
    end
    
    subgraph "📬 Queue Infrastructure"
        Q1[🎯 tier_evaluation_queue<br/>Main processing queue<br/>Deduplication: 30 seconds<br/>Batch size: 2000]
        Q2[⚡ Real-time Triggers<br/>• Purchase completed<br/>• Points earned<br/>• Tickets earned]
        Q3[⏰ Scheduled Jobs<br/>• Daily evaluations<br/>• Monthly evaluations<br/>• Period-end checks]
        
        Q2 --> Q1
        Q3 --> Q1
    end
    
    DS1 --> E1
    DS2 --> E1
    DS3 --> E1
    
    W1 --> E3
    W2 --> E3
    W3 --> E3
    
    E1 --> P1
    E1 --> P2
    E1 --> P3
    E1 --> P4
    
    subgraph "💾 Output Tables"
        O1[tier_progress<br/>📈 Real-time progress<br/>upgrade_progress_percent<br/>maintain_progress]
        O2[tier_change_ledger<br/>📝 Complete audit trail<br/>from_tier_id → to_tier_id<br/>change_type, metadata]
        O3[tier_evaluation_tracking<br/>⚙️ Queue processing status<br/>last_queued_at<br/>processing_status]
        O4[tier_evaluation_errors<br/>🚨 Error logging<br/>error_message<br/>context jsonb]
    end
    
    P1 --> O1
    P1 --> O2
    P2 --> O1
    P2 --> O2
    P3 --> O1
    P4 --> O1
    P4 --> O2
    
    Q1 --> O3
    Q1 --> O4
    
    style T1 fill:#8d6e63,color:#fff
    style T2 fill:#9e9e9e,color:#fff
    style T3 fill:#ffb300,color:#fff
    style T4 fill:#e1bee7
    style T5 fill:#b39ddb
    
    style DS1 fill:#e8f5e8
    style DS2 fill:#e3f2fd
    style DS3 fill:#fff3e0
    
    style P1 fill:#e1f5fe
    style P2 fill:#ffebee
    style P3 fill:#f9fbe7
    style P4 fill:#f3e5f5
    
    style Q1 fill:#fce4ec
    style E1 fill:#e0f2f1
```

### Key Concepts Glossary

#### Transaction Types
- **Earn**: Currency/points awarded to user (INCLUDED in tier evaluation)
- **Burn**: Currency/points spent by user for rewards (EXCLUDED from tier evaluation)
- **Reversal**: Correction/refund transaction (earn type with negative signed_amount, INCLUDED in tier evaluation)

#### Currency Components
- **Base**: Standard earning from purchases (rate-based calculation)
- **Bonus**: Additional earning from multipliers and campaigns
- **Adjustment**: Manual corrections by administrators
- **Reversal**: Refund/correction transactions (negative signed_amount but positive amount)

#### Window Types
- **Calendar Month**: Current calendar month (e.g., "January 1-31", "February 1-28/29") - Auto-handles month lengths
- **Calendar Quarter**: Current calendar quarter (e.g., "Q1: Jan-Mar", "Q2: Apr-Jun", "Q3: Jul-Sep", "Q4: Oct-Dec")
- **Rolling**: Dynamic lookback from evaluation date (e.g., "last 6 months from today")
- **Fixed Period**: Custom date-based periods (e.g., "June 15 - December 14" or annual "January 1 - December 31")
- **Anniversary**: User-specific periods based on signup date (e.g., "March 15 - March 14 for user who joined March 15")

#### Evaluation Frequencies
- **Realtime**: Immediate evaluation on transaction events (most responsive)
- **Daily**: Scheduled evaluation once per day via cron (resource-efficient)
- **Monthly**: Scheduled evaluation once per month via cron (batch processing)
- **Period End**: Evaluation only at window expiration (anniversary/fixed period end)

#### Record Types (Purchase Ledger)
- **Credit**: Normal purchase transactions (positive final_amount)
- **Debit**: Refund transactions (positive final_amount but treated as negative in calculations)

---

## Function Categories & Architecture

### 🎯 CORE FUNCTIONS (Business Logic Orchestrators)

#### `evaluate_user_tier_status(user_id, merchant_id, evaluation_date)`
**Purpose**: Master tier evaluation engine that determines tier changes - **used for BOTH upgrade and maintain evaluations**  
**Category**: Core Business Logic Orchestrator  
**Returns**: JSONB with evaluation results, recommendations, **and upgrade timing information**
**Fixed in v4.1**: Now properly respects window_type (previously ignored, causing all evaluations to use rolling windows)

**Return Fields** (key fields):
| Field | Type | Description |
|-------|------|-------------|
| `recommended_action` | text | 'upgrade', 'downgrade', 'maintain', or 'assign_entry' |
| `recommended_tier_id` | uuid | Target tier for upgrade/downgrade |
| `to_tier_ranking` | smallint | Ranking of recommended tier |
| `upgrade_timing` | text | Delay type: NULL, 'end_of_month', 'fixed_date', 'rolling_days' |
| `upgrade_timing_value` | text | Configuration value for timing |
| `effective_at` | date | Calculated effective date for delayed upgrades |

**Unified Evaluation for Upgrade and Maintain**:
- Same function handles both condition types
- For upgrades: Evaluates against higher tier conditions directly from source tables
- For maintains: Called when tier_evaluation_tracking indicates deadline reached
- **Window calculation**: Uses `calculate_tier_window_dates()` to properly respect window_type (fixed in v4.1)
- Returns upgrade timing configuration when upgrade is recommended

**Detailed Logic Flow**:
1. **Current Tier Lookup**: Retrieves current tier from `user_accounts` joined with `tier_master`
2. **Entry Tier Assignment**: If no current tier, finds and assigns entry tier (`entry_tier = true`)
3. **Metric Calculation**: Calculates all metrics for appropriate windows based on condition configuration
4. **Maintenance Evaluation**: Checks all maintain conditions for current tier (if deadline reached)
5. **Upgrade Evaluation**: Identifies best upgrade opportunities from higher tiers
6. **Decision Logic**: Determines recommended action (upgrade/downgrade/maintain/assign_entry)
7. **Timing Calculation** (NEW): If upgrade recommended, calculates `effective_at` using `calculate_upgrade_effective_date()`

**Key Business Rules Implementation**:
```sql
-- Points/Tickets (wallet_ledger evaluation)
WHERE currency = 'points' 
  AND transaction_type = 'earn'  -- Excludes burn transactions
  AND created_at >= evaluation_date - INTERVAL '6 months'

-- Sales (purchase_ledger evaluation with credit/debit handling)
SUM(CASE 
  WHEN record_type = 'credit' THEN final_amount
  WHEN record_type = 'debit' THEN -ABS(final_amount)
END)

-- Orders (purchase_ledger count excluding refunds)
COUNT(*) WHERE final_amount > 0  -- Don't count refunds as orders
```

#### `ensure_tier_progress(user_id, merchant_id)`
**Purpose**: Progress management and tier change execution  
**Category**: Core Business Logic Orchestrator  
**Returns**: void (performs updates)

**Comprehensive Responsibilities**:
1. **Current State Assessment**: Gets current tier from `user_accounts`
2. **Tier Evaluation**: Calls `evaluate_user_tier_status` for current assessment
3. **Next Tier Calculation**: Determines next achievable tier based on ranking
4. **Progress Updates**: Updates `tier_progress` with current progress percentages
5. **Tier Change Execution**: If recommended tier differs from current tier
6. **Maintenance Deadline Setting** (NEW): On upgrade, calculates and stores maintenance deadline in `tier_evaluation_tracking`
7. **Progress Calculation Logic**:
   ```sql
   -- Upgrade Progress
   upgrade_progress = (current_points_6mo / upgrade_threshold) * 100
   
   -- Maintenance Progress (can exceed 100%)
   maintain_progress = (current_points_12mo / maintenance_threshold) * 100
   ```

**Critical for Maintenance**: When user upgrades, this function:
- Calls `calculate_maintain_deadline()` to determine when maintenance evaluation should occur
- Stores deadline in `tier_evaluation_tracking` for cron job processing
- Updates `tier_progress.maintain_deadline` for display purposes

#### `calculate_tier_metric_value(user_id, metric, window_start, window_end, user_type)`
**Purpose**: Individual metric calculation engine  
**Category**: Core Calculation Engine  
**Returns**: NUMERIC value for specified metric

**Metric-Specific Implementation Logic**:

**Points/Tickets Calculation**:
```sql
WHEN p_metric IN ('points', 'ticket') THEN
  SELECT COALESCE(SUM(amount), 0)
  FROM wallet_ledger
  WHERE user_id = p_user_id
    AND currency = p_metric
    AND transaction_type = 'earn'  -- CRITICAL: Only earn transactions
    AND created_at >= p_window_start
    AND created_at < p_window_end + INTERVAL '1 day'
```

**Sales Calculation**:
```sql
WHEN p_metric = 'sales' THEN
  SELECT COALESCE(SUM(final_amount), 0)  -- Handles negative amounts for refunds
  FROM purchase_ledger
  WHERE merchant_id = p_merchant_id
    AND CASE 
      WHEN p_user_type = 'buyer' THEN user_id = p_user_id
      WHEN p_user_type = 'seller' THEN seller_id = p_user_id
    END
    AND created_at >= p_window_start
    AND created_at < p_window_end + INTERVAL '1 day'
```

### 🖥️ RENDER CONSUMER (Upgrade Processing)

#### `crm-event-processors` Service
**Purpose**: Kafka consumer for real-time tier evaluation and upgrade orchestration  
**Category**: Event Processor  
**Platform**: Render Web Service  
**Runtime**: Node.js + TypeScript

**Key Components**:

| File | Purpose |
|------|---------|
| `src/consumers/tier-consumer.ts` | Main Kafka consumer logic |
| `src/clients/kafka.ts` | Kafka client + Debezium parsing |
| `src/clients/supabase.ts` | Supabase RPC calls |
| `src/clients/redis.ts` | Redis deduplication |
| `src/clients/inngest.ts` | Inngest event publishing |

**Processing Flow**:
```typescript
// 1. Consume message from Kafka
const debezium = parseDebeziumMessage(message.value);

// 2. Redis deduplication (5-minute window) - ONLY for dedup, not pending state
const duplicate = await isDuplicate(tierDedupKey(userId, merchantId), 300);
if (duplicate) return;

// 3. Evaluate tier status
const result = await evaluateUserTier(userId, merchantId);

// 4. Handle based on recommendation
if (result.recommended_action === 'upgrade' && result.recommended_tier_id) {
  // ALWAYS cancel any existing pending first (handles superseding)
  await publishToInngest('tier/upgrade-cancelled', { user_id: userId, merchant_id: merchantId });
  
  if (result.upgrade_timing && result.effective_at) {
    // DELAYED: Publish to Inngest - workflow state IS the pending state
    await publishToInngest('tier/upgrade', { 
      user_id: userId, 
      merchant_id: merchantId,
      to_tier_id: result.recommended_tier_id,
      to_tier_ranking: result.to_tier_ranking,
      effective_at: result.effective_at
    });
  } else {
    // IMMEDIATE: Apply directly
    await applyTierUpgrade(userId, merchantId, result.recommended_tier_id);
  }
} else if (result.recommended_action === 'maintain' || result.recommended_action === 'downgrade') {
  // Cancel any pending upgrade via Inngest cancelOn
  await publishToInngest('tier/upgrade-cancelled', { user_id: userId, merchant_id: merchantId });
}
```

**Environment Variables**:
| Variable | Purpose |
|----------|---------|
| `KAFKA_BROKERS` | Confluent Cloud bootstrap servers |
| `KAFKA_USERNAME` | API key for Kafka |
| `KAFKA_PASSWORD` | API secret for Kafka |
| `SUPABASE_URL` | Supabase project URL |
| `SUPABASE_SERVICE_ROLE_KEY` | Service role key for RPC calls |
| `REDIS_URL` | Render Redis connection string |
| `INNGEST_EVENT_KEY` | Inngest event publishing key |

### ⚙️ EDGE FUNCTIONS (Workflow Orchestration)

#### `inngest-tier-serve` Edge Function (NEW)
**Purpose**: Hosts Inngest workflows for delayed tier upgrades  
**Category**: Workflow Host  
**Endpoint**: `/functions/v1/inngest-tier-serve`
**JWT**: Disabled (receives from Inngest)

**Workflows Hosted**:

##### `tier-upgrade` Workflow
**Purpose**: Handles delayed tier upgrades with point-in-time evaluation  
**Trigger Event**: `tier/upgrade`  
**Cancel Event**: `tier/upgrade-cancelled` (matched by `user_id + merchant_id` only)

> **Key Architecture**: Inngest workflow state IS the pending state. No `pending_tier_upgrades` table or Redis cache needed.

**Workflow Steps**:
```typescript
const tierUpgrade = inngest.createFunction(
  {
    id: "tier-upgrade",
    // Cancel by user_id + merchant_id only
    // User can only have one pending tier upgrade at a time
    // When new qualification happens: cancel existing → create new (or apply)
    cancelOn: [{
      event: "tier/upgrade-cancelled",
      if: "event.data.user_id == async.data.user_id && event.data.merchant_id == async.data.merchant_id",
    }],
  },
  { event: "tier/upgrade" },
  async ({ event, step }) => {
    const { user_id, merchant_id, to_tier_id, to_tier_ranking, effective_at } = event.data;

    // Step 1: Sleep until scheduled effective date
    // Inngest persists workflow state during sleep
    await step.sleepUntil("wait-for-effective-date", new Date(effective_at));

    // Step 2: Re-evaluate tier status at this point in time
    const evalResult = await step.run("re-evaluate-tier", async () => {
      return await supabase.rpc("evaluate_user_tier_status", {
        p_user_id: user_id,
        p_merchant_id: merchant_id,
      });
    });

    // Step 3: Apply or end based on current qualification
    if (evalResult.recommended_action === "upgrade" && 
        evalResult.to_tier_ranking >= to_tier_ranking) {
      // Still qualifies - apply upgrade
      await step.run("apply-upgrade", async () => {
        await supabase.rpc("apply_tier_upgrade", {
          p_user_id: user_id,
          p_merchant_id: merchant_id,
          p_to_tier_id: evalResult.recommended_tier_id,
        });
      });
      return { status: "applied", to_tier_id: evalResult.recommended_tier_id };
    } else {
      // No longer qualifies - workflow simply ends
      console.log(`User ${user_id} no longer qualifies at effective date`);
      return { status: "cancelled", reason: "no_longer_qualifies" };
    }
  }
);
```

**Key Features**:
- **sleepUntil**: Workflow pauses until exact effective date - Inngest persists state
- **cancelOn by user_id + merchant_id**: User can only have one pending upgrade at a time
- **Point-in-Time Evaluation**: Re-evaluates at effective date, not qualification date
- **No Pending Table or Redis**: Workflow state IS the pending state - simplest architecture
- **Automatic Cleanup**: Workflow completion/cancellation requires no state management

#### `tier-batch-initiator` Edge Function
**Purpose**: Initiates fixed-period batch evaluations for maintains/downgrades  
**Category**: Batch Orchestrator  
**Endpoint**: `/functions/v1/tier-batch-initiator`
**Triggered By**: pg_cron via pg_net

**Batch Publishing Flow**:
1. Query merchants with evaluations due
2. For each merchant, calculate chunk count
3. Invoke `evaluate_and_apply_chunk` for each chunk
4. Log progress to `tier_bulk_chunk_log`

### ⚙️ PROCESSING FUNCTIONS (Database Layer)

#### `evaluate_and_apply_chunk(merchant_id, user_ids, offset, limit, evaluation_date)`
**Purpose**: Unified bulk tier evaluation and application  
**Category**: Bulk Processing Core  
**Returns**: JSONB with processing statistics  
**Timeout**: 60 seconds (SET statement_timeout)

**Dual Mode Operation**:
- **User IDs Mode**: When `p_user_ids` provided (real-time single/batch)
- **Offset/Limit Mode**: When `p_user_ids` is NULL (chunked batch)

**Processing Logic**:
```sql
-- For each user in chunk:
-- 1. Evaluate tier status
v_eval_result := evaluate_user_tier_status(user_id, merchant_id);

-- 2. Apply tier change if needed
IF v_eval_result->>'recommended_action' = 'upgrade' THEN
  UPDATE user_accounts SET tier_id = new_tier;
  INSERT INTO tier_change_ledger (...);
  INSERT INTO tier_evaluation_tracking (...);
END IF;

-- 3. Update progress display
PERFORM ensure_tier_progress(user_id, merchant_id);
```

**Returns**:
```json
{
  "success": true,
  "users_evaluated": 1000,
  "upgrades": 45,
  "downgrades": 12,
  "maintains": 940,
  "entry_assignments": 3,
  "errors": 0,
  "duration_ms": 2340
}
```

#### `get_tier_evaluation_chunks(merchant_id, chunk_size)`
**Purpose**: Calculate chunk distribution for batch processing  
**Category**: Chunk Calculator  
**Returns**: TABLE of chunk information

**Used By**: `tier-batch-initiator` to determine how many chunk messages to publish

#### `start_tier_chunk_processing(merchant_id, evaluation_date, chunk_index, total_chunks, qstash_message_id)`
**Purpose**: Record chunk processing start  
**Category**: Chunk Tracking  
**Returns**: UUID chunk_id

#### `complete_tier_chunk_processing(chunk_id, users_processed, changes_applied, success, error_message)`
**Purpose**: Record chunk completion or failure  
**Category**: Chunk Tracking

### 🗑️ DEPRECATED FUNCTIONS (Legacy Architectures)

The following functions are from previous architectures and should be removed:

#### From PGMQ Architecture (v2.0)
| Function | Replacement |
|----------|-------------|
| `queue_tier_evaluation` | Render Consumer with Redis dedup |
| `process_tier_evaluation_batch` | Render Consumer + Inngest workflows |
| `process_tier_queue_true_bulk` | `evaluate_and_apply_chunk` for batch only |

#### From QStash Architecture (v3.0)
| Function | Replacement |
|----------|-------------|
| `event-router` Edge Function | Render Consumer (`crm-event-processors`) |
| `tier-bulk-process` Edge Function | Render Consumer + Inngest + `apply_tier_upgrade` |
| QStash deduplication | Redis-based deduplication in Render |

**Note**: The batch processing for maintains/downgrades still uses `evaluate_and_apply_chunk` via `tier-batch-initiator`. Only the real-time upgrade path has changed.

### 🔄 TRIGGER FUNCTIONS (Legacy - Replaced by CDC)

> **Note**: The following trigger functions are being replaced by the CDC pipeline. 
> CDC automatically captures all changes to monitored tables without requiring 
> application-side triggers. The triggers below are documented for reference 
> but should be disabled once CDC is fully operational.

#### `trigger_tier_eval_on_purchase()` - DEPRECATED
**Purpose**: Purchase completion event handler  
**Category**: Event Trigger Handler  
**Status**: **DEPRECATED** - Replaced by CDC on `purchase_ledger`
**Trigger**: AFTER INSERT/UPDATE ON `purchase_ledger`

**Activation Logic**:
```sql
-- Only when status changes to 'completed'
IF (TG_OP = 'UPDATE' AND OLD.status != 'completed' AND NEW.status = 'completed')
   OR (TG_OP = 'INSERT' AND NEW.status = 'completed') THEN
```

#### `trigger_tier_eval_on_wallet()` - DEPRECATED
**Purpose**: Wallet transaction event handler  
**Category**: Event Trigger Handler  
**Status**: **DEPRECATED** - Replaced by CDC on `wallet_ledger`
**Trigger**: AFTER INSERT ON `wallet_ledger`

**Selective Activation Logic**:
```sql
-- Critical business rule: Only 'earn' transactions affect tier progression
IF NEW.transaction_type = 'earn' AND NEW.user_id IS NOT NULL THEN
  PERFORM queue_tier_evaluation(
    NEW.user_id, NEW.merchant_id, 
    'wallet_' || NEW.currency::text,  -- 'wallet_points' or 'wallet_ticket'
    NEW.id
  );
END IF;
```

### CDC Event Filtering (New Approach)

The `event-router` Edge Function handles filtering that was previously done in triggers:

```typescript
// Skip delete operations (user/record deleted - no tier eval needed)
if (operation === 'd') {
  return { skipped: true, reason: 'Delete operations do not trigger tier evaluation' };
}

// Skip events without user context
if (!user_id || !merchant_id) {
  return { skipped: true, reason: 'Missing user_id or merchant_id' };
}

// All other events trigger tier evaluation
// (filtering for 'earn' transactions happens in evaluate_user_tier_status)
```

### 🚀 BULK PROCESSING FUNCTIONS (Performance Optimizers)

#### Current Architecture: `evaluate_and_apply_chunk`

The new unified bulk function combines evaluation and application:

**Single Function Approach**:
```sql
-- evaluate_and_apply_chunk handles everything:
-- 1. Get users (by IDs or offset/limit)
-- 2. Evaluate each user's tier status
-- 3. Apply tier changes
-- 4. Log to tier_change_ledger
-- 5. Update tier_evaluation_tracking
-- 6. Update tier_progress for display
```

**Why Combined Function**:
- Reduces round-trips between Edge Function and database
- Atomic transaction for consistency
- 60-second timeout handles 1,000 users comfortably
- Errors logged per-user without stopping batch

#### `ensure_tier_progress(user_id, merchant_id)`
**Purpose**: Progress display update (called within evaluate_and_apply_chunk)  
**Category**: Progress Manager  
**Returns**: void

**Calculates and Updates**:
- `upgrade_progress_percent`: Progress toward next tier
- `maintain_progress`: Progress toward maintenance threshold
- `upgrade_deadline`: When upgrade window closes
- `maintain_deadline`: When maintenance check occurs

#### Future Optimization: True Set-Based Processing

For even larger scale (10M+ users), the architecture supports migration to true set-based processing:

```sql
-- Future: Single query for ALL evaluations
WITH user_metrics AS (
    SELECT user_id, 
           SUM(points_6mo), SUM(points_12mo),
           SUM(sales_6mo), COUNT(orders_6mo)
    FROM wallet_ledger, purchase_ledger
    WHERE user_id = ANY(p_user_ids)
    GROUP BY user_id
),
evaluations AS (
    SELECT user_id, 
           MAX(tier_id) FILTER (WHERE meets_upgrade) as upgrade_tier,
           bool_and(meets_maintain) as maintains_current
    FROM user_metrics
    CROSS JOIN tier_conditions
    GROUP BY user_id
)
-- Bulk update all at once
UPDATE user_accounts ua
SET tier_id = COALESCE(e.upgrade_tier, 
                       CASE WHEN NOT e.maintains_current THEN downgrade_tier END,
                       ua.tier_id)
FROM evaluations e
WHERE ua.id = e.user_id;
```

This would reduce 1,000 user processing from ~2 seconds to ~100ms.

### 🔧 HELPER FUNCTIONS (Supporting Utilities)

#### `calculate_maintain_deadline(tier_id, achieved_date)`
**Purpose**: Calculates when maintenance evaluation should occur for a tier  
**Category**: Maintenance Deadline Calculator  
**Returns**: TABLE(deadline date, window_type, condition_ids[])
**Enhanced in v4.1**: Added calendar_month and calendar_quarter support with harsh deadline behavior

**Logic by Window Type**:
- **Calendar Month**: deadline = end of current month (harsh), then auto-advances to next month-end after each check
- **Calendar Quarter**: deadline = end of current quarter (harsh), then auto-advances to next quarter-end after each check
- **Rolling**: deadline = achieved_date + window_months
- **Fixed Period**: deadline = next occurrence of (window_start + window_months)
- **Anniversary**: achieved_date + window_months (not typically used for maintain)

**Harsh Deadline Examples**:
- Achieved March 15 with calendar_month → Deadline March 31 (only 16 days)
- Achieved May 15 with calendar_quarter → Deadline June 30 (only 45 days)

**Auto-Advancement**: When evaluated ON the deadline date, automatically calculates next period's deadline

**Multiple Conditions**: Returns earliest deadline when tier has multiple maintain conditions

#### `calculate_upgrade_effective_date(timing, value, qualified_at)` (NEW)
**Purpose**: Calculates when a delayed upgrade should take effect  
**Category**: Upgrade Timing Calculator  
**Returns**: DATE

**Logic by Timing Type**:
```sql
CASE p_timing
  WHEN NULL OR 'immediate' THEN
    p_qualified_at
  WHEN 'end_of_month' THEN
    (date_trunc('month', p_qualified_at) + INTERVAL '1 month - 1 day')::DATE
  WHEN 'fixed_date' THEN
    -- p_value format: 'MM-DD'
    -- Returns next occurrence of that date (this year or next)
    make_date(year, month, day)
  WHEN 'rolling_days' THEN
    p_qualified_at + (p_value || ' days')::INTERVAL
END
```

**Usage**: Called by `evaluate_user_tier_status` when upgrade timing is configured.

#### `apply_tier_upgrade(user_id, merchant_id, to_tier_id, pending_id)`
**Purpose**: Applies a tier upgrade and updates related records  
**Category**: Tier Change Executor  
**Returns**: JSONB with upgrade results
**Fixed in v4.1**: Now updates tier_evaluation_tracking (correct table) instead of non-existent columns

**Actions Performed**:
1. Updates `user_accounts.tier_id` to new tier
2. Calculates maintain deadline via `calculate_maintain_deadline()`
3. Stores tracking data in `tier_evaluation_tracking` (tier_achieved_at, maintain_deadline, maintain_window_type)
4. Inserts record into `tier_change_ledger`
5. Returns success status with deadline information

```sql
-- Core logic (v4.1 - FIXED)
UPDATE user_accounts
SET tier_id = p_to_tier_id,
    updated_at = NOW()
WHERE id = p_user_id AND merchant_id = p_merchant_id;

-- Store tracking in correct table
INSERT INTO tier_evaluation_tracking (
    user_id, merchant_id, tier_achieved_at, maintain_deadline,
    maintain_window_type, maintain_condition_ids
) VALUES (...)
ON CONFLICT (user_id, merchant_id) DO UPDATE SET ...;

INSERT INTO tier_change_ledger (
    user_id, merchant_id, from_tier_id, to_tier_id, 
    change_type, change_reason
) VALUES (
    p_user_id, p_merchant_id, v_current_tier, p_to_tier_id, 
    'upgrade', 'Tier upgrade applied'
);
```

#### `calculate_next_period_end(window_start, window_months)`
**Purpose**: Helper to calculate next fixed period end date  
**Category**: Period Calculation Helper  
**Returns**: date of next period end
**Usage**: Used by cron jobs to determine when fixed_period evaluations should run

#### `check_tier_queue_health()`
**Purpose**: System health monitoring and alerting  
**Category**: Monitoring Helper  
**Returns**: TABLE with queue status and recommendations

---

## Automation & Scheduling Architecture

### Event-Driven Processing (Upgrades)

Real-time tier upgrades are triggered automatically via CDC → Kafka → Render Consumer:

```mermaid
sequenceDiagram
    participant DB as PostgreSQL
    participant CDC as Confluent CDC
    participant Kafka as Kafka Topic
    participant Consumer as Render Consumer
    participant Redis as Redis Dedup
    participant Inngest as Inngest
    
    DB->>CDC: INSERT into wallet_ledger
    CDC->>Kafka: CDC Event
    Kafka->>Consumer: Consume message
    Consumer->>Redis: Check deduplication
    Redis-->>Consumer: Not duplicate
    Consumer->>DB: evaluate_user_tier_status()
    
    alt Immediate Upgrade
        Consumer->>DB: apply_tier_upgrade()
        DB-->>Consumer: Done
    else Delayed Upgrade
        Consumer->>DB: INSERT pending_tier_upgrades
        Consumer->>Inngest: Publish tier/upgrade event
        Inngest->>Inngest: sleepUntil(effective_at)
        Note over Inngest: Workflow sleeps until effective date
        Inngest->>DB: Re-evaluate tier status
        alt Still Qualifies
            Inngest->>DB: apply_tier_upgrade()
        else No Longer Qualifies
            Inngest->>DB: Cancel pending upgrade
        end
    end
```

**Deduplication Strategy**:
- Redis-based with 5-minute TTL per user+merchant
- Key format: `tier:dedup:{user_id}:{merchant_id}`
- Result: Multiple rapid events consolidated into single evaluation

### Delayed Upgrade Workflow

```mermaid
sequenceDiagram
    participant Consumer as Render Consumer
    participant DB as PostgreSQL
    participant Inngest as Inngest
    
    Note over Consumer: User qualifies for tier with end_of_month timing
    Consumer->>DB: evaluate_user_tier_status()
    DB-->>Consumer: upgrade_timing=end_of_month, effective_at=2025-12-31
    Consumer->>DB: INSERT pending_tier_upgrades
    Consumer->>Inngest: tier/upgrade event
    
    Note over Inngest: Workflow starts and sleeps
    Inngest->>Inngest: sleepUntil("2025-12-31")
    
    alt User loses qualification before effective date
        Consumer->>DB: User spent points, no longer qualifies
        Consumer->>Inngest: tier/upgrade-cancelled event
        Inngest->>Inngest: cancelOn triggers
        Note over Inngest: Workflow cancelled
        Inngest->>DB: Update pending status = cancelled
    else User maintains qualification
        Note over Inngest: Wake up on effective date
        Inngest->>DB: evaluate_user_tier_status()
        DB-->>Inngest: Still qualifies for upgrade
        Inngest->>DB: apply_tier_upgrade()
        Note over DB: Tier upgraded!
    end
```

### Cron Job Infrastructure - Batch Processing (Maintains/Downgrades)

| Job Name | Schedule | Purpose | Implementation |
|----------|----------|---------|----------------|
| `tier-batch-daily` | `0 2 * * *` | Daily maintain evaluations | Calls `tier-batch-initiator` via pg_net |
| `tier-period-end` | `0 3 * * *` | Period-end maintain evaluations | Checks for period endings today |
| `tier-progress-reconciliation` | `*/30 * * * *` | Progress updates | Lightweight updates for display |
| `cleanup-tier-errors` | `0 5 * * *` | Error cleanup | Housekeeping: Delete errors >30 days old |

**Batch Processing Flow** (Maintains/Downgrades):
```mermaid
sequenceDiagram
    participant Cron as pg_cron
    participant Init as tier-batch-initiator
    participant DB as PostgreSQL
    
    Cron->>Init: HTTP POST (via pg_net)
    Init->>DB: get_tier_evaluation_chunks()
    DB-->>Init: 100 chunks needed
    
    loop For each chunk
        Init->>DB: evaluate_and_apply_chunk(offset, limit)
        Note over DB: Evaluate maintains, apply downgrades
        DB-->>Init: Chunk complete
    end
    
    Init->>DB: Log to tier_bulk_chunk_log
```

**Key Architecture Points**:
- **Upgrades**: Render Consumer + Inngest (real-time with optional delay)
- **Maintains/Downgrades**: pg_cron batch processing
- **Deduplication**: Redis for real-time (dedup only), chunk-based for batch
- **Workflow Control**: Inngest provides sleepUntil, cancelOn for delayed upgrades
- **No Pending State Storage**: Inngest workflow state IS the pending state

### New Tables for Tier Processing

#### `tier_bulk_chunk_log` Table
Tracks progress of chunked bulk tier evaluations:

| Field | Type | Purpose |
|-------|------|---------|
| `id` | uuid | Unique identifier |
| `merchant_id` | uuid | Links to merchant |
| `evaluation_date` | date | Date of evaluation run |
| `chunk_index` | integer | Chunk number (1-based) |
| `total_chunks` | integer | Total chunks in run |
| `status` | text | pending/processing/completed/failed/retrying |
| `users_processed` | integer | Users evaluated in chunk |
| `changes_applied` | integer | Tier changes made |
| `qstash_message_id` | text | QStash tracking ID |
| `error_message` | text | Error details if failed |
| `created_at` | timestamptz | Chunk creation time |
| `started_at` | timestamptz | Processing start time |
| `completed_at` | timestamptz | Processing completion time |

**Unique Constraint**: `(merchant_id, evaluation_date, chunk_index)`

### Workflow Logging

All tier evaluations are logged to `inngest_workflow_log`:

| Field | Type | Purpose |
|-------|------|---------|
| `workflow_type` | text | 'tier_evaluation' |
| `event_name` | text | 'tier/evaluate/single' or 'tier/evaluate/batch_chunk' |
| `status` | text | started/completed/failed |
| `source_type` | text | 'cdc' for real-time, 'batch' for scheduled |
| `user_id` | uuid | User being evaluated (single mode) |
| `merchant_id` | uuid | Merchant context |
| `metadata` | jsonb | Evaluation results and details |

---

## What's New in v4.1

### Key Changes from v4.0

1. **Calendar Window Types Added**
   - `calendar_month`: Evaluates current calendar month (Jan 1-31, Feb 1-28/29, etc.)
   - `calendar_quarter`: Evaluates current calendar quarter (Q1-Q4)
   - Both support harsh deadline behavior for immediate engagement pressure
   - Auto-advancement: Deadlines automatically move to next period after successful maintain checks

2. **Critical Bug Fixes**
   - **evaluate_user_tier_status**: Now properly respects window_type (previously ignored, all evaluations were rolling!)
   - **apply_tier_upgrade**: Now updates tier_evaluation_tracking instead of non-existent columns
   - **calculate_maintain_deadline**: Fixed edge case where deadline didn't advance on exact deadline date
   - **Data cleanup**: Fixed malformed window_start values in existing tier_conditions

3. **Enhanced Deadline Advancement**
   - Universal pattern works for ALL window types (calendar, rolling, fixed_period, anniversary)
   - Harsh option implemented for calendar types (current period end, not next period)
   - Automatic advancement via evaluate_and_apply_chunk recalculation

4. **Production Impact**
   - **Breaking Changes**: None (100% backward compatible)
   - **Existing Conditions**: Now work correctly (bug fixes improve accuracy)
   - **New Features**: Can create monthly/quarterly tiers immediately
   - **Cron Integration**: No changes needed, existing daily cron handles all types

---

## What's New in v4.0

### Key Changes from v3.0

1. **Upgrade Processing Moved to Render Consumer**
   - CDC events consumed directly via Kafka (no more HTTP Sink → Edge Function)
   - Redis-based deduplication (5-minute window, dedup only)
   - Cleaner separation: upgrades via consumer, maintains via batch

2. **Delayed Upgrade Support via Inngest**
   - Configurable upgrade timing: immediate, end_of_month, fixed_date, rolling_days
   - Point-in-time evaluation: re-evaluates at effective date, not qualification date
   - Automatic cancellation: if user loses qualification, workflow is cancelled
   - **No pending table or Redis cache**: Inngest workflow state IS the pending state

3. **New Database Components**
   - `calculate_upgrade_effective_date()`: calculates effective date for delays
   - `apply_tier_upgrade()`: atomic upgrade application with ledger entry
   - `upgrade_evaluation_timing` column on `tier_conditions`

4. **Workflow Cancellation Pattern**
   - When user qualifies for upgrade or no longer qualifies, `tier/upgrade-cancelled` event published first
   - Inngest `cancelOn` matches by `user_id + merchant_id` (user can only have one pending at a time)
   - Prevents stale upgrades and handles superseding automatically

### Migration Notes (v4.0 → v4.1)

**No Migration Required**:
- Calendar month/quarter support added via enum extension only
- All existing tier_conditions continue to work (now work better with bug fixes)
- No data changes needed
- No cron job changes needed

**Bug Fixes Applied Automatically**:
- evaluate_user_tier_status now respects window_type for ALL existing conditions
- Existing fixed_period and anniversary conditions now evaluate correctly
- apply_tier_upgrade now updates correct tables

**To Use New Calendar Types**:
- Create tier_conditions with `window_type = 'calendar_month'` or `'calendar_quarter'`
- Set `window_months = NULL` and `window_start = NULL` for calendar types
- Use `frequency = 'period_end'` (only valid option for calendar types)
- Harsh deadline behavior is automatic (no configuration needed)

### Migration Notes (v3.0 → v4.0)

- Existing immediate upgrades continue to work unchanged
- To enable delayed upgrades, set `upgrade_evaluation_timing` on tier conditions
- Render consumer must have `INNGEST_EVENT_KEY` env var set
- Inngest app must be configured to point to `inngest-tier-serve` Edge Function

---

## Current Production Status & Test Validation

### System Health
- **Total Users**: 13 with complete tier assignments
- **Progress Records**: 13 (100% coverage)
- **Tier Changes**: 25 automatic changes processed
- **Queue Status**: Empty (all messages processed successfully)
- **Health Status**: HEALTHY (normal operation)
- **Error Rate**: 0% (no processing errors)

### Tier Distribution
- **Bronze**: 9 users (including downgrades and new entries)
- **Silver**: 0 users (all qualified users skipped to Gold)
- **Gold**: 3 users (successful tier skipping demonstrated)
- **Platinum**: 1 user (high performer)
- **Diamond**: 0 users (highest tier, requires exceptional performance)

### Tier Progression Validation

| User Type | Points 6mo | Expected Tier | Actual Tier | Progression Type |
|-----------|------------|---------------|-------------|------------------|
| High Performer | 10,000 | Platinum | ✅ Platinum | Bronze → **Skipped Silver & Gold** → Platinum |
| Steady Climber | 1,800 | Gold | ✅ Gold | Bronze → **Skipped Silver** → Gold |
| Edge Case | 1,550 | Gold | ✅ Gold | Bronze → **Skipped Silver** → Gold |
| Ticket User | 600 + 7 tickets | Silver | ✅ Silver | Bronze → Silver (via points) |
| Mixed Metrics | 1,850 + 120k sales | Gold | ✅ Gold | Bronze → **Skipped Silver** → Gold |

### Transaction Type Coverage

**Wallet Transactions by Type**:
- **Points Earn/Base**: 64 transactions (17,250 points) ✅ Included in tier evaluation
- **Points Earn/Bonus**: 8 transactions (5,900 points) ✅ Included in tier evaluation
- **Points Earn/Reversal**: 5 transactions (-250 points) ✅ Correctly included (negative impact)
- **Points Burn/Base**: 2 transactions (-1,200 points) ✅ Correctly excluded (reward redemptions)
- **Tickets Earn**: 6 transactions (26 tickets) ✅ Included in tier evaluation
- **Tickets Burn**: 2 transactions (-5 tickets) ✅ Correctly excluded (ticket redemptions)

### Edge Cases Validated

#### ✅ Tier Skipping Logic
- **Bronze → Platinum**: High Performer earned 6,200 points, qualified for Platinum (5,000 threshold), skipped Gold (1,500 threshold)
- **Bronze → Gold**: Multiple users earned 1,500+ points, skipped Silver (500 threshold)

#### ✅ Maintenance Progress >100%
- **Platinum User**: 206.67% maintenance (6,200 points ÷ 3,000 requirement)
- **Business Logic**: Shows "tier security" - user has earned double the required points
- **Customer Value**: Indicates high-value customers exceeding expectations

#### ✅ Reversal Handling
- **Correct Implementation**: `transaction_type = 'earn'`, `component = 'reversal'`, `signed_amount = negative`
- **Tier Impact**: Properly reduces tier evaluation metrics
- **vs Burn Transactions**: Reward redemptions correctly excluded from tier calculations

The tier management system demonstrates **production-ready reliability** with comprehensive business logic, robust error handling, tier skipping capability, and scalable processing architecture suitable for enterprise-level loyalty programs with complex, multi-path tier progression requirements.

---

## Appendix: Technology Stack

### Core Infrastructure

| Component | Technology | Purpose |
|-----------|------------|---------|
| Database | Supabase (PostgreSQL) | Data storage, RPC functions |
| Edge Functions | Deno Runtime | Inngest workflow hosting, batch initiation |
| CDC | Confluent Cloud | Change Data Capture from PostgreSQL |
| Message Queue | Apache Kafka | Durable event streaming |
| Event Consumer | Render (Node.js) | Kafka consumption, tier evaluation orchestration |
| Workflow Engine | Inngest | Delayed upgrade orchestration with sleepUntil/cancelOn |
| Caching | Render Redis | Deduplication for event processing |
| Scheduling | pg_cron + pg_net | Batch job initiation for maintains/downgrades |

### Render Services

| Service | Purpose | Type |
|---------|---------|------|
| `crm-event-processors` | Kafka consumer for tier evaluation | Web Service |
| `crm-dedup-cache` | Redis for deduplication only (not pending state) | Key-Value Store |

### Edge Functions

| Function | Purpose | JWT |
|----------|---------|-----|
| `inngest-tier-serve` | Hosts Inngest workflows for delayed upgrades | No |
| `tier-batch-initiator` | Initiates batch evaluations for maintains | No |

### Database Functions

| Function | Purpose | Timeout |
|----------|---------|---------|
| `evaluate_user_tier_status` | Core tier evaluation logic (returns timing info) | Default |
| `apply_tier_upgrade` | Applies upgrade and updates ledger | Default |
| `calculate_upgrade_effective_date` | Calculates delayed upgrade effective date | Default |
| `calculate_maintain_deadline` | Calculates maintenance deadline | Default |
| `evaluate_and_apply_chunk` | Bulk evaluation and application for batch | 60s |
| `ensure_tier_progress` | Progress display updates | Default |

### Tables

| Table | Purpose |
|-------|---------|
| `tier_master` | Tier definitions |
| `tier_conditions` | Upgrade/maintain conditions (includes `upgrade_evaluation_timing`) |
| `tier_progress` | User progress display |
| `tier_evaluation_tracking` | Maintenance deadline tracking |
| `tier_change_ledger` | Audit trail |
| `tier_bulk_chunk_log` | Batch chunk tracking |

> **Note**: No `pending_tier_upgrades` table needed - Inngest workflow state IS the pending state.

### Environment Variables

#### Render Consumer (`crm-event-processors`)

| Variable | Purpose |
|----------|---------|
| `KAFKA_BROKERS` | Confluent Cloud bootstrap servers |
| `KAFKA_USERNAME` | Confluent API key |
| `KAFKA_PASSWORD` | Confluent API secret |
| `SUPABASE_URL` | Supabase project URL |
| `SUPABASE_SERVICE_ROLE_KEY` | Service role key for RPC calls |
| `REDIS_URL` | Render Redis internal URL |
| `INNGEST_EVENT_KEY` | Inngest event publishing key |

#### Edge Functions

| Variable | Purpose |
|----------|---------|
| `SUPABASE_URL` | Supabase project URL |
| `SUPABASE_SERVICE_ROLE_KEY` | Database access |
| `INNGEST_SIGNING_KEY` | Inngest webhook verification |

### Monitoring & Observability

| Component | Data |
|-----------|------|
| `tier_bulk_chunk_log` | Batch progress, chunk status |
| `tier_change_ledger` | Complete audit trail of all tier changes |
| `tier_evaluation_errors` | Evaluation failures |
| `tier_evaluation_tracking` | Maintain deadlines, next evaluation dates (all window types) |
| Inngest Dashboard | Workflow runs, sleeping workflows (IS the pending state), cancellations |
| Render Dashboard | Consumer logs, Redis dedup metrics |
| Confluent Console | CDC lag, connector status |

### Query Examples for Calendar Types

**Check users due for evaluation today**:
```sql
SELECT ua.fullname, tet.maintain_deadline, tet.maintain_window_type
FROM tier_evaluation_tracking tet
JOIN user_accounts ua ON ua.id = tet.user_id
WHERE tet.maintain_deadline = CURRENT_DATE
ORDER BY tet.maintain_window_type, ua.fullname;
```

**View all monthly tier users and their next check date**:
```sql
SELECT ua.fullname, tm.tier_name, tet.maintain_deadline
FROM tier_evaluation_tracking tet
JOIN user_accounts ua ON ua.id = tet.user_id
JOIN tier_master tm ON tm.id = ua.tier_id
WHERE tet.maintain_window_type = 'calendar_month'
ORDER BY tet.maintain_deadline;
```

**View all quarterly tier users grouped by quarter**:
```sql
SELECT 
    CASE 
        WHEN EXTRACT(MONTH FROM tet.maintain_deadline) = 3 THEN 'Q1'
        WHEN EXTRACT(MONTH FROM tet.maintain_deadline) = 6 THEN 'Q2'
        WHEN EXTRACT(MONTH FROM tet.maintain_deadline) = 9 THEN 'Q3'
        WHEN EXTRACT(MONTH FROM tet.maintain_deadline) = 12 THEN 'Q4'
    END as quarter,
    COUNT(*) as users_due,
    tet.maintain_deadline
FROM tier_evaluation_tracking tet
WHERE tet.maintain_window_type = 'calendar_quarter'
GROUP BY quarter, tet.maintain_deadline
ORDER BY tet.maintain_deadline;
```

### Inngest Configuration

| Setting | Value |
|---------|-------|
| App ID | `crm-tier-system` |
| Endpoint | `https://{supabase-project}.supabase.co/functions/v1/inngest-tier-serve` |
| Events | `tier/upgrade`, `tier/upgrade-cancelled` |
| Workflows | `tier-upgrade` (with `cancelOn` support) |