-- ========================================
-- Multi-Product Multiplier Configuration
-- ========================================
-- Goal: Different multipliers for different products
-- All in ONE earn_factor_group (non-stackable)
-- ========================================

-- Step 1: Create ONE earn factor group for all product promotions
-- ========================================
INSERT INTO earn_factor_group (id, name, stackable, merchant_id, active_status)
VALUES (
  gen_random_uuid(), -- Will generate something like: 'abc-123-def'
  'Product Promotions 2026',
  false,  -- Non-stackable (each product gets its own multiplier)
  '09b45463-3812-42fb-9c7f-9d43b6fd3eb9',
  true
) RETURNING id;
-- SAVE THIS ID! Let's call it: 'factor_group_id'

-- ========================================
-- Step 2: Create conditions groups (one per product/rule)
-- ========================================

-- Conditions for Product A (3x multiplier)
INSERT INTO earn_conditions_group (id, name, merchant_id)
VALUES (
  gen_random_uuid(),
  'Product A Conditions',
  '09b45463-3812-42fb-9c7f-9d43b6fd3eb9'
) RETURNING id;
-- Save as: 'conditions_group_a'

-- Conditions for Product B (5x multiplier)
INSERT INTO earn_conditions_group (id, name, merchant_id)
VALUES (
  gen_random_uuid(),
  'Product B Conditions',
  '09b45463-3812-42fb-9c7f-9d43b6fd3eb9'
) RETURNING id;
-- Save as: 'conditions_group_b'

-- Conditions for Product C (8x multiplier)
INSERT INTO earn_conditions_group (id, name, merchant_id)
VALUES (
  gen_random_uuid(),
  'Product C Conditions',
  '09b45463-3812-42fb-9c7f-9d43b6fd3eb9'
) RETURNING id;
-- Save as: 'conditions_group_c'

-- Conditions for Brand X (2x multiplier)
INSERT INTO earn_conditions_group (id, name, merchant_id)
VALUES (
  gen_random_uuid(),
  'Brand X Conditions',
  '09b45463-3812-42fb-9c7f-9d43b6fd3eb9'
) RETURNING id;
-- Save as: 'conditions_group_x'

-- ========================================
-- Step 3: Define conditions (WHEN each rule applies)
-- ========================================

-- Product A: Secondary UOM > 100
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
  'conditions_group_a',  -- Links to Product A conditions
  'product_product',  -- Check by product
  ARRAY['product_a_uuid']::uuid[],  -- Product A UUID
  'quantity_secondary',  -- Check bulk UOM
  100,  -- Minimum 100 tonnes/pallets/etc
  NULL,  -- No maximum cap
  false,  -- Apply to full line (not just excess)
  '09b45463-3812-42fb-9c7f-9d43b6fd3eb9'
);

-- Product B: Primary UOM > 500
INSERT INTO earn_conditions (
  group_id,
  entity,
  entity_ids,
  threshold_unit,
  min_threshold,
  apply_to_excess_only,
  merchant_id
) VALUES (
  'conditions_group_b',
  'product_product',
  ARRAY['product_b_uuid']::uuid[],
  'quantity_primary',  -- Check retail UOM
  500,  -- Minimum 500 pieces/bags/etc
  false,
  '09b45463-3812-42fb-9c7f-9d43b6fd3eb9'
);

-- Product C: Amount > 1000 THB
INSERT INTO earn_conditions (
  group_id,
  entity,
  entity_ids,
  threshold_unit,
  min_threshold,
  apply_to_excess_only,
  merchant_id
) VALUES (
  'conditions_group_c',
  'product_product',
  ARRAY['product_c_uuid']::uuid[],
  'amount',  -- Check line total
  1000,  -- Minimum 1000 THB
  true,  -- Bonus on excess only (8x on amount above 1000)
  '09b45463-3812-42fb-9c7f-9d43b6fd3eb9'
);

-- Brand X: Any purchase of Brand X products
INSERT INTO earn_conditions (
  group_id,
  entity,
  entity_ids,
  merchant_id
) VALUES (
  'conditions_group_x',
  'product_brand',  -- Check by brand
  ARRAY['brand_x_uuid']::uuid[],  -- Brand X UUID
  '09b45463-3812-42fb-9c7f-9d43b6fd3eb9'
  -- No threshold = applies to any quantity/amount
);

-- ========================================
-- Step 4: Create earn factors (HOW MUCH bonus)
-- ALL link to the SAME earn_factor_group!
-- ========================================

-- Product A: 3x multiplier
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
  3,  -- 3x
  'points',
  NULL,
  'factor_group_id',  -- SAME GROUP
  'conditions_group_a',
  true,
  true,
  '09b45463-3812-42fb-9c7f-9d43b6fd3eb9'
);

-- Product B: 5x multiplier
INSERT INTO earn_factor (
  earn_factor_type,
  earn_factor_amount,
  target_currency,
  earn_factor_group_id,
  earn_conditions_group_id,
  public,
  active_status,
  merchant_id
) VALUES (
  'multiplier',
  5,  -- 5x
  'points',
  'factor_group_id',  -- SAME GROUP
  'conditions_group_b',
  true,
  true,
  '09b45463-3812-42fb-9c7f-9d43b6fd3eb9'
);

-- Product C: 8x multiplier
INSERT INTO earn_factor (
  earn_factor_type,
  earn_factor_amount,
  target_currency,
  earn_factor_group_id,
  earn_conditions_group_id,
  public,
  active_status,
  merchant_id
) VALUES (
  'multiplier',
  8,  -- 8x
  'points',
  'factor_group_id',  -- SAME GROUP
  'conditions_group_c',
  true,
  true,
  '09b45463-3812-42fb-9c7f-9d43b6fd3eb9'
);

-- Brand X: 2x multiplier
INSERT INTO earn_factor (
  earn_factor_type,
  earn_factor_amount,
  target_currency,
  earn_factor_group_id,
  earn_conditions_group_id,
  public,
  active_status,
  merchant_id
) VALUES (
  'multiplier',
  2,  -- 2x
  'points',
  'factor_group_id',  -- SAME GROUP
  'conditions_group_x',
  true,
  true,
  '09b45463-3812-42fb-9c7f-9d43b6fd3eb9'
);

-- ========================================
-- How It Works:
-- ========================================

/*
TRANSACTION 1: Buy Product A (150 secondary UOM) + Product B (600 primary UOM)
├── Product A line item:
│   ├── Condition check: 150 secondary > 100 ✅
│   └── Award: 3x multiplier on Product A amount
└── Product B line item:
    ├── Condition check: 600 primary > 500 ✅
    └── Award: 5x multiplier on Product B amount

Result: Each product gets its OWN multiplier!

TRANSACTION 2: Buy Product A (150) + Product A again (200)
├── Product A line 1: 3x multiplier
└── Product A line 2: 3x multiplier
Result: Both get 3x (same product, same rule)

TRANSACTION 3: Buy Product A (80 secondary UOM)
├── Product A line:
│   ├── Condition check: 80 < 100 ❌
│   └── Award: Base rate only (no multiplier)

STACKABLE = FALSE means:
- Each LINE ITEM gets matched to ONE multiplier
- Different products in same transaction get their respective multipliers
- Same product gets same multiplier
- Does NOT mean "only one multiplier per transaction"
*/

-- ========================================
-- Query to Verify Configuration:
-- ========================================

SELECT 
  efg.name as group_name,
  efg.stackable,
  ef.earn_factor_amount as multiplier,
  ec.entity,
  ec.threshold_unit,
  ec.min_threshold,
  ec.entity_ids
FROM earn_factor_group efg
JOIN earn_factor ef ON efg.id = ef.earn_factor_group_id
JOIN earn_conditions ec ON ef.earn_conditions_group_id = ec.group_id
WHERE efg.merchant_id = '09b45463-3812-42fb-9c7f-9d43b6fd3eb9'
AND ef.active_status = true
ORDER BY ef.earn_factor_amount DESC;
