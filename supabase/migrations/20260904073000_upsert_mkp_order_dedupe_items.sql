-- Dedupe duplicate platform_item_id rows in a single upsert payload (Shopee bundle edge case).
CREATE OR REPLACE FUNCTION public.upsert_marketplace_order(p_order jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE v_existing_id uuid; v_order_id uuid; v_action text; v_items_inserted int:=0; v_order_sn text; v_codes text[]; v_attr jsonb; v_synced boolean:=false;
BEGIN
 v_order_sn:=p_order->>'order_sn';
 IF p_order?'discount_codes' AND jsonb_typeof(p_order->'discount_codes')='array' THEN SELECT COALESCE(array_agg(x),'{}'::text[]) INTO v_codes FROM jsonb_array_elements_text(p_order->'discount_codes') x WHERE NULLIF(btrim(x),'') IS NOT NULL; ELSE v_codes:='{}'::text[]; END IF;
 SELECT id,COALESCE(synced_to_transaction,false) INTO v_existing_id,v_synced FROM order_ledger_mkp WHERE order_sn=v_order_sn AND platform=p_order->>'platform';
 IF v_existing_id IS NOT NULL THEN
  UPDATE order_ledger_mkp SET order_status=p_order->>'order_status',update_time=(p_order->>'update_time')::timestamptz,payment_status=p_order->>'payment_status',buyer_phone=COALESCE(p_order->>'buyer_phone',buyer_phone),buyer_email=COALESCE(p_order->>'buyer_email',buyer_email),total_amount=CASE WHEN NOT v_synced THEN COALESCE((p_order->>'total_amount')::numeric,total_amount) ELSE total_amount END,shipping_fee=CASE WHEN NOT v_synced THEN COALESCE((p_order->>'shipping_fee')::numeric,shipping_fee) ELSE shipping_fee END,discount_amount=CASE WHEN NOT v_synced THEN COALESCE((p_order->>'discount_amount')::numeric,discount_amount) ELSE discount_amount END,tax_amount=CASE WHEN NOT v_synced THEN COALESCE((p_order->>'tax_amount')::numeric,tax_amount) ELSE tax_amount END,final_amount=CASE WHEN NOT v_synced THEN COALESCE((p_order->>'final_amount')::numeric,final_amount) ELSE final_amount END,earnable_amount=CASE WHEN NOT v_synced THEN COALESCE((p_order->>'earnable_amount')::numeric,earnable_amount) ELSE earnable_amount END,financial_details=CASE WHEN NOT v_synced THEN COALESCE(p_order->'financial_details',financial_details) ELSE financial_details END,payment_method=CASE WHEN NOT v_synced THEN COALESCE(p_order->>'payment_method',payment_method) ELSE payment_method END,discount_codes=CASE WHEN v_codes<>'{}'::text[] THEN v_codes ELSE discount_codes END,updated_at=now() WHERE id=v_existing_id;
  v_order_id:=v_existing_id; v_action:='updated';
 ELSE
  INSERT INTO order_ledger_mkp(merchant_id,platform,shop_id,order_sn,external_user_id,buyer_username,buyer_phone,buyer_email,order_status,transaction_date,update_time,currency,total_amount,shipping_fee,discount_amount,tax_amount,final_amount,earnable_amount,financial_details,payment_method,payment_status,status,discount_codes)
  VALUES((p_order->>'merchant_id')::uuid,p_order->>'platform',p_order->>'shop_id',v_order_sn,p_order->>'external_user_id',p_order->>'buyer_username',p_order->>'buyer_phone',p_order->>'buyer_email',p_order->>'order_status',(p_order->>'transaction_date')::timestamptz,(p_order->>'update_time')::timestamptz,COALESCE(p_order->>'currency','THB'),(p_order->>'total_amount')::numeric,COALESCE((p_order->>'shipping_fee')::numeric,0),COALESCE((p_order->>'discount_amount')::numeric,0),COALESCE((p_order->>'tax_amount')::numeric,0),(p_order->>'final_amount')::numeric,(p_order->>'earnable_amount')::numeric,COALESCE(p_order->'financial_details','{}'::jsonb),p_order->>'payment_method',p_order->>'payment_status','completed',COALESCE(v_codes,'{}'::text[])) RETURNING id INTO v_order_id;
  v_action:='inserted';
 END IF;
 IF NOT v_synced AND p_order?'items' AND jsonb_typeof(p_order->'items')='array' AND jsonb_array_length(p_order->'items')>0 THEN
  INSERT INTO order_items_ledger_mkp(order_id,merchant_id,platform,order_sn,platform_item_id,variant_id,platform_sku,variant_sku,item_name,variant_name,quantity,currency,unit_price,discount_amount,line_total,earnable_amount,financial_details)
  SELECT v_order_id,(p_order->>'merchant_id')::uuid,p_order->>'platform',v_order_sn,item->>'platform_item_id',item->>'variant_id',item->>'platform_sku',item->>'variant_sku',item->>'item_name',item->>'variant_name',(item->>'quantity')::numeric,COALESCE(item->>'currency','THB'),(item->>'unit_price')::numeric,COALESCE((item->>'discount_amount')::numeric,0),(item->>'line_total')::numeric,(item->>'earnable_amount')::numeric,COALESCE(item->'financial_details','{}'::jsonb)
  FROM (
    SELECT DISTINCT ON (item->>'platform_item_id') item
    FROM jsonb_array_elements(p_order->'items') WITH ORDINALITY AS t(item, ord)
    ORDER BY item->>'platform_item_id', ord DESC
  ) deduped
  ON CONFLICT(platform,platform_item_id,order_id) DO UPDATE SET quantity=EXCLUDED.quantity,unit_price=EXCLUDED.unit_price,discount_amount=EXCLUDED.discount_amount,line_total=EXCLUDED.line_total,earnable_amount=EXCLUDED.earnable_amount,financial_details=EXCLUDED.financial_details;
  GET DIAGNOSTICS v_items_inserted=ROW_COUNT;
 END IF;
 BEGIN v_attr:=public.fn_attribute_referral(p_kind:='purchase',p_merchant_id:=(p_order->>'merchant_id')::uuid,p_platform:=p_order->>'platform',p_order_key:=v_order_sn,p_order_status:=p_order->>'order_status',p_payment_status:=p_order->>'payment_status',p_buyer_email:=p_order->>'buyer_email',p_buyer_phone:=p_order->>'buyer_phone',p_buyer_external_id:=p_order->>'external_user_id',p_codes:=COALESCE(v_codes,'{}'::text[])); EXCEPTION WHEN OTHERS THEN v_attr:=jsonb_build_object('success',false,'error',SQLERRM); END;
 RETURN jsonb_build_object('success',true,'code',CASE WHEN v_action='inserted' THEN 'CREATED' ELSE 'UPDATED' END,'title',CASE WHEN v_action='inserted' THEN 'Order Created' ELSE 'Order Updated' END,'description',format('Order %s %s with %s items',v_order_sn,v_action,v_items_inserted),'action',v_action,'order_id',v_order_id,'order_sn',v_order_sn,'items_count',v_items_inserted,'referral',v_attr);
END;
$function$;
