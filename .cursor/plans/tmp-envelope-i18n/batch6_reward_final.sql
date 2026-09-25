CREATE OR REPLACE FUNCTION public.bff_upsert_reward(p_config jsonb, p_language text DEFAULT 'en'::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
DECLARE
  v_lang text;
    v_merchant_id UUID;
    v_reward_id UUID;
    v_reward_name TEXT;
    v_parent_created BOOLEAN := false;
    v_parent_updated BOOLEAN := false;
    v_conditions_created INT := 0;
    v_conditions_updated INT := 0;
    v_conditions_deleted INT := 0;
    v_conditions_skipped INT := 0;
    v_limits_created INT := 0;
    v_limits_updated INT := 0;
    v_limits_deleted INT := 0;
    v_limits_skipped INT := 0;
    v_condition_obj JSONB;
    v_condition_id UUID;
    v_limit_obj JSONB;
    v_limit_id UUID;
    v_conditions_to_keep UUID[] := ARRAY[]::UUID[];
    v_limits_to_keep UUID[] := ARRAY[]::UUID[];
    v_user_type user_type;
    v_window_start TIMESTAMPTZ;
    v_window_end TIMESTAMPTZ;
    v_name TEXT;
    v_visibility reward_visibility;
    v_description_headline TEXT;
    v_description_body TEXT;
    v_description_tc TEXT;
    v_description_slip TEXT;
    v_stock_control BOOLEAN;
    v_assign_promocode BOOLEAN;
    v_fulfillment_method reward_fulfillment_method;
    v_redeem_window_start TIMESTAMPTZ;
    v_redeem_window_end TIMESTAMPTZ;
    v_use_expire_mode reward_expire_mode;
    v_use_expire_date TIMESTAMPTZ;
    v_use_expire_ttl NUMERIC;
    v_fallback_points NUMERIC;
    v_require_points_match BOOLEAN;
    v_category_id UUID[];
    v_allowed_tier UUID[];
    v_allowed_persona UUID[];
    v_allowed_tags UUID[];
    v_allowed_birthmonth TEXT[];
    v_image TEXT[];
    v_online_store TEXT[];
    v_external_id_shopify TEXT;
    v_variant_config JSONB;
    v_points_conditions JSONB;
    v_transaction_limits JSONB;
BEGIN
  v_lang := fn_normalize_ui_language(p_language);
    v_merchant_id := get_current_merchant_id();
    IF v_merchant_id IS NULL THEN
        RETURN jsonb_build_object('success', false, 'code', 'NO_MERCHANT_CONTEXT', 'title', fn_admin_envelope_message('error_title', v_lang), 'description', fn_admin_envelope_message('no_merchant_found_title', v_lang), 'error', fn_admin_envelope_message('no_merchant_found_title', v_lang));
    END IF;

    v_reward_id := CASE 
        WHEN p_config->>'id' IS NULL OR p_config->>'id' = '' THEN NULL 
        ELSE (p_config->>'id')::UUID 
    END;

    v_name := p_config->>'name';
    v_reward_name := COALESCE(v_name, 'Untitled Reward');
    v_visibility := CASE WHEN p_config->>'visibility' IS NULL OR p_config->>'visibility' = '' THEN NULL ELSE (p_config->>'visibility')::reward_visibility END;
    v_description_headline := p_config->>'description_headline';
    v_description_body := p_config->>'description_body';
    v_description_tc := p_config->>'description_tc';
    v_description_slip := p_config->>'description_slip';
    v_stock_control := COALESCE((p_config->>'stock_control')::BOOLEAN, false);
    v_assign_promocode := COALESCE((p_config->>'assign_promocode')::BOOLEAN, false);
    v_fulfillment_method := CASE WHEN p_config->>'fulfillment_method' IS NULL OR p_config->>'fulfillment_method' = '' THEN NULL ELSE (p_config->>'fulfillment_method')::reward_fulfillment_method END;
    v_redeem_window_start := CASE WHEN p_config->>'redeem_window_start' IS NULL OR p_config->>'redeem_window_start' = '' THEN NULL ELSE (p_config->>'redeem_window_start')::TIMESTAMPTZ END;
    v_redeem_window_end := CASE WHEN p_config->>'redeem_window_end' IS NULL OR p_config->>'redeem_window_end' = '' THEN NULL ELSE (p_config->>'redeem_window_end')::TIMESTAMPTZ END;
    v_use_expire_mode := CASE WHEN p_config->>'use_expire_mode' IS NULL OR p_config->>'use_expire_mode' = '' THEN NULL ELSE (p_config->>'use_expire_mode')::reward_expire_mode END;
    v_use_expire_date := CASE WHEN p_config->>'use_expire_date' IS NULL OR p_config->>'use_expire_date' = '' THEN NULL ELSE (p_config->>'use_expire_date')::TIMESTAMPTZ END;
    v_use_expire_ttl := CASE WHEN p_config->>'use_expire_ttl' IS NULL OR p_config->>'use_expire_ttl' = '' THEN NULL ELSE (p_config->>'use_expire_ttl')::NUMERIC END;
    v_fallback_points := CASE WHEN p_config->>'fallback_points' IS NULL OR p_config->>'fallback_points' = '' THEN NULL ELSE (p_config->>'fallback_points')::NUMERIC END;
    v_require_points_match := COALESCE((p_config->>'require_points_match')::BOOLEAN, false);
    v_external_id_shopify := p_config->>'external_id_shopify';
    v_variant_config := p_config->'variant_config';

    v_category_id := fn_jsonb_to_uuid_array(p_config->'category_id');
    v_allowed_tier := fn_jsonb_to_uuid_array(p_config->'allowed_tier');
    v_allowed_persona := fn_jsonb_to_uuid_array(p_config->'allowed_persona');
    v_allowed_tags := fn_jsonb_to_uuid_array(p_config->'allowed_tags');
    v_allowed_birthmonth := fn_jsonb_to_text_array(p_config->'allowed_birthmonth');
    v_image := fn_jsonb_to_text_array(p_config->'image');
    v_online_store := fn_jsonb_to_text_array(p_config->'online_store');
    v_points_conditions := p_config->'points_conditions';
    v_transaction_limits := p_config->'transaction_limits';

    IF v_reward_id IS NULL THEN
        v_reward_id := gen_random_uuid();
        INSERT INTO reward_master (id, merchant_id, name, description_headline, description_body, description_tc, description_slip, image, category_id, visibility, redeem_window_start, redeem_window_end, stock_control, assign_promocode, use_expire_mode, use_expire_date, use_expire_ttl, fulfillment_method, allowed_tier, allowed_persona, allowed_tags, allowed_birthmonth, fallback_points, require_points_match, external_id_shopify, online_store, variant_config, created_at)
        VALUES (v_reward_id, v_merchant_id, v_name, v_description_headline, v_description_body, v_description_tc, v_description_slip, v_image, v_category_id, v_visibility, v_redeem_window_start, v_redeem_window_end, v_stock_control, v_assign_promocode, v_use_expire_mode, v_use_expire_date, v_use_expire_ttl, v_fulfillment_method, v_allowed_tier, v_allowed_persona, v_allowed_tags, v_allowed_birthmonth, v_fallback_points, v_require_points_match, v_external_id_shopify, v_online_store, v_variant_config, NOW());
        v_parent_created := true;
    ELSE
        UPDATE reward_master SET name = v_name, description_headline = v_description_headline, description_body = v_description_body, description_tc = v_description_tc, description_slip = v_description_slip, image = v_image, category_id = v_category_id, visibility = v_visibility, redeem_window_start = v_redeem_window_start, redeem_window_end = v_redeem_window_end, stock_control = v_stock_control, assign_promocode = v_assign_promocode, use_expire_mode = v_use_expire_mode, use_expire_date = v_use_expire_date, use_expire_ttl = v_use_expire_ttl, fulfillment_method = v_fulfillment_method, allowed_tier = v_allowed_tier, allowed_persona = v_allowed_persona, allowed_tags = v_allowed_tags, allowed_birthmonth = v_allowed_birthmonth, fallback_points = v_fallback_points, require_points_match = v_require_points_match, external_id_shopify = v_external_id_shopify, online_store = v_online_store, variant_config = v_variant_config
        WHERE id = v_reward_id AND merchant_id = v_merchant_id;
        IF NOT FOUND THEN RETURN jsonb_build_object('success', false, 'code', 'NOT_FOUND', 'title', fn_admin_envelope_message('not_found_title', v_lang), 'description', fn_admin_envelope_message('reward_not_found_desc', v_lang), 'error', fn_admin_envelope_message('reward_not_found_desc', v_lang)); END IF;
        SELECT name INTO v_reward_name FROM reward_master WHERE id = v_reward_id;
        v_parent_updated := true;
    END IF;

    IF v_points_conditions IS NOT NULL AND jsonb_typeof(v_points_conditions) = 'array' AND jsonb_array_length(v_points_conditions) > 0 THEN
        FOR v_condition_obj IN SELECT * FROM jsonb_array_elements(v_points_conditions) LOOP
            v_condition_id := CASE WHEN v_condition_obj->>'id' IS NULL OR v_condition_obj->>'id' = '' THEN NULL ELSE (v_condition_obj->>'id')::UUID END;
            IF (v_condition_obj->>'points_required') IS NULL THEN v_conditions_skipped := v_conditions_skipped + 1; CONTINUE; END IF;
            v_user_type := CASE WHEN v_condition_obj->>'user_type' IS NULL OR v_condition_obj->>'user_type' = '' THEN NULL ELSE (v_condition_obj->>'user_type')::user_type END;
            
            IF v_condition_id IS NOT NULL THEN
                UPDATE reward_points_conditions SET 
                    tier_id = CASE WHEN v_condition_obj->>'tier_id' IS NULL OR v_condition_obj->>'tier_id' = '' THEN NULL ELSE (v_condition_obj->>'tier_id')::UUID END,
                    user_type = v_user_type,
                    persona_id = CASE WHEN v_condition_obj->>'persona_id' IS NULL OR v_condition_obj->>'persona_id' = '' THEN NULL ELSE (v_condition_obj->>'persona_id')::UUID END,
                    tag_ids = fn_jsonb_to_uuid_array(v_condition_obj->'tag_ids'),
                    points_required = (v_condition_obj->>'points_required')::NUMERIC,
                    priority = COALESCE((v_condition_obj->>'priority')::INTEGER, 100),
                    condition_name = v_condition_obj->>'condition_name',
                    description = v_condition_obj->>'description',
                    active_status = COALESCE((v_condition_obj->>'active_status')::BOOLEAN, true),
                    updated_at = NOW()
                WHERE id = v_condition_id AND reward_id = v_reward_id AND merchant_id = v_merchant_id;
                IF FOUND THEN v_conditions_updated := v_conditions_updated + 1; v_conditions_to_keep := array_append(v_conditions_to_keep, v_condition_id); 
                ELSE v_conditions_skipped := v_conditions_skipped + 1; END IF;
            ELSE
                v_condition_id := gen_random_uuid();
                INSERT INTO reward_points_conditions (id, reward_id, merchant_id, tier_id, user_type, persona_id, tag_ids, points_required, priority, condition_name, description, active_status, created_at, updated_at)
                VALUES (v_condition_id, v_reward_id, v_merchant_id, 
                    CASE WHEN v_condition_obj->>'tier_id' IS NULL OR v_condition_obj->>'tier_id' = '' THEN NULL ELSE (v_condition_obj->>'tier_id')::UUID END,
                    v_user_type, 
                    CASE WHEN v_condition_obj->>'persona_id' IS NULL OR v_condition_obj->>'persona_id' = '' THEN NULL ELSE (v_condition_obj->>'persona_id')::UUID END,
                    fn_jsonb_to_uuid_array(v_condition_obj->'tag_ids'), 
                    (v_condition_obj->>'points_required')::NUMERIC, COALESCE((v_condition_obj->>'priority')::INTEGER, 100),
                    v_condition_obj->>'condition_name', v_condition_obj->>'description', COALESCE((v_condition_obj->>'active_status')::BOOLEAN, true), NOW(), NOW());
                v_conditions_created := v_conditions_created + 1;
                v_conditions_to_keep := array_append(v_conditions_to_keep, v_condition_id);
            END IF;
        END LOOP;
        DELETE FROM reward_points_conditions WHERE reward_id = v_reward_id AND merchant_id = v_merchant_id AND id != ALL(v_conditions_to_keep);
        GET DIAGNOSTICS v_conditions_deleted = ROW_COUNT;
    ELSE
        DELETE FROM reward_points_conditions WHERE reward_id = v_reward_id AND merchant_id = v_merchant_id;
        GET DIAGNOSTICS v_conditions_deleted = ROW_COUNT;
    END IF;

    IF v_transaction_limits IS NOT NULL AND jsonb_typeof(v_transaction_limits) = 'array' AND jsonb_array_length(v_transaction_limits) > 0 THEN
        FOR v_limit_obj IN SELECT * FROM jsonb_array_elements(v_transaction_limits) LOOP
            v_limit_id := CASE WHEN v_limit_obj->>'id' IS NULL OR v_limit_obj->>'id' = '' THEN NULL ELSE (v_limit_obj->>'id')::UUID END;
            IF (v_limit_obj->>'scope') IS NULL OR v_limit_obj->>'scope' = '' OR (v_limit_obj->>'count') IS NULL THEN v_limits_skipped := v_limits_skipped + 1; CONTINUE; END IF;
            v_window_start := CASE WHEN v_limit_obj->>'window_start' IS NULL OR v_limit_obj->>'window_start' = '' THEN NULL ELSE (v_limit_obj->>'window_start')::TIMESTAMPTZ END;
            v_window_end := CASE WHEN v_limit_obj->>'window_end' IS NULL OR v_limit_obj->>'window_end' = '' THEN NULL ELSE (v_limit_obj->>'window_end')::TIMESTAMPTZ END;
            
            IF v_limit_id IS NOT NULL THEN
                UPDATE transaction_limits SET scope = (v_limit_obj->>'scope')::reward_condition_scope, count = (v_limit_obj->>'count')::NUMERIC,
                    time_unit = CASE WHEN v_limit_obj->>'time_unit' IS NULL OR v_limit_obj->>'time_unit' = '' THEN NULL ELSE (v_limit_obj->>'time_unit')::reward_condition_time_unit END,
                    window_start = v_window_start, window_end = v_window_end, active_status = COALESCE((v_limit_obj->>'active_status')::BOOLEAN, true)
                WHERE id = v_limit_id AND entity_id = v_reward_id AND merchant_id = v_merchant_id;
                IF FOUND THEN v_limits_updated := v_limits_updated + 1; v_limits_to_keep := array_append(v_limits_to_keep, v_limit_id); 
                ELSE v_limits_skipped := v_limits_skipped + 1; END IF;
            ELSE
                v_limit_id := gen_random_uuid();
                INSERT INTO transaction_limits (id, entity_id, entity_type, merchant_id, scope, count, time_unit, window_start, window_end, active_status, created_at)
                VALUES (v_limit_id, v_reward_id, 'reward', v_merchant_id, (v_limit_obj->>'scope')::reward_condition_scope, (v_limit_obj->>'count')::NUMERIC,
                    CASE WHEN v_limit_obj->>'time_unit' IS NULL OR v_limit_obj->>'time_unit' = '' THEN NULL ELSE (v_limit_obj->>'time_unit')::reward_condition_time_unit END,
                    v_window_start, v_window_end, COALESCE((v_limit_obj->>'active_status')::BOOLEAN, true), NOW());
                v_limits_created := v_limits_created + 1;
                v_limits_to_keep := array_append(v_limits_to_keep, v_limit_id);
            END IF;
        END LOOP;
        DELETE FROM transaction_limits WHERE entity_id = v_reward_id AND entity_type = 'reward' AND merchant_id = v_merchant_id AND id != ALL(v_limits_to_keep);
        GET DIAGNOSTICS v_limits_deleted = ROW_COUNT;
    ELSE
        DELETE FROM transaction_limits WHERE entity_id = v_reward_id AND entity_type = 'reward' AND merchant_id = v_merchant_id;
        GET DIAGNOSTICS v_limits_deleted = ROW_COUNT;
    END IF;

    RETURN jsonb_build_object(
        'success', true,
        'code', CASE WHEN v_parent_created THEN 'CREATED' ELSE 'UPDATED' END,
        'title', CASE WHEN v_parent_created THEN fn_admin_envelope_message('reward_created_title', v_lang) ELSE fn_admin_envelope_message('reward_updated_title', v_lang) END,
        'description', fn_admin_envelope_message('reward_action_desc', v_lang, ARRAY[v_reward_name, CASE WHEN v_parent_created THEN fn_admin_envelope_message('word_created', v_lang) ELSE fn_admin_envelope_message('word_updated', v_lang) END, (v_conditions_created + v_conditions_updated)::text, (v_limits_created + v_limits_updated)::text]),
        'reward_id', v_reward_id, 
        'parent_created', v_parent_created, 
        'parent_updated', v_parent_updated,
        'conditions_created', v_conditions_created, 
        'conditions_updated', v_conditions_updated, 
        'conditions_deleted', v_conditions_deleted, 
        'conditions_skipped', v_conditions_skipped,
        'limits_created', v_limits_created, 
        'limits_updated', v_limits_updated, 
        'limits_deleted', v_limits_deleted, 
        'limits_skipped', v_limits_skipped
    );
EXCEPTION WHEN OTHERS THEN 
    RETURN jsonb_build_object('success', false, 'code', 'ERROR', 'title', fn_admin_envelope_message('error_title', v_lang), 'description', SQLERRM, 'error', SQLERRM, 'detail', SQLSTATE);
END;
$function$;

DROP FUNCTION IF EXISTS public.bff_upsert_reward(jsonb);
