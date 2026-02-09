# YUMYUM Operator Test Guide

## 📋 Your Configuration:

**Earn Factor:** 5x multiplier on points

**Conditions:**
1. **Brand:** YUMYUM
   - operator: AND
   - threshold_unit: quantity_primary
   - min_threshold: 1000
   
2. **Persona:** ผู้บริโ (or Cooperative in test data)

**Both conditions must be satisfied!**

---

## 🧪 Test Scenarios Created:

### Scenario 1: YUM-PASS-1 ✅ SHOULD GET 5x

```
User: +66966564526 (has Cooperative persona)
Product: YUMYUM SKU 110050330
Quantity: 1200 units
Line total: $12,000

Checks:
✅ Persona matches (Cooperative)
✅ Brand matches (YUMYUM)
✅ Quantity: 1200 ≥ 1000

Expected:
- Base: ~480 points (12000 ÷ 25 = 480 at 4% rate)
- Bonus: 480 × 5 = 2400 points
- Total: ~2880 points
```

---

### Scenario 2: YUM-FAIL-QTY ❌ BASE ONLY

```
User: Same (Cooperative persona)
Product: YUMYUM SKU 110050330
Quantity: 900 units
Line total: $9,000

Checks:
✅ Persona matches
✅ Brand matches
❌ Quantity: 900 < 1000 (FAIL)

Expected:
- Base: ~360 points
- Bonus: 0 (below threshold)
- Total: ~360 points
```

---

### Scenario 3: YUM-MULTI-PASS ✅ OPERATOR=AND AGGREGATE

```
User: Same
Products: 
- YUMYUM SKU 110050330: 600 units ($6,000)
- YUMYUM SKU 110050326: 500 units ($5,000)
Total: 1100 units, $11,000

Checks (operator=AND with aggregate):
✅ Persona matches
✅ Brand matches (YUMYUM in all items)
✅ Aggregate: 600 + 500 = 1100 ≥ 1000

Expected:
- Both line items get 5x multiplier!
- Base: ~440 points total
- Bonus: 440 × 5 = 2200 points
- Total: ~2640 points
```

---

### Scenario 4: YUM-MULTI-FAIL ❌ BELOW AGGREGATE

```
User: Same
Products:
- YUMYUM SKU 110050330: 500 units ($5,000)
- YUMYUM SKU 110050370: 400 units ($4,000)
Total: 900 units, $9,000

Checks (operator=AND with aggregate):
✅ Persona matches
✅ Brand matches
❌ Aggregate: 500 + 400 = 900 < 1000 (FAIL)

Expected:
- Base: ~360 points
- Bonus: 0 (below aggregate threshold)
- Total: ~360 points
```

---

## 🚀 Run Test:

```bash
curl -X POST https://crm-batch-upload.onrender.com/api/import/purchases \
  -F "file=@test-yumyum-operator.csv" \
  -F "merchant_id=09b45463-3812-42fb-9c7f-9d43b6fd3eb9" \
  -F "batch_name=YUMYUM Operator Test"
```

---

## 📊 Verification Query:

After CDC processes (wait 2 minutes):

```sql
SELECT 
  pl.transaction_number,
  pl.final_amount,
  SUM(pil.quantity) as total_qty,
  SUM(CASE WHEN wl.component = 'base' AND wl.currency = 'points' THEN wl.amount ELSE 0 END) as base_points,
  SUM(CASE WHEN wl.component = 'bonus' AND wl.currency = 'points' THEN wl.amount ELSE 0 END) as bonus_points,
  SUM(CASE WHEN wl.currency = 'points' THEN wl.amount ELSE 0 END) as total_points
FROM purchase_ledger pl
JOIN purchase_items_ledger pil ON pl.id = pil.transaction_id
LEFT JOIN wallet_ledger wl ON wl.source_id::uuid = pl.id
WHERE pl.transaction_number LIKE 'YUM-%'
GROUP BY pl.transaction_number, pl.final_amount
ORDER BY pl.transaction_number;
```

---

## ✅ Expected Results Summary:

| Transaction | Total Qty | Meets Threshold? | Gets 5x Bonus? |
|------------|-----------|------------------|----------------|
| YUM-PASS-1 | 1200 | ✅ YES (≥1000) | ✅ YES |
| YUM-FAIL-QTY | 900 | ❌ NO (<1000) | ❌ NO (base only) |
| YUM-MULTI-PASS | 1100 | ✅ YES (aggregate) | ✅ YES (both items) |
| YUM-MULTI-FAIL | 900 | ❌ NO (aggregate) | ❌ NO (base only) |

---

**File ready:** `/Users/rangwan/Documents/Supabase CRM/test-yumyum-operator.csv`

**Test the AND operator with aggregate threshold!** 🎯
