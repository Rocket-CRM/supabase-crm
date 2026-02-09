# Persona/Customer Segment Targeting in Earn Factors

## 🎯 Three Ways to Target Personas:

---

## Method 1: Public Rules with Tier/Type Conditions ⭐ (Recommended)

**Use Case:** Automatic bonuses for customer segments (VIP, Gold, Premium users)

### Using Tier:
```sql
-- Step 1: Create conditions for VIP tier
INSERT INTO earn_conditions_group (name, merchant_id)
VALUES ('VIP Tier Conditions', 'merchant-id') RETURNING id;

INSERT INTO earn_conditions (
  group_id,
  entity,
  entity_ids,
  merchant_id
) VALUES (
  'conditions_group_id',
  'tier',  -- Check user's tier
  ARRAY['vip_tier_uuid', 'gold_tier_uuid']::uuid[],  -- VIP and Gold tiers
  'merchant-id'
);

-- Step 2: Create earn factor with 2x multiplier
INSERT INTO earn_factor (
  earn_factor_type,
  earn_factor_amount,
  target_currency,
  earn_factor_group_id,
  earn_conditions_group_id,
  public,  -- TRUE = applies to all users with this tier
  active_status,
  merchant_id
) VALUES (
  'multiplier',
  2,  -- 2x for VIP/Gold
  'points',
  'factor_group_id',
  'conditions_group_id',
  true,  -- Public
  true,
  'merchant-id'
);
```

**Result:** ALL VIP and Gold tier users automatically get 2x multiplier!

---

## Method 2: Personalized Offers (Individual Assignments)

**Use Case:** One-time bonuses for specific users (birthday, welcome back, special rewards)

### Setup:
```sql
-- Step 1: Create earn factor (NO conditions)
INSERT INTO earn_factor (
  earn_factor_type,
  earn_factor_amount,
  target_currency,
  earn_factor_group_id,
  public,  -- FALSE = not available to everyone
  active_status,
  merchant_id
) VALUES (
  'multiplier',
  5,  -- 5x birthday bonus
  'points',
  'factor_group_id',
  false,  -- Private/Personalized
  true,
  'merchant-id'
) RETURNING id;  -- Save as 'birthday_factor_id'

-- Step 2: Assign to specific users
INSERT INTO earn_factor_user (
  earn_factor_id,
  user_id,
  merchant_id,
  window_end  -- Expiration date
) VALUES
  ('birthday_factor_id', 'user_1_id', 'merchant-id', '2026-02-15'),  -- Expires Feb 15
  ('birthday_factor_id', 'user_2_id', 'merchant-id', '2026-03-01'),  -- Expires Mar 1
  ('birthday_factor_id', 'user_3_id', 'merchant-id', '2026-02-28');  -- Expires Feb 28
```

**Result:** Only these 3 users get 5x birthday bonus, expires on their specific dates!

---

## Method 3: Using Type/Subtype Entities

**Use Case:** Segment by user_type or persona_id

### user_accounts has:
- `type_id` - User type classification
- `persona_id` - Customer persona/segment
- `user_type` - Buyer/seller designation

### Using Type Entity:
```sql
-- Create conditions for specific user type
INSERT INTO earn_conditions (
  group_id,
  entity,
  entity_ids,
  merchant_id
) VALUES (
  'conditions_group_id',
  'type',  -- Check user_accounts.type_id
  ARRAY['premium_customer_type_uuid']::uuid[],
  'merchant-id'
);

-- Create factor
INSERT INTO earn_factor (
  earn_factor_amount,
  earn_conditions_group_id,
  public,
  ...
) VALUES (
  3,  -- 3x for Premium customers
  'conditions_group_id',
  true,
  ...
);
```

**Result:** All users with `type_id` = premium_customer_type_uuid get 3x!

---

## 📊 Comparison:

| Method | Scope | Automatic | Expiry | Use Case |
|--------|-------|-----------|--------|----------|
| **Tier/Type Conditions** | Segment | ✅ Yes | Group window | "All VIP get 2x" |
| **Personalized (earn_factor_user)** | Individual | ❌ Manual | Per user | "Happy birthday 5x" |
| **Type/Subtype** | Segment | ✅ Yes | Group window | "All premium users 3x" |

---

## 🎯 Your Question: Can we specify persona per earn_factor_group?

**Answer: No, but you can achieve the same result:**

### Option A: Use Conditions (Recommended)
```
Group 1: "VIP Promotions"
├── Factor 1: 3x for Product A (with tier=VIP condition)
├── Factor 2: 5x for Product B (with tier=VIP condition)
└── All factors have tier=VIP in their conditions
```

### Option B: Separate Groups per Segment
```
Group 1: "VIP Product Bonuses"
└── All factors have tier=VIP condition

Group 2: "Gold Product Bonuses"  
└── All factors have tier=Gold condition

Group 3: "Regular Product Bonuses"
└── All factors have tier=Regular condition
```

**Both work! Option A is simpler.** ✅

---

## 🧪 Example: 3x for Brand A, only for VIP customers

```sql
-- Step 1: Conditions (Product + Tier)
INSERT INTO earn_conditions_group (name) 
VALUES ('Brand A + VIP') RETURNING id;

-- Condition 1: Brand A
INSERT INTO earn_conditions (
  group_id,
  entity,
  entity_ids
) VALUES (
  'conditions_group_id',
  'product_brand',
  ARRAY['brand_a_uuid']
);

-- Condition 2: VIP tier (same group!)
INSERT INTO earn_conditions (
  group_id,
  entity,
  entity_ids
) VALUES (
  'conditions_group_id',
  'tier',
  ARRAY['vip_tier_uuid']
);

-- Step 2: Create factor
INSERT INTO earn_factor (
  earn_factor_amount,
  earn_conditions_group_id,
  public
) VALUES (
  3,
  'conditions_group_id',
  true
);
```

**Result:** Only VIP users get 3x on Brand A products! (Both conditions must match)

---

## ✅ Summary:

**Persona targeting:**
- ❌ Not a direct field on earn_factor_group
- ✅ Use `tier` entity in conditions (automatic for all users in tier)
- ✅ Use `type` entity in conditions (automatic for all users with that type)
- ✅ Use `earn_factor_user` table (manual assignment per user)

**Most common approach:** Add `tier` condition to your factors! 🎯