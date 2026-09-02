-- Daily catch-up: full re-eval walk for every custom merchant (no gap filter).
-- Nightly Render job chains 5000-user chunks until has_more = false.
-- Resume only when a prior run was interrupted (cursor.after_user_id set).

CREATE OR REPLACE FUNCTION public.fn_loyalty_cache_daily_walk_prepare(p_merchant_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_job text := 'loyalty_cache_daily_catchup';
  v_after uuid;
  v_status text;
BEGIN
  IF NOT public.fn_loyalty_is_custom_tier(p_merchant_id)
     AND NOT public.fn_loyalty_is_custom_expiry(p_merchant_id) THEN
    RETURN jsonb_build_object('ok', false, 'reason', 'not_custom_merchant');
  END IF;

  INSERT INTO public.system_cron (job_name, merchant_id, status, cursor, updated_at)
  VALUES (v_job, p_merchant_id, 'idle', '{}'::jsonb, now())
  ON CONFLICT (job_name, merchant_id) DO NOTHING;

  SELECT sc.status, NULLIF(sc.cursor->>'after_user_id', '')::uuid
  INTO v_status, v_after
  FROM public.system_cron sc
  WHERE sc.job_name = v_job
    AND sc.merchant_id = p_merchant_id;

  IF v_status = 'running' AND v_after IS NOT NULL THEN
    RETURN jsonb_build_object('ok', true, 'resumed', true, 'after_user_id', v_after);
  END IF;

  UPDATE public.system_cron
  SET status = 'running',
      cursor = '{}'::jsonb,
      updated_at = now()
  WHERE job_name = v_job
    AND merchant_id = p_merchant_id;

  RETURN jsonb_build_object('ok', true, 'resumed', false);
END;
$function$;

CREATE OR REPLACE FUNCTION public.fn_loyalty_cache_invalidate_merchant(p_merchant_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
BEGIN
  RETURN public.fn_loyalty_cache_daily_walk_prepare(p_merchant_id);
END;
$function$;

CREATE OR REPLACE FUNCTION public.fn_loyalty_cache_catchup_due(p_merchant_id uuid)
RETURNS boolean
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_after uuid;
  v_status text;
BEGIN
  IF NOT public.fn_loyalty_is_custom_tier(p_merchant_id)
     AND NOT public.fn_loyalty_is_custom_expiry(p_merchant_id) THEN
    RETURN false;
  END IF;

  SELECT sc.status, NULLIF(sc.cursor->>'after_user_id', '')::uuid
  INTO v_status, v_after
  FROM public.system_cron sc
  WHERE sc.job_name = 'loyalty_cache_daily_catchup'
    AND sc.merchant_id = p_merchant_id;

  -- Legacy helper: due when custom merchant and (in progress or always run nightly).
  IF v_status = 'running' AND v_after IS NOT NULL THEN
    RETURN true;
  END IF;

  RETURN true;
END;
$function$;

CREATE OR REPLACE FUNCTION public.fn_loyalty_cache_catchup_chunk(
  p_merchant_id uuid,
  p_as_of_date date DEFAULT (timezone('Asia/Bangkok'::text, now()))::date,
  p_batch_size integer DEFAULT 5000
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_job text := 'loyalty_cache_daily_catchup';
  v_after uuid;
  v_users uuid[];
  v_last uuid;
  v_has_more boolean := false;
BEGIN
  IF p_batch_size IS NULL OR p_batch_size < 1 THEN
    RAISE EXCEPTION 'p_batch_size must be a positive integer';
  END IF;

  IF NOT public.fn_loyalty_is_custom_tier(p_merchant_id)
     AND NOT public.fn_loyalty_is_custom_expiry(p_merchant_id) THEN
    RETURN jsonb_build_object('skipped', true, 'reason', 'not_custom_merchant');
  END IF;

  INSERT INTO public.system_cron (job_name, merchant_id, status, cursor, updated_at)
  VALUES (v_job, p_merchant_id, 'idle', '{}'::jsonb, now())
  ON CONFLICT (job_name, merchant_id) DO NOTHING;

  SELECT NULLIF(sc.cursor->>'after_user_id', '')::uuid
  INTO v_after
  FROM public.system_cron sc
  WHERE sc.job_name = v_job
    AND sc.merchant_id = p_merchant_id;

  SELECT COALESCE(array_agg(q.id ORDER BY q.id), ARRAY[]::uuid[])
  INTO v_users
  FROM (
    SELECT ua.id
    FROM public.user_accounts ua
    WHERE ua.merchant_id = p_merchant_id
      AND (v_after IS NULL OR ua.id > v_after)
    ORDER BY ua.id
    LIMIT p_batch_size
  ) q;

  IF cardinality(v_users) = 0 THEN
    UPDATE public.system_cron
    SET cursor = '{}'::jsonb,
        status = 'success',
        last_finished_at = now(),
        updated_at = now()
    WHERE job_name = v_job
      AND merchant_id = p_merchant_id;

    RETURN jsonb_build_object(
      'users_refreshed', 0,
      'has_more', false,
      'walk_complete', true
    );
  END IF;

  v_last := v_users[cardinality(v_users)];
  PERFORM public.fn_loyalty_cache_refresh_users(p_merchant_id, v_users, p_as_of_date);

  SELECT EXISTS (
    SELECT 1
    FROM public.user_accounts ua
    WHERE ua.merchant_id = p_merchant_id
      AND ua.id > v_last
  ) INTO v_has_more;

  UPDATE public.system_cron
  SET cursor = CASE
        WHEN v_has_more THEN jsonb_build_object('after_user_id', v_last)
        ELSE '{}'::jsonb
      END,
      status = CASE WHEN v_has_more THEN 'running' ELSE 'success' END,
      last_finished_at = CASE WHEN v_has_more THEN last_finished_at ELSE now() END,
      updated_at = now()
  WHERE job_name = v_job
    AND merchant_id = p_merchant_id;

  RETURN jsonb_build_object(
    'users_refreshed', cardinality(v_users),
    'has_more', v_has_more,
    'walk_complete', NOT v_has_more
  );
END;
$function$;
