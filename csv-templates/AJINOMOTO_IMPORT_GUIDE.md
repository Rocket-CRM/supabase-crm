# Ajinomoto Customer Import Template - CORRECTED FIELD NAMES

## 📋 CSV Column Reference

### ✅ CORRECTED Custom Field Names (for Ajinomoto)

**OLD (WRONG):**
- ❌ `user_profile_store_code`
- ❌ `user_profile_store_name`
- ❌ `user_profile_salesman_code`
- ❌ `user_profile_salesman_name`

**NEW (CORRECT):**
- ✅ `user_profile_shop_code`
- ✅ `user_profile_shop_name`
- ✅ `user_profile_sales_code`
- ✅ `user_profile_sales_name`
- ✅ `user_profile_display_size`

---

## 📝 All Available Columns

### REQUIRED (at least one):
- `user_accounts_tel` - Phone with country code (e.g. +66812345678)
- `user_accounts_line_id` - LINE ID (alternative identifier)

### BASIC INFO:
- `user_accounts_firstname` - First name
- `user_accounts_lastname` - Last name
- `user_accounts_fullname` - Full name
- `user_accounts_email` - Email address
- `user_accounts_birth_date` - Birth date (format: DD-MM-YYYY, e.g. 15-03-1985)
- `user_accounts_gender` - Gender (male/female/other)

### PERSONA & TIER:
- `user_accounts_persona_id` - UUID from persona_master
  - Wholesaler (ผู้ค้าส่ง): `5f1aa0fb-3e2b-4c60-9bd4-5f7e8a5374cd`
  - Retailer (ผู้ค้าปลีก): `ff432547-e7ec-46e8-ba95-f0e5cb79d661`
- `user_accounts_user_type` - "buyer" or "seller"
- `user_accounts_tier_id` - UUID from tier_master

### CONTACT PREFERENCES:
- `user_accounts_channel_email` - true/false (can contact via email)
- `user_accounts_channel_sms` - true/false (can contact via SMS)
- `user_accounts_channel_line` - true/false (can contact via LINE)
- `user_accounts_channel_push` - true/false (can send push notifications)

### ADDRESS:
- `user_address_addressline_1` - Street address
- `user_address_subdistrict` - Subdistrict/Tambon
- `user_address_district` - District/Amphoe
- `user_address_city` - City/Province
- `user_address_postcode` - Postal code

### WALLET:
- `user_wallet_points_balance` - Initial points balance (integer)

### CUSTOM FIELDS (Ajinomoto Specific):

**For Both Wholesaler & Retailer:**
- `user_profile_shop_name` - ชื่อร้านค้า (REQUIRED)
- `user_profile_shop_code` - รหัสร้านค้า (REQUIRED)
- `user_profile_sales_code` - รหัสพนักงานขาย (REQUIRED)
- `user_profile_sales_name` - ชื่อพนักงานขาย (REQUIRED)

**For Retailer Only:**
- `user_profile_display_size` - ขนาดการแสดงผล (REQUIRED for Retailer)
  - Options: small, medium, large (or whatever values are configured)

---

## 📊 Field Requirements by Persona

### Persona: Wholesaler (ผู้ค้าส่ง) - `5f1aa0fb-3e2b-4c60-9bd4-5f7e8a5374cd`
**Required Custom Fields:**
- ✅ `user_profile_shop_name`
- ✅ `user_profile_shop_code`
- ✅ `user_profile_sales_code`
- ✅ `user_profile_sales_name`

### Persona: Retailer (ผู้ค้าปลีก) - `ff432547-e7ec-46e8-ba95-f0e5cb79d661`
**Required Custom Fields:**
- ✅ `user_profile_shop_name`
- ✅ `user_profile_shop_code`
- ✅ `user_profile_sales_code`
- ✅ `user_profile_sales_name`
- ✅ `user_profile_display_size` (ADDITIONAL requirement for Retailer only)

---

## 🔧 Import Command

```bash
curl -X POST "https://crm-batch-upload.onrender.com/api/import/customers" \
  -F "file=@csv-templates/ajinomoto_import_template_CORRECTED.csv" \
  -F "merchant_id=99e456a2-107c-48c5-a12d-2b8b8b85aa2d" \
  -F "batch_name=Ajinomoto Customer Import - Corrected Fields" \
  -F "create_wallet_ledger_entry=true"
```

---

## 📌 Important Notes

1. **Use "-" for empty/null values** (not blank cells)
2. **Date format:** DD-MM-YYYY (e.g. 15-03-1985)
3. **Phone format:** Must include country code (+66...)
4. **Boolean values:** true/false (lowercase)
5. **Persona is REQUIRED** - Every user must have a persona_id for custom fields to work properly
6. **Email must be unique** per merchant (use "-" if no email)

---

## ⚠️ Critical Fix Applied

This template fixes the field naming mismatch that was causing imported data to NOT appear in user profiles:

| Old Column Name (WRONG) | New Column Name (CORRECT) |
|-------------------------|---------------------------|
| user_profile_store_code | user_profile_shop_code |
| user_profile_store_name | user_profile_shop_name |
| user_profile_salesman_code | user_profile_sales_code |
| user_profile_salesman_name | user_profile_sales_name |

**Files Updated:**
- Created: `ajinomoto_import_template_CORRECTED.csv`
- Documentation: This file

**Date:** February 6, 2026
