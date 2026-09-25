CREATE OR REPLACE FUNCTION public.bff_upload_signup_codes(p_field_config_id uuid, p_codes jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
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
  v_merchant_id := get_current_merchant_id();
  IF v_merchant_id IS NULL THEN
    RETURN jsonb_build_object('success', false, 'title', 'No merchant context', 'description', null, 'data', null);
  END IF;

  IF NOT check_admin_permission('form', 'create') THEN
    RETURN jsonb_build_object('success', false, 'title', 'Forbidden', 'description', 'Insufficient permissions', 'data', jsonb_build_object('error_code', 'FORBIDDEN'));
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
    RETURN jsonb_build_object('success', false, 'title', 'Field not found', 'description', 'Field config does not belong to this merchant', 'data', jsonb_build_object('error_code', 'FIELD_NOT_FOUND'));
  END IF;

  IF v_field_type != 'external_code' THEN
    RETURN jsonb_build_object('success', false, 'title', 'Wrong field type', 'description', 'Target field must be field_type=external_code', 'data', jsonb_build_object('error_code', 'WRONG_FIELD_TYPE'));
  END IF;

  IF v_store_binding NOT IN ('off','optional','required') THEN
    RETURN jsonb_build_object('success', false, 'title', 'Invalid pool config',
      'description', 'config.external_code.store_binding must be off|optional|required',
      'data', jsonb_build_object('error_code', 'INVALID_STORE_BINDING'));
  END IF;

  IF jsonb_typeof(p_codes) != 'array' OR jsonb_array_length(p_codes) = 0 THEN
    RETURN jsonb_build_object('success', false, 'title', 'No codes provided', 'description', 'p_codes must be a non-empty array', 'data', jsonb_build_object('error_code', 'EMPTY_PAYLOAD'));
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
      'title', 'Store binding validation failed',
      'description', 'No codes were uploaded. Fix the errors and retry.',
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
    'title', 'Codes uploaded',
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
$function$
