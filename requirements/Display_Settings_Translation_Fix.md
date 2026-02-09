# Display Settings Translation System - Implementation Summary

## Problem

The translation grid was empty when calling `translation_api` with action `get_form` for `entity_type='display_settings'` because:

1. **No translatable fields defined**: `get_entity_type_config()` returned an empty array `[]` for `translatable_fields`
2. **Dynamic field structure**: Display settings use a JSON `config` column with dynamic nested fields like `group_1.items[0].header_text`
3. **Entity type mismatch**: Existing translations used `entity_type='display_block_item'`, but the system was querying for `'display_settings'`

## Solution Implemented

### 1. Helper Function: Extract Translatable Fields

**Function:** `fn_extract_display_settings_translatable_fields(p_config JSONB)`

- **Purpose**: Dynamically extract field paths from display_settings config
- **Input**: Config JSON structure
- **Output**: Array of field paths like `["group_1.0.header_text", "group_1.0.description_text", "group_1.0.button_text"]`
- **Logic**: Loops through all `group_*` keys, finds items arrays, generates field paths for each item

**Example:**
```json
Config: {
  "group_1": {
    "items": [
      {"header_text": "", "description_text": "", "button_text": ""}
    ]
  }
}

Output: [
  "group_1.0.header_text",
  "group_1.0.description_text", 
  "group_1.0.button_text"
]
```

### 2. Helper Function: Get Field Values

**Function:** `fn_get_display_settings_field_value(p_config JSONB, p_field_path TEXT)`

- **Purpose**: Extract the value for a specific field path from config
- **Input**: Config JSON + field path (e.g., `"group_1.0.header_text"`)
- **Output**: The field value from the config
- **Logic**: Parses path into `[group_key, item_index, field_name]` and navigates the JSON

**Example:**
```sql
SELECT fn_get_display_settings_field_value(
  '{"group_1": {"items": [{"header_text": "Welcome"}]}}'::jsonb,
  'group_1.0.header_text'
)
-- Returns: "Welcome"
```

### 3. Helper Function: Format Field Labels

**Function:** `fn_format_display_settings_field_label(p_field_path TEXT)`

- **Purpose**: Convert field paths to human-readable labels
- **Logic**: Transforms `"group_1.0.header_text"` → `"Group 1 Item 1 - Header Text"`
- **Features**: 0-indexed to 1-indexed conversion, proper capitalization

### 4. Helper Function: Entity Type Mapping

**Function:** `fn_get_translation_entity_type(p_entity_type TEXT)`

- **Purpose**: Map UI entity types to translation storage entity types
- **Mapping**: `'display_settings'` → `'display_block_item'`
- **Reason**: Display settings translations are stored as `display_block_item` to distinguish item-level translations from display_settings records

### 5. Updated: get_translation_form_data

**Changes:**
1. Added special case for `entity_type='display_settings'`
2. Dynamically extracts translatable fields from config using helper functions
3. Builds reference_data with field values from config
4. Uses mapped entity_type (`display_block_item`) when querying translations
5. Formats field labels nicely for display

**Result:**
```json
{
  "entity_type": "display_settings",
  "translations_grid": [
    {
      "field": "group_1.0.header_text",
      "field_label": "Group 1 Item 1 - Header Text",
      "th": "",
      "en": "Welcome",
      "ja": "ようこそ",
      "zh": "欢迎"
    },
    {
      "field": "group_1.0.description_text",
      "field_label": "Group 1 Item 1 - Description Text",
      "th": "",
      "en": null,
      "ja": null,
      "zh": null
    },
    {
      "field": "group_1.0.button_text",
      "field_label": "Group 1 Item 1 - Button Text",
      "th": "",
      "en": null,
      "ja": null,
      "zh": null
    }
  ]
}
```

### 6. Updated: save_entity_translations

**Changes:**
1. Uses mapped entity_type (`display_block_item`) when saving translations
2. Correctly stores translations with proper entity_type for compatibility with `fn_build_display_config_with_translations`

### 7. Updated: get_translation_entities

**Changes:**
1. Uses mapped entity_type when counting translations for display_settings
2. Accurately shows translation completion status in the entity list

## Database Schema

### Tables Used

**display_settings**
- `id`: UUID (primary key)
- `merchant_id`: UUID
- `block_type`: Text (e.g., "banner_hero", "navigation")
- `config`: JSONB (contains dynamic structure with translatable fields)

**translations**
- `merchant_id`: UUID
- `entity_type`: Text (`'display_block_item'` for display settings)
- `entity_id`: UUID (references `display_settings.id`)
- `field_name`: Text (field path like `"group_1.0.header_text"`)
- `language_code`: Text ('th', 'en', 'ja', 'zh')
- `translated_value`: Text

## How It Works

### Loading Translation Form

1. User calls `/rest/v1/rpc/translation_api` with:
   ```json
   {
     "p_action": "get_form",
     "p_params": {
       "entity_type": "display_settings",
       "entity_id": "5364a593-e90b-41d1-998b-a7cc7fc545e4"
     }
   }
   ```

2. System:
   - Retrieves display_settings record from database
   - Extracts config JSON
   - Dynamically generates field paths from config structure
   - Queries translations table with `entity_type='display_block_item'`
   - Builds grid with all languages (default + translations)

3. Returns populated translation grid ready for editing

### Saving Translations

1. User submits translations grid via `translation_api` with action `save`

2. System:
   - Maps `entity_type='display_settings'` → `'display_block_item'`
   - Loops through each field in the grid
   - For each non-default language:
     - If value is empty/null → DELETE existing translation
     - If value exists → UPSERT translation
   - Returns summary: inserted, updated, deleted counts

3. Translations are stored in `translations` table with:
   - `entity_type='display_block_item'`
   - `entity_id=display_settings.id`
   - Proper field paths and language codes

## Testing

### Test 1: Retrieve Empty Grid

```sql
SELECT get_translation_form_data(
  'display_settings',
  '5364a593-e90b-41d1-998b-a7cc7fc545e4'::uuid,
  '99e456a2-107c-48c5-a12d-2b8b8b85aa2d'::uuid
);
-- Returns grid with 3 fields, all showing default language values
```

### Test 2: Save Translations

```sql
SELECT save_entity_translations(
  'display_settings',
  '5364a593-e90b-41d1-998b-a7cc7fc545e4'::uuid,
  '99e456a2-107c-48c5-a12d-2b8b8b85aa2d'::uuid,
  '[{
    "field": "group_1.0.header_text",
    "th": "ยินดีต้อนรับ",
    "en": "Welcome",
    "ja": "ようこそ",
    "zh": "欢迎"
  }]'::jsonb
);
-- Returns: {"success": true, "inserted": 3, "updated": 0, "deleted": 0}
```

### Test 3: Retrieve with Translations

```sql
SELECT get_translation_form_data(
  'display_settings',
  '5364a593-e90b-41d1-998b-a7cc7fc545e4'::uuid,
  '99e456a2-107c-48c5-a12d-2b8b8b85aa2d'::uuid
);
-- Returns grid with saved translations populated
```

### Test 4: Verify Storage

```sql
SELECT entity_type, field_name, language_code, translated_value
FROM translations
WHERE entity_id = '5364a593-e90b-41d1-998b-a7cc7fc545e4';
-- Shows entity_type='display_block_item' with correct translations
```

## Functions Created/Updated

### Created (New)
1. `fn_extract_display_settings_translatable_fields(JSONB) → JSONB`
2. `fn_get_display_settings_field_value(JSONB, TEXT) → TEXT`
3. `fn_format_display_settings_field_label(TEXT) → TEXT`
4. `fn_get_translation_entity_type(TEXT) → TEXT`

### Updated (Modified)
1. `get_translation_form_data(TEXT, UUID, UUID) → JSONB`
2. `save_entity_translations(TEXT, UUID, UUID, JSONB) → JSONB`
3. `get_translation_entities(TEXT, UUID) → JSONB`

## Compatibility

### Existing Translation System
- ✅ All changes are **backward compatible**
- ✅ Other entity types (reward, tier, form_field, etc.) continue to work unchanged
- ✅ Uses existing `translations` table schema
- ✅ Follows existing entity_type mapping pattern

### Existing Display Settings
- ✅ Works with existing `display_block_item` translations in database
- ✅ Compatible with `fn_build_display_config_with_translations` (used by frontend)
- ✅ No migration needed for existing data

## Frontend Integration

The translation grid is now populated and ready to use. When calling from your frontend:

```javascript
// Call the translation API
const { data } = await supabase.rpc('translation_api', {
  p_action: 'get_form',
  p_params: {
    entity_type: 'display_settings',
    entity_id: '5364a593-e90b-41d1-998b-a7cc7fc545e4'
  }
});

// data.translations_grid will contain:
// - Field paths (group_1.0.header_text, etc.)
// - Formatted labels (Group 1 Item 1 - Header Text)
// - Values for all languages (th, en, ja, zh)
```

## Edge Cases Handled

1. **Multiple Groups**: If config has `group_1`, `group_2`, etc., all are processed
2. **Multiple Items**: If a group has multiple items in the array, each gets separate fields
3. **Empty Config**: Returns empty grid if config is null or has no groups
4. **Missing Translations**: Shows `null` for languages without translations
5. **Default Language**: Correctly shows values from config for default language (Thai)

## Performance Considerations

- **Field Extraction**: O(n) where n = number of groups × items per group
- **Translation Lookup**: Uses indexed queries on `entity_type + entity_id + field_name + language_code`
- **Save Operations**: Batch upsert/delete with single transaction

## Future Enhancements

Potential improvements:
1. Cache extracted field paths to avoid re-parsing config on every request
2. Validate field paths before saving to prevent invalid references
3. Add support for additional field types beyond `header_text`, `description_text`, `button_text`
4. Bulk translation import/export for display settings

---

**Status**: ✅ Complete and tested
**Date**: February 3, 2026
**Impact**: Translation grid now populates correctly for display_settings entity type
