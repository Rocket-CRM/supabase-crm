-- Landing section surface.swatch: retire `brand` enum → `primary` (matches tokens.primary).
-- Also invalidate widget settings cache on brand-scheme upsert (landing cache only was pre-existing).

-- ---------------------------------------------------------------------------
-- Normalize legacy swatch on read
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.fn_shopify_landing_upgrade_section_config(p_block_type text, p_config jsonb)
RETURNS jsonb
LANGUAGE plpgsql
IMMUTABLE
AS $function$
DECLARE
  v_out jsonb;
  v_surface jsonb;
  v_swatch text;
BEGIN
  IF p_config IS NULL OR jsonb_typeof(p_config) <> 'object' THEN
    RETURN public.fn_shopify_landing_default_section_config(p_block_type);
  END IF;

  IF p_config ? 'surface' AND NOT (p_config ? 'section_style') THEN
    v_out := p_config;
  ELSE
    v_surface := coalesce(
      p_config -> 'surface',
      public.fn_shopify_landing_section_style_to_surface(p_config ->> 'section_style')
    );
    v_out := (p_config - 'section_style')
      || jsonb_build_object('surface', v_surface, 'text_hex', coalesce(p_config -> 'text_hex', 'null'::jsonb));
    IF NOT (v_out ? 'text_hex') OR v_out -> 'text_hex' = 'null'::jsonb THEN
      v_out := jsonb_set(v_out, '{text_hex}', 'null'::jsonb, true);
    END IF;
  END IF;

  v_swatch := v_out #>> '{surface,swatch}';
  IF v_swatch = 'brand' THEN
    v_out := jsonb_set(v_out, '{surface,swatch}', to_jsonb('primary'::text), true);
  ELSIF v_swatch = 'extra' THEN
    v_out := jsonb_set(v_out, '{surface,swatch}', to_jsonb('primary'::text), true);
  END IF;

  IF v_out ? 'guest' THEN
    v_out := jsonb_set(
      v_out,
      '{guest}',
      coalesce(v_out -> 'guest', '{}'::jsonb)
        || jsonb_build_object(
          'cta',
          public.fn_shopify_landing_upgrade_section_cta(v_out #> '{guest,cta}')
        ),
      true
    );
  END IF;
  IF v_out ? 'member' THEN
    v_out := jsonb_set(
      v_out,
      '{member}',
      coalesce(v_out -> 'member', '{}'::jsonb)
        || jsonb_build_object(
          'cta',
          public.fn_shopify_landing_upgrade_section_cta(v_out #> '{member,cta}')
        ),
      true
    );
  END IF;

  RETURN v_out;
END;
$function$;

-- ---------------------------------------------------------------------------
-- Persisted landing sections: brand|extra → primary
-- ---------------------------------------------------------------------------
UPDATE public.display_settings ds
SET config = jsonb_set(
      config,
      '{surface,swatch}',
      to_jsonb('primary'::text),
      true
    ),
    updated_at = now()
WHERE ds.page = 'shopify_loyalty_landing'::public.display_page_type
  AND config #>> '{surface,swatch}' IN ('brand', 'extra');

SELECT public.fn_invalidate_shopify_landing_page_cache(merchant_id)
FROM public.merchant_shopify_landing_page_settings
WHERE merchant_id IN (
  SELECT DISTINCT merchant_id
  FROM public.display_settings
  WHERE page = 'shopify_loyalty_landing'::public.display_page_type
);

-- ---------------------------------------------------------------------------
-- admin_upsert_shopify_brand_scheme — also bust widget cache
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
  PERFORM public.fn_invalidate_widget_settings_cache(v_merchant_id, 'shopify');

  RETURN public.admin_get_shopify_brand_scheme();
END;
$function$;
