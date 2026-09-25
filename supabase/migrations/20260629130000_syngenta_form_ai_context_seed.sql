-- Seed Syngenta form/field ai_context + AMP Analysis form field guide

DO $$
DECLARE
  v_mid uuid := '8f67aa08-dfce-454d-bfb1-effc4ee45f1f';
BEGIN
  -- ─── Form templates ───────────────────────────────────────────────────────
  UPDATE form_templates SET ai_context = 'Member profile captured at signup and profile updates. Use member_latest aggregation (one row per member, latest submission). Primary source for grower segmentation: crop type and farm size (area in rai). Cross-reference with query_cross_tab_profile + outcome event_attended for event attendance questions.'
  WHERE merchant_id = v_mid AND code = 'USER_PROFILE';

  UPDATE form_templates SET ai_context = 'Post-event survey for corn fair / field crop events. Submission-level aggregation. Use for event-specific product and variety preferences among attendees.'
  WHERE merchant_id = v_mid AND code = 'corn_fair_survey';

  UPDATE form_templates SET ai_context = 'Rice expo event survey. Submission-level. has_attended_syngenta_event and product usage fields indicate prior Syngenta engagement at point of survey.'
  WHERE merchant_id = v_mid AND code = 'rice_expo_survey';

  UPDATE form_templates SET ai_context = 'Field Crop Survey 2025 — event-linked grower research (corn seed varieties, sales rep). Submission-level.'
  WHERE merchant_id = v_mid AND code = 'field_crop_survey_2025';

  UPDATE form_templates SET ai_context = 'Field Crop Survey V2 — updated corn grower survey. Submission-level.'
  WHERE merchant_id = v_mid AND code = 'field_crop_survey_v2';

  UPDATE form_templates SET ai_context = 'EXPO SIMODIS vegetable event (Phetchabun). Submission-level event survey.'
  WHERE merchant_id = v_mid AND code = 'expo_simodis_veg_phetchabun';

  UPDATE form_templates SET ai_context = 'Grow Well Eat Well (GWEP) program survey. Submission-level; tracks program awareness and participation.'
  WHERE merchant_id = v_mid AND code = 'gwew_survey';

  UPDATE form_templates SET ai_context = 'Rice Big Grower deep-dive survey 2026. Submission-level; rich rice farming economics (area, yield, crop protection spend).'
  WHERE merchant_id = v_mid AND code = 'RICE_BIGGROWER_2026';

  UPDATE form_templates SET ai_context = 'Syngenta GWEP enrollment form. Submission-level; participated_crop and area fields for program participants.'
  WHERE merchant_id = v_mid AND code = 'SYNGENTA_GWEP';

  UPDATE form_templates SET ai_context = 'Special event satisfaction survey. Submission-level post-event feedback.'
  WHERE merchant_id = v_mid AND code = 'special_event';

  UPDATE form_templates SET ai_context = 'Big grower advanced profile — detailed commercial grower attributes (crop areas, Syngenta activity experience). Submission-level.'
  WHERE merchant_id = v_mid AND name = 'Big grower - advanced';

  UPDATE form_templates SET ai_context = 'Big grower field crop (FC) profile — crop details, farm mechanics, segment. Submission-level.'
  WHERE merchant_id = v_mid AND name = 'Big grower - FC';

  UPDATE form_templates SET ai_context = 'Big grower crop protection (CP) profile — product usage, yields, Syngenta activity experience. Submission-level.'
  WHERE merchant_id = v_mid AND name = 'Big grower CP';

  UPDATE form_templates SET ai_context = 'Generic event activity satisfaction form. Submission-level.'
  WHERE merchant_id = v_mid AND name = 'แบบฟอร์มกิจกรรม';

  -- ─── USER_PROFILE fields ──────────────────────────────────────────────────
  UPDATE form_fields SET ai_context = 'Primary crops grown (multi-select). Values include rice, sweet_corn, field_corn, fruit, leafy_vegetables, etc. Use for "which crop growers" questions. For event attendance cross-tabs use query_cross_tab_profile with field_key=crop and outcome_type=event_attended. Members with multiple crops appear in each crop segment.'
  WHERE merchant_id = v_mid AND field_key = 'crop'
    AND form_id = (SELECT id FROM form_templates WHERE merchant_id = v_mid AND code = 'USER_PROFILE' LIMIT 1);

  UPDATE form_fields SET ai_context = 'Total planting area in rai (numeric). Default buckets: <20 rai = smallholder, 20-99 = medium, 100+ = large commercial. Use query_profile_field or query_cross_tab_profile with field_key=area for farm-size vs event attendance.'
  WHERE merchant_id = v_mid AND field_key = 'area'
    AND form_id = (SELECT id FROM form_templates WHERE merchant_id = v_mid AND code = 'USER_PROFILE' LIMIT 1);

  UPDATE form_fields SET ai_context = 'Legacy migration source tag. Internal only — not useful for grower segmentation.'
  WHERE merchant_id = v_mid AND field_key = 'migrated_source'
    AND form_id = (SELECT id FROM form_templates WHERE merchant_id = v_mid AND code = 'USER_PROFILE' LIMIT 1);

  UPDATE form_fields SET ai_context = 'Account classification from legacy CRM. Internal metadata.'
  WHERE merchant_id = v_mid AND field_key = 'account_type'
    AND form_id = (SELECT id FROM form_templates WHERE merchant_id = v_mid AND code = 'USER_PROFILE' LIMIT 1);

  -- ─── Common survey fields (by field_key across forms) ─────────────────────
  UPDATE form_fields SET ai_context = 'Self-reported prior Syngenta event attendance (yes/no). Submission-level — reflects answer at time of survey, not authoritative attendance ledger. Prefer syngenta_event_registration_ledger via query_event_attendance for actual attendance.'
  WHERE merchant_id = v_mid AND field_key = 'has_attended_syngenta_event';

  UPDATE form_fields SET ai_context = 'Self-reported Syngenta product usage from survey. Submission-level.'
  WHERE merchant_id = v_mid AND field_key = 'has_used_syngenta_product_list';

  UPDATE form_fields SET ai_context = 'Rice planting area in rai (latest season). Submission-level from Rice Big Grower survey.'
  WHERE merchant_id = v_mid AND field_key = 'a2_rice_area_rai';

  UPDATE form_fields SET ai_context = 'Years of rice farming experience. Submission-level.'
  WHERE merchant_id = v_mid AND field_key = 'a4_farming_years';

  UPDATE form_fields SET ai_context = 'Crop(s) enrolled in GWEP program. Submission-level multi-select.'
  WHERE merchant_id = v_mid AND field_key = 'participated_crop';

  UPDATE form_fields SET ai_context = 'Farm area in rai on GWEP enrollment form. Submission-level.'
  WHERE merchant_id = v_mid AND field_key = 'area'
    AND form_id = (SELECT id FROM form_templates WHERE merchant_id = v_mid AND code = 'SYNGENTA_GWEP' LIMIT 1);

  UPDATE form_fields SET ai_context = 'Prior Syngenta activity types experienced (demo plot, training, etc.). Submission-level multi-select on big grower advanced form.'
  WHERE merchant_id = v_mid AND field_key = 'syngenta_activity_experience';

  UPDATE form_fields SET ai_context = 'Field crop details (crop types planted). Submission-level multi-select on big grower FC form.'
  WHERE merchant_id = v_mid AND field_key = 'fc_crop_details';

  UPDATE form_fields SET ai_context = 'Grower segment classification on FC form. Submission-level.'
  WHERE merchant_id = v_mid AND field_key = 'fc_segment';

  UPDATE form_fields SET ai_context = 'First crop planted area. Submission-level on big grower advanced form.'
  WHERE merchant_id = v_mid AND field_key = '1stcroparea';

  UPDATE form_fields SET ai_context = 'Owned planting area. Submission-level on big grower advanced form.'
  WHERE merchant_id = v_mid AND field_key = 'plantareaowned';

  UPDATE form_fields SET ai_context = 'GWEP program participation (yes/no). Submission-level.'
  WHERE merchant_id = v_mid AND field_key = 'has_attend_activity_gwew';

  UPDATE form_fields SET ai_context = 'Event satisfaction score. Submission-level post-event feedback.'
  WHERE merchant_id = v_mid AND field_key = 'event_satisfaction';
END $$;

-- ─── AI knowledge registry: form analysis guide ───────────────────────────

INSERT INTO ai_knowledge_registry (feature_key, title, content, content_type, version, is_active)
VALUES (
  'amp_analysis.form_field_guide',
  'Form Field Guide — AMP Analysis Agent',
  $guide$
# Form Field Guide — AMP Analysis Agent

Always consult FORM CATALOG in thread context (form_catalog) before answering questions about crops, farm size, surveys, profile attributes, or event attendance.

## Two aggregation modes

| Mode | Forms | Tool | Count unit |
|---|---|---|---|
| member_latest | USER_PROFILE (code=USER_PROFILE) | query_profile_field, query_cross_tab_profile | unique members (latest submission per user) |
| submission | all other published forms | query_form_field_breakdown | form submissions |

Never claim crop/farm/event data is unavailable without calling form tools first.

## Tool routing

| Question type | Tools to call |
|---|---|
| What forms/fields exist? | form_catalog (in context) or query_form_catalog |
| Crop or farm size distribution | query_profile_field (crop, area) |
| Which segment attends events more? | query_cross_tab_profile (field_key=crop or area, outcome_type=event_attended) |
| Event attendance totals | query_event_attendance |
| Survey response breakdown | query_form_field_breakdown (form_id from catalog) |

## Event attendance (Syngenta)

Authoritative attendance: syngenta_event_registration_ledger via query_event_attendance and query_cross_tab_profile.
Survey field has_attended_syngenta_event is self-reported only — use ledger for "who actually attended".

## Area bucketing defaults (rai)

- small: < 20 rai
- medium: 20–99 rai
- large: 100+ rai

Respect field ai_context in catalog when present — it overrides defaults.

## Multi-select crops

Members can select multiple crops. query_cross_tab_profile counts a member in each crop segment they grow.

## Purchase vs event merchants

If query_member_overview shows never_bought + earn_only but form/event tools return data, this merchant is event-driven — lead with form and event tools, not purchase cohorts.
$guide$,
  'markdown',
  1,
  true
)
ON CONFLICT (feature_key) DO UPDATE SET
  title = EXCLUDED.title,
  content = EXCLUDED.content,
  content_type = EXCLUDED.content_type,
  version = ai_knowledge_registry.version + 1,
  is_active = true,
  updated_at = now();
