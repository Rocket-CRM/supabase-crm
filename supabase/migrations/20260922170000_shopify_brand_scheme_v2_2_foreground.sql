-- Brand scheme 2.2.0: store Horizon foreground_heading and rename tokens.text → tokens.foreground.
-- Existing rows copy the old text colour onto both keys so the landing does not change until re-import.
-- tokens.text is still written as a copy of foreground so an admin build that only reads text keeps the colour.

CREATE OR REPLACE FUNCTION public.fn_shopify_brand_scheme_default()
RETURNS jsonb
LANGUAGE sql
IMMUTABLE
AS $$
  SELECT jsonb_build_object(
    '_schema_version', '2.2.0',
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
      'text', '#0D0D0D'
    ),
    'buttons', jsonb_build_object(
      'primary', jsonb_build_object('bg', NULL, 'text', NULL),
      'secondary', jsonb_build_object('text', NULL),
      'radius_px', 8
    )
  );
$$;

CREATE OR REPLACE FUNCTION public.fn_shopify_brand_scheme_merge(p_scheme jsonb, p_primary_color text)
RETURNS jsonb
LANGUAGE plpgsql
IMMUTABLE
AS $$
DECLARE
  v_default jsonb := public.fn_shopify_brand_scheme_default();
  v_in jsonb := coalesce(p_scheme, '{}'::jsonb);
  v_src jsonb;
  v_tok jsonb;
  v_btn jsonb;
  v_primary text;
  v_foreground text;
  v_heading text;
  v_radius int;
BEGIN
  v_src := (v_default -> 'source') || coalesce(v_in -> 'source', '{}'::jsonb);
  v_tok := coalesce(v_in -> 'tokens', '{}'::jsonb);

  v_primary := coalesce(
    CASE WHEN public.fn_shopify_landing_is_hex(v_tok ->> 'primary') THEN upper(btrim(v_tok ->> 'primary')) END,
    CASE WHEN public.fn_shopify_landing_is_hex(v_tok ->> 'brand') THEN upper(btrim(v_tok ->> 'brand')) END,
    CASE WHEN public.fn_shopify_landing_is_hex(p_primary_color) THEN upper(btrim(p_primary_color)) END,
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

  v_btn := coalesce(v_in -> 'buttons', '{}'::jsonb);
  v_radius := coalesce((v_btn ->> 'radius_px')::int, (v_default -> 'buttons' ->> 'radius_px')::int, 8);

  RETURN jsonb_build_object(
    '_schema_version', '2.2.0',
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
      'text', v_foreground
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
$$;

CREATE OR REPLACE FUNCTION public.fn_validate_shopify_brand_scheme(p_scheme jsonb)
RETURNS jsonb
LANGUAGE plpgsql
IMMUTABLE
AS $$
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

  v_merged := public.fn_shopify_brand_scheme_merge(
    p_scheme,
    coalesce(p_scheme #>> '{tokens,primary}', p_scheme #>> '{tokens,brand}')
  );

  IF coalesce(p_scheme ->> '_schema_version', '2.2.0') NOT IN ('2.2.0', '2.1.0', '2.0.0', '1.0.0') THEN
    v_errors := v_errors || jsonb_build_array(jsonb_build_object(
      'path', '_schema_version',
      'message', '_schema_version must be 2.2.0'
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
$$;

UPDATE public.merchant_display_settings
SET shopify_brand_scheme = public.fn_shopify_brand_scheme_merge(shopify_brand_scheme, primary_color)
WHERE shopify_brand_scheme IS NOT NULL;
