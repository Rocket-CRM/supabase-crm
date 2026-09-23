-- Widget settings: plain read for loyalty-cache-api (Render owns the cache).
-- Render calls this on a Redis miss; no SQL-side ui_cache.

CREATE OR REPLACE FUNCTION public.api_get_widget_settings(p_widget_type text, p_merchant_code text)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_merchant_id uuid;
  v_row public.merchant_widget_settings;
  v_template public.widget_config_template;
  v_resolved_config jsonb;
  v_display jsonb;
BEGIN
  IF coalesce(p_merchant_code, '') = '' OR coalesce(p_widget_type, '') = '' THEN
    RETURN jsonb_build_object('ok', false, 'error', 'merchant_code and widget_type required');
  END IF;
  SELECT id INTO v_merchant_id FROM public.merchant_master WHERE merchant_code = p_merchant_code;
  IF v_merchant_id IS NULL THEN RETURN jsonb_build_object('ok', false, 'error', 'merchant not found'); END IF;

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

  RETURN jsonb_build_object(
    'ok', true,
    'widget_type', p_widget_type,
    'schema_version', v_template.schema_version,
    'config', v_resolved_config,
    'brand_scheme', v_display -> 'scheme',
    'resolved', v_display - 'scheme'
  );
END;
$function$;

-- Tier ordering and earn-rate inputs feed the widget payload but had no purge trigger.
CREATE CONSTRAINT TRIGGER trg_cache_purge_tier_conditions
  AFTER INSERT OR DELETE OR UPDATE ON public.tier_conditions
  DEFERRABLE INITIALLY DEFERRED FOR EACH ROW
  EXECUTE FUNCTION public.trigger_cache_purge('widget');

CREATE CONSTRAINT TRIGGER trg_cache_purge_earn_conditions
  AFTER INSERT OR DELETE OR UPDATE ON public.earn_conditions
  DEFERRABLE INITIALLY DEFERRED FOR EACH ROW
  EXECUTE FUNCTION public.trigger_cache_purge('widget');

CREATE CONSTRAINT TRIGGER trg_cache_purge_earn_factor_group
  AFTER INSERT OR DELETE OR UPDATE ON public.earn_factor_group
  DEFERRABLE INITIALLY DEFERRED FOR EACH ROW
  EXECUTE FUNCTION public.trigger_cache_purge('widget');
