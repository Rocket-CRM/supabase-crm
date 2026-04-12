# Syngenta Old CRM → New CRM Migration Guide

**Merchant ID:** `8f67aa08-dfce-454d-bfb1-effc4ee45f1f`

---

## OBJECTIVE

**Goal:** Migrate all Syngenta user data from old CRM to new CRM including:
- User profiles (identity, contact info, address)
- Points balances and transaction history
- Form submissions (farming data, surveys, program participation)
- Tier/segment assignments
- Admin tracking fields (BZB integration, staff assignments)

**Approach:** Build as **daily sync pipeline from Snowflake** (NOT one-time migration)

**Why Daily Pipeline?**
1. **Data Integrity:** Continuous validation - catch issues early, fix incrementally
2. **Zero Cutover Risk:** New CRM stays in sync with old CRM automatically
3. **Flexible Go-Live:** Choose any night for cutover without extra migration work
4. **No Data Loss:** Users added/updated in old CRM during transition period are captured
5. **Rollback Safety:** Can revert to old CRM if issues found

**Cutover Strategy:**
```
Day 1-N:  Daily sync running → New CRM mirrors old CRM
Day N:    Choose cutover night
Night N:  Final sync → Disable old CRM → Enable new CRM
Day N+1:  New CRM is live, old CRM retired
```

**Pipeline should be:**
- **Idempotent:** Safe to run multiple times
- **Incremental:** Only process changed records (use `updated_at` or similar)
- **Logged:** Track what was synced, errors, skipped records
- **Alertable:** Notify if sync fails or data mismatches

---

## DATA MODEL OVERVIEW (Context for Migration)

### Terminology Mapping: Old CRM → New CRM

**IMPORTANT: Forms = Custom Fields**

In the old CRM, these are called "**Custom Fields**"  
In the new CRM, these are called "**Form Submissions**"

```
OLD CRM                          NEW CRM
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
Default Custom Fields       →    User Profile Form
(shown on signup form)           (form_id: USER_PROFILE)

Additional Custom Fields    →    Other Forms
(program-specific)               (Big Grower, Surveys, etc.)
```

**For Migration:**
- Old CRM "custom field groups" → New CRM "form field groups"
- Old CRM "custom field values" → New CRM "form responses"
- Old CRM "user filled custom fields" → New CRM "form submission"

---

### user_accounts vs form_submissions - What's the Difference?

**`user_accounts` = Core Identity Record**
- **Purpose:** Single source of truth for WHO the user is
- **One record per user** (unique by line_id or tel)
- **Contains:** Name, phone, email, tier, authentication data
- **Think:** Like a passport - identifies the person
- **Updatable:** Can UPDATE fields directly

**`form_submissions` = Data Collection Events**
- **Purpose:** Track WHAT users submitted and WHEN
- **Multiple records per user** (one per form submission)
- **Contains:** Questionnaire answers, survey data, profile details they filled in
- **Think:** Like filled forms in a filing cabinet - each is a snapshot
- **Immutable:** NEVER update, always create new submission

**Why separate?**
```
user_accounts.firstname = "John"     → Who the person IS (identity)
form_submission.crop = ["Rice"]      → What they TOLD US (data point)
```

**Migration Impact:**
- Basic identity data (name, phone, tier) → `user_accounts`
- Everything users "filled out" (crops, area, preferences) → `form_submissions`

---

### User Profile Form vs Other Forms - What's the Difference?

**User Profile Form** (code: `USER_PROFILE`)
- **Old CRM Equivalent:** Default custom fields shown on signup form
- **Purpose:** Core profile data used across the system
- **Special:** Auto-submitted during registration, all users have it
- **Data:** Basic farming info (crops, land area)
- **Visibility:** Always visible, often required
- **Think:** Your LinkedIn profile - core info everyone sees

**Other Forms** (Big Grower, Surveys, Events)
- **Old CRM Equivalent:** Additional custom field groups (program-specific)
- **Purpose:** Specialized data collection for programs/campaigns
- **Special:** User opts-in or staff submits, not all users have it
- **Data:** Detailed program-specific info (equipment, costs, preferences)
- **Visibility:** May be conditional based on user type/persona
- **Think:** Job applications - specific to an opportunity

**Examples:**

| Form Type | When Created | Data Examples |
|-----------|-------------|---------------|
| User Profile | Every user gets one | crops: ["Rice"], area: 50 |
| Big Grower CP | Only CP users | spray equipment, cost breakdowns |
| Event Survey | After attending event | satisfaction rating, feedback |
| GWEP Form | Only GWEP participants | income before/after, yield data |

**Migration Decision Tree:**
```
Is this data universal to all users? 
  YES → User Profile form
  NO → Is it program/campaign specific?
    YES → Specialized form (Big Grower, Survey, etc.)
    NO → Might belong in user_accounts directly
```

**For Syngenta Migration:**
- Old CRM **default custom fields** (`plant`, `area`) → User Profile form (everyone has this)
- Old CRM **additional custom fields** (spray equipment, purchase factors) → Big Grower forms (program-specific)
- Old CRM **core identity** (name, phone, tier) → user_accounts table

**Key Insight:**
```
Old CRM has ONE user record with ALL custom fields mixed together
New CRM separates into:
  - user_accounts (identity)
  - form_submissions (custom field groups as separate forms)
```

### Data Flow Diagram
```
OLD CRM USER RECORD
    |
    ├─→ Identity Data (name, phone, email, tier)
    |   └─→ user_accounts (1 record)
    |       └─→ user_address (1 record)
    |
    ├─→ Basic Farming Data (crops, area)
    |   └─→ form_submissions (User Profile form)
    |       └─→ form_responses (crop=[], area=N)
    |
    ├─→ Detailed Program Data (equipment, costs)
    |   └─→ form_submissions (Big Grower forms)
    |       └─→ form_responses (spray methods, purchase factors, etc.)
    |
    ├─→ Points/Wallet
    |   └─→ user_wallet + wallet_ledger
    |
    └─→ Admin Tracking (migrated_source, staff_code, BZB IDs)
        └─→ user_accounts.marketplace_external_ids (JSONB)
```

---

## SECTION 1: USER ACCOUNTS + PROFILE DATA

### 1.1 Core User Account (`user_accounts` table)

**Primary Key Strategy:**
- Generate new UUID for `id`
- Map old `Line user Id` → `line_id` (primary identifier)
- Map old `userid` → `external_user_id` (preserve old CRM ID)

**Deduplication Logic (Priority Order):**
1. Match by `line_id` (if exists)
2. Match by `tel` (if exists)
3. Match by `email` (if exists)
4. Create new record

**Field Mapping:**

| Old CRM Field | New CRM Field | Table | Notes |
|--------------|---------------|-------|-------|
| Line user Id | `line_id` | user_accounts | Primary identifier |
| userid | `external_user_id` | user_accounts | Keep old CRM ID for reference |
| Phone No | `tel` | user_accounts | Strip +66 prefix or normalize |
| Email | `email` | user_accounts | Lowercase |
| First Name / firstName | `firstname` | user_accounts | |
| Last Name / lastName | `lastname` | user_accounts | |
| Name (if no first/last) | `fullname` | user_accounts | Use only if first/last empty |
| Date of birth | `birth_date` | user_accounts | Convert text to DATE |
| Gender / gender | `gender` | user_accounts | Map: "ชาย"→"male", "หญิง"→"female" |
| Profile image URL | `image` | user_accounts | Direct URL |
| Register Date | `created_at` | user_accounts | Convert text to TIMESTAMP |
| Status | `user_stage` | user_accounts | Map: "ACTIVE"→"member", "INACTIVE"→"lead" |
| Tier | `tier_id` | user_accounts | Map tier name to tier_master.id (create tiers first) |
| Points balance | DO NOT USE | - | Use wallet system instead |
| merchant_id | `8f67aa08-dfce-454d-bfb1-effc4ee45f1f` | user_accounts | Fixed value |
| user_type | `buyer` | user_accounts | Default value |
| role | `user` | user_accounts | Default value |

**SQL Template:**
```sql
INSERT INTO user_accounts (
  merchant_id, line_id, tel, email, firstname, lastname, fullname,
  birth_date, gender, image, external_user_id, user_stage, created_at,
  user_type, role
) VALUES (
  '8f67aa08-dfce-454d-bfb1-effc4ee45f1f',
  :line_id,
  :tel,
  :email,
  :firstname,
  :lastname,
  :fullname,
  :birth_date,
  :gender,
  :image,
  :external_user_id,
  :user_stage,
  :created_at,
  'buyer',
  'user'
)
ON CONFLICT (line_id, merchant_id) DO UPDATE
SET tel = EXCLUDED.tel, email = EXCLUDED.email, ...;
```

---

### 1.2 User Address (`user_address` table)

**One record per user**

| Old CRM Field | New CRM Field | Table | Notes |
|--------------|---------------|-------|-------|
| Address / Full Address | `addressline_1` | user_address | Street address |
| Province Name / province | `city` + `state` | user_address | Province |
| District Name | `district` | user_address | |
| Sub District Name | `subdistrict` | user_address | |
| Post Code | `postcode` | user_address | |
| - | `country_code` | user_address | Default: "TH" |
| - | `province_code` | user_address | Lookup from address_th_province |
| - | `district_code` | user_address | Lookup from address_th_district |
| - | `subdistrict_code` | user_address | Lookup from address_th_subdistrict |

**SQL Template:**
```sql
INSERT INTO user_address (
  user_id, merchant_id, addressline_1, city, state, district, subdistrict,
  postcode, country_code, province_code, district_code, subdistrict_code
) VALUES (
  :user_id,
  '8f67aa08-dfce-454d-bfb1-effc4ee45f1f',
  :addressline_1,
  :province,
  :province,
  :district,
  :subdistrict,
  :postcode,
  'TH',
  :province_code,
  :district_code,
  :subdistrict_code
);
```

---

### 1.3 Admin-Only Custom Fields

**Store in `user_accounts.marketplace_external_ids` (JSONB)**

| Old CRM Field | JSONB Key | Suggested Value | Notes |
|--------------|-----------|-----------------|-------|
| Migrated Source | `migrated_source` | "old_crm" | All migrated users |
| Member Type | `account_type` | Map: "Member"→"individual" | User classification |
| Seller Id | `staff_code` | Staff ID managing user | For reference |
| (BZB ID from old system) | `bzb_loyalty_id` | Direct copy | BZB integration |
| (BZB Code from old system) | `bzb_user_code` | Direct copy | BZB integration |

**SQL Template:**
```sql
UPDATE user_accounts SET
  marketplace_external_ids = jsonb_build_object(
    'migrated_source', 'old_crm',
    'account_type', :account_type,
    'staff_code', :staff_code,
    'bzb_loyalty_id', :bzb_loyalty_id,
    'bzb_user_code', :bzb_user_code
  )
WHERE id = :user_id;
```

**Example JSONB Value:**
```json
{
  "migrated_source": "old_crm",
  "account_type": "individual",
  "staff_code": "EMP001",
  "bzb_loyalty_id": "BZB123456",
  "bzb_user_code": "USER789"
}
```

---

### 1.4 Form Submissions - PROFILE DATA

**⚠️ IMPORTANT: Event Sourcing Nature**

`form_submissions` is an **append-only log** (similar to event sourcing):
- Each submission = one immutable snapshot in time
- Same user can have MULTIPLE submissions for same form
- Each has unique `id`, `submission_number`, `submitted_at`
- **DO NOT UPDATE** existing submissions - always INSERT new records
- To "update" user data = submit a new form submission

**Think of it as:** "User filled out profile form on DATE X with VALUES Y"

**Current State = Latest Submission** (filtered by max(submitted_at))

**For Migration:** Create ONE initial submission per user representing their state from old CRM

**Form ID for User Profile:** `a0000000-0000-0000-0000-000000000001` (code: `USER_PROFILE`)

**Step 1: Insert into `form_submissions`**

```sql
INSERT INTO form_submissions (
  form_id,
  merchant_id,
  user_id,
  status,
  created_at,
  submitted_at,
  source,
  tel
) VALUES (
  'a0000000-0000-0000-0000-000000000001',
  '8f67aa08-dfce-454d-bfb1-effc4ee45f1f',
  :user_id,
  'completed',
  :register_date,
  :register_date,
  'migration',
  :tel
) RETURNING id;
```

**Step 2: Insert field responses into `form_responses`**

Get field IDs first:
```sql
SELECT id, field_key FROM form_fields 
WHERE form_id = 'a0000000-0000-0000-0000-000000000001';
```

Current fields in Syngenta User Profile form:
- `crop` (multi-select, array) - map from old `plant` field
- `area` (number) - map from old `area` field

```sql
-- Crop field (array value)
INSERT INTO form_responses (submission_id, field_id, array_value)
VALUES (:submission_id, :crop_field_id, :plant_array);

-- Area field (text value)
INSERT INTO form_responses (submission_id, field_id, text_value)
VALUES (:submission_id, :area_field_id, :area_value);
```

**Mapping Examples:**

| Old CRM Field | Form Field | Response Type | Transformation |
|--------------|------------|---------------|----------------|
| plant (e.g., "ข้าว,ข้าวโพดไร่") | `crop` | array_value | Split by comma → `["ข้าว", "ข้าวโพดไร่"]` |
| area (e.g., "20") | `area` | text_value | Convert to string |

---

### 1.5 Form Submissions - BIG GROWER DATA (If Applicable)

**Only migrate if user has this data in old CRM**

**Forms available:**
1. Big grower - advanced: `form_id` TBD
2. Big grower - FC: `form_id` TBD  
3. Big grower CP: `form_id` TBD

**Complex Field Structures (use array_value or object_value):**

**Example: CP Application Method (Spray Equipment)**
```json
{
  "array_value": [
    {
      "type": "boomspray",
      "size": "200 ลิตร",
      "budget": "1000",
      "labour": "ใช้แรงงาน จ้างประจำ"
    }
  ]
}
```

**Example: Purchase Factors**
```json
{
  "object_value": {
    "price": "40",
    "quality": "60",
    "promotion": "0",
    "trend": "0",
    "trust": "0",
    "sales": "0"
  }
}
```

**Example: Purchase Channel**
```json
{
  "array_value": [
    {
      "channel": "Freemarket",
      "channelPurchase": 50,
      "storeName": "ร้านค้าXYZ",
      "cash": 30,
      "credit": 70
    }
  ]
}
```

**See full field mapping in OLD_CRM_FIELD_MAPPING.md**

---

## SECTION 2: WALLET BALANCE (Points)

### 2.1 User Wallet (`user_wallet` table)

**One record per user - current balance snapshot**

| Old CRM Field | New CRM Field | Calculation |
|--------------|---------------|-------------|
| Points balance | `points_balance` | Direct copy |
| - | `ticket_balance` | Default: 0 (if not in old CRM) |

**SQL Template:**
```sql
INSERT INTO user_wallet (
  user_id,
  merchant_id,
  points_balance,
  ticket_balance
) VALUES (
  :user_id,
  '8f67aa08-dfce-454d-bfb1-effc4ee45f1f',
  :points_balance,
  0
);
```

**CRITICAL:** Wallet balance will be recalculated from ledger. This is just initial seed.

---

## SECTION 3: WALLET TRANSACTION HISTORY

### 3.1 Wallet Ledger (`wallet_ledger` table)

**Reconstruct transaction history from old CRM data**

**If old CRM has transaction history:**
- Migrate each transaction as separate ledger entry

**If old CRM only has summary (Points collected, Points Used):**
- Create synthetic transactions to match final balance

**Required Ledger Entries:**

1. **Initial Points Grant (if Points collected exists)**
```sql
INSERT INTO wallet_ledger (
  merchant_id,
  user_id,
  currency,
  transaction_type,
  signed_amount,
  amount,
  balance_before,
  balance_after,
  source_type,
  source_id,
  description,
  created_by,
  component,
  created_at
) VALUES (
  '8f67aa08-dfce-454d-bfb1-effc4ee45f1f',
  :user_id,
  'points',
  'earn',  -- or appropriate type
  :points_collected,  -- positive number
  :points_collected,
  0,
  :points_collected,
  'migration',
  :user_id,
  'Migrated from old CRM - Points Collected',
  'system',
  'base',
  :register_date
);
```

2. **Points Redemption (if Points Used exists)**
```sql
INSERT INTO wallet_ledger (
  merchant_id,
  user_id,
  currency,
  transaction_type,
  signed_amount,
  amount,
  balance_before,
  balance_after,
  source_type,
  source_id,
  description,
  created_by,
  component,
  created_at
) VALUES (
  '8f67aa08-dfce-454d-bfb1-effc4ee45f1f',
  :user_id,
  'points',
  'redeem',  -- or appropriate type
  -:points_used,  -- negative number
  :points_used,
  :points_collected,
  :final_balance,  -- should equal "Points balance"
  'migration',
  :user_id,
  'Migrated from old CRM - Points Used',
  'system',
  'base',
  :register_date
);
```

**Field Mapping:**

| Field | Value | Type | Notes |
|-------|-------|------|-------|
| currency | `points` or `ticket` | ENUM | Use 'points' for loyalty points |
| transaction_type | TBD | ENUM | Check valid values in DB |
| source_type | `migration` | ENUM | Check valid values in DB |
| source_id | `user_id` | UUID | Reference to user |
| component | `base` | ENUM | Default component |
| signed_amount | +/- number | INTEGER | Positive for earn, negative for spend |
| amount | absolute value | INTEGER | Always positive |
| balance_before | previous balance | INTEGER | Running balance |
| balance_after | new balance | INTEGER | Running balance |
| dedup_key | unique string | TEXT | Prevent duplicate imports |

**Calculate Final Balance:**
```
Final Balance = Points Collected - Points Used
Should equal "Points balance" from old CRM
```

**Deduplication Key Format:**
```
migration_{old_user_id}_{transaction_type}_{sequence}
```

---

## SECTION 4: TIER ASSIGNMENT

### 4.1 Tier Master (Prerequisites)

**BEFORE MIGRATION:** Create tier records in `tier_master` table

Map old CRM tier names:
- "Member" → Create tier with `tier_name = "Member"`
- Other tiers → Map accordingly

```sql
INSERT INTO tier_master (
  merchant_id,
  tier_name,
  user_type,
  ranking,
  entry_tier
) VALUES (
  '8f67aa08-dfce-454d-bfb1-effc4ee45f1f',
  'Member',
  'buyer',
  1,
  true
) RETURNING id;
```

### 4.2 Tier Assignment

In `user_accounts.tier_id`, set to matched tier UUID.

**No separate tier change ledger needed for initial migration** - just set current tier.

If you want tier history, create entry in `tier_change_ledger`:
```sql
INSERT INTO tier_change_ledger (
  user_id,
  merchant_id,
  old_tier_id,
  new_tier_id,
  change_reason,
  created_at
) VALUES (
  :user_id,
  '8f67aa08-dfce-454d-bfb1-effc4ee45f1f',
  NULL,
  :tier_id,
  'Initial migration from old CRM',
  :register_date
);
```

---

## PIPELINE IMPLEMENTATION CHECKLIST

### Pre-Pipeline Setup
- [ ] Create tier records in `tier_master`
- [ ] Get form field IDs for User Profile form
- [ ] Verify enum values for wallet_ledger (currency, transaction_type, source_type)
- [ ] Set up province/district/subdistrict code lookup tables
- [ ] Create Snowflake → New CRM sync job (daily schedule)
- [ ] Set up monitoring/alerting for sync failures

### Sync Order (Run Daily)
1. [ ] `user_accounts` - Upsert users (match by `external_user_id` or `line_id`)
2. [ ] `user_address` - Upsert addresses (match by `user_id`)
3. [ ] `marketplace_external_ids` - Update admin fields (BZB IDs, etc.)
4. [ ] `user_wallet` - Update balances (or recalculate from ledger)
5. [ ] `wallet_ledger` - Insert new transactions only (check `dedup_key`)
6. [ ] `form_submissions` - Insert new submissions only (check by `external_user_id` + `form_id` + date)
7. [ ] Validation: Verify balances match between old and new CRM

### Incremental Sync Strategy
**Track last sync timestamp** - Only process records where:
```sql
old_crm.updated_at > last_sync_timestamp
```

**Deduplication:**
- `user_accounts`: Use `ON CONFLICT (line_id, merchant_id) DO UPDATE`
- `wallet_ledger`: Check `dedup_key` before insert
- `form_submissions`: Check if submission already exists for user+form+date

### Daily Validation Checks
- [ ] Count: Old CRM active users = New CRM users
- [ ] Sum: Old CRM total points = New CRM total points (±tolerance)
- [ ] Check: No orphaned records (addresses without users, etc.)
- [ ] Alert: Any sync errors or data mismatches
- [ ] Report: Daily sync stats (new users, updated users, points synced)

---

## IMPORTANT NOTES

### For Daily Pipeline
1. **Idempotency is critical** - Pipeline must be safe to re-run multiple times
2. **Use upsert patterns** - `ON CONFLICT DO UPDATE` for user_accounts, user_address
3. **Deduplication keys** - Prevent duplicate wallet_ledger entries on re-runs
4. **Track sync state** - Store `last_sync_timestamp` to process only changed records
5. **Atomic operations** - Use transactions per user to rollback individual failures
6. **Monitoring** - Alert on sync failures, data mismatches, or missing records
7. **Validation queries** - Run after each sync to verify data integrity

### For Initial Load
1. **Batch processing** - Process in chunks of 100-1000 users
2. **Parallel workers** - Can process multiple batches simultaneously
3. **Resume capability** - If pipeline fails mid-run, resume from last successful batch
4. **Dry run** - Test full pipeline on staging environment first

### For Cutover Night
1. **Final sync** - Run one last time before cutover
2. **Verify counts** - Ensure 100% of old CRM users are in new CRM
3. **Freeze old CRM** - Disable writes to old CRM
4. **Enable new CRM** - Switch application to use new CRM
5. **Keep old CRM read-only** - For reference and rollback if needed

---

## ENUM VALUES REFERENCE

**Currency** (what type of currency):
- `points` - Loyalty points
- `ticket` - Raffle/event tickets

**Transaction Type** (earn or spend):
- `earn` - Points earned/credited
- `burn` - Points spent/debited

**Source Type** (where transaction came from):
- `manual` - Manual admin adjustment
- `purchase` - From purchase/order
- `activity` - From activity/mission completion
- **Use `manual` for migration transactions**

**Currency Component** (base vs bonus):
- `base` - Standard points
- `bonus` - Bonus/promotional points
- `adjustment` - Admin correction
- `reversal` - Reversal of previous transaction
- **Use `base` for migration transactions**
