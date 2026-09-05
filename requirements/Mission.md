# Mission System V2

## Overview

The mission system enables merchants to define goal-based challenges where users progress through qualifying actions and receive rewards upon completion. V2 introduces per-condition JSONB progress tracking with event-driven architecture using CDC, Kafka, and Inngest orchestration.

### Mission Types

**Standard Missions** follow single-objective patterns with configurable repeatability. All conditions must be satisfied simultaneously (AND logic). Each condition tracks progress independently.

**Milestone Missions** implement multi-level progressive achievement paths. Users advance through sequential levels (1→2→3), each with distinct targets and rewards. Progress "waterfalls" through levels—overflow from completing one level automatically applies to the next.

## Architecture (post-Confluent, 2026-07-08)

```
┌──────────────────────────────────────────────────────────┐
│                     Event Sources                         │
├───────────────────────────┬──────────────────────────────┤
│ purchase_ledger (+items)  │        wallet_ledger         │
└─────────────┬─────────────┴──────────────┬───────────────┘
              │ chokepoint_post_purchase_… │ chokepoint wallet emit
              ▼                            ▼
      ┌──────────────────────────────────────────┐
      │ chokepoint_event_outbox                  │
      │ (crm.events.purchase / purchase_item /   │
      │  wallet)                                 │
      └───────────────────┬──────────────────────┘
                          │ OutboxPublisher (crm-event-processors)
                          ▼
      ┌──────────────────────────────────────────┐
      │ inngest-event-router-serve (Edge Fn)     │
      │ mission-purchase-router                  │
      │ mission-purchase-item-router             │
      │ mission-wallet-router                    │
      └───────────────────┬──────────────────────┘
                          │ mission/evaluate (per active mission)
                          ▼
      ┌──────────────────────────────────────────┐
      │ inngest-mission-serve (Edge Fn)          │
      │ mission-evaluate workflow                │
      └───────────────────┬──────────────────────┘
                          ▼
      ┌──────────────────────────────────────────┐
      │ fn_evaluate_mission_conditions           │
      │ fn_update_mission_progress               │
      │ fn_process_mission_outcomes              │
      └───────────────────┬──────────────────────┘
                          ▼
      ┌──────────────────────────────────────────┐
      │ mission_progress (condition_progress     │
      │ JSONB) + mission_log_completion          │
      └──────────────────────────────────────────┘
```

Removed 2026-07-08 (dead/duplicate paths): `trg_mission_eval_queue_wallet` →
`mission_evaluation_queue` (no consumer since Inngest migration; queue truncated) and
`trg_mission_eval_realtime_wallet` (double-evaluated manual missions already covered by the
Inngest wallet router). The Inngest path is the single evaluation owner.

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

### 1. Chokepoint emit (CDC/Kafka decommissioned 2026-06-04 / 2026-07-07)

`chokepoint_post_purchase_event` and the wallet chokepoint write flat JSON payloads to
`chokepoint_event_outbox`; the OutboxPublisher (crm-event-processors, Inngest mode)
publishes them as Inngest events (`crm.events.purchase` → `crm/purchase.event`, etc.).

| Topic | Payload fields used by missions | Condition Type |
|-------|--------------------------------|----------------|
| `crm.events.purchase` | `purchase_id`, `user_id`, `status`, `final_amount`, `total_amount`, `seller_id`, `store_id`, `store_code` | `purchase` (unscoped conditions) |
| `crm.events.purchase_item` | `item_id`, `purchase_id`, `user_id`, `item_status`, `sku_id`, `product_id`, `category_id`, `brand_id`, `amount` (line_total), `transaction_amount`, `seller_id` | `purchase` (SKU/product/category/brand-scoped conditions) |
| `crm.events.wallet` | `wallet_ledger_id`, `user_id`, `currency`, `amount`, `transaction_type`, `target_entity_id` | `points_earned`, `tickets_earned` |

Item payload enrichment (sku/product/category/brand/line amount) added 2026-07-08; the
`product_id`/`category_id`/`brand_id` are resolved via `product_sku_master` → `product_master`
at emit time.

### 2. Router processing (`inngest-event-router-serve`)

Three mission routers replace the legacy MissionConsumer:

1. **`mission-purchase-router`** — fires on `status='completed'` only. Forwards
   `amount` (= `final_amount ?? total_amount`), `seller_id`, `store_id`, `store_code`
   in `event_data` (amount forwarding restored 2026-07-08 — its omission in the initial
   Confluent→Inngest port silently zeroed all purchase-sum progress).
2. **`mission-purchase-item-router`** — fires on `item_status='completed'` only (added
   2026-07-08). Feeds SKU/product/category/brand-scoped purchase conditions with line-level
   `amount`. Idempotency `item_id:item_status`.
3. **`mission-wallet-router`** — fires on `transaction_type='earn'`; condition type
   `points_earned` (currency=points) or `tickets_earned` (others).

Each router gates on `fn_has_active_missions` + `fn_get_active_missions_by_condition_type`
(replaces the legacy Redis mission cache) and emits one `mission/evaluate` per active mission.

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
- **Header/item scoping (2026-07-08):** purchase conditions with `sku_ids` / `product_ids` /
  `category_ids` / `brand_ids` match ONLY `p_event_type='purchase_item'`; unscoped purchase
  conditions match ONLY `p_event_type='purchase'`. Header and item events therefore never
  double-count the same condition.
- Do product/category/brand filters match?
- Are amount thresholds satisfied? (`min/max_transaction_amount` compares the transaction
  total — item events carry it as `transaction_amount`; `sum` increments use the event
  `amount`, which is the line amount on item events)
- Does store location match attribute set? Resolve the store in this order, then
  call `get_store_attribute_sets`: event `store_id` as `store_master.id` (UUID),
  else event `store_code`, else `store_master.store_code = event.store_id`
  (POS / legacy text code). Front Line receipts persist `purchase_ledger.store_id`
  as a UUID.
- For `points_earned` only: non-empty `earn_source_type` must match wallet
  `source_type`. Empty / NULL matches all earn sources except `mission` (mission-sourced
  earns still need an explicit `mission` allow).
- For `tickets_earned`: `NULL` / empty `ticket_type_id` matches every ticket type;
  non-empty = wallet `target_entity_id` is in that UUID array. Mission-outcome ticket
  earns **do** count (`source_type='mission'`). Recursion is capped by progress/claim
  loop limits, not by dropping mission-source wallet events. `earn_source_type` is
  ignored for this condition type.

**`fn_check_progress_limits` / `fn_check_claim_limits`**

- Progress limits (`mission_limit_progress`) cap **completions written** in the
  merchant-TZ calendar window of `time_unit × time_value` (lookback of
  `time_value` calendar days/weeks/months/years including today). `time_value=2`
  on `day` covers today and yesterday and does **not** reopen at the next
  midnight. `fn_update_mission_progress` asks
  `fn_check_progress_limits` for remaining quota and caps loops at that number.
  Spend that would complete a loop after the cap is **discarded** — current-loop
  progress is not left at target. A new window counts only new eligible spend;
  leftover from a capped window must not become completions. Count is
  `mission_log_completion` rows, not progress events.
- Claim limits (`mission_limit_claim`) cap **reward payouts** only, via
  `fn_check_claim_limits` inside `fn_process_mission_outcomes_batch` (member claim,
  Front Line claim, auto-claim). They use the same `time_unit × time_value`
  merchant-TZ window. They must not cap progress writes.

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

## Active-Mission Pre-filter (Redis cache retired)

The legacy Redis cache (`missions:active:{merchant_id}:{condition_type}`) died with the
MissionConsumer. Routers now call the same DB RPCs the cache was built from, per event:
`fn_has_active_missions(p_merchant_id, p_condition_type)` (cheap boolean gate) then
`fn_get_active_missions_by_condition_type()` filtered to the merchant.

## Condition Types

| Type | Source | Event Trigger | Filters Available |
|------|--------|---------------|-------------------|
| `purchase` | `crm.events.purchase` (unscoped) / `crm.events.purchase_item` (SKU/product/category/brand-scoped) | status / item_status ='completed' | products, SKUs, categories, brands, stores, amounts |
| `points_earned` | `crm.events.wallet` | transaction_type='earn', currency='points' | earn_source_type |
| `tickets_earned` | `crm.events.wallet` | transaction_type='earn', currency≠'points' | ticket_type_id |
| `form_submission` | **DEAD** — no chokepoint source since CDC decommission | — | form_id |
| `referral_signup` | **DEAD** — no chokepoint source since CDC decommission | — | — |
| `referral_purchase` | **DEAD** — no chokepoint source since CDC decommission | — | — |

`bff_upsert_mission` rejects the three dead condition types (`UNSUPPORTED_CONDITION_TYPE`,
2026-07-08) until chokepoint emits exist at their write sites.

Admin Mission Settings shows **Earn source** only for `points_earned`. The writer persists
`conditions[].earn_source_type` (`text[]`; empty / omitted / JSON null → SQL `NULL` = all
sources). A leftover `earn_source` key is still accepted. Purchase and tickets-earned
payloads must not send a wallet source filter.

ASSERT: a `tickets_earned` condition counts mission-outcome ticket earns; the type
filter matches wallet `target_entity_id`.

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
| `claim_type` | `auto` / `manual` | Auto: rewards immediately and writes `frontline_mission_claim_log` so Front Line Claim Mission History matches issued outcomes. Manual: user / staff must claim |

### Reset Frequency

| Setting | Behavior |
|---------|----------|
| `NULL` | Progress accumulates indefinitely |
| `daily` | Resets at merchant-local midnight |
| `monthly` | Resets on 1st of month |

Period reset (`fn_batch_reset_due_missions`, pg_cron every 15 min) zeroes in-period progress **and** `unclaimed_completions`. Claimed rewards (`lifetime_*`) stay. `NULL` `reset_mode` means `global`.

**Note:** Milestone missions cannot have reset frequency (constraint enforced).

### Reset Mode

| Mode | Behavior |
|------|----------|
| `global` | All users reset at same calendar time |
| `user_specific` | Each user resets relative to their `period_started_at` |

Default when `reset_mode` is null: `global`.

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

### bff_upsert_mission

Admin create/update for mission definition + children (conditions, outcomes, limits).

**Endpoint:** `POST /rest/v1/rpc/bff_upsert_mission`

**Eligibility fields** (`eligible_persona_ids`, `eligible_persona_group_ids`):

- Parsed via `fn_jsonb_uuid_array`. Null, empty array `[]`, or any non-array JSON (including `""` from FE “All personas”) → stored as `NULL` = all members.
- Only a JSON array of UUID strings is persisted. Merchant ownership is validated in `fn_validate_mission_upsert` when the array is non-empty.

**`earn_source_type`:** read from `conditions[].earn_source_type` (jsonb array or scalar
string) into `mission_conditions.earn_source_type`. Empty array → NULL. GET
(`bff_get_mission_details_conditions_limits`) returns the same key.

### admin_delete_mission

Hard-delete of a mission definition. Returns `MISSION_HAS_CLAIM_HISTORY` when
`frontline_mission_claim_log` rows exist for that mission. Claim logs stay (RESTRICT) —
do not CASCADE. Deactivate (`is_active = false`) to take a claimed mission off the floor.

### bff_get_user_missions

Returns list of missions for a user with progress summary.

**Endpoint:** `POST /rest/v1/rpc/bff_get_user_missions`

**Parameters:**
| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `p_user_id` | uuid | `auth.uid()` | Target user (admin override) |
| `p_include_inactive` | boolean | false | Include inactive missions |

Admin override (`p_user_id` set, e.g. Frontline Claim Mission) requires an active `admin_users` row for the current merchant (`auth_user_id = auth.uid()`, `merchant_id` match, `active_status = true`). Do not use the removed `admin_users.role` text column.

Each mission row includes `claim_exclusivity_group` (trimmed text, null when blank). Front Line Group view buckets by this string so booth staff see exclusive siblings together. No Group Mission master.

List `outcomes[]` include `entity_name` for tickets (`ticket_type.name`) and rewards (`reward_master.name`), plus existing `reward_name` / `reward_image`. Front Line Claim Mission uses `entity_name` so the modal can show `QA ticket : 1` instead of raw `tickets : 1`.

`fn_process_mission_outcomes_batch` pays a set of completions in one transaction: each distinct outcome is dispatched once with `amount × completion count`. Non-promo rewards therefore get one `reward_redemptions_ledger` row (`qty = grant`). Promo-code rewards still split per `requirements/Reward.md#Multi-Quantity Redemption`. Member `bff_claim_mission` / auto-claim use the same batch.

### bff_get_mission_detail

Returns comprehensive mission details including conditions, outcomes, and progress.

**Endpoint:** `POST /rest/v1/rpc/bff_get_mission_detail`

**Parameters:**
| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `p_mission_id` | uuid | required | Mission to retrieve |
| `p_user_id` | uuid | `auth.uid()` | Target user (admin override) |

`end_date` stops join/progress. `claim_end_date` (else `end_date`) is the claim window. After `end_date`, list `is_visible` is true only when `can_claim`. Detail still returns the payload when `reason_codes` includes `after_end` (claim window still open) so Claim is not a fake “Mission not found.” Unclaimed is `mission_log_completion.outcomes_distributed IS DISTINCT FROM true` — same as list count and `bff_claim_mission`.

### bff_claim_mission

Claims mission outcomes for user.

**Endpoint:** `POST /rest/v1/rpc/bff_claim_mission`

**Parameters:**
| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `p_mission_id` | uuid | required | Mission to claim |
| `p_user_id` | uuid | `auth.uid()` | Target user (admin override) |
| `p_milestone_level` | integer | null | Specific milestone to claim (milestone missions only) |
| `p_quantity` | integer | `1` | Completions to pay this call. Passed as `p_max_claims` to `fn_process_mission_outcomes_batch`. Default 1 — not all remaining. Auto-claim still uses `fn_process_mission_outcomes` (uncapped). Front Line stays on `bff_frontline_claim_mission`. |

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

### Condition evaluation (direct tables)

`fn_evaluate_mission_conditions` reads `mission` + `mission_conditions` directly (indexed).
The former `mv_mission_conditions_expanded` and its refresh crons were removed 2026-08-09
(S0.5). Admin writes still go through live `bff_upsert_mission(p_data jsonb)` — the 2026-07-08
change only removed the inline MV refresh, not the upsert function.

### Mission completed shared event (E2)

`AFTER INSERT` on `mission_log_completion` → `trigger_emit_mission_completed_event` →
`fn_chokepoint_emit_event('crm.events.mission', …)` with `event=completed` and identity
`completion_id`. This is for cross-module consumers (notifications/AMP/analytics). It must
**not** drive mission outcome distribution (`fn_distribute_mission_completion` /
`fn_dispatch_outcome` remain authoritative). Opt out of emits in a transaction with
`SELECT set_config('mission.skip_emit','true',true)`. OutboxPublisher must include `mission`
in `OUTBOX_PUBLISH_TOPICS` (added 2026-08-09).

### Legacy retirement (E3)

Dropped dead `mission_evaluation_queue` + batch/queue/realtime functions (Inngest owns eval).
`mission_log_outcome_distribution` table replaced by a compatibility **view** over
`outcome_distribution_log` (`source_type=mission`, success only). Canonical writes stay on
the shared log. `fn_process_mission_outcomes_for_milestone` removed; milestone claim uses
`fn_distribute_mission_completion` directly.

### Loop missions (`allow_progress_loop`)

On completion of a loop mission, `fn_update_mission_progress` calls
`fn_reset_condition_progress(p_user_id, p_mission_id)` BEFORE incrementing the completion
counters (the reset zeroes `current_progress`/`period_completions`). Fixed 2026-07-08 —
previously it called the function with a jsonb argument that doesn't match any signature,
crashing (and rolling back) every loop-mission completion.

`max_loops_per_transaction` NULL means unlimited loops from one event (still bounded by
receipt amount and progress limits). Admin Completion frequency **Multiple** saves NULL;
**Limited** requires an integer > 0. `COALESCE(max_loops, raw_completions)` in the
progress function is the unlimited path.

**Once** (`allow_progress_loop = false`) caps `lifetime_completions` at 1. Parked-at-target
fills do not cash another Ready-to-claim. Limited leftover zeroing stays on limit rows only.

### Admin claim-on-behalf

`bff_claim_mission(p_mission_id, p_user_id, …)` with an explicit `p_user_id` requires the
caller to be an active `admin_users` row for the merchant (`active_status = true`). Fixed
2026-07-08 — previously it checked non-existent `role` / `is_active` columns and always failed.

### Monitoring

Check Inngest dashboard for:
- `mission/evaluate` execution status
- Failed function runs
- Concurrency utilization

Check Supabase logs for:
- PostgreSQL function errors
- Edge Function execution

### Reward dropdown for Mission Outcomes

`bff_list_rewards_for_mission_outcomes` returns rewards with `visibility IN ('user',
'campaign')`, campaign-first. If the admin Outcomes dropdown shows only `user` rewards,
verify (a) the merchant actually has active `campaign` rewards and (b) the FE calls this
RPC rather than `bff_list_rewards` or a client-side visibility filter.
