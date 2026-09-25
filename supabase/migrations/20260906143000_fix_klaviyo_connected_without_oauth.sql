-- Klaviyo must not appear connected until OAuth access_token exists.
-- Saving sync_new_members via bff_upsert_integration_config was inserting is_active=true.

UPDATE public.merchant_credentials
SET
  is_active = false,
  health_status = 'disconnected'
WHERE service_name = 'klaviyo'
  AND is_active = true
  AND COALESCE(NULLIF(TRIM(credentials->>'access_token'), ''), '') = '';

CREATE OR REPLACE FUNCTION public.bff_integration_klaviyo_get_connection(
  p_language text DEFAULT 'en'::text
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_lang text;
  v_merchant_id uuid;
  v_cred record;
  v_job record;
  v_has_token boolean;
BEGIN
  v_lang := fn_normalize_ui_language(p_language);
  v_merchant_id := get_current_merchant_id();
  IF v_merchant_id IS NULL THEN
    RETURN fn_response_error(
      fn_admin_envelope_message('merchant_context_not_found_title', v_lang),
      fn_admin_envelope_message('unable_identify_merchant_token_desc', v_lang)
    );
  END IF;

  SELECT
    mc.id,
    mc.is_active,
    mc.health_status,
    mc.last_health_check,
    mc.expires_at,
    mc.updated_at,
    mc.credentials
  INTO v_cred
  FROM public.merchant_credentials mc
  WHERE mc.merchant_id = v_merchant_id
    AND mc.service_name = 'klaviyo'
  ORDER BY mc.updated_at DESC NULLS LAST
  LIMIT 1;

  SELECT
    j.id,
    j.status,
    j.members_total,
    j.members_synced,
    j.members_skipped_no_email,
    j.last_error,
    j.started_at,
    j.finished_at,
    j.created_at
  INTO v_job
  FROM public.integration_sync_jobs j
  WHERE j.merchant_id = v_merchant_id
    AND j.integration_key = 'klaviyo'
  ORDER BY j.created_at DESC
  LIMIT 1;

  v_has_token := COALESCE(NULLIF(TRIM(v_cred.credentials->>'access_token'), ''), '') <> '';

  RETURN fn_response_success(
    NULL,
    NULL,
    jsonb_build_object(
      'connected', COALESCE(v_cred.is_active, false) AND v_has_token,
      'account_name', v_cred.credentials->>'account_name',
      'health_status', COALESCE(v_cred.health_status, 'disconnected'),
      'last_health_check', v_cred.last_health_check,
      'sync_new_members', COALESCE((v_cred.credentials->>'sync_new_members')::boolean, true),
      'expires_at', v_cred.expires_at,
      'credential_id', v_cred.id,
      'latest_sync_job', CASE
        WHEN v_job.id IS NULL THEN NULL
        ELSE jsonb_build_object(
          'job_id', v_job.id,
          'status', v_job.status,
          'members_total', v_job.members_total,
          'members_synced', v_job.members_synced,
          'members_skipped_no_email', v_job.members_skipped_no_email,
          'last_error', v_job.last_error,
          'started_at', v_job.started_at,
          'finished_at', v_job.finished_at,
          'created_at', v_job.created_at
        )
      END
    )
  );
END;
$function$;

CREATE OR REPLACE FUNCTION public.bff_upsert_integration_config(
  p_integration_key text,
  p_config jsonb,
  p_language text DEFAULT 'en'::text
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
AS $function$
DECLARE
  v_lang text;
  v_merchant_id UUID;
  v_credential_id UUID;
  v_was_created BOOLEAN := false;
  v_field_count INTEGER;
  v_existing RECORD;
  v_service_name TEXT;
  v_type_id UUID;
  v_flat_config JSONB;
  v_nested_config JSONB;
  v_field RECORD;
  v_path_parts TEXT[];
  v_partial_path TEXT[];
  v_typed_value JSONB;
  i INTEGER;
BEGIN
  v_lang := fn_normalize_ui_language(p_language);
  v_merchant_id := get_current_merchant_id();

  IF v_merchant_id IS NULL THEN
    RETURN jsonb_build_object(
      'success', false,
      'title', fn_admin_envelope_message('merchant_context_not_found_title', v_lang),
      'description', fn_admin_envelope_message('unable_identify_merchant_token_desc', v_lang),
      'data', NULL
    );
  END IF;

  SELECT id, integration_key INTO v_type_id, v_service_name
  FROM integration_type_master
  WHERE LOWER(integration_key) = LOWER(p_integration_key);

  IF v_service_name IS NULL THEN
    RETURN jsonb_build_object(
      'success', false,
      'title', fn_admin_envelope_message('integration_type_not_found_title', v_lang, ARRAY[p_integration_key]),
      'description', fn_admin_envelope_message('integration_type_not_found_desc', v_lang),
      'data', NULL
    );
  END IF;

  IF jsonb_typeof(p_config) = 'array' THEN
    SELECT jsonb_object_agg(elem->>'field_name', elem->'value')
    INTO v_flat_config
    FROM jsonb_array_elements(p_config) AS elem
    WHERE elem->>'field_name' IS NOT NULL;
  ELSE
    v_flat_config := p_config;
  END IF;

  SELECT COUNT(*) INTO v_field_count FROM jsonb_each(v_flat_config);

  SELECT id, credentials INTO v_existing
  FROM merchant_credentials
  WHERE merchant_id = v_merchant_id
    AND service_name = v_service_name
  ORDER BY updated_at DESC NULLS LAST
  LIMIT 1;

  v_nested_config := COALESCE(v_existing.credentials, '{}'::jsonb);

  FOR v_field IN
    SELECT
      fc.key AS field_name,
      fc.value AS field_value,
      ifd.field_path,
      ifd.data_type
    FROM jsonb_each(v_flat_config) fc
    LEFT JOIN integration_field_definitions ifd
      ON ifd.field_name = fc.key
      AND ifd.integration_type_id = v_type_id
  LOOP
    IF jsonb_typeof(v_field.field_value) = 'string' AND v_field.field_value #>> '{}' = '***' THEN
      CONTINUE;
    END IF;

    IF v_field.field_path IS NOT NULL THEN
      v_path_parts := string_to_array(
        substring(v_field.field_path from position('.' in v_field.field_path) + 1), '.'
      );
    ELSE
      v_path_parts := ARRAY[v_field.field_name];
    END IF;

    IF v_field.data_type = 'boolean' THEN
      IF jsonb_typeof(v_field.field_value) = 'boolean' THEN
        v_typed_value := v_field.field_value;
      ELSIF jsonb_typeof(v_field.field_value) = 'string' THEN
        IF v_field.field_value #>> '{}' IN ('true', '1', 'yes') THEN
          v_typed_value := 'true'::jsonb;
        ELSE
          v_typed_value := 'false'::jsonb;
        END IF;
      ELSE
        v_typed_value := v_field.field_value;
      END IF;
    ELSIF v_field.data_type = 'array' THEN
      IF jsonb_typeof(v_field.field_value) = 'array' THEN
        v_typed_value := v_field.field_value;
      ELSIF jsonb_typeof(v_field.field_value) = 'string' THEN
        BEGIN
          v_typed_value := v_field.field_value::text::jsonb;
        EXCEPTION WHEN OTHERS THEN
          v_typed_value := jsonb_build_array(v_field.field_value #>> '{}');
        END;
      ELSE
        v_typed_value := v_field.field_value;
      END IF;
    ELSE
      v_typed_value := v_field.field_value;
    END IF;

    FOR i IN 1..array_length(v_path_parts, 1) - 1 LOOP
      v_partial_path := v_path_parts[1:i];
      IF v_nested_config #> v_partial_path IS NULL
        OR jsonb_typeof(v_nested_config #> v_partial_path) != 'object' THEN
        v_nested_config := jsonb_set(v_nested_config, v_partial_path, '{}'::jsonb, true);
      END IF;
    END LOOP;

    v_nested_config := jsonb_set(v_nested_config, v_path_parts, v_typed_value, true);
  END LOOP;

  IF v_existing.id IS NOT NULL THEN
    UPDATE merchant_credentials
    SET credentials = v_nested_config,
        updated_at = NOW()
    WHERE id = v_existing.id
    RETURNING id INTO v_credential_id;
    v_was_created := false;
  ELSE
    INSERT INTO merchant_credentials (
      merchant_id,
      service_name,
      credentials,
      environment,
      is_active,
      health_status,
      updated_at
    ) VALUES (
      v_merchant_id,
      v_service_name,
      v_nested_config,
      'production',
      CASE WHEN v_service_name = 'klaviyo' THEN false ELSE true END,
      CASE WHEN v_service_name = 'klaviyo' THEN 'disconnected' ELSE NULL END,
      NOW()
    )
    RETURNING id INTO v_credential_id;
    v_was_created := true;
  END IF;

  RETURN jsonb_build_object(
    'success', true,
    'title', fn_admin_envelope_message('integration_saved_title', v_lang, ARRAY[
      initcap(v_service_name),
      CASE WHEN v_was_created THEN fn_admin_envelope_message('word_created', v_lang)
           ELSE fn_admin_envelope_message('word_updated', v_lang) END
    ]),
    'description', fn_admin_envelope_message('integration_fields_saved_desc', v_lang, ARRAY[v_field_count::text]),
    'data', jsonb_build_object(
      'merchant_id', v_merchant_id,
      'credential_id', v_credential_id,
      'integration_key', v_service_name,
      'was_created', v_was_created,
      'field_count', v_field_count
    )
  );
END;
$function$;
