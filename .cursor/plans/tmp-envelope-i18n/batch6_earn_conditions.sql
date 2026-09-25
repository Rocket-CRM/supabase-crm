-- bff_upsert_earn_conditions_group + drop old
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

DROP FUNCTION IF EXISTS public.bff_upsert_earn_conditions_group(jsonb);
