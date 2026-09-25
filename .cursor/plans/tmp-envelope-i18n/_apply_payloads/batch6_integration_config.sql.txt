CREATE OR REPLACE FUNCTION public.bff_get_integration_config(p_integration_key text, p_language text DEFAULT 'en'::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
DECLARE
  v_lang text;
  v_merchant_id UUID;
  v_integration_type RECORD;
  v_credentials RECORD;
  v_fields JSONB := '[]'::jsonb;
  v_structure JSONB := '[]'::jsonb;
  v_current_values JSONB := NULL;
  v_service_name TEXT;
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

  SELECT id, integration_key, display_name, description, platform_key, platform_name
  INTO v_integration_type
  FROM integration_type_master
  WHERE LOWER(integration_key) = LOWER(p_integration_key);

  IF v_integration_type.id IS NULL THEN
    RETURN jsonb_build_object(
      'success', false,
      'title', fn_admin_envelope_message('integration_type_not_found_title', v_lang, ARRAY[p_integration_key]),
      'description', fn_admin_envelope_message('integration_type_not_found_desc', v_lang),
      'data', NULL
    );
  END IF;

  v_service_name := v_integration_type.integration_key;

  SELECT mc.id AS credential_id, mc.credentials, mc.environment, mc.is_active, mc.external_id, mc.updated_at
  INTO v_credentials
  FROM merchant_credentials mc
  WHERE mc.merchant_id = v_merchant_id
    AND mc.service_name = v_service_name
  ORDER BY mc.updated_at DESC NULLS LAST
  LIMIT 1;

  SELECT jsonb_agg(
    jsonb_build_object(
      'field_name', ifd.field_name,
      'data_type', ifd.data_type,
      'is_required', COALESCE(ifd.is_required, false),
      'is_sensitive', NOT COALESCE(ifd.expose_in_public_api, true),
      'group_key', ifd.group_key,
      'value', CASE
        WHEN v_credentials.credentials IS NULL THEN ''
        WHEN NOT COALESCE(ifd.expose_in_public_api, true)
          AND v_credentials.credentials #>> string_to_array(
            substring(ifd.field_path from position('.' in ifd.field_path) + 1), '.'
          ) IS NOT NULL
          AND v_credentials.credentials #>> string_to_array(
            substring(ifd.field_path from position('.' in ifd.field_path) + 1), '.'
          ) != ''
        THEN '***'
        ELSE COALESCE(
          v_credentials.credentials #>> string_to_array(
            substring(ifd.field_path from position('.' in ifd.field_path) + 1), '.'
          ), ''
        )
      END
    ) ORDER BY ifd.group_order, ifd.field_order, ifd.field_name
  )
  INTO v_fields
  FROM integration_field_definitions ifd
  WHERE ifd.integration_type_id = v_integration_type.id;

  v_fields := COALESCE(v_fields, '[]'::jsonb);

  SELECT jsonb_agg(
    jsonb_build_object(
      'group_key', mg.group_key,
      'group_name', mg.group_name,
      'group_order', mg.group_order,
      'fields', mg.fields
    )
    ORDER BY mg.group_order
  )
  INTO v_structure
  FROM (
    SELECT
      ifd.group_key,
      ifd.group_name,
      ifd.group_order,
      jsonb_agg(
        jsonb_build_object(
          'title', COALESCE(ifd.display_title, initcap(replace(ifd.field_name, '_', ' '))),
          'init_value', ifd.field_name,
          'type', COALESCE(ifd.input_type, 'normal'),
          'data_type', ifd.data_type,
          'is_required', COALESCE(ifd.is_required, false),
          'is_sensitive', NOT COALESCE(ifd.expose_in_public_api, true)
        ) || CASE
          WHEN ifd.select_options IS NOT NULL
          THEN jsonb_build_object('options', ifd.select_options)
          ELSE '{}'::jsonb
        END
        ORDER BY ifd.field_order, ifd.field_name
      ) AS fields
    FROM integration_field_definitions ifd
    WHERE ifd.integration_type_id = v_integration_type.id
    GROUP BY ifd.group_key, ifd.group_name, ifd.group_order
  ) mg;

  v_structure := COALESCE(v_structure, '[]'::jsonb);

  IF v_credentials.credentials IS NOT NULL THEN
    SELECT jsonb_object_agg(
      ifd.field_name,
      CASE
        WHEN NOT COALESCE(ifd.expose_in_public_api, true)
          AND v_credentials.credentials #>> string_to_array(
            substring(ifd.field_path from position('.' in ifd.field_path) + 1), '.'
          ) IS NOT NULL
          AND v_credentials.credentials #>> string_to_array(
            substring(ifd.field_path from position('.' in ifd.field_path) + 1), '.'
          ) != ''
        THEN to_jsonb('***'::text)
        ELSE COALESCE(
          v_credentials.credentials #> string_to_array(
            substring(ifd.field_path from position('.' in ifd.field_path) + 1), '.'
          ),
          'null'::jsonb
        )
      END
    )
    INTO v_current_values
    FROM integration_field_definitions ifd
    WHERE ifd.integration_type_id = v_integration_type.id;
  END IF;

  RETURN jsonb_build_object(
    'success', true,
    'title', NULL,
    'description', NULL,
    'data', jsonb_build_object(
      'integration_key', v_service_name,
      'display_name', v_integration_type.display_name,
      'platform_key', v_integration_type.platform_key,
      'platform_name', v_integration_type.platform_name,
      'fields', v_fields,
      'structure', v_structure,
      'current_values', CASE
        WHEN v_credentials.credential_id IS NOT NULL THEN
          jsonb_build_object(
            'credential_id', v_credentials.credential_id,
            'environment', v_credentials.environment,
            'external_id', v_credentials.external_id,
            'is_active', v_credentials.is_active,
            'updated_at', v_credentials.updated_at,
            'values', v_current_values
          )
        ELSE NULL
      END
    )
  );
END;
$function$;

DROP FUNCTION IF EXISTS public.bff_get_integration_config(text);
