# Earn Conditions Operator Field - Enhancement Proposal

## 🎯 Problem Statement

Current system with multiple `entity_ids` always uses OR logic with per-line-item threshold checking. This doesn't support:

1. **Combined threshold:** "Buy 1000 total across brands A + B"
2. **AND logic:** "Must buy BOTH brands in same transaction"

---

## 💡 Proposed Solution: Add `operator` Field

```sql
ALTER TABLE earn_conditions
ADD COLUMN operator TEXT DEFAULT 'OR' 
  CHECK (operator IN ('OR', 'AND'));

COMMENT ON COLUMN earn_conditions.operator IS 
  'How to evaluate multiple entity_ids: OR (any qualifies) or AND (all required, aggregate threshold)';
```

---

## 📊 How It Would Work:

### Operator: OR (Default - Current Behavior)

**Without Threshold:**
```
entity_ids = [POWDER COFFEE, ROSDEE MENU]
operator = 'OR'
threshold = None

Purchase:
- Buy POWDER only → ✅ Qualifies
- Buy ROSDEE only → ✅ Qualifies
- Buy both → ✅ Both qualify
- Buy neither → ❌ No bonus
```

**With Threshold:**
```
entity_ids = [POWDER COFFEE, ROSDEE MENU]
operator = 'OR'
threshold_unit = quantity_primary
min_threshold = 1000

Purchase: 500 POWDER + 500 ROSDEE

Evaluation (per-line):
- POWDER line: 500 < 1000 → ❌
- ROSDEE line: 500 < 1000 → ❌
Result: No bonus
```

---

### Operator: AND (New Behavior)

**Without Threshold:**
```
entity_ids = [POWDER COFFEE, ROSDEE MENU]
operator = 'AND'
threshold = None

Purchase:
- Buy POWDER only → ❌ Need both!
- Buy ROSDEE only → ❌ Need both!
- Buy both → ✅ Qualifies (both present)
- Buy neither → ❌ No bonus
```

**With Threshold (AGGREGATE):**
```
entity_ids = [POWDER COFFEE, ROSDEE MENU]
operator = 'AND'
threshold_unit = quantity_primary
min_threshold = 1000

Purchase: 500 POWDER + 500 ROSDEE

Evaluation (aggregated):
- Check presence: POWDER ✅ + ROSDEE ✅ → Both present
- Aggregate quantity: 500 + 500 = 1000
- Threshold check: 1000 ≥ 1000 → ✅ PASS
Result: ✅ BOTH lines get multiplier!
```

---

## 🎯 Use Cases:

### Use Case 1: "Buy ANY of these brands"
```
operator = 'OR'
threshold = None
→ Current behavior
→ Any brand qualifies
```

### Use Case 2: "Buy 1000+ of ANY single brand"
```
operator = 'OR'
threshold = 1000
→ Current behavior
→ Each brand checked individually
```

### Use Case 3: "Buy BOTH brands together"
```
operator = 'AND'
threshold = None
→ NEW behavior
→ Both must be in transaction
```

### Use Case 4: "Buy 1000+ total across these brands" ⭐ **Your Request**
```
operator = 'AND'
threshold = 1000
→ NEW behavior
→ Quantities aggregated, then checked
```

---

## 📐 Calculation Logic:

### operator = 'OR' (Per-Line)

```javascript
for each line_item in purchase {
  if (line_item.brand in entity_ids) {
    if (no_threshold || line_item.quantity >= threshold) {
      apply_multiplier_to_this_line()
    }
  }
}
```

### operator = 'AND' (Aggregate)

```javascript
// Step 1: Check all entities present
matching_lines = purchase.items.filter(item => entity_ids.includes(item.brand))
required_entities_present = entity_ids.every(entity => 
  matching_lines.some(line => line.brand === entity)
)

if (!required_entities_present) {
  return; // Don't apply multiplier at all
}

// Step 2: Aggregate quantities
total_quantity = matching_lines.reduce((sum, line) => sum + line.quantity, 0)

// Step 3: Check threshold on aggregate
if (no_threshold || total_quantity >= threshold) {
  // Apply multiplier to ALL matching lines
  matching_lines.forEach(line => apply_multiplier(line))
}
```

---

## 🧪 Test Matrix:

| operator | Threshold | Purchase | Result |
|----------|-----------|----------|--------|
| OR | None | 100 POWDER | ✅ POWDER gets bonus |
| OR | 1000 | 500 POWDER + 500 ROSDEE | ❌ Neither qualifies |
| AND | None | 500 POWDER only | ❌ Need both brands |
| AND | None | 500 POWDER + 500 ROSDEE | ✅ Both get bonus |
| AND | 1000 | 500 POWDER + 500 ROSDEE | ✅ Both get bonus (agg=1000) |
| AND | 1000 | 600 POWDER + 300 ROSDEE | ❌ Aggregate 900 < 1000 |
| AND | 1000 | 600 POWDER only | ❌ Missing ROSDEE |

---

## 🔧 Implementation Impact:

### Database:
```sql
-- Add column
ALTER TABLE earn_conditions
ADD COLUMN operator TEXT DEFAULT 'OR' 
  CHECK (operator IN ('OR', 'AND'));

-- Backfill existing records
UPDATE earn_conditions SET operator = 'OR'; -- Maintain current behavior
```

### Currency Calculation Function:
- Update `evaluate_earn_conditions()` to handle operator
- Add aggregation logic for operator='AND'
- Maintain backward compatibility (default='OR')

### Frontend (WeWeb):
- Add operator dropdown to condition form
- Options: "ANY (OR)" vs "ALL (AND)"
- Show when `entity_ids.length > 1`

---

## ✅ Recommended Schema:

```sql
ALTER TABLE earn_conditions
ADD COLUMN operator TEXT DEFAULT 'OR' 
  CHECK (operator IN ('OR', 'AND'));

COMMENT ON COLUMN earn_conditions.operator IS 
  'OR: Any entity qualifies (per-line threshold). AND: All entities required (aggregate threshold)';
```

**Default='OR' preserves current behavior for all existing configurations!** ✅

---

## 🎯 For Your Use Case:

**Config:**
```
entity_ids = [POWDER COFFEE, ROSDEE MENU]
operator = 'AND'
threshold_unit = quantity_primary
min_threshold = 1000
```

**Result:**
- 500 POWDER + 500 ROSDEE → ✅ Both get bonus (aggregate 1000)
- 1200 POWDER + 0 ROSDEE → ❌ No bonus (missing ROSDEE)
- 1200 POWDER + 100 ROSDEE → ✅ Both get bonus (aggregate 1300)

**Want me to document this as a feature request with implementation details?** 🚀
