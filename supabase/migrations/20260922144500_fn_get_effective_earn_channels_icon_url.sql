-- fn_get_effective_earn_channels: expose icon_url for bff_get_earn_channels / Shopify hub
-- Completes 20260922130000_earn_channel_icon_url (BFF already selects c.icon_url).

DROP FUNCTION IF EXISTS public.fn_get_effective_earn_channels(uuid, text, boolean);

CREATE FUNCTION public.fn_get_effective_earn_channels(p_merchant_id uuid, p_language text DEFAULT NULL::text, p_include_admin_metadata boolean DEFAULT false)
 RETURNS TABLE(id uuid, override_id uuid, registry_id uuid, channel_code text, channel_type text, method_type text, channel_name text, headline text, description text, banner_urls text[], icon_url text, display_order integer, config jsonb, button_action jsonb, active boolean, howto_banners text[], howto_description text, stores_banner text, marketplace_platforms text[], default_award_scope text, is_system boolean, source text, source_status text, source_ref jsonb, is_computed_default boolean, can_hide boolean, can_delete boolean, can_customize_copy boolean, can_customize_assets boolean, can_customize_method boolean, can_customize_button boolean, created_at timestamp with time zone, updated_at timestamp with time zone)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
BEGIN
  RETURN QUERY
  WITH merchant_ctx AS (
    SELECT mm.id AS merchant_id, mm.plan_id, mm.merchant_code
    FROM merchant_master mm
    WHERE mm.id = p_merchant_id
  ), registry_eval AS (
    SELECT
      r.*,
      r.availability_rule AS rule,
      CASE r.availability_rule->>'source'
        WHEN 'feature_config' THEN public.fn_merchant_feature_enabled(
          p_merchant_id,
          r.availability_rule->>'feature_group',
          NULLIF(r.availability_rule->>'feature_key', '')
        )
        WHEN 'integration' THEN EXISTS (
          SELECT 1
          FROM merchant_credentials mc
          WHERE mc.merchant_id = p_merchant_id
            AND mc.service_name = COALESCE(NULLIF(r.availability_rule->>'service_name', ''), r.availability_rule->>'integration')
            AND COALESCE(mc.is_active, true) = true
            AND (mc.expires_at IS NULL OR mc.expires_at > now())
        )
        WHEN 'workflow' THEN EXISTS (
          SELECT 1
          FROM workflow_master wm
          WHERE wm.merchant_id = p_merchant_id
            AND wm.domain = COALESCE(NULLIF(r.availability_rule->>'domain', ''), 'loyalty')
            AND wm.config->>'surface' = r.availability_rule->>'surface'
            AND wm.config->>'lifecycle_event' = r.availability_rule->>'event'
            AND (
              COALESCE((r.availability_rule->>'requires_active')::boolean, false) = false
              OR COALESCE(wm.is_active, false) = true
            )
            AND (
              COALESCE((r.availability_rule->>'requires_earning_action')::boolean, false) = false
              OR EXISTS (
                SELECT 1
                FROM workflow_node wn
                WHERE wn.workflow_id = wm.id
                  AND wn.merchant_id = p_merchant_id
                  AND wn.node_type = 'action'
                  AND COALESCE(wn.node_config->>'action_type', wn.node_config->'node_config'->>'action_type')
                    IN ('award_currency', 'award_points', 'award_tickets', 'push_reward')
              )
            )
        )
        WHEN 'campaign' THEN CASE r.availability_rule->>'campaign_type'
          WHEN 'mission' THEN EXISTS (
            SELECT 1 FROM mission m
            WHERE m.merchant_id = p_merchant_id
              AND COALESCE(m.is_active, true) = true
              AND (m.start_date IS NULL OR m.start_date <= now())
              AND (m.end_date IS NULL OR m.end_date >= now())
          )
          WHEN 'checkin' THEN EXISTS (
            SELECT 1 FROM checkin c
            WHERE c.merchant_id = p_merchant_id
              AND COALESCE(c.active_status, true) = true
              AND (c.window_start IS NULL OR c.window_start <= now())
              AND (c.window_end IS NULL OR c.window_end >= now())
          )
          WHEN 'referral' THEN true
          WHEN 'form' THEN EXISTS (
            SELECT 1 FROM form_templates ft
            WHERE ft.merchant_id = p_merchant_id
              AND ft.status::text = 'published'
              AND COALESCE(ft.form_category, '') <> 'USER_PROFILE'
          )
          ELSE false
        END
        WHEN 'form' THEN EXISTS (
          SELECT 1 FROM form_templates ft
          WHERE ft.merchant_id = p_merchant_id
            AND ft.status::text = CASE
              WHEN COALESCE((r.availability_rule->>'requires_published')::boolean, false) THEN 'published'
              ELSE ft.status::text
            END
            AND (
              NULLIF(r.availability_rule->>'form_category', '') IS NULL
              OR ft.form_category = r.availability_rule->>'form_category'
            )
        )
        ELSE false
      END AS is_available,
      CASE r.availability_rule->>'source'
        WHEN 'feature_config' THEN public.fn_merchant_feature_config(
          p_merchant_id,
          r.availability_rule->>'feature_group',
          NULLIF(r.availability_rule->>'feature_key', '')
        )
        WHEN 'integration' THEN (
          SELECT jsonb_build_object(
            'credential_id', mc.id,
            'service_name', mc.service_name,
            'external_id', mc.external_id,
            'health_status', mc.health_status
          )
          FROM merchant_credentials mc
          WHERE mc.merchant_id = p_merchant_id
            AND mc.service_name = COALESCE(NULLIF(r.availability_rule->>'service_name', ''), r.availability_rule->>'integration')
            AND COALESCE(mc.is_active, true) = true
          ORDER BY mc.updated_at DESC NULLS LAST
          LIMIT 1
        )
        WHEN 'workflow' THEN (
          SELECT jsonb_build_object(
            'workflow_id', wm.id,
            'lifecycle_event', wm.config->>'lifecycle_event',
            'is_active', wm.is_active
          )
          FROM workflow_master wm
          WHERE wm.merchant_id = p_merchant_id
            AND wm.config->>'surface' = r.availability_rule->>'surface'
            AND wm.config->>'lifecycle_event' = r.availability_rule->>'event'
          ORDER BY wm.updated_at DESC NULLS LAST, wm.created_at DESC NULLS LAST
          LIMIT 1
        )
        ELSE '{}'::jsonb
      END AS resolved_source_ref
    FROM earn_channel_registry r
    WHERE COALESCE(r.is_active, true) = true
      AND COALESCE(r.channel_code, '') <> ''
  ), registry_available AS (
    SELECT re.*
    FROM registry_eval re
    WHERE re.is_available = true
  ), computed AS (
    SELECT
      COALESCE(o.id, public.fn_earn_channel_effective_id(p_merchant_id, ra.channel_code)) AS id,
      o.id AS override_id,
      ra.id AS registry_id,
      ra.channel_code,
      COALESCE(o.channel_type, ra.type) AS channel_type,
      COALESCE(o.method_type, ra.default_method_type, ra.ui_component) AS method_type,
      COALESCE(NULLIF(o.channel_name, ''), sut.channel_name, ra.display_name) AS raw_channel_name,
      COALESCE(o.headline, sut.headline, ra.default_headline, ra.display_name) AS raw_headline,
      COALESCE(o.description, sut.description, ra.default_description, '') AS raw_description,
      COALESCE(o.banner_urls, CASE WHEN ra.default_banner_url IS NOT NULL THEN ARRAY[ra.default_banner_url]::text[] ELSE NULL END) AS banner_urls,
      COALESCE(o.icon_url, ra.default_icon_url) AS icon_url,
      COALESCE(o.display_order, ra.sort_order, 0) AS display_order,
      CASE
        WHEN o.config IS NOT NULL AND o.config <> '{}'::jsonb THEN o.config
        WHEN ra.channel_code = 'shopify_store' AND mc.merchant_code LIKE '%.myshopify.com'
          THEN jsonb_build_object('mode', 'url', 'value', 'https://' || mc.merchant_code)
        ELSE COALESCE(ra.default_config, '{}'::jsonb)
      END AS config,
      CASE
        WHEN o.button_action IS NOT NULL AND o.button_action <> '{}'::jsonb THEN o.button_action
        WHEN ra.channel_code = 'shopify_store' AND mc.merchant_code LIKE '%.myshopify.com'
          THEN jsonb_build_object('show', true, 'label', COALESCE(ra.default_button_action->>'label', 'Shop now'))
        ELSE COALESCE(ra.default_button_action, '{}'::jsonb)
      END AS button_action,
      COALESCE(o.active, true) AS active,
      o.howto_banners,
      COALESCE(o.howto_description, sut.howto_description, ra.default_howto_description) AS raw_howto_description,
      o.stores_banner,
      COALESCE(
        o.marketplace_platforms,
        CASE WHEN ra.channel_code = 'purchase:marketplace'
          THEN ARRAY(SELECT jsonb_array_elements_text(COALESCE(ra.resolved_source_ref->'channels', '[]'::jsonb)))
          ELSE NULL
        END
      ) AS marketplace_platforms,
      COALESCE(o.default_award_scope, ra.default_award_scope, 'purchase') AS default_award_scope,
      COALESCE(o.is_system, false) AS is_system,
      COALESCE(ra.availability_rule->>'source', 'registry') AS source,
      'available'::text AS source_status,
      COALESCE(ra.resolved_source_ref, '{}'::jsonb) AS source_ref,
      true AS is_computed_default,
      COALESCE((ra.capabilities->>'can_hide')::boolean, true) AS can_hide,
      COALESCE((ra.capabilities->>'can_delete')::boolean, false) AS can_delete,
      COALESCE((ra.capabilities->>'can_customize_copy')::boolean, true) AS can_customize_copy,
      COALESCE((ra.capabilities->>'can_customize_assets')::boolean, true) AS can_customize_assets,
      COALESCE((ra.capabilities->>'can_customize_method')::boolean, false) AS can_customize_method,
      COALESCE((ra.capabilities->>'can_customize_button')::boolean, false) AS can_customize_button,
      COALESCE(o.created_at, ra.created_at) AS created_at,
      COALESCE(o.updated_at, ra.updated_at) AS updated_at,
      COALESCE(o.id, public.fn_earn_channel_effective_id(p_merchant_id, ra.channel_code)) AS translation_entity_id
    FROM registry_available ra
    CROSS JOIN merchant_ctx mc
    LEFT JOIN LATERAL (
      SELECT ec.*
      FROM earn_channel ec
      WHERE ec.merchant_id = p_merchant_id
        AND ec.channel_code = ra.channel_code
      ORDER BY ec.is_system DESC, ec.updated_at DESC NULLS LAST, ec.created_at DESC NULLS LAST
      LIMIT 1
    ) o ON true
    LEFT JOIN LATERAL (
      SELECT
        COALESCE(
          (SELECT ut.translated_value FROM ui_translations ut
           WHERE ut.page_key = 'ways_to_earn'
             AND ut.field_key = 'default_' || replace(ra.channel_code, ':', '_') || '_channel_name'
             AND ut.language_code = p_language AND ut.merchant_id = p_merchant_id LIMIT 1),
          (SELECT ut.translated_value FROM ui_translations ut
           WHERE ut.page_key = 'ways_to_earn'
             AND ut.field_key = 'default_' || replace(ra.channel_code, ':', '_') || '_channel_name'
             AND ut.language_code = p_language AND ut.merchant_id IS NULL LIMIT 1)
        ) AS channel_name,
        COALESCE(
          (SELECT ut.translated_value FROM ui_translations ut
           WHERE ut.page_key = 'ways_to_earn'
             AND ut.field_key = 'default_' || replace(ra.channel_code, ':', '_') || '_headline'
             AND ut.language_code = p_language AND ut.merchant_id = p_merchant_id LIMIT 1),
          (SELECT ut.translated_value FROM ui_translations ut
           WHERE ut.page_key = 'ways_to_earn'
             AND ut.field_key = 'default_' || replace(ra.channel_code, ':', '_') || '_headline'
             AND ut.language_code = p_language AND ut.merchant_id IS NULL LIMIT 1)
        ) AS headline,
        COALESCE(
          (SELECT ut.translated_value FROM ui_translations ut
           WHERE ut.page_key = 'ways_to_earn'
             AND ut.field_key = 'default_' || replace(ra.channel_code, ':', '_') || '_description'
             AND ut.language_code = p_language AND ut.merchant_id = p_merchant_id LIMIT 1),
          (SELECT ut.translated_value FROM ui_translations ut
           WHERE ut.page_key = 'ways_to_earn'
             AND ut.field_key = 'default_' || replace(ra.channel_code, ':', '_') || '_description'
             AND ut.language_code = p_language AND ut.merchant_id IS NULL LIMIT 1)
        ) AS description,
        COALESCE(
          (SELECT ut.translated_value FROM ui_translations ut
           WHERE ut.page_key = 'ways_to_earn'
             AND ut.field_key = 'default_' || replace(ra.channel_code, ':', '_') || '_howto_description'
             AND ut.language_code = p_language AND ut.merchant_id = p_merchant_id LIMIT 1),
          (SELECT ut.translated_value FROM ui_translations ut
           WHERE ut.page_key = 'ways_to_earn'
             AND ut.field_key = 'default_' || replace(ra.channel_code, ':', '_') || '_howto_description'
             AND ut.language_code = p_language AND ut.merchant_id IS NULL LIMIT 1)
        ) AS howto_description
    ) sut ON true
    WHERE o.id IS NOT NULL
       OR NOT EXISTS (
        SELECT 1
        FROM earn_channel legacy
        WHERE legacy.merchant_id = p_merchant_id
          AND legacy.channel_code <> ra.channel_code
          AND legacy.channel_type = ra.type
          AND legacy.method_type = COALESCE(ra.default_method_type, ra.ui_component)
          AND NOT EXISTS (
            SELECT 1 FROM earn_channel_registry rr
            WHERE rr.channel_code = legacy.channel_code
          )
      )
  ), physical AS (
    SELECT
      ec.id,
      ec.id AS override_id,
      NULL::uuid AS registry_id,
      ec.channel_code,
      ec.channel_type,
      ec.method_type,
      ec.channel_name AS raw_channel_name,
      ec.headline AS raw_headline,
      ec.description AS raw_description,
      ec.banner_urls,
      ec.icon_url,
      ec.display_order,
      ec.config,
      ec.button_action,
      ec.active,
      ec.howto_banners,
      ec.howto_description AS raw_howto_description,
      ec.stores_banner,
      ec.marketplace_platforms,
      ec.default_award_scope,
      ec.is_system,
      COALESCE(ec.source_type, CASE WHEN ec.is_system THEN 'integration' ELSE 'legacy' END) AS source,
      'physical'::text AS source_status,
      COALESCE(ec.source_ref, '{}'::jsonb) AS source_ref,
      false AS is_computed_default,
      true AS can_hide,
      NOT ec.is_system AS can_delete,
      true AS can_customize_copy,
      true AS can_customize_assets,
      NOT ec.is_system AS can_customize_method,
      true AS can_customize_button,
      ec.created_at,
      ec.updated_at,
      ec.id AS translation_entity_id
    FROM earn_channel ec
    WHERE ec.merchant_id = p_merchant_id
      AND NOT EXISTS (
        SELECT 1
        FROM registry_available ra
        WHERE ra.channel_code = ec.channel_code
      )
      AND NOT EXISTS (
        SELECT 1
        FROM earn_channel_registry r
        WHERE r.channel_code = ec.channel_code
          AND COALESCE(r.is_active, true) = true
      )
  ), unioned AS (
    SELECT * FROM computed
    UNION ALL
    SELECT * FROM physical
  ), channel_trans AS (
    SELECT
      t.entity_id,
      MAX(CASE WHEN t.field_name = 'channel_name' THEN t.translated_value END) AS t_channel_name,
      MAX(CASE WHEN t.field_name = 'headline' THEN t.translated_value END) AS t_headline,
      MAX(CASE WHEN t.field_name = 'description' THEN t.translated_value END) AS t_description,
      MAX(CASE WHEN t.field_name = 'howto_description' THEN t.translated_value END) AS t_howto_description
    FROM translations t
    WHERE t.entity_type = 'earn_channel'
      AND t.language_code = p_language
      AND t.merchant_id = p_merchant_id
    GROUP BY t.entity_id
  )
  SELECT
    u.id,
    u.override_id,
    u.registry_id,
    u.channel_code,
    u.channel_type,
    u.method_type,
    COALESCE(ct.t_channel_name, u.raw_channel_name) AS channel_name,
    COALESCE(ct.t_headline, u.raw_headline) AS headline,
    COALESCE(ct.t_description, u.raw_description) AS description,
    u.banner_urls,
    u.icon_url,
    u.display_order,
    u.config,
    u.button_action,
    u.active,
    u.howto_banners,
    COALESCE(ct.t_howto_description, u.raw_howto_description) AS howto_description,
    u.stores_banner,
    u.marketplace_platforms,
    u.default_award_scope,
    u.is_system,
    u.source,
    u.source_status,
    u.source_ref,
    u.is_computed_default,
    u.can_hide,
    u.can_delete,
    u.can_customize_copy,
    u.can_customize_assets,
    u.can_customize_method,
    u.can_customize_button,
    u.created_at,
    u.updated_at
  FROM unioned u
  LEFT JOIN channel_trans ct ON ct.entity_id = u.translation_entity_id
  ORDER BY u.display_order ASC, COALESCE(ct.t_channel_name, u.raw_channel_name) ASC, u.channel_code ASC;
END;
$function$

