-- Cache-first tier progress reads + expiry catch-up predicate + cursor reset on complete.
--
-- 1. tier_progress stores upgrade_metric_current + upgrade_threshold (writer fills; readers trust).
-- 2. fn_admin_get_tier_progress_enriched / get_user_summary read cache only (no ladder stale guard).
-- 3. Daily catch-up: expiry unfinished = missing row AND user has unexpired deductible earns.
-- 4. Clear catch-up cursor when backlog_complete (stops false in-progress state).

ALTER TABLE public.tier_progress
  ADD COLUMN IF NOT EXISTS upgrade_metric_current numeric,
  ADD COLUMN IF NOT EXISTS upgrade_threshold numeric;

COMMENT ON COLUMN public.tier_progress.upgrade_metric_current IS
  'Cached qualifying earn toward next tier (calculator point_earn).';
COMMENT ON COLUMN public.tier_progress.upgrade_threshold IS
  'Cached points required for next_tier_id at eval time.';

-- ---------------------------------------------------------------------------
-- Expiry catch-up: only users who can have cache rows (unexpired deductible earns).
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.fn_loyalty_user_has_unexpired_point_earns(
  p_user_id uuid,
  p_merchant_id uuid
)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
  SELECT EXISTS (
    SELECT 1
    FROM public.wallet_ledger wl
    WHERE wl.user_id = p_user_id
      AND wl.merchant_id = p_merchant_id
      AND wl.currency = 'points'::public.currency
      AND wl.transaction_type = 'earn'::public.currency_transaction_type
      AND COALESCE(wl.deductible_balance, 0) > 0
      AND wl.expiry_processed_at IS NULL
  );
$function$;

-- ---------------------------------------------------------------------------
-- Tier cache writer: persist metric_current + threshold from calculator output.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.fn_loyalty_cache_upsert_tier_progress(
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
  v_proc regprocedure;
  v_sql text;
  v_count int := 0;
BEGIN
  IF p_user_ids IS NULL OR cardinality(p_user_ids) = 0 THEN
    RETURN jsonb_build_object('refreshed', 0, 'skipped', true, 'reason', 'empty_users');
  END IF;

  v_proc := public.fn_loyalty_resolve_calculator(p_merchant_id, 'tier_progress');
  IF v_proc IS NULL THEN
    RETURN jsonb_build_object('refreshed', 0, 'skipped', true, 'reason', 'missing_calculator');
  END IF;

  CREATE TEMP TABLE IF NOT EXISTS _loyalty_tier_calc (
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
  ) ON COMMIT DROP;
  TRUNCATE _loyalty_tier_calc;

  v_sql := format(
    'INSERT INTO _loyalty_tier_calc
     SELECT user_id, point_earn, current_tier_id, recommended_tier_id, recommended_action,
            next_tier_id, upgrade_metric_needed, upgrade_progress_percent, upgrade_deadline,
            maintain_metric_needed, maintain_progress, maintain_deadline
     FROM %s($1, $2, $3)',
    v_proc::oid::regproc
  );
  EXECUTE v_sql USING p_merchant_id, p_user_ids, p_as_of_date;

  INSERT INTO public.tier_progress AS tp (
    id, user_id, merchant_id, current_tier_id, next_tier_id,
    upgrade_metric_needed, upgrade_progress_percent, upgrade_deadline,
    maintain_metric_needed, maintain_progress, maintain_deadline,
    upgrade_metric_current, upgrade_threshold,
    created_at, updated_at
  )
  SELECT
    gen_random_uuid(),
    c.user_id,
    p_merchant_id,
    c.current_tier_id,
    c.next_tier_id,
    c.upgrade_metric_needed,
    c.upgrade_progress_percent,
    c.upgrade_deadline,
    c.maintain_metric_needed,
    c.maintain_progress,
    c.maintain_deadline,
    c.point_earn,
    CASE
      WHEN c.upgrade_progress_percent IS NOT NULL
        AND c.upgrade_progress_percent > 0
        AND COALESCE(c.point_earn, 0) > 0
        THEN ROUND(c.point_earn * 100.0 / c.upgrade_progress_percent)
      ELSE ladder.upgrade_amount
    END,
    now(),
    now()
  FROM _loyalty_tier_calc c
  LEFT JOIN LATERAL (
    SELECT l.upgrade_amount
    FROM public.fn_tier_ladder_for_user(c.user_id, p_merchant_id) l
    WHERE l.tier_id = c.next_tier_id
    LIMIT 1
  ) ladder ON c.next_tier_id IS NOT NULL
  ON CONFLICT (user_id, merchant_id) DO UPDATE SET
    current_tier_id = EXCLUDED.current_tier_id,
    next_tier_id = EXCLUDED.next_tier_id,
    upgrade_metric_needed = EXCLUDED.upgrade_metric_needed,
    upgrade_progress_percent = EXCLUDED.upgrade_progress_percent,
    upgrade_deadline = EXCLUDED.upgrade_deadline,
    maintain_metric_needed = EXCLUDED.maintain_metric_needed,
    maintain_progress = EXCLUDED.maintain_progress,
    maintain_deadline = EXCLUDED.maintain_deadline,
    upgrade_metric_current = EXCLUDED.upgrade_metric_current,
    upgrade_threshold = EXCLUDED.upgrade_threshold,
    updated_at = now();

  GET DIAGNOSTICS v_count = ROW_COUNT;
  RETURN jsonb_build_object('refreshed', v_count, 'skipped', false);
END;
$function$;

-- ---------------------------------------------------------------------------
-- Admin Front Line: read tier_progress cache only (+ tier_master labels).
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.fn_admin_get_tier_progress_enriched(
  p_user_id uuid,
  p_merchant_id uuid
)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_tp record;
  v_upgrade_metric text;
  v_progress numeric;
  v_amount_to_next numeric;
  v_percent numeric;
BEGIN
  SELECT tpc.metric::text
  INTO v_upgrade_metric
  FROM public.user_accounts ua
  LEFT JOIN public.tier_program_config tpc
    ON tpc.merchant_id = ua.merchant_id
   AND tpc.user_type = ua.user_type
  WHERE ua.id = p_user_id
    AND ua.merchant_id = p_merchant_id;

  SELECT
    tp.current_tier_id,
    tp.next_tier_id,
    tp.upgrade_metric_needed,
    tp.upgrade_progress_percent,
    tp.upgrade_deadline,
    tp.maintain_progress,
    tp.maintain_metric_needed,
    tp.maintain_deadline,
    tp.upgrade_metric_current,
    tp.upgrade_threshold,
    ct.tier_name AS current_tier_name,
    ct.icon AS current_tier_icon,
    ct.color AS current_tier_color,
    nt.tier_name AS next_tier_name
  INTO v_tp
  FROM public.tier_progress tp
  LEFT JOIN public.tier_master ct
    ON ct.id = COALESCE(
      tp.current_tier_id,
      (SELECT ua.tier_id FROM public.user_accounts ua WHERE ua.id = p_user_id AND ua.merchant_id = p_merchant_id)
    )
  LEFT JOIN public.tier_master nt ON nt.id = tp.next_tier_id
  WHERE tp.user_id = p_user_id
    AND tp.merchant_id = p_merchant_id;

  IF NOT FOUND THEN
    RETURN '{}'::jsonb;
  END IF;

  v_percent := v_tp.upgrade_progress_percent;
  IF v_tp.next_tier_id IS NOT NULL AND v_percent IS NULL THEN
    v_percent := 0;
  END IF;

  v_progress := v_tp.upgrade_metric_current;
  IF v_progress IS NULL
     AND v_tp.upgrade_threshold IS NOT NULL
     AND v_percent IS NOT NULL THEN
    v_progress := ROUND(v_tp.upgrade_threshold * v_percent / 100.0);
  END IF;

  IF v_tp.upgrade_threshold IS NOT NULL THEN
    v_amount_to_next := GREATEST(
      0,
      v_tp.upgrade_threshold - COALESCE(v_progress, 0)
    );
  END IF;

  RETURN jsonb_build_object(
    'current_tier_id', COALESCE(
      v_tp.current_tier_id,
      (SELECT ua.tier_id FROM public.user_accounts ua WHERE ua.id = p_user_id AND ua.merchant_id = p_merchant_id)
    ),
    'current_tier_name', v_tp.current_tier_name,
    'current_tier_icon', v_tp.current_tier_icon,
    'current_tier_color', v_tp.current_tier_color,
    'next_tier_id', v_tp.next_tier_id,
    'next_tier_name', v_tp.next_tier_name,
    'upgrade_progress_percent', v_percent,
    'upgrade_metric_needed', COALESCE(v_tp.upgrade_metric_needed::text, v_upgrade_metric),
    'upgrade_deadline', v_tp.upgrade_deadline,
    'maintain_progress', v_tp.maintain_progress,
    'maintain_metric_needed', v_tp.maintain_metric_needed,
    'maintain_deadline', v_tp.maintain_deadline,
    'upgrade_metric', v_upgrade_metric,
    'upgrade_threshold', v_tp.upgrade_threshold,
    'upgrade_progress', v_progress,
    'amount_to_next_tier', v_amount_to_next
  );
END;
$function$;

-- ---------------------------------------------------------------------------
-- Member summary: tier progress from cache (same contract as admin reader).
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.get_user_summary()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
    v_auth_user_id uuid;
    v_user_id uuid;
    v_merchant_id uuid;
    v_current_tier_id uuid;
    v_user_type user_type;
    v_persona_id uuid;
    v_cfg record;
    v_next_tier_id uuid;
    v_next_tier_name text;
    v_upgrade_metric text;
    v_upgrade_threshold numeric;
    v_upgrade_window_months smallint;
    v_upgrade_progress_percent numeric;
    v_upgrade_progress numeric;
    v_points_expiry_active boolean;
    v_next_expiry_date date;
    v_points_expiring_on_next_date numeric;
    v_points_expiry_amount numeric;
    v_points_expiry jsonb;
    v_as_of_date date := (timezone('Asia/Bangkok', now()))::date;
    v_maintain_metric text;
    v_ticket_type_id uuid;
    v_ticket_type_name text;
    v_result jsonb;
    v_tp record;
    v_amount_to_next numeric;
BEGIN
    v_auth_user_id := auth.uid();

    IF v_auth_user_id IS NULL THEN
        RETURN jsonb_build_object('error', 'Not authenticated');
    END IF;

    SELECT ua.id, ua.merchant_id, ua.tier_id, ua.user_type, ua.persona_id
    INTO v_user_id, v_merchant_id, v_current_tier_id, v_user_type, v_persona_id
    FROM user_accounts ua
    WHERE ua.auth_user_id = v_auth_user_id;

    IF v_user_id IS NULL THEN
        RETURN jsonb_build_object('error', 'User account not found');
    END IF;

    SELECT mm.points_expiry_active INTO v_points_expiry_active
    FROM merchant_master mm
    WHERE mm.id = v_merchant_id;

    SELECT * INTO v_cfg
    FROM tier_program_config
    WHERE merchant_id = v_merchant_id AND user_type = v_user_type;

    IF FOUND THEN
        v_upgrade_metric := v_cfg.metric::text;
        v_upgrade_window_months := CASE
            WHEN v_cfg.period_type = 'rolling' THEN v_cfg.rolling_months
            ELSE 12::smallint
        END;
    END IF;

    SELECT
      tp.next_tier_id,
      tp.upgrade_progress_percent,
      tp.upgrade_deadline,
      tp.maintain_metric_needed::text,
      tp.maintain_progress,
      tp.maintain_deadline,
      tp.upgrade_metric_current,
      tp.upgrade_threshold,
      nt.tier_name AS next_tier_name
    INTO v_tp
    FROM tier_progress tp
    LEFT JOIN tier_master nt ON nt.id = tp.next_tier_id
    WHERE tp.user_id = v_user_id
      AND tp.merchant_id = v_merchant_id;

    IF FOUND THEN
      v_next_tier_id := v_tp.next_tier_id;
      v_next_tier_name := v_tp.next_tier_name;
      v_upgrade_progress_percent := v_tp.upgrade_progress_percent;
      v_maintain_metric := v_tp.maintain_metric_needed;
      v_upgrade_threshold := v_tp.upgrade_threshold;
      v_upgrade_progress := v_tp.upgrade_metric_current;

      IF v_next_tier_id IS NOT NULL AND v_upgrade_progress_percent IS NULL THEN
        v_upgrade_progress_percent := 0;
      END IF;

      IF v_upgrade_progress IS NULL
         AND v_upgrade_threshold IS NOT NULL
         AND v_upgrade_progress_percent IS NOT NULL THEN
        v_upgrade_progress := ROUND(v_upgrade_threshold * v_upgrade_progress_percent / 100);
      END IF;

      IF v_upgrade_threshold IS NOT NULL THEN
        v_amount_to_next := GREATEST(0, v_upgrade_threshold - COALESCE(v_upgrade_progress, 0));
      END IF;
    END IF;

    IF v_upgrade_metric = 'ticket' OR v_maintain_metric = 'ticket' THEN
        SELECT tt.id, tt.name
        INTO v_ticket_type_id, v_ticket_type_name
        FROM ticket_type tt
        WHERE tt.merchant_id = v_merchant_id
          AND tt.active = true
          AND tt.is_credit = false
        ORDER BY tt.created_at ASC, tt.name ASC
        LIMIT 1;
    END IF;

    IF public.fn_loyalty_expiry_display_enabled(v_merchant_id) THEN
        v_points_expiry := public.fn_loyalty_expiry_envelope(v_user_id, v_merchant_id, v_as_of_date);
        v_next_expiry_date := NULLIF(v_points_expiry -> 'next' ->> 'expiry_date', '')::date;
        v_points_expiring_on_next_date := COALESCE((v_points_expiry -> 'next' ->> 'amount')::numeric, 0);
        v_points_expiry_amount := COALESCE((v_points_expiry -> 'within_30_days' ->> 'amount')::numeric, 0);
    END IF;

    SELECT jsonb_build_object(
        'id', ua.id,
        'user_id', ua.id,
        'mongo_id', ua.mongo_id,
        'member_code', ua.member_code,
        'fullname', ua.fullname,
        'firstname', ua.firstname,
        'lastname', ua.lastname,
        'email', ua.email,
        'tel', ua.tel,
        'line_id', ua.line_id,
        'image', ua.image,
        'birth_date', ua.birth_date,
        'is_freeze', COALESCE(ua.is_freeze, false),
        'profile_complete', true,
        'persona_id', pm.id,
        'persona_name', pm.persona_name,
        'persona_icon', pm.image,
        'tier_id', tm.id,
        'tier_name', tm.tier_name,
        'tier_icon', tm.icon,
        'tier_color', tm.color,
        'next_tier_id', v_next_tier_id,
        'next_tier_name', v_next_tier_name,
        'points_balance', COALESCE(uw.points_balance, 0),
        'points_expiry_date', v_next_expiry_date,
        'points_expiring_on_next_date', v_points_expiring_on_next_date,
        'points_expiry_amount', v_points_expiry_amount,
        'points_expiry', v_points_expiry,
        'upgrade_metric', v_upgrade_metric,
        'upgrade_metric_label', CASE WHEN v_upgrade_metric = 'ticket' THEN v_ticket_type_name ELSE NULL END,
        'upgrade_ticket_type_id', CASE WHEN v_upgrade_metric = 'ticket' THEN v_ticket_type_id ELSE NULL END,
        'upgrade_progress', v_upgrade_progress,
        'upgrade_progress_percent', v_upgrade_progress_percent,
        'upgrade_threshold', v_upgrade_threshold,
        'upgrade_window_months', v_upgrade_window_months,
        'upgrade_deadline', tp.upgrade_deadline,
        'amount_to_next_tier', v_amount_to_next,
        'maintain_metric', tp.maintain_metric_needed,
        'maintain_metric_label', CASE WHEN tp.maintain_metric_needed::text = 'ticket' THEN v_ticket_type_name ELSE NULL END,
        'maintain_ticket_type_id', CASE WHEN tp.maintain_metric_needed::text = 'ticket' THEN v_ticket_type_id ELSE NULL END,
        'maintain_progress', tp.maintain_progress,
        'maintain_deadline', tp.maintain_deadline,
        'unredeemed_rewards_count', (
            SELECT COUNT(*)::int
            FROM reward_redemptions_ledger rrl
            WHERE rrl.user_id = v_user_id
              AND rrl.merchant_id = v_merchant_id
              AND rrl.redeemed_status = true
              AND rrl.used_status = false
              AND COALESCE(rrl.cancelled, false) = false
        )
    ) INTO v_result
    FROM user_accounts ua
    LEFT JOIN persona_master pm ON pm.id = ua.persona_id
    LEFT JOIN tier_master tm ON tm.id = ua.tier_id
    LEFT JOIN tier_progress tp ON tp.user_id = ua.id AND tp.merchant_id = ua.merchant_id
    LEFT JOIN user_wallet uw ON uw.user_id = ua.id AND uw.merchant_id = ua.merchant_id
    WHERE ua.id = v_user_id;

    RETURN COALESCE(v_result, jsonb_build_object('error', 'Failed to build summary'));
END;
$function$;

-- ---------------------------------------------------------------------------
-- Daily catch-up chunk: expiry predicate + clear cursor when done.
-- ---------------------------------------------------------------------------
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
  v_invalidate boolean := false;
  v_users uuid[];
  v_last uuid;
  v_has_more boolean := false;
  v_custom_tier boolean;
  v_custom_expiry boolean;
BEGIN
  IF p_batch_size IS NULL OR p_batch_size < 1 THEN
    RAISE EXCEPTION 'p_batch_size must be a positive integer';
  END IF;

  v_custom_tier := public.fn_loyalty_is_custom_tier(p_merchant_id);
  v_custom_expiry := public.fn_loyalty_is_custom_expiry(p_merchant_id);

  IF NOT v_custom_tier AND NOT v_custom_expiry THEN
    RETURN jsonb_build_object('skipped', true, 'reason', 'not_custom_merchant');
  END IF;

  INSERT INTO public.system_cron (job_name, merchant_id, status, cursor, updated_at)
  VALUES (v_job, p_merchant_id, 'idle', '{}'::jsonb, now())
  ON CONFLICT (job_name, merchant_id) DO NOTHING;

  SELECT
    NULLIF(sc.cursor->>'after_user_id', '')::uuid,
    COALESCE((sc.cursor->>'invalidate')::boolean, false)
  INTO v_after, v_invalidate
  FROM public.system_cron sc
  WHERE sc.job_name = v_job
    AND sc.merchant_id = p_merchant_id;

  IF v_invalidate THEN
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
  ELSE
    SELECT COALESCE(array_agg(q.id ORDER BY q.id), ARRAY[]::uuid[])
    INTO v_users
    FROM (
      SELECT ua.id
      FROM public.user_accounts ua
      WHERE ua.merchant_id = p_merchant_id
        AND (v_after IS NULL OR ua.id > v_after)
        AND (
          (v_custom_tier AND (
            NOT EXISTS (
              SELECT 1
              FROM public.tier_progress tp
              WHERE tp.user_id = ua.id
                AND tp.merchant_id = p_merchant_id
            )
            OR EXISTS (
              SELECT 1
              FROM public.tier_progress tp
              WHERE tp.user_id = ua.id
                AND tp.merchant_id = p_merchant_id
                AND tp.upgrade_progress_percent IS NULL
                AND tp.next_tier_id IS NOT NULL
            )
          ))
          OR (v_custom_expiry AND NOT EXISTS (
              SELECT 1
              FROM public.user_points_expiry_cache c
              WHERE c.user_id = ua.id
                AND c.merchant_id = p_merchant_id
            )
            AND public.fn_loyalty_user_has_unexpired_point_earns(ua.id, p_merchant_id)
          )
        )
      ORDER BY ua.id
      LIMIT p_batch_size
    ) q;
  END IF;

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
      'backlog_complete', true,
      'invalidate', false
    );
  END IF;

  v_last := v_users[cardinality(v_users)];
  PERFORM public.fn_loyalty_cache_refresh_users(p_merchant_id, v_users, p_as_of_date);

  IF v_invalidate THEN
    SELECT EXISTS (
      SELECT 1
      FROM public.user_accounts ua
      WHERE ua.merchant_id = p_merchant_id
        AND ua.id > v_last
    ) INTO v_has_more;
  ELSE
    SELECT EXISTS (
      SELECT 1
      FROM public.user_accounts ua
      WHERE ua.merchant_id = p_merchant_id
        AND ua.id > v_last
        AND (
          (v_custom_tier AND (
            NOT EXISTS (
              SELECT 1
              FROM public.tier_progress tp
              WHERE tp.user_id = ua.id
                AND tp.merchant_id = p_merchant_id
            )
            OR EXISTS (
              SELECT 1
              FROM public.tier_progress tp
              WHERE tp.user_id = ua.id
                AND tp.merchant_id = p_merchant_id
                AND tp.upgrade_progress_percent IS NULL
                AND tp.next_tier_id IS NOT NULL
            )
          ))
          OR (v_custom_expiry AND NOT EXISTS (
              SELECT 1
              FROM public.user_points_expiry_cache c
              WHERE c.user_id = ua.id
                AND c.merchant_id = p_merchant_id
            )
            AND public.fn_loyalty_user_has_unexpired_point_earns(ua.id, p_merchant_id)
          )
        )
    ) INTO v_has_more;
  END IF;

  UPDATE public.system_cron
  SET cursor = CASE
        WHEN v_has_more THEN jsonb_build_object(
          'after_user_id', v_last,
          'invalidate', v_invalidate
        )
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
    'backlog_complete', NOT v_has_more,
    'invalidate', CASE WHEN v_invalidate AND NOT v_has_more THEN false ELSE v_invalidate END
  );
END;
$function$;

-- Backfill display columns for existing cache rows (until next cron refresh).
UPDATE public.tier_progress AS tp
SET
  upgrade_threshold = COALESCE(tp.upgrade_threshold, sub.upgrade_amount),
  upgrade_metric_current = COALESCE(
    tp.upgrade_metric_current,
    CASE
      WHEN tp.upgrade_progress_percent IS NOT NULL
        AND COALESCE(sub.upgrade_amount, 0) > 0
        THEN ROUND(sub.upgrade_amount * tp.upgrade_progress_percent / 100.0)
      ELSE 0
    END
  )
FROM (
  SELECT
    tp2.id,
    ladder.upgrade_amount
  FROM public.tier_progress tp2
  LEFT JOIN LATERAL (
    SELECT l.upgrade_amount
    FROM public.fn_tier_ladder_for_user(tp2.user_id, tp2.merchant_id) l
    WHERE l.tier_id = tp2.next_tier_id
    LIMIT 1
  ) ladder ON tp2.next_tier_id IS NOT NULL
  WHERE tp2.next_tier_id IS NOT NULL
    AND (tp2.upgrade_metric_current IS NULL OR tp2.upgrade_threshold IS NULL)
) AS sub
WHERE tp.id = sub.id;

-- Clear stale in-progress cursors from prior expiry walks.
UPDATE public.system_cron
SET cursor = '{}'::jsonb,
    status = 'idle',
    updated_at = now()
WHERE job_name = 'loyalty_cache_daily_catchup'
  AND NULLIF(cursor->>'after_user_id', '') IS NOT NULL;
