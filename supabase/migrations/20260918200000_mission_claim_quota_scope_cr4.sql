-- CR4: expose binding claim-limit scope for member exhausted toast (Total vs Per user).
-- Also deployed on wkevmsedchftztoolkmi: bff_get_mission_detail (progress.claim_limit_scope),
-- bff_claim_mission (claim_limit_* on claim_limit_exceeded). Full bodies: _cr4_bff_patches.sql.

CREATE OR REPLACE FUNCTION public.fn_mission_claim_quota(p_user_id uuid, p_mission_id uuid, p_unclaimed integer)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE
AS $function$
DECLARE
  v_limit RECORD;
  v_count INTEGER;
  v_merchant_id uuid;
  v_tz text;
  v_window_start timestamptz;
  v_scope text;
  v_headroom integer;
  v_min_headroom integer := NULL;
  v_binding_time_unit text := NULL;
  v_binding_max integer := NULL;
  v_binding_scope text := NULL;
  v_binding_limit_id uuid := NULL;
  v_replace_binding boolean;
  v_claimable integer;
BEGIN
  IF NOT EXISTS (SELECT 1 FROM mission_limit_claim WHERE mission_id = p_mission_id) THEN
    RETURN jsonb_build_object(
      'claimable_now', GREATEST(0, COALESCE(p_unclaimed, 0)),
      'claim_limit_time_unit', NULL,
      'claim_limit_max', NULL,
      'claim_limit_scope', NULL
    );
  END IF;

  SELECT merchant_id INTO v_merchant_id FROM mission WHERE id = p_mission_id;
  v_tz := fn_mission_merchant_tz(v_merchant_id);

  FOR v_limit IN
    SELECT * FROM mission_limit_claim WHERE mission_id = p_mission_id
  LOOP
    v_scope := v_limit.scope::text;

    IF v_scope IN ('user_store', 'store') THEN
      RETURN jsonb_build_object(
        'claimable_now', 0,
        'claim_limit_time_unit', v_limit.time_unit::text,
        'claim_limit_max', v_limit.amount,
        'claim_limit_scope', v_scope
      );
    END IF;

    v_window_start := fn_mission_calendar_boundary_start(
      v_limit.time_unit::text,
      now(),
      v_tz,
      COALESCE(v_limit.time_value, 1)
    );

    IF v_scope = 'user' THEN
      SELECT COUNT(*) INTO v_count
      FROM mission_log_completion
      WHERE mission_id = p_mission_id
        AND user_id = p_user_id
        AND is_claimed = true
        AND (v_window_start = '-infinity'::timestamptz OR claimed_at >= v_window_start);
    ELSE
      SELECT COUNT(*) INTO v_count
      FROM mission_log_completion
      WHERE mission_id = p_mission_id
        AND is_claimed = true
        AND (v_window_start = '-infinity'::timestamptz OR claimed_at >= v_window_start);
    END IF;

    v_headroom := GREATEST(0, v_limit.amount - v_count);

    v_replace_binding := false;
    IF v_min_headroom IS NULL THEN
      v_replace_binding := true;
    ELSIF v_headroom < v_min_headroom THEN
      v_replace_binding := true;
    ELSIF v_headroom = v_min_headroom THEN
      IF v_scope = 'user' AND COALESCE(v_binding_scope, '') <> 'user' THEN
        v_replace_binding := true;
      ELSIF v_scope <> 'user' AND v_binding_scope = 'user' THEN
        v_replace_binding := false;
      ELSIF v_limit.amount < v_binding_max THEN
        v_replace_binding := true;
      ELSIF v_limit.amount = v_binding_max AND v_limit.id < v_binding_limit_id THEN
        v_replace_binding := true;
      END IF;
    END IF;

    IF v_replace_binding THEN
      v_min_headroom := v_headroom;
      v_binding_time_unit := v_limit.time_unit::text;
      v_binding_max := v_limit.amount;
      v_binding_scope := v_scope;
      v_binding_limit_id := v_limit.id;
    END IF;
  END LOOP;

  v_claimable := fn_check_claim_limits(
    p_user_id,
    p_mission_id,
    GREATEST(0, COALESCE(p_unclaimed, 0))
  );

  RETURN jsonb_build_object(
    'claimable_now', GREATEST(0, v_claimable),
    'claim_limit_time_unit', v_binding_time_unit,
    'claim_limit_max', v_binding_max,
    'claim_limit_scope', v_binding_scope
  );
END;
$function$;
