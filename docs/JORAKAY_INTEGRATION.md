# Jorakay × HubSpot Integration

Supabase Edge Functions that replaced the n8n webhook workflows. They receive events from the **Rewarding backend**, fetch full user data from the **CRM API**, and sync contacts, companies, deals, and line items into **HubSpot**.

---

## Where It Lives

| Item | Value |
|---|---|
| Supabase project | **MCA - play** (`brdzjnbnqoflodlekdmf`) |
| Function: crm_contacts | `https://brdzjnbnqoflodlekdmf.supabase.co/functions/v1/integration_jorakay_crm_contacts` |
| Function: crm_receipts | `https://brdzjnbnqoflodlekdmf.supabase.co/functions/v1/integration_jorakay_crm_receipts` |
| Log table | `integration_jorakay_logs` (same project) |

Secrets stored in Supabase project secrets:
- `JORAKAY_HUBSPOT_TOKEN` — HubSpot Private App token
- `JORAKAY_CRM_API_KEY` — CRM API key (`x-api-key` header)

---

## How the Code Works

Both functions follow the same pattern: **receive → fetch → sync → log**.

### `integration_jorakay_crm_contacts`

Triggered when a user signs up or updates their profile in the Rewarding system.

```
POST { _id: "<crm_internal_id>" }
  1. Validate _id present
  2. GET crm-api/users/{_id}           → resolve full user profile
  3. Search HubSpot contact            → by jorakay_event_code = user_id
  4. Create contact (if not found)     → name, phone, address, province (from custom_fields), line_id
  5. PATCH crm-api/users/{user_id}     → write back HubSpot hs_object_id as reference_id
  6. Search HubSpot company            → by name (skipped if company_name empty/blank)
  7. Create company (if not found)
  8. Associate contact ↔ company
```

CRM `purchase_ledger` rows with `skip_cdc = true` do not fire `trg_jorakay_receipt_webhook` (historical / backfill). Live completed purchases keep posting to this URL.

### `integration_jorakay_crm_receipts`

Triggered when a receipt is approved in the Rewarding system.

```
POST { profile_id, order_code, net, basket_items: [...] }
  1. Validate profile_id present
  2. GET crm-api/users/{profile_id}    → resolve full user profile
  3. Search HubSpot contact            → by jorakay_event_code = user_id
  4. Create contact (if not found)     → minimal: name, phone only
  5. PATCH crm-api reference_id        → fire & forget
  6. Search HubSpot company            → skipped if no company_name
  7. Create company (if not found)
  8. Associate contact ↔ company       → fire & forget, does NOT gate deal creation
  9. Create HubSpot deal               → pipeline 3678552, stage 183511953, amount = net, receipt_number = order_code
 10. Associate contact ↔ deal
 11. Create line items (parallel)      → one per basket_item with product_name, qty, price, sku, brand, category
```

**Key design decisions:**
- Email is omitted if the CRM user has none — HubSpot does not require it
- Province is read from `user.custom_fields.Province[0]` (not `user.state` which is always empty)
- `company_name` is trimmed before use — empty/whitespace strings are treated as no company
- Deal is always created exactly once, regardless of company branch outcome
- Line items are created in parallel via `Promise.allSettled`

---

## How Logging Works

Every function invocation writes one row to `integration_jorakay_logs`:

| Column | Description |
|---|---|
| `id` | UUID |
| `function_name` | `integration_jorakay_crm_contacts` or `integration_jorakay_crm_receipts` |
| `status` | `success` or `error` |
| `duration_ms` | Total wall-clock time for the run |
| `input_payload` | The raw webhook body received |
| `result` | Final output: contactId, dealId, lineItemsCreated etc. |
| `error_message` | Top-level error string if the run failed |
| `steps` | JSONB array — one entry per step with input, output, duration_ms, status |
| `created_at` | Timestamp |

Each step entry in `steps`:
```json
{
  "step": "4_hs_contact_create",
  "status": "ok | skipped | error",
  "input": { "properties": { ... } },
  "output": { "contactId": "123", "hsObjectId": "123" },
  "duration_ms": 429,
  "error": "Error: HS create contact failed: 400 ..."
}
```

### Useful queries

```sql
-- Latest 20 runs
select function_name, status, duration_ms, error_message, created_at
from integration_jorakay_logs
order by created_at desc limit 20;

-- All failed runs with step detail
select id, function_name, error_message, steps, created_at
from integration_jorakay_logs
where status = 'error'
order by created_at desc;

-- Specific run — full step breakdown
select jsonb_array_elements(steps) as step
from integration_jorakay_logs
where id = '<paste-run-id>';

-- Success rate per function
select function_name, status, count(*), round(avg(duration_ms)) as avg_ms
from integration_jorakay_logs
group by function_name, status;
```

---

## Debugging Guide

### Scenario 1 — Data not arriving (nothing in logs)

The function was never called. Check in this order:

1. **Did the Rewarding backend fire the webhook?**
   Check Rewarding backend logs for outbound HTTP calls to the Supabase URLs. Look at the two trigger points:
   - User signup/update: `PUT /api/rewarding/auth/sign-up/member-type-form`
   - Receipt approval: `POST /api/rewarding/approvereceipt/receiptApprove`

2. **Is the webhook URL correct?**
   Both functions use `verify_jwt: false` so no auth header is needed. Confirm the Rewarding backend is posting to:
   - `https://brdzjnbnqoflodlekdmf.supabase.co/functions/v1/integration_jorakay_crm_contacts`
   - `https://brdzjnbnqoflodlekdmf.supabase.co/functions/v1/integration_jorakay_crm_receipts`

3. **Test manually with a known payload:**
   ```bash
   # crm_contacts — paste a real _id from the CRM
   curl -X POST https://brdzjnbnqoflodlekdmf.supabase.co/functions/v1/integration_jorakay_crm_contacts \
     -H "Content-Type: application/json" \
     -d '{"_id": "<paste_crm_user_id>"}'

   # crm_receipts — paste a real profile_id and receipt fields
   curl -X POST https://brdzjnbnqoflodlekdmf.supabase.co/functions/v1/integration_jorakay_crm_receipts \
     -H "Content-Type: application/json" \
     -d '{"profile_id": "<paste_profile_id>", "net": 100, "order_code": "TEST-001", "basket_items": []}'
   ```

   Then check the log table immediately:
   ```sql
   select * from integration_jorakay_logs order by created_at desc limit 1;
   ```

---

### Scenario 2 — Run arrived but failed (status = 'error')

1. Find the failed run:
   ```sql
   select id, function_name, error_message, steps, created_at
   from integration_jorakay_logs
   where status = 'error'
   order by created_at desc limit 5;
   ```

2. Look at `error_message` for the top-level failure.

3. Drill into `steps` to find which step failed and what input/output it had:
   ```sql
   select jsonb_array_elements(steps) as step
   from integration_jorakay_logs
   where id = '<run-id>';
   ```

4. Common failures and fixes:

   | Error | Cause | Fix |
   |---|---|---|
   | `CRM get user failed: 401` | `JORAKAY_CRM_API_KEY` secret missing or wrong | Re-set secret via Supabase dashboard |
   | `HS search contact failed: 401` | `JORAKAY_HUBSPOT_TOKEN` secret missing or expired | Regenerate HubSpot Private App token |
   | `HS create contact failed: 400 VALIDATION_ERROR` | A property value is invalid or the custom property doesn't exist in HubSpot | Check `input.properties` in the step log — the HubSpot error message names the exact field |
   | `Missing _id in payload` | Rewarding backend sent wrong body shape | Check step `1_validate_payload` input to see what was actually received |
   | `Missing profile_id in payload` | Same — wrong body shape from caller | Same as above |

---

### Scenario 3 — User pastes a receipt/contact case and wants to trace it

If someone reports "receipt X didn't sync to HubSpot":

1. Find the run by order_code:
   ```sql
   select id, status, error_message, result, steps, created_at
   from integration_jorakay_logs
   where function_name = 'integration_jorakay_crm_receipts'
     and input_payload->>'order_code' = '<order_code>';
   ```

2. If found: look at `status`, `result`, and `steps` to see exactly which step succeeded or failed.

3. If NOT found: the webhook was never received. Go back to Scenario 1.

4. For a user/contact case, search by their CRM `_id` or by `user_id` embedded in the step logs:
   ```sql
   select id, status, steps, created_at
   from integration_jorakay_logs
   where function_name = 'integration_jorakay_crm_contacts'
     and input_payload->>'_id' = '<crm_internal_id>';
   ```

5. To see what the CRM returned for a specific user (step 2 output):
   ```sql
   select step->>'output' as crm_user
   from integration_jorakay_logs,
        jsonb_array_elements(steps) as step
   where id = '<run-id>'
     and step->>'step' = '2_crm_user_fetch';
   ```

---

## Known Issues Fixed vs n8n

| n8n Bug | Status in Edge Functions |
|---|---|
| Company search sent empty `name` → HubSpot 400 VALIDATION_ERROR | Fixed — `company_name` is trimmed and skipped if blank |
| Missing/invalid contact fields (email fallback rejected, province empty) | Fixed — email omitted when blank; province read from `custom_fields.Province[0]` |
| Receipt workflow created 2 deals when company branch triggered both paths | Fixed — deal creation is unconditional, runs once after all company logic |
