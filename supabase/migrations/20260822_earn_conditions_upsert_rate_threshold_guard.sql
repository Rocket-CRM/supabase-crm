-- Reject a real min_threshold on a conditions group linked to a rate.
-- Check before writes so a failed save does not persist the group/factor.

CREATE OR REPLACE FUNCTION public.bff_upsert_earn_conditions_group(p_config jsonb, p_language text DEFAULT 'en'::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
DECLARE
    v_lang text;
    v_group_id UUID;
    v_merchant_id UUID;
    v_group_name TEXT;
    v_condition JSONB;
    v_condition_ids UUID[] := '{}';
    v_condition_id UUID;
    v_group_existed BOOLEAN;
    v_condition_existed BOOLEAN;
    v_conditions_inserted INT := 0;
    v_conditions_updated INT := 0;
    v_conditions_deleted INT := 0;
    v_group_action TEXT;
BEGIN
    v_lang := fn_normalize_ui_language(p_language);
    v_group_id := NULLIF(p_config->>'id', '')::UUID;
    v_merchant_id := COALESCE(NULLIF(p_config->>'merchant_id', '')::UUID, get_current_merchant_id());
    v_group_name := COALESCE(NULLIF(p_config->>'name', ''), 'Untitled Conditions Group');

    IF v_group_id IS NULL THEN
        v_group_id := gen_random_uuid();
    END IF;

    IF v_merchant_id IS NULL THEN
        RETURN jsonb_build_object('success', false, 'code', 'VALIDATION_ERROR',
          'title', fn_admin_envelope_message('validation_error_title', v_lang),
          'description', fn_admin_envelope_message('missing_merchant_id_desc', v_lang));
    END IF;

    IF EXISTS (
        SELECT 1
        FROM jsonb_array_elements(COALESCE(p_config->'conditions', '[]'::jsonb)) c
        WHERE NULLIF(c->>'min_threshold', '') IS NOT NULL
          AND NULLIF(c->>'min_threshold', '')::numeric <> 0
    ) AND EXISTS (
        SELECT 1 FROM earn_factor f
        WHERE f.earn_conditions_group_id = v_group_id
          AND f.merchant_id = v_merchant_id
          AND f.earn_factor_type = 'rate'
    ) THEN
        RETURN jsonb_build_object(
            'success', false,
            'code', 'RATE_THRESHOLD_NOT_ALLOWED',
            'title', fn_admin_envelope_message('validation_error_title', v_lang),
            'description', CASE v_lang
                WHEN 'th' THEN 'เกณฑ์ขั้นต่ำใช้ได้เฉพาะตัวคูณ ไม่สามารถใส่เกณฑ์บนกลุ่มเงื่อนไขที่ผูกกับเรทได้'
                ELSE 'Thresholds apply only to multipliers. A conditions group linked to a rate cannot have a minimum threshold.'
            END
        );
    END IF;

    SELECT EXISTS(SELECT 1 FROM earn_conditions_group WHERE id = v_group_id) INTO v_group_existed;

    INSERT INTO earn_conditions_group (id, name, merchant_id, created_at)
    VALUES (
        v_group_id,
        v_group_name,
        v_merchant_id,
        COALESCE(NULLIF(p_config->>'created_at', '')::TIMESTAMPTZ, NOW())
    )
    ON CONFLICT (id) DO UPDATE SET
        name = EXCLUDED.name;

    v_group_action := CASE WHEN v_group_existed THEN 'updated' ELSE 'inserted' END;

    IF p_config->'conditions' IS NOT NULL AND jsonb_typeof(p_config->'conditions') = 'array' AND jsonb_array_length(p_config->'conditions') > 0 THEN
        FOR v_condition IN SELECT * FROM jsonb_array_elements(p_config->'conditions')
        LOOP
            v_condition_id := NULLIF(v_condition->>'id', '')::UUID;

            IF v_condition_id IS NULL THEN
                v_condition_id := gen_random_uuid();
                v_condition_existed := false;
            ELSE
                SELECT EXISTS(SELECT 1 FROM earn_conditions WHERE id = v_condition_id) INTO v_condition_existed;
            END IF;

            v_condition_ids := array_append(v_condition_ids, v_condition_id);

            INSERT INTO earn_conditions (
                id, group_id, entity, entity_ids, merchant_id, created_at,
                threshold_unit, min_threshold, max_threshold, apply_to_excess_only, operator, exclude
            )
            VALUES (
                v_condition_id,
                v_group_id,
                (v_condition->>'entity')::earn_factor_entity_type,
                CASE
                    WHEN v_condition->'entity_ids' IS NOT NULL AND jsonb_typeof(v_condition->'entity_ids') = 'array'
                    THEN ARRAY(SELECT jsonb_array_elements_text(v_condition->'entity_ids'))::UUID[]
                    ELSE ARRAY[]::UUID[]
                END,
                v_merchant_id,
                COALESCE(NULLIF(v_condition->>'created_at', '')::TIMESTAMPTZ, NOW()),
                NULLIF(v_condition->>'threshold_unit', ''),
                NULLIF(v_condition->>'min_threshold', '')::NUMERIC,
                NULLIF(v_condition->>'max_threshold', '')::NUMERIC,
                COALESCE((v_condition->>'apply_to_excess_only')::BOOLEAN, false),
                COALESCE(NULLIF(v_condition->>'operator', ''), 'OR'),
                COALESCE((v_condition->>'exclude')::BOOLEAN, false)
            )
            ON CONFLICT (id) DO UPDATE SET
                entity = EXCLUDED.entity,
                entity_ids = EXCLUDED.entity_ids,
                threshold_unit = EXCLUDED.threshold_unit,
                min_threshold = EXCLUDED.min_threshold,
                max_threshold = EXCLUDED.max_threshold,
                apply_to_excess_only = EXCLUDED.apply_to_excess_only,
                operator = EXCLUDED.operator,
                exclude = EXCLUDED.exclude;

            IF v_condition_existed THEN
                v_conditions_updated := v_conditions_updated + 1;
            ELSE
                v_conditions_inserted := v_conditions_inserted + 1;
            END IF;
        END LOOP;
    END IF;

    WITH deleted AS (
        DELETE FROM earn_conditions
        WHERE group_id = v_group_id
          AND (array_length(v_condition_ids, 1) IS NULL OR id != ALL(v_condition_ids))
        RETURNING id
    )
    SELECT COUNT(*) INTO v_conditions_deleted FROM deleted;

    RETURN jsonb_build_object(
        'success', true,
        'code', CASE WHEN v_group_action = 'inserted' THEN 'CREATED' ELSE 'UPDATED' END,
        'title', CASE WHEN v_group_action = 'inserted'
          THEN fn_admin_envelope_message('conditions_group_created_title', v_lang)
          ELSE fn_admin_envelope_message('conditions_group_updated_title', v_lang) END,
        'description', fn_admin_envelope_message('conditions_group_action_desc', v_lang, ARRAY[
            v_group_name,
            CASE WHEN v_group_action = 'inserted'
              THEN fn_admin_envelope_message('word_created', v_lang)
              ELSE fn_admin_envelope_message('word_updated', v_lang) END,
            (v_conditions_inserted + v_conditions_updated)::text
        ]),
        'group', jsonb_build_object(
            'id', v_group_id,
            'name', v_group_name,
            'action', v_group_action
        ),
        'conditions', jsonb_build_object(
            'inserted', v_conditions_inserted,
            'updated', v_conditions_updated,
            'deleted', v_conditions_deleted,
            'total', COALESCE(array_length(v_condition_ids, 1), 0)
        )
    );
EXCEPTION WHEN OTHERS THEN
    RETURN jsonb_build_object('success', false, 'code', 'ERROR',
      'title', fn_admin_envelope_message('error_title', v_lang),
      'description', SQLERRM, 'detail', SQLSTATE);
END;
$function$;

CREATE OR REPLACE FUNCTION public.bff_upsert_earn_factor_group(p_group_data jsonb, p_language text DEFAULT 'en'::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
DECLARE
  v_lang text;
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
  v_lang := fn_normalize_ui_language(p_language);
    v_merchant_id := get_current_merchant_id();
    IF v_merchant_id IS NULL THEN
        RETURN jsonb_build_object('success', false, 'code', 'NO_MERCHANT_CONTEXT', 'title', fn_admin_envelope_message('error_title', v_lang), 'description', fn_admin_envelope_message('no_merchant_found_title', v_lang));
    END IF;

    v_group_id := NULLIF(p_group_data->>'id', '')::UUID;
    v_group_name := COALESCE(NULLIF(p_group_data->>'name', ''), 'Untitled Group');
    v_perspective := COALESCE(NULLIF(p_group_data->>'perspective', ''), 'buyer');
    IF v_perspective NOT IN ('buyer', 'seller') THEN
        RETURN jsonb_build_object('success', false, 'code', 'INVALID_PERSPECTIVE', 'title', fn_admin_envelope_message('validation_error_title', v_lang), 'description', fn_admin_envelope_message('invalid_perspective_desc', v_lang, ARRAY[v_perspective]));
    END IF;

    IF p_group_data ? 'factors'
       AND jsonb_typeof(p_group_data->'factors') = 'array'
       AND EXISTS (
           SELECT 1
           FROM jsonb_array_elements(p_group_data->'factors') f
           WHERE NULLIF(f->>'earn_factor_type', '') = 'rate'
             AND NULLIF(f->>'earn_conditions_group_id', '') IS NOT NULL
             AND EXISTS (
                 SELECT 1 FROM earn_conditions ec
                 WHERE ec.group_id = NULLIF(f->>'earn_conditions_group_id', '')::uuid
                   AND ec.merchant_id = v_merchant_id
                   AND ec.min_threshold IS NOT NULL
                   AND ec.min_threshold <> 0
             )
       ) THEN
        RETURN jsonb_build_object(
            'success', false,
            'code', 'RATE_THRESHOLD_NOT_ALLOWED',
            'title', fn_admin_envelope_message('validation_error_title', v_lang),
            'description', CASE v_lang
                WHEN 'th' THEN 'เกณฑ์ขั้นต่ำใช้ได้เฉพาะตัวคูณ ไม่สามารถผูกเรทกับกลุ่มเงื่อนไขที่มีเกณฑ์ขั้นต่ำได้'
                ELSE 'Thresholds apply only to multipliers. A rate cannot link to a conditions group that has a minimum threshold.'
            END
        );
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
            RETURN jsonb_build_object('success', false, 'code', 'NOT_FOUND', 'title', fn_admin_envelope_message('not_found_title', v_lang), 'description', fn_admin_envelope_message('earn_factor_group_not_found_desc', v_lang));
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
                    RETURN jsonb_build_object('success', false, 'code', 'INVALID_AWARD_SCOPE', 'title', fn_admin_envelope_message('validation_error_title', v_lang), 'description', fn_admin_envelope_message('invalid_award_scope_desc', v_lang, ARRAY[v_award_scope]));
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
        'title', CASE WHEN v_group_created THEN fn_admin_envelope_message('earn_factor_group_created_title', v_lang) ELSE fn_admin_envelope_message('earn_factor_group_updated_title', v_lang) END,
        'description', fn_admin_envelope_message('earn_factor_group_action_desc', v_lang, ARRAY[v_group_name, CASE WHEN v_group_created THEN fn_admin_envelope_message('word_created', v_lang) ELSE fn_admin_envelope_message('word_updated', v_lang) END, (v_factors_created + v_factors_updated)::text]),
        'group_id', v_group_id,
        'group_created', v_group_created,
        'group_updated', v_group_updated,
        'factors_created', v_factors_created,
        'factors_updated', v_factors_updated,
        'factors_deleted', v_factors_deleted,
        'factors_skipped', v_factors_skipped
    );
EXCEPTION WHEN OTHERS THEN
    RETURN jsonb_build_object('success', false, 'code', 'ERROR', 'title', fn_admin_envelope_message('error_title', v_lang), 'description', SQLERRM, 'detail', SQLSTATE);
END;
$function$;
