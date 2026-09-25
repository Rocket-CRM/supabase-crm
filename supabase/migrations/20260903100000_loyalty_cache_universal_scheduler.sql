-- Loyalty cache v2: universal scheduler (cron → wrapper → standard|custom calculator).
-- Crons no longer gate on fn_loyalty_is_custom_*; routing lives in fn_loyalty_resolve_calculator.
-- BFF expiry read path uses cache only (populated by the same wrappers).

-- ---------------------------------------------------------------------------
-- Merchant eligibility (tier program and/or expiry display) — not custom/standard
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.fn_loyalty_cache_merchant_eligible(p_merchant_id uuid)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path TO 'public'
AS $$
  SELECT EXISTS (
    SELECT 1
    FROM public.tier_program_config tpc
    WHERE tpc.merchant_id = p_merchant_id
  )
  OR public.fn_loyalty_expiry_display_enabled(p_merchant_id);
$$;

-- ---------------------------------------------------------------------------
-- Standard calculators (same contract as custom_function.{slug}_*)
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION custom_function.standard_points_expiry(
  p_merchant_id uuid,
  p_user_ids uuid[],
  p_as_of_date date
)
RETURNS TABLE(user_id uuid, expiry_date date, amount numeric)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path TO 'public'
AS $$
  SELECT
    wl.user_id,
    wl.expiry_date,
    SUM(GREATEST(wl.deductible_balance, 0))::numeric AS amount
  FROM public.wallet_ledger wl
  WHERE wl.merchant_id = p_merchant_id
    AND wl.user_id = ANY (p_user_ids)
    AND wl.currency = 'points'::public.currency
    AND wl.transaction_type = 'earn'::public.currency_transaction_type
    AND wl.expiry_date IS NOT NULL
    AND wl.expiry_date > p_as_of_date
    AND wl.deductible_balance > 0
  GROUP BY wl.user_id, wl.expiry_date
  HAVING SUM(GREATEST(wl.deductible_balance, 0)) > 0;
$$;

CREATE OR REPLACE FUNCTION custom_function.standard_tier_progress(
  p_merchant_id uuid,
  p_user_ids uuid[],
  p_as_of_date date
)
RETURNS TABLE(
  user_id uuid,
  point_earn numeric,
  current_tier_id uuid,
  recommended_tier_id uuid,
  recommended_action text,
  next_tier_id uuid,
  upgrade_metric_needed public.metric,
  upgrade_progress_percent numeric,
  upgrade_deadline date,
  maintain_metric_needed public.metric,
  maintain_progress numeric,
  maintain_deadline date
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_uid uuid;
  v_current_tier_id uuid;
  v_user_type public.user_type;
  v_cfg record;
  v_eval jsonb;
  v_action text;
  v_effective_position integer;
  v_next_tier_id uuid;
  v_next_amount numeric;
  v_window_start date;
  v_window_end date;
  v_metric_value numeric;
  v_upgrade_metric public.metric;
  v_upgrade_progress numeric;
  v_maintain_metric public.metric;
  v_maintain_threshold numeric;
  v_maintain_progress numeric;
  v_recommended_tier_id uuid;
BEGIN
  IF p_user_ids IS NULL OR cardinality(p_user_ids) = 0 THEN
    RETURN;
  END IF;

  FOREACH v_uid IN ARRAY p_user_ids LOOP
    SELECT ua.tier_id, ua.user_type
    INTO v_current_tier_id, v_user_type
    FROM public.user_accounts ua
    WHERE ua.id = v_uid
      AND ua.merchant_id = p_merchant_id;

    IF NOT FOUND THEN
      CONTINUE;
    END IF;

    SELECT * INTO v_cfg
    FROM public.tier_program_config
    WHERE merchant_id = p_merchant_id
      AND user_type = v_user_type;

    IF NOT FOUND THEN
      CONTINUE;
    END IF;

    v_eval := public.evaluate_user_tier_status(v_uid, p_merchant_id, p_as_of_date);
    v_action := v_eval->>'recommended_action';
    v_recommended_tier_id := NULLIF(v_eval->>'recommended_tier_id', '')::uuid;

    IF v_action = 'error' THEN
      CONTINUE;
    END IF;

    SELECT w.window_start, w.window_end
    INTO v_window_start, v_window_end
    FROM public.fn_tier_window(p_merchant_id, v_user_type, p_as_of_date) w;

    v_metric_value := public.calculate_tier_metric_value(
      v_uid, p_merchant_id, v_cfg.metric, v_user_type, v_window_start, v_window_end
    );

    v_upgrade_metric := NULL;
    v_upgrade_progress := NULL;
    v_next_tier_id := NULL;
    v_next_amount := NULL;
    v_maintain_metric := NULL;
    v_maintain_progress := NULL;

    SELECT max(l.ladder_position) FILTER (WHERE l.tier_id = v_current_tier_id)
    INTO v_effective_position
    FROM public.fn_tier_ladder_for_user(v_uid, p_merchant_id) l;

    SELECT l.tier_id, l.upgrade_amount
    INTO v_next_tier_id, v_next_amount
    FROM public.fn_tier_ladder_for_user(v_uid, p_merchant_id) l
    WHERE l.ladder_position > COALESCE(v_effective_position, 0)
    ORDER BY l.ladder_position ASC
    LIMIT 1;

    IF v_next_tier_id IS NOT NULL THEN
      v_upgrade_metric := v_cfg.metric;
      v_upgrade_progress := LEAST(
        COALESCE(v_metric_value * 100.0 / NULLIF(v_next_amount, 0), 0), 100
      );
    END IF;

    IF COALESCE(v_cfg.maintain_mode, 'lifetime') = 'period'
       AND v_current_tier_id IS NOT NULL THEN
      SELECT l.upgrade_amount INTO v_maintain_threshold
      FROM public.fn_tier_ladder_for_user(v_uid, p_merchant_id) l
      WHERE l.tier_id = v_current_tier_id
      LIMIT 1;

      IF v_maintain_threshold IS NOT NULL THEN
        v_maintain_metric := v_cfg.metric;
        v_maintain_progress := v_metric_value * 100.0 / NULLIF(v_maintain_threshold, 0);
      END IF;
    END IF;

    user_id := v_uid;
    point_earn := v_metric_value;
    current_tier_id := v_current_tier_id;
    recommended_tier_id := v_recommended_tier_id;
    recommended_action := v_action;
    next_tier_id := v_next_tier_id;
    upgrade_metric_needed := v_upgrade_metric;
    upgrade_progress_percent := v_upgrade_progress;
    upgrade_deadline := v_window_end;
    maintain_metric_needed := v_maintain_metric;
    maintain_progress := v_maintain_progress;
    maintain_deadline := NULL;
    RETURN NEXT;
  END LOOP;
END;
$function$;

-- ---------------------------------------------------------------------------
-- Resolver: merchant calculator when custom, else standard (routing inside wrapper)
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.fn_loyalty_resolve_calculator(p_merchant_id uuid, p_kind text)
RETURNS regprocedure
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_slug text;
  v_name text;
  v_reg regprocedure;
  v_use_custom boolean;
BEGIN
  IF p_kind NOT IN ('tier_progress', 'points_expiry') THEN
    RAISE EXCEPTION 'invalid calculator kind: %', p_kind;
  END IF;

  v_use_custom := CASE p_kind
    WHEN 'tier_progress' THEN public.fn_loyalty_is_custom_tier(p_merchant_id)
    WHEN 'points_expiry' THEN public.fn_loyalty_is_custom_expiry(p_merchant_id)
    ELSE false
  END;

  IF v_use_custom THEN
    SELECT mm.merchant_code INTO v_slug
    FROM public.merchant_master mm
    WHERE mm.id = p_merchant_id;

    IF v_slug IS NULL OR btrim(v_slug) = '' THEN
      RETURN NULL;
    END IF;

    v_name := format('custom_function.%I_%s(uuid,uuid[],date)', v_slug, p_kind);
  ELSE
    v_name := format('custom_function.standard_%s(uuid,uuid[],date)', p_kind);
  END IF;

  BEGIN
    v_reg := v_name::regprocedure;
  EXCEPTION WHEN OTHERS THEN
    RETURN NULL;
  END;

  RETURN v_reg;
END;
$function$;

-- ---------------------------------------------------------------------------
-- Refresh wrapper: always refresh tier + expiry; calculators decide math
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.fn_loyalty_cache_refresh_users(
  p_merchant_id uuid,
  p_user_ids uuid[],
  p_as_of_date date DEFAULT (timezone('Asia/Bangkok'::text, now()))::date
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_tier jsonb := '{}'::jsonb;
  v_expiry jsonb := '{}'::jsonb;
BEGIN
  IF NOT public.fn_loyalty_cache_merchant_eligible(p_merchant_id) THEN
    RETURN jsonb_build_object(
      'merchant_id', p_merchant_id,
      'users', COALESCE(cardinality(p_user_ids), 0),
      'skipped', true,
      'reason', 'not_eligible'
    );
  END IF;

  IF EXISTS (
    SELECT 1
    FROM public.tier_program_config tpc
    WHERE tpc.merchant_id = p_merchant_id
  ) THEN
    v_tier := public.fn_loyalty_cache_upsert_tier_progress(p_merchant_id, p_user_ids, p_as_of_date);
  END IF;

  IF public.fn_loyalty_expiry_display_enabled(p_merchant_id) THEN
    v_expiry := public.fn_loyalty_cache_upsert_points_expiry(p_merchant_id, p_user_ids, p_as_of_date);
  END IF;

  RETURN jsonb_build_object(
    'merchant_id', p_merchant_id,
    'users', COALESCE(cardinality(p_user_ids), 0),
    'tier', v_tier,
    'expiry', v_expiry
  );
END;
$function$;

-- ---------------------------------------------------------------------------
-- BFF read: cache only (cron/wrapper keeps it fresh)
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.fn_loyalty_expiry_buckets_for_user(
  p_user_id uuid,
  p_merchant_id uuid,
  p_as_of_date date DEFAULT (timezone('Asia/Bangkok', now()))::date
)
RETURNS TABLE(expiry_date date, amount numeric)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path TO 'public'
AS $$
  SELECT c.expiry_date, c.amount::numeric
  FROM public.user_points_expiry_cache c
  WHERE c.merchant_id = p_merchant_id
    AND c.user_id = p_user_id
    AND c.expiry_date > p_as_of_date
    AND c.amount > 0;
$$;

-- ---------------------------------------------------------------------------
-- Daily walk helpers (all eligible merchants)
-- ---------------------------------------------------------------------------
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
  IF NOT public.fn_loyalty_cache_merchant_eligible(p_merchant_id) THEN
    RETURN jsonb_build_object('ok', false, 'reason', 'not_eligible');
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
  IF NOT public.fn_loyalty_cache_merchant_eligible(p_merchant_id) THEN
    RETURN false;
  END IF;

  SELECT sc.status, NULLIF(sc.cursor->>'after_user_id', '')::uuid
  INTO v_status, v_after
  FROM public.system_cron sc
  WHERE sc.job_name = 'loyalty_cache_daily_catchup'
    AND sc.merchant_id = p_merchant_id;

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

  IF NOT public.fn_loyalty_cache_merchant_eligible(p_merchant_id) THEN
    RETURN jsonb_build_object('skipped', true, 'reason', 'not_eligible');
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

-- ---------------------------------------------------------------------------
-- 5-minute dirty refresh (all eligible merchants)
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.fn_loyalty_cache_refresh_5m()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_locked boolean;
  v_merchant record;
  v_cutoff timestamptz;
  v_scan_from timestamptz;
  v_now timestamptz := now();
  v_as_of date := (timezone('Asia/Bangkok', now()))::date;
  v_users uuid[];
  v_chunk uuid[];
  v_i int;
  v_merchants int := 0;
  v_users_total int := 0;
  v_failed boolean := false;
  v_err text;
  v_result jsonb;
  v_details jsonb := '[]'::jsonb;
  v_internal_chunk_size constant integer := 500;
BEGIN
  v_locked := pg_try_advisory_lock(hashtext('loyalty_cache_refresh_5m'));
  IF NOT v_locked THEN
    RETURN jsonb_build_object('ok', true, 'locked', true);
  END IF;

  BEGIN
    FOR v_merchant IN
      SELECT mm.id AS merchant_id, mm.merchant_code
      FROM public.merchant_master mm
      WHERE public.fn_loyalty_cache_merchant_eligible(mm.id)
      ORDER BY mm.id
    LOOP
      v_merchants := v_merchants + 1;

      INSERT INTO public.system_cron (job_name, merchant_id, cutoff_at, status, updated_at)
      VALUES ('loyalty_cache_refresh', v_merchant.merchant_id, v_now - interval '1 day', 'running', v_now)
      ON CONFLICT (job_name, merchant_id) DO UPDATE SET
        status = 'running',
        updated_at = v_now;

      SELECT sc.cutoff_at INTO v_cutoff
      FROM public.system_cron sc
      WHERE sc.job_name = 'loyalty_cache_refresh'
        AND sc.merchant_id = v_merchant.merchant_id;

      v_cutoff := COALESCE(v_cutoff, v_now - interval '1 day');
      v_scan_from := v_cutoff - interval '5 minutes';

      BEGIN
        SELECT COALESCE(array_agg(DISTINCT d.user_id), ARRAY[]::uuid[])
        INTO v_users
        FROM (
          SELECT wl.user_id
          FROM public.wallet_ledger wl
          WHERE wl.merchant_id = v_merchant.merchant_id
            AND wl.currency = 'points'::public.currency
            AND wl.transaction_type = ANY (
              ARRAY[
                'earn'::public.currency_transaction_type,
                'burn'::public.currency_transaction_type
              ]
            )
            AND wl.created_at >= v_scan_from
          UNION
          SELECT pr.user_id
          FROM public.purchase_receipt_upload pr
          WHERE pr.merchant_id = v_merchant.merchant_id
            AND pr.status = 'approved'
            AND pr.crm_sync_status = 'confirmed'
            AND pr.updated_at >= v_scan_from
            AND pr.user_id IS NOT NULL
        ) d;

        IF cardinality(v_users) > 0 THEN
          v_i := 1;
          WHILE v_i <= cardinality(v_users) LOOP
            v_chunk := v_users[v_i : LEAST(v_i + v_internal_chunk_size - 1, cardinality(v_users))];
            v_result := public.fn_loyalty_cache_refresh_users(v_merchant.merchant_id, v_chunk, v_as_of);
            v_users_total := v_users_total + cardinality(v_chunk);
            v_i := v_i + v_internal_chunk_size;
          END LOOP;
        END IF;

        UPDATE public.system_cron
        SET cutoff_at = v_now,
            last_finished_at = v_now,
            status = 'success',
            updated_at = v_now
        WHERE job_name = 'loyalty_cache_refresh'
          AND merchant_id = v_merchant.merchant_id;

        v_details := v_details || jsonb_build_array(jsonb_build_object(
          'merchant_id', v_merchant.merchant_id,
          'merchant_code', v_merchant.merchant_code,
          'dirty_users', COALESCE(cardinality(v_users), 0),
          'status', 'success'
        ));
      EXCEPTION WHEN OTHERS THEN
        v_failed := true;
        v_err := SQLERRM;
        UPDATE public.system_cron
        SET status = 'failed',
            last_finished_at = v_now,
            updated_at = v_now
        WHERE job_name = 'loyalty_cache_refresh'
          AND merchant_id = v_merchant.merchant_id;
        v_details := v_details || jsonb_build_array(jsonb_build_object(
          'merchant_id', v_merchant.merchant_id,
          'merchant_code', v_merchant.merchant_code,
          'status', 'failed',
          'error', v_err
        ));
      END;
    END LOOP;
  EXCEPTION WHEN OTHERS THEN
    PERFORM pg_advisory_unlock(hashtext('loyalty_cache_refresh_5m'));
    RAISE;
  END;

  PERFORM pg_advisory_unlock(hashtext('loyalty_cache_refresh_5m'));

  RETURN jsonb_build_object(
    'ok', NOT v_failed,
    'merchants', v_merchants,
    'users_refreshed', v_users_total,
    'details', v_details
  );
END;
$function$;
