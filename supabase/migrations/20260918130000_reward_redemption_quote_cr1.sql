-- CR 1: shared reward redemption quote + member/admin BFF wrappers.
-- Also: redeem_reward_with_points — hard cap 1–1000, promo multi-quantity (append patched body below).

CREATE OR REPLACE FUNCTION public.fn_transaction_limit_effective_window(
  p_time_unit text,
  p_window_start timestamptz,
  p_window_end timestamptz
) RETURNS timestamptz
LANGUAGE plpgsql
IMMUTABLE
AS $function$
DECLARE
  v_limit_window_start timestamptz;
BEGIN
  IF p_window_end IS NOT NULL AND CURRENT_TIMESTAMP > p_window_end THEN
    RETURN NULL;
  END IF;
  IF p_window_start IS NOT NULL AND CURRENT_TIMESTAMP < p_window_start THEN
    RETURN NULL;
  END IF;

  v_limit_window_start := CASE p_time_unit
    WHEN 'day' THEN date_trunc('day', CURRENT_TIMESTAMP)
    WHEN 'week' THEN date_trunc('week', CURRENT_TIMESTAMP)
    WHEN 'month' THEN date_trunc('month', CURRENT_TIMESTAMP)
    WHEN 'year' THEN date_trunc('year', CURRENT_TIMESTAMP)
    WHEN 'all_time' THEN NULL
    ELSE NULL
  END;

  IF p_window_start IS NOT NULL AND v_limit_window_start IS NOT NULL THEN
    v_limit_window_start := GREATEST(v_limit_window_start, p_window_start);
  ELSIF p_window_start IS NOT NULL THEN
    v_limit_window_start := p_window_start;
  END IF;

  RETURN v_limit_window_start;
END;
$function$;

CREATE OR REPLACE FUNCTION public.fn_reward_redemption_quote(
  p_user_id uuid,
  p_reward_id uuid,
  p_merchant_id uuid
) RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
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
$function$;

REVOKE ALL ON FUNCTION public.fn_reward_redemption_quote(uuid, uuid, uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.fn_reward_redemption_quote(uuid, uuid, uuid) TO postgres, service_role;

CREATE OR REPLACE FUNCTION public.bff_user_get_reward_redemption_quote(p_reward_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_auth_uid uuid;
  v_user_id uuid;
  v_merchant_id uuid;
  v_quote jsonb;
BEGIN
  IF p_reward_id IS NULL THEN
    RETURN jsonb_build_object('success', false, 'code', 'VALIDATION_ERROR', 'error', 'reward_id is required');
  END IF;

  v_auth_uid := public.get_current_user_id();
  IF v_auth_uid IS NULL THEN
    RETURN jsonb_build_object('success', false, 'code', 'UNAUTHENTICATED', 'error', 'No authenticated user context');
  END IF;

  SELECT ua.id, ua.merchant_id
  INTO v_user_id, v_merchant_id
  FROM public.user_accounts ua
  WHERE ua.deleted_at IS NULL
    AND ua.is_active IS NOT FALSE
    AND (ua.auth_user_id = v_auth_uid OR ua.id = v_auth_uid)
  LIMIT 1;

  IF v_user_id IS NULL THEN
    RETURN jsonb_build_object('success', false, 'code', 'USER_NOT_FOUND', 'error', 'No user account linked');
  END IF;

  v_quote := public.fn_reward_redemption_quote(v_user_id, p_reward_id, v_merchant_id);
  RETURN jsonb_build_object('success', true, 'data', v_quote);
EXCEPTION WHEN OTHERS THEN
  RETURN jsonb_build_object('success', false, 'code', 'INTERNAL_ERROR', 'error', SQLERRM);
END;
$function$;

CREATE OR REPLACE FUNCTION public.bff_get_reward_redemption_quote(p_user_id uuid, p_reward_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_merchant_id uuid;
  v_is_admin boolean := false;
  v_quote jsonb;
BEGIN
  IF p_user_id IS NULL OR p_reward_id IS NULL THEN
    RETURN jsonb_build_object('success', false, 'code', 'VALIDATION_ERROR', 'error', 'user_id and reward_id are required');
  END IF;

  v_merchant_id := public.get_current_merchant_id();
  IF v_merchant_id IS NULL THEN
    RETURN jsonb_build_object('success', false, 'code', 'NO_MERCHANT', 'error', 'Merchant context required');
  END IF;

  SELECT EXISTS (
    SELECT 1 FROM public.admin_users au
    WHERE au.auth_user_id = auth.uid()
      AND au.merchant_id = v_merchant_id
      AND au.active_status = true
  ) INTO v_is_admin;

  IF NOT v_is_admin THEN
    RETURN jsonb_build_object('success', false, 'code', 'FORBIDDEN', 'error', 'Admin access required');
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM public.user_accounts ua
    WHERE ua.id = p_user_id AND ua.merchant_id = v_merchant_id
  ) THEN
    RETURN jsonb_build_object('success', false, 'code', 'USER_NOT_FOUND', 'error', 'User not found for merchant');
  END IF;

  v_quote := public.fn_reward_redemption_quote(p_user_id, p_reward_id, v_merchant_id);
  RETURN jsonb_build_object('success', true, 'data', v_quote);
EXCEPTION WHEN OTHERS THEN
  RETURN jsonb_build_object('success', false, 'code', 'INTERNAL_ERROR', 'error', SQLERRM);
END;
$function$;

REVOKE ALL ON FUNCTION public.bff_user_get_reward_redemption_quote(uuid) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.bff_get_reward_redemption_quote(uuid, uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.bff_user_get_reward_redemption_quote(uuid) TO postgres, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.bff_get_reward_redemption_quote(uuid, uuid) TO postgres, authenticated, service_role;

COMMENT ON FUNCTION public.fn_reward_redemption_quote(uuid, uuid, uuid) IS
  'Internal redemption quote: max selectable quantity, can_redeem, limit/available display fields.';
COMMENT ON FUNCTION public.bff_user_get_reward_redemption_quote(uuid) IS
  'Member JWT wrapper around fn_reward_redemption_quote for reward detail stepper.';
COMMENT ON FUNCTION public.bff_get_reward_redemption_quote(uuid, uuid) IS
  'Admin wrapper around fn_reward_redemption_quote (Front Line CR 5).';


-- Patched redeem_reward_with_points (qty 1–1000, promo multi-qty)

CREATE OR REPLACE FUNCTION public.redeem_reward_with_points(p_reward_id uuid, p_quantity integer DEFAULT 1, p_user_id uuid DEFAULT NULL::uuid, p_merchant_id uuid DEFAULT NULL::uuid, p_mode text DEFAULT NULL::text, p_source_type text DEFAULT NULL::text, p_source_id uuid DEFAULT NULL::uuid, p_event_id uuid DEFAULT NULL::uuid, p_store_id uuid DEFAULT NULL::uuid, p_selected_variants jsonb DEFAULT NULL::jsonb, p_language text DEFAULT 'en'::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
DECLARE
    v_target_user_id UUID;
    v_merchant_id UUID;
    v_user user_accounts;
    v_reward RECORD;
    v_points_calc JSONB;
    v_points_required NUMERIC;
    v_user_balance NUMERIC;
    v_promo_code TEXT;
    v_promo_codes_array TEXT[];
    v_available_codes INT;
    v_redemptions JSONB[];
    v_redemption RECORD;
    v_use_expire_date TIMESTAMPTZ;
    v_wallet_ledger_id UUID;
    v_user_tag_ids UUID[];
    v_translations JSONB;
    v_effective_mode TEXT;
    v_is_service_role BOOLEAN;
    v_is_admin BOOLEAN;
    v_is_internal_call BOOLEAN;
    v_caller_user_id UUID;
    v_actor_admin_user_id UUID;
    v_source_type_enum wallet_transaction_source_type;
    v_source_valid BOOLEAN;
    v_record_id UUID;
    i INTEGER;
    v_limit RECORD;
    v_limit_count NUMERIC;
    v_limit_window_start TIMESTAMPTZ;
    v_redeemed_stock NUMERIC;
    v_birth_month TEXT;
    v_group_limit_result JSONB;
    v_delivery_address JSONB;
    v_fulfillment_status rewards_redemption_fulfillment_status;
    v_selected_variants JSONB;
    v_variant_result JSONB;
    v_language TEXT;
    v_time_unit_label TEXT;
BEGIN
    v_is_internal_call := (p_merchant_id IS NOT NULL);
    v_merchant_id := COALESCE(p_merchant_id, get_current_merchant_id());

    -- Envelope language: request p_language (th|en), default en. Backward compatible.
    v_language := public.fn_normalize_ui_language(p_language);

    IF p_event_id IS NOT NULL THEN
        IF EXISTS (SELECT 1 FROM reward_redemptions_ledger WHERE id = p_event_id) THEN
            SELECT jsonb_agg(to_jsonb(r)) INTO v_redemptions FROM reward_redemptions_ledger r WHERE r.id = p_event_id;
            -- Fill merchant from ledger when missing; language already from p_language
            IF v_merchant_id IS NULL THEN
                SELECT r.merchant_id INTO v_merchant_id FROM reward_redemptions_ledger r WHERE r.id = p_event_id LIMIT 1;
            END IF;
            RETURN jsonb_build_object(
                'success', true,
                'title', fn_redeem_member_message('idempotent_title', v_language),
                'description', fn_redeem_member_message('idempotent_desc', v_language),
                'data', jsonb_build_object('redemptions', v_redemptions, 'idempotent', true)
            );
        END IF;
    END IF;

    IF v_merchant_id IS NULL THEN
        RETURN jsonb_build_object('success', false, 'title', fn_redeem_member_message('no_merchant_title', v_language), 'description', null, 'data', null);
    END IF;
    IF p_quantity IS NULL OR p_quantity < 1 OR p_quantity > 1000 THEN
        RETURN jsonb_build_object(
            'success', false,
            'title', 'Invalid quantity',
            'description', 'Quantity must be between 1 and 1000',
            'data', jsonb_build_object('error_code', 'INVALID_QUANTITY', 'quantity', p_quantity, 'min', 1, 'max', 1000)
        );
    END IF;


    v_caller_user_id := auth.uid();

    SELECT au.id
    INTO v_actor_admin_user_id
    FROM admin_users au
    WHERE au.auth_user_id = v_caller_user_id
      AND au.merchant_id = v_merchant_id
      AND au.active_status = true
    LIMIT 1;

    IF p_store_id IS NOT NULL AND NOT EXISTS (
        SELECT 1 FROM store_master sm WHERE sm.id = p_store_id AND sm.merchant_id = v_merchant_id
    ) THEN
        RETURN jsonb_build_object(
            'success', false,
            'title', fn_redeem_member_message('store_not_found_title', v_language),
            'description', fn_redeem_member_message('store_not_found_desc', v_language),
            'data', jsonb_build_object('store_id', p_store_id)
        );
    END IF;

    IF v_is_internal_call THEN
        IF p_user_id IS NULL THEN
            RETURN jsonb_build_object('success', false, 'title', fn_redeem_member_message('user_id_required_title', v_language), 'description', null, 'data', null);
        END IF;
        SELECT * INTO v_user FROM user_accounts WHERE id = p_user_id AND merchant_id = v_merchant_id;
        IF NOT FOUND THEN
            RETURN jsonb_build_object('success', false, 'title', fn_redeem_member_message('user_not_found_title', v_language), 'description', null, 'data', null);
        END IF;
        v_target_user_id := v_user.id;
        v_effective_mode := COALESCE(p_mode, 'calc');
    ELSE
        BEGIN
            v_is_service_role := COALESCE((current_setting('request.jwt.claims', true)::json->>'role') = 'service_role', FALSE);
        EXCEPTION WHEN OTHERS THEN
            v_is_service_role := FALSE;
        END;
        v_is_admin := FALSE;
        IF v_caller_user_id IS NOT NULL THEN
            SELECT EXISTS (SELECT 1 FROM admin_users WHERE auth_user_id = v_caller_user_id AND merchant_id = v_merchant_id AND active_status = true) INTO v_is_admin;
        END IF;
        IF v_is_service_role OR v_is_admin THEN
            v_effective_mode := COALESCE(p_mode, 'calc');
        ELSE
            v_effective_mode := 'calc';
        END IF;
        v_user := resolve_target_user(p_user_id);
        v_target_user_id := v_user.id;
    END IF;

    IF v_effective_mode = 'direct' AND p_source_type IS NOT NULL THEN
        v_source_valid := FALSE;
        CASE p_source_type
            WHEN 'mission' THEN
                SELECT EXISTS (SELECT 1 FROM mission_log_completion mlc WHERE mlc.user_id = v_target_user_id AND mlc.mission_id = p_source_id AND mlc.is_claimed = false) INTO v_source_valid;
                IF NOT v_source_valid THEN
                    IF EXISTS (SELECT 1 FROM reward_redemptions_ledger rrl WHERE rrl.user_id = v_target_user_id AND rrl.source_type = 'mission' AND rrl.source_id = p_source_id AND rrl.reward_id = p_reward_id) THEN
                        RETURN jsonb_build_object('success', false, 'title', fn_redeem_member_message('reward_already_granted_title', v_language), 'description', fn_redeem_member_message('reward_already_granted_desc', v_language), 'data', null);
                    ELSE
                        RETURN jsonb_build_object('success', false, 'title', fn_redeem_member_message('invalid_mission_title', v_language), 'description', fn_redeem_member_message('invalid_mission_desc', v_language), 'data', null);
                    END IF;
                END IF;
            WHEN 'manual' THEN
                SELECT EXISTS (SELECT 1 FROM manual_currency_request_ledger mcr WHERE mcr.id = p_source_id AND mcr.user_id = v_target_user_id AND mcr.status = 'pending') INTO v_source_valid;
                IF NOT v_source_valid THEN
                    RETURN jsonb_build_object('success', false, 'title', fn_redeem_member_message('invalid_manual_title', v_language), 'description', fn_redeem_member_message('invalid_manual_desc', v_language), 'data', null);
                END IF;
            ELSE
                v_source_valid := TRUE;
        END CASE;
    END IF;

    SELECT * INTO v_reward FROM reward_master WHERE id = p_reward_id AND merchant_id = v_merchant_id;
    IF NOT FOUND THEN
        RETURN jsonb_build_object('success', false, 'title', fn_redeem_member_message('reward_not_found_title', v_language), 'description', null, 'data', null);
    END IF;

    -- Shipping fulfillment: snapshot the member's saved address at redemption time.
    -- Member-initiated redemptions (mode 'calc') are rejected without a usable address;
    -- direct grants (missions, admin) stamp best-effort and never fail on address.
    IF v_reward.fulfillment_method = 'shipping' THEN
        v_fulfillment_status := 'pending'::rewards_redemption_fulfillment_status;
        v_delivery_address := fn_get_user_address_snapshot(v_target_user_id, v_merchant_id);
        IF v_delivery_address IS NOT NULL
           AND (NULLIF(TRIM(COALESCE(v_delivery_address->>'addressline_1', '')), '') IS NULL
             OR NULLIF(TRIM(COALESCE(v_delivery_address->>'postcode', '')), '') IS NULL) THEN
            v_delivery_address := NULL;
        END IF;
        IF v_delivery_address IS NULL AND v_effective_mode = 'calc' THEN
            RETURN jsonb_build_object(
                'success', false,
                'title', fn_redeem_member_message('address_required_title', v_language),
                'description', fn_redeem_member_message('address_required_desc', v_language),
                'data', jsonb_build_object('error_code', 'ADDRESS_REQUIRED', 'reward_id', p_reward_id)
            );
        END IF;
    END IF;

    -- Reward variants: required on member calc path; optional/best-effort on direct grants
    v_variant_result := public.fn_resolve_reward_variant_selection(
        v_reward.variant_config,
        p_selected_variants,
        (v_effective_mode = 'calc')
    );
    IF COALESCE((v_variant_result->>'ok')::boolean, false) IS NOT TRUE THEN
        RETURN jsonb_build_object(
            'success', false,
            'title', CASE WHEN v_variant_result->>'error_code' = 'VARIANT_REQUIRED'
                THEN fn_redeem_member_message('variant_required_title', v_language)
                ELSE fn_redeem_member_message('variant_invalid_title', v_language) END,
            'description', CASE
                WHEN v_variant_result->>'error_code' = 'VARIANT_REQUIRED'
                THEN fn_redeem_member_message('variant_required_desc', v_language, ARRAY[COALESCE(v_variant_result->>'dimension_label', '')])
                ELSE fn_redeem_member_message('variant_invalid_desc', v_language, ARRAY[COALESCE(v_variant_result->>'dimension_code', '')])
            END,
            'data', jsonb_build_object(
                'error_code', v_variant_result->>'error_code',
                'reward_id', p_reward_id,
                'dimension_code', v_variant_result->>'dimension_code',
                'option_code', v_variant_result->>'option_code'
            )
        );
    END IF;
    v_selected_variants := v_variant_result->'snapshot';
    IF v_selected_variants = 'null'::jsonb THEN v_selected_variants := NULL; END IF;

    v_translations := get_reward_translations(v_reward.id, v_reward.name, v_reward.description_headline, v_reward.description_body, v_reward.description_tc, v_reward.description_slip);
    SELECT ARRAY_AGG(tag_id) INTO v_user_tag_ids FROM user_tags WHERE user_id = v_target_user_id;

    IF v_effective_mode = 'calc' THEN
        IF public.fn_merchant_shopify_feature_enabled(v_merchant_id, 'reward', 'reward.tier_reward_eligibility') AND v_reward.allowed_tier IS NOT NULL AND array_length(v_reward.allowed_tier, 1) > 0 THEN
            IF v_user.tier_id IS NULL OR NOT (v_user.tier_id = ANY(v_reward.allowed_tier)) THEN
                RETURN jsonb_build_object('success', false, 'title', fn_redeem_member_message('tier_title', v_language), 'description', fn_redeem_member_message('tier_desc', v_language), 'data', null);
            END IF;
        END IF;
        IF v_reward.allowed_persona IS NOT NULL AND array_length(v_reward.allowed_persona, 1) > 0 THEN
            IF v_user.persona_id IS NULL OR NOT (v_user.persona_id = ANY(v_reward.allowed_persona)) THEN
                RETURN jsonb_build_object('success', false, 'title', fn_redeem_member_message('persona_title', v_language), 'description', fn_redeem_member_message('persona_desc', v_language), 'data', null);
            END IF;
        END IF;
        IF v_reward.allowed_tags IS NOT NULL AND array_length(v_reward.allowed_tags, 1) > 0 THEN
            IF v_user_tag_ids IS NULL OR NOT (v_reward.allowed_tags && v_user_tag_ids) THEN
                RETURN jsonb_build_object('success', false, 'title', fn_redeem_member_message('tag_title', v_language), 'description', fn_redeem_member_message('tag_desc', v_language), 'data', null);
            END IF;
        END IF;
        IF v_reward.allowed_birthmonth IS NOT NULL AND array_length(v_reward.allowed_birthmonth, 1) > 0 THEN
            v_birth_month := EXTRACT(MONTH FROM v_user.birth_date)::INT::TEXT;
            IF v_birth_month IS NULL OR NOT (v_birth_month = ANY(v_reward.allowed_birthmonth)) THEN
                RETURN jsonb_build_object('success', false, 'title', fn_redeem_member_message('birthday_title', v_language), 'description', fn_redeem_member_message('birthday_desc', v_language), 'data', null);
            END IF;
        END IF;
    END IF;

    IF v_effective_mode = 'calc' THEN
        IF v_reward.redeem_window_start IS NOT NULL AND CURRENT_TIMESTAMP < v_reward.redeem_window_start THEN
            RETURN jsonb_build_object(
                'success', false,
                'title', fn_redeem_member_message('period_not_started_title', v_language),
                'description', fn_redeem_member_message('period_not_started_desc', v_language, ARRAY[to_char(v_reward.redeem_window_start, 'YYYY-MM-DD HH24:MI')]),
                'data', jsonb_build_object('available_from', v_reward.redeem_window_start)
            );
        END IF;
        IF v_reward.redeem_window_end IS NOT NULL AND CURRENT_TIMESTAMP > v_reward.redeem_window_end THEN
            RETURN jsonb_build_object(
                'success', false,
                'title', fn_redeem_member_message('period_ended_title', v_language),
                'description', fn_redeem_member_message('period_ended_desc', v_language, ARRAY[to_char(v_reward.redeem_window_end, 'YYYY-MM-DD')]),
                'data', jsonb_build_object('expired_on', v_reward.redeem_window_end)
            );
        END IF;
    END IF;

    IF v_effective_mode = 'calc' THEN
        FOR v_limit IN SELECT * FROM transaction_limits WHERE entity_id = p_reward_id AND entity_type = 'reward' AND merchant_id = v_merchant_id AND active_status = true LOOP
            v_limit_window_start := CASE v_limit.time_unit WHEN 'day' THEN date_trunc('day', CURRENT_TIMESTAMP) WHEN 'week' THEN date_trunc('week', CURRENT_TIMESTAMP) WHEN 'month' THEN date_trunc('month', CURRENT_TIMESTAMP) WHEN 'year' THEN date_trunc('year', CURRENT_TIMESTAMP) WHEN 'all_time' THEN NULL ELSE NULL END;
            IF v_limit.window_start IS NOT NULL AND CURRENT_TIMESTAMP < v_limit.window_start THEN CONTINUE; END IF;
            IF v_limit.window_end IS NOT NULL AND CURRENT_TIMESTAMP > v_limit.window_end THEN CONTINUE; END IF;
            IF v_limit.window_start IS NOT NULL AND v_limit_window_start IS NOT NULL THEN v_limit_window_start := GREATEST(v_limit_window_start, v_limit.window_start);
            ELSIF v_limit.window_start IS NOT NULL THEN v_limit_window_start := v_limit.window_start;
            END IF;
            IF v_limit.scope = 'user' THEN
                SELECT COALESCE(SUM(qty), 0) INTO v_limit_count FROM reward_redemptions_ledger WHERE user_id = v_target_user_id AND reward_id = p_reward_id AND redeemed_status = true AND (cancelled IS NOT TRUE) AND (source_type IS NULL OR source_type NOT IN ('package_assignment', 'persona_entitlement')) AND (v_limit_window_start IS NULL OR created_at >= v_limit_window_start);
            ELSIF v_limit.scope = 'total' THEN
                SELECT COALESCE(SUM(qty), 0) INTO v_limit_count FROM reward_redemptions_ledger WHERE reward_id = p_reward_id AND merchant_id = v_merchant_id AND redeemed_status = true AND (cancelled IS NOT TRUE) AND (v_limit_window_start IS NULL OR created_at >= v_limit_window_start);
            END IF;
            IF v_limit_count + p_quantity > v_limit.count THEN
                v_time_unit_label := fn_redeem_member_message('time_unit', v_language, ARRAY[v_limit.time_unit::text]);
                RETURN jsonb_build_object(
                    'success', false,
                    'title', CASE v_limit.scope
                        WHEN 'user' THEN fn_redeem_member_message('limit_personal_title', v_language)
                        WHEN 'total' THEN fn_redeem_member_message('limit_total_title', v_language)
                    END,
                    'description', fn_redeem_member_message(
                        'limit_desc', v_language,
                        ARRAY[v_limit.count::text, v_time_unit_label, v_limit_count::text, p_quantity::text]
                    ),
                    'data', jsonb_build_object(
                        'limit_scope', v_limit.scope,
                        'limit_count', v_limit.count,
                        'time_unit', v_limit.time_unit,
                        'current_count', v_limit_count,
                        'remaining', GREATEST(v_limit.count - v_limit_count, 0),
                        'requested', p_quantity
                    )
                );
            END IF;
        END LOOP;
    END IF;

    IF v_effective_mode = 'calc' THEN
        v_group_limit_result := fn_check_reward_group_limits(v_target_user_id, p_reward_id, p_quantity, v_merchant_id);
        IF NOT (v_group_limit_result->>'allowed')::boolean THEN
            v_time_unit_label := fn_redeem_member_message('time_unit', v_language, ARRAY[COALESCE(v_group_limit_result->>'time_unit', '')]);
            RETURN jsonb_build_object(
                'success', false,
                'title', CASE (v_group_limit_result->>'limit_scope')
                    WHEN 'user' THEN fn_redeem_member_message('group_limit_personal_title', v_language, ARRAY[COALESCE(v_group_limit_result->>'group_name', '')])
                    WHEN 'total' THEN fn_redeem_member_message('group_limit_total_title', v_language, ARRAY[COALESCE(v_group_limit_result->>'group_name', '')])
                END,
                'description', fn_redeem_member_message(
                    'group_limit_desc', v_language,
                    ARRAY[
                        COALESCE(v_group_limit_result->>'limit_count', ''),
                        v_time_unit_label,
                        COALESCE(v_group_limit_result->>'current_count', ''),
                        COALESCE(v_group_limit_result->>'requested', '')
                    ]
                ),
                'data', v_group_limit_result
            );
        END IF;
    END IF;

    IF v_effective_mode = 'calc' AND v_reward.stock_control AND NOT v_reward.assign_promocode THEN
        IF v_reward.stock_total IS NOT NULL THEN
            SELECT COALESCE(SUM(qty), 0) INTO v_redeemed_stock FROM reward_redemptions_ledger WHERE reward_id = p_reward_id AND merchant_id = v_merchant_id AND redeemed_status = true AND (cancelled IS NOT TRUE);
            IF v_redeemed_stock + p_quantity > v_reward.stock_total THEN
                RETURN jsonb_build_object(
                    'success', false,
                    'title', fn_redeem_member_message('out_of_stock_title', v_language),
                    'description', fn_redeem_member_message('out_of_stock_desc', v_language, ARRAY[GREATEST(v_reward.stock_total - v_redeemed_stock, 0)::text]),
                    'data', jsonb_build_object('stock_total', v_reward.stock_total, 'redeemed', v_redeemed_stock, 'available', GREATEST(v_reward.stock_total - v_redeemed_stock, 0), 'requested', p_quantity)
                );
            END IF;
        END IF;
    END IF;

    IF v_reward.assign_promocode THEN
        SELECT COUNT(*) INTO v_available_codes FROM reward_promo_code WHERE reward_id = p_reward_id AND merchant_id = v_merchant_id AND redeemed_status = false;
        IF v_available_codes < p_quantity THEN
            RETURN jsonb_build_object(
                'success', false,
                'title', fn_redeem_member_message('insufficient_codes_title', v_language),
                'description', fn_redeem_member_message('insufficient_codes_desc', v_language, ARRAY[v_available_codes::text, p_quantity::text]),
                'data', jsonb_build_object('available', v_available_codes, 'requested', p_quantity, 'shortage', p_quantity - v_available_codes)
            );
        END IF;
        SELECT ARRAY_AGG(promo_code ORDER BY created_at) INTO v_promo_codes_array FROM (SELECT promo_code, created_at FROM reward_promo_code WHERE reward_id = p_reward_id AND merchant_id = v_merchant_id AND redeemed_status = false ORDER BY created_at LIMIT p_quantity FOR UPDATE SKIP LOCKED) codes;
        IF v_promo_codes_array IS NULL OR array_length(v_promo_codes_array, 1) < p_quantity THEN
            RETURN jsonb_build_object(
                'success', false,
                'title', fn_redeem_member_message('concurrent_title', v_language),
                'description', fn_redeem_member_message('concurrent_desc', v_language),
                'data', null
            );
        END IF;
    END IF;

    IF v_effective_mode IN ('calc', 'force') THEN
        v_points_calc := calculate_redemption_points_fast(v_user.tier_id, v_user.user_type, v_user.persona_id, v_user_tag_ids, p_reward_id, v_reward.fallback_points, v_reward.require_points_match);
        IF NOT (v_points_calc->>'success')::boolean THEN
            RETURN jsonb_build_object('success', false, 'title', fn_redeem_member_message('points_calc_failed_title', v_language), 'description', v_points_calc->>'message', 'data', null);
        END IF;
        v_points_required := (v_points_calc->>'points_required')::numeric * p_quantity;
        SELECT COALESCE(points_balance, 0) INTO v_user_balance FROM user_wallet WHERE user_id = v_target_user_id AND merchant_id = v_merchant_id;
        IF v_user_balance IS NULL THEN v_user_balance := 0; END IF;
        IF v_user_balance < v_points_required THEN
            RETURN jsonb_build_object(
                'success', false,
                'title', fn_redeem_member_message('insufficient_points_title', v_language),
                'description', fn_redeem_member_message('insufficient_points_desc', v_language, ARRAY[(v_points_required - v_user_balance)::text]),
                'data', jsonb_build_object('required', v_points_required, 'available', v_user_balance, 'shortage', v_points_required - v_user_balance)
            );
        END IF;
    ELSE
        v_points_required := 0;
        v_points_calc := jsonb_build_object('mode', 'direct', 'source_type', p_source_type, 'source_id', p_source_id);
        v_user_balance := 0;
    END IF;

    IF v_reward.use_expire_mode = 'relative_days' THEN v_use_expire_date := CURRENT_TIMESTAMP + (v_reward.use_expire_ttl || ' days')::INTERVAL;
    ELSIF v_reward.use_expire_mode = 'absolute_date' THEN v_use_expire_date := v_reward.use_expire_date;
    ELSIF v_reward.use_expire_mode = 'relative_mins' THEN v_use_expire_date := CURRENT_TIMESTAMP + (v_reward.use_expire_ttl || ' minutes')::INTERVAL;
    END IF;

    IF p_source_type IS NOT NULL AND EXISTS (
        SELECT 1
        FROM pg_type t
        JOIN pg_enum e ON e.enumtypid = t.oid
        WHERE t.typname = 'wallet_transaction_source_type'
          AND e.enumlabel = p_source_type
    ) THEN
        v_source_type_enum := p_source_type::wallet_transaction_source_type;
    ELSE
        v_source_type_enum := 'reward_redemption'::wallet_transaction_source_type;
    END IF;

    v_redemptions := ARRAY[]::JSONB[];

    IF v_reward.assign_promocode THEN
        FOR i IN 1..p_quantity LOOP
            IF p_event_id IS NOT NULL THEN v_record_id := p_event_id; ELSE v_record_id := gen_random_uuid(); END IF;
            INSERT INTO reward_redemptions_ledger (id, merchant_id, user_id, reward_id, qty, points_deducted, points_calculation, promo_code, use_expire_date, redeemed_status, redeemed_at, source_type, source_id, redeemed_store_id, fulfillment_status, delivery_address, selected_variants) VALUES (v_record_id, v_merchant_id, v_target_user_id, p_reward_id, 1, CASE WHEN v_effective_mode IN ('calc', 'force') THEN v_points_required / p_quantity ELSE 0 END, v_points_calc, v_promo_codes_array[i], v_use_expire_date, true, CURRENT_TIMESTAMP, v_source_type_enum, p_source_id, p_store_id, v_fulfillment_status, v_delivery_address, v_selected_variants) RETURNING * INTO v_redemption;
            UPDATE reward_promo_code SET redeemed_status = true WHERE promo_code = v_promo_codes_array[i] AND merchant_id = v_merchant_id;

            INSERT INTO redemption_usage_log (
                merchant_id, redemption_id, action, qty_change, used_qty_after,
                performed_by, admin_user_id, source_type, store_id, notes
            )
            VALUES (
                v_merchant_id, v_redemption.id, 'redeem', COALESCE(v_redemption.qty, 1)::integer, COALESCE(v_redemption.used_qty, 0),
                COALESCE(v_caller_user_id::text, v_target_user_id::text),
                v_actor_admin_user_id,
                CASE
                    WHEN p_source_type = 'admin_frontline' OR p_store_id IS NOT NULL
                    THEN COALESCE(p_source_type, 'admin_frontline')
                    ELSE COALESCE(p_source_type, 'member_app')
                END,
                p_store_id, NULL
            );

            v_redemptions := array_append(v_redemptions, jsonb_build_object('redemption_id', v_redemption.id, 'redemption_code', v_redemption.code, 'reward_id', v_reward.id, 'reward_name', v_reward.name, 'description_tc', v_reward.description_tc, 'description_slip', v_reward.description_slip, 'translations', v_translations, 'promo_code', v_redemption.promo_code, 'qty', 1, 'unit_number', i, 'points_deducted', v_redemption.points_deducted, 'redeemed_at', v_redemption.redeemed_at, 'redeemed_store_id', v_redemption.redeemed_store_id, 'use_expire_date', v_redemption.use_expire_date, 'use_expire_mode', v_reward.use_expire_mode, 'use_expire_ttl', v_reward.use_expire_ttl, 'fulfillment_status', v_redemption.fulfillment_status, 'lucky_draw_slip', fn_build_lucky_draw_slip(v_merchant_id, v_reward.id, v_redemption.code, v_target_user_id, v_redemption.redeemed_at)));
        END LOOP;
    ELSE
        v_record_id := COALESCE(p_event_id, gen_random_uuid());
        INSERT INTO reward_redemptions_ledger (id, merchant_id, user_id, reward_id, qty, points_deducted, points_calculation, promo_code, use_expire_date, redeemed_status, redeemed_at, source_type, source_id, redeemed_store_id, fulfillment_status, delivery_address, selected_variants) VALUES (v_record_id, v_merchant_id, v_target_user_id, p_reward_id, p_quantity, v_points_required, v_points_calc, v_reward.promo_code, v_use_expire_date, true, CURRENT_TIMESTAMP, v_source_type_enum, p_source_id, p_store_id, v_fulfillment_status, v_delivery_address, v_selected_variants) RETURNING * INTO v_redemption;

        INSERT INTO redemption_usage_log (
            merchant_id, redemption_id, action, qty_change, used_qty_after,
            performed_by, admin_user_id, source_type, store_id, notes
        )
        VALUES (
            v_merchant_id, v_redemption.id, 'redeem', COALESCE(v_redemption.qty, p_quantity)::integer, COALESCE(v_redemption.used_qty, 0),
            COALESCE(v_caller_user_id::text, v_target_user_id::text),
            v_actor_admin_user_id,
            CASE
                WHEN p_source_type = 'admin_frontline' OR p_store_id IS NOT NULL
                THEN COALESCE(p_source_type, 'admin_frontline')
                ELSE COALESCE(p_source_type, 'member_app')
            END,
            p_store_id, NULL
        );

        v_redemptions := ARRAY[jsonb_build_object('redemption_id', v_redemption.id, 'redemption_code', v_redemption.code, 'reward_id', v_reward.id, 'reward_name', v_reward.name, 'description_tc', v_reward.description_tc, 'description_slip', v_reward.description_slip, 'translations', v_translations, 'promo_code', v_redemption.promo_code, 'qty', v_redemption.qty, 'points_deducted', v_redemption.points_deducted, 'redeemed_at', v_redemption.redeemed_at, 'redeemed_store_id', v_redemption.redeemed_store_id, 'use_expire_date', v_redemption.use_expire_date, 'use_expire_mode', v_reward.use_expire_mode, 'use_expire_ttl', v_reward.use_expire_ttl, 'fulfillment_status', v_redemption.fulfillment_status, 'lucky_draw_slip', fn_build_lucky_draw_slip(v_merchant_id, v_reward.id, v_redemption.code, v_target_user_id, v_redemption.redeemed_at))];
    END IF;

    IF v_effective_mode IN ('calc', 'force') AND v_points_required > 0 THEN
        v_wallet_ledger_id := chokepoint_post_wallet_transaction(p_user_id := v_target_user_id, p_currency := 'points'::currency, p_source_type := 'reward_redemption'::wallet_transaction_source_type, p_component := 'base'::currency_component, p_transaction_type := 'burn'::currency_transaction_type, p_amount := v_points_required::integer, p_transaction_id := (v_redemptions[1]->>'redemption_id')::uuid, p_merchant_id := v_merchant_id, p_description := 'Reward redemption: ' || v_reward.name, p_metadata := v_points_calc, p_target_entity_id := NULL);
        SELECT COALESCE(points_balance, 0) INTO v_user_balance FROM user_wallet WHERE user_id = v_target_user_id AND merchant_id = v_merchant_id;
    END IF;

    RETURN jsonb_build_object(
        'success', true,
        'title', CASE WHEN v_effective_mode = 'direct'
            THEN fn_redeem_member_message('success_granted', v_language)
            ELSE fn_redeem_member_message('success_redeemed', v_language) END,
        'description', null,
        'data', jsonb_build_object('redemptions', to_jsonb(v_redemptions), 'total_quantity', p_quantity, 'total_points_deducted', v_points_required, 'new_balance', CASE WHEN v_effective_mode IN ('calc', 'force') THEN v_user_balance ELSE NULL END, 'mode', v_effective_mode, 'source_type', p_source_type, 'source_id', p_source_id, 'store_id', p_store_id, 'wallet_ledger_id', v_wallet_ledger_id, 'has_promo_codes', v_reward.assign_promocode, 'records_created', array_length(v_redemptions, 1), 'event_id', p_event_id, 'external_id_shopify', v_reward.external_id_shopify)
    );

EXCEPTION
    WHEN SQLSTATE 'PGRST' OR SQLSTATE 'PGUSR' THEN PERFORM set_config('response.status', '401', true); RAISE;
    WHEN SQLSTATE 'PGADM' THEN PERFORM set_config('response.status', '403', true); RAISE;
END;
$function$
