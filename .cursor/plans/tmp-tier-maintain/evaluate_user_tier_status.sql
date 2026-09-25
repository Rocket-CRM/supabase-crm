CREATE OR REPLACE FUNCTION public.evaluate_user_tier_status(p_user_id uuid, p_merchant_id uuid, p_evaluation_date date DEFAULT CURRENT_DATE)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_user record;
  v_cfg record;
  v_window_start date;
  v_window_end date;
  v_metric_value numeric;
  v_entry_tier_id uuid;
  v_qualified_tier_id uuid;
  v_current_position integer;
  v_upgrade_tier_id uuid;
  v_downgrade_tier_id uuid;
  v_maintain_amount numeric;
  v_maintain_qualified boolean := true;
  v_maintain_deadline date;
  v_recommended_tier_id uuid;
  v_action text;
  v_effective_at date;
BEGIN
  SELECT ua.tier_id, ua.user_type, ua.persona_id, tm.tier_name
  INTO v_user
  FROM public.user_accounts ua
  LEFT JOIN public.tier_master tm ON tm.id = ua.tier_id
  WHERE ua.id = p_user_id AND ua.merchant_id = p_merchant_id;

  IF NOT FOUND THEN
    RETURN jsonb_build_object(
      'user_id', p_user_id, 'merchant_id', p_merchant_id,
      'recommended_action', 'error',
      'error', 'user not found for merchant',
      'evaluation_date', p_evaluation_date
    );
  END IF;

  SELECT * INTO v_cfg
  FROM public.tier_program_config
  WHERE merchant_id = p_merchant_id AND user_type = v_user.user_type;

  IF NOT FOUND THEN
    RETURN jsonb_build_object(
      'user_id', p_user_id, 'merchant_id', p_merchant_id,
      'current_tier_id', v_user.tier_id,
      'current_tier_name', v_user.tier_name,
      'recommended_action', 'error',
      'error', 'no tier_program_config for this merchant and user_type',
      'evaluation_date', p_evaluation_date
    );
  END IF;

  SELECT w.window_start, w.window_end
  INTO v_window_start, v_window_end
  FROM public.fn_tier_window(p_merchant_id, v_user.user_type, p_evaluation_date) w;

  v_metric_value := public.calculate_tier_metric_value(
    p_user_id, p_merchant_id, v_cfg.metric, v_user.user_type, v_window_start, v_window_end
  );

  SELECT
    (array_agg(l.tier_id ORDER BY l.ladder_position) FILTER (WHERE l.is_entry))[1],
    (array_agg(l.tier_id ORDER BY l.ladder_position DESC)
      FILTER (WHERE l.upgrade_amount IS NULL OR l.upgrade_amount <= v_metric_value))[1],
    max(l.ladder_position) FILTER (WHERE l.tier_id = v_user.tier_id)
  INTO v_entry_tier_id, v_qualified_tier_id, v_current_position
  FROM public.fn_tier_ladder_for_user(p_user_id, p_merchant_id) l;

  -- Entry assignment must still be earned. When every rung on the member's effective
  -- ladder carries a threshold they have not met, they get no tier rather than a free one.
  IF v_user.tier_id IS NULL OR v_current_position IS NULL THEN
    RETURN jsonb_build_object(
      'user_id', p_user_id, 'merchant_id', p_merchant_id,
      'current_tier_id', v_user.tier_id,
      'current_tier_name', v_user.tier_name,
      'metric', v_cfg.metric,
      'metric_value', v_metric_value,
      'window_start', v_window_start,
      'window_end', v_window_end,
      'maintain_qualified', true,
      'recommended_action', 'assign_entry',
      'recommended_tier_id', v_qualified_tier_id,
      'evaluation_date', p_evaluation_date
    );
  END IF;

  SELECT tet.maintain_deadline INTO v_maintain_deadline
  FROM public.tier_evaluation_tracking tet
  WHERE tet.user_id = p_user_id AND tet.merchant_id = p_merchant_id;

  IF v_maintain_deadline IS NOT NULL AND v_maintain_deadline <= p_evaluation_date THEN
    SELECT tc.amount INTO v_maintain_amount
    FROM public.tier_conditions tc
    WHERE tc.tier_id = v_user.tier_id
      AND tc.condition_type = 'maintain'
      AND tc.active_status IS TRUE
    ORDER BY tc.amount DESC NULLS LAST
    LIMIT 1;

    IF v_maintain_amount IS NOT NULL AND v_metric_value < v_maintain_amount THEN
      v_maintain_qualified := false;
    END IF;
  END IF;

  SELECT
    (array_agg(l.tier_id ORDER BY l.ladder_position DESC)
      FILTER (WHERE l.ladder_position > v_current_position
                AND (l.upgrade_amount IS NULL OR l.upgrade_amount <= v_metric_value)))[1],
    (array_agg(l.tier_id ORDER BY l.ladder_position DESC)
      FILTER (WHERE l.ladder_position < v_current_position
                AND (l.upgrade_amount IS NULL OR l.upgrade_amount <= v_metric_value)))[1]
  INTO v_upgrade_tier_id, v_downgrade_tier_id
  FROM public.fn_tier_ladder_for_user(p_user_id, p_merchant_id) l;

  IF v_upgrade_tier_id IS NOT NULL THEN
    v_action := 'upgrade';
    v_recommended_tier_id := v_upgrade_tier_id;

    IF v_cfg.upgrade_timing = 'end_of_month' THEN
      v_effective_at := (DATE_TRUNC('month', p_evaluation_date) + INTERVAL '1 month - 1 day')::date;
    ELSE
      v_effective_at := p_evaluation_date;
    END IF;
  ELSIF NOT v_maintain_qualified THEN
    -- D1: land on the highest lower rung the member still qualifies for, else the entry rung.
    v_action := 'downgrade';
    v_recommended_tier_id := COALESCE(v_downgrade_tier_id, v_entry_tier_id);
  ELSE
    v_action := 'maintain';
    v_recommended_tier_id := v_user.tier_id;
  END IF;

  RETURN jsonb_build_object(
    'user_id', p_user_id,
    'merchant_id', p_merchant_id,
    'current_tier_id', v_user.tier_id,
    'current_tier_name', v_user.tier_name,
    'metric', v_cfg.metric,
    'metric_value', v_metric_value,
    'window_start', v_window_start,
    'window_end', v_window_end,
    'maintain_qualified', v_maintain_qualified,
    'recommended_action', v_action,
    'recommended_tier_id', v_recommended_tier_id,
    'upgrade_timing', v_cfg.upgrade_timing,
    'effective_at', v_effective_at,
    'evaluation_date', p_evaluation_date
  );
END;
$function$
