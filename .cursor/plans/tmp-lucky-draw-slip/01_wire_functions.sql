-- Wire Lucky Draw slip fields through BFFs + redemption payloads.
-- Depends on: reward_master.physical_draw_name/description + fn_build_lucky_draw_slip

-- 1) Admin get
CREATE OR REPLACE FUNCTION public.bff_get_reward_details(p_mode text DEFAULT 'edit'::text, p_reward_id uuid DEFAULT NULL::uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
DECLARE
    v_merchant_id UUID;
    v_reward RECORD;
    v_points_conditions JSONB;
    v_transaction_limits JSONB;
    v_reward_groups JSONB;
BEGIN
    v_merchant_id := get_current_merchant_id();

    IF v_merchant_id IS NULL THEN
        RETURN jsonb_build_object('success', false, 'error', 'No merchant context found');
    END IF;

    IF p_mode = 'new' THEN
        RETURN jsonb_build_object(
            'mode', 'new',
            'id', NULL,
            'name', NULL,
            'visibility', NULL,
            'description_headline', NULL,
            'description_body', NULL,
            'description_tc', NULL,
            'description_slip', NULL,
            'physical_draw_name', NULL,
            'physical_draw_description', NULL,
            'image', NULL,
            'category_id', NULL,
            'stock_control', false,
            'assign_promocode', false,
            'fulfillment_method', NULL,
            'redeem_window_start', NULL,
            'redeem_window_end', NULL,
            'use_expire_mode', NULL,
            'use_expire_date', NULL,
            'use_expire_ttl', NULL,
            'allowed_tier', '[]'::jsonb,
            'allowed_persona', '[]'::jsonb,
            'allowed_tags', '[]'::jsonb,
            'allowed_birthmonth', '[]'::jsonb,
            'fallback_points', NULL,
            'require_points_match', false,
            'ranking', NULL,
            'online_store', NULL,
            'external_id_shopify', NULL,
            'merchant_id', v_merchant_id,
            'created_at', NULL,
            'points_conditions', '[]'::jsonb,
            'transaction_limits', '[]'::jsonb,
            'reward_group_ids', NULL,
            'reward_groups', '[]'::jsonb,
            'variant_config', NULL
        );
    END IF;

    IF p_reward_id IS NULL THEN
        RETURN jsonb_build_object('success', false, 'error', 'reward_id is required for edit mode');
    END IF;

    SELECT * INTO v_reward
    FROM reward_master
    WHERE id = p_reward_id AND merchant_id = v_merchant_id;

    IF v_reward.id IS NULL THEN
        RETURN jsonb_build_object('success', false, 'error', 'Reward not found or access denied');
    END IF;

    SELECT COALESCE(
        jsonb_agg(
            jsonb_build_object(
                'id', pc.id,
                'tier_id', pc.tier_id,
                'user_type', pc.user_type,
                'persona_id', pc.persona_id,
                'tag_ids', pc.tag_ids,
                'points_required', pc.points_required,
                'priority', pc.priority,
                'condition_name', pc.condition_name,
                'description', pc.description,
                'active_status', pc.active_status,
                'created_at', pc.created_at
            ) ORDER BY pc.priority DESC, pc.created_at
        ),
        '[]'::jsonb
    ) INTO v_points_conditions
    FROM reward_points_conditions pc
    WHERE pc.reward_id = p_reward_id AND pc.merchant_id = v_merchant_id;

    SELECT COALESCE(
        jsonb_agg(
            jsonb_build_object(
                'id', tl.id,
                'scope', tl.scope,
                'count', tl.count,
                'time_unit', tl.time_unit,
                'window_start', tl.window_start,
                'window_end', tl.window_end,
                'active_status', tl.active_status,
                'created_at', tl.created_at
            ) ORDER BY tl.created_at
        ),
        '[]'::jsonb
    ) INTO v_transaction_limits
    FROM transaction_limits tl
    WHERE tl.entity_id = p_reward_id
      AND tl.entity_type = 'reward'
      AND tl.merchant_id = v_merchant_id;

    IF v_reward.reward_group_ids IS NOT NULL AND array_length(v_reward.reward_group_ids, 1) > 0 THEN
        SELECT COALESCE(
            jsonb_agg(
                jsonb_build_object(
                    'id', rg.id,
                    'name', rg.name,
                    'group_code', rg.group_code,
                    'is_active', rg.is_active
                ) ORDER BY rg.name
            ),
            '[]'::jsonb
        ) INTO v_reward_groups
        FROM reward_group rg
        WHERE rg.id = ANY(v_reward.reward_group_ids)
          AND rg.merchant_id = v_merchant_id;
    ELSE
        v_reward_groups := '[]'::jsonb;
    END IF;

    RETURN jsonb_build_object(
        'mode', 'edit',
        'id', v_reward.id,
        'name', v_reward.name,
        'visibility', v_reward.visibility,
        'description_headline', v_reward.description_headline,
        'description_body', v_reward.description_body,
        'description_tc', v_reward.description_tc,
        'description_slip', v_reward.description_slip,
        'physical_draw_name', v_reward.physical_draw_name,
        'physical_draw_description', v_reward.physical_draw_description,
        'image', v_reward.image,
        'category_id', v_reward.category_id,
        'stock_control', v_reward.stock_control,
        'assign_promocode', v_reward.assign_promocode,
        'fulfillment_method', v_reward.fulfillment_method,
        'redeem_window_start', v_reward.redeem_window_start,
        'redeem_window_end', v_reward.redeem_window_end,
        'use_expire_mode', v_reward.use_expire_mode,
        'use_expire_date', v_reward.use_expire_date,
        'use_expire_ttl', v_reward.use_expire_ttl,
        'allowed_tier', v_reward.allowed_tier,
        'allowed_persona', v_reward.allowed_persona,
        'allowed_tags', v_reward.allowed_tags,
        'allowed_birthmonth', v_reward.allowed_birthmonth,
        'fallback_points', v_reward.fallback_points,
        'require_points_match', v_reward.require_points_match,
        'ranking', v_reward.ranking,
        'online_store', v_reward.online_store,
        'external_id_shopify', v_reward.external_id_shopify,
        'merchant_id', v_reward.merchant_id,
        'created_at', v_reward.created_at,
        'points_conditions', v_points_conditions,
        'transaction_limits', v_transaction_limits,
        'reward_group_ids', v_reward.reward_group_ids,
        'reward_groups', v_reward_groups,
        'variant_config', v_reward.variant_config
    );
END;
$function$;

-- 2) Admin upsert — drop old signature, recreate with new trailing params
DO $patch$
DECLARE
  v_def text;
  v_identity text;
BEGIN
  SELECT pg_get_functiondef(p.oid), pg_get_function_identity_arguments(p.oid)
  INTO v_def, v_identity
  FROM pg_proc p
  JOIN pg_namespace n ON p.pronamespace = n.oid
  WHERE n.nspname = 'public'
    AND p.proname = 'bff_upsert_reward_with_conditions_and_limits';

  IF v_def IS NULL THEN
    RAISE EXCEPTION 'bff_upsert_reward_with_conditions_and_limits not found';
  END IF;

  IF position('p_physical_draw_name' in v_def) > 0 THEN
    RAISE NOTICE 'upsert already has physical_draw params';
    RETURN;
  END IF;

  EXECUTE format('DROP FUNCTION public.bff_upsert_reward_with_conditions_and_limits(%s)', v_identity);

  v_def := replace(
    v_def,
    'p_variant_config jsonb DEFAULT NULL::jsonb)',
    'p_variant_config jsonb DEFAULT NULL::jsonb, p_physical_draw_name text DEFAULT NULL::text, p_physical_draw_description text DEFAULT NULL::text)'
  );

  v_def := replace(
    v_def,
    'shopify_discount_type, shopify_discount_label, variant_config, created_at)
        VALUES (v_reward_id, v_merchant_id, p_name, p_description_headline, p_description_body, p_description_tc, p_description_slip, v_image, v_category_id, p_visibility, p_redeem_window_start, p_redeem_window_end, p_stock_control, p_assign_promocode, p_use_expire_mode, p_use_expire_date, p_use_expire_ttl, p_fulfillment_method, v_allowed_tier, v_allowed_persona, v_allowed_tags, v_allowed_birthmonth, p_fallback_points, p_require_points_match, p_external_id_shopify, v_online_store, v_reward_group_ids, p_shopify_discount_type, p_shopify_discount_label, p_variant_config, NOW());',
    'shopify_discount_type, shopify_discount_label, variant_config, physical_draw_name, physical_draw_description, created_at)
        VALUES (v_reward_id, v_merchant_id, p_name, p_description_headline, p_description_body, p_description_tc, p_description_slip, v_image, v_category_id, p_visibility, p_redeem_window_start, p_redeem_window_end, p_stock_control, p_assign_promocode, p_use_expire_mode, p_use_expire_date, p_use_expire_ttl, p_fulfillment_method, v_allowed_tier, v_allowed_persona, v_allowed_tags, v_allowed_birthmonth, p_fallback_points, p_require_points_match, p_external_id_shopify, v_online_store, v_reward_group_ids, p_shopify_discount_type, p_shopify_discount_label, p_variant_config, p_physical_draw_name, p_physical_draw_description, NOW());'
  );

  v_def := replace(
    v_def,
    'variant_config = p_variant_config
        WHERE id = v_reward_id AND merchant_id = v_merchant_id;',
    'variant_config = p_variant_config,
          physical_draw_name = p_physical_draw_name,
          physical_draw_description = p_physical_draw_description
        WHERE id = v_reward_id AND merchant_id = v_merchant_id;'
  );

  IF position('p_physical_draw_name' in v_def) = 0
     OR position('physical_draw_name = p_physical_draw_name' in v_def) = 0 THEN
    RAISE EXCEPTION 'upsert patch failed — expected markers not found';
  END IF;

  EXECUTE v_def;
END;
$patch$;

-- 3) redeem_reward_with_points — attach lucky_draw_slip on each redemption object
DO $patch$
DECLARE
  v_def text;
  v_old1 text;
  v_new1 text;
  v_old2 text;
  v_new2 text;
BEGIN
  SELECT pg_get_functiondef(p.oid) INTO v_def
  FROM pg_proc p
  JOIN pg_namespace n ON p.pronamespace = n.oid
  WHERE n.nspname = 'public'
    AND p.proname = 'redeem_reward_with_points';

  IF v_def IS NULL THEN
    RAISE EXCEPTION 'redeem_reward_with_points not found';
  END IF;

  IF position('lucky_draw_slip' in v_def) > 0 THEN
    RAISE NOTICE 'redeem already has lucky_draw_slip';
    RETURN;
  END IF;

  v_old1 := '''fulfillment_status'', v_redemption.fulfillment_status));';
  v_new1 := '''fulfillment_status'', v_redemption.fulfillment_status, ''lucky_draw_slip'', fn_build_lucky_draw_slip(v_merchant_id, v_reward.id, v_redemption.code, v_target_user_id, v_redemption.redeemed_at));';

  v_old2 := '''fulfillment_status'', v_redemption.fulfillment_status)];';
  v_new2 := '''fulfillment_status'', v_redemption.fulfillment_status, ''lucky_draw_slip'', fn_build_lucky_draw_slip(v_merchant_id, v_reward.id, v_redemption.code, v_target_user_id, v_redemption.redeemed_at)];';

  IF position(v_old1 in v_def) = 0 OR position(v_old2 in v_def) = 0 THEN
    RAISE EXCEPTION 'redeem patch markers not found (promocode loop / single insert)';
  END IF;

  v_def := replace(v_def, v_old1, v_new1);
  v_def := replace(v_def, v_old2, v_new2);

  EXECUTE v_def;
END;
$patch$;

-- 4) Member/admin get_redemption_details
CREATE OR REPLACE FUNCTION public.get_redemption_details(p_redemption_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
DECLARE
    v_user_id UUID;
    v_merchant_id UUID;
    v_result JSONB;
BEGIN
    v_user_id := auth.uid();
    v_merchant_id := get_current_merchant_id();

    IF v_user_id IS NULL OR v_merchant_id IS NULL THEN
        RETURN jsonb_build_object(
            'success', false,
            'error', 'Authentication required'
        );
    END IF;

    SELECT jsonb_build_object(
        'success', true,
        'redemption', jsonb_build_object(
            'id', rrl.id,
            'created_at', rrl.created_at,
            'redeemed_at', rrl.redeemed_at,
            'qty', rrl.qty,
            'points_deducted', rrl.points_deducted,
            'promo_code', rrl.promo_code,
            'code', rrl.code,
            'use_expire_date', rrl.use_expire_date,
            'redeemed_status', rrl.redeemed_status,
            'used_status', rrl.used_status,
            'used_at', rrl.used_at,
            'fulfillment_status', rrl.fulfillment_status
        ),
        'reward', jsonb_build_object(
            'id', rm.id,
            'name', rm.name,
            'description_headline', rm.description_headline,
            'description_body', rm.description_body,
            'description_tc', rm.description_tc,
            'description_slip', rm.description_slip,
            'physical_draw_name', rm.physical_draw_name,
            'physical_draw_description', rm.physical_draw_description,
            'image', rm.image,
            'fulfillment_method', rm.fulfillment_method,
            'fallback_points', rm.fallback_points
        ),
        'lucky_draw_slip', fn_build_lucky_draw_slip(
            v_merchant_id,
            rm.id,
            rrl.code,
            rrl.user_id,
            COALESCE(rrl.redeemed_at, rrl.created_at)
        )
    ) INTO v_result
    FROM reward_redemptions_ledger rrl
    JOIN reward_master rm ON rrl.reward_id = rm.id
    WHERE rrl.id = p_redemption_id
      AND rrl.merchant_id = v_merchant_id
      AND (rrl.user_id = v_user_id OR is_admin());

    IF v_result IS NULL THEN
        RETURN jsonb_build_object(
            'success', false,
            'error', 'Redemption not found or unauthorized'
        );
    END IF;

    RETURN v_result;

EXCEPTION
    WHEN OTHERS THEN
        RETURN jsonb_build_object(
            'success', false,
            'error', SQLERRM
        );
END;
$function$;

-- 5) Frontline/API lookup — add lucky_draw_slip for print/reprint
CREATE OR REPLACE FUNCTION public.api_get_redemption(p_merchant_id uuid, p_redemption_id uuid DEFAULT NULL::uuid, p_redemption_code text DEFAULT NULL::text, p_store_id uuid DEFAULT NULL::uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
DECLARE
    v_redemption RECORD;
    v_reward_name TEXT;
    v_redeemed_store_name TEXT;
    v_used_store_name TEXT;
    v_redeemed_by_user_id UUID;
    v_redeemed_by_name TEXT;
    v_used_by_user_id UUID;
    v_used_by_name TEXT;
    v_actor_auth_user_id UUID;
    v_actor_admin_user_id UUID;
    v_lucky_draw_slip JSONB;
BEGIN
    v_actor_auth_user_id := auth.uid();

    SELECT au.id
    INTO v_actor_admin_user_id
    FROM admin_users au
    WHERE au.auth_user_id = v_actor_auth_user_id
      AND au.merchant_id = p_merchant_id
      AND au.active_status = true
    LIMIT 1;

    IF p_redemption_id IS NOT NULL THEN
        SELECT * INTO v_redemption FROM reward_redemptions_ledger
        WHERE id = p_redemption_id AND merchant_id = p_merchant_id;
    ELSIF p_redemption_code IS NOT NULL THEN
        SELECT * INTO v_redemption FROM reward_redemptions_ledger
        WHERE code = p_redemption_code AND merchant_id = p_merchant_id;
    ELSE
        RETURN jsonb_build_object('success', false, 'error', 'Provide redemption_id or redemption_code', 'code', 'MISSING_IDENTIFIER');
    END IF;

    IF v_redemption.id IS NULL THEN
        RETURN jsonb_build_object('success', false, 'error', 'Redemption not found', 'code', 'REDEMPTION_NOT_FOUND');
    END IF;

    IF p_store_id IS NOT NULL AND NOT EXISTS (
        SELECT 1
        FROM store_master sm
        WHERE sm.id = p_store_id
          AND sm.merchant_id = p_merchant_id
    ) THEN
        RETURN jsonb_build_object('success', false, 'error', 'Store does not belong to merchant', 'code', 'STORE_NOT_FOUND');
    END IF;

    IF p_store_id IS NOT NULL THEN
        INSERT INTO redemption_usage_log (
            merchant_id, redemption_id, action, qty_change, used_qty_after,
            performed_by, admin_user_id, source_type, store_id, notes
        )
        VALUES (
            p_merchant_id, v_redemption.id, 'lookup', 0, COALESCE(v_redemption.used_qty, 0),
            COALESCE(v_actor_auth_user_id::text, 'api_get_redemption'), v_actor_admin_user_id,
            'frontline_lookup', p_store_id, 'Redemption lookup'
        );
    END IF;

    SELECT name INTO v_reward_name FROM reward_master WHERE id = v_redemption.reward_id AND merchant_id = p_merchant_id;
    SELECT store_name::text INTO v_redeemed_store_name FROM store_master WHERE id = v_redemption.redeemed_store_id AND merchant_id = p_merchant_id;
    SELECT store_name::text INTO v_used_store_name FROM store_master WHERE id = v_redemption.used_store_id AND merchant_id = p_merchant_id;

    SELECT COALESCE(au.auth_user_id, au.id, by_log.performed_uuid), COALESCE(au.name, ua.fullname)
    INTO v_redeemed_by_user_id, v_redeemed_by_name
    FROM (
        SELECT
            rul.admin_user_id,
            CASE
                WHEN rul.performed_by ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
                THEN rul.performed_by::uuid
                ELSE NULL::uuid
            END AS performed_uuid,
            rul.performed_at,
            rul.id
        FROM redemption_usage_log rul
        WHERE rul.merchant_id = p_merchant_id
          AND rul.redemption_id = v_redemption.id
          AND rul.action = 'redeem'
        ORDER BY rul.performed_at DESC NULLS LAST, rul.id DESC
        LIMIT 1
    ) by_log
    LEFT JOIN admin_users au
      ON au.merchant_id = p_merchant_id
     AND (au.id = by_log.admin_user_id OR au.auth_user_id = by_log.performed_uuid)
    LEFT JOIN user_accounts ua
      ON ua.merchant_id = p_merchant_id
     AND (ua.id = by_log.performed_uuid OR ua.auth_user_id = by_log.performed_uuid);

    IF v_redeemed_by_name IS NULL THEN
        SELECT COALESCE(ua.auth_user_id, ua.id), ua.fullname
        INTO v_redeemed_by_user_id, v_redeemed_by_name
        FROM user_accounts ua
        WHERE ua.merchant_id = p_merchant_id
          AND ua.id = v_redemption.user_id;
    END IF;

    SELECT COALESCE(au.auth_user_id, au.id, by_log.performed_uuid), COALESCE(au.name, ua.fullname)
    INTO v_used_by_user_id, v_used_by_name
    FROM (
        SELECT
            rul.admin_user_id,
            CASE
                WHEN rul.performed_by ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
                THEN rul.performed_by::uuid
                ELSE NULL::uuid
            END AS performed_uuid,
            rul.performed_at,
            rul.id
        FROM redemption_usage_log rul
        WHERE rul.merchant_id = p_merchant_id
          AND rul.redemption_id = v_redemption.id
          AND rul.action = 'use'
        ORDER BY rul.performed_at DESC NULLS LAST, rul.id DESC
        LIMIT 1
    ) by_log
    LEFT JOIN admin_users au
      ON au.merchant_id = p_merchant_id
     AND (au.id = by_log.admin_user_id OR au.auth_user_id = by_log.performed_uuid)
    LEFT JOIN user_accounts ua
      ON ua.merchant_id = p_merchant_id
     AND (ua.id = by_log.performed_uuid OR ua.auth_user_id = by_log.performed_uuid);

    v_lucky_draw_slip := fn_build_lucky_draw_slip(
        p_merchant_id,
        v_redemption.reward_id,
        v_redemption.code,
        v_redemption.user_id,
        COALESCE(v_redemption.redeemed_at, v_redemption.created_at)
    );

    RETURN jsonb_build_object(
        'success', true,
        'redemption', jsonb_build_object(
            'redemption_id', v_redemption.id,
            'code', v_redemption.code,
            'user_id', v_redemption.user_id,
            'reward_id', v_redemption.reward_id,
            'reward_name', v_reward_name,
            'quantity', v_redemption.qty,
            'points_deducted', v_redemption.points_deducted,
            'promo_code', v_redemption.promo_code,
            'redeemed_status', v_redemption.redeemed_status,
            'redeemed_at', v_redemption.redeemed_at,
            'redeemed_store_id', v_redemption.redeemed_store_id,
            'redeemed_store_name', v_redeemed_store_name,
            'redeemed_by_user_id', v_redeemed_by_user_id,
            'redeemed_by_name', v_redeemed_by_name,
            'used_status', v_redemption.used_status,
            'used_at', v_redemption.used_at,
            'used_store_id', v_redemption.used_store_id,
            'used_store_name', v_used_store_name,
            'used_by_user_id', v_used_by_user_id,
            'used_by_name', v_used_by_name,
            'use_expire_date', v_redemption.use_expire_date,
            'fulfillment_status', v_redemption.fulfillment_status,
            'delivery_address_code', v_redemption.delivery_address_code,
            'delivery_address', v_redemption.delivery_address,
            'selected_variants', v_redemption.selected_variants,
            'cancelled', v_redemption.cancelled,
            'cancelled_at', v_redemption.cancelled_at,
            'cancelled_reason', v_redemption.cancelled_reason,
            'source_type', v_redemption.source_type,
            'source_id', v_redemption.source_id,
            'created_at', v_redemption.created_at
        ),
        'lucky_draw_slip', v_lucky_draw_slip
    );

EXCEPTION WHEN OTHERS THEN
    RETURN jsonb_build_object('success', false, 'error', 'Failed to retrieve redemption', 'code', 'REDEMPTION_FETCH_FAILED', 'details', SQLERRM);
END;
$function$;
