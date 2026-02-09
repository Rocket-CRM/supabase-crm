# Display Settings Translation - Quick Reference

## ✅ Problem Fixed

**Before**: Translation grid was empty when opening display_settings for translation

**After**: Translation grid shows all translatable fields with proper labels

---

## 🎯 What Changed

### New Functions Added
1. **Field Extraction**: Automatically finds all translatable fields in display_settings config
2. **Value Retrieval**: Gets current values from config JSON
3. **Label Formatting**: Converts `group_1.0.header_text` → "Group 1 Item 1 - Header Text"
4. **Entity Type Mapping**: Correctly uses `display_block_item` for storage while showing `display_settings` in UI

### Updated Functions
1. **get_translation_form_data**: Now handles display_settings with dynamic field extraction
2. **save_entity_translations**: Correctly saves with `display_block_item` entity_type
3. **get_translation_entities**: Accurately counts translations for display_settings

---

## 🔧 How to Use

### From Frontend/API

```javascript
// 1. Get translation form (this now works!)
const { data } = await supabase.rpc('translation_api', {
  p_action: 'get_form',
  p_params: {
    entity_type: 'display_settings',
    entity_id: '5364a593-e90b-41d1-998b-a7cc7fc545e4'
  }
});

// data.translations_grid will contain rows like:
// {
//   "field": "group_1.0.header_text",
//   "field_label": "Group 1 Item 1 - Header Text",
//   "th": "ยินดีต้อนรับ",  // default language value
//   "en": "Welcome",        // English translation
//   "ja": "ようこそ",        // Japanese translation
//   "zh": "欢迎"            // Chinese translation
// }

// 2. Save translations
await supabase.rpc('translation_api', {
  p_action: 'save',
  p_params: {
    entity_type: 'display_settings',
    entity_id: '5364a593-e90b-41d1-998b-a7cc7fc545e4',
    translations: data.translations_grid // modified grid
  }
});
```

---

## 📊 Translation Grid Structure

### Fields Detected Automatically

For each item in each group in the display_settings config, the system detects:
- `header_text` - Main heading/title
- `description_text` - Description/body text  
- `button_text` - Button label/CTA text

### Example Config

```json
{
  "group_1": {
    "items": [
      {
        "header_text": "Welcome",
        "description_text": "Get started today",
        "button_text": "Learn More",
        "image": "...",
        "url": "..."
      },
      {
        "header_text": "Featured",
        "description_text": "Check out our offers",
        "button_text": "View All"
      }
    ]
  }
}
```

### Detected Fields

- `group_1.0.header_text` → "Group 1 Item 1 - Header Text"
- `group_1.0.description_text` → "Group 1 Item 1 - Description Text"
- `group_1.0.button_text` → "Group 1 Item 1 - Button Text"
- `group_1.1.header_text` → "Group 1 Item 2 - Header Text"
- `group_1.1.description_text` → "Group 1 Item 2 - Description Text"
- `group_1.1.button_text` → "Group 1 Item 2 - Button Text"

---

## 🗄️ Database Storage

### Where Translations Are Stored

**Table**: `translations`

**Key Points**:
- `entity_type`: `'display_block_item'` (NOT `'display_settings'`)
- `entity_id`: The `display_settings.id`
- `field_name`: Field path like `'group_1.0.header_text'`
- `language_code`: `'en'`, `'ja'`, `'zh'` (not default language 'th')

### Example Record

```sql
merchant_id: 99e456a2-107c-48c5-a12d-2b8b8b85aa2d
entity_type: display_block_item
entity_id: 5364a593-e90b-41d1-998b-a7cc7fc545e4
field_name: group_1.0.header_text
language_code: en
translated_value: Welcome
```

---

## ✨ Features

### ✅ Automatic Field Detection
- No manual configuration needed
- Dynamically reads from display_settings.config
- Supports multiple groups and items

### ✅ User-Friendly Labels
- Converts technical paths to readable labels
- Shows group number, item number, and field name
- Example: "Group 1 Item 1 - Header Text"

### ✅ Full Language Support
- Default language (Thai): Shown from config
- Other languages (EN, JA, ZH): Shown from translations table
- Empty fields show as `null` (not yet translated)

### ✅ Smart Saving
- Only saves non-default languages
- Deletes empty translations (cleanup)
- Upserts existing translations (no duplicates)
- Returns detailed statistics

---

## 🔍 Troubleshooting

### Grid Still Empty?

1. **Check display_settings record exists**:
   ```sql
   SELECT * FROM display_settings WHERE id = 'your-id';
   ```

2. **Check config structure**:
   ```sql
   SELECT config FROM display_settings WHERE id = 'your-id';
   ```
   Should have `group_*` keys with `items` arrays

3. **Test field extraction**:
   ```sql
   SELECT fn_extract_display_settings_translatable_fields(config)
   FROM display_settings WHERE id = 'your-id';
   ```
   Should return array of field paths

### Translations Not Saving?

1. **Check entity_type in database**:
   ```sql
   SELECT entity_type FROM translations 
   WHERE entity_id = 'your-id' LIMIT 1;
   ```
   Should be `'display_block_item'`

2. **Verify merchant_id matches**:
   ```sql
   SELECT merchant_id FROM display_settings WHERE id = 'your-id';
   ```

3. **Check for constraint violations**:
   - Unique constraint: (merchant_id, entity_type, entity_id, field_name, language_code)
   - Ensure no duplicate combinations

---

## 🎓 Technical Notes

### Why Two Entity Types?

- **UI/Navigation**: Uses `'display_settings'` (matches table name)
- **Storage**: Uses `'display_block_item'` (indicates item-level translations)
- **Reason**: Separates display_settings metadata from item content translations
- **Mapping**: Handled automatically by `fn_get_translation_entity_type()`

### Field Path Format

- **Pattern**: `group_{N}.{M}.{field_name}`
- **N**: Group number (1, 2, 3, ...)
- **M**: Item index (0, 1, 2, ...) - zero-based
- **field_name**: One of: header_text, description_text, button_text

### Compatibility

- ✅ Works with existing `fn_build_display_config_with_translations`
- ✅ Compatible with existing display_block_item translations
- ✅ No breaking changes to other translation entity types

---

## 📝 Summary

**Your translation grid is now working!** The system automatically:
1. Detects translatable fields from display_settings config
2. Shows them in a user-friendly grid with proper labels
3. Saves translations correctly with the right entity_type
4. Retrieves and displays existing translations

No manual configuration or migration needed. Just use the translation_api as normal.

---

**Status**: ✅ Complete
**Last Updated**: February 3, 2026
