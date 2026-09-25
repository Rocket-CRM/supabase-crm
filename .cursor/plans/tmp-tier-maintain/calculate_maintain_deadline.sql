CREATE OR REPLACE FUNCTION public.calculate_maintain_deadline(p_merchant_id uuid, p_user_type user_type, p_achieved_date date DEFAULT CURRENT_DATE)
 RETURNS TABLE(deadline date, window_type tier_evaluation_window_type)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_cfg record;
  v_has_maintain boolean;
  v_start date;
  v_end date;
BEGIN
  SELECT * INTO v_cfg
  FROM public.tier_program_config
  WHERE merchant_id = p_merchant_id AND user_type = p_user_type;

  IF NOT FOUND THEN
    RETURN;
  END IF;

  -- maintain_enabled is derived: the ladder must carry at least one active maintain amount.
  SELECT EXISTS (
    SELECT 1
    FROM public.tier_conditions tc
    JOIN public.tier_master tm ON tm.id = tc.tier_id
    WHERE tm.merchant_id = p_merchant_id
      AND tm.user_type = p_user_type
      AND tc.condition_type = 'maintain'
      AND tc.active_status IS TRUE
  ) INTO v_has_maintain;

  IF NOT v_has_maintain THEN
    RETURN;
  END IF;

  IF v_cfg.period_type = 'calendar_year' THEN
    v_start := make_date(EXTRACT(YEAR FROM p_achieved_date)::int, v_cfg.period_start_month, 1);
    IF v_start > p_achieved_date THEN
      v_start := (v_start - INTERVAL '1 year')::date;
    END IF;
    v_end := (v_start + INTERVAL '1 year' - INTERVAL '1 day')::date;
    IF v_end <= p_achieved_date THEN
      v_end := (v_start + INTERVAL '2 years' - INTERVAL '1 day')::date;
    END IF;
    deadline := v_end;
    window_type := 'fixed_period'::public.tier_evaluation_window_type;
  ELSE
    deadline := (p_achieved_date + (v_cfg.rolling_months || ' months')::interval)::date;
    window_type := 'rolling'::public.tier_evaluation_window_type;
  END IF;

  RETURN NEXT;
END;
$function$
