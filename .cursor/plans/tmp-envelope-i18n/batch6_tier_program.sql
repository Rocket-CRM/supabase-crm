CREATE OR REPLACE FUNCTION public.bff_upsert_tier_program_config(p_config jsonb, p_language text DEFAULT 'en'::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_lang text;
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
  v_lang := fn_normalize_ui_language(p_language);
  v_merchant_id := public.get_current_merchant_id();

  IF v_merchant_id IS NULL THEN
    RETURN jsonb_build_object('success', false, 'code', 'NO_MERCHANT_CONTEXT',
      'title', fn_admin_envelope_message('error_title', v_lang),
      'description', fn_admin_envelope_message('no_merchant_found_title', v_lang));
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
      'title', fn_admin_envelope_message('invalid_metric_title', v_lang),
      'description', fn_admin_envelope_message('metric_required_desc', v_lang));
  END IF;

  IF v_period_type NOT IN ('calendar_year', 'rolling') THEN
    RETURN jsonb_build_object('success', false, 'code', 'INVALID_PERIOD_TYPE',
      'title', fn_admin_envelope_message('invalid_period_type_title', v_lang),
      'description', fn_admin_envelope_message('period_type_must_be_desc', v_lang));
  END IF;

  IF v_period_type = 'calendar_year' THEN
    IF v_period_start_month IS NULL OR v_period_start_month NOT BETWEEN 1 AND 12 THEN
      RETURN jsonb_build_object('success', false, 'code', 'INVALID_PERIOD_START_MONTH',
        'title', fn_admin_envelope_message('invalid_start_month_title', v_lang),
        'description', fn_admin_envelope_message('calendar_year_month_desc', v_lang));
    END IF;
    v_rolling_months := NULL;
  ELSE
    IF v_rolling_months IS NULL OR v_rolling_months NOT BETWEEN 1 AND 36 THEN
      RETURN jsonb_build_object('success', false, 'code', 'INVALID_ROLLING_MONTHS',
        'title', fn_admin_envelope_message('invalid_rolling_months_title', v_lang),
        'description', fn_admin_envelope_message('rolling_months_range_desc', v_lang));
    END IF;
    v_period_start_month := NULL;
  END IF;

  IF v_upgrade_timing NOT IN ('immediate', 'end_of_month') THEN
    RETURN jsonb_build_object('success', false, 'code', 'INVALID_UPGRADE_TIMING',
      'title', fn_admin_envelope_message('invalid_upgrade_timing_title', v_lang),
      'description', fn_admin_envelope_message('upgrade_timing_must_be_desc', v_lang));
  END IF;

  IF v_maintain_mode NOT IN ('lifetime', 'period') THEN
    RETURN jsonb_build_object('success', false, 'code', 'INVALID_MAINTAIN_MODE',
      'title', fn_admin_envelope_message('invalid_maintain_mode_title', v_lang),
      'description', fn_admin_envelope_message('maintain_mode_must_be_desc', v_lang));
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

  RETURN jsonb_build_object('success', true, 'code', 'SAVED',
    'title', fn_admin_envelope_message('program_saved_title', v_lang),
    'description', fn_admin_envelope_message('tier_program_config_saved_desc', v_lang),
    'data', jsonb_build_object(
      'id', v_id,
      'user_type', v_user_type,
      'maintain_mode', v_maintain_mode
    ));
EXCEPTION WHEN OTHERS THEN
  RETURN jsonb_build_object('success', false, 'code', 'ERROR',
    'title', fn_admin_envelope_message('error_title', v_lang),
    'description', SQLERRM, 'detail', SQLSTATE);
END;
$function$;

DROP FUNCTION IF EXISTS public.bff_upsert_tier_program_config(jsonb);
