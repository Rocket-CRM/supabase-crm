-- Product feature catalog rework 2026-08-12
-- Provenance + three-module public catalog + audit log
-- Applied via Supabase MCP; kept here as the run artifact.

BEGIN;

-- ---------------------------------------------------------------------------
-- 0) Run id
-- ---------------------------------------------------------------------------
CREATE TEMP TABLE _catalog_run (run_id uuid PRIMARY KEY);
INSERT INTO _catalog_run VALUES ('a8f3c2e1-5b4d-4e9a-9c1f-20260812c001');

-- ---------------------------------------------------------------------------
-- 1) Provenance columns
-- ---------------------------------------------------------------------------
ALTER TABLE internal_product_feature
  ADD COLUMN IF NOT EXISTS source_refs jsonb NOT NULL DEFAULT '[]'::jsonb,
  ADD COLUMN IF NOT EXISTS last_verified_at timestamptz;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conname = 'internal_product_feature_source_refs_is_array'
  ) THEN
    ALTER TABLE internal_product_feature
      ADD CONSTRAINT internal_product_feature_source_refs_is_array
      CHECK (jsonb_typeof(source_refs) = 'array');
  END IF;
END $$;

-- ---------------------------------------------------------------------------
-- 2) Append-only change log
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS internal_product_catalog_change_log (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  run_id uuid NOT NULL,
  entity_type text NOT NULL CHECK (entity_type = ANY (ARRAY[
    'module'::text, 'feature_group'::text, 'feature'::text,
    'package'::text, 'feature_package'::text
  ])),
  entity_key text NOT NULL,
  change_type text NOT NULL CHECK (change_type = ANY (ARRAY[
    'add'::text, 'update'::text, 'move'::text, 'deprecate'::text,
    'activate'::text, 'deactivate'::text,
    'package_assign'::text, 'package_unassign'::text
  ])),
  before_snapshot jsonb,
  after_snapshot jsonb,
  source_refs jsonb NOT NULL DEFAULT '[]'::jsonb,
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS internal_product_catalog_change_log_run_id_idx
  ON internal_product_catalog_change_log (run_id);

CREATE INDEX IF NOT EXISTS internal_product_catalog_change_log_entity_idx
  ON internal_product_catalog_change_log (entity_type, entity_key);

CREATE OR REPLACE FUNCTION trg_internal_product_catalog_change_log_append_only()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
  RAISE EXCEPTION 'internal_product_catalog_change_log is append-only';
END;
$$;

DROP TRIGGER IF EXISTS internal_product_catalog_change_log_no_update
  ON internal_product_catalog_change_log;
CREATE TRIGGER internal_product_catalog_change_log_no_update
  BEFORE UPDATE OR DELETE ON internal_product_catalog_change_log
  FOR EACH ROW
  EXECUTE FUNCTION trg_internal_product_catalog_change_log_append_only();

-- ---------------------------------------------------------------------------
-- 3) Snapshot helpers into temp
-- ---------------------------------------------------------------------------
CREATE TEMP TABLE _before_modules AS
SELECT to_jsonb(m.*) AS snap FROM internal_product_module m;

CREATE TEMP TABLE _before_groups AS
SELECT to_jsonb(g.*) AS snap FROM internal_product_feature_group g;

CREATE TEMP TABLE _before_features AS
SELECT to_jsonb(f.*) AS snap FROM internal_product_feature f;

-- ---------------------------------------------------------------------------
-- 4) Module rework: deactivate platform; rename amp/cs; refresh loyalty summary
-- ---------------------------------------------------------------------------
UPDATE internal_product_module m
SET
  name = 'Loyalty',
  summary = 'Acquisition through activation: foundation, points, rewards, tiers, campaigns, lifecycle automations, Customer 360, segmentation, and 30+ reports.',
  sort_order = 10,
  is_active = true,
  updated_at = now()
WHERE module_key = 'loyalty';

UPDATE internal_product_module m
SET
  is_active = false,
  summary = 'Deprecated as a public module. Features folded into Loyalty; stable feature keys preserved.',
  updated_at = now()
WHERE module_key = 'platform';

UPDATE internal_product_module m
SET
  module_key = 'marketing_automation',
  name = 'Marketing Automation',
  summary = 'Deterministic multi-step workflows, AI decisioning agents (ACT/WAIT/SKIP), and AI analysis/recommendations.',
  sort_order = 20,
  is_active = true,
  updated_at = now()
WHERE module_key = 'amp';

UPDATE internal_product_module m
SET
  module_key = 'customer_service',
  name = 'Customer Service',
  summary = 'Omnichannel inbox operations, AI service agent with AOPs/actions, and supervisor quality scoring.',
  sort_order = 30,
  is_active = true,
  updated_at = now()
WHERE module_key = 'cs';

-- ---------------------------------------------------------------------------
-- 5) Fold platform groups into Loyalty (preserve group + feature keys)
-- ---------------------------------------------------------------------------
UPDATE internal_product_feature_group g
SET
  module_id = (SELECT id FROM internal_product_module WHERE module_key = 'loyalty'),
  sort_order = CASE g.feature_group_key
    WHEN 'platform.signup' THEN 1
    WHEN 'platform.experience' THEN 2
    WHEN 'platform.governance' THEN 3
    ELSE g.sort_order
  END,
  summary = CASE g.feature_group_key
    WHEN 'platform.signup' THEN 'Foundation and acquisition: how members join and complete signup.'
    WHEN 'platform.experience' THEN 'Member app layout and homepage composition.'
    WHEN 'platform.governance' THEN 'Admin permissions, privacy consent, and languages.'
    ELSE g.summary
  END,
  updated_at = now()
WHERE g.module_id = (SELECT id FROM internal_product_module WHERE module_key = 'platform');

-- Rename lifecycle group language
UPDATE internal_product_feature_group g
SET
  name = 'Lifecycle automations',
  summary = 'Automate loyalty actions around signup, birthday, anniversary, and tier change.',
  updated_at = now()
WHERE feature_group_key = 'loyalty.lifecycle';

-- Clarify analytics / persona group names for taxonomy
UPDATE internal_product_feature_group g
SET
  name = 'Segmentation and RFM',
  summary = 'Tags, personas, user types, RFM scoring, and funnel stages for targeting.',
  updated_at = now()
WHERE feature_group_key = 'loyalty.persona';

UPDATE internal_product_feature_group g
SET
  name = 'Customer profile and Customer 360',
  summary = 'Profile fields/forms plus Front Line Customer 360 for service and assisted actions.',
  updated_at = now()
WHERE feature_group_key = 'loyalty.forms';

UPDATE internal_product_feature_group g
SET
  name = 'Analytics and reports',
  summary = '30+ reports spanning loyalty performance, campaigns, and member intelligence.',
  updated_at = now()
WHERE feature_group_key = 'loyalty.analytics';

UPDATE internal_product_feature_group g
SET
  name = 'Admin, data operations, and integrations',
  summary = 'Imports/exports, Open API, storefront integrations, and operational data tools.',
  updated_at = now()
WHERE feature_group_key = 'loyalty.ops';

-- Move RFM/funnel under analytics already; move frontline next to forms for narrative — keep keys.
-- Move customer 360 group naming
UPDATE internal_product_feature_group g
SET
  name = 'Front Line / Customer 360',
  summary = 'Admin Customer 360 and assisted member actions.',
  updated_at = now()
WHERE feature_group_key = 'loyalty.frontline';

-- ---------------------------------------------------------------------------
-- 6) Feature copy corrections (Loyalty)
-- ---------------------------------------------------------------------------
UPDATE internal_product_feature f
SET
  name = 'Signup lifecycle automation',
  summary = 'Automatically award points, rewards, or tags when members complete signup.',
  updated_at = now()
WHERE feature_key = 'loyalty.lifecycle.signup_outcomes';

UPDATE internal_product_feature f
SET
  name = 'Birthday lifecycle automation',
  summary = 'Automatically trigger loyalty outcomes around a member birthday.',
  updated_at = now()
WHERE feature_key = 'loyalty.lifecycle.birthday';

UPDATE internal_product_feature f
SET
  name = 'Anniversary lifecycle automation',
  summary = 'Automatically trigger loyalty outcomes on membership anniversary.',
  updated_at = now()
WHERE feature_key = 'loyalty.lifecycle.anniversary';

UPDATE internal_product_feature f
SET
  name = 'Tier-change lifecycle automation',
  summary = 'Automatically trigger outcomes when a member upgrades or downgrades tier.',
  updated_at = now()
WHERE feature_key = 'loyalty.lifecycle.tier_change';

UPDATE internal_product_feature f
SET
  summary = 'Set different point earn rates by channel (and related dimensions) — not just one flat rate.',
  includes = '["Example: in-store 1 pt / 25 THB, marketplace 1 pt / 50 THB.","Example: Gold earns faster than Silver."]'::jsonb,
  updated_at = now()
WHERE feature_key = 'loyalty.currency.earn_rate_advanced';

UPDATE internal_product_feature f
SET
  summary = 'Multiply points for selected products or categories — for example double points on skincare.',
  includes = '["Example: 2x points on skincare this month.","Example: double points on a featured category."]'::jsonb,
  updated_at = now()
WHERE feature_key = 'loyalty.currency.multipliers';

UPDATE internal_product_feature f
SET
  summary = '30+ reports for purchases, points, redemptions, campaigns, and members — so the team can see program performance.',
  includes = '["Covers loyalty, campaign, automation, and service reporting surfaces."]'::jsonb,
  updated_at = now()
WHERE feature_key = 'loyalty.analytics.reports';

UPDATE internal_product_feature f
SET
  name = 'Customer 360 / Front Line',
  summary = 'Admin Customer 360 for service: status, tier progress, history, and member context.',
  updated_at = now()
WHERE feature_key = 'loyalty.frontline.customer_360';

-- ---------------------------------------------------------------------------
-- 7) Packages: move foundation features onto loyalty packages; deactivate platform_base
-- ---------------------------------------------------------------------------
WITH loyalty_pkgs AS (
  SELECT id, package_key FROM internal_product_package
  WHERE package_key IN ('loyalty_core', 'loyalty_advanced')
),
platform_feats AS (
  SELECT f.id AS feature_id
  FROM internal_product_feature f
  WHERE f.feature_key LIKE 'platform.%'
),
ins AS (
  INSERT INTO internal_product_feature_package (feature_id, package_id)
  SELECT pf.feature_id, lp.id
  FROM platform_feats pf
  CROSS JOIN loyalty_pkgs lp
  ON CONFLICT DO NOTHING
  RETURNING feature_id, package_id
)
INSERT INTO internal_product_catalog_change_log (run_id, entity_type, entity_key, change_type, after_snapshot, source_refs)
SELECT
  (SELECT run_id FROM _catalog_run),
  'feature_package',
  f.feature_key || '→' || p.package_key,
  'package_assign',
  jsonb_build_object('feature_id', ins.feature_id, 'package_id', ins.package_id),
  '[{"kind":"requirements","path":"requirements/Signup_Login.md","heading":"Signup"}]'::jsonb
FROM ins
JOIN internal_product_feature f ON f.id = ins.feature_id
JOIN internal_product_package p ON p.id = ins.package_id;

DELETE FROM internal_product_feature_package fp
USING internal_product_package p, internal_product_feature f
WHERE fp.package_id = p.id
  AND fp.feature_id = f.id
  AND p.package_key = 'platform_base';

UPDATE internal_product_package
SET
  is_active = false,
  summary = 'Retired as a public package after App foundation features folded into Loyalty packages.',
  updated_at = now()
WHERE package_key = 'platform_base';

UPDATE internal_product_package
SET
  module_id = (SELECT id FROM internal_product_module WHERE module_key = 'loyalty'),
  updated_at = now()
WHERE package_key IN ('loyalty_core', 'loyalty_advanced');

-- New module packages for AMP / CS
INSERT INTO internal_product_package (package_key, module_id, name, summary, sort_order, is_active)
SELECT 'marketing_automation_core', m.id, 'Marketing Automation', 'Core Marketing Automation capabilities.', 30, true
FROM internal_product_module m WHERE m.module_key = 'marketing_automation'
ON CONFLICT (package_key) DO UPDATE
SET module_id = EXCLUDED.module_id, name = EXCLUDED.name, summary = EXCLUDED.summary,
    is_active = true, updated_at = now();

INSERT INTO internal_product_package (package_key, module_id, name, summary, sort_order, is_active)
SELECT 'customer_service_core', m.id, 'Customer Service', 'Core Customer Service capabilities.', 40, true
FROM internal_product_module m WHERE m.module_key = 'customer_service'
ON CONFLICT (package_key) DO UPDATE
SET module_id = EXCLUDED.module_id, name = EXCLUDED.name, summary = EXCLUDED.summary,
    is_active = true, updated_at = now();

-- ---------------------------------------------------------------------------
-- 8) Seed Marketing Automation groups + features
-- ---------------------------------------------------------------------------
WITH m AS (
  SELECT id FROM internal_product_module WHERE module_key = 'marketing_automation'
)
INSERT INTO internal_product_feature_group (module_id, feature_group_key, name, summary, sort_order, is_active)
SELECT m.id, v.feature_group_key, v.name, v.summary, v.sort_order, true
FROM m
CROSS JOIN (VALUES
  ('marketing_automation.workflows', 'Deterministic multi-step workflows', 'Rule-based journeys that condition on customer data and execute messages plus loyalty actions.', 10),
  ('marketing_automation.ai_decisioning', 'AI decisioning agents', 'Goal-driven agents that review customer context and choose ACT, WAIT, or SKIP.', 20),
  ('marketing_automation.ai_analysis', 'AI analysis and recommendations', 'Analysis of campaign/workflow performance with recommended next improvements.', 30)
) AS v(feature_group_key, name, summary, sort_order)
ON CONFLICT (feature_group_key) DO UPDATE
SET module_id = EXCLUDED.module_id, name = EXCLUDED.name, summary = EXCLUDED.summary,
    sort_order = EXCLUDED.sort_order, is_active = true, updated_at = now();

WITH feats(feature_key, group_key, name, summary, includes, status, sort_order, source_path, source_heading) AS (
  VALUES
  ('marketing_automation.workflows.multi_step', 'marketing_automation.workflows',
   'Multi-step workflow automation',
   'Marketers build deterministic journeys that react to customer events, wait, branch, send messages, and run loyalty actions.',
   '["Example: welcome series after signup with wait + purchase branch."]'::jsonb,
   'ga', 10, 'requirements/AMP_Workflows.md', 'Scope'),
  ('marketing_automation.workflows.audiences', 'marketing_automation.workflows',
   'Audience membership automation',
   'Maintain dynamic or static audiences and use entry/exit as workflow triggers and targeting.',
   '[]'::jsonb,
   'ga', 20, 'requirements/AMP_Workflows.md', 'Audience Membership'),
  ('marketing_automation.ai_decisioning.agent', 'marketing_automation.ai_decisioning',
   'AI decisioning agent',
   'Configure goals, allowed actions, outcomes, and constraints; the agent chooses ACT, WAIT, or SKIP per member.',
   '["Example: win-back agent waits, then awards points and sends LINE if still inactive."]'::jsonb,
   'ga', 10, 'requirements/AMP - AI Decisioning.md', 'Vision'),
  ('marketing_automation.ai_analysis.recommendations', 'marketing_automation.ai_analysis',
   'AI analysis and recommendations',
   'Analyze workflow and agent results, then recommend what marketers should change next.',
   '["Advisory only — does not ACT on customers by itself."]'::jsonb,
   'ga', 10, 'docs/AMP_LIFECYCLE_AUTOMATION.md', 'Current Production Shape')
)
INSERT INTO internal_product_feature (
  feature_group_id, feature_key, name, summary, includes, status, sort_order, is_active,
  source_refs, last_verified_at
)
SELECT
  g.id,
  feats.feature_key,
  feats.name,
  feats.summary,
  feats.includes,
  feats.status,
  feats.sort_order,
  true,
  jsonb_build_array(jsonb_build_object(
    'kind', 'requirements',
    'path', feats.source_path,
    'heading', feats.source_heading
  )),
  now()
FROM feats
JOIN internal_product_feature_group g ON g.feature_group_key = feats.group_key
ON CONFLICT (feature_key) DO UPDATE
SET
  feature_group_id = EXCLUDED.feature_group_id,
  name = EXCLUDED.name,
  summary = EXCLUDED.summary,
  includes = EXCLUDED.includes,
  status = EXCLUDED.status,
  sort_order = EXCLUDED.sort_order,
  is_active = true,
  source_refs = EXCLUDED.source_refs,
  last_verified_at = EXCLUDED.last_verified_at,
  updated_at = now();

INSERT INTO internal_product_feature_package (feature_id, package_id)
SELECT f.id, p.id
FROM internal_product_feature f
JOIN internal_product_package p ON p.package_key = 'marketing_automation_core'
WHERE f.feature_key LIKE 'marketing_automation.%'
ON CONFLICT DO NOTHING;

-- ---------------------------------------------------------------------------
-- 9) Seed Customer Service groups + features
-- ---------------------------------------------------------------------------
WITH m AS (
  SELECT id FROM internal_product_module WHERE module_key = 'customer_service'
)
INSERT INTO internal_product_feature_group (module_id, feature_group_key, name, summary, sort_order, is_active)
SELECT m.id, v.feature_group_key, v.name, v.summary, v.sort_order, true
FROM m
CROSS JOIN (VALUES
  ('customer_service.connectivity', 'Omnichannel inbox and connectivity', 'Connect channels and unify customer identity into one inbox context.', 10),
  ('customer_service.chat_voice', 'Chat and voice', 'Handle messaging and voice conversations on the same service surface.', 20),
  ('customer_service.agent_productivity', 'Agent productivity', 'Quick replies, knowledge search, and live-assist tools for agents.', 30),
  ('customer_service.routing_workflows', 'Routing and chatbot workflows', 'Route conversations and run chatbot / rules automation before or beside agents.', 40),
  ('customer_service.analytics', 'Service analytics', 'Operational analytics for volume, speed, CSAT, and containment.', 50),
  ('customer_service.ai_agent', 'AI service agent', 'Brand AI that handles or assists conversations under configured guardrails.', 60),
  ('customer_service.aop_actions', 'AOPs, knowledge, and customer actions', 'Procedures, knowledge retrieval, and customer actions the AI or agent can run.', 70),
  ('customer_service.supervisor_ai', 'Supervisor AI and quality scoring', 'Quality scoring and supervisor review for human and AI cases.', 80)
) AS v(feature_group_key, name, summary, sort_order)
ON CONFLICT (feature_group_key) DO UPDATE
SET module_id = EXCLUDED.module_id, name = EXCLUDED.name, summary = EXCLUDED.summary,
    sort_order = EXCLUDED.sort_order, is_active = true, updated_at = now();

WITH feats(feature_key, group_key, name, summary, includes, status, sort_order, source_path, source_heading) AS (
  VALUES
  ('customer_service.connectivity.omnichannel_inbox', 'customer_service.connectivity',
   'Omnichannel unified inbox',
   'Agents work one inbox across connected channels with a unified customer record.',
   '[]'::jsonb, 'ga', 10, 'requirements/CS_Unified_Inbox.md', 'Overview'),
  ('customer_service.connectivity.channel_connectors', 'customer_service.connectivity',
   'Channel connectors',
   'Connect marketplaces, messaging apps, email, web, SMS, and related surfaces into CS.',
   '[]'::jsonb, 'ga', 20, 'requirements/CS_Channel_Connectors.md', 'Overview'),
  ('customer_service.connectivity.phone_numbers', 'customer_service.connectivity',
   'Phone number management',
   'Provision and manage phone numbers used for voice and SMS service journeys.',
   '[]'::jsonb, 'ga', 30, 'requirements/CS_Phone_Number_Purchasing.md', 'Overview'),
  ('customer_service.chat_voice.chat', 'customer_service.chat_voice',
   'Chat conversations',
   'Handle asynchronous chat conversations with full history and agent tools.',
   '[]'::jsonb, 'ga', 10, 'requirements/CS_Conversations.md', 'Overview'),
  ('customer_service.chat_voice.voice', 'customer_service.chat_voice',
   'Voice console',
   'Handle voice contacts with the same customer context used for chat.',
   '[]'::jsonb, 'ga', 20, 'requirements/CS_Voice.md', 'Overview'),
  ('customer_service.agent_productivity.quick_replies', 'customer_service.agent_productivity',
   'Quick replies',
   'Agents insert approved reply snippets to answer faster with consistent tone.',
   '[]'::jsonb, 'ga', 10, 'requirements/CS_Platform_Features.md', 'Overview'),
  ('customer_service.agent_productivity.knowledge_search', 'customer_service.agent_productivity',
   'Knowledge search for agents',
   'Agents search the knowledge base while handling a live conversation.',
   '[]'::jsonb, 'ga', 20, 'requirements/CS_Knowledge_Base.md', 'Overview'),
  ('customer_service.agent_productivity.live_assist', 'customer_service.agent_productivity',
   'Live assist',
   'Assist agents mid-conversation with suggested replies and context.',
   '[]'::jsonb, 'ga', 30, 'requirements/CS_Live_Assist.md', 'Overview'),
  ('customer_service.routing_workflows.routing', 'customer_service.routing_workflows',
   'Routing and assignment',
   'Route conversations to queues, skills, or agents based on rules.',
   '[]'::jsonb, 'ga', 10, 'requirements/CS_Rules_Engine.md', 'Overview'),
  ('customer_service.routing_workflows.chatbot_flows', 'customer_service.routing_workflows',
   'Chatbot flows',
   'Run visual chatbot workflows before or beside human agents.',
   '[]'::jsonb, 'ga', 20, 'requirements/CS_Rules_Engine.md', 'Overview'),
  ('customer_service.analytics.service_analytics', 'customer_service.analytics',
   'Service analytics',
   'Report conversation volume, response times, CSAT, containment, and agent productivity.',
   '[]'::jsonb, 'ga', 10, 'requirements/CS_Analytics.md', 'Overview'),
  ('customer_service.ai_agent.brand_ai', 'customer_service.ai_agent',
   'AI service agent',
   'Brand-configured AI handles or assists conversations under tone, language, and escalation rules.',
   '[]'::jsonb, 'ga', 10, 'requirements/CS_AI_System.md', 'Overview'),
  ('customer_service.aop_actions.aops', 'customer_service.aop_actions',
   'Agent operating procedures (AOPs)',
   'Define per-intent procedures the AI follows when resolving customer issues.',
   '[]'::jsonb, 'ga', 10, 'requirements/CS_Procedures.md', 'Overview'),
  ('customer_service.aop_actions.knowledge_base', 'customer_service.aop_actions',
   'Knowledge base',
   'Store and retrieve service knowledge with citations for agents and AI.',
   '[]'::jsonb, 'ga', 20, 'requirements/CS_Knowledge_Base.md', 'Overview'),
  ('customer_service.aop_actions.customer_actions', 'customer_service.aop_actions',
   'Customer actions',
   'Run permitted customer actions (lookups, loyalty actions, integrations) from service flows.',
   '[]'::jsonb, 'ga', 30, 'requirements/CS_Actions.md', 'Overview'),
  ('customer_service.supervisor_ai.quality_scoring', 'customer_service.supervisor_ai',
   'Quality scoring',
   'Score human and AI conversations for quality, policy adherence, and coaching signals.',
   '[]'::jsonb, 'ga', 10, 'requirements/CS_AI_System.md', 'Overview'),
  ('customer_service.supervisor_ai.watchtower', 'customer_service.supervisor_ai',
   'Supervisor AI / Watchtower',
   'Supervisor review that inspects AI and human cases and feeds prompt/AOP improvement.',
   '[]'::jsonb, 'ga', 20, 'requirements/CS_AI_System.md', 'Overview')
)
INSERT INTO internal_product_feature (
  feature_group_id, feature_key, name, summary, includes, status, sort_order, is_active,
  source_refs, last_verified_at
)
SELECT
  g.id,
  feats.feature_key,
  feats.name,
  feats.summary,
  feats.includes,
  feats.status,
  feats.sort_order,
  true,
  jsonb_build_array(jsonb_build_object(
    'kind', 'requirements',
    'path', feats.source_path,
    'heading', feats.source_heading
  )),
  now()
FROM feats
JOIN internal_product_feature_group g ON g.feature_group_key = feats.group_key
ON CONFLICT (feature_key) DO UPDATE
SET
  feature_group_id = EXCLUDED.feature_group_id,
  name = EXCLUDED.name,
  summary = EXCLUDED.summary,
  includes = EXCLUDED.includes,
  status = EXCLUDED.status,
  sort_order = EXCLUDED.sort_order,
  is_active = true,
  source_refs = EXCLUDED.source_refs,
  last_verified_at = EXCLUDED.last_verified_at,
  updated_at = now();

INSERT INTO internal_product_feature_package (feature_id, package_id)
SELECT f.id, p.id
FROM internal_product_feature f
JOIN internal_product_package p ON p.package_key = 'customer_service_core'
WHERE f.feature_key LIKE 'customer_service.%'
ON CONFLICT DO NOTHING;

-- ---------------------------------------------------------------------------
-- 10) Backfill source_refs + last_verified_at for existing active features
-- ---------------------------------------------------------------------------
UPDATE internal_product_feature f
SET
  source_refs = CASE
    WHEN f.feature_key LIKE 'platform.signup%' THEN '[{"kind":"requirements","path":"requirements/Signup_Login.md","heading":"Signup"}]'::jsonb
    WHEN f.feature_key LIKE 'platform.governance.pdpa%' THEN '[{"kind":"requirements","path":"requirements/Authentication.md","heading":"PDPA"}]'::jsonb
    WHEN f.feature_key LIKE 'platform.governance.translation%' THEN '[{"kind":"requirements","path":"requirements/Translation_System.md","heading":"Overview"}]'::jsonb
    WHEN f.feature_key LIKE 'platform.governance.admin%' THEN '[{"kind":"requirements","path":"requirements/Authentication.md","heading":"Admin"}]'::jsonb
    WHEN f.feature_key LIKE 'platform.experience%' THEN '[{"kind":"requirements","path":"requirements/Signup_Login.md","heading":"Display"}]'::jsonb
    WHEN f.feature_key LIKE 'loyalty.currency%' THEN '[{"kind":"requirements","path":"requirements/Currency.md","heading":"Overview"}]'::jsonb
    WHEN f.feature_key LIKE 'loyalty.earn%' THEN '[{"kind":"requirements","path":"requirements/Purchase_Transaction.md","heading":"Overview"}]'::jsonb
    WHEN f.feature_key LIKE 'loyalty.reward%' THEN '[{"kind":"requirements","path":"requirements/Reward.md","heading":"Overview"}]'::jsonb
    WHEN f.feature_key LIKE 'loyalty.burn%' THEN '[{"kind":"requirements","path":"requirements/Currency.md","heading":"Burn"}]'::jsonb
    WHEN f.feature_key LIKE 'loyalty.tier%' THEN '[{"kind":"requirements","path":"requirements/Tier.md","heading":"Overview"}]'::jsonb
    WHEN f.feature_key LIKE 'loyalty.campaign.mission%' THEN '[{"kind":"requirements","path":"requirements/Mission.md","heading":"Overview"}]'::jsonb
    WHEN f.feature_key LIKE 'loyalty.campaign.referral%' THEN '[{"kind":"requirements","path":"requirements/Referral.md","heading":"Overview"}]'::jsonb
    WHEN f.feature_key LIKE 'loyalty.campaign%' THEN '[{"kind":"requirements","path":"requirements/Mission.md","heading":"Overview"}]'::jsonb
    WHEN f.feature_key LIKE 'loyalty.forms%' THEN '[{"kind":"requirements","path":"requirements/Forms.md","heading":"Overview"}]'::jsonb
    WHEN f.feature_key LIKE 'loyalty.lifecycle%' THEN '[{"kind":"requirements","path":"docs/AMP_LIFECYCLE_AUTOMATION.md","heading":"Batch lifecycle"}]'::jsonb
    WHEN f.feature_key LIKE 'loyalty.persona%' THEN '[{"kind":"requirements","path":"requirements/Tag_and_Persona.md","heading":"Overview"}]'::jsonb
    WHEN f.feature_key LIKE 'loyalty.store%' THEN '[{"kind":"requirements","path":"requirements/Store_Attribute_Classification.md","heading":"Overview"}]'::jsonb
    WHEN f.feature_key LIKE 'loyalty.frontline%' THEN '[{"kind":"requirements","path":"requirements/Authentication.md","heading":"Front Line"}]'::jsonb
    WHEN f.feature_key LIKE 'loyalty.analytics%' THEN '[{"kind":"requirements","path":"docs/LOYALTY_REPORTS_MARKETING_BRIEF.md","heading":"Purpose"}]'::jsonb
    WHEN f.feature_key LIKE 'loyalty.ops%' THEN '[{"kind":"requirements","path":"requirements/REGISTRY_SUPABASE.md","heading":"Overview"}]'::jsonb
    WHEN f.feature_key LIKE 'loyalty.storefront%' THEN '[{"kind":"requirements","path":"requirements/Ecommerce_Marketplace_Integration.md","heading":"Overview"}]'::jsonb
    WHEN f.feature_key LIKE 'loyalty.stored_value%' THEN '[{"kind":"requirements","path":"requirements/Currency.md","heading":"Stored value"}]'::jsonb
    WHEN f.feature_key LIKE 'loyalty.event_promo%' THEN '[{"kind":"requirements","path":"requirements/Purchase_Transaction.md","heading":"Event promo"}]'::jsonb
    WHEN f.feature_key LIKE 'loyalty.integrations%' THEN '[{"kind":"requirements","path":"docs/Rocket Loyalty Open API Documentation.md","heading":"Overview"}]'::jsonb
    ELSE f.source_refs
  END,
  last_verified_at = COALESCE(f.last_verified_at, now()),
  updated_at = now()
WHERE f.is_active = true
  AND (f.source_refs = '[]'::jsonb OR f.last_verified_at IS NULL);

-- ---------------------------------------------------------------------------
-- 11) Audit log for module / group / feature deltas in this run
-- ---------------------------------------------------------------------------
INSERT INTO internal_product_catalog_change_log (run_id, entity_type, entity_key, change_type, before_snapshot, after_snapshot, source_refs)
SELECT
  (SELECT run_id FROM _catalog_run),
  'module',
  m.module_key,
  CASE WHEN m.is_active THEN 'update' ELSE 'deactivate' END,
  b.snap,
  to_jsonb(m.*),
  '[{"kind":"plan","path":".cursor/plans/product-feature-catalog-maintenance.md","heading":"Deliverable 2"}]'::jsonb
FROM internal_product_module m
LEFT JOIN _before_modules b ON b.snap->>'module_key' = m.module_key
   OR (m.module_key = 'marketing_automation' AND b.snap->>'module_key' = 'amp')
   OR (m.module_key = 'customer_service' AND b.snap->>'module_key' = 'cs')
WHERE m.module_key IN ('loyalty', 'platform', 'marketing_automation', 'customer_service');

INSERT INTO internal_product_catalog_change_log (run_id, entity_type, entity_key, change_type, before_snapshot, after_snapshot, source_refs)
SELECT
  (SELECT run_id FROM _catalog_run),
  'feature_group',
  g.feature_group_key,
  CASE WHEN b.snap IS NULL THEN 'add' ELSE 'update' END,
  b.snap,
  to_jsonb(g.*),
  '[{"kind":"plan","path":".cursor/plans/product-feature-catalog-maintenance.md","heading":"Deliverable 2"}]'::jsonb
FROM internal_product_feature_group g
LEFT JOIN _before_groups b ON b.snap->>'feature_group_key' = g.feature_group_key
WHERE g.feature_group_key LIKE 'marketing_automation.%'
   OR g.feature_group_key LIKE 'customer_service.%'
   OR g.feature_group_key LIKE 'platform.%'
   OR g.feature_group_key IN (
     'loyalty.lifecycle', 'loyalty.persona', 'loyalty.forms',
     'loyalty.analytics', 'loyalty.ops', 'loyalty.frontline'
   );

INSERT INTO internal_product_catalog_change_log (run_id, entity_type, entity_key, change_type, before_snapshot, after_snapshot, source_refs)
SELECT
  (SELECT run_id FROM _catalog_run),
  'feature',
  f.feature_key,
  CASE WHEN b.snap IS NULL THEN 'add' ELSE 'update' END,
  b.snap,
  to_jsonb(f.*),
  f.source_refs
FROM internal_product_feature f
LEFT JOIN _before_features b ON b.snap->>'feature_key' = f.feature_key
WHERE f.feature_key LIKE 'marketing_automation.%'
   OR f.feature_key LIKE 'customer_service.%'
   OR f.feature_key LIKE 'loyalty.lifecycle.%'
   OR f.feature_key IN (
     'loyalty.currency.earn_rate_advanced',
     'loyalty.currency.multipliers',
     'loyalty.analytics.reports',
     'loyalty.frontline.customer_360'
   );

INSERT INTO internal_product_catalog_change_log (run_id, entity_type, entity_key, change_type, before_snapshot, after_snapshot, source_refs)
SELECT
  (SELECT run_id FROM _catalog_run),
  'package',
  p.package_key,
  CASE
    WHEN p.package_key = 'platform_base' THEN 'deactivate'
    WHEN p.package_key IN ('marketing_automation_core', 'customer_service_core') THEN 'add'
    ELSE 'update'
  END,
  NULL,
  to_jsonb(p.*),
  '[{"kind":"plan","path":".cursor/plans/product-feature-catalog-maintenance.md","heading":"Deliverable 4"}]'::jsonb
FROM internal_product_package p
WHERE p.package_key IN (
  'platform_base', 'loyalty_core', 'loyalty_advanced',
  'marketing_automation_core', 'customer_service_core'
);

COMMIT;
