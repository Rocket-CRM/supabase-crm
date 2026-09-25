-- Masters: stores, catalog, earn, activity types, personas, tags, reward points, mkt, RFM.
-- Does not recreate rewards or Silver/Gold/Platinum tiers.

CREATE OR REPLACE FUNCTION public.custom_ausiris_demo_bootstrap_masters()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $fn$
DECLARE
  v_mid uuid := custom_ausiris_demo_merchant_id();
  v_tier_silver uuid;
  v_tier_gold uuid;
  v_tier_plat uuid;
  v_pg uuid;
  v_earn_res jsonb;
  v_brand_id uuid;
  v_cat_id uuid;
  v_prod_id uuid;
  r record;
  v_reward record;
  v_pts numeric;
  v_mkt_id uuid;
  v_ids jsonb := '{}'::jsonb;
BEGIN
  PERFORM custom_ausiris_demo_set_ctx();

  SELECT id INTO v_tier_silver FROM tier_master WHERE merchant_id = v_mid AND tier_name = 'Silver' LIMIT 1;
  SELECT id INTO v_tier_gold FROM tier_master WHERE merchant_id = v_mid AND tier_name = 'Gold' LIMIT 1;
  SELECT id INTO v_tier_plat FROM tier_master WHERE merchant_id = v_mid AND tier_name = 'Platinum' LIMIT 1;
  IF v_tier_silver IS NULL OR v_tier_gold IS NULL OR v_tier_plat IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'expected Silver/Gold/Platinum tiers missing');
  END IF;

  INSERT INTO custom_ausiris_demo_config (kind, code, payload, sort_order)
  VALUES
    ('id', 'tier_silver', jsonb_build_object('id', v_tier_silver), 1),
    ('id', 'tier_gold', jsonb_build_object('id', v_tier_gold), 2),
    ('id', 'tier_plat', jsonb_build_object('id', v_tier_plat), 3)
  ON CONFLICT (kind, code) DO UPDATE SET payload = EXCLUDED.payload, updated_at = now();

  -- Stores / channels
  INSERT INTO store_master (merchant_id, store_code, store_name, active_status, province, address)
  VALUES
    (v_mid, 'AUS-NEXT-APP', 'Ausiris Next', true, 'Bangkok', 'App'),
    (v_mid, 'AUS-PLUS-APP', 'My Gold Plus', true, 'Bangkok', 'App'),
    (v_mid, 'AUS-EXPRESS-WEB', 'Ausiris Express', true, 'Bangkok', 'Web'),
    (v_mid, 'AUS-POS-SILOM', 'Ausiris Gold Silom', true, 'Bangkok', 'Silom'),
    (v_mid, 'AUS-POS-SIAM', 'Ausiris Gold Siam', true, 'Bangkok', 'Siam'),
    (v_mid, 'AUS-POS-CNX', 'Ausiris Gold Chiang Mai', true, 'Chiang Mai', 'Chiang Mai'),
    (v_mid, 'AUS-POS-SLV-TDP', 'Ausiris Silver True Digital Park', true, 'Bangkok', 'True Digital Park'),
    (v_mid, 'AUS-VD-TDP', 'Ausiris Vending True Digital Park', true, 'Bangkok', 'True Digital Park'),
    (v_mid, 'AUS-SHOPEE', 'Ausiris Shopee Official', true, 'Bangkok', 'Marketplace'),
    (v_mid, 'AUS-LAZADA', 'Ausiris Lazada Official', true, 'Bangkok', 'Marketplace'),
    (v_mid, 'AUS-TIKTOK', 'Ausiris TikTok Shop', true, 'Bangkok', 'Marketplace'),
    (v_mid, 'AUS-IRIS-LIVE', 'Iris Jewel Live', true, 'Bangkok', 'Live')
  ON CONFLICT (merchant_id, store_code) DO UPDATE
  SET store_name = EXCLUDED.store_name, active_status = true, updated_at = now();

  INSERT INTO earn_channel (
    merchant_id, channel_code, channel_name, channel_type, method_type,
    active, display_order, is_system, marketplace_platforms
  )
  SELECT v_mid, x.code, x.name, 'purchase', x.method, true, x.ord, false, x.mkp
  FROM (VALUES
    ('trading', 'Ausiris Next (Trading)', 'api', 1, NULL::text[]),
    ('gold_saving', 'My Gold Plus', 'api', 2, NULL::text[]),
    ('web', 'Ausiris Express', 'api', 3, NULL::text[]),
    ('pos', 'In-store POS', 'api', 4, NULL::text[]),
    ('vending', 'Vending', 'api', 5, NULL::text[]),
    ('marketplace', 'Marketplace', 'marketplace_code', 6, ARRAY['shopee','lazada','tiktok']::text[]),
    ('live', 'Iris Jewel Live', 'api', 7, NULL::text[])
  ) AS x(code, name, method, ord, mkp)
  ON CONFLICT (merchant_id, channel_code) DO UPDATE
  SET channel_name = EXCLUDED.channel_name,
      channel_type = 'purchase',
      method_type = EXCLUDED.method_type,
      active = true,
      display_order = EXCLUDED.display_order,
      marketplace_platforms = EXCLUDED.marketplace_platforms,
      updated_at = now();

  UPDATE earn_channel
  SET active = false, updated_at = now()
  WHERE merchant_id = v_mid AND channel_code = 'app';

  INSERT INTO custom_ausiris_demo_config (kind, code, payload)
  SELECT 'id', 'earn_channel_' || e.channel_code, jsonb_build_object('id', e.id)
  FROM earn_channel e
  WHERE e.merchant_id = v_mid
    AND e.channel_code IN ('trading','gold_saving','web','pos','vending','marketplace','live')
  ON CONFLICT (kind, code) DO UPDATE SET payload = EXCLUDED.payload, updated_at = now();

  v_earn_res := custom_ausiris_demo_bootstrap_store_channels();

  -- Brands
  FOR r IN SELECT * FROM (VALUES
    ('Ausiris'), ('Ausiris Next'), ('My Gold Plus'), ('Iris Jewel'), ('Ausiris Express')
  ) AS t(name)
  LOOP
    SELECT id INTO v_brand_id FROM product_brand_master WHERE merchant_id = v_mid AND name = r.name LIMIT 1;
    IF v_brand_id IS NULL THEN
      INSERT INTO product_brand_master (merchant_id, name) VALUES (v_mid, r.name) RETURNING id INTO v_brand_id;
    END IF;
    INSERT INTO custom_ausiris_demo_config (kind, code, payload)
    VALUES ('brand', r.name, jsonb_build_object('id', v_brand_id))
    ON CONFLICT (kind, code) DO UPDATE SET payload = EXCLUDED.payload, updated_at = now();
  END LOOP;

  -- Categories
  FOR r IN SELECT * FROM (VALUES
    ('Gold Trading'), ('Gold Saving'), ('Gold Bar'), ('Silver'), ('Jewelry')
  ) AS t(name)
  LOOP
    SELECT id INTO v_cat_id FROM product_category_master WHERE merchant_id = v_mid AND name = r.name LIMIT 1;
    IF v_cat_id IS NULL THEN
      INSERT INTO product_category_master (merchant_id, name) VALUES (v_mid, r.name) RETURNING id INTO v_cat_id;
    END IF;
    INSERT INTO custom_ausiris_demo_config (kind, code, payload)
    VALUES ('category', r.name, jsonb_build_object('id', v_cat_id))
    ON CONFLICT (kind, code) DO UPDATE SET payload = EXCLUDED.payload, updated_at = now();
  END LOOP;

  -- Products + SKUs
  FOR r IN SELECT * FROM (VALUES
    ('AUS-SPOT-965-025B', 'ทอง 96.5% 0.25 บาท', 'Ausiris Next', 'Gold Trading', 10500::numeric, 'spot_gold'),
    ('AUS-SPOT-965-050B', 'ทอง 96.5% 0.50 บาท', 'Ausiris Next', 'Gold Trading', 21000, 'spot_gold'),
    ('AUS-SPOT-965-1B', 'ทอง 96.5% 1 บาท', 'Ausiris Next', 'Gold Trading', 42000, 'spot_gold'),
    ('AUS-SPOT-965-2B', 'ทอง 96.5% 2 บาท', 'Ausiris Next', 'Gold Trading', 84000, 'spot_gold'),
    ('AUS-SPOT-999-1B', 'ทอง 99.99% 1 บาท', 'Ausiris Next', 'Gold Trading', 43500, 'spot_gold'),
    ('AUS-SAVE-DCA-500', 'ออมทองรายเดือน ฿500', 'My Gold Plus', 'Gold Saving', 500, 'gold_saving'),
    ('AUS-SAVE-DCA-1000', 'ออมทองรายเดือน ฿1,000', 'My Gold Plus', 'Gold Saving', 1000, 'gold_saving'),
    ('AUS-SAVE-DCA-3000', 'ออมทองรายเดือน ฿3,000', 'My Gold Plus', 'Gold Saving', 3000, 'gold_saving'),
    ('AUS-SAVE-LUMP-10K', 'ออมก้อน ฿10,000', 'My Gold Plus', 'Gold Saving', 10000, 'gold_saving'),
    ('AUS-SAVE-LUMP-50K', 'ออมก้อน ฿50,000', 'My Gold Plus', 'Gold Saving', 50000, 'gold_saving'),
    ('AUS-BAR-1G', 'ทองแท่ง 1 กรัม', 'Ausiris Express', 'Gold Bar', 2800, 'small_bar'),
    ('AUS-BAR-5G', 'ทองแท่ง 5 กรัม', 'Ausiris Express', 'Gold Bar', 14000, 'small_bar'),
    ('AUS-BAR-1SL', 'ทองแท่ง 1 สลึง', 'Ausiris', 'Gold Bar', 10500, 'small_bar'),
    ('AUS-BAR-1B', 'ทองแท่ง 1 บาท', 'Ausiris', 'Gold Bar', 42500, 'small_bar'),
    ('AUS-BAR-2B', 'ทองแท่ง 2 บาท', 'Ausiris', 'Gold Bar', 85000, 'small_bar'),
    ('AUS-SLV-BAR-10G', 'เงินแท่ง 10 กรัม', 'Ausiris', 'Silver', 450, 'silver'),
    ('AUS-SLV-BAR-1KG', 'เงินแท่ง 1 กิโลกรัม', 'Ausiris', 'Silver', 42000, 'silver'),
    ('AUS-SLV-COIN-1OZ', 'เหรียญเงิน 1 ออนซ์', 'Ausiris', 'Silver', 1400, 'silver'),
    ('IRIS-NL-MOTHER', 'สร้อย Mother''s Day', 'Iris Jewel', 'Jewelry', 8900, 'jewelry'),
    ('IRIS-RG-MINI', 'แหวนมินิมอล', 'Iris Jewel', 'Jewelry', 3500, 'jewelry'),
    ('IRIS-BR-LIVE', 'กำไล Live drop', 'Iris Jewel', 'Jewelry', 6200, 'jewelry'),
    ('IRIS-ER-GIFT', 'ต่างหูของขวัญ', 'Iris Jewel', 'Jewelry', 2900, 'jewelry'),
    ('IRIS-NL-DAILY', 'สร้อยใส่ทุกวัน', 'Iris Jewel', 'Jewelry', 4500, 'jewelry')
  ) AS t(sku_code, sku_name, brand, category, price, lob)
  LOOP
    v_brand_id := (custom_ausiris_demo_cfg('brand', r.brand)->>'id')::uuid;
    v_cat_id := (custom_ausiris_demo_cfg('category', r.category)->>'id')::uuid;
    SELECT id INTO v_prod_id FROM product_master WHERE merchant_id = v_mid AND product_code = r.sku_code LIMIT 1;
    IF v_prod_id IS NULL THEN
      INSERT INTO product_master (merchant_id, product_code, name, brand_id, category_id, price)
      VALUES (v_mid, r.sku_code, r.sku_name, v_brand_id, v_cat_id, r.price)
      RETURNING id INTO v_prod_id;
    ELSE
      UPDATE product_master SET name = r.sku_name, brand_id = v_brand_id, category_id = v_cat_id, price = r.price, updated_at = now()
      WHERE id = v_prod_id;
    END IF;
    INSERT INTO product_sku_master (merchant_id, product_id, sku_code, name, price)
    VALUES (v_mid, v_prod_id, r.sku_code, r.sku_name, r.price)
    ON CONFLICT (sku_code, merchant_id) DO UPDATE
    SET name = EXCLUDED.name, price = EXCLUDED.price, product_id = EXCLUDED.product_id, updated_at = now();
    INSERT INTO custom_ausiris_demo_config (kind, code, payload)
    VALUES (
      'sku', r.sku_code,
      jsonb_build_object(
        'id', (SELECT id FROM product_sku_master WHERE merchant_id = v_mid AND sku_code = r.sku_code),
        'product_id', v_prod_id,
        'price', r.price,
        'lob', r.lob,
        'category', r.category
      )
    )
    ON CONFLICT (kind, code) DO UPDATE SET payload = EXCLUDED.payload, updated_at = now();
  END LOOP;

  -- Custom activity types
  FOR r IN SELECT * FROM (VALUES
    ('gold_price_view', 'Gold Price View'),
    ('price_alert_subscribe', 'Price Alert Subscribe'),
    ('kyc_complete', 'KYC Complete'),
    ('savings_deposit_confirm', 'Savings Deposit Confirm'),
    ('mission_progress', 'Mission Progress'),
    ('vending_dispense', 'Vending Dispense'),
    ('workshop_rsvp', 'Workshop RSVP')
  ) AS t(code, name)
  LOOP
    INSERT INTO activity_type_master (merchant_id, code, name, is_active)
    SELECT v_mid, r.code, r.name, true
    WHERE NOT EXISTS (
      SELECT 1 FROM activity_type_master a WHERE a.merchant_id = v_mid AND a.code = r.code
    );
    INSERT INTO custom_ausiris_demo_config (kind, code, payload)
    VALUES ('activity_type', r.code, jsonb_build_object(
      'id', (SELECT id FROM activity_type_master WHERE merchant_id = v_mid AND code = r.code LIMIT 1)
    ))
    ON CONFLICT (kind, code) DO UPDATE SET payload = EXCLUDED.payload, updated_at = now();
  END LOOP;

  INSERT INTO custom_ausiris_demo_config (kind, code, payload)
  SELECT 'activity_type', code, jsonb_build_object('id', id)
  FROM activity_type_master
  WHERE merchant_id IS NULL AND code IN ('page_view', 'link_click', 'campaign_touch')
  ON CONFLICT (kind, code) DO UPDATE SET payload = EXCLUDED.payload, updated_at = now();

  -- Personas
  SELECT id INTO v_pg FROM persona_group_master WHERE merchant_id = v_mid AND group_name = 'Ausiris Customers' LIMIT 1;
  IF v_pg IS NULL THEN
    INSERT INTO persona_group_master (merchant_id, group_name, user_type, active_status)
    VALUES (v_mid, 'Ausiris Customers', 'buyer', true)
    RETURNING id INTO v_pg;
  END IF;
  FOR r IN SELECT * FROM (VALUES
    ('Gold Trader', 'aus-trader'),
    ('Gold Saver', 'aus-saver'),
    ('Bar & Gift', 'aus-bar'),
    ('Jewelry', 'aus-jewel'),
    ('Lapsed Investor', 'aus-lapsed')
  ) AS t(pname, pcode)
  LOOP
    INSERT INTO persona_master (merchant_id, group_id, persona_name, code, active_status)
    VALUES (v_mid, v_pg, r.pname, r.pcode, true)
    ON CONFLICT (merchant_id, persona_name) DO UPDATE SET code = EXCLUDED.code, active_status = true, updated_at = now();
    INSERT INTO custom_ausiris_demo_config (kind, code, payload)
    VALUES ('persona', r.pcode, jsonb_build_object(
      'id', (SELECT id FROM persona_master WHERE merchant_id = v_mid AND code = r.pcode LIMIT 1)
    ))
    ON CONFLICT (kind, code) DO UPDATE SET payload = EXCLUDED.payload, updated_at = now();
  END LOOP;

  -- Tags
  FOR r IN SELECT * FROM (VALUES
    ('VIP Trader'), ('New Member'), ('At Risk'), ('Saver Streak'),
    ('App Engager'), ('Marketplace Shopper'), ('Hibernating'), ('Lost')
  ) AS t(tname)
  LOOP
    INSERT INTO tag_master (merchant_id, tag_name, description, active_status)
    VALUES (v_mid, r.tname, r.tname, true)
    ON CONFLICT (merchant_id, tag_name) DO UPDATE SET active_status = true, updated_at = now();
    INSERT INTO custom_ausiris_demo_config (kind, code, payload)
    VALUES ('tag', r.tname, jsonb_build_object(
      'id', (SELECT id FROM tag_master WHERE merchant_id = v_mid AND tag_name = r.tname LIMIT 1)
    ))
    ON CONFLICT (kind, code) DO UPDATE SET payload = EXCLUDED.payload, updated_at = now();
  END LOOP;

  -- Reward points conditions on existing 7 rewards (do not recreate rewards)
  FOR v_reward IN
    SELECT id, name FROM reward_master WHERE merchant_id = v_mid
  LOOP
    v_pts := CASE
      WHEN v_reward.name ILIKE '%Shopee%' OR v_reward.name ILIKE '%Lazada%' THEN 200
      WHEN v_reward.name ILIKE '%Starbucks%' OR v_reward.name ILIKE '%Central%' THEN 500
      WHEN v_reward.name ILIKE '%E-Coupon%' OR v_reward.name ILIKE '%100 บาท%' THEN 800
      WHEN v_reward.name ILIKE '%Stamping%' THEN 300
      WHEN v_reward.name ILIKE '%50%' THEN 1500
      ELSE 200
    END;
    IF NOT EXISTS (
      SELECT 1 FROM reward_points_conditions c
      WHERE c.reward_id = v_reward.id AND c.merchant_id = v_mid
        AND c.tier_id IS NULL AND c.user_type = 'buyer' AND c.persona_id IS NULL
    ) THEN
      INSERT INTO reward_points_conditions (
        reward_id, merchant_id, user_type, points_required, condition_name, active_status, priority
      ) VALUES (
        v_reward.id, v_mid, 'buyer', v_pts, 'All buyers', true, 1
      );
    ELSE
      UPDATE reward_points_conditions
      SET points_required = v_pts, active_status = true, updated_at = now()
      WHERE reward_id = v_reward.id AND merchant_id = v_mid AND tier_id IS NULL AND user_type = 'buyer';
    END IF;
    INSERT INTO custom_ausiris_demo_config (kind, code, payload)
    VALUES ('reward', v_reward.name, jsonb_build_object('id', v_reward.id, 'points', v_pts))
    ON CONFLICT (kind, code) DO UPDATE SET payload = EXCLUDED.payload, updated_at = now();
  END LOOP;

  -- Marketing campaigns (9 flights)
  DELETE FROM mkt_campaign_identifier i
  USING mkt_campaign c
  WHERE i.campaign_id = c.id AND c.merchant_id = v_mid;
  DELETE FROM mkt_campaign WHERE merchant_id = v_mid;
  FOR r IN SELECT * FROM (VALUES
    ('aus-line-gold', 'LINE Gold Saving Push', 'line', 120000::numeric, -170, -10, 'strong'),
    ('aus-fb-mother', 'Facebook Mother''s Day Gold', 'facebook', 150000, -90, -60, 'strong'),
    ('aus-g-brand', 'Google Brand Ausiris', 'google', 180000, -180, -5, 'strong'),
    ('aus-email-wb', 'Email Win-back Investors', 'email', 80000, -100, -5, 'medium'),
    ('aus-ws-series', 'Gold Workshop Series', 'event', 60000, -120, -20, 'medium'),
    ('aus-tt-teaser', 'TikTok Gold Teaser', 'tiktok', 800000, -180, 0, 'weak'),
    ('aus-line-bar', 'LINE ทองเล็ก Express', 'line', 100000, -150, -8, 'strong'),
    ('aus-tt-live', 'TikTok Iris Live', 'tiktok', 90000, -80, -15, 'medium'),
    ('aus-pay-day', 'Payday Gold Top-up', 'line', 70000, -160, 0, 'strong')
  ) AS t(code, name, channel, budget, start_off, end_off, roi)
  LOOP
    INSERT INTO mkt_campaign (
      merchant_id, name, channel, status, budget_amount, window_start, window_end
    ) VALUES (
      v_mid, r.name, r.channel, 'active', r.budget,
      (current_date + r.start_off)::timestamptz,
      (current_date + r.end_off + 1)::timestamptz
    ) RETURNING id INTO v_mkt_id;
    INSERT INTO mkt_campaign_identifier (merchant_id, campaign_id, key_type, key_value)
    VALUES
      (v_mid, v_mkt_id, 'utm_campaign', r.code),
      (v_mid, v_mkt_id, 'line_param', r.code);
    INSERT INTO custom_ausiris_demo_config (kind, code, payload)
    VALUES ('mkt', r.code, jsonb_build_object('id', v_mkt_id, 'name', r.name, 'roi', r.roi, 'channel', r.channel))
    ON CONFLICT (kind, code) DO UPDATE SET payload = EXCLUDED.payload, updated_at = now();
  END LOOP;

  INSERT INTO mkt_config (merchant_id, attribution_model, attribution_lookback_days)
  VALUES (v_mid, 'u_shape', 30)
  ON CONFLICT (merchant_id) DO UPDATE
  SET attribution_model = 'u_shape', attribution_lookback_days = 30, updated_at = now();

  DELETE FROM rfm_config WHERE merchant_id = v_mid;
  INSERT INTO rfm_config (merchant_id, is_active, recency_source, window_months, segment_map)
  VALUES (v_mid, true, 'purchase', 12, fn_rfm_default_segment_map());

  -- Earn studio: 10 THB = 1 pt, Gold+ 1.5x, weekend jewelry+bar multiplier
  DELETE FROM earn_factor_group WHERE merchant_id = v_mid AND name = 'Ausiris Gold Earn';
  v_earn_res := create_complete_earn_factor_setup(
    v_mid,
    jsonb_build_object(
      'window_start', (current_date - 200)::timestamptz,
      'window_end', NULL,
      'active_status', true,
      'stackable', true
    ),
    jsonb_build_array(
      jsonb_build_object(
        'earn_factor_type', 'rate',
        'earn_factor_amount', 10,
        'target_currency', 'points',
        'active_status', true,
        'public', true,
        'allowed_purchase_statuses', jsonb_build_array('completed'),
        'condition_group_name', 'Ausiris base all tiers',
        'conditions', jsonb_build_array(jsonb_build_object(
          'entity', 'tier',
          'entity_ids', jsonb_build_array(v_tier_silver, v_tier_gold, v_tier_plat)
        ))
      ),
      jsonb_build_object(
        'earn_factor_type', 'multiplier',
        'earn_factor_amount', 1.5,
        'target_currency', 'points',
        'active_status', true,
        'public', true,
        'allowed_purchase_statuses', jsonb_build_array('completed'),
        'condition_group_name', 'Ausiris Gold+ boost',
        'conditions', jsonb_build_array(jsonb_build_object(
          'entity', 'tier',
          'entity_ids', jsonb_build_array(v_tier_gold, v_tier_plat)
        ))
      ),
      jsonb_build_object(
        'earn_factor_type', 'multiplier',
        'earn_factor_amount', 1.2,
        'target_currency', 'points',
        'active_status', true,
        'public', true,
        'allowed_purchase_statuses', jsonb_build_array('completed'),
        'condition_group_name', 'Weekend bar & jewelry',
        'has_time_conditions', true,
        'time_conditions', jsonb_build_array(
          jsonb_build_object(
            'day_of_week', jsonb_build_array(0, 6),
            'hour_start', 0,
            'hour_end', 23,
            'timezone', 'Asia/Bangkok'
          )
        ),
        'conditions', jsonb_build_array(jsonb_build_object(
          'entity', 'product_category',
          'entity_ids', jsonb_build_array(
            (custom_ausiris_demo_cfg('category', 'Gold Bar')->>'id')::uuid,
            (custom_ausiris_demo_cfg('category', 'Jewelry')->>'id')::uuid
          )
        ))
      )
    ),
    true
  );
  UPDATE earn_factor_group
  SET name = 'Ausiris Gold Earn', perspective = 'buyer'
  WHERE merchant_id = v_mid AND id = (
    SELECT id FROM earn_factor_group WHERE merchant_id = v_mid ORDER BY created_at DESC LIMIT 1
  );
  PERFORM refresh_earn_factors_complete();

  RETURN jsonb_build_object(
    'success', true,
    'skus', (SELECT count(*) FROM product_sku_master WHERE merchant_id = v_mid),
    'stores', (SELECT count(*) FROM store_master WHERE merchant_id = v_mid),
    'mkt', (SELECT count(*) FROM mkt_campaign WHERE merchant_id = v_mid),
    'earn', v_earn_res,
    'channels', (
      SELECT count(*) FROM earn_channel
      WHERE merchant_id = v_mid AND channel_code IN
        ('trading','gold_saving','web','pos','vending','marketplace','live')
    )
  );
END;
$fn$;

-- Sales-channel + business-unit store attributes. One CHANNEL value per store (is_store_channel).
CREATE OR REPLACE FUNCTION public.custom_ausiris_demo_bootstrap_store_channels()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $fn$
DECLARE
  v_mid uuid := custom_ausiris_demo_merchant_id();
  v_ch_cat uuid;
  v_bu_cat uuid;
  v_attr uuid;
  v_ch_map jsonb := '{}'::jsonb;
  v_bu_map jsonb := '{}'::jsonb;
  r record;
BEGIN
  PERFORM custom_ausiris_demo_set_ctx();

  INSERT INTO earn_channel (
    merchant_id, channel_code, channel_name, channel_type, method_type,
    active, display_order, is_system, marketplace_platforms
  )
  SELECT v_mid, x.code, x.name, 'purchase', x.method, true, x.ord, false, x.mkp
  FROM (VALUES
    ('trading', 'Ausiris Next (Trading)', 'api', 1, NULL::text[]),
    ('gold_saving', 'My Gold Plus', 'api', 2, NULL::text[]),
    ('web', 'Ausiris Express', 'api', 3, NULL::text[]),
    ('pos', 'In-store POS', 'api', 4, NULL::text[]),
    ('vending', 'Vending', 'api', 5, NULL::text[]),
    ('marketplace', 'Marketplace', 'marketplace_code', 6, ARRAY['shopee','lazada','tiktok']::text[]),
    ('live', 'Iris Jewel Live', 'api', 7, NULL::text[])
  ) AS x(code, name, method, ord, mkp)
  ON CONFLICT (merchant_id, channel_code) DO UPDATE
  SET channel_name = EXCLUDED.channel_name,
      channel_type = 'purchase',
      method_type = EXCLUDED.method_type,
      active = true,
      display_order = EXCLUDED.display_order,
      marketplace_platforms = EXCLUDED.marketplace_platforms,
      updated_at = now();

  UPDATE earn_channel
  SET active = false, updated_at = now()
  WHERE merchant_id = v_mid AND channel_code = 'app';

  INSERT INTO custom_ausiris_demo_config (kind, code, payload)
  SELECT 'id', 'earn_channel_' || e.channel_code, jsonb_build_object('id', e.id)
  FROM earn_channel e
  WHERE e.merchant_id = v_mid
    AND e.channel_code IN ('trading','gold_saving','web','pos','vending','marketplace','live')
  ON CONFLICT (kind, code) DO UPDATE SET payload = EXCLUDED.payload, updated_at = now();

  INSERT INTO store_attribute_categories (
    merchant_id, attribute_category_code, attribute_category_name, is_store_channel, is_store_property, is_deleted
  ) VALUES (
    v_mid, 'CHANNEL', 'Sales Channel', true, false, false
  )
  ON CONFLICT (merchant_id, attribute_category_code) DO UPDATE
  SET attribute_category_name = EXCLUDED.attribute_category_name,
      is_store_channel = true,
      is_deleted = false,
      updated_at = now()
  RETURNING id INTO v_ch_cat;

  IF v_ch_cat IS NULL THEN
    SELECT id INTO v_ch_cat
    FROM store_attribute_categories
    WHERE merchant_id = v_mid AND attribute_category_code = 'CHANNEL';
  END IF;

  INSERT INTO store_attribute_categories (
    merchant_id, attribute_category_code, attribute_category_name, is_store_channel, is_store_property, is_deleted
  ) VALUES (
    v_mid, 'BUSINESS_UNIT', 'Business Unit', false, false, false
  )
  ON CONFLICT (merchant_id, attribute_category_code) DO UPDATE
  SET attribute_category_name = EXCLUDED.attribute_category_name,
      is_store_channel = false,
      is_deleted = false,
      updated_at = now()
  RETURNING id INTO v_bu_cat;

  IF v_bu_cat IS NULL THEN
    SELECT id INTO v_bu_cat
    FROM store_attribute_categories
    WHERE merchant_id = v_mid AND attribute_category_code = 'BUSINESS_UNIT';
  END IF;

  FOR r IN
    SELECT * FROM (VALUES
      ('TRADING_PLATFORM', 'Trading Platform'),
      ('GOLD_SAVING_APP', 'Gold Saving App'),
      ('EXPRESS_WEB', 'Express Web'),
      ('IN_STORE_POS', 'In-store POS'),
      ('VENDING', 'Vending'),
      ('MARKETPLACE', 'Marketplace'),
      ('LIVE_COMMERCE', 'Live Commerce')
    ) AS t(code, name)
  LOOP
    INSERT INTO store_attributes (merchant_id, category_id, attribute_code, attribute_name, is_deleted)
    VALUES (v_mid, v_ch_cat, r.code, r.name, false)
    ON CONFLICT (merchant_id, category_id, attribute_code) DO UPDATE
    SET attribute_name = EXCLUDED.attribute_name, is_deleted = false, updated_at = now()
    RETURNING id INTO v_attr;
    IF v_attr IS NULL THEN
      SELECT id INTO v_attr FROM store_attributes
      WHERE merchant_id = v_mid AND category_id = v_ch_cat AND attribute_code = r.code;
    END IF;
    v_ch_map := v_ch_map || jsonb_build_object(r.code, v_attr);
  END LOOP;

  FOR r IN
    SELECT * FROM (VALUES
      ('AUSIRIS_NEXT', 'Ausiris Next'),
      ('MY_GOLD_PLUS', 'My Gold Plus'),
      ('AUSIRIS_EXPRESS', 'Ausiris Express'),
      ('AUSIRIS_GOLD', 'Ausiris Gold'),
      ('AUSIRIS_SILVER', 'Ausiris Silver'),
      ('IRIS_JEWEL', 'Iris Jewel')
    ) AS t(code, name)
  LOOP
    INSERT INTO store_attributes (merchant_id, category_id, attribute_code, attribute_name, is_deleted)
    VALUES (v_mid, v_bu_cat, r.code, r.name, false)
    ON CONFLICT (merchant_id, category_id, attribute_code) DO UPDATE
    SET attribute_name = EXCLUDED.attribute_name, is_deleted = false, updated_at = now()
    RETURNING id INTO v_attr;
    IF v_attr IS NULL THEN
      SELECT id INTO v_attr FROM store_attributes
      WHERE merchant_id = v_mid AND category_id = v_bu_cat AND attribute_code = r.code;
    END IF;
    v_bu_map := v_bu_map || jsonb_build_object(r.code, v_attr);
  END LOOP;

  DELETE FROM store_attribute_assignments
  WHERE merchant_id = v_mid AND category_id IN (v_ch_cat, v_bu_cat);

  FOR r IN
    SELECT sm.id AS store_id, x.ch, x.bu
    FROM store_master sm
    JOIN (VALUES
      ('AUS-NEXT-APP', 'TRADING_PLATFORM', 'AUSIRIS_NEXT'),
      ('AUS-PLUS-APP', 'GOLD_SAVING_APP', 'MY_GOLD_PLUS'),
      ('AUS-EXPRESS-WEB', 'EXPRESS_WEB', 'AUSIRIS_EXPRESS'),
      ('AUS-POS-SILOM', 'IN_STORE_POS', 'AUSIRIS_GOLD'),
      ('AUS-POS-SIAM', 'IN_STORE_POS', 'AUSIRIS_GOLD'),
      ('AUS-POS-CNX', 'IN_STORE_POS', 'AUSIRIS_GOLD'),
      ('AUS-POS-SLV-TDP', 'IN_STORE_POS', 'AUSIRIS_SILVER'),
      ('AUS-VD-TDP', 'VENDING', 'AUSIRIS_SILVER'),
      ('AUS-SHOPEE', 'MARKETPLACE', 'AUSIRIS_EXPRESS'),
      ('AUS-LAZADA', 'MARKETPLACE', 'AUSIRIS_EXPRESS'),
      ('AUS-TIKTOK', 'MARKETPLACE', 'IRIS_JEWEL'),
      ('AUS-IRIS-LIVE', 'LIVE_COMMERCE', 'IRIS_JEWEL')
    ) AS x(store_code, ch, bu) ON x.store_code = sm.store_code
    WHERE sm.merchant_id = v_mid
  LOOP
    INSERT INTO store_attribute_assignments (merchant_id, store_id, category_id, attribute_id)
    VALUES (v_mid, r.store_id, v_ch_cat, (v_ch_map ->> r.ch)::uuid)
    ON CONFLICT (merchant_id, store_id, category_id) DO UPDATE
    SET attribute_id = EXCLUDED.attribute_id, assigned_at = now();

    INSERT INTO store_attribute_assignments (merchant_id, store_id, category_id, attribute_id)
    VALUES (v_mid, r.store_id, v_bu_cat, (v_bu_map ->> r.bu)::uuid)
    ON CONFLICT (merchant_id, store_id, category_id) DO UPDATE
    SET attribute_id = EXCLUDED.attribute_id, assigned_at = now();
  END LOOP;

  INSERT INTO custom_ausiris_demo_config (kind, code, payload)
  VALUES (
    'id', 'store_channels',
    jsonb_build_object(
      'channel_category_id', v_ch_cat,
      'business_unit_category_id', v_bu_cat,
      'channels', v_ch_map,
      'business_units', v_bu_map
    )
  )
  ON CONFLICT (kind, code) DO UPDATE SET payload = EXCLUDED.payload, updated_at = now();

  RETURN jsonb_build_object(
    'success', true,
    'channel_attrs', 7,
    'business_units', 6,
    'assignments', (
      SELECT count(*) FROM store_attribute_assignments
      WHERE merchant_id = v_mid AND category_id IN (v_ch_cat, v_bu_cat)
    )
  );
END;
$fn$;
