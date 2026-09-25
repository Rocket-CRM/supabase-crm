-- Seed driver: day-by-day with pause between days
CREATE OR REPLACE FUNCTION public.custom_internal_demo_seed_range(
  p_from date DEFAULT NULL,
  p_to date DEFAULT NULL,
  p_pause_seconds numeric DEFAULT 10,
  p_mode text DEFAULT 'backfill'
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $fn$
DECLARE
  v_settings jsonb := custom_internal_demo_settings();
  v_from date;
  v_to date;
  v_day date;
  v_result jsonb;
  v_results jsonb := '[]'::jsonb;
  v_ok int := 0;
  v_fail int := 0;
  v_skip int := 0;
  v_seed_days int;
BEGIN
  IF v_settings IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'settings missing');
  END IF;

  v_seed_days := coalesce((v_settings->>'seed_days')::int, 180);
  v_to := coalesce(p_to, current_date);
  v_from := coalesce(p_from, v_to - v_seed_days);

  -- Persist anchor used by campaign offsets
  UPDATE custom_internal_demo_config
  SET payload = payload || jsonb_build_object('seed_anchor', v_to),
      updated_at = now()
  WHERE kind = 'settings' AND code = 'default';

  v_day := v_from;
  WHILE v_day <= v_to LOOP
    v_result := custom_internal_demo_generate_day(v_day, p_mode);
    v_results := v_results || jsonb_build_array(jsonb_build_object(
      'date', v_day,
      'success', v_result->>'success',
      'skipped', v_result->'skipped',
      'counts', v_result->'counts'
    ));

    IF coalesce((v_result->>'skipped')::boolean, false) THEN
      v_skip := v_skip + 1;
    ELSIF coalesce((v_result->>'success')::boolean, false) THEN
      v_ok := v_ok + 1;
    ELSE
      v_fail := v_fail + 1;
    END IF;

    IF v_day < v_to AND coalesce(p_pause_seconds, 0) > 0 THEN
      PERFORM pg_sleep(p_pause_seconds);
    END IF;

    v_day := v_day + 1;
  END LOOP;

  RETURN jsonb_build_object(
    'success', v_fail = 0,
    'from', v_from,
    'to', v_to,
    'ok_days', v_ok,
    'skipped_days', v_skip,
    'failed_days', v_fail,
    'pause_seconds', p_pause_seconds,
    'mode', p_mode
  );
END;
$fn$;

CREATE OR REPLACE FUNCTION public.custom_internal_demo_daily_job()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $fn$
BEGIN
  RETURN custom_internal_demo_generate_day(current_date, 'live');
END;
$fn$;
