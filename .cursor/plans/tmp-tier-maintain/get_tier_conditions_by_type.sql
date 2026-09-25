CREATE OR REPLACE FUNCTION public.get_tier_conditions_by_type(p_mode text DEFAULT 'edit'::text, p_tier_id uuid DEFAULT NULL::uuid)
 RETURNS json
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_merchant_id uuid;
  v_tier_record record;
  v_program jsonb;
  v_upgrade_conditions jsonb;
  v_maintain_conditions jsonb;
BEGIN
  v_merchant_id := public.get_current_merchant_id();

  IF v_merchant_id IS NULL THEN
    RETURN json_build_object('success', false, 'error', 'No merchant context found');
  END IF;

  IF p_mode = 'new' THEN
    RETURN json_build_object(
      'mode', 'new', 'tier_id', NULL, 'tier_name', NULL, 'user_type', NULL,
      'persona_id', NULL, 'persona_ids', '[]'::jsonb, 'personas', '[]'::jsonb,
      'created_at', NULL, 'program_config', NULL,
      'upgrade', '[]'::jsonb, 'maintain', '[]'::jsonb
    );
  END IF;

  IF p_tier_id IS NULL THEN
    RETURN json_build_object('success', false, 'error', 'tier_id is required for edit mode');
  END IF;

  SELECT id, tier_name, user_type, persona_id, created_at
  INTO v_tier_record
  FROM public.tier_master
  WHERE id = p_tier_id AND merchant_id = v_merchant_id;

  IF v_tier_record.id IS NULL THEN
    RETURN json_build_object('success', false, 'error', 'Tier not found or access denied');
  END IF;

  SELECT jsonb_build_object(
           'metric', c.metric,
           'period_type', c.period_type,
           'period_start_month', c.period_start_month,
           'rolling_months', c.rolling_months,
           'program_start_date', c.program_start_date,
           'upgrade_timing', c.upgrade_timing
         )
  INTO v_program
  FROM public.tier_program_config c
  WHERE c.merchant_id = v_merchant_id AND c.user_type = v_tier_record.user_type;

  SELECT COALESCE(jsonb_agg(jsonb_build_object(
           'id', tc.id,
           'condition_type', tc.condition_type,
           'amount', tc.amount,
           'active_status', tc.active_status
         ) ORDER BY tc.amount), '[]'::jsonb)
  INTO v_upgrade_conditions
  FROM public.tier_conditions tc
  WHERE tc.tier_id = p_tier_id AND tc.merchant_id = v_merchant_id
    AND tc.condition_type = 'upgrade';

  SELECT COALESCE(jsonb_agg(jsonb_build_object(
           'id', tc.id,
           'condition_type', tc.condition_type,
           'amount', tc.amount,
           'active_status', tc.active_status
         ) ORDER BY tc.amount), '[]'::jsonb)
  INTO v_maintain_conditions
  FROM public.tier_conditions tc
  WHERE tc.tier_id = p_tier_id AND tc.merchant_id = v_merchant_id
    AND tc.condition_type = 'maintain';

  RETURN json_build_object(
    'mode', 'edit',
    'tier_id', v_tier_record.id,
    'tier_name', v_tier_record.tier_name,
    'user_type', v_tier_record.user_type,
    'persona_id', v_tier_record.persona_id,
    'persona_ids', public.fn_tier_persona_ids(v_tier_record.id),
    'personas', public.fn_tier_personas_json(v_tier_record.id),
    'created_at', v_tier_record.created_at,
    'program_config', v_program,
    'upgrade', v_upgrade_conditions,
    'maintain', v_maintain_conditions
  );
END;
$function$
