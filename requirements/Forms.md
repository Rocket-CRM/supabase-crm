# Forms & User Profile System

## Architecture Overview

Two distinct field systems work together:

| System | Purpose | Storage | Configuration |
|--------|---------|---------|---------------|
| **Default Fields** | Standard user profile fields (email, phone, name, address) | `user_accounts`, `user_address` | `user_field_config` |
| **Custom Fields** | Merchant-defined additional fields | `form_submissions`, `form_responses` | `form_templates` → `form_fields` |

Both systems share the same frontend API and rendering logic.

---

## Default Fields System

### Configuration Table: `user_field_config`

Defines which standard user fields are enabled and how they behave per merchant.

```
user_field_config
├── merchant_id
├── field_key (email, phone, firstname, lastname, fullname, birth_date, id_card, line_id, gender, addressline_1, city, district, subdistrict, postcode, country_code)
├── field_label
├── field_type (normal, email, phone, date, select)
├── placeholder
├── help_text
├── order_index
├── is_required
├── validation_pattern (regex)
├── min_length / max_length
├── validate_format
├── editable_by_user
├── visible_to_user
├── active_status
├── options (JSONB - for select fields like gender)
├── persona_ids (UUID[] - show only for specific personas)
```

### Data Storage

Default field values are stored directly in user tables:

| Field Key | Table | Column |
|-----------|-------|--------|
| email | user_accounts | email |
| phone | user_accounts | tel |
| firstname | user_accounts | firstname |
| lastname | user_accounts | lastname |
| fullname | user_accounts | fullname |
| birth_date | user_accounts | birth_date |
| id_card | user_accounts | id_card |
| line_id | user_accounts | line_id |
| gender | user_accounts | gender |
| addressline_1 | user_address | addressline_1 |
| city | user_address | city |
| district | user_address | district |
| subdistrict | user_address | subdistrict |
| postcode | user_address | postcode |
| country_code | user_address | country_code |

---

## Custom Fields System

### Table Structure

```
form_templates
├── id, merchant_id, code, name, description
├── status (draft, published, archived)
└── created_at, updated_at

form_field_groups
├── id, form_id, group_key, group_name
├── order_index
└── require_at_least_one (group-level validation)

form_fields
├── id, group_id, field_key, label
├── field_type (free_text, single_select, multi_select)
├── text_format (text, email, phone, number, date, multiline)
├── placeholder, help_text
├── order_index, is_required
├── regex_pattern, min_value, max_value
├── min_selections, max_selections
└── persona_ids (UUID[] - show only for specific personas)

form_field_options
├── id, field_id, option_value, option_label
├── is_default, order_index

form_conditions
├── id, form_id
├── source_field_key (the field that triggers)
├── operator (equals, not_equals, contains, is_empty, is_not_empty, greater_than, less_than)
├── compare_value
├── target_field_key (the field affected)
└── action_type (show, hide, enable, disable, require)
```

### USER_PROFILE Form

Special form template with `code = 'USER_PROFILE'` used to store custom profile fields.

- One per merchant
- Must have `status = 'published'` to be active
- Groups organize fields into sections (preferences, demographics, etc.)

### Custom Field Data Storage

```
form_submissions
├── id, form_id, merchant_id, user_id
├── submission_number (legacy, nullable)
├── status, source
└── submitted_at, created_at

form_responses
├── id, submission_id, field_id
├── text_value (for free_text, single_select)
├── array_value (jsonb[] for multi_select)
├── object_value (jsonb for complex data)
└── created_at
```

Each user has one `form_submission` for USER_PROFILE form. Field values stored in `form_responses` linked by `field_id`.

---

## Conditional Field Logic

Conditions enable dynamic form behavior based on user input.

### Condition Components

| Component | Purpose |
|-----------|---------|
| `source_field_key` | Field being monitored |
| `operator` | Comparison logic |
| `compare_value` | Value to match against |
| `target_field_key` | Field whose behavior changes |
| `action_type` | What happens when condition is met |

### Operators

- `equals` / `not_equals` - exact match
- `contains` / `not_contains` - substring
- `greater_than` / `less_than` - numeric
- `is_empty` / `is_not_empty` - presence check

### Action Types

- `show` / `hide` - visibility
- `enable` / `disable` - interactivity
- `require` - make mandatory

### Example

```
source_field_key: "occupation"
operator: "equals"
compare_value: "student"
target_field_key: "income_range"
action_type: "hide"
```

When occupation = "student", hide income_range field.

---

## Cache Structure

### Cache Key Pattern

```
merchant:{merchant_id}:user_profile_template:all_languages
```

### Cached Data Structure

```json
{
  "default_fields_config": [...],
  "custom_fields_config": [...],
  "persona": {
    "merchant_config": { "persona_attain": "pre-form" },
    "persona_groups": [...]
  },
  "consent_config": [...],
  "channels_item": {...},
  "topics_item": {...}
}
```

### Cache Behavior

- TTL: 300 seconds (5 minutes)
- Stored in Redis via `extensions.user_profile_cache_set`
- Structure cached, user values always fetched live
- Cache invalidated when merchant config changes

---

## API Functions

### GET Template

```
POST /rest/v1/rpc/bff_get_user_profile_template

Parameters:
- p_language: "en" | "th" (default: "en")
- p_mode: "new" | "edit" (default: "new")

Headers:
- Authorization: Bearer {jwt}
- x-merchant-id: {uuid} (optional, extracted from JWT if not provided)
```

**Mode Behavior:**

| Mode | Structure | Values |
|------|-----------|--------|
| `new` | From cache | All `null` |
| `edit` | From cache | From database for authenticated user |

**Response Structure:**

```json
{
  "selected_section": null,
  "default_fields_config": [{
    "id": "default-fields-group",
    "group_key": "default_fields",
    "group_name": "ข้อมูลพื้นฐาน",
    "fields": [{
      "id": "uuid",
      "field_key": "email",
      "field_type": "email",
      "label": "Email Address",
      "value": null,
      "options": [],
      "is_required": true,
      "is_address_field": false,
      "persona_ids": null,
      "conditions": []
    }]
  }],
  "custom_fields_config": [{
    "id": "uuid",
    "group_key": "preferences",
    "group_name": "ความสนใจ",
    "fields": [{
      "id": "uuid",
      "field_key": "interests",
      "field_type": "multi-select",
      "label": "สิ่งที่สนใจ",
      "value": null,
      "options": [{
        "id": "uuid",
        "option_value": "fashion",
        "option_label": "แฟชั่น"
      }],
      "conditions": [{
        "source_field_key": "occupation",
        "operator": "equals",
        "compare_value": "student",
        "action_type": "hide"
      }]
    }]
  }],
  "persona": {
    "selected_persona_id": null,
    "merchant_config": { "persona_attain": "pre-form" },
    "persona_groups": [...]
  },
  "pdpa": [{
    "id": "uuid",
    "consent_type": "privacy_policy",
    "interaction_type": "notice",
    "type": "notice",
    "title": "นโยบายความเป็นส่วนตัว",
    "content": "...",
    "isAccepted": false,
    "requires_action": false,
    "is_mandatory": false,
    "options": []
  }, {
    "id": "channels",
    "type": "checkbox_options",
    "title": "ช่องทางการติดต่อ",
    "isAccepted": false,
    "options": [
      { "id": "email", "label": "อีเมล", "selected": false },
      { "id": "sms", "label": "SMS", "selected": false },
      { "id": "line", "label": "LINE", "selected": false },
      { "id": "push", "label": "การแจ้งเตือน", "selected": false }
    ]
  }],
  "mode": "new",
  "cache_hit": true,
  "language": "th",
  "timestamp": "2025-12-07T..."
}
```

### SAVE Profile

```
POST /rest/v1/rpc/bff_save_user_profile

Parameters:
- p_data: Full payload from bff_get_user_profile_template with user-filled values

Headers:
- Authorization: Bearer {jwt}
```

**What it saves:**

| Data | Destination |
|------|-------------|
| Default fields | `user_accounts` (UPSERT) |
| Address fields | `user_address` (UPSERT) |
| `selected_persona_id` | `user_accounts.persona_id` |
| Custom fields | `form_responses` via USER_PROFILE submission |
| Consent acceptance | `user_consent_ledger` |
| Communication channels | `user_accounts.channel_*` flags |
| Communication topics | `user_communication_preferences` |

**Response:**

```json
{
  "success": true,
  "user_id": "uuid",
  "is_new_user": false
}
```

---

## Frontend Integration (WeWeb)

### State Management

Store API response in a WeWeb variable. All handlers modify this variable directly.

```javascript
const state = variables['45691153-f0a5-42fa-ac9a-5729a9853be2'];
```

### Form Field Handler

Handles `default_fields_config`, `custom_fields_config`, and `persona` updates with 5-second debounce.

```javascript
// Parameters: object_type, field_key, group_id, value

const objectType = context.parameters['object_type'];
const fieldKey = context.parameters['field_key'];
const groupId = context.parameters['group_id'];
const valueParam = context.parameters['value'];

const rawValue = valueParam !== undefined && valueParam !== null ? valueParam : event;
const newValue = typeof rawValue === 'object' ? JSON.parse(JSON.stringify(rawValue)) : rawValue;

const debounceKey = `debounce_${fieldKey}`;
const debounceDelay = 5000;

if (window[debounceKey]) {
  clearTimeout(window[debounceKey]);
}

return new Promise((resolve) => {
  window[debounceKey] = setTimeout(() => {
    const target = variables['45691153-f0a5-42fa-ac9a-5729a9853be2'];
    
    if (!target) {
      resolve(null);
      return;
    }

    if (objectType === 'persona') {
      target.persona.selected_persona_id = newValue;
    } 
    else if (objectType === 'custom_fields_config') {
      const group = target.custom_fields_config.find(g => g.id === groupId);
      if (group) {
        const field = group.fields.find(f => f.field_key === fieldKey);
        if (field) field.value = newValue;
      }
    } 
    else if (objectType === 'default_fields_config') {
      for (const group of target.default_fields_config) {
        const field = group.fields.find(f => f.field_key === fieldKey);
        if (field) {
          field.value = newValue;
          break;
        }
      }
    }

    resolve(true);
  }, debounceDelay);
});
```

### PDPA Handler

Handles consent accordion expand/collapse and acceptance toggles.

```javascript
// Parameters: type, action, section_id, option_id

const type = context.parameters['type'];
const action = context.parameters['action'];
const section_id = context.parameters['section_id'];
const option_id = context.parameters['option_id'];

const pdpaState = variables['45691153-f0a5-42fa-ac9a-5729a9853be2'];

// EXPAND: Toggle accordion section
if (action === 'expand') {
  pdpaState.selected_section = (pdpaState.selected_section === section_id) ? null : section_id;
  return pdpaState;
}

// ACCEPT_ALL: Accept all consents and select all options
if (action === 'accept_all') {
  pdpaState.pdpa.forEach(section => {
    section.isAccepted = true;
    if (section.options && section.options.length > 0) {
      section.options.forEach(opt => opt.selected = true);
    }
  });
  return pdpaState;
}

// ACCEPT: Toggle individual consent or option
if (action === 'accept') {
  const sectionIndex = pdpaState.pdpa.findIndex(item => item.id === section_id);
  if (sectionIndex === -1) return pdpaState;
  
  const section = pdpaState.pdpa[sectionIndex];

  if (type === 'notice' || type === 'text_content') {
    // Simple toggle
    section.isAccepted = !section.isAccepted;
  }
  else if (type === 'checkbox_options') {
    if (option_id) {
      // Individual option toggle
      const optionIndex = section.options.findIndex(opt => opt.id === option_id);
      if (optionIndex !== -1) {
        section.options[optionIndex].selected = !section.options[optionIndex].selected;
      }
      // Master checkbox = true only if ALL options selected
      section.isAccepted = section.options.every(opt => opt.selected === true);
    } 
    else {
      // Master checkbox toggle - cascades to all options
      const newValue = !section.isAccepted;
      section.isAccepted = newValue;
      section.options.forEach(opt => opt.selected = newValue);
    }
  }
  
  return pdpaState;
}

return pdpaState;
```

### PDPA Types

| `interaction_type` | `type` | UI Behavior |
|--------------------|--------|-------------|
| `notice` | `notice` | Read-only, no checkbox |
| `optional` | `text_content` | Checkbox, optional |
| `required` | `text_content` | Checkbox, mandatory |
| (channels/topics) | `checkbox_options` | Multiple checkboxes |

---

## Database Schema Summary

```
┌─────────────────────┐      ┌──────────────────────┐
│  user_field_config  │      │    form_templates    │
│  (default fields)   │      │   (custom fields)    │
└─────────────────────┘      └──────────────────────┘
         │                            │
         │                   ┌────────┴────────┐
         │                   │                 │
         ▼              ┌────▼─────┐    ┌──────▼──────┐
┌─────────────────┐    │form_field│    │form_conditions│
│  user_accounts  │    │ _groups  │    └──────────────┘
│  user_address   │    └────┬─────┘
└─────────────────┘         │
                       ┌────▼─────┐
                       │form_fields│
                       └────┬─────┘
                            │
                       ┌────▼──────────┐
                       │form_field_    │
                       │   options     │
                       └───────────────┘

┌─────────────────────┐     ┌─────────────────────┐
│  form_submissions   │────▶│   form_responses    │
│  (one per user)     │     │  (one per field)    │
└─────────────────────┘     └─────────────────────┘
```

---

## Validation

### Field-Level

- `is_required` - mandatory field
- `regex_pattern` - format validation
- `min_value` / `max_value` - range
- `min_selections` / `max_selections` - for multi-select

### Group-Level

- `require_at_least_one` - at least one field in group must be filled

### Conditional

- Conditions can dynamically `require` a field based on other field values
