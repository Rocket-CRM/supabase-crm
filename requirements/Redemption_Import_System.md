# Redemption Import System

## System Overview

The Redemption Import System enables bulk importing of historical or admin-created reward redemptions from CSV files via HTTP API. The system supports two transaction modes — **all-or-nothing** and **per-row** — with configurable action types (redeem only vs redeem and use), optional points deduction, and comprehensive failure tracking per row.

**Scale**: Supports up to 500,000 redemption rows per import via chunked async processing.

**Why Inngest + Render?** Same reasons as Customer and Purchase imports: CSV file handling requires a real HTTP server (Render), and processing hundreds of thousands of rows requires a long-running workflow with per-step retry capability that survives beyond a single HTTP request timeout (Inngest). The infrastructure already exists — this adds a new import type to the same services.

---

## Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                      CLIENT REQUEST                              │
│  curl POST /api/import/redemptions + CSV file                    │
└──────────────────────┬──────────────────────────────────────────┘
                       │
                       ▼
┌─────────────────────────────────────────────────────────────────┐
│  RENDER WEB SERVICE (crm-bulk-import)                           │
│                                                                  │
│  1. Accept multipart/form-data (max 100MB)                      │
│  2. Validate: merchant_id required                              │
│  3. Parse CSV with PapaParser                                   │
│  4. Validate import-level params:                               │
│     - transaction_mode: 'all_or_nothing' | 'per_row'           │
│     - Warn if all_or_nothing + rows > 5,000                    │
│  5. Create bulk_import_batches record (status: pending)         │
│  6. Publish 'import/bulk-redemptions' event to Inngest          │
│  7. Delete temp file                                            │
│  8. Return batch_id                                             │
└──────────────────────┬──────────────────────────────────────────┘
                       │ Event: import/bulk-redemptions
                       ▼
┌─────────────────────────────────────────────────────────────────┐
│  INNGEST CLOUD (Workflow Orchestrator)                          │
│  Function: bulk-import-redemptions                              │
│  Timeout: 2 hours   Retries: 1 per step                        │
│                                                                  │
│  Step 1: update-status-processing                               │
│  Step 2: validate-headers                                       │
│  Step 3: resolve-users     (batch DB lookup)                    │
│  Step 4: validate-rewards  (batch DB lookup)                    │
│  Step 5-N: process-chunk-{n} (500 rows each)                   │
│  Step N+1: update-status-completed                              │
└──────────────────────┬──────────────────────────────────────────┘
                       │ RPC per chunk
                       ▼
┌─────────────────────────────────────────────────────────────────┐
│  SUPABASE (inngest-bulk-import-redemptions-serve edge function)             │
│                                                                  │
│  Function: bulk_import_redemptions_chunk()                      │
│                                                                  │
│  Per-chunk (500 rows):                                          │
│  - If all_or_nothing: single BEGIN/COMMIT, any fail = ROLLBACK  │
│  - If per_row: SAVEPOINT per row, failures collected, skipped   │
│  - For each row: call redeem_reward_with_points() internally    │
│  - Returns: succeeded_count, failed_rows array                  │
│                                                                  │
│  Batch record updated with cumulative progress after each chunk │
└─────────────────────────────────────────────────────────────────┘
```

---

## Key Design Decisions

### 1. Transaction Mode (Import-Level Parameter)

Specified once for the entire batch at upload time:

| Mode | Behavior | When to Use |
|------|----------|-------------|
| `per_row` | Each row is independent. Failures collected, successes committed. Import completes even if some rows fail. | **Default. Recommended for all imports.** Historical data with mixed quality. Large batches. |
| `all_or_nothing` | Entire batch succeeds or fails together. Any single row failure rolls back the entire import. | Small audited batches (<5,000 rows) where partial state is unacceptable. |

**Important**: `all_or_nothing` is capped at 5,000 rows. Above this limit, the API returns a 400 error instructing the user to split the file or use `per_row`. A single database transaction processing 100K reward redemptions (each touching the wallet, ledger, and promo code tables) would exceed statement timeouts and lock the database.

With chunked processing (500 rows/chunk), `all_or_nothing` applies **within each chunk**. If a chunk fails, only that chunk's rows are rolled back — this is explained clearly to the user. True all-or-nothing across 100K rows is not architecturally feasible.

### 2. Action (Per-Row in CSV)

| Action | Effect |
|--------|--------|
| `redeem` | Creates `reward_redemptions_ledger` record with `redeemed_status = true`, `used_status = false`. Points deducted if mode=`calc`. |
| `redeem_and_use` | Same as above, plus `used_status = true` and `used_at = redeemed_at`. For pre-consumed vouchers or historical data where voucher was already used. |

### 3. Mode (Per-Row in CSV)

| Mode | Eligibility Checks | Points Deducted | Use Case |
|------|-------------------|-----------------|----------|
| `direct` | **None** | **No** | Admin grants, historical backfill, offline event redemptions, mission rewards. |
| `calc` | Full (tier, persona, tags, window) | **Yes**, uses multi-dimensional matching engine | Live redemption replay, testing, user-initiated historic re-import. |

**Default**: `direct` (the overwhelmingly common use case for imports is historical backfill where points were already deducted in another system, or admin-granted rewards with no cost).

### 4. Async with Status Tracking

Redemption import is fully asynchronous. The API returns a `batch_id` immediately. Progress is tracked in `bulk_import_batches` and polled via the existing `/api/import/status/:batch_id` endpoint.

**Why async is required**: Processing 100K rows at 10–50ms per row = 17–83 minutes of computation. No HTTP request can stay open that long.

**Per-row failure tracking**: The batch record stores a `row_errors` JSONB array in the `metadata` field, updated as chunks complete. Each entry includes the row number, the input data, and the reason for failure. A separate `failed_rows_count` and `succeeded_rows_count` column tracks progress numerically.

### 5. Chunking Strategy

Rows are processed in chunks of **500 rows** per Inngest step. This provides:
- **Resilience**: If one chunk's step fails, it retries that chunk independently without affecting completed chunks
- **Progress visibility**: `bulk_import_batches.processed_rows` updated after each chunk completes
- **Memory safety**: Edge function never holds more than 500 redemption objects in memory
- **Database safety**: No single transaction exceeds ~500 wallet operations

For 100K rows: 200 chunks × ~2 seconds/chunk ≈ ~7 minutes end-to-end.

---

## `bulk_import_batches` Schema Additions

New columns added (migration required, additive only):

| Column | Type | Purpose |
|--------|------|---------|
| `succeeded_rows` | integer | Count of rows successfully processed |
| `failed_rows_count` | integer | Count of rows that failed |
| `processed_rows` | integer | Running total: succeeded + failed so far |
| `row_errors` | jsonb | Array of `{row, user_id, reward_id, reason, error_code}` — up to 1,000 entries |

`import_type` new value: `'redemptions'`

---

## CSV Format Specification

### Column Reference

| Column | Required | Values / Format | Notes |
|--------|----------|-----------------|-------|
| `user_id` | One of `user_id`, `tel`, or `email` required | UUID | Direct user ID match |
| `tel` | One of three | E.164 format (+66812345678) | Resolved to user_id via user_accounts |
| `email` | One of three | Email string | Resolved to user_id via user_accounts |
| `reward_id` | **Yes** | UUID | Must exist for merchant |
| `quantity` | No | Integer 1–1000 | Default: 1 |
| `mode` | No | `direct` or `calc` | Default: `direct` |
| `action` | No | `redeem` or `redeem_and_use` | Default: `redeem` |
| `redeemed_at` | No | ISO8601 timestamp | Default: NOW(). Used for backdating. |
| `used_at` | No | ISO8601 timestamp | Only applies when `action=redeem_and_use`. Default: same as `redeemed_at`. |
| `notes` | No | Free text | Stored in redemption ledger metadata |
| `source_type` | No | `manual`, `import`, `mission`, etc. | Stored in ledger for audit trail |
| `source_id` | No | UUID | Reference ID for the source (e.g. campaign ID) |

### User Resolution Priority

When resolving a user, the system checks in this order:
1. `user_id` (direct match, fastest)
2. `tel` (phone lookup within merchant)
3. `email` (email lookup within merchant)

If multiple match, first found wins. If none match → row fails with `USER_NOT_FOUND`.

### Sample CSV

```csv
user_id,reward_id,quantity,mode,action,redeemed_at,notes
7faab812-e179-48c2-9707-0d8a9b2f84ea,abc12345-0000-0000-0000-000000000001,1,direct,redeem,2024-01-15T10:00:00Z,Historical event Jan 2024
,abc12345-0000-0000-0000-000000000001,1,direct,redeem_and_use,2024-01-15T11:00:00Z,Used same day
+66812345678,abc12345-0000-0000-0000-000000000002,2,direct,redeem,,Offline counter
user@example.com,abc12345-0000-0000-0000-000000000003,1,calc,redeem,,Live deduction
```

**Row 1**: Direct user_id. Historical redeem. Points NOT deducted (`direct`). Not yet used.  
**Row 2**: User identified by tel. Points NOT deducted. Already used (`redeem_and_use`).  
**Row 3**: User by phone. Quantity 2. No redeemed_at → defaults to NOW().  
**Row 4**: User by email. Points WILL be deducted (`calc`). Eligibility checks run.

### Special Value Handling (consistent with other imports)

- Empty string → treated as not provided (use default)
- `-` → treated as NULL / not provided
- `quantity` < 1 or > 1000 → validation error
- Invalid UUID format for `user_id`, `reward_id` → validation error
- Invalid timestamp for `redeemed_at` → validation error

---

## API Specification

### POST /api/import/redemptions

**Request Format**: `multipart/form-data`

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `file` | File | Yes | CSV file (max 100MB) |
| `merchant_id` | UUID | Yes | Target merchant |
| `batch_name` | String | No | Human label (defaults to filename) |
| `transaction_mode` | String | No | `per_row` (default) or `all_or_nothing` |
| `max_row_errors` | Integer | No | Stop after N row errors (default: unlimited). Only applies in `per_row` mode. |

**Example**:
```bash
curl -X POST https://PROJECT.supabase.co/functions/v1/admin-user-import-kickoff/api/import/redemptions \
  -F "file=@redemptions.csv" \
  -F "merchant_id=7faab812-e179-48c2-9707-0d8a9b2f84ea" \
  -F "batch_name=January 2024 Redemption Backfill" \
  -F "transaction_mode=per_row"
```

**Success Response** (HTTP 200):
```json
{
  "success": true,
  "batch_id": "uuid-here",
  "total_rows": 12450,
  "transaction_mode": "per_row",
  "message": "Redemption import started. Poll /api/import/status/uuid-here for progress."
}
```

**Error Responses**:
- `400`: Missing file or merchant_id
- `400`: CSV parse errors (malformed file)
- `400`: `all_or_nothing` selected with more than 5,000 rows
- `400`: Invalid `transaction_mode` value
- `500`: Batch creation or Inngest publish failed

---

### GET /api/import/status/:batch_id

Existing endpoint. Returns extended fields for redemption imports:

**Response - Processing (In Progress)**:
```json
{
  "id": "batch-uuid",
  "import_type": "redemptions",
  "status": "processing",
  "total_rows": 12450,
  "processed_rows": 3500,
  "succeeded_rows": 3480,
  "failed_rows_count": 20,
  "started_at": "2024-01-15T10:00:15Z"
}
```

**Response - Completed (Per-Row with some failures)**:
```json
{
  "id": "batch-uuid",
  "import_type": "redemptions",
  "status": "completed",
  "transaction_mode": "per_row",
  "total_rows": 12450,
  "processed_rows": 12450,
  "succeeded_rows": 12380,
  "failed_rows_count": 70,
  "started_at": "2024-01-15T10:00:15Z",
  "completed_at": "2024-01-15T10:08:42Z",
  "row_errors": [
    {
      "row": 45,
      "user_id": "uuid",
      "reward_id": "uuid",
      "error_code": "INSUFFICIENT_POINTS",
      "reason": "Required 200 points, user has 50"
    },
    {
      "row": 112,
      "tel": "+66811111111",
      "reward_id": "uuid",
      "error_code": "USER_NOT_FOUND",
      "reason": "No user found with tel +66811111111 for this merchant"
    },
    {
      "row": 890,
      "user_id": "uuid",
      "reward_id": "uuid",
      "error_code": "REWARD_NOT_FOUND",
      "reason": "Reward not found or not active for this merchant"
    }
  ],
  "metadata": {
    "total_error_count": 70,
    "errors_truncated": false
  }
}
```

**Response - Completed (All-or-Nothing, SUCCESS)**:
```json
{
  "id": "batch-uuid",
  "import_type": "redemptions",
  "status": "completed",
  "transaction_mode": "all_or_nothing",
  "total_rows": 500,
  "succeeded_rows": 500,
  "failed_rows_count": 0,
  "completed_at": "2024-01-15T10:02:10Z"
}
```

**Response - Failed (All-or-Nothing, one row caused rollback)**:
```json
{
  "id": "batch-uuid",
  "import_type": "redemptions",
  "status": "failed",
  "transaction_mode": "all_or_nothing",
  "total_rows": 500,
  "succeeded_rows": 0,
  "failed_rows_count": 1,
  "error_message": "Batch rolled back: Row 247 - INSUFFICIENT_POINTS: Required 500 points, user has 120",
  "row_errors": [
    {
      "row": 247,
      "user_id": "uuid",
      "reward_id": "uuid",
      "error_code": "INSUFFICIENT_POINTS",
      "reason": "Required 500 points, user has 120"
    }
  ]
}
```

---

## Inngest Workflow Design

**Event Name**: `import/bulk-redemptions`

**Function ID**: `bulk-import-redemptions`

**Timeout**: 2 hours (accommodates ~360K rows)  
**Retries**: 1 per step

### Workflow Steps

#### Step 1: update-status-processing
Update `bulk_import_batches` → `status = 'processing'`, `started_at = NOW()`.

#### Step 2: validate-headers
Validate every row in `csv_data` (in-memory, no DB writes):
- At least one of: `user_id`, `tel`, `email` present per row
- `reward_id` present and valid UUID format
- `quantity` is integer between 1–1000 (if provided)
- `mode` is `direct` or `calc` (if provided)
- `action` is `redeem` or `redeem_and_use` (if provided)
- `redeemed_at` is valid ISO8601 (if provided)
- `user_id` is valid UUID (if provided)

On header validation failure → update status to `validation_failed`, store errors, stop workflow. No DB changes have been made.

Returns first 100 validation errors (consistent with customer import behavior).

#### Step 3: resolve-users
Batch-resolve all user identifiers to `user_id` UUIDs. Single optimized query per identifier type:
- Collect all `user_id` values → validate exist in `user_accounts` for merchant
- Collect all `tel` values → resolve to UUIDs
- Collect all `email` values → resolve to UUIDs

Build a lookup map: `{identifier → user_id}`. Unknown identifiers marked as unresolvable.

In `all_or_nothing` mode: if ANY identifier fails to resolve → fail immediately before touching DB.  
In `per_row` mode: continue; rows with unresolvable users will fail as `USER_NOT_FOUND` during chunk processing.

#### Step 4: validate-rewards
Batch-resolve all `reward_id` values. Single query to `reward_master` where `merchant_id` matches.

Build a set of valid reward IDs.

In `all_or_nothing` mode: any unknown reward → fail immediately.  
In `per_row` mode: continue; rows with unknown rewards will fail as `REWARD_NOT_FOUND` during chunk processing.

#### Steps 5 to N: process-chunk-{n}
Split all rows into chunks of 500. Each chunk becomes its own Inngest step.

Each step calls `bulk_import_redemptions_chunk()` Supabase RPC with:
- The chunk rows (500 at a time)
- Pre-resolved user lookup map
- Merchant ID, batch ID
- `transaction_mode`

After each step:
- `processed_rows` incremented
- `succeeded_rows` incremented
- `failed_rows_count` incremented
- `row_errors` appended (if `per_row` mode)

**Step isolation**: Each chunk step is independently retried. If a chunk step fails due to a transient error (DB timeout, network issue), it retries with the same 500 rows. Idempotency is handled via `event_id`-based duplicate detection in the underlying redemption function.

#### Step N+1: update-status-completed
Final status update with all counts and summary.

---

## PostgreSQL Function

**Function**: `bulk_import_redemptions_chunk()`

**Signature**:
```sql
bulk_import_redemptions_chunk(
  p_rows          JSONB,     -- Array of up to 500 row objects
  p_user_map      JSONB,     -- Pre-resolved {identifier: user_id} lookup
  p_merchant_id   UUID,
  p_batch_id      UUID,
  p_transaction_mode TEXT    -- 'per_row' or 'all_or_nothing'
)
RETURNS JSONB  -- {succeeded_count, failed_rows: [{row, error_code, reason}]}
```

### Processing Logic

**For `per_row` mode**:
```
FOR EACH row in p_rows:
  BEGIN SAVEPOINT row_savepoint;
  
  1. Resolve user_id from p_user_map
  2. Set effective mode (direct/calc), action (redeem/redeem_and_use), quantity, redeemed_at
  3. Call redeem_reward_with_points(
       p_reward_id    := row.reward_id,
       p_quantity     := row.quantity,
       p_user_id      := resolved_user_id,
       p_merchant_id  := p_merchant_id,
       p_mode         := row.mode,  -- 'direct' or 'calc'
       p_source_type  := row.source_type,
       p_source_id    := row.source_id,
       p_event_id     := deterministic_uuid(p_batch_id, row_index)
     )
  4. IF result.success = false:
       ROLLBACK TO SAVEPOINT row_savepoint;
       Append to failed_rows: {row_index, error_code, reason}
     ELSE:
       IF action = 'redeem_and_use':
         UPDATE reward_redemptions_ledger
         SET used_status = true,
             used_at = COALESCE(row.used_at, row.redeemed_at, NOW())
         WHERE id = result.redemption_id
       RELEASE SAVEPOINT row_savepoint;
       succeeded_count := succeeded_count + 1
  
RETURN {succeeded_count, failed_rows}
```

**For `all_or_nothing` mode**:
```
BEGIN;
  FOR EACH row in p_rows:
    [same logic, but NO savepoints]
    IF any row fails: RAISE EXCEPTION with row details
COMMIT;

EXCEPTION:
  ROLLBACK;
  RETURN {succeeded_count: 0, failed_rows: [failed row details]}
```

### Deterministic Event ID

To ensure chunk step retries are idempotent (no duplicate redemptions on retry), each row's `event_id` is computed deterministically:

```
event_id = uuid_v5(namespace=batch_id, name=str(row_index))
```

This means re-running the same chunk produces the same event IDs, which the existing `redeem_reward_with_points` idempotency check will detect and return the already-processed redemption.

### Backdating (`redeemed_at`)

When `row.redeemed_at` is provided:
- The redemption ledger record's `created_at` is set to `row.redeemed_at`
- `redeemed_at` is set to `row.redeemed_at`
- `used_at` is set to `row.used_at` (or same as `redeemed_at` for `redeem_and_use`)
- Wallet ledger `created_at` also backdated

This requires the PostgreSQL function to `INSERT` with explicit `created_at`, not rely on `DEFAULT NOW()`.

---

## Per-Row Error Codes

| Code | Meaning | Applies to Mode |
|------|---------|-----------------|
| `USER_NOT_FOUND` | No user found with given user_id / tel / email for this merchant | both |
| `REWARD_NOT_FOUND` | reward_id doesn't exist or isn't active for merchant | both |
| `INSUFFICIENT_POINTS` | User balance < points required | `calc` only |
| `ELIGIBILITY_FAILED` | Tier, persona, or tag requirement not met | `calc` only |
| `OUTSIDE_REDEMPTION_WINDOW` | Current time (or redeemed_at) outside reward's allowed window | `calc` only |
| `LIMIT_EXCEEDED` | User or global redemption limit already reached | `calc` only |
| `INSUFFICIENT_PROMO_CODES` | Reward requires unique codes but pool is exhausted | both |
| `INVALID_QUANTITY` | Quantity > 1 on a promo-code reward | both |
| `DUPLICATE` | Redemption already processed (idempotency hit) | both |
| `NO_POINTS_CONFIG` | `require_points_match=true` but no condition matched user | `calc` only |
| `UNKNOWN_ERROR` | Unexpected DB error for this row | both |

---

## Validation Rules Summary

### Import-Level (Checked at Upload / Step 2)

| Rule | Error |
|------|-------|
| At least one of user_id, tel, email per row | Row validation error |
| reward_id present and valid UUID | Row validation error |
| quantity integer 1–1000 | Row validation error |
| mode must be 'direct' or 'calc' | Row validation error |
| action must be 'redeem' or 'redeem_and_use' | Row validation error |
| redeemed_at must be valid ISO8601 if provided | Row validation error |
| all_or_nothing + total_rows > 5,000 | 400 at upload |

### Per-Row Processing (During Chunk Execution)

These are caught per row in `per_row` mode, and cause batch rollback in `all_or_nothing` mode:
- User must exist in merchant's account
- Reward must exist and belong to merchant
- If mode=`calc`: all eligibility, points balance, and limit checks from `redeem_reward_with_points`
- If promo codes required: pool must have sufficient codes
- If promo code reward: quantity must = 1

---

## Status Flow

```
pending  →  processing  →  completed      (success, all or some rows passed)
                        →  failed          (all_or_nothing rollback, or catastrophic system error)
                        →  validation_failed  (CSV header validation caught errors before any DB writes)
```

`completed` in `per_row` mode can include failed rows — check `failed_rows_count`. A completed import with `failed_rows_count > 0` means some rows were skipped.

---

## Timing Estimates

| Rows | Chunks | Estimated Duration | Notes |
|------|--------|--------------------|-------|
| 1,000 | 2 | ~20–30 seconds | |
| 10,000 | 20 | ~3–5 minutes | |
| 50,000 | 100 | ~12–20 minutes | |
| 100,000 | 200 | ~25–40 minutes | |
| 500,000 | 1,000 | ~2–3 hours | Near Inngest 2-hour timeout |

**Per-row cost**: Redemptions are heavier per row than customers or purchases because each row potentially touches 3–4 tables (wallet, ledger, promo codes). Budget ~100–200ms per row at the DB level.

**Recommendation**: Split imports > 100,000 rows into multiple files uploaded sequentially.

---

## Implementation Scope

### New Components Required

| Component | Type | Change |
|-----------|------|--------|
| `POST /api/import/redemptions` | Render route | **New** |
| `import/bulk-redemptions` Inngest event | Inngest | **New event** |
| `bulk-import-redemptions` Inngest function | Inngest | **Live** on `inngest-bulk-import-redemptions-serve` |
| `bulk_import_redemptions_chunk()` | PostgreSQL function | **New** |
| `bulk_import_batches` schema | PostgreSQL table | **Migration** to add 4 new columns |

### Existing Components Reused (No Changes)

| Component | Reused As-Is |
|-----------|-------------|
| `GET /api/import/status/:batch_id` | Status polling |
| `GET /api/import/list/:merchant_id` | Import history |
| `bulk_import_batches` table | Batch tracking (with added columns) |
| `inngest-bulk-import-redemptions-serve` edge function | Hosts redemptions import worker |
| `redeem_reward_with_points()` | Called internally per row |
| Render service infrastructure | New route added |

---

## Sample Use Cases

### Use Case 1: Historical Redemption Backfill (Most Common)

**Scenario**: Merchant migrating from legacy system. 50,000 historical voucher redemptions need to be imported. Points were already deducted in the old system.

**CSV**: `user_id`, `reward_id`, `quantity=1`, `mode=direct`, `action=redeem_and_use`, `redeemed_at` (historical timestamps)

**Import params**: `transaction_mode=per_row` (some old users may not exist, skip them)

**Outcome**: 50,000 redemption records created with historical dates. No points deducted. All marked as used. Rows where the user no longer exists in the system are logged as `USER_NOT_FOUND` failures.

---

### Use Case 2: Offline Event Voucher Distribution

**Scenario**: Trade show. 2,000 users received physical vouchers. Staff scanned their phone numbers. Now importing into the system.

**CSV**: `tel`, `reward_id`, `quantity=1`, `mode=direct`, `action=redeem`

**Import params**: `transaction_mode=per_row`

**Outcome**: Users resolved by phone number. 2,000 redemption records created. Users can later use their voucher (mark as used separately). A few rows with unrecognized phone numbers fail with `USER_NOT_FOUND`.

---

### Use Case 3: Admin Points-Deducting Batch (Audited)

**Scenario**: 200 customers won a promotion. Each must have 500 points deducted and a premium reward recorded.

**CSV**: `user_id`, `reward_id`, `quantity=1`, `mode=calc`, `action=redeem`

**Import params**: `transaction_mode=all_or_nothing` (all 200 must succeed or none)

**Outcome**: If all 200 users have sufficient points and meet eligibility → all 200 redemptions created, points deducted. If even one user has insufficient points → entire batch rolled back, error returned, no points deducted for anyone.

---

### Use Case 4: Promo Code Reward Assignment

**Scenario**: 500 customers need a unique promo code voucher reward assigned without deducting points.

**CSV**: `user_id`, `reward_id` (has `assign_promocode=true`), `quantity=1`, `mode=direct`, `action=redeem`

**Import params**: `transaction_mode=per_row`

**Outcome**: For each user, one unique promo code is pulled from the pool and assigned. If the pool runs out mid-batch, remaining rows fail with `INSUFFICIENT_PROMO_CODES`. Users who were processed successfully keep their codes.

---

## Downstream Effects

### When `mode = calc`
- `wallet_ledger` entry created (`transaction_type = burn`, `source_type = 'reward_redemption'`)
- `user_wallet.points_balance` reduced
- Existing cache invalidation triggers fire (`reward_redemptions_ledger` INSERT triggers Redis cache clear)

### When `mode = direct`
- No wallet changes
- No points deducted
- Redemption ledger record created as if admin granted it

### Downstream Events
Imported redemptions go through the same redemption write path as live redeems (`redeem_reward_with_points` / ledger inserts). Downstream mission/notification/AMP routers fire when chokepoint outbox events are emitted. Use `api_source = 'bulk_import'` (or equivalent metadata) to filter import-origin rows in analytics if needed.

---

## Row Errors Storage

`row_errors` in `bulk_import_batches.metadata` stores up to **1,000 error entries**. Beyond 1,000, errors continue to be counted in `failed_rows_count` but individual details are not stored (to avoid unbounded JSONB growth). The `metadata.errors_truncated` flag will be `true` if this cap was hit.

For imports with > 1,000 failures, the recommended resolution is to fix the source CSV and re-import.

---

## Security

- **Authentication**: Same as other import endpoints (currently API-key or open depending on deployment). Inngest webhook verified via `INNGEST_SIGNING_KEY`.
- **Data isolation**: All DB operations scoped to `merchant_id`. Merchant cannot affect other merchants' data.
- **Function security**: `bulk_import_redemptions_chunk()` uses `SECURITY DEFINER`, bypasses RLS (required to operate on behalf of users).
- **Audit trail**: `batch_id` stored in wallet_ledger metadata. Every imported redemption can be traced back to its import batch.

---

## Deployment Checklist

- [ ] **Migration**: Add `succeeded_rows`, `failed_rows_count`, `processed_rows`, `row_errors` columns to `bulk_import_batches`
- [ ] **PostgreSQL**: Deploy `bulk_import_redemptions_chunk()` function
- [ ] **Render service**: Add `POST /api/import/redemptions` route
- [ ] **Inngest function**: Write `bulk-import-redemptions` workflow
- [x] **Edge function**: `inngest-bulk-import-redemptions-serve` live
- [ ] **End-to-end test**: Small `per_row` CSV (10 rows, mix of valid and invalid)
- [ ] **End-to-end test**: `all_or_nothing` CSV (5 rows, all valid)
- [ ] **End-to-end test**: `all_or_nothing` CSV (5 rows, one with insufficient points → verify rollback)
- [ ] **Load test**: 10,000 row `per_row` import

---

*Document Version: 1.0*  
*Created: February 24, 2026*  
*System: Supabase CRM — Redemption Import System*
