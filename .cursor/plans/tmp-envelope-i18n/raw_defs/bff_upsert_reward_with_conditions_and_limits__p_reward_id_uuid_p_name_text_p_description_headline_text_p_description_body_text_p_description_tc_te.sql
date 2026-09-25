CREATE OR REPLACE FUNCTION public.bff_upsert_reward_with_conditions_and_limits(p_reward_id uuid DEFAULT NULL::uuid, p_name text DEFAULT NULL::text, p_description_headline text DEFAULT NULL::text, p_description_body text DEFAULT NULL::text, p_description_tc text DEFAULT NULL::text, p_description_slip text DEFAULT NULL::text, p_image jsonb DEFAULT NULL::jsonb, p_category_id jsonb DEFAULT NULL::jsonb, p_visibility reward_visibility DEFAULT NULL::reward_visibility, p_redeem_window_start timestamp with time zone DEFAULT NULL::timestamp with time zone, p_redeem_window_end timestamp with time zone DEFAULT NULL::timestamp with time zone, p_stock_control boolean DEFAULT false, p_assign_promocode boolean DEFAULT false, p_use_expire_mode reward_expire_mode DEFAULT NULL::reward_expire_mode, p_use_expire_date timestamp with time zone DEFAULT NULL::timestamp with time zone, p_use_expire_ttl numeric DEFAULT NULL::numeric, p_fulfillment_method reward_fulfillment_method DEFAULT NULL::reward_fulfillment_method, p_allowed_tier jsonb DEFAULT NULL::jsonb, p_allowed_persona jsonb DEFAULT NULL::jsonb, p_allowed_tags jsonb DEFAULT NULL::jsonb, p_allowed_birthmonth jsonb DEFAULT NULL::jsonb, p_fallback_points numeric DEFAULT NULL::numeric, p_require_points_match boolean DEFAULT false, p_points_conditions jsonb DEFAULT NULL::jsonb, p_transaction_limits jsonb DEFAULT NULL::jsonb, p_external_id_shopify text DEFAULT NULL::text, p_online_store jsonb DEFAULT NULL::jsonb, p_reward_group_ids jsonb DEFAULT NULL::jsonb, p_shopify_discount_type text DEFAULT NULL::text, p_shopify_discount_label text DEFAULT NULL::text, p_variant_config jsonb DEFAULT NULL::jsonb, p_physical_draw_name text DEFAULT NULL::text, p_physical_draw_description text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
DECLARE
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
    v_tier_id UUID;
    v_persona_id UUID;
    v_limit_obj JSONB;
    v_limit_id UUID;
    v_limit_id_text TEXT;
    v_conditions_to_keep UUID[] := ARRAY[]::UUID[];
    v_limits_to_keep UUID[] := ARRAY[]::UUID[];
    v_tag_ids UUID[];
    v_user_type user_type;
    v_window_start TIMESTAMPTZ;
    v_window_end TIMESTAMPTZ;
    v_category_id UUID[];
    v_allowed_tier UUID[];
    v_allowed_persona UUID[];
    v_allowed_tags UUID[];
    v_allowed_birthmonth TEXT[];
    v_image TEXT[];
    v_online_store TEXT[];
    v_reward_group_ids UUID[];
BEGIN
    v_merchant_id := get_current_merchant_id();
    IF v_merchant_id IS NULL THEN
        RETURN jsonb_build_object('success', false, 'code', 'NO_MERCHANT_CONTEXT', 'title', 'Error', 'description', 'No merchant context found');
    END IF;
    
    v_reward_name := COALESCE(p_name, 'Untitled Reward');
    v_category_id := CASE WHEN p_category_id IS NULL OR jsonb_typeof(p_category_id) != 'array' OR jsonb_array_length(p_category_id) = 0 THEN NULL ELSE (SELECT ARRAY_AGG(value::text::uuid) FROM jsonb_array_elements_text(p_category_id)) END;
    v_allowed_tier := CASE WHEN p_allowed_tier IS NULL OR jsonb_typeof(p_allowed_tier) != 'array' OR jsonb_array_length(p_allowed_tier) = 0 THEN NULL ELSE (SELECT ARRAY_AGG(value::text::uuid) FROM jsonb_array_elements_text(p_allowed_tier)) END;
    v_allowed_persona := CASE WHEN p_allowed_persona IS NULL OR jsonb_typeof(p_allowed_persona) != 'array' OR jsonb_array_length(p_allowed_persona) = 0 THEN NULL ELSE (SELECT ARRAY_AGG(value::text::uuid) FROM jsonb_array_elements_text(p_allowed_persona)) END;
    v_allowed_tags := CASE WHEN p_allowed_tags IS NULL OR jsonb_typeof(p_allowed_tags) != 'array' OR jsonb_array_length(p_allowed_tags) = 0 THEN NULL ELSE (SELECT ARRAY_AGG(value::text::uuid) FROM jsonb_array_elements_text(p_allowed_tags)) END;
    v_allowed_birthmonth := CASE WHEN p_allowed_birthmonth IS NULL OR jsonb_typeof(p_allowed_birthmonth) != 'array' OR jsonb_array_length(p_allowed_birthmonth) = 0 THEN NULL ELSE (SELECT ARRAY_AGG(value::text) FROM jsonb_array_elements_text(p_allowed_birthmonth)) END;
    v_image := CASE WHEN p_image IS NULL OR jsonb_typeof(p_image) != 'array' OR jsonb_array_length(p_image) = 0 THEN NULL ELSE (SELECT ARRAY_AGG(value::text) FROM jsonb_array_elements_text(p_image)) END;
    v_online_store := CASE WHEN p_online_store IS NULL OR jsonb_typeof(p_online_store) != 'array' OR jsonb_array_length(p_online_store) = 0 THEN NULL ELSE (SELECT ARRAY_AGG(value::text) FROM jsonb_array_elements_text(p_online_store)) END;
    v_reward_group_ids := CASE WHEN p_reward_group_ids IS NULL OR jsonb_typeof(p_reward_group_ids) != 'array' OR jsonb_array_length(p_reward_group_ids) = 0 THEN NULL ELSE (SELECT ARRAY_AGG(value::text::uuid) FROM jsonb_array_elements_text(p_reward_group_ids)) END;
    
    IF p_reward_id IS NULL THEN
        v_reward_id := gen_random_uuid();
        INSERT INTO reward_master (id, merchant_id, name, description_headline, description_body, description_tc, description_slip, image, category_id, visibility, redeem_window_start, redeem_window_end, stock_control, assign_promocode, use_expire_mode, use_expire_date, use_expire_ttl, fulfillment_method, allowed_tier, allowed_persona, allowed_tags, allowed_birthmonth, fallback_points, require_points_match, external_id_shopify, online_store, reward_group_ids, shopify_discount_type, shopify_discount_label, variant_config, physical_draw_name, physical_draw_description, created_at)
        VALUES (v_reward_id, v_merchant_id, p_name, p_description_headline, p_description_body, p_description_tc, p_description_slip, v_image, v_category_id, p_visibility, p_redeem_window_start, p_redeem_window_end, p_stock_control, p_assign_promocode, p_use_expire_mode, p_use_expire_date, p_use_expire_ttl, p_fulfillment_method, v_allowed_tier, v_allowed_persona, v_allowed_tags, v_allowed_birthmonth, p_fallback_points, p_require_points_match, p_external_id_shopify, v_online_store, v_reward_group_ids, p_shopify_discount_type, p_shopify_discount_label, p_variant_config, p_physical_draw_name, p_physical_draw_description, NOW());
        v_parent_created := true;
    ELSE
        v_reward_id := p_reward_id;
        UPDATE reward_master SET name = p_name, description_headline = p_description_headline, description_body = p_description_body, description_tc = p_description_tc, description_slip = p_description_slip, image = v_image, category_id = v_category_id, visibility = p_visibility, redeem_window_start = p_redeem_window_start, redeem_window_end = p_redeem_window_end, stock_control = p_stock_control, assign_promocode = p_assign_promocode, use_expire_mode = p_use_expire_mode, use_expire_date = p_use_expire_date, use_expire_ttl = p_use_expire_ttl, fulfillment_method = p_fulfillment_method, allowed_tier = v_allowed_tier, allowed_persona = v_allowed_persona, allowed_tags = v_allowed_tags, allowed_birthmonth = v_allowed_birthmonth, fallback_points = p_fallback_points, require_points_match = p_require_points_match, external_id_shopify = p_external_id_shopify, online_store = v_online_store, reward_group_ids = v_reward_group_ids,
          shopify_discount_type = COALESCE(p_shopify_discount_type, shopify_discount_type),
          shopify_discount_label = COALESCE(p_shopify_discount_label, shopify_discount_label),
          variant_config = p_variant_config,
          physical_draw_name = p_physical_draw_name,
          physical_draw_description = p_physical_draw_description
        WHERE id = v_reward_id AND merchant_id = v_merchant_id;
        IF NOT FOUND THEN RETURN jsonb_build_object('success', false, 'code', 'NOT_FOUND', 'title', 'Not Found', 'description', 'Reward not found or access denied'); END IF;
        SELECT rm.name INTO v_reward_name FROM reward_master rm WHERE rm.id = v_reward_id;
        v_parent_updated := true;
    END IF;
    
    IF p_points_conditions IS NOT NULL AND jsonb_typeof(p_points_conditions) = 'array' AND jsonb_array_length(p_points_conditions) > 0 THEN
        FOR v_condition_obj IN SELECT * FROM jsonb_array_elements(p_points_conditions) LOOP
            v_condition_id := CASE WHEN v_condition_obj->>'id' IS NULL OR v_condition_obj->>'id' = '' THEN NULL ELSE (v_condition_obj->>'id')::UUID END;
            v_tier_id := CASE WHEN v_condition_obj->>'tier_id' IS NULL OR v_condition_obj->>'tier_id' = '' THEN NULL ELSE (v_condition_obj->>'tier_id')::UUID END;
            v_persona_id := CASE WHEN v_condition_obj->>'persona_id' IS NULL OR v_condition_obj->>'persona_id' = '' THEN NULL ELSE (v_condition_obj->>'persona_id')::UUID END;
            IF (v_condition_obj->>'points_required') IS NULL THEN v_conditions_skipped := v_conditions_skipped + 1; CONTINUE; END IF;
            v_tag_ids := NULL;
            IF v_condition_obj->'tag_ids' IS NOT NULL AND jsonb_typeof(v_condition_obj->'tag_ids') = 'array' THEN
                v_tag_ids := (SELECT ARRAY_AGG(value::text::uuid) FROM jsonb_array_elements_text(v_condition_obj->'tag_ids'));
            END IF;
            v_user_type := CASE WHEN v_condition_obj->>'user_type' IS NULL OR v_condition_obj->>'user_type' = '' THEN NULL ELSE (v_condition_obj->>'user_type')::user_type END;
            IF v_condition_id IS NOT NULL THEN
                UPDATE reward_points_conditions SET tier_id = v_tier_id, user_type = v_user_type, persona_id = v_persona_id, tag_ids = v_tag_ids, points_required = (v_condition_obj->>'points_required')::NUMERIC, priority = COALESCE((v_condition_obj->>'priority')::INTEGER, 100), condition_name = v_condition_obj->>'condition_name', description = v_condition_obj->>'description', active_status = COALESCE((v_condition_obj->>'active_status')::BOOLEAN, true), updated_at = NOW()
                WHERE id = v_condition_id AND reward_id = v_reward_id AND merchant_id = v_merchant_id;
                IF FOUND THEN v_conditions_updated := v_conditions_updated + 1; v_conditions_to_keep := array_append(v_conditions_to_keep, v_condition_id); ELSE v_conditions_skipped := v_conditions_skipped + 1; END IF;
            ELSE
                v_condition_id := gen_random_uuid();
                INSERT INTO reward_points_conditions (id, reward_id, merchant_id, tier_id, user_type, persona_id, tag_ids, points_required, priority, condition_name, description, active_status, created_at, updated_at)
                VALUES (v_condition_id, v_reward_id, v_merchant_id, v_tier_id, v_user_type, v_persona_id, v_tag_ids, (v_condition_obj->>'points_required')::NUMERIC, COALESCE((v_condition_obj->>'priority')::INTEGER, 100), v_condition_obj->>'condition_name', v_condition_obj->>'description', COALESCE((v_condition_obj->>'active_status')::BOOLEAN, true), NOW(), NOW());
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
    
    IF p_transaction_limits IS NOT NULL AND jsonb_typeof(p_transaction_limits) = 'array' AND jsonb_array_length(p_transaction_limits) > 0 THEN
        FOR v_limit_obj IN SELECT * FROM jsonb_array_elements(p_transaction_limits) LOOP
            v_limit_id_text := v_limit_obj->>'id';
            v_limit_id := CASE WHEN v_limit_id_text IS NULL OR v_limit_id_text = '' THEN NULL ELSE v_limit_id_text::UUID END;
            IF (v_limit_obj->>'scope') IS NULL OR v_limit_obj->>'scope' = '' OR (v_limit_obj->>'count') IS NULL THEN v_limits_skipped := v_limits_skipped + 1; CONTINUE; END IF;
            v_window_start := CASE WHEN v_limit_obj->>'window_start' IS NULL OR v_limit_obj->>'window_start' = '' THEN NULL ELSE (v_limit_obj->>'window_start')::TIMESTAMPTZ END;
            v_window_end := CASE WHEN v_limit_obj->>'window_end' IS NULL OR v_limit_obj->>'window_end' = '' THEN NULL ELSE (v_limit_obj->>'window_end')::TIMESTAMPTZ END;
            IF v_limit_id IS NOT NULL THEN
                UPDATE transaction_limits SET scope = (v_limit_obj->>'scope')::reward_condition_scope, count = (v_limit_obj->>'count')::NUMERIC, time_unit = CASE WHEN v_limit_obj->>'time_unit' IS NULL OR v_limit_obj->>'time_unit' = '' THEN NULL ELSE (v_limit_obj->>'time_unit')::reward_condition_time_unit END, window_start = v_window_start, window_end = v_window_end, active_status = COALESCE((v_limit_obj->>'active_status')::BOOLEAN, true)
                WHERE id = v_limit_id AND entity_id = v_reward_id AND merchant_id = v_merchant_id;
                IF FOUND THEN v_limits_updated := v_limits_updated + 1; v_limits_to_keep := array_append(v_limits_to_keep, v_limit_id); ELSE v_limits_skipped := v_limits_skipped + 1; END IF;
            ELSE
                v_limit_id := gen_random_uuid();
                INSERT INTO transaction_limits (id, entity_id, entity_type, merchant_id, scope, count, time_unit, window_start, window_end, active_status, created_at)
                VALUES (v_limit_id, v_reward_id, 'reward', v_merchant_id, (v_limit_obj->>'scope')::reward_condition_scope, (v_limit_obj->>'count')::NUMERIC, CASE WHEN v_limit_obj->>'time_unit' IS NULL OR v_limit_obj->>'time_unit' = '' THEN NULL ELSE (v_limit_obj->>'time_unit')::reward_condition_time_unit END, v_window_start, v_window_end, COALESCE((v_limit_obj->>'active_status')::BOOLEAN, true), NOW());
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
        'title', CASE WHEN v_parent_created THEN 'Reward Created' ELSE 'Reward Updated' END,
        'description', format('Reward "%s" %s with %s price tiers and %s limits', 
            v_reward_name,
            CASE WHEN v_parent_created THEN 'created' ELSE 'updated' END,
            v_conditions_created + v_conditions_updated,
            v_limits_created + v_limits_updated),
        'reward_id', v_reward_id, 
        'parent_created', v_parent_created, 
        'parent_updated', v_parent_updated, 
        'conditions_created', v_conditions_created, 
        'conditions_updated', v_conditions_updated, 
        'conditions_deleted', v_conditions_deleted, 
        'limits_created', v_limits_created, 
        'limits_updated', v_limits_updated, 
        'limits_deleted', v_limits_deleted
    );
EXCEPTION WHEN OTHERS THEN 
    RETURN jsonb_build_object('success', false, 'code', 'ERROR', 'title', 'Error', 'description', SQLERRM, 'detail', SQLSTATE);
END;
$function$
