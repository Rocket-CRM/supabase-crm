CREATE OR REPLACE FUNCTION public.bff_list_reward_groups()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
DECLARE
    v_merchant_id UUID;
    v_groups JSONB;
BEGIN
    v_merchant_id := get_current_merchant_id();
    IF v_merchant_id IS NULL THEN
        RETURN fn_response_error('Error', 'No merchant context found', 'NO_MERCHANT_CONTEXT');
    END IF;

    SELECT COALESCE(jsonb_agg(
        jsonb_build_object(
            'id', rg.id,
            'group_code', rg.group_code,
            'name', rg.name,
            'description', rg.description,
            'is_active', rg.is_active,
            'is_featured', rg.is_featured,
            'created_at', rg.created_at,
            'updated_at', rg.updated_at,
            'member_count', COALESCE(mc.cnt, 0),
            'limits', COALESCE(lm.limits_arr, '[]'::jsonb)
        ) ORDER BY rg.created_at DESC
    ), '[]'::jsonb)
    INTO v_groups
    FROM reward_group rg
    LEFT JOIN LATERAL (
        SELECT COUNT(*) as cnt
        FROM reward_master rm
        WHERE rm.merchant_id = v_merchant_id
          AND rm.reward_group_ids @> ARRAY[rg.id]
    ) mc ON true
    LEFT JOIN LATERAL (
        SELECT jsonb_agg(
            jsonb_build_object(
                'metric', tl.metric::text,
                'scope', tl.scope::text,
                'count', tl.count,
                'time_unit', tl.time_unit::text
            )
        ) as limits_arr
        FROM transaction_limits tl
        WHERE tl.entity_id = rg.id
          AND tl.entity_type = 'reward_group'
          AND tl.merchant_id = v_merchant_id
          AND tl.active_status = true
    ) lm ON true
    WHERE rg.merchant_id = v_merchant_id;

    RETURN jsonb_build_object(
        'success', true,
        'data', v_groups
    );

EXCEPTION WHEN OTHERS THEN
    RETURN fn_response_error('Error', SQLERRM, 'ERROR');
END;
$function$
