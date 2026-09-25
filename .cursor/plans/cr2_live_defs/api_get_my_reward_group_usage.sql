CREATE OR REPLACE FUNCTION public.api_get_my_reward_group_usage()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
DECLARE
  v_merchant_id        UUID;
  v_user_id            UUID;
  v_rows               JSONB := '[]'::jsonb;

  -- per-group loop
  v_group              RECORD;
  v_sibling_ids        UUID[];
  v_redeemed_ids       UUID[];
  v_limits_arr         JSONB;

  -- per-limit inner loop
  v_limit              RECORD;
  v_limit_window_start TIMESTAMPTZ;
  v_current_usage      NUMERIC;
  v_limit_rows         JSONB;
BEGIN
  v_merchant_id := get_current_merchant_id();
  IF v_merchant_id IS NULL THEN
    RAISE EXCEPTION 'No merchant context found';
  END IF;

  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'No authenticated user found';
  END IF;

  -- Iterate every active reward group that has at least one distinct_reward limit
  FOR v_group IN
    SELECT DISTINCT
      rg.id          AS group_id,
      rg.name        AS group_name,
      rg.is_featured AS is_featured
    FROM reward_group rg
    JOIN transaction_limits tl
      ON tl.entity_id    = rg.id
     AND tl.entity_type  = 'reward_group'
     AND tl.merchant_id  = v_merchant_id
     AND tl.metric       = 'distinct_reward'
     AND tl.scope        = 'user'
     AND tl.active_status = true
    WHERE rg.merchant_id = v_merchant_id
      AND rg.is_active   = true
  LOOP
    -- All reward IDs that belong to this group
    SELECT ARRAY_AGG(rm.id) INTO v_sibling_ids
    FROM reward_master rm
    WHERE rm.merchant_id        = v_merchant_id
      AND rm.reward_group_ids  @> ARRAY[v_group.group_id];

    IF v_sibling_ids IS NULL OR array_length(v_sibling_ids, 1) IS NULL THEN
      v_redeemed_ids := ARRAY[]::UUID[];
    ELSE
      -- Collect distinct reward IDs the user has redeemed across all limits' windows.
      -- We use all_time as the widest window here; per-limit current_usage below uses each limit's own window.
      SELECT ARRAY_AGG(DISTINCT reward_id) INTO v_redeemed_ids
      FROM reward_redemptions_ledger
      WHERE user_id         = v_user_id
        AND reward_id       = ANY(v_sibling_ids)
        AND redeemed_status = true
        AND (cancelled IS NOT TRUE)
        AND (source_type IS NULL OR source_type NOT IN ('package_assignment', 'persona_entitlement'));
    END IF;

    -- Build per-limit usage rows for this group
    v_limit_rows := '[]'::jsonb;

    FOR v_limit IN
      SELECT
        tl.id            AS limit_id,
        tl.count         AS limit_count,
        tl.time_unit,
        tl.window_start  AS limit_window_start,
        tl.window_end    AS limit_window_end,
        tl.metric
      FROM transaction_limits tl
      WHERE tl.entity_id    = v_group.group_id
        AND tl.entity_type  = 'reward_group'
        AND tl.merchant_id  = v_merchant_id
        AND tl.metric       = 'distinct_reward'
        AND tl.scope        = 'user'
        AND tl.active_status = true
        AND (tl.window_start IS NULL OR CURRENT_TIMESTAMP >= tl.window_start)
        AND (tl.window_end   IS NULL OR CURRENT_TIMESTAMP <= tl.window_end)
    LOOP
      -- Rolling window floor (same logic as fn_check_reward_group_limits)
      v_limit_window_start := CASE v_limit.time_unit
        WHEN 'day'      THEN date_trunc('day',   CURRENT_TIMESTAMP)
        WHEN 'week'     THEN date_trunc('week',  CURRENT_TIMESTAMP)
        WHEN 'month'    THEN date_trunc('month', CURRENT_TIMESTAMP)
        WHEN 'year'     THEN date_trunc('year',  CURRENT_TIMESTAMP)
        WHEN 'all_time' THEN NULL
        ELSE NULL
      END;

      IF v_limit.limit_window_start IS NOT NULL AND v_limit_window_start IS NOT NULL THEN
        v_limit_window_start := GREATEST(v_limit_window_start, v_limit.limit_window_start);
      ELSIF v_limit.limit_window_start IS NOT NULL THEN
        v_limit_window_start := v_limit.limit_window_start;
      END IF;

      IF v_sibling_ids IS NULL OR array_length(v_sibling_ids, 1) IS NULL THEN
        v_current_usage := 0;
      ELSE
        SELECT COUNT(DISTINCT reward_id) INTO v_current_usage
        FROM reward_redemptions_ledger
        WHERE user_id         = v_user_id
          AND reward_id       = ANY(v_sibling_ids)
          AND redeemed_status = true
          AND (cancelled IS NOT TRUE)
          AND (source_type IS NULL OR source_type NOT IN ('package_assignment', 'persona_entitlement'))
          AND (v_limit_window_start IS NULL OR created_at >= v_limit_window_start);
      END IF;

      v_limit_rows := v_limit_rows || jsonb_build_array(
        jsonb_build_object(
          'metric',        v_limit.metric::text,
          'count',         v_limit.limit_count,
          'time_unit',     v_limit.time_unit::text,
          'current_usage', v_current_usage,
          'remaining',     GREATEST(v_limit.limit_count - v_current_usage, 0)
        )
      );
    END LOOP;

    v_rows := v_rows || jsonb_build_array(
      jsonb_build_object(
        'group_id',           v_group.group_id,
        'group_name',         v_group.group_name,
        'is_featured',        v_group.is_featured,
        'limits',             v_limit_rows,
        'redeemed_reward_ids', COALESCE(v_redeemed_ids, ARRAY[]::UUID[])
      )
    );
  END LOOP;

  RETURN v_rows;
END;
$function$
