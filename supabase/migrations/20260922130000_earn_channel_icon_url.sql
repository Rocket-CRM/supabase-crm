-- Earn channel merchant icon override → landing / hub / widget

ALTER TABLE public.earn_channel ADD COLUMN IF NOT EXISTS icon_url text;

CREATE OR REPLACE FUNCTION public.fn_enrich_shopify_landing_sections(
  p_sections jsonb,
  p_merchant_id uuid,
  p_language text DEFAULT 'en',
  p_user_id uuid DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SET search_path TO 'public'
AS $function$
DECLARE
  v_out jsonb := '[]'::jsonb;
  v_section jsonb;
  v_type text;
  v_cfg jsonb;
  v_hub jsonb;
  v_points text;
  v_current_tier uuid;
  v_tile jsonb;
  v_tiles jsonb;
  v_referral jsonb;
BEGIN
  v_hub := public.fn_compose_shopify_hub(p_merchant_id, p_user_id, p_language);
  v_points := coalesce(v_hub -> 'branding' ->> 'points_name', 'Points');

  IF p_user_id IS NOT NULL THEN
    SELECT ua.tier_id INTO v_current_tier
    FROM public.user_accounts ua
    WHERE ua.id = p_user_id AND ua.merchant_id = p_merchant_id;
  END IF;

  IF p_sections IS NULL OR jsonb_typeof(p_sections) <> 'array' THEN
    RETURN v_out;
  END IF;

  FOR v_section IN SELECT * FROM jsonb_array_elements(p_sections)
  LOOP
    v_type := v_section ->> 'block_type';
    v_cfg := public.fn_shopify_landing_merge_section_config(
      v_type,
      coalesce(v_section -> 'config', '{}'::jsonb)
    );
    v_section := (v_section - 'config' - 'style_tokens')
      || jsonb_build_object('config', v_cfg);

    IF v_type = 'shopify_landing_ways_to_earn' THEN
      v_tiles := '[]'::jsonb;
      FOR v_tile IN
        SELECT * FROM jsonb_array_elements(coalesce(v_hub -> 'earn', '[]'::jsonb))
      LOOP
        v_tiles := v_tiles || jsonb_build_array(
          jsonb_build_object(
            'name', coalesce(v_tile ->> 'title', ''),
            'points_label', coalesce(v_tile ->> 'reward_copy', ''),
            'icon_url', v_tile ->> 'icon_url',
            'featured', coalesce(v_tile ->> 'method', '') = 'purchase'
          )
        );
      END LOOP;
      v_section := v_section || jsonb_build_object('tiles', v_tiles);
    ELSIF v_type = 'shopify_landing_ways_to_spend' THEN
      v_tiles := '[]'::jsonb;
      FOR v_tile IN
        SELECT * FROM jsonb_array_elements(
          coalesce(v_hub -> 'spend', '[]'::jsonb) || coalesce(v_hub -> 'shop', '[]'::jsonb)
        )
      LOOP
        v_tiles := v_tiles || jsonb_build_array(
          jsonb_build_object(
            'name', coalesce(v_tile ->> 'name', ''),
            'points_label', trim(
              coalesce(v_tile ->> 'cost', '0') || ' ' || v_points
            ),
            'image_url', v_tile ->> 'image_url',
            'icon_url', v_tile ->> 'image_url',
            'affordable', coalesce((v_tile ->> 'affordable')::boolean, false)
          )
        );
      END LOOP;
      v_section := v_section || jsonb_build_object('tiles', v_tiles);
    ELSIF v_type = 'shopify_landing_vip' THEN
      v_section := v_section || jsonb_build_object(
        'tiers',
        public.fn_shopify_landing_vip_tiers_from_hub(
          coalesce(v_hub -> 'tiers', '[]'::jsonb),
          v_current_tier
        )
      );
    ELSIF v_type = 'shopify_landing_referrals' THEN
      v_referral := v_hub -> 'referral';
      IF v_referral IS NOT NULL AND v_referral <> 'null'::jsonb THEN
        v_section := v_section || jsonb_build_object(
          'referral_offers',
          jsonb_build_object(
            'you_get', coalesce(v_referral ->> 'you_get', ''),
            'they_get', coalesce(v_referral ->> 'they_get', '')
          )
        );
      END IF;
    END IF;

    v_out := v_out || jsonb_build_array(v_section);
  END LOOP;

  RETURN v_out;
END;
$function$;

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
  v_icon_url              TEXT;
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
  IF p_data ? 'icon_url' THEN
    v_icon_url := NULLIF(p_data->>'icon_url', '');
  END IF;
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

  IF p_data ? 'receipt_number' THEN
    IF jsonb_typeof(p_data->'receipt_number') IS DISTINCT FROM 'object' THEN
      RETURN jsonb_build_object('success', false, 'code', 'VALIDATION_ERROR',
        'title', fn_admin_envelope_message('validation_error_title', v_lang),
        'description', 'receipt_number must be an object with enabled/required');
    END IF;
    v_config := COALESCE(v_config, '{}'::jsonb) || jsonb_build_object(
      'receipt_number', public.fn_receipt_member_field_toggle(p_data->'receipt_number')
    );
  END IF;

  IF p_data ? 'purchase_date' THEN
    IF jsonb_typeof(p_data->'purchase_date') IS DISTINCT FROM 'object' THEN
      RETURN jsonb_build_object('success', false, 'code', 'VALIDATION_ERROR',
        'title', fn_admin_envelope_message('validation_error_title', v_lang),
        'description', 'purchase_date must be an object with enabled/required');
    END IF;
    v_config := COALESCE(v_config, '{}'::jsonb) || jsonb_build_object(
      'purchase_date', public.fn_receipt_member_field_toggle(p_data->'purchase_date')
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
      method_type, display_order, config, button_action, active, icon_url,
      default_award_scope, is_system, override_kind, source_type, source_ref,
      created_at, updated_at
    ) VALUES (
      v_channel_id, v_merchant_id, v_channel_code, v_channel_type,
      v_channel_name, v_headline, v_description, v_banner_urls,
      v_howto_banners, v_howto_description, v_stores_banner, v_marketplace_platforms,
      v_method_type, v_display_order, v_config, v_button_action, v_active,
      CASE WHEN p_data ? 'icon_url' THEN v_icon_url ELSE NULL END,
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
      icon_url              = CASE WHEN p_data ? 'icon_url' THEN v_icon_url ELSE icon_url END,
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


CREATE OR REPLACE FUNCTION public.fn_compose_shopify_hub_unbranded(p_merchant_id uuid, p_user_id uuid, p_language text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_language text;
  v_store_name text;
  v_store_url text;
  v_points_name text;
  v_symbol_type text;
  v_symbol_icon text;
  v_symbol_image text;
  v_hero text;
  v_header_type text;
  v_header_items jsonb;
  v_earn_rate jsonb;
  v_member jsonb;
  v_my_rewards jsonb;
  v_spend jsonb;
  v_shop jsonb;
  v_tiers jsonb;
  v_earn jsonb;
  v_referral jsonb;
  v_ua public.user_accounts;
  v_balance numeric := 0;
  v_expiry date;
  v_expiring numeric;
  v_expiry_json jsonb;
  v_as_of date := (timezone('Asia/Bangkok', now()))::date;
  v_tp record;
  v_program public.referral_program;
  v_member_code text;
  v_hop text;
  v_share_url text;
BEGIN
  IF p_merchant_id IS NULL THEN
    RETURN jsonb_build_object('error_code', 'NO_MERCHANT_CONTEXT');
  END IF;

  SELECT language_code INTO v_language
  FROM public.merchant_languages
  WHERE merchant_id = p_merchant_id AND is_default = true
  LIMIT 1;
  v_language := COALESCE(NULLIF(trim(p_language), ''), v_language, 'en');

  SELECT mm.name INTO v_store_name FROM public.merchant_master mm WHERE mm.id = p_merchant_id;

  SELECT 'https://' || (mc.credentials->>'shop_domain')
  INTO v_store_url
  FROM public.merchant_credentials mc
  WHERE mc.merchant_id = p_merchant_id
    AND mc.service_name = 'shopify_app'
    AND mc.is_active IS TRUE
    AND NULLIF(mc.credentials->>'shop_domain', '') IS NOT NULL
  LIMIT 1;

  SELECT
    mds.points_unit_label,
    mds.points_symbol_type,
    mds.points_symbol_icon,
    mds.points_symbol_image_url
  INTO v_points_name, v_symbol_type, v_symbol_icon, v_symbol_image
  FROM public.merchant_display_settings mds
  WHERE mds.merchant_id = p_merchant_id;
  v_points_name := COALESCE(NULLIF(btrim(v_points_name), ''), 'Points');

  SELECT
    mws.config #>> '{header,background,type}',
    mws.config #> '{header,background,image,items}'
  INTO v_header_type, v_header_items
  FROM public.merchant_widget_settings mws
  WHERE mws.merchant_id = p_merchant_id
    AND mws.widget_type = 'shopify'
    AND mws.active_status IS TRUE
  LIMIT 1;

  IF v_header_type = 'image' AND jsonb_typeof(v_header_items) = 'array' THEN
    SELECT item->>'url'
    INTO v_hero
    FROM jsonb_array_elements(v_header_items) AS item
    WHERE NULLIF(item->>'url', '') IS NOT NULL
    ORDER BY COALESCE((item->>'order')::int, 0)
    LIMIT 1;
  END IF;

  v_earn_rate := public.fn_resolve_widget_earn_rate(p_merchant_id);

  IF p_user_id IS NOT NULL THEN
    SELECT * INTO v_ua FROM public.user_accounts
    WHERE id = p_user_id AND merchant_id = p_merchant_id AND deleted_at IS NULL;
  END IF;

  IF v_ua.id IS NOT NULL THEN
    SELECT COALESCE(uw.points_balance, 0) INTO v_balance
    FROM public.user_wallet uw
    WHERE uw.user_id = v_ua.id AND uw.merchant_id = p_merchant_id;

    IF public.fn_loyalty_expiry_display_enabled(p_merchant_id) THEN
      v_expiry_json := public.fn_loyalty_expiry_envelope(v_ua.id, p_merchant_id, v_as_of);
      v_expiry := NULLIF(v_expiry_json -> 'next' ->> 'expiry_date', '')::date;
      v_expiring := COALESCE((v_expiry_json -> 'next' ->> 'amount')::numeric, 0);
    END IF;

    SELECT
      tp.next_tier_id,
      nt.tier_name AS next_tier_name,
      tp.upgrade_progress_percent,
      tp.upgrade_metric_current,
      tp.upgrade_threshold,
      tp.maintain_deadline,
      GREATEST(0, COALESCE(tp.upgrade_threshold, 0) - COALESCE(tp.upgrade_metric_current, 0)) AS amount_to_next
    INTO v_tp
    FROM public.tier_progress tp
    LEFT JOIN public.tier_master nt ON nt.id = tp.next_tier_id
    WHERE tp.user_id = v_ua.id AND tp.merchant_id = p_merchant_id;

    SELECT jsonb_build_object(
      'first_name', v_ua.firstname,
      'points_balance', v_balance,
      'points_expiry_date', v_expiry,
      'points_expiring_next', v_expiring,
      'tier', CASE WHEN tm.id IS NULL THEN NULL ELSE jsonb_build_object(
        'id', tm.id,
        'name', tm.tier_name,
        'icon', tm.icon,
        'attained_until', v_tp.maintain_deadline,
        'next_tier_name', v_tp.next_tier_name,
        'amount_to_next', v_tp.amount_to_next,
        'progress_value', COALESCE(v_tp.upgrade_metric_current, 0),
        'progress_max', COALESCE(v_tp.upgrade_threshold, 0),
        'metric', NULL
      ) END
    )
    INTO v_member
    FROM (SELECT 1) s
    LEFT JOIN public.tier_master tm ON tm.id = v_ua.tier_id;
  END IF;

  IF v_ua.id IS NOT NULL THEN
    SELECT COALESCE(jsonb_agg(jsonb_build_object(
      'redemption_id', rrl.id,
      'reward_name', rm.name,
      'discount_label', rm.shopify_discount_label,
      'code', COALESCE(NULLIF(rrl.promo_code, ''), rrl.code),
      'use_expire_date', rrl.use_expire_date,
      'terms', rm.description_tc
    ) ORDER BY rrl.created_at DESC), '[]'::jsonb)
    INTO v_my_rewards
    FROM public.reward_redemptions_ledger rrl
    LEFT JOIN public.reward_master rm ON rm.id = rrl.reward_id
    WHERE rrl.merchant_id = p_merchant_id
      AND rrl.user_id = v_ua.id
      AND rrl.redeemed_status = true
      AND COALESCE(rrl.used_status, false) = false
      AND COALESCE(rrl.cancelled, false) = false
      AND (rrl.use_expire_date IS NULL OR rrl.use_expire_date > now());
  ELSE
    v_my_rewards := '[]'::jsonb;
  END IF;

  WITH priced AS (
    SELECT
      r.id,
      r.name,
      r.shopify_discount_label,
      r.shopify_discount_type,
      r.shopify_free_product_id,
      CASE WHEN r.image IS NOT NULL AND cardinality(r.image) > 0 THEN r.image[1] ELSE NULL END AS image_url,
      CASE
        WHEN best_match.id IS NOT NULL THEN best_match.points_required
        WHEN r.fallback_points IS NOT NULL THEN r.fallback_points
        ELSE 0
      END AS cost
    FROM public.reward_master r
    LEFT JOIN LATERAL (
      SELECT rpc.id, rpc.points_required
      FROM public.reward_points_conditions rpc
      WHERE v_ua.id IS NOT NULL
        AND rpc.reward_id = r.id
        AND rpc.active_status = true
        AND (rpc.tier_id IS NULL OR rpc.tier_id = v_ua.tier_id)
        AND (rpc.user_type IS NULL OR rpc.user_type = v_ua.user_type)
        AND (rpc.persona_id IS NULL OR rpc.persona_id = v_ua.persona_id)
      ORDER BY
        (CASE WHEN rpc.tier_id IS NOT NULL THEN 1 ELSE 0 END
         + CASE WHEN rpc.user_type IS NOT NULL THEN 1 ELSE 0 END
         + CASE WHEN rpc.persona_id IS NOT NULL THEN 1 ELSE 0 END) DESC,
        rpc.priority DESC NULLS LAST,
        rpc.points_required ASC
      LIMIT 1
    ) best_match ON true
    WHERE r.merchant_id = p_merchant_id
      AND r.active_status IS TRUE
      AND COALESCE(r.visibility::text, 'user') = 'user'
      AND r.shopify_discount_type IN ('percentage', 'fixed_amount', 'free_shipping', 'free_product')
  )
  SELECT
    COALESCE(jsonb_agg(jsonb_build_object(
      'reward_id', p.id,
      'name', p.name,
      'discount_label', p.shopify_discount_label,
      'cost', p.cost,
      'affordable', v_ua.id IS NOT NULL AND v_balance >= COALESCE(p.cost, 0),
      'image_url', p.image_url
    ) ORDER BY p.name) FILTER (WHERE p.shopify_discount_type IN ('percentage', 'fixed_amount', 'free_shipping')), '[]'::jsonb),
    COALESCE(jsonb_agg(jsonb_build_object(
      'reward_id', p.id,
      'name', p.name,
      'discount_label', p.shopify_discount_label,
      'cost', p.cost,
      'affordable', v_ua.id IS NOT NULL AND v_balance >= COALESCE(p.cost, 0),
      'image_url', p.image_url,
      'shopify_product_id', p.shopify_free_product_id
    ) ORDER BY p.name) FILTER (WHERE p.shopify_discount_type = 'free_product'), '[]'::jsonb)
  INTO v_spend, v_shop
  FROM priced p;

  SELECT COALESCE(jsonb_agg(jsonb_build_object(
    'id', tm.id,
    'name', tm.tier_name,
    'icon', tm.icon,
    'threshold_label', CASE WHEN tcu.amount IS NULL THEN NULL ELSE tcu.amount::text END,
    'is_current', v_ua.tier_id IS NOT NULL AND tm.id = v_ua.tier_id,
    'entry_rewards', COALESCE((
      SELECT jsonb_agg(
        COALESCE(NULLIF(btrim(ter.description), ''), rm.name, (ter.points_amount::text || ' ' || v_points_name))
        ORDER BY ter.sort_order, ter.created_at
      )
      FROM public.tier_entry_rewards ter
      LEFT JOIN public.reward_master rm ON rm.id = ter.reward_id
      WHERE ter.merchant_id = p_merchant_id
        AND ter.tier_id = tm.id
        AND ter.active_status IS TRUE
    ), '[]'::jsonb),
    'perks', COALESCE((
      SELECT jsonb_agg(COALESCE(perk->>'name', perk->>'title', perk->>'label', perk->>'description'))
      FROM jsonb_array_elements(public.fn_tier_composed_perks_json(tm.id)) perk
      WHERE COALESCE(perk->>'name', perk->>'title', perk->>'label', perk->>'description') IS NOT NULL
    ), '[]'::jsonb)
  ) ORDER BY tcu.amount ASC NULLS FIRST, tm.tier_name), '[]'::jsonb)
  INTO v_tiers
  FROM public.tier_master tm
  LEFT JOIN public.tier_conditions tcu
    ON tcu.tier_id = tm.id AND tcu.condition_type = 'upgrade' AND tcu.active_status IS TRUE
  WHERE tm.merchant_id = p_merchant_id
    AND tm.tier_name IS NOT NULL
    AND btrim(tm.tier_name) <> '';

  SELECT COALESCE(jsonb_agg(jsonb_build_object(
    'id', c.id,
    'method', CASE
      WHEN c.channel_code = 'shopify_store' THEN 'purchase'
      WHEN c.method_type = 'referral' OR c.channel_code ILIKE '%referral%' THEN 'referral'
      WHEN c.channel_code ILIKE '%birthday%' THEN 'birthday'
      WHEN c.method_type = 'social' THEN 'social'
      WHEN c.method_type = 'external_link' THEN 'external_link'
      ELSE COALESCE(c.method_type, 'external_link')
    END,
    'title', COALESCE(c.headline, c.channel_name),
    'description', c.description,
    'reward_copy', CASE
      WHEN c.channel_code = 'shopify_store' AND (v_earn_rate->>'base_points_per_unit') IS NOT NULL THEN
        trim(to_char(COALESCE((v_earn_rate->>'base_points_per_unit')::numeric, 0), 'FM999990.099999'))
        || ' ' || v_points_name || ' for every '
        || CASE
             WHEN NULLIF(v_earn_rate->>'currency', '') IS NULL THEN '1'
             ELSE (v_earn_rate->>'currency') || '1'
           END
        || ' spent'
      ELSE COALESCE(c.howto_description, c.description)
    END,
    'cta_label', COALESCE(c.button_action->>'label', 'Learn more'),
    'cta_url', CASE
      WHEN c.channel_code = 'shopify_store' THEN v_store_url
      WHEN c.method_type = 'referral' OR c.channel_code ILIKE '%referral%' THEN '#referrals'
      WHEN c.method_type = 'external_link' THEN COALESCE(c.config->>'value', c.button_action->>'value')
      ELSE COALESCE(c.config->>'value', c.button_action->>'value')
    END,
    'icon_url', COALESCE(
      c.icon_url,
      (
        SELECT r.default_icon_url
        FROM public.earn_channel_registry r
        WHERE r.channel_code = c.channel_code
          AND COALESCE(r.is_active, true) = true
        LIMIT 1
      )
    )
  ) ORDER BY c.display_order ASC, c.channel_name ASC), '[]'::jsonb)
  INTO v_earn
  FROM public.fn_get_effective_earn_channels(p_merchant_id, v_language, false) c
  WHERE c.active = true
    AND c.channel_type <> 'campaign'
    AND NOT (c.channel_type = 'purchase' AND c.channel_code <> 'shopify_store');

  SELECT * INTO v_program FROM public.referral_program WHERE merchant_id = p_merchant_id;
  IF v_program.id IS NOT NULL AND v_program.is_active AND 'shopify' = ANY (COALESCE(v_program.platforms, '{}'::text[])) THEN
    IF v_ua.id IS NOT NULL AND COALESCE(v_program.purchase_enabled, false) THEN
      v_member_code := public.fn_ensure_member_code(v_ua.id, p_merchant_id);
      v_hop := public.fn_referral_share_hop(p_merchant_id);
      IF v_hop IS NOT NULL AND v_member_code IS NOT NULL THEN
        v_share_url := v_hop || '?p=shopify&r=' || v_member_code;
      END IF;
    END IF;
    v_referral := jsonb_build_object(
      'active', true,
      'share_url', v_share_url,
      'you_get', COALESCE(v_program.friend_offer->>'referrer_label', v_program.friend_offer->>'you_get', 'A thank-you reward'),
      'they_get', COALESCE(v_program.friend_offer->>'headline', v_program.friend_offer->>'label', v_program.friend_offer->>'they_get', 'A welcome reward'),
      'intro', COALESCE(v_program.friend_offer->>'intro', 'Share your link. They get a reward, you get one when they order.')
    );
  ELSE
    v_referral := NULL;
  END IF;

  RETURN jsonb_build_object(
    'branding', jsonb_build_object(
      'store_name', COALESCE(v_store_name, ''),
      'store_url', v_store_url,
      'points_name', v_points_name,
      'points_symbol', jsonb_build_object(
        'type', v_symbol_type,
        'icon', v_symbol_icon,
        'image_url', v_symbol_image
      ),
      'hero_image_url', v_hero
    ),
    'member', v_member,
    'my_rewards', COALESCE(v_my_rewards, '[]'::jsonb),
    'spend', COALESCE(v_spend, '[]'::jsonb),
    'shop', COALESCE(v_shop, '[]'::jsonb),
    'tiers', COALESCE(v_tiers, '[]'::jsonb),
    'earn', COALESCE(v_earn, '[]'::jsonb),
    'referral', v_referral,
    'earn_rate', v_earn_rate
  );
END;
$function$;


CREATE OR REPLACE FUNCTION public.bff_get_earn_channels(p_language text DEFAULT NULL::text, p_surface text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
DECLARE
  v_merchant_id   UUID;
  v_language      TEXT;
  v_surface       TEXT;
  v_cache_key     TEXT;
  v_cached_result TEXT;
  v_cached_data   JSONB;
  v_page_icon     TEXT;
  v_default_icon  TEXT := 'https://wkevmsedchftztoolkmi.supabase.co/storage/v1/object/public/default%20images/Earn%20page%20default%20icon.svg';
  v_channels      JSONB;
BEGIN
  v_merchant_id := get_current_merchant_id();

  IF v_merchant_id IS NULL THEN
    RAISE EXCEPTION 'No merchant context found';
  END IF;

  SELECT language_code INTO v_language
  FROM merchant_languages
  WHERE merchant_id = v_merchant_id AND is_default = true
  LIMIT 1;

  v_language  := COALESCE(p_language, v_language, 'en');
  v_surface   := NULLIF(lower(trim(p_surface)), '');
  v_cache_key := 'merchant:' || v_merchant_id::TEXT || ':earn_channels:' || v_language
                 || ':surface:' || COALESCE(v_surface, 'default');

  BEGIN
    v_cached_result := extensions.earn_channels_cache_get(v_cache_key);
    IF v_cached_result IS NOT NULL THEN
      v_cached_data := v_cached_result::JSONB;
      RETURN v_cached_data || jsonb_build_object('cache_hit', true);
    END IF;
  EXCEPTION WHEN OTHERS THEN NULL;
  END;

  SELECT COALESCE(ui_config->>'earn_channel_page_icon', v_default_icon)
  INTO v_page_icon
  FROM merchant_display_settings
  WHERE merchant_id = v_merchant_id;

  v_page_icon := COALESCE(v_page_icon, v_default_icon);

  SELECT jsonb_agg(
    jsonb_build_object(
      'id',                    c.id,
      'channel_code',          c.channel_code,
      'channel_type',          c.channel_type,
      'earn_method',           c.method_type,
      'channel_name',          c.channel_name,
      'headline',              c.headline,
      'description',           c.description,
      'howto_description',     c.howto_description,
      'banner_urls',           c.banner_urls,
      'icon_url', COALESCE(
        c.icon_url,
        (
          SELECT r.default_icon_url
          FROM public.earn_channel_registry r
          WHERE r.channel_code = c.channel_code
            AND COALESCE(r.is_active, true) = true
          LIMIT 1
        )
      ),
      'display_order',         c.display_order,
      'default_award_scope',  c.default_award_scope,
      'config',               COALESCE(c.config, '{}'::jsonb),
      'seller_reference',     COALESCE(c.config->'seller_reference', jsonb_build_object('enabled', false, 'required', false)),
      'receipt_selection',    COALESCE(c.config->'receipt_selection', jsonb_build_object('mode', 'none')),
      'receipt_number',      COALESCE(c.config->'receipt_number', jsonb_build_object('enabled', false, 'required', false)),
      'purchase_date',       COALESCE(c.config->'purchase_date', jsonb_build_object('enabled', false, 'required', false)),
      'button_show',           COALESCE((c.button_action->>'show')::boolean, false),
      'button_label',          c.button_action->>'label',
      'button_config_mode',    c.config->>'mode',
      'button_config_value',   c.config->>'value',
      'howto_banners',         c.howto_banners,
      'stores_banner',         c.stores_banner,
      'marketplace_platforms', c.marketplace_platforms
    )
    ORDER BY c.display_order ASC, c.channel_name ASC, c.channel_code ASC
  )
  INTO v_channels
  FROM public.fn_get_effective_earn_channels(v_merchant_id, v_language, false) c
  WHERE c.active = true
    AND (
      -- Backward compatible: no surface (or unknown surface) => no filtering
      v_surface IS DISTINCT FROM 'shopify'
      OR (
        -- Shopify surface: drop all campaign channels and every
        -- purchase channel except the Shopify channel itself.
        c.channel_type <> 'campaign'
        AND NOT (c.channel_type = 'purchase' AND c.channel_code <> 'shopify_store')
      )
    );

  BEGIN
    PERFORM extensions.earn_channels_cache_set(
      v_cache_key,
      jsonb_build_object(
        'page_icon', v_page_icon,
        'channels',  COALESCE(v_channels, '[]'::jsonb),
        'language',  v_language
      )::TEXT,
      'EX',
      300
    );
  EXCEPTION WHEN OTHERS THEN NULL;
  END;

  RETURN jsonb_build_object(
    'page_icon',  v_page_icon,
    'channels',   COALESCE(v_channels, '[]'::jsonb),
    'language',   v_language,
    'cache_hit',  false
  );
END;
$function$;

