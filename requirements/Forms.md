# Forms & User Profile

Merchant-configurable member data: standard profile columns, optional custom questions, standalone surveys, and conditional visibility. Default values live on the member row; custom answers live on form submissions linked to that member.

Owner surfaces: loyalty-admin, loyalty-user

## Concept

The platform treats member data as **two cooperating field systems** that share one member-facing template API for signup and profile edit.

**Default fields** — Built-in profile keys (name, email, phone, address, demographics, and similar). Merchants tune labels, order, requiredness, and visibility per key. Values are stored on **`user_accounts`** and **`user_address`**, not in form response rows.

**Custom fields** — Merchant-defined questions grouped into sections. Definition lives on a **form template**; answers live on **submissions** and **responses** keyed by field id.

**USER_PROFILE template** — One special template per merchant (`code = 'USER_PROFILE'`) that holds custom profile questions. Must be **published** to appear in the member profile/signup template. Custom answers for a member are read and written through that template’s submission row.

**Survey template** — Any other published template with **`form_category = 'survey'`**. Used for one-off or repeatable questionnaires (insights, event follow-ups). Member apps list and submit surveys separately from the profile flow.

**Form submission** — A single fill event for a template: links merchant, optional member, source metadata, and status (**draft** or **completed**). Profile custom fields use one logical submission per member per USER_PROFILE form; surveys create a new submission each time (subject to limits).

**Form response** — One answered field on a submission: text, multi-select array, or structured object value.

**Conditions** — Rules that show, hide, enable, disable, or require a target field when a source field matches an operator. Apply to custom fields on a template (including USER_PROFILE).

**Persona scoping** — Default and custom fields may list `persona_ids`; empty means all personas. The profile template RPC filters fields for the authenticated member’s persona.

**Profile completion flag** — `user_accounts.is_signup_form_complete` records that the member completed signup profile at least once; merchants can add new required fields later and still force another pass (see Signup & Login).

**Signup vs edit** — The same template builder powers signup (`p_mode = 'new'`) and profile edit (`p_mode = 'edit'`): structure from cache/config, values loaded live for edit.

Surveys may attach **reward workflows** (hidden AMP config) and **submission caps** via shared participation limits; USER_PROFILE and anonymous profile paths skip survey-style caps.

## Rules

### Default fields

- Each merchant has rows in **`user_field_config`** per `field_key`. Inactive keys (`active_status = false`) are omitted from member templates; auth-managed keys (e.g. phone, LINE id) stay off the free-text profile form.
- Required default fields must be non-empty on save; format validation runs when `validate_format` is true (pattern / length from config).
- **Phone** is stored as `user_accounts.tel`; **email**, names, **birth_date**, **id_card**, **line_id**, **gender**, and related keys map to `user_accounts` columns. Address keys map to **`user_address`** (upserted with the member).
- Persona filter: if `persona_ids` is set, the field appears only when the member’s persona is in the list.
- Admin may edit fields marked `editable_by_admin`; member edit respects `editable_by_user` and visibility flags.

### Custom fields (USER_PROFILE)

- At most one USER_PROFILE template per merchant (by product convention); it must be **published** for custom sections to render.
- Custom values are stored only in **`form_responses`** tied to a **`form_submissions`** row for that template and `user_id`. Saving profile upserts account/address columns and merges custom responses into the member’s USER_PROFILE submission.
- Soft-deleted field definitions (`form_fields.deleted_at`) must not accept new answers; historical responses may remain for audit.

### Surveys

- Member-facing survey APIs expose only templates with **`status = 'published'`** and **`form_category = 'survey'`**.
- Submission uses **`bff_user_submit_survey`** / **`submit_form_public`** (anonymous or identified via `ref_userid` / `tel` when no JWT).
- Per-user and campaign-wide caps use **`transaction_limits`** with `entity_type = 'form'`, enforced on public submit. **USER_PROFILE** saves and anonymous survey paths configured to skip limits are not capped the same way.
- Optional **`banner_url`** on the template: shown at the top of the member survey; blank hides the banner.
- Survey rewards are configured via hidden workflow config (`system_survey_reward:{form_id}`); display copy comes from that config, not the form name alone.

### Conditions and validation

- Operators include equals, not equals, contains, is empty / not empty, greater than, less than (per enum on `form_conditions`).
- Actions: show, hide, enable, disable, require on **`target_field_key`** when **`source_field_key`** matches **`compare_value`** (where applicable).
- Field-level: `is_required`, regex, min/max numeric, min/max selections on multi-select.
- Group-level: **`require_at_least_one`** on a field group forces at least one field in the group to be filled.
- Server validation: **`validate_form_submission`** before persist; profile save runs the full profile validator inside **`bff_save_user_profile`**.

### Consent and channels (profile template)

- Profile template payload may include PDPA sections and communication channel/topic blocks. Acceptance writes **`user_consent_ledger`** and updates **`user_accounts.channel_*`** plus **`user_communication_preferences`** on save (see Consent domain).
- PDPA interaction types drive UI: notice (read-only), text content (checkbox), checkbox options (multi-option blocks including channels).

### Cache

- Merged profile **structure** (default config, custom config, persona metadata, consent shells) is cached in Redis (~5 minutes, key pattern `merchant:{merchant_id}:user_profile_template:all_languages`). **Values are always read from the database** on edit/submit.
- Cache invalidates on merchant profile/form config changes (DB triggers on `user_field_config`, form template children, and related invalidation helpers).

### Status and sources

- Template **`status`**: `draft` → `published` → `archived`. Only published templates are active for members (USER_PROFILE and surveys).
- Submission **`status`**: `draft` (e.g. bulk import placeholder) or `completed`.
- **`source`** / **`source_id`** / **`source_id_2`** identify origin (member app, event, bulk import, survey web). Unique dedup index on `(source_id, source_id_2)` when both set.

## Journeys

### Admin journey

| Page | Owning repo | BFF / RPC |
| --- | --- | --- |
| User profile form settings | loyalty-admin | `bff_admin_get_user_profile_config`, `bff_admin_upsert_user_profile_config` |
| External code pools (profile field) | loyalty-admin | `user_field_config` + upsert config; code tables per field |
| Surveys list | loyalty-admin | list via survey actions / `bff_get_form_details` |
| Survey create/edit | loyalty-admin | `bff_upsert_form`, `bff_get_form_details`, `bff_get_form_reward_workflow_config`, `bff_upsert_form_reward_workflow` |
| Survey reports | loyalty-admin | `get_form_submission_summary`, dashboard aggregations |
| Customer 360 — profile tab / edit | loyalty-admin | `bff_get_user_profile_template` (admin audience), direct `user_accounts` / field config reads |
| Event registration (survey link) | loyalty-admin | `bff_get_form_details_user` |
| Front line / order booking — create member | loyalty-admin | `bff_get_user_profile_template`, validation helpers (not always `bff_save_user_profile` — may use admin member APIs) |

| Setting | Effect on behaviour |
| --- | --- |
| Default field enable / required / label | `user_field_config` row; drives template and validation |
| Default field persona_ids | Restricts field to listed personas |
| Custom groups and fields | USER_PROFILE `form_templates` structure via profile form settings UI |
| Field conditions | `form_conditions` on USER_PROFILE or survey template |
| Survey name, status, banner | `form_templates`; publish gates member visibility |
| Survey submission limits | `transaction_limits` synced on `bff_upsert_form` save |
| Survey reward workflow | AMP workflow config via reward workflow BFFs |
| Allow bulk import (non–USER_PROFILE) | `form_templates.allow_bulk_import` |

1. **User profile form settings** — Configure default fields (order, required, visibility, validated external codes) and custom groups/fields on USER_PROFILE; save merges config without wiping nested `config` jsonb (id card, external code pools).
2. **Surveys** — Create survey, add fields and conditions, set limits and optional banner; publish; copy member link (`/surveys/{identifier}` on loyalty app host).
3. **Reports → Surveys** — Review aggregated responses for a published survey.
4. **Customer 360** — View or edit member profile; custom values read from USER_PROFILE submission responses.

### Member journey

| Step | Owning repo | BFF / RPC |
| --- | --- | --- |
| Signup profile (after auth) | loyalty-user | `bff_get_user_profile_template`, `bff_save_user_profile` |
| Edit profile | loyalty-user | `bff_get_user_profile_template` (`p_mode = 'edit'`), `bff_save_user_profile` |
| Survey list | loyalty-user | survey list API (published surveys only) |
| Survey detail / submit | loyalty-user | `bff_user_get_survey_details`, `bff_user_submit_survey` |

1. **Signup** — Auth hub returns `complete_profile_*`; client loads template (`p_mode = 'new'`), walks sections (persona → default → custom → PDPA/channels per Signup & Login `form_step`), then **`bff_save_user_profile`**; hub sets **`is_signup_form_complete`**.
2. **Edit profile** — Open profile drawer/page; template `edit` mode prefills values; save merges account, address, USER_PROFILE responses, consent, and channels.
3. **Survey** — Open linked survey; submit once per attempt; success state and any reward dispatch per workflow config; limit errors if caps exceeded.

Errors the member may see: required field, format validation, consent not accepted, survey limit exceeded, or unpublished/missing survey identifier.

## System

### Data model

| Object | Role |
| --- | --- |
| `user_field_config` | Per-merchant default field metadata: key, label, type, validation, order, visibility, persona_ids, `config` jsonb (external codes, id document settings). |
| `user_accounts` | Default field values; `persona_id`, `is_signup_form_complete`, `channel_*`, identity columns. |
| `user_address` | Address-line default fields (1:1 with member). |
| `form_templates` | Form definition: `code` (USER_PROFILE or null), `form_category` (`survey` or null), `status`, `banner_url`, `allow_bulk_import`, merchant scope. |
| `form_field_groups` | Section headers; `require_at_least_one`. |
| `form_fields` | Custom field defs: `field_key`, `field_type`, `text_format`, validation, persona_ids, admin visibility flags, soft delete. |
| `form_field_options` | Select options. |
| `form_conditions` | Conditional UI/validation rules. |
| `form_submissions` | Submission header: `form_id`, `merchant_id`, `user_id` (nullable for anonymous), `status`, `source`, `ref_userid`, `tel`, dedup ids, `skip_cdc`. |
| `form_responses` | Answers: `submission_id`, `field_id`, `text_value`, `array_value`, `object_value`. |
| `transaction_limits` | Survey caps (`entity_type = 'form'`). |
| `user_consent_ledger` | PDPA acceptances on profile save (Consent domain). |

**Profile linkage:** `user_id` on `form_submissions` ties USER_PROFILE responses to `user_accounts.id`. Signup completion flag is on the account row, not on the submission status alone. Bulk import may insert a **draft** USER_PROFILE submission to establish the relationship before responses exist.

### Functions

| Function | Role |
| --- | --- |
| `fn_seed_default_user_field_config` / `trigger_seed_default_user_field_config` | Seed default keys for new merchants. |
| `get_default_user_fields` | Resolve default field definitions by visibility context. |
| `bff_admin_get_user_profile_config` / `bff_admin_upsert_user_profile_config` | Admin read/write of default + USER_PROFILE structure. |
| `bff_get_user_profile_template` | Member/admin template: structure (+ values in edit), persona, PDPA, channels; Redis-backed structure. |
| `bff_save_user_profile` | Atomic profile save: accounts, address, USER_PROFILE responses, consent, channels; sets signup complete. |
| `mark_signup_form_complete` | Explicit completion marker when needed outside save. |
| `bff_get_form_details` / `bff_upsert_form` | Admin survey (and form) edit pipeline. |
| `bff_get_form_details_user` / `bff_user_get_survey_details` | Member-facing published form/survey definition. |
| `submit_form_public` / `submit_form_response` / `bff_user_submit_survey` | Persist survey (and generic) submissions. |
| `validate_form_submission` | Server-side validation gate. |
| `fn_check_form_submission_limits` | Limit enforcement for surveys. |
| `fn_get_user_form_values` | Read custom answers by field keys for segmentation/AMP. |
| `evaluate_field_visibility` / `get_field_dependencies` | Condition evaluation helpers. |
| `fn_amp_submit_form` | AMP/event path for structured form posts. |
| `get_form_submission_summary` / `get_form_dashboard_aggregated` | Admin reporting. |
| `bff_get_form_reward_workflow_config` / `bff_upsert_form_reward_workflow` | Survey reward wiring. |

### Flows

**Profile load:** Client calls `bff_get_user_profile_template` → load cached structure → merge live `user_accounts` / `user_address` / USER_PROFILE `form_responses` / consent state → apply persona and condition metadata.

**Profile save:** Client posts full template payload to `bff_save_user_profile` → validate → upsert account + address → upsert USER_PROFILE submission + responses → write consent ledger and channel prefs → set `is_signup_form_complete`.

**Survey submit:** Load published survey → client validation → `fn_check_form_submission_limits` (if applicable) → insert submission + responses → trigger reward workflow if configured.

**Import:** Customer import may create draft USER_PROFILE submission (`source = 'bulk_import'`) when a published USER_PROFILE exists and the member has no submission yet.

### External services

- **Redis** — Profile template structure cache (`extensions.user_profile_cache_*` helpers).
- **AMP / workflows** — Survey rewards and analysis (`fn_amp_analysis_query_form_summary`, user profile form id helper for AMP).

### Known gaps

- No database unique constraint on `(merchant_id, form_id, user_id)` for USER_PROFILE; one submission per member is enforced by application upsert logic — duplicate rows would be a data bug.
- Legacy **`submission_number`** uniqueness per merchant is for older numbering, not member identity.
- Merchant-specific survey UIs (e.g. rice survey in loyalty-admin) bypass generic survey list for dedicated flows; behaviour is duplicated at the app layer.
- Registry may list overloaded symbols (e.g. two `submit_form_response` arities); clients use the RPC signature their app generated.

## Related

- **Signup & Login** — Auth `next_step`, `form_step`, profile completion flag, and signup code validation on save.
- **Consent** — PDPA templates, ledger writes, and version rules bundled in profile template.
- **Customer Import System** — Optional draft USER_PROFILE submission on import.
- **Tag and Persona** — Persona selection and `persona_ids` field scoping.
- **AMP (workflows)** — Survey rewards, form analysis, `fn_amp_submit_form`.
- **Syngenta Events** — Event-linked surveys and registration forms.
