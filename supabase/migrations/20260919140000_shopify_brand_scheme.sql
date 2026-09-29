-- Shopify brand scheme — central merchant-level colors (widget, landing, hub).
-- Spec: docs/SHOPIFY_BRAND_SCHEME_EDITORS_PLAN.md §4
-- Draft for MCP apply_migration — do not apply without approval.

-- ---------------------------------------------------------------------------
-- Schema
-- ---------------------------------------------------------------------------
ALTER TABLE public.merchant_display_settings
  ADD COLUMN IF NOT EXISTS shopify_brand_scheme jsonb;

-- ---------------------------------------------------------------------------
-- Scheme defaults, merge, validate, resolve
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.fn_shopify_brand_scheme_default()
RETURNS jsonb
LANGUAGE sql
IMMUTABLE
AS $function$
  SELECT jsonb_build_object(
    '_schema_version', '1.0.0',
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
      'heading', '#0D0D0D',
      'text', '#0D0D0D',
      'link', NULL,
      'link_hover', NULL,
      'border', NULL,
      'shadow', NULL,
      'dark_surface', '#1C1C1C',
      'extra', NULL
    ),
    'buttons', jsonb_build_object(
      'primary', jsonb_build_object(
        'bg', NULL,
        'text', NULL,
        'border', NULL,
        'hover_bg', NULL,
        'hover_text', NULL,
        'hover_border', NULL,
        'border_width_px', 0
      ),
      'secondary', jsonb_build_object(
        'bg', 'transparent',
        'text', NULL,
        'border', NULL,
        'hover_bg', NULL,
        'hover_text', NULL,
        'hover_border', NULL,
        'border_width_px', 1
      ),
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
  v_out jsonb;
  v_brand text;
BEGIN
  v_out := v_default || v_in;
  v_out := jsonb_set(v_out, '{source}', (v_default -> 'source') || coalesce(v_in -> 'source', '{}'::jsonb), true);
  v_out := jsonb_set(v_out, '{tokens}', (v_default -> 'tokens') || coalesce(v_in -> 'tokens', '{}'::jsonb), true);
  v_out := jsonb_set(
    v_out,
    '{buttons}',
    (v_default -> 'buttons')
      || jsonb_build_object(
        'primary', (v_default -> 'buttons' -> 'primary') || coalesce(v_in -> 'buttons' -> 'primary', '{}'::jsonb),
        'secondary', (v_default -> 'buttons' -> 'secondary') || coalesce(v_in -> 'buttons' -> 'secondary', '{}'::jsonb),
        'radius_px', coalesce(v_in -> 'buttons' -> 'radius_px', v_default -> 'buttons' -> 'radius_px')
      ),
    true
  );

  v_brand := v_out #>> '{tokens,brand}';
  IF v_brand IS NULL OR btrim(v_brand) = '' THEN
    v_brand := coalesce(nullif(btrim(p_primary_color), ''), '#1C1C1C');
    v_out := jsonb_set(v_out, '{tokens,brand}', to_jsonb(v_brand), true);
  END IF;

  RETURN v_out;
END;
$function$;

CREATE OR REPLACE FUNCTION public.fn_shopify_brand_scheme_source_to_imported_from(p_source jsonb)
RETURNS jsonb
LANGUAGE sql
IMMUTABLE
AS $function$
  SELECT CASE
    WHEN p_source IS NULL OR jsonb_typeof(p_source) <> 'object' THEN NULL
    WHEN coalesce(p_source ->> 'kind', 'custom') <> 'theme' THEN NULL
    ELSE (p_source - 'kind' - 'detached_at')
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
  v_err text;
  v_radius int;
BEGIN
  IF p_scheme IS NULL OR jsonb_typeof(p_scheme) <> 'object' THEN
    RETURN jsonb_build_array(jsonb_build_object('path', '', 'message', 'scheme must be a JSON object'));
  END IF;

  v_merged := public.fn_shopify_brand_scheme_merge(p_scheme, p_scheme #>> '{tokens,brand}');

  IF coalesce(v_merged ->> '_schema_version', '') <> '1.0.0' THEN
    v_errors := v_errors || jsonb_build_array(jsonb_build_object(
      'path', '_schema_version',
      'message', '_schema_version must be 1.0.0'
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
  IF NOT public.fn_shopify_landing_is_hex(v_tokens ->> 'brand') THEN
    v_errors := v_errors || jsonb_build_array(jsonb_build_object(
      'path', 'tokens.brand',
      'message', 'tokens.brand must be a hex color'
    ));
  END IF;

  FOREACH v_field IN ARRAY ARRAY['background', 'heading', 'text', 'dark_surface'] LOOP
    IF NOT public.fn_shopify_landing_is_hex(v_tokens ->> v_field) THEN
      v_errors := v_errors || jsonb_build_array(jsonb_build_object(
        'path', 'tokens.' || v_field,
        'message', format('tokens.%s must be a hex color', v_field)
      ));
    END IF;
  END LOOP;

  FOREACH v_field IN ARRAY ARRAY['link', 'link_hover', 'border', 'shadow', 'extra'] LOOP
    IF v_tokens ? v_field AND v_tokens -> v_field IS NOT NULL AND v_tokens -> v_field <> 'null'::jsonb THEN
      IF NOT public.fn_shopify_landing_is_hex(v_tokens ->> v_field) THEN
        v_errors := v_errors || jsonb_build_array(jsonb_build_object(
          'path', 'tokens.' || v_field,
          'message', format('tokens.%s must be hex or null', v_field)
        ));
      END IF;
    END IF;
  END LOOP;

  v_buttons := coalesce(v_merged -> 'buttons', '{}'::jsonb);
  v_err := public.fn_shopify_landing_validate_button_role_v2('primary', v_buttons -> 'primary', false);
  IF v_err IS NOT NULL THEN
    v_errors := v_errors || jsonb_build_array(jsonb_build_object(
      'path', replace(v_err, 'theme.buttons.', 'buttons.'),
      'message', v_err
    ));
  END IF;
  v_err := public.fn_shopify_landing_validate_button_role_v2('secondary', v_buttons -> 'secondary', true);
  IF v_err IS NOT NULL THEN
    v_errors := v_errors || jsonb_build_array(jsonb_build_object(
      'path', replace(v_err, 'theme.buttons.', 'buttons.'),
      'message', v_err
    ));
  END IF;

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

CREATE OR REPLACE FUNCTION public.fn_shopify_merchant_brand_scheme_merged(p_merchant_id uuid)
RETURNS jsonb
LANGUAGE sql
STABLE
SET search_path TO 'public'
AS $function$
  SELECT public.fn_shopify_brand_scheme_merge(
    d.shopify_brand_scheme,
    d.primary_color
  )
  FROM public.merchant_display_settings d
  WHERE d.merchant_id = p_merchant_id;
$function$;

CREATE OR REPLACE FUNCTION public.fn_resolve_shopify_brand_scheme(p_scheme jsonb)
RETURNS jsonb
LANGUAGE plpgsql
IMMUTABLE
AS $function$
DECLARE
  v_merged jsonb;
  v_brand text;
  v_tokens jsonb;
  v_theme jsonb;
  v_style jsonb;
  v_link text;
  v_link_hover text;
BEGIN
  v_merged := public.fn_shopify_brand_scheme_merge(p_scheme, p_scheme #>> '{tokens,brand}');
  v_tokens := v_merged -> 'tokens';
  v_brand := v_tokens ->> 'brand';

  v_link := coalesce(v_tokens ->> 'link', v_brand);
  v_link_hover := coalesce(v_tokens ->> 'link_hover', v_link);

  v_theme := jsonb_build_object(
    'palette', jsonb_build_object(
      'background', coalesce(v_tokens ->> 'background', '#FFFFFF'),
      'heading', coalesce(v_tokens ->> 'heading', '#0D0D0D'),
      'text', coalesce(v_tokens ->> 'text', '#0D0D0D'),
      'link', v_link,
      'link_hover', v_link_hover,
      'border', v_tokens -> 'border',
      'shadow', v_tokens -> 'shadow',
      'dark_surface', coalesce(v_tokens ->> 'dark_surface', '#1C1C1C'),
      'extra', v_tokens -> 'extra'
    ),
    'buttons', coalesce(v_merged -> 'buttons', public.fn_shopify_brand_scheme_default() -> 'buttons')
  );

  v_style := public.fn_resolve_shopify_landing_section_style(
    jsonb_build_object('swatch', 'background', 'custom_hex', NULL, 'gradient', false),
    NULL,
    v_theme,
    v_brand
  );

  RETURN jsonb_build_object(
    'mode', v_style ->> 'mode',
    'tokens', jsonb_build_object(
      'brand', v_brand,
      'background', coalesce(v_tokens ->> 'background', '#FFFFFF'),
      'heading', coalesce(v_tokens ->> 'heading', '#0D0D0D'),
      'text', coalesce(v_tokens ->> 'text', '#0D0D0D'),
      'link', v_style ->> 'link',
      'link_hover', v_style ->> 'link_hover',
      'border', v_style ->> 'card_border',
      'shadow', coalesce(v_tokens ->> 'shadow', NULL),
      'dark_surface', coalesce(v_tokens ->> 'dark_surface', '#1C1C1C'),
      'extra', v_tokens -> 'extra'
    ),
    'buttons', jsonb_build_object(
      'primary', jsonb_build_object(
        'bg', v_style ->> 'button_primary_bg',
        'text', v_style ->> 'button_primary_text',
        'border', v_style ->> 'button_primary_border',
        'hover_bg', v_style ->> 'button_primary_hover_bg',
        'hover_text', v_style ->> 'button_primary_hover_text',
        'hover_border', v_style ->> 'button_primary_hover_border',
        'border_width_px', v_style -> 'button_primary_border_width_px'
      ),
      'secondary', jsonb_build_object(
        'bg', v_style ->> 'button_secondary_bg',
        'text', v_style ->> 'button_secondary_text',
        'border', v_style ->> 'button_secondary_border',
        'hover_bg', v_style ->> 'button_secondary_hover_bg',
        'hover_text', v_style ->> 'button_secondary_hover_text',
        'hover_border', v_style ->> 'button_secondary_hover_border',
        'border_width_px', v_style -> 'button_secondary_border_width_px'
      ),
      'radius_px', v_style -> 'button_radius_px'
    )
  );
END;
$function$;

CREATE OR REPLACE FUNCTION public.fn_shopify_landing_compose_theme(p_merchant_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SET search_path TO 'public'
AS $function$
DECLARE
  v_scheme jsonb;
  v_slim jsonb;
  v_palette jsonb;
  v_pad int;
  v_dismissed jsonb;
BEGIN
  v_scheme := coalesce(
    public.fn_shopify_merchant_brand_scheme_merged(p_merchant_id),
    public.fn_shopify_brand_scheme_default()
  );

  SELECT public.fn_shopify_landing_merge_page_config(m.config) -> 'theme'
  INTO v_slim
  FROM public.merchant_shopify_landing_page_settings m
  WHERE m.merchant_id = p_merchant_id;

  IF v_slim IS NULL THEN
    v_slim := public.fn_shopify_landing_default_page_config() -> 'theme';
  END IF;

  v_palette := (v_scheme -> 'tokens') - 'brand';
  v_pad := coalesce((v_slim ->> 'section_padding_px')::int, 88);
  v_dismissed := coalesce(v_slim #> '{import,first_run_dismissed_at}', 'null'::jsonb);

  RETURN jsonb_build_object(
    'palette', v_palette,
    'buttons', coalesce(v_scheme -> 'buttons', public.fn_shopify_brand_scheme_default() -> 'buttons'),
    'section_padding_px', v_pad,
    'import', jsonb_build_object(
      'first_run_dismissed_at', v_dismissed,
      'imported_from', public.fn_shopify_brand_scheme_source_to_imported_from(v_scheme -> 'source')
    )
  );
END;
$function$;

-- ---------------------------------------------------------------------------
-- Admin brand scheme RPCs
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
      'resolved', public.fn_resolve_shopify_brand_scheme(v_scheme),
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
-- Widget display resolver + admin/cached reads
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
  v_scheme_resolved jsonb;
BEGIN
  SELECT * INTO v_row FROM public.merchant_display_settings WHERE merchant_id = p_merchant_id;

  v_scheme_merged := public.fn_shopify_brand_scheme_merge(
    v_row.shopify_brand_scheme,
    coalesce(v_row.primary_color, '#1C1C1C')
  );
  v_scheme_resolved := public.fn_resolve_shopify_brand_scheme(v_scheme_merged);

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
    'scheme_merged', v_scheme_merged,
    'scheme_resolved', v_scheme_resolved
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
  v_display public.merchant_display_settings;
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
      'scheme_resolved', public.fn_resolve_shopify_brand_scheme(v_scheme),
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

  v_cache_key := 'merchant:' || v_merchant_id::text || ':widget:' || p_widget_type;

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
    'resolved', (v_display - 'scheme_merged' - 'scheme_resolved')
      || jsonb_build_object('scheme', v_display -> 'scheme_resolved')
  );

  BEGIN PERFORM extensions.ui_cache_set(v_cache_key, v_payload::text, 'EX', 300); EXCEPTION WHEN OTHERS THEN NULL; END;
  RETURN v_payload;
END;
$function$;

-- ---------------------------------------------------------------------------
-- Landing config: slim stored theme; composed theme at read time
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.fn_shopify_landing_merge_page_config(p_config jsonb)
RETURNS jsonb
LANGUAGE plpgsql
IMMUTABLE
AS $function$
DECLARE
  v_merged jsonb;
  v_theme jsonb;
BEGIN
  v_merged := public.fn_jsonb_deep_merge_landing(
    public.fn_shopify_landing_default_page_config(),
    public.fn_shopify_landing_upgrade_page_config(coalesce(p_config, '{}'::jsonb))
  );
  v_theme := coalesce(v_merged -> 'theme', '{}'::jsonb);
  v_theme := (v_theme - 'palette' - 'buttons')
    || jsonb_build_object(
      'import', jsonb_build_object(
        'first_run_dismissed_at', v_theme #> '{import,first_run_dismissed_at}'
      )
    );
  RETURN jsonb_set(v_merged, '{theme}', v_theme, true);
END;
$function$;

CREATE OR REPLACE FUNCTION public.fn_shopify_landing_default_page_config()
RETURNS jsonb
LANGUAGE sql
IMMUTABLE
AS $function$
  SELECT jsonb_build_object(
    '_schema_version', '2.0.0',
    'seo', jsonb_build_object(
      'slug', 'rewards',
      'meta_title', '',
      'meta_description', '',
      'og_image_url', ''
    ),
    'cta_defaults', jsonb_build_object(
      'guest', jsonb_build_object(
        'button_style', 'primary',
        'link_type', 'drawer',
        'page', 'drawer_earn-channels',
        'url', '',
        'url_param', ''
      ),
      'member', jsonb_build_object(
        'button_style', 'primary',
        'link_type', 'drawer',
        'page', 'drawer_my-rewards',
        'url', '',
        'url_param', ''
      )
    ),
    'theme', jsonb_build_object(
      'section_padding_px', 88,
      'import', jsonb_build_object(
        'first_run_dismissed_at', NULL
      )
    )
  );
$function$;

CREATE OR REPLACE FUNCTION public.fn_validate_shopify_landing_page_config(p_config jsonb)
RETURNS text
LANGUAGE plpgsql
IMMUTABLE
AS $function$
DECLARE
  v_slug text;
  v_theme jsonb;
  v_style text;
  v_pad int;
BEGIN
  IF p_config IS NULL OR jsonb_typeof(p_config) <> 'object' THEN
    RETURN 'config must be a JSON object';
  END IF;

  IF coalesce(p_config ->> '_schema_version', '') <> '2.0.0' THEN
    RETURN '_schema_version must be 2.0.0';
  END IF;

  v_slug := coalesce(p_config #>> '{seo,slug}', '');
  IF v_slug = '' OR v_slug !~ '^[a-z0-9-]+$' THEN
    RETURN 'seo.slug must be lowercase letters, numbers, and hyphens';
  END IF;

  v_theme := p_config -> 'theme';
  IF v_theme IS NULL OR jsonb_typeof(v_theme) <> 'object' THEN
    RETURN 'theme is required';
  END IF;

  IF v_theme ? 'secondary_color' OR v_theme ? 'accent_color' OR v_theme ? 'text_on_dark'
     OR v_theme ? 'text_on_light' OR v_theme ? 'typography' THEN
    RETURN 'theme uses removed v1 keys; upgrade to v2 palette model';
  END IF;
  IF v_theme ? 'palette' OR v_theme ? 'buttons' THEN
    RETURN 'theme.palette and theme.buttons moved to shopify_brand_scheme; use Brand scheme editor';
  END IF;
  IF v_theme #> '{import,imported_from}' IS NOT NULL AND v_theme #> '{import,imported_from}' <> 'null'::jsonb THEN
    RETURN 'theme.import.imported_from moved to shopify_brand_scheme; use Brand scheme editor';
  END IF;

  v_pad := coalesce((v_theme ->> 'section_padding_px')::int, 88);
  IF v_pad NOT BETWEEN 24 AND 160 THEN
    RETURN 'theme.section_padding_px must be 24–160';
  END IF;

  FOREACH v_style IN ARRAY ARRAY[
    p_config #>> '{cta_defaults,guest,button_style}',
    p_config #>> '{cta_defaults,member,button_style}'
  ] LOOP
    IF coalesce(v_style, '') NOT IN ('primary', 'secondary', 'link') THEN
      RETURN 'cta_defaults button_style must be primary, secondary, or link';
    END IF;
  END LOOP;

  RETURN NULL;
END;
$function$;

CREATE OR REPLACE FUNCTION public.admin_upsert_shopify_landing_page_settings(p_config jsonb)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_merchant_id uuid;
  v_err text;
  v_row public.merchant_shopify_landing_page_settings;
  v_config jsonb;
  v_theme jsonb;
BEGIN
  v_merchant_id := public.get_current_merchant_id();
  IF v_merchant_id IS NULL THEN
    RETURN public.fn_response_error('Unauthorized', 'No merchant context', 'UNAUTHORIZED');
  END IF;

  v_theme := coalesce(p_config -> 'theme', '{}'::jsonb);
  IF v_theme ? 'palette' OR v_theme ? 'buttons' THEN
    RETURN public.fn_response_error(
      'Invalid config',
      'theme.palette and theme.buttons moved to shopify_brand_scheme',
      'VALIDATION_ERROR'
    );
  END IF;
  IF v_theme #> '{import,imported_from}' IS NOT NULL AND v_theme #> '{import,imported_from}' <> 'null'::jsonb THEN
    RETURN public.fn_response_error(
      'Invalid config',
      'theme.import.imported_from moved to shopify_brand_scheme',
      'VALIDATION_ERROR'
    );
  END IF;

  v_config := public.fn_shopify_landing_upgrade_page_config(p_config);

  v_err := public.fn_validate_shopify_landing_page_config(v_config);
  IF v_err IS NOT NULL THEN
    RETURN public.fn_response_error('Invalid config', v_err, 'VALIDATION_ERROR');
  END IF;

  INSERT INTO public.merchant_shopify_landing_page_settings (merchant_id, config)
  VALUES (v_merchant_id, v_config)
  ON CONFLICT (merchant_id) DO UPDATE
  SET config = EXCLUDED.config,
      updated_at = now()
  RETURNING * INTO v_row;

  PERFORM public.fn_invalidate_shopify_landing_page_cache(v_merchant_id);

  RETURN public.fn_response_success(
    'OK',
    'Shopify landing page settings saved',
    jsonb_build_object(
      'config', v_row.config,
      'publish_status', v_row.publish_status,
      'updated_at', v_row.updated_at
    )
  );
END;
$function$;

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
  v_theme jsonb;
  v_primary text;
  v_tokens jsonb;
  v_cfg jsonb;
  v_hub jsonb;
  v_points text;
  v_current_tier uuid;
  v_tile jsonb;
  v_tiles jsonb;
  v_referral jsonb;
BEGIN
  v_theme := public.fn_shopify_landing_compose_theme(p_merchant_id);

  SELECT d.primary_color INTO v_primary
  FROM public.merchant_display_settings d
  WHERE d.merchant_id = p_merchant_id;

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
    v_tokens := public.fn_resolve_shopify_landing_section_style(
      coalesce(v_cfg -> 'surface', '{}'::jsonb),
      v_cfg ->> 'text_hex',
      coalesce(v_theme, '{}'::jsonb),
      v_primary
    );
    v_section := (v_section - 'config')
      || jsonb_build_object('config', v_cfg, 'style_tokens', v_tokens);

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

  v_cache_key := 'merchant:' || v_merchant_id::text || ':shopify_landing_page:' || v_lang || ':published';

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
  v_page_config := jsonb_set(
    v_page_config,
    '{theme}',
    public.fn_shopify_landing_compose_theme(v_merchant_id),
    true
  );

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
    'schema_version', coalesce(v_page_config ->> '_schema_version', '1.0.0'),
    'seo', coalesce(v_page_config -> 'seo', '{}'::jsonb),
    'cta_defaults', coalesce(v_page_config -> 'cta_defaults', '{}'::jsonb),
    'theme', coalesce(v_page_config -> 'theme', '{}'::jsonb),
    'theme_resolved', public.fn_resolve_widget_merchant_display(v_merchant_id),
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
  v_config := jsonb_set(v_config, '{theme}', public.fn_shopify_landing_compose_theme(v_merchant_id), true);

  RETURN public.fn_response_success(
    'OK',
    'Shopify landing page settings loaded',
    jsonb_build_object(
      'config', v_config,
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

-- ---------------------------------------------------------------------------
-- Hub composer + shopify_hub template default
-- ---------------------------------------------------------------------------
UPDATE public.widget_config_template
SET config_default = config_default || jsonb_build_object('blend_with_theme', true),
    updated_at = now()
WHERE widget_type = 'shopify_hub';

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
  v_scheme := public.fn_resolve_shopify_brand_scheme(
    coalesce(
      public.fn_shopify_merchant_brand_scheme_merged(p_merchant_id),
      public.fn_shopify_brand_scheme_default()
    )
  );
  RETURN jsonb_set(v_hub, '{branding,scheme}', coalesce(v_scheme, 'null'::jsonb), true);
END;
$function$;

-- ---------------------------------------------------------------------------
-- Data migration §4.3
-- ---------------------------------------------------------------------------
UPDATE public.merchant_display_settings d
SET shopify_brand_scheme = public.fn_shopify_brand_scheme_merge(
  jsonb_build_object(
    '_schema_version', '1.0.0',
    'source', COALESCE(
      (
        SELECT jsonb_build_object(
          'kind',
          CASE
            WHEN l.config #> '{theme,import,imported_from}' IS NOT NULL
              AND l.config #> '{theme,import,imported_from}' <> 'null'::jsonb
            THEN 'theme'
            ELSE 'custom'
          END
        )
        || COALESCE(l.config #> '{theme,import,imported_from}', '{}'::jsonb)
        || jsonb_build_object('detached_at', NULL)
        FROM public.merchant_shopify_landing_page_settings l
        WHERE l.merchant_id = d.merchant_id
      ),
      jsonb_build_object('kind', 'custom')
    ),
    'tokens',
    (
      jsonb_build_object('brand', COALESCE(d.primary_color, '#1C1C1C'))
      || COALESCE(
        (
          SELECT l.config #> '{theme,palette}'
          FROM public.merchant_shopify_landing_page_settings l
          WHERE l.merchant_id = d.merchant_id
        ),
        '{}'::jsonb
      )
      || CASE
        WHEN NOT EXISTS (
          SELECT 1
          FROM public.merchant_shopify_landing_page_settings l
          WHERE l.merchant_id = d.merchant_id
            AND l.config #> '{theme,import,imported_from}' IS NOT NULL
            AND l.config #> '{theme,import,imported_from}' <> 'null'::jsonb
        ) THEN jsonb_build_object(
          'link',
          CASE
            WHEN COALESCE(
              (
                SELECT l.config #>> '{theme,palette,link}'
                FROM public.merchant_shopify_landing_page_settings l
                WHERE l.merchant_id = d.merchant_id
              ),
              '#0D0D0D'
            ) IN ('#0D0D0D', '#0d0d0d')
            THEN NULL
            ELSE (
              SELECT l.config #> '{theme,palette,link}'
              FROM public.merchant_shopify_landing_page_settings l
              WHERE l.merchant_id = d.merchant_id
            )
          END,
          'link_hover',
          CASE
            WHEN COALESCE(
              (
                SELECT l.config #>> '{theme,palette,link_hover}'
                FROM public.merchant_shopify_landing_page_settings l
                WHERE l.merchant_id = d.merchant_id
              ),
              COALESCE(
                (
                  SELECT l.config #>> '{theme,palette,link}'
                  FROM public.merchant_shopify_landing_page_settings l
                  WHERE l.merchant_id = d.merchant_id
                ),
                '#0D0D0D'
              )
            ) IN ('#0D0D0D', '#0d0d0d')
            THEN NULL
            ELSE (
              SELECT l.config #> '{theme,palette,link_hover}'
              FROM public.merchant_shopify_landing_page_settings l
              WHERE l.merchant_id = d.merchant_id
            )
          END
        )
        ELSE '{}'::jsonb
      END
    ),
    'buttons', COALESCE(
      (
        SELECT l.config #> '{theme,buttons}'
        FROM public.merchant_shopify_landing_page_settings l
        WHERE l.merchant_id = d.merchant_id
      ),
      public.fn_shopify_brand_scheme_default() -> 'buttons'
    )
  ),
  d.primary_color
)
WHERE d.shopify_brand_scheme IS NULL
  AND (
    EXISTS (
      SELECT 1 FROM public.merchant_widget_settings w
      WHERE w.merchant_id = d.merchant_id AND w.widget_type = 'shopify'
    )
    OR EXISTS (
      SELECT 1 FROM public.merchant_shopify_landing_page_settings l
      WHERE l.merchant_id = d.merchant_id
    )
  );

UPDATE public.merchant_shopify_landing_page_settings
SET config = jsonb_set(
      config,
      '{theme}',
      jsonb_build_object(
        'section_padding_px', COALESCE(config #> '{theme,section_padding_px}', '88'::jsonb),
        'import', jsonb_build_object(
          'first_run_dismissed_at', config #> '{theme,import,first_run_dismissed_at}'
        )
      ),
      true
    ),
    updated_at = now();

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
-- Grants
-- ---------------------------------------------------------------------------
GRANT EXECUTE ON FUNCTION public.fn_shopify_brand_scheme_default() TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.fn_shopify_brand_scheme_merge(jsonb, text) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.fn_shopify_brand_scheme_source_to_imported_from(jsonb) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.fn_validate_shopify_brand_scheme(jsonb) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.fn_shopify_merchant_brand_scheme_merged(uuid) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.fn_resolve_shopify_brand_scheme(jsonb) TO anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.fn_shopify_landing_compose_theme(uuid) TO anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.admin_get_shopify_brand_scheme() TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.admin_upsert_shopify_brand_scheme(jsonb) TO authenticated, service_role;
