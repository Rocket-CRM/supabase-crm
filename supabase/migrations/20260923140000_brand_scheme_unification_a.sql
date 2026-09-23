-- Brand scheme unification — Migration A (Phase 1)
-- Rename shopify_brand_scheme → brand_scheme, v2.3.0, backfill all merchants.
-- Flat column readers unchanged until Migration B.

BEGIN;

-- ---------------------------------------------------------------------------
-- Capture migration inputs + V1 snapshot (uses pre-rename column + old helpers)
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.tmp_brand_unification_snapshot (
  merchant_id uuid PRIMARY KEY,
  merchant_code text NOT NULL,
  display_settings_fast jsonb NOT NULL,
  captured_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS public.tmp_brand_migration_inputs (
  merchant_id uuid PRIMARY KEY,
  new_scheme jsonb NOT NULL
);

TRUNCATE public.tmp_brand_migration_inputs;

INSERT INTO public.tmp_brand_migration_inputs (merchant_id, new_scheme)
WITH prep AS (
  SELECT
    m.id AS merchant_id,
    EXISTS (
      SELECT 1
      FROM public.merchant_credentials mc
      WHERE mc.merchant_id = m.id
        AND mc.service_name = 'shopify_app'
        AND mc.is_active IS TRUE
    ) AS is_shopify,
    mds.primary_color,
    mds.secondary_color,
    mds.border_radius_cards,
    coalesce(
      public.fn_shopify_merchant_brand_scheme_merged(m.id),
      public.fn_shopify_brand_scheme_merge(NULL, NULL)
    ) AS current_scheme
  FROM public.merchant_master m
  LEFT JOIN public.merchant_display_settings mds ON mds.merchant_id = m.id
),
computed AS (
  SELECT
    merchant_id,
    is_shopify,
    coalesce(nullif(btrim(secondary_color), ''), '#666666') AS member_accent,
    least(
      40,
      greatest(
        0,
        coalesce(
          nullif(regexp_replace(coalesce(border_radius_cards, '12px'), 'px$', ''), '')::int,
          12
        )
      )
    ) AS member_cards,
    coalesce(nullif(btrim(primary_color), ''), '#000000') AS member_primary,
    current_scheme,
    coalesce((current_scheme #>> '{buttons,radius_px}')::int, 8) AS btn_radius
  FROM prep
)
SELECT
  merchant_id,
  jsonb_set(
    jsonb_set(
      jsonb_set(
        jsonb_set(
          current_scheme,
          '{_schema_version}',
          '"2.3.0"'::jsonb
        ),
        '{tokens,primary}',
        to_jsonb(
          CASE
            WHEN is_shopify THEN coalesce(current_scheme #>> '{tokens,primary}', '#1C1C1C')
            ELSE member_primary
          END
        )
      ),
      '{tokens,accent}',
      to_jsonb(member_accent)
    ),
    '{cards}',
    jsonb_build_object(
      'radius_px',
      CASE WHEN is_shopify THEN btn_radius ELSE member_cards END
    )
  )
FROM computed;

INSERT INTO public.tmp_brand_unification_snapshot (merchant_id, merchant_code, display_settings_fast)
SELECT
  m.id,
  coalesce(nullif(btrim(m.merchant_code), ''), m.id::text),
  public.get_display_settings_fast(m.merchant_code)::jsonb
FROM public.merchant_master m
ON CONFLICT (merchant_id) DO UPDATE
SET
  merchant_code = EXCLUDED.merchant_code,
  display_settings_fast = EXCLUDED.display_settings_fast,
  captured_at = now();

ALTER TABLE public.merchant_display_settings
  RENAME COLUMN shopify_brand_scheme TO brand_scheme;

-- ---------------------------------------------------------------------------
-- Renamed helpers + v2.3.0 scheme functions
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.fn_brand_scheme_null_if_placeholder(p_value text)
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

CREATE OR REPLACE FUNCTION public.fn_brand_scheme_source_to_imported_from(p_source jsonb)
RETURNS jsonb
LANGUAGE sql
IMMUTABLE
AS $function$
  SELECT CASE
    WHEN p_source IS NULL OR jsonb_typeof(p_source) <> 'object' THEN NULL
    WHEN coalesce(p_source ->> 'kind', 'custom') <> 'theme' THEN NULL
    ELSE jsonb_strip_nulls(
      jsonb_build_object(
        'theme_id', p_source -> 'theme_id',
        'theme_name', p_source -> 'theme_name',
        'scheme_model', p_source -> 'scheme_model',
        'scheme_id', p_source -> 'scheme_id',
        'dark_scheme_id', p_source -> 'dark_scheme_id',
        'imported_at', p_source -> 'imported_at'
      )
    )
  END;
$function$;

CREATE OR REPLACE FUNCTION public.fn_brand_scheme_default()
RETURNS jsonb
LANGUAGE sql
IMMUTABLE
AS $function$
  SELECT jsonb_build_object(
    '_schema_version', '2.3.0',
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
      'primary', '#1C1C1C',
      'background', '#FFFFFF',
      'dark_surface', '#1C1C1C',
      'foreground_heading', '#0D0D0D',
      'foreground', '#0D0D0D',
      'text', '#0D0D0D',
      'accent', '#666666'
    ),
    'buttons', jsonb_build_object(
      'primary', jsonb_build_object('bg', NULL, 'text', NULL),
      'secondary', jsonb_build_object('text', NULL),
      'radius_px', 8
    ),
    'cards', jsonb_build_object('radius_px', 12)
  );
$function$;

CREATE OR REPLACE FUNCTION public.fn_brand_scheme_merge(p_scheme jsonb)
RETURNS jsonb
LANGUAGE plpgsql
IMMUTABLE
AS $function$
DECLARE
  v_default jsonb := public.fn_brand_scheme_default();
  v_in jsonb := coalesce(p_scheme, '{}'::jsonb);
  v_src jsonb;
  v_tok jsonb;
  v_btn jsonb;
  v_cards jsonb;
  v_primary text;
  v_foreground text;
  v_heading text;
  v_accent text;
  v_radius int;
  v_cards_radius int;
BEGIN
  v_src := (v_default -> 'source') || coalesce(v_in -> 'source', '{}'::jsonb);
  v_tok := coalesce(v_in -> 'tokens', '{}'::jsonb);

  v_primary := coalesce(
    CASE WHEN public.fn_shopify_landing_is_hex(v_tok ->> 'primary') THEN upper(btrim(v_tok ->> 'primary')) END,
    CASE WHEN public.fn_shopify_landing_is_hex(v_tok ->> 'brand') THEN upper(btrim(v_tok ->> 'brand')) END,
    v_default #>> '{tokens,primary}'
  );

  v_foreground := coalesce(
    CASE WHEN public.fn_shopify_landing_is_hex(v_tok ->> 'foreground') THEN upper(btrim(v_tok ->> 'foreground')) END,
    CASE WHEN public.fn_shopify_landing_is_hex(v_tok ->> 'text') THEN upper(btrim(v_tok ->> 'text')) END,
    CASE WHEN public.fn_shopify_landing_is_hex(v_tok ->> 'heading') THEN upper(btrim(v_tok ->> 'heading')) END,
    v_default #>> '{tokens,foreground}'
  );

  v_heading := coalesce(
    CASE WHEN public.fn_shopify_landing_is_hex(v_tok ->> 'foreground_heading') THEN upper(btrim(v_tok ->> 'foreground_heading')) END,
    CASE WHEN public.fn_shopify_landing_is_hex(v_tok ->> 'heading') THEN upper(btrim(v_tok ->> 'heading')) END,
    v_foreground
  );

  v_accent := coalesce(
    CASE WHEN public.fn_shopify_landing_is_hex(v_tok ->> 'accent') THEN upper(btrim(v_tok ->> 'accent')) END,
    v_default #>> '{tokens,accent}'
  );

  v_btn := coalesce(v_in -> 'buttons', '{}'::jsonb);
  v_radius := coalesce((v_btn ->> 'radius_px')::int, (v_default -> 'buttons' ->> 'radius_px')::int, 8);

  v_cards := coalesce(v_in -> 'cards', '{}'::jsonb);
  v_cards_radius := coalesce((v_cards ->> 'radius_px')::int, (v_default -> 'cards' ->> 'radius_px')::int, 12);

  RETURN jsonb_build_object(
    '_schema_version', '2.3.0',
    'source', v_src,
    'tokens', jsonb_build_object(
      'primary', v_primary,
      'background', coalesce(
        CASE WHEN public.fn_shopify_landing_is_hex(v_tok ->> 'background') THEN upper(btrim(v_tok ->> 'background')) END,
        v_default #>> '{tokens,background}'
      ),
      'dark_surface', coalesce(
        CASE WHEN public.fn_shopify_landing_is_hex(v_tok ->> 'dark_surface') THEN upper(btrim(v_tok ->> 'dark_surface')) END,
        v_default #>> '{tokens,dark_surface}'
      ),
      'foreground_heading', v_heading,
      'foreground', v_foreground,
      'text', v_foreground,
      'accent', v_accent
    ),
    'buttons', jsonb_build_object(
      'primary', jsonb_build_object(
        'bg', public.fn_brand_scheme_null_if_placeholder(v_btn #>> '{primary,bg}'),
        'text', public.fn_brand_scheme_null_if_placeholder(v_btn #>> '{primary,text}')
      ),
      'secondary', jsonb_build_object(
        'text', public.fn_brand_scheme_null_if_placeholder(v_btn #>> '{secondary,text}')
      ),
      'radius_px', v_radius
    ),
    'cards', jsonb_build_object('radius_px', v_cards_radius)
  );
END;
$function$;

CREATE OR REPLACE FUNCTION public.fn_validate_brand_scheme(p_scheme jsonb)
RETURNS jsonb
LANGUAGE plpgsql
IMMUTABLE
AS $function$
DECLARE
  v_errors jsonb := '[]'::jsonb;
  v_merged jsonb;
  v_tokens jsonb;
  v_buttons jsonb;
  v_cards jsonb;
  v_kind text;
  v_field text;
  v_radius int;
  v_cards_radius int;
  v_opt text;
  v_accent text;
BEGIN
  IF p_scheme IS NULL OR jsonb_typeof(p_scheme) <> 'object' THEN
    RETURN jsonb_build_array(jsonb_build_object('path', '', 'message', 'scheme must be a JSON object'));
  END IF;

  v_merged := public.fn_brand_scheme_merge(p_scheme);

  IF coalesce(p_scheme ->> '_schema_version', '2.3.0') NOT IN ('2.3.0', '2.2.0', '2.1.0', '2.0.0', '1.0.0') THEN
    v_errors := v_errors || jsonb_build_array(jsonb_build_object(
      'path', '_schema_version',
      'message', '_schema_version must be 2.3.0, 2.2.0, 2.1.0, 2.0.0, or 1.0.0'
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
  FOREACH v_field IN ARRAY ARRAY['primary', 'background', 'dark_surface', 'foreground', 'foreground_heading'] LOOP
    IF NOT public.fn_shopify_landing_is_hex(v_tokens ->> v_field) THEN
      v_errors := v_errors || jsonb_build_array(jsonb_build_object(
        'path', 'tokens.' || v_field,
        'message', format('tokens.%s must be a hex color', v_field)
      ));
    END IF;
  END LOOP;

  v_accent := v_tokens ->> 'accent';
  IF v_accent IS NOT NULL AND btrim(v_accent) <> '' AND NOT public.fn_shopify_landing_is_hex(v_accent) THEN
    v_errors := v_errors || jsonb_build_array(jsonb_build_object(
      'path', 'tokens.accent',
      'message', 'tokens.accent must be a hex color or null'
    ));
  END IF;

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
  IF v_radius NOT BETWEEN 0 AND 100 THEN
    v_errors := v_errors || jsonb_build_array(jsonb_build_object(
      'path', 'buttons.radius_px',
      'message', 'buttons.radius_px must be 0–100'
    ));
  END IF;

  v_cards := coalesce(v_merged -> 'cards', '{}'::jsonb);
  v_cards_radius := coalesce((v_cards ->> 'radius_px')::int, 12);
  IF v_cards_radius NOT BETWEEN 0 AND 40 THEN
    v_errors := v_errors || jsonb_build_array(jsonb_build_object(
      'path', 'cards.radius_px',
      'message', 'cards.radius_px must be 0–40'
    ));
  END IF;

  RETURN v_errors;
END;
$function$;

CREATE OR REPLACE FUNCTION public.fn_brand_scheme_merged(p_merchant_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SET search_path TO 'public'
AS $function$
DECLARE
  v_row public.merchant_display_settings;
BEGIN
  SELECT * INTO v_row
  FROM public.merchant_display_settings
  WHERE merchant_id = p_merchant_id;

  IF NOT FOUND THEN
    RETURN public.fn_brand_scheme_default();
  END IF;

  RETURN public.fn_brand_scheme_merge(v_row.brand_scheme);
END;
$function$;

-- Backfill every merchant row
INSERT INTO public.merchant_display_settings (merchant_id, brand_scheme, primary_color)
SELECT
  t.merchant_id,
  public.fn_brand_scheme_merge(t.new_scheme),
  public.fn_brand_scheme_merge(t.new_scheme) #>> '{tokens,primary}'
FROM public.tmp_brand_migration_inputs t
WHERE NOT EXISTS (
  SELECT 1 FROM public.merchant_display_settings mds WHERE mds.merchant_id = t.merchant_id
);

UPDATE public.merchant_display_settings mds
SET
  brand_scheme = public.fn_brand_scheme_merge(t.new_scheme),
  primary_color = public.fn_brand_scheme_merge(t.new_scheme) #>> '{tokens,primary}',
  updated_at = now()
FROM public.tmp_brand_migration_inputs t
WHERE mds.merchant_id = t.merchant_id;

-- ---------------------------------------------------------------------------
-- Admin RPCs
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.admin_get_brand_scheme()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_merchant_id uuid;
  v_logo text;
  v_updated timestamptz;
BEGIN
  v_merchant_id := public.get_current_merchant_id();
  IF v_merchant_id IS NULL THEN
    RETURN public.fn_response_error('Unauthorized', 'No merchant context', 'UNAUTHORIZED');
  END IF;

  SELECT d.logo, d.updated_at
  INTO v_logo, v_updated
  FROM public.merchant_display_settings d
  WHERE d.merchant_id = v_merchant_id;

  RETURN public.fn_response_success(
    'OK',
    'Brand scheme loaded',
    jsonb_build_object(
      'scheme', public.fn_brand_scheme_merged(v_merchant_id),
      'logo', v_logo,
      'updated_at', v_updated
    )
  );
END;
$function$;

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
  v_primary text;
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

  v_primary := v_merged #>> '{tokens,primary}';

  UPDATE public.merchant_display_settings
  SET brand_scheme = v_merged,
      primary_color = v_primary,
      updated_at = now()
  WHERE merchant_id = v_merchant_id;

  IF NOT FOUND THEN
    INSERT INTO public.merchant_display_settings (merchant_id, brand_scheme, primary_color)
    VALUES (v_merchant_id, v_merged, v_primary);
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

CREATE OR REPLACE FUNCTION public.admin_get_shopify_brand_scheme()
RETURNS jsonb
LANGUAGE sql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
  SELECT public.admin_get_brand_scheme();
$function$;

CREATE OR REPLACE FUNCTION public.admin_upsert_shopify_brand_scheme(p_scheme jsonb)
RETURNS jsonb
LANGUAGE sql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
  SELECT public.admin_upsert_brand_scheme(p_scheme, '{}'::jsonb);
$function$;

-- ---------------------------------------------------------------------------
-- Group 2 — column rename + new helper names
-- ---------------------------------------------------------------------------
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

  v_scheme := public.fn_brand_scheme_merged(p_merchant_id);
  v_pad := coalesce((v_slim ->> 'section_padding_px')::int, 88);
  v_dismissed := coalesce(v_slim #> '{import,first_run_dismissed_at}', 'null'::jsonb);

  RETURN jsonb_build_object(
    'section_padding_px', v_pad,
    'import', jsonb_build_object(
      'first_run_dismissed_at', v_dismissed,
      'imported_from', public.fn_brand_scheme_source_to_imported_from(v_scheme -> 'source')
    )
  );
END;
$function$;

CREATE OR REPLACE FUNCTION public.fn_compose_shopify_hub(p_merchant_id uuid, p_user_id uuid, p_language text DEFAULT NULL::text)
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
  v_scheme := public.fn_brand_scheme_merged(p_merchant_id);
  RETURN jsonb_set(v_hub, '{branding,scheme}', v_scheme, true);
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
    'primary_color', coalesce(v_row.primary_color, v_scheme_merged #>> '{tokens,primary}'),
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

  v_scheme := public.fn_brand_scheme_merged(v_merchant_id);

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
  v_scheme := public.fn_brand_scheme_merged(v_merchant_id);

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
      'theme.palette and theme.buttons moved to brand_scheme',
      'VALIDATION_ERROR'
    );
  END IF;
  IF v_theme #> '{import,imported_from}' IS NOT NULL AND v_theme #> '{import,imported_from}' <> 'null'::jsonb THEN
    RETURN public.fn_response_error(
      'Invalid config',
      'theme.import.imported_from moved to brand_scheme',
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

CREATE OR REPLACE FUNCTION public.api_get_shopify_landing_page_cached(p_merchant_code text, p_language text DEFAULT 'en'::text)
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
  v_scheme := public.fn_brand_scheme_merged(v_merchant_id);
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

CREATE OR REPLACE FUNCTION public.fn_validate_shopify_landing_page_config(p_config jsonb)
RETURNS text
LANGUAGE plpgsql
IMMUTABLE
AS $function$
DECLARE
  v_slug text;
  v_theme jsonb;
  v_pad int;
  v_cards jsonb;
  v_gap int;
  v_border text;
  v_fill text;
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
    RETURN 'theme.palette and theme.buttons moved to brand_scheme; use Brand scheme editor';
  END IF;
  IF v_theme #> '{import,imported_from}' IS NOT NULL AND v_theme #> '{import,imported_from}' <> 'null'::jsonb THEN
    RETURN 'theme.import.imported_from moved to brand_scheme; use Brand scheme editor';
  END IF;

  v_pad := coalesce((v_theme ->> 'section_padding_px')::int, 88);
  IF v_pad NOT BETWEEN 24 AND 160 THEN
    RETURN 'theme.section_padding_px must be 24–160';
  END IF;

  v_cards := coalesce(v_theme -> 'cards', '{}'::jsonb);
  IF jsonb_typeof(v_cards) <> 'object' THEN
    RETURN 'theme.cards must be an object';
  END IF;

  IF v_cards ? 'gap_px' THEN
    IF (v_cards ->> 'gap_px') !~ '^-?\d+$' THEN
      RETURN 'theme.cards.gap_px must be an integer';
    END IF;
    v_gap := (v_cards ->> 'gap_px')::int;
    IF v_gap NOT BETWEEN 0 AND 48 OR v_gap % 4 <> 0 THEN
      RETURN 'theme.cards.gap_px must be 0–48 in steps of 4';
    END IF;
  END IF;

  v_border := coalesce(v_cards ->> 'border', 'none');
  IF v_border NOT IN ('none', 'line') THEN
    RETURN 'theme.cards.border must be none or line';
  END IF;

  v_fill := coalesce(v_cards ->> 'fill', 'raised');
  IF v_fill NOT IN ('flat', 'raised') THEN
    RETURN 'theme.cards.fill must be flat or raised';
  END IF;

  RETURN NULL;
END;
$function$;

DROP FUNCTION IF EXISTS public.fn_shopify_brand_scheme_merge(jsonb, text);
DROP FUNCTION IF EXISTS public.fn_shopify_brand_scheme_default();
DROP FUNCTION IF EXISTS public.fn_validate_shopify_brand_scheme(jsonb);
DROP FUNCTION IF EXISTS public.fn_shopify_merchant_brand_scheme_merged(uuid);
DROP FUNCTION IF EXISTS public.fn_shopify_brand_scheme_null_if_placeholder(text);
DROP FUNCTION IF EXISTS public.fn_shopify_brand_scheme_source_to_imported_from(jsonb);

GRANT EXECUTE ON FUNCTION public.fn_brand_scheme_null_if_placeholder(text) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.fn_brand_scheme_source_to_imported_from(jsonb) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.fn_brand_scheme_default() TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.fn_brand_scheme_merge(jsonb) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.fn_validate_brand_scheme(jsonb) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.fn_brand_scheme_merged(uuid) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.admin_get_brand_scheme() TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.admin_upsert_brand_scheme(jsonb, jsonb) TO authenticated, service_role;

COMMIT;
