BEGIN;
-- Weekly catalog maintenance run_id d1f5a8c3-6e2b-4a91-9d44-20260817c002
-- REVIEW ONLY — do not apply without human approval (automation write policy).
-- Scope: provenance refresh for evidence-backed features; source_refs repairs for broken paths.
-- Conflicts left unchanged: see SUMMARY.md in this folder.

CREATE TEMP TABLE _catalog_run (run_id uuid PRIMARY KEY);
INSERT INTO _catalog_run VALUES ('d1f5a8c3-6e2b-4a91-9d44-20260817c002');

CREATE TEMP TABLE _before_features AS
SELECT to_jsonb(f.*) AS snap FROM internal_product_feature f
WHERE f.feature_key IN (
  'loyalty.currency.points',
  'loyalty.currency.tickets',
  'loyalty.currency.expiry',
  'loyalty.currency.earn_rate_basic',
  'loyalty.tier.ladder',
  'loyalty.tier.upgrade_conditions',
  'loyalty.tier.maintain_mode',
  'loyalty.campaign.mission_standard',
  'loyalty.campaign.mission_milestone',
  'loyalty.campaign.referral',
  'loyalty.reward.catalog',
  'platform.signup.login_methods',
  'loyalty.persona.tags_personas',
  'loyalty.store.master',
  'loyalty.earn.purchase_sync',
  'loyalty.integrations.open_api',
  'platform.governance.admin_shell',
  'customer_service.chat_voice.voice'
);

-- verify (copy unchanged): loyalty.currency.points
UPDATE internal_product_feature f SET
  source_refs = '[{"kind": "requirements", "path": "requirements/Currency.md", "heading": "Glossary of Terms"}]'::jsonb,
  last_verified_at = now(),
  updated_at = now()
WHERE f.feature_key = 'loyalty.currency.points';

-- verify (copy unchanged): loyalty.currency.tickets
UPDATE internal_product_feature f SET
  source_refs = '[{"kind": "requirements", "path": "requirements/Currency.md", "heading": "Glossary of Terms"}]'::jsonb,
  last_verified_at = now(),
  updated_at = now()
WHERE f.feature_key = 'loyalty.currency.tickets';

-- verify (copy unchanged): loyalty.currency.expiry
UPDATE internal_product_feature f SET
  source_refs = '[{"kind": "requirements", "path": "requirements/Currency.md", "heading": "Currency Expiry Management"}]'::jsonb,
  last_verified_at = now(),
  updated_at = now()
WHERE f.feature_key = 'loyalty.currency.expiry';

-- verify (copy unchanged): loyalty.currency.earn_rate_basic
UPDATE internal_product_feature f SET
  source_refs = '[{"kind": "requirements", "path": "requirements/Currency.md", "heading": "How Currency Award Mechanisms Work"}]'::jsonb,
  last_verified_at = now(),
  updated_at = now()
WHERE f.feature_key = 'loyalty.currency.earn_rate_basic';

-- verify (copy unchanged): loyalty.tier.ladder
UPDATE internal_product_feature f SET
  source_refs = '[{"kind": "requirements", "path": "requirements/Tier.md", "heading": "Core Tiering Concept"}]'::jsonb,
  last_verified_at = now(),
  updated_at = now()
WHERE f.feature_key = 'loyalty.tier.ladder';

-- verify (copy unchanged): loyalty.tier.upgrade_conditions
UPDATE internal_product_feature f SET
  source_refs = '[{"kind": "requirements", "path": "requirements/Tier.md", "heading": "Tier Progression Philosophy"}]'::jsonb,
  last_verified_at = now(),
  updated_at = now()
WHERE f.feature_key = 'loyalty.tier.upgrade_conditions';

-- verify (copy unchanged): loyalty.tier.maintain_mode
UPDATE internal_product_feature f SET
  source_refs = '[{"kind": "requirements", "path": "requirements/Tier.md", "heading": "Tier Progression Philosophy"}]'::jsonb,
  last_verified_at = now(),
  updated_at = now()
WHERE f.feature_key = 'loyalty.tier.maintain_mode';

-- verify (copy unchanged): loyalty.campaign.mission_standard
UPDATE internal_product_feature f SET
  source_refs = '[{"kind": "requirements", "path": "requirements/Mission.md", "heading": "Mission Types"}]'::jsonb,
  last_verified_at = now(),
  updated_at = now()
WHERE f.feature_key = 'loyalty.campaign.mission_standard';

-- verify (copy unchanged): loyalty.campaign.mission_milestone
UPDATE internal_product_feature f SET
  source_refs = '[{"kind": "requirements", "path": "requirements/Mission.md", "heading": "Mission Types"}]'::jsonb,
  last_verified_at = now(),
  updated_at = now()
WHERE f.feature_key = 'loyalty.campaign.mission_milestone';

-- verify (copy unchanged): loyalty.campaign.referral
UPDATE internal_product_feature f SET
  source_refs = '[{"kind": "requirements", "path": "requirements/Referral.md", "heading": "Core Referral Concept"}]'::jsonb,
  last_verified_at = now(),
  updated_at = now()
WHERE f.feature_key = 'loyalty.campaign.referral';

-- verify (copy unchanged): loyalty.reward.catalog
UPDATE internal_product_feature f SET
  source_refs = '[{"kind": "requirements", "path": "requirements/Reward.md", "heading": "Executive Summary"}]'::jsonb,
  last_verified_at = now(),
  updated_at = now()
WHERE f.feature_key = 'loyalty.reward.catalog';

-- verify (copy unchanged): platform.signup.login_methods
UPDATE internal_product_feature f SET
  source_refs = '[{"kind": "requirements", "path": "requirements/Signup_Login.md", "heading": "Authentication Methods Configuration"}]'::jsonb,
  last_verified_at = now(),
  updated_at = now()
WHERE f.feature_key = 'platform.signup.login_methods';

-- verify (copy unchanged): loyalty.persona.tags_personas
UPDATE internal_product_feature f SET
  source_refs = '[{"kind": "requirements", "path": "requirements/Tag_and_Persona.md", "heading": "Core Segmentation Concept"}]'::jsonb,
  last_verified_at = now(),
  updated_at = now()
WHERE f.feature_key = 'loyalty.persona.tags_personas';

-- verify (copy unchanged): loyalty.store.master
UPDATE internal_product_feature f SET
  source_refs = '[{"kind": "requirements", "path": "requirements/Store_Attribute_Classification.md", "heading": "1. store_master Table"}, {"kind": "requirements", "path": "requirements/Purchase_Transaction.md", "heading": "store_master (location context)"}]'::jsonb,
  last_verified_at = now(),
  updated_at = now()
WHERE f.feature_key = 'loyalty.store.master';

-- verify (copy unchanged): loyalty.earn.purchase_sync
UPDATE internal_product_feature f SET
  source_refs = '[{"kind": "requirements", "path": "requirements/Purchase_Transaction.md", "heading": "Currency Award Integration"}]'::jsonb,
  last_verified_at = now(),
  updated_at = now()
WHERE f.feature_key = 'loyalty.earn.purchase_sync';

-- provenance repair + verify: loyalty.integrations.open_api
UPDATE internal_product_feature f SET
  source_refs = '[{"kind": "requirements", "path": "requirements/REGISTRY_SUPABASE.md", "heading": "API Key & Asset"}, {"kind": "requirements", "path": "requirements/REGISTRY_SUPABASE.md", "heading": "Asset"}]'::jsonb,
  last_verified_at = now(),
  updated_at = now()
WHERE f.feature_key = 'loyalty.integrations.open_api';

-- provenance repair (Admin_Panel.md missing; registry-only evidence — claims not fully re-litigated): platform.governance.admin_shell
UPDATE internal_product_feature f SET
  source_refs = '[{"kind": "requirements", "path": "requirements/REGISTRY_SUPABASE.md", "heading": "Admin Panel"}]'::jsonb,
  updated_at = now()
WHERE f.feature_key = 'platform.governance.admin_shell';

-- provenance repair + verify: customer_service.chat_voice.voice
UPDATE internal_product_feature f SET
  source_refs = '[{"kind": "requirements", "path": "docs/cs_voice_architecture.md", "heading": "Architecture Overview"}]'::jsonb,
  last_verified_at = now(),
  updated_at = now()
WHERE f.feature_key = 'customer_service.chat_voice.voice';

INSERT INTO internal_product_catalog_change_log (
  run_id, entity_type, entity_key, change_type, before_snapshot, after_snapshot, source_refs
)
SELECT
  (SELECT run_id FROM _catalog_run),
  'feature',
  f.feature_key,
  'update',
  b.snap,
  to_jsonb(f.*),
  f.source_refs
FROM internal_product_feature f
JOIN _before_features b ON b.snap->>'feature_key' = f.feature_key;

COMMIT;
