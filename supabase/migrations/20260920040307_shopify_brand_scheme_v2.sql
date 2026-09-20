-- Brand scheme v2: stored tokens only; storefront owns all derived colours.
-- Drops SQL resolvers; RPC payloads expose raw merged scheme + slim landing theme.

-- ---------------------------------------------------------------------------
-- Helpers
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.fn_shopify_brand_scheme_null_if_placeholder(p_value text)
RETURNS text
LANGUAGE sql
IMMUTABLE
AS $function$
  SELECT CASE
    WHEN p_value IS NULL OR btrim(p_value) = '' THEN NULL
    WHEN upper(btrim(p_value)) = '#1C1C1C' THEN NULL
    WHEN public.fn_shopify_landing_is_hex(p_value) THEN upper(btrim(p_value))
    ELSE NULL
  END;
$function$;

CREATE OR REPLACE FUNCTION public.fn_shopify_landing_page_theme_layout(p_merchant_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SET search_path TO 'public'
AS $function$
DECLARE
  v_slim jsonb;
  v_scheme jsonb;
  v_pad int;
  v_dismissed jsonb;
BEGIN
  SELECT public.fn_shopify_landing_merge_page_config(m.config) -> 'theme'
  INTO v_slim
  FROM public.merchant_shopify_landing_page_settings m
  WHERE m.merchant_id = p_merchant_id;

  IF v_slim IS NULL THEN
    v_slim := public.fn_shopify_landing_default_page_config() -> 'theme';
  END IF;

  v_scheme := coalesce(
    public.fn_shopify_merchant_brand_scheme_merged(p_merchant_id),
    public.fn_shopify_brand_scheme_default()
  );
  v_pad := coalesce((v_slim ->> 'section_padding_px')::int, 88);
  v_dismissed := coalesce(v_slim #> '{import,first_run_dismissed_at}', 'null'::jsonb);

  RETURN jsonb_build_object(
    'section_padding_px', v_pad,
    'import', jsonb_build_object(
      'first_run_dismissed_at', v_dismissed,
      'imported_from', public.fn_shopify_brand_scheme_source_to_imported_from(v_scheme -> 'source')
    )
  );
END;
$function$;

-- ---------------------------------------------------------------------------
-- Scheme v2 default, merge, validate
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.fn_shopify_brand_scheme_default()
RETURNS jsonb
LANGUAGE sql
IMMUTABLE
AS $function$
  SELECT jsonb_build_object(
    '_schema_version', '2.0.0',
    'source', jsonb_build_object(
      'kind', 'custom',
      'theme_id', NULL,
      'theme_name', NULL,
      'scheme_model', NULL,
      'scheme_id', NULL,
      'dark_scheme_id', NULL,
      'imported_at', NULL,
      'detached_at', NULL
    ),
    'tokens', jsonb_build_object(
      'brand', '#1C1C1C',
      'background', '#FFFFFF',
      'dark_surface', '#1C1C1C',
      'text', '#0D0D0D'
    ),
    'buttons', jsonb_build_object(
      'primary', jsonb_build_object('bg', NULL, 'text', NULL),
      'secondary', jsonb_build_object('text', NULL),
      'radius_px', 8
    )
  );
$function$;

CREATE OR REPLACE FUNCTION public.fn_shopify_brand_scheme_merge(p_scheme jsonb, p_primary_color text)
RETURNS jsonb
LANGUAGE plpgsql
IMMUTABLE
AS $function$
DECLARE
  v_default jsonb := public.fn_shopify_brand_scheme_default();
  v_in jsonb := coalesce(p_scheme, '{}'::jsonb);
  v_src jsonb;
  v_tok jsonb;
  v_btn jsonb;
  v_brand text;
  v_radius int;
BEGIN
  v_src := (v_default -> 'source') || coalesce(v_in -> 'source', '{}'::jsonb);
  v_tok := coalesce(v_in -> 'tokens', '{}'::jsonb);

  v_brand := coalesce(
    CASE WHEN public.fn_shopify_landing_is_hex(v_tok ->> 'brand') THEN upper(btrim(v_tok ->> 'brand')) END,
    CASE WHEN public.fn_shopify_landing_is_hex(p_primary_color) THEN upper(btrim(p_primary_color)) END,
    v_default #>> '{tokens,brand}'
  );

  v_btn := coalesce(v_in -> 'buttons', '{}'::jsonb);
  v_radius := coalesce((v_btn ->> 'radius_px')::int, (v_default -> 'buttons' ->> 'radius_px')::int, 8);

  RETURN jsonb_build_object(
    '_schema_version', '2.0.0',
    'source', v_src,
    'tokens', jsonb_build_object(
      'brand', v_brand,
      'background', coalesce(
        CASE WHEN public.fn_shopify_landing_is_hex(v_tok ->> 'background') THEN upper(btrim(v_tok ->> 'background')) END,
        v_default #>> '{tokens,background}'
      ),
      'dark_surface', coalesce(
        CASE WHEN public.fn_shopify_landing_is_hex(v_tok ->> 'dark_surface') THEN upper(btrim(v_tok ->> 'dark_surface')) END,
        v_default #>> '{tokens,dark_surface}'
      ),
      'text', coalesce(
        CASE WHEN public.fn_shopify_landing_is_hex(v_tok ->> 'text') THEN upper(btrim(v_tok ->> 'text')) END,
        CASE WHEN public.fn_shopify_landing_is_hex(v_tok ->> 'heading') THEN upper(btrim(v_tok ->> 'heading')) END,
        v_default #>> '{tokens,text}'
      )
    ),
    'buttons', jsonb_build_object(
      'primary', jsonb_build_object(
        'bg', public.fn_shopify_brand_scheme_null_if_placeholder(v_btn #>> '{primary,bg}'),
        'text', public.fn_shopify_brand_scheme_null_if_placeholder(v_btn #>> '{primary,text}')
      ),
      'secondary', jsonb_build_object(
        'text', public.fn_shopify_brand_scheme_null_if_placeholder(v_btn #>> '{secondary,text}')
      ),
      'radius_px', v_radius
    )
  );
END;
$function$;

CREATE OR REPLACE FUNCTION public.fn_validate_shopify_brand_scheme(p_scheme jsonb)
RETURNS jsonb
LANGUAGE plpgsql
IMMUTABLE
AS $function$
DECLARE
  v_errors jsonb := '[]'::jsonb;
  v_merged jsonb;
  v_tokens jsonb;
  v_buttons jsonb;
  v_kind text;
  v_field text;
  v_radius int;
  v_opt text;
BEGIN
  IF p_scheme IS NULL OR jsonb_typeof(p_scheme) <> 'object' THEN
    RETURN jsonb_build_array(jsonb_build_object('path', '', 'message', 'scheme must be a JSON object'));
  END IF;

  v_merged := public.fn_shopify_brand_scheme_merge(p_scheme, p_scheme #>> '{tokens,brand}');

  IF coalesce(v_merged ->> '_schema_version', '') NOT IN ('2.0.0', '1.0.0') THEN
    v_errors := v_errors || jsonb_build_array(jsonb_build_object(
      'path', '_schema_version',
      'message', '_schema_version must be 2.0.0'
    ));
  END IF;

  v_kind := coalesce(v_merged #>> '{source,kind}', 'custom');
  IF v_kind NOT IN ('custom', 'theme') THEN
    v_errors := v_errors || jsonb_build_array(jsonb_build_object(
      'path', 'source.kind',
      'message', 'source.kind must be custom or theme'
    ));
  END IF;

  v_tokens := coalesce(v_merged -> 'tokens', '{}'::jsonb);
  FOREACH v_field IN ARRAY ARRAY['brand', 'background', 'dark_surface', 'text'] LOOP
    IF NOT public.fn_shopify_landing_is_hex(v_tokens ->> v_field) THEN
      v_errors := v_errors || jsonb_build_array(jsonb_build_object(
        'path', 'tokens.' || v_field,
        'message', format('tokens.%s must be a hex color', v_field)
      ));
    END IF;
  END LOOP;

  v_buttons := coalesce(v_merged -> 'buttons', '{}'::jsonb);
  FOREACH v_opt IN ARRAY ARRAY[
    v_buttons #>> '{primary,bg}',
    v_buttons #>> '{primary,text}',
    v_buttons #>> '{secondary,text}'
  ] LOOP
    IF v_opt IS NOT NULL AND btrim(v_opt) <> '' AND NOT public.fn_shopify_landing_is_hex(v_opt) THEN
      v_errors := v_errors || jsonb_build_array(jsonb_build_object(
        'path', 'buttons',
        'message', 'optional button colours must be hex or null'
      ));
      EXIT;
    END IF;
  END LOOP;

  v_radius := coalesce((v_buttons ->> 'radius_px')::int, 8);
  IF v_radius NOT BETWEEN 0 AND 40 THEN
    v_errors := v_errors || jsonb_build_array(jsonb_build_object(
      'path', 'buttons.radius_px',
      'message', 'buttons.radius_px must be 0–40'
    ));
  END IF;

  RETURN v_errors;
END;
$function$;

-- ---------------------------------------------------------------------------
-- Admin brand scheme RPCs (scheme only — no resolved)
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.admin_get_shopify_brand_scheme()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_merchant_id uuid;
  v_row public.merchant_display_settings;
  v_scheme jsonb;
BEGIN
  v_merchant_id := public.get_current_merchant_id();
  IF v_merchant_id IS NULL THEN
    RETURN public.fn_response_error('Unauthorized', 'No merchant context', 'UNAUTHORIZED');
  END IF;

  SELECT * INTO v_row
  FROM public.merchant_display_settings
  WHERE merchant_id = v_merchant_id;

  v_scheme := public.fn_shopify_brand_scheme_merge(v_row.shopify_brand_scheme, v_row.primary_color);

  RETURN public.fn_response_success(
    'OK',
    'Brand scheme loaded',
    jsonb_build_object(
      'scheme', v_scheme,
      'updated_at', v_row.updated_at
    )
  );
END;
$function$;

CREATE OR REPLACE FUNCTION public.admin_upsert_shopify_brand_scheme(p_scheme jsonb)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_merchant_id uuid;
  v_errors jsonb;
  v_merged jsonb;
  v_brand text;
BEGIN
  v_merchant_id := public.get_current_merchant_id();
  IF v_merchant_id IS NULL THEN
    RETURN public.fn_response_error('Unauthorized', 'No merchant context', 'UNAUTHORIZED');
  END IF;

  v_errors := public.fn_validate_shopify_brand_scheme(p_scheme);
  IF jsonb_array_length(v_errors) > 0 THEN
    RETURN public.fn_response_error(
      'Invalid scheme',
      'Brand scheme validation failed',
      'VALIDATION_ERROR',
      jsonb_build_object('errors', v_errors)
    );
  END IF;

  v_merged := public.fn_shopify_brand_scheme_merge(p_scheme, p_scheme #>> '{tokens,brand}');
  v_brand := v_merged #>> '{tokens,brand}';

  UPDATE public.merchant_display_settings
  SET shopify_brand_scheme = v_merged,
      primary_color = v_brand,
      updated_at = now()
  WHERE merchant_id = v_merchant_id;

  IF NOT FOUND THEN
    INSERT INTO public.merchant_display_settings (merchant_id, shopify_brand_scheme, primary_color)
    VALUES (v_merchant_id, v_merged, v_brand);
  END IF;

  PERFORM public.fn_invalidate_shopify_landing_page_cache(v_merchant_id);

  RETURN public.admin_get_shopify_brand_scheme();
END;
$function$;

-- ---------------------------------------------------------------------------
-- Widget display + cached reads
-- ---------------------------------------------------------------------------
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

  v_scheme_merged := public.fn_shopify_brand_scheme_merge(
    v_row.shopify_brand_scheme,
    coalesce(v_row.primary_color, '#1C1C1C')
  );

  SELECT COALESCE(jsonb_agg(jsonb_build_object(
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
    'primary_color', v_row.primary_color,
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

CREATE OR REPLACE FUNCTION public.admin_get_widget_settings(p_widget_type text DEFAULT 'shopify'::text)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_merchant_id uuid;
  v_row public.merchant_widget_settings;
  v_template public.widget_config_template;
  v_resolved_config jsonb;
  v_existed boolean := false;
  v_scheme jsonb;
BEGIN
  v_merchant_id := public.get_current_merchant_id();
  IF v_merchant_id IS NULL THEN
    RETURN public.fn_response_error('Unauthorized','No merchant context','UNAUTHORIZED');
  END IF;

  SELECT * INTO v_template FROM public.widget_config_template WHERE widget_type = p_widget_type;
  IF v_template.widget_type IS NULL THEN
    RETURN public.fn_response_error('Unknown widget_type', format('No template for widget_type=%s', p_widget_type), 'NOT_FOUND');
  END IF;

  SELECT * INTO v_row FROM public.merchant_widget_settings
  WHERE merchant_id = v_merchant_id AND widget_type = p_widget_type;

  IF v_row.id IS NULL THEN
    v_resolved_config := v_template.config_default;
  ELSE
    v_existed := true;
    v_resolved_config := public.fn_widget_config_with_defaults(p_widget_type, v_row.config);
  END IF;

  v_scheme := public.fn_shopify_brand_scheme_merge(
    (SELECT d.shopify_brand_scheme FROM public.merchant_display_settings d WHERE d.merchant_id = v_merchant_id),
    (SELECT d.primary_color FROM public.merchant_display_settings d WHERE d.merchant_id = v_merchant_id)
  );

  RETURN public.fn_response_success(
    'OK',
    'Widget settings loaded',
    jsonb_build_object(
      'widget_type', p_widget_type,
      'schema_version', v_template.schema_version,
      'exists', v_existed,
      'id', v_row.id,
      'active_status', coalesce(v_row.active_status, true),
      'config', v_resolved_config,
      'scheme', v_scheme,
      'resolved', public.fn_resolve_widget_merchant_display(v_merchant_id),
      'storage', public.fn_resolve_widget_storage(p_widget_type, v_merchant_id),
      'updated_at', v_row.updated_at
    )
  );
END;
$function$;

CREATE OR REPLACE FUNCTION public.api_get_widget_settings_cached(p_widget_type text, p_merchant_code text)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_merchant_id uuid;
  v_cache_key text;
  v_cached text;
  v_row public.merchant_widget_settings;
  v_template public.widget_config_template;
  v_resolved_config jsonb;
  v_display jsonb;
  v_payload jsonb;
BEGIN
  IF coalesce(p_merchant_code, '') = '' OR coalesce(p_widget_type, '') = '' THEN
    RETURN jsonb_build_object('ok', false, 'error', 'merchant_code and widget_type required');
  END IF;
  SELECT id INTO v_merchant_id FROM public.merchant_master WHERE merchant_code = p_merchant_code;
  IF v_merchant_id IS NULL THEN RETURN jsonb_build_object('ok', false, 'error', 'merchant not found'); END IF;

  v_cache_key := 'merchant:' || v_merchant_id::text || ':widget:v2:' || p_widget_type;

  BEGIN SELECT extensions.ui_cache_get(v_cache_key) INTO v_cached; EXCEPTION WHEN OTHERS THEN v_cached := NULL; END;
  IF v_cached IS NOT NULL THEN RETURN v_cached::jsonb; END IF;

  SELECT * INTO v_template FROM public.widget_config_template WHERE widget_type = p_widget_type;
  IF v_template.widget_type IS NULL THEN RETURN jsonb_build_object('ok', false, 'error', 'unknown widget_type'); END IF;

  SELECT * INTO v_row FROM public.merchant_widget_settings
  WHERE merchant_id = v_merchant_id AND widget_type = p_widget_type AND active_status = true;

  IF v_row.id IS NULL THEN
    v_resolved_config := v_template.config_default;
  ELSE
    BEGIN
      v_resolved_config := public.fn_widget_config_with_defaults(p_widget_type, v_row.config);
    EXCEPTION WHEN OTHERS THEN v_resolved_config := v_template.config_default;
    END;
  END IF;

  v_display := public.fn_resolve_widget_merchant_display(v_merchant_id);

  v_payload := jsonb_build_object(
    'ok', true,
    'widget_type', p_widget_type,
    'schema_version', v_template.schema_version,
    'config', v_resolved_config,
    'brand_scheme', v_display -> 'scheme',
    'resolved', v_display - 'scheme'
  );

  BEGIN PERFORM extensions.ui_cache_set(v_cache_key, v_payload::text, 'EX', 300); EXCEPTION WHEN OTHERS THEN NULL; END;
  RETURN v_payload;
END;
$function$;

-- ---------------------------------------------------------------------------
-- Landing enrich + cached/admin reads
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.fn_enrich_shopify_landing_sections(
  p_sections jsonb,
  p_merchant_id uuid,
  p_language text DEFAULT 'en',
  p_user_id uuid DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SET search_path TO 'public'
AS $function$
DECLARE
  v_out jsonb := '[]'::jsonb;
  v_section jsonb;
  v_type text;
  v_cfg jsonb;
  v_hub jsonb;
  v_points text;
  v_current_tier uuid;
  v_tile jsonb;
  v_tiles jsonb;
  v_referral jsonb;
BEGIN
  v_hub := public.fn_compose_shopify_hub(p_merchant_id, p_user_id, p_language);
  v_points := coalesce(v_hub -> 'branding' ->> 'points_name', 'Points');

  IF p_user_id IS NOT NULL THEN
    SELECT ua.tier_id INTO v_current_tier
    FROM public.user_accounts ua
    WHERE ua.id = p_user_id AND ua.merchant_id = p_merchant_id;
  END IF;

  IF p_sections IS NULL OR jsonb_typeof(p_sections) <> 'array' THEN
    RETURN v_out;
  END IF;

  FOR v_section IN SELECT * FROM jsonb_array_elements(p_sections)
  LOOP
    v_type := v_section ->> 'block_type';
    v_cfg := public.fn_shopify_landing_merge_section_config(
      v_type,
      coalesce(v_section -> 'config', '{}'::jsonb)
    );
    v_section := (v_section - 'config' - 'style_tokens')
      || jsonb_build_object('config', v_cfg);

    IF v_type = 'shopify_landing_ways_to_earn' THEN
      v_tiles := '[]'::jsonb;
      FOR v_tile IN
        SELECT * FROM jsonb_array_elements(coalesce(v_hub -> 'earn', '[]'::jsonb))
      LOOP
        v_tiles := v_tiles || jsonb_build_array(
          jsonb_build_object(
            'name', coalesce(v_tile ->> 'title', ''),
            'points_label', coalesce(v_tile ->> 'reward_copy', ''),
            'icon_url', NULL,
            'featured', coalesce(v_tile ->> 'method', '') = 'purchase'
          )
        );
      END LOOP;
      v_section := v_section || jsonb_build_object('tiles', v_tiles);
    ELSIF v_type = 'shopify_landing_ways_to_spend' THEN
      v_tiles := '[]'::jsonb;
      FOR v_tile IN
        SELECT * FROM jsonb_array_elements(
          coalesce(v_hub -> 'spend', '[]'::jsonb) || coalesce(v_hub -> 'shop', '[]'::jsonb)
        )
      LOOP
        v_tiles := v_tiles || jsonb_build_array(
          jsonb_build_object(
            'name', coalesce(v_tile ->> 'name', ''),
            'points_label', trim(
              coalesce(v_tile ->> 'cost', '0') || ' ' || v_points
            ),
            'image_url', v_tile ->> 'image_url',
            'icon_url', v_tile ->> 'image_url',
            'affordable', coalesce((v_tile ->> 'affordable')::boolean, false)
          )
        );
      END LOOP;
      v_section := v_section || jsonb_build_object('tiles', v_tiles);
    ELSIF v_type = 'shopify_landing_vip' THEN
      v_section := v_section || jsonb_build_object(
        'tiers',
        public.fn_shopify_landing_vip_tiers_from_hub(
          coalesce(v_hub -> 'tiers', '[]'::jsonb),
          v_current_tier
        )
      );
    ELSIF v_type = 'shopify_landing_referrals' THEN
      v_referral := v_hub -> 'referral';
      IF v_referral IS NOT NULL AND v_referral <> 'null'::jsonb THEN
        v_section := v_section || jsonb_build_object(
          'referral_offers',
          jsonb_build_object(
            'you_get', coalesce(v_referral ->> 'you_get', ''),
            'they_get', coalesce(v_referral ->> 'they_get', '')
          )
        );
      END IF;
    END IF;

    v_out := v_out || jsonb_build_array(v_section);
  END LOOP;

  RETURN v_out;
END;
$function$;

CREATE OR REPLACE FUNCTION public.api_get_shopify_landing_page_cached(
  p_merchant_code text,
  p_language text DEFAULT 'en'
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_merchant_id uuid;
  v_cache_key text;
  v_cached text;
  v_row public.merchant_shopify_landing_page_settings;
  v_sections jsonb;
  v_payload jsonb;
  v_lang text := coalesce(nullif(p_language, ''), 'en');
  v_page_config jsonb;
  v_display jsonb;
  v_scheme jsonb;
BEGIN
  IF coalesce(p_merchant_code, '') = '' THEN
    RETURN jsonb_build_object('ok', false, 'error', 'merchant_code required');
  END IF;

  SELECT id INTO v_merchant_id
  FROM public.merchant_master
  WHERE merchant_code = p_merchant_code;

  IF v_merchant_id IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'error', 'merchant not found');
  END IF;

  v_cache_key := 'merchant:' || v_merchant_id::text || ':shopify_landing_page:v2:' || v_lang || ':published';

  BEGIN
    SELECT extensions.ui_cache_get(v_cache_key) INTO v_cached;
  EXCEPTION WHEN OTHERS THEN
    v_cached := NULL;
  END;
  IF v_cached IS NOT NULL THEN
    RETURN v_cached::jsonb;
  END IF;

  SELECT * INTO v_row
  FROM public.merchant_shopify_landing_page_settings
  WHERE merchant_id = v_merchant_id;

  IF v_row.merchant_id IS NULL OR v_row.publish_status <> 'published' THEN
    RETURN jsonb_build_object('ok', false, 'published', false);
  END IF;

  v_page_config := public.fn_shopify_landing_merge_page_config(v_row.config);
  v_scheme := coalesce(
    public.fn_shopify_merchant_brand_scheme_merged(v_merchant_id),
    public.fn_shopify_brand_scheme_default()
  );
  v_page_config := jsonb_set(
    v_page_config,
    '{theme}',
    public.fn_shopify_landing_page_theme_layout(v_merchant_id),
    true
  );
  v_display := public.fn_resolve_widget_merchant_display(v_merchant_id);

  SELECT coalesce(jsonb_agg(section ORDER BY (section ->> 'order')::int), '[]'::jsonb)
  INTO v_sections
  FROM (
    SELECT jsonb_build_object(
      'id', ds.id,
      'block_type', ds.block_type,
      'block_style', ds.block_style,
      'order', ds."order",
      'active_status', ds.active_status,
      'config', public.fn_shopify_landing_merge_section_config(
        ds.block_type::text,
        coalesce(ds.config, dbt.config)
      )
    ) AS section
    FROM public.display_settings ds
    LEFT JOIN public.display_block_template dbt
      ON dbt.block_type = ds.block_type
     AND dbt.block_style = ds.block_style
    WHERE ds.merchant_id = v_merchant_id
      AND ds.page = 'shopify_loyalty_landing'::public.display_page_type
      AND coalesce(ds.active_status, true) IS TRUE
  ) s;

  v_sections := public.fn_enrich_shopify_landing_sections(v_sections, v_merchant_id, v_lang, NULL);

  v_payload := jsonb_build_object(
    'ok', true,
    'published', true,
    'schema_version', coalesce(v_page_config ->> '_schema_version', '2.0.0'),
    'seo', coalesce(v_page_config -> 'seo', '{}'::jsonb),
    'cta_defaults', coalesce(v_page_config -> 'cta_defaults', '{}'::jsonb),
    'brand_scheme', v_scheme,
    'theme', coalesce(v_page_config -> 'theme', '{}'::jsonb),
    'theme_resolved', jsonb_build_object(
      'primary_color', v_display ->> 'primary_color',
      'points', v_display -> 'points'
    ),
    'sections', v_sections,
    'audience', 'guest'
  );

  BEGIN
    PERFORM extensions.ui_cache_set(v_cache_key, v_payload::text, 'EX', 300);
  EXCEPTION WHEN OTHERS THEN
    NULL;
  END;

  RETURN v_payload;
END;
$function$;

CREATE OR REPLACE FUNCTION public.admin_get_shopify_landing_page_settings()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_merchant_id uuid;
  v_row public.merchant_shopify_landing_page_settings;
  v_sections jsonb;
  v_section jsonb;
  v_merged_sections jsonb := '[]'::jsonb;
  v_config jsonb;
  v_scheme jsonb;
BEGIN
  v_merchant_id := public.get_current_merchant_id();
  IF v_merchant_id IS NULL THEN
    RETURN public.fn_response_error('Unauthorized', 'No merchant context', 'UNAUTHORIZED');
  END IF;

  PERFORM public.shopify_seed_default_landing_page(v_merchant_id, NULL);

  SELECT * INTO v_row
  FROM public.merchant_shopify_landing_page_settings
  WHERE merchant_id = v_merchant_id;

  v_sections := coalesce(public.admin_get_display_blocks('shopify_loyalty_landing')::jsonb, '[]'::jsonb);

  FOR v_section IN SELECT * FROM jsonb_array_elements(v_sections)
  LOOP
    v_merged_sections := v_merged_sections || jsonb_build_array(
      v_section || jsonb_build_object(
        'config',
        public.fn_shopify_landing_merge_section_config(
          v_section ->> 'block_type',
          coalesce(v_section -> 'config', '{}'::jsonb)
        )
      )
    );
  END LOOP;

  v_config := public.fn_shopify_landing_merge_page_config(coalesce(v_row.config, '{}'::jsonb));
  v_config := jsonb_set(
    v_config,
    '{theme}',
    public.fn_shopify_landing_page_theme_layout(v_merchant_id),
    true
  );
  v_scheme := coalesce(
    public.fn_shopify_merchant_brand_scheme_merged(v_merchant_id),
    public.fn_shopify_brand_scheme_default()
  );

  RETURN public.fn_response_success(
    'OK',
    'Shopify landing page settings loaded',
    jsonb_build_object(
      'config', v_config,
      'brand_scheme', v_scheme,
      'resolved', public.fn_resolve_widget_merchant_display(v_merchant_id),
      'storage', public.fn_resolve_shopify_landing_storage(v_merchant_id),
      'publish_status', coalesce(v_row.publish_status, 'draft'),
      'published_at', v_row.published_at,
      'updated_at', v_row.updated_at,
      'sections', v_merged_sections
    )
  );
END;
$function$;

CREATE OR REPLACE FUNCTION public.fn_compose_shopify_hub(
  p_merchant_id uuid,
  p_user_id uuid,
  p_language text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_hub jsonb;
  v_scheme jsonb;
BEGIN
  v_hub := public.fn_shopify_hub_apply_images(
    p_merchant_id,
    public.fn_compose_shopify_hub_unbranded(p_merchant_id, p_user_id, p_language)
  );
  v_scheme := coalesce(
    public.fn_shopify_merchant_brand_scheme_merged(p_merchant_id),
    public.fn_shopify_brand_scheme_default()
  );
  RETURN jsonb_set(v_hub, '{branding,scheme}', v_scheme, true);
END;
$function$;

-- ---------------------------------------------------------------------------
-- Data cleanup v1 → v2
-- ---------------------------------------------------------------------------
UPDATE public.merchant_display_settings d
SET shopify_brand_scheme = public.fn_shopify_brand_scheme_merge(d.shopify_brand_scheme, d.primary_color),
    updated_at = now()
WHERE d.shopify_brand_scheme IS NOT NULL;

UPDATE public.display_settings ds
SET config = jsonb_set(
      config,
      '{surface,swatch}',
      to_jsonb('brand'::text),
      true
    ),
    updated_at = now()
WHERE ds.page = 'shopify_loyalty_landing'::public.display_page_type
  AND config #>> '{surface,swatch}' = 'extra';

UPDATE public.display_settings ds
SET config = jsonb_set(
      config,
      '{content_card,bg_color}',
      'null'::jsonb,
      true
    ),
    updated_at = now()
WHERE ds.block_type = 'shopify_landing_hero'::public.display_block_type
  AND upper(coalesce(config #>> '{content_card,bg_color}', '')) = '#1C1C1C';

SELECT public.fn_invalidate_shopify_landing_page_cache(merchant_id)
FROM public.merchant_shopify_landing_page_settings;

DO $migrate$
DECLARE
  v_rec record;
  v_errors jsonb;
BEGIN
  FOR v_rec IN
    SELECT merchant_id, shopify_brand_scheme
    FROM public.merchant_display_settings
    WHERE shopify_brand_scheme IS NOT NULL
  LOOP
    v_errors := public.fn_validate_shopify_brand_scheme(v_rec.shopify_brand_scheme);
    IF jsonb_array_length(v_errors) > 0 THEN
      RAISE EXCEPTION 'shopify_brand_scheme validation failed for merchant %: %',
        v_rec.merchant_id, v_errors::text;
    END IF;
  END LOOP;
END;
$migrate$;

-- ---------------------------------------------------------------------------
-- Drop SQL colour resolvers (storefront owns derivation)
-- ---------------------------------------------------------------------------
DROP FUNCTION IF EXISTS public.fn_resolve_shopify_brand_scheme(jsonb);
DROP FUNCTION IF EXISTS public.fn_resolve_shopify_landing_section_style(jsonb, text, jsonb, text);
DROP FUNCTION IF EXISTS public.fn_shopify_landing_compose_theme(uuid);

GRANT EXECUTE ON FUNCTION public.fn_shopify_brand_scheme_null_if_placeholder(text) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.fn_shopify_landing_page_theme_layout(uuid) TO anon, authenticated, service_role;
