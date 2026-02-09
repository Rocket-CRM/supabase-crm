# Multi-Quantity Promo Code Redemption - Implementation Plan

## Current State Analysis

### Current Limitations

**From requirements (Reward.md line 1155):**
> "Single Promo Code Redemption: Rewards with promo codes can only be redeemed one at a time"

**Current Implementation Issues:**

1. **Inefficient Loop** - Creates multiple records with qty=1 each:
```sql
FOR i IN 1..p_quantity LOOP
    INSERT INTO reward_redemptions_ledger (..., qty, promo_code, ...)
    VALUES (..., 1, CASE WHEN i = 1 THEN v_promo_code ELSE NULL END, ...)
END LOOP
```

**Problems:**
- Only first record gets promo code
- Records 2-N have `promo_code = NULL`
- Creates N rows instead of using the qty column
- No atomicity: if pool runs out mid-loop, partial redemptions occur

2. **Quantity Restriction:**
```sql
IF v_reward.assign_promocode AND p_quantity = 1 THEN
    -- Only assigns code when qty = 1
END IF
```

**Result:** User must make 5 separate API calls to redeem 5 vouchers with codes.

---

## Proposed Solution

### Design Philosophy

**Two distinct redemption patterns:**

1. **Rewards WITHOUT promo codes:**
   - Single ledger record with `qty = N`
   - One redemption code (RWD000123)
   - Efficient storage

2. **Rewards WITH promo codes:**
   - Multiple ledger records (one per unit)
   - Each record has `qty = 1` and unique promo code
   - One redemption transaction ID to group them
   - Clear audit trail per promo code

### Why Different Patterns?

**Without Promo Codes:**
- No need to track individual units
- User gets "5 coffee vouchers" as a bundle
- One fulfillment action

**With Promo Codes:**
- Each code must be individually tracked
- User gets 5 distinct codes: `PROMO-A`, `PROMO-B`, `PROMO-C`, etc.
- Each code may be used at different times/places
- Need separate fulfillment per code

---

## Implementation Details

### 1. Add Transaction Grouping Field

**Schema Change:**
```sql
ALTER TABLE reward_redemptions_ledger 
ADD COLUMN transaction_id UUID;

-- Add index for grouping queries
CREATE INDEX idx_redemption_transaction 
ON reward_redemptions_ledger(transaction_id, user_id);

COMMENT ON COLUMN reward_redemptions_ledger.transaction_id IS 
'Groups multiple redemption records that belong to the same redemption transaction (for multi-qty promo code redemptions)';
```

**Purpose:**
- Groups related records: "These 5 records = 1 redemption transaction"
- Query: "Show me all codes from this redemption"
- Refund: "Cancel entire transaction atomically"

### 2. Enhanced Promo Code Assignment Logic

**New Algorithm:**

```sql
-- Step 1: Check promo code availability BEFORE creating records
IF v_reward.assign_promocode THEN
    -- Count available codes in pool
    SELECT COUNT(*) INTO v_available_codes
    FROM reward_promo_code
    WHERE reward_id = p_reward_id 
      AND merchant_id = v_merchant_id 
      AND redeemed_status = false;
    
    -- Validate sufficient codes exist
    IF v_available_codes < p_quantity THEN
        RETURN jsonb_build_object(
            'success', false,
            'title', 'Insufficient promo codes',
            'description', format('Only %s code(s) available, you requested %s', 
                                  v_available_codes, p_quantity),
            'data', jsonb_build_object(
                'available', v_available_codes,
                'requested', p_quantity,
                'shortage', p_quantity - v_available_codes
            )
        );
    END IF;
    
    -- Step 2: Reserve codes atomically
    -- Use FOR UPDATE SKIP LOCKED to prevent race conditions
    WITH reserved_codes AS (
        SELECT promo_code
        FROM reward_promo_code
        WHERE reward_id = p_reward_id 
          AND merchant_id = v_merchant_id 
          AND redeemed_status = false
        ORDER BY created_at
        LIMIT p_quantity
        FOR UPDATE SKIP LOCKED
    )
    SELECT ARRAY_AGG(promo_code) INTO v_promo_codes_array
    FROM reserved_codes;
    
    -- Verify we got all codes (concurrent redemption check)
    IF array_length(v_promo_codes_array, 1) < p_quantity THEN
        RAISE EXCEPTION 'Concurrent redemption conflict - codes unavailable';
    END IF;
END IF;
```

### 3. Redemption Logic Branching

```sql
-- Generate transaction ID for grouping
v_transaction_id := gen_random_uuid();

-- Branch based on promo code requirement
IF v_reward.assign_promocode THEN
    -- ==========================================
    -- PATH A: Multiple records (one per code)
    -- ==========================================
    
    FOR i IN 1..p_quantity LOOP
        INSERT INTO reward_redemptions_ledger (
            merchant_id, user_id, reward_id,
            qty,                    -- ✅ Set to 1 (individual unit)
            promo_code,            -- ✅ Unique code per record
            transaction_id,        -- ✅ Groups related records
            points_deducted,       -- ✅ Points per unit
            points_calculation,
            use_expire_date,
            redeemed_status, redeemed_at,
            source_type, source_id
        ) VALUES (
            v_merchant_id, v_target_user_id, p_reward_id,
            1,                                    -- Individual unit
            v_promo_codes_array[i],              -- Unique code from pool
            v_transaction_id,                    -- Same for all in transaction
            v_points_required / p_quantity,      -- Split points evenly
            v_points_calc,
            v_use_expire_date,
            true, CURRENT_TIMESTAMP,
            v_source_type_enum, p_source_id
        ) RETURNING * INTO v_redemption;
        
        -- Mark promo code as redeemed
        UPDATE reward_promo_code 
        SET redeemed_status = true 
        WHERE promo_code = v_promo_codes_array[i];
        
        -- Collect for response
        v_redemptions := array_append(v_redemptions, 
            jsonb_build_object(
                'redemption_id', v_redemption.id,
                'redemption_code', v_redemption.code,
                'promo_code', v_redemption.promo_code,
                'qty', 1,
                'unit_number', i,
                'transaction_id', v_transaction_id
            )
        );
    END LOOP;
    
ELSE
    -- ==========================================
    -- PATH B: Single record (qty field used)
    -- ==========================================
    
    INSERT INTO reward_redemptions_ledger (
        merchant_id, user_id, reward_id,
        qty,                    -- ✅ Actual quantity
        promo_code,            -- NULL or default code
        transaction_id,        -- Can be NULL (not needed for grouping)
        points_deducted,
        points_calculation,
        use_expire_date,
        redeemed_status, redeemed_at,
        source_type, source_id
    ) VALUES (
        v_merchant_id, v_target_user_id, p_reward_id,
        p_quantity,                          -- ✅ Full quantity in one record
        v_reward.promo_code,                -- Default code (if any)
        NULL,                               -- No grouping needed
        v_points_required,                  -- Total points
        v_points_calc,
        v_use_expire_date,
        true, CURRENT_TIMESTAMP,
        v_source_type_enum, p_source_id
    ) RETURNING * INTO v_redemption;
    
    -- Single record response
    v_redemptions := ARRAY[
        jsonb_build_object(
            'redemption_id', v_redemption.id,
            'redemption_code', v_redemption.code,
            'promo_code', v_redemption.promo_code,
            'qty', v_redemption.qty
        )
    ];
END IF;
```

### 4. Response Structure Enhancement

```json
{
  "success": true,
  "title": "Reward redeemed successfully",
  "data": {
    "transaction_id": "uuid",  // NEW: Groups related records
    "total_quantity": 5,
    "total_points_deducted": 500,
    "new_balance": 1500,
    
    "redemptions": [
      {
        "redemption_id": "uuid-1",
        "redemption_code": "RWD000123",
        "promo_code": "COFFEE-ABC123",  // Unique code
        "qty": 1,
        "unit_number": 1  // NEW: Position in transaction
      },
      {
        "redemption_id": "uuid-2",
        "redemption_code": "RWD000124",
        "promo_code": "COFFEE-DEF456",  // Different unique code
        "qty": 1,
        "unit_number": 2
      },
      // ... 3 more records
    ],
    
    "redemption_summary": {
      "has_promo_codes": true,
      "records_created": 5,
      "pattern": "multiple"  // or "single"
    }
  }
}
```

---

## Edge Cases & Handling

### 1. Insufficient Promo Codes

**Scenario:** User tries to redeem 10 vouchers, but only 7 codes available

**Solution:**
```sql
-- Check BEFORE starting transaction
IF v_available_codes < p_quantity THEN
    RETURN error with available count
END IF
```

**UX:** Frontend can show:
- "Only 7 vouchers available (you requested 10)"
- Allow user to adjust quantity
- Or split into multiple redemptions

### 2. Concurrent Redemptions

**Scenario:** Two users redeem simultaneously, both claim same codes

**Solution:**
```sql
-- Use FOR UPDATE SKIP LOCKED
SELECT ... FOR UPDATE SKIP LOCKED
```

**Behavior:**
- User A: Locks codes 1-5
- User B (concurrent): Gets codes 6-10 (skips locked rows)
- No deadlocks, no duplicates

### 3. Partial Failure Mid-Loop

**Scenario:** Loop creates 3 records, fails on 4th

**Solution:**
```sql
-- Entire function runs in transaction
-- PostgreSQL automatically rolls back on exception
BEGIN
    -- All INSERTs and UPDATEs
    ...
EXCEPTION WHEN OTHERS THEN
    -- Transaction rolled back automatically
    RETURN error response
END
```

**Result:** Either ALL records created, or NONE. No partial redemptions.

### 4. Promo Code Pool Depletion During Transaction

**Scenario:** Between availability check and reservation, another transaction consumes codes

**Solution:**
```sql
-- Double-check after locking
IF array_length(v_promo_codes_array, 1) < p_quantity THEN
    RAISE EXCEPTION 'Concurrent redemption conflict';
END IF
```

**Behavior:** Transaction fails gracefully, user notified to retry.

---

## Migration Strategy

### Phase 1: Schema Update

```sql
-- Add transaction_id field
ALTER TABLE reward_redemptions_ledger 
ADD COLUMN transaction_id UUID;

-- Add index
CREATE INDEX idx_redemption_transaction 
ON reward_redemptions_ledger(transaction_id, user_id);

-- Add comment
COMMENT ON COLUMN reward_redemptions_ledger.transaction_id IS 
'Groups multiple redemption records from the same redemption transaction';
```

### Phase 2: Update Function

**Replace `redeem_reward_with_points` with new logic:**

1. Availability check for promo codes
2. Atomic code reservation
3. Branching logic (promo codes vs. no promo codes)
4. Enhanced response with transaction grouping

### Phase 3: Remove Business Rule Restriction

**Update documentation:**
- ❌ ~~"Rewards with promo codes can only be redeemed one at a time"~~
- ✅ "Rewards with promo codes create individual records per unit, grouped by transaction_id"

**Remove error RWD013:**
- No longer needed
- Users can redeem any quantity (if codes available)

---

## Query Patterns

### Get All Redemptions from a Transaction

```sql
SELECT 
    r.id,
    r.code as redemption_code,
    r.promo_code,
    r.qty,
    r.points_deducted,
    r.redeemed_at
FROM reward_redemptions_ledger r
WHERE r.transaction_id = 'transaction-uuid'
ORDER BY r.created_at;
```

### Count User's Total Redemptions (Both Patterns)

```sql
-- Old way (wrong - counts records)
SELECT COUNT(*) FROM reward_redemptions_ledger WHERE user_id = ?;

-- New way (correct - sums qty)
SELECT 
    COUNT(DISTINCT COALESCE(transaction_id, id)) as total_transactions,
    SUM(qty) as total_units_redeemed
FROM reward_redemptions_ledger 
WHERE user_id = ?;
```

### Group Redemptions for Display

```sql
SELECT 
    COALESCE(transaction_id, id) as group_id,
    MIN(created_at) as redeemed_at,
    reward_id,
    SUM(qty) as total_qty,
    SUM(points_deducted) as total_points,
    ARRAY_AGG(promo_code) FILTER (WHERE promo_code IS NOT NULL) as promo_codes,
    bool_or(assign_promocode) as has_promo_codes
FROM reward_redemptions_ledger
WHERE user_id = ?
GROUP BY COALESCE(transaction_id, id), reward_id
ORDER BY MIN(created_at) DESC;
```

---

## Testing Checklist

### Unit Tests

- [ ] Redeem 1 reward without promo code → 1 record, qty=1
- [ ] Redeem 5 rewards without promo code → 1 record, qty=5
- [ ] Redeem 1 reward with promo code → 1 record, qty=1, code assigned
- [ ] Redeem 5 rewards with promo code → 5 records, qty=1 each, 5 unique codes
- [ ] Try to redeem 10 when only 7 codes available → Error with available count
- [ ] Concurrent redemptions don't assign duplicate codes
- [ ] Transaction rollback on mid-loop failure
- [ ] Points deducted correctly for both patterns
- [ ] transaction_id properly groups multi-unit redemptions

### Integration Tests

- [ ] Frontend displays grouped redemptions correctly
- [ ] User can cancel entire transaction (all units)
- [ ] Promo code pool updates correctly after batch redemption
- [ ] Wallet balance updates atomically
- [ ] Audit trail shows proper lineage

### Performance Tests

- [ ] Redeem 100 units with promo codes (stress test pool locking)
- [ ] Concurrent redemptions from 50 users
- [ ] Query performance with transaction_id grouping

---

## Rollout Plan

### Step 1: Schema Migration (Non-Breaking)
```sql
-- Add transaction_id field (nullable, no default)
ALTER TABLE reward_redemptions_ledger ADD COLUMN transaction_id UUID;
CREATE INDEX idx_redemption_transaction ON reward_redemptions_ledger(transaction_id, user_id);
```

**Impact:** None - existing records continue working with `transaction_id = NULL`

### Step 2: Deploy New Function
- Replace `redeem_reward_with_points` 
- Backward compatible (existing calls with qty=1 work identically)

### Step 3: Update Documentation
- Remove RWD013 error code
- Update API examples
- Frontend integration guide

### Step 4: Monitor
- Track promo code pool depletion rates
- Monitor concurrent redemption conflicts
- Measure query performance with grouping

---

## Benefits Summary

### User Experience
✅ **Single API call** for multiple redemptions
✅ **Atomic transaction** - all or nothing
✅ **Clear error messages** when codes unavailable
✅ **Grouped receipts** - see all codes from one redemption

### System Performance
✅ **Efficient storage** - No promo codes = single record
✅ **Clear audit trail** - With promo codes = individual tracking
✅ **No race conditions** - Atomic code reservation with locking
✅ **Transaction safety** - Rollback on any failure

### Business Logic
✅ **Flexible patterns** - Adapts to reward type
✅ **Accurate reporting** - Proper qty aggregation
✅ **Code tracking** - Each promo code individually managed
✅ **Cancellation support** - Cancel entire transaction via transaction_id

---

## Open Questions

1. **Partial fulfillment:** If user redeems 5 units, can they cancel 2 and keep 3?
   - Proposed: Cancel entire transaction only (all or nothing)
   - Alternative: Allow individual unit cancellation

2. **Points refund calculation:** When canceling, how to handle:
   - Scenario: Redeemed 5 @ 100pts each = 500pts total
   - Cancel entire transaction → Refund 500pts ✅
   - Cancel 2 units → Refund 200pts? (if allowed)

3. **Promo code expiry:** If transaction has 5 codes:
   - Do all codes expire together?
   - Or individual expiry per code?
   - Proposed: Same expiry for all (from transaction timestamp)

4. **Display in user history:**
   - Show as 1 line: "5x Coffee Voucher (5 codes)"
   - Or 5 separate lines?
   - Proposed: Grouped view with expandable details

---

**Implementation Status:** 📋 Planning Phase
**Next Step:** Get approval on design decisions
**Estimated Effort:** 4-6 hours (schema + function + tests)
