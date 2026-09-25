-- Bootstrap Rocket Demo merchant masters (tiers, stores, catalog, rewards)
CREATE OR REPLACE FUNCTION public.custom_internal_demo_bootstrap_merchant()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $fn$
DECLARE
  v_settings jsonb := custom_internal_demo_settings();
  v_merchant_id uuid;
  v_tier_member uuid;
  v_tier_silver uuid;
  v_tier_gold uuid;
  v_tier_plat uuid;
  v_store_ids uuid[];
  v_brand_ids jsonb := '{}'::jsonb;
  v_cat_ids jsonb := '{}'::jsonb;
  v_earn_channel_id uuid;
  v_channel_cat_id uuid;
  v_attr_id uuid;
  v_channel_map jsonb := '{}'::jsonb;
  r record;
  v_brand_id uuid;
  v_cat_id uuid;
  v_product_id uuid;
  v_sku_id uuid;
  v_reward_id uuid;
  v_reward_count int := 0;
  v_usage_store_ids uuid[];
BEGIN
  IF v_settings IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'settings missing');
  END IF;
  v_merchant_id := (v_settings->>'merchant_id')::uuid;

  -- Clean prior bootstrap rows for this merchant (idempotent re-run).
  -- Stores are upserted (not deleted) so purchase/redemption FKs stay intact.
  DELETE FROM reward_points_conditions WHERE merchant_id = v_merchant_id;
  DELETE FROM reward_master WHERE merchant_id = v_merchant_id AND reward_code LIKE 'RKT-%';
  DELETE FROM product_sku_master WHERE merchant_id = v_merchant_id AND sku_code LIKE 'RG-%';
  DELETE FROM product_master WHERE merchant_id = v_merchant_id AND product_code LIKE 'RG-%';
  DELETE FROM product_brand_master WHERE merchant_id = v_merchant_id;
  DELETE FROM product_category_master WHERE merchant_id = v_merchant_id;
  DELETE FROM earn_channel WHERE merchant_id = v_merchant_id AND channel_code = 'pos';
  DELETE FROM tier_master WHERE merchant_id = v_merchant_id
    AND tier_name IN ('Member', 'Silver', 'Gold', 'Platinum');

  INSERT INTO tier_master (merchant_id, tier_name, ranking, entry_tier, user_type, color)
  VALUES (v_merchant_id, 'Member', 1, true, 'buyer', '#94A3B8')
  RETURNING id INTO v_tier_member;
  INSERT INTO tier_master (merchant_id, tier_name, ranking, entry_tier, user_type, color)
  VALUES (v_merchant_id, 'Silver', 2, false, 'buyer', '#CBD5E1')
  RETURNING id INTO v_tier_silver;
  INSERT INTO tier_master (merchant_id, tier_name, ranking, entry_tier, user_type, color)
  VALUES (v_merchant_id, 'Gold', 3, false, 'buyer', '#F59E0B')
  RETURNING id INTO v_tier_gold;
  INSERT INTO tier_master (merchant_id, tier_name, ranking, entry_tier, user_type, color)
  VALUES (v_merchant_id, 'Platinum', 4, false, 'buyer', '#6366F1')
  RETURNING id INTO v_tier_plat;

  -- Lifestyle retail stores (upsert by merchant_id + store_code)
  INSERT INTO store_master (merchant_id, store_code, store_name, active_status, province, address)
  VALUES
    (v_merchant_id, 'RKT-SIAM', 'Siam Paragon Flagship', true, 'Bangkok', '991 Rama I Rd'),
    (v_merchant_id, 'RKT-ICON', 'ICONSIAM Flagship', true, 'Bangkok', '299 Charoen Nakhon Rd'),
    (v_merchant_id, 'RKT-EMQ', 'EmQuartier Boutique', true, 'Bangkok', '693 Sukhumvit Rd'),
    (v_merchant_id, 'RKT-CEB', 'Central Embassy Boutique', true, 'Bangkok', '1031 Ploenchit Rd'),
    (v_merchant_id, 'RKT-OBK', 'One Bangkok Boutique', true, 'Bangkok', 'Rama IV Rd'),
    (v_merchant_id, 'RKT-CM', 'Maya Chiang Mai', true, 'Chiang Mai', 'Maya Lifestyle'),
    (v_merchant_id, 'RKT-CTL', 'CentralWorld Beauty', true, 'Bangkok', '4 Ratchadamri Rd'),
    (v_merchant_id, 'RKT-CLP', 'Central Ladprao Beauty', true, 'Bangkok', '1693 Phahonyothin Rd'),
    (v_merchant_id, 'RKT-MBK', 'The Mall Bangkapi Beauty', true, 'Bangkok', '3520 Lat Phrao Rd'),
    (v_merchant_id, 'RKT-WAT', 'Watsons Siam Center', true, 'Bangkok', 'Siam Center'),
    (v_merchant_id, 'RKT-BOOT', 'Boots Silom Complex', true, 'Bangkok', 'Silom Complex'),
    (v_merchant_id, 'RKT-EVE', 'Eveandboy EmQuartier', true, 'Bangkok', 'EmQuartier'),
    (v_merchant_id, 'RKT-BEA', 'Beautrium CentralWorld', true, 'Bangkok', 'CentralWorld'),
    (v_merchant_id, 'RKT-KNV', 'Konvy Pickup Silom', true, 'Bangkok', 'Silom Rd'),
    (v_merchant_id, 'RKT-PHX', 'Terminal 21 Pattaya', true, 'Chonburi', 'Terminal 21'),
    (v_merchant_id, 'RKT-HKT', 'Central Festival Phuket', true, 'Phuket', 'Central Festival'),
    (v_merchant_id, 'RKT-ONLINE', 'Rocket Club Online', true, 'Bangkok', 'Own e-commerce'),
    (v_merchant_id, 'RKT-SHOPEE', 'Shopee Official Store', true, 'Bangkok', 'Marketplace'),
    (v_merchant_id, 'RKT-LAZ', 'Lazada Official Store', true, 'Bangkok', 'Marketplace'),
    (v_merchant_id, 'RKT-TT', 'TikTok Shop Official', true, 'Bangkok', 'Marketplace')
  ON CONFLICT (merchant_id, store_code) DO UPDATE
  SET store_name = EXCLUDED.store_name,
      active_status = EXCLUDED.active_status,
      province = EXCLUDED.province,
      address = EXCLUDED.address,
      updated_at = now();

  SELECT array_agg(id ORDER BY store_code)
  INTO v_store_ids
  FROM store_master
  WHERE merchant_id = v_merchant_id AND store_code LIKE 'RKT-%';

  -- Sales Channel category + lifestyle channel values + store assignments
  INSERT INTO store_attribute_categories (
    merchant_id, attribute_category_code, attribute_category_name, is_store_channel, is_deleted
  ) VALUES (
    v_merchant_id, 'CHANNEL', 'Sales Channel', true, false
  )
  ON CONFLICT (merchant_id, attribute_category_code) DO UPDATE
  SET attribute_category_name = EXCLUDED.attribute_category_name,
      is_store_channel = true,
      is_deleted = false,
      updated_at = now()
  RETURNING id INTO v_channel_cat_id;

  IF v_channel_cat_id IS NULL THEN
    SELECT id INTO v_channel_cat_id
    FROM store_attribute_categories
    WHERE merchant_id = v_merchant_id AND attribute_category_code = 'CHANNEL';
  END IF;

  DELETE FROM store_attribute_assignments
  WHERE merchant_id = v_merchant_id AND category_id = v_channel_cat_id;

  FOR r IN
    SELECT * FROM (VALUES
      ('FLAGSHIP', 'Flagship'),
      ('BOUTIQUE_MALL', 'Boutique Mall'),
      ('DEPARTMENT_STORE', 'Department Store'),
      ('SPECIALTY_RETAIL', 'Specialty Retail'),
      ('OWN_ONLINE', 'Own Online'),
      ('MARKETPLACE', 'Marketplace')
    ) AS t(code, name)
  LOOP
    INSERT INTO store_attributes (
      merchant_id, category_id, attribute_code, attribute_name, is_deleted
    ) VALUES (
      v_merchant_id, v_channel_cat_id, r.code, r.name, false
    )
    ON CONFLICT (merchant_id, category_id, attribute_code) DO UPDATE
    SET attribute_name = EXCLUDED.attribute_name,
        is_deleted = false,
        updated_at = now()
    RETURNING id INTO v_attr_id;

    IF v_attr_id IS NULL THEN
      SELECT id INTO v_attr_id
      FROM store_attributes
      WHERE merchant_id = v_merchant_id
        AND category_id = v_channel_cat_id
        AND attribute_code = r.code;
    END IF;

    v_channel_map := v_channel_map || jsonb_build_object(r.code, v_attr_id);
  END LOOP;

  FOR r IN
    SELECT sm.id AS store_id, x.channel_code
    FROM store_master sm
    JOIN (VALUES
      ('RKT-SIAM', 'FLAGSHIP'),
      ('RKT-ICON', 'FLAGSHIP'),
      ('RKT-EMQ', 'BOUTIQUE_MALL'),
      ('RKT-CEB', 'BOUTIQUE_MALL'),
      ('RKT-OBK', 'BOUTIQUE_MALL'),
      ('RKT-CM', 'BOUTIQUE_MALL'),
      ('RKT-PHX', 'BOUTIQUE_MALL'),
      ('RKT-HKT', 'BOUTIQUE_MALL'),
      ('RKT-CTL', 'DEPARTMENT_STORE'),
      ('RKT-CLP', 'DEPARTMENT_STORE'),
      ('RKT-MBK', 'DEPARTMENT_STORE'),
      ('RKT-WAT', 'SPECIALTY_RETAIL'),
      ('RKT-BOOT', 'SPECIALTY_RETAIL'),
      ('RKT-EVE', 'SPECIALTY_RETAIL'),
      ('RKT-BEA', 'SPECIALTY_RETAIL'),
      ('RKT-KNV', 'SPECIALTY_RETAIL'),
      ('RKT-ONLINE', 'OWN_ONLINE'),
      ('RKT-SHOPEE', 'MARKETPLACE'),
      ('RKT-LAZ', 'MARKETPLACE'),
      ('RKT-TT', 'MARKETPLACE')
    ) AS x(store_code, channel_code) ON x.store_code = sm.store_code
    WHERE sm.merchant_id = v_merchant_id
  LOOP
    INSERT INTO store_attribute_assignments (
      merchant_id, store_id, category_id, attribute_id
    ) VALUES (
      v_merchant_id, r.store_id, v_channel_cat_id, (v_channel_map ->> r.channel_code)::uuid
    )
    ON CONFLICT (merchant_id, store_id, category_id) DO UPDATE
    SET attribute_id = EXCLUDED.attribute_id,
        assigned_at = now();
  END LOOP;

  SELECT array_agg(sm.id ORDER BY sm.store_code)
  INTO v_usage_store_ids
  FROM store_master sm
  JOIN store_attribute_assignments saa
    ON saa.store_id = sm.id AND saa.merchant_id = sm.merchant_id
  JOIN store_attributes sa ON sa.id = saa.attribute_id
  WHERE sm.merchant_id = v_merchant_id
    AND sm.store_code LIKE 'RKT-%'
    AND sa.attribute_code IN ('FLAGSHIP', 'BOUTIQUE_MALL', 'DEPARTMENT_STORE', 'SPECIALTY_RETAIL');

  FOR r IN
    SELECT DISTINCT payload->>'brand' AS brand
    FROM custom_internal_demo_config
    WHERE kind = 'product' AND is_active
  LOOP
    INSERT INTO product_brand_master (merchant_id, name)
    VALUES (v_merchant_id, r.brand)
    RETURNING id INTO v_brand_id;
    v_brand_ids := v_brand_ids || jsonb_build_object(r.brand, v_brand_id);
  END LOOP;

  FOR r IN
    SELECT DISTINCT payload->>'category' AS category
    FROM custom_internal_demo_config
    WHERE kind = 'product' AND is_active
  LOOP
    INSERT INTO product_category_master (merchant_id, name)
    VALUES (v_merchant_id, r.category)
    RETURNING id INTO v_cat_id;
    v_cat_ids := v_cat_ids || jsonb_build_object(r.category, v_cat_id);
  END LOOP;

  FOR r IN
    SELECT code, payload
    FROM custom_internal_demo_config
    WHERE kind = 'product' AND is_active
    ORDER BY sort_order
  LOOP
    v_brand_id := (v_brand_ids ->> (r.payload->>'brand'))::uuid;
    v_cat_id := (v_cat_ids ->> (r.payload->>'category'))::uuid;
    INSERT INTO product_master (merchant_id, product_code, name, brand_id, category_id, price)
    VALUES (
      v_merchant_id, r.code, r.payload->>'name', v_brand_id, v_cat_id,
      (r.payload->>'price')::numeric
    )
    RETURNING id INTO v_product_id;

    INSERT INTO product_sku_master (merchant_id, product_id, sku_code, name, price, uom_primary)
    VALUES (
      v_merchant_id, v_product_id, r.code, r.payload->>'name',
      (r.payload->>'price')::numeric, 'ea'
    )
    RETURNING id INTO v_sku_id;

    UPDATE custom_internal_demo_config
    SET payload = payload || jsonb_build_object('product_id', v_product_id, 'sku_id', v_sku_id),
        updated_at = now()
    WHERE kind = 'product' AND code = r.code;
  END LOOP;

  INSERT INTO earn_channel (
    merchant_id, channel_code, channel_name, channel_type, method_type,
    active, display_order, is_system
  )
  VALUES (v_merchant_id, 'pos', 'In-Store POS', 'purchase', 'api', true, 1, false)
  RETURNING id INTO v_earn_channel_id;

  FOR r IN
    SELECT * FROM (VALUES
      ('RKT-V100', '฿100 Voucher (min. spend ฿500)', 500::numeric, 'digital'),
      ('RKT-V300', '฿300 Voucher (min. spend ฿1,200)', 1200, 'digital'),
      ('RKT-SUN', 'Free Travel-Size Sunscreen', 800, 'pickup'),
      ('RKT-DEL', 'Free Delivery Voucher', 400, 'digital'),
      ('RKT-BDAY', 'Birthday Double Points Pass', 150, 'digital'),
      ('RKT-GIFT', 'Exclusive Member Gift Set', 2500, 'shipping'),
      ('RKT-SERUM', 'Niacinamide Bright Serum Sample', 600, 'pickup'),
      ('RKT-VIP', 'Platinum Soft Glow Kit', 5000, 'shipping'),
      ('RKT-HAND', 'Hand Cream Soft Petal', 350, 'pickup'),
      ('RKT-MASK', 'Overnight Sleeping Mask', 900, 'pickup'),
      ('RKT-V50', '฿50 Soft Glow Voucher', 250, 'digital'),
      ('RKT-DUO', 'Brightening Duo Mini Set', 1800, 'shipping')
    ) AS t(code, name, pts, fulfill)
  LOOP
    INSERT INTO reward_master (
      merchant_id, name, reward_code, active_status, visibility, fulfillment_method,
      fallback_points, stock_control, use_expire_mode, use_expire_ttl,
      description_headline, description_body, ranking
    ) VALUES (
      v_merchant_id, r.name, r.code, true, 'user', r.fulfill::reward_fulfillment_method,
      r.pts, false, 'relative_days', 90,
      r.name, 'Redeem with Rocket Club points.', 1
    )
    RETURNING id INTO v_reward_id;

    INSERT INTO reward_points_conditions (
      merchant_id, reward_id, condition_name, points_required, active_status, priority, user_type
    ) VALUES (
      v_merchant_id, v_reward_id, 'Default', r.pts, true, 1, 'buyer'
    );
    v_reward_count := v_reward_count + 1;
  END LOOP;

  UPDATE custom_internal_demo_config
  SET payload = payload || jsonb_build_object(
    'tier_member_id', v_tier_member,
    'tier_silver_id', v_tier_silver,
    'tier_gold_id', v_tier_gold,
    'tier_platinum_id', v_tier_plat,
    'earn_channel_id', v_earn_channel_id,
    'store_ids', to_jsonb(v_store_ids),
    'usage_store_ids', to_jsonb(v_usage_store_ids),
    'store_channel_category_id', v_channel_cat_id,
    'bootstrapped_at', now()
  ),
  updated_at = now()
  WHERE kind = 'settings' AND code = 'default';

  RETURN jsonb_build_object(
    'success', true,
    'merchant_id', v_merchant_id,
    'tiers', 4,
    'stores', coalesce(array_length(v_store_ids, 1), 0),
    'usage_stores', coalesce(array_length(v_usage_store_ids, 1), 0),
    'channels', 6,
    'rewards', v_reward_count
  );
END;
$fn$;

-- Safe incremental: upsert lifestyle stores + sales channels without wiping rewards/tiers.
CREATE OR REPLACE FUNCTION public.custom_internal_demo_bootstrap_store_channels()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $fn$
DECLARE
  v_settings jsonb := custom_internal_demo_settings();
  v_merchant_id uuid;
  v_store_ids uuid[];
  v_usage_store_ids uuid[];
  v_channel_cat_id uuid;
  v_attr_id uuid;
  v_channel_map jsonb := '{}'::jsonb;
  r record;
BEGIN
  IF v_settings IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'settings missing');
  END IF;
  v_merchant_id := (v_settings->>'merchant_id')::uuid;

  INSERT INTO store_master (merchant_id, store_code, store_name, active_status, province, address)
  VALUES
    (v_merchant_id, 'RKT-SIAM', 'Siam Paragon Flagship', true, 'Bangkok', '991 Rama I Rd'),
    (v_merchant_id, 'RKT-ICON', 'ICONSIAM Flagship', true, 'Bangkok', '299 Charoen Nakhon Rd'),
    (v_merchant_id, 'RKT-EMQ', 'EmQuartier Boutique', true, 'Bangkok', '693 Sukhumvit Rd'),
    (v_merchant_id, 'RKT-CEB', 'Central Embassy Boutique', true, 'Bangkok', '1031 Ploenchit Rd'),
    (v_merchant_id, 'RKT-OBK', 'One Bangkok Boutique', true, 'Bangkok', 'Rama IV Rd'),
    (v_merchant_id, 'RKT-CM', 'Maya Chiang Mai', true, 'Chiang Mai', 'Maya Lifestyle'),
    (v_merchant_id, 'RKT-CTL', 'CentralWorld Beauty', true, 'Bangkok', '4 Ratchadamri Rd'),
    (v_merchant_id, 'RKT-CLP', 'Central Ladprao Beauty', true, 'Bangkok', '1693 Phahonyothin Rd'),
    (v_merchant_id, 'RKT-MBK', 'The Mall Bangkapi Beauty', true, 'Bangkok', '3520 Lat Phrao Rd'),
    (v_merchant_id, 'RKT-WAT', 'Watsons Siam Center', true, 'Bangkok', 'Siam Center'),
    (v_merchant_id, 'RKT-BOOT', 'Boots Silom Complex', true, 'Bangkok', 'Silom Complex'),
    (v_merchant_id, 'RKT-EVE', 'Eveandboy EmQuartier', true, 'Bangkok', 'EmQuartier'),
    (v_merchant_id, 'RKT-BEA', 'Beautrium CentralWorld', true, 'Bangkok', 'CentralWorld'),
    (v_merchant_id, 'RKT-KNV', 'Konvy Pickup Silom', true, 'Bangkok', 'Silom Rd'),
    (v_merchant_id, 'RKT-PHX', 'Terminal 21 Pattaya', true, 'Chonburi', 'Terminal 21'),
    (v_merchant_id, 'RKT-HKT', 'Central Festival Phuket', true, 'Phuket', 'Central Festival'),
    (v_merchant_id, 'RKT-ONLINE', 'Rocket Club Online', true, 'Bangkok', 'Own e-commerce'),
    (v_merchant_id, 'RKT-SHOPEE', 'Shopee Official Store', true, 'Bangkok', 'Marketplace'),
    (v_merchant_id, 'RKT-LAZ', 'Lazada Official Store', true, 'Bangkok', 'Marketplace'),
    (v_merchant_id, 'RKT-TT', 'TikTok Shop Official', true, 'Bangkok', 'Marketplace')
  ON CONFLICT (merchant_id, store_code) DO UPDATE
  SET store_name = EXCLUDED.store_name,
      active_status = EXCLUDED.active_status,
      province = EXCLUDED.province,
      address = EXCLUDED.address,
      updated_at = now();

  SELECT array_agg(id ORDER BY store_code)
  INTO v_store_ids
  FROM store_master
  WHERE merchant_id = v_merchant_id AND store_code LIKE 'RKT-%';

  INSERT INTO store_attribute_categories (
    merchant_id, attribute_category_code, attribute_category_name, is_store_channel, is_deleted
  ) VALUES (
    v_merchant_id, 'CHANNEL', 'Sales Channel', true, false
  )
  ON CONFLICT (merchant_id, attribute_category_code) DO UPDATE
  SET attribute_category_name = EXCLUDED.attribute_category_name,
      is_store_channel = true,
      is_deleted = false,
      updated_at = now()
  RETURNING id INTO v_channel_cat_id;

  IF v_channel_cat_id IS NULL THEN
    SELECT id INTO v_channel_cat_id
    FROM store_attribute_categories
    WHERE merchant_id = v_merchant_id AND attribute_category_code = 'CHANNEL';
  END IF;

  DELETE FROM store_attribute_assignments
  WHERE merchant_id = v_merchant_id AND category_id = v_channel_cat_id;

  FOR r IN
    SELECT * FROM (VALUES
      ('FLAGSHIP', 'Flagship'),
      ('BOUTIQUE_MALL', 'Boutique Mall'),
      ('DEPARTMENT_STORE', 'Department Store'),
      ('SPECIALTY_RETAIL', 'Specialty Retail'),
      ('OWN_ONLINE', 'Own Online'),
      ('MARKETPLACE', 'Marketplace')
    ) AS t(code, name)
  LOOP
    INSERT INTO store_attributes (
      merchant_id, category_id, attribute_code, attribute_name, is_deleted
    ) VALUES (
      v_merchant_id, v_channel_cat_id, r.code, r.name, false
    )
    ON CONFLICT (merchant_id, category_id, attribute_code) DO UPDATE
    SET attribute_name = EXCLUDED.attribute_name,
        is_deleted = false,
        updated_at = now()
    RETURNING id INTO v_attr_id;

    IF v_attr_id IS NULL THEN
      SELECT id INTO v_attr_id
      FROM store_attributes
      WHERE merchant_id = v_merchant_id
        AND category_id = v_channel_cat_id
        AND attribute_code = r.code;
    END IF;

    v_channel_map := v_channel_map || jsonb_build_object(r.code, v_attr_id);
  END LOOP;

  FOR r IN
    SELECT sm.id AS store_id, x.channel_code
    FROM store_master sm
    JOIN (VALUES
      ('RKT-SIAM', 'FLAGSHIP'),
      ('RKT-ICON', 'FLAGSHIP'),
      ('RKT-EMQ', 'BOUTIQUE_MALL'),
      ('RKT-CEB', 'BOUTIQUE_MALL'),
      ('RKT-OBK', 'BOUTIQUE_MALL'),
      ('RKT-CM', 'BOUTIQUE_MALL'),
      ('RKT-PHX', 'BOUTIQUE_MALL'),
      ('RKT-HKT', 'BOUTIQUE_MALL'),
      ('RKT-CTL', 'DEPARTMENT_STORE'),
      ('RKT-CLP', 'DEPARTMENT_STORE'),
      ('RKT-MBK', 'DEPARTMENT_STORE'),
      ('RKT-WAT', 'SPECIALTY_RETAIL'),
      ('RKT-BOOT', 'SPECIALTY_RETAIL'),
      ('RKT-EVE', 'SPECIALTY_RETAIL'),
      ('RKT-BEA', 'SPECIALTY_RETAIL'),
      ('RKT-KNV', 'SPECIALTY_RETAIL'),
      ('RKT-ONLINE', 'OWN_ONLINE'),
      ('RKT-SHOPEE', 'MARKETPLACE'),
      ('RKT-LAZ', 'MARKETPLACE'),
      ('RKT-TT', 'MARKETPLACE')
    ) AS x(store_code, channel_code) ON x.store_code = sm.store_code
    WHERE sm.merchant_id = v_merchant_id
  LOOP
    INSERT INTO store_attribute_assignments (
      merchant_id, store_id, category_id, attribute_id
    ) VALUES (
      v_merchant_id, r.store_id, v_channel_cat_id, (v_channel_map ->> r.channel_code)::uuid
    )
    ON CONFLICT (merchant_id, store_id, category_id) DO UPDATE
    SET attribute_id = EXCLUDED.attribute_id,
        assigned_at = now();
  END LOOP;

  SELECT array_agg(sm.id ORDER BY sm.store_code)
  INTO v_usage_store_ids
  FROM store_master sm
  JOIN store_attribute_assignments saa
    ON saa.store_id = sm.id AND saa.merchant_id = sm.merchant_id
  JOIN store_attributes sa ON sa.id = saa.attribute_id
  WHERE sm.merchant_id = v_merchant_id
    AND sm.store_code LIKE 'RKT-%'
    AND sa.attribute_code IN ('FLAGSHIP', 'BOUTIQUE_MALL', 'DEPARTMENT_STORE', 'SPECIALTY_RETAIL');

  UPDATE custom_internal_demo_config
  SET payload = payload || jsonb_build_object(
    'store_ids', to_jsonb(v_store_ids),
    'usage_store_ids', to_jsonb(v_usage_store_ids),
    'store_channel_category_id', v_channel_cat_id,
    'store_channels_bootstrapped_at', now()
  ),
  updated_at = now()
  WHERE kind = 'settings' AND code = 'default';

  RETURN jsonb_build_object(
    'success', true,
    'stores', coalesce(array_length(v_store_ids, 1), 0),
    'usage_stores', coalesce(array_length(v_usage_store_ids, 1), 0),
    'channels', 6
  );
END;
$fn$;
