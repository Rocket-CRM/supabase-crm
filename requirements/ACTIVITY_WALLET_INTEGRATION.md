# Activity → Wallet Integration: Complete Source & Component Tracking

## The Question: Does Direct Call Support Proper Data?

**Answer: YES.** Direct `chokepoint_post_wallet_transaction()` provides the same wallet_ledger audit trail as async earn paths (purchase/mission via chokepoint outbox → Inngest).

---

## Complete wallet_ledger Entry from Activity Approval

### When Admin Approves Upload

```sql
-- Inside bff_approve_activity_upload()
PERFORM chokepoint_post_wallet_transaction(
  p_user_id := v_upload.user_id,
  p_merchant_id := v_merchant_id,
  p_currency := 'points',                     -- or 'ticket'
  p_transaction_type := 'earn',
  p_component := 'base',
  p_amount := 50,
  p_transaction_id := gen_random_uuid(),      -- required
  p_dedup_key := 'activity_' || p_upload_id::text,  -- required for idempotency
  p_source_type := 'activity',
  p_source_id := p_upload_id,                 -- activity_upload_ledger.id
  p_target_entity_id := NULL,                 -- NULL for points, ticket_type_id for tickets
  p_description := 'Activity: exercise',
  p_metadata := jsonb_build_object(
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

## Comparison: Async Earn Path vs Direct Call

### Async path (Purchase, Mission, etc.)

```
Ledger write → chokepoint_event_outbox → OutboxPublisher → Inngest routers
  → calc / process → chokepoint_post_wallet_transaction → wallet_ledger
```

**wallet_ledger result:**
- source_type: 'purchase' / 'mission' / …
- source_id: source ledger id
- component: 'base'/'bonus'
- metadata: calculation details
- **All fields populated ✅**

### Direct call (Activity, Reward Redemption, Manual)

```
Admin approves → bff_approve_activity_upload() → chokepoint_post_wallet_transaction
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

When `chokepoint_post_wallet_transaction()` creates a `wallet_ledger` earn row, the chokepoint emits a wallet domain event to `chokepoint_event_outbox` (unless emit is skipped). Live path:

```
wallet outbox event → OutboxPublisher → inngest-event-router-serve
  → tier-wallet-router → process_tier_event
```

There is **no** `trigger_tier_eval_on_wallet` on `wallet_ledger`. Live triggers on that table are `set_dedup_key_on_wallet` and `trg_enqueue_shopify_store_credit_issue`. FIFO burn allocation lives in `chokepoint_post_wallet_transaction` (`fn_allocate_fifo_burn`), not in a ledger trigger.

**Activity earnings count toward tier progression:**
- Tier conditions with `metric='points'` include activity-earned points
- Query: `SUM(amount) WHERE transaction_type='earn'` (includes all source_types)
- Activity uploads can contribute to tier upgrades

---

## Edit-and-Recalculate (implemented 2026-05-14)

`bff_edit_activity_upload(p_upload_id, p_field_values, p_reason, p_language)` is the single entry point for editing an `approved` or `rejected` upload. It computes the target totals from the new field values, diffs against the current net per `(currency, target_entity_id)` in `wallet_ledger`, and posts one chokepoint call per non-zero delta.

### Component routing

| Direction | Source state | `component` | `transaction_type` | Amount |
|---|---|---|---|---|
| Re-approve a rejected upload | `rejected` → `approved` | `base` | `earn` | full new amount |
| New > previous (admin gave higher value) | `approved` → `approved` | `adjustment` | `earn` | `Δ = new − previous` |
| New < previous (admin gave lower value) | `approved` → `approved` | `reversal` | `burn` | `|Δ|` (clamped — see below) |
| New == previous | — | (skipped) | — | — |

All entries keep `source_type='activity'`, `source_id=upload_id`. Audit query `WHERE source_type='activity' AND source_id=upload_id` returns the original earn row plus every edit delta in time order.

### FIFO partial reversal

Burns allocate through `chokepoint_post_wallet_transaction` → `fn_allocate_fifo_burn`: oldest-expiry-first earn lots, points fungible within the wallet, tickets isolated by `target_entity_id`. No targeted-by-source-id consumption. Insufficient matching lots raise and roll back the burn.

### Partial-cover clamping

`chokepoint_post_wallet_transaction` raises `Insufficient balance` if a burn would drive the balance negative. The edit BFF prevents this by reading the current balance first and clamping:

- Points: `current_balance := user_wallet.points_balance`
- Tickets: `current_balance := user_ticket_balances.balance` per `target_entity_id`

If `current_balance < |Δ|`:
- Post `amount = current_balance` only
- Record `unreversed_amount = |Δ| − current_balance` and `skipped_reason ∈ {zero_balance, partial_balance}` in `edit_history.deltas[i]` and in the wallet_ledger row's `metadata`
- Status still flips to / stays at `approved`; `points_awarded` / `tickets_awarded` reflect the target totals (not the partially-applied balance)

### Dedup key construction

Explicit override to avoid collision with the original approve row and prior edits:

```
activity_<upload_id>_v<edit_version>_<currency>_<target_entity_id_or_'none'>
```

`edit_version` is incremented per edit, so repeat edits of the same upload in the same direction never collide.

### Edit history entry shape

Each edit appends one entry to `activity_upload_ledger.edit_history`:

```json
{
  "edit_version": 2,
  "edited_at": "2026-05-14T03:14:22Z",
  "edited_by": "<admin_uuid>",
  "edited_by_name": "Alice",
  "reason": "Customer provided corrected field values",
  "previous_status": "approved",
  "new_status": "approved",
  "previous_field_values": { ... },
  "new_field_values": { ... },
  "previous_points_awarded": 500,
  "new_points_awarded": 350,
  "previous_tickets_awarded_total": 3,
  "new_tickets_awarded_total": 2,
  "deltas": [
    {
      "currency": "points",
      "target_entity_id": null,
      "previous_amount": 500,
      "new_amount": 350,
      "delta_intended": -150,
      "delta_applied": -100,
      "unreversed_amount": 50,
      "component": "reversal",
      "transaction_type": "burn",
      "ledger_id": "<wallet_ledger_id>",
      "dedup_key": "activity_<upload>_v2_points_none",
      "skipped_reason": "partial_balance"
    }
  ]
}
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
- `chokepoint_post_wallet_transaction()` calculates expiry_date based on merchant config
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
| `purchase` | Outbox → Inngest currency routers | Async pipeline | ✅ Full (source_type, source_id, metadata) |
| `mission` | Outcome / mission routers → chokepoint | Async pipeline | ✅ Full (source_type, source_id, metadata) |

**Conclusion:** Direct call provides the same data quality as the async earn path. The only difference is synchronous vs asynchronous execution, not data completeness.

---

*Document Version: 1.0*  
*Purpose: Demonstrate wallet_ledger integration completeness*

