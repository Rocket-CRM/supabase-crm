# Code Import and Duplicate Checking System

## System Overview

The Code Import System enables bulk importing of millions of promotional codes from CSV files while ensuring data integrity through comprehensive duplicate detection. The system handles CSV files containing up to millions of rows, validates data structure, identifies duplicates both within uploaded files and against existing database records, and provides atomic insertion with full rollback capability.

---

## Architecture

### Three-Table Design

**Staging → Validation → Production**

```
CSV Files (100+ files, 10M+ rows)
    ↓
codes_check_temp (staging table)
    ↓ duplicate check
codes_check_temp (with flags set)
    ↓ clean codes only
codes (production table)
```

---

## Database Tables

### **codes_check_temp** (Staging Table)

**Purpose**: Temporary workspace for validating CSV imports before production insertion

**Lifecycle**: Data accumulates during import → Duplicate flags set → Clean codes copied to production → Table cleared for next batch

**Key Columns**:
- `merchant_id` - Merchant ownership (from CSV column)
- `code` - The promotional code (primary data)
- `serial` - Optional serial number
- `sku`, `points`, `sku_name`, `batch_code`, `price` - Product metadata
- `row_number` - Sequential numbering for tracking
- `internal_dup` (boolean) - True if code appears multiple times within imported CSVs
- `existing_dup` (boolean) - True if code already exists in production codes table
- `created_at` - Import timestamp

**Design Notes**:
- RLS disabled for performance (temporary processing table)
- Indexed on (code, merchant_id) for fast duplicate checking
- Indexed on (merchant_id, internal_dup, existing_dup) for filtering
- Cleared between import batches via `clear_temp_data.sh`

---

### **codes** (Production Table)

**Purpose**: Main table storing all active promotional codes for all merchants

**Size**: 16M+ rows (5.3M original NBD codes + 10.9M newly imported)

**Key Columns**:
- `id` - Primary key
- `merchant_id` - Merchant ownership
- `code` - The promotional code (unique per merchant)
- `sku`, `points`, `sku_name`, `batch_code` - Product info
- `serial`, `price` - Optional metadata
- `window_start`, `window_end` - Validity period
- `activated`, `deactivated` - Status flags
- `claimed`, `claimed_customer_id` - Redemption tracking
- **`import_job_id`** (NEW) - Links to codes_import_jobs for rollback capability
- `source` - Import source identifier
- `created_at` - Creation timestamp

**Critical Indexes**:
- `codes_code_merchant_id_unique` - Ensures no duplicate codes per merchant
- `idx_codes_merchant_code` - Fast merchant+code lookups
- `idx_codes_import_job_id` - Fast job-based rollback queries

**Design Notes**:
- RLS enabled filtering by merchant_id
- Unique constraint on (code, merchant_id) prevents duplicate inserts
- import_job_id enables batch rollback without affecting other data

---

### **codes_import_jobs** (Audit Trail Table)

**Purpose**: Tracks every bulk import operation for audit, verification, and rollback

**Lifecycle**: One row created per import job → Status updated during processing → Permanent record

**Key Columns**:
- `id` (UUID) - Job identifier stamped on all imported codes
- `merchant_id` - Which merchant's codes were imported
- `status` - Job state: pending → validating → processing → completed | failed | rolled_back
- `total_codes_to_insert` - Expected count from validation
- `codes_inserted` - Actual count inserted (must match expected)
- `validation_passed` (boolean) - Whether pre-flight validation succeeded
- `validation_errors` (JSONB) - Error details if validation failed
- `created_at` - Job start timestamp
- `created_by` (UUID) - User who initiated (from auth.uid())
- `completed_at` - Job completion timestamp
- `rolled_back_at` - If job was reversed
- `error_message` - Failure details
- `source_info` (JSONB) - Optional metadata (file names, batch info)

**Design Notes**:
- Indexed on merchant_id, status, created_at for reporting
- Permanent record - never deleted even after rollback
- Enables "show all imports from last month" queries

---

## Core Functions

### **1. mark_duplicates_in_temp(p_merchant_id)**

**Category**: Duplicate Detection Engine  
**Returns**: JSONB with statistics

**Purpose**: Identifies duplicate codes within staging table through two-phase detection

**Phase 1 - Internal Duplicates**:
- Uses window function ROW_NUMBER() OVER (PARTITION BY code)
- Marks 2nd, 3rd, nth occurrences where code appears multiple times
- Single table scan: O(n) complexity
- Fast: ~30 seconds for 15M rows

**Phase 2 - Database Duplicates**:
- Joins codes_check_temp against production codes table
- Processes in 100K row chunks to avoid timeout (156 chunks for 15.5M rows)
- Uses EXISTS subquery with indexed lookups
- Each chunk: ~3-10 seconds depending on duplicate density
- Total: ~5-15 minutes for 15M rows against 5M production codes

**Processing Logic**:
```
For each 100K row chunk:
  1. Query codes_check_temp rows in range (row_number 1-100K)
  2. For each row, check if code exists in codes table
  3. Use index on (code, merchant_id) for fast lookup
  4. Mark existing_dup = true for matches
  5. Continue to next chunk
```

**Returns**:
```json
{
  "success": true,
  "total_rows": 15520410,
  "internal_duplicates": 310312,
  "database_duplicates": 4302241,
  "clean_count": 10907894,
  "chunks_processed": 156
}
```

**Timeout Handling**: Requires `SET statement_timeout = '30min'` in session

---

### **2. validate_clean_codes_for_insert(p_merchant_id)**

**Category**: Pre-Flight Safety Validator  
**Returns**: JSONB with validation status

**Purpose**: Final safety check before production insertion, detecting race conditions

**Validation Checks**:
1. **Count clean codes**: WHERE internal_dup = false AND existing_dup = false
2. **Re-check database duplicates**: Race condition protection - codes may have been inserted since duplicate check ran
3. **Validate required fields**: code NOT NULL, merchant_id NOT NULL
4. **Data type validation**: Points is numeric, UUIDs valid
5. **Empty string check**: Reject codes that are empty

**Race Condition Protection Example**:
```
10:00 AM - Run mark_duplicates_in_temp() → 10M clean codes
10:30 AM - Someone else inserts 5K codes
10:35 AM - You run insert → validate_clean_codes_for_insert re-checks
         → Finds 5K codes now exist in database
         → Updates their existing_dup flags
         → Returns clean_count = 9,995,000 (not 10M)
         → Warns about new duplicates found
```

**Returns**:
```json
{
  "valid": true,
  "total_clean_codes": 10907894,
  "validation_errors": 0,
  "errors": [],
  "new_db_duplicates_found": 0
}
```

**Design**: Always call this immediately before insert, never trust stale duplicate check results

---

### **3. insert_clean_codes_to_production(p_merchant_id, p_source_info)**

**Category**: Atomic Production Inserter  
**Returns**: JSONB with job details

**Purpose**: All-or-nothing transaction inserting clean codes from staging to production with full audit trail

**Transaction Flow**:
```sql
BEGIN TRANSACTION;

  -- Step 1: Run validation
  validate_clean_codes_for_insert()
  If not valid → ROLLBACK and RETURN error
  
  -- Step 2: Create job record
  INSERT INTO codes_import_jobs (...) RETURNING job_id
  
  -- Step 3: Insert codes with job_id tag
  INSERT INTO codes (
    merchant_id, code, sku, points, ..., import_job_id
  )
  SELECT 
    ct.merchant_id, ct.code, ct.sku, ct.points, ...,
    v_job_id  ← SAME job_id stamped on ALL rows
  FROM codes_check_temp ct
  WHERE ct.merchant_id = p_merchant_id
    AND ct.internal_dup = false
    AND ct.existing_dup = false
    AND NOT EXISTS (  ← Final duplicate protection
        SELECT 1 FROM codes c 
        WHERE c.code = ct.code AND c.merchant_id = ct.merchant_id
    );
  
  GET DIAGNOSTICS v_inserted_count = ROW_COUNT;
  
  -- Step 4: Verify count matches expected
  IF v_inserted_count != v_expected_count THEN
    ROLLBACK;
    RAISE EXCEPTION 'Count mismatch: expected %, got %', 
                    v_expected_count, v_inserted_count;
  END IF;
  
  -- Step 5: Update job as completed
  UPDATE codes_import_jobs SET status = 'completed', 
                              codes_inserted = v_inserted_count,
                              completed_at = NOW();

COMMIT;  ← Only commits if ALL steps succeeded
```

**Safety Guarantees**:
- All-or-nothing: Either all codes insert or none
- If ANY row violates unique constraint → ROLLBACK entire batch
- If count mismatch → ROLLBACK (catches race conditions)
- Triple duplicate check: During duplicate check, validation, and insert
- Every code tagged with job_id for traceability

**Performance**: 
- 10.9M rows inserted in 9 minutes
- ~20,000 rows/second throughput
- Indexes updated in real-time

**Returns**:
```json
{
  "success": true,
  "job_id": "f8241ebd-48e4-475e-a3f4-82633befe0d6",
  "codes_inserted": 10907894,
  "message": "Successfully inserted 10907894 clean codes to production"
}
```

---

### **4. rollback_import_job(p_job_id)**

**Category**: Emergency Rollback Function  
**Returns**: JSONB with deletion statistics

**Purpose**: Completely reverses a production import by deleting all codes from a specific job

**Logic**:
```sql
BEGIN TRANSACTION;

  -- Verify job exists and is completed
  SELECT * FROM codes_import_jobs WHERE id = p_job_id
  If status != 'completed' → RETURN error
  
  -- Delete all codes from this job
  DELETE FROM codes WHERE import_job_id = p_job_id;
  
  GET DIAGNOSTICS v_deleted_count = ROW_COUNT;
  
  -- Update job status
  UPDATE codes_import_jobs 
  SET status = 'rolled_back',
      rolled_back_at = NOW();

COMMIT;
```

**Use Cases**:
- Discovered data quality issues after insert
- Wrong merchant_id used
- Need to re-import with corrections
- Testing rollback capability

**Safety**: Only works on completed jobs (prevents rolling back failed/partial jobs)

**Performance**: Deletes 10.9M rows in ~3-5 minutes using import_job_id index

**Returns**:
```json
{
  "success": true,
  "job_id": "f8241ebd-...",
  "codes_deleted": 10907894,
  "original_insert_count": 10907894,
  "message": "Rolled back 10907894 codes from job..."
}
```

---

### **5. verify_import_job(p_job_id)**

**Category**: Post-Insert Integrity Checker  
**Returns**: JSONB with verification status

**Purpose**: Confirms inserted code count matches job record expectations

**Logic**:
```sql
-- Get job record
SELECT codes_inserted FROM codes_import_jobs WHERE id = p_job_id

-- Count actual codes in production
SELECT COUNT(*) FROM codes WHERE import_job_id = p_job_id

-- Compare
verified = (actual_count == expected_count)
```

**Returns**:
```json
{
  "success": true,
  "job_id": "f8241ebd-...",
  "expected_count": 10907894,
  "actual_count": 10907894,
  "verified": true
}
```

---

### **6. get_duplicate_report(p_merchant_id)**

**Category**: Export Helper Function  
**Returns**: TABLE with all codes + duplicate status

**Purpose**: Formats codes_check_temp data for CSV export with human-readable status labels

**Returns Columns**:
- All original columns from codes_check_temp
- `status` - Derived field: "CLEAN" | "INTERNAL_DUPLICATE" | "DATABASE_DUPLICATE" | "BOTH_DUPLICATE"

**Used by**: `export_duplicates_only.sh` to generate downloadable reports

---

## Command Line Scripts

### **Import Scripts**

#### **validate_csv_headers.sh**
```bash
./validate_csv_headers.sh ~/Downloads/NBD
```
**Purpose**: Pre-import validation of CSV file structure  
**Checks**: Required 'code' column exists, counts rows per file  
**Output**: List of all files with validation status  
**Time**: <5 seconds for 100 files  

---

#### **import_codes_folder.sh**
```bash
./import_codes_folder.sh ~/Downloads/NBD
```
**Purpose**: Bulk import all CSV files from folder to staging table  
**Process**:
1. Connects to database via psql
2. For each CSV file:
   - Creates temp table matching CSV structure
   - Uses PostgreSQL COPY for fast loading
   - Extracts merchant_id from CSV column
   - Inserts to codes_check_temp with sequential row_number
   - Sets internal_dup = false, existing_dup = false (defaults)
3. Shows progress for each file
4. Accumulates all data (does not clear between files)

**Handles**:
- Mixed column structures (some files have batch_id, others batch_code)
- Missing columns (sets to NULL)
- Empty rows (skipped)
- Column variations (batch_code vs batch_id)

**Performance**: 
- 63 files with 15M rows: ~30-40 minutes
- Processes ~6,000-10,000 rows/second
- Limited by network and CSV parsing

**Output**: Total files processed, rows imported per file, cumulative count

---

### **Duplicate Checking Scripts**

#### **check_duplicates.sh**
```bash
./check_duplicates.sh 7faab812-e179-48c2-9707-0d8a9b2f84ea
```
**Purpose**: Mark duplicate flags on all codes in staging table for specified merchant  
**Process**:
1. Sets session timeout to 30 minutes
2. Calls `mark_duplicates_in_temp(merchant_id)` function
3. Shows before/after statistics

**Requires**: PGPASSWORD environment variable or prompts for password

**Performance**:
- 15M rows against 5M production codes: ~8-12 minutes
- Processes in 100K row chunks (156 chunks for 15M rows)
- Shows progress for each chunk

**Output**:
```
Before: 15,520,410 total rows
After:
  Clean codes: 10,907,894
  Internal duplicates: 310,312
  Database duplicates: 4,302,241
```

---

### **Production Insert Scripts**

#### **insert_clean_codes.sh**
```bash
./insert_clean_codes.sh 7faab812-e179-48c2-9707-0d8a9b2f84ea
```
**Purpose**: Atomic insertion of clean codes from staging to production  
**Safety Workflow**:
1. **Pre-flight validation** - Calls validate_clean_codes_for_insert()
2. **Shows summary** - "Ready to insert X clean codes"
3. **User confirmation** - Must type 'YES' to proceed
4. **Atomic insert** - Calls insert_clean_codes_to_production()
5. **Post-verification** - Calls verify_import_job()
6. **Returns job_id** - For rollback capability

**Safety Features**:
- Re-validates duplicates before insert (race condition protection)
- All-or-nothing transaction (10.9M rows or 0 rows)
- Count verification (expected vs actual)
- Automatic rollback on any failure
- User must confirm before execution

**Performance**:
- 10.9M rows inserted in ~9 minutes
- ~20,000 rows/second with index updates
- Table locked during operation

**Critical Output**: Job ID must be saved for rollback capability

---

#### **rollback_import.sh**
```bash
./rollback_import.sh f8241ebd-48e4-475e-a3f4-82633befe0d6
```
**Purpose**: Emergency rollback - delete all codes from a specific import job  
**Safety Workflow**:
1. Shows job details
2. **User confirmation** - Must type 'DELETE' to proceed
3. Calls `rollback_import_job(job_id)` function
4. Deletes all codes with matching import_job_id
5. Updates job status to 'rolled_back'

**Performance**: Deletes 10.9M rows in ~3-5 minutes using import_job_id index

**Use Cases**:
- Wrong data imported
- Data quality issues discovered post-import
- Testing rollback capability
- Need to re-import with corrections

---

### **Export Scripts**

#### **export_duplicates_only.sh**
```bash
./export_duplicates_only.sh 7faab812-... ~/Downloads/duplicates.csv
```
**Purpose**: Export all duplicate codes to CSV file for review  
**Data**: Internal duplicates + database duplicates only (excludes clean codes)  
**Columns**: All original columns + internal_dup + existing_dup + duplicate_type  
**Performance**: 4.6M duplicates exported in ~10-15 minutes (~500MB file)

---

#### **export_duplicate_report.sh**
```bash
./export_duplicate_report.sh 7faab812-... ~/Downloads/full_report.csv
```
**Purpose**: Export ALL codes (clean + duplicates) with status flags  
**Data**: Complete staging table for specified merchant  
**Performance**: 15M rows exported in ~15-20 minutes (~1.5GB file)

---

### **Utility Scripts**

#### **clear_temp_data.sh**
```bash
./clear_temp_data.sh 7faab812-e179-48c2-9707-0d8a9b2f84ea
```
**Purpose**: Delete all data from codes_check_temp for specified merchant  
**Safety**: Prompts for confirmation before deletion  
**Use**: Clean workspace between import batches

---

## Complete Import Workflow

### **Preparation (Once Per Session)**

```bash
# Navigate to project directory
cd "/Users/rangwan/Documents/Supabase CRM"

# Set PostgreSQL path
export PATH="/opt/homebrew/opt/postgresql@17/bin:$PATH"

# Set database password (avoids repeated prompts)
export PGPASSWORD="your_database_password"
```

---

### **Step 0: Pre-Validation (Optional)**

**Validate CSV structure before importing**:

```bash
./validate_csv_headers.sh ~/Downloads/NBD
```

**Output**: Shows each file's column headers, row counts, validates required columns

**If invalid**: Fix CSV files manually  
**If valid**: Proceed to import

**Time**: <10 seconds for 100 files

---

### **Step 1: Import CSV Files to Staging**

**Import all CSV files from folder**:

```bash
./import_codes_folder.sh ~/Downloads/NBD
```

**What happens**:
- All .csv files in folder processed sequentially
- merchant_id read from CSV column (not parameter)
- Data accumulates in codes_check_temp table
- Shows progress: "File 5 of 63: Imported 495,000 rows"

**Result**: All CSV data loaded into staging table

**Time**: ~30-60 minutes for 63 files with 15M rows total

**Critical**: Do NOT clear codes_check_temp between files - data accumulates

---

### **Step 2: Check Duplicates**

**Mark duplicate flags on all imported codes**:

```bash
./check_duplicates.sh 7faab812-e179-48c2-9707-0d8a9b2f84ea
```

**What happens**:
- Internal duplicate detection (within CSV files)
- Database duplicate detection (against 5.3M existing codes)
- Updates internal_dup and existing_dup flags
- Processes in 100K row chunks with progress messages

**Result**: Every row in staging table has duplicate flags set

**Time**: ~8-15 minutes for 15M rows against 5M production codes

**Output Example**:
```
Total rows: 15,520,410
Clean codes: 10,907,894 (70%)
Internal duplicates: 310,312 (2%)
Database duplicates: 4,302,241 (28%)
```

---

### **Step 3: Export Duplicates (Optional)**

**Download duplicate codes for review**:

```bash
./export_duplicates_only.sh 7faab812-... ~/Downloads/duplicates.csv
```

**What happens**:
- Queries all rows where internal_dup = true OR existing_dup = true
- Streams to CSV file with all columns + status
- Generates ~500MB file for 4.6M duplicates

**Use cases**:
- Review which codes are duplicates
- Share with team for investigation
- Archive for compliance

**Time**: ~10-15 minutes for 4.6M rows

**Optional**: Can skip and proceed directly to insert

---

### **Step 4: Insert Clean Codes to Production**

**Critical step - production data modification**:

```bash
./insert_clean_codes.sh 7faab812-e179-48c2-9707-0d8a9b2f84ea
```

**Workflow**:
1. **Pre-flight validation** - Re-checks duplicates, validates data
2. **Shows summary** - "Ready to insert 10,907,894 codes"
3. **Confirmation required** - User must type 'YES'
4. **Atomic insert** - Single transaction, all-or-nothing
5. **Verification** - Confirms count matches expected
6. **Returns job_id** - Save for rollback capability

**⚠️ IMPORTANT**:
- Table locked for ~9-45 minutes
- Cannot cancel mid-transaction safely
- Automatic rollback on any failure
- **SAVE THE JOB_ID** displayed at end

**Time**: 9-45 minutes depending on data size and server load

**Success Output**:
```
✅ INSERT SUCCESSFUL!
Job ID: f8241ebd-48e4-475e-a3f4-82633befe0d6
Codes inserted: 10,907,894
Time taken: 9m 22s

To rollback if needed:
./rollback_import.sh f8241ebd-48e4-475e-a3f4-82633befe0d6
```

---

### **Step 5: Rollback (If Needed)**

**If data issues discovered after insert**:

```bash
./rollback_import.sh f8241ebd-48e4-475e-a3f4-82633befe0d6
```

**Workflow**:
1. Fetches job details
2. **Confirmation required** - User must type 'DELETE'
3. Deletes all codes where import_job_id matches
4. Updates job status to 'rolled_back'

**Result**: All codes from job removed as if import never happened

**Time**: ~3-5 minutes for 10.9M rows

**Irreversible**: Cannot un-rollback - codes are permanently deleted

---

### **Step 6: Clear Staging (Prepare for Next Batch)**

**Clear temp table for next import cycle**:

```bash
./clear_temp_data.sh 7faab812-e179-48c2-9707-0d8a9b2f84ea
```

**What happens**:
- Prompts for confirmation
- Deletes all rows from codes_check_temp for specified merchant
- Shows remaining row count (should be 0)

**When to use**:
- After successful production insert
- Before starting new import batch
- When cleaning up failed imports

**Time**: <10 seconds

---

## Data Flow Diagram

```
┌─────────────────┐
│  CSV Files      │  63 files, 15M rows, mixed structures
│  ~/Downloads/   │  (code, sku, points, merchant_id columns)
└────────┬────────┘
         │
         │ import_codes_folder.sh
         │ (PostgreSQL COPY command)
         │ Reads merchant_id FROM CSV
         ↓
┌─────────────────────────┐
│  codes_check_temp       │  Staging table
│  15,520,410 rows        │  All files accumulated
│  internal_dup = false   │  All codes initially unmarked
│  existing_dup = false   │
└────────┬────────────────┘
         │
         │ check_duplicates.sh
         │ → mark_duplicates_in_temp()
         │   Phase 1: Internal dup detection
         │   Phase 2: Database dup check (156 chunks)
         ↓
┌─────────────────────────┐
│  codes_check_temp       │  Duplicate flags set
│  10,907,894 clean       │  internal_dup and existing_dup
│  310,312 internal dup   │  flags now accurate
│  4,302,241 db dup       │
└────────┬────────────────┘
         │
         │ insert_clean_codes.sh
         │ → validate_clean_codes_for_insert()
         │ → insert_clean_codes_to_production()
         │   Creates job, inserts WHERE both flags = false
         │   Stamps import_job_id on all rows
         ↓
┌─────────────────────────┐
│  codes (production)     │  Clean codes only
│  + 10,907,894 new rows  │  All tagged with job_id
│  = 16,264,865 total     │  Atomic transaction
│  (was 5,356,971)        │  Rollback-capable
└─────────────────────────┘
```

---

## Performance Characteristics

### **By Operation**

| Operation | Data Size | Time | Bottleneck |
|-----------|-----------|------|------------|
| CSV Header Validation | 63 files | 5 sec | File I/O |
| Import to Staging | 15M rows | 30-40 min | Network + CSV parsing |
| Internal Dup Check | 15M rows | 30 sec | Window function |
| Database Dup Check | 15M vs 5M | 8-12 min | Hash joins (156 chunks) |
| Insert to Production | 11M rows | 9-45 min | Index updates |
| Rollback | 11M rows | 3-5 min | Index deletion |
| Export Duplicates | 4.6M rows | 10-15 min | Network transfer |

### **Scalability Limits**

**Tested Successfully**:
- ✅ 63 CSV files in single batch
- ✅ 15.5M rows in staging table
- ✅ 10.9M rows atomic insert
- ✅ Duplicate check against 5.3M production codes

**Known Limitations**:
- Statement timeout: Max 30 min via session SET
- Pooler only (direct connection blocked by Supabase)
- Chunked processing required for >10M duplicate checks
- Export timeouts for >5M rows (recommend smaller batches)

**Recommended Batch Size**:
- Import: Up to 20M rows (tested working)
- Duplicate check: Up to 20M rows with chunking
- Insert: Up to 15M rows in single transaction
- Export: Up to 5M rows per file

---

## Error Handling and Recovery

### **Import Errors**

**CSV Parse Failures**:
- File-level isolation: Failed file doesn't affect other files
- Script continues to next file
- Shows "Failed" status with error message
- Can re-run import for failed files only

**Database Connection Errors**:
- Immediate failure before any data loaded
- No partial data in staging
- Retry with correct credentials

---

### **Duplicate Check Errors**

**Timeout (Pre-Fix)**:
- Partial duplicate marking
- Some chunks completed, others not
- Solution: Re-run check_duplicates.sh (idempotent - already marked rows skipped)

**Timeout (Post-Fix)**:
- Should not occur with session timeout set
- If occurs: Increase chunk size or reduce data volume

---

### **Insert Errors**

**Validation Failure**:
- Insert blocked before transaction starts
- No production data touched
- Fix errors in staging table and retry

**Mid-Transaction Failure**:
- Automatic ROLLBACK
- 0 codes inserted
- Production unchanged
- Job status = 'failed' with error_message
- Can fix issue and retry

**Count Mismatch**:
- Race condition detected
- Automatic ROLLBACK
- Indicates codes were inserted between validation and insert
- Re-run duplicate check and try again

---

## Safety Mechanisms

### **Pre-Flight Safety**

1. **CSV Structure Validation**: Ensures required columns exist before import
2. **Duplicate Check Required**: Cannot insert without running duplicate check first
3. **Race Condition Protection**: Re-validates right before insert
4. **User Confirmation**: Must type 'YES' to proceed with production changes

### **Transaction Safety**

1. **Atomic Transaction**: Either all codes insert or none (via BEGIN/COMMIT)
2. **Count Verification**: Inserted count must exactly match expected count
3. **Unique Constraint**: Database enforces no duplicate codes per merchant
4. **Final Duplicate Check**: EXISTS clause in INSERT prevents duplicates

### **Post-Insert Safety**

1. **Job Tagging**: Every code marked with import_job_id
2. **Verification Function**: Confirms count integrity
3. **Rollback Capability**: Can delete entire job in minutes
4. **Audit Trail**: Permanent record in codes_import_jobs

---

## Troubleshooting

### **Import Issues**

**Problem**: "Missing data for column 'serial'"  
**Cause**: CSV structure doesn't match temp table schema  
**Solution**: Script auto-handles - missing columns set to NULL

**Problem**: "Empty CSV" error  
**Cause**: File has only headers or blank rows  
**Solution**: Check CSV file integrity, ensure data rows exist

**Problem**: Import shows 0 rows  
**Cause**: All rows filtered out (empty codes, NULL values)  
**Solution**: Validate CSV has valid code values

---

### **Duplicate Check Issues**

**Problem**: Timeout after 60 seconds  
**Cause**: Using pooler without session timeout set  
**Solution**: Script now includes `SET statement_timeout = '30min'`

**Problem**: Partial results (some chunks not processed)  
**Cause**: Function crashed mid-processing  
**Solution**: Re-run check_duplicates.sh (idempotent)

**Problem**: All codes marked as duplicates  
**Cause**: Wrong merchant_id used  
**Solution**: Verify merchant_id matches CSV data

---

### **Insert Issues**

**Problem**: "No clean codes to insert"  
**Cause**: All codes are duplicates  
**Solution**: Expected if re-importing same data

**Problem**: Count mismatch error  
**Cause**: Codes inserted between validation and insert  
**Solution**: Re-run duplicate check, try insert again

**Problem**: Unique constraint violation  
**Cause**: Race condition - duplicate snuck in  
**Solution**: Automatic rollback, re-run duplicate check

---

## System Requirements

### **Local Machine**

- **PostgreSQL Client (psql)**: Version 14+ (tested with 17)
  - Mac: `brew install postgresql@17`
  - Exports PATH: `/opt/homebrew/opt/postgresql@17/bin`
  
- **Bash Shell**: For running scripts
- **Network**: Stable connection to Supabase (processes run 10-45 minutes)

### **Database**

- **Supabase Project**: Any plan (tested on Pro)
- **Database Password**: From Project Settings → Database
- **Disk Space**: 2-3GB per 10M codes imported
- **Extensions**: http (for future webhook integrations)

### **Permissions**

- **Database Role**: Must have INSERT/UPDATE/DELETE on codes and codes_check_temp
- **Service Role**: Used for atomicity in functions (SECURITY DEFINER)

---

## Production Considerations

### **Timing**

**Best Times to Run Large Imports**:
- Off-peak hours (nights/weekends)
- During scheduled maintenance windows
- When code claiming traffic is low

**Avoid**:
- Peak business hours
- During active promotional campaigns
- When codes table has heavy read activity

### **Monitoring**

**During Import**:
- Watch for progress messages in terminal
- Do not close terminal or cancel
- Table locked - other operations may queue

**After Import**:
- Verify job_id returned
- Check codes_import_jobs table for status
- Run verify_import_job() to confirm integrity

### **Rollback Decision**

**Consider rollback if**:
- Data quality issues discovered
- Wrong merchant_id detected
- Duplicate codes appearing despite checks
- Business rule violations found

**Rollback window**: No time limit - can rollback months later using job_id

---

## Known Limitations

### **Scale Limits**

1. **Single Import Batch**: Tested up to 20M rows in staging
2. **Duplicate Check**: Tested 15M rows against 5M production codes
3. **Atomic Insert**: Tested 11M rows in single transaction
4. **Export**: Practical limit ~5M rows before timeout risk

### **Timeout Constraints**

1. **Pooler statement timeout**: 60 seconds default, settable to 30 min per session
2. **Function execution**: Can set up to 2 hours
3. **Network stability**: Long operations require stable connection

### **Concurrency**

1. **Table locks**: codes table locked during insert (9-45 minutes)
2. **No parallel imports**: One import job per merchant at a time
3. **Read operations**: Blocked during insert transaction

---

## Future Enhancements

### **Potential Improvements**

1. **Parallel Chunk Processing**: Process duplicate check chunks in parallel (requires async framework)
2. **Progress Tracking**: Real-time progress updates in codes_import_jobs table
3. **Partial Insert Resume**: If insert fails at chunk 8 of 11, resume from chunk 8
4. **Streaming Export**: Export directly to Supabase Storage instead of local download
5. **Automated Batching**: Script auto-splits 20M rows into optimal batch sizes
6. **Duplicate Prevention**: Block CSV upload if >50% duplicates detected

### **Not Recommended**

1. **Auto-insert without confirmation**: Too risky for production
2. **Skip validation**: Risks data integrity
3. **Disable indexes during insert**: Table unavailable during rebuild
4. **Increase pooler timeout globally**: Controlled by Supabase, not configurable

---

## Quick Reference

### **Standard Import Journey (10M Rows)**

```bash
# Setup (once per session)
export PATH="/opt/homebrew/opt/postgresql@17/bin:$PATH"
export PGPASSWORD="Showmethecode789"
cd "/Users/rangwan/Documents/Supabase CRM"

# 1. Validate (optional, 5 sec)
./validate_csv_headers.sh ~/Downloads/NBD

# 2. Import (~30 min)
./import_codes_folder.sh ~/Downloads/NBD

# 3. Check duplicates (~10 min)
./check_duplicates.sh 7faab812-e179-48c2-9707-0d8a9b2f84ea

# 4. Export duplicates (optional, ~15 min)
./export_duplicates_only.sh 7faab812-... ~/Downloads/dups.csv

# 5. Insert to production (~9-45 min)
./insert_clean_codes.sh 7faab812-e179-48c2-9707-0d8a9b2f84ea
# → Type YES when prompted
# → SAVE THE JOB_ID

# 6. Rollback if needed (~5 min)
./rollback_import.sh <job_id>
# → Type DELETE to confirm

# 7. Clear for next batch (~1 sec)
./clear_temp_data.sh 7faab812-e179-48c2-9707-0d8a9b2f84ea
```

**Total Time**: ~1-2 hours for complete cycle with 10M rows

---

## Recent Production Import

**Date**: October 17, 2025  
**Merchant**: NBD (7faab812-e179-48c2-9707-0d8a9b2f84ea)  
**Job ID**: f8241ebd-48e4-475e-a3f4-82633befe0d6

**Statistics**:
- CSV files imported: 63
- Total rows staged: 15,520,410
- Internal duplicates: 310,312
- Database duplicates: 4,302,241
- Clean codes inserted: 10,907,894
- Insert time: 9 minutes 22 seconds
- Final NBD code count: 16,264,865 (was 5,356,971)

**Outcome**: ✅ Success - All-or-nothing transaction committed successfully

