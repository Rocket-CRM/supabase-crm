# Simplified CSV Format Guide

## ✅ User-Friendly Format (Recommended)

Use **human-readable codes** instead of UUIDs!

### Minimal Required Columns:

```csv
transaction_number,transaction_date,user_phone,final_amount,sku_code,quantity_primary,unit_price,line_total
TXN001,2026-02-01T10:00:00Z,+66966564526,350.00,AJI-MSG-001-250G,7,50.00,350.00
```

**Only 8 columns needed!**

---

## Column Mapping:

| CSV Column | Maps To | Example |
|-----------|---------|---------|
| `sku_code` | `product_sku_master.sku_code` → `sku_id` (UUID) | AJI-MSG-001-250G |
| `store_code` | `store_master.store_code` → `store_id` (UUID) | BKK-EX-001 |
| `user_phone` | `user_accounts.tel` → `user_id` (UUID) | +66966564526 |
| `quantity_primary` | `purchase_items_ledger.quantity` | 10 |
| `quantity_secondary` | `purchase_items_ledger.quantity_secondary` | 2.5 |

---

## All Supported Columns:

### Required (Choose one for user):
- `user_id` (UUID) OR
- `user_phone` (+66xxxxxxxxx)

### Required (Product):
- `transaction_number` - Your transaction ID
- `transaction_date` - ISO timestamp
- `final_amount` - Total amount
- `sku_code` - Product SKU code (human-readable)
- `quantity_primary` - Primary quantity
- `unit_price` - Price per unit
- `line_total` - Line total

### Optional (Recommended):
- `quantity_secondary` - Bulk UOM (for B2B)
- `store_code` - Store location code
- `discount_amount` - Transaction discount
- `tax_amount` - Transaction tax

### Optional (Advanced):
- `item_discount_amount` - Line item discount
- `item_tax_amount` - Line item tax
- `status` - pending/completed/etc
- `payment_status` - paid/pending/etc
- `record_type` - credit/debit
- `processing_method` - queue/direct/skip
- `earn_currency` - true/false
- `transaction_source` - admin/online/mobile
- `external_ref` - External system reference
- `notes` - Additional notes

---

## Advantages of Code-Based Format:

✅ **No need to look up UUIDs** - Use codes you already know  
✅ **Human readable** - Easy to create in Excel/Google Sheets  
✅ **Less error-prone** - Codes are easier to verify  
✅ **Automatic validation** - System checks if codes exist  

---

## Error Messages:

### Invalid SKU Code:
```
"SKU code not found: INVALID-SKU-123"
```

### Invalid Store Code:
```
"Store code not found: INVALID-STORE"
```

### Invalid Phone:
```
"Invalid user_ids found. Expected 3, found 2"
```
(One phone number not found)

---

## Example Upload:

```bash
curl -X POST https://crm-batch-upload.onrender.com/api/import/purchases \
  -F "file=@USER_FRIENDLY_TEMPLATE.csv" \
  -F "merchant_id=09b45463-3812-42fb-9c7f-9d43b6fd3eb9" \
  -F "batch_name=Easy Import"
```

---

## Get Your Codes:

### Get Available SKU Codes:
```sql
SELECT sku_code, id 
FROM product_sku_master 
WHERE merchant_id = 'your-merchant-id' 
ORDER BY sku_code;
```

### Get Available Store Codes:
```sql
SELECT store_code, id 
FROM store_master 
WHERE merchant_id = 'your-merchant-id' 
ORDER BY store_code;
```

### Get User Phones:
```sql
SELECT tel, id 
FROM user_accounts 
WHERE merchant_id = 'your-merchant-id' 
AND tel IS NOT NULL
ORDER BY tel;
```

---

**This is the easiest format for admins to use!** 🎯

No more UUID hunting - just use the codes you know!
