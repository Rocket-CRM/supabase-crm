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

