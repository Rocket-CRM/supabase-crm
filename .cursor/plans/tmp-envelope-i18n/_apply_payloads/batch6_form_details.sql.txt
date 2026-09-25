CREATE OR REPLACE FUNCTION public.bff_get_form_details(p_form_id uuid DEFAULT NULL::uuid, p_mode text DEFAULT 'new'::text, p_language text DEFAULT 'en'::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
AS $function$
DECLARE
    v_lang text;
    v_merchant_id UUID;
    v_form_merchant_id UUID;
    v_result JSONB;
BEGIN
    v_lang := fn_normalize_ui_language(p_language);
    v_merchant_id := get_current_merchant_id();

    IF v_merchant_id IS NULL THEN
        RETURN jsonb_build_object('success', false, 'title', fn_admin_envelope_message('no_merchant_title', v_lang), 'description', fn_admin_envelope_message('unable_merchant_auth_desc', v_lang), 'data', null);
    END IF;

    IF p_mode NOT IN ('new', 'edit') THEN
        RETURN jsonb_build_object('success', false, 'title', fn_admin_envelope_message('invalid_mode_title', v_lang), 'description', fn_admin_envelope_message('invalid_mode_new_edit_desc', v_lang), 'data', null);
    END IF;

    IF p_mode = 'new' OR p_form_id IS NULL THEN
        RETURN jsonb_build_object(
            'success', true, 'title', null, 'description', null,
            'data', jsonb_build_object(
                'mode', 'new',
                'form', jsonb_build_object('id', null, 'merchant_id', v_merchant_id, 'code', null, 'name', null, 'description', null, 'status', 'draft', 'allow_bulk_import', false),
                'groups', '[]'::jsonb, 'fields', '[]'::jsonb, 'conditions', '[]'::jsonb,
                'metadata', jsonb_build_object(
                    'available_field_types', jsonb_build_array(
                        jsonb_build_object('value', 'normal', 'label', 'Text'), jsonb_build_object('value', 'email', 'label', 'Email'),
                        jsonb_build_object('value', 'password', 'label', 'Password'), jsonb_build_object('value', 'tel', 'label', 'Phone'),
                        jsonb_build_object('value', 'number', 'label', 'Number'), jsonb_build_object('value', 'date', 'label', 'Date'),
                        jsonb_build_object('value', 'time', 'label', 'Time'), jsonb_build_object('value', 'date-time', 'label', 'Date & Time'),
                        jsonb_build_object('value', 'currency', 'label', 'Currency'), jsonb_build_object('value', 'select', 'label', 'Dropdown'),
                        jsonb_build_object('value', 'multi-select', 'label', 'Multi-Select')
                    ),
                    'available_operators', jsonb_build_array(
                        jsonb_build_object('value', 'equals', 'label', 'Equals'), jsonb_build_object('value', 'not_equals', 'label', 'Not Equals'),
                        jsonb_build_object('value', 'contains', 'label', 'Contains'), jsonb_build_object('value', 'not_contains', 'label', 'Not Contains'),
                        jsonb_build_object('value', 'is_empty', 'label', 'Is Empty'), jsonb_build_object('value', 'is_not_empty', 'label', 'Is Not Empty'),
                        jsonb_build_object('value', 'greater_than', 'label', 'Greater Than'), jsonb_build_object('value', 'less_than', 'label', 'Less Than')
                    ),
                    'available_actions', jsonb_build_array(
                        jsonb_build_object('value', 'show', 'label', 'Show'), jsonb_build_object('value', 'hide', 'label', 'Hide'),
                        jsonb_build_object('value', 'enable', 'label', 'Enable'), jsonb_build_object('value', 'disable', 'label', 'Disable'),
                        jsonb_build_object('value', 'require', 'label', 'Require')
                    ),
                    'available_statuses', jsonb_build_array(
                        jsonb_build_object('value', 'draft', 'label', 'Draft'), jsonb_build_object('value', 'published', 'label', 'Published'),
                        jsonb_build_object('value', 'archived', 'label', 'Archived')
                    )
                )
            )
        );
    END IF;

    SELECT merchant_id INTO v_form_merchant_id FROM form_templates WHERE id = p_form_id;
    IF v_form_merchant_id IS NULL THEN
        RETURN jsonb_build_object('success', false, 'title', fn_admin_envelope_message('form_not_found_title', v_lang), 'description', fn_admin_envelope_message('form_not_exist_desc', v_lang), 'data', null);
    END IF;
    IF v_form_merchant_id != v_merchant_id THEN
        RETURN jsonb_build_object('success', false, 'title', fn_admin_envelope_message('unauthorized_title', v_lang), 'description', fn_admin_envelope_message('form_wrong_merchant_desc', v_lang), 'data', null);
    END IF;

    WITH form_base AS (
        SELECT ft.id, ft.merchant_id, ft.code, ft.name, ft.description, ft.status,
               ft.allow_bulk_import,
               ft.created_at, ft.updated_at
        FROM form_templates ft WHERE ft.id = p_form_id
    ),
    groups_json AS (
        SELECT COALESCE(jsonb_agg(
            jsonb_build_object('id', fg.id, 'group_key', fg.group_key, 'group_name', fg.group_name, 'order_index', fg.order_index, 'require_at_least_one', fg.require_at_least_one)
            ORDER BY fg.order_index
        ), '[]'::jsonb) AS groups
        FROM form_field_groups fg WHERE fg.form_id = p_form_id
    ),
    fields_json AS (
        SELECT COALESCE(jsonb_agg(
            jsonb_build_object(
                'id', ff.id, 'field_key', ff.field_key, 'field_type', ff.field_type, 'text_format', ff.text_format,
                'label', ff.label, 'group_id', ff.group_id, 'position_after', ff.position_after,
                'order_index', ff.order_index, 'is_required', ff.is_required, 'placeholder', ff.placeholder,
                'help_text', ff.help_text, 'regex_pattern', ff.regex_pattern,
                'min_value', ff.min_value, 'max_value', ff.max_value,
                'min_selections', ff.min_selections, 'max_selections', ff.max_selections,
                'persona_ids', ff.persona_ids,
                'options', (
                    SELECT COALESCE(jsonb_agg(
                        jsonb_build_object('id', ffo.id, 'option_value', ffo.option_value, 'option_label', ffo.option_label, 'order_index', ffo.order_index, 'is_default', ffo.is_default)
                        ORDER BY ffo.order_index
                    ), '[]'::jsonb)
                    FROM form_field_options ffo WHERE ffo.field_id = ff.id
                )
            ) ORDER BY ff.order_index
        ), '[]'::jsonb) AS fields
        FROM form_fields ff
        WHERE ff.form_id = p_form_id AND ff.deleted_at IS NULL
    ),
    conditions_json AS (
        SELECT COALESCE(jsonb_agg(
            jsonb_build_object('id', fc.id, 'source_field_key', fc.source_field_key, 'operator', fc.operator, 'compare_value', fc.compare_value, 'target_field_key', fc.target_field_key, 'action_type', fc.action_type)
            ORDER BY fc.id
        ), '[]'::jsonb) AS conditions
        FROM form_conditions fc WHERE fc.form_id = p_form_id
    ),
    stats AS (
        SELECT COUNT(DISTINCT fs.id) as submission_count, COUNT(DISTINCT fs.user_id) as unique_users
        FROM form_submissions fs WHERE fs.form_id = p_form_id
    )
    SELECT jsonb_build_object(
        'success', true, 'title', null, 'description', null,
        'data', jsonb_build_object(
            'mode', 'edit', 'form', to_jsonb(fb.*), 'groups', gj.groups, 'fields', fj.fields, 'conditions', cj.conditions,
            'metadata', jsonb_build_object(
                'submission_count', s.submission_count, 'unique_users', s.unique_users,
                'total_fields', (SELECT COUNT(*) FROM form_fields WHERE form_id = p_form_id AND deleted_at IS NULL),
                'total_groups', (SELECT COUNT(*) FROM form_field_groups WHERE form_id = p_form_id),
                'total_conditions', (SELECT COUNT(*) FROM form_conditions WHERE form_id = p_form_id),
                'is_user_profile', (fb.code = 'USER_PROFILE'),
                'allow_bulk_import_locked', (fb.code = 'USER_PROFILE'),
                'available_field_types', jsonb_build_array(
                    jsonb_build_object('value', 'normal', 'label', 'Text'), jsonb_build_object('value', 'email', 'label', 'Email'),
                    jsonb_build_object('value', 'password', 'label', 'Password'), jsonb_build_object('value', 'tel', 'label', 'Phone'),
                    jsonb_build_object('value', 'number', 'label', 'Number'), jsonb_build_object('value', 'date', 'label', 'Date'),
                    jsonb_build_object('value', 'time', 'label', 'Time'), jsonb_build_object('value', 'date-time', 'label', 'Date & Time'),
                    jsonb_build_object('value', 'currency', 'label', 'Currency'), jsonb_build_object('value', 'select', 'label', 'Dropdown'),
                    jsonb_build_object('value', 'multi-select', 'label', 'Multi-Select')
                ),
                'available_operators', jsonb_build_array(
                    jsonb_build_object('value', 'equals', 'label', 'Equals'), jsonb_build_object('value', 'not_equals', 'label', 'Not Equals'),
                    jsonb_build_object('value', 'contains', 'label', 'Contains'), jsonb_build_object('value', 'not_contains', 'label', 'Not Contains'),
                    jsonb_build_object('value', 'is_empty', 'label', 'Is Empty'), jsonb_build_object('value', 'is_not_empty', 'label', 'Is Not Empty'),
                    jsonb_build_object('value', 'greater_than', 'label', 'Greater Than'), jsonb_build_object('value', 'less_than', 'label', 'Less Than')
                ),
                'available_actions', jsonb_build_array(
                    jsonb_build_object('value', 'show', 'label', 'Show'), jsonb_build_object('value', 'hide', 'label', 'Hide'),
                    jsonb_build_object('value', 'enable', 'label', 'Enable'), jsonb_build_object('value', 'disable', 'label', 'Disable'),
                    jsonb_build_object('value', 'require', 'label', 'Require')
                ),
                'available_statuses', jsonb_build_array(
                    jsonb_build_object('value', 'draft', 'label', 'Draft'), jsonb_build_object('value', 'published', 'label', 'Published'),
                    jsonb_build_object('value', 'archived', 'label', 'Archived')
                )
            )
        )
    ) INTO v_result
    FROM form_base fb
    CROSS JOIN groups_json gj
    CROSS JOIN fields_json fj
    CROSS JOIN conditions_json cj
    CROSS JOIN stats s;

    RETURN v_result;
END;
$function$;

DROP FUNCTION IF EXISTS public.bff_get_form_details(uuid, text);
