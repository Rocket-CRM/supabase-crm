# CSV Import Field Name Fix - Summary

## 🔴 Problem Discovered

Users imported with custom field data were showing `"complete_profile_existing"` because the CSV used **incorrect field names** that didn't match the database.

## 🔍 Root Cause

**CSV Column Names (OLD - WRONG):**
```
user_profile_store_code
user_profile_store_name
user_profile_salesman_code
user_profile_salesman_name
```

**Database Custom Field Keys (ACTUAL):**
```
shop_code
shop_name
sales_code
sales_name
display_size
```

**Result:** Data was imported but never saved to custom fields because the field keys didn't match!

## ✅ Solution

Created corrected CSV templates and documentation with proper field names:

**CSV Column Names (NEW - CORRECT):**
```
user_profile_shop_code
user_profile_shop_name
user_profile_sales_code
user_profile_sales_name
user_profile_display_size
```

## 📁 Files Created

1. **`csv-templates/ajinomoto_import_template_CORRECTED.csv`**
   - Ready-to-use CSV template with sample data
   - All field names corrected

2. **`csv-templates/AJINOMOTO_IMPORT_GUIDE.md`**
   - Complete documentation
   - Field requirements by persona
   - Import commands
   - Critical fix notes

3. **`csv-templates/AJINOMOTO_QUICK_REF.txt`**
   - Quick reference card
   - Copy/paste ready commands
   - Field mapping table

4. **`csv-templates/IMPORT_FIELDS_AND_CURL.txt`** (UPDATED)
   - Added warning about merchant-specific field keys
   - Documented old incorrect names to avoid

## 🎯 Persona Requirements

### Wholesaler (ผู้ค้าส่ง) - Required Fields:
- ✅ shop_code
- ✅ shop_name
- ✅ sales_code
- ✅ sales_name

### Retailer (ผู้ค้าปลีก) - Required Fields:
- ✅ shop_code
- ✅ shop_name
- ✅ sales_code
- ✅ sales_name
- ✅ display_size (ADDITIONAL)

## 🔄 Next Steps

1. **Re-import users** using the corrected CSV template
2. **Verify** that custom fields are saved in `form_responses` table
3. **Test authentication** - users should now get `"complete"` status
4. **Update any existing import scripts** to use new field names

## ⚠️ Important Notes

- **Persona is REQUIRED** - Without persona_id, custom fields won't be validated properly
- **Field names are case-sensitive** and must match exactly
- **Use "-" for empty values**, not blank cells
- **Each merchant may have different custom field keys** - always check the database first

## 🎉 Persona Filtering Working Correctly

The persona-aware filtering deployed earlier IS working as expected:
- ✅ Skips fields not relevant to user's persona
- ✅ Only validates fields assigned to user's persona
- ✅ Correctly returns `"complete"` when persona-irrelevant fields are missing
- ❌ Was showing `"complete_profile_existing"` because data never saved (field name mismatch)

Now that field names are corrected, the full system will work end-to-end!

---

**Date:** February 6, 2026  
**Issue:** CSV field name mismatch causing missing custom field data  
**Status:** ✅ Fixed - New templates created  
**Action Required:** Re-import with corrected CSV
