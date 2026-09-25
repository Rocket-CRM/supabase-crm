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
