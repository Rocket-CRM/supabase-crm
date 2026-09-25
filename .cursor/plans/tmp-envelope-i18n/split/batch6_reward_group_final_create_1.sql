CREATE OR REPLACE FUNCTION public.bff_upsert_reward_group_with_limits(p_group_id uuid DEFAULT NULL::uuid, p_group_code text DEFAULT NULL::text, p_name text DEFAULT NULL::text, p_description text DEFAULT NULL::text, p_is_active boolean DEFAULT true, p_transaction_limits jsonb DEFAULT NULL::jsonb, p_language text DEFAULT 'en'::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
DECLARE
  v_lang text;
    v_merchant_id UUID;
    v_group_id UUID;
    v_group_name TEXT;
    v_parent_created BOOLEAN := false;
    v_parent_updated BOOLEAN := false;
    v_limits_created INT := 0;
    v_limits_updated INT := 0;
    v_limits_deleted INT := 0;
    v_limits_skipped INT := 0;
    v_limit_obj JSONB;
    v_limit_id UUID;
    v_limit_id_text TEXT;
    v_limits_to_keep UUID[] := ARRAY[]::UUID[];
    v_window_start TIMESTAMPTZ;
    v_window_end TIMESTAMPTZ;
    v_metric reward_limit_metric;
    v_scope reward_condition_scope;
    v_time_unit reward_condition_time_unit;
    v_count NUMERIC;
    -- For config guardrail
    v_max_distinct NUMERIC := NULL;
    v_group_qty_user NUMERIC := NULL;
BEGIN
  v_lang := fn_normalize_ui_language(p_language);
    v_merchant_id := get_current_merchant_id();
    IF v_merchant_id IS NULL THEN
        RETURN fn_response_error(fn_admin_envelope_message('error_title', v_lang), fn_admin_envelope_message('no_merchant_found_title', v_lang), 'NO_MERCHANT_CONTEXT');
    END IF;

    v_group_name := COALESCE(p_name, 'Untitled Group');

    -- ----------------------------------------------------------------
    -- Guardrail: reject contradictory config BEFORE touching the DB.
    -- max_distinct > group_quantity (scope=user) is unsatisfiable.
    -- ----------------------------------------------------------------
    IF p_transaction_limits IS NOT NULL AND jsonb_typeof(p_transaction_limits) = 'array' THEN
        FOR v_limit_obj IN SELECT * FROM jsonb_array_elements(p_transaction_limits) LOOP
            IF COALESCE((v_limit_obj->>'active_status')::BOOLEAN, true) = false THEN CONTINUE; END IF;

            v_metric := COALESCE(NULLIF(v_limit_obj->>'metric','')::reward_limit_metric, 'quantity');
            v_scope  := NULLIF(v_limit_obj->>'scope','')::reward_condition_scope;
            v_count  := NULLIF(v_limit_obj->>'count','')::NUMERIC;

            IF v_metric = 'distinct_reward' AND v_scope = 'user' THEN
                v_max_distinct := LEAST(COALESCE(v_max_distinct, v_count), v_count);
            ELSIF v_metric = 'quantity' AND v_scope = 'user' THEN
                v_group_qty_user := LEAST(COALESCE(v_group_qty_user, v_count), v_count);
            END IF;
        END LOOP;

        IF v_max_distinct IS NOT NULL AND v_group_qty_user IS NOT NULL
           AND v_max_distinct > v_group_qty_user THEN
            RETURN fn_response_error(
                fn_admin_envelope_message('invalid_configuration_title', v_lang),
                fn_admin_envelope_message('conflicting_group_limits_desc', v_lang, ARRAY[v_max_distinct::text, v_group_qty_user::text]),
                'CONFLICTING_GROUP_LIMITS'
            );
        END IF;
    END IF;

    -- ----------------------------------------------------------------
    -- Parent row
    -- ----------------------------------------------------------------
    IF p_group_id IS NULL THEN
        v_group_id := gen_random_uuid();
        INSERT INTO reward_group (id, merchant_id, group_code, name, description, is_active, created_at, updated_at)
        VALUES (v_group_id, v_merchant_id, p_group_code, v_group_name, p_description, p_is_active, NOW(), NOW());
        v_parent_created := true;
    ELSE
        v_group_id := p_group_id;
        UPDATE reward_group
        SET group_code = p_group_code,
            name = v_group_name,
            description = p_description,
            is_active = p_is_active,
            updated_at = NOW()
        WHERE id = v_group_id AND merchant_id = v_merchant_id;
        IF NOT FOUND THEN
            RETURN fn_response_error(fn_admin_envelope_message('not_found_title', v_lang), fn_admin_envelope_message('reward_group_not_found_desc', v_lang), 'NOT_FOUND');
        END IF;
        SELECT rg.name INTO v_group_name FROM reward_group rg WHERE rg.id = v_group_id;
        v_parent_updated := true;
    END IF;

    -- ----------------------------------------------------------------
    -- Upsert limits
    -- ----------------------------------------------------------------
    IF p_transaction_limits IS NOT NULL AND jsonb_typeof(p_transaction_limits) = 'array' AND jsonb_array_length(p_transaction_limits) > 0 THEN
        FOR v_limit_obj IN SELECT * FROM jsonb_array_elements(p_transaction_limits) LOOP
            v_limit_id_text := v_limit_obj->>'id';
            v_limit_id := CASE WHEN v_limit_id_text IS NULL OR v_limit_id_text = '' THEN NULL ELSE v_limit_id_text::UUID END;

            IF (v_limit_obj->>'scope') IS NULL OR v_limit_obj->>'scope' = '' OR (v_limit_obj->>'count') IS NULL THEN
                v_limits_skipped := v_limits_skipped + 1; CONTINUE;
            END IF;

            v_metric := COALESCE(NULLIF(v_limit_obj->>'metric','')::reward_limit_metric, 'quantity');
            v_scope  := (v_limit_obj->>'scope')::reward_condition_scope;
            v_count  := (v_limit_obj->>'count')::NUMERIC;
            v_time_unit := CASE WHEN v_limit_obj->>'time_unit' IS NULL OR v_limit_obj->>'time_unit' = ''
                                THEN NULL ELSE (v_limit_obj->>'time_unit')::reward_condition_time_unit END;
            v_window_start := CASE WHEN v_limit_obj->>'window_start' IS NULL OR v_limit_obj->>'window_start' = ''
                                   THEN NULL ELSE (v_limit_obj->>'window_start')::TIMESTAMPTZ END;
            v_window_end   := CASE WHEN v_limit_obj->>'window_end'   IS NULL OR v_limit_obj->>'window_end'   = ''
                                   THEN NULL ELSE (v_limit_obj->>'window_end')::TIMESTAMPTZ END;

            IF v_metric = 'distinct_reward' AND v_scope <> 'user' THEN
                -- enforced by CHECK but surface a friendly error
                RETURN fn_response_error(
                    fn_admin_envelope_message('invalid_configuration_title', v_lang),
                    fn_admin_envelope_message('invalid_metric_scope_desc', v_lang),
                    'INVALID_METRIC_SCOPE'
                );
            END IF;

            IF v_limit_id IS NOT NULL THEN
                UPDATE transaction_limits
                SET metric = v_metric,
                    scope = v_scope,
                    count = v_count,
                    time_unit = v_time_unit,
                    window_start = v_window_start,
                    window_end = v_window_end,
                    active_status = COALESCE((v_limit_obj->>'active_status')::BOOLEAN, true)
                WHERE id = v_limit_id AND entity_id = v_group_id AND merchant_id = v_merchant_id;
                IF FOUND THEN
                    v_limits_updated := v_limits_updated + 1;
                    v_limits_to_keep := array_append(v_limits_to_keep, v_limit_id);
                ELSE
                    v_limits_skipped := v_limits_skipped + 1;
                END IF;
            ELSE
                v_limit_id := gen_random_uuid();
                INSERT INTO transaction_limits (id, entity_id, entity_type, merchant_id, metric, scope, count, time_unit, window_start, window_end, active_status, created_at)
                VALUES (
                    v_limit_id, v_group_id, 'reward_group', v_merchant_id,
                    v_metric, v_scope, v_count, v_time_unit,
                    v_window_start, v_window_end,
                    COALESCE((v_limit_obj->>'active_status')::BOOLEAN, true),
                    NOW()
                );
                v_limits_created := v_limits_created + 1;
                v_limits_to_keep := array_append(v_limits_to_keep, v_limit_id);
            END IF;
        END LOOP;

        DELETE FROM transaction_limits
        WHERE entity_id = v_group_id AND entity_type = 'reward_group' AND merchant_id = v_merchant_id AND id != ALL(v_limits_to_keep);
        GET DIAGNOSTICS v_limits_deleted = ROW_COUNT;
    ELSE
        DELETE FROM transaction_limits
        WHERE entity_id = v_group_id AND entity_type = 'reward_group' AND merchant_id = v_merchant_id;
        GET DIAGNOSTICS v_limits_deleted = ROW_COUNT;
    END IF;

    RETURN jsonb_build_object(
        'success', true,
        'code', CASE WHEN v_parent_created THEN 'CREATED' ELSE 'UPDATED' END,
        'title', CASE WHEN v_parent_created THEN fn_admin_envelope_message('reward_group_created_title', v_lang) ELSE fn_admin_envelope_message('reward_group_updated_title', v_lang) END,
        'description', fn_admin_envelope_message('reward_group_action_desc', v_lang, ARRAY[v_group_name, CASE WHEN v_parent_created THEN fn_admin_envelope_message('word_created', v_lang) ELSE fn_admin_envelope_message('word_updated', v_lang) END, (v_limits_created + v_limits_updated)::text]),
        'group_id', v_group_id,
        'parent_created', v_parent_created,
        'parent_updated', v_parent_updated,
        'limits_created', v_limits_created,
        'limits_updated', v_limits_updated,
        'limits_deleted', v_limits_deleted
    );

EXCEPTION WHEN OTHERS THEN
    RETURN fn_response_error(fn_admin_envelope_message('error_title', v_lang), SQLERRM, 'ERROR');
END;
$function$;
