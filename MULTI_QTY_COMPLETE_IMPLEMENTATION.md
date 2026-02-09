# Multi-Quantity Reward Redemption - Complete Implementation

## ✅ All Services Updated

**Implementation Date:** 2026-02-03  
**Status:** Complete - Ready for Deployment

---

## What Was Changed

### 1. ✅ Supabase Function (Already Done)
**Function:** `redeem_reward_with_points`  
**Changes:** 
- Added promo code availability check
- Atomic code reservation with `FOR UPDATE SKIP LOCKED`
- Smart branching:
  - WITH promo codes → N records with unique codes
  - WITHOUT promo codes → 1 record with qty=N

### 2. ✅ Render API (`crm-api`)
**File:** `src/server.ts`  
**GitHub:** https://github.com/Rocket-CRM/crm-api  
**Commit:** 7a50b41d265af1fab57e04ebe1b7e93c04f8ae0e

**Changes:**
```typescript
// Added quantity parameter extraction with default
const { reward_id, quantity = 1 } = req.body;

// Added quantity validation
if (typeof quantity !== 'number' || quantity < 1 || quantity > 100) {
  return res.status(400).json({
    success: false,
    error: 'quantity must be a number between 1 and 100',
  });
}

// Added quantity to Kafka event
value: JSON.stringify({
  event_id: eventId,
  user_id: user.id,
  reward_id,
  quantity,  // ✅ NEW
  merchant_id: merchantId,
  timestamp: new Date().toISOString(),
}),
```

### 3. ✅ Event Processor (`crm-event-processors`)
**File:** `src/consumers/reward-consumer.ts`  
**GitHub:** https://github.com/Rocket-CRM/crm-event-processors  
**Commit:** c0d07f21899551dd6e2c9f1a43ec5a3ce057e3d4

**Changes:**
```typescript
// Extract quantity from Kafka event with default
const { event_id, user_id, reward_id, quantity = 1, merchant_id, timestamp } = event;

// Log quantity in console
console.log(
  `[RewardConsumer] Processing event ${event_id} for user=${user_id}, reward=${reward_id}, quantity=${quantity}`
);

// Pass quantity to Supabase RPC
const { data, error } = await supabase.rpc('redeem_reward_with_points', {
  p_reward_id: reward_id,
  p_quantity: quantity,  // ✅ Changed from hardcoded 1
  p_user_id: user_id,
  p_merchant_id: merchant_id,
});

// Removed redundant ledger INSERT
// (Supabase function already creates the record(s))
```

---

## Complete Architecture Flow

```
┌─────────────────────────────────────────────────────────────────┐
│                         FRONTEND                                │
│  POST /redemptions { reward_id, quantity: 5 }                  │
└────────────────────────────┬────────────────────────────────────┘
                             │
                             ↓
┌─────────────────────────────────────────────────────────────────┐
│                    RENDER API (crm-api)                         │
│  1. Validate JWT (extract user_id, merchant_id)                │
│  2. Validate reward_id and quantity (1-100)                    │
│  3. Publish to Kafka: { event_id, user_id, reward_id,         │
│                         quantity, merchant_id, timestamp }      │
│  4. Return: { success: true, event_id }                        │
└────────────────────────────┬────────────────────────────────────┘
                             │
                             ↓ (Kafka: reward_redemptions topic)
                             │
┌─────────────────────────────────────────────────────────────────┐
│               EVENT PROCESSOR (crm-event-processors)            │
│  1. Consume Kafka event                                         │
│  2. Extract: user_id, reward_id, quantity, merchant_id         │
│  3. Check idempotency (already processed?)                     │
│  4. Call Supabase RPC:                                          │
│     redeem_reward_with_points(                                  │
│       p_reward_id, p_quantity, p_user_id, p_merchant_id        │
│     )                                                            │
│  5. Handle retry on transient errors                           │
└────────────────────────────┬────────────────────────────────────┘
                             │
                             ↓
┌─────────────────────────────────────────────────────────────────┐
│          SUPABASE (redeem_reward_with_points function)          │
│  1. Validate eligibility (tier, persona, tags)                 │
│  2. Calculate points (multi-dimensional matching)              │
│  3. Check user balance                                          │
│  4. Branch based on promo codes:                                │
│                                                                  │
│     IF reward has promo codes:                                  │
│       ├─ Check pool availability (need N codes)                │
│       ├─ Reserve N codes atomically (FOR UPDATE SKIP LOCKED)   │
│       ├─ Create N ledger records (qty=1 each)                  │
│       ├─ Assign unique promo code to each                      │
│       └─ Mark each code as redeemed                            │
│                                                                  │
│     IF reward has NO promo codes:                               │
│       ├─ Create 1 ledger record (qty=N)                        │
│       └─ Use default promo code or NULL                        │
│                                                                  │
│  5. Deduct points via wallet system                            │
│  6. Return success with all redemption details                 │
└─────────────────────────────────────────────────────────────────┘
```

---

## API Usage

### Frontend Request

```javascript
// POST to Render API
const response = await fetch('https://crm-api-67ej.onrender.com/redemptions', {
  method: 'POST',
  headers: {
    'Authorization': `Bearer ${jwtToken}`,
    'Content-Type': 'application/json',
  },
  body: JSON.stringify({
    reward_id: 'reward-uuid',
    quantity: 5,  // ✅ NEW: Can now request multiple
  }),
});

const result = await response.json();

// Immediate response (async processing)
{
  "success": true,
  "event_id": "event-uuid",
  "message": "Redemption request received and processing",
  "quantity": 5  // ✅ NEW: Confirmed quantity
}
```

### Listen for Results (Supabase Realtime)

```javascript
// Subscribe to reward_redemptions_ledger for this event_id
const channel = supabase
  .channel('redemption-results')
  .on(
    'postgres_changes',
    {
      event: 'INSERT',
      schema: 'public',
      table: 'reward_redemptions_ledger',
      filter: `user_id=eq.${userId}`,
    },
    (payload) => {
      const redemption = payload.new;
      
      if (redemption.success === false) {
        // Show error
        alert(`Failed: ${redemption.error_message}`);
      } else {
        // Show success with promo codes
        console.log('Redemption successful!');
        console.log('Promo code:', redemption.promo_code);
      }
    }
  )
  .subscribe();
```

---

## Response Patterns

### Pattern A: Reward WITHOUT Promo Codes

**Request:**
```json
{
  "reward_id": "coffee-mug-uuid",
  "quantity": 5
}
```

**Kafka Event:**
```json
{
  "event_id": "evt-123",
  "user_id": "user-123",
  "reward_id": "coffee-mug-uuid",
  "quantity": 5,
  "merchant_id": "merchant-123",
  "timestamp": "2026-02-03T10:00:00Z"
}
```

**Database Result:**
```sql
-- 1 record created in reward_redemptions_ledger
id: evt-123
qty: 5
promo_code: NULL
points_deducted: 500
code: RWD000123
```

**Realtime Event:**
```json
{
  "redemption_id": "evt-123",
  "redemption_code": "RWD000123",
  "qty": 5,
  "promo_code": null,
  "points_deducted": 500
}
```

### Pattern B: Reward WITH Promo Codes

**Request:**
```json
{
  "reward_id": "voucher-with-codes-uuid",
  "quantity": 5
}
```

**Kafka Event:** (Same as above)

**Database Result:**
```sql
-- 5 records created in reward_redemptions_ledger

id: uuid-1, qty: 1, promo_code: 'CODE-ABC123', code: RWD000123
id: uuid-2, qty: 1, promo_code: 'CODE-DEF456', code: RWD000124
id: uuid-3, qty: 1, promo_code: 'CODE-GHI789', code: RWD000125
id: uuid-4, qty: 1, promo_code: 'CODE-JKL012', code: RWD000126
id: uuid-5, qty: 1, promo_code: 'CODE-MNO345', code: RWD000127
```

**Realtime Events:** (5 separate INSERT events)
```json
// Event 1
{ "redemption_code": "RWD000123", "promo_code": "CODE-ABC123", "qty": 1 }
// Event 2
{ "redemption_code": "RWD000124", "promo_code": "CODE-DEF456", "qty": 1 }
// ... 3 more events
```

### Pattern C: Insufficient Promo Codes

**Request:**
```json
{
  "reward_id": "voucher-with-codes-uuid",
  "quantity": 10
}
```

**Database Result:**
```sql
-- 1 failure record created
id: evt-123
success: false
error_code: 'INSUFFICIENT_CODES'
error_message: 'Only 7 code(s) available, you requested 10'
```

**Realtime Event:**
```json
{
  "success": false,
  "error_code": "INSUFFICIENT_CODES",
  "error_message": "Only 7 code(s) available, you requested 10"
}
```

---

## Key Points

### ✅ No Promo Code Logic in Render/Processor

**Render API:**
- Just validates quantity (1-100)
- Passes it through to Kafka
- No knowledge of promo codes

**Event Processor:**
- Just reads quantity from event
- Passes to Supabase function
- No knowledge of promo codes

**Supabase Function:**
- ✅ ALL promo code logic here
- Checks availability
- Reserves codes
- Creates appropriate records
- Handles all edge cases

### ✅ Backward Compatible

**Old requests still work:**
```json
// Omit quantity (defaults to 1)
{ "reward_id": "uuid" }
```

**New requests:**
```json
// Specify quantity
{ "reward_id": "uuid", "quantity": 5 }
```

### ✅ Error Handling

**Validation errors (immediate):**
- Missing reward_id → 400 from Render API
- Invalid quantity → 400 from Render API
- Invalid JWT → 401 from Render API

**Business errors (async via Realtime):**
- Insufficient points → Failure in ledger
- Insufficient promo codes → Failure in ledger
- Not eligible → Failure in ledger

---

## Deployment

Both repos have been updated on `main` branch:

**1. crm-api**
- Auto-deploys on Render.com
- Will redeploy automatically
- URL: https://crm-api-67ej.onrender.com

**2. crm-event-processors**
- Auto-deploy: NO (manual trigger)
- Need to trigger deployment manually

### Deploy Event Processor

You can trigger deployment via:
1. **Render Dashboard:** https://dashboard.render.com/worker/srv-d56v5pogjchc7399dfqg
2. **Or push an empty commit:**
```bash
git commit --allow-empty -m "Trigger deploy"
git push
```

---

## Testing Guide

### Test 1: Single Redemption (No Promo Codes)
```javascript
await fetch('https://crm-api-67ej.onrender.com/redemptions', {
  method: 'POST',
  headers: {
    'Authorization': `Bearer ${token}`,
    'Content-Type': 'application/json',
  },
  body: JSON.stringify({
    reward_id: 'coffee-mug-uuid',
    quantity: 1
  })
});

// Expected: 1 ledger record with qty=1
```

### Test 2: Multi-Quantity (No Promo Codes)
```javascript
await fetch('https://crm-api-67ej.onrender.com/redemptions', {
  method: 'POST',
  headers: {
    'Authorization': `Bearer ${token}`,
    'Content-Type': 'application/json',
  },
  body: JSON.stringify({
    reward_id: 'coffee-mug-uuid',
    quantity: 5
  })
});

// Expected: 1 ledger record with qty=5
```

### Test 3: Multi-Quantity WITH Promo Codes
```javascript
await fetch('https://crm-api-67ej.onrender.com/redemptions', {
  method: 'POST',
  headers: {
    'Authorization': `Bearer ${token}`,
    'Content-Type': 'application/json',
  },
  body: JSON.stringify({
    reward_id: 'voucher-with-codes-uuid',
    quantity: 5
  })
});

// Expected: 5 ledger records, each with qty=1 and unique promo_code
```

### Test 4: Insufficient Promo Codes
```javascript
await fetch('https://crm-api-67ej.onrender.com/redemptions', {
  method: 'POST',
  headers: {
    'Authorization': `Bearer ${token}`,
    'Content-Type': 'application/json',
  },
  body: JSON.stringify({
    reward_id: 'voucher-with-codes-uuid',
    quantity: 100  // More than available
  })
});

// Expected: Failure record with error_code='INSUFFICIENT_CODES'
```

### Test 5: Invalid Quantity
```javascript
await fetch('https://crm-api-67ej.onrender.com/redemptions', {
  method: 'POST',
  headers: {
    'Authorization': `Bearer ${token}`,
    'Content-Type': 'application/json',
  },
  body: JSON.stringify({
    reward_id: 'reward-uuid',
    quantity: 0  // Invalid
  })
});

// Expected: 400 error from Render API (immediate)
{
  "success": false,
  "error": "quantity must be a number between 1 and 100"
}
```

---

## Monitoring

### Logs to Watch

**Render API (`crm-api`):**
```
[API] Published event {event_id} for user {user_id}, quantity: 5
```

**Event Processor (`crm-event-processors`):**
```
[RewardConsumer] Processing event {event_id} for user={user_id}, reward={reward_id}, quantity=5
[RewardConsumer] Successfully processed event {event_id} in 234ms
```

**Supabase (via application logs):**
- Promo code availability checks
- Code reservation queries
- Ledger record creations

### Metrics to Track

1. **Quantity Distribution:**
   - % of redemptions with qty=1
   - % with qty>1
   - Average quantity per redemption

2. **Promo Code Pool Health:**
   - Alert when pool < 50 codes
   - Track depletion rate
   - Monitor "Insufficient codes" errors

3. **Processing Time:**
   - API response time (should be <50ms)
   - Event processing time (should be <500ms)
   - End-to-end latency

---

## Complete Flow Example

### Scenario: User Redeems 3 Vouchers with Promo Codes

**Step 1: Frontend Call**
```javascript
fetch('https://crm-api-67ej.onrender.com/redemptions', {
  method: 'POST',
  headers: { 'Authorization': 'Bearer jwt-token' },
  body: JSON.stringify({
    reward_id: 'voucher-uuid',
    quantity: 3
  })
})
```

**Step 2: Render API**
- Validates JWT → extracts user_id, merchant_id
- Validates quantity (3 is between 1-100) ✅
- Publishes to Kafka
- Returns immediately: `{ success: true, event_id: 'evt-123', quantity: 3 }`

**Step 3: Event Processor**
- Consumes event from Kafka
- Extracts quantity: 3
- Calls Supabase: `redeem_reward_with_points(..., p_quantity: 3, ...)`

**Step 4: Supabase Function**
- Loads reward → sees `assign_promocode = true`
- Checks pool → 100 codes available ✅
- Reserves 3 codes: `['CODE-A', 'CODE-B', 'CODE-C']`
- Creates 3 ledger records:
  ```sql
  INSERT ... (qty=1, promo_code='CODE-A', code='RWD001') ...
  INSERT ... (qty=1, promo_code='CODE-B', code='RWD002') ...
  INSERT ... (qty=1, promo_code='CODE-C', code='RWD003') ...
  ```
- Marks 3 codes as redeemed in `reward_promo_code`
- Deducts 300 points via wallet system
- Returns success

**Step 5: Frontend Receives via Realtime**
- 3 INSERT events on `reward_redemptions_ledger`
- Each has unique promo code
- UI shows: "Redeemed 3 vouchers! Your codes: CODE-A, CODE-B, CODE-C"

---

## Deployment Checklist

### ✅ Completed
- [x] Update Supabase function
- [x] Update Render API (crm-api)
- [x] Update Event Processor (crm-event-processors)
- [x] Git commits pushed to main

### 🔄 Deployment Status

**crm-api:**
- ✅ Auto-deploy enabled
- 🔄 Will deploy automatically (~5 mins)
- Check: https://dashboard.render.com/web/srv-d58fk9chg0os73bpa1ng

**crm-event-processors:**
- ⏸️ Auto-deploy DISABLED
- ⚠️ **Manual deployment required**
- Check: https://dashboard.render.com/worker/srv-d56v5pogjchc7399dfqg

### Next Steps

1. **Wait for crm-api deployment** (~5 minutes)
2. **Manually deploy crm-event-processors** (via Render dashboard)
3. **Test with small quantity first** (qty=1, then qty=2)
4. **Monitor logs** for both services
5. **Test with promo code rewards**

---

## Rollback Plan

If issues occur:

### Render API
```bash
# Revert to previous commit
git revert 7a50b41d265af1fab57e04ebe1b7e93c04f8ae0e
git push
```

### Event Processor
```bash
# Revert to previous commit
git revert c0d07f21899551dd6e2c9f1a43ec5a3ce057e3d4
git push
```

### Supabase Function
```sql
-- Contact admin to restore previous function version
-- Or redeploy from backup migration
```

---

**Status:** ✅ Code Complete - Awaiting Deployment  
**Risk Level:** Low (backward compatible)  
**Testing:** Required before production load
