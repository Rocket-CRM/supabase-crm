# Complete CSV Test Guide - All Columns

## Overview

File: `COMPLETE_TEST_ALL_COLUMNS.csv`

**Contains 8 transactions (11 line items) demonstrating ALL supported features:**

---

## Column Reference

### Required Columns (Minimum):
1. `transaction_number` - Unique ID
2. `transaction_date` - ISO timestamp
3. `user_id` OR `user_phone` - User identification
4. `final_amount` - Total transaction amount
5. `sku_id` - Product SKU UUID
6. `quantity` - Primary UOM quantity
7. `unit_price` - Price per unit
8. `line_total` - Line item total

### Optional Columns:
9. `quantity_secondary` - Bulk/secondary UOM (tonnes, pallets, cartons)
10. `discount_amount` - Transaction-level discount
11. `tax_amount` - Transaction-level tax
12. `item_discount_amount` - Line item discount
13. `item_tax_amount` - Line item tax
14. `store_id` - Store location UUID
15. `status` - pending/processing/completed/cancelled/refunded
16. `payment_status` - Payment state
17. `record_type` - credit/debit
18. `processing_method` - queue/direct/skip
19. `earn_currency` - true/false
20. `transaction_source` - Channel (admin/online/mobile/kiosk)
21. `external_ref` - External system reference
22. `notes` - Additional notes

---

## Test Scenarios in CSV:

### Scenario 1: TXN-COMPLETE-001 (2 items)
**Demonstrates:**
- ✅ All fields populated
- ✅ Multiple items per transaction
- ✅ Different Ajinomoto SKUs (250G + 1KG)
- ✅ quantity_secondary (bulk UOM)
- ✅ Item-level discounts and tax
- ✅ Transaction-level discounts

**Data:**
- User: UUID (fe64008f...)
- SKUs: AJI-MSG-001-250G + AJI-MSG-001-1KG
- Total: $450
- Quantities: 10 bags + 5 bags = 2.5 + 1.0 tonnes
- External ref: POS-12345

### Scenario 2: TXN-PHONE-001
**Demonstrates:**
- ✅ **Phone number mapping** (no user_id)
- ✅ Different product (T-shirt)
- ✅ Different source (online/Shopify)

**Data:**
- Phone: +66966564526
- Source: online
- External ref: SHOPIFY-789

### Scenario 3: TXN-B2B-001
**Demonstrates:**
- ✅ **Large B2B bulk order**
- ✅ **High quantity_secondary** (5 tonnes)
- ✅ Should trigger threshold bonuses if configured

**Data:**
- 2,500 bags = 5.0 tonnes
- $125,000 order
- External ref: B2B-CONTRACT-123

### Scenario 4: TXN-DISCOUNT-001
**Demonstrates:**
- ✅ **Complex discounting**
- ✅ Both item and transaction-level discounts
- ✅ Tax handling
- ✅ Phone mapping

**Data:**
- Phone: +66863107599
- Item discount: $40
- Item tax: $10
- Transaction discount: $90
- Final: $270 (from $360 base)

### Scenario 5: TXN-PENDING-001
**Demonstrates:**
- ✅ **Pending status** (not completed)
- ✅ **earn_currency = false** (no currency processing)
- ✅ **processing_method = skip**

**Data:**
- Status: pending
- Should NOT trigger CDC currency processing

### Scenario 6: TXN-REFUND-001
**Demonstrates:**
- ✅ **Refund transaction**
- ✅ **record_type = debit**
- ✅ **status = refunded**
- ✅ Should trigger currency reversal

**Data:**
- Record type: debit
- External ref: REFUND-REF-999

### Scenario 7: TXN-DIRECT-001
**Demonstrates:**
- ✅ **Direct processing** (not queued)
- ✅ Different source (kiosk)

**Data:**
- Processing method: direct
- Source: kiosk

### Scenario 8: TXN-MULTI-ITEM-001 (3 items)
**Demonstrates:**
- ✅ **Complex multi-item transaction**
- ✅ Mixed products (Ajinomoto + T-shirt + other)
- ✅ Mix of bulk and retail quantities
- ✅ Shared transaction-level tax

**Data:**
- 3 different products
- Mixed UOMs
- $1,850 total

---

## Upload Command:

```bash
curl -X POST https://crm-batch-upload.onrender.com/api/import/purchases \
  -F "file=@COMPLETE_TEST_ALL_COLUMNS.csv" \
  -F "merchant_id=09b45463-3812-42fb-9c7f-9d43b6fd3eb9" \
  -F "batch_name=Complete Test - All Columns"
```

---

## Expected Results:

**Imports:**
- ✅ 8 transactions
- ✅ 11 line items
- ✅ Phone mapping: 2 transactions
- ✅ B2B bulk: 1 transaction
- ✅ Total value: ~$130,070

**Currency Processing:**
- ✅ 6 transactions will earn currency (completed + earn_currency=true)
- ❌ 1 will skip (pending status)
- ❌ 1 will skip (earn_currency=false)
- ✅ 1 refund will trigger reversal

---

## Column Value Examples:

| Column | Example Values | Notes |
|--------|----------------|-------|
| transaction_date | 2026-02-01T10:00:00Z | ISO 8601 format |
| user_id | fe64008f-... | UUID or blank if using phone |
| user_phone | +66966564526 | E.164 format with + |
| quantity_secondary | 2.5, 5.0, null | Decimal allowed, optional |
| status | completed, pending, refunded | Must be valid enum |
| record_type | credit, debit | Must be valid enum |
| processing_method | queue, direct, skip | Text field |
| earn_currency | true, false | Boolean |

---

*File ready at: `/Users/rangwan/Documents/Supabase CRM/COMPLETE_TEST_ALL_COLUMNS.csv`*

**This CSV demonstrates every single feature of the bulk import system!** 🎯
