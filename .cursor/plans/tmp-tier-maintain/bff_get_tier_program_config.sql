CREATE OR REPLACE FUNCTION public.bff_get_tier_program_config(p_user_type user_type DEFAULT NULL::user_type)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_merchant_id uuid;
  v_data jsonb;
BEGIN
  v_merchant_id := public.get_current_merchant_id();

  IF v_merchant_id IS NULL THEN
    RETURN jsonb_build_object('success', false, 'code', 'NO_MERCHANT_CONTEXT',
      'title', 'Error', 'description', 'No merchant context found');
  END IF;

  SELECT COALESCE(jsonb_agg(jsonb_build_object(
           'id', c.id,
           'user_type', c.user_type,
           'program_start_date', c.program_start_date,
           'metric', c.metric,
           'period_type', c.period_type,
           'period_start_month', c.period_start_month,
           'rolling_months', c.rolling_months,
           'upgrade_timing', c.upgrade_timing,
           'maintain_enabled', EXISTS (
             SELECT 1 FROM public.tier_conditions tc
             JOIN public.tier_master tm ON tm.id = tc.tier_id
             WHERE tm.merchant_id = c.merchant_id
               AND tm.user_type = c.user_type
               AND tc.condition_type = 'maintain'
               AND tc.active_status IS TRUE
           )
         ) ORDER BY c.user_type), '[]'::jsonb)
  INTO v_data
  FROM public.tier_program_config c
  WHERE c.merchant_id = v_merchant_id
    AND (p_user_type IS NULL OR c.user_type = p_user_type);

  RETURN jsonb_build_object('success', true, 'code', 'OK', 'title', 'Tier Program Config',
    'description', 'Loaded tier program config', 'data', v_data);
END;
$function$
