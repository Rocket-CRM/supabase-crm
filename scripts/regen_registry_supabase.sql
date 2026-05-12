-- regen_registry_supabase.sql
-- Emits the entire content of requirements/REGISTRY_SUPABASE.md in one column.
-- Run via psql -t -A -X -f scripts/regen_registry_supabase.sql or via Supabase MCP.
-- Output: one row, one column, the full markdown text.

WITH
domains(prio, name, pattern) AS (VALUES
  (15, 'Tier',                  'tier'),
  (15, 'Currency',              '(wallet|currency|point|ticket|expiry|earn_factor|burn)'),
  (15, 'Reward',                '(reward|redemption|promo_code)'),
  (15, 'Mission',               'mission'),
  (15, 'Referral',              'referral'),
  (20, 'Signup Code Validation','signup_code'),
  (15, 'Signup & Login',        '(signup|login)'),
  (15, 'Auth (LINE/JWT/OTP)',   '(jwt|otp|line_login|line_auth|merchant_auth)'),
  (15, 'Forms & User Profile',  '(form|user_field|user_io)'),
  (15, 'Customer Import',       '(user_import|bulk_import|bulk_upsert)'),
  (15, 'Store Classification',  '(store_|location_|partner_)'),
  (15, 'Tag & Persona',         '(persona|user_tag|tag_master|tag_assignment)'),
  (15, 'Activity & Earning',    '(activity_|earning_)'),
  (15, 'Purchase Transaction',  '(purchase|transaction_|ledger)'),
  (15, 'Event Promotion',       'event_promo'),
  (15, 'Display Settings',      '(display_settings|display_block)'),
  (15, 'Translation',           'translation'),
  (15, 'Internal Knowledge',    '(internal_knowledge|knowledge_block|feature_item)'),
  (15, 'Admin Panel',           '(admin_user|admin_role|admin_menu|admin_analytics|superadmin|platform_admin)'),
  (15, 'BigCommerce Storefront API', 'bigcommerce'),
  (15, 'AMP Workflows',         '(workflow|amp_agent|amp_analysis)'),
  (15, 'Receipt / OCR',         '(receipt|ocr_)'),
  (15, 'Resource Content',      '(content_resource|resource_content|quick_reply|canned_response|media_resource)'),
  (15, 'Action Macro',          '(action_macro|macro_)'),
  (15, 'Universal Action System','(action_registry|action_caller_config|rule_type_registry|entity_registry|intent_registry)'),
  (15, 'Stored Value Card',     '(svc_|stored_value_card)'),
  (15, 'Checkin',               'checkin'),
  (15, 'Campaign',              'campaign'),
  (15, 'API Key & Asset',       '(api_key|api_create_or_update_asset|api_find_asset|api_get_asset|api_update_asset|api_assign_package)'),
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
