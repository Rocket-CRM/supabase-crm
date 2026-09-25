-- bff_upsert_single_earn_channel + bff_upsert_earn_channel with p_language

CREATE OR REPLACE FUNCTION public.bff_upsert_single_earn_channel(p_data jsonb, p_language text DEFAULT 'en'::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_lang                  text;
  v_merchant_id           UUID;
  v_channel_id            UUID;
  v_channel_code          TEXT;
  v_channel_type          TEXT;
  v_channel_name          TEXT;
  v_headline              TEXT;
  v_description           TEXT;
  v_banner_urls           TEXT[];
  v_howto_banners         TEXT[];
  v_howto_description     TEXT;
  v_stores_banner         TEXT;
  v_marketplace_platforms TEXT[];
  v_method_type           TEXT;
  v_display_order         INTEGER;
  v_config                JSONB;
  v_button_action         JSONB;
  v_active                BOOLEAN;
  v_default_award_scope   TEXT;
  v_is_create             BOOLEAN := false;
  v_existing              earn_channel%ROWTYPE;
  v_registry              earn_channel_registry%ROWTYPE;
  v_registry_found        BOOLEAN := false;
  v_is_registry_backed    BOOLEAN := false;
  v_result_name           TEXT;
  v_valid_types           TEXT[] := ARRAY['purchase', 'campaign', 'lifecycle', 'custom'];
BEGIN
  v_lang := fn_normalize_ui_language(p_language);
  v_merchant_id := get_current_merchant_id();
  IF v_merchant_id IS NULL THEN
    RETURN jsonb_build_object('success', false, 'code', 'NO_MERCHANT_CONTEXT',
      'title', fn_admin_envelope_message('no_merchant_title', v_lang),
      'description', fn_admin_envelope_message('could_not_resolve_merchant_desc', v_lang));
  END IF;

  IF p_data IS NULL OR jsonb_typeof(p_data) != 'object' THEN
    RETURN jsonb_build_object('success', false, 'code', 'VALIDATION_ERROR',
      'title', fn_admin_envelope_message('validation_error_title', v_lang),
      'description', fn_admin_envelope_message('json_object_required_desc', v_lang));
  END IF;

  v_channel_id      := NULLIF(p_data->>'id', '')::UUID;
  v_channel_code    := NULLIF(p_data->>'channel_code', '');
  v_channel_type    := NULLIF(p_data->>'channel_type', '');
  v_channel_name    := NULLIF(p_data->>'channel_name', '');
  v_headline        := p_data->>'headline';
  v_description     := p_data->>'description';
  v_method_type     := NULLIF(p_data->>'method_type', '');
  v_display_order   := COALESCE((p_data->>'display_order')::INTEGER, 0);
  v_active          := COALESCE((p_data->>'active')::BOOLEAN, true);
  v_howto_description := p_data->>'howto_description';
  v_stores_banner   := p_data->>'stores_banner';
  v_default_award_scope := NULLIF(p_data->>'default_award_scope', '');
  IF p_data ? 'config' AND jsonb_typeof(p_data->'config') = 'object' THEN
    v_config := p_data->'config';
  END IF;

  IF v_default_award_scope IS NOT NULL AND v_default_award_scope NOT IN ('purchase','purchase_item') THEN
    RETURN jsonb_build_object('success', false, 'code', 'INVALID_AWARD_SCOPE',
      'title', fn_admin_envelope_message('validation_error_title', v_lang),
      'description', fn_admin_envelope_message('invalid_award_scope_desc', v_lang, ARRAY[v_default_award_scope]));
  END IF;

  v_banner_urls := CASE
    WHEN p_data->'banner_urls' IS NOT NULL AND jsonb_typeof(p_data->'banner_urls') = 'array'
    THEN ARRAY(SELECT jsonb_array_elements_text(p_data->'banner_urls'))
    ELSE NULL END;
  v_howto_banners := CASE
    WHEN p_data->'howto_banners' IS NOT NULL AND jsonb_typeof(p_data->'howto_banners') = 'array'
    THEN ARRAY(SELECT jsonb_array_elements_text(p_data->'howto_banners'))
    ELSE NULL END;
  v_marketplace_platforms := CASE
    WHEN p_data->'marketplace_platforms' IS NOT NULL AND jsonb_typeof(p_data->'marketplace_platforms') = 'array'
    THEN ARRAY(SELECT jsonb_array_elements_text(p_data->'marketplace_platforms'))
    ELSE NULL END;

  IF v_channel_id IS NOT NULL THEN
    SELECT * INTO v_existing
    FROM earn_channel ec
    WHERE ec.id = v_channel_id AND ec.merchant_id = v_merchant_id;

    IF FOUND THEN
      v_channel_code := COALESCE(v_channel_code, v_existing.channel_code);
    ELSE
      SELECT * INTO v_registry
      FROM earn_channel_registry r
      WHERE public.fn_earn_channel_effective_id(v_merchant_id, r.channel_code) = v_channel_id
        AND COALESCE(r.is_active, true) = true
      LIMIT 1;

      IF NOT FOUND THEN
        RETURN jsonb_build_object('success', false, 'code', 'NOT_FOUND',
          'title', fn_admin_envelope_message('not_found_title', v_lang),
          'description', fn_admin_envelope_message('earn_channel_not_found_desc', v_lang, ARRAY[v_channel_id::text]));
      END IF;

      v_registry_found := true;
      v_channel_code := COALESCE(v_channel_code, v_registry.channel_code);
      v_channel_id := NULL;
    END IF;
  END IF;

  IF v_channel_code IS NOT NULL AND NOT v_registry_found THEN
    SELECT * INTO v_registry
    FROM earn_channel_registry r
    WHERE r.channel_code = v_channel_code
      AND COALESCE(r.is_active, true) = true
    LIMIT 1;
    v_registry_found := FOUND;
  END IF;

  IF v_registry_found THEN
    v_is_registry_backed := true;
    v_channel_type := COALESCE(v_channel_type, v_registry.type);
    v_method_type := COALESCE(v_method_type, v_registry.default_method_type, v_registry.ui_component);
    v_channel_name := COALESCE(v_channel_name, v_registry.display_name);
    v_headline := COALESCE(v_headline, v_registry.default_headline);
    v_description := COALESCE(v_description, v_registry.default_description);
    v_default_award_scope := COALESCE(v_default_award_scope, v_registry.default_award_scope, 'purchase');

    IF COALESCE((v_registry.capabilities->>'can_customize_method')::boolean, false) = false THEN
      v_method_type := COALESCE(v_existing.method_type, v_registry.default_method_type, v_registry.ui_component);
    END IF;

    IF COALESCE((v_registry.capabilities->>'can_customize_button')::boolean, false) = false THEN
      v_config := COALESCE(v_registry.default_config, '{}'::jsonb);
      v_button_action := COALESCE(v_registry.default_button_action, '{}'::jsonb);
    END IF;
  END IF;

  IF v_channel_type IS NOT NULL AND NOT (v_channel_type = ANY(v_valid_types)) THEN
    RETURN jsonb_build_object('success', false, 'code', 'INVALID_CHANNEL_TYPE',
      'title', fn_admin_envelope_message('invalid_channel_type_title', v_lang),
      'description', fn_admin_envelope_message('invalid_channel_type_desc', v_lang, ARRAY[v_channel_type]));
  END IF;

  IF v_config IS NULL THEN
    IF p_data->>'button_config_mode' IS NOT NULL
       AND p_data->>'button_config_mode' NOT IN ('url', 'page') THEN
      RETURN jsonb_build_object('success', false, 'code', 'VALIDATION_ERROR',
        'title', fn_admin_envelope_message('validation_error_title', v_lang),
        'description', fn_admin_envelope_message('button_config_mode_desc', v_lang, ARRAY[p_data->>'button_config_mode']));
    END IF;

    IF COALESCE(v_method_type, v_existing.method_type) IN ('external_link', 'generic_card') THEN
      v_config := CASE
        WHEN p_data->>'button_config_mode' IS NOT NULL
        THEN jsonb_build_object('mode', p_data->>'button_config_mode', 'value', p_data->>'button_config_value')
        ELSE '{}'::jsonb
      END;
    ELSE
      v_config := '{}'::jsonb;
    END IF;
  END IF;

  IF p_data ? 'seller_reference' AND jsonb_typeof(p_data->'seller_reference') = 'object' THEN
    v_config := COALESCE(v_config, '{}'::jsonb) || jsonb_build_object('seller_reference', p_data->'seller_reference');
  ELSIF p_data ? 'show_seller_reference' THEN
    v_config := COALESCE(v_config, '{}'::jsonb) || jsonb_build_object('seller_reference', jsonb_build_object('enabled', COALESCE((p_data->>'show_seller_reference')::boolean, false), 'required', COALESCE((p_data->>'require_seller_reference')::boolean, false)));
  END IF;

  IF p_data ? 'receipt_selection' AND jsonb_typeof(p_data->'receipt_selection') = 'object' THEN
    IF COALESCE(p_data->'receipt_selection'->>'mode', 'none') NOT IN ('none', 'channel', 'store_only') THEN
      RETURN jsonb_build_object('success', false, 'code', 'VALIDATION_ERROR',
        'title', fn_admin_envelope_message('validation_error_title', v_lang),
        'description', fn_admin_envelope_message('receipt_selection_mode_desc', v_lang));
    END IF;
    v_config := COALESCE(v_config, '{}'::jsonb) || jsonb_build_object(
      'receipt_selection',
      jsonb_build_object('mode', COALESCE(p_data->'receipt_selection'->>'mode', 'none'))
    );
  END IF;

  IF v_button_action IS NULL THEN
    v_button_action := jsonb_build_object(
      'show',  COALESCE((p_data->>'button_show')::boolean, false),
      'label', COALESCE(p_data->>'button_label', '')
    );
  END IF;

  IF v_channel_id IS NULL AND v_channel_code IS NOT NULL THEN
    SELECT * INTO v_existing
    FROM earn_channel ec
    WHERE ec.merchant_id = v_merchant_id
      AND ec.channel_code = v_channel_code
    ORDER BY ec.is_system DESC, ec.updated_at DESC NULLS LAST, ec.created_at DESC NULLS LAST
    LIMIT 1;

    IF FOUND THEN
      v_channel_id := v_existing.id;
    END IF;
  END IF;

  IF v_channel_id IS NULL THEN
    v_is_create := true;

    IF v_channel_code IS NULL THEN
      RETURN jsonb_build_object('success', false, 'code', 'VALIDATION_ERROR',
        'title', fn_admin_envelope_message('validation_error_title', v_lang),
        'description', fn_admin_envelope_message('channel_code_required_desc', v_lang));
    END IF;
    IF v_channel_type IS NULL THEN
      RETURN jsonb_build_object('success', false, 'code', 'VALIDATION_ERROR',
        'title', fn_admin_envelope_message('validation_error_title', v_lang),
        'description', fn_admin_envelope_message('channel_type_required_desc', v_lang));
    END IF;
    IF v_method_type IS NULL THEN
      RETURN jsonb_build_object('success', false, 'code', 'VALIDATION_ERROR',
        'title', fn_admin_envelope_message('validation_error_title', v_lang),
        'description', fn_admin_envelope_message('method_type_required_desc', v_lang));
    END IF;
    IF v_channel_name IS NULL THEN
      RETURN jsonb_build_object('success', false, 'code', 'VALIDATION_ERROR',
        'title', fn_admin_envelope_message('validation_error_title', v_lang),
        'description', fn_admin_envelope_message('channel_name_required_desc', v_lang));
    END IF;

    v_channel_id := CASE
      WHEN v_is_registry_backed THEN public.fn_earn_channel_effective_id(v_merchant_id, v_channel_code)
      ELSE gen_random_uuid()
    END;

    INSERT INTO earn_channel (
      id, merchant_id, channel_code, channel_type,
      channel_name, headline, description, banner_urls,
      howto_banners, howto_description, stores_banner, marketplace_platforms,
      method_type, display_order, config, button_action, active,
      default_award_scope, is_system, override_kind, source_type, source_ref,
      created_at, updated_at
    ) VALUES (
      v_channel_id, v_merchant_id, v_channel_code, v_channel_type,
      v_channel_name, v_headline, v_description, v_banner_urls,
      v_howto_banners, v_howto_description, v_stores_banner, v_marketplace_platforms,
      v_method_type, v_display_order, v_config, v_button_action, v_active,
      COALESCE(v_default_award_scope, 'purchase'), false,
      CASE WHEN v_is_registry_backed THEN 'default_override' ELSE 'custom' END,
      CASE WHEN v_is_registry_backed THEN 'registry' ELSE 'custom' END,
      CASE WHEN v_is_registry_backed THEN jsonb_build_object('registry_id', v_registry.id, 'channel_code', v_registry.channel_code) ELSE '{}'::jsonb END,
      NOW(), NOW()
    );
  ELSE
    UPDATE earn_channel SET
      channel_type          = COALESCE(v_channel_type, channel_type),
      channel_name          = COALESCE(v_channel_name, channel_name),
      headline              = v_headline,
      description           = v_description,
      banner_urls           = v_banner_urls,
      howto_banners         = v_howto_banners,
      howto_description     = v_howto_description,
      stores_banner         = v_stores_banner,
      marketplace_platforms = v_marketplace_platforms,
      method_type           = COALESCE(v_method_type, method_type),
      display_order         = v_display_order,
      config                = v_config,
      button_action         = v_button_action,
      active                = v_active,
      default_award_scope   = COALESCE(v_default_award_scope, default_award_scope),
      override_kind         = COALESCE(override_kind, CASE WHEN v_is_registry_backed THEN 'default_override' ELSE 'legacy' END),
      source_type           = COALESCE(source_type, CASE WHEN v_is_registry_backed THEN 'registry' ELSE 'legacy' END),
      source_ref            = CASE WHEN v_is_registry_backed AND (source_ref IS NULL OR source_ref = '{}'::jsonb)
                              THEN jsonb_build_object('registry_id', v_registry.id, 'channel_code', v_registry.channel_code)
                              ELSE COALESCE(source_ref, '{}'::jsonb) END,
      updated_at            = NOW()
    WHERE id = v_channel_id AND merchant_id = v_merchant_id;
  END IF;

  PERFORM public.fn_invalidate_earn_channels_cache(v_merchant_id);

  SELECT ec.channel_name INTO v_result_name
  FROM earn_channel ec WHERE ec.id = v_channel_id;

  RETURN jsonb_build_object(
    'success', true,
    'code', CASE WHEN v_is_create THEN 'CREATED' ELSE 'UPDATED' END,
    'title', CASE WHEN v_is_create
      THEN fn_admin_envelope_message('earn_channel_created_title', v_lang)
      ELSE fn_admin_envelope_message('earn_channel_updated_title', v_lang) END,
    'description', fn_admin_envelope_message('earn_channel_action_desc', v_lang, ARRAY[
      v_result_name,
      CASE WHEN v_is_create THEN fn_admin_envelope_message('word_created', v_lang)
           ELSE fn_admin_envelope_message('word_updated', v_lang) END
    ]),
    'channel_id', v_channel_id
  );

EXCEPTION WHEN OTHERS THEN
  RETURN jsonb_build_object('success', false, 'code', 'ERROR',
    'title', fn_admin_envelope_message('unexpected_error_title', v_lang),
    'description', SQLERRM, 'detail', SQLSTATE);
END;
$function$;

DROP FUNCTION IF EXISTS public.bff_upsert_single_earn_channel(jsonb);

CREATE OR REPLACE FUNCTION public.bff_upsert_earn_channel(p_data jsonb, p_language text DEFAULT 'en'::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_lang                  text;
  v_merchant_id           UUID;
  v_item                  JSONB;
  v_result                JSONB;
  v_channel_id            UUID;
  v_channels_to_keep      UUID[] := ARRAY[]::UUID[];
  v_created               INTEGER := 0;
  v_updated               INTEGER := 0;
  v_deleted               INTEGER := 0;
  v_deleted_count         INTEGER;
BEGIN
  v_lang := fn_normalize_ui_language(p_language);
  v_merchant_id := get_current_merchant_id();

  IF v_merchant_id IS NULL THEN
    RETURN jsonb_build_object(
      'success', false, 'code', 'NO_MERCHANT_CONTEXT',
      'title', fn_admin_envelope_message('no_merchant_title', v_lang),
      'description', fn_admin_envelope_message('could_not_resolve_merchant_desc', v_lang)
    );
  END IF;

  IF p_data IS NULL OR jsonb_typeof(p_data) != 'array' THEN
    RETURN jsonb_build_object(
      'success', false, 'code', 'VALIDATION_ERROR',
      'title', fn_admin_envelope_message('validation_error_title', v_lang),
      'description', fn_admin_envelope_message('earn_channels_array_required_desc', v_lang)
    );
  END IF;

  FOR v_item IN SELECT * FROM jsonb_array_elements(p_data)
  LOOP
    v_result := public.bff_upsert_single_earn_channel(v_item, v_lang);
    IF COALESCE((v_result->>'success')::boolean, false) = false THEN
      RETURN v_result;
    END IF;

    v_channel_id := NULLIF(v_result->>'channel_id', '')::uuid;
    IF v_channel_id IS NOT NULL THEN
      v_channels_to_keep := array_append(v_channels_to_keep, v_channel_id);
    END IF;

    IF v_result->>'code' = 'CREATED' THEN
      v_created := v_created + 1;
    ELSE
      v_updated := v_updated + 1;
    END IF;
  END LOOP;

  DELETE FROM earn_channel ec
  WHERE ec.merchant_id = v_merchant_id
    AND ec.id != ALL(v_channels_to_keep)
    AND COALESCE(ec.is_system, false) = false
    AND NOT EXISTS (
      SELECT 1 FROM earn_channel_registry r
      WHERE r.channel_code = ec.channel_code
        AND COALESCE(r.is_active, true) = true
    )
    AND NOT EXISTS (
      SELECT 1 FROM purchase_ledger pl WHERE pl.earning_channel_id = ec.id
    )
    AND NOT EXISTS (
      SELECT 1 FROM purchase_receipt_upload pru WHERE pru.earning_channel_id = ec.id
    );
  GET DIAGNOSTICS v_deleted_count = ROW_COUNT;
  v_deleted := v_deleted_count;

  PERFORM public.fn_invalidate_earn_channels_cache(v_merchant_id);

  RETURN jsonb_build_object(
    'success', true,
    'code', 'SYNCED',
    'title', fn_admin_envelope_message('earn_channels_synced_title', v_lang),
    'description', fn_admin_envelope_message('earn_channels_synced_desc', v_lang, ARRAY[(v_created + v_updated)::text]),
    'stats', jsonb_build_object(
      'created', v_created,
      'updated', v_updated,
      'deleted', v_deleted
    )
  );

EXCEPTION WHEN OTHERS THEN
  RETURN jsonb_build_object(
    'success', false, 'code', 'ERROR',
    'title', fn_admin_envelope_message('unexpected_error_title', v_lang),
    'description', SQLERRM, 'detail', SQLSTATE
  );
END;
$function$;

DROP FUNCTION IF EXISTS public.bff_upsert_earn_channel(jsonb);
