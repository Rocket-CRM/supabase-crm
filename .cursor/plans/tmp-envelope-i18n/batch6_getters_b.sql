-- getters batch B: wrapper keys + integration, marketplace, form, consent, upload

-- Scope C getters B: extend wrapper with marketplace/form/upload keys (preserve live keys)
CREATE OR REPLACE FUNCTION public.fn_admin_envelope_message(p_key text, p_language text DEFAULT 'en'::text, p_params text[] DEFAULT NULL::text[])
 RETURNS text
 LANGUAGE plpgsql
 IMMUTABLE
 SET search_path TO 'public'
AS $function$
DECLARE
  v_lang text := public.fn_normalize_ui_language(p_language);
  v_p1 text := COALESCE(p_params[1], '');
  v_p2 text := COALESCE(p_params[2], '');
  v_hit text;
BEGIN
  v_hit := CASE p_key
    -- preserve existing live wrapper keys
    WHEN 'activity_not_found_title' THEN CASE v_lang WHEN 'th' THEN 'ไม่พบกิจกรรม' ELSE 'Activity not found' END
    WHEN 'activity_created_title' THEN CASE v_lang WHEN 'th' THEN 'สร้างกิจกรรมแล้ว' ELSE 'Activity created' END
    WHEN 'activity_updated_title' THEN CASE v_lang WHEN 'th' THEN 'อัปเดตกิจกรรมแล้ว' ELSE 'Activity updated' END
    WHEN 'matrix_updated_title' THEN CASE v_lang WHEN 'th' THEN 'อัปเดตเมทริกซ์สำเร็จ' ELSE 'Matrix updated successfully' END
    WHEN 'tier_program_config_title' THEN CASE v_lang WHEN 'th' THEN 'การตั้งค่าโปรแกรมระดับสมาชิก' ELSE 'Tier Program Config' END
    WHEN 'tier_program_config_desc' THEN CASE v_lang WHEN 'th' THEN 'โหลดการตั้งค่าโปรแกรมระดับสมาชิกแล้ว' ELSE 'Loaded tier program config' END
    WHEN 'event_not_found_title' THEN CASE v_lang WHEN 'th' THEN 'ไม่พบอีเวนต์' ELSE 'Event not found' END
    WHEN 'event_not_found_desc' THEN CASE v_lang WHEN 'th' THEN 'ไม่พบอีเวนต์รหัส: ' || v_p1 ELSE 'No event found with code: ' || v_p1 END
    WHEN 'agent_not_found_desc' THEN CASE v_lang WHEN 'th' THEN 'ไม่พบเอเจนต์หรือไม่มีสิทธิ์เข้าถึง' ELSE 'Agent not found or access denied' END
    WHEN 'agent_not_found_title' THEN CASE v_lang WHEN 'th' THEN 'ไม่พบเอเจนต์' ELSE 'Agent not found' END
    WHEN 'not_authenticated_desc' THEN CASE v_lang WHEN 'th' THEN 'ยังไม่ได้เข้าสู่ระบบ' ELSE 'Not authenticated' END
    WHEN 'wrong_field_type_title' THEN CASE v_lang WHEN 'th' THEN 'ประเภทฟิลด์ไม่ถูกต้อง' ELSE 'Wrong field type' END
    WHEN 'wrong_field_type_external_code_desc' THEN CASE v_lang WHEN 'th' THEN 'พูลต้องเป็น field_type=external_code' ELSE 'Pool must be field_type=external_code' END
    WHEN 'field_not_found_title' THEN CASE v_lang WHEN 'th' THEN 'ไม่พบฟิลด์' ELSE 'Field not found' END
    WHEN 'package_saved_title' THEN CASE v_lang WHEN 'th' THEN 'บันทึกแพ็กเกจแล้ว' ELSE 'Package saved' END
    WHEN 'earn_conditions_saved_title' THEN CASE v_lang WHEN 'th' THEN 'บันทึกเงื่อนไขการสะสมแล้ว' ELSE 'Earn conditions saved' END
    WHEN 'tier_program_saved_title' THEN CASE v_lang WHEN 'th' THEN 'บันทึกการตั้งค่าโปรแกรมระดับสมาชิกแล้ว' ELSE 'Tier program config saved' END

    -- marketplace order
    WHEN 'unable_determine_merchant_identity_desc' THEN CASE v_lang WHEN 'th' THEN 'ไม่สามารถระบุตัวตนร้านค้าได้' ELSE 'Unable to determine merchant identity' END
    WHEN 'order_number_required_title' THEN CASE v_lang WHEN 'th' THEN 'ต้องระบุหมายเลขคำสั่งซื้อ' ELSE 'Order number required' END
    WHEN 'order_number_required_desc' THEN CASE v_lang WHEN 'th' THEN 'กรุณาระบุ order_sn' ELSE 'Please provide an order_sn' END
    WHEN 'platform_required_title' THEN CASE v_lang WHEN 'th' THEN 'ต้องระบุแพลตฟอร์ม' ELSE 'Platform required' END
    WHEN 'platform_required_desc' THEN CASE v_lang WHEN 'th' THEN 'กรุณาเลือกแพลตฟอร์ม (shopee, tiktok, lazada)' ELSE 'Please select a platform (shopee, tiktok, lazada)' END
    WHEN 'order_not_found_title' THEN CASE v_lang WHEN 'th' THEN 'ไม่พบคำสั่งซื้อ' ELSE 'Order not found' END
    WHEN 'order_not_found_desc' THEN CASE v_lang WHEN 'th' THEN 'ไม่พบคำสั่งซื้อ ' || v_p1 || ' รหัส: ' || v_p2 ELSE 'No ' || v_p1 || ' order found with order_sn: ' || v_p2 END
    WHEN 'order_found_title' THEN CASE v_lang WHEN 'th' THEN 'พบคำสั่งซื้อ' ELSE 'Order found' END

    -- form details
    WHEN 'invalid_mode_new_edit_desc' THEN CASE v_lang WHEN 'th' THEN 'โหมดต้องเป็น "new" หรือ "edit"' ELSE 'Mode must be "new" or "edit"' END
    WHEN 'form_not_found_title' THEN CASE v_lang WHEN 'th' THEN 'ไม่พบฟอร์ม' ELSE 'Form not found' END
    WHEN 'form_not_exist_desc' THEN CASE v_lang WHEN 'th' THEN 'ไม่มีฟอร์มที่ร้องขอ' ELSE 'The requested form does not exist' END
    WHEN 'unauthorized_title' THEN CASE v_lang WHEN 'th' THEN 'ไม่มีสิทธิ์' ELSE 'Unauthorized' END
    WHEN 'form_wrong_merchant_desc' THEN CASE v_lang WHEN 'th' THEN 'ฟอร์มนี้เป็นของร้านค้าอื่น' ELSE 'This form belongs to a different merchant' END

    -- signup codes upload
    WHEN 'field_not_found_desc' THEN CASE v_lang WHEN 'th' THEN 'การตั้งค่าฟิลด์ไม่ใช่ของร้านค้านี้' ELSE 'Field config does not belong to this merchant' END
    WHEN 'target_external_code_required_desc' THEN CASE v_lang WHEN 'th' THEN 'ฟิลด์เป้าหมายต้องเป็น field_type=external_code' ELSE 'Target field must be field_type=external_code' END
    WHEN 'invalid_pool_config_title' THEN CASE v_lang WHEN 'th' THEN 'การตั้งค่าพูลไม่ถูกต้อง' ELSE 'Invalid pool config' END
    WHEN 'invalid_store_binding_desc' THEN CASE v_lang WHEN 'th' THEN 'config.external_code.store_binding ต้องเป็น off|optional|required' ELSE 'config.external_code.store_binding must be off|optional|required' END
    WHEN 'no_codes_provided_title' THEN CASE v_lang WHEN 'th' THEN 'ไม่ได้ระบุรหัส' ELSE 'No codes provided' END
    WHEN 'no_codes_provided_desc' THEN CASE v_lang WHEN 'th' THEN 'p_codes ต้องเป็นอาร์เรย์ที่ไม่ว่าง' ELSE 'p_codes must be a non-empty array' END
    WHEN 'store_binding_validation_failed_title' THEN CASE v_lang WHEN 'th' THEN 'การตรวจสอบการผูกสาขาไม่ผ่าน' ELSE 'Store binding validation failed' END
    WHEN 'store_binding_validation_failed_desc' THEN CASE v_lang WHEN 'th' THEN 'ยังไม่ได้อัปโหลดรหัสใด ๆ กรุณาแก้ไขข้อผิดพลาดแล้วลองใหม่' ELSE 'No codes were uploaded. Fix the errors and retry.' END
    WHEN 'codes_uploaded_title' THEN CASE v_lang WHEN 'th' THEN 'อัปโหลดรหัสแล้ว' ELSE 'Codes uploaded' END
    ELSE NULL
  END;
  IF v_hit IS NOT NULL THEN
    RETURN v_hit;
  END IF;
  RETURN public.fn_admin_envelope_message_core(p_key, p_language, p_params);
END;
$function$;

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

CREATE OR REPLACE FUNCTION public.bff_get_marketplace_order(p_order_sn text, p_platform text, p_language text DEFAULT 'en'::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
DECLARE
  v_lang text;
  v_merchant_id UUID;
  v_order RECORD;
  v_items JSONB;
  v_crm RECORD;
  v_shop_name TEXT;
  v_platform_icon_url TEXT;
  v_order_details JSONB;
BEGIN
  v_lang := fn_normalize_ui_language(p_language);
  v_merchant_id := get_current_merchant_id();
  IF v_merchant_id IS NULL THEN
    RETURN jsonb_build_object(
      'success', false,
      'title', fn_admin_envelope_message('merchant_context_required_title', v_lang),
      'description', fn_admin_envelope_message('unable_determine_merchant_identity_desc', v_lang),
      'data', null
    );
  END IF;

  IF p_order_sn IS NULL OR trim(p_order_sn) = '' THEN
    RETURN jsonb_build_object(
      'success', false,
      'title', fn_admin_envelope_message('order_number_required_title', v_lang),
      'description', fn_admin_envelope_message('order_number_required_desc', v_lang),
      'data', null
    );
  END IF;

  IF p_platform IS NULL OR trim(p_platform) = '' THEN
    RETURN jsonb_build_object(
      'success', false,
      'title', fn_admin_envelope_message('platform_required_title', v_lang),
      'description', fn_admin_envelope_message('platform_required_desc', v_lang),
      'data', null
    );
  END IF;

  SELECT
    o.id,
    o.platform,
    o.shop_id,
    o.order_sn,
    o.transaction_number,
    o.external_user_id,
    o.buyer_username,
    o.buyer_phone,
    o.buyer_email,
    o.order_status,
    o.status,
    o.transaction_date,
    o.update_time,
    o.currency,
    o.total_amount,
    o.shipping_fee,
    o.discount_amount,
    o.tax_amount,
    o.final_amount,
    o.payment_method,
    o.payment_status,
    o.synced_to_transaction,
    o.synced_at
  INTO v_order
  FROM order_ledger_mkp o
  WHERE o.merchant_id = v_merchant_id
    AND o.order_sn = trim(p_order_sn)
    AND o.platform = lower(trim(p_platform));

  IF NOT FOUND THEN
    RETURN jsonb_build_object(
      'success', false,
      'title', fn_admin_envelope_message('order_not_found_title', v_lang),
      'description', fn_admin_envelope_message('order_not_found_desc', v_lang, ARRAY[p_platform, p_order_sn]),
      'data', null
    );
  END IF;

  -- Resolve shop name
  SELECT COALESCE(
    mc.credentials->>'shop_name',
    mc.credentials->>'seller_name',
    mc.credentials->>'account',
    v_order.shop_id
  )
  INTO v_shop_name
  FROM merchant_credentials mc
  WHERE mc.external_id = v_order.shop_id
    AND mc.service_name = v_order.platform
    AND mc.merchant_id = v_merchant_id;

  IF v_shop_name IS NULL THEN
    v_shop_name := v_order.shop_id;
  END IF;

  -- Platform icon URL
  v_platform_icon_url := 'https://wkevmsedchftztoolkmi.supabase.co/storage/v1/object/public/default%20images/' || v_order.platform || '%20logo.svg';

  -- Build order_details array for FE label/value binding
  v_order_details := jsonb_build_array(
    jsonb_build_object(
      'label', 'Transaction Date',
      'value', to_char(v_order.transaction_date AT TIME ZONE 'Asia/Bangkok', 'FMMM/DD/YYYY, HH24:MI')
    ),
    jsonb_build_object(
      'label', 'Total Balance',
      'value', COALESCE(v_order.currency, 'THB') || ' ' || to_char(v_order.final_amount, 'FM999,999,999.00')
    ),
    jsonb_build_object(
      'label', 'Order Status',
      'value', v_order.order_status
    )
  );

  -- Get items
  SELECT COALESCE(jsonb_agg(
    jsonb_build_object(
      'id', oi.id,
      'platform_item_id', oi.platform_item_id,
      'platform_sku', oi.platform_sku,
      'variant_id', oi.variant_id,
      'variant_sku', oi.variant_sku,
      'item_name', oi.item_name,
      'variant_name', oi.variant_name,
      'quantity', oi.quantity,
      'currency', oi.currency,
      'unit_price', oi.unit_price,
      'discount_amount', oi.discount_amount,
      'line_total', oi.line_total
    )
  ), '[]'::jsonb)
  INTO v_items
  FROM order_items_ledger_mkp oi
  WHERE oi.order_id = v_order.id;

  -- CRM sync status
  SELECT
    pl.id,
    pl.user_id,
    pl.earn_currency,
    pl.status,
    pl.currency_processed_at,
    pl.currency_error
  INTO v_crm
  FROM purchase_ledger pl
  WHERE pl.transaction_number = ('MKP-' || upper(v_order.platform) || '-' || v_order.order_sn)
    AND pl.merchant_id = v_merchant_id;

  RETURN jsonb_build_object(
    'success', true,
    'title', fn_admin_envelope_message('order_found_title', v_lang),
    'description', null,
    'data', jsonb_build_object(
      'order', jsonb_build_object(
        'id', v_order.id,
        'platform', v_order.platform,
        'platform_icon_url', v_platform_icon_url,
        'shop_id', v_order.shop_id,
        'shop_name', v_shop_name,
        'order_sn', v_order.order_sn,
        'transaction_number', v_order.transaction_number,
        'order_status', v_order.order_status,
        'status', v_order.status,
        'transaction_date', v_order.transaction_date,
        'update_time', v_order.update_time,
        'currency', v_order.currency,
        'total_amount', v_order.total_amount,
        'shipping_fee', v_order.shipping_fee,
        'discount_amount', v_order.discount_amount,
        'tax_amount', v_order.tax_amount,
        'final_amount', v_order.final_amount,
        'payment_method', v_order.payment_method,
        'payment_status', v_order.payment_status,
        'synced_to_transaction', v_order.synced_to_transaction,
        'synced_at', v_order.synced_at
      ),
      'order_details', v_order_details,
      'buyer', jsonb_build_object(
        'external_user_id', v_order.external_user_id,
        'username', v_order.buyer_username,
        'phone', v_order.buyer_phone,
        'email', v_order.buyer_email
      ),
      'items', v_items,
      'items_count', jsonb_array_length(v_items),
      'crm_sync', CASE
        WHEN v_crm.id IS NOT NULL THEN jsonb_build_object(
          'is_synced', true,
          'purchase_id', v_crm.id,
          'user_id', v_crm.user_id,
          'earn_currency', v_crm.earn_currency,
          'crm_status', v_crm.status,
          'currency_processed_at', v_crm.currency_processed_at,
          'currency_error', v_crm.currency_error
        )
        ELSE jsonb_build_object(
          'is_synced', false,
          'purchase_id', null,
          'user_id', null,
          'earn_currency', null,
          'crm_status', null,
          'currency_processed_at', null,
          'currency_error', null
        )
      END
    )
  );
END;
$function$;

DROP FUNCTION IF EXISTS public.bff_get_marketplace_order(text, text);

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
