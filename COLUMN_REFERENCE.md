# Bulk Import CSV - Complete Column Reference

## All 23 Supported Columns

| # | Column Name | Required | Type | Example | Notes |
|---|------------|----------|------|---------|-------|
| 1 | `transaction_number` | ✅ Yes | Text | TXN001 | Unique per merchant |
| 2 | `transaction_date` | ✅ Yes | ISO Timestamp | 2026-02-01T10:00:00Z | Must be valid ISO 8601 |
| 3 | `user_id` | ⚠️ One of | UUID | fe64008f-... | User UUID OR use user_phone |
| 4 | `user_phone` | ⚠️ One of | Phone | +66966564526 | E.164 format OR use user_id |
| 5 | `final_amount` | ✅ Yes | Decimal | 350.00 | Total amount customer paid |
| 6 | `sku_id` | ✅ Yes | UUID | 358df89b-... | Product SKU UUID |
| 7 | `quantity` | ✅ Yes | Decimal | 10 | Primary UOM quantity |
| 8 | `quantity_secondary` | ⬜ Optional | Decimal | 2.5 | Bulk/secondary UOM (tonnes, pallets) |
| 9 | `unit_price` | ✅ Yes | Decimal | 50.00 | Price per unit |
| 10 | `line_total` | ✅ Yes | Decimal | 500.00 | Line item total |
| 11 | `discount_amount` | ⬜ Optional | Decimal | 50 | Transaction-level discount |
| 12 | `tax_amount` | ⬜ Optional | Decimal | 35 | Transaction-level tax |
| 13 | `item_discount_amount` | ⬜ Optional | Decimal | 20 | Line item discount |
| 14 | `item_tax_amount` | ⬜ Optional | Decimal | 10 | Line item tax |
| 15 | `store_id` | ⬜ Optional | UUID | null | Store location UUID |
| 16 | `status` | ⬜ Optional | Enum | completed | Default: completed |
| 17 | `payment_status` | ⬜ Optional | Text | paid | Default: paid |
| 18 | `record_type` | ⬜ Optional | Enum | credit | Default: credit (or debit) |
| 19 | `processing_method` | ⬜ Optional | Text | queue | queue/direct/skip |
| 20 | `earn_currency` | ⬜ Optional | Boolean | true | Default: true |
| 21 | `transaction_source` | ⬜ Optional | Text | admin | admin/online/mobile/kiosk |
| 22 | `external_ref` | ⬜ Optional | Text | POS-12345 | External system reference |
| 23 | `notes` | ⬜ Optional | Text | Bulk order | Additional notes |

---

## Valid Enum Values:

### status:
- `pending` - Not finalized
- `processing` - In progress
- `completed` - Finalized (triggers currency) ⭐
- `cancelled` - Aborted
- `refunded` - Reversed

### record_type:
- `credit` - Normal purchase (default)
- `debit` - Refund/reversal

### processing_method:
- `queue` - Async currency calculation (default, recommended)
- `direct` - Immediate currency calculation
- `skip` - No currency processing

---

## User Identification Rules:

**You MUST provide ONE of:**
- `user_id` (UUID) - Direct user lookup
- `user_phone` (E.164) - Phone number lookup

**You CAN provide both:**
- If both provided, `user_id` takes priority
- `user_phone` is ignored if `user_id` exists

**Format validation:**
- user_id: Must be valid UUID
- user_phone: Must match format in database (usually `+66xxxxxxxxx`)

---

## Quantity UOM Fields:

### quantity (Primary UOM):
- **Always required**
- Standard retail units: PIECE, BAG, BOTTLE, KG
- Examples: 10 pieces, 5 bags, 2.5 kg

### quantity_secondary (Secondary UOM):
- **Optional**
- Bulk/wholesale units: TON, PALLET, CARTON, CASE
- Examples: 2.5 tonnes, 3 pallets, 10 cases
- **Required for threshold-based B2B earning rules**

**Example:**
- Cement: 1000 bags (quantity) = 2.5 tonnes (quantity_secondary)
- Steel: 500 pieces (quantity) = 1 tonne (quantity_secondary)

---

## Amount Calculations:

```
Line Item Level:
(quantity × unit_price) - item_discount_amount + item_tax_amount = line_total

Transaction Level:
SUM(all line_totals) - transaction discount_amount + transaction tax_amount = final_amount
```

**Important:** The CSV uses flat structure, so `final_amount`, `discount_amount`, and `tax_amount` are **duplicated** across all line items with the same `transaction_number`.

---

## Special Cases:

### Refund Transaction:
```csv
record_type=debit, status=refunded
```
- Creates reversal in currency
- Negative impact on metrics

### No Currency Processing:
```csv
earn_currency=false
```
OR
```csv
status=pending
```
- No currency calculation
- No wallet updates

### Direct Processing:
```csv
processing_method=direct
```
- Currency calculated immediately (not queued)
- Slower but real-time

---

## File Location:

📁 `/Users/rangwan/Documents/Supabase CRM/COMPLETE_TEST_ALL_COLUMNS.csv`

**Ready to upload and test all features!** 🚀
