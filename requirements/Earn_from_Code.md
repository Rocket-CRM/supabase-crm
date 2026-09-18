# Earn from Code

> **Sibling mechanic** (codes / bulk import / edges). Earn-page channel display ownership: [`Earn_Channel.md`](./Earn_Channel.md).


## Feature Overview

Earn from Code is a product-level loyalty mechanic where unique codes are physically attached to products (printed inside packaging, under caps, on stickers, etc.). Consumers scan or key in these codes to earn points. The system covers the full lifecycle: **bulk import** codes into the platform, **activate** them when products ship, let consumers **validate → claim → earn points**, and give admins tools to **manage, delete, and report** on the code pool.

### How It Works (Consumer Journey)

1. **Brand prints codes on products** — each physical unit gets a unique code (QR, Data Matrix, or alphanumeric) during manufacturing
2. **Codes are imported into the platform** — brand uploads CSV of codes with product metadata (SKU, price, points, batch, validity windows)
3. **Codes are activated** — admin activates codes by serial range when product batches ship
4. **Consumer buys the product** — finds the code inside packaging or under a cap
5. **Consumer scans or keys in the code** — via mobile app (camera scan or manual entry)
6. **System validates the code** — checks existence, activation, window, claimed status
7. **Points are awarded** — code is marked claimed, points credited to consumer's wallet, receipt created

### Entry Points for Consumers

| Method | How It Works | Edge Function |
|--------|-------------|---------------|
| **QR / Barcode Scan** | Camera opens, scans QR/Data Matrix/barcode on product → code extracted automatically | `scanner` (serves HTML scanner UI) |
| **Manual Key-in** | Consumer types the alphanumeric code printed on product | Frontend sends to `validate-codes-public` or `claim-codes-award-points-create-receipt` |
| **Store Staff Scan** | Sales rep scans codes at point of sale on behalf of consumer | `claim-codes` with `claimed_store_code` and `claimed_sales_code` |

---

## Architecture

```
┌─────────────────────────────────────────────────────────┐
│  CODE LIFECYCLE                                         │
│                                                         │
│  1. IMPORT        Render service / Edge function        │
│     CSV → codes_staging → process_code_import()         │
│     → codes table (activated=false or true)             │
│                                                         │
│  2. ACTIVATE      admin_activate_codes_by_serial_range()│
│     Set SKU, price, MFG date, expiry, activated=true    │
│                                                         │
│  3. VALIDATE      validate-codes-public (Edge)          │
│     Consumer scans/keys in → check existence, status    │
│                                                         │
│  4. CLAIM+EARN    claim-codes-award-points-create-      │
│                   receipt (Edge)                         │
│     Mark claimed → award points via currency system     │
│     → create receipt in CRM                             │
│                                                         │
│  5. MANAGE        Admin dashboard                       │
│     View, download, delete, rollback, problem reports   │
└─────────────────────────────────────────────────────────┘
```

---

## Database Schema

### **codes** (Production Table)

The main table storing all codes for all merchants. 21M+ rows in production.

| Column | Type | Description |
|--------|------|-------------|
| `id` | BIGINT (identity) | Auto-generated primary key |
| `merchant_id` | UUID | Merchant ownership |
| `code` | TEXT | The unique code printed on product |
| `serial` | TEXT | Serial number from manufacturer |
| `sku` | TEXT | Product SKU code |
| `sku_name` | TEXT | Product display name |
| `batch_code` | TEXT | Manufacturing batch identifier |
| `price` | NUMERIC | Product retail price |
| `points` | NUMERIC | Points awarded on claim |
| `window_start` | TIMESTAMPTZ | Earliest valid claim time |
| `window_end` | TIMESTAMPTZ | Expiry time |
| `activated` | BOOLEAN | Whether code is active for claiming |
| `activated_at` | TIMESTAMPTZ | When activated |
| `activated_user_code` | TEXT | Who activated it |
| `deactivated` | BOOLEAN | Whether code has been deactivated |
| `deactivated_at` | TIMESTAMPTZ | When deactivated |
| `deactivated_user_code` | TEXT | Who deactivated it |
| `claimed` | BOOLEAN | Whether consumer has claimed this code |
| `claimed_at` | TIMESTAMPTZ | When claimed |
| `claimed_customer_id` | TEXT | CRM customer ID of claimer |
| `claimed_store_code` | TEXT | Store where claimed (if staff-assisted) |
| `claimed_sales_code` | TEXT | Sales rep code (if staff-assisted) |
| `claimed_sales_id` | UUID | Sales rep user ID |
| `mfg_datetime` | TIMESTAMPTZ | Manufacturing date |
| `source` | TEXT | Import source identifier |
| `import_job_id` | UUID | Links to `codes_import_jobs` for rollback |
| `created_at` | TIMESTAMPTZ | Row creation time |

**Indexes**:

| Index | Definition | Purpose |
|-------|-----------|---------|
| `Codes_pkey` | `UNIQUE (id)` | Primary key |
| `codes_code_merchant_id_unique` | `UNIQUE (code, merchant_id)` | No duplicate codes per merchant |
| `idx_codes_merchant_code` | `(merchant_id, code)` | Fast validate/claim lookups |
| `idx_codes_claimed` | `(claimed) WHERE claimed IS NOT TRUE` | Fast unclaimed code queries |
| `idx_codes_claimed_status` | `(merchant_id, claimed, activated, deactivated) WHERE claimed IS NOT TRUE` | Multi-condition validation |
| `idx_codes_merchant_sku_unclaimed` | `(merchant_id, sku) WHERE claimed IS NOT TRUE` | SKU-level reporting |
| `idx_codes_import_job_id` | `(import_job_id)` | Fast rollback queries |
| `idx_codes_claimed_sales_id` | `(claimed_sales_id) WHERE NOT NULL` | Sales rep attribution |
| `idx_codes_windows` | `(window_start, window_end) WHERE NOT NULL` | Window validity checks |

---

### **codes_staging** (Staging Table)

Temporary workspace for loading CSV data before processing. Cleared before and after each import.

| Column | Type | Description |
|--------|------|-------------|
| `row_num` | BIGSERIAL | Auto-incrementing row number |
| `merchant_id` | UUID | From import parameter |
| `code` | TEXT | NULL in generate mode, populated in import mode |
| `serial`, `sku`, `sku_name`, `batch_code` | TEXT | Product metadata |
| `activated` | BOOLEAN | Activation status |
| `activated_at`, `deactivated_at` | TIMESTAMPTZ | Activation timestamps |
| `mfg_datetime` | TIMESTAMPTZ | Manufacturing date |
| `window_start`, `window_end` | TIMESTAMPTZ | Validity period |
| `price`, `points` | NUMERIC | Value fields |
| `source` | TEXT | Source identifier |

---

### **codes_import_jobs** (Import Audit Trail)

Tracks every import operation for audit, verification, and rollback.

| Column | Type | Description |
|--------|------|-------------|
| `id` | UUID | Job identifier stamped on all imported codes |
| `merchant_id` | UUID | Which merchant |
| `status` | TEXT | `processing` → `completed` \| `failed` \| `rolled_back` |
| `total_codes_to_insert` | INT | Expected count |
| `codes_inserted` | INT | Actual count inserted |
| `duration_seconds` | NUMERIC | PG function execution time |
| `notes` | TEXT | Free text notes |
| `created_by` | UUID | Admin who triggered (from `admin_id` parameter) |
| `source_info` | JSONB | Auto-collected: filename, file size, row count, mode, code prefix/length, batch codes, SKUs, duplicate handling |
| `created_at`, `completed_at` | TIMESTAMPTZ | Timestamps |
| `rolled_back_at` | TIMESTAMPTZ | If job was reversed |
| `error_message` | TEXT | Failure details |

---

### **codes_problem_reports** (Consumer Problem Reports)

When a code doesn't work, consumers can report it. Admin reviews and resolves.

| Column | Type | Description |
|--------|------|-------------|
| `id` | UUID | Report ID |
| `merchant_id` | UUID | Merchant |
| `code` | TEXT | The problematic code |
| `user_id` | UUID | Auth user ID (if available) |
| `crm_userid` | TEXT | CRM customer ID |
| `tel` | TEXT | Consumer phone |
| `name` | TEXT | Consumer name |
| `image_url` | TEXT | Photo of the code/product |
| `status` | TEXT | `pending` → resolved |
| `resolution_notes` | TEXT | Admin resolution notes |
| `created_at` | TIMESTAMPTZ | When reported |

---

### **codes_deletion_jobs** + **codes_deletion_log** (Deletion & Restore)

Supports batch deletion with backup and restore capability.

**codes_deletion_jobs**: Tracks deletion/restore operations with progress.

| Column | Type | Description |
|--------|------|-------------|
| `id` | UUID | Job ID |
| `merchant_id` | UUID | Merchant |
| `action` | TEXT | `delete` or `restore` |
| `status` | TEXT | `pending` → `processing` → `completed` \| `failed` |
| `total_codes` | INT | Total codes to process |
| `processed_codes` | INT | Progress counter |
| `deletion_batch_id` | UUID | Groups deleted codes for restore |
| `deletion_reason` | TEXT | Why codes were deleted |
| `codes_deleted`, `codes_backed_up`, `codes_restored` | INT | Counters |

**codes_deletion_log**: Full backup of every deleted code (mirrors `codes` columns) with restore metadata.

Key fields: `deletion_batch_id`, `original_code_id`, `deletion_reason`, `can_restore`, `restored_at`, `restored_by`.

---

### Views & Materialized Views

| View | Type | Purpose |
|------|------|---------|
| `mv_codes_claimed` | Materialized | Cached view of all claimed codes with key fields for reporting |
| `v_codes_deletion_history` | View | Admin-facing deletion audit trail with merchant name, admin email, restore status |

---

## Database Functions

### Claim & Validation Functions

#### **validate_codes(input_codes[], p_merchant_id)**

Pre-claim check — tells the consumer if their code(s) will work before committing.

- Looks up each code against `codes` table for the merchant
- For duplicate codes, prefers unclaimed → most recent
- Returns per-code: `code_exists`, `unused`, `activated`, `not_deactivated`, `started` (window), `not_ended` (window), plus `sku_name`, `points`, `sku_code`, `price`

#### **claim_codes(input_codes[], p_merchant_id, ...)**

Marks codes as claimed in a single atomic operation.

- Validates all codes in one CTE (same logic as `validate_codes`)
- Separates into passed/failed with specific error messages per code
- Batch UPDATE all passed codes: `claimed = true`, `claimed_at`, `claimed_customer_id`, `claimed_store_code`, `claimed_sales_code`
- Returns: `passed_codes[]`, `failed_codes[]`, `total_points`, `details_pass` (JSONB), `details_fail` (JSONB with error per code), `details_pass_for_receipt` (product/price info for receipt creation), `receipt_number`
- Race condition handling: if fewer rows updated than expected (concurrent claim), proceeds with actual count

**Validation rules** (a code must pass ALL):
1. Code exists for this merchant
2. Not already claimed
3. Activated = true
4. Not deactivated
5. Window has started (or no window_start)
6. Window has not ended (or no window_end)

**Error messages returned**: `Code does not exist`, `Code already claimed`, `Code not activated`, `Code deactivated`, `Code validity period not started`, `Code validity period expired`

#### **claim_codes_with_award(input_codes[], p_merchant_id, p_user_id, ...)**

Wraps `claim_codes` + publishes a currency event to the unified currency system.

- Calls `claim_codes()` first
- If passed codes have points > 0: publishes to `publish-currency-event` edge function via `net.http_post`
- Currency event: `source_type = 'campaign'`, `currency_type = 'points'`, `component = 'base'`, includes `codes_claimed`, `code_ids`, `receipt_number` in metadata
- Returns same as `claim_codes` plus `currency_request_id`

### Import Functions

#### **process_code_import(p_merchant_id, p_mode, ...)**

The single function that handles all code imports. Two modes in one atomic transaction.

**Parameters**:

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| p_merchant_id | UUID | required | Target merchant |
| p_mode | TEXT | 'generate' | `generate` or `import` |
| p_on_duplicate | TEXT | 'reject' | `reject` or `skip` (import mode) |
| p_code_prefix | TEXT | '' | Prefix for generated codes |
| p_code_length | INT | 12 | Random character length |
| p_source_info | JSONB | '{}' | Auto-populated by service |
| p_admin_id | UUID | NULL | Who triggered the import |
| p_notes | TEXT | NULL | Free text notes |

**Generate Mode**: Auto-creates unique codes for each CSV row. Generates N + 5% random codes → self-dedup → anti-join against production → pair with staging rows → INSERT.

**Import Mode**: Uses codes from the CSV. Checks internal dups (within CSV) + database dups → reject or skip → INSERT.

**Code generation character set**: `ABCDEFGHJKMNPQRSTUVWXYZ23456789` (30 chars, no ambiguous 0/O/1/I/L)

**Any failure → entire transaction ROLLBACK. Zero codes inserted.**

#### **rollback_import_job(p_job_id)**

Reverses a completed import by deleting all codes with that job_id. No time limit — can rollback months later. Updates job status to `rolled_back`.

### Admin Management Functions

#### **admin_activate_codes_by_serial_range(p_serial_start, p_serial_end, p_sku, p_mrp, p_mfd, p_lot_id, ...)**

Activates a range of codes by serial number after products are manufactured.

- Parses serial prefix + numeric range (e.g., `AZN000001` to `AZN005000`)
- Zero-pads serial numbers to match original format
- Sets: `sku`, `price`, `mfg_datetime`, `batch_code`, `window_end`, `source`, `activated = true`
- Classifies each serial: already activated (error), not found (error), or ready to update
- Returns summary with success/error counts and per-serial error details
- Uses `get_current_merchant_id()` for merchant context (admin token)

#### **api_get_code_details(p_code)**

Admin lookup for a single code. Returns full details including claim info, activation status, window, import job. Uses `get_current_merchant_id()`.

#### **submit_code_problem_report(p_code, p_crm_userid, p_tel, p_name, p_image_url)**

Creates a problem report when a consumer's code doesn't work. Inserts into `codes_problem_reports` with status `pending`.

#### **get_merchant_id_by_code(p_merchant_code)**

Maps a merchant_code string (e.g., `duluxreward`) to UUID via `merchant_master` table.

---

## Edge Functions

### Consumer-Facing

#### **validate-codes-public**

Public validation endpoint — consumer scans/keys in code, gets instant feedback before claiming.

- Input: `{ codes: string[], merchant_code: string }`
- Maps `merchant_code` → `merchant_id` via registry
- Calls `validate_codes()` PG function
- Returns per-code: `exists`, `unused`, `activated`, `not_deactivated`, `started`, `not_ended`, `sku_name`, `points`, `price`
- Handles empty/blank codes gracefully

#### **validate-codes**

Internal validation endpoint (JWT required). Same logic as `validate-codes-public`.

#### **claim-codes**

Claim-only endpoint — marks codes as claimed, returns pass/fail details.

- Input: `{ codes: string[], merchant_code: string, claimed_store_code?, claimed_customer_id?, claimed_sales_code? }`
- Calls `claim_codes()` PG function
- Returns: `passed_codes`, `failed_codes`, `total_points`, `receipt_number`, `details_pass`, `details_fail`, `details_pass_for_receipt`

#### **claim-codes-award-points-create-receipt**

The full orchestrator — validates, claims, awards points, creates receipt. This is the primary production endpoint.

- Input: `{ codes: string[], merchant_code: string, customer: { customer_id, first_name?, last_name?, customer_phone? }, store?: { store_code, store_name }, claimed_sales_code?, claimed_sales_id? }`
- Max 100 codes per call
- **Step 1**: Validate codes against `codes` table
- **Step 2**: Calculate total points (supports SKU-based promo multipliers — e.g., 2x points for specific SKUs)
- **Step 3**: Build receipt items from valid codes
- **Step 4**: Award points via CRM direct-earn API
- **Step 5**: Mark codes as claimed (only if points awarded successfully)
- **Step 6**: Create receipt in CRM with line items
- Returns full result: valid/failed codes, points data, receipt data

**Promo SKU multiplier**: Configurable set of SKUs that earn multiplied points (currently 2x for specific SKU range). Applied at claim time.

#### **scanner**

Serves a self-contained HTML page with camera-based QR/Data Matrix/barcode scanning. Uses `html5-qrcode` library. Supports QR, Data Matrix, EAN-13, EAN-8, Code 128, Code 39, Code 93, UPC-A, UPC-E. Posts `SCAN_RESULT` message to parent window with decoded text and format.

#### **report-code-problem**

Consumer reports problematic codes.

- Input: `{ codes: string[], merchant_code: string, crm_userid?, tel?, name? }`
- Inserts each code into `codes_problem_reports`
- Max 100 codes per submission
- Dedup: unique constraint prevents same consumer reporting same code twice

### Admin/Operations

#### **download-filtered-codes**

Exports codes with duplicate filtering. Supports chunked download for large datasets and streaming CSV.

#### **delete-merchant-codes**

Batch deletion of merchant codes with backup to `codes_deletion_log`.

---

## Bulk Import System

### Architecture

```
curl POST /import-codes
  ┌──────────────────────────────────────────────────┐
  │  RENDER SERVICE (Node.js)                        │
  │  https://code-import.onrender.com                │
  │                                                  │
  │  1. Receive CSV file + parameters                │
  │  2. Validate request + check concurrency         │
  │  3. Parse CSV (auto-maps column names)           │
  │  4. Load to codes_staging table                  │
  │  5. Call process_code_import() PG function        │
  │  6. Clean staging on success or failure           │
  │  7. Return response with job_id                  │
  └──────────────┬───────────────────────────────────┘
                 │ Direct PostgreSQL connection
                 ▼
  ┌──────────────────────────────────────────────────┐
  │  SUPABASE PG FUNCTION (atomic transaction)       │
  │                                                  │
  │  mode=generate:                                  │
  │    Generate code pool → dedup → pair with rows   │
  │                                                  │
  │  mode=import:                                    │
  │    Check internal + DB dups → reject or skip     │
  │                                                  │
  │  Both: INSERT to codes table → verify count      │
  │  Any failure → entire transaction ROLLBACK        │
  └──────────────────────────────────────────────────┘
```

### API Endpoints

#### **POST /import-codes** — Main Import

| Parameter | Required | Default | Description |
|-----------|----------|---------|-------------|
| file | Yes | - | CSV file |
| merchant_id | Yes | - | Merchant UUID |
| mode | Yes | - | `generate` or `import` |
| on_duplicate | No | `reject` | `reject` or `skip` (import mode) |
| code_prefix | No | `""` | Prefix for generated codes |
| code_length | No | `12` | Length of random part |
| admin_id | No | NULL | UUID of who triggered it |
| notes | No | NULL | Free text notes |

**Generate mode** (CSV without codes — system creates them):
```bash
curl -X POST https://code-import.onrender.com/import-codes \
  -H "x-api-key: YOUR_API_KEY" \
  -F "file=@codes.csv" \
  -F "merchant_id=<uuid>" \
  -F "mode=generate" \
  -F "code_prefix=AZN" \
  -F "notes=Feb 2026 unsold inventory batch"
```

**Import mode** (CSV already has codes):
```bash
curl -X POST https://code-import.onrender.com/import-codes \
  -H "x-api-key: YOUR_API_KEY" \
  -F "file=@codes.csv" \
  -F "merchant_id=<uuid>" \
  -F "mode=import" \
  -F "on_duplicate=skip"
```

#### **GET /progress/:merchant_id** — Real-time Progress

Stages: `received` → `parsing_csv` → `loading_staging` → `processing` → `cleanup` → `completed` | `failed`

#### **POST /rollback** — Rollback an Import

```bash
curl -X POST https://code-import.onrender.com/rollback \
  -H "x-api-key: YOUR_API_KEY" \
  -H "Content-Type: application/json" \
  -d '{"job_id": "JOB_ID_HERE"}'
```

No time limit — can rollback months later.

#### **GET /jobs/:merchant_id** — Import History

#### **GET /health** — Health Check (no auth)

### CSV Format

The service accepts both DB column names and vendor CSV names:

| DB Column | Also Accepts | Type | Notes |
|-----------|-------------|------|-------|
| `code` | `document_id` | TEXT | Import mode only |
| `serial` | `serial_no` | TEXT | |
| `sku` | `sku_code` | TEXT | |
| `sku_name` | | TEXT | |
| `batch_code` | `batchId`, `batch_id` | TEXT | |
| `activated` | `isActivated_int` | BOOL | `true`/`false`/`1`/`0` |
| `activated_at` | `activation_timestamp` | DATE | |
| `deactivated_at` | `deactivation_timestamp` | DATE | |
| `mfg_datetime` | `mfd` | DATE | |
| `window_start` | | DATE | |
| `window_end` | `expiry` | DATE | |
| `price` | | NUMERIC | |
| `points` | | NUMERIC | |
| `source` | | TEXT | |

Date formats: `DD/MM/YYYY HH:mm:ss`, `DD/MM/YYYY`, `YYYY-MM-DD`, ISO 8601.

### Concurrency & Safety

- Same merchant: second import returns `409 Conflict` with current progress
- Different merchants: both proceed independently
- Atomic: either all codes insert or none
- Count verification: inserted count must match expected
- Final NOT EXISTS: last-resort duplicate protection

### Performance

| Scale | Total Time |
|-------|-----------|
| 126K rows vs 21M existing | ~27s |
| 5M rows vs 50M existing (estimated) | ~15-25 min |

### Infrastructure

| Component | Details |
|-----------|---------|
| Render Service | `code-import` at https://code-import.onrender.com (Node.js, Singapore) |
| GitHub Repo | [Rocket-CRM/render-code-import](https://github.com/Rocket-CRM/render-code-import) |
| Supabase Project | wkevmsedchftztoolkmi (ap-southeast-1) |

---

## Error Handling

### Import Errors

| Error | Cause | Resolution |
|-------|-------|------------|
| "No CSV file provided" | Missing file | Add `-F "file=@path.csv"` |
| "mode is required" | Missing mode | Add `-F "mode=generate"` or `"mode=import"` |
| "CSV file is empty" | No data rows | Check CSV has data below headers |
| "mode=generate but CSV already has codes" | CSV has code column | Use `mode=import` or remove code column |
| "mode=import but CSV has no code column" | Missing code column | Use `mode=generate` or add codes |
| "Import already in progress" | Concurrent import | Wait for current import to finish |
| "Found N duplicate codes" | on_duplicate=reject | Use `on_duplicate=skip` or fix CSV |

### Claim Errors

| Error | Cause | Resolution |
|-------|-------|------------|
| "Code does not exist" | Code not in DB for merchant | Check code and merchant |
| "Code already claimed" | Previously claimed | Code is one-time use |
| "Code not activated" | Not yet activated by admin | Wait for activation |
| "Code deactivated" | Administratively disabled | Contact admin |
| "Code validity period not started" | Before window_start | Wait for validity window |
| "Code validity period expired" | After window_end | Code has expired |

### Automatic Recovery

- **PG function failure** → automatic rollback, codes table untouched, staging cleaned
- **Render crash** → staging has stale data, cleared on next import
- **Connection drop** → PG transaction rolls back, no partial data
- **Points award failure** → codes NOT marked as claimed (claim-codes-award-points-create-receipt)
