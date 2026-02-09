# Mission System V2

## Overview

The mission system enables merchants to define goal-based challenges where users progress through qualifying actions and receive rewards upon completion. V2 introduces per-condition JSONB progress tracking with event-driven architecture using CDC, Kafka, and Inngest orchestration.

### Mission Types

**Standard Missions** follow single-objective patterns with configurable repeatability. All conditions must be satisfied simultaneously (AND logic). Each condition tracks progress independently.

**Milestone Missions** implement multi-level progressive achievement paths. Users advance through sequential levels (1→2→3), each with distinct targets and rewards. Progress "waterfalls" through levels—overflow from completing one level automatically applies to the next.

## Architecture

```
┌─────────────────────────────────────────────────────────────────────────┐
│                           Event Sources                                  │
├─────────────────┬─────────────────┬─────────────────┬───────────────────┤
│ purchase_ledger │  wallet_ledger  │form_submissions │  referral_ledger  │
└────────┬────────┴────────┬────────┴────────┬────────┴─────────┬─────────┘
         │                 │                 │                  │
         └────────────────┬┴─────────────────┴──────────────────┘
                          │
                          ▼
                 ┌────────────────┐
                 │  Debezium CDC  │
                 │  (Supabase)    │
                 └───────┬────────┘
                         │
                         ▼
                 ┌────────────────┐
                 │  Kafka Topics  │
                 │  (Upstash)     │
                 └───────┬────────┘
                         │
                         ▼
                 ┌────────────────┐
                 │MissionConsumer │◄── Redis Pre-filter Cache
                 │(crm-event-     │    (active missions lookup)
                 │ processors)    │
                 └───────┬────────┘
                         │
                         ▼
                 ┌────────────────┐
                 │ Inngest Cloud  │
                 │ mission/evaluate│
                 └───────┬────────┘
                         │
                         ▼
                 ┌────────────────┐
                 │inngest-mission │
                 │   -serve       │
                 │ (Edge Function)│
                 └───────┬────────┘
                         │
                         ▼
         ┌───────────────┴───────────────┐
         │     PostgreSQL Functions      │
         ├───────────────────────────────┤
         │fn_evaluate_mission_conditions │
         │fn_update_mission_progress     │
         │fn_process_mission_outcomes    │
         └───────────────┬───────────────┘
                         │
                         ▼
                 ┌────────────────┐
                 │mission_progress│
                 │(condition_     │
                 │ progress JSONB)│
                 └────────────────┘
```

## Per-Condition JSONB Progress Tracking

### Core Concept

One JSONB field (`condition_progress`) stores progress for both mission types. The key structure and update strategy differ:

| Mission Type | Key Structure | Update Strategy |
|--------------|---------------|-----------------|
| Standard | `condition_id` (UUID) | Parallel—each event updates its matching condition |
| Milestone | `level_N` | Waterfall—event fills from first incomplete level, overflow continues to next |

### Standard Mission Structure

```json
{
  "0d284fa9-b6d8-4159-b95c-4a16e110cbc2": {
    "type": "purchase",
    "target": 1000,
    "current": 750,
    "condition_id": "0d284fa9-b6d8-4159-b95c-4a16e110cbc2"
  },
  "76add59b-8e7b-4b18-a1c4-3e3bdbf71113": {
    "type": "points_earned",
    "target": 100,
    "current": 82,
    "condition_id": "76add59b-8e7b-4b18-a1c4-3e3bdbf71113"
  }
}
```

**Parallel Update Logic:** When a purchase event arrives, only the `purchase` condition updates. When a points_earned event arrives, only that condition updates. Mission completes when ALL conditions reach their targets.

### Milestone Mission Structure

```json
{
  "level_1": {
    "type": "purchase",
    "target": 500,
    "current": 500,
    "completed_at": "2025-12-30T14:13:25Z",
    "condition_id": "7c4db085-7446-45ba-92b1-674b46eee69f"
  },
  "level_2": {
    "type": "purchase",
    "target": 2000,
    "current": 2000,
    "completed_at": "2025-12-30T14:13:37Z",
    "condition_id": "772c1c36-0574-45c2-8aeb-490f06c3a65d"
  },
  "level_3": {
    "type": "purchase",
    "target": 5000,
    "current": 700,
    "completed_at": null,
    "condition_id": "1cca15ff-945c-42b3-99b4-e0b3bbc9c4f0"
  }
}
```

**Waterfall Update Logic:** When a purchase event arrives:
1. Find first incomplete level (where `completed_at` is null)
2. Add amount to that level's `current`
3. If `current >= target`, mark completed, calculate overflow
4. Apply overflow to next level, repeat until depleted

**Example:**
- User has Level 1 at 300/500, Level 2 at 0/2000
- Purchase of 400 THB arrives
- Level 1: 300 + 400 = 700, needs 500, overflow = 200
- Level 1 completes (500/500), Level 2 gets overflow (200/2000)

## Event Flow

### 1. CDC Capture

Debezium captures changes from source tables and streams to Kafka:

| Source Table | Kafka Topic | Condition Type |
|--------------|-------------|----------------|
| `purchase_ledger` | `crm_cdc.public.purchase_ledger` | `purchase` |
| `wallet_ledger` | `crm_cdc.public.wallet_ledger` | `points_earned`, `tickets_earned` |
| `form_submissions` | `crm_cdc.public.form_submissions` | `form_submission` |
| `referral_ledger` | `crm_cdc.public.referral_ledger` | `referral_signup`, `referral_purchase` |

### 2. MissionConsumer Processing

The consumer service (`crm-event-processors`) receives CDC messages and:

1. **Parses Debezium message** - Extracts `after` payload with row data
2. **Decodes decimal values** - Debezium encodes DECIMAL/NUMERIC as base64; consumer decodes them
3. **Checks Redis cache** - Fast lookup: does this merchant have active missions for this condition type?
4. **Publishes to Inngest** - Sends `mission/evaluate` event with user, merchant, event data

```typescript
// Debezium decimal decoding example
// Input: "JxA=" (base64-encoded 100.00)
// Output: 100.00
const amount = decodeDebeziumDecimal(after.final_amount, 2);
```

### 3. Inngest Workflow: mission/evaluate

The `inngest-mission-serve` Edge Function orchestrates evaluation:

```typescript
inngest.createFunction(
  { id: "mission-evaluate", concurrency: { limit: 50 } },
  { event: "mission/evaluate" },
  async ({ event, step }) => {
    const { user_id, merchant_id, mission_id, event_type, event_data, trigger_id } = event.data;
    
    // Step 1: Evaluate conditions
    const increments = await step.run("evaluate-conditions", async () => {
      return await supabase.rpc("fn_evaluate_mission_conditions", {
        p_mission_id: mission_id,
        p_merchant_id: merchant_id,
        p_user_id: user_id,
        p_event_type: event_type,
        p_event_data: event_data
      });
    });
    
    // Step 2: Update progress
    const result = await step.run("update-progress", async () => {
      return await supabase.rpc("fn_update_mission_progress", {
        p_user_id: user_id,
        p_mission_id: mission_id,
        p_merchant_id: merchant_id,
        p_increments: increments,
        p_trigger_type: event_type,
        p_trigger_id: trigger_id
      });
    });
    
    // Step 3: Process outcomes if completed
    if (result.newly_completed?.length > 0) {
      await step.run("process-outcomes", async () => {
        return await supabase.rpc("fn_process_mission_outcomes", {...});
      });
    }
  }
);
```

### 4. PostgreSQL Functions

**`fn_evaluate_mission_conditions`**

Evaluates event against mission conditions and returns increments:

- For **standard missions**: Returns `{"condition-uuid": increment}`
- For **milestone missions**: Returns `{"level_1": increment}` (always targets level_1, waterfall handles distribution)

The function checks:
- Does event_type match condition_type?
- Do product/category/brand filters match?
- Are amount thresholds satisfied?
- Does store location match attribute set?

**`fn_update_mission_progress`**

Applies increments to `condition_progress` JSONB:

```sql
-- Determine update strategy
IF mission_type = 'milestone' THEN
  -- Waterfall: fill from first incomplete level
  FOR level_key IN SELECT key FROM levels ORDER BY level_num LOOP
    IF current < target THEN
      remaining = target - current;
      applied = LEAST(increment, remaining);
      new_current = current + applied;
      increment = increment - applied;  -- overflow
      
      IF new_current >= target THEN
        -- Mark level completed
        condition_progress[level_key].completed_at = NOW();
        newly_completed = array_append(newly_completed, level_key);
      END IF;
    END IF;
  END LOOP;
ELSE
  -- Parallel: update matching condition directly
  condition_progress[condition_id].current += increment;
END IF;
```

**`fn_process_mission_outcomes`**

Distributes rewards when milestones/conditions complete:

- Creates `wallet_ledger` entries for points/tickets
- Creates `redemption_pool` entries for physical rewards
- Logs to `mission_log_completion` and `mission_log_outcome_distribution`

## Redis Cache Layer

The consumer maintains a Redis cache for fast pre-filtering:

**Key Pattern:** `missions:active:{merchant_id}:{condition_type}`
**Value:** Set of active mission IDs

**Population:**
```sql
SELECT DISTINCT m.id
FROM mission m
JOIN mission_conditions mc ON mc.mission_id = m.id
WHERE m.merchant_id = $1 
  AND mc.condition_type = $2
  AND m.is_active = true
  AND (m.start_date IS NULL OR m.start_date <= NOW())
  AND (m.end_date IS NULL OR m.end_date >= NOW());
```

**Invalidation:** Cache refreshes on service restart or when materialized view `mv_mission_conditions_expanded` is refreshed.

## Condition Types

| Type | Source Table | Event Trigger | Filters Available |
|------|--------------|---------------|-------------------|
| `purchase` | `purchase_ledger` | status='completed' | products, SKUs, categories, brands, stores, amounts |
| `points_earned` | `wallet_ledger` | transaction_type='earn', currency='points' | earn_source_type |
| `tickets_earned` | `wallet_ledger` | transaction_type='earn', currency='ticket' | ticket_type_id |
| `form_submission` | `form_submissions` | status='completed' | form_id |
| `referral_signup` | `referral_ledger` | signed_up_at IS NOT NULL | — |
| `referral_purchase` | `referral_ledger` | first_purchase_at IS NOT NULL | — |

### Measurement Types

| Type | Behavior | Example |
|------|----------|---------|
| `count` | Each event adds +1 | "Make 5 purchases" |
| `sum` | Each event adds its value | "Spend 5000 THB" |

Binary events (forms, referrals) always use count logic.

## Database Schema

### mission_progress Table

| Column | Type | Purpose |
|--------|------|---------|
| `id` | uuid | Primary key |
| `user_id` | uuid | User being tracked |
| `mission_id` | uuid | Mission reference |
| `merchant_id` | uuid | Merchant context |
| `current_progress` | numeric | Legacy—sum of all progress (backwards compatibility) |
| `condition_progress` | jsonb | **V2: Per-condition/level progress tracking** |
| `lifetime_completions` | integer | Total completions ever |
| `unclaimed_completions` | integer | Pending claims (manual-claim missions) |
| `last_progress_at` | timestamptz | Last progress update |
| `accepted_at` | timestamptz | When user accepted (manual missions) |

### mission_conditions Table

| Column | Type | Purpose |
|--------|------|---------|
| `id` | uuid | Condition identifier (used as JSONB key for standard) |
| `mission_id` | uuid | Parent mission |
| `condition_type` | enum | Event type to track |
| `measurement_type` | enum | 'count' or 'sum' |
| `target_value` | numeric | Completion threshold |
| `milestone_level` | integer | Level number (milestone missions only) |
| `operator` | enum | 'AND' or 'OR' for array filters |
| `product_ids`, `sku_ids`, `category_ids`, `brand_ids` | uuid[] | Product filters |
| `store_attribute_set_id` | uuid | Location filter |
| `min_transaction_amount`, `max_transaction_amount` | numeric | Amount range |

### mission_milestones Table

| Column | Type | Purpose |
|--------|------|---------|
| `id` | uuid | Milestone identifier |
| `mission_id` | uuid | Parent mission |
| `milestone_level` | integer | Level number (1, 2, 3...) |
| `milestone_name` | text | Display name ("Bronze", "Silver", "Gold") |
| `milestone_description` | text | Level description |
| `display_order` | integer | UI ordering |

## Mission Configuration

### Activation & Claim Types

| Setting | Options | Behavior |
|---------|---------|----------|
| `progress_activation_type` | `auto` / `manual` | Auto: tracks all users. Manual: requires accept_mission call |
| `claim_type` | `auto` / `manual` | Auto: rewards immediately. Manual: user must claim |

### Reset Frequency

| Setting | Behavior |
|---------|----------|
| `NULL` | Progress accumulates indefinitely |
| `daily` | Resets at midnight |
| `monthly` | Resets on 1st of month |

**Note:** Milestone missions cannot have reset frequency (constraint enforced).

### Reset Mode

| Mode | Behavior |
|------|----------|
| `global` | All users reset at same calendar time |
| `user_specific` | Each user resets relative to their `period_started_at` |

## Examples

### Standard Mission: "Big Spender & Earner"

**Configuration:**
- Type: Standard
- Activation: Auto
- Conditions:
  - Purchase 5000 THB total (sum)
  - Earn 500 points (sum)
- Outcome: 1000 bonus points

**Progress Tracking:**
```json
{
  "purchase-cond-id": { "type": "purchase", "target": 5000, "current": 3500 },
  "points-cond-id": { "type": "points_earned", "target": 500, "current": 420 }
}
```

**Completion:** When BOTH conditions reach target simultaneously.

### Milestone Mission: "Spending Spree Challenge"

**Configuration:**
- Type: Milestone
- Activation: Auto
- Levels:
  - Level 1 (Bronze): Spend 500 THB → 50 points
  - Level 2 (Silver): Spend 2000 THB → 200 points
  - Level 3 (Gold): Spend 5000 THB → 500 points + badge

**Progress Tracking:**
```json
{
  "level_1": { "type": "purchase", "target": 500, "current": 500, "completed_at": "2025-12-30T14:13:25Z" },
  "level_2": { "type": "purchase", "target": 2000, "current": 2000, "completed_at": "2025-12-30T14:13:37Z" },
  "level_3": { "type": "purchase", "target": 5000, "current": 700, "completed_at": null }
}
```

**Waterfall Example:**
1. User purchases 300 THB → Level 1: 300/500
2. User purchases 400 THB → Level 1: 500/500 ✓, overflow 200 → Level 2: 200/2000
3. User purchases 2500 THB → Level 2 fills to 2000 ✓, overflow 700 → Level 3: 700/5000

## BFF Functions (Frontend API)

### bff_get_user_missions

Returns list of missions for a user with progress summary.

**Endpoint:** `POST /rest/v1/rpc/bff_get_user_missions`

**Parameters:**
| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `p_user_id` | uuid | `auth.uid()` | Target user (admin override) |
| `p_include_inactive` | boolean | false | Include inactive missions |

### bff_get_mission_detail

Returns comprehensive mission details including conditions, outcomes, and progress.

**Endpoint:** `POST /rest/v1/rpc/bff_get_mission_detail`

**Parameters:**
| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `p_mission_id` | uuid | required | Mission to retrieve |
| `p_user_id` | uuid | `auth.uid()` | Target user (admin override) |

### bff_claim_mission

Claims mission outcomes for user.

**Endpoint:** `POST /rest/v1/rpc/bff_claim_mission`

**Parameters:**
| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `p_mission_id` | uuid | required | Mission to claim |
| `p_user_id` | uuid | `auth.uid()` | Target user (admin override) |
| `p_milestone_level` | integer | null | Specific milestone to claim (milestone missions only) |

### button_action Field

Both list and detail BFF functions return a `button_action` field for frontend button binding:

| Value | Condition | Frontend Action |
|-------|-----------|-----------------|
| `claim_outcome` | Has unclaimed completions AND manual claim | Call `bff_claim_mission` |
| `join_mission` | Not accepted AND manual activation | Call `accept_mission` |
| `claimed` | All conditions/milestones completed & claimed | Disabled button |
| `view_progress` | Has progress record | Navigate to detail |
| `view_details` | Default (no progress) | Navigate to detail |

**Priority Order (checked top-to-bottom):**
1. `claim_outcome` → unclaimed_completions > 0 AND claim_type = 'manual'
2. `join_mission` → accepted_at IS NULL AND activation_type = 'manual'
3. `claimed` → all conditions met (100%) and claimed
4. `view_progress` → has mission_progress record
5. `view_details` → fallback

**Frontend JavaScript Example:**
```javascript
const buttonAction = missionData?.button_action;

const textMap = {
  'claim_outcome': 'รับรางวัล',
  'join_mission': 'เข้าร่วมภารกิจ',
  'claimed': 'รับแล้ว',
  'view_progress': 'ดูความคืบหน้า',
  'view_details': 'ดูรายละเอียด'
};

const buttonText = textMap[buttonAction] || 'ดูรายละเอียด';
const isDisabled = buttonAction === 'claimed';
```

## Operational Notes

### Cache Refresh

When creating new missions, the Redis cache must be refreshed for the consumer to pick them up:

1. Restart `crm-event-processors` service, OR
2. Cache auto-refreshes on next scheduled interval

### Materialized View

After mission/condition changes:
```sql
REFRESH MATERIALIZED VIEW mv_mission_conditions_expanded;
```

### Monitoring

Check Inngest dashboard for:
- `mission/evaluate` execution status
- Failed function runs
- Concurrency utilization

Check Supabase logs for:
- PostgreSQL function errors
- Edge Function execution

### Debezium Decimal Handling

CDC encodes PostgreSQL `DECIMAL/NUMERIC` as base64 byte arrays:
- `"JxA="` = 100.00 (base64 → bytes → integer 10000 → divide by 100)
- Consumer's `decodeDebeziumDecimal()` handles this automatically
