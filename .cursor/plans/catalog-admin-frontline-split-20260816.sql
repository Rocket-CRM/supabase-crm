BEGIN;
-- Catalog: Admin portal and reports vs Front Line
-- run_id a6d2e8f1-4c70-4b19-9e33-20260816c004
-- Applied via Supabase MCP; kept here as the run artifact.

CREATE TEMP TABLE _catalog_run (run_id uuid PRIMARY KEY);
INSERT INTO _catalog_run VALUES ('a6d2e8f1-4c70-4b19-9e33-20260816c004');

CREATE TEMP TABLE _before_groups AS
SELECT to_jsonb(g.*) AS snap FROM internal_product_feature_group g
WHERE g.feature_group_key IN (
  'platform.governance',
  'platform.experience',
  'loyalty.frontline',
  'loyalty.analytics'
);

CREATE TEMP TABLE _before_features AS
SELECT to_jsonb(f.*) AS snap FROM internal_product_feature f
WHERE f.feature_key IN (
  'platform.governance.admin_shell',
  'platform.governance.pdpa_consent',
  'platform.governance.translation',
  'loyalty.analytics.reports',
  'loyalty.frontline.customer_360',
  'loyalty.frontline.assisted_actions'
);

-- Operator surfaces after the member-journey groups (store = 100)
UPDATE internal_product_feature_group
SET
  name = 'Member app UI CMS',
  sort_order = 105,
  updated_at = now()
WHERE feature_group_key = 'platform.experience';

UPDATE internal_product_feature_group
SET
  name = 'Admin portal and reports',
  summary = 'Loyalty admin: configure the program, Member 360, and 30+ reports. Privacy consent (PDPA) and languages sit inside admin.',
  sort_order = 110,
  updated_at = now()
WHERE feature_group_key = 'platform.governance';

UPDATE internal_product_feature_group
SET
  name = 'Front Line',
  summary = 'Store-staff workspace to look up a member and complete assisted actions.',
  sort_order = 120,
  updated_at = now()
WHERE feature_group_key = 'loyalty.frontline';

UPDATE internal_product_feature_group
SET
  name = 'RFM and funnels',
  summary = 'Score members by recency, frequency, and value, and report conversion across journey stages.',
  sort_order = 125,
  updated_at = now()
WHERE feature_group_key = 'loyalty.analytics';

UPDATE internal_product_feature f
SET
  name = 'Admin portal',
  name_th = 'Admin portal',
  summary = 'Invite your team, control what each role can see or change, and configure the loyalty program from admin — reward codes, tier earn rates, space settings, privacy consent (PDPA), and languages.',
  summary_th = 'เชิญทีม กำหนดว่าแต่ละ role ดูหรือแก้ได้อะไร และตั้งค่า loyalty จากแอดมิน — รหัสของรางวัล อัตราได้คะแนนตาม Tier การตั้งค่า Space ความยินยอม PDPA และภาษา',
  includes = '["reward codes","tier earn rates","space settings","privacy consent (PDPA)","languages","team roles"]'::jsonb,
  source_refs = '[{"kind":"requirements","path":"requirements/Admin_Panel.md","heading":"Overview"}]'::jsonb,
  last_verified_at = now(),
  sort_order = 10,
  updated_at = now()
WHERE feature_key = 'platform.governance.admin_shell';

UPDATE internal_product_feature f
SET
  feature_group_id = (SELECT id FROM internal_product_feature_group WHERE feature_group_key = 'platform.governance'),
  includes = '["Members","Member 360","Redemptions","Transactions","Campaigns"]'::jsonb,
  summary = 'More than 30 reports in the standard admin portal. Key areas: Members, Member 360, Redemptions, Transactions, and Campaigns.',
  summary_th = 'รายงานกว่า 30 ฉบับในแอดมินมาตรฐาน พื้นที่หลัก: Members, Member 360, การแลกของรางวัล, ธุรกรรม และ Campaign',
  source_refs = '[{"kind":"requirements","path":"docs/LOYALTY_REPORTS_MARKETING_BRIEF.md","heading":"Purpose"},{"kind":"requirements","path":"requirements/Analytics.md","heading":"Admin journey"}]'::jsonb,
  last_verified_at = now(),
  sort_order = 20,
  updated_at = now()
WHERE feature_key = 'loyalty.analytics.reports';

UPDATE internal_product_feature f
SET
  feature_group_id = (SELECT id FROM internal_product_feature_group WHERE feature_group_key = 'platform.governance'),
  name = 'Customer 360',
  summary = 'Open a member in admin (Member 360): status, tier progress, history, and context in one place.',
  summary_th = 'เปิดดูสมาชิกในแอดมิน (Member 360): สถานะ ความคืบหน้า Tier ประวัติ และบริบทในที่เดียว',
  source_refs = '[{"kind":"requirements","path":"requirements/Frontline_Admin_Actions.md","heading":"Overview"},{"kind":"requirements","path":"requirements/Activity_Attribution.md","heading":"Admin UI (loyalty-admin)"}]'::jsonb,
  last_verified_at = now(),
  sort_order = 30,
  updated_at = now()
WHERE feature_key = 'loyalty.frontline.customer_360';

UPDATE internal_product_feature f
SET
  sort_order = 40,
  last_verified_at = now(),
  updated_at = now()
WHERE feature_key = 'platform.governance.pdpa_consent';

UPDATE internal_product_feature f
SET
  sort_order = 50,
  last_verified_at = now(),
  updated_at = now()
WHERE feature_key = 'platform.governance.translation';

UPDATE internal_product_feature f
SET
  name = 'Front Line',
  name_th = 'Front Line',
  summary = 'Store staff look up a member and help them on the spot: adjust points, push a reward, mark a reward used, update profile, or change mobile and persona.',
  summary_th = 'พนักงานหน้าร้านค้นสมาชิกแล้วช่วยได้ทันที: ปรับคะแนน ส่งของรางวัล ทำเครื่องหมายว่าใช้แล้ว แก้โปรไฟล์ หรือเปลี่ยนเบอร์และ persona',
  includes = '["adjust points","push a reward","mark a reward used","update profile","change mobile","change persona"]'::jsonb,
  source_refs = '[{"kind":"requirements","path":"requirements/Frontline_Admin_Actions.md","heading":"Overview"},{"kind":"requirements","path":"requirements/feature-docs/rewards.md","heading":"4f. Push reward 1-to-1 & claim QR (frontline)"}]'::jsonb,
  last_verified_at = now(),
  sort_order = 10,
  updated_at = now()
WHERE feature_key = 'loyalty.frontline.assisted_actions';

INSERT INTO internal_product_catalog_change_log (
  run_id, entity_type, entity_key, change_type, before_snapshot, after_snapshot, source_refs
)
SELECT
  (SELECT run_id FROM _catalog_run),
  'feature_group',
  g.feature_group_key,
  'update',
  b.snap,
  to_jsonb(g.*),
  '[{"kind":"plan","path":".cursor/plans/catalog-admin-frontline-split-20260816.sql"}]'::jsonb
FROM internal_product_feature_group g
JOIN _before_groups b ON b.snap->>'feature_group_key' = g.feature_group_key;

INSERT INTO internal_product_catalog_change_log (
  run_id, entity_type, entity_key, change_type, before_snapshot, after_snapshot, source_refs
)
SELECT
  (SELECT run_id FROM _catalog_run),
  'feature',
  f.feature_key,
  CASE
    WHEN f.feature_key IN ('loyalty.analytics.reports', 'loyalty.frontline.customer_360') THEN 'move'
    ELSE 'update'
  END,
  b.snap,
  to_jsonb(f.*),
  f.source_refs
FROM internal_product_feature f
JOIN _before_features b ON b.snap->>'feature_key' = f.feature_key;

COMMIT;
