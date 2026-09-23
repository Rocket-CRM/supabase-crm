-- Brand scheme unification — Migration B (Phase 2)
-- Flat readers → scheme; upsert stops syncing primary_color.

BEGIN;

CREATE OR REPLACE FUNCTION public.get_display_settings_fast(p_merchant_code text)
RETURNS json
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
AS $function$
DECLARE
  v_merchant_id uuid;
  v_scheme jsonb;
  v_primary text;
  v_accent text;
  v_cards_radius int;
  v_btn_radius int;
BEGIN
  SELECT mm.id INTO v_merchant_id
  FROM public.merchant_master mm
  WHERE mm.merchant_code = p_merchant_code
  LIMIT 1;

  IF v_merchant_id IS NULL THEN
    v_scheme := public.fn_brand_scheme_default();
  ELSE
    v_scheme := public.fn_brand_scheme_merged(v_merchant_id);
  END IF;

  v_primary := v_scheme #>> '{tokens,primary}';
  v_accent := v_scheme #>> '{tokens,accent}';
  v_cards_radius := coalesce((v_scheme #>> '{cards,radius_px}')::int, 12);
  v_btn_radius := coalesce((v_scheme #>> '{buttons,radius_px}')::int, 8);

  RETURN COALESCE(
    (
      SELECT json_build_object(
        'merchant_name', mm.name,
        'logo', mds.logo,
        'primary_color', v_primary,
        'secondary_color', v_accent,
        'background_image', mds.background_image,
        'select_store', coalesce(mds.select_store, false),
        'scan_mode', coalesce(mds.scan_mode, false),
        'scan_code_banners', coalesce(mds.scan_code_banners, '[]'::jsonb),
        'border_radius_cards', v_cards_radius::text || 'px',
        'border_radius_buttons', v_btn_radius::text || 'px',
        'border_radius_inputs', '8px',
        'border_radius_modals', '16px',
        'border_button_radius_small', '6px',
        'ui_config', coalesce(mds.ui_config, '{}'::jsonb),
        'old_crm_merchantid', coalesce(mds.old_crm_merchantid, '')
      )
      FROM public.merchant_master mm
      LEFT JOIN public.merchant_display_settings mds ON mds.merchant_id = mm.id
      WHERE mm.merchant_code = p_merchant_code
      LIMIT 1
    ),
    json_build_object(
      'merchant_name', null,
      'logo', null,
      'primary_color', v_primary,
      'secondary_color', v_accent,
      'background_image', null,
      'select_store', false,
      'scan_mode', false,
      'scan_code_banners', '[]'::jsonb,
      'border_radius_cards', v_cards_radius::text || 'px',
      'border_radius_buttons', v_btn_radius::text || 'px',
      'border_radius_inputs', '8px',
      'border_radius_modals', '16px',
      'border_button_radius_small', '6px',
      'ui_config', '{}'::jsonb,
      'old_crm_merchantid', ''
    )
  );
END;
$function$;

CREATE OR REPLACE FUNCTION public.get_merchant_display_settings(p_merchant_code text)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_merchant_id uuid;
  v_result jsonb;
  v_scheme jsonb;
  v_cards_radius int;
  v_btn_radius int;
BEGIN
  SELECT id INTO v_merchant_id
  FROM public.merchant_master
  WHERE merchant_code = p_merchant_code;

  IF v_merchant_id IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'Invalid merchant_code');
  END IF;

  v_scheme := public.fn_brand_scheme_merged(v_merchant_id);
  v_cards_radius := coalesce((v_scheme #>> '{cards,radius_px}')::int, 12);
  v_btn_radius := coalesce((v_scheme #>> '{buttons,radius_px}')::int, 8);

  SELECT jsonb_build_object(
    'success', true,
    'merchant_code', p_merchant_code,
    'logo', mds.logo,
    'primary_color', v_scheme #>> '{tokens,primary}',
    'secondary_color', v_scheme #>> '{tokens,accent}',
    'background_image', mds.background_image,
    'border_radius_cards', v_cards_radius::text || 'px',
    'border_radius_buttons', v_btn_radius::text || 'px',
    'border_radius_inputs', '8px',
    'border_radius_modals', '16px',
    'ui_config', mds.ui_config
  )
  INTO v_result
  FROM public.merchant_display_settings mds
  WHERE mds.merchant_id = v_merchant_id;

  IF v_result IS NULL THEN
    RETURN jsonb_build_object(
      'success', true,
      'merchant_code', p_merchant_code,
      'logo', null,
      'primary_color', v_scheme #>> '{tokens,primary}',
      'secondary_color', v_scheme #>> '{tokens,accent}',
      'border_radius_cards', v_cards_radius::text || 'px',
      'border_radius_buttons', v_btn_radius::text || 'px',
      'border_radius_inputs', '8px',
      'border_radius_modals', '16px',
      'ui_config', '{}'::jsonb
    );
  END IF;

  RETURN v_result;

EXCEPTION
  WHEN OTHERS THEN
    RETURN jsonb_build_object('success', false, 'error', 'An error occurred');
END;
$function$;

CREATE OR REPLACE FUNCTION public.get_display_settings_batch(p_merchant_codes text[])
RETURNS TABLE(
  merchant_code text,
  merchant_id uuid,
  merchant_name text,
  primary_color text,
  secondary_color text,
  background_image text
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
BEGIN
  RETURN QUERY
  SELECT
    mm.merchant_code,
    mm.id AS merchant_id,
    mm.name AS merchant_name,
    public.fn_brand_scheme_merged(mm.id) #>> '{tokens,primary}' AS primary_color,
    public.fn_brand_scheme_merged(mm.id) #>> '{tokens,accent}' AS secondary_color,
    mds.background_image
  FROM public.merchant_master mm
  LEFT JOIN public.merchant_display_settings mds ON mds.merchant_id = mm.id
  WHERE mm.merchant_code = ANY(p_merchant_codes);
END;
$function$;

CREATE OR REPLACE FUNCTION public.fn_resolve_widget_merchant_display(p_merchant_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SET search_path TO 'public'
AS $function$
DECLARE
  v_row public.merchant_display_settings;
  v_tiers jsonb;
  v_scheme_merged jsonb;
BEGIN
  SELECT * INTO v_row FROM public.merchant_display_settings WHERE merchant_id = p_merchant_id;

  v_scheme_merged := public.fn_brand_scheme_merged(p_merchant_id);

  SELECT coalesce(jsonb_agg(jsonb_build_object(
      'name', t.tier_name,
      'icon', t.icon
    ) ORDER BY tcu.amount ASC NULLS FIRST, t.tier_name), '[]'::jsonb)
  INTO v_tiers
  FROM public.tier_master t
  LEFT JOIN public.tier_conditions tcu
    ON tcu.tier_id = t.id AND tcu.condition_type = 'upgrade' AND tcu.active_status IS TRUE
  WHERE t.merchant_id = p_merchant_id
    AND t.tier_name IS NOT NULL
    AND btrim(t.tier_name) <> '';

  RETURN jsonb_build_object(
    'primary_color', v_scheme_merged #>> '{tokens,primary}',
    'points', jsonb_build_object(
      'unit_label', v_row.points_unit_label,
      'symbol_type', v_row.points_symbol_type,
      'symbol_icon', v_row.points_symbol_icon,
      'symbol_image_url', v_row.points_symbol_image_url
    ),
    'tiers', v_tiers,
    'earn_rate', public.fn_resolve_widget_earn_rate(p_merchant_id),
    'scheme', v_scheme_merged
  );
END;
$function$;

CREATE OR REPLACE FUNCTION public.bff_get_notification_settings()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
AS $function$
DECLARE
  v_merchant_id uuid;
  v_rows jsonb;
  v_appearance jsonb;
  v_scheme jsonb;
BEGIN
  v_merchant_id := public.get_current_merchant_id();
  IF v_merchant_id IS NULL THEN
    RETURN public.fn_response_error('No merchant context', NULL, 'NO_MERCHANT_CONTEXT', NULL);
  END IF;

  v_scheme := public.fn_brand_scheme_merged(v_merchant_id);

  SELECT jsonb_agg(row_obj ORDER BY row_obj->>'event_key', row_obj->>'sub_event')
    INTO v_rows
    FROM (
      SELECT jsonb_build_object(
        'event_key',                c.event_key,
        'sub_event',                c.sub_event,
        'source_topic',             c.source_topic,
        'description',              c.description,
        'available_fields',         c.available_fields,
        'template_field_allowlist', public.fn_notification_template_field_allowlist(c.event_key, c.sub_event),
        'line', jsonb_build_object(
          'default_enabled',         c.default_enabled,
          'enabled',                 COALESCE(ls.enabled, c.default_enabled),
          'default_selected_fields', c.default_selected_fields,
          'selected_fields',         COALESCE(ls.selected_fields, c.default_selected_fields),
          'is_customized',           ls.id IS NOT NULL,
          'default_flex_template',   line_sys.flex_template,
          'flex_template',           line_merch.flex_template,
          'has_custom_template',     line_merch.id IS NOT NULL
        ),
        'email', jsonb_build_object(
          'default_enabled',           c.default_enabled_email,
          'enabled',                   COALESCE(es.enabled, c.default_enabled_email),
          'is_customized',             es.id IS NOT NULL,
          'default_email_template',    email_sys.email_template,
          'email_template',            email_merch.email_template,
          'has_custom_template',       email_merch.id IS NOT NULL
        )
      ) AS row_obj
      FROM public.notification_event_catalog c
      LEFT JOIN public.merchant_notification_settings ls
        ON ls.merchant_id = v_merchant_id
       AND ls.event_key  = c.event_key
       AND ls.sub_event  = c.sub_event
       AND ls.channel    = 'line'
      LEFT JOIN public.merchant_notification_settings es
        ON es.merchant_id = v_merchant_id
       AND es.event_key  = c.event_key
       AND es.sub_event  = c.sub_event
       AND es.channel    = 'email'
      LEFT JOIN public.notification_template line_sys
        ON line_sys.event_key = c.event_key
       AND line_sys.sub_event = c.sub_event
       AND line_sys.merchant_id IS NULL
       AND line_sys.channel = 'line'
       AND line_sys.is_active = true
      LEFT JOIN public.notification_template line_merch
        ON line_merch.event_key = c.event_key
       AND line_merch.sub_event = c.sub_event
       AND line_merch.merchant_id = v_merchant_id
       AND line_merch.channel = 'line'
       AND line_merch.is_active = true
      LEFT JOIN public.notification_template email_sys
        ON email_sys.event_key = c.event_key
       AND email_sys.sub_event = c.sub_event
       AND email_sys.merchant_id IS NULL
       AND email_sys.channel = 'email'
       AND email_sys.is_active = true
      LEFT JOIN public.notification_template email_merch
        ON email_merch.event_key = c.event_key
       AND email_merch.sub_event = c.sub_event
       AND email_merch.merchant_id = v_merchant_id
       AND email_merch.channel = 'email'
       AND email_merch.is_active = true
     WHERE c.is_active = true
    ) q;

  SELECT jsonb_build_object(
    'from_name',     COALESCE(NULLIF(btrim(a.from_name), ''), NULLIF(btrim(m.name), ''), m.merchant_code),
    'logo_url',      COALESCE(a.logo_url, NULLIF(d.logo::text, '')),
    'primary_color', COALESCE(a.primary_color, v_scheme #>> '{tokens,primary}'),
    'is_customized', a.merchant_id IS NOT NULL
  )
    INTO v_appearance
    FROM public.merchant_master m
    LEFT JOIN public.merchant_display_settings d ON d.merchant_id = m.id
    LEFT JOIN public.merchant_notification_appearance a ON a.merchant_id = m.id
   WHERE m.id = v_merchant_id;

  RETURN public.fn_response_success(
    'Notification settings loaded',
    NULL,
    jsonb_build_object(
      'settings', COALESCE(v_rows, '[]'::jsonb),
      'appearance', COALESCE(v_appearance, '{}'::jsonb),
      'system_template_fields', to_jsonb(public.fn_notification_system_template_fields())
    )
  );
EXCEPTION WHEN OTHERS THEN
  RETURN public.fn_response_error('Failed to load notification settings', SQLERRM, 'UNKNOWN', NULL);
END;
$function$;

-- History BFFs: primary from scheme once per request
DO $patch$
DECLARE
  r record;
  v_def text;
  v_new text;
BEGIN
  FOR r IN
    SELECT p.oid, p.proname
    FROM pg_proc p
    JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'public'
      AND p.proname IN (
        'bff_get_campaign_history',
        'bff_get_currency_history',
        'bff_get_purchase_history',
        'bff_get_reward_history',
        'bff_get_tier_history',
        'bff_get_upload_receipt_history',
        'bff_get_user_history_menu'
      )
  LOOP
    v_def := pg_get_functiondef(r.oid);
    v_new := replace(
      v_def,
      E'SELECT mds.primary_color INTO v_primary_color FROM merchant_display_settings mds WHERE mds.merchant_id = v_merchant_id;',
      E'SELECT public.fn_brand_scheme_merged(v_merchant_id) #>> ''{tokens,primary}'' INTO v_primary_color;'
    );
    IF v_new = v_def THEN
      v_new := replace(
        v_def,
        E'SELECT mds.primary_color INTO v_primary_color FROM public.merchant_display_settings mds WHERE mds.merchant_id = v_merchant_id;',
        E'SELECT public.fn_brand_scheme_merged(v_merchant_id) #>> ''{tokens,primary}'' INTO v_primary_color;'
      );
    END IF;
    IF v_new <> v_def THEN
      EXECUTE v_new;
    END IF;
  END LOOP;
END;
$patch$;

DO $bc_patch$
DECLARE
  v_def text;
  v_new text;
BEGIN
  SELECT pg_get_functiondef(oid) INTO v_def
  FROM pg_proc
  WHERE proname = 'api_bigcommerce_get_merchant_config'
    AND pronamespace = 'public'::regnamespace;

  v_new := replace(
    v_def,
    E'''themeColor'', COALESCE(md.primary_color, ''#000000''),',
    E'''themeColor'', COALESCE(public.fn_brand_scheme_merged(md.id) #>> ''{tokens,primary}'', ''#000000''),'
  );
  IF v_new <> v_def THEN
    EXECUTE v_new;
  END IF;
END;
$bc_patch$;

CREATE OR REPLACE FUNCTION public.admin_upsert_brand_scheme(p_scheme jsonb, p_assets jsonb DEFAULT '{}'::jsonb)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_merchant_id uuid;
  v_stored jsonb;
  v_work jsonb;
  v_errors jsonb;
  v_merged jsonb;
  v_logo text;
BEGIN
  v_merchant_id := public.get_current_merchant_id();
  IF v_merchant_id IS NULL THEN
    RETURN public.fn_response_error('Unauthorized', 'No merchant context', 'UNAUTHORIZED');
  END IF;

  v_stored := public.fn_brand_scheme_merged(v_merchant_id);
  v_work := coalesce(p_scheme, '{}'::jsonb);

  IF NOT (v_work -> 'tokens' ? 'accent') THEN
    v_work := jsonb_set(v_work, '{tokens,accent}', coalesce(v_stored #> '{tokens,accent}', 'null'::jsonb), true);
  END IF;
  IF NOT (v_work ? 'cards') THEN
    v_work := v_work || jsonb_build_object('cards', coalesce(v_stored -> 'cards', public.fn_brand_scheme_default() -> 'cards'));
  END IF;

  v_merged := public.fn_brand_scheme_merge(v_work);
  v_errors := public.fn_validate_brand_scheme(v_merged);
  IF jsonb_array_length(v_errors) > 0 THEN
    RETURN public.fn_response_error(
      'Invalid scheme',
      'Brand scheme validation failed',
      'VALIDATION_ERROR',
      jsonb_build_object('errors', v_errors)
    );
  END IF;

  UPDATE public.merchant_display_settings
  SET brand_scheme = v_merged,
      updated_at = now()
  WHERE merchant_id = v_merchant_id;

  IF NOT FOUND THEN
    INSERT INTO public.merchant_display_settings (merchant_id, brand_scheme)
    VALUES (v_merchant_id, v_merged);
  END IF;

  IF p_assets ? 'logo' THEN
    v_logo := p_assets ->> 'logo';
    IF v_logo IS NOT NULL AND btrim(v_logo) <> '' AND NOT (v_logo ~* '^https://') THEN
      RETURN public.fn_response_error(
        'Invalid logo',
        'logo must be https URL or null',
        'VALIDATION_ERROR'
      );
    END IF;
    UPDATE public.merchant_display_settings
    SET logo = NULLIF(btrim(v_logo), ''),
        updated_at = now()
    WHERE merchant_id = v_merchant_id;
  END IF;

  PERFORM public.fn_invalidate_shopify_landing_page_cache(v_merchant_id);

  RETURN public.admin_get_brand_scheme();
END;
$function$;

COMMIT;
