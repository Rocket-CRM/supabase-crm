-- Daily ops recon: run in-database (long timeout), cache for MCP/automation reads.

CREATE INDEX IF NOT EXISTS wallet_ledger_merchant_user_points_idx
  ON public.wallet_ledger (merchant_id, user_id)
  WHERE currency = 'points'::public.currency;

CREATE INDEX IF NOT EXISTS purchase_ledger_earn_unprocessed_merchant_idx
  ON public.purchase_ledger (merchant_id, created_at)
  WHERE earn_currency = true
    AND currency_processed_at IS NULL
    AND status = 'completed'::public.purchase_status;

CREATE OR REPLACE FUNCTION public.fn_ops_daily_recon_refresh(p_day date DEFAULT NULL::date)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_day date := COALESCE(
    p_day,
    (timezone('Asia/Bangkok', now()) - interval '1 day')::date
  );
  v_result jsonb;
BEGIN
  PERFORM set_config('statement_timeout', '900000', true);

  v_result := public.fn_ops_daily_recon(v_day);

  DELETE FROM public._ops_daily_recon_cache
  WHERE (result ->> 'day')::date = v_day;

  INSERT INTO public._ops_daily_recon_cache (result)
  VALUES (v_result);

  RETURN v_result;
END;
$function$;

CREATE OR REPLACE FUNCTION public.fn_ops_daily_recon_get(p_day date DEFAULT NULL::date)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_day date := COALESCE(
    p_day,
    (timezone('Asia/Bangkok', now()) - interval '1 day')::date
  );
  v_result jsonb;
  v_cached_at timestamptz;
BEGIN
  SELECT c.result, c.created_at
  INTO v_result, v_cached_at
  FROM public._ops_daily_recon_cache c
  WHERE (c.result ->> 'day')::date = v_day
  ORDER BY c.id DESC
  LIMIT 1;

  IF v_result IS NULL THEN
    RETURN jsonb_build_object(
      'status', 'error',
      'day', v_day,
      'message',
        'No cached daily recon for this day. '
        || 'pg_cron job ops-daily-recon-refresh runs at 00:22 UTC '
        || '(07:22 Asia/Bangkok) for the prior BKK calendar day, '
        || 'or run SELECT public.fn_ops_daily_recon_refresh($1) from the SQL editor.',
      'automation_hint',
        'Do not call fn_ops_daily_recon() via MCP/API — use fn_ops_daily_recon_get() instead.'
    );
  END IF;

  RETURN v_result || jsonb_build_object(
    'cached_at', v_cached_at,
    'source', 'cache'
  );
END;
$function$;

SELECT cron.unschedule(jobid)
FROM cron.job
WHERE jobname = 'ops-daily-recon-refresh';

SELECT cron.schedule(
  'ops-daily-recon-refresh',
  '22 0 * * *',
  $$SELECT public.fn_ops_daily_recon_refresh();$$
);
