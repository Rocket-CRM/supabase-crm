CREATE OR REPLACE FUNCTION public.api_mark_redemption_used(p_redemption_id uuid DEFAULT NULL::uuid, p_redemption_code text DEFAULT NULL::text, p_user_id uuid DEFAULT NULL::uuid, p_notes text DEFAULT NULL::text, p_language text DEFAULT 'en'::text, p_merchant_id uuid DEFAULT NULL::uuid, p_store_id uuid DEFAULT NULL::uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
DECLARE
    v_redemption RECORD;
    v_merchant_id UUID;
    v_calling_user_id UUID;
    v_target_user_id UUID;
    v_is_admin BOOLEAN;
    v_is_service_role BOOLEAN := false;
    v_default_language TEXT;
    v_reward_name TEXT;
    v_description_headline TEXT;
    v_description_body TEXT;
    v_status_translation TEXT;
    v_used_at TIMESTAMPTZ;
    v_actor_admin_user_id UUID;
BEGIN
    v_merchant_id := get_current_merchant_id();

    IF v_merchant_id IS NULL THEN
        BEGIN
            v_is_service_role := COALESCE(
                (current_setting('request.jwt.claims', true)::json->>'role') = 'service_role',
                FALSE
            );
        EXCEPTION WHEN OTHERS THEN
            v_is_service_role := FALSE;
        END;

        IF v_is_service_role AND p_merchant_id IS NOT NULL THEN
            v_merchant_id := p_merchant_id;
        ELSE
            RETURN fn_response_error('No merchant context', NULL, NULL);
        END IF;
    ELSE
        IF p_merchant_id IS NOT NULL AND p_merchant_id != v_merchant_id THEN
            RETURN fn_response_error('Access Denied', 'Merchant ID mismatch', 'MERCHANT_MISMATCH');
        END IF;
    END IF;

    IF p_store_id IS NOT NULL AND NOT EXISTS (
        SELECT 1 FROM store_master sm WHERE sm.id = p_store_id AND sm.merchant_id = v_merchant_id
    ) THEN
        RETURN fn_response_error('Store not found', 'Store does not belong to merchant', 'STORE_NOT_FOUND');
    END IF;

    SELECT language_code INTO v_default_language
    FROM merchant_languages
    WHERE merchant_id = v_merchant_id AND is_default = true
    LIMIT 1;
    v_default_language := COALESCE(v_default_language, 'en');

    IF v_is_service_role THEN
        v_target_user_id := p_user_id;
        v_is_admin := true;
    ELSE
        v_calling_user_id := auth.uid();
        IF v_calling_user_id IS NULL THEN
            RETURN fn_response_error('Authentication required', 'Please log in to continue', NULL);
        END IF;

        SELECT au.id
        INTO v_actor_admin_user_id
        FROM admin_users au
        WHERE au.auth_user_id = v_calling_user_id
          AND au.merchant_id = v_merchant_id
          AND au.active_status = true
        LIMIT 1;

        IF p_user_id IS NULL THEN
            v_target_user_id := v_calling_user_id;
            v_is_admin := false;
        ELSE
            v_is_admin := is_admin();
            IF NOT v_is_admin THEN
                RETURN fn_response_error('Admin required', 'Only admins can mark redemptions for other users', NULL);
            END IF;
            v_target_user_id := p_user_id;
        END IF;
    END IF;

    IF v_is_service_role AND v_target_user_id IS NULL THEN
        SELECT
            rrl.*,
            rm.name as reward_name,
            rm.image as reward_image,
            rm.description_headline,
            rm.description_body,
            rm.use_expire_mode,
            rm.category_id,
            rm.fulfillment_method,
            rm.online_store as reward_online_store,
            rm.active_status as catalog_active_status,
            rm.use_expire_date as catalog_use_expire_date
        INTO v_redemption
        FROM reward_redemptions_ledger rrl
        JOIN reward_master rm ON rm.id = rrl.reward_id
        WHERE rrl.merchant_id = v_merchant_id
          AND (rrl.id = p_redemption_id OR rrl.code = p_redemption_code)
        LIMIT 1;
    ELSE
        SELECT
            rrl.*,
            rm.name as reward_name,
            rm.image as reward_image,
            rm.description_headline,
            rm.description_body,
            rm.use_expire_mode,
            rm.category_id,
            rm.fulfillment_method,
            rm.online_store as reward_online_store,
            rm.active_status as catalog_active_status,
            rm.use_expire_date as catalog_use_expire_date
        INTO v_redemption
        FROM reward_redemptions_ledger rrl
        JOIN reward_master rm ON rm.id = rrl.reward_id
        WHERE rrl.merchant_id = v_merchant_id
          AND rrl.user_id = v_target_user_id
          AND (rrl.id = p_redemption_id OR rrl.code = p_redemption_code)
        LIMIT 1;
    END IF;

    IF v_redemption.id IS NULL THEN
        RETURN fn_response_error('Redemption not found',
            CASE WHEN v_is_admin THEN 'Redemption not found for specified user' ELSE 'Redemption not found or does not belong to you' END,
            'NOT_FOUND');
    END IF;

    IF NOT v_is_admin AND NOT v_is_service_role THEN
        IF NOT COALESCE((
            SELECT rm.allow_member_mark_used
            FROM reward_master rm
            WHERE rm.id = v_redemption.reward_id
        ), true) THEN
            RETURN fn_response_error(
                'Self-use disabled',
                'This reward must be marked used by staff',
                'MEMBER_SELF_USE_DISABLED'
            );
        END IF;
    END IF;

    v_reward_name := COALESCE(
        (SELECT translated_value FROM translations
         WHERE entity_id = v_redemption.reward_id AND entity_type = 'reward'
           AND field_name = 'name' AND language_code = p_language LIMIT 1),
        (SELECT translated_value FROM translations
         WHERE entity_id = v_redemption.reward_id AND entity_type = 'reward'
           AND field_name = 'name' AND language_code = v_default_language LIMIT 1),
        v_redemption.reward_name
    );

    v_description_headline := COALESCE(
        (SELECT translated_value FROM translations
         WHERE entity_id = v_redemption.reward_id AND entity_type = 'reward'
           AND field_name = 'description_headline' AND language_code = p_language LIMIT 1),
        (SELECT translated_value FROM translations
         WHERE entity_id = v_redemption.reward_id AND entity_type = 'reward'
           AND field_name = 'description_headline' AND language_code = v_default_language LIMIT 1),
        v_redemption.description_headline
    );

    v_description_body := COALESCE(
        (SELECT translated_value FROM translations
         WHERE entity_id = v_redemption.reward_id AND entity_type = 'reward'
           AND field_name = 'description_body' AND language_code = p_language LIMIT 1),
        (SELECT translated_value FROM translations
         WHERE entity_id = v_redemption.reward_id AND entity_type = 'reward'
           AND field_name = 'description_body' AND language_code = v_default_language LIMIT 1),
        v_redemption.description_body
    );

    IF v_redemption.source_type IS NOT NULL
       AND v_redemption.source_type::text IN ('package_assignment', 'persona_entitlement')
       AND v_redemption.qty > 1 THEN
        RETURN fn_response_error('Use the entitlement API',
            'Multi-use entitlements must be consumed via api_use_entitlement', 'MULTI_USE_ENTITLEMENT',
            jsonb_build_object('redemption_id', v_redemption.id, 'qty', v_redemption.qty, 'used_qty', v_redemption.used_qty));
    END IF;

    IF v_redemption.cancelled = true THEN
        v_status_translation := (SELECT translated_value FROM ui_translations
                                WHERE page_key = 'redemption_status' AND field_key = 'status_cancelled'
                                  AND language_code = p_language LIMIT 1);
        RETURN fn_response_error('Redemption cancelled', 'Cannot mark as used - this redemption has been cancelled', 'CANCELLED',
            jsonb_build_object('status', 'cancelled', 'status_translation', v_status_translation, 'cancelled_at', v_redemption.cancelled_at));
    END IF;

    IF v_redemption.redeemed_status = false THEN
        v_status_translation := (SELECT translated_value FROM ui_translations
                                WHERE page_key = 'redemption_status' AND field_key = 'status_pending'
                                  AND language_code = p_language LIMIT 1);
        RETURN fn_response_error('Not yet redeemed', 'Cannot mark as used - redemption has not been completed yet', 'NOT_REDEEMED',
            jsonb_build_object('status', 'pending', 'status_translation', v_status_translation));
    END IF;

    IF v_redemption.used_status = true THEN
        v_status_translation := (SELECT translated_value FROM ui_translations
                                WHERE page_key = 'redemption_status' AND field_key = 'status_used'
                                  AND language_code = p_language LIMIT 1);
        RETURN fn_response_error('Already marked as used', 'This redemption was already marked as used', 'ALREADY_USED',
            jsonb_build_object(
                'redemption_id', v_redemption.id,
                'code', v_redemption.code,
                'status', 'used',
                'status_translation', v_status_translation,
                'used_at', v_redemption.used_at,
                'used_store_id', v_redemption.used_store_id,
                'reward_name', v_reward_name,
                'description_headline', v_description_headline,
                'description_body', v_description_body
            ));
    END IF;

    IF (v_redemption.use_expire_date IS NOT NULL AND v_redemption.use_expire_date < NOW())
       OR COALESCE(v_redemption.catalog_active_status, true) = false
       OR (v_redemption.catalog_use_expire_date IS NOT NULL AND v_redemption.catalog_use_expire_date < NOW()) THEN
        v_status_translation := (SELECT translated_value FROM ui_translations
                                WHERE page_key = 'redemption_status' AND field_key = 'status_expired'
                                  AND language_code = p_language LIMIT 1);
        RETURN fn_response_error('Redemption expired', 'Cannot mark as used - this redemption has expired', 'EXPIRED',
            jsonb_build_object('status', 'expired', 'status_translation', v_status_translation, 'expired_at', v_redemption.use_expire_date));
    END IF;

    v_used_at := NOW();

    UPDATE reward_redemptions_ledger
    SET used_status = true,
        used_at = v_used_at,
        used_store_id = COALESCE(p_store_id, used_store_id),
        fulfillment_status = 'completed'
    WHERE id = v_redemption.id;

    INSERT INTO redemption_usage_log (
        merchant_id, redemption_id, action, qty_change, used_qty_after,
        performed_by, admin_user_id, source_type, store_id, notes
    )
    VALUES (
        v_merchant_id, v_redemption.id, 'use', 1, GREATEST(COALESCE(v_redemption.used_qty, 0), 1),
        COALESCE(v_calling_user_id::text, CASE WHEN v_is_service_role THEN 'service_role' ELSE 'system' END),
        v_actor_admin_user_id, 'frontline_use', p_store_id, p_notes
    );

    v_status_translation := (SELECT translated_value FROM ui_translations
                            WHERE page_key = 'redemption_status' AND field_key = 'status_used'
                              AND language_code = p_language LIMIT 1);

    RETURN fn_response_success('Reward used successfully', NULL,
        jsonb_build_object(
            'redemption_id', v_redemption.id,
            'code', v_redemption.code,
            'status', 'used',
            'status_translation', COALESCE(v_status_translation, 'Used'),
            'used_at', v_used_at,
            'used_store_id', p_store_id,
            'redeemed_at', v_redemption.redeemed_at,
            'redeemed_store_id', v_redemption.redeemed_store_id,
            'reward_id', v_redemption.reward_id,
            'reward_name', v_reward_name,
            'reward_image', v_redemption.reward_image,
            'description_headline', v_description_headline,
            'description_body', v_description_body,
            'category_id', v_redemption.category_id,
            'fulfillment_method', v_redemption.fulfillment_method,
            'online_store', v_redemption.reward_online_store,
            'promo_code', v_redemption.promo_code,
            'points_deducted', v_redemption.points_deducted,
            'use_expire_date', v_redemption.use_expire_date,
            'language', p_language,
            'default_language', v_default_language
        ));

EXCEPTION WHEN OTHERS THEN
    RETURN fn_response_error('Operation failed', 'Failed to mark redemption as used', 'ERROR',
        jsonb_build_object('details', SQLERRM));
END;
$function$;
