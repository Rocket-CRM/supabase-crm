# Activity-Based Earning System

## Overview

The Activity-Based Earning system enables users to upload activity images (exercise, meditation, volunteer work, etc.) that admins review and approve. Upon approval, the system awards currency based on dynamic field combinations configured in a multi-dimensional matrix.

**Key Features:**
- User self-service image upload with frequency limits
- Admin approval workflow with dynamic field entry
- Multi-dimensional currency matrix (2D combinations) with pivot table display
- Direct currency award integration (sync chokepoint; no earn-router hop)
- Full audit trail in wallet_ledger
- **Edit + recalculate** for already-approved or rejected uploads, with delta earn / FIFO partial reversal (2026-05-14)
- WeWeb Data Grid optimized response with dynamic columns

**Architecture Pattern:** Synchronous admin action → Direct `chokepoint_post_wallet_transaction()` call (same as reward redemption)

**Edit flow (2026-05-14):** Admins can re-enter field values for an already-approved or rejected upload via `bff_edit_activity_upload`. The function recalculates the target totals through `fn_calculate_activity_currency`, diffs against the current net per `(currency, target_entity_id)` from `wallet_ledger`, and posts one chokepoint call per non-zero delta — `component='adjustment'`+`transaction_type='earn'` for delta-up, `component='reversal'`+`transaction_type='burn'` for delta-down, `component='base'`+`transaction_type='earn'` when transitioning from `rejected`. FIFO consumption is `fn_allocate_fifo_burn` inside `chokepoint_post_wallet_transaction` (oldest-expiry-first earn lots; points fungible, tickets isolated by `target_entity_id`). Partial-cover clamping is applied when current balance is insufficient: the function reads `user_wallet.points_balance` / `user_ticket_balances.balance` first, posts `min(|delta|, current_balance)`, and records the shortfall as `unreversed_amount` in both the chokepoint metadata and `activity_upload_ledger.edit_history`. Edits to a rejected row also flip the row to `approved` and clear `rejected_at` / `rejected_by` / `rejection_reason`. No time-window cap. Each edit increments `edit_version` and appends one entry to `edit_history`.

**Terminology:**
- **Primary Dimension:** The field that creates columns in matrix view (e.g., time_of_day, display_size)
- **Secondary Fields:** Other fields that create rows (e.g., exercise_type, check_type)
- **Matrix Cell:** One combination of primary × secondary values with currency award

---

## System Architecture

### Data Flow

```
┌─────────────────────────────────────────────────────────────────┐
│  User Upload Flow                                                │
├─────────────────────────────────────────────────────────────────┤
│                                                                  │
│  User uploads image                                              │
│         ↓                                                        │
│  upload_activity_image()                                         │
│         ↓                                                        │
│  Check frequency limits (fn_check_activity_upload_limits)       │
│         ↓                                                        │
│  Create activity_upload_ledger (status='pending')               │
│         ↓                                                        │
│  Return success to user                                          │
│                                                                  │
└─────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────┐
│  Admin Approval Flow                                             │
├─────────────────────────────────────────────────────────────────┤
│                                                                  │
│  Admin reviews image                                             │
│         ↓                                                        │
│  Admin fills field values (exercise_type: yoga, time: morning)  │
│         ↓                                                        │
│  bff_approve_activity_upload(upload_id, field_values)           │
│         ↓                                                        │
│  Validate field values (fn_validate_activity_field_values)      │
│         ↓                                                        │
│  Re-check limits (race condition protection)                    │
│         ↓                                                        │
│  Calculate currency (fn_calculate_activity_currency)            │
│    - Match field_values to activity_currency_config             │
│    - Find matching primary_value + secondary_value combos       │
│         ↓                                                        │
│  Award currency DIRECTLY (chokepoint_post_wallet_transaction)              │
│    - source_type: 'activity'                                    │
│    - source_id: upload_id                                       │
│    - component: 'base'                                          │
│    - metadata: full audit trail                                 │
│         ↓                                                        │
│  Update upload status='approved'                                │
│         ↓                                                        │
│  Return success with currency amounts                           │
│                                                                  │
└─────────────────────────────────────────────────────────────────┘
```

---

## Database Schema

### Table 1: activity_master

**Purpose:** Defines activity types with dynamic field configurations

| Column | Type | Description |
|--------|------|-------------|
| `id` | UUID | Primary key |
| `merchant_id` | UUID | Merchant ownership |
| `activity_code` | VARCHAR(50) | Unique code (e.g., 'exercise', 'meditation') |
| `activity_name` | TEXT | Display name |
| `description` | TEXT | Activity description |
| `field_definitions` | JSONB | Dynamic field configs (see structure below) |
| `primary_dimension` | TEXT | Which field is primary grouping |
| `icon_url` | TEXT | Activity icon |
| `banner_urls` | TEXT[] | Banner images |
| `active_status` | BOOLEAN | Active flag |

**field_definitions JSONB Structure:**

**Manual Fields (Admin selects from options):**
```json
{
  "exercise_type": {
    "type": "manual",
    "label": "Type of Exercise",
    "options": ["yoga", "running", "swimming", "cycling"],
    "required": true,
    "order": 1
  },
  "time_of_day": {
    "type": "manual",
    "label": "Time",
    "options": ["morning", "afternoon", "evening"],
    "required": true,
    "order": 2
  }
}
```

**Auto-Populated Fields (Pulled from USER_PROFILE form):**
```json
{
  "user_tier": {
    "type": "auto_populate",
    "label": "User Tier",
    "field_key": "membership_tier",
    "required": true,
    "order": 3
  },
  "user_outlet": {
    "type": "auto_populate",
    "label": "User Branch",
    "field_key": "preferred_outlet",
    "required": false,
    "order": 4
  }
}
```

**Field Type Properties:**

| Property | Type: `manual` | Type: `auto_populate` |
|----------|----------------|------------------------|
| `type` | Free text (flexible) | Free text (flexible) |
| `label` | Display name | Display name |
| `options` | Array of dropdown values | Not used |
| `field_key` | Not used | Field key from USER_PROFILE form |
| `required` | true/false | true/false |
| `order` | Display order | Display order |

**Notes:**
- `type` is free text string (not enum) for future extensibility
- Auto-populated fields always pull from USER_PROFILE form (no source field needed)
- Values are fetched from `form_responses` table via `field_key` mapping
- Auto-populated at upload time, stored in `activity_upload_ledger.field_values`

**📄 See detailed implementation:** [Activity_Auto_Populate_Fields.md](./Activity_Auto_Populate_Fields.md)

---

### Table 2: activity_currency_config

**Purpose:** Currency awards for field combinations (matrix cells)

| Column | Type | Description |
|--------|------|-------------|
| `id` | UUID | Primary key |
| `merchant_id` | UUID | Merchant ownership |
| `activity_id` | UUID | References activity_master |
| `primary_value` | TEXT | Value from primary dimension (e.g., 'morning') |
| `secondary_field` | TEXT | Which secondary field (e.g., 'exercise_type') |
| `secondary_value` | TEXT | Value from secondary field (e.g., 'yoga') |
| `points_amount` | NUMERIC | Points to award |
| `ticket_type_id` | UUID | Optional ticket type reference |
| `ticket_amount` | NUMERIC | Tickets to award |
| `active_status` | BOOLEAN | Active flag |

**Example Records:**
```sql
-- Matrix 1: time × exercise_type
{primary_value: 'morning', secondary_field: 'exercise_type', secondary_value: 'yoga'} → 50 points
{primary_value: 'morning', secondary_field: 'exercise_type', secondary_value: 'running'} → 60 points
{primary_value: 'evening', secondary_field: 'exercise_type', secondary_value: 'yoga'} → 40 points

-- Matrix 2: time × location  
{primary_value: 'morning', secondary_field: 'location', secondary_value: 'central'} → 30 points + 2 raffle tickets
{primary_value: 'evening', secondary_field: 'location', secondary_value: 'central'} → 25 points + 1 raffle ticket
```

**Unique Constraint:** `(activity_id, primary_value, secondary_field, secondary_value)`

---

### Table 3: activity_upload_ledger

**Purpose:** User submissions with approval workflow

| Column | Type | Description |
|--------|------|-------------|
| `id` | UUID | Primary key |
| `merchant_id` | UUID | Merchant ownership |
| `user_id` | UUID | Submitter |
| `activity_id` | UUID | Activity type |
| `image_url` | TEXT | Uploaded image |
| `field_values` | JSONB | Admin-filled values |
| `status` | TEXT | pending/approved/rejected/cancelled |
| `submitted_at` | TIMESTAMPTZ | Upload time |
| `approved_at` | TIMESTAMPTZ | Approval time |
| `approved_by` | UUID | Admin who approved |
| `rejected_by` | UUID | Admin who rejected |
| `rejection_reason` | TEXT | Rejection explanation |
| `currency_processed_at` | TIMESTAMPTZ | When currency awarded |
| `currency_error` | TEXT | Error if award failed |
| `points_awarded` | NUMERIC | Points given (snapshot) |
| `tickets_awarded` | NUMERIC | Tickets given (snapshot) |

---

## wallet_ledger Integration

### Complete Source Tracking

When `bff_approve_activity_upload()` awards currency, it creates `wallet_ledger` entries with **full audit trail**:

```json
{
  "id": "ledger-uuid",
  "user_id": "user-uuid",
  "merchant_id": "merchant-uuid",
  "currency": "points",
  "transaction_type": "earn",
  "component": "base",
  "amount": 50,
  "signed_amount": 50,
  "source_type": "activity",           ← Added to enum
  "source_id": "upload-uuid",          ← Links to activity_upload_ledger.id
  "target_entity_id": null,            ← NULL for points, ticket_type_id for tickets
  "balance_before": 100,
  "balance_after": 150,
  "metadata": {                        ← Full context
    "activity_id": "exercise-uuid",
    "activity_name": "Exercise Activity",
    "activity_code": "exercise",
    "field_values": {
      "exercise_type": "yoga",
      "time_of_day": "morning",
      "location": "central"
    },
    "matrix_match": {
      "primary_dimension": "time_of_day",
      "primary_value": "morning",
      "secondary_field": "exercise_type",
      "secondary_value": "yoga"
    },
    "approved_by": "admin-uuid",
    "approved_at": "2026-01-22T14:30:00Z",
    "image_url": "https://storage.../image.jpg"
  },
  "description": "Activity: exercise-uuid",
  "expiry_date": "2026-07-22",         ← Calculated by chokepoint_post_wallet_transaction
  "deductible_balance": 50,
  "created_at": "2026-01-22T14:30:00Z"
}
```

### Audit Trail Capabilities

**Query all activity earnings:**
```sql
SELECT * FROM wallet_ledger 
WHERE source_type = 'activity'
  AND merchant_id = get_current_merchant_id();
```

**Trace specific upload:**
```sql
SELECT 
  wl.*,
  aul.image_url,
  aul.field_values,
  am.activity_name
FROM wallet_ledger wl
JOIN activity_upload_ledger aul ON wl.source_id = aul.id
JOIN activity_master am ON aul.activity_id = am.id
WHERE wl.source_id = 'specific-upload-uuid';
```

**User activity earning history:**
```sql
SELECT 
  aul.submitted_at,
  am.activity_name,
  aul.field_values,
  aul.points_awarded,
  wl.balance_after
FROM activity_upload_ledger aul
JOIN activity_master am ON aul.activity_id = am.id
LEFT JOIN wallet_ledger wl ON wl.source_id = aul.id AND wl.source_type = 'activity'
WHERE aul.user_id = 'user-uuid'
  AND aul.status = 'approved'
ORDER BY aul.submitted_at DESC;
```

---

## Frequency Limits

### Configuration via transaction_limits

**Reuses existing table** with `entity_type='activity'`:

```sql
-- Example: Max 1 upload per user per day
INSERT INTO transaction_limits (
  merchant_id,
  entity_type,
  entity_id,        -- activity_master.id
  scope,            -- 'user' or 'total'
  count,            -- Max uploads
  time_unit,        -- 'day', 'week', 'month', 'year'
  time_value,       -- Usually 1
  active_status
) VALUES (
  'merchant-uuid',
  'activity',
  'exercise-activity-uuid',
  'user',
  1,                -- 1 upload
  'day',            -- per day
  1,
  true
);
```

**Dual Validation:**
1. **Upload time** - `upload_activity_image()` checks limits before creating record
2. **Approval time** - `bff_approve_activity_upload()` re-checks limits (prevents race conditions)

**Supported Patterns:**
- ✅ Per user per day/week/month/year
- ✅ Total (global) per period
- ✅ Lifetime limits
- ✅ Multiple limits per activity (e.g., 1/day AND 7/week AND 30/month)

---

## API Reference

### Primary Function: `api_get_activity_full()`

Returns complete activity configuration with pivot table structure optimized for WeWeb Data Grid.

**Parameters:**
- `p_activity_id` (UUID) - Activity to fetch (NULL for new mode)
- `p_mode` (TEXT) - 'edit' (default) or 'new'

**Response Structure:**
```json
{
  "success": true,
  "title": null,
  "description": null,
  "columns": [
    {"headerName": "Type", "field": "secondary_value", "width": "250px", "editable": false},
    {"headerName": "L", "field": "L", "width": "200px", "editable": true},
    {"headerName": "M", "field": "M", "width": "200px", "editable": true},
    {"headerName": "S", "field": "S", "width": "200px", "editable": true}
  ],
  "config": {
    "id": "activity-uuid",
    "activity_code": "posm_check",
    "activity_name": "POSM Check Activity",
    "field_definitions": {
      "display_size": {
        "label": "Display Size",
        "options": ["S", "M", "L"],
        "required": true
      },
      "check_type": {
        "label": "Check Type",
        "options": ["plan_correct", "posm_check"],
        "required": true
      }
    },
    "primary_dimension": "display_size",
    "limits": [
      {"scope": "user", "count": 1, "time_unit": "month"}
    ],
    "matrices": [
      {
        "secondary_field": "check_type",
        "label": "Check Type",
        "data": [
          {"secondary_value": "plan_correct", "L": 600, "M": 300, "S": 200},
          {"secondary_value": "posm_check", "L": 300, "M": 200, "S": 100}
        ]
      }
    ]
  }
}
```

**Key Structure:**
- `columns` - Shared column definitions (Type + primary dimension values)
- `config.matrices` - Array of pivot tables (one per secondary field)
- `config.matrices[].data` - Pivoted rows with primary values as properties

---

## API Usage

### 1. User Upload Activity

**Endpoint:** `POST /rest/v1/rpc/upload_activity_image`

**Request:**
```json
{
  "p_activity_id": "exercise-uuid",
  "p_image_url": "https://storage.supabase.co/bucket/user-123/exercise.jpg"
}
```

**Response (Success):**
```json
{
  "success": true,
  "title": "Activity uploaded successfully",
  "description": "Your submission is pending admin approval",
  "data": {
    "upload_id": "upload-uuid",
    "activity_name": "Exercise Activity",
    "status": "pending"
  }
}
```

**Response (Limit Exceeded):**
```json
{
  "success": false,
  "title": "Upload limit reached",
  "description": "You have reached the limit of 1 uploads per day. Next available: 2026-01-23 14:30",
  "data": {
    "current_count": 1,
    "max_allowed": 1,
    "time_unit": "day",
    "next_available_at": "2026-01-23T14:30:00Z"
  }
}
```

---

### 2. Admin Approve Upload

**Endpoint:** `POST /rest/v1/rpc/bff_approve_activity_upload`

**Request:**
```json
{
  "p_upload_id": "upload-uuid",
  "p_field_values": {
    "exercise_type": "yoga",
    "time_of_day": "morning",
    "location": "central"
  }
}
```

**Response (Success):**
```json
{
  "success": true,
  "title": "Activity approved",
  "description": "Awarded 50 points",
  "data": {
    "upload_id": "upload-uuid",
    "points_awarded": 50,
    "tickets_awarded": [
      {
        "ticket_type_id": "raffle-uuid",
        "amount": 2
      }
    ],
    "field_values": {
      "exercise_type": "yoga",
      "time_of_day": "morning",
      "location": "central"
    }
  }
}
```

**Response (Validation Error):**
```json
{
  "success": false,
  "title": "Invalid field values",
  "description": "Some required fields are missing or have invalid values",
  "data": {
    "missing_fields": ["time_of_day"],
    "invalid_values": {
      "exercise_type": {
        "provided": "dancing",
        "allowed": ["yoga", "running", "swimming"]
      }
    }
  }
}
```

---

### 3. Admin Get Pending Uploads

**Endpoint:** `POST /rest/v1/rpc/bff_get_activity_uploads`

**Request:**
```json
{
  "p_status_filter": "pending",
  "p_activity_id": null,
  "p_limit": 50,
  "p_offset": 0
}
```

**Response:**
```json
{
  "success": true,
  "title": null,
  "description": null,
  "data": {
    "uploads": [
      {
        "upload_id": "uuid",
        "user_id": "user-uuid",
        "user_name": "John Doe",
        "user_phone": "0812345678",
        "activity_id": "exercise-uuid",
        "activity_name": "Exercise Activity",
        "image_url": "https://...",
        "field_values": null,
        "status": "pending",
        "submitted_at": "2026-01-22T10:30:00Z",
        "approved_at": null,
        "points_awarded": 0,
        "tickets_awarded": 0
      }
    ],
    "total_count": 15,
    "limit": 50,
    "offset": 0
  }
}
```

---

### 4. Get Matrix Configuration (For FE Rendering)

**Endpoint:** `POST /rest/v1/rpc/bff_get_activity_matrix`

**Request:**
```json
{
  "p_activity_id": "exercise-uuid"
}
```

**Response:**
```json
{
  "success": true,
  "title": null,
  "description": null,
  "data": {
    "activity_id": "exercise-uuid",
    "activity_name": "Exercise Activity",
    "primary_dimension": "time_of_day",
    "field_definitions": {
      "exercise_type": {
        "label": "Type of Exercise",
        "options": ["yoga", "running", "swimming"],
        "required": true
      },
      "time_of_day": {
        "label": "Time",
        "options": ["morning", "evening"],
        "required": true
      }
    },
    "matrix": [
      {
        "id": "config-uuid-1",
        "primary_value": "morning",
        "secondary_field": "exercise_type",
        "secondary_value": "yoga",
        "points_amount": 50,
        "ticket_type_id": null,
        "ticket_amount": 0
      },
      {
        "id": "config-uuid-2",
        "primary_value": "morning",
        "secondary_field": "exercise_type",
        "secondary_value": "running",
        "points_amount": 60,
        "ticket_type_id": "raffle-uuid",
        "ticket_amount": 2
      },
      {
        "id": "config-uuid-3",
        "primary_value": "evening",
        "secondary_field": "exercise_type",
        "secondary_value": "yoga",
        "points_amount": 40,
        "ticket_type_id": null,
        "ticket_amount": 0
      }
    ]
  }
}
```

**Frontend can render as table:**
```
              | Yoga  | Running | Swimming
--------------+-------+---------+---------
Morning       | 50pts | 60pts   | 70pts
              |       | +2 tix  |
--------------+-------+---------+---------
Evening       | 40pts | 55pts   | 65pts
```

---

### 5. Update Matrix Configuration

**Endpoint:** `POST /rest/v1/rpc/bff_upsert_activity_currency_matrix`

**Request:**
```json
{
  "p_activity_id": "exercise-uuid",
  "p_matrix_configs": [
    {
      "id": "existing-uuid-1",
      "primary_value": "morning",
      "secondary_field": "exercise_type",
      "secondary_value": "yoga",
      "points_amount": 55,
      "ticket_type_id": null,
      "ticket_amount": 0,
      "active_status": true
    },
    {
      "primary_value": "evening",
      "secondary_field": "location",
      "secondary_value": "central",
      "points_amount": 30,
      "ticket_type_id": "raffle-uuid",
      "ticket_amount": 1,
      "active_status": true
    }
  ]
}
```

**Note:** 
- Include `id` to update existing config (preserves ID)
- Omit `id` to create new config
- Configs not in array are deleted

**Response:**
```json
{
  "success": true,
  "title": "Matrix updated successfully",
  "description": null,
  "data": {
    "activity_id": "exercise-uuid",
    "children_created": 1,
    "children_updated": 1,
    "children_deleted": 0,
    "children_skipped": 0
  }
}
```

---

## Why Direct Currency Award Works

### Comparison to Other Source Types

| Source Type | Flow | Reason |
|-------------|------|--------|
| `purchase` | Outbox → Inngest currency routers → chokepoint | Async earn from purchase ledger |
| `mission` | Mission / outcome routers → chokepoint | Async completion awards |
| `reward_redemption` | **Direct `chokepoint_post_wallet_transaction()`** | Synchronous user action |
| `manual` | **Direct `chokepoint_post_wallet_transaction()`** | Synchronous admin action |
| **`activity`** | **Direct `chokepoint_post_wallet_transaction()`** | Synchronous admin action |

### Why Direct Call for Activities

- Admin approval is synchronous — admin waits for result
- Immediate feedback needed — did currency award succeed or fail?
- Same pattern as `redeem_reward_with_points()`
- No async router hop for the award itself
- Full audit trail in `wallet_ledger` metadata
- Atomic with rollback on failure

### Complete wallet_ledger Population

**All required fields properly set:**
- `source_type: 'activity'` — clear source identification
- `source_id: upload_id` — traceable to exact submission
- `component: 'base'` — standard earned currency
- `transaction_type: 'earn'`
- `target_entity_id` — NULL for points, ticket_type_id for tickets
- `metadata` — field_values, matrix match, approval context
- `expiry_date` — calculated by chokepoint
- `balance_before/after` — balance snapshots

Same audit capability as the async earn path.

---

## Production Examples

### Example 1: newcrm - Exercise Activity

**Activity ID:** `6ab7256a-e86f-45f9-8be0-23416fe1ceeb`  
**Merchant:** newcrm (`09b45463-3812-42fb-9c7f-9d43b6fd3eb9`)

**Fields:**
- `exercise_type` (required): yoga, running, swimming, cycling, gym
- `time_of_day` (required): morning, afternoon, evening
- `location` (optional): home, gym, outdoor, studio
- `duration` (optional): 15min, 30min, 45min, 60min, 90min

**Primary Dimension:** `time_of_day` (creates columns: Morning, Afternoon, Evening)

**Matrix 1 - Exercise Type:**
```
Type      | Morning | Afternoon | Evening
----------+---------+-----------+--------
yoga      |   50    |    45     |   40
running   |   60    |    50     |   45
swimming  |   55    |    48     |   42
cycling   |   58    |    52     |   47
gym       |   52    |    46     |   43
```

**Matrix 2 - Location:**
```
Type      | Morning | Afternoon | Evening
----------+---------+-----------+--------
home      |   25    |    22     |   20
gym       |   30    |    28     |   25
outdoor   |   35    |    32     |   28
studio    |   32    |    30     |   27
```

**Limits:**
- 1 upload per user per day
- 7 uploads per user per week
- 500 total uploads per month (global)

**Total Matrix Cells:** 27 (15 exercise + 12 location)

---

### Example 2: Ajinomoto - POSM Check Activity

**Activity ID:** `f9a7a998-5e7a-436b-b612-dad2c9a30dc6`  
**Merchant:** Ajinomoto (`99e456a2-107c-48c5-a12d-2b8b8b85aa2d`)

**Fields:**
- `display_size` (required): S, M, L
- `check_type` (required): plan_correct, posm_check

**Primary Dimension:** `display_size` (creates columns: L, M, S)

**Matrix - Check Type:**
```
Type          | L   | M   | S
--------------+-----+-----+-----
plan_correct  | 600 | 300 | 200
posm_check    | 300 | 200 | 100
```

**Limits:**
- 1 upload per user per calendar month

**Total Matrix Cells:** 6 (2 types × 3 sizes)

**API Call:**
```bash
curl -X POST 'https://wkevmsedchftztoolkmi.supabase.co/rest/v1/rpc/api_get_activity_full' \
  -H "apikey: YOUR_KEY" \
  -H "x-merchant-id: 99e456a2-107c-48c5-a12d-2b8b8b85aa2d" \
  -H "Content-Type: application/json" \
  -d '{"p_activity_id": "f9a7a998-5e7a-436b-b612-dad2c9a30dc6"}'
```

---

## Configuration Examples

### Example 3: Create New Activity via API

**Activity Definition:**
```sql
INSERT INTO activity_master (
  merchant_id, activity_code, activity_name,
  field_definitions, primary_dimension
) VALUES (
  'merchant-uuid',
  'exercise',
  'Exercise Activity',
  '{
    "exercise_type": {
      "label": "Exercise Type",
      "options": ["yoga", "running", "swimming"],
      "required": true
    },
    "time_of_day": {
      "label": "Time",
      "options": ["morning", "evening"],
      "required": true
    }
  }'::jsonb,
  'time_of_day'
);
```

**Currency Matrix:**
```sql
-- Morning yoga: 50 points
-- Morning running: 60 points
-- Evening yoga: 40 points
-- Evening running: 55 points
```

**Frequency Limit:**
```sql
-- Max 1 upload per user per day
INSERT INTO transaction_limits (
  merchant_id, entity_type, entity_id,
  scope, count, time_unit, time_value
) VALUES (
  'merchant-uuid', 'activity', 'exercise-activity-uuid',
  'user', 1, 'day', 1
);
```

---

### Example 2: Multi-Matrix with Tickets

**Activity:** Volunteer Work

**Fields:**
- `volunteer_type`: ["teaching", "cleanup", "donation"]
- `duration`: ["short", "medium", "long"]
- `location`: ["urban", "rural"]

**Primary Dimension:** `duration`

**Matrix 1:** duration × volunteer_type
```
         | Teaching | Cleanup | Donation
---------+----------+---------+---------
Short    | 20pts    | 15pts   | 25pts
Medium   | 50pts    | 40pts   | 60pts
Long     | 100pts   | 80pts   | 120pts
```

**Matrix 2:** duration × location (with tickets!)
```
         | Urban          | Rural
---------+----------------+------------------
Short    | 10pts          | 15pts + 1 ticket
Medium   | 25pts          | 35pts + 2 tickets
Long     | 50pts + 1 tix  | 70pts + 3 tickets
```

**Implementation:**
- All stored in same `activity_currency_config` table
- Differentiated by `secondary_field` ('volunteer_type' vs 'location')
- FE groups by secondary_field to render separate matrices

---

## Business Rules

### Core Rules

1. **Field Validation**
   - Required fields must be filled by admin
   - Values must be in defined options list
   - Validation at approval time (not upload time)

2. **Currency Calculation**
   - Matches `field_values` against `activity_currency_config`
   - Primary dimension value must match `primary_value`
   - Secondary field and value must match exactly
   - Can award multiple currencies per upload (points + tickets)

3. **Frequency Limits**
   - Validated at upload (user-facing error)
   - Re-validated at approval (admin-facing error)
   - Counts both 'pending' and 'approved' uploads in window
   - Prevents race conditions

4. **Status Workflow**
   - `pending` → User submitted, awaiting review
   - `approved` → Admin approved, currency awarded
   - `rejected` → Admin rejected, no currency
   - `cancelled` → User cancelled before review

5. **Direct Currency Award**
   - Uses `chokepoint_post_wallet_transaction()` directly
   - Sync chokepoint award (wallet outbox may still emit for tier/notification/AMP)
   - Same pattern as `redeem_reward_with_points()`
   - Atomic transaction: approval + currency award together
   - Rollback if currency award fails

---

## WeWeb Data Grid Integration

### Load Activity Configuration

```javascript
// Single RPC call
const response = await supabase.rpc('api_get_activity_full', {
  p_activity_id: 'activity-uuid',
  p_mode: 'edit'
});

// Response structure
const columns = response.columns;          // Shared columns
const config = response.config;            // Activity config
const matrices = response.config.matrices; // Array of pivot tables
```

### Bind to Repeater with Grids

**Repeater Setup:**
- **Data source:** `response.config.matrices`
- **Item variable:** `matrix`

**Inside Each Repeater Item:**

**1. Matrix Label/Heading:**
```javascript
heading.text = matrix.label;  // "Check Type", "Exercise Type", etc.
```

**2. Data Grid Binding:**
```javascript
// Columns (same for all grids - bind from parent context)
dataGrid.columns = response.columns;

// Data (different per matrix)
dataGrid.data = matrix.data;
```

### Handle Cell Edits

**On Cell Value Changed Event:**

```javascript
// Calculate row index
const matrixIndex = context.item.index;  // From repeater

const rowIndex = variables['your-variable-id']
  .config
  .matrices[matrixIndex]
  .data
  .findIndex(row => row.secondary_value === event.row.secondary_value);

// Update entire row
const updatedRow = {
  ...event.row,
  [event.columnId]: event.newValue
};

// Execute edit action
executeAction({
  action: 'edit',
  group: 'matrices',
  index: matrixIndex,
  nested_field: 'data',
  nested_index: rowIndex,
  value: updatedRow
});
```

**What This Does:**
- Finds which row was edited (by matching `secondary_value`)
- Updates the changed field in the row object
- Replaces entire row in state (LEVEL 3.5 edit pattern)
- Triggers 3-second debounced save

---

## Frontend Integration Patterns

### User Upload Flow (Customer App)

```javascript
// Check user can upload (optional - backend validates anyway)
const canUpload = await checkUploadAvailable(activityId);

// Upload image to storage
const imageUrl = await uploadToSupabaseStorage(file);

// Submit activity
const { data } = await supabase.rpc('upload_activity_image', {
  p_activity_id: activityId,
  p_image_url: imageUrl
});

if (data.success) {
  showToast(data.title, data.description, 'success');
} else {
  showToast(data.title, data.description, 'error');
  // Show next_available_at from data if limit exceeded
}
```

---

### Admin Approval Flow (Admin UI)

```javascript
// Get pending uploads
const { data } = await supabase.rpc('bff_get_activity_uploads', {
  p_status_filter: 'pending',
  p_limit: 50,
  p_offset: 0
});

const pendingUploads = data.data.uploads;

// Admin selects upload, fills in field values
const fieldValues = {
  exercise_type: 'yoga',
  time_of_day: 'morning',
  location: 'central'
};

// Approve with field values
const result = await supabase.rpc('bff_approve_activity_upload', {
  p_upload_id: selectedUpload.upload_id,
  p_field_values: fieldValues
});

if (result.success) {
  showToast(
    result.title, 
    `Awarded ${result.data.points_awarded} points`,
    'success'
  );
  refreshPendingList();
} else {
  showToast(result.title, result.description, 'error');
}
```

---

### Matrix Configuration Flow (Admin UI)

```javascript
// Fetch current matrix
const { data } = await supabase.rpc('bff_get_activity_matrix', {
  p_activity_id: activityId
});

const fieldDefs = data.data.field_definitions;
const matrix = data.data.matrix;
const primaryDim = data.data.primary_dimension;

// Render matrix table
// Rows: primary_dimension values (morning, evening)
// Columns: secondary field values (yoga, running, swimming)
const primaryValues = [...new Set(matrix.map(m => m.primary_value))];
const secondaryField = 'exercise_type'; // Can switch between fields
const secondaryValues = fieldDefs[secondaryField].options;

// Build grid
const grid = {};
primaryValues.forEach(pv => {
  grid[pv] = {};
  secondaryValues.forEach(sv => {
    const cell = matrix.find(m => 
      m.primary_value === pv && 
      m.secondary_field === secondaryField &&
      m.secondary_value === sv
    );
    grid[pv][sv] = cell || { points_amount: 0 };
  });
});

// Admin edits cells
grid['morning']['yoga'].points_amount = 55;

// Convert back to array for save
const matrixArray = [];
Object.entries(grid).forEach(([primary, secondaries]) => {
  Object.entries(secondaries).forEach(([secondary, config]) => {
    matrixArray.push({
      id: config.id, // Include ID for update, omit for create
      primary_value: primary,
      secondary_field: secondaryField,
      secondary_value: secondary,
      points_amount: config.points_amount,
      ticket_type_id: config.ticket_type_id,
      ticket_amount: config.ticket_amount || 0
    });
  });
});

// Save matrix
await supabase.rpc('bff_upsert_activity_currency_matrix', {
  p_activity_id: activityId,
  p_matrix_configs: matrixArray
});
```

---

## Monitoring & Analytics

### Admin Dashboard Queries

**Pending uploads count:**
```sql
SELECT COUNT(*) FROM activity_upload_ledger
WHERE merchant_id = get_current_merchant_id()
  AND status = 'pending';
```

**Activity earnings report:**
```sql
SELECT 
  am.activity_name,
  COUNT(DISTINCT aul.user_id) as unique_users,
  COUNT(*) as total_uploads,
  SUM(aul.points_awarded) as total_points,
  SUM(aul.tickets_awarded) as total_tickets
FROM activity_upload_ledger aul
JOIN activity_master am ON aul.activity_id = am.id
WHERE aul.merchant_id = get_current_merchant_id()
  AND aul.status = 'approved'
  AND aul.submitted_at >= NOW() - INTERVAL '30 days'
GROUP BY am.activity_name;
```

**User activity leaderboard:**
```sql
SELECT 
  ua.fullname,
  COUNT(*) as upload_count,
  SUM(aul.points_awarded) as total_points_earned
FROM activity_upload_ledger aul
JOIN user_accounts ua ON aul.user_id = ua.id
WHERE aul.merchant_id = get_current_merchant_id()
  AND aul.status = 'approved'
  AND aul.submitted_at >= NOW() - INTERVAL '7 days'
GROUP BY ua.id, ua.fullname
ORDER BY total_points_earned DESC
LIMIT 10;
```

---

## Migration Checklist

- [ ] Run migration `009_activity_based_earning.sql`
- [ ] Verify enum extension: `wallet_transaction_source_type` includes 'activity'
- [ ] Verify enum extension: `entity_type` includes 'activity'
- [ ] Test RLS policies with WeWeb user context
- [ ] Create sample activity type with field definitions
- [ ] Configure sample currency matrix
- [ ] Set up frequency limits
- [ ] Test user upload flow
- [ ] Test admin approval flow
- [ ] Verify currency appears in wallet_ledger with proper source_type

---

## Extension Points

### Future Enhancements

**Multi-image uploads:**
- Change `image_url` to `image_urls TEXT[]`
- Support before/after photos, multiple angles

**Auto-approval rules:**
- Add `auto_approve_conditions` JSONB to activity_master
- Auto-approve if conditions met (e.g., trusted users)

**GPS validation:**
- Add `location_coordinates` to upload_ledger
- Validate location against activity requirements

**OCR integration:**
- Auto-extract field values from image (if text-based)
- Pre-fill for admin review

**Batch approval:**
- Function to approve multiple uploads at once
- Bulk limit validation

---

## Summary

### Key Architectural Decisions

**1. Typed Columns vs JSONB**
- Decision: Use typed columns (`primary_value`, `secondary_field`, `secondary_value`)
- Rationale: Easier FE integration, simpler queries, better performance
- Trade-off: Fixed to 2-dimension matrices (acceptable for current use cases)

**2. Direct Currency Award**
- Decision: Call `chokepoint_post_wallet_transaction()` directly in approval function
- Rationale: Synchronous admin action, immediate feedback, same pattern as rewards
- Result: No async earn-router hop for the award; wallet outbox still emits for tier/notification/AMP unless skipped

**3. Pivot Table Response**
- Decision: Return both raw data (`currency_matrices`) and pivoted grid data
- Structure: Columns generated dynamically from primary dimension options
- Rationale: True matrix visualization in admin UI

**4. Multiple Grids per Activity**
- Structure: Array of matrices, one per secondary field
- Display: Repeater with separate grid for each matrix
- Rationale: Supports multiple matrix views (time×exercise, time×location)

**5. Frequency Limits**
- Decision: Reuse existing `transaction_limits` table
- Added: `'activity'` to entity_type enum
- Validation: Dual check (upload + approval) for race condition protection

### Function List

| Function | Purpose | Caller |
|----------|---------|--------|
| `api_get_activity_full` | Get activity with pivot grid data | Admin UI |
| `api_get_activity_display` / `api_get_my_activity_uploads` | User-facing activity views | Customer app |
| `upload_activity_image` | User upload | Customer app |
| `bff_approve_activity_upload` | Approve + award currency | Admin UI |
| `bff_edit_activity_upload` | Edit approved/rejected + wallet delta | Admin UI |
| `bff_reject_activity_upload` | Reject upload | Admin UI |
| `bff_get_activity_uploads` | List uploads | Admin UI |
| `bff_upsert_activity_master` / `bff_upsert_activity_currency_matrix` | Create/update activity + matrix | Admin UI |
| `fn_calculate_activity_currency` / `fn_check_activity_upload_limits` / `fn_check_activity_approval_limits` | Award + limit helpers | Internal |

### Database Tables

| Table | Purpose |
|-------|---------|
| `activity_master` | Activity type definitions |
| `activity_currency_config` | Matrix cells (currency awards) |
| `activity_upload_ledger` | User submissions |
| `transaction_limits` | Frequency limits (`entity_type = activity`) |

**Disambiguation:** upload earning (`activity_master`) ≠ CDP log (`activity_ledger`) ≠ report grouping (`campaign_activity`).

---

*Document Version: 2.1*  
*Last Updated: 2026-08-09*  
*System: Supabase CRM - Activity-Based Earning*  
*Architecture: Direct currency award with pivot table display*  
*Production: 2 activities configured (newcrm Exercise, Ajinomoto POSM)*

