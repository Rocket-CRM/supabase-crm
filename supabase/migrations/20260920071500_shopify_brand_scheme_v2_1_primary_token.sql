-- Shopify brand scheme v2.1 — rename tokens.brand → tokens.primary.
--
-- The scheme's token names follow Shopify Horizon's colour-scheme roles so theme import is a
-- field copy (primary ← primary, background ← background, text ← foreground). `brand` was our
-- own name for Horizon's `primary` role; this migration retires it.
--
-- * default / merge / validate emit and require `tokens.primary`
-- * merge still reads legacy `tokens.brand` (and `primary_color`) so unsaved 2.0 payloads and
--   older admin builds keep working; output is always 2.1.0 with `primary`
-- * admin_upsert syncs merchant_display_settings.primary_color from tokens.primary
-- * stored rows are rewritten through merge; landing + widget caches invalidated
--
-- Storefront bundle (rewarding-shopify widget-builder) reads `tokens.primary ?? tokens.brand`.

-- ---------------------------------------------------------------------------
-- Default
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.fn_shopify_brand_scheme_default()
RETURNS jsonb
LANGUAGE sql
IMMUTABLE
AS $function$
  SELECT jsonb_build_object(
    '_schema_version', '2.1.0',
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
      'text', '#0D0D0D'
    ),
    'buttons', jsonb_build_object(
      'primary', jsonb_build_object('bg', NULL, 'text', NULL),
      'secondary', jsonb_build_object('text', NULL),
      'radius_px', 8
    )
  );
$function$;

-- ---------------------------------------------------------------------------
-- Merge (accepts 2.1 `primary`, legacy 2.0 `brand`, then merchant primary_color)
-- ---------------------------------------------------------------------------
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
  v_primary text;
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

  v_btn := coalesce(v_in -> 'buttons', '{}'::jsonb);
  v_radius := coalesce((v_btn ->> 'radius_px')::int, (v_default -> 'buttons' ->> 'radius_px')::int, 8);

  RETURN jsonb_build_object(
    '_schema_version', '2.1.0',
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

-- ---------------------------------------------------------------------------
-- Validate
-- ---------------------------------------------------------------------------
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

  v_merged := public.fn_shopify_brand_scheme_merge(
    p_scheme,
    coalesce(p_scheme #>> '{tokens,primary}', p_scheme #>> '{tokens,brand}')
  );

  IF coalesce(p_scheme ->> '_schema_version', '2.1.0') NOT IN ('2.1.0', '2.0.0', '1.0.0') THEN
    v_errors := v_errors || jsonb_build_array(jsonb_build_object(
      'path', '_schema_version',
      'message', '_schema_version must be 2.1.0'
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
  FOREACH v_field IN ARRAY ARRAY['primary', 'background', 'dark_surface', 'text'] LOOP
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
-- Admin upsert — primary_color synced from tokens.primary
-- ---------------------------------------------------------------------------
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
  v_primary text;
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

  v_merged := public.fn_shopify_brand_scheme_merge(
    p_scheme,
    coalesce(p_scheme #>> '{tokens,primary}', p_scheme #>> '{tokens,brand}')
  );
  v_primary := v_merged #>> '{tokens,primary}';

  UPDATE public.merchant_display_settings
  SET shopify_brand_scheme = v_merged,
      primary_color = v_primary,
      updated_at = now()
  WHERE merchant_id = v_merchant_id;

  IF NOT FOUND THEN
    INSERT INTO public.merchant_display_settings (merchant_id, shopify_brand_scheme, primary_color)
    VALUES (v_merchant_id, v_merged, v_primary);
  END IF;

  PERFORM public.fn_invalidate_shopify_landing_page_cache(v_merchant_id);

  RETURN public.admin_get_shopify_brand_scheme();
END;
$function$;

-- ---------------------------------------------------------------------------
-- Data: rewrite stored schemes to 2.1 (`brand` → `primary`), drop caches
-- ---------------------------------------------------------------------------
UPDATE public.merchant_display_settings d
SET shopify_brand_scheme = public.fn_shopify_brand_scheme_merge(d.shopify_brand_scheme, d.primary_color),
    updated_at = now()
WHERE d.shopify_brand_scheme IS NOT NULL;

SELECT public.fn_invalidate_shopify_landing_page_cache(merchant_id)
FROM public.merchant_shopify_landing_page_settings;

SELECT public.fn_invalidate_widget_settings_cache(merchant_id, 'shopify')
FROM public.merchant_display_settings
WHERE shopify_brand_scheme IS NOT NULL;

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
    IF (v_rec.shopify_brand_scheme -> 'tokens') ? 'brand'
       OR NOT ((v_rec.shopify_brand_scheme -> 'tokens') ? 'primary') THEN
      RAISE EXCEPTION 'shopify_brand_scheme v2.1 rewrite incomplete for merchant %', v_rec.merchant_id;
    END IF;
    v_errors := public.fn_validate_shopify_brand_scheme(v_rec.shopify_brand_scheme);
    IF jsonb_array_length(v_errors) > 0 THEN
      RAISE EXCEPTION 'shopify_brand_scheme validation failed for merchant %: %',
        v_rec.merchant_id, v_errors::text;
    END IF;
  END LOOP;
END;
$migrate$;
