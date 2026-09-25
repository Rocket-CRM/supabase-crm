-- 2) Admin upsert — drop old signature, recreate with new trailing params
DO $patch$
DECLARE
  v_def text;
  v_identity text;
BEGIN
  SELECT pg_get_functiondef(p.oid), pg_get_function_identity_arguments(p.oid)
  INTO v_def, v_identity
  FROM pg_proc p
  JOIN pg_namespace n ON p.pronamespace = n.oid
  WHERE n.nspname = 'public'
    AND p.proname = 'bff_upsert_reward_with_conditions_and_limits';

  IF v_def IS NULL THEN
    RAISE EXCEPTION 'bff_upsert_reward_with_conditions_and_limits not found';
  END IF;

  IF position('p_physical_draw_name' in v_def) > 0 THEN
    RAISE NOTICE 'upsert already has physical_draw params';
    RETURN;
  END IF;

  EXECUTE format('DROP FUNCTION public.bff_upsert_reward_with_conditions_and_limits(%s)', v_identity);

  v_def := replace(
    v_def,
    'p_variant_config jsonb DEFAULT NULL::jsonb)',
    'p_variant_config jsonb DEFAULT NULL::jsonb, p_physical_draw_name text DEFAULT NULL::text, p_physical_draw_description text DEFAULT NULL::text)'
  );

  v_def := replace(
    v_def,
    'shopify_discount_type, shopify_discount_label, variant_config, created_at)
        VALUES (v_reward_id, v_merchant_id, p_name, p_description_headline, p_description_body, p_description_tc, p_description_slip, v_image, v_category_id, p_visibility, p_redeem_window_start, p_redeem_window_end, p_stock_control, p_assign_promocode, p_use_expire_mode, p_use_expire_date, p_use_expire_ttl, p_fulfillment_method, v_allowed_tier, v_allowed_persona, v_allowed_tags, v_allowed_birthmonth, p_fallback_points, p_require_points_match, p_external_id_shopify, v_online_store, v_reward_group_ids, p_shopify_discount_type, p_shopify_discount_label, p_variant_config, NOW());',
    'shopify_discount_type, shopify_discount_label, variant_config, physical_draw_name, physical_draw_description, created_at)
        VALUES (v_reward_id, v_merchant_id, p_name, p_description_headline, p_description_body, p_description_tc, p_description_slip, v_image, v_category_id, p_visibility, p_redeem_window_start, p_redeem_window_end, p_stock_control, p_assign_promocode, p_use_expire_mode, p_use_expire_date, p_use_expire_ttl, p_fulfillment_method, v_allowed_tier, v_allowed_persona, v_allowed_tags, v_allowed_birthmonth, p_fallback_points, p_require_points_match, p_external_id_shopify, v_online_store, v_reward_group_ids, p_shopify_discount_type, p_shopify_discount_label, p_variant_config, p_physical_draw_name, p_physical_draw_description, NOW());'
  );

  v_def := replace(
    v_def,
    'variant_config = p_variant_config
        WHERE id = v_reward_id AND merchant_id = v_merchant_id;',
    'variant_config = p_variant_config,
          physical_draw_name = p_physical_draw_name,
          physical_draw_description = p_physical_draw_description
        WHERE id = v_reward_id AND merchant_id = v_merchant_id;'
  );

  IF position('p_physical_draw_name' in v_def) = 0
     OR position('physical_draw_name = p_physical_draw_name' in v_def) = 0 THEN
    RAISE EXCEPTION 'upsert patch failed — expected markers not found';
  END IF;

  EXECUTE v_def;
END;
$patch$;

