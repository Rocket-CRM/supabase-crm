# crm-event-processors — Consumer Changes for Event Ordering

## Overview

Two consumers in `crm-event-processors` need additive changes to support:
1. **CurrencyConsumer** — award currency on pending event orders (existing completed flow unchanged)
2. **AmpConsumer** — trigger AMP workflows on pending event orders (for reward push)

Both changes are **additive only** — existing routing logic is not modified.

---

## 1. CurrencyConsumer

### File
`src/consumers/currency-consumer.ts` (or equivalent)

### Current behaviour
Filters `purchase_ledger` CDC events to `status = 'completed'` only before processing currency awards.

### Change required

In the `shouldProcess` / filter logic, add a second routing path:

```typescript
// Existing path (unchanged):
if (record.status === 'completed') {
  return true;
}

// New path — pending event orders:
if (
  record.status === 'pending' &&
  record.transaction_source === 'event_order'
) {
  return true;
}

return false;
```

### Processing logic for pending event orders

When processing a pending event order, the consumer must **only** evaluate earn_factor_groups whose linked `earn_conditions_group.allowed_purchase_statuses` includes `'pending'`.

Pseudo-logic:

```typescript
// When status === 'pending' && transaction_source === 'event_order':
// 1. Load earn_factor_groups for the merchant that are active and within window
// 2. For each group, load its earn_factors and their earn_conditions_group
// 3. Skip the group if earn_conditions_group.allowed_purchase_statuses
//    does NOT include 'pending' (or is NULL)
// 4. Run normal currency calc for qualifying groups only
// 5. Call chokepoint_post_wallet_transaction as normal
```

The `allowed_purchase_statuses` column is on `earn_conditions_group` (added by migration `event_ordering_schema_additions`). Query it alongside normal earn factor loading.

### Why this is safe
- NULL `allowed_purchase_statuses` → skip (default, existing groups unaffected)
- Only explicitly opted-in earn_conditions_groups fire on pending
- Completed orders still go through the original path and evaluate all groups normally

---

## 2. AmpConsumer

### File
`src/consumers/amp-consumer.ts` (or equivalent)

### Current behaviour
In `shouldDispatch()` for `purchase_ledger` table: only dispatches when `record.status === 'completed'`.

### Change required

Add one additional condition:

```typescript
// Existing (unchanged):
if (table === 'purchase_ledger' && record.status === 'completed') {
  return true;
}

// New:
if (
  table === 'purchase_ledger' &&
  record.status === 'pending' &&
  record.transaction_source === 'event_order'
) {
  return true;
}
```

### Field mapping for dispatch payload

When routing a pending event order, ensure `transaction_source_id` is included in `extractRecordData()` so the `dispatch-workflow-trigger` edge function can match `amp_workflow_trigger.trigger_conditions` (which merchants use to scope workflows to a specific event via `{ "transaction_source_id": "<event_uuid>" }`).

```typescript
// In extractRecordData for purchase_ledger:
{
  trigger_table: 'purchase_ledger',
  trigger_operation: 'INSERT',
  merchant_id: record.merchant_id,
  user_id: record.user_id,
  record_id: record.id,
  record_data: {
    status: record.status,
    transaction_source: record.transaction_source,
    transaction_source_id: record.transaction_source_id,  // ← ensure this is included
    final_amount: record.final_amount,
    api_source: record.api_source,
  }
}
```

### No other changes needed
`dispatch-workflow-trigger` and `inngest-serve` require no changes — they already handle the routing and the updated `fn_execute_amp_action` (with `push_reward`) is live in Supabase.

---

## Deployment

1. Deploy Supabase migrations first (already done)
2. Deploy `crm-event-processors` with both consumer changes
3. No other services require changes

## Testing

### CurrencyConsumer test
1. Create an earn_conditions_group with `allowed_purchase_statuses = ['pending']`
2. Link an earn_factor to it
3. Call `api_create_manual_purchase_order` with `transaction_source='event_order'`
4. Verify `wallet_ledger` entry created for the pending purchase
5. Verify completed purchases still process normally (regression check)

### AmpConsumer test
1. Create an AMP workflow with trigger on `purchase_ledger INSERT`, trigger_conditions `{ "transaction_source_id": "<event_id>", "status": "pending" }`
2. Add a `push_reward` action node
3. Call `api_create_manual_purchase_order` with `transaction_source='event_order'`
4. Verify `reward_redemptions_ledger` entry created for the user
