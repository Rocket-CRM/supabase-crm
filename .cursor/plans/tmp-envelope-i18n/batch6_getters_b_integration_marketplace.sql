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
