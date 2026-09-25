CREATE OR REPLACE FUNCTION public.bff_get_reward_group_details(p_group_id uuid DEFAULT NULL::uuid, p_mode text DEFAULT 'new'::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
DECLARE
    v_merchant_id UUID;
    v_group RECORD;
    v_limits JSONB;
    v_member_rewards JSONB;
BEGIN
    v_merchant_id := get_current_merchant_id();
    IF v_merchant_id IS NULL THEN
        RETURN fn_response_error('Error', 'No merchant context found', 'NO_MERCHANT_CONTEXT');
    END IF;

    IF p_mode = 'new' THEN
        RETURN jsonb_build_object(
            'success', true,
            'data', jsonb_build_object(
                'mode', 'new',
                'id', NULL,
                'merchant_id', v_merchant_id,
                'group_code', NULL,
                'name', NULL,
                'description', NULL,
                'is_active', true,
                'is_featured', false,
                'transaction_limits', '[]'::jsonb,
                'member_rewards', '[]'::jsonb
            )
        );
    END IF;

    IF p_group_id IS NULL THEN
        RETURN fn_response_error('Error', 'group_id is required for edit mode', 'MISSING_PARAM');
    END IF;

    SELECT rg.id, rg.merchant_id, rg.group_code, rg.name, rg.description,
           rg.is_active, rg.is_featured, rg.created_at, rg.updated_at
    INTO v_group
    FROM reward_group rg
    WHERE rg.id = p_group_id AND rg.merchant_id = v_merchant_id;

    IF v_group IS NULL THEN
        RETURN fn_response_error('Not Found', 'Reward group not found or access denied', 'NOT_FOUND');
    END IF;

    SELECT COALESCE(jsonb_agg(
        jsonb_build_object(
            'id', tl.id,
            'metric', tl.metric::text,
            'scope', tl.scope::text,
            'count', tl.count,
            'time_unit', tl.time_unit::text,
            'window_start', tl.window_start,
            'window_end', tl.window_end,
            'active_status', tl.active_status
        )
    ), '[]'::jsonb)
    INTO v_limits
    FROM transaction_limits tl
    WHERE tl.entity_id = p_group_id
      AND tl.entity_type = 'reward_group'
      AND tl.merchant_id = v_merchant_id;

    SELECT COALESCE(jsonb_agg(
        jsonb_build_object(
            'id', rm.id,
            'name', rm.name,
            'visibility', rm.visibility::text,
            'active_status', rm.active_status,
            'is_featured', rm.is_featured,
            'category_id', rm.category_id
        ) ORDER BY rm.name
    ), '[]'::jsonb)
    INTO v_member_rewards
    FROM reward_master rm
    WHERE rm.merchant_id = v_merchant_id
      AND rm.reward_group_ids @> ARRAY[p_group_id];

    RETURN jsonb_build_object(
        'success', true,
        'data', jsonb_build_object(
            'mode', 'edit',
            'id', v_group.id,
            'merchant_id', v_group.merchant_id,
            'group_code', v_group.group_code,
            'name', v_group.name,
            'description', v_group.description,
            'is_active', v_group.is_active,
            'is_featured', v_group.is_featured,
            'created_at', v_group.created_at,
            'updated_at', v_group.updated_at,
            'transaction_limits', v_limits,
            'member_rewards', v_member_rewards
        )
    );

EXCEPTION WHEN OTHERS THEN
    RETURN fn_response_error('Error', SQLERRM, 'ERROR');
END;
$function$
