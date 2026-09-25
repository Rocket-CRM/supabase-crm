CREATE OR REPLACE FUNCTION public.bff_upsert_integration_config(p_integration_key text, p_config jsonb, p_language text DEFAULT 'en'::text)
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
      merchant_id, service_name, credentials, environment, is_active, updated_at
    ) VALUES (
      v_merchant_id, v_service_name, v_nested_config, 'production', true, NOW()
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

DROP FUNCTION IF EXISTS public.bff_upsert_integration_config(text, jsonb);

CREATE OR REPLACE FUNCTION public.bff_upsert_leaderboard_campaign(p_config jsonb, p_language text DEFAULT 'en'::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_lang text;
  v_merchant_id uuid;
  v_id uuid;
  v_campaign_code text;
  v_campaign_name text;
  v_path text;
  v_datawh_table_code text;
  v_banner jsonb;
  v_page_header text;
  v_page_description text;
  v_columns_config jsonb;
  v_rank_config jsonb;
  v_top_x integer;
  v_requires_participation boolean;
  v_active_status boolean;
  v_existing_id uuid;
  v_result_id uuid;
BEGIN
  v_lang := fn_normalize_ui_language(p_language);
  v_merchant_id := get_current_merchant_id();

  IF v_merchant_id IS NULL THEN
    RETURN jsonb_build_object(
      'success', false,
      'title', fn_admin_envelope_message('no_merchant_title', v_lang),
      'description', fn_admin_envelope_message('could_not_resolve_merchant_desc', v_lang)
    );
  END IF;

  v_id := NULLIF(p_config->>'id', '')::uuid;
  v_campaign_code := upper(regexp_replace(trim(COALESCE(p_config->>'campaign_code', '')), '[^A-Za-z0-9_-]+', '_', 'g'));
  v_campaign_name := NULLIF(trim(COALESCE(p_config->>'campaign_name', '')), '');
  v_path := lower(regexp_replace(trim(COALESCE(p_config->>'path', '')), '^/+', ''));
  v_path := regexp_replace(v_path, '/+$', '');
  v_datawh_table_code := NULLIF(trim(COALESCE(p_config->>'datawh_table_code', '')), '');
  v_banner := COALESCE(p_config->'banner', '[]'::jsonb);
  v_page_header := NULLIF(trim(COALESCE(p_config->>'page_header', '')), '');
  v_page_description := NULLIF(trim(COALESCE(p_config->>'page_description', '')), '');
  v_columns_config := COALESCE(p_config->'columns_config', '[]'::jsonb);
  v_rank_config := COALESCE(p_config->'rank_config', '{}'::jsonb);
  v_top_x := COALESCE(NULLIF(p_config->>'top_x', '')::integer, 10);
  v_requires_participation := COALESCE((p_config->>'requires_participation')::boolean, false);
  v_active_status := COALESCE((p_config->>'active_status')::boolean, true);

  IF v_campaign_code = '' THEN
    RETURN jsonb_build_object(
      'success', false,
      'title', fn_admin_envelope_message('validation_error_title', v_lang),
      'description', fn_admin_envelope_message('campaign_code_required_desc', v_lang)
    );
  END IF;

  IF v_campaign_name IS NULL THEN
    RETURN jsonb_build_object(
      'success', false,
      'title', fn_admin_envelope_message('validation_error_title', v_lang),
      'description', fn_admin_envelope_message('campaign_name_required_desc', v_lang)
    );
  END IF;

  IF v_path = '' THEN
    RETURN jsonb_build_object(
      'success', false,
      'title', fn_admin_envelope_message('validation_error_title', v_lang),
      'description', fn_admin_envelope_message('path_required_desc', v_lang)
    );
  END IF;

  IF v_datawh_table_code IS NULL THEN
    RETURN jsonb_build_object(
      'success', false,
      'title', fn_admin_envelope_message('validation_error_title', v_lang),
      'description', fn_admin_envelope_message('metabase_table_required_desc', v_lang)
    );
  END IF;

  IF v_top_x <= 0 THEN
    RETURN jsonb_build_object(
      'success', false,
      'title', fn_admin_envelope_message('validation_error_title', v_lang),
      'description', fn_admin_envelope_message('top_x_positive_desc', v_lang)
    );
  END IF;

  SELECT id INTO v_existing_id
  FROM campaign_leaderboard
  WHERE merchant_id = v_merchant_id
    AND path = v_path
    AND (v_id IS NULL OR id <> v_id)
  LIMIT 1;

  IF v_existing_id IS NOT NULL THEN
    RETURN jsonb_build_object(
      'success', false,
      'title', fn_admin_envelope_message('validation_error_title', v_lang),
      'description', fn_admin_envelope_message('path_already_used_desc', v_lang)
    );
  END IF;

  UPDATE campaign_master
  SET campaign_name = v_campaign_name,
      wh_table_code = v_datawh_table_code,
      banner = CASE
        WHEN jsonb_typeof(v_banner) = 'array' AND jsonb_array_length(v_banner) > 0 THEN v_banner->>0
        WHEN jsonb_typeof(v_banner) = 'string' THEN v_banner #>> '{}'
        ELSE banner
      END
  WHERE merchant_id = v_merchant_id
    AND campaign_code = v_campaign_code;

  IF NOT FOUND THEN
    INSERT INTO campaign_master (campaign_name, campaign_code, merchant_id, wh_table_code, banner)
    VALUES (
      v_campaign_name,
      v_campaign_code,
      v_merchant_id,
      v_datawh_table_code,
      CASE
        WHEN jsonb_typeof(v_banner) = 'array' AND jsonb_array_length(v_banner) > 0 THEN v_banner->>0
        WHEN jsonb_typeof(v_banner) = 'string' THEN v_banner #>> '{}'
        ELSE NULL
      END
    );
  END IF;

  IF v_id IS NULL THEN
    INSERT INTO campaign_leaderboard (
      campaign_code, path, datawh_table_code, merchant_id, banner,
      page_header, page_description, columns_config, rank_config, top_x,
      requires_participation, active_status, color_primary, color_secondary, updated_at
    ) VALUES (
      v_campaign_code, v_path, v_datawh_table_code, v_merchant_id, v_banner,
      v_page_header, v_page_description, v_columns_config, v_rank_config, v_top_x,
      v_requires_participation, v_active_status,
      NULLIF(p_config->>'color_primary', ''),
      NULLIF(p_config->>'color_secondary', ''),
      now()
    ) RETURNING id INTO v_result_id;
  ELSE
    UPDATE campaign_leaderboard
    SET campaign_code = v_campaign_code,
        path = v_path,
        datawh_table_code = v_datawh_table_code,
        banner = v_banner,
        page_header = v_page_header,
        page_description = v_page_description,
        columns_config = v_columns_config,
        rank_config = v_rank_config,
        top_x = v_top_x,
        requires_participation = v_requires_participation,
        active_status = v_active_status,
        color_primary = NULLIF(p_config->>'color_primary', ''),
        color_secondary = NULLIF(p_config->>'color_secondary', ''),
        updated_at = now()
    WHERE id = v_id
      AND merchant_id = v_merchant_id
    RETURNING id INTO v_result_id;

    IF v_result_id IS NULL THEN
      RETURN jsonb_build_object(
        'success', false,
        'title', fn_admin_envelope_message('not_found_title', v_lang),
        'description', fn_admin_envelope_message('leaderboard_not_found_desc', v_lang)
      );
    END IF;
  END IF;

  RETURN jsonb_build_object(
    'success', true,
    'code', 'leaderboard_saved',
    'title', fn_admin_envelope_message('leaderboard_saved_title', v_lang),
    'description', fn_admin_envelope_message('leaderboard_saved_desc', v_lang),
    'data', jsonb_build_object('id', v_result_id)
  );
END;
$function$;

DROP FUNCTION IF EXISTS public.bff_upsert_leaderboard_campaign(jsonb);

CREATE OR REPLACE FUNCTION public.bff_upsert_currency_config(p_data jsonb, p_language text DEFAULT 'en'::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_lang text;
  v_merchant_id UUID;
  v_new_type TEXT;
  v_default_burn numeric;
BEGIN
  v_lang := fn_normalize_ui_language(p_language);
  v_merchant_id := get_current_merchant_id();

  IF v_merchant_id IS NULL THEN
    RETURN jsonb_build_object('success', false, 'code', 'NO_MERCHANT_CONTEXT',
      'title', fn_admin_envelope_message('no_merchant_title', v_lang),
      'description', null, 'data', null);
  END IF;

  IF NOT check_admin_permission('currency', 'update') THEN
    RETURN jsonb_build_object('success', false, 'code', 'PERMISSION_DENIED',
      'title', fn_admin_envelope_message('permission_denied_title_cap', v_lang),
      'description', fn_admin_envelope_message('currency_update_permission_desc', v_lang),
      'data', null);
  END IF;

  IF p_data ? 'default_burn_rate' THEN
    v_default_burn := NULLIF(p_data->>'default_burn_rate', '')::numeric;
    IF v_default_burn IS NOT NULL AND v_default_burn < 0 THEN
      RETURN jsonb_build_object(
        'success', false,
        'code', 'INVALID_BURN_RATE',
        'title', fn_admin_envelope_message('invalid_burn_rate_title', v_lang),
        'description', fn_admin_envelope_message('invalid_burn_rate_desc', v_lang),
        'data', null
      );
    END IF;
  END IF;

  v_new_type := p_data->>'currency_award_delay_type';

  UPDATE merchant_master
  SET
    points_expiry_active = CASE
      WHEN p_data ? 'points_expiry_active'
        THEN COALESCE((p_data->>'points_expiry_active')::BOOLEAN, false)
      ELSE points_expiry_active
    END,
    points_expiry_mode = CASE
      WHEN p_data ? 'points_expiry_mode'
        THEN NULLIF(p_data->>'points_expiry_mode', '')
      ELSE points_expiry_mode
    END,
    points_ttl_months = CASE
      WHEN p_data ? 'points_ttl_months'
        THEN NULLIF(p_data->>'points_ttl_months', '')::INTEGER
      ELSE points_ttl_months
    END,
    points_frequency = CASE
      WHEN p_data ? 'points_frequency'
        THEN NULLIF(p_data->>'points_frequency', '')
      ELSE points_frequency
    END,
    points_fiscal_year_end_month = CASE
      WHEN p_data ? 'points_fiscal_year_end_month'
        THEN NULLIF(p_data->>'points_fiscal_year_end_month', '')::INTEGER
      ELSE points_fiscal_year_end_month
    END,
    points_minimum_period_months = CASE
      WHEN p_data ? 'points_minimum_period_months'
        THEN NULLIF(p_data->>'points_minimum_period_months', '')::INTEGER
      ELSE points_minimum_period_months
    END,
    currency_award_delay_type = COALESCE(v_new_type, currency_award_delay_type),
    currency_award_delay_days = CASE
      WHEN v_new_type = 'rolling_days'
        THEN COALESCE(NULLIF(p_data->>'currency_award_delay_days', '')::INTEGER, 0)
      WHEN v_new_type IN ('immediate', 'rolling_minutes', 'scheduled')
        THEN 0
      ELSE currency_award_delay_days
    END,
    currency_award_delay_minutes = CASE
      WHEN v_new_type = 'rolling_minutes'
        THEN COALESCE(NULLIF(p_data->>'currency_award_delay_minutes', '')::INTEGER, 0)
      WHEN v_new_type IN ('immediate', 'rolling_days', 'scheduled')
        THEN 0
      ELSE currency_award_delay_minutes
    END,
    currency_award_time = CASE
      WHEN p_data ? 'currency_award_time'
        THEN NULLIF(p_data->>'currency_award_time', '')::TIME
      WHEN v_new_type IN ('immediate', 'rolling_minutes')
        THEN NULL
      ELSE currency_award_time
    END,
    currency_award_timezone = COALESCE(p_data->>'currency_award_timezone', currency_award_timezone),
    default_burn_rate = CASE
      WHEN p_data ? 'default_burn_rate'
        THEN NULLIF(p_data->>'default_burn_rate', '')::numeric
      ELSE default_burn_rate
    END
  WHERE id = v_merchant_id;

  RETURN jsonb_build_object(
    'success', true,
    'code', 'CONFIG_UPDATED',
    'title', fn_admin_envelope_message('currency_settings_updated_title', v_lang),
    'description', fn_admin_envelope_message('currency_config_saved_desc', v_lang),
    'data', null
  );
EXCEPTION
  WHEN check_violation THEN
    RETURN jsonb_build_object(
      'success', false,
      'code', 'VALIDATION_ERROR',
      'title', fn_admin_envelope_message('invalid_currency_settings_title', v_lang),
      'description', CASE
        WHEN SQLERRM ILIKE '%chk_points_frequency_config%'
          THEN fn_admin_envelope_message('points_frequency_config_desc', v_lang)
        WHEN SQLERRM ILIKE '%chk_points_ttl_config%'
          THEN fn_admin_envelope_message('points_ttl_config_desc', v_lang)
        WHEN SQLERRM ILIKE '%default_burn_rate%'
          THEN fn_admin_envelope_message('burn_rate_nonneg_desc', v_lang)
        ELSE fn_admin_envelope_message('check_points_expiry_desc', v_lang)
      END,
      'data', null
    );
END;
$function$;

DROP FUNCTION IF EXISTS public.bff_upsert_currency_config(jsonb);
