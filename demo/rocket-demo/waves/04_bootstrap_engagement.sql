-- One-time engagement masters for Rocket Demo (personas, earn studio, missions, spin, surveys).
-- Does NOT wipe existing tiers/products/purchases. Idempotent by SEED-RKT codes.
CREATE OR REPLACE FUNCTION public.custom_internal_demo_bootstrap_engagement()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $fn$
DECLARE
  v_settings jsonb := custom_internal_demo_settings();
  v_merchant_id uuid;
  v_group_id uuid;
  v_persona_beauty uuid;
  v_persona_skincare uuid;
  v_persona_gift uuid;
  v_persona_wellness uuid;
  v_tag_vip uuid;
  v_tag_new uuid;
  v_tag_risk uuid;
  v_tag_fragrance uuid;
  v_tag_app uuid;
  v_tier_member uuid;
  v_tier_silver uuid;
  v_tier_gold uuid;
  v_tier_plat uuid;
  v_cat_treat uuid;
  v_cat_protect uuid;
  v_cat_cleanse uuid;
  v_earn_result jsonb;
  v_earn_group_id uuid;
  v_form_pref uuid;
  v_form_nps uuid;
  v_fg_pref uuid;
  v_fg_nps uuid;
  v_ff_interest uuid;
  v_ff_category uuid;
  v_ff_concern uuid;
  v_ff_nps uuid;
  v_ff_comment uuid;
  v_mission_spend uuid;
  v_mission_survey uuid;
  v_mission_mile uuid;
  v_cond_id uuid;
  v_spin_weekend uuid;
  v_spin_festive uuid;
  v_seg uuid;
  v_reward_v50 uuid;
  v_counts jsonb := '{}'::jsonb;
BEGIN
  IF v_settings IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'settings missing');
  END IF;
  v_merchant_id := (v_settings->>'merchant_id')::uuid;

  SELECT id INTO v_tier_member FROM tier_master WHERE merchant_id = v_merchant_id AND tier_name = 'Member' LIMIT 1;
  SELECT id INTO v_tier_silver FROM tier_master WHERE merchant_id = v_merchant_id AND tier_name = 'Silver' LIMIT 1;
  SELECT id INTO v_tier_gold FROM tier_master WHERE merchant_id = v_merchant_id AND tier_name = 'Gold' LIMIT 1;
  SELECT id INTO v_tier_plat FROM tier_master WHERE merchant_id = v_merchant_id AND tier_name = 'Platinum' LIMIT 1;
  SELECT id INTO v_cat_treat FROM product_category_master WHERE merchant_id = v_merchant_id AND name = 'Treat' LIMIT 1;
  SELECT id INTO v_cat_protect FROM product_category_master WHERE merchant_id = v_merchant_id AND name = 'Protect' LIMIT 1;
  SELECT id INTO v_cat_cleanse FROM product_category_master WHERE merchant_id = v_merchant_id AND name = 'Cleanse' LIMIT 1;
  SELECT id INTO v_reward_v50 FROM reward_master WHERE merchant_id = v_merchant_id AND reward_code = 'RKT-V50' LIMIT 1;

  IF v_tier_member IS NULL OR v_cat_treat IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'tiers/categories missing — run custom_internal_demo_bootstrap_merchant first');
  END IF;

  -- ── Personas ──────────────────────────────────────────────
  UPDATE user_accounts ua
  SET persona_id = NULL
  FROM persona_master pm
  WHERE ua.persona_id = pm.id AND pm.merchant_id = v_merchant_id AND pm.code LIKE 'rkt-%';
  DELETE FROM persona_master WHERE merchant_id = v_merchant_id AND code LIKE 'rkt-%';
  DELETE FROM persona_group_master WHERE merchant_id = v_merchant_id AND group_name = 'Lifestyle Shoppers';

  INSERT INTO persona_group_master (merchant_id, group_name, user_type, active_status)
  VALUES (v_merchant_id, 'Lifestyle Shoppers', 'buyer', true)
  RETURNING id INTO v_group_id;

  INSERT INTO persona_master (merchant_id, group_id, persona_name, code, active_status)
  VALUES (v_merchant_id, v_group_id, 'Beauty Enthusiast', 'rkt-beauty', true)
  RETURNING id INTO v_persona_beauty;
  INSERT INTO persona_master (merchant_id, group_id, persona_name, code, active_status)
  VALUES (v_merchant_id, v_group_id, 'Skincare Routine', 'rkt-skincare', true)
  RETURNING id INTO v_persona_skincare;
  INSERT INTO persona_master (merchant_id, group_id, persona_name, code, active_status)
  VALUES (v_merchant_id, v_group_id, 'Gift Shopper', 'rkt-gift', true)
  RETURNING id INTO v_persona_gift;
  INSERT INTO persona_master (merchant_id, group_id, persona_name, code, active_status)
  VALUES (v_merchant_id, v_group_id, 'Wellness Seeker', 'rkt-wellness', true)
  RETURNING id INTO v_persona_wellness;

  -- ── Tags ──────────────────────────────────────────────────
  DELETE FROM user_tags ut USING tag_master t
  WHERE ut.tag_id = t.id AND t.merchant_id = v_merchant_id AND t.tag_name LIKE 'SEED-RKT %';
  DELETE FROM tag_master WHERE merchant_id = v_merchant_id AND tag_name LIKE 'SEED-RKT %';

  INSERT INTO tag_master (merchant_id, tag_name, description, active_status)
  VALUES (v_merchant_id, 'SEED-RKT VIP', 'High-value lifestyle members', true)
  RETURNING id INTO v_tag_vip;
  INSERT INTO tag_master (merchant_id, tag_name, description, active_status)
  VALUES (v_merchant_id, 'SEED-RKT New Member', 'Joined in last 30 days', true)
  RETURNING id INTO v_tag_new;
  INSERT INTO tag_master (merchant_id, tag_name, description, active_status)
  VALUES (v_merchant_id, 'SEED-RKT At Risk', 'Quiet for 60+ days after prior purchase', true)
  RETURNING id INTO v_tag_risk;
  INSERT INTO tag_master (merchant_id, tag_name, description, active_status)
  VALUES (v_merchant_id, 'SEED-RKT Fragrance Lover', 'Affinity for fragrance / scent products', true)
  RETURNING id INTO v_tag_fragrance;
  INSERT INTO tag_master (merchant_id, tag_name, description, active_status)
  VALUES (v_merchant_id, 'SEED-RKT App Engager', 'Active in app / engagement', true)
  RETURNING id INTO v_tag_app;

  -- ── Earn Studio ───────────────────────────────────────────
  -- Clean prior seed earn graph
  DELETE FROM earn_factor_time_conditions eft
  USING earn_factor ef
  WHERE eft.earn_factor_id = ef.id AND ef.merchant_id = v_merchant_id
    AND ef.earn_factor_group_id IN (
      SELECT id FROM earn_factor_group WHERE merchant_id = v_merchant_id AND name = 'Rocket Club Earning 2026'
    );
  DELETE FROM earn_factor_user efu
  USING earn_factor ef
  WHERE efu.earn_factor_id = ef.id AND ef.merchant_id = v_merchant_id
    AND ef.earn_factor_group_id IN (
      SELECT id FROM earn_factor_group WHERE merchant_id = v_merchant_id AND name = 'Rocket Club Earning 2026'
    );
  DELETE FROM earn_factor
  WHERE merchant_id = v_merchant_id
    AND earn_factor_group_id IN (
      SELECT id FROM earn_factor_group WHERE merchant_id = v_merchant_id AND name = 'Rocket Club Earning 2026'
    );
  DELETE FROM earn_conditions
  WHERE merchant_id = v_merchant_id
    AND group_id IN (
      SELECT id FROM earn_conditions_group WHERE merchant_id = v_merchant_id AND name LIKE 'SEED-RKT %'
    );
  DELETE FROM earn_conditions_group
  WHERE merchant_id = v_merchant_id AND name LIKE 'SEED-RKT %';
  DELETE FROM earn_factor_group
  WHERE merchant_id = v_merchant_id AND name = 'Rocket Club Earning 2026';

  v_earn_result := create_complete_earn_factor_setup(
    v_merchant_id,
    jsonb_build_object(
      'window_start', (current_date - 200)::timestamptz,
      'window_end', null,
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
        'condition_group_name', 'SEED-RKT Base All Tiers',
        'conditions', jsonb_build_array(
          jsonb_build_object(
            'entity', 'tier',
            'entity_ids', jsonb_build_array(v_tier_member, v_tier_silver, v_tier_gold, v_tier_plat)
          )
        )
      ),
      jsonb_build_object(
        'earn_factor_type', 'multiplier',
        'earn_factor_amount', 1.5,
        'target_currency', 'points',
        'active_status', true,
        'public', true,
        'allowed_purchase_statuses', jsonb_build_array('completed'),
        'condition_group_name', 'SEED-RKT Gold+ Tier Boost',
        'conditions', jsonb_build_array(
          jsonb_build_object(
            'entity', 'tier',
            'entity_ids', jsonb_build_array(v_tier_gold, v_tier_plat)
          )
        )
      ),
      jsonb_build_object(
        'earn_factor_type', 'multiplier',
        'earn_factor_amount', 2,
        'target_currency', 'points',
        'active_status', true,
        'public', true,
        'allowed_purchase_statuses', jsonb_build_array('completed'),
        'has_time_conditions', true,
        'condition_group_name', 'SEED-RKT Treat & Protect Promo',
        'conditions', jsonb_build_array(
          jsonb_build_object(
            'entity', 'product_category',
            'entity_ids', jsonb_build_array(v_cat_treat, v_cat_protect, v_cat_cleanse)
          )
        ),
        'time_conditions', jsonb_build_array(
          jsonb_build_object(
            'day_of_week', jsonb_build_array(0, 6),
            'hour_start', 0,
            'hour_end', 23,
            'timezone', 'Asia/Bangkok'
          )
        )
      )
    ),
    true
  );

  -- create_complete_earn_factor_setup does not always set name; stamp the newest group
  SELECT id INTO v_earn_group_id
  FROM earn_factor_group
  WHERE merchant_id = v_merchant_id
  ORDER BY created_at DESC
  LIMIT 1;

  UPDATE earn_factor_group
  SET name = 'Rocket Club Earning 2026', perspective = 'buyer'
  WHERE id = v_earn_group_id;

  IF coalesce((v_earn_result->>'success')::boolean, false) IS DISTINCT FROM true
     AND v_earn_result ? 'error' THEN
    RETURN jsonb_build_object('success', false, 'error', 'earn setup failed', 'detail', v_earn_result);
  END IF;

  PERFORM refresh_earn_factors_complete();

  -- ── Surveys ───────────────────────────────────────────────
  DELETE FROM form_responses fr
  USING form_submissions fs, form_templates ft
  WHERE fr.submission_id = fs.id AND fs.form_id = ft.id
    AND ft.merchant_id = v_merchant_id AND ft.code LIKE 'seed-rkt-%';
  DELETE FROM form_submissions fs
  USING form_templates ft
  WHERE fs.form_id = ft.id AND ft.merchant_id = v_merchant_id AND ft.code LIKE 'seed-rkt-%';
  DELETE FROM form_field_options fo
  USING form_fields ff, form_templates ft
  WHERE fo.field_id = ff.id AND ff.form_id = ft.id
    AND ft.merchant_id = v_merchant_id AND ft.code LIKE 'seed-rkt-%';
  DELETE FROM form_fields ff
  USING form_templates ft
  WHERE ff.form_id = ft.id AND ft.merchant_id = v_merchant_id AND ft.code LIKE 'seed-rkt-%';
  DELETE FROM form_field_groups fg
  USING form_templates ft
  WHERE fg.form_id = ft.id AND ft.merchant_id = v_merchant_id AND ft.code LIKE 'seed-rkt-%';
  DELETE FROM form_templates
  WHERE merchant_id = v_merchant_id AND code LIKE 'seed-rkt-%';

  INSERT INTO form_templates (merchant_id, name, description, status, form_category, code)
  VALUES (
    v_merchant_id,
    'Product Preference Survey',
    'Tell us what you love so we can personalize Rocket Club.',
    'published',
    'survey',
    'seed-rkt-pref'
  ) RETURNING id INTO v_form_pref;

  INSERT INTO form_field_groups (form_id, group_key, group_name, order_index)
  VALUES (v_form_pref, 'prefs', 'Your preferences', 1)
  RETURNING id INTO v_fg_pref;

  INSERT INTO form_fields (form_id, group_id, field_key, label, field_type, order_index, is_required, merchant_id, visible_to_user, visible_to_admin)
  VALUES (v_form_pref, v_fg_pref, 'interests', 'What are you most interested in?', 'select', 1, true, v_merchant_id, true, true)
  RETURNING id INTO v_ff_interest;
  INSERT INTO form_field_options (field_id, option_value, option_label, order_index) VALUES
    (v_ff_interest, 'skincare', 'Skincare routines', 1),
    (v_ff_interest, 'makeup', 'Makeup & beauty', 2),
    (v_ff_interest, 'fragrance', 'Fragrance', 3),
    (v_ff_interest, 'wellness', 'Wellness & body', 4);

  INSERT INTO form_fields (form_id, group_id, field_key, label, field_type, order_index, is_required, merchant_id, visible_to_user, visible_to_admin)
  VALUES (v_form_pref, v_fg_pref, 'favorite_category', 'Favorite category', 'select', 2, true, v_merchant_id, true, true)
  RETURNING id INTO v_ff_category;
  INSERT INTO form_field_options (field_id, option_value, option_label, order_index) VALUES
    (v_ff_category, 'treat', 'Treat / serums', 1),
    (v_ff_category, 'protect', 'Protect / SPF', 2),
    (v_ff_category, 'cleanse', 'Cleanse', 3),
    (v_ff_category, 'body', 'Body', 4);

  INSERT INTO form_fields (form_id, group_id, field_key, label, field_type, order_index, is_required, merchant_id, visible_to_user, visible_to_admin)
  VALUES (v_form_pref, v_fg_pref, 'skin_concern', 'Main skin concern', 'select', 3, false, v_merchant_id, true, true)
  RETURNING id INTO v_ff_concern;
  INSERT INTO form_field_options (field_id, option_value, option_label, order_index) VALUES
    (v_ff_concern, 'dryness', 'Dryness', 1),
    (v_ff_concern, 'dullness', 'Dullness', 2),
    (v_ff_concern, 'acne', 'Acne-prone', 3),
    (v_ff_concern, 'aging', 'Aging / firmness', 4);

  INSERT INTO form_templates (merchant_id, name, description, status, form_category, code)
  VALUES (
    v_merchant_id,
    'Quick NPS',
    'How likely are you to recommend Rocket Club?',
    'published',
    'survey',
    'seed-rkt-nps'
  ) RETURNING id INTO v_form_nps;

  INSERT INTO form_field_groups (form_id, group_key, group_name, order_index)
  VALUES (v_form_nps, 'nps', 'Feedback', 1)
  RETURNING id INTO v_fg_nps;

  INSERT INTO form_fields (form_id, group_id, field_key, label, field_type, order_index, is_required, merchant_id, visible_to_user, visible_to_admin, min_value, max_value)
  VALUES (v_form_nps, v_fg_nps, 'nps_score', 'Score (0–10)', 'number', 1, true, v_merchant_id, true, true, 0, 10)
  RETURNING id INTO v_ff_nps;

  INSERT INTO form_fields (form_id, group_id, field_key, label, field_type, order_index, is_required, merchant_id, visible_to_user, visible_to_admin)
  VALUES (v_form_nps, v_fg_nps, 'comment', 'Anything else?', 'text', 2, false, v_merchant_id, true, true)
  RETURNING id INTO v_ff_comment;

  -- ── Missions ──────────────────────────────────────────────
  DELETE FROM mission_log_outcome_distribution mld
  USING mission m WHERE mld.mission_id = m.id AND m.merchant_id = v_merchant_id AND m.mission_code LIKE 'rkt-%';
  DELETE FROM mission_log_completion mlc
  USING mission m WHERE mlc.mission_id = m.id AND m.merchant_id = v_merchant_id AND m.mission_code LIKE 'rkt-%';
  DELETE FROM mission_progress mp
  USING mission m WHERE mp.mission_id = m.id AND m.merchant_id = v_merchant_id AND m.mission_code LIKE 'rkt-%';
  DELETE FROM mission_outcomes mo
  USING mission m WHERE mo.mission_id = m.id AND m.merchant_id = v_merchant_id AND m.mission_code LIKE 'rkt-%';
  DELETE FROM mission_conditions mc
  USING mission m WHERE mc.mission_id = m.id AND m.merchant_id = v_merchant_id AND m.mission_code LIKE 'rkt-%';
  DELETE FROM mission WHERE merchant_id = v_merchant_id AND mission_code LIKE 'rkt-%';

  INSERT INTO mission (
    merchant_id, mission_code, mission_name, mission_description, mission_type,
    progress_activation_type, claim_type, is_active,
    start_date, end_date, allow_progress_loop, description_goal
  ) VALUES (
    v_merchant_id, 'rkt-spend-3k', 'Spend ฿3,000 this season',
    'Shop any Rocket Club products and hit ฿3,000 to earn bonus points.',
    'standard', 'auto', 'auto', true,
    (current_date - 180)::timestamptz, (current_date + 90)::timestamptz, false,
    'Spend ฿3,000 across completed purchases'
  ) RETURNING id INTO v_mission_spend;

  INSERT INTO mission_conditions (
    mission_id, operator, condition_type, measurement_type, target_value, description
  ) VALUES (
    v_mission_spend, 'AND', 'purchase', 'sum', 3000, 'Cumulative purchase amount'
  ) RETURNING id INTO v_cond_id;

  INSERT INTO mission_outcomes (mission_id, outcome_type, amount)
  VALUES (v_mission_spend, 'points', 300);

  INSERT INTO mission (
    merchant_id, mission_code, mission_name, mission_description, mission_type,
    progress_activation_type, claim_type, is_active,
    start_date, end_date, allow_progress_loop, description_goal
  ) VALUES (
    v_merchant_id, 'rkt-survey-pref', 'Share your preferences',
    'Complete the Product Preference Survey and earn points.',
    'standard', 'auto', 'auto', true,
    (current_date - 180)::timestamptz, (current_date + 90)::timestamptz, false,
    'Submit the preference survey once'
  ) RETURNING id INTO v_mission_survey;

  INSERT INTO mission_conditions (
    mission_id, operator, condition_type, measurement_type, target_value, form_id, description
  ) VALUES (
    v_mission_survey, 'AND', 'form_submission', 'count', 1, v_form_pref, 'Preference survey submit'
  );

  INSERT INTO mission_outcomes (mission_id, outcome_type, amount)
  VALUES (v_mission_survey, 'points', 50);

  INSERT INTO mission (
    merchant_id, mission_code, mission_name, mission_description, mission_type,
    progress_activation_type, claim_type, is_active,
    start_date, end_date, allow_progress_loop, description_goal
  ) VALUES (
    v_merchant_id, 'rkt-milestone-shop', 'Shopping milestones',
    'Climb Bronze → Silver → Gold shopping levels.',
    'milestone', 'auto', 'auto', true,
    (current_date - 180)::timestamptz, (current_date + 90)::timestamptz, false,
    'Hit spend milestones for bonus points'
  ) RETURNING id INTO v_mission_mile;

  INSERT INTO mission_conditions (
    mission_id, operator, condition_type, measurement_type, target_value,
    milestone_level, milestone_name, milestone_display_order, description
  ) VALUES
    (v_mission_mile, 'AND', 'purchase', 'sum', 1000, 1, 'Bronze', 1, 'Spend ฿1,000'),
    (v_mission_mile, 'AND', 'purchase', 'sum', 3000, 2, 'Silver', 2, 'Spend ฿3,000'),
    (v_mission_mile, 'AND', 'purchase', 'sum', 8000, 3, 'Gold', 3, 'Spend ฿8,000');

  INSERT INTO mission_outcomes (mission_id, outcome_type, amount, milestone_level) VALUES
    (v_mission_mile, 'points', 50, 1),
    (v_mission_mile, 'points', 150, 2),
    (v_mission_mile, 'points', 400, 3);

  PERFORM refresh_mission_conditions_mv();

  -- ── Spin wheels ───────────────────────────────────────────
  DELETE FROM spin_wheel_log swl
  USING spin_wheel sw WHERE swl.spin_wheel_id = sw.id AND sw.merchant_id = v_merchant_id AND sw.name LIKE 'SEED-RKT %';
  DELETE FROM spin_wheel_segment_outcome so
  USING spin_wheel_segment ss, spin_wheel sw
  WHERE so.segment_id = ss.id AND ss.spin_wheel_id = sw.id AND sw.merchant_id = v_merchant_id AND sw.name LIKE 'SEED-RKT %';
  DELETE FROM spin_wheel_segment ss
  USING spin_wheel sw WHERE ss.spin_wheel_id = sw.id AND sw.merchant_id = v_merchant_id AND sw.name LIKE 'SEED-RKT %';
  DELETE FROM transaction_limits tl
  USING spin_wheel sw WHERE tl.entity_type = 'spin_wheel' AND tl.entity_id = sw.id
    AND sw.merchant_id = v_merchant_id AND sw.name LIKE 'SEED-RKT %';
  DELETE FROM spin_wheel WHERE merchant_id = v_merchant_id AND name LIKE 'SEED-RKT %';

  INSERT INTO spin_wheel (
    merchant_id, name, description, active_status,
    window_start, window_end, cost_currency, cost_amount, display_config
  ) VALUES (
    v_merchant_id, 'SEED-RKT Weekend Lucky Spin',
    'Spend 50 points for a weekend spin.',
    true, (current_date - 180)::timestamptz, (current_date + 90)::timestamptz,
    'points', 50, '{"theme":"weekend"}'::jsonb
  ) RETURNING id INTO v_spin_weekend;

  INSERT INTO spin_wheel_segment (merchant_id, spin_wheel_id, label, weight, is_no_win, display_order, active_status)
  VALUES (v_merchant_id, v_spin_weekend, '10 points', 40, false, 1, true)
  RETURNING id INTO v_seg;
  INSERT INTO spin_wheel_segment_outcome (merchant_id, segment_id, outcome_type, amount)
  VALUES (v_merchant_id, v_seg, 'points', 10);

  INSERT INTO spin_wheel_segment (merchant_id, spin_wheel_id, label, weight, is_no_win, display_order, active_status)
  VALUES (v_merchant_id, v_spin_weekend, '50 points', 25, false, 2, true)
  RETURNING id INTO v_seg;
  INSERT INTO spin_wheel_segment_outcome (merchant_id, segment_id, outcome_type, amount)
  VALUES (v_merchant_id, v_seg, 'points', 50);

  INSERT INTO spin_wheel_segment (merchant_id, spin_wheel_id, label, weight, is_no_win, display_order, active_status)
  VALUES (v_merchant_id, v_spin_weekend, '100 points', 10, false, 3, true)
  RETURNING id INTO v_seg;
  INSERT INTO spin_wheel_segment_outcome (merchant_id, segment_id, outcome_type, amount)
  VALUES (v_merchant_id, v_seg, 'points', 100);

  INSERT INTO spin_wheel_segment (merchant_id, spin_wheel_id, label, weight, is_no_win, display_order, active_status)
  VALUES (v_merchant_id, v_spin_weekend, 'Try again', 25, true, 4, true);

  INSERT INTO transaction_limits (merchant_id, entity_type, entity_id, scope, metric, count, time_unit, active_status)
  VALUES (v_merchant_id, 'spin_wheel', v_spin_weekend, 'user', 'quantity', 3, 'day', true);

  INSERT INTO spin_wheel (
    merchant_id, name, description, active_status,
    window_start, window_end, cost_currency, cost_amount, display_config
  ) VALUES (
    v_merchant_id, 'SEED-RKT Festive Prize Wheel',
    'Festive spins with vouchers and points.',
    true, (current_date - 90)::timestamptz, (current_date + 60)::timestamptz,
    'points', 80, '{"theme":"festive"}'::jsonb
  ) RETURNING id INTO v_spin_festive;

  INSERT INTO spin_wheel_segment (merchant_id, spin_wheel_id, label, weight, is_no_win, display_order, active_status)
  VALUES (v_merchant_id, v_spin_festive, '20 points', 35, false, 1, true)
  RETURNING id INTO v_seg;
  INSERT INTO spin_wheel_segment_outcome (merchant_id, segment_id, outcome_type, amount)
  VALUES (v_merchant_id, v_seg, 'points', 20);

  INSERT INTO spin_wheel_segment (merchant_id, spin_wheel_id, label, weight, is_no_win, display_order, active_status)
  VALUES (v_merchant_id, v_spin_festive, '฿50 Voucher', 15, false, 2, true)
  RETURNING id INTO v_seg;
  IF v_reward_v50 IS NOT NULL THEN
    INSERT INTO spin_wheel_segment_outcome (merchant_id, segment_id, outcome_type, entity_id, amount)
    VALUES (v_merchant_id, v_seg, 'reward', v_reward_v50, 1);
  ELSE
    INSERT INTO spin_wheel_segment_outcome (merchant_id, segment_id, outcome_type, amount)
    VALUES (v_merchant_id, v_seg, 'points', 80);
  END IF;

  INSERT INTO spin_wheel_segment (merchant_id, spin_wheel_id, label, weight, is_no_win, display_order, active_status)
  VALUES (v_merchant_id, v_spin_festive, '150 points', 15, false, 3, true)
  RETURNING id INTO v_seg;
  INSERT INTO spin_wheel_segment_outcome (merchant_id, segment_id, outcome_type, amount)
  VALUES (v_merchant_id, v_seg, 'points', 150);

  INSERT INTO spin_wheel_segment (merchant_id, spin_wheel_id, label, weight, is_no_win, display_order, active_status)
  VALUES (v_merchant_id, v_spin_festive, 'Better luck next time', 35, true, 4, true);

  INSERT INTO transaction_limits (merchant_id, entity_type, entity_id, scope, metric, count, time_unit, active_status)
  VALUES (v_merchant_id, 'spin_wheel', v_spin_festive, 'user', 'quantity', 2, 'day', true);

  -- Persist refs into settings
  UPDATE custom_internal_demo_config
  SET payload = payload || jsonb_build_object(
    'engagement_bootstrapped_at', now(),
    'persona_group_id', v_group_id,
    'persona_ids', jsonb_build_object(
      'beauty', v_persona_beauty,
      'skincare', v_persona_skincare,
      'gift', v_persona_gift,
      'wellness', v_persona_wellness
    ),
    'tag_ids', jsonb_build_object(
      'vip', v_tag_vip,
      'new_member', v_tag_new,
      'at_risk', v_tag_risk,
      'fragrance', v_tag_fragrance,
      'app_engager', v_tag_app
    ),
    'earn_factor_group_id', v_earn_group_id,
    'form_ids', jsonb_build_object(
      'preference', v_form_pref,
      'nps', v_form_nps
    ),
    'form_field_ids', jsonb_build_object(
      'interest', v_ff_interest,
      'favorite_category', v_ff_category,
      'skin_concern', v_ff_concern,
      'nps_score', v_ff_nps,
      'nps_comment', v_ff_comment
    ),
    'mission_ids', jsonb_build_object(
      'spend_3k', v_mission_spend,
      'survey_pref', v_mission_survey,
      'milestone_shop', v_mission_mile
    ),
    'spin_wheel_ids', jsonb_build_object(
      'weekend', v_spin_weekend,
      'festive', v_spin_festive
    )
  ),
  updated_at = now()
  WHERE kind = 'settings' AND code = 'default';

  v_counts := jsonb_build_object(
    'personas', 4,
    'tags', 5,
    'earn_setup', v_earn_result,
    'forms', 2,
    'missions', 3,
    'spin_wheels', 2
  );

  RETURN jsonb_build_object('success', true, 'merchant_id', v_merchant_id, 'counts', v_counts);
EXCEPTION WHEN OTHERS THEN
  RETURN jsonb_build_object('success', false, 'error', SQLERRM, 'state', SQLSTATE);
END;
$fn$;
