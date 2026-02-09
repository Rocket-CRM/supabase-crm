# Earn Factor Configuration Guide

## 🏗️ System Architecture

```
earn_factor_group (Container)
  ├── stackable: true/false (Can multipliers combine?)
  ├── window_start/end (Validity period)
  └── Contains multiple earn_factors
      │
      ├── earn_factor #1 (3x Brand A)
      │   ├── earn_factor_type: "multiplier"
      │   ├── earn_factor_amount: 3
      │   ├── target_currency: "points"
      │   └── Links to → earn_conditions_group
      │       │
      │       └── earn_conditions
      │           ├── entity: "product_brand"
      │           ├── entity_ids: [brand_a_uuid]
      │           ├── threshold_unit: "quantity_secondary"
      │           └── min_threshold: 100
      │
      ├── earn_factor #2 (8x Product B)
      │   ├── earn_factor_type: "multiplier"
      │   ├── earn_factor_amount: 8
      │   ├── target_currency: "points"
      │   └── Links to → earn_conditions_group
      │       │
      │       └── earn_conditions
      │           ├── entity: "product_product"
      │           ├── entity_ids: [product_b_uuid]
      │           ├── threshold_unit: "quantity_primary"
      │           └── min_threshold: 500
      │
      └── earn_factor #3 (Base rate)
          ├── earn_factor_type: "rate"
          ├── earn_factor_amount: 100 (100 THB = 1 point)
          └── No conditions (applies to all)
```

---

## 📋 Table Relationships

### 1. `earn_factor_group` (Container)
**Purpose:** Groups related earn factors together

| Column | Description | Example |
|--------|-------------|---------|
| `id` | UUID | Generated |
| `name` | Group name | "Product Promotions 2026" |
| `stackable` | Can multipliers combine? | true/false |
| `window_start` | Start date | 2026-01-01 |
| `window_end` | End date | 2026-12-31 |
| `merchant_id` | Merchant owner | your-merchant-id |

### 2. `earn_factor` (Earning Rule)
**Purpose:** Defines HOW MUCH currency to award

| Column | Description | Example |
|--------|-------------|---------|
| `id` | UUID | Generated |
| `earn_factor_type` | "rate" or "multiplier" | multiplier |
| `earn_factor_amount` | Rate or multiplier value | 3 (for 3x) |
| `target_currency` | "points" or "ticket" | points |
| `target_entity_id` | Ticket type (if ticket) | NULL for points |
| `earn_factor_group_id` | Links to group | FK |
| `earn_conditions_group_id` | Links to conditions | FK |
| `public` | Available to all users? | true |
| `active_status` | Is active? | true |

### 3. `earn_conditions_group` (Condition Container)
**Purpose:** Groups conditions together (AND/OR logic)

| Column | Description |
|--------|-------------|
| `id` | UUID |
| `name` | Group name |
| `merchant_id` | Merchant owner |

### 4. `earn_conditions` (Qualifying Criteria)
**Purpose:** Defines WHEN the earn factor applies

| Column | Description | Example |
|--------|-------------|---------|
| `id` | UUID | Generated |
| `group_id` | Links to conditions group | FK |
| `entity` | What to check | product_brand |
| `entity_ids` | Which brands/products | [brand_uuid] |
| `threshold_unit` | What to measure | quantity_secondary |
| `min_threshold` | Minimum value | 100 |
| `max_threshold` | Maximum cap | NULL (no cap) |
| `apply_to_excess_only` | Bonus on excess only? | true |

---

## 🎯 Your Specific Rules

### Rule 1: 3x for Brand A (Secondary UOM > 100)

```sql
-- Step 1: Create conditions group
INSERT INTO earn_conditions_group (id, name, merchant_id)
VALUES (
  gen_random_uuid(),
  'Brand A Bulk Purchase Conditions',
  'your-merchant-id'
) RETURNING id; -- Save this as conditions_group_1_id

-- Step 2: Create condition (Brand A + secondary UOM threshold)
INSERT INTO earn_conditions (
  group_id,
  entity,
  entity_ids,
  threshold_unit,
  min_threshold,
  max_threshold,
  apply_to_excess_only,
  merchant_id
) VALUES (
  'conditions_group_1_id', -- From step 1
  'product_brand',  -- Check brand
  ARRAY['brand_a_uuid']::uuid[],  -- Brand A UUID
  'quantity_secondary',  -- Check bulk UOM
  100,  -- Minimum 100 units (secondary)
  NULL,  -- No cap
  false,  -- Apply to full line (not just excess)
  'your-merchant-id'
);

-- Step 3: Create or use earn factor group
INSERT INTO earn_factor_group (id, name, stackable, merchant_id)
VALUES (
  gen_random_uuid(),
  'Product Promotions',
  false,  -- Non-stackable (best multiplier wins)
  'your-merchant-id'
) RETURNING id; -- Save as factor_group_id

-- Step 4: Create earn factor (3x multiplier)
INSERT INTO earn_factor (
  earn_factor_type,
  earn_factor_amount,
  target_currency,
  target_entity_id,
  earn_factor_group_id,
  earn_conditions_group_id,
  public,
  active_status,
  merchant_id
) VALUES (
  'multiplier',  -- Multiplier type
  3,  -- 3x
  'points',
  NULL,  -- Points are fungible
  'factor_group_id',  -- From step 3
  'conditions_group_1_id',  -- From step 1
  true,  -- Public (all users)
  true,  -- Active
  'your-merchant-id'
);
```

### Rule 2: 8x for Product B (Primary UOM > 500)

```sql
-- Step 1: Create conditions group
INSERT INTO earn_conditions_group (id, name, merchant_id)
VALUES (
  gen_random_uuid(),
  'Product B High Volume Conditions',
  'your-merchant-id'
) RETURNING id; -- Save as conditions_group_2_id

-- Step 2: Create condition (Product B + primary UOM threshold)
INSERT INTO earn_conditions (
  group_id,
  entity,
  entity_ids,
  threshold_unit,
  min_threshold,
  max_threshold,
  apply_to_excess_only,
  merchant_id
) VALUES (
  'conditions_group_2_id',
  'product_product',  -- Check product
  ARRAY['product_b_uuid']::uuid[],  -- Product B UUID
  'quantity_primary',  -- Check primary UOM
  500,  -- Minimum 500 units
  NULL,
  false,  -- Apply to full line
  'your-merchant-id'
);

-- Step 3: Create earn factor (8x multiplier)
-- Use SAME earn_factor_group_id as Rule 1 if non-stackable
INSERT INTO earn_factor (
  earn_factor_type,
  earn_factor_amount,
  target_currency,
  target_entity_id,
  earn_factor_group_id,
  earn_conditions_group_id,
  public,
  active_status,
  merchant_id
) VALUES (
  'multiplier',
  8,  -- 8x
  'points',
  NULL,
  'factor_group_id',  -- SAME group = non-stackable
  'conditions_group_2_id',
  true,
  true,
  'your-merchant-id'
);
```

---

## 🔑 Key Concepts:

### Stackable vs Non-Stackable:

**Stackable = true:**
```
Brand A: 3x + Product B: 8x = 11x total (they stack)
```

**Stackable = false (same group):**
```
Brand A: 3x OR Product B: 8x = best one wins (8x)
```

**Different groups:**
```
Group 1 (Product): 3x
Group 2 (Customer): 2x for VIP
= Can combine even if both non-stackable (different scopes)
```

### Threshold Units:

| Value | Checks | Example |
|-------|--------|---------|
| `quantity_primary` | `purchase_items_ledger.quantity` | ≥500 pieces |
| `quantity_secondary` | `purchase_items_ledger.quantity_secondary` | ≥100 tonnes |
| `amount` | `purchase_items_ledger.line_total` | ≥1000 THB |

### Apply to Excess Only:

**false (Full Line):**
```
Buy 150 units with 100 min threshold
→ 3x applies to ALL 150 units
```

**true (Excess Only):**
```
Buy 150 units with 100 min threshold
→ Base rate on first 100 units
→ 3x on the 50 excess units only
```

---

## 🧪 Test Your Configuration:

### CSV for Brand A (Secondary UOM > 100):
```csv
transaction_number,transaction_date,user_phone,final_amount,sku_code,quantity_primary,quantity_secondary,unit_price,line_total
TEST-BRAND-A-PASS,2026-02-01T10:00:00Z,+66966564526,5000.00,BRAND-A-SKU-001,500,150,10.00,5000.00
TEST-BRAND-A-FAIL,2026-02-01T10:05:00Z,+66966564526,900.00,BRAND-A-SKU-001,90,90,10.00,900.00
```
- First: 150 secondary units → **Gets 3x** ✅
- Second: 90 secondary units → **No bonus** (below 100)

### CSV for Product B (Primary UOM > 500):
```csv
transaction_number,transaction_date,user_phone,final_amount,sku_code,quantity_primary,unit_price,line_total
TEST-PRODUCT-B-PASS,2026-02-01T11:00:00Z,+66966564526,60000.00,PRODUCT-B-SKU-001,600,,100.00,60000.00
TEST-PRODUCT-B-FAIL,2026-02-01T11:05:00Z,+66966564526,40000.00,PRODUCT-B-SKU-001,400,,100.00,40000.00
```
- First: 600 primary units → **Gets 8x** ✅
- Second: 400 primary units → **No bonus** (below 500)

---

## 📊 Expected Results:

### Brand A (3x on secondary > 100):
```
quantity_secondary = 150
→ Base points on amount
→ +3x bonus points (since 150 > 100)
```

### Product B (8x on primary > 500):
```
quantity_primary = 600
→ Base points on amount
→ +8x bonus points (since 600 > 500)
```

### Both in Same Transaction:
```
If same factor group (non-stackable):
→ Only best multiplier applies (8x wins)

If different factor groups:
→ Both apply (3x on Brand A item + 8x on Product B item)
```

---

## 🔍 Verify Configuration:

```sql
-- Check your earn factors
SELECT 
  ef.earn_factor_type,
  ef.earn_factor_amount,
  ec.entity,
  ec.threshold_unit,
  ec.min_threshold,
  efg.stackable
FROM earn_factor ef
JOIN earn_conditions ec ON ef.earn_conditions_group_id = ec.group_id
JOIN earn_factor_group efg ON ef.earn_factor_group_id = efg.id
WHERE ef.merchant_id = 'your-merchant-id'
AND ef.active_status = true;
```

---

*Want me to create the actual INSERT statements with your real brand/product UUIDs?*
