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
$function$
