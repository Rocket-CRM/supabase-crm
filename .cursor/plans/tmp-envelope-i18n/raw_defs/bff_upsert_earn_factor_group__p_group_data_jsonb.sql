CREATE OR REPLACE FUNCTION public.bff_upsert_earn_factor_group(p_group_data jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
DECLARE
    v_merchant_id UUID;
    v_group_id UUID;
    v_group_name TEXT;
    v_group_created BOOLEAN := false;
    v_group_updated BOOLEAN := false;
    v_factors_created INTEGER := 0;
    v_factors_updated INTEGER := 0;
    v_factors_deleted INTEGER := 0;
    v_factors_skipped INTEGER := 0;
    v_factor JSONB;
    v_factor_id UUID;
    v_factor_id_text TEXT;
    v_factor_ids_to_keep UUID[] := ARRAY[]::UUID[];
    v_allowed_statuses TEXT[];
    v_award_scope TEXT;
    v_item_statuses TEXT[];
    v_perspective TEXT;
BEGIN
    v_merchant_id := get_current_merchant_id();
    IF v_merchant_id IS NULL THEN
        RETURN jsonb_build_object('success', false, 'code', 'NO_MERCHANT_CONTEXT', 'title', 'Error', 'description', 'No merchant context found');
    END IF;

    v_group_id := NULLIF(p_group_data->>'id', '')::UUID;
    v_group_name := COALESCE(NULLIF(p_group_data->>'name', ''), 'Untitled Group');
    v_perspective := COALESCE(NULLIF(p_group_data->>'perspective', ''), 'buyer');
    IF v_perspective NOT IN ('buyer', 'seller') THEN
        RETURN jsonb_build_object('success', false, 'code', 'INVALID_PERSPECTIVE', 'title', 'Validation Error', 'description', 'Invalid perspective: "' || v_perspective || '". Must be one of: buyer, seller.');
    END IF;

    IF v_group_id IS NULL THEN
        v_group_id := gen_random_uuid();
        INSERT INTO earn_factor_group (id, merchant_id, name, stackable, perspective, window_start, window_end, active_status)
        VALUES (
            v_group_id, v_merchant_id, v_group_name,
            COALESCE(NULLIF(p_group_data->>'stackable', '')::BOOLEAN, true),
            v_perspective,
            NULLIF(p_group_data->>'window_start', '')::TIMESTAMPTZ,
            NULLIF(p_group_data->>'window_end', '')::TIMESTAMPTZ,
            COALESCE(NULLIF(p_group_data->>'active_status', '')::BOOLEAN, true)
        );
        v_group_created := true;
    ELSE
        UPDATE earn_factor_group
        SET name = COALESCE(NULLIF(p_group_data->>'name', ''), name),
            stackable = COALESCE(NULLIF(p_group_data->>'stackable', '')::BOOLEAN, stackable),
            perspective = v_perspective,
            window_start = COALESCE(NULLIF(p_group_data->>'window_start', '')::TIMESTAMPTZ, window_start),
            window_end = COALESCE(NULLIF(p_group_data->>'window_end', '')::TIMESTAMPTZ, window_end),
            active_status = COALESCE(NULLIF(p_group_data->>'active_status', '')::BOOLEAN, active_status)
        WHERE id = v_group_id AND merchant_id = v_merchant_id;
        IF NOT FOUND THEN
            RETURN jsonb_build_object('success', false, 'code', 'NOT_FOUND', 'title', 'Not Found', 'description', 'Earn factor group not found or access denied');
        END IF;
        SELECT name INTO v_group_name FROM earn_factor_group WHERE id = v_group_id;
        v_group_updated := true;
    END IF;

    IF p_group_data ? 'factors' THEN
        IF jsonb_array_length(p_group_data->'factors') > 0 THEN
            FOR v_factor IN SELECT * FROM jsonb_array_elements(p_group_data->'factors') LOOP
                v_factor_id_text := v_factor->>'id';
                v_factor_id := NULLIF(v_factor_id_text, '')::UUID;

                IF NULLIF(v_factor->>'earn_factor_type', '') IS NULL THEN
                    v_factors_skipped := v_factors_skipped + 1;
                    CONTINUE;
                END IF;

                v_allowed_statuses := CASE
                    WHEN v_factor ? 'allowed_purchase_statuses'
                         AND jsonb_typeof(v_factor->'allowed_purchase_statuses') = 'array'
                         AND jsonb_array_length(v_factor->'allowed_purchase_statuses') > 0
                    THEN ARRAY(SELECT jsonb_array_elements_text(v_factor->'allowed_purchase_statuses'))
                    ELSE NULL
                END;

                v_award_scope := NULLIF(v_factor->>'award_scope', '');
                IF v_award_scope IS NOT NULL AND v_award_scope NOT IN ('purchase','purchase_item') THEN
                    RETURN jsonb_build_object('success', false, 'code', 'INVALID_AWARD_SCOPE', 'title', 'Validation Error', 'description', 'Invalid award_scope: "' || v_award_scope || '". Must be one of: purchase, purchase_item.');
                END IF;

                v_item_statuses := CASE
                    WHEN v_factor ? 'allowed_item_statuses'
                         AND jsonb_typeof(v_factor->'allowed_item_statuses') = 'array'
                         AND jsonb_array_length(v_factor->'allowed_item_statuses') > 0
                    THEN ARRAY(SELECT jsonb_array_elements_text(v_factor->'allowed_item_statuses'))
                    ELSE NULL
                END;

                IF v_factor_id IS NOT NULL THEN
                    UPDATE earn_factor
                    SET earn_factor_type = (NULLIF(v_factor->>'earn_factor_type', ''))::earn_factor_type,
                        earn_factor_amount = NULLIF(v_factor->>'earn_factor_amount', '')::NUMERIC,
                        target_currency = NULLIF(v_factor->>'target_currency', '')::currency,
                        target_entity_id = NULLIF(v_factor->>'target_entity_id', '')::UUID,
                        public = COALESCE(NULLIF(v_factor->>'public', '')::BOOLEAN, true),
                        window_start = NULLIF(v_factor->>'window_start', '')::TIMESTAMPTZ,
                        window_end = NULLIF(v_factor->>'window_end', '')::TIMESTAMPTZ,
                        window_end_ttl_days = NULLIF(v_factor->>'window_end_ttl_days', '')::NUMERIC,
                        active_status = COALESCE(NULLIF(v_factor->>'active_status', '')::BOOLEAN, true),
                        has_time_conditions = COALESCE(NULLIF(v_factor->>'has_time_conditions', '')::BOOLEAN, false),
                        earn_conditions_group_id = NULLIF(v_factor->>'earn_conditions_group_id', '')::UUID,
                        allowed_purchase_statuses = COALESCE(v_allowed_statuses, allowed_purchase_statuses),
                        award_scope = COALESCE(v_award_scope, award_scope),
                        allowed_item_statuses = COALESCE(v_item_statuses, allowed_item_statuses)
                    WHERE id = v_factor_id AND earn_factor_group_id = v_group_id AND merchant_id = v_merchant_id;
                    IF FOUND THEN
                        v_factors_updated := v_factors_updated + 1;
                        v_factor_ids_to_keep := array_append(v_factor_ids_to_keep, v_factor_id);
                    END IF;
                ELSE
                    v_factor_id := gen_random_uuid();
                    INSERT INTO earn_factor (
                        id, merchant_id, earn_factor_group_id, earn_factor_type, earn_factor_amount,
                        target_currency, target_entity_id, public, window_start, window_end,
                        window_end_ttl_days, active_status, has_time_conditions, earn_conditions_group_id,
                        allowed_purchase_statuses, award_scope, allowed_item_statuses
                    ) VALUES (
                        v_factor_id, v_merchant_id, v_group_id,
                        (NULLIF(v_factor->>'earn_factor_type', ''))::earn_factor_type,
                        NULLIF(v_factor->>'earn_factor_amount', '')::NUMERIC,
                        NULLIF(v_factor->>'target_currency', '')::currency,
                        NULLIF(v_factor->>'target_entity_id', '')::UUID,
                        COALESCE(NULLIF(v_factor->>'public', '')::BOOLEAN, true),
                        NULLIF(v_factor->>'window_start', '')::TIMESTAMPTZ,
                        NULLIF(v_factor->>'window_end', '')::TIMESTAMPTZ,
                        NULLIF(v_factor->>'window_end_ttl_days', '')::NUMERIC,
                        COALESCE(NULLIF(v_factor->>'active_status', '')::BOOLEAN, true),
                        COALESCE(NULLIF(v_factor->>'has_time_conditions', '')::BOOLEAN, false),
                        NULLIF(v_factor->>'earn_conditions_group_id', '')::UUID,
                        COALESCE(v_allowed_statuses, ARRAY['completed']::text[]),
                        COALESCE(v_award_scope, 'purchase'),
                        COALESCE(v_item_statuses, ARRAY['completed']::text[])
                    );
                    v_factors_created := v_factors_created + 1;
                    v_factor_ids_to_keep := array_append(v_factor_ids_to_keep, v_factor_id);
                END IF;
            END LOOP;
        END IF;

        DELETE FROM earn_factor
        WHERE earn_factor_group_id = v_group_id AND merchant_id = v_merchant_id
          AND id != ALL(v_factor_ids_to_keep);
        GET DIAGNOSTICS v_factors_deleted = ROW_COUNT;
    END IF;

    RETURN jsonb_build_object(
        'success', true,
        'code', CASE WHEN v_group_created THEN 'CREATED' ELSE 'UPDATED' END,
        'title', CASE WHEN v_group_created THEN 'Earn Factor Group Created' ELSE 'Earn Factor Group Updated' END,
        'description', format('Earn factor group "%s" %s with %s factors', v_group_name, CASE WHEN v_group_created THEN 'created' ELSE 'updated' END, v_factors_created + v_factors_updated),
        'group_id', v_group_id,
        'group_created', v_group_created,
        'group_updated', v_group_updated,
        'factors_created', v_factors_created,
        'factors_updated', v_factors_updated,
        'factors_deleted', v_factors_deleted,
        'factors_skipped', v_factors_skipped
    );
EXCEPTION WHEN OTHERS THEN
    RETURN jsonb_build_object('success', false, 'code', 'ERROR', 'title', 'Error', 'description', SQLERRM, 'detail', SQLSTATE);
END;
$function$
