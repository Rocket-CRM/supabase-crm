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

  INSERT INTO public.tier_program_config (
    merchant_id, user_type, program_start_date, metric,
    period_type, period_start_month, rolling_months, upgrade_timing
  ) VALUES (
    v_merchant_id, v_user_type, v_program_start_date, v_metric,
    v_period_type, v_period_start_month, v_rolling_months, v_upgrade_timing
  )
  ON CONFLICT (merchant_id, user_type) DO UPDATE SET
    program_start_date = EXCLUDED.program_start_date,
    metric = EXCLUDED.metric,
    period_type = EXCLUDED.period_type,
    period_start_month = EXCLUDED.period_start_month,
    rolling_months = EXCLUDED.rolling_months,
    upgrade_timing = EXCLUDED.upgrade_timing,
    updated_at = now()
  RETURNING id INTO v_id;

  RETURN jsonb_build_object('success', true, 'code', 'SAVED', 'title', 'Program Saved',
    'description', 'Tier program config saved',
    'data', jsonb_build_object('id', v_id, 'user_type', v_user_type));
EXCEPTION WHEN OTHERS THEN
  RETURN jsonb_build_object('success', false, 'code', 'ERROR', 'title', 'Error',
    'description', SQLERRM, 'detail', SQLSTATE);
END;
$function$
