-- Missions, native leaderboards, grouping campaigns, funnel, AMP audiences.

CREATE OR REPLACE FUNCTION public.custom_ausiris_demo_bootstrap_engagement()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $fn$
DECLARE
  v_mid uuid := custom_ausiris_demo_merchant_id();
  v_save_cat uuid := (custom_ausiris_demo_cfg('category', 'Gold Saving')->>'id')::uuid;
  v_bar_cat uuid := (custom_ausiris_demo_cfg('category', 'Gold Bar')->>'id')::uuid;
  v_trade_cat uuid := (custom_ausiris_demo_cfg('category', 'Gold Trading')->>'id')::uuid;
  v_jewel_cat uuid := (custom_ausiris_demo_cfg('category', 'Jewelry')->>'id')::uuid;
  v_bar_1g uuid := (custom_ausiris_demo_cfg('sku', 'AUS-BAR-1G')->>'id')::uuid;
  v_bar_5g uuid := (custom_ausiris_demo_cfg('sku', 'AUS-BAR-5G')->>'id')::uuid;
  v_rw_stamp uuid;
  v_rw_shopee uuid;
  v_rw_first uuid;
  v_rw_ecoup uuid;
  v_rw_central uuid;
  v_rw_sbux uuid;
  v_mid_save uuid;
  v_mid_bar uuid;
  v_mid_trade uuid;
  v_mid_bar1 uuid;
  v_mid_jewel uuid;
  v_mid_cross uuid;
  v_mid_mile uuid;
  v_mid_pay uuid;
  v_funnel jsonb;
  v_funnel_id uuid;
  v_aud jsonb;
  v_camp uuid;
  v_act uuid;
  r record;
  v_save_skus uuid[];
  v_bar_skus uuid[];
  v_jewel_skus uuid[];
  v_tag_app uuid := (custom_ausiris_demo_cfg('tag', 'App Engager')->>'id')::uuid;
  v_tag_vip uuid := (custom_ausiris_demo_cfg('tag', 'VIP Trader')->>'id')::uuid;
  v_tag_risk uuid := (custom_ausiris_demo_cfg('tag', 'At Risk')->>'id')::uuid;
  v_tag_hib uuid := (custom_ausiris_demo_cfg('tag', 'Hibernating')->>'id')::uuid;
  v_tag_lost uuid := (custom_ausiris_demo_cfg('tag', 'Lost')->>'id')::uuid;
  v_tier_gold uuid := (custom_ausiris_demo_cfg('id', 'tier_gold')->>'id')::uuid;
  v_tier_plat uuid := (custom_ausiris_demo_cfg('id', 'tier_plat')->>'id')::uuid;
  v_stage_lead uuid;
  v_stage_fp uuid;
  v_stage_prog uuid;
BEGIN
  PERFORM custom_ausiris_demo_set_ctx();

  SELECT (payload->>'id')::uuid INTO v_rw_stamp FROM custom_ausiris_demo_config WHERE kind = 'reward' AND code ILIKE '%Stamping%' LIMIT 1;
  SELECT (payload->>'id')::uuid INTO v_rw_shopee FROM custom_ausiris_demo_config WHERE kind = 'reward' AND code ILIKE '%Shopee%' LIMIT 1;
  SELECT (payload->>'id')::uuid INTO v_rw_first FROM custom_ausiris_demo_config WHERE kind = 'reward' AND code ILIKE '%50%' LIMIT 1;
  SELECT (payload->>'id')::uuid INTO v_rw_ecoup FROM custom_ausiris_demo_config WHERE kind = 'reward' AND code ILIKE '%E-Coupon%' LIMIT 1;
  SELECT (payload->>'id')::uuid INTO v_rw_central FROM custom_ausiris_demo_config WHERE kind = 'reward' AND code ILIKE '%Central%' LIMIT 1;
  SELECT (payload->>'id')::uuid INTO v_rw_sbux FROM custom_ausiris_demo_config WHERE kind = 'reward' AND code ILIKE '%Starbucks%' LIMIT 1;

  SELECT array_agg((payload->>'id')::uuid) INTO v_save_skus FROM custom_ausiris_demo_config WHERE kind = 'sku' AND payload->>'lob' = 'gold_saving';
  SELECT array_agg((payload->>'id')::uuid) INTO v_bar_skus FROM custom_ausiris_demo_config WHERE kind = 'sku' AND payload->>'lob' = 'small_bar';
  SELECT array_agg((payload->>'id')::uuid) INTO v_jewel_skus FROM custom_ausiris_demo_config WHERE kind = 'sku' AND payload->>'lob' = 'jewelry';

  -- Replace prior Ausiris missions
  DELETE FROM mission_log_completion mlc USING mission m WHERE mlc.mission_id = m.id AND m.merchant_id = v_mid AND m.mission_code LIKE 'aus-%';
  DELETE FROM mission_progress mp USING mission m WHERE mp.mission_id = m.id AND m.merchant_id = v_mid AND m.mission_code LIKE 'aus-%';
  DELETE FROM mission_outcomes mo USING mission m WHERE mo.mission_id = m.id AND m.merchant_id = v_mid AND m.mission_code LIKE 'aus-%';
  DELETE FROM mission_conditions mc USING mission m WHERE mc.mission_id = m.id AND m.merchant_id = v_mid AND m.mission_code LIKE 'aus-%';
  DELETE FROM mission WHERE merchant_id = v_mid AND mission_code LIKE 'aus-%';

  INSERT INTO mission (merchant_id, mission_code, mission_name, mission_description, mission_type, progress_activation_type, claim_type, is_active, start_date, end_date, allow_progress_loop, description_goal)
  VALUES (v_mid, 'aus-save-3m', 'ออมต่อเนื่อง 3 เดือน', 'ออมทอง 3 ครั้ง', 'standard', 'auto', 'auto', true, (current_date-180)::timestamptz, (current_date+90)::timestamptz, false, '3× Gold Saving')
  RETURNING id INTO v_mid_save;
  INSERT INTO mission_conditions (mission_id, operator, condition_type, measurement_type, target_value, category_ids, description)
  VALUES (v_mid_save, 'AND', 'purchase', 'count', 3, ARRAY[v_save_cat], 'Gold Saving count');
  INSERT INTO mission_outcomes (mission_id, outcome_type, amount) VALUES (v_mid_save, 'points', 300);
  IF v_rw_stamp IS NOT NULL THEN
    INSERT INTO mission_outcomes (mission_id, outcome_type, amount, entity_id) VALUES (v_mid_save, 'reward', 1, v_rw_stamp);
  END IF;

  INSERT INTO mission (merchant_id, mission_code, mission_name, mission_description, mission_type, progress_activation_type, claim_type, is_active, start_date, end_date, allow_progress_loop, description_goal)
  VALUES (v_mid, 'aus-bar-collect', 'ทองเล็กสะสม', 'ซื้อทอง 1g หรือ 5g สองครั้ง', 'standard', 'auto', 'auto', true, (current_date-180)::timestamptz, (current_date+90)::timestamptz, false, '2× small bar')
  RETURNING id INTO v_mid_bar;
  INSERT INTO mission_conditions (mission_id, operator, condition_type, measurement_type, target_value, sku_ids, description)
  VALUES (v_mid_bar, 'AND', 'purchase', 'count', 2, ARRAY[v_bar_1g, v_bar_5g], '1g/5g bars');
  INSERT INTO mission_outcomes (mission_id, outcome_type, amount) VALUES (v_mid_bar, 'points', 150);
  IF v_rw_shopee IS NOT NULL THEN
    INSERT INTO mission_outcomes (mission_id, outcome_type, amount, entity_id) VALUES (v_mid_bar, 'reward', 1, v_rw_shopee);
  END IF;

  INSERT INTO mission (merchant_id, mission_code, mission_name, mission_description, mission_type, progress_activation_type, claim_type, is_active, start_date, end_date, allow_progress_loop, description_goal)
  VALUES (v_mid, 'aus-first-trade', 'นักลงทุนเริ่มต้น', 'ซื้อทองคำแท่งเทรดครั้งแรก', 'standard', 'auto', 'auto', true, (current_date-180)::timestamptz, (current_date+90)::timestamptz, false, '1× Gold Trading')
  RETURNING id INTO v_mid_trade;
  INSERT INTO mission_conditions (mission_id, operator, condition_type, measurement_type, target_value, category_ids, description)
  VALUES (v_mid_trade, 'AND', 'purchase', 'count', 1, ARRAY[v_trade_cat], 'Gold Trading');
  INSERT INTO mission_outcomes (mission_id, outcome_type, amount) VALUES (v_mid_trade, 'points', 200);
  IF v_rw_first IS NOT NULL THEN
    INSERT INTO mission_outcomes (mission_id, outcome_type, amount, entity_id) VALUES (v_mid_trade, 'reward', 1, v_rw_first);
  END IF;

  INSERT INTO mission (merchant_id, mission_code, mission_name, mission_description, mission_type, progress_activation_type, claim_type, is_active, start_date, end_date, allow_progress_loop, description_goal)
  VALUES (v_mid, 'aus-bar-1b', 'ซื้อทองครบ 1 บาท', 'ยอดซื้อทองแท่ง ฿50,000', 'standard', 'auto', 'auto', true, (current_date-180)::timestamptz, (current_date+90)::timestamptz, false, 'Gold Bar spend ฿50k')
  RETURNING id INTO v_mid_bar1;
  INSERT INTO mission_conditions (mission_id, operator, condition_type, measurement_type, target_value, category_ids, min_transaction_amount, description)
  VALUES (v_mid_bar1, 'AND', 'purchase', 'sum', 50000, ARRAY[v_bar_cat], 0, 'Gold Bar sum');
  INSERT INTO mission_outcomes (mission_id, outcome_type, amount) VALUES (v_mid_bar1, 'points', 400);

  INSERT INTO mission (merchant_id, mission_code, mission_name, mission_description, mission_type, progress_activation_type, claim_type, is_active, start_date, end_date, allow_progress_loop, description_goal)
  VALUES (v_mid, 'aus-iris-gift', 'ของขวัญ Iris', 'ซื้อเครื่องประดับ Iris 1 ชิ้น', 'standard', 'auto', 'auto', true, (current_date-180)::timestamptz, (current_date+90)::timestamptz, false, '1× Jewelry')
  RETURNING id INTO v_mid_jewel;
  INSERT INTO mission_conditions (mission_id, operator, condition_type, measurement_type, target_value, category_ids, description)
  VALUES (v_mid_jewel, 'AND', 'purchase', 'count', 1, ARRAY[v_jewel_cat], 'Jewelry');
  INSERT INTO mission_outcomes (mission_id, outcome_type, amount) VALUES (v_mid_jewel, 'points', 100);
  IF v_rw_ecoup IS NOT NULL THEN
    INSERT INTO mission_outcomes (mission_id, outcome_type, amount, entity_id) VALUES (v_mid_jewel, 'reward', 1, v_rw_ecoup);
  END IF;

  INSERT INTO mission (merchant_id, mission_code, mission_name, mission_description, mission_type, progress_activation_type, claim_type, is_active, start_date, end_date, allow_progress_loop, description_goal)
  VALUES (v_mid, 'aus-cross', 'ข้ามไลน์ (ออม+แท่ง)', 'ออมทองและซื้อแท่งในโปรแกรมเดียวกัน', 'standard', 'auto', 'auto', true, (current_date-180)::timestamptz, (current_date+90)::timestamptz, false, 'saving AND bar')
  RETURNING id INTO v_mid_cross;
  INSERT INTO mission_conditions (mission_id, operator, condition_type, measurement_type, target_value, category_ids, description) VALUES
    (v_mid_cross, 'AND', 'purchase', 'count', 1, ARRAY[v_save_cat], 'Saving'),
    (v_mid_cross, 'AND', 'purchase', 'count', 1, ARRAY[v_bar_cat], 'Bar');
  INSERT INTO mission_outcomes (mission_id, outcome_type, amount) VALUES (v_mid_cross, 'points', 250);

  INSERT INTO mission (merchant_id, mission_code, mission_name, mission_description, mission_type, progress_activation_type, claim_type, is_active, start_date, end_date, allow_progress_loop, description_goal)
  VALUES (v_mid, 'aus-spend-ms', 'Milestone ยอดซื้อ', 'ยอดซื้อ 10k / 50k / 200k', 'milestone', 'auto', 'auto', true, (current_date-180)::timestamptz, (current_date+90)::timestamptz, false, 'Spend milestones')
  RETURNING id INTO v_mid_mile;
  INSERT INTO mission_conditions (mission_id, operator, condition_type, measurement_type, target_value, milestone_level, milestone_name, milestone_display_order, description) VALUES
    (v_mid_mile, 'AND', 'purchase', 'sum', 10000, 1, '10k', 1, '฿10k'),
    (v_mid_mile, 'AND', 'purchase', 'sum', 50000, 2, '50k', 2, '฿50k'),
    (v_mid_mile, 'AND', 'purchase', 'sum', 200000, 3, '200k', 3, '฿200k');
  INSERT INTO mission_outcomes (mission_id, outcome_type, amount, milestone_level) VALUES
    (v_mid_mile, 'points', 50, 1),
    (v_mid_mile, 'points', 200, 2),
    (v_mid_mile, 'points', 1000, 3);

  INSERT INTO mission (merchant_id, mission_code, mission_name, mission_description, mission_type, progress_activation_type, claim_type, is_active, start_date, end_date, allow_progress_loop, description_goal)
  VALUES (v_mid, 'aus-payday-dca', 'เงินเดือนออม', 'ออม DCA ในเดือนปฏิทิน', 'recurring', 'auto', 'auto', true, (current_date-180)::timestamptz, (current_date+90)::timestamptz, true, '1× DCA / month')
  RETURNING id INTO v_mid_pay;
  INSERT INTO mission_conditions (mission_id, operator, condition_type, measurement_type, target_value, sku_ids, description)
  VALUES (v_mid_pay, 'AND', 'purchase', 'count', 1,
    ARRAY[(custom_ausiris_demo_cfg('sku','AUS-SAVE-DCA-500')->>'id')::uuid,
          (custom_ausiris_demo_cfg('sku','AUS-SAVE-DCA-1000')->>'id')::uuid,
          (custom_ausiris_demo_cfg('sku','AUS-SAVE-DCA-3000')->>'id')::uuid],
    'DCA sku');
  INSERT INTO mission_outcomes (mission_id, outcome_type, amount) VALUES (v_mid_pay, 'points', 80);

  INSERT INTO custom_ausiris_demo_config (kind, code, payload) VALUES
    ('mission', 'aus-save-3m', jsonb_build_object('id', v_mid_save)),
    ('mission', 'aus-bar-collect', jsonb_build_object('id', v_mid_bar)),
    ('mission', 'aus-first-trade', jsonb_build_object('id', v_mid_trade)),
    ('mission', 'aus-bar-1b', jsonb_build_object('id', v_mid_bar1)),
    ('mission', 'aus-iris-gift', jsonb_build_object('id', v_mid_jewel)),
    ('mission', 'aus-cross', jsonb_build_object('id', v_mid_cross)),
    ('mission', 'aus-spend-ms', jsonb_build_object('id', v_mid_mile)),
    ('mission', 'aus-payday-dca', jsonb_build_object('id', v_mid_pay))
  ON CONFLICT (kind, code) DO UPDATE SET payload = EXCLUDED.payload, updated_at = now();

  EXECUTE $v$
    CREATE OR REPLACE VIEW public.v_lb_ausiris_gold_spend AS
    SELECT pl.merchant_id, pl.user_id,
           split_part(ua.fullname, ' ', 1) AS display_name,
           ua.lastname,
           ua.tel AS phone_masked,
           SUM(pl.final_amount)::numeric AS gold_spend
    FROM purchase_ledger pl
    JOIN user_accounts ua ON ua.id = pl.user_id
    JOIN purchase_items_ledger pil ON pil.transaction_id = pl.id
    JOIN product_sku_master sku ON sku.id = pil.sku_id
    JOIN product_master pm ON pm.id = sku.product_id
    JOIN product_category_master pc ON pc.id = pm.category_id
    WHERE pl.status = 'completed'
      AND COALESCE(pl.completed_at, pl.transaction_date) >= current_date - 180
      AND pc.name IN ('Gold Trading', 'Gold Bar')
    GROUP BY pl.merchant_id, pl.user_id, ua.fullname, ua.lastname, ua.tel
  $v$;
  EXECUTE $v$
    CREATE OR REPLACE VIEW public.v_lb_ausiris_saving_streak AS
    SELECT pl.merchant_id, pl.user_id,
           split_part(ua.fullname, ' ', 1) AS display_name,
           ua.lastname,
           ua.tel AS phone_masked,
           COUNT(*)::integer AS saving_count
    FROM purchase_ledger pl
    JOIN user_accounts ua ON ua.id = pl.user_id
    JOIN purchase_items_ledger pil ON pil.transaction_id = pl.id
    JOIN product_sku_master sku ON sku.id = pil.sku_id
    JOIN product_master pm ON pm.id = sku.product_id
    JOIN product_category_master pc ON pc.id = pm.category_id
    WHERE pl.status = 'completed'
      AND COALESCE(pl.completed_at, pl.transaction_date) >= current_date - 180
      AND pc.name = 'Gold Saving'
    GROUP BY pl.merchant_id, pl.user_id, ua.fullname, ua.lastname, ua.tel
  $v$;

  DELETE FROM campaign_leaderboard WHERE merchant_id = v_mid AND path IN ('ausiris-gold-ranking', 'ausiris-saving-ranking');
  DELETE FROM campaign_master WHERE merchant_id = v_mid AND campaign_code IN ('aus-lb-gold', 'aus-lb-save');
  INSERT INTO campaign_master (merchant_id, campaign_name, campaign_code)
  VALUES (v_mid, 'Ausiris Gold Ranking', 'aus-lb-gold'), (v_mid, 'Ausiris Saving Streak', 'aus-lb-save');
  INSERT INTO campaign_leaderboard (
    merchant_id, campaign_code, path, datawh_table_code, source_kind, user_key_field,
    columns_config, rank_config, top_x, requires_participation, active_status,
    page_header, page_description, color_primary
  ) VALUES
  (
    v_mid, 'aus-lb-gold', 'ausiris-gold-ranking', 'v_lb_ausiris_gold_spend', 'native', 'user_id',
    '[{"field":"display_name","label":"ชื่อ","order":0,"visible":true,"mask_enabled":true,"mask_char_count":2},{"field":"gold_spend","label":"ยอดซื้อทอง","order":1,"visible":true,"mask_enabled":false,"mask_char_count":0}]'::jsonb,
    '{"field":"gold_spend","direction":"desc"}'::jsonb, 20, false, true,
    'จัดอันดับยอดซื้อทอง', '180 วัน เทรดและแท่ง', '#BCA48D'
  ),
  (
    v_mid, 'aus-lb-save', 'ausiris-saving-ranking', 'v_lb_ausiris_saving_streak', 'native', 'user_id',
    '[{"field":"display_name","label":"ชื่อ","order":0,"visible":true,"mask_enabled":true,"mask_char_count":2},{"field":"saving_count","label":"ครั้งที่ออม","order":1,"visible":true,"mask_enabled":false,"mask_char_count":0}]'::jsonb,
    '{"field":"saving_count","direction":"desc"}'::jsonb, 20, false, true,
    'สายออมทอง', '180 วัน My Gold Plus', '#4B4A58'
  );

  -- Grouping campaigns
  DELETE FROM campaign_mapping cm USING campaign_activity ca, campaign c
    WHERE cm.campaign_activity_id = ca.id AND ca.campaign_id = c.id AND c.merchant_id = v_mid;
  DELETE FROM campaign_activity ca USING campaign c WHERE ca.campaign_id = c.id AND c.merchant_id = v_mid;
  DELETE FROM campaign WHERE merchant_id = v_mid;

  INSERT INTO campaign (merchant_id, name, is_active) VALUES (v_mid, 'หาลูกค้าใหม่', true) RETURNING id INTO v_camp;
  INSERT INTO campaign_activity (merchant_id, campaign_id, name, is_active) VALUES (v_mid, v_camp, 'Acquisition', true) RETURNING id INTO v_act;
  INSERT INTO campaign_mapping (merchant_id, campaign_activity_id, activity_type, entity_id) VALUES
    (v_mid, v_act, 'mission', v_mid_trade),
    (v_mid, v_act, 'reward', v_rw_first);

  INSERT INTO campaign (merchant_id, name, is_active) VALUES (v_mid, 'รักษาลูกค้าออมทอง', true) RETURNING id INTO v_camp;
  INSERT INTO campaign_activity (merchant_id, campaign_id, name, is_active) VALUES (v_mid, v_camp, 'Retention saving', true) RETURNING id INTO v_act;
  INSERT INTO campaign_mapping (merchant_id, campaign_activity_id, activity_type, entity_id) VALUES
    (v_mid, v_act, 'mission', v_mid_save),
    (v_mid, v_act, 'mission', v_mid_pay),
    (v_mid, v_act, 'reward', v_rw_stamp);

  INSERT INTO campaign (merchant_id, name, is_active) VALUES (v_mid, 'ดันสินค้าแท่งและจิวเวล', true) RETURNING id INTO v_camp;
  INSERT INTO campaign_activity (merchant_id, campaign_id, name, is_active) VALUES (v_mid, v_camp, 'Product push', true) RETURNING id INTO v_act;
  INSERT INTO campaign_mapping (merchant_id, campaign_activity_id, activity_type, entity_id) VALUES
    (v_mid, v_act, 'mission', v_mid_bar),
    (v_mid, v_act, 'mission', v_mid_jewel),
    (v_mid, v_act, 'reward', v_rw_shopee),
    (v_mid, v_act, 'reward', v_rw_ecoup);

  INSERT INTO campaign (merchant_id, name, is_active) VALUES (v_mid, 'วินแบ็คและ VIP', true) RETURNING id INTO v_camp;
  INSERT INTO campaign_activity (merchant_id, campaign_id, name, is_active) VALUES (v_mid, v_camp, 'Win-back VIP', true) RETURNING id INTO v_act;
  INSERT INTO campaign_mapping (merchant_id, campaign_activity_id, activity_type, entity_id) VALUES
    (v_mid, v_act, 'mission', v_mid_mile),
    (v_mid, v_act, 'reward', v_rw_central),
    (v_mid, v_act, 'reward', v_rw_sbux);

  -- Funnel
  DELETE FROM funnel_transition_ledger ftl USING funnel_master fm WHERE ftl.funnel_id = fm.id AND fm.merchant_id = v_mid;
  UPDATE amp_audience_master SET funnel_id = NULL, funnel_sort_order = NULL
  WHERE merchant_id = v_mid AND funnel_id IN (SELECT id FROM funnel_master WHERE merchant_id = v_mid);
  DELETE FROM funnel_master WHERE merchant_id = v_mid AND name = 'Ausiris Gold Customer Journey';

  v_funnel := bff_upsert_funnel(
    NULL,
    'Ausiris Gold Customer Journey',
    'Gold customer journey, latest-stage-wins',
    true,
    jsonb_build_array(
      jsonb_build_object(
        'name', 'Lead', 'sort_order', 1,
        'conditions', jsonb_build_object('groups_operator', 'AND', 'groups', jsonb_build_array(
          jsonb_build_object('id', 'g1', 'type', 'simple', 'collection', 'user_accounts',
            'conditions', jsonb_build_array(jsonb_build_object('field', 'is_active', 'operator', 'equals', 'value', true)))
        ))
      ),
      jsonb_build_object(
        'name', 'Engaged', 'sort_order', 2,
        'conditions', jsonb_build_object('groups_operator', 'AND', 'groups', jsonb_build_array(
          jsonb_build_object('id', 'g1', 'type', 'simple', 'collection', 'user_tags',
            'conditions', jsonb_build_array(jsonb_build_object('field', 'tag_id', 'operator', 'equals', 'value', v_tag_app)))
        ))
      ),
      jsonb_build_object(
        'name', 'First Purchase', 'sort_order', 3,
        'conditions', jsonb_build_object('groups_operator', 'AND', 'groups', jsonb_build_array(
          jsonb_build_object('id', 'g1', 'type', 'aggregate', 'collection', 'purchase_ledger',
            'aggregate', 'count', 'field', 'id', 'operator', 'gte', 'value', 1,
            'time_field', 'created_at', 'time_range', '12 months', 'filters', '[]'::jsonb)
        ))
      ),
      jsonb_build_object(
        'name', 'Repeat Buyer', 'sort_order', 4,
        'conditions', jsonb_build_object('groups_operator', 'AND', 'groups', jsonb_build_array(
          jsonb_build_object('id', 'g1', 'type', 'aggregate', 'collection', 'purchase_ledger',
            'aggregate', 'count', 'field', 'id', 'operator', 'gte', 'value', 2,
            'time_field', 'created_at', 'time_range', '12 months', 'filters', '[]'::jsonb)
        ))
      ),
      jsonb_build_object(
        'name', 'Program Member', 'sort_order', 5,
        'conditions', jsonb_build_object('groups_operator', 'OR', 'groups', jsonb_build_array(
          jsonb_build_object('id', 'g1', 'type', 'simple', 'collection', 'user_accounts',
            'conditions', jsonb_build_array(jsonb_build_object('field', 'tier_id', 'operator', 'in',
              'value', jsonb_build_array(v_tier_gold, v_tier_plat)))),
          jsonb_build_object('id', 'g2', 'type', 'aggregate', 'collection', 'purchase_items_ledger',
            'aggregate', 'count', 'field', 'id', 'operator', 'gte', 'value', 1,
            'time_field', 'created_at', 'time_range', '12 months',
            'join', jsonb_build_object('table', 'purchase_ledger', 'on', jsonb_build_object('local', 'transaction_id', 'foreign', 'id')),
            'filters', jsonb_build_array(jsonb_build_object('field', 'sku', 'operator', 'in', 'value', to_jsonb(v_save_skus)))),
          jsonb_build_object('id', 'g3', 'type', 'aggregate', 'collection', 'mission_log_completion',
            'aggregate', 'count', 'field', 'id', 'operator', 'gte', 'value', 1,
            'time_field', 'completed_at', 'time_range', '12 months', 'filters', '[]'::jsonb)
        ))
      )
    )
  );
  IF NOT COALESCE((v_funnel->>'success')::boolean, false) THEN
    RETURN jsonb_build_object('success', false, 'error', 'funnel', 'detail', v_funnel);
  END IF;
  v_funnel_id := COALESCE((v_funnel->>'funnel_id')::uuid, (v_funnel->>'id')::uuid);
  IF v_funnel_id IS NULL THEN
    SELECT id INTO v_funnel_id FROM funnel_master WHERE merchant_id = v_mid AND name = 'Ausiris Gold Customer Journey' LIMIT 1;
  END IF;
  INSERT INTO custom_ausiris_demo_config (kind, code, payload)
  VALUES ('id', 'funnel', jsonb_build_object('id', v_funnel_id, 'raw', v_funnel))
  ON CONFLICT (kind, code) DO UPDATE SET payload = EXCLUDED.payload, updated_at = now();

  SELECT id INTO v_stage_lead FROM amp_audience_master WHERE merchant_id = v_mid AND funnel_id = v_funnel_id AND funnel_sort_order = 1;
  SELECT id INTO v_stage_fp FROM amp_audience_master WHERE merchant_id = v_mid AND funnel_id = v_funnel_id AND funnel_sort_order = 3;
  SELECT id INTO v_stage_prog FROM amp_audience_master WHERE merchant_id = v_mid AND funnel_id = v_funnel_id AND funnel_sort_order = 5;

  -- AMP audiences (rule-only). RFM segments use tags stamped after compute.
  DELETE FROM amp_audience_member aam USING amp_audience_master a
    WHERE aam.audience_id = a.id AND a.merchant_id = v_mid AND a.funnel_id IS NULL AND a.name LIKE 'Ausiris %';
  -- leave funnel audiences; delete non-funnel Ausiris-named ones via bff would drop workflows — skip wipe if already present

  v_aud := bff_create_audience('Ausiris VIP exclusive', 'Champions or Platinum',
    jsonb_build_object('groups_operator', 'OR', 'groups', jsonb_build_array(
      jsonb_build_object('id','g1','type','simple','collection','user_accounts','conditions',
        jsonb_build_array(jsonb_build_object('field','tier_id','operator','equals','value', v_tier_plat))),
      jsonb_build_object('id','g2','type','simple','collection','user_tags','conditions',
        jsonb_build_array(jsonb_build_object('field','tag_id','operator','equals','value', v_tag_vip)))
    )), 'dynamic');
  v_aud := bff_create_audience('Ausiris Savers special', 'Program + saving 90d',
    jsonb_build_object('groups_operator', 'AND', 'groups', jsonb_build_array(
      jsonb_build_object('id','g1','type','simple','collection','amp_audience_member','conditions',
        jsonb_build_array(jsonb_build_object('field','audience_id','operator','is_member_of','value', v_stage_prog::text))),
      jsonb_build_object('id','g2','type','aggregate','collection','purchase_items_ledger','aggregate','count','field','id','operator','gte','value',1,
        'time_field','created_at','time_range','90 days',
        'join', jsonb_build_object('table','purchase_ledger','on', jsonb_build_object('local','transaction_id','foreign','id')),
        'filters', jsonb_build_array(jsonb_build_object('field','sku','operator','in','value', to_jsonb(v_save_skus))))
    )), 'dynamic');
  v_aud := bff_create_audience('Ausiris Bar / mission', 'Bar purchase or bar mission 60d',
    jsonb_build_object('groups_operator', 'OR', 'groups', jsonb_build_array(
      jsonb_build_object('id','g1','type','aggregate','collection','purchase_items_ledger','aggregate','count','field','id','operator','gte','value',1,
        'time_field','created_at','time_range','60 days',
        'join', jsonb_build_object('table','purchase_ledger','on', jsonb_build_object('local','transaction_id','foreign','id')),
        'filters', jsonb_build_array(jsonb_build_object('field','sku','operator','in','value', to_jsonb(v_bar_skus)))),
      jsonb_build_object('id','g2','type','aggregate','collection','mission_log_completion','aggregate','count','field','id','operator','gte','value',1,
        'time_field','completed_at','time_range','60 days',
        'filters', jsonb_build_array(jsonb_build_object('field','mission_id','operator','equals','value', v_mid_bar)))
    )), 'dynamic');
  v_aud := bff_create_audience('Ausiris Jewelry 30d', 'Jewelry purchase 30d',
    jsonb_build_object('groups_operator', 'AND', 'groups', jsonb_build_array(
      jsonb_build_object('id','g1','type','aggregate','collection','purchase_items_ledger','aggregate','count','field','id','operator','gte','value',1,
        'time_field','created_at','time_range','30 days',
        'join', jsonb_build_object('table','purchase_ledger','on', jsonb_build_object('local','transaction_id','foreign','id')),
        'filters', jsonb_build_array(jsonb_build_object('field','sku','operator','in','value', to_jsonb(v_jewel_skus))))
    )), 'dynamic');
  v_aud := bff_create_audience('Ausiris Win-back', 'RFM At Risk tag',
    jsonb_build_object('groups_operator', 'AND', 'groups', jsonb_build_array(
      jsonb_build_object('id','g1','type','simple','collection','user_tags','conditions',
        jsonb_build_array(jsonb_build_object('field','tag_id','operator','equals','value', v_tag_risk)))
    )), 'dynamic');
  v_aud := bff_create_audience('Ausiris Reactivation', 'Hibernating or Lost tag',
    jsonb_build_object('groups_operator', 'OR', 'groups', jsonb_build_array(
      jsonb_build_object('id','g1','type','simple','collection','user_tags','conditions',
        jsonb_build_array(jsonb_build_object('field','tag_id','operator','equals','value', v_tag_hib))),
      jsonb_build_object('id','g2','type','simple','collection','user_tags','conditions',
        jsonb_build_array(jsonb_build_object('field','tag_id','operator','equals','value', v_tag_lost)))
    )), 'dynamic');
  v_aud := bff_create_audience('Ausiris High-intent unpaid', 'App engager with no purchases',
    jsonb_build_object('groups_operator', 'AND', 'groups', jsonb_build_array(
      jsonb_build_object('id','g1','type','simple','collection','user_tags','conditions',
        jsonb_build_array(jsonb_build_object('field','tag_id','operator','equals','value', v_tag_app))),
      jsonb_build_object('id','g2','type','aggregate','collection','purchase_ledger','aggregate','count','field','id','operator','eq','value',0,
        'time_field','created_at','time_range','12 months','filters','[]'::jsonb)
    )), 'dynamic');
  v_aud := bff_create_audience('Ausiris Welcome', 'Lead signup ≤14d',
    jsonb_build_object('groups_operator', 'AND', 'groups', jsonb_build_array(
      jsonb_build_object('id','g1','type','simple','collection','amp_audience_member','conditions',
        jsonb_build_array(jsonb_build_object('field','audience_id','operator','is_member_of','value', v_stage_lead::text))),
      jsonb_build_object('id','g2','type','simple','collection','user_accounts','conditions',
        jsonb_build_array(jsonb_build_object('field','created_at','operator','greater_or_equal','value', (current_date - 14)::text)))
    )), 'dynamic');
  v_aud := bff_create_audience('Ausiris Convert to repeat', 'Funnel First Purchase',
    jsonb_build_object('groups_operator', 'AND', 'groups', jsonb_build_array(
      jsonb_build_object('id','g1','type','simple','collection','amp_audience_member','conditions',
        jsonb_build_array(jsonb_build_object('field','audience_id','operator','is_member_of','value', v_stage_fp::text)))
    )), 'dynamic');

  RETURN jsonb_build_object(
    'success', true,
    'missions', (SELECT count(*) FROM mission WHERE merchant_id = v_mid AND mission_code LIKE 'aus-%'),
    'funnel', v_funnel_id,
    'grouping', (SELECT count(*) FROM campaign WHERE merchant_id = v_mid)
  );
END;
$fn$;
