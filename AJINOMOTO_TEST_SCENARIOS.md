# Ajinomoto MSG Test Scenarios

## Earn Factor Rule Discovered:

**Product:** Ajinomoto MSG 250G  
**SKU ID:** `358df89b-9970-4810-a8a4-1f54c5da8711`  
**SKU Code:** `AJI-MSG-001-250G`  
**UOM:** BAG (primary), CARTON (secondary)

**Earning Rule:**
- **Type:** 5x multiplier on points
- **Threshold:** Amount-based (line_total)
- **Min:** 100 THB
- **Max:** 1,000 THB
- **Mode:** Excess only (5x applies only to amount above 100 THB)

---

## Test Scenarios (10 Cases)

### ✅ Scenario 1: Above Threshold (Should Get 5x on Excess)
**Transaction:** AJI-MATCH-01  
**Line Total:** 250 THB  
**Expected:**
- Base: 100 THB → X points (base rate)
- Bonus: 150 THB × 5 → 5X points
- Total: Base + Bonus points

### ✅ Scenario 2: Below Threshold (Base Rate Only)
**Transaction:** AJI-BELOW-01  
**Line Total:** 50 THB  
**Expected:**
- 50 THB → Base rate only
- No multiplier (below 100 THB threshold)

### ✅ Scenario 3: Above Cap (Should Cap at 1000 THB)
**Transaction:** AJI-ABOVE-CAP-01  
**Line Total:** 2,000 THB  
**Expected:**
- Base: 100 THB → Base rate
- Bonus: 900 THB × 5 (capped at 1000-100)
- Remaining 1,000 THB → Base rate (above cap)

### ✅ Scenario 4: Exactly at Minimum (No Excess)
**Transaction:** AJI-EXACT-MIN-01  
**Line Total:** 100 THB  
**Expected:**
- 100 THB → Base rate only
- No excess to multiply (0 THB above threshold)

### ✅ Scenario 5: Different SKU (1KG variant)
**Transaction:** AJI-1KG-01  
**SKU ID:** `82f7c1b5-b7d5-4661-86a4-7e348b732336`  
**Line Total:** 500 THB  
**Expected:**
- Check if rule applies to this SKU
- If not: Base rate only
- If yes: 400 THB × 5 bonus

### ✅ Scenario 6: Non-Ajinomoto Product
**Transaction:** NON-AJI-01  
**SKU ID:** `37158166-383d-4456-8cf0-e367e5d69d5e` (T-shirt)  
**Line Total:** 500 THB  
**Expected:**
- Base rate only (no Ajinomoto multiplier)

### ✅ Scenario 7: Valid Phone Number
**Transaction:** PHONE-VALID-01  
**Phone:** +66863107599 (exists)  
**Line Total:** 300 THB  
**Expected:**
- ✅ Phone resolves to user_id
- ✅ Import succeeds
- ✅ Gets 5x on 200 THB excess

### ❌ Scenario 8: Invalid Phone Number
**Transaction:** PHONE-INVALID-01  
**Phone:** +66999999999 (doesn't exist)  
**Expected:**
- ❌ **Import FAILS** at validation
- ❌ Error: "Invalid user_ids found"
- ❌ No data inserted

### ❌ Scenario 9: Invalid User ID
**Transaction:** USER-INVALID-01  
**User ID:** 00000000-0000-0000-0000-000000000000  
**Expected:**
- ❌ **Import FAILS** at validation
- ❌ Error: "Invalid user_ids found"
- ❌ No data inserted

### ❌ Scenario 10: Invalid SKU ID
**Transaction:** SKU-INVALID-01  
**SKU ID:** 00000000-0000-0000-0000-000000000000  
**Expected:**
- ❌ **Import FAILS** at validation
- ❌ Error: "Invalid sku_ids found"
- ❌ No data inserted

---

## Run Test:

```bash
curl -X POST https://crm-batch-upload.onrender.com/api/import/purchases \
  -F "file=@test-ajinomoto-scenarios.csv" \
  -F "merchant_id=09b45463-3812-42fb-9c7f-9d43b6fd3eb9" \
  -F "batch_name=Ajinomoto Test Scenarios"
```

**Expected Result:**
- ❌ Import should **FAIL** because scenarios 8, 9, 10 have invalid data
- ❌ Atomic protection: NO scenarios will be imported (all-or-nothing)

---

## Valid-Only Test:

To test successful scenarios only, create separate CSV without scenarios 8-10:

```bash
# Will create valid-only CSV
```

---

## Verification Queries:

### Check Currency Awarded:
```sql
SELECT 
  pl.transaction_number, 
  pl.final_amount,
  wl.currency, 
  wl.component,
  wl.amount 
FROM wallet_ledger wl 
JOIN purchase_ledger pl ON wl.source_id::uuid = pl.id 
WHERE pl.transaction_number LIKE 'AJI-%' 
ORDER BY pl.transaction_number, wl.component;
```

### Check Base vs Bonus Breakdown:
```sql
SELECT 
  pl.transaction_number,
  SUM(CASE WHEN wl.component = 'base' THEN wl.amount ELSE 0 END) as base_points,
  SUM(CASE WHEN wl.component = 'bonus' THEN wl.amount ELSE 0 END) as bonus_points
FROM wallet_ledger wl 
JOIN purchase_ledger pl ON wl.source_id::uuid = pl.id 
WHERE pl.transaction_number LIKE 'AJI-%' AND wl.currency = 'points'
GROUP BY pl.transaction_number;
```

---

*File ready: `/Users/rangwan/Documents/Supabase CRM/test-ajinomoto-scenarios.csv`*
