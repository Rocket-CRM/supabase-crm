-- Phase 1a: daily static audience refresh schedule + broadcast refresh-before-send flag

ALTER TABLE public.amp_audience_master
  ADD COLUMN IF NOT EXISTS refresh_schedule text NOT NULL DEFAULT 'manual',
  ADD COLUMN IF NOT EXISTS refresh_time time,
  ADD COLUMN IF NOT EXISTS next_refresh_at timestamptz,
  ADD COLUMN IF NOT EXISTS last_refreshed_at timestamptz;

ALTER TABLE public.amp_audience_master
  DROP CONSTRAINT IF EXISTS amp_audience_master_refresh_schedule_chk;

ALTER TABLE public.amp_audience_master
  ADD CONSTRAINT amp_audience_master_refresh_schedule_chk
  CHECK (refresh_schedule IN ('manual', 'daily'));

CREATE INDEX IF NOT EXISTS amp_audience_master_next_refresh_idx
  ON public.amp_audience_master (next_refresh_at)
  WHERE refresh_schedule = 'daily' AND is_active = true;

ALTER TABLE public.amp_broadcast_master
  ADD COLUMN IF NOT EXISTS refresh_before_send boolean NOT NULL DEFAULT true;

CREATE OR REPLACE FUNCTION public.fn_amp_audience_schedule_timezone(p_merchant_id uuid)
RETURNS text
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
  SELECT COALESCE(
    (
      SELECT NULLIF(btrim(ui_config->>'timezone'), '')
      FROM merchant_display_settings
      WHERE merchant_id = p_merchant_id
      LIMIT 1
    ),
    'Asia/Bangkok'
  );
$function$;

REVOKE ALL ON FUNCTION public.fn_amp_audience_schedule_timezone(uuid) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.fn_amp_audience_schedule_timezone(uuid) TO service_role;

CREATE OR REPLACE FUNCTION public.fn_amp_compute_next_audience_refresh_at(
  p_merchant_id uuid,
  p_refresh_time time,
  p_from timestamptz DEFAULT now()
)
RETURNS timestamptz
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
  SELECT public.fn_amp_compute_next_run_at(
    jsonb_build_object(
      'type', 'daily',
      'time_of_day', to_char(p_refresh_time, 'HH24:MI:SS'),
      'timezone', public.fn_amp_audience_schedule_timezone(p_merchant_id)
    ),
    p_from
  );
$function$;

REVOKE ALL ON FUNCTION public.fn_amp_compute_next_audience_refresh_at(uuid, time, timestamptz) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.fn_amp_compute_next_audience_refresh_at(uuid, time, timestamptz) TO service_role;

CREATE OR REPLACE FUNCTION public.fn_amp_apply_audience_refresh_schedule(p_audience_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_row public.amp_audience_master%ROWTYPE;
BEGIN
  SELECT * INTO v_row FROM public.amp_audience_master WHERE id = p_audience_id;
  IF NOT FOUND THEN
    RETURN;
  END IF;

  IF v_row.audience_type <> 'static'
     OR v_row.refresh_schedule <> 'daily'
     OR NOT v_row.is_active
     OR v_row.refresh_time IS NULL THEN
    UPDATE public.amp_audience_master
    SET next_refresh_at = NULL, updated_at = now()
    WHERE id = p_audience_id;
    RETURN;
  END IF;

  UPDATE public.amp_audience_master
  SET next_refresh_at = public.fn_amp_compute_next_audience_refresh_at(
        v_row.merchant_id,
        v_row.refresh_time,
        now()
      ),
      updated_at = now()
  WHERE id = p_audience_id;
END;
$function$;

REVOKE ALL ON FUNCTION public.fn_amp_apply_audience_refresh_schedule(uuid) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.fn_amp_apply_audience_refresh_schedule(uuid) TO service_role;

CREATE OR REPLACE FUNCTION public.fn_amp_resnapshot_audience(p_audience_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
DECLARE
  v_audience RECORD;
  v_match_sql TEXT;
  v_entered INTEGER;
  v_exited INTEGER;
  v_member_count INTEGER;
BEGIN
  SELECT * INTO v_audience FROM amp_audience_master WHERE id = p_audience_id;

  IF NOT FOUND THEN
    RETURN jsonb_build_object('success', false, 'code', 'NOT_FOUND', 'audience_id', p_audience_id);
  END IF;

  IF v_audience.audience_type = 'imported' THEN
    RETURN jsonb_build_object(
      'success', true,
      'code', 'SKIPPED_IMPORTED',
      'audience_id', p_audience_id,
      'entered', 0,
      'exited', 0,
      'member_count', COALESCE(v_audience.member_count, 0)
    );
  END IF;

  IF v_audience.workflow_id IS NULL THEN
    RETURN jsonb_build_object('success', false, 'code', 'NO_WORKFLOW', 'audience_id', p_audience_id);
  END IF;

  v_match_sql := fn_amp_compile_workflow_match_sql(v_audience.workflow_id);
  IF v_match_sql IS NULL THEN
    RETURN jsonb_build_object('success', false, 'code', 'NO_CONDITIONS', 'audience_id', p_audience_id);
  END IF;

  EXECUTE format(
    'WITH matches AS (SELECT DISTINCT m.user_id FROM (%s) m WHERE m.user_id IS NOT NULL), '
    || 'exits AS ( '
    || '  UPDATE amp_audience_member am SET exited_at = now() '
    || '  WHERE am.audience_id = %L AND am.exited_at IS NULL '
    || '    AND NOT EXISTS (SELECT 1 FROM matches x WHERE x.user_id = am.user_id) '
    || '  RETURNING am.user_id), '
    || 'adds AS ( '
    || '  INSERT INTO amp_audience_member (audience_id, user_id, source_workflow_id) '
    || '  SELECT %L, x.user_id, %L FROM matches x '
    || '  WHERE NOT EXISTS (SELECT 1 FROM amp_audience_member am2 WHERE am2.audience_id = %L AND am2.user_id = x.user_id AND am2.exited_at IS NULL) '
    || '  ON CONFLICT (audience_id, user_id) WHERE (exited_at IS NULL) DO NOTHING '
    || '  RETURNING user_id) '
    || 'SELECT (SELECT count(*) FROM exits)::int, (SELECT count(*) FROM adds)::int',
    v_match_sql, p_audience_id, p_audience_id, v_audience.workflow_id, p_audience_id
  ) INTO v_exited, v_entered;

  SELECT count(*)::int INTO v_member_count
  FROM amp_audience_member WHERE audience_id = p_audience_id AND exited_at IS NULL;

  UPDATE amp_audience_master
  SET member_count = v_member_count,
      last_refreshed_at = now(),
      updated_at = now()
  WHERE id = p_audience_id;

  IF v_entered > 0 OR v_exited > 0 THEN
    INSERT INTO workflow_log (merchant_id, workflow_id, user_id, inngest_run_id, event_type, event_data)
    VALUES (
      v_audience.merchant_id, v_audience.workflow_id,
      '00000000-0000-0000-0000-000000000000'::uuid,
      'audience_resnapshot_' || gen_random_uuid()::text,
      'audience_reconciled',
      jsonb_build_object('audience_id', p_audience_id, 'entered', v_entered, 'exited', v_exited, 'member_count', v_member_count)
    );
  END IF;

  RETURN jsonb_build_object(
    'success', true,
    'audience_id', p_audience_id,
    'entered', v_entered,
    'exited', v_exited,
    'member_count', v_member_count
  );
END;
$function$;

CREATE OR REPLACE FUNCTION public.fn_amp_run_due_audience_refreshes(p_run_at timestamptz DEFAULT now())
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_row RECORD;
  v_result jsonb;
  v_processed int := 0;
  v_failed int := 0;
  v_errors jsonb := '[]'::jsonb;
BEGIN
  FOR v_row IN
    SELECT *
    FROM public.amp_audience_master
    WHERE is_active = true
      AND audience_type = 'static'
      AND refresh_schedule = 'daily'
      AND refresh_time IS NOT NULL
      AND next_refresh_at IS NOT NULL
      AND next_refresh_at <= p_run_at
    ORDER BY next_refresh_at
    FOR UPDATE SKIP LOCKED
  LOOP
    v_processed := v_processed + 1;
    BEGIN
      v_result := public.fn_amp_resnapshot_audience(v_row.id);
      IF COALESCE((v_result->>'success')::boolean, false) THEN
        PERFORM public.fn_amp_apply_audience_refresh_schedule(v_row.id);
      ELSE
        v_failed := v_failed + 1;
        v_errors := v_errors || jsonb_build_object(
          'audience_id', v_row.id,
          'code', v_result->>'code',
          'detail', v_result
        );
        INSERT INTO workflow_log (merchant_id, workflow_id, user_id, inngest_run_id, event_type, event_data)
        VALUES (
          v_row.merchant_id,
          v_row.workflow_id,
          '00000000-0000-0000-0000-000000000000'::uuid,
          'audience_refresh_failed_' || gen_random_uuid()::text,
          'audience_reconciled',
          jsonb_build_object(
            'audience_id', v_row.id,
            'success', false,
            'code', v_result->>'code',
            'scheduled_refresh', true
          )
        );
      END IF;
    EXCEPTION WHEN OTHERS THEN
      v_failed := v_failed + 1;
      v_errors := v_errors || jsonb_build_object('audience_id', v_row.id, 'error', SQLERRM);
      INSERT INTO workflow_log (merchant_id, workflow_id, user_id, inngest_run_id, event_type, event_data)
      VALUES (
        v_row.merchant_id,
        v_row.workflow_id,
        '00000000-0000-0000-0000-000000000000'::uuid,
        'audience_refresh_failed_' || gen_random_uuid()::text,
        'audience_reconciled',
        jsonb_build_object('audience_id', v_row.id, 'success', false, 'error', SQLERRM, 'scheduled_refresh', true)
      );
    END;
  END LOOP;

  RETURN jsonb_build_object(
    'success', true,
    'run_at', p_run_at,
    'processed', v_processed,
    'failed', v_failed,
    'errors', v_errors
  );
END;
$function$;

REVOKE ALL ON FUNCTION public.fn_amp_run_due_audience_refreshes(timestamptz) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.fn_amp_run_due_audience_refreshes(timestamptz) TO service_role;

SELECT cron.unschedule(jobid)
FROM cron.job
WHERE jobname = 'amp_run_due_audience_refreshes';

SELECT cron.schedule(
  'amp_run_due_audience_refreshes',
  '*/5 * * * *',
  $$SELECT public.fn_amp_run_due_audience_refreshes();$$
);
