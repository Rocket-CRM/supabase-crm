CREATE OR REPLACE FUNCTION public.bff_upsert_form(p_data jsonb, p_language text DEFAULT 'en'::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET statement_timeout TO '30s'
AS $function$
DECLARE
  v_lang text;
    v_merchant_id UUID;
    v_form JSONB;
    v_form_id UUID;
    v_is_create BOOLEAN;
    v_code TEXT;
    v_allow_bulk_import BOOLEAN;
    v_existing_code TEXT;

    v_group JSONB;
    v_group_id UUID;
    v_default_group_id UUID;
    v_groups_to_keep UUID[] := ARRAY[]::UUID[];
    v_groups_created INTEGER := 0;
    v_groups_updated INTEGER := 0;
    v_groups_deleted INTEGER := 0;

    v_field JSONB;
    v_field_id UUID;
    v_field_group_id UUID;
    v_fields_to_keep UUID[] := ARRAY[]::UUID[];
    v_fields_created INTEGER := 0;
    v_fields_updated INTEGER := 0;
    v_fields_deleted INTEGER := 0;

    v_option JSONB;
    v_option_id UUID;
    v_options_to_keep UUID[] := ARRAY[]::UUID[];
    v_option_index INTEGER;

    v_condition JSONB;
    v_condition_id UUID;
    v_conditions_to_keep UUID[] := ARRAY[]::UUID[];
    v_conditions_created INTEGER := 0;
    v_conditions_updated INTEGER := 0;
    v_conditions_deleted INTEGER := 0;

    v_limit JSONB;
    v_limit_id UUID;
    v_limits_to_keep UUID[] := ARRAY[]::UUID[];
    v_limits_created INTEGER := 0;
    v_limits_updated INTEGER := 0;
    v_limits_deleted INTEGER := 0;

    v_group_index INTEGER;
    v_field_index INTEGER;
    v_has_fields BOOLEAN;
BEGIN
  v_lang := fn_normalize_ui_language(p_language);
    v_merchant_id := get_current_merchant_id();

    IF v_merchant_id IS NULL THEN
        RETURN jsonb_build_object('success', false, 'title', fn_admin_envelope_message('no_merchant_title', v_lang), 'description', fn_admin_envelope_message('unable_merchant_auth_desc', v_lang), 'data', null);
    END IF;

    PERFORM set_config('app.defer_profile_cache_invalidation', 'on', true);

    v_form := p_data->'form';
    IF v_form IS NULL THEN
        RETURN jsonb_build_object('success', false, 'title', fn_admin_envelope_message('invalid_payload_title', v_lang), 'description', fn_admin_envelope_message('missing_form_object_desc', v_lang), 'data', null);
    END IF;

    v_form_id := (v_form->>'id')::UUID;
    v_is_create := (v_form_id IS NULL);
    v_code := v_form->>'code';

    IF v_is_create THEN
        IF v_form ? 'allow_bulk_import' THEN
            v_allow_bulk_import := COALESCE((v_form->>'allow_bulk_import')::boolean, false);
        ELSE
            v_allow_bulk_import := false;
        END IF;
    ELSE
        SELECT code INTO v_existing_code FROM form_templates WHERE id = v_form_id;
        IF v_existing_code IS NULL THEN
            RETURN jsonb_build_object('success', false, 'title', fn_admin_envelope_message('form_not_found_title', v_lang), 'description', fn_admin_envelope_message('form_not_exist_desc', v_lang), 'data', null);
        END IF;
        v_code := COALESCE(v_code, v_existing_code);
        IF v_form ? 'allow_bulk_import' THEN
            v_allow_bulk_import := COALESCE((v_form->>'allow_bulk_import')::boolean, false);
        ELSE
            SELECT allow_bulk_import INTO v_allow_bulk_import FROM form_templates WHERE id = v_form_id;
        END IF;
    END IF;
    IF v_code = 'USER_PROFILE' THEN
        v_allow_bulk_import := true;
    END IF;

    IF v_is_create THEN
        INSERT INTO form_templates (merchant_id, code, name, description, status, allow_bulk_import)
        VALUES (
            v_merchant_id,
            v_code,
            v_form->>'name',
            v_form->>'description',
            COALESCE((v_form->>'status')::form_status, 'draft'),
            v_allow_bulk_import
        )
        RETURNING id INTO v_form_id;
    ELSE
        IF NOT EXISTS (
            SELECT 1 FROM form_templates
            WHERE id = v_form_id AND merchant_id = v_merchant_id
        ) THEN
            RETURN jsonb_build_object('success', false, 'title', fn_admin_envelope_message('unauthorized_title', v_lang), 'description', fn_admin_envelope_message('form_not_found_merchant_desc', v_lang), 'data', null);
        END IF;

        UPDATE form_templates
        SET code = v_form->>'code',
            name = v_form->>'name',
            description = v_form->>'description',
            status = (v_form->>'status')::form_status,
            allow_bulk_import = v_allow_bulk_import,
            updated_at = NOW()
        WHERE id = v_form_id;
    END IF;

    v_group_index := 0;
    FOR v_group IN SELECT * FROM jsonb_array_elements(COALESCE(p_data->'groups', '[]'::jsonb))
    LOOP
        IF v_group->>'id' IS NOT NULL AND v_group->>'id' != '' AND v_group->>'id' != 'null' THEN
            v_group_id := (v_group->>'id')::UUID;
            UPDATE form_field_groups
            SET group_key = v_group->>'group_key',
                group_name = v_group->>'group_name',
                order_index = v_group_index,
                require_at_least_one = COALESCE((v_group->>'require_at_least_one')::BOOLEAN, false)
            WHERE id = v_group_id AND form_id = v_form_id;
            v_groups_to_keep := array_append(v_groups_to_keep, v_group_id);
            v_groups_updated := v_groups_updated + 1;
        ELSE
            INSERT INTO form_field_groups (form_id, group_key, group_name, order_index, require_at_least_one)
            VALUES (v_form_id, v_group->>'group_key', v_group->>'group_name', v_group_index, COALESCE((v_group->>'require_at_least_one')::BOOLEAN, false))
            RETURNING id INTO v_group_id;
            v_groups_to_keep := array_append(v_groups_to_keep, v_group_id);
            v_groups_created := v_groups_created + 1;
        END IF;
        v_group_index := v_group_index + 1;
    END LOOP;

    v_has_fields := jsonb_array_length(COALESCE(p_data->'fields', '[]'::jsonb)) > 0;
    IF array_length(v_groups_to_keep, 1) IS NULL AND v_has_fields THEN
        SELECT id INTO v_default_group_id FROM form_field_groups WHERE form_id = v_form_id AND group_key = 'default_fields' LIMIT 1;
        IF v_default_group_id IS NULL THEN
            INSERT INTO form_field_groups (form_id, group_key, group_name, order_index, require_at_least_one)
            VALUES (v_form_id, 'default_fields', 'Fields', 0, false) RETURNING id INTO v_default_group_id;
            v_groups_created := v_groups_created + 1;
        END IF;
        v_groups_to_keep := array_append(v_groups_to_keep, v_default_group_id);
    END IF;

    DELETE FROM form_field_groups
    WHERE form_id = v_form_id
      AND id != ALL(v_groups_to_keep)
      AND NOT EXISTS (SELECT 1 FROM form_fields ff WHERE ff.group_id = form_field_groups.id AND ff.deleted_at IS NULL);
    GET DIAGNOSTICS v_groups_deleted = ROW_COUNT;

    v_field_index := 0;
    FOR v_field IN SELECT * FROM jsonb_array_elements(COALESCE(p_data->'fields', '[]'::jsonb))
    LOOP
        IF v_field->>'group_id' IS NOT NULL AND v_field->>'group_id' != '' AND v_field->>'group_id' != 'null' THEN
            v_field_group_id := (v_field->>'group_id')::UUID;
        ELSE
            v_field_group_id := v_default_group_id;
        END IF;

        IF v_field->>'id' IS NOT NULL AND v_field->>'id' != '' AND v_field->>'id' != 'null' THEN
            v_field_id := (v_field->>'id')::UUID;
            UPDATE form_fields
            SET field_key = v_field->>'field_key',
                field_type = (v_field->>'field_type')::field_type_simplified,
                text_format = (v_field->>'text_format')::text_format_type,
                label = v_field->>'label',
                group_id = v_field_group_id,
                position_after = v_field->>'position_after',
                order_index = v_field_index,
                is_required = COALESCE((v_field->>'is_required')::BOOLEAN, false),
                placeholder = v_field->>'placeholder',
                help_text = v_field->>'help_text',
                regex_pattern = v_field->>'regex_pattern',
                min_value = (v_field->>'min_value')::NUMERIC,
                max_value = (v_field->>'max_value')::NUMERIC,
                min_selections = (v_field->>'min_selections')::INTEGER,
                max_selections = (v_field->>'max_selections')::INTEGER,
                deleted_at = NULL,
                persona_ids = CASE
                    WHEN v_field->'persona_ids' IS NULL
                         OR v_field->'persona_ids' = 'null'::jsonb
                         OR v_field->'persona_ids' @> '"all"'::jsonb
                    THEN NULL
                    ELSE ARRAY(SELECT jsonb_array_elements_text(v_field->'persona_ids'))::UUID[]
                END
            WHERE id = v_field_id AND form_id = v_form_id;
            v_fields_updated := v_fields_updated + 1;
        ELSE
            INSERT INTO form_fields (
                form_id, field_key, field_type, text_format, label, group_id,
                position_after, order_index, is_required, placeholder, help_text,
                regex_pattern, min_value, max_value, min_selections, max_selections, persona_ids
            ) VALUES (
                v_form_id, v_field->>'field_key', (v_field->>'field_type')::field_type_simplified, (v_field->>'text_format')::text_format_type,
                v_field->>'label', v_field_group_id, v_field->>'position_after', v_field_index,
                COALESCE((v_field->>'is_required')::BOOLEAN, false), v_field->>'placeholder', v_field->>'help_text',
                v_field->>'regex_pattern', (v_field->>'min_value')::NUMERIC, (v_field->>'max_value')::NUMERIC,
                (v_field->>'min_selections')::INTEGER, (v_field->>'max_selections')::INTEGER,
                CASE
                    WHEN v_field->'persona_ids' IS NULL
                         OR v_field->'persona_ids' = 'null'::jsonb
                         OR v_field->'persona_ids' @> '"all"'::jsonb
                    THEN NULL
                    ELSE ARRAY(SELECT jsonb_array_elements_text(v_field->'persona_ids'))::UUID[]
                END
            ) RETURNING id INTO v_field_id;
            v_fields_created := v_fields_created + 1;
        END IF;

        v_fields_to_keep := array_append(v_fields_to_keep, v_field_id);
        v_options_to_keep := ARRAY[]::UUID[];
        v_option_index := 0;

        FOR v_option IN SELECT * FROM jsonb_array_elements(COALESCE(v_field->'options', '[]'::jsonb))
        LOOP
            IF v_option->>'id' IS NOT NULL AND v_option->>'id' != '' AND v_option->>'id' != 'null' THEN
                v_option_id := (v_option->>'id')::UUID;
                UPDATE form_field_options
                SET option_value = v_option->>'option_value', option_label = v_option->>'option_label',
                    order_index = v_option_index, is_default = COALESCE((v_option->>'is_default')::BOOLEAN, false)
                WHERE id = v_option_id AND field_id = v_field_id;
                v_options_to_keep := array_append(v_options_to_keep, v_option_id);
            ELSE
                INSERT INTO form_field_options (field_id, option_value, option_label, order_index, is_default)
                VALUES (v_field_id, v_option->>'option_value', v_option->>'option_label', v_option_index, COALESCE((v_option->>'is_default')::BOOLEAN, false))
                RETURNING id INTO v_option_id;
                v_options_to_keep := array_append(v_options_to_keep, v_option_id);
            END IF;
            v_option_index := v_option_index + 1;
        END LOOP;

        DELETE FROM form_field_options WHERE field_id = v_field_id AND id != ALL(v_options_to_keep);
        v_field_index := v_field_index + 1;
    END LOOP;

    UPDATE form_fields SET deleted_at = NOW()
    WHERE form_id = v_form_id AND deleted_at IS NULL AND id != ALL(v_fields_to_keep);
    GET DIAGNOSTICS v_fields_deleted = ROW_COUNT;

    FOR v_condition IN SELECT * FROM jsonb_array_elements(COALESCE(p_data->'conditions', '[]'::jsonb))
    LOOP
        IF v_condition->>'id' IS NOT NULL AND v_condition->>'id' != '' AND v_condition->>'id' != 'null' THEN
            v_condition_id := (v_condition->>'id')::UUID;
            UPDATE form_conditions
            SET source_field_key = v_condition->>'source_field_key',
                operator = (v_condition->>'operator')::form_condition_operator,
                compare_value = v_condition->>'compare_value',
                target_field_key = v_condition->>'target_field_key',
                action_type = (v_condition->>'action_type')::form_condition_action
            WHERE id = v_condition_id AND form_id = v_form_id;
            v_conditions_to_keep := array_append(v_conditions_to_keep, v_condition_id);
            v_conditions_updated := v_conditions_updated + 1;
        ELSE
            INSERT INTO form_conditions (form_id, source_field_key, operator, compare_value, target_field_key, action_type)
            VALUES (v_form_id, v_condition->>'source_field_key', (v_condition->>'operator')::form_condition_operator,
                v_condition->>'compare_value', v_condition->>'target_field_key', (v_condition->>'action_type')::form_condition_action)
            RETURNING id INTO v_condition_id;
            v_conditions_to_keep := array_append(v_conditions_to_keep, v_condition_id);
            v_conditions_created := v_conditions_created + 1;
        END IF;
    END LOOP;

    DELETE FROM form_conditions WHERE form_id = v_form_id AND id != ALL(v_conditions_to_keep);
    GET DIAGNOSTICS v_conditions_deleted = ROW_COUNT;

    IF p_data ? 'limits' THEN
        FOR v_limit IN SELECT * FROM jsonb_array_elements(COALESCE(p_data->'limits', '[]'::jsonb))
        LOOP
            IF v_limit->>'id' IS NOT NULL AND v_limit->>'id' != '' AND v_limit->>'id' != 'null' THEN
                v_limit_id := (v_limit->>'id')::UUID;
                UPDATE transaction_limits
                SET scope = (v_limit->>'scope')::reward_condition_scope,
                    count = (v_limit->>'count')::numeric,
                    time_unit = (v_limit->>'time_unit')::reward_condition_time_unit,
                    active_status = COALESCE((v_limit->>'active_status')::boolean, true)
                WHERE id = v_limit_id AND entity_type = 'form'::entity_type AND entity_id = v_form_id AND merchant_id = v_merchant_id;
                v_limits_to_keep := array_append(v_limits_to_keep, v_limit_id);
                v_limits_updated := v_limits_updated + 1;
            ELSE
                INSERT INTO transaction_limits (merchant_id, entity_type, entity_id, scope, count, time_unit, active_status, metric)
                VALUES (v_merchant_id, 'form'::entity_type, v_form_id,
                    (v_limit->>'scope')::reward_condition_scope, (v_limit->>'count')::numeric,
                    (v_limit->>'time_unit')::reward_condition_time_unit, COALESCE((v_limit->>'active_status')::boolean, true),
                    'quantity'::reward_limit_metric)
                RETURNING id INTO v_limit_id;
                v_limits_to_keep := array_append(v_limits_to_keep, v_limit_id);
                v_limits_created := v_limits_created + 1;
            END IF;
        END LOOP;
        DELETE FROM transaction_limits
        WHERE entity_type = 'form'::entity_type AND entity_id = v_form_id AND merchant_id = v_merchant_id
          AND id != ALL(v_limits_to_keep);
        GET DIAGNOSTICS v_limits_deleted = ROW_COUNT;
    END IF;

    BEGIN
        IF v_code = 'USER_PROFILE' THEN
            PERFORM fn_invalidate_user_profile_template_cache(v_merchant_id);
        END IF;
    EXCEPTION WHEN OTHERS THEN NULL;
    END;

    RETURN jsonb_build_object(
        'success', true,
        'title', CASE WHEN v_is_create THEN fn_admin_envelope_message('form_created_title', v_lang) ELSE fn_admin_envelope_message('form_updated_title', v_lang) END,
        'description', fn_admin_envelope_message('form_saved_with_full_desc', v_lang, ARRAY[
            (v_groups_created + v_groups_updated)::text,
            (v_fields_created + v_fields_updated)::text,
            (v_conditions_created + v_conditions_updated)::text,
            (v_limits_created + v_limits_updated)::text
        ]),
        'data', jsonb_build_object(
            'form_id', v_form_id, 'form_created', v_is_create, 'form_updated', NOT v_is_create,
            'allow_bulk_import', v_allow_bulk_import,
            'groups_created', v_groups_created, 'groups_updated', v_groups_updated, 'groups_deleted', v_groups_deleted,
            'fields_created', v_fields_created, 'fields_updated', v_fields_updated, 'fields_deleted', v_fields_deleted,
            'conditions_created', v_conditions_created, 'conditions_updated', v_conditions_updated, 'conditions_deleted', v_conditions_deleted,
            'limits_created', v_limits_created, 'limits_updated', v_limits_updated, 'limits_deleted', v_limits_deleted
        )
    );

EXCEPTION WHEN OTHERS THEN
    RETURN jsonb_build_object('success', false, 'title', fn_admin_envelope_message('error_saving_form_title', v_lang), 'description', SQLERRM, 'data', null);
END;
$function$;

DROP FUNCTION IF EXISTS public.bff_upsert_form(jsonb);
