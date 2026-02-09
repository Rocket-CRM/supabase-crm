# Multi-Quantity Promo Code Redemption - Implementation Summary

## ✅ Implementation Complete

**Date:** 2026-02-03  
**Function:** `redeem_reward_with_points`  
**Status:** Deployed and Ready

---

## What Was Implemented

### **Two Redemption Patterns**

#### Pattern A: Rewards WITHOUT Promo Codes
**Behavior:** Single efficient record
```javascript
// User redeems 5 coffee vouchers (no promo codes)
await supabase.rpc('redeem_reward_with_points', {
  p_reward_id: 'coffee-uuid',
  p_quantity: 5
});

// Result: 1 ledger record with qty=5
```

**Database:**
```sql
reward_redemptions_ledger
├─ id: uuid-1
├─ qty: 5                    ✅ Uses qty column
├─ promo_code: NULL or default
├─ points_deducted: 500
└─ code: RWD000123
```

#### Pattern B: Rewards WITH Promo Codes
**Behavior:** Multiple records (one per code)
```javascript
// User redeems 5 vouchers WITH promo codes
await supabase.rpc('redeem_reward_with_points', {
  p_reward_id: 'voucher-with-codes-uuid',
  p_quantity: 5
});

// Result: 5 ledger records, each with qty=1 and unique promo code
```

**Database:**
```sql
reward_redemptions_ledger
├─ id: uuid-1, qty: 1, promo_code: 'COFFEE-ABC123', code: RWD000123
├─ id: uuid-2, qty: 1, promo_code: 'COFFEE-DEF456', code: RWD000124
├─ id: uuid-3, qty: 1, promo_code: 'COFFEE-GHI789', code: RWD000125
├─ id: uuid-4, qty: 1, promo_code: 'COFFEE-JKL012', code: RWD000126
└─ id: uuid-5, qty: 1, promo_code: 'COFFEE-MNO345', code: RWD000127
```

**Why separate records?**
- Each promo code tracked individually
- Can be used at different times/places
- Clear audit trail per code
- Allows individual fulfillment tracking

---

## Key Features

### 1. ✅ Promo Code Availability Check

**Before creating ANY records:**
```sql
-- Counts available codes in pool
SELECT COUNT(*) FROM reward_promo_code 
WHERE reward_id = ? AND redeemed_status = false;

-- If insufficient, returns error
IF available < requested THEN
  RETURN error with details
END IF
```

**Error Response:**
```json
{
  "success": false,
  "title": "Insufficient promo codes",
  "description": "Only 7 code(s) available, you requested 10",
  "data": {
    "available": 7,
    "requested": 10,
    "shortage": 3
  }
}
```

### 2. ✅ Atomic Code Reservation

**Uses `FOR UPDATE SKIP LOCKED` to prevent race conditions:**
```sql
SELECT ARRAY_AGG(promo_code ORDER BY created_at)
FROM (
  SELECT promo_code, created_at
  FROM reward_promo_code
  WHERE reward_id = ? 
    AND merchant_id = ? 
    AND redeemed_status = false
  ORDER BY created_at
  LIMIT quantity
  FOR UPDATE SKIP LOCKED  -- ✅ Atomic locking
) codes;
```

**Concurrent Redemption Safety:**
- User A requests 5 codes → locks codes 1-5
- User B requests 5 codes (concurrent) → gets codes 6-10 (skips locked)
- No duplicate assignments
- No deadlocks

### 3. ✅ All-or-Nothing Transaction

**If anything fails, everything rolls back:**
- Promo code pool depleted mid-loop → Full rollback
- Points deduction fails → No redemption records created
- PostgreSQL transaction safety ensures atomicity

### 4. ✅ Intelligent Branching

**Function automatically chooses pattern:**
```sql
IF reward.assign_promocode THEN
  -- Create N records with unique codes
  FOR i IN 1..quantity LOOP
    INSERT ... promo_code = codes_array[i]
  END LOOP
ELSE
  -- Create 1 record with full quantity
  INSERT ... qty = quantity
END IF
```

---

## Response Structure

### Success Response (With Promo Codes)

```json
{
  "success": true,
  "title": "Reward redeemed successfully",
  "description": null,
  "data": {
    "redemptions": [
      {
        "redemption_id": "uuid-1",
        "redemption_code": "RWD000123",
        "reward_id": "reward-uuid",
        "reward_name": "Coffee Voucher",
        "promo_code": "COFFEE-ABC123",
        "qty": 1,
        "unit_number": 1,
        "points_deducted": 100,
        "redeemed_at": "2026-02-03T10:00:00Z",
        "use_expire_date": "2026-03-05T10:00:00Z",
        "translations": {...}
      },
      {
        "redemption_id": "uuid-2",
        "redemption_code": "RWD000124",
        "promo_code": "COFFEE-DEF456",
        "qty": 1,
        "unit_number": 2,
        ...
      }
      // ... 3 more records
    ],
    "total_quantity": 5,
    "total_points_deducted": 500,
    "new_balance": 1500,
    "has_promo_codes": true,
    "records_created": 5
  }
}
```

### Success Response (Without Promo Codes)

```json
{
  "success": true,
  "title": "Reward redeemed successfully",
  "data": {
    "redemptions": [
      {
        "redemption_id": "uuid-1",
        "redemption_code": "RWD000123",
        "reward_id": "reward-uuid",
        "reward_name": "Coffee Mug",
        "promo_code": null,
        "qty": 5,                    // ✅ Full quantity
        "points_deducted": 500,
        "redeemed_at": "2026-02-03T10:00:00Z",
        ...
      }
    ],
    "total_quantity": 5,
    "total_points_deducted": 500,
    "new_balance": 1500,
    "has_promo_codes": false,
    "records_created": 1             // ✅ Single record
  }
}
```

---

## Edge Cases Handled

### ✅ Insufficient Codes
**Scenario:** User requests 10, only 7 available

**Behavior:**
- Check before creating records
- Return clear error with available count
- No partial redemptions
- Frontend can adjust quantity or split request

### ✅ Concurrent Redemptions
**Scenario:** Two users redeem simultaneously

**Behavior:**
- `FOR UPDATE SKIP LOCKED` prevents duplicates
- Each user gets different codes
- No deadlocks
- Graceful failure if pool depletes during reservation

### ✅ Mid-Loop Failure
**Scenario:** Loop creates 3 records, fails on 4th

**Behavior:**
- PostgreSQL transaction rolls back automatically
- All 3 records deleted
- Promo code status reverted
- Points not deducted
- User gets error response

### ✅ Expiry Handling
**Scenario:** 5 units redeemed in one transaction

**Behavior:**
- All created at same timestamp
- Expiry mode applied uniformly:
  - `relative_days`: All expire on same date
  - `relative_mins`: All expire at same time
  - `absolute_date`: All use same fixed date
- No special handling needed ✅

---

## Breaking Changes

### ❌ None - Fully Backward Compatible

**Existing code continues working:**
```javascript
// Old code (qty=1) - works identically
await supabase.rpc('redeem_reward_with_points', {
  p_reward_id: 'reward-uuid',
  p_quantity: 1  // or omit (defaults to 1)
});
```

**New functionality:**
```javascript
// New code (qty>1) - now supported
await supabase.rpc('redeem_reward_with_points', {
  p_reward_id: 'reward-uuid',
  p_quantity: 5  // ✅ Now works with promo codes!
});
```

---

## Removed Restrictions

### ❌ Removed Error: RWD013

**Old behavior:**
- Error RWD013: "Multi-quantity not allowed: Promo code rewards require qty=1"
- Users forced to make N separate API calls

**New behavior:**
- Single API call for any quantity
- Proper code assignment
- Clear error if pool insufficient

---

## Query Patterns

### Get User's Total Redemptions

```sql
-- ❌ WRONG (counts records, not units)
SELECT COUNT(*) FROM reward_redemptions_ledger WHERE user_id = ?;

-- ✅ CORRECT (sums qty)
SELECT SUM(qty) as total_units
FROM reward_redemptions_ledger 
WHERE user_id = ?;
```

### Display User's Redemption History

```sql
-- For UI display, group by reward
SELECT 
    reward_id,
    MIN(created_at) as redeemed_at,
    SUM(qty) as total_qty,
    SUM(points_deducted) as total_points,
    ARRAY_AGG(promo_code) FILTER (WHERE promo_code IS NOT NULL) as codes,
    COUNT(*) as record_count
FROM reward_redemptions_ledger
WHERE user_id = ?
GROUP BY reward_id
ORDER BY MIN(created_at) DESC;
```

**Result:**
```
reward_id        | redeemed_at | total_qty | total_points | codes                                    | record_count
----------------|-------------|-----------|--------------|------------------------------------------|-------------
coffee-voucher  | 10:00 AM    | 5         | 500          | [CODE1, CODE2, CODE3, CODE4, CODE5]      | 5
coffee-mug      | 09:00 AM    | 3         | 300          | []                                       | 1
```

---

## Testing Recommendations

### Unit Tests

✅ Redeem 1 reward without promo code → 1 record, qty=1  
✅ Redeem 5 rewards without promo code → 1 record, qty=5  
✅ Redeem 1 reward with promo code → 1 record, 1 unique code  
✅ Redeem 5 rewards with promo code → 5 records, 5 unique codes  
✅ Request 10 when only 7 codes available → Error with details  
✅ Concurrent redemptions don't duplicate codes  
✅ Mid-loop failure rolls back completely  
✅ Points deducted correctly for both patterns  

### Integration Tests

✅ Frontend displays multi-code redemptions properly  
✅ All codes from multi-qty redemption expire together  
✅ Promo code pool updates correctly  
✅ Wallet balance atomic update  

---

## Performance Impact

### Without Promo Codes
- **Better:** 1 INSERT instead of N INSERTs
- **Storage:** Minimal (single record)
- **Query:** Fast (no joins needed)

### With Promo Codes
- **Same:** N INSERTs (unavoidable - each code needs tracking)
- **Storage:** N records (necessary for audit trail)
- **Query:** Use SUM(qty) for aggregations

### Promo Code Locking
- **`FOR UPDATE SKIP LOCKED`:** No deadlocks
- **Impact:** Minimal (row-level locks, milliseconds)
- **Scalability:** Handles concurrent users well

---

## Documentation Updates

### Updated Requirements

**Line 1155 in Reward.md:**
- ❌ ~~"Single Promo Code Redemption: Rewards with promo codes can only be redeemed one at a time"~~
- ✅ "Multi-Quantity Redemption: Rewards with promo codes create individual records per unit for audit trail"

### API Documentation

**Updated examples:**
```javascript
// Multi-quantity redemption
const { data, error } = await supabase.rpc('redeem_reward_with_points', {
  p_reward_id: 'reward-uuid',
  p_quantity: 5  // ✅ Supported for both promo and non-promo rewards
});

// Check response
if (data.success) {
  console.log(`Redeemed ${data.data.total_quantity} units`);
  console.log(`Created ${data.data.records_created} records`);
  
  if (data.data.has_promo_codes) {
    data.data.redemptions.forEach(r => {
      console.log(`Code ${r.unit_number}: ${r.promo_code}`);
    });
  }
}
```

---

## Monitoring

### Metrics to Track

1. **Promo Code Pool Depletion Rate**
   - Alert when pools drop below threshold
   - Auto-replenish if possible

2. **Concurrent Redemption Conflicts**
   - Count "Concurrent redemption conflict" errors
   - If frequent, consider increasing pool size

3. **Multi-Quantity Usage**
   - Track average qty per redemption
   - Identify popular rewards for code pool planning

4. **Pattern Distribution**
   - % using Pattern A (no codes) vs Pattern B (with codes)
   - Optimize based on usage

---

## Next Steps

### Recommended Enhancements

1. **Auto-Refill Promo Codes**
   - Alert when pool < 100 codes
   - Trigger bulk import workflow

2. **Batch Cancellation** (Future)
   - Cancel all related records for multi-qty redemptions
   - Requires grouping field (transaction_id)

3. **Frontend Updates**
   - Display multi-code redemptions in expandable card
   - Show "5x Coffee Voucher (5 codes)"
   - Click to expand and see individual codes

---

**Status:** ✅ Production Ready  
**Deployment:** Immediate (backward compatible)  
**Risk:** Low (no breaking changes)  
**Testing:** Recommended before heavy use
