-- Shopify mkp order_status ladder: paid → fulfilled → delivered → completed
-- Claim thresholds, monotonic upsert, member receipt → claim

CREATE OR REPLACE FUNCTION public.fn_shopify_mkp_status_rank(p_status text)
RETURNS integer
LANGUAGE sql
IMMUTABLE
AS $$
  SELECT CASE lower(btrim(COALESCE(p_status, '')))
    WHEN 'voided' THEN 1
    WHEN 'cancelled' THEN 1
    WHEN 'refunded' THEN 1
    WHEN 'pending' THEN 10
    WHEN 'authorized' THEN 20
    WHEN 'partially_paid' THEN 30
    WHEN 'paid' THEN 40
    WHEN 'partially_refunded' THEN 45
    WHEN 'fulfilled' THEN 50
    WHEN 'delivered' THEN 60
    WHEN 'completed' THEN 70
    ELSE 0
  END;
$$;

CREATE OR REPLACE FUNCTION public.map_marketplace_status(p_platform text, p_order_status text)
RETURNS text
LANGUAGE plpgsql
IMMUTABLE
AS $function$
BEGIN
  RETURN CASE p_platform
    WHEN 'shopee' THEN
      CASE p_order_status
        WHEN 'UNPAID' THEN 'pending'
        WHEN 'READY_TO_SHIP' THEN 'completed'
        WHEN 'SHIPPED' THEN 'completed'
        WHEN 'TO_CONFIRM_RECEIVE' THEN 'completed'
        WHEN 'COMPLETED' THEN 'completed'
        WHEN 'CANCELLED' THEN 'cancelled'
        WHEN 'IN_CANCEL' THEN 'cancelled'
        WHEN 'TO_RETURN' THEN 'refunded'
        ELSE 'pending'
      END
    WHEN 'lazada' THEN
      CASE p_order_status
        WHEN 'pending' THEN 'pending'
        WHEN 'unpaid' THEN 'pending'
        WHEN 'ready_to_ship' THEN 'completed'
        WHEN 'shipped' THEN 'completed'
        WHEN 'delivered' THEN 'completed'
        WHEN 'canceled' THEN 'cancelled'
        WHEN 'returned' THEN 'refunded'
        ELSE 'pending'
      END
    WHEN 'tiktok' THEN
      CASE p_order_status
        WHEN 'UNPAID' THEN 'pending'
        WHEN 'AWAITING_SHIPMENT' THEN 'completed'
        WHEN 'SHIPPED' THEN 'completed'
        WHEN 'DELIVERED' THEN 'completed'
        WHEN 'COMPLETED' THEN 'completed'
        WHEN 'CANCELLED' THEN 'cancelled'
        WHEN 'RETURNED' THEN 'refunded'
        ELSE 'pending'
      END
    WHEN 'shopify' THEN
      CASE lower(btrim(COALESCE(p_order_status, '')))
        WHEN 'pending' THEN 'pending'
        WHEN 'authorized' THEN 'pending'
        WHEN 'partially_paid' THEN 'pending'
        WHEN 'paid' THEN 'completed'
        WHEN 'fulfilled' THEN 'completed'
        WHEN 'delivered' THEN 'completed'
        WHEN 'completed' THEN 'completed'
        WHEN 'partially_refunded' THEN 'completed'
        WHEN 'refunded' THEN 'refunded'
        WHEN 'voided' THEN 'cancelled'
        WHEN 'cancelled' THEN 'cancelled'
        ELSE 'pending'
      END
    ELSE 'pending'
  END;
END;
$function$;

CREATE OR REPLACE FUNCTION public.get_claimable_statuses(p_platform text, p_from_status text)
RETURNS text[]
LANGUAGE sql
IMMUTABLE
AS $function$
  WITH sequences AS (
    SELECT CASE p_platform
      WHEN 'tiktok' THEN ARRAY['UNPAID','ON_HOLD','AWAITING_SHIPMENT','AWAITING_COLLECTION','IN_TRANSIT','DELIVERED','COMPLETED']
      WHEN 'shopee' THEN ARRAY['UNPAID','READY_TO_SHIP','PROCESSED','SHIPPED','COMPLETED']
      WHEN 'lazada' THEN ARRAY['unpaid','pending','confirmed','packed','ready_to_ship','shipped','delivered']
      WHEN 'shopify' THEN ARRAY['pending','authorized','partially_paid','paid','partially_refunded','fulfilled','delivered','completed']
      ELSE ARRAY[]::TEXT[]
    END AS seq
  )
  SELECT COALESCE(seq[array_position(seq, p_from_status):], seq)
  FROM sequences;
$function$;

CREATE OR REPLACE FUNCTION public.get_platform_order_statuses(p_platform text DEFAULT NULL::text)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
BEGIN
  RETURN (
    SELECT jsonb_agg(
      jsonb_build_object(
        'platform', plat,
        'statuses', statuses
      )
    )
    FROM (
      SELECT s.plat, jsonb_agg(
        jsonb_build_object(
          'value', s.val,
          'label', s.label
        ) ORDER BY s.ord
      ) AS statuses
      FROM (
        VALUES
          ('tiktok', 'UNPAID',                'Unpaid',              1),
          ('tiktok', 'ON_HOLD',               'On Hold',             2),
          ('tiktok', 'AWAITING_SHIPMENT',     'Awaiting Shipment',   3),
          ('tiktok', 'AWAITING_COLLECTION',   'Awaiting Collection', 4),
          ('tiktok', 'IN_TRANSIT',            'In Transit',          5),
          ('tiktok', 'DELIVERED',             'Delivered',           6),
          ('tiktok', 'COMPLETED',             'Completed',           7),
          ('shopee', 'UNPAID',                'Unpaid',              1),
          ('shopee', 'READY_TO_SHIP',         'Ready to Ship',       2),
          ('shopee', 'PROCESSED',             'Processed',           3),
          ('shopee', 'SHIPPED',               'Shipped',             4),
          ('shopee', 'COMPLETED',             'Completed',           5),
          ('lazada', 'pending',               'Pending',             1),
          ('lazada', 'ready_to_ship',         'Ready to Ship',       2),
          ('lazada', 'shipped',               'Shipped',             3),
          ('lazada', 'delivered',             'Delivered',           4),
          ('shopify', 'paid',                 'Paid',                1),
          ('shopify', 'fulfilled',             'Fulfilled',           2),
          ('shopify', 'delivered',             'Delivered',           3),
          ('shopify', 'completed',            'Completed',           4)
      ) AS s(plat, val, label, ord)
      WHERE (p_platform IS NULL OR s.plat = p_platform)
      GROUP BY s.plat
    ) grouped
  );
END;
$function$;

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
  v_claim jsonb;
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

  UPDATE order_ledger_mkp
  SET order_status = 'completed', updated_at = now()
  WHERE id = v_order.id;

  SELECT public.fn_claim_marketplace_order_service(
    v_merchant_id,
    'shopify',
    btrim(p_order_sn),
    v_user_id,
    true,
    'Member confirmed receipt (storefront)'
  ) INTO v_claim;

  RETURN jsonb_build_object('success', true, 'code', 'MEMBER_RECEIVED', 'claim', v_claim);
END;
$function$;

GRANT EXECUTE ON FUNCTION public.bff_shopify_member_order_received(text) TO authenticated;

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

-- Monotonic order_status for Shopify on upsert (avoid webhook downgrades)
CREATE OR REPLACE FUNCTION public.upsert_marketplace_order(p_order jsonb)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE v_existing_id uuid; v_order_id uuid; v_action text; v_items_inserted int:=0; v_order_sn text; v_codes text[]; v_attr jsonb; v_synced boolean:=false;
  v_incoming_status text;
  v_existing_status text;
BEGIN
 v_order_sn:=p_order->>'order_sn';
 IF p_order?'discount_codes' AND jsonb_typeof(p_order->'discount_codes')='array' THEN SELECT COALESCE(array_agg(x),'{}'::text[]) INTO v_codes FROM jsonb_array_elements_text(p_order->'discount_codes') x WHERE NULLIF(btrim(x),'') IS NOT NULL; ELSE v_codes:='{}'::text[]; END IF;
 SELECT id,COALESCE(synced_to_transaction,false), order_status INTO v_existing_id,v_synced,v_existing_status FROM order_ledger_mkp WHERE order_sn=v_order_sn AND platform=p_order->>'platform';
 v_synced:=COALESCE(v_synced,false);
 v_incoming_status := p_order->>'order_status';
 IF v_existing_id IS NOT NULL THEN
  IF p_order->>'platform' = 'shopify' THEN
    IF lower(btrim(COALESCE(v_incoming_status,''))) IN ('cancelled','refunded','voided') THEN
      v_incoming_status := lower(btrim(v_incoming_status));
    ELSIF public.fn_shopify_mkp_status_rank(v_incoming_status) <= public.fn_shopify_mkp_status_rank(v_existing_status) THEN
      v_incoming_status := v_existing_status;
    END IF;
  END IF;
  UPDATE order_ledger_mkp SET order_status=v_incoming_status,update_time=(p_order->>'update_time')::timestamptz,payment_status=p_order->>'payment_status',buyer_phone=COALESCE(p_order->>'buyer_phone',buyer_phone),buyer_email=COALESCE(p_order->>'buyer_email',buyer_email),total_amount=CASE WHEN NOT v_synced THEN COALESCE((p_order->>'total_amount')::numeric,total_amount) ELSE total_amount END,shipping_fee=CASE WHEN NOT v_synced THEN COALESCE((p_order->>'shipping_fee')::numeric,shipping_fee) ELSE shipping_fee END,discount_amount=CASE WHEN NOT v_synced THEN COALESCE((p_order->>'discount_amount')::numeric,discount_amount) ELSE discount_amount END,tax_amount=CASE WHEN NOT v_synced THEN COALESCE((p_order->>'tax_amount')::numeric,tax_amount) ELSE tax_amount END,final_amount=CASE WHEN NOT v_synced THEN COALESCE((p_order->>'final_amount')::numeric,final_amount) ELSE final_amount END,earnable_amount=CASE WHEN NOT v_synced THEN COALESCE((p_order->>'earnable_amount')::numeric,earnable_amount) ELSE earnable_amount END,financial_details=CASE WHEN NOT v_synced THEN COALESCE(p_order->'financial_details',financial_details) ELSE financial_details END,payment_method=CASE WHEN NOT v_synced THEN COALESCE(p_order->>'payment_method',payment_method) ELSE payment_method END,discount_codes=CASE WHEN v_codes<>'{}'::text[] THEN v_codes ELSE discount_codes END,updated_at=now() WHERE id=v_existing_id;
  v_order_id:=v_existing_id; v_action:='updated';
 ELSE
  INSERT INTO order_ledger_mkp(merchant_id,platform,shop_id,order_sn,external_user_id,buyer_username,buyer_phone,buyer_email,order_status,transaction_date,update_time,currency,total_amount,shipping_fee,discount_amount,tax_amount,final_amount,earnable_amount,financial_details,payment_method,payment_status,status,discount_codes)
  VALUES((p_order->>'merchant_id')::uuid,p_order->>'platform',p_order->>'shop_id',v_order_sn,p_order->>'external_user_id',p_order->>'buyer_username',p_order->>'buyer_phone',p_order->>'buyer_email',v_incoming_status,(p_order->>'transaction_date')::timestamptz,(p_order->>'update_time')::timestamptz,COALESCE(p_order->>'currency','THB'),(p_order->>'total_amount')::numeric,COALESCE((p_order->>'shipping_fee')::numeric,0),COALESCE((p_order->>'discount_amount')::numeric,0),COALESCE((p_order->>'tax_amount')::numeric,0),(p_order->>'final_amount')::numeric,(p_order->>'earnable_amount')::numeric,COALESCE(p_order->'financial_details','{}'::jsonb),p_order->>'payment_method',p_order->>'payment_status',public.map_marketplace_status(p_order->>'platform', v_incoming_status),COALESCE(v_codes,'{}'::text[])) RETURNING id INTO v_order_id;
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
