# Bulk Import CSV Format Guide

## Overview

The bulk import system supports multiple CSV formats depending on your needs:

1. **Simple Format** - User ID + basic fields
2. **Phone Mapping** - Use phone numbers instead of user IDs
3. **B2B/Bulk Format** - Includes secondary UOM for bulk purchases

---

## Format 1: Simple (Minimal Required Fields)

**Use when:** You have user_ids and standard retail quantities

### Required Columns:
- `transaction_number` - Unique ID per transaction
- `transaction_date` - ISO timestamp (YYYY-MM-DDTHH:MM:SSZ)
- `user_id` - UUID of user
- `final_amount` - Total transaction amount
- `sku_id` - Product SKU UUID
- `quantity` - Item quantity (primary UOM)
- `unit_price` - Price per unit
- `line_total` - Line item total

### Example:

```csv
transaction_number,transaction_date,user_id,final_amount,sku_id,quantity,unit_price,line_total
TXN001,2026-01-15T10:00:00Z,fe64008f-3ce6-49ce-b707-fae1316b9a64,350.00,37158166-383d-4456-8cf0-e367e5d69d5e,2,120.00,240.00
TXN001,2026-01-15T10:00:00Z,fe64008f-3ce6-49ce-b707-fae1316b9a64,350.00,5b0fa2e1-9913-4d3c-9e5e-454e8fa349f7,1,110.00,110.00
```

**File:** `csv-templates/simple_template.csv`

---

## Format 2: Phone Number Mapping

**Use when:** You have phone numbers but not user_ids

### Use `user_phone` Instead of `user_id`:

```csv
transaction_number,transaction_date,user_phone,final_amount,sku_id,quantity,unit_price,line_total
TXN001,2026-01-15T10:00:00Z,+66966564526,350.00,37158166-383d-4456-8cf0-e367e5d69d5e,2,120.00,240.00
```

### Phone Format Rules:

✅ **Correct formats:**
- `+66966564526` - E.164 with country code (RECOMMENDED)
- `+66 96 656 4526` - With spaces (system will match)
- `0966564526` - Local format (if stored that way)

❌ **Will NOT match:**
- `66966564526` - Missing +
- `966564526` - Missing country code
- Different formatting than stored in database

### How It Works:

1. System looks up phone number in `user_accounts.tel`
2. Finds matching user_id for that merchant
3. Uses user_id for the import
4. **Fails if phone number not found**

**File:** `csv-templates/phone_mapping_template.csv`

---

## Format 3: B2B/Bulk with Secondary UOM

**Use when:** You have bulk purchases with dual quantity tracking

### Includes `quantity_secondary`:

```csv
transaction_number,transaction_date,user_id,final_amount,sku_id,quantity,quantity_secondary,unit_price,line_total,notes
BULK001,2026-01-15T10:00:00Z,fe64008f-3ce6-49ce-b707-fae1316b9a64,50000.00,37158166-383d-4456-8cf0-e367e5d69d5e,1000,2.5,50.00,50000.00,1000 bags = 2.5 tonnes
```

### When to Use Secondary UOM:

- **B2B scenarios:** "Buy ≥2 tonnes of steel"
- **Bulk thresholds:** "Purchase ≥50 cartons for bonus"
- **Wholesale:** Track both pieces AND pallets

### Example Mappings:

| Product | Primary UOM | Secondary UOM | Example |
|---------|-------------|---------------|---------|
| Cement | BAG | TON | 1000 bags = 2.5 tonnes |
| Beer | BOTTLE | CASE | 24 bottles = 1 case |
| Rice | KG | TON | 1000 kg = 1 tonne |
| Snacks | PIECE | CARTON | 48 pieces = 1 carton |

**File:** `csv-templates/bulk_b2b_template.csv`

---

## All Optional Fields

| Column | Type | Default | Description |
|--------|------|---------|-------------|
| `discount_amount` | number | 0 | Transaction-level discount |
| `tax_amount` | number | 0 | Transaction-level tax |
| `item_discount_amount` | number | 0 | Line item discount |
| `item_tax_amount` | number | 0 | Line item tax |
| `store_id` | UUID | null | Store location |
| `status` | enum | completed | pending/processing/completed/cancelled/refunded |
| `payment_status` | text | paid | Payment state |
| `record_type` | enum | credit | credit/debit |
| `processing_method` | text | queue | queue/direct/skip |
| `earn_currency` | boolean | true | Award currency? |
| `transaction_source` | text | admin | Channel identifier |
| `external_ref` | text | null | External system reference |
| `notes` | text | null | Additional notes |
| `quantity_secondary` | number | null | Bulk/secondary UOM quantity |

---

## Phone Number Validation

### Stored Format in Database:

```
+66966564526
+66863107599
+66631158652
```

**Format:** E.164 international format (`+[country][number]`)

### Validation Rules:

1. ✅ Must start with `+`
2. ✅ Must match exactly what's stored in `user_accounts.tel`
3. ✅ Case-sensitive (though numbers aren't affected)
4. ❌ Fails if phone not found for merchant

### To Get User Phones:

```sql
SELECT id, tel FROM user_accounts 
WHERE merchant_id = 'your-merchant-id';
```

---

## Upload Examples

### With User ID:
```bash
curl -X POST https://crm-batch-upload.onrender.com/api/import/purchases \
  -F "file=@purchases-with-userid.csv" \
  -F "merchant_id=09b45463-3812-42fb-9c7f-9d43b6fd3eb9" \
  -F "batch_name=January Import"
```

### With Phone Number:
```bash
curl -X POST https://crm-batch-upload.onrender.com/api/import/purchases \
  -F "file=@purchases-with-phone.csv" \
  -F "merchant_id=09b45463-3812-42fb-9c7f-9d43b6fd3eb9" \
  -F "batch_name=Phone-based Import"
```

### With Bulk/B2B Quantities:
```bash
curl -X POST https://crm-batch-upload.onrender.com/api/import/purchases \
  -F "file=@bulk-purchases.csv" \
  -F "merchant_id=09b45463-3812-42fb-9c7f-9d43b6fd3eb9" \
  -F "batch_name=Wholesale Orders"
```

---

## Error Handling

### Invalid Phone Number:
```json
{
  "status": "failed",
  "error_message": "Invalid user_ids found. Expected 5, found 3"
}
```
**Reason:** 2 phone numbers not found in database

### Missing Both user_id AND user_phone:
```json
{
  "status": "failed",
  "error_message": "No valid user_ids found. Check user_id or user_phone columns."
}
```

---

## Best Practices

1. **Use user_id when possible** - Faster, no lookup needed
2. **Use user_phone for external data** - When you only have phone numbers
3. **Always include quantity_secondary for B2B** - Required for threshold-based currency rules
4. **Verify phone format matches database** - Export sample to check format
5. **Test with small batch first** - Validate your CSV structure

---

*Templates available in: `/Users/rangwan/Documents/Supabase CRM/csv-templates/`*
