# Forms & User Profile System

## Architecture Overview

Two distinct field systems work together:


| System             | Purpose                                                    | Storage                              | Configuration                    |
| ------------------ | ---------------------------------------------------------- | ------------------------------------ | -------------------------------- |
| **Default Fields** | Standard user profile fields (email, phone, name, address) | `user_accounts`, `user_address`      | `user_field_config`              |
| **Custom Fields**  | Merchant-defined additional fields                         | `form_submissions`, `form_responses` | `form_templates` → `form_fields` |


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


| Field Key     | Table         | Column        |
| ------------- | ------------- | ------------- |
| email         | user_accounts | email         |
| phone         | user_accounts | tel           |
| firstname     | user_accounts | firstname     |
| lastname      | user_accounts | lastname      |
| fullname      | user_accounts | fullname      |
| birth_date    | user_accounts | birth_date    |
| id_card       | user_accounts | id_card       |
| id_document_type | user_accounts | id_document_type |
| line_id       | user_accounts | line_id       |
| gender        | user_accounts | gender        |
| addressline_1 | user_address  | addressline_1 |
| city          | user_address  | city          |
| district      | user_address  | district      |
| subdistrict   | user_address  | subdistrict   |
| postcode      | user_address  | postcode      |
| country_code  | user_address  | country_code  |

### ID Card / Passport (`id_card`)

One default field stores the identity **number** on `user_accounts.id_card`. Document **type** is stored separately on `user_accounts.id_document_type` (`thai_national_id` | `passport`; legacy `other` may exist from an old backfill).

**Merchant config** on `user_field_config.config` for `field_key = id_card`:

| Key | Values | Default |
|---|---|---|
| `id_document_mode` | `id_only` \| `passport_only` \| `both` | `id_only` (legacy `allow_passport: true` → `both`) |
| `enforce_unique_id_document` | boolean | `true` |

`bff_get_user_profile_template` and `bff_admin_get_user_profile_config` return **enriched** config via `fn_enrich_user_field_config` so `id_document_mode` / uniqueness are always present for FE.

**Write-time rules** (`fn_prepare_id_document` + `BEFORE INSERT/UPDATE OF id_card, id_document_type` trigger on `user_accounts`):

- Type is **not** inferred from digit shape for validation.
- `id_only` → force `thai_national_id`; validate 13-digit Thai ID + checksum; normalize by stripping spaces/hyphens.
- `passport_only` → force `passport`; light alphanumeric length rules (5–20).
- `both` → require explicit `id_document_type` (`thai_national_id` or `passport`); validate by that type.
- Clearing `id_card` clears `id_document_type`.
- When uniqueness is on: reject another active member in the same merchant with the same normalized number (`ID_DOCUMENT_DUPLICATE`). No DB unique index yet (~1k legacy duplicate groups); enforcement is application-level.

Error prefix: `ID_DOCUMENT:<code>:<message>` with codes `ID_DOCUMENT_INVALID`, `ID_DOCUMENT_TYPE_REQUIRED`, `ID_DOCUMENT_TYPE_NOT_ALLOWED`, `ID_DOCUMENT_DUPLICATE`. `bff_save_user_profile` / admin create+update map these to `{ success:false, data.error_code, data.field_key:'id_card' }`.

Callers pass type via chokepoint `p_changes.id_document_type`, profile field property `id_document_type` on the `id_card` field object, or `bff_admin_create_member(p_id_document_type)`.

---

## Custom Fields System

### Table Structure

```
form_templates
├── id, merchant_id, code, name, description
├── banner_url (optional survey header image; null/blank hides the member header)
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

### User Profile Template RPCs

`bff_get_user_profile_template(p_mode text, p_language text, p_merchant_code text, p_event_code text, p_selected_persona_id uuid)` returns the frontend profile form template.

`fn_apply_user_profile_edit_overlay(p_extracted_data jsonb, p_merchant_id uuid)` overlays the current user's saved default-field, custom-field, and PDPA values when `p_mode = 'edit'`. It resolves the member via `auth.uid()` against `user_accounts.auth_user_id` or `user_accounts.id` (the member JWT `sub` is `user_accounts.id`). On `id_card`, it also sets the `id_document_type` sibling from `user_accounts.id_document_type`. Empty profile sections must remain JSON arrays (`[]`), not SQL `NULL`, so all `jsonb_agg` overlay results are wrapped with `COALESCE(..., '[]'::jsonb)`.

### Custom Field Data Storage

```
form_submissions
├── id, form_id, merchant_id, user_id
├── submission_number (legacy, nullable)
├── status, source
├── submitted_at, created_at
└── skip_cdc (boolean, default false; true excludes the row from CDC/Kafka)

form_responses
├── id, submission_id, field_id
├── text_value (for free_text, single_select)
├── array_value (jsonb[] for multi_select)
├── object_value (jsonb for complex data)
└── created_at
```

Each user has one `form_submission` for USER_PROFILE form. Field values stored in `form_responses` linked by `field_id`.

---

## Survey Completion Rewards

Survey/form templates may offer a completion reward: when an identified user completes a form, the system awards points or tickets.

### Configuration

The survey page owns the marketer-facing configuration. Marketers should not configure this reward through the AMP workflow builder.

Required fields:


| Field            | Purpose                                 |
| ---------------- | --------------------------------------- |
| `enabled`        | Whether the completion reward is active |
| `currency`       | `points` or `ticket`                    |
| `amount`         | Positive integer amount to award        |
| `ticket_type_id` | Required when `currency = ticket`       |
| `frequency`      | `once` or `every`                       |


Frequency rules:

- `once`: award only once per user per form.
- `every`: award once per completed form submission.

Rewarded submissions must have a resolved `user_id`. Anonymous submissions can be stored, but cannot receive wallet currency until linked to a user.

### Backend Workflow Model

The backend creates and manages one hidden AMP system workflow per rewarded form.

Workflow requirements:

- `workflow_master.scope = 'system'`
- `workflow_master.domain = 'forms'` or `survey`
- Stable workflow code, for example `system_survey_reward:{form_id}`
- One active trigger on `form_submissions`
- One action node that awards currency

System workflows are internal implementation details. Normal marketer workflow lists must filter to user-visible workflows, e.g. `scope = 'user'`.

### Backend APIs

`bff_get_form_reward_workflow_config(p_form_id uuid)` loads the current survey completion reward config for the survey/form settings page.

Response data:

- `form_id`
- `workflow_id`
- `workflow_code` when configured
- `config.enabled`
- `config.currency`
- `config.amount`
- `config.ticket_type_id`
- `config.frequency`

`bff_upsert_form_reward_workflow(p_form_id uuid, p_config jsonb)` creates, updates, or disables the hidden system workflow.

Input config:

```json
{
  "enabled": true,
  "currency": "points",
  "amount": 100,
  "ticket_type_id": null,
  "frequency": "once"
}
```

Validation rules:

- Merchant is resolved from admin auth with `get_current_merchant_id()`.
- `form_id` must belong to the current merchant.
- `currency` must be `points` or `ticket`.
- `frequency` must be `once` or `every`.
- `amount` must be greater than zero when enabled.
- `ticket_type_id` is required when `currency = ticket` and must point to an active ticket type for the merchant.

When disabled, the backend keeps the deterministic workflow code but sets the system workflow and trigger inactive.

The save API supports partial updates. If the page sends only `{ "enabled": false }`, the backend disables the workflow while preserving existing `currency`, `amount`, `ticket_type_id`, and `frequency` in workflow config.

### User Survey APIs

`bff_user_get_surveys(p_language text)` returns published survey forms for the current merchant.

Response data:

- `surveys[]`
- `surveys[].id`
- `surveys[].code`
- `surveys[].name`
- `surveys[].description`
- `surveys[].banner_url`
- `surveys[].field_count`
- `surveys[].reward_preview`
- `surveys[].user_state`

`bff_user_get_survey_details(p_form_identifier text, p_language text)` returns one published survey form by UUID or code.

Response data includes the existing user form detail shape from `bff_get_form_details_user` (`form` includes `banner_url`), plus:

- `reward_preview`
- `user_state`

A survey header banner is optional. Admin sets `form_templates.banner_url` on the survey settings page (`bff_get_form_details` / `bff_upsert_form`). The member app shows that image at the top of the survey and hides the banner section when `banner_url` is null or blank.

`bff_user_submit_survey(p_form_id uuid, p_submission_data jsonb, p_source text, p_source_id text, p_ref_userid text, p_tel text)` submits one published survey.

Submission data must be a JSON object keyed by `form_fields.field_key`. The function resolves the current user account from user auth/header context when available, delegates validation and response storage to `submit_form_public`, and returns:

- `submission_id`
- `form_id`
- `submitted_at`
- `reward_outcome`

Reward outcome statuses:

- `not_configured`: no active completion reward exists.
- `not_eligible_unidentified_user`: survey was stored, but the reward requires a resolved user account.
- `not_eligible_already_completed`: reward frequency is `once` and the user already completed the survey.
- `eligible_pending_processing`: survey was stored and the configured reward workflow should process the reward asynchronously.

`fn_get_survey_reward_preview(p_form_id uuid, p_merchant_id uuid)` is the shared internal helper used by the user-facing survey APIs. It reads `workflow_master.workflow_code = 'system_survey_reward:{form_id}'` and returns normalized display fields: `enabled`, `status`, `currency`, `currency_label`, `amount`, `ticket_type_id`, `ticket_name`, `frequency`, and `display_text`.

### Trigger Event

Completed form submissions enter the event-driven system through CDC:

```text
form_submissions INSERT
→ crm.public.form_submissions Kafka topic
→ crm-event-processors AmpConsumer
→ dispatch-workflow-trigger
→ Inngest AMP workflow execution
```

System workflow trigger:

```json
{
  "trigger_table": "form_submissions",
  "trigger_operation": "INSERT",
  "trigger_conditions": {
    "form_id": "<form_id>",
    "status": "completed"
  }
}
```

The consumer dispatch payload includes `form_id`, `status`, `source`, `source_id`, and `submitted_at` in `record_data`.

### Idempotency

Wallet posting must pass an explicit dedup key because CDC/Kafka/Inngest can replay events.

Required dedup keys:

- `once`: `survey_reward:{form_id}:{user_id}`
- `every`: `survey_reward:{form_id}:{submission_id}:{user_id}`

The final wallet write must still go through `chokepoint_post_wallet_transaction`, using `source_type = 'amp'`.

`fn_execute_amp_action` accepts `dedup_key` inside AMP action params and passes it to `chokepoint_post_wallet_transaction` for `award_points`, `award_tickets`, and `award_currency`.

### Survey analytics report

Native Analytics report at `/reports/surveys` (menu `report-surveys`, Marketing & growth). Completions, unique members, time series, and per-question answer breakdowns for `form_category = 'survey'`. RPC: `bff_report_surveys`. Config stays on `/survey`. Do not wire the Metabase `Forms & surveys` placeholder.

### Survey Config Page Prompt

Use this prompt when implementing the survey/form admin page:

```text
Add a Completion Reward section to the survey/form settings page.

Backend RPCs:
- Load: bff_get_form_reward_workflow_config(p_form_id)
- Save: bff_upsert_form_reward_workflow(p_form_id, p_config)

UI fields:
- Enable completion reward toggle
- Currency selector: points or ticket
- Amount numeric input, integer > 0 when enabled
- Ticket type selector, shown and required only when currency = ticket
- Frequency selector:
  - once: award only once per user for this form
  - every: award on every completed submission

Behavior:
- On page load, call bff_get_form_reward_workflow_config and hydrate defaults.
- On save, include the reward config in bff_upsert_form_reward_workflow.
- Do not expose or link to the hidden AMP workflow.
- Show validation errors from the RPC directly.
- For disabled rewards, save { enabled: false } and keep other fields locally editable.
- Disabled saves preserve the existing backend config, so re-enabling can restore the prior currency, amount, ticket type, and frequency.

Expected save payload:
{
  "enabled": true,
  "currency": "ticket",
  "amount": 1,
  "ticket_type_id": "<ticket_type_id>",
  "frequency": "every"
}
```

---

## Conditional Field Logic

Conditions enable dynamic form behavior based on user input.

### Condition Components


| Component          | Purpose                            |
| ------------------ | ---------------------------------- |
| `source_field_key` | Field being monitored              |
| `operator`         | Comparison logic                   |
| `compare_value`    | Value to match against             |
| `target_field_key` | Field whose behavior changes       |
| `action_type`      | What happens when condition is met |


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


| Mode   | Structure  | Values                               |
| ------ | ---------- | ------------------------------------ |
| `new`  | From cache | All `null`                           |
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


| Data                   | Destination                                  |
| ---------------------- | -------------------------------------------- |
| Default fields         | `user_accounts` (UPSERT)                     |
| Address fields         | `user_address` (UPSERT)                      |
| `selected_persona_id`  | `user_accounts.persona_id`                   |
| Custom fields          | `form_responses` via USER_PROFILE submission |
| Consent acceptance     | `user_consent_ledger`                        |
| Communication channels | `user_accounts.channel`_* flags              |
| Communication topics   | `user_communication_preferences`             |


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


| `interaction_type` | `type`             | UI Behavior            |
| ------------------ | ------------------ | ---------------------- |
| `notice`           | `notice`           | Read-only, no checkbox |
| `optional`         | `text_content`     | Checkbox, optional     |
| `required`         | `text_content`     | Checkbox, mandatory    |
| (channels/topics)  | `checkbox_options` | Multiple checkboxes    |


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

---

## Survey Submission Limits

Survey forms (non-USER_PROFILE) support per-user and total submission limits via the shared `transaction_limits` infrastructure.

### How it works

- `transaction_limits` rows with `entity_type = 'form'` and `entity_id = <form_template UUID>` define limits
- `scope = 'user'` → per-user limit; `scope = 'total'` → global cap across all users
- `time_unit` options: `day`, `week`, `month`, `year`, `all_time`
- `count` = maximum allowed submissions within the time window

### Enforcement

`submit_form_public` calls `fn_check_form_submission_limits(p_user_id, p_form_id, p_merchant_id)` before accepting a submission. Limits are skipped for:

- USER_PROFILE forms (always unlimited)
- Anonymous submissions (`p_user_id IS NULL`) — per-user limits cannot apply without an identified user

### Error response when limit exceeded

```json
{
  "success": false,
  "title": "Submission limit reached",
  "description": "You have reached the maximum of 3 submissions per month for this form",
  "data": {
    "error_code": "FORM_LIMIT_EXCEEDED",
    "limit_scope": "user",
    "limit_time_unit": "month",
    "current_count": 3,
    "max_allowed": 3,
    "next_available_at": "2026-05-01T00:00:00Z"
  }
}
```

### Functions


| Function                          | Type    | Purpose                                                                                        |
| --------------------------------- | ------- | ---------------------------------------------------------------------------------------------- |
| `fn_check_form_submission_limits` | Backend | Check per-user/total submission limits against `transaction_limits` where `entity_type='form'` |
| `submit_form_public`              | API     | Submit survey form — now enforces limits before validation and insert                          |


