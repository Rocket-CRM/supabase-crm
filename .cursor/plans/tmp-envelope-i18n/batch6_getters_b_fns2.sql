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

CREATE OR REPLACE FUNCTION public.bff_get_consent_form_template(p_mode text DEFAULT 'new'::text, p_language text DEFAULT 'en'::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
DECLARE
    v_lang text;
    v_merchant_id UUID;
    v_user_id UUID;
    v_result JSONB;
    v_notices JSONB;
    v_consents JSONB;
    v_channels JSONB;
    v_topics JSONB;
    v_channel_email BOOLEAN := false;
    v_channel_line BOOLEAN := false;
    v_channel_sms BOOLEAN := false;
    v_channel_push BOOLEAN := false;
BEGIN
    v_lang := fn_normalize_ui_language(p_language);
    v_merchant_id := get_current_merchant_id();

    IF v_merchant_id IS NULL THEN
        RETURN jsonb_build_object(
          'success', false,
          'title', fn_admin_envelope_message('no_merchant_title', v_lang),
          'description', null
        );
    END IF;

    -- For edit mode, get user and their channel preferences
    IF p_mode = 'edit' THEN
        SELECT id,
               COALESCE(channel_email, false),
               COALESCE(channel_line, false),
               COALESCE(channel_sms, false),
               COALESCE(channel_push, false)
        INTO v_user_id, v_channel_email, v_channel_line, v_channel_sms, v_channel_push
        FROM user_accounts
        WHERE id = auth.uid() AND merchant_id = v_merchant_id;

        IF v_user_id IS NULL THEN
            RETURN jsonb_build_object(
              'success', false,
              'title', fn_admin_envelope_message('user_not_found_title', v_lang),
              'description', null
            );
        END IF;
    END IF;

    -- 1. Get Privacy Notices (display only, no action needed)
    SELECT COALESCE(jsonb_agg(
        jsonb_build_object(
            'id', cv.id,
            'type', cv.consent_type::text,
            'version_code', cv.version_code,
            'title', cv.title,
            'content', cv.content,
            'is_mandatory', cv.is_mandatory,
            'requires_action', false
        ) ORDER BY cv.created_at
    ), '[]'::jsonb) INTO v_notices
    FROM consent_versions cv
    WHERE cv.merchant_id = v_merchant_id
        AND cv.consent_type = 'privacy_policy'
        AND cv.active_status = true;

    -- 2. Get Consents (requires accept/reject)
    SELECT COALESCE(jsonb_agg(
        jsonb_build_object(
            'id', cv.id,
            'type', cv.consent_type::text,
            'version_code', cv.version_code,
            'title', cv.title,
            'content', cv.content,
            'is_mandatory', cv.is_mandatory,
            'requires_action', true,
            'accepted', CASE
                WHEN p_mode = 'edit' AND v_user_id IS NOT NULL THEN COALESCE(
                    (SELECT ucl.action = 'accepted'
                     FROM user_consent_ledger ucl
                     WHERE ucl.user_id = v_user_id
                         AND ucl.consent_version_id = cv.id
                     ORDER BY ucl.created_at DESC
                     LIMIT 1),
                    false
                )
                ELSE false
            END
        ) ORDER BY cv.is_mandatory DESC, cv.created_at
    ), '[]'::jsonb) INTO v_consents
    FROM consent_versions cv
    WHERE cv.merchant_id = v_merchant_id
        AND cv.consent_type IN ('terms_of_service', 'marketing')
        AND cv.active_status = true;

    -- 3. Get Communication Channels
    v_channels := jsonb_build_array(
        jsonb_build_object(
            'key', 'channel_email',
            'label', 'Email',
            'enabled', v_channel_email
        ),
        jsonb_build_object(
            'key', 'channel_line',
            'label', 'LINE',
            'enabled', v_channel_line
        ),
        jsonb_build_object(
            'key', 'channel_sms',
            'label', 'SMS',
            'enabled', v_channel_sms
        ),
        jsonb_build_object(
            'key', 'channel_push',
            'label', 'Push Notification',
            'enabled', v_channel_push
        )
    );

    -- 4. Get Communication Topics
    SELECT COALESCE(jsonb_agg(
        jsonb_build_object(
            'id', ct.id,
            'name', ct.topic_name,
            'description', ct.description,
            'opted_in', CASE
                WHEN p_mode = 'edit' AND v_user_id IS NOT NULL THEN COALESCE(
                    (SELECT ucp.opted_in
                     FROM user_communication_preferences ucp
                     WHERE ucp.user_id = v_user_id AND ucp.topic_id = ct.id),
                    false
                )
                ELSE false
            END
        ) ORDER BY ct.created_at
    ), '[]'::jsonb) INTO v_topics
    FROM communication_topics ct
    WHERE ct.merchant_id = v_merchant_id
        AND ct.active_status = true;

    -- Build final result
    RETURN jsonb_build_object(
        'success', true,
        'mode', p_mode,
        'notices', v_notices,
        'consents', v_consents,
        'channels', v_channels,
        'topics', v_topics,
        'timestamp', NOW()
    );
END;
$function$;

DROP FUNCTION IF EXISTS public.bff_get_consent_form_template(text);

CREATE OR REPLACE FUNCTION public.bff_upload_signup_codes(p_field_config_id uuid, p_codes jsonb, p_language text DEFAULT 'en'::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_lang text;
  v_merchant_id uuid;
  v_field_owner uuid;
  v_field_type text;
  v_schema_default text[];
  v_schema_custom text[];
  v_store_binding text;
  v_code_row jsonb;
  v_row_index int;
  v_code text;
  v_store_code text;
  v_store_id uuid;
  v_metadata jsonb;
  v_max_consumers int;
  v_is_active boolean;
  v_created int := 0;
  v_updated int := 0;
  v_skipped int := 0;
  v_existing_id uuid;
  v_errors jsonb := '[]'::jsonb;
  v_store_errors jsonb := '[]'::jsonb;
  v_has_row_error boolean;
  v_prefill_default jsonb;
  v_prefill_custom jsonb;
  v_prefill_key text;
BEGIN
  v_lang := fn_normalize_ui_language(p_language);
  v_merchant_id := get_current_merchant_id();
  IF v_merchant_id IS NULL THEN
    RETURN jsonb_build_object('success', false, 'title', fn_admin_envelope_message('no_merchant_title', v_lang), 'description', null, 'data', null);
  END IF;

  IF NOT check_admin_permission('form', 'create') THEN
    RETURN jsonb_build_object('success', false, 'title', fn_admin_envelope_message('forbidden_title', v_lang), 'description', fn_admin_envelope_message('insufficient_permissions_title', v_lang), 'data', jsonb_build_object('error_code', 'FORBIDDEN'));
  END IF;

  SELECT
    merchant_id,
    field_type,
    COALESCE(ARRAY(SELECT jsonb_array_elements_text(config #> '{external_code,prefill_schema,default}')), ARRAY[]::text[]),
    COALESCE(ARRAY(SELECT jsonb_array_elements_text(config #> '{external_code,prefill_schema,custom}')), ARRAY[]::text[]),
    COALESCE(NULLIF(trim(config #>> '{external_code,store_binding}'), ''), 'off')
  INTO v_field_owner, v_field_type, v_schema_default, v_schema_custom, v_store_binding
  FROM user_field_config WHERE id = p_field_config_id;

  IF v_field_owner IS NULL OR v_field_owner != v_merchant_id THEN
    RETURN jsonb_build_object('success', false, 'title', fn_admin_envelope_message('field_not_found_title', v_lang), 'description', fn_admin_envelope_message('field_not_found_desc', v_lang), 'data', jsonb_build_object('error_code', 'FIELD_NOT_FOUND'));
  END IF;

  IF v_field_type != 'external_code' THEN
    RETURN jsonb_build_object('success', false, 'title', fn_admin_envelope_message('wrong_field_type_title', v_lang), 'description', fn_admin_envelope_message('target_external_code_required_desc', v_lang), 'data', jsonb_build_object('error_code', 'WRONG_FIELD_TYPE'));
  END IF;

  IF v_store_binding NOT IN ('off','optional','required') THEN
    RETURN jsonb_build_object('success', false, 'title', fn_admin_envelope_message('invalid_pool_config_title', v_lang),
      'description', fn_admin_envelope_message('invalid_store_binding_desc', v_lang),
      'data', jsonb_build_object('error_code', 'INVALID_STORE_BINDING'));
  END IF;

  IF jsonb_typeof(p_codes) != 'array' OR jsonb_array_length(p_codes) = 0 THEN
    RETURN jsonb_build_object('success', false, 'title', fn_admin_envelope_message('no_codes_provided_title', v_lang), 'description', fn_admin_envelope_message('no_codes_provided_desc', v_lang), 'data', jsonb_build_object('error_code', 'EMPTY_PAYLOAD'));
  END IF;

  -- Validation pass: any store-binding error aborts the entire upload.
  v_row_index := 0;
  FOR v_code_row IN SELECT * FROM jsonb_array_elements(p_codes) LOOP
    v_row_index := v_row_index + 1;
    v_code := NULLIF(trim(v_code_row->>'code'), '');
    v_store_code := NULLIF(trim(v_code_row->>'store_code'), '');

    -- skip empty-code rows here; the write pass reports them as EMPTY_CODE
    IF v_code IS NULL THEN
      CONTINUE;
    END IF;

    IF v_store_binding = 'off' AND v_store_code IS NOT NULL THEN
      v_store_errors := v_store_errors || jsonb_build_object(
        'row', v_row_index, 'code', v_code, 'store_code', v_store_code,
        'error_code', 'STORE_BINDING_DISABLED',
        'message', 'This pool does not allow store binding (store_binding=off)'
      );
    ELSIF v_store_binding = 'required' AND v_store_code IS NULL THEN
      v_store_errors := v_store_errors || jsonb_build_object(
        'row', v_row_index, 'code', v_code, 'store_code', null,
        'error_code', 'STORE_BINDING_REQUIRED',
        'message', 'This pool requires every code to include a store_code'
      );
    ELSIF v_store_code IS NOT NULL THEN
      IF NOT EXISTS (
        SELECT 1 FROM store_master
        WHERE merchant_id = v_merchant_id AND store_code = v_store_code
      ) THEN
        v_store_errors := v_store_errors || jsonb_build_object(
          'row', v_row_index, 'code', v_code, 'store_code', v_store_code,
          'error_code', 'STORE_NOT_FOUND',
          'message', 'store_code ' || quote_literal(v_store_code) || ' does not exist in store_master'
        );
      END IF;
    END IF;
  END LOOP;

  IF jsonb_array_length(v_store_errors) > 0 THEN
    RETURN jsonb_build_object('success', false,
      'title', fn_admin_envelope_message('store_binding_validation_failed_title', v_lang),
      'description', fn_admin_envelope_message('store_binding_validation_failed_desc', v_lang),
      'data', jsonb_build_object('error_code', 'STORE_VALIDATION_FAILED', 'errors', v_store_errors));
  END IF;

  -- Write pass: existing per-row prefill-schema check + upsert.
  v_row_index := 0;
  FOR v_code_row IN SELECT * FROM jsonb_array_elements(p_codes) LOOP
    v_row_index := v_row_index + 1;
    v_code := NULLIF(trim(v_code_row->>'code'), '');
    v_store_code := NULLIF(trim(v_code_row->>'store_code'), '');
    v_metadata := COALESCE(v_code_row->'metadata', '{}'::jsonb);
    v_max_consumers := GREATEST(1, COALESCE((v_code_row->>'max_consumers')::int, 1));
    v_is_active := COALESCE((v_code_row->>'is_active')::boolean, true);
    v_has_row_error := false;

    IF v_code IS NULL THEN
      v_skipped := v_skipped + 1;
      v_errors := v_errors || jsonb_build_object(
        'row', v_row_index, 'code', null,
        'error_code', 'EMPTY_CODE', 'scope', null, 'field_key', null,
        'message', 'Code value is missing or empty'
      );
      CONTINUE;
    END IF;

    v_prefill_default := v_metadata #> '{prefill,default}';
    IF v_prefill_default IS NOT NULL AND jsonb_typeof(v_prefill_default) = 'object' THEN
      FOR v_prefill_key IN SELECT jsonb_object_keys(v_prefill_default) LOOP
        IF NOT (v_prefill_key = ANY(v_schema_default)) THEN
          v_has_row_error := true;
          v_errors := v_errors || jsonb_build_object(
            'row', v_row_index, 'code', v_code,
            'error_code', 'KEY_NOT_IN_POOL_SCHEMA',
            'scope', 'default', 'field_key', v_prefill_key,
            'message', 'Default field ' || quote_literal(v_prefill_key) || ' is not in this pool''s prefill schema'
          );
        END IF;
      END LOOP;
    END IF;

    v_prefill_custom := v_metadata #> '{prefill,custom}';
    IF v_prefill_custom IS NOT NULL AND jsonb_typeof(v_prefill_custom) = 'object' THEN
      FOR v_prefill_key IN SELECT jsonb_object_keys(v_prefill_custom) LOOP
        IF NOT (v_prefill_key = ANY(v_schema_custom)) THEN
          v_has_row_error := true;
          v_errors := v_errors || jsonb_build_object(
            'row', v_row_index, 'code', v_code,
            'error_code', 'KEY_NOT_IN_POOL_SCHEMA',
            'scope', 'custom', 'field_key', v_prefill_key,
            'message', 'Custom field ' || quote_literal(v_prefill_key) || ' is not in this pool''s prefill schema'
          );
        END IF;
      END LOOP;
    END IF;

    IF v_has_row_error THEN
      v_skipped := v_skipped + 1;
      CONTINUE;
    END IF;

    v_store_id := NULL;
    IF v_store_code IS NOT NULL THEN
      SELECT id INTO v_store_id FROM store_master
      WHERE merchant_id = v_merchant_id AND store_code = v_store_code;
    END IF;

    SELECT id INTO v_existing_id FROM signup_codes
    WHERE field_config_id = p_field_config_id AND code = v_code;

    IF v_existing_id IS NULL THEN
      INSERT INTO signup_codes (merchant_id, field_config_id, code, metadata, max_consumers, is_active, store_id)
      VALUES (v_merchant_id, p_field_config_id, v_code, v_metadata, v_max_consumers, v_is_active, v_store_id);
      v_created := v_created + 1;
    ELSE
      UPDATE signup_codes SET
        metadata = v_metadata,
        max_consumers = GREATEST(v_max_consumers, consumed_count),
        is_active = v_is_active,
        store_id = v_store_id
      WHERE id = v_existing_id;
      v_updated := v_updated + 1;
    END IF;
  END LOOP;

  RETURN jsonb_build_object(
    'success', true,
    'title', fn_admin_envelope_message('codes_uploaded_title', v_lang),
    'description', null,
    'data', jsonb_build_object(
      'created', v_created,
      'updated', v_updated,
      'skipped', v_skipped,
      'errors', v_errors,
      'store_binding', v_store_binding
    )
  );
END;
$function$;

DROP FUNCTION IF EXISTS public.bff_upload_signup_codes(uuid, jsonb);
