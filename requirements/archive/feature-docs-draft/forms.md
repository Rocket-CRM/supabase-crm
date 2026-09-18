# Feature Guide: Forms

## 1. Overview

Forms control what data the platform collects from members — during signup and on their profile page. Two distinct systems work together: **default fields** for standard profile data (name, email, phone, address) and **custom fields** for merchant-defined questions (interests, occupation, preferences). Both appear as a single unified form to the member, but are stored and configured separately.

Default fields map directly to columns in `user_accounts` and `user_address`. Custom fields live in a flexible schema: merchants create a `USER_PROFILE` form template, organize fields into groups, and the system stores responses in `form_submissions` and `form_responses`. This separation means merchants can extend the profile without schema changes — they add fields through the admin UI, and those fields appear on the next signup.

The form system also handles PDPA consent collection (privacy notices, marketing opt-ins, communication channel preferences) and supports persona-aware field filtering — different member types can see different fields. Conditional logic lets fields show, hide, or become required based on other field values, enabling dynamic forms without code.

## 2. Key Concepts

**Default Field** — A standard profile field backed by a real database column (e.g., `email` in `user_accounts`, `city` in `user_address`). Configured per-merchant via `user_field_config` with settings for visibility, editability, validation, and persona filtering. There are 15 possible default fields (email, phone, firstname, lastname, fullname, birth_date, id_card, line_id, gender, plus 6 address fields).

**Custom Field** — A merchant-defined field stored in the `form_responses` table. Three types: `free_text` (with format variants: text, email, phone, number, date, multiline), `single_select`, and `multi_select`. Each field has a unique `field_key` used in conditional logic.

**Form Template** — A container for custom fields. The special template with `code = 'USER_PROFILE'` holds the signup/profile form. One per merchant. Must have `status = 'published'` to be active. Statuses: `draft`, `published`, `archived`.

**Field Group** — An organizational unit within a form template. Groups have a `group_key`, display name, ordering, and an optional `require_at_least_one` validation rule. Example: "Employment Info", "Preferences".

**Field Type** — Determines how a custom field renders. `free_text` uses `text_format` to select the input variant (text input, email keyboard, phone with country code, number pad, date calendar, multiline textarea). `single_select` and `multi_select` render as bottom-sheet pickers with options from `form_field_options`.

**Conditional Field Logic** — Rules that change field behavior based on other field values. A condition links a `source_field_key` (monitored field) to a `target_field_key` (affected field) via an operator and action. Example: when `occupation` equals `"student"`, hide the `income_range` field.

**Operator** — Comparison logic for conditions: `equals`, `not_equals`, `contains`, `is_empty`, `is_not_empty`, `greater_than`, `less_than`.

**Action Type** — What happens when a condition matches: `show`, `hide` (visibility), `enable`, `disable` (interactivity), `require` (make mandatory).

**PDPA Consent** — Privacy/data-protection consent items shown during signup. Three interaction types: `notice` (read-only text, no checkbox), `text_content` (single checkbox — optional or mandatory), `checkbox_options` (master checkbox with individual sub-options for channels/topics).

**Form Step** — Frontend-only navigation state for the multi-step signup form. Sequence: `persona` → `default_field` → `custom_field` → `pdpa`. Steps with no content are automatically skipped.

**Persona-Aware Field** — A field with `persona_ids` set to specific persona UUIDs. Only members with a matching persona see this field. `persona_ids = null` or `[]` means visible to all.

## 3. Configuration Reference

### Default Field Settings

| Setting | What it controls | Example | Default |
|---|---|---|---|
| field_label | Display label | "Email Address" | field_key name |
| field_type | Input component type | `email`, `phone`, `date`, `select`, `normal` | `normal` |
| placeholder | Placeholder text | "Enter your email" | None |
| help_text | Guidance below field | "We'll send updates here" | None |
| order_index | Display order (0-based) | 0 | Sequential |
| is_required | Mandatory for submission | true | false |
| visible_to_user | Member sees this field | true | true |
| visible_to_admin | Admin sees in profile view | true | true |
| editable_by_user | Member can modify value | true | true |
| active_status | Field is enabled | true | true |
| validation_pattern | Regex for input validation | `^[0-9]{13}$` | None |
| min_length / max_length | Character limits | 2 / 100 | None |
| options | Choices for select-type fields (JSONB) | `[{"value":"male","label":"Male"}]` | None |
| persona_ids | Restrict to specific personas | `["uuid1","uuid2"]` | null (all) |

### Custom Field Settings

| Setting | What it controls | Example | Default |
|---|---|---|---|
| field_key | Unique machine identifier | "occupation" | Required |
| field_type | Input type | `free_text`, `single_select`, `multi_select` | Required |
| text_format | Sub-type for free_text | `text`, `email`, `phone`, `number`, `date`, `multiline` | `text` |
| label | Display label | "What is your occupation?" | Required |
| is_required | Mandatory for submission | true | false |
| persona_ids | Restrict to specific personas | `["uuid1"]` | null (all) |
| options | Choices for select fields | `[{"value":"fashion","label":"Fashion"}]` | [] |
| conditions | Conditional logic rules | See Key Concepts | [] |

### Field Group Settings

| Setting | What it controls | Example | Default |
|---|---|---|---|
| group_key | Unique identifier | "preferences" | Required |
| group_name | Display heading | "Your Interests" | Required |
| order_index | Group display order | 0 | Sequential |
| require_at_least_one | At least one field must be filled | true | false |

### PDPA Consent Settings

| Setting | What it controls | Example |
|---|---|---|
| consent_type | Category | `privacy_policy`, `marketing` |
| interaction_type → `notice` | Read-only display, no action needed | Privacy policy text |
| interaction_type → `optional` / `required` | Checkbox consent (type: `text_content`) | Marketing opt-in |
| type: `checkbox_options` | Multiple sub-checkboxes | Communication channels (email, SMS, LINE, push) |
| is_mandatory | Must accept to proceed | true for required consents |

## 4. Admin Journey

**Repo:** `Rocket-CRM/loyalty-admin`

**Route map:**

| Page Name | Current Route | BFF / Data Source |
|---|---|---|
| Profile Form Settings | `/user-profile-form-settings` | `bff_admin_get_user_profile_config`, `bff_admin_upsert_user_profile_config` |
| Consent & Communication Settings | `/consent-settings` | `loadConsentConfig()`, consent save action |

### 4a. Configure Default Fields

1. Open **Profile Form Settings** — page loads with two sections: Default Fields and Custom Fields
2. Each default field appears as a collapsible card showing: label, field_key tag, active/inactive badge, and summary (Required, Visible user/admin, Editable, Personas)
3. Click **"Edit"** on a field card to expand — configure: Required, Visible to user, Visible to admin, Editable by user checkboxes
4. If personas exist, a **Persona requirement** multi-select appears — leave empty for all personas, or select specific ones to restrict
5. Use **arrow buttons** to reorder fields — position determines display order in signup form
6. Click **"Disable"/"Enable"** to toggle `active_status` — disabled fields disappear from the member form
7. Click **"Save"** in page header — normalizes order indexes and submits via `bff_admin_upsert_user_profile_config`

### 4b. Configure Custom Fields

1. In **Profile Form Settings**, scroll to the Custom Fields section
2. Click **"Add group"** to create a field group — set group name, group key, and optionally enable "Require at least one field"
3. Within a group, click **"Add Field"** — configure: label, field_key, field type (free_text/single_select/multi_select), placeholder, required, persona filter
4. For select fields: an **Options** sub-section appears — add options with value, label, default flag, and reorder with arrows
5. Use arrow buttons to reorder groups and fields within groups
6. Click **"Save"** — entire config (default + custom) saves atomically

### 4c. Configure PDPA / Consent

1. Open **Consent & Communication Settings** — separate page for consent configuration
2. Configure consent items: privacy notices, marketing opt-ins, communication channels, topics
3. Set interaction type (notice/optional/required) and mandatory flag per consent item

### 4d. Common Admin Mistakes

- Creating custom fields but leaving the USER_PROFILE form template in `draft` status → fields don't appear on signup
- Setting `persona_ids` on a field when no personas are configured → field hidden from all members
- Making a field required but not visible to user → form submission fails
- Forgetting to save after reordering → changes lost on page refresh
- Adding a new required field post-launch → returning members see `complete_profile_existing` flow with missing fields only

## 5. Member Experience

**Repo:** `Rocket-CRM/loyalty-user`

**Route map:**

| Page / Component | Current Route | Data Source |
|---|---|---|
| Signup Drawer | Bottom-sheet on any page | `bff-auth-complete` edge function → `bff_get_user_profile_template(mode='new')` |
| Edit Profile Drawer | Bottom-sheet on `/profile` | `bff_get_user_profile_template(mode='edit')` |
| Profile Page | `/profile` | `get_user_summary()` |

### 5a. Signup Flow (New User)

1. Member authenticates (LINE / phone OTP) → `bff-auth-complete` returns `next_step = complete_profile_new` with full form in `missing_data`
2. **Persona step** — grid of persona avatars grouped by type; member selects one (skipped if merchant doesn't use personas)
3. **Default fields step** — renders fields from `default_fields_config` dynamically: text inputs, email/phone fields, date pickers, select dropdowns. Terms acceptance row at bottom
4. **Custom fields step** — renders merchant-defined fields from `custom_fields_config`. Conditional logic evaluated in real-time: changing a source field triggers show/hide/enable/disable/require on target fields
5. **PDPA step** — consent accordion: notice items (read-only), text_content items (single checkbox), checkbox_options (channel/topic multi-checkboxes). "Accept All" button toggles everything
6. **"Next"** validates current step (required fields, mandatory consents) → advances to next step. **"Back"** returns to previous
7. **"Confirm"** on last step → `bff_save_user_profile` saves all data atomically → drawer closes

### 5b. Returning User — Incomplete Profile

1. Authenticated user with `is_signup_form_complete = false` → `bff-auth-complete` returns `complete_profile_existing` with full form and pre-filled values
2. Same multi-step flow as 5a but with existing values populated

### 5c. Returning User — New Required Fields

1. Authenticated user with `is_signup_form_complete = true` but new required fields added post-signup → `complete_profile_existing` with only missing required fields
2. Abbreviated form — only the fields that need filling

### 5d. Edit Profile

1. From **Profile Page**, tap edit icon → **Edit Profile Drawer** opens
2. Fetches `bff_get_user_profile_template(mode='edit')` — structure from cache, values from database
3. Reuses same `DynamicFormFields` component from signup — same field rendering, conditional logic, validation
4. Phone editing triggers nested **Edit Phone Dialog** with OTP verification
5. Save via `bff_save_user_profile`

### 5e. Consent Management

1. From **Profile Page** → Settings → **Consent Management** drawer
2. Shows current consent state with accordion UI (same `ConsentSection` component as signup)
3. Save via `bff_save_user_profile` with pdpa payload

## 6. Perspectives

### 6a. For Customer Success / Support

**Elevator pitch:** "Forms let you control exactly what information you collect from members — from basic contact details to custom questions about preferences and interests. You choose which fields are required, who sees which fields based on their persona, and what consent you collect."

**Top support questions:**

| Question | Answer |
|---|---|
| "Member can't complete signup" | Check if all required fields are visible (`visible_to_user = true`). Check persona filtering — if a field is restricted to personas the member hasn't selected, it's hidden but may still be required upstream |
| "A field isn't showing for some members" | Field has `persona_ids` set — only matching personas see it. Or `active_status = false`. Or a conditional rule is hiding it |
| "Member says form is asking questions again" | New required fields were added after their initial signup → `complete_profile_existing` shows only the new fields |
| "Custom field data is missing" | Check USER_PROFILE form template status — must be `published`. Check that `form_submission` exists for the user |
| "Consent options not appearing" | Consent items configured in Consent Settings — separate from Profile Form Settings. Check consent config |

### 6b. For Marketing

**Value proposition:** Forms are the data collection layer for personalization. Every field captured during signup feeds into segmentation — persona selection drives which fields appear (and which promotions, rewards, and tier benefits a member sees). Custom fields like "interests" and "occupation" enable targeted campaigns without surveys.

**Use-case stories:**

1. **Fashion retailer** — Custom multi-select "Style Preferences" field (Casual, Formal, Streetwear) appears during signup. Marketing uses responses to segment members for targeted push notifications about relevant collections.

2. **B2B distributor** — Persona selection (Corporate, SME, Individual) at signup determines which default fields appear (Corporate sees "Company Name" and "Tax ID", Individual doesn't). Different earn rates and reward catalogs per persona.

3. **Restaurant chain** — Conditional field: when "Dietary Preference" = "Vegetarian", a follow-up "Allergen Info" field appears. Data feeds into personalized menu recommendations and birthday reward selection.

### 6c. For Testers

**Config → expected behavior:**

| Config | Expected behavior |
|---|---|
| Default field `active_status = false` | Field absent from signup form |
| Default field `visible_to_user = false`, `is_required = true` | Save fails — required but invisible |
| Custom field `persona_ids = ["uuid1"]`, member has different persona | Field not rendered |
| `persona_ids = null` or `[]` | Field visible to all members |
| Condition: source=occupation, operator=equals, value=student, target=income, action=hide | When occupation="student", income field hidden |
| Condition action=require | Target field becomes mandatory when condition matches |
| `require_at_least_one = true` on group | Submission fails if all fields in group are empty |
| USER_PROFILE template status=draft | No custom fields appear in signup |
| PDPA consent `is_mandatory = true`, not accepted | "Next"/"Confirm" blocked |
| mode=new | All field values are null (fresh form) |
| mode=edit | Field values populated from database |

**Business rules as assertions:**

- ASSERT: Form step sequence is persona → default_field → custom_field → pdpa; empty steps are skipped
- ASSERT: New user (`complete_profile_new`) gets full form with all values null
- ASSERT: Returning user with `is_signup_form_complete = false` gets full form with existing values
- ASSERT: Returning user with `is_signup_form_complete = true` and new required fields gets only those fields
- ASSERT: Conditional logic evaluates on every field change — show/hide/enable/disable/require update instantly
- ASSERT: Persona selection filters both default and custom fields in subsequent steps
- ASSERT: "Accept All" on PDPA toggles all consents and all sub-options to true
- ASSERT: Checkbox_options master toggle cascades to all child options; unchecking any child unchecks master
- ASSERT: Field value changes debounce at 5 seconds before updating state
- ASSERT: If `missing_data` is null/empty, Retry button shown — form never auto-saves empty data

**Error states to test:**

- `bff-auth-complete` fails to load form → "Could not load the registration form" + Retry button
- Required field left empty → Next button validation blocks advancement
- Mandatory consent not accepted → cannot proceed past PDPA step
- Phone edit requires OTP re-verification
- Concurrent profile edit (two tabs) — last save wins

## 7. Business Rules

**Rule:** Two-system architecture — default fields write to `user_accounts`/`user_address` columns; custom fields write to `form_responses` via a `form_submission` record. Both save atomically through `bff_save_user_profile`.
**Example:** Saving a form with email (default) and occupation (custom) → email updates `user_accounts.email`, occupation creates/updates a `form_responses` row linked to the USER_PROFILE submission.

**Rule:** Persona selection during signup determines which fields are visible. Fields with `persona_ids` containing the selected persona (or `persona_ids = null`) appear; others are filtered out.
**Example:** "Company Name" field has `persona_ids = ["corporate-uuid"]`. Member selects "Individual" persona → field not shown.

**Rule:** Conditional field logic evaluates client-side in real-time. When a source field's value matches the condition's operator + compare_value, the action is applied to the target field.
**Example:** Source "has_children" equals "yes" → action "show" on "number_of_children" field.

**Rule:** `form_step` auto-skips steps with no content. If a merchant has no personas, the persona step is skipped. If no custom fields exist, the custom_field step is skipped.
**Example:** Merchant with only default fields and PDPA → member sees: default_field → pdpa (two steps).

**Rule:** Cache has 5-minute TTL for form structure. User values are always fetched live. Structure cached in Redis via `extensions.user_profile_cache_set`.
**Example:** Admin adds a new field → members may see old structure for up to 5 minutes. Values submitted against the new field are still saved correctly.

**Rule:** The `bff-auth-complete` edge function fetches the form template using an anon Supabase client (no user JWT) with explicit `p_merchant_code`. This is necessary because the custom JWT's `sub` is a `user_accounts.id`, not an `auth.users` UUID.
**Example:** After OTP verification, the edge function loads the form before the user JWT is available.

**Rule:** "Accept All" in PDPA sets `isAccepted = true` on all consent sections and `selected = true` on all sub-options. Individual option toggles update the master checkbox (true only when all children are selected).
**Example:** Member unchecks "SMS" in communication channels → master "Communication Channels" checkbox unchecks.

**Rule:** Empty `persona_ids` (null or []) means unrestricted — all members see the field. Setting `persona_ids` to specific UUIDs restricts to those personas only.
**Example:** Field with `persona_ids = null` → visible to Corporate, SME, and Individual personas alike.

## 8. Related Features

| Feature | Connection to Forms |
|---|---|
| Tags & Personas | Persona selection during signup filters which form fields appear. See `Tag_and_Persona.md`. |
| Translation | Field labels, placeholders, group names, and PDPA content support multi-language rendering via the translation system. |
| Tier | Profile completion (form fields) can be a prerequisite for tier-gated features. |
| Rewards | Persona-aware field filtering affects eligibility when persona-aware features are active. See `Reward.md`. |
| Activity/Earning | Custom field data (e.g., store preference) can feed into activity-based earning segmentation. |
