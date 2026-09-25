CREATE OR REPLACE FUNCTION public.custom_ausiris_demo_seed_ledgers()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $fn$
DECLARE
  v_mid uuid := custom_ausiris_demo_merchant_id();
  v_purch int;
  v_act int;
  v_wlt int;
  v_rdm int;
BEGIN
  PERFORM custom_ausiris_demo_set_ctx();

  -- Purchases + items (set-based)
  WITH members AS (
    SELECT
      u.id, u.created_at::date AS signup,
      u.acquisition_attribution->>'archetype' AS arch,
      u.acquisition_attribution->>'named' AS named,
      (cfg.payload->>'n_buy_min')::int AS nmin,
      (cfg.payload->>'n_buy_max')::int AS nmax,
      NULLIF(cfg.payload->>'last_buy_min_days','')::int AS last_min,
      NULLIF(cfg.payload->>'last_buy_max_days','')::int AS last_max
    FROM user_accounts u
    JOIN custom_ausiris_demo_config cfg ON cfg.kind = 'archetype' AND cfg.code = u.acquisition_attribution->>'archetype'
    WHERE u.merchant_id = v_mid AND u.external_user_id LIKE 'AUSV2-%'
  ),
  sized AS (
    SELECT m.*,
      CASE WHEN m.nmax = 0 THEN 0
           WHEN m.arch = 'loyal_saver' THEN GREATEST(m.nmin, LEAST(m.nmax, 1 + ((current_date - m.signup) / 30)))
           ELSE m.nmin + floor(custom_ausiris_demo_rand('nb-'||m.id::text) * (m.nmax - m.nmin + 1))::int
      END AS n_buys
    FROM members m
  ),
  exploded AS (
    SELECT s.*, gs AS buy_i,
      GREATEST(s.signup, current_date - COALESCE(s.last_max, 14)
        + floor(custom_ausiris_demo_rand('ld-'||s.id::text) * GREATEST(COALESCE(s.last_max,14) - COALESCE(s.last_min,1), 1) + 1)::int
      ) AS last_date
    FROM sized s
    CROSS JOIN LATERAL generate_series(1, GREATEST(s.n_buys, 0)) gs
    WHERE s.n_buys > 0
  ),
  dated AS (
    SELECT e.*,
      CASE WHEN e.n_buys = 1 THEN e.last_date
           ELSE e.signup + GREATEST(1, ((e.last_date - e.signup) * (e.buy_i - 1)) / GREATEST(e.n_buys - 1, 1))
      END AS buy_date,
      custom_ausiris_demo_pick_sku(e.arch, e.buy_i, e.id::text || e.buy_i::text, e.named) AS sku_code,
      'AUSV2-PUR-' || e.id::text || '-' || e.buy_i::text AS xref
    FROM exploded e
  ),
  enriched AS (
    SELECT d.*,
      st.store_code,
      (sk.payload->>'id')::uuid AS sku_id,
      (sk.payload->>'price')::numeric AS unit_price,
      sk.payload->>'lob' AS lob,
      sm.id AS store_id
    FROM dated d
    JOIN custom_ausiris_demo_config sk ON sk.kind = 'sku' AND sk.code = d.sku_code
    CROSS JOIN LATERAL (
      SELECT custom_ausiris_demo_store_for_sku(d.sku_code, d.named, d.xref) AS store_code
    ) st
    JOIN store_master sm ON sm.merchant_id = v_mid AND sm.store_code = st.store_code
  ),
  ins_p AS (
    INSERT INTO purchase_ledger (
      id, merchant_id, user_id, transaction_number, transaction_date, completed_at,
      total_amount, discount_amount, tax_amount, final_amount,
      payment_status, transaction_type, transaction_source, status, record_type,
      earn_currency, currency_processed_at, skip_cdc, external_ref, dedup_key,
      store_id, store_code, earning_channel_id, currency, metadata, created_at, updated_at, api_source
    )
    SELECT
      gen_random_uuid(),
      v_mid,
      e.id,
      'AUSV2-PUR-' || to_char(e.buy_date, 'YYYYMMDD') || '-' || substr(e.id::text, 1, 8) || '-' || e.buy_i::text,
      e.buy_date::timestamptz + ((8 + custom_ausiris_demo_rand('tm-'||e.id::text||e.buy_i)*10) || ' hours')::interval,
      e.buy_date::timestamptz + ((8 + custom_ausiris_demo_rand('tm-'||e.id::text||e.buy_i)*10) || ' hours')::interval,
      e.unit_price, 0, 0, e.unit_price,
      'paid', 'sale', e.lob, 'completed', 'credit',
      false, e.buy_date::timestamptz + ((8 + custom_ausiris_demo_rand('tm-'||e.id::text||e.buy_i)*10) || ' hours')::interval,
      true,
      e.xref,
      e.xref,
      e.store_id, e.store_code, custom_ausiris_demo_earn_channel_for_store(e.store_code), 'THB',
      jsonb_build_object('seed','SEED-AUS-V2','line_of_business', e.lob, 'sku', e.sku_code,
        'utm_campaign', CASE e.lob
          WHEN 'gold_saving' THEN 'aus-line-gold'
          WHEN 'jewelry' THEN 'aus-fb-mother'
          WHEN 'small_bar' THEN 'aus-line-bar'
          ELSE NULL END),
      e.buy_date::timestamptz,
      now(),
      'ausiris-demo-seed'
    FROM enriched e
    RETURNING id, user_id, final_amount, completed_at, external_ref, metadata, store_id
  )
  SELECT count(*) INTO v_purch FROM ins_p;

  INSERT INTO purchase_items_ledger (
    transaction_id, merchant_id, sku_id, sku_code, product_name, quantity, unit_price,
    discount_amount, tax_amount, line_total, item_type, status, completed_at,
    quantity_completed, currency_processed_at, created_at, updated_at
  )
  SELECT
    p.id, v_mid,
    (sk.payload->>'id')::uuid,
    p.metadata->>'sku',
    sm.name,
    1,
    (sk.payload->>'price')::numeric,
    0, 0, p.final_amount,
    'product', 'completed', p.completed_at, 1, p.completed_at, p.completed_at, now()
  FROM purchase_ledger p
  JOIN custom_ausiris_demo_config sk ON sk.kind = 'sku' AND sk.code = p.metadata->>'sku'
  JOIN product_sku_master sm ON sm.id = (sk.payload->>'id')::uuid
  WHERE p.merchant_id = v_mid AND p.external_ref LIKE 'AUSV2-PUR-%';

  -- Wallet earns from purchases
  INSERT INTO wallet_ledger (
    merchant_id, user_id, currency, transaction_type, source_type, component,
    amount, signed_amount, balance_before, balance_after, source_id, description,
    created_at, created_by, dedup_key, skip_cdc, metadata
  )
  SELECT
    v_mid, p.user_id, 'points', 'earn', 'purchase', 'base',
    GREATEST(1, round(p.final_amount * 0.1)::int),
    GREATEST(1, round(p.final_amount * 0.1)::int),
    0, 0, p.id, 'Purchase earn',
    p.completed_at, 'ausiris-demo-seed',
    'AUSV2-WLT-' || p.id::text, true,
    jsonb_build_object('seed','SEED-AUS-V2')
  FROM purchase_ledger p
  WHERE p.merchant_id = v_mid AND p.external_ref LIKE 'AUSV2-PUR-%';

  -- Activities (no purchase copies)
  WITH members AS (
    SELECT u.id, u.created_at,
           u.acquisition_attribution->>'archetype' AS arch,
           u.acquisition_attribution->>'named' AS named,
           COALESCE((cfg.payload->>'act_n')::int, 4) AS act_n
    FROM user_accounts u
    JOIN custom_ausiris_demo_config cfg ON cfg.kind = 'archetype' AND cfg.code = u.acquisition_attribution->>'archetype'
    WHERE u.merchant_id = v_mid AND u.external_user_id LIKE 'AUSV2-%'
  ),
  exploded AS (
    SELECT m.*, gs AS act_i
    FROM members m
    CROSS JOIN LATERAL generate_series(1, GREATEST(m.act_n, 0)) gs
  ),
  typed AS (
    SELECT e.*,
      CASE
        WHEN e.named = 'C8' THEN (ARRAY['gold_price_view','gold_price_view','price_alert_subscribe','page_view'])[1 + ((e.act_i-1) % 4)]
        WHEN e.arch = 'whale_trader' THEN (ARRAY['gold_price_view','gold_price_view','page_view','kyc_complete'])[1 + ((e.act_i-1) % 4)]
        WHEN e.arch = 'loyal_saver' THEN (ARRAY['savings_deposit_confirm','page_view','mission_progress'])[1 + ((e.act_i-1) % 3)]
        WHEN e.arch = 'high_intent_unpaid' THEN (ARRAY['gold_price_view','gold_price_view','price_alert_subscribe','page_view'])[1 + ((e.act_i-1) % 4)]
        WHEN e.arch = 'new_lead' THEN (ARRAY['campaign_touch','page_view','link_click'])[1 + ((e.act_i-1) % 3)]
        WHEN e.arch = 'jewelry_gifter' THEN (ARRAY['campaign_touch','page_view','link_click'])[1 + ((e.act_i-1) % 3)]
        WHEN e.arch = 'cooling_vip' THEN (ARRAY['gold_price_view','page_view','campaign_touch'])[1 + ((e.act_i-1) % 3)]
        WHEN e.arch = 'omni_program' THEN (ARRAY['gold_price_view','page_view','savings_deposit_confirm','vending_dispense','kyc_complete','mission_progress','workshop_rsvp','campaign_touch'])[1 + ((e.act_i-1) % 8)]
        WHEN e.arch = 'hibernating' THEN 'page_view'
        ELSE (ARRAY['page_view','link_click'])[1 + ((e.act_i-1) % 2)]
      END AS act_code,
      (e.created_at + ((current_date - e.created_at::date) * ((e.act_i)::numeric / GREATEST(e.act_n,1))) * interval '1 day') AS occurred
    FROM exploded e
  )
  INSERT INTO activity_ledger (
    merchant_id, user_id, activity_type_id, occurred_at, properties,
    utm_source, utm_campaign, attribution, mkt_campaign_id, source, external_ref
  )
  SELECT
    v_mid, t.id,
    (custom_ausiris_demo_cfg('activity_type', t.act_code)->>'id')::uuid,
    LEAST(t.occurred, now()),
    CASE t.act_code
      WHEN 'gold_price_view' THEN jsonb_build_object('metal','gold','duration_sec', 20 + (t.act_i * 3), 'page_path','/gold-price')
      WHEN 'price_alert_subscribe' THEN jsonb_build_object('metal','gold','threshold_thb', 40000)
      WHEN 'kyc_complete' THEN jsonb_build_object('method','ndid')
      WHEN 'savings_deposit_confirm' THEN jsonb_build_object('month', to_char(t.occurred,'YYYY-MM'), 'amount_thb', 1000, 'sku_code','AUS-SAVE-DCA-1000')
      WHEN 'mission_progress' THEN jsonb_build_object('mission_code','aus-save-3m','step', t.act_i)
      WHEN 'vending_dispense' THEN jsonb_build_object('location','True Digital Park')
      WHEN 'workshop_rsvp' THEN jsonb_build_object('event_name','Gold Workshop Series')
      WHEN 'page_view' THEN jsonb_build_object('page_path', CASE t.arch WHEN 'loyal_saver' THEN '/saving/dca' WHEN 'jewelry_gifter' THEN '/jewel/pdp' WHEN 'bar_shopper' THEN '/express/bar-1g' ELSE '/gold-price' END)
      ELSE '{}'::jsonb
    END,
    CASE WHEN t.act_code = 'campaign_touch' THEN
      CASE t.arch WHEN 'jewelry_gifter' THEN 'facebook' WHEN 'new_lead' THEN 'tiktok' WHEN 'cooling_vip' THEN 'email' ELSE 'line' END
    ELSE NULL END,
    CASE WHEN t.act_code = 'campaign_touch' THEN
      CASE t.arch
        WHEN 'jewelry_gifter' THEN 'aus-fb-mother'
        WHEN 'new_lead' THEN 'aus-tt-teaser'
        WHEN 'high_intent_unpaid' THEN 'aus-tt-teaser'
        WHEN 'cooling_vip' THEN 'aus-email-wb'
        WHEN 'loyal_saver' THEN 'aus-line-gold'
        WHEN 'bar_shopper' THEN 'aus-line-bar'
        ELSE 'aus-g-brand' END
    ELSE NULL END,
    '{}'::jsonb,
    CASE WHEN t.act_code = 'campaign_touch' THEN
      (custom_ausiris_demo_cfg('mkt', CASE t.arch
        WHEN 'jewelry_gifter' THEN 'aus-fb-mother'
        WHEN 'new_lead' THEN 'aus-tt-teaser'
        WHEN 'high_intent_unpaid' THEN 'aus-tt-teaser'
        WHEN 'cooling_vip' THEN 'aus-email-wb'
        WHEN 'loyal_saver' THEN 'aus-line-gold'
        WHEN 'bar_shopper' THEN 'aus-line-bar'
        ELSE 'aus-g-brand' END)->>'id')::uuid
    ELSE NULL END,
    'seed',
    'AUSV2-ACT-' || t.id::text || '-' || t.act_i::text
  FROM typed t
  WHERE (custom_ausiris_demo_cfg('activity_type', t.act_code)->>'id') IS NOT NULL;

  GET DIAGNOSTICS v_act = ROW_COUNT;

  -- ~8k engagement bonuses
  INSERT INTO wallet_ledger (
    merchant_id, user_id, currency, transaction_type, source_type, component,
    amount, signed_amount, balance_before, balance_after, description,
    created_at, created_by, dedup_key, skip_cdc, metadata
  )
  SELECT
    v_mid, a.user_id, 'points', 'earn', 'activity', 'bonus',
    15, 15, 0, 0, 'Engagement bonus',
    a.occurred_at, 'ausiris-demo-seed',
    'AUSV2-BONUS-' || a.id::text, true,
    jsonb_build_object('seed','SEED-AUS-V2','bonus_type','engagement')
  FROM activity_ledger a
  WHERE a.merchant_id = v_mid AND a.external_ref LIKE 'AUSV2-ACT-%'
    AND custom_ausiris_demo_rand('bonus-'||a.id::text) < 0.12;

  -- Redemptions ~1500 among members with enough purchase-earn
  WITH eligible AS (
    SELECT u.id AS user_id,
           COALESCE(SUM(w.amount) FILTER (WHERE w.transaction_type = 'earn'), 0) AS earned
    FROM user_accounts u
    JOIN wallet_ledger w ON w.user_id = u.id AND w.merchant_id = v_mid
    WHERE u.merchant_id = v_mid AND u.external_user_id LIKE 'AUSV2-%'
    GROUP BY u.id
    HAVING COALESCE(SUM(w.amount) FILTER (WHERE w.transaction_type = 'earn'), 0) >= 200
  ),
  picked AS (
    SELECT e.user_id, e.earned,
           row_number() OVER (ORDER BY custom_ausiris_demo_rand('rdm-'||e.user_id::text)) AS rn
    FROM eligible e
    WHERE custom_ausiris_demo_rand('rdmkeep-'||e.user_id::text) < 0.22
  ),
  rw AS (
    SELECT payload->>'id' AS rid, (payload->>'points')::int AS pts, code
    FROM custom_ausiris_demo_config WHERE kind = 'reward'
  )
  INSERT INTO reward_redemptions_ledger (
    merchant_id, user_id, reward_id, qty, points_deducted, redeemed_status, used_status,
    success, cancelled, redeemed_at, created_at, code, source_type, external_ref_id
  )
  SELECT
    v_mid, p.user_id, (r.rid)::uuid, 1, r.pts, true, false, true, false,
    (SELECT max(created_at) + interval '2 days' FROM wallet_ledger w WHERE w.user_id = p.user_id AND w.merchant_id = v_mid),
    (SELECT max(created_at) + interval '2 days' FROM wallet_ledger w WHERE w.user_id = p.user_id AND w.merchant_id = v_mid),
    'AUSV2-RDM-' || substr(p.user_id::text,1,8),
    'reward_redemption',
    'AUSV2-RDM-' || substr(p.user_id::text,1,8)
  FROM picked p
  JOIN LATERAL (
    SELECT * FROM rw
    WHERE pts <= p.earned
    ORDER BY custom_ausiris_demo_rand('rw-'||p.user_id::text||rid)
    LIMIT 1
  ) r ON true
  WHERE p.rn <= 1500;

  GET DIAGNOSTICS v_rdm = ROW_COUNT;

  INSERT INTO wallet_ledger (
    merchant_id, user_id, currency, transaction_type, source_type, component,
    amount, signed_amount, balance_before, balance_after, description,
    created_at, created_by, dedup_key, skip_cdc, metadata
  )
  SELECT
    v_mid, r.user_id, 'points', 'burn', 'reward_redemption', 'base',
    r.points_deducted::int, -r.points_deducted::int, 0, 0, 'Reward redeem',
    r.redeemed_at, 'ausiris-demo-seed',
    COALESCE(r.external_ref_id, r.code), true,
    jsonb_build_object('seed','SEED-AUS-V2')
  FROM reward_redemptions_ledger r
  WHERE r.merchant_id = v_mid AND r.external_ref_id LIKE 'AUSV2-RDM-%';

  -- Roll running balances then headers
  WITH ordered AS (
    SELECT id, user_id, signed_amount,
           SUM(signed_amount) OVER (PARTITION BY user_id ORDER BY created_at, id) AS after
    FROM wallet_ledger
    WHERE merchant_id = v_mid AND (dedup_key LIKE 'AUSV2-%' OR metadata->>'seed' = 'SEED-AUS-V2')
  )
  UPDATE wallet_ledger w
  SET balance_after = o.after,
      balance_before = o.after - w.signed_amount
  FROM ordered o
  WHERE w.id = o.id;

  UPDATE user_wallet uw
  SET points_balance = COALESCE((
    SELECT w.balance_after FROM wallet_ledger w
    WHERE w.user_id = uw.user_id AND w.merchant_id = v_mid
    ORDER BY w.created_at DESC, w.id DESC LIMIT 1
  ), 0)
  WHERE uw.merchant_id = v_mid
    AND uw.user_id IN (SELECT id FROM user_accounts WHERE merchant_id = v_mid AND external_user_id LIKE 'AUSV2-%');

  -- Tiers from 6-month spend
  WITH spend AS (
    SELECT user_id, SUM(final_amount) AS amt
    FROM purchase_ledger
    WHERE merchant_id = v_mid AND external_ref LIKE 'AUSV2-%' AND status = 'completed'
    GROUP BY user_id
  )
  UPDATE user_accounts u
  SET tier_id = CASE
    WHEN s.amt >= 500000 THEN (custom_ausiris_demo_cfg('id','tier_plat')->>'id')::uuid
    WHEN s.amt >= 80000 THEN (custom_ausiris_demo_cfg('id','tier_gold')->>'id')::uuid
    ELSE (custom_ausiris_demo_cfg('id','tier_silver')->>'id')::uuid
  END
  FROM spend s
  WHERE u.id = s.user_id AND u.merchant_id = v_mid;

  -- Mission progress / completions from actual SKU purchases
  WITH mc AS (
    SELECT m.id AS mission_id, m.mission_code, c.id AS cond_id, c.target_value, c.category_ids, c.sku_ids, c.measurement_type
    FROM mission m
    JOIN mission_conditions c ON c.mission_id = m.id
    WHERE m.merchant_id = v_mid AND m.mission_code LIKE 'aus-%' AND m.mission_type <> 'milestone'
  ),
  prog AS (
    SELECT ua.id AS user_id, mc.mission_id, mc.cond_id, mc.target_value,
           CASE
             WHEN mc.sku_ids IS NOT NULL THEN (
               SELECT count(*) FROM purchase_items_ledger pil
               JOIN purchase_ledger pl ON pl.id = pil.transaction_id
               WHERE pl.user_id = ua.id AND pil.sku_id = ANY (mc.sku_ids) AND pl.status = 'completed')
             WHEN mc.category_ids IS NOT NULL THEN (
               SELECT count(*) FROM purchase_items_ledger pil
               JOIN purchase_ledger pl ON pl.id = pil.transaction_id
               JOIN product_sku_master sku ON sku.id = pil.sku_id
               JOIN product_master pm ON pm.id = sku.product_id
               WHERE pl.user_id = ua.id AND pm.category_id = ANY (mc.category_ids) AND pl.status = 'completed')
             ELSE 0
           END AS cur
    FROM user_accounts ua
    CROSS JOIN mc
    WHERE ua.merchant_id = v_mid AND ua.external_user_id LIKE 'AUSV2-%'
  ),
  agg AS (
    SELECT user_id, mission_id,
           MIN(target_value) AS target,
           MIN(cur) AS current_progress,
           jsonb_object_agg(cond_id::text, jsonb_build_object('current', cur, 'target', target_value, 'completed', cur >= target_value)) AS condition_progress
    FROM prog
    GROUP BY user_id, mission_id
  )
  INSERT INTO mission_progress (
    user_id, mission_id, current_progress, current_target_value, period_completions, lifetime_completions,
    period_claims, lifetime_claims, unclaimed_completions, condition_progress, is_active,
    last_progress_at, last_completed_at, accepted_at
  )
  SELECT
    a.user_id, a.mission_id, LEAST(a.current_progress, a.target), a.target,
    CASE WHEN a.current_progress >= a.target THEN 1 ELSE 0 END,
    CASE WHEN a.current_progress >= a.target THEN 1 ELSE 0 END,
    CASE WHEN a.current_progress >= a.target THEN 1 ELSE 0 END,
    CASE WHEN a.current_progress >= a.target THEN 1 ELSE 0 END,
    0, a.condition_progress, true,
    now(),
    CASE WHEN a.current_progress >= a.target THEN now() ELSE NULL END,
    (SELECT created_at FROM user_accounts WHERE id = a.user_id)
  FROM agg a
  WHERE a.current_progress > 0
  ON CONFLICT (user_id, mission_id) DO UPDATE
  SET current_progress = EXCLUDED.current_progress,
      lifetime_completions = EXCLUDED.lifetime_completions,
      condition_progress = EXCLUDED.condition_progress,
      last_completed_at = EXCLUDED.last_completed_at;

  INSERT INTO mission_log_completion (
    user_id, mission_id, merchant_id, completion_number, global_completion_number,
    progress_used, loops_completed, trigger_type, is_claimed, claimed_at, completed_at, outcomes_distributed
  )
  SELECT mp.user_id, mp.mission_id, v_mid, 1, 1, mp.current_target_value, 1, 'seed', true, mp.last_completed_at, mp.last_completed_at, true
  FROM mission_progress mp
  JOIN mission m ON m.id = mp.mission_id
  WHERE m.merchant_id = v_mid AND mp.lifetime_completions > 0
    AND NOT EXISTS (
      SELECT 1 FROM mission_log_completion c WHERE c.user_id = mp.user_id AND c.mission_id = mp.mission_id
    );

  -- Activity-derived tags
  INSERT INTO user_tags (user_id, tag_id, merchant_id, source_type)
  SELECT DISTINCT a.user_id, (custom_ausiris_demo_cfg('tag','App Engager')->>'id')::uuid, v_mid, 'demo_seed'
  FROM activity_ledger a
  JOIN activity_type_master t ON t.id = a.activity_type_id
  WHERE a.merchant_id = v_mid AND t.code IN ('gold_price_view','page_view')
    AND a.occurred_at >= now() - interval '30 days'
  ON CONFLICT (user_id, tag_id) DO NOTHING;

  INSERT INTO user_tags (user_id, tag_id, merchant_id, source_type)
  SELECT u.id, (custom_ausiris_demo_cfg('tag','New Member')->>'id')::uuid, v_mid, 'demo_seed'
  FROM user_accounts u
  WHERE u.merchant_id = v_mid AND u.external_user_id LIKE 'AUSV2-%' AND u.created_at >= now() - interval '30 days'
  ON CONFLICT (user_id, tag_id) DO NOTHING;

  INSERT INTO user_tags (user_id, tag_id, merchant_id, source_type)
  SELECT DISTINCT p.user_id, (custom_ausiris_demo_cfg('tag','Marketplace Shopper')->>'id')::uuid, v_mid, 'demo_seed'
  FROM purchase_ledger p
  WHERE p.merchant_id = v_mid AND p.store_code IN ('AUS-SHOPEE','AUS-LAZADA','AUS-TIKTOK')
  ON CONFLICT (user_id, tag_id) DO NOTHING;

  INSERT INTO user_tags (user_id, tag_id, merchant_id, source_type)
  SELECT u.id, (custom_ausiris_demo_cfg('tag','Saver Streak')->>'id')::uuid, v_mid, 'demo_seed'
  FROM user_accounts u
  WHERE u.merchant_id = v_mid AND u.acquisition_attribution->>'archetype' = 'loyal_saver'
  ON CONFLICT (user_id, tag_id) DO NOTHING;

  SELECT count(*) INTO v_wlt FROM wallet_ledger WHERE merchant_id = v_mid AND metadata->>'seed' = 'SEED-AUS-V2';

  RETURN jsonb_build_object(
    'success', true,
    'purchases', v_purch,
    'activities', v_act,
    'wallet_rows', v_wlt,
    'redemptions', v_rdm
  );
END;
$fn$;
