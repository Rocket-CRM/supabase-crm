-- Widget settings: remove SQL-side ui_cache. loyalty-cache-api owns caching;
-- trg_cache_purge_* triggers are the only invalidation path.

DROP TRIGGER IF EXISTS merchant_widget_settings_invalidate_cache ON public.merchant_widget_settings;
DROP TRIGGER IF EXISTS merchant_display_settings_invalidate_widget_cache ON public.merchant_display_settings;
DROP TRIGGER IF EXISTS tier_master_invalidate_widget_cache ON public.tier_master;
DROP TRIGGER IF EXISTS earn_factor_invalidate_widget_cache ON public.earn_factor;

DROP FUNCTION IF EXISTS public.trigger_invalidate_widget_settings_cache_on_change();
DROP FUNCTION IF EXISTS public.trigger_invalidate_widget_cache_on_merchant_display_change();
DROP FUNCTION IF EXISTS public.trigger_invalidate_widget_cache_on_tier_change();
DROP FUNCTION IF EXISTS public.trigger_invalidate_widget_cache_on_earn_factor_change();

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

CREATE OR REPLACE FUNCTION public.bff_get_widget_settings(p_widget_type text DEFAULT 'shopify'::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
DECLARE
  v_merchant_id uuid;
  v_row public.merchant_widget_settings;
  v_template public.widget_config_template;
  v_resolved jsonb;
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
    v_resolved := v_template.config_default;
  ELSE
    v_resolved := public.fn_widget_config_with_defaults(p_widget_type, v_row.config);
  END IF;

  RETURN public.fn_response_success(
    'OK',
    'Widget settings loaded',
    jsonb_build_object(
      'widget_type', p_widget_type,
      'schema_version', v_template.schema_version,
      'active_status', coalesce(v_row.active_status, true),
      'config', v_resolved,
      'resolved', public.fn_resolve_widget_merchant_display(v_merchant_id),
      'storage', public.fn_resolve_widget_storage(p_widget_type, v_merchant_id)
    )
  );
END;
$function$;

DROP FUNCTION IF EXISTS public.fn_invalidate_widget_settings_cache(uuid, text);
DROP FUNCTION IF EXISTS public.api_get_widget_settings_cached(text, text);
