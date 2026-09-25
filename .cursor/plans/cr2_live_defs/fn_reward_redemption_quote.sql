CREATE OR REPLACE FUNCTION public.fn_reward_redemption_quote(p_user_id uuid, p_reward_id uuid, p_merchant_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_user public.user_accounts;
  v_reward public.reward_master;
  v_user_tag_ids uuid[];
  v_points_calc jsonb;
  v_points_per_unit numeric := 0;
  v_balance numeric := 0;
  v_hard_cap integer := 1000;
  v_max_selectable integer := 1000;
  v_can_redeem boolean := true;
  v_quantity_binding text := 'unlimited';
  v_blocking_reason text;
  v_redeem_limit jsonb;
  v_available jsonb;
  v_limit record;
  v_limit_window timestamptz;
  v_limit_count numeric;
  v_remaining numeric;
  v_pool_remaining numeric;
  v_pool_time_unit text;
  v_has_pool boolean := false;
  v_group_ids uuid[];
  v_group_id uuid;
  v_sibling_ids uuid[];
  v_group_check jsonb;
  v_promo_remaining integer;
  v_stock_remaining numeric;
  v_points_cap integer;
  v_tightest_user_remaining numeric;
  v_tightest_user_used numeric;
  v_tightest_user_cap numeric;
  v_tightest_user_time_unit text;
BEGIN
  IF p_user_id IS NULL OR p_reward_id IS NULL OR p_merchant_id IS NULL THEN
    RETURN jsonb_build_object(
      'max_selectable_quantity', 0,
      'can_redeem', false,
      'quantity_binding_reason', 'hard_cap',
      'blocking_reason', 'ineligible',
      'points_per_unit', 0,
      'qty_hard_cap', v_hard_cap
    );
  END IF;

  SELECT * INTO v_user
  FROM public.user_accounts
  WHERE id = p_user_id AND merchant_id = p_merchant_id;

  SELECT * INTO v_reward
  FROM public.reward_master
  WHERE id = p_reward_id AND merchant_id = p_merchant_id;

  IF v_user.id IS NULL OR v_reward.id IS NULL THEN
    RETURN jsonb_build_object(
      'max_selectable_quantity', 0,
      'can_redeem', false,
      'quantity_binding_reason', 'hard_cap',
      'blocking_reason', 'ineligible',
      'points_per_unit', 0,
      'qty_hard_cap', v_hard_cap
    );
  END IF;

  SELECT ARRAY_AGG(tag_id) INTO v_user_tag_ids FROM public.user_tags WHERE user_id = p_user_id;

  IF public.fn_merchant_shopify_feature_enabled(p_merchant_id, 'reward', 'reward.tier_reward_eligibility')
     AND v_reward.allowed_tier IS NOT NULL AND array_length(v_reward.allowed_tier, 1) > 0 THEN
    IF v_user.tier_id IS NULL OR NOT (v_user.tier_id = ANY(v_reward.allowed_tier)) THEN
      v_can_redeem := false;
      v_blocking_reason := 'ineligible';
    END IF;
  END IF;

  IF v_blocking_reason IS NULL AND v_reward.allowed_persona IS NOT NULL AND array_length(v_reward.allowed_persona, 1) > 0 THEN
    IF v_user.persona_id IS NULL OR NOT (v_user.persona_id = ANY(v_reward.allowed_persona)) THEN
      v_can_redeem := false;
      v_blocking_reason := 'ineligible';
    END IF;
  END IF;

  IF v_blocking_reason IS NULL AND v_reward.allowed_tags IS NOT NULL AND array_length(v_reward.allowed_tags, 1) > 0 THEN
    IF v_user_tag_ids IS NULL OR NOT (v_reward.allowed_tags && v_user_tag_ids) THEN
      v_can_redeem := false;
      v_blocking_reason := 'ineligible';
    END IF;
  END IF;

  IF v_blocking_reason IS NULL AND v_reward.allowed_birthmonth IS NOT NULL AND array_length(v_reward.allowed_birthmonth, 1) > 0 THEN
    IF EXTRACT(MONTH FROM v_user.birth_date)::INT::TEXT IS NULL
       OR NOT (EXTRACT(MONTH FROM v_user.birth_date)::INT::TEXT = ANY(v_reward.allowed_birthmonth)) THEN
      v_can_redeem := false;
      v_blocking_reason := 'ineligible';
    END IF;
  END IF;

  IF v_blocking_reason IS NULL AND v_reward.redeem_window_start IS NOT NULL AND CURRENT_TIMESTAMP < v_reward.redeem_window_start THEN
    v_can_redeem := false;
    v_blocking_reason := 'ineligible';
  END IF;

  IF v_blocking_reason IS NULL AND v_reward.redeem_window_end IS NOT NULL AND CURRENT_TIMESTAMP > v_reward.redeem_window_end THEN
    v_can_redeem := false;
    v_blocking_reason := 'ineligible';
  END IF;

  v_points_calc := public.calculate_redemption_points_fast(
    v_user.tier_id, v_user.user_type, v_user.persona_id, v_user_tag_ids,
    p_reward_id, v_reward.fallback_points, v_reward.require_points_match
  );

  IF NOT COALESCE((v_points_calc->>'success')::boolean, false) THEN
    v_can_redeem := false;
    v_blocking_reason := COALESCE(v_blocking_reason, 'ineligible');
  ELSE
    v_points_per_unit := COALESCE((v_points_calc->>'points_required')::numeric, 0);
    IF COALESCE(v_reward.require_points_match, false)
       AND COALESCE(v_points_calc->>'match_type', '') = 'blocked' THEN
      v_can_redeem := false;
      v_blocking_reason := COALESCE(v_blocking_reason, 'points_match_blocked');
    END IF;
  END IF;

  IF v_blocking_reason IN ('ineligible', 'points_match_blocked') THEN
    RETURN jsonb_build_object(
      'max_selectable_quantity', 0,
      'can_redeem', false,
      'quantity_binding_reason', 'hard_cap',
      'blocking_reason', v_blocking_reason,
      'points_per_unit', COALESCE(v_points_per_unit, 0),
      'qty_hard_cap', v_hard_cap
    );
  END IF;

  SELECT COALESCE(points_balance, 0) INTO v_balance
  FROM public.user_wallet
  WHERE user_id = p_user_id AND merchant_id = p_merchant_id;
  v_balance := COALESCE(v_balance, 0);

  v_tightest_user_remaining := NULL;

  FOR v_limit IN
    SELECT * FROM public.transaction_limits
    WHERE entity_id = p_reward_id
      AND entity_type = 'reward'
      AND merchant_id = p_merchant_id
      AND active_status = true
      AND metric = 'quantity'
      AND scope = 'user'
  LOOP
    v_limit_window := public.fn_transaction_limit_effective_window(v_limit.time_unit::text, v_limit.window_start, v_limit.window_end);
    IF v_limit_window IS NULL AND v_limit.window_start IS NOT NULL AND CURRENT_TIMESTAMP < v_limit.window_start THEN
      CONTINUE;
    END IF;
    IF v_limit.window_end IS NOT NULL AND CURRENT_TIMESTAMP > v_limit.window_end THEN
      CONTINUE;
    END IF;

    SELECT COALESCE(SUM(qty), 0) INTO v_limit_count
    FROM public.reward_redemptions_ledger
    WHERE user_id = p_user_id
      AND reward_id = p_reward_id
      AND redeemed_status = true
      AND (cancelled IS NOT TRUE)
      AND (source_type IS NULL OR source_type NOT IN ('package_assignment', 'persona_entitlement'))
      AND (v_limit_window IS NULL OR created_at >= v_limit_window);

    v_remaining := GREATEST(v_limit.count - v_limit_count, 0);
    IF v_tightest_user_remaining IS NULL OR v_remaining < v_tightest_user_remaining THEN
      v_tightest_user_remaining := v_remaining;
      v_tightest_user_used := v_limit_count;
      v_tightest_user_cap := v_limit.count;
      v_tightest_user_time_unit := v_limit.time_unit::text;
    END IF;
    v_max_selectable := LEAST(v_max_selectable, v_remaining::integer);
    v_quantity_binding := 'reward_quota';
  END LOOP;

  IF v_tightest_user_remaining IS NOT NULL THEN
    v_redeem_limit := jsonb_build_object(
      'used', v_tightest_user_used,
      'cap', v_tightest_user_cap,
      'time_unit', v_tightest_user_time_unit
    );
  END IF;

  v_pool_remaining := NULL;

  FOR v_limit IN
    SELECT * FROM public.transaction_limits
    WHERE entity_id = p_reward_id
      AND entity_type = 'reward'
      AND merchant_id = p_merchant_id
      AND active_status = true
      AND metric = 'quantity'
      AND scope = 'total'
  LOOP
    v_limit_window := public.fn_transaction_limit_effective_window(v_limit.time_unit::text, v_limit.window_start, v_limit.window_end);
    IF v_limit_window IS NULL AND v_limit.window_start IS NOT NULL AND CURRENT_TIMESTAMP < v_limit.window_start THEN
      CONTINUE;
    END IF;
    IF v_limit.window_end IS NOT NULL AND CURRENT_TIMESTAMP > v_limit.window_end THEN
      CONTINUE;
    END IF;

    SELECT COALESCE(SUM(qty), 0) INTO v_limit_count
    FROM public.reward_redemptions_ledger
    WHERE reward_id = p_reward_id
      AND merchant_id = p_merchant_id
      AND redeemed_status = true
      AND (cancelled IS NOT TRUE)
      AND (v_limit_window IS NULL OR created_at >= v_limit_window);

    v_remaining := GREATEST(v_limit.count - v_limit_count, 0);
    v_has_pool := true;
    IF v_pool_remaining IS NULL OR v_remaining < v_pool_remaining THEN
      v_pool_remaining := v_remaining;
      v_pool_time_unit := v_limit.time_unit::text;
    END IF;
    v_max_selectable := LEAST(v_max_selectable, v_remaining::integer);
    IF v_quantity_binding = 'unlimited' THEN
      v_quantity_binding := 'group_quantity';
    END IF;
  END LOOP;

  v_group_ids := v_reward.reward_group_ids;

  IF v_group_ids IS NOT NULL THEN
    FOREACH v_group_id IN ARRAY v_group_ids LOOP
      IF NOT EXISTS (
        SELECT 1 FROM public.reward_group rg
        WHERE rg.id = v_group_id AND rg.merchant_id = p_merchant_id AND rg.is_active = true
      ) THEN
        CONTINUE;
      END IF;

      SELECT ARRAY_AGG(rm.id) INTO v_sibling_ids
      FROM public.reward_master rm
      WHERE rm.merchant_id = p_merchant_id
        AND rm.reward_group_ids @> ARRAY[v_group_id];

      FOR v_limit IN
        SELECT * FROM public.transaction_limits
        WHERE entity_id = v_group_id
          AND entity_type = 'reward_group'
          AND merchant_id = p_merchant_id
          AND active_status = true
          AND metric = 'quantity'
      LOOP
        v_limit_window := public.fn_transaction_limit_effective_window(v_limit.time_unit::text, v_limit.window_start, v_limit.window_end);
        IF v_limit_window IS NULL AND v_limit.window_start IS NOT NULL AND CURRENT_TIMESTAMP < v_limit.window_start THEN
          CONTINUE;
        END IF;
        IF v_limit.window_end IS NOT NULL AND CURRENT_TIMESTAMP > v_limit.window_end THEN
          CONTINUE;
        END IF;

        IF v_limit.scope = 'user' THEN
          SELECT COALESCE(SUM(qty), 0) INTO v_limit_count
          FROM public.reward_redemptions_ledger
          WHERE user_id = p_user_id
            AND reward_id = ANY(v_sibling_ids)
            AND redeemed_status = true
            AND (cancelled IS NOT TRUE)
            AND (source_type IS NULL OR source_type NOT IN ('package_assignment', 'persona_entitlement'))
            AND (v_limit_window IS NULL OR created_at >= v_limit_window);
        ELSE
          SELECT COALESCE(SUM(qty), 0) INTO v_limit_count
          FROM public.reward_redemptions_ledger
          WHERE reward_id = ANY(v_sibling_ids)
            AND merchant_id = p_merchant_id
            AND redeemed_status = true
            AND (cancelled IS NOT TRUE)
            AND (v_limit_window IS NULL OR created_at >= v_limit_window);
        END IF;

        v_remaining := GREATEST(v_limit.count - v_limit_count, 0);

        IF v_limit.scope = 'user' THEN
          IF v_tightest_user_remaining IS NULL OR v_remaining < v_tightest_user_remaining THEN
            v_tightest_user_remaining := v_remaining;
            v_tightest_user_used := v_limit_count;
            v_tightest_user_cap := v_limit.count;
            v_tightest_user_time_unit := v_limit.time_unit::text;
          END IF;
          v_max_selectable := LEAST(v_max_selectable, v_remaining::integer);
          v_quantity_binding := 'reward_quota';
          IF v_redeem_limit IS NULL OR v_remaining < (v_redeem_limit->>'cap')::numeric - (v_redeem_limit->>'used')::numeric THEN
            v_redeem_limit := jsonb_build_object(
              'used', v_limit_count,
              'cap', v_limit.count,
              'time_unit', v_limit.time_unit::text
            );
          END IF;
        ELSE
          v_has_pool := true;
          IF v_pool_remaining IS NULL OR v_remaining < v_pool_remaining THEN
            v_pool_remaining := v_remaining;
            v_pool_time_unit := v_limit.time_unit::text;
          END IF;
          v_max_selectable := LEAST(v_max_selectable, v_remaining::integer);
          v_quantity_binding := 'group_quantity';
        END IF;
      END LOOP;
    END LOOP;
  END IF;

  IF v_reward.stock_control AND NOT v_reward.assign_promocode AND v_reward.stock_total IS NOT NULL THEN
    SELECT COALESCE(SUM(qty), 0) INTO v_limit_count
    FROM public.reward_redemptions_ledger
    WHERE reward_id = p_reward_id
      AND merchant_id = p_merchant_id
      AND redeemed_status = true
      AND (cancelled IS NOT TRUE);

    v_stock_remaining := GREATEST(v_reward.stock_total - v_limit_count, 0);
    v_has_pool := true;
    IF v_pool_remaining IS NULL OR v_stock_remaining < v_pool_remaining THEN
      v_pool_remaining := v_stock_remaining;
      v_pool_time_unit := NULL;
    END IF;
    v_max_selectable := LEAST(v_max_selectable, v_stock_remaining::integer);
    IF v_stock_remaining <= 0 THEN
      v_quantity_binding := 'sold_out';
    END IF;
  END IF;

  IF v_reward.assign_promocode THEN
    SELECT COUNT(*)::integer INTO v_promo_remaining
    FROM public.reward_promo_code
    WHERE reward_id = p_reward_id
      AND merchant_id = p_merchant_id
      AND redeemed_status = false;

    v_has_pool := true;
    IF v_pool_remaining IS NULL OR v_promo_remaining < v_pool_remaining THEN
      v_pool_remaining := v_promo_remaining;
      v_pool_time_unit := NULL;
    END IF;
    v_max_selectable := LEAST(v_max_selectable, v_promo_remaining);
    v_quantity_binding := CASE WHEN v_promo_remaining <= 0 THEN 'sold_out' ELSE 'promo_codes' END;
  END IF;

  IF v_points_per_unit > 0 THEN
    v_points_cap := FLOOR(v_balance / v_points_per_unit)::integer;
    v_max_selectable := LEAST(v_max_selectable, GREATEST(v_points_cap, 0));
    IF v_points_cap < v_max_selectable AND v_quantity_binding = 'unlimited' THEN
      v_quantity_binding := 'points';
    END IF;
    IF v_balance < v_points_per_unit THEN
      v_can_redeem := false;
      v_blocking_reason := COALESCE(v_blocking_reason, 'insufficient_points');
    END IF;
  END IF;

  v_max_selectable := LEAST(v_max_selectable, v_hard_cap);
  IF v_max_selectable < v_hard_cap AND v_quantity_binding = 'unlimited' THEN
    v_quantity_binding := 'hard_cap';
  END IF;

  IF v_max_selectable < 1 THEN
    v_can_redeem := false;
    v_blocking_reason := COALESCE(v_blocking_reason, 'sold_out');
  END IF;

  v_group_check := public.fn_check_reward_group_limits(p_user_id, p_reward_id, 1, p_merchant_id);
  IF NOT COALESCE((v_group_check->>'allowed')::boolean, true)
     AND COALESCE(v_group_check->>'metric', '') = 'distinct_reward' THEN
    v_can_redeem := false;
    v_blocking_reason := 'group_distinct';
  END IF;

  IF v_has_pool AND v_pool_remaining IS NOT NULL THEN
    v_available := jsonb_build_object(
      'qty', GREATEST(v_pool_remaining, 0),
      'time_unit', v_pool_time_unit
    );
    IF v_pool_remaining <= 0 THEN
      v_can_redeem := false;
      v_blocking_reason := COALESCE(v_blocking_reason, 'sold_out');
    END IF;
  END IF;

  IF v_redeem_limit IS NOT NULL AND v_tightest_user_remaining IS NOT NULL THEN
    v_redeem_limit := jsonb_build_object(
      'used', v_tightest_user_used,
      'cap', v_tightest_user_cap,
      'time_unit', v_tightest_user_time_unit
    );
  END IF;

  RETURN jsonb_build_object(
    'max_selectable_quantity', GREATEST(v_max_selectable, 0),
    'can_redeem', v_can_redeem,
    'quantity_binding_reason', v_quantity_binding,
    'blocking_reason', v_blocking_reason,
    'redeem_limit', v_redeem_limit,
    'available', v_available,
    'points_per_unit', COALESCE(v_points_per_unit, 0),
    'qty_hard_cap', v_hard_cap
  );
END;
$function$
