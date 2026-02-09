# Earn Conditions Operator Field - Implementation Plan

## 🎯 Goal

Add `operator` field to `earn_conditions` table to support:
1. **OR logic** (current): Any entity qualifies, per-line threshold
2. **AND logic** (new): All entities required, aggregate threshold

---

## 📋 Implementation Checklist

- [ ] Database schema migration
- [ ] Update currency calculation function
- [ ] Update frontend UI
- [ ] Create test scenarios
- [ ] Document new behavior
- [ ] Backward compatibility verification

---

## Part 1: Database Schema Changes

### 1.1 Add Operator Column

**File:** `sql/migrations/add_operator_to_earn_conditions.sql`

```sql
-- Add operator column with default
ALTER TABLE earn_conditions
ADD COLUMN IF NOT EXISTS operator TEXT DEFAULT 'OR' 
  CHECK (operator IN ('OR', 'AND'));

-- Add index for query optimization
CREATE INDEX IF NOT EXISTS idx_earn_conditions_operator 
  ON earn_conditions(operator) 
  WHERE operator = 'AND';

-- Add comment
COMMENT ON COLUMN earn_conditions.operator IS 
  'Logic for multiple entity_ids: OR (any entity qualifies, per-line threshold) or AND (all entities required, aggregate threshold)';

-- Backfill existing records to maintain current behavior
UPDATE earn_conditions 
SET operator = 'OR' 
WHERE operator IS NULL;
```

**Impact:**
- ✅ Backward compatible (default='OR' preserves current behavior)
- ✅ All existing conditions continue working unchanged
- ✅ New conditions can use AND logic

---

## Part 2: Currency Calculation Function Updates

### 2.1 Functions to Modify

**Primary function:**
- `evaluate_earn_conditions()` - Main condition evaluation logic

**Related functions:**
- `calc_currency_for_source()` - Calls evaluate_earn_conditions
- `calc_currency_for_transaction()` - Transaction-level calculation

### 2.2 Logic Changes in `evaluate_earn_conditions()`

**Current logic (OR, per-line):**
```sql
-- Pseudo-code
FOR each line_item IN purchase_items {
  IF line_item.entity_id IN condition.entity_ids {
    IF no_threshold OR line_item.quantity >= min_threshold {
      -- Apply multiplier to this line
    }
  }
}
```

**New logic (with operator support):**
```sql
-- Pseudo-code
IF condition.operator = 'OR' THEN
  -- Current behavior (per-line)
  FOR each line_item IN purchase_items {
    IF line_item.entity_id IN condition.entity_ids {
      IF no_threshold OR line_item.quantity >= min_threshold {
        -- Apply multiplier to this line
      }
    }
  }
  
ELSIF condition.operator = 'AND' THEN
  -- New behavior (aggregate)
  
  -- Step 1: Find all matching line items
  matching_items = SELECT * FROM purchase_items 
                   WHERE entity_id IN condition.entity_ids
  
  -- Step 2: Check all entities present (AND requirement)
  entities_found = ARRAY_AGG(DISTINCT matching_items.entity_id)
  all_present = condition.entity_ids <@ entities_found  -- All required entities present?
  
  IF NOT all_present THEN
    RETURN;  -- Don't apply multiplier
  END IF;
  
  -- Step 3: Aggregate quantity/amount across all matching items
  IF condition.threshold_unit = 'quantity_primary' THEN
    total_value = SUM(matching_items.quantity)
  ELSIF condition.threshold_unit = 'quantity_secondary' THEN
    total_value = SUM(matching_items.quantity_secondary)
  ELSIF condition.threshold_unit = 'amount' THEN
    total_value = SUM(matching_items.line_total)
  ELSE
    total_value = 0  -- No threshold
  END IF;
  
  -- Step 4: Check threshold on aggregate
  IF no_threshold OR total_value >= min_threshold THEN
    -- Apply multiplier to ALL matching line items
    FOR each item IN matching_items {
      -- Apply multiplier
    }
  END IF;
  
END IF;
```

### 2.3 Detailed Implementation

**Function signature (no change):**
```sql
CREATE OR REPLACE FUNCTION evaluate_earn_conditions(
  p_purchase_id UUID,
  p_merchant_id UUID,
  p_user_id UUID
) RETURNS JSONB
```

**Add new helper function:**
```sql
CREATE OR REPLACE FUNCTION check_and_condition(
  p_condition_id UUID,
  p_purchase_items JSONB,
  p_threshold_unit TEXT,
  p_min_threshold NUMERIC,
  p_max_threshold NUMERIC,
  p_apply_to_excess_only BOOLEAN
) RETURNS JSONB AS $$
DECLARE
  v_matching_items JSONB;
  v_aggregate_value NUMERIC;
  v_required_entities UUID[];
  v_found_entities UUID[];
BEGIN
  -- Get required entities from condition
  SELECT entity_ids INTO v_required_entities
  FROM earn_conditions
  WHERE id = p_condition_id;
  
  -- Find matching items
  v_matching_items = (
    SELECT jsonb_agg(item)
    FROM jsonb_array_elements(p_purchase_items) AS item
    WHERE (item->>'entity_id')::UUID = ANY(v_required_entities)
  );
  
  -- Check if all required entities are present
  SELECT ARRAY_AGG(DISTINCT (item->>'entity_id')::UUID)
  INTO v_found_entities
  FROM jsonb_array_elements(v_matching_items) AS item;
  
  IF NOT (v_required_entities <@ v_found_entities) THEN
    -- Not all required entities present
    RETURN '{"qualified": false, "reason": "missing_entities"}'::jsonb;
  END IF;
  
  -- Aggregate quantities
  IF p_threshold_unit = 'quantity_primary' THEN
    SELECT SUM((item->>'quantity')::NUMERIC)
    INTO v_aggregate_value
    FROM jsonb_array_elements(v_matching_items) AS item;
  ELSIF p_threshold_unit = 'quantity_secondary' THEN
    SELECT SUM((item->>'quantity_secondary')::NUMERIC)
    INTO v_aggregate_value
    FROM jsonb_array_elements(v_matching_items) AS item;
  ELSIF p_threshold_unit = 'amount' THEN
    SELECT SUM((item->>'line_total')::NUMERIC)
    INTO v_aggregate_value
    FROM jsonb_array_elements(v_matching_items) AS item;
  END IF;
  
  -- Check threshold
  IF p_threshold_unit IS NULL OR 
     v_aggregate_value >= p_min_threshold THEN
    RETURN jsonb_build_object(
      'qualified', true,
      'matching_items', v_matching_items,
      'aggregate_value', v_aggregate_value
    );
  ELSE
    RETURN jsonb_build_object(
      'qualified', false,
      'reason', 'below_threshold',
      'aggregate_value', v_aggregate_value,
      'required', p_min_threshold
    );
  END IF;
END;
$$ LANGUAGE plpgsql;
```

---

## Part 3: Frontend UI Changes

### 3.1 Add Operator Selector

**Location:** Earn Condition form

**UI Component:**
```
Operator: [Dropdown]
├── ANY (OR) - Default
│   └── Description: "Applies if purchase contains ANY of the selected entities"
└── ALL (AND)
    └── Description: "Applies only if purchase contains ALL selected entities (aggregates quantities)"
```

**Visibility:**
```javascript
// Show operator dropdown only when multiple entities selected
context.item.data?.['entity_ids']?.length > 1
```

**Default value:**
```javascript
'OR'  // Maintains current behavior
```

### 3.2 Update Threshold Description

**Current:**
```
"Minimum quantity/amount required per line item"
```

**New (dynamic based on operator):**
```javascript
operator === 'OR' 
  ? "Minimum quantity/amount required per line item"
  : "Minimum total quantity/amount across all selected entities combined"
```

### 3.3 UI Warning Messages

**When operator='AND':**
```
⚠️ AND mode requires ALL entities present in transaction
Example: With [A, B, C] - customer must buy A AND B AND C
```

**When operator='AND' with threshold:**
```
✅ Quantities will be aggregated across all matching items
Example: 500 of A + 600 of B = 1100 total (checked against threshold)
```

---

## Part 4: Test Scenarios

### 4.1 Test Data Requirements

**Brands:**
- POWDER COFFEE (id: get from database)
- ROSDEE MENU (id: get from database)

**Test user:**
- User with appropriate persona

### 4.2 Test CSV Files

**Test 1: OR with threshold (current behavior)**
```csv
transaction_number,user_phone,sku_code,quantity_primary,line_total
OR-TEST-1,+66966564526,POWDER-COFFEE-SKU,1200,12000
OR-TEST-2,+66966564526,POWDER-COFFEE-SKU,500,5000
OR-TEST-3,+66966564526,ROSDEE-SKU,500,5000
```

Expected:
- OR-TEST-1: POWDER 1200 ≥ 1000 → ✅ Bonus
- OR-TEST-2: POWDER 500 < 1000 → ❌ No bonus
- OR-TEST-3: ROSDEE 500 < 1000 → ❌ No bonus

**Test 2: AND without threshold (new behavior)**
```csv
transaction_number,user_phone,sku_code,quantity_primary,line_total
AND-TEST-1,+66966564526,POWDER-COFFEE-SKU,100,1000
AND-TEST-1,+66966564526,ROSDEE-SKU,100,1000
AND-TEST-2,+66966564526,POWDER-COFFEE-SKU,100,1000
```

Expected:
- AND-TEST-1: Has POWDER ✅ + ROSDEE ✅ → Both get bonus
- AND-TEST-2: Has POWDER ✅ but missing ROSDEE ❌ → No bonus

**Test 3: AND with aggregate threshold (new behavior)**
```csv
transaction_number,user_phone,sku_code,quantity_primary,line_total
AND-AGG-1,+66966564526,POWDER-COFFEE-SKU,500,5000
AND-AGG-1,+66966564526,ROSDEE-SKU,500,5000
AND-AGG-2,+66966564526,POWDER-COFFEE-SKU,600,6000
AND-AGG-2,+66966564526,ROSDEE-SKU,300,3000
```

Expected (threshold=1000):
- AND-AGG-1: 500+500=1000 ≥ 1000 → ✅ Both get bonus
- AND-AGG-2: 600+300=900 < 1000 → ❌ No bonus (below aggregate)

---

## Part 5: Verification Queries

### 5.1 Check Configuration
```sql
SELECT 
  ec.entity,
  ec.entity_ids,
  ec.operator,
  ec.threshold_unit,
  ec.min_threshold,
  ef.earn_factor_amount as multiplier
FROM earn_conditions ec
JOIN earn_factor ef ON ec.group_id = ef.earn_conditions_group_id
WHERE ec.merchant_id = 'your-merchant-id'
AND ec.operator IS NOT NULL;
```

### 5.2 Verify Currency Awards
```sql
-- Check if AND logic worked (all entities present + aggregate)
SELECT 
  pl.transaction_number,
  STRING_AGG(DISTINCT psm.sku_code, ', ') as skus_purchased,
  SUM(pil.quantity) as total_quantity,
  SUM(CASE WHEN wl.component = 'base' THEN wl.amount ELSE 0 END) as base_points,
  SUM(CASE WHEN wl.component = 'bonus' THEN wl.amount ELSE 0 END) as bonus_points
FROM purchase_ledger pl
JOIN purchase_items_ledger pil ON pl.id = pil.transaction_id
JOIN product_sku_master psm ON pil.sku_id = psm.id
LEFT JOIN wallet_ledger wl ON wl.source_id::uuid = pl.id
WHERE pl.transaction_number LIKE 'AND-AGG%'
GROUP BY pl.transaction_number;
```

---

## Part 6: Rollback Plan

### 6.1 Rollback Migration

**File:** `sql/migrations/rollback_operator_field.sql`

```sql
-- Remove operator column
ALTER TABLE earn_conditions
DROP COLUMN IF EXISTS operator;

-- Drop helper function
DROP FUNCTION IF EXISTS check_and_condition(UUID, JSONB, TEXT, NUMERIC, NUMERIC, BOOLEAN);

-- Drop index
DROP INDEX IF EXISTS idx_earn_conditions_operator;
```

### 6.2 Data Preservation

**Before migration:**
```sql
-- Backup existing conditions
CREATE TABLE earn_conditions_backup AS
SELECT * FROM earn_conditions;

-- Verify count
SELECT COUNT(*) FROM earn_conditions;
SELECT COUNT(*) FROM earn_conditions_backup;
```

---

## Part 7: Backward Compatibility

### 7.1 Existing Configurations

**All existing conditions will:**
- ✅ Get `operator = 'OR'` by default
- ✅ Behave exactly as before
- ✅ No changes to currency calculation

### 7.2 Migration Strategy

**Phase 1: Schema (Safe)**
- Add column with default='OR'
- Backfill all existing records
- No functional changes yet

**Phase 2: Function Update (Deploy)**
- Update evaluate_earn_conditions()
- Add AND logic branch
- Test with new conditions only

**Phase 3: UI Update**
- Add operator dropdown
- Default to 'OR' for new conditions
- Document new feature

**Phase 4: Testing**
- Create test conditions with AND operator
- Verify aggregate threshold works
- Verify presence check works

---

## Part 8: Implementation Steps

### Step 1: Database Migration (5 minutes)

```bash
# Execute migration
# Via Supabase SQL Editor or MCP
```

**Verification:**
```sql
-- Check column exists
SELECT column_name, column_default 
FROM information_schema.columns 
WHERE table_name = 'earn_conditions' 
AND column_name = 'operator';

-- Check all records have default
SELECT operator, COUNT(*) 
FROM earn_conditions 
GROUP BY operator;
```

### Step 2: Update Currency Function (30 minutes)

**Files to modify:**
- `evaluate_earn_conditions()` - Add operator handling
- May need to update `calc_currency_for_source()` if logic changes

**Testing:**
```sql
-- Test OR behavior (should match current)
SELECT * FROM evaluate_earn_conditions(
  'test-purchase-id',
  'merchant-id',
  'user-id'
);

-- Test AND behavior (new)
-- Create test condition with operator='AND'
-- Verify it checks presence + aggregates
```

### Step 3: Frontend UI Updates (20 minutes)

**Add to earn condition form:**

1. **Operator dropdown**
   - Show when: `entity_ids.length > 1`
   - Options: ['OR', 'AND']
   - Default: 'OR'

2. **Threshold description (dynamic)**
   ```javascript
   operator === 'OR' 
     ? "Per line item threshold"
     : "Aggregate threshold (combined)"
   ```

3. **Help text**
   - OR: "Applies if ANY selected entity is purchased (threshold checked per item)"
   - AND: "Applies only if ALL selected entities are purchased (threshold checked on total)"

### Step 4: Testing (15 minutes)

**Test matrix:**

| Config | Purchase | Expected | Pass? |
|--------|----------|----------|-------|
| OR, threshold=1000 | 1200 POWDER | Bonus | [ ] |
| OR, threshold=1000 | 500 POWDER + 500 ROSDEE | No bonus | [ ] |
| AND, no threshold | POWDER only | No bonus | [ ] |
| AND, no threshold | POWDER + ROSDEE | Bonus both | [ ] |
| AND, threshold=1000 | 500 POWDER + 500 ROSDEE | Bonus both | [ ] |
| AND, threshold=1000 | 600 POWDER + 300 ROSDEE | No bonus | [ ] |

---

## Part 9: Edge Cases & Considerations

### 9.1 Edge Cases

**Case 1: AND with one entity_id**
```
entity_ids = [POWDER COFFEE]  (only one)
operator = 'AND'

→ Should behave same as OR (only one entity to check)
```

**Case 2: AND with missing entity**
```
entity_ids = [A, B, C]
operator = 'AND'
Purchase: Has A + B, missing C

→ No multiplier (not all present)
```

**Case 3: AND with partial threshold**
```
entity_ids = [A, B]
operator = 'AND'
threshold = 1000
Purchase: 1200 A + 0 B

→ No multiplier (B missing)
```

**Case 4: Max threshold with AND**
```
entity_ids = [A, B]
operator = 'AND'
min = 1000, max = 5000
Purchase: 3000 A + 3000 B = 6000 total

→ Cap at 5000 for bonus calculation
```

### 9.2 apply_to_excess_only with AND

**Question:** How does excess mode work with AND operator?

**Answer:**
```
operator = 'AND'
threshold = 1000
apply_to_excess_only = true
Purchase: 500 A + 700 B = 1200 total

Calculation:
- Base rate on first 1000 (distributed proportionally across A + B)
- Multiplier on 200 excess (distributed proportionally)

A gets: Base(~417) + Bonus(~83 × multiplier)
B gets: Base(~583) + Bonus(~117 × multiplier)
```

**Recommendation:** Document this behavior clearly!

---

## Part 10: Documentation Updates

### 10.1 Update Currency.md

**Add section:**
- "Operator Field: OR vs AND Logic"
- Examples with screenshots
- Test scenarios

### 10.2 Update Admin Guide

**Add:**
- When to use OR vs AND
- Common use cases
- Troubleshooting

### 10.3 Update Bulk Import Guide

**Mention:**
- Bulk imports work with both operators
- Test CSVs for each operator type

---

## Part 11: Performance Considerations

### 11.1 Query Performance

**OR operator (current):**
- ✅ Fast - simple per-line check
- ✅ No aggregation needed
- ✅ Scales well with many line items

**AND operator (new):**
- ⚠️ Slower - requires aggregation
- ⚠️ Needs to check all entities present
- ⚠️ More complex query

**Optimization:**
- Add index on operator for faster filtering
- Cache entity presence check
- Consider materialized view for large merchants

### 11.2 Estimated Impact

**For typical purchase (1-10 line items):**
- OR: ~10ms query time
- AND: ~20ms query time
- **Acceptable impact** ✅

**For bulk import (1000s of purchases):**
- May add 10-30 seconds to processing
- Still acceptable for async processing ✅

---

## Part 12: Timeline & Resources

### Estimated Time:

| Phase | Time | Owner |
|-------|------|-------|
| Schema migration | 5 min | DBA/Backend |
| Function update | 2 hours | Backend engineer |
| Frontend UI | 1 hour | Frontend engineer |
| Testing | 1 hour | QA + Backend |
| Documentation | 30 min | Tech writer |
| **Total** | **~5 hours** | Team |

### Prerequisites:

- [ ] Database write access
- [ ] Supabase function deploy access
- [ ] Frontend code access
- [ ] Test merchant account

---

## Part 13: Success Criteria

**Schema:**
- ✅ Column added with default
- ✅ All existing records backfilled
- ✅ Check constraint working

**Function:**
- ✅ OR logic works (same as before)
- ✅ AND logic works (new behavior)
- ✅ Aggregate threshold calculates correctly
- ✅ Presence check works
- ✅ No performance degradation

**Frontend:**
- ✅ Operator dropdown shows when needed
- ✅ Help text explains difference
- ✅ Saves correctly to database

**Testing:**
- ✅ All 6 test scenarios pass
- ✅ Backward compatibility verified
- ✅ Bulk import works with both operators

---

## Part 14: Risks & Mitigation

| Risk | Impact | Mitigation |
|------|--------|------------|
| Breaking existing configs | High | Default='OR' preserves behavior |
| Complex aggregation logic | Medium | Extensive testing + helper function |
| UI confusion | Medium | Clear help text + examples |
| Performance degradation | Low | Add index + monitor queries |
| Migration failure | Low | Backup table + rollback script |

---

## ✅ Ready to Implement?

**This plan covers:**
- ✅ Database schema
- ✅ Function logic  
- ✅ Frontend UI
- ✅ Testing strategy
- ✅ Backward compatibility
- ✅ Rollback plan

**Estimated effort: 5 hours**

**Want me to start with the database migration?** 🚀
