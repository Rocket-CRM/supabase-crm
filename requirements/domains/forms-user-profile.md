# Forms & User Profile

> Per-domain reference. Read ONLY when working on this domain. For the keyword → file map, see `_index.md`.

**Keywords:** form, survey, field, custom field, default field, profile, user field config, form template, form field, form response, form submission, field type, select, multi-select, conditional field, PDPA, consent, address

**Source:** `Forms.md`

**FE-Relevant Sections:**

| Section Heading | Lines | What it contains |
|---|---|---|
| Architecture Overview | 1–13 | Two systems: default fields (user_accounts/user_address) vs custom fields (form_submissions/form_responses) |
| Default Fields — user_field_config | 16–40 | All config properties: field_key, type, required, validation, persona_ids |
| Default Fields — Data Storage | 42–63 | Mapping of field_key → table.column |
| Custom Fields — Table Structure | 66–102 | form_templates → form_field_groups → form_fields → form_field_options → form_conditions |
| Conditional Field Logic | 132–168 | source_field_key → operator → compare_value → target_field_key → action_type |
| Cache Structure | 170–204 | Redis cache key pattern, cached data shape, TTL |
| API — GET Template | 206–307 | `bff_get_user_profile_template` response structure with default/custom fields, persona, PDPA |
| API — SAVE Profile | 309–344 | What `bff_save_user_profile` saves and where |
| Frontend Integration — Form Field Handler | 356–410 | JavaScript handler with 5s debounce for field value updates |
| Frontend Integration — PDPA Handler | 412–476 | Expand/accept/accept_all logic for consent UI |
| PDPA Types | 478–486 | `notice`, `text_content`, `checkbox_options` interaction types |
| Validation | 519–537 | Field-level, group-level, and conditional validation rules |

**Supabase Functions (FE-callable):**

| Function | Parameters | Returns | Lines |
|---|---|---|---|
| `bff_get_user_profile_template(p_language, p_mode)` | `p_language`, `p_mode ('new'/'edit')` | Full form config with fields, options, conditions, PDPA | 206–307 |
| `bff_save_user_profile(p_data)` | `p_data (jsonb)` | `{ success, user_id, is_new_user }` | 309–344 |
| `bff_admin_update_member_profile(p_user_id, p_data)` | `p_user_id (uuid)`, `p_data (jsonb)` | Admin update for allowed default/custom profile fields; address upsert uses `(user_id, merchant_id)` | — |
| `bff_admin_get_form_submission_data(p_form_id, p_user_id)` | `p_form_id (uuid)`, `p_user_id (uuid)` | `{ success, data: { submission_id, submitted_at, status, source, values: {field_key: value} } }` | — |
| `bff_user_get_surveys(p_language)` | `p_language` | Published surveys with `banner_url`, `reward_preview` and `user_state` | Survey Completion Rewards |
| `bff_user_get_survey_details(p_form_identifier, p_language)` | `p_form_identifier`, `p_language` | Survey form detail with fields/options/placeholders plus `form.banner_url`, `reward_preview` and `user_state` | Survey Completion Rewards |
| `bff_user_submit_survey(p_form_id, p_submission_data, p_source, p_source_id, p_ref_userid, p_tel)` | `p_form_id`, keyed submission JSON, source metadata | Submission result with `reward_outcome` | Survey Completion Rewards |
| `bff_get_form_details(p_form_id, p_mode)` | `p_form_id`, `p_mode ('new'/'edit')` | Form admin payload — includes `data.form.allow_bulk_import`, `data.form.banner_url`, and `data.metadata.allow_bulk_import_locked` (true for USER_PROFILE) | — |
| `bff_upsert_form(p_data jsonb)` | full form payload incl. `form.allow_bulk_import`, `form.banner_url` | Saves form; persists `allow_bulk_import` (USER_PROFILE auto-true) and optional survey header `banner_url` | — |

**Key Business Rules (summary):**
- Default fields stored in `user_accounts` / `user_address`; custom fields in `form_responses`
- `user_address` is merchant-scoped; one editable profile address is keyed by `(user_id, merchant_id)`, not `user_id` alone
- USER_PROFILE form (code = `USER_PROFILE`) is the special signup/profile form
- `persona_ids` on fields: show only for specific personas (NULL = universal)
- Conditional logic: field visibility/requirement changes based on other field values
- PDPA types: `notice` (read-only), `text_content` (single checkbox), `checkbox_options` (multiple)
- Cache: 5-min TTL, structure cached, values always live
- Survey submission limits: per-user and total caps via `transaction_limits` with `entity_type='form'`, enforced in `submit_form_public`. Skipped for USER_PROFILE and anonymous submissions.
- User survey APIs only expose `form_templates.status='published'` and `form_category='survey'`; rewards are displayed from the hidden `system_survey_reward:{form_id}` workflow config. Optional `form_templates.banner_url` is the member survey header; blank hides it.

---
