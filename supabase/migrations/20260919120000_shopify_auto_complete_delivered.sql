-- Shopify: delivered_at anchor, complete+claim primitive, auto-complete batch, config

ALTER TABLE public.order_ledger_mkp
  ADD COLUMN IF NOT EXISTS delivered_at timestamptz;

ALTER TABLE public.merchant_master
  ADD COLUMN IF NOT EXISTS marketplace_auto_complete_after_days jsonb;

COMMENT ON COLUMN public.order_ledger_mkp.delivered_at IS
  'First time Shopify mkp order reached delivered (for auto-complete countdown).';
COMMENT ON COLUMN public.merchant_master.marketplace_auto_complete_after_days IS
  'Per-platform days after delivered to auto-complete (e.g. {"shopify": 7}). Null/off = disabled.';

CREATE OR REPLACE FUNCTION public.fn_shopify_complete_order_for_loyalty(
  p_merchant_id uuid,
  p_order_sn text,
  p_user_id uuid,
  p_notes text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_order record;
  v_claim jsonb;
  v_status text;
BEGIN
  IF p_merchant_id IS NULL OR p_user_id IS NULL OR NULLIF(btrim(p_order_sn), '') IS NULL THEN
    RETURN jsonb_build_object('success', false, 'code', 'INVALID_INPUT');
  END IF;

  SELECT * INTO v_order
  FROM order_ledger_mkp
  WHERE merchant_id = p_merchant_id
    AND platform = 'shopify'
    AND order_sn = btrim(p_order_sn);

  IF v_order IS NULL THEN
    RETURN jsonb_build_object('success', false, 'code', 'ORDER_NOT_FOUND');
  END IF;

  v_status := lower(btrim(COALESCE(v_order.order_status, '')));
  IF v_status IN ('cancelled', 'refunded', 'voided') THEN
    RETURN jsonb_build_object('success', false, 'code', 'ORDER_TERMINAL', 'data', jsonb_build_object('order_status', v_order.order_status));
  END IF;

  IF v_status <> 'completed' THEN
    UPDATE order_ledger_mkp
    SET order_status = 'completed', updated_at = now()
    WHERE id = v_order.id;
  END IF;

  SELECT public.fn_claim_marketplace_order_service(
    p_merchant_id,
    'shopify',
    btrim(p_order_sn),
    p_user_id,
    true,
    COALESCE(p_notes, 'Shopify order completed for loyalty')
  ) INTO v_claim;

  RETURN jsonb_build_object(
    'success', true,
    'code', 'COMPLETED',
    'claim', v_claim,
    'shop_id', v_order.shop_id,
    'order_sn', v_order.order_sn
  );
END;
$function$;

REVOKE ALL ON FUNCTION public.fn_shopify_complete_order_for_loyalty(uuid, text, uuid, text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.fn_shopify_complete_order_for_loyalty(uuid, text, uuid, text) TO authenticated, service_role;

CREATE OR REPLACE FUNCTION public.bff_shopify_member_order_received(p_order_sn text)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_merchant_id uuid;
  v_user_id uuid;
  v_user_email text;
  v_ext_shopify text;
  v_order record;
  v_result jsonb;
BEGIN
  v_merchant_id := get_current_merchant_id();
  IF v_merchant_id IS NULL THEN
    RETURN jsonb_build_object('success', false, 'code', 'NO_MERCHANT_CONTEXT');
  END IF;

  SELECT ua.id, lower(btrim(ua.email)), nullif(btrim(ua.marketplace_external_ids->>'shopify'), '')
  INTO v_user_id, v_user_email, v_ext_shopify
  FROM user_accounts ua
  WHERE ua.auth_user_id = auth.uid() AND ua.merchant_id = v_merchant_id;

  IF v_user_id IS NULL THEN
    RETURN jsonb_build_object('success', false, 'code', 'USER_NOT_FOUND');
  END IF;

  SELECT * INTO v_order
  FROM order_ledger_mkp
  WHERE merchant_id = v_merchant_id
    AND platform = 'shopify'
    AND order_sn = btrim(p_order_sn);

  IF v_order IS NULL THEN
    RETURN jsonb_build_object('success', false, 'code', 'ORDER_NOT_FOUND');
  END IF;

  IF NOT (
    (v_user_email IS NOT NULL AND v_order.buyer_email IS NOT NULL AND v_user_email = lower(btrim(v_order.buyer_email)))
    OR (v_ext_shopify IS NOT NULL AND v_order.external_user_id IS NOT NULL AND v_ext_shopify = btrim(v_order.external_user_id))
  ) THEN
    RETURN jsonb_build_object('success', false, 'code', 'ORDER_NOT_OWNED');
  END IF;

  SELECT public.fn_shopify_complete_order_for_loyalty(
    v_merchant_id,
    btrim(p_order_sn),
    v_user_id,
    'Member confirmed receipt (storefront)'
  ) INTO v_result;

  RETURN jsonb_build_object('success', true, 'code', 'MEMBER_RECEIVED', 'result', v_result);
END;
$function$;

CREATE OR REPLACE FUNCTION public.fn_shopify_auto_complete_delivered_orders(p_limit integer DEFAULT 100)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_row record;
  v_user_id uuid;
  v_days int;
  v_result jsonb;
  v_processed jsonb := '[]'::jsonb;
  v_skipped jsonb := '[]'::jsonb;
  v_count int := 0;
BEGIN
  IF p_limit IS NULL OR p_limit < 1 THEN
    p_limit := 100;
  END IF;
  IF p_limit > 500 THEN
    p_limit := 500;
  END IF;

  FOR v_row IN
    SELECT o.id, o.merchant_id, o.order_sn, o.shop_id, o.buyer_email, o.buyer_phone, o.external_user_id,
           COALESCE((m.marketplace_auto_complete_after_days->>'shopify')::int, 0) AS auto_days
    FROM order_ledger_mkp o
    JOIN merchant_master m ON m.id = o.merchant_id
    WHERE o.platform = 'shopify'
      AND o.order_status = 'delivered'
      AND COALESCE(o.synced_to_transaction, false) = false
      AND o.delivered_at IS NOT NULL
      AND COALESCE(m.marketplace_claim_from_status->>'shopify', 'paid') = 'completed'
      AND COALESCE((m.marketplace_auto_complete_after_days->>'shopify')::int, 0) > 0
      AND o.delivered_at + (COALESCE((m.marketplace_auto_complete_after_days->>'shopify')::int, 0) || ' days')::interval <= now()
    ORDER BY o.delivered_at ASC
    LIMIT p_limit
  LOOP
    v_count := v_count + 1;
    v_user_id := public.fn_match_marketplace_user(
      v_row.merchant_id,
      'shopify',
      v_row.external_user_id,
      v_row.buyer_email,
      v_row.buyer_phone
    );

    IF v_user_id IS NULL THEN
      v_skipped := v_skipped || jsonb_build_array(jsonb_build_object(
        'order_sn', v_row.order_sn,
        'merchant_id', v_row.merchant_id,
        'reason', 'NO_MATCHED_USER'
      ));
      CONTINUE;
    END IF;

    SELECT public.fn_shopify_complete_order_for_loyalty(
      v_row.merchant_id,
      v_row.order_sn,
      v_user_id,
      format('Auto-completed after %s days (delivered %s)', v_row.auto_days, v_row.id)
    ) INTO v_result;

    IF COALESCE((v_result->>'success')::boolean, false) THEN
      v_processed := v_processed || jsonb_build_array(jsonb_build_object(
        'merchant_id', v_row.merchant_id,
        'order_sn', v_row.order_sn,
        'shop_id', v_row.shop_id,
        'user_id', v_user_id,
        'claim', v_result->'claim'
      ));
    ELSE
      v_skipped := v_skipped || jsonb_build_array(jsonb_build_object(
        'order_sn', v_row.order_sn,
        'merchant_id', v_row.merchant_id,
        'reason', COALESCE(v_result->>'code', 'FAILED'),
        'detail', v_result
      ));
    END IF;
  END LOOP;

  RETURN jsonb_build_object(
    'success', true,
    'scanned', v_count,
    'processed', v_processed,
    'skipped', v_skipped
  );
END;
$function$;

REVOKE ALL ON FUNCTION public.fn_shopify_auto_complete_delivered_orders(integer) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.fn_shopify_auto_complete_delivered_orders(integer) TO service_role;

CREATE OR REPLACE FUNCTION public.bff_get_general_config()
RETURNS jsonb
LANGUAGE plpgsql
STABLE SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_merchant_id UUID;
  v_config JSONB;
  v_languages JSONB;
BEGIN
  v_merchant_id := get_current_merchant_id();

  IF v_merchant_id IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'No merchant context');
  END IF;

  SELECT jsonb_build_object(
    'auth_methods', auth_methods,
    'attain_persona', attain_persona,
    'marketplace_claim_from_status', marketplace_claim_from_status,
    'marketplace_auto_complete_after_days', marketplace_auto_complete_after_days
  )
  INTO v_config
  FROM merchant_master
  WHERE id = v_merchant_id;

  SELECT COALESCE(jsonb_agg(
    jsonb_build_object(
      'language_code', ml.language_code,
      'language_name', ml.language_name,
      'is_default', ml.is_default
    ) ORDER BY ml.display_order
  ), '[]'::jsonb)
  INTO v_languages
  FROM merchant_languages ml
  WHERE ml.merchant_id = v_merchant_id
    AND ml.is_active = true;

  v_config := v_config || jsonb_build_object('languages', v_languages);

  RETURN jsonb_build_object('success', true, 'data', v_config);
END;
$function$;

CREATE OR REPLACE FUNCTION public.bff_upsert_general_config(p_data jsonb, p_language text DEFAULT 'en'::text)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_lang text;
  v_merchant_id UUID;
BEGIN
  v_lang := fn_normalize_ui_language(p_language);
  v_merchant_id := get_current_merchant_id();

  IF v_merchant_id IS NULL THEN
    RETURN jsonb_build_object('success', false, 'code', 'NO_MERCHANT_CONTEXT', 'title', fn_admin_envelope_message('no_merchant_title', v_lang), 'description', null, 'data', null);
  END IF;

  IF NOT check_admin_permission('global_setting', 'update') THEN
    RETURN jsonb_build_object('success', false, 'code', 'PERMISSION_DENIED', 'title', fn_admin_envelope_message('permission_denied_title_cap', v_lang), 'description', null, 'data', null);
  END IF;

  UPDATE merchant_master
  SET
    auth_methods = COALESCE(
      CASE
        WHEN p_data->'auth_methods' IS NOT NULL
        THEN ARRAY(SELECT jsonb_array_elements_text(p_data->'auth_methods'))
        ELSE auth_methods
      END,
      auth_methods
    ),
    attain_persona = COALESCE(p_data->>'attain_persona', attain_persona),
    marketplace_claim_from_status = CASE
      WHEN p_data->'marketplace_claim_from_status' IS NOT NULL
      THEN COALESCE(marketplace_claim_from_status, '{}'::jsonb) || (p_data->'marketplace_claim_from_status')
      ELSE marketplace_claim_from_status
    END,
    marketplace_auto_complete_after_days = CASE
      WHEN p_data->'marketplace_auto_complete_after_days' IS NOT NULL
      THEN COALESCE(marketplace_auto_complete_after_days, '{}'::jsonb) || (p_data->'marketplace_auto_complete_after_days')
      ELSE marketplace_auto_complete_after_days
    END
  WHERE id = v_merchant_id;

  RETURN jsonb_build_object(
    'success', true,
    'code', 'CONFIG_UPDATED',
    'title', 'General Settings Updated',
    'description', 'General configuration has been saved',
    'data', null
  );
END;
$function$;

CREATE OR REPLACE FUNCTION public.upsert_marketplace_order(p_order jsonb)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE v_existing_id uuid; v_order_id uuid; v_action text; v_items_inserted int:=0; v_order_sn text; v_codes text[]; v_attr jsonb; v_synced boolean:=false;
  v_incoming_status text;
  v_existing_status text;
  v_existing_delivered_at timestamptz;
  v_delivered_at timestamptz;
BEGIN
 v_order_sn:=p_order->>'order_sn';
 IF p_order?'discount_codes' AND jsonb_typeof(p_order->'discount_codes')='array' THEN SELECT COALESCE(array_agg(x),'{}'::text[]) INTO v_codes FROM jsonb_array_elements_text(p_order->'discount_codes') x WHERE NULLIF(btrim(x),'') IS NOT NULL; ELSE v_codes:='{}'::text[]; END IF;
 SELECT id,COALESCE(synced_to_transaction,false), order_status, delivered_at INTO v_existing_id,v_synced,v_existing_status,v_existing_delivered_at FROM order_ledger_mkp WHERE order_sn=v_order_sn AND platform=p_order->>'platform';
 v_synced:=COALESCE(v_synced,false);
 v_incoming_status := p_order->>'order_status';
 v_delivered_at := v_existing_delivered_at;
 IF p_order->>'platform' = 'shopify'
    AND public.fn_shopify_mkp_status_rank(v_incoming_status) >= public.fn_shopify_mkp_status_rank('delivered')
    AND v_delivered_at IS NULL THEN
   v_delivered_at := COALESCE(NULLIF(p_order->>'delivered_at','')::timestamptz, now());
 END IF;
 IF v_existing_id IS NOT NULL THEN
  IF p_order->>'platform' = 'shopify' THEN
    IF lower(btrim(COALESCE(v_incoming_status,''))) IN ('cancelled','refunded','voided') THEN
      v_incoming_status := lower(btrim(v_incoming_status));
    ELSIF public.fn_shopify_mkp_status_rank(v_incoming_status) <= public.fn_shopify_mkp_status_rank(v_existing_status) THEN
      v_incoming_status := v_existing_status;
    END IF;
    IF public.fn_shopify_mkp_status_rank(v_incoming_status) >= public.fn_shopify_mkp_status_rank('delivered')
       AND v_delivered_at IS NULL THEN
      v_delivered_at := COALESCE(NULLIF(p_order->>'delivered_at','')::timestamptz, now());
    END IF;
  END IF;
  UPDATE order_ledger_mkp SET order_status=v_incoming_status,update_time=(p_order->>'update_time')::timestamptz,payment_status=p_order->>'payment_status',buyer_phone=COALESCE(p_order->>'buyer_phone',buyer_phone),buyer_email=COALESCE(p_order->>'buyer_email',buyer_email),total_amount=CASE WHEN NOT v_synced THEN COALESCE((p_order->>'total_amount')::numeric,total_amount) ELSE total_amount END,shipping_fee=CASE WHEN NOT v_synced THEN COALESCE((p_order->>'shipping_fee')::numeric,shipping_fee) ELSE shipping_fee END,discount_amount=CASE WHEN NOT v_synced THEN COALESCE((p_order->>'discount_amount')::numeric,discount_amount) ELSE discount_amount END,tax_amount=CASE WHEN NOT v_synced THEN COALESCE((p_order->>'tax_amount')::numeric,tax_amount) ELSE tax_amount END,final_amount=CASE WHEN NOT v_synced THEN COALESCE((p_order->>'final_amount')::numeric,final_amount) ELSE final_amount END,earnable_amount=CASE WHEN NOT v_synced THEN COALESCE((p_order->>'earnable_amount')::numeric,earnable_amount) ELSE earnable_amount END,financial_details=CASE WHEN NOT v_synced THEN COALESCE(p_order->'financial_details',financial_details) ELSE financial_details END,payment_method=CASE WHEN NOT v_synced THEN COALESCE(p_order->>'payment_method',payment_method) ELSE payment_method END,discount_codes=CASE WHEN v_codes<>'{}'::text[] THEN v_codes ELSE discount_codes END,delivered_at=COALESCE(delivered_at,v_delivered_at),updated_at=now() WHERE id=v_existing_id;
  v_order_id:=v_existing_id; v_action:='updated';
 ELSE
  INSERT INTO order_ledger_mkp(merchant_id,platform,shop_id,order_sn,external_user_id,buyer_username,buyer_phone,buyer_email,order_status,transaction_date,update_time,currency,total_amount,shipping_fee,discount_amount,tax_amount,final_amount,earnable_amount,financial_details,payment_method,payment_status,status,discount_codes,delivered_at)
  VALUES((p_order->>'merchant_id')::uuid,p_order->>'platform',p_order->>'shop_id',v_order_sn,p_order->>'external_user_id',p_order->>'buyer_username',p_order->>'buyer_phone',p_order->>'buyer_email',v_incoming_status,(p_order->>'transaction_date')::timestamptz,(p_order->>'update_time')::timestamptz,COALESCE(p_order->>'currency','THB'),(p_order->>'total_amount')::numeric,COALESCE((p_order->>'shipping_fee')::numeric,0),COALESCE((p_order->>'discount_amount')::numeric,0),COALESCE((p_order->>'tax_amount')::numeric,0),(p_order->>'final_amount')::numeric,(p_order->>'earnable_amount')::numeric,COALESCE(p_order->'financial_details','{}'::jsonb),p_order->>'payment_method',p_order->>'payment_status',public.map_marketplace_status(p_order->>'platform', v_incoming_status),COALESCE(v_codes,'{}'::text[]),CASE WHEN p_order->>'platform'='shopify' THEN v_delivered_at ELSE NULL END) RETURNING id INTO v_order_id;
  v_action:='inserted';
 END IF;
 IF p_order?'items' AND jsonb_typeof(p_order->'items')='array' AND jsonb_array_length(p_order->'items')>0 THEN
  INSERT INTO order_items_ledger_mkp(order_id,merchant_id,platform,order_sn,platform_item_id,variant_id,platform_sku,variant_sku,item_name,variant_name,quantity,currency,unit_price,discount_amount,line_total,earnable_amount,financial_details)
  SELECT v_order_id,(p_order->>'merchant_id')::uuid,p_order->>'platform',v_order_sn,item->>'platform_item_id',item->>'variant_id',item->>'platform_sku',item->>'variant_sku',item->>'item_name',item->>'variant_name',(item->>'quantity')::numeric,COALESCE(item->>'currency','THB'),(item->>'unit_price')::numeric,COALESCE((item->>'discount_amount')::numeric,0),(item->>'line_total')::numeric,(item->>'earnable_amount')::numeric,COALESCE(item->'financial_details','{}'::jsonb)
  FROM (
    SELECT DISTINCT ON (item->>'platform_item_id') item
    FROM jsonb_array_elements(p_order->'items') WITH ORDINALITY AS t(item, ord)
    ORDER BY item->>'platform_item_id', ord DESC
  ) deduped
  ON CONFLICT(platform,platform_item_id,order_id) DO UPDATE SET quantity=EXCLUDED.quantity,unit_price=EXCLUDED.unit_price,discount_amount=EXCLUDED.discount_amount,line_total=EXCLUDED.line_total,earnable_amount=EXCLUDED.earnable_amount,financial_details=EXCLUDED.financial_details
  WHERE NOT v_synced;
  GET DIAGNOSTICS v_items_inserted=ROW_COUNT;
 END IF;
 BEGIN v_attr:=public.fn_attribute_referral(p_kind:='purchase',p_merchant_id:=(p_order->>'merchant_id')::uuid,p_platform:=p_order->>'platform',p_order_key:=v_order_sn,p_order_status:=v_incoming_status,p_payment_status:=p_order->>'payment_status',p_buyer_email:=p_order->>'buyer_email',p_buyer_phone:=p_order->>'buyer_phone',p_buyer_external_id:=p_order->>'external_user_id',p_codes:=COALESCE(v_codes,'{}'::text[]),p_buyer_orders_count:=NULLIF(p_order->>'buyer_orders_count','')::integer); EXCEPTION WHEN OTHERS THEN v_attr:=jsonb_build_object('success',false,'error',SQLERRM); END;
 RETURN jsonb_build_object('success',true,'code',CASE WHEN v_action='inserted' THEN 'CREATED' ELSE 'UPDATED' END,'title',CASE WHEN v_action='inserted' THEN 'Order Created' ELSE 'Order Updated' END,'description',format('Order %s %s with %s items',v_order_sn,v_action,v_items_inserted),'action',v_action,'order_id',v_order_id,'order_sn',v_order_sn,'items_count',v_items_inserted,'referral',v_attr);
END;
$function$;
