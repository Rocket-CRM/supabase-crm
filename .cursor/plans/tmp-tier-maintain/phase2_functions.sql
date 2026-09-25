-- tier_maintain_program_level_phase2: rewire functions for program-level maintain_mode

CREATE OR REPLACE FUNCTION public.calculate_maintain_deadline(
  p_merchant_id uuid,
  p_user_type user_type,
  p_achieved_date date DEFAULT CURRENT_DATE
)
RETURNS TABLE(deadline date, window_type tier_evaluation_window_type)
LANGUAGE plpgsql
STABLE SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_cfg record;
  v_start date;
  v_end date;
BEGIN
  SELECT * INTO v_cfg
  FROM public.tier_program_config
  WHERE merchant_id = p_merchant_id AND user_type = p_user_type;

  IF NOT FOUND THEN
    RETURN;
  END IF;

  -- Program-level gate: lifetime (or missing mode) never stamps a deadline.
  IF COALESCE(v_cfg.maintain_mode, 'lifetime') <> 'period' THEN
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
$function$;

CREATE OR REPLACE FUNCTION public.evaluate_user_tier_status(
  p_user_id uuid,
  p_merchant_id uuid,
  p_evaluation_date date DEFAULT CURRENT_DATE
)
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
  v_current_upgrade_amount numeric;
  v_upgrade_tier_id uuid;
  v_downgrade_tier_id uuid;
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
    max(l.ladder_position) FILTER (WHERE l.tier_id = v_user.tier_id),
    max(l.upgrade_amount) FILTER (WHERE l.tier_id = v_user.tier_id)
  INTO v_entry_tier_id, v_qualified_tier_id, v_current_position, v_current_upgrade_amount
  FROM public.fn_tier_ladder_for_user(p_user_id, p_merchant_id) l;

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

  -- Maintain bar = current rung upgrade amount. Floor (null amount) always qualifies.
  IF v_maintain_deadline IS NOT NULL AND v_maintain_deadline <= p_evaluation_date THEN
    IF v_current_upgrade_amount IS NOT NULL AND v_metric_value < v_current_upgrade_amount THEN
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
$function$;

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

  -- Under lifetime, leave maintain progress null (member can never fail maintain).
  -- Under period, maintain bar = current rung upgrade amount (floor/null → null progress).
  IF COALESCE(v_cfg.maintain_mode, 'lifetime') = 'period'
     AND v_effective_tier_id IS NOT NULL THEN
    SELECT l.upgrade_amount INTO v_maintain_threshold
    FROM public.fn_tier_ladder_for_user(p_user_id, p_merchant_id) l
    WHERE l.tier_id = v_effective_tier_id
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
$function$;

CREATE OR REPLACE FUNCTION public.bff_get_tier_program_config(
  p_user_type user_type DEFAULT NULL::user_type
)
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
           'maintain_mode', c.maintain_mode
         ) ORDER BY c.user_type), '[]'::jsonb)
  INTO v_data
  FROM public.tier_program_config c
  WHERE c.merchant_id = v_merchant_id
    AND (p_user_type IS NULL OR c.user_type = p_user_type);

  RETURN jsonb_build_object('success', true, 'code', 'OK', 'title', 'Tier Program Config',
    'description', 'Loaded tier program config', 'data', v_data);
END;
$function$;

CREATE OR REPLACE FUNCTION public.bff_upsert_tier_program_config(p_config jsonb)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_merchant_id uuid;
  v_user_type public.user_type;
  v_metric public.metric;
  v_period_type text;
  v_period_start_month smallint;
  v_rolling_months smallint;
  v_upgrade_timing text;
  v_program_start_date date;
  v_maintain_mode text;
  v_old_mode text;
  v_id uuid;
BEGIN
  v_merchant_id := public.get_current_merchant_id();

  IF v_merchant_id IS NULL THEN
    RETURN jsonb_build_object('success', false, 'code', 'NO_MERCHANT_CONTEXT',
      'title', 'Error', 'description', 'No merchant context found');
  END IF;

  v_user_type := COALESCE(NULLIF(p_config->>'user_type', ''), 'buyer')::public.user_type;
  v_metric := NULLIF(p_config->>'metric', '')::public.metric;
  v_period_type := NULLIF(p_config->>'period_type', '');
  v_period_start_month := NULLIF(p_config->>'period_start_month', '')::smallint;
  v_rolling_months := NULLIF(p_config->>'rolling_months', '')::smallint;
  v_upgrade_timing := COALESCE(NULLIF(p_config->>'upgrade_timing', ''), 'immediate');
  v_program_start_date := NULLIF(p_config->>'program_start_date', '')::date;
  v_maintain_mode := COALESCE(NULLIF(p_config->>'maintain_mode', ''), 'lifetime');

  IF v_metric IS NULL THEN
    RETURN jsonb_build_object('success', false, 'code', 'INVALID_METRIC',
      'title', 'Invalid Metric', 'description', 'metric is required');
  END IF;

  IF v_period_type NOT IN ('calendar_year', 'rolling') THEN
    RETURN jsonb_build_object('success', false, 'code', 'INVALID_PERIOD_TYPE',
      'title', 'Invalid Period Type', 'description', 'period_type must be calendar_year or rolling');
  END IF;

  IF v_period_type = 'calendar_year' THEN
    IF v_period_start_month IS NULL OR v_period_start_month NOT BETWEEN 1 AND 12 THEN
      RETURN jsonb_build_object('success', false, 'code', 'INVALID_PERIOD_START_MONTH',
        'title', 'Invalid Start Month', 'description', 'calendar_year requires period_start_month between 1 and 12');
    END IF;
    v_rolling_months := NULL;
  ELSE
    IF v_rolling_months IS NULL OR v_rolling_months NOT BETWEEN 1 AND 36 THEN
      RETURN jsonb_build_object('success', false, 'code', 'INVALID_ROLLING_MONTHS',
        'title', 'Invalid Rolling Months', 'description', 'rolling requires rolling_months between 1 and 36');
    END IF;
    v_period_start_month := NULL;
  END IF;

  IF v_upgrade_timing NOT IN ('immediate', 'end_of_month') THEN
    RETURN jsonb_build_object('success', false, 'code', 'INVALID_UPGRADE_TIMING',
      'title', 'Invalid Upgrade Timing', 'description', 'upgrade_timing must be immediate or end_of_month');
  END IF;

  IF v_maintain_mode NOT IN ('lifetime', 'period') THEN
    RETURN jsonb_build_object('success', false, 'code', 'INVALID_MAINTAIN_MODE',
      'title', 'Invalid Maintain Mode',
      'description', 'maintain_mode must be lifetime or period');
  END IF;

  SELECT c.maintain_mode INTO v_old_mode
  FROM public.tier_program_config c
  WHERE c.merchant_id = v_merchant_id AND c.user_type = v_user_type;

  INSERT INTO public.tier_program_config (
    merchant_id, user_type, program_start_date, metric,
    period_type, period_start_month, rolling_months, upgrade_timing, maintain_mode
  ) VALUES (
    v_merchant_id, v_user_type, v_program_start_date, v_metric,
    v_period_type, v_period_start_month, v_rolling_months, v_upgrade_timing, v_maintain_mode
  )
  ON CONFLICT (merchant_id, user_type) DO UPDATE SET
    program_start_date = EXCLUDED.program_start_date,
    metric = EXCLUDED.metric,
    period_type = EXCLUDED.period_type,
    period_start_month = EXCLUDED.period_start_month,
    rolling_months = EXCLUDED.rolling_months,
    upgrade_timing = EXCLUDED.upgrade_timing,
    maintain_mode = EXCLUDED.maintain_mode,
    updated_at = now()
  RETURNING id INTO v_id;

  -- Transition side-effects for maintain_mode flips.
  IF COALESCE(v_old_mode, 'lifetime') = 'period' AND v_maintain_mode = 'lifetime' THEN
    UPDATE public.tier_evaluation_tracking tet
    SET maintain_deadline = NULL,
        maintain_window_type = NULL,
        updated_at = now()
    FROM public.user_accounts ua
    WHERE tet.user_id = ua.id
      AND tet.merchant_id = v_merchant_id
      AND ua.merchant_id = v_merchant_id
      AND ua.user_type = v_user_type;

    UPDATE public.tier_progress tp
    SET maintain_deadline = NULL,
        maintain_metric_needed = NULL,
        maintain_progress = NULL,
        updated_at = now()
    FROM public.user_accounts ua
    WHERE tp.user_id = ua.id
      AND tp.merchant_id = v_merchant_id
      AND ua.merchant_id = v_merchant_id
      AND ua.user_type = v_user_type;

  ELSIF COALESCE(v_old_mode, 'lifetime') = 'lifetime' AND v_maintain_mode = 'period' THEN
    INSERT INTO public.tier_evaluation_tracking (
      user_id, merchant_id, tier_achieved_at, maintain_deadline,
      maintain_window_type, updated_at
    )
    SELECT
      ua.id,
      v_merchant_id,
      COALESCE(tet.tier_achieved_at, now()),
      cmd.deadline,
      cmd.window_type,
      now()
    FROM public.user_accounts ua
    LEFT JOIN public.tier_evaluation_tracking tet
      ON tet.user_id = ua.id AND tet.merchant_id = v_merchant_id
    CROSS JOIN LATERAL public.calculate_maintain_deadline(
      v_merchant_id,
      v_user_type,
      COALESCE(tet.tier_achieved_at::date, CURRENT_DATE)
    ) cmd
    WHERE ua.merchant_id = v_merchant_id
      AND ua.user_type = v_user_type
      AND ua.tier_id IS NOT NULL
    ON CONFLICT (user_id, merchant_id) DO UPDATE SET
      maintain_deadline = EXCLUDED.maintain_deadline,
      maintain_window_type = EXCLUDED.maintain_window_type,
      updated_at = now();
  END IF;

  RETURN jsonb_build_object('success', true, 'code', 'SAVED', 'title', 'Program Saved',
    'description', 'Tier program config saved',
    'data', jsonb_build_object(
      'id', v_id,
      'user_type', v_user_type,
      'maintain_mode', v_maintain_mode
    ));
EXCEPTION WHEN OTHERS THEN
  RETURN jsonb_build_object('success', false, 'code', 'ERROR', 'title', 'Error',
    'description', SQLERRM, 'detail', SQLSTATE);
END;
$function$;

CREATE OR REPLACE FUNCTION public.get_tier_conditions_by_type(
  p_mode text DEFAULT 'edit'::text,
  p_tier_id uuid DEFAULT NULL::uuid
)
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
      'upgrade', '[]'::jsonb
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
           'upgrade_timing', c.upgrade_timing,
           'maintain_mode', c.maintain_mode
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
    'upgrade', v_upgrade_conditions
  );
END;
$function$;
