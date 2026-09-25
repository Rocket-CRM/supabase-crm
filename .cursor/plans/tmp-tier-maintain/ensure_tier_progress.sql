CREATE OR REPLACE FUNCTION public.ensure_tier_progress(p_user_id uuid, p_merchant_id uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_current_tier_id uuid;
  v_user_type public.user_type;
  v_cfg record;
  v_eval jsonb;
  v_action text;
  v_new_tier_id uuid;
  v_effective_tier_id uuid;
  v_effective_position integer;
  v_next_tier_id uuid;
  v_next_amount numeric;
  v_window_start date;
  v_window_end date;
  v_metric_value numeric;
  v_upgrade_metric public.metric;
  v_upgrade_threshold numeric;
  v_upgrade_progress numeric;
  v_maintain_metric public.metric;
  v_maintain_threshold numeric;
  v_maintain_progress numeric;
  v_maintain_deadline date;
  v_maintain_window_type public.tier_evaluation_window_type;
BEGIN
  SELECT ua.tier_id, ua.user_type
  INTO v_current_tier_id, v_user_type
  FROM public.user_accounts ua
  WHERE ua.id = p_user_id AND ua.merchant_id = p_merchant_id;

  SELECT * INTO v_cfg
  FROM public.tier_program_config
  WHERE merchant_id = p_merchant_id AND user_type = v_user_type;

  IF NOT FOUND THEN
    RETURN;
  END IF;

  v_eval := public.evaluate_user_tier_status(p_user_id, p_merchant_id, CURRENT_DATE);
  v_action := v_eval->>'recommended_action';

  IF v_action = 'error' THEN
    RETURN;
  END IF;

  v_new_tier_id := NULLIF(v_eval->>'recommended_tier_id', '')::uuid;
  v_effective_tier_id := COALESCE(v_new_tier_id, v_current_tier_id);

  SELECT w.window_start, w.window_end
  INTO v_window_start, v_window_end
  FROM public.fn_tier_window(p_merchant_id, v_user_type, CURRENT_DATE) w;

  v_metric_value := public.calculate_tier_metric_value(
    p_user_id, p_merchant_id, v_cfg.metric, v_user_type, v_window_start, v_window_end
  );

  SELECT max(l.ladder_position) FILTER (WHERE l.tier_id = v_effective_tier_id)
  INTO v_effective_position
  FROM public.fn_tier_ladder_for_user(p_user_id, p_merchant_id) l;

  SELECT l.tier_id, l.upgrade_amount
  INTO v_next_tier_id, v_next_amount
  FROM public.fn_tier_ladder_for_user(p_user_id, p_merchant_id) l
  WHERE l.ladder_position > COALESCE(v_effective_position, 0)
  ORDER BY l.ladder_position ASC
  LIMIT 1;

  IF v_next_tier_id IS NOT NULL THEN
    v_upgrade_metric := v_cfg.metric;
    v_upgrade_threshold := v_next_amount;
    v_upgrade_progress := LEAST(
      COALESCE(v_metric_value * 100.0 / NULLIF(v_next_amount, 0), 0), 100
    );
  END IF;

  IF v_effective_tier_id IS NOT NULL THEN
    SELECT tc.amount INTO v_maintain_threshold
    FROM public.tier_conditions tc
    WHERE tc.tier_id = v_effective_tier_id
      AND tc.condition_type = 'maintain'
      AND tc.active_status IS TRUE
    ORDER BY tc.amount DESC NULLS LAST
    LIMIT 1;

    IF v_maintain_threshold IS NOT NULL THEN
      v_maintain_metric := v_cfg.metric;
      v_maintain_progress := v_metric_value * 100.0 / NULLIF(v_maintain_threshold, 0);
    END IF;
  END IF;

  INSERT INTO public.tier_progress (
    id, user_id, merchant_id, current_tier_id, next_tier_id,
    upgrade_metric_needed, upgrade_progress_percent, upgrade_deadline,
    maintain_metric_needed, maintain_progress,
    created_at, updated_at
  ) VALUES (
    gen_random_uuid(), p_user_id, p_merchant_id,
    v_effective_tier_id, v_next_tier_id,
    v_upgrade_metric, v_upgrade_progress, v_window_end,
    v_maintain_metric, v_maintain_progress,
    NOW(), NOW()
  )
  ON CONFLICT (user_id, merchant_id) DO UPDATE SET
    current_tier_id = EXCLUDED.current_tier_id,
    next_tier_id = EXCLUDED.next_tier_id,
    upgrade_metric_needed = EXCLUDED.upgrade_metric_needed,
    upgrade_progress_percent = EXCLUDED.upgrade_progress_percent,
    upgrade_deadline = EXCLUDED.upgrade_deadline,
    maintain_metric_needed = EXCLUDED.maintain_metric_needed,
    maintain_progress = EXCLUDED.maintain_progress,
    updated_at = NOW();

  IF v_action IN ('upgrade', 'downgrade')
     AND v_current_tier_id IS DISTINCT FROM v_new_tier_id
     AND v_new_tier_id IS NOT NULL THEN

    PERFORM public.chokepoint_post_user_event(
      p_event_type := 'update',
      p_merchant_id := p_merchant_id,
      p_user_id := p_user_id,
      p_changes := jsonb_build_object('tier_id', v_new_tier_id),
      p_metadata := jsonb_build_object(
        'tier_change_type', v_action,
        'tier_change_reason', format('%s based on evaluation', v_action),
        'tier_evaluation', v_eval
      )
    );

    SELECT cmd.deadline, cmd.window_type
    INTO v_maintain_deadline, v_maintain_window_type
    FROM public.calculate_maintain_deadline(p_merchant_id, v_user_type, CURRENT_DATE) cmd;

    INSERT INTO public.tier_evaluation_tracking (
      user_id, merchant_id, tier_achieved_at, maintain_deadline,
      maintain_window_type, updated_at
    ) VALUES (
      p_user_id, p_merchant_id, NOW(), v_maintain_deadline,
      v_maintain_window_type, NOW()
    )
    ON CONFLICT (user_id, merchant_id) DO UPDATE SET
      tier_achieved_at = NOW(),
      maintain_deadline = EXCLUDED.maintain_deadline,
      maintain_window_type = EXCLUDED.maintain_window_type,
      updated_at = NOW();

    UPDATE public.tier_progress
    SET maintain_deadline = v_maintain_deadline
    WHERE user_id = p_user_id AND merchant_id = p_merchant_id;
  END IF;
END;
$function$
