# Activity → Wallet Integration: Complete Source & Component Tracking

## The Question: Does Direct Call Support Proper Data?

**Answer: YES!** Direct `post_wallet_transaction()` call provides **identical audit trail** to CDC flow.

---

## Complete wallet_ledger Entry from Activity Approval

### When Admin Approves Upload

```sql
-- Inside bff_approve_activity_upload()
PERFORM post_wallet_transaction(
  p_user_id := v_upload.user_id,              -- User who uploaded
  p_merchant_id := v_merchant_id,             -- Merchant context
  p_currency := 'points',                     -- or 'ticket'
  p_transaction_type := 'earn',               -- Earning currency
  p_component := 'base',                      -- Standard earned (not bonus/adjustment/reversal)
  p_amount := 50,                             -- From activity_currency_config
  p_source_type := 'activity',                -- ← NEW enum value
  p_source_id := p_upload_id,                 -- ← activity_upload_ledger.id
  p_target_entity_id := NULL,                 -- NULL for points, ticket_type_id for tickets
  p_description := 'Activity: exercise',
  p_metadata := jsonb_build_object(           -- ← FULL AUDIT TRAIL
    'activity_id', v_activity_id,
    'activity_name', 'Exercise Activity',
    'activity_code', 'exercise',
    'field_values', {
      "exercise_type": "yoga",
      "time_of_day": "morning", 
      "location": "central"
    },
    'matrix_match', {
      "primary_dimension": "time_of_day",
      "primary_value": "morning",
      "secondary_field": "exercise_type",
      "secondary_value": "yoga",
      "config_id": "currency-config-uuid"
    },
    'approved_by', 'admin-uuid',
    'approved_at', '2026-01-22T14:30:00Z',
    'image_url', 'https://storage.../image.jpg'
  )
);
```

### Resulting wallet_ledger Record

```json
{
  "id": "wallet-ledger-uuid",
  "user_id": "user-uuid",
  "merchant_id": "merchant-uuid",
  
  "currency": "points",
  "transaction_type": "earn",
  "component": "base",
  
  "amount": 50,
  "signed_amount": 50,
  "balance_before": 100,
  "balance_after": 150,
  
  "source_type": "activity",
  "source_id": "upload-uuid",
  "target_entity_id": null,
  
  "description": "Activity: exercise",
  
  "metadata": {
    "activity_id": "exercise-uuid",
    "activity_name": "Exercise Activity",
    "activity_code": "exercise",
    "field_values": {
      "exercise_type": "yoga",
      "time_of_day": "morning",
      "location": "central"
    },
    "matrix_match": {
      "primary_dimension": "time_of_day",
      "primary_value": "morning",
      "secondary_field": "exercise_type",
      "secondary_value": "yoga",
      "config_id": "currency-config-uuid"
    },
    "approved_by": "admin-uuid",
    "approved_at": "2026-01-22T14:30:00Z",
    "image_url": "https://storage.../image.jpg"
  },
  
  "expiry_date": "2026-07-22",
  "deductible_balance": 50,
  "expired_amount": 0,
  "expiry_processed_at": null,
  
  "created_at": "2026-01-22T14:30:00Z"
}
```

---

## All Required Fields Properly Populated

| Field | Value | Purpose |
|-------|-------|---------|
| ✅ `source_type` | `'activity'` | Identifies this is activity-earned currency |
| ✅ `source_id` | `upload_id` | Direct link to `activity_upload_ledger.id` |
| ✅ `component` | `'base'` | Standard earned currency (correct categorization) |
| ✅ `transaction_type` | `'earn'` | Earning transaction (counts for tier evaluation) |
| ✅ `currency` | `'points'` or `'ticket'` | Which currency type |
| ✅ `target_entity_id` | `NULL` or `ticket_type_id` | Proper fungible/non-fungible separation |
| ✅ `metadata` | Full JSONB | Complete context for audit and analysis |
| ✅ `amount` | From matrix | Magnitude value |
| ✅ `signed_amount` | Positive (earn) | Directional value for balance calc |
| ✅ `balance_before/after` | Calculated | Balance snapshots |
| ✅ `expiry_date` | Auto-calculated | Based on merchant/ticket expiry config |

---

## Comparison: CDC Flow vs Direct Call

### CDC Flow (Purchase, Mission, etc.)

```
Event occurs → CDC captures → Kafka → Consumer calculates → Inngest orchestrates → post_wallet_transaction
                                                                                            ↓
                                                                                    wallet_ledger entry
```

**wallet_ledger result:**
- source_type: 'purchase'
- source_id: purchase_ledger.id
- component: 'base'/'bonus'
- metadata: calculation details
- **All fields populated ✅**

### Direct Call Flow (Activity, Reward Redemption, Manual)

```
Admin approves → bff_approve_activity_upload() → post_wallet_transaction
                                                            ↓
                                                    wallet_ledger entry
```

**wallet_ledger result:**
- source_type: 'activity'
- source_id: activity_upload_ledger.id
- component: 'base'
- metadata: approval details
- **All fields populated ✅**

### Result: Identical Audit Trail

**Both flows produce complete wallet_ledger entries with:**
- ✅ Source tracking (type + id)
- ✅ Component categorization
- ✅ Full metadata
- ✅ Balance history
- ✅ Expiry calculation
- ✅ Tier evaluation trigger

**No difference in data quality!**

---

## Audit & Reporting Capabilities

### Query Activity Earnings

**All activity-earned currency:**
```sql
SELECT 
  wl.created_at,
  wl.amount,
  wl.currency,
  wl.metadata->>'activity_name' as activity,
  wl.metadata->'field_values'->>'exercise_type' as exercise_type,
  wl.metadata->'field_values'->>'time_of_day' as time
FROM wallet_ledger wl
WHERE wl.source_type = 'activity'
  AND wl.merchant_id = get_current_merchant_id()
ORDER BY wl.created_at DESC;
```

**Activity currency by type:**
```sql
SELECT 
  wl.metadata->>'activity_name' as activity_type,
  COUNT(*) as award_count,
  SUM(wl.amount) as total_currency
FROM wallet_ledger wl
WHERE wl.source_type = 'activity'
  AND wl.merchant_id = get_current_merchant_id()
  AND wl.created_at >= NOW() - INTERVAL '30 days'
GROUP BY wl.metadata->>'activity_name';
```

**User's activity earning breakdown:**
```sql
SELECT 
  wl.created_at,
  wl.metadata->>'activity_name' as activity,
  wl.metadata->'field_values' as field_values,
  wl.amount,
  wl.balance_after
FROM wallet_ledger wl
WHERE wl.source_type = 'activity'
  AND wl.user_id = 'user-uuid'
ORDER BY wl.created_at DESC;
```

**Trace specific upload:**
```sql
SELECT 
  aul.submitted_at,
  aul.image_url,
  aul.field_values,
  aul.approved_at,
  au.name as approved_by_name,
  wl.amount as points_awarded,
  wl.balance_after,
  wl.metadata
FROM activity_upload_ledger aul
LEFT JOIN wallet_ledger wl ON wl.source_id = aul.id AND wl.source_type = 'activity'
LEFT JOIN admin_users au ON aul.approved_by = au.id
WHERE aul.id = 'specific-upload-uuid';
```

---

## Tier Evaluation Integration

### Automatic Tier Re-evaluation

When `post_wallet_transaction()` creates wallet_ledger entry with `transaction_type='earn'`:

**Existing trigger fires:**
```sql
trigger_tier_eval_on_wallet()
  ↓
Queues tier evaluation for user
  ↓
User's tier re-evaluated based on ALL earn sources including activity
```

**Activity earnings count toward tier progression:**
- Tier conditions with `metric='points'` include activity-earned points
- Query: `SUM(amount) WHERE transaction_type='earn'` (includes all source_types)
- Activity uploads can contribute to tier upgrades!

---

## Reversal Support (Future)

If you need to reverse activity currency (e.g., fraud detection):

```sql
-- Find original award
SELECT * FROM wallet_ledger
WHERE source_type = 'activity'
  AND source_id = 'upload-to-reverse';

-- Create reversal entry
PERFORM post_wallet_transaction(
  p_user_id := v_user_id,
  p_merchant_id := v_merchant_id,
  p_currency := 'points',
  p_transaction_type := 'earn',      -- Still 'earn' type
  p_component := 'reversal',         -- But 'reversal' component
  p_amount := 50,                    -- Positive amount
  p_signed_amount := -50,            -- Negative signed amount
  p_source_type := 'activity',
  p_source_id := 'upload-uuid',
  p_reference_id := 'original-wallet-ledger-id',  -- Links to original
  p_metadata := jsonb_build_object(
    'reversal_reason', 'Fraudulent upload detected',
    'reversed_by', 'admin-uuid',
    'original_field_values', {...}
  )
);
```

---

## Why This Works Perfectly

### ✅ Complete Audit Trail
- Every activity approval creates wallet_ledger entry
- `source_type + source_id` uniquely identifies origin
- `metadata` contains full approval context
- Can trace back to original image upload

### ✅ Proper Component Classification
- `component='base'` correctly categorizes as standard earned currency
- Distinguishes from `bonus` (multipliers), `adjustment` (admin fixes), `reversal` (refunds)
- Financial reporting works correctly

### ✅ Tier Integration
- Activity earnings automatically count toward tier progression
- `transaction_type='earn'` triggers tier evaluation
- No special handling needed - works like purchase/mission earnings

### ✅ Expiry Handling
- `post_wallet_transaction()` calculates expiry_date based on merchant config
- Activity-earned currency expires same as purchase-earned
- No special expiry logic needed

### ✅ Query Flexibility
- Can filter by `source_type='activity'`
- Can aggregate activity earnings separately
- Can join to activity_upload_ledger via source_id
- Metadata enables detailed analysis

---

## Comparison to Other Direct-Call Sources

| Source Type | Caller | Pattern | wallet_ledger Population |
|-------------|--------|---------|-------------------------|
| `reward_redemption` | User (redemption) | Direct call | ✅ Full (source_type, source_id, metadata) |
| `manual` | Admin (adjustment) | Direct call | ✅ Full (source_type, source_id, metadata) |
| **`activity`** | **Admin (approval)** | **Direct call** | **✅ Full (source_type, source_id, metadata)** |
| `purchase` | CDC event | Async pipeline | ✅ Full (source_type, source_id, metadata) |
| `mission` | CDC event | Async pipeline | ✅ Full (source_type, source_id, metadata) |

**Conclusion:** Direct call provides **identical data quality** to CDC flow. The only difference is synchronous vs asynchronous execution, not data completeness.

---

*Document Version: 1.0*  
*Purpose: Demonstrate wallet_ledger integration completeness*

