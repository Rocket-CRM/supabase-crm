-- regen_registry_supabase.sql
-- Emits the entire content of requirements/REGISTRY_SUPABASE.md in one column.
-- Run via psql -t -A -X -f scripts/regen_registry_supabase.sql or via Supabase MCP.
-- Output: one row, one column, the full markdown text.

WITH
domains(prio, name, pattern) AS (VALUES
  (15, 'Tier',                  'tier'),
  (15, 'Currency',              '(^|_)(wallet|currency|point|ticket|expiry|earn_factor|burn)'),
  (15, 'Reward',                '(reward|redeem|promo_code|claim_link|admin_push_reward)'),
  (15, 'Mission',               'mission'),
  (15, 'Referral',              '(referral|fn_ensure_member_code|bff_user_get_invite|bff_user_apply_referral)'),
  (20, 'Signup Code Validation','signup_code'),
  (15, 'Signup & Login',        '(signup|login)'),
  (15, 'Auth (LINE/JWT/OTP)',   '(jwt|otp|line_login|line_auth|merchant_auth)'),
  (20, 'Member Freeze',         '(is_freeze|member_freeze|fn_is_user_frozen|fn_account_restricted|fn_assert_user_not_frozen|bff_admin_set_member_freeze)'),
  (15, 'Forms & User Profile',  '(form|user_field|user_io)'),
  (15, 'Customer Import',       '(user_import|bulk_import|bulk_upsert|user_export|export_)'),
  (15, 'Store Classification',  '(store_|location_|partner_)'),
  (15, 'Tag & Persona',         '(persona|user_tag|tag_master|tag_assignment|assign_tag|admin_delete_tag|bff_.*tag)'),
  (15, 'Activity & Earning',    '(activity_|earning_)'),
  (15, 'Purchase Transaction',  '(purchase|transaction_|ledger)'),
  (15, 'Chokepoint Outbox',     '(chokepoint_event_outbox|fn_chokepoint_emit_event|v_chokepoint_outbox_health)'),
  (15, 'Event Promotion',       '(event_promo|fn_calc_promo_set_count|fn_evaluate_promo_condition|fn_calc_event_promos|fn_apply_event_promos|bff_.*event_promo)'),
  (15, 'Display Settings',      '(display_settings|display_block|display_link|get_display_|fn_get_display)'),
  (15, 'Translation',           'translation'),
  (15, 'Internal Knowledge',    '(internal_knowledge|knowledge_block|feature_item)'),
  (15, 'Admin Panel',           '(admin_user|admin_role|admin_menu|admin_analytics|superadmin|platform_admin|loyalty_setup_mastery)'),
  (15, 'BigCommerce Storefront API', 'bigcommerce'),
  (15, 'Custom Webhooks',         'custom_webhook'),
  (20, 'Marketplace',             '(marketplace_|merchant_credentials|get_shop_credentials|get_merchant_marketplace)'),
  (15, 'AMP Workflows',         '(workflow|amp_agent|amp_analysis|amp_audience|audience|amp_tracked_link|amp_engagement|fn_amp_|bff_amp_|fn_evaluate_amp)'),
  (15, 'Receipt / OCR',         '(receipt|ocr_)'),
  (15, 'Resource Content',      '(content_resource|resource_content|quick_reply|canned_response|media_resource|rich_content|member_app_deep_link)'),
  (15, 'Action Macro',          '(action_macro|macro_)'),
  (15, 'Universal Action System','(action_registry|action_caller_config|rule_type_registry|entity_registry|intent_registry)'),
  (15, 'Stored Value Card',     '(svc_|stored_value_card)'),
  (15, 'Checkin',               'checkin'),
  (15, 'Spin Wheel',            'spin_wheel'),
  (20, 'Activity Log & Attribution', '(mkt_|activity_type|activity_field_def|activity_ledger|log_user_activity|attribution_field)'),
  (20, 'RFM Scoring',           'rfm'),
  (20, 'Funnel',                'funnel'),
  (15, 'Campaign',              'campaign'),
  (20, 'Asset',                 '(^asset($|_)|asset_type|asset_tier_config|asset_field|asset_relation|custom_crm_asset_sync|fn_asset_|bff_admin_.*asset|bff_get_user_assets|bff_get_asset_filters|validate_asset_custom_fields|api_create_or_update_asset|api_find_asset|api_get_asset|api_update_asset)'),
  (15, 'API Key & Asset',       '(api_key|api_assign_package)'),
  (15, 'Platform Plan Registry','(platform|merchant_plan|feature_registry|feature_config|feature_entitlements|fn_merchant_feature)'),
  (10, 'CS Conversations',      'cs_(conversation|message)'),
  (10, 'CS Knowledge Base',     'cs_knowledge'),
  (10, 'CS Procedures (AOPs)',  'cs_procedure'),
  (10, 'CS Channels & Customers','cs_(channel|customer|platform_identit|phone_number)'),
  (10, 'CS Brand Configuration','cs_brand'),
  (10, 'CS Teams & Agent Profiles','cs_(team|agent_profile)'),
  (10, 'CS Voice',              '(cs_voice|cs_call|cs_telephony)'),
  (5,  'CS (other)',            'cs_')
),
fns_raw AS (
  SELECT p.oid, p.proname,
    CASE WHEN length(pg_get_function_arguments(p.oid)) > 110
         THEN substring(pg_get_function_arguments(p.oid), 1, 110) || '...'
         ELSE pg_get_function_arguments(p.oid) END AS args,
    CASE WHEN length(pg_get_function_result(p.oid)) > 40
         THEN substring(pg_get_function_result(p.oid), 1, 40) || '...'
         ELSE pg_get_function_result(p.oid) END AS rtype
  FROM pg_proc p JOIN pg_namespace n ON p.pronamespace = n.oid
  WHERE n.nspname = 'public' AND p.prokind = 'f'
),
fns_assigned AS (
  SELECT f.oid, f.proname, f.args, f.rtype, d.name AS dn, d.prio, d.pattern,
    row_number() OVER (PARTITION BY f.oid ORDER BY d.prio DESC NULLS LAST, length(d.pattern) DESC NULLS LAST) AS rn
  FROM fns_raw f LEFT JOIN domains d ON f.proname ~ d.pattern
),
fns AS (
  SELECT proname, args, rtype, COALESCE(dn, 'Unassigned') AS domain
  FROM fns_assigned WHERE rn = 1
),
tbls_raw AS (
  SELECT table_name AS name
  FROM information_schema.tables
  WHERE table_schema = 'public' AND table_type = 'BASE TABLE'
),
tbls_assigned AS (
  SELECT t.name, d.name AS dn, d.prio, d.pattern,
    row_number() OVER (PARTITION BY t.name ORDER BY d.prio DESC NULLS LAST, length(d.pattern) DESC NULLS LAST) AS rn
  FROM tbls_raw t LEFT JOIN domains d ON t.name ~ d.pattern
),
tbls AS (
  SELECT name, COALESCE(dn, 'Unassigned') AS domain
  FROM tbls_assigned WHERE rn = 1
),
trgs_raw AS (
  SELECT DISTINCT event_object_table AS tbl, trigger_name AS tname,
    action_timing || ' ' || event_manipulation AS timing
  FROM information_schema.triggers WHERE trigger_schema = 'public'
),
trgs_assigned AS (
  SELECT t.tbl, t.tname, t.timing, d.name AS dn, d.prio, d.pattern,
    row_number() OVER (PARTITION BY t.tbl, t.tname ORDER BY d.prio DESC NULLS LAST, length(d.pattern) DESC NULLS LAST) AS rn
  FROM trgs_raw t LEFT JOIN domains d ON t.tbl ~ d.pattern
),
trgs AS (
  SELECT tbl, tname, timing, COALESCE(dn, 'Unassigned') AS domain
  FROM trgs_assigned WHERE rn = 1
),
all_domains AS (
  SELECT DISTINCT domain FROM (
    SELECT domain FROM tbls UNION ALL SELECT domain FROM fns UNION ALL SELECT domain FROM trgs
  ) u
),
domain_blocks AS (
  SELECT
    d.domain,
    '## ' || d.domain || E'\n\n' ||
    COALESCE((SELECT string_agg('T: ' || name, E'\n' ORDER BY name) FROM tbls WHERE tbls.domain = d.domain) || E'\n', '') ||
    COALESCE((SELECT string_agg('F: ' || proname || '(' || args || ') -> ' || rtype, E'\n' ORDER BY proname) FROM fns WHERE fns.domain = d.domain) || E'\n', '') ||
    COALESCE((SELECT string_agg('X: ' || tbl || ' -> ' || tname || ' (' || timing || ')', E'\n' ORDER BY tbl, tname) FROM trgs WHERE trgs.domain = d.domain) || E'\n', '')
    AS body
  FROM all_domains d
),
header AS (
  SELECT
    '# Supabase Registry' || E'\n\n' ||
    '> Auto-generated by `scripts/regen_registry_supabase.sql`. Run on demand via the `registry-regenerate` skill.' || E'\n' ||
    '> Live truth is Supabase MCP — this file is a grep target only.' || E'\n' ||
    '> Project: wkevmsedchftztoolkmi' || E'\n' ||
    '> Last generated: ' || to_char(now() AT TIME ZONE 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS"Z"') || E'\n\n' ||
    'Legend: `T:` = table, `F:` = function (signature truncated; query MCP for full body), `X:` = trigger.' || E'\n\n' ||
    'Hard ban: never full-read this file. Always grep + read scoped. See `.cursor/rules/12-doc-search.mdc`.' || E'\n\n' ||
    '---' || E'\n\n' AS body
)
SELECT
  (SELECT body FROM header) ||
  string_agg(body, E'\n---\n\n' ORDER BY CASE WHEN domain = 'Unassigned' THEN 1 ELSE 0 END, domain)
FROM domain_blocks;
