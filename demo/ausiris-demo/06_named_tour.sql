CREATE OR REPLACE FUNCTION public.custom_ausiris_demo_seed_named_tour()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $fn$
DECLARE
  v_mid uuid := custom_ausiris_demo_merchant_id();
  r record;
  v_user uuid;
  v_sku uuid;
  v_price numeric;
  v_store uuid;
  v_store_code text;
  v_pid uuid;
  v_rw_first uuid;
  v_rw_shopee uuid;
  v_act text;
  v_i int;
  v_ts timestamptz;
  v_pts int;
BEGIN
  PERFORM custom_ausiris_demo_set_ctx();
  SELECT (payload->>'id')::uuid INTO v_rw_first FROM custom_ausiris_demo_config WHERE kind = 'reward' AND code ILIKE '%50%' LIMIT 1;
  SELECT (payload->>'id')::uuid INTO v_rw_shopee FROM custom_ausiris_demo_config WHERE kind = 'reward' AND code ILIKE '%Shopee%' LIMIT 1;

  -- Extra C0 rows: mixed LOB purchases if missing, all activity types, both redemptions, 3 campaign touches
  SELECT id INTO v_user FROM user_accounts
  WHERE merchant_id = v_mid AND tel = '0812345678' AND external_user_id LIKE 'AUSV2-%'
  LIMIT 1;
  IF v_user IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'C0 not found');
  END IF;

  FOREACH v_store_code IN ARRAY ARRAY['AUS-PLUS-APP','AUS-EXPRESS-WEB','AUS-POS-SILOM','AUS-VD-TDP']
  LOOP
    NULL;
  END LOOP;

  FOR r IN SELECT * FROM (VALUES
    ('AUS-SAVE-DCA-3000', 'AUS-PLUS-APP', current_date - 150),
    ('AUS-SAVE-DCA-3000', 'AUS-PLUS-APP', current_date - 120),
    ('AUS-SAVE-DCA-3000', 'AUS-PLUS-APP', current_date - 90),
    ('AUS-SAVE-DCA-3000', 'AUS-PLUS-APP', current_date - 60),
    ('AUS-SAVE-DCA-3000', 'AUS-PLUS-APP', current_date - 30),
    ('AUS-SAVE-DCA-3000', 'AUS-PLUS-APP', current_date - 5),
    ('AUS-BAR-5G', 'AUS-EXPRESS-WEB', current_date - 40),
    ('AUS-BAR-1G', 'AUS-VD-TDP', current_date - 12),
    ('AUS-SPOT-965-1B', 'AUS-NEXT-APP', current_date - 8),
    ('AUS-BAR-1SL', 'AUS-POS-SILOM', current_date - 3)
  ) AS t(sku, store, d)
  LOOP
    IF EXISTS (
      SELECT 1 FROM purchase_ledger p
      WHERE p.user_id = v_user AND p.external_ref = 'AUSV2-C0-' || r.sku || '-' || r.d::text
    ) THEN
      CONTINUE;
    END IF;
    v_sku := (custom_ausiris_demo_cfg('sku', r.sku)->>'id')::uuid;
    v_price := (custom_ausiris_demo_cfg('sku', r.sku)->>'price')::numeric;
    SELECT id INTO v_store FROM store_master WHERE merchant_id = v_mid AND store_code = r.store;
    v_ts := r.d::timestamptz + interval '11 hours';
    INSERT INTO purchase_ledger (
      id, merchant_id, user_id, transaction_number, transaction_date, completed_at,
      total_amount, discount_amount, tax_amount, final_amount, payment_status, transaction_type,
      transaction_source, status, record_type, earn_currency, currency_processed_at, skip_cdc,
      external_ref, dedup_key, store_id, store_code, earning_channel_id, currency, metadata,
      created_at, updated_at, api_source
    ) VALUES (
      gen_random_uuid(), v_mid, v_user,
      'AUSV2-C0-' || r.sku || '-' || to_char(r.d, 'YYYYMMDD'),
      v_ts, v_ts, v_price, 0, 0, v_price, 'paid', 'sale',
      custom_ausiris_demo_cfg('sku', r.sku)->>'lob', 'completed', 'credit', false, v_ts, true,
      'AUSV2-C0-' || r.sku || '-' || r.d::text,
      'AUSV2-C0-' || r.sku || '-' || r.d::text,
      v_store, r.store, custom_ausiris_demo_earn_channel_for_store(r.store), 'THB',
      jsonb_build_object('seed','SEED-AUS-V2','line_of_business', custom_ausiris_demo_cfg('sku', r.sku)->>'lob', 'sku', r.sku,
        'utm_campaign', CASE WHEN r.sku LIKE 'AUS-SAVE%' THEN 'aus-line-gold' WHEN r.sku LIKE 'AUS-BAR%' THEN 'aus-line-bar' ELSE 'aus-pay-day' END),
      v_ts, now(), 'ausiris-demo-seed'
    ) RETURNING id INTO v_pid;
    INSERT INTO purchase_items_ledger (
      transaction_id, merchant_id, sku_id, sku_code, product_name, quantity, unit_price,
      discount_amount, tax_amount, line_total, item_type, status, completed_at, quantity_completed, currency_processed_at
    )
    SELECT v_pid, v_mid, v_sku, r.sku, name, 1, v_price, 0, 0, v_price, 'product', 'completed', v_ts, 1, v_ts
    FROM product_sku_master WHERE id = v_sku;
    v_pts := GREATEST(1, round(v_price * 0.1)::int);
    INSERT INTO wallet_ledger (
      merchant_id, user_id, currency, transaction_type, source_type, component,
      amount, signed_amount, balance_before, balance_after, source_id, description,
      created_at, created_by, dedup_key, skip_cdc, metadata
    ) VALUES (
      v_mid, v_user, 'points', 'earn', 'purchase', 'base', v_pts, v_pts, 0, 0, v_pid, 'C0 purchase earn',
      v_ts, 'ausiris-demo-seed', 'AUSV2-C0-WLT-' || v_pid::text, true, jsonb_build_object('seed','SEED-AUS-V2')
    );
  END LOOP;

  FOREACH v_act IN ARRAY ARRAY['gold_price_view','price_alert_subscribe','kyc_complete','savings_deposit_confirm','mission_progress','vending_dispense','workshop_rsvp','page_view','link_click','campaign_touch']
  LOOP
    FOR v_i IN 1..3 LOOP
      IF v_act = 'campaign_touch' AND v_i > 3 THEN EXIT; END IF;
      INSERT INTO activity_ledger (
        merchant_id, user_id, activity_type_id, occurred_at, properties,
        utm_source, utm_campaign, attribution, mkt_campaign_id, source, external_ref
      )
      SELECT v_mid, v_user,
        (custom_ausiris_demo_cfg('activity_type', v_act)->>'id')::uuid,
        now() - (v_i * 7 + 2) * interval '1 day',
        CASE v_act
          WHEN 'gold_price_view' THEN jsonb_build_object('metal','gold','duration_sec', 45, 'page_path','/gold-price')
          WHEN 'price_alert_subscribe' THEN jsonb_build_object('metal','gold','threshold_thb', 39500)
          WHEN 'kyc_complete' THEN jsonb_build_object('method','ndid')
          WHEN 'savings_deposit_confirm' THEN jsonb_build_object('month', to_char(now(),'YYYY-MM'), 'amount_thb', 3000, 'sku_code','AUS-SAVE-DCA-3000')
          WHEN 'mission_progress' THEN jsonb_build_object('mission_code','aus-cross','step', v_i)
          WHEN 'vending_dispense' THEN jsonb_build_object('location','True Digital Park')
          WHEN 'workshop_rsvp' THEN jsonb_build_object('event_name','Gold Workshop Series')
          WHEN 'page_view' THEN jsonb_build_object('page_path','/saving/dca')
          ELSE '{}'::jsonb
        END,
        CASE WHEN v_act = 'campaign_touch' THEN (ARRAY['line','facebook','line'])[v_i] END,
        CASE WHEN v_act = 'campaign_touch' THEN (ARRAY['aus-line-gold','aus-fb-mother','aus-pay-day'])[v_i] END,
        '{}'::jsonb,
        CASE WHEN v_act = 'campaign_touch' THEN (custom_ausiris_demo_cfg('mkt', (ARRAY['aus-line-gold','aus-fb-mother','aus-pay-day'])[v_i])->>'id')::uuid END,
        'seed',
        'AUSV2-C0-ACT-' || v_act || '-' || v_i::text
      WHERE NOT EXISTS (
        SELECT 1 FROM activity_ledger a WHERE a.external_ref = 'AUSV2-C0-ACT-' || v_act || '-' || v_i::text
      );
    END LOOP;
  END LOOP;

  -- C0 burns: first-trade + Shopee catalog
  IF v_rw_first IS NOT NULL AND NOT EXISTS (
    SELECT 1 FROM reward_redemptions_ledger WHERE user_id = v_user AND reward_id = v_rw_first
  ) THEN
    INSERT INTO reward_redemptions_ledger (
      merchant_id, user_id, reward_id, qty, points_deducted, redeemed_status, used_status,
      success, cancelled, redeemed_at, created_at, code, source_type, external_ref_id
    ) VALUES (
      v_mid, v_user, v_rw_first, 1, 1500, true, true, true, false,
      now() - interval '6 days', now() - interval '6 days',
      'AUSV2-C0-RDM-FIRST', 'reward_redemption', 'AUSV2-C0-RDM-FIRST'
    );
    INSERT INTO wallet_ledger (
      merchant_id, user_id, currency, transaction_type, source_type, component,
      amount, signed_amount, balance_before, balance_after, description, created_at, created_by, dedup_key, skip_cdc, metadata
    ) VALUES (
      v_mid, v_user, 'points', 'burn', 'reward_redemption', 'base', 1500, -1500, 0, 0,
      'First-trade privilege', now() - interval '6 days', 'ausiris-demo-seed', 'AUSV2-C0-RDM-FIRST', true,
      jsonb_build_object('seed','SEED-AUS-V2')
    );
  END IF;
  IF v_rw_shopee IS NOT NULL AND NOT EXISTS (
    SELECT 1 FROM reward_redemptions_ledger WHERE user_id = v_user AND reward_id = v_rw_shopee
  ) THEN
    INSERT INTO reward_redemptions_ledger (
      merchant_id, user_id, reward_id, qty, points_deducted, redeemed_status, used_status,
      success, cancelled, redeemed_at, created_at, code, source_type, external_ref_id
    ) VALUES (
      v_mid, v_user, v_rw_shopee, 1, 200, true, false, true, false,
      now() - interval '4 days', now() - interval '4 days',
      'AUSV2-C0-RDM-SHOPEE', 'reward_redemption', 'AUSV2-C0-RDM-SHOPEE'
    );
    INSERT INTO wallet_ledger (
      merchant_id, user_id, currency, transaction_type, source_type, component,
      amount, signed_amount, balance_before, balance_after, description, created_at, created_by, dedup_key, skip_cdc, metadata
    ) VALUES (
      v_mid, v_user, 'points', 'burn', 'reward_redemption', 'base', 200, -200, 0, 0,
      'Shopee voucher', now() - interval '4 days', 'ausiris-demo-seed', 'AUSV2-C0-RDM-SHOPEE', true,
      jsonb_build_object('seed','SEED-AUS-V2')
    );
  END IF;

  -- C6 recovered: one recent win-back attributed purchase
  SELECT id INTO v_user FROM user_accounts WHERE merchant_id = v_mid AND tel = '0812345606' LIMIT 1;
  IF v_user IS NOT NULL THEN
    v_sku := (custom_ausiris_demo_cfg('sku','AUS-SPOT-965-050B')->>'id')::uuid;
    v_price := (custom_ausiris_demo_cfg('sku','AUS-SPOT-965-050B')->>'price')::numeric;
    SELECT id INTO v_store FROM store_master WHERE merchant_id = v_mid AND store_code = 'AUS-NEXT-APP';
    v_ts := now() - interval '4 days';
    IF NOT EXISTS (SELECT 1 FROM purchase_ledger WHERE user_id = v_user AND external_ref = 'AUSV2-C6-WB') THEN
      INSERT INTO purchase_ledger (
        id, merchant_id, user_id, transaction_number, transaction_date, completed_at,
        total_amount, discount_amount, tax_amount, final_amount, payment_status, transaction_type,
        transaction_source, status, record_type, earn_currency, currency_processed_at, skip_cdc,
        external_ref, dedup_key, store_id, store_code, earning_channel_id, currency, metadata, created_at, api_source
      ) VALUES (
        gen_random_uuid(), v_mid, v_user, 'AUSV2-C6-WB', v_ts, v_ts, v_price, 0, 0, v_price,
        'paid','sale','spot_gold','completed','credit', false, v_ts, true, 'AUSV2-C6-WB','AUSV2-C6-WB',
        v_store, 'AUS-NEXT-APP', custom_ausiris_demo_earn_channel_for_store('AUS-NEXT-APP'), 'THB',
        jsonb_build_object('seed','SEED-AUS-V2','line_of_business','spot_gold','sku','AUS-SPOT-965-050B','utm_campaign','aus-email-wb'),
        v_ts, 'ausiris-demo-seed'
      ) RETURNING id INTO v_pid;
      INSERT INTO purchase_items_ledger (transaction_id, merchant_id, sku_id, sku_code, product_name, quantity, unit_price, discount_amount, tax_amount, line_total, item_type, status, completed_at, quantity_completed)
      SELECT v_pid, v_mid, v_sku, 'AUS-SPOT-965-050B', name, 1, v_price, 0, 0, v_price, 'product', 'completed', v_ts, 1
      FROM product_sku_master WHERE id = v_sku;
      INSERT INTO wallet_ledger (merchant_id, user_id, currency, transaction_type, source_type, component, amount, signed_amount, balance_before, balance_after, source_id, description, created_at, created_by, dedup_key, skip_cdc, metadata)
      VALUES (v_mid, v_user, 'points','earn','purchase','base', GREATEST(1,round(v_price*0.1)::int), GREATEST(1,round(v_price*0.1)::int), 0, 0, v_pid, 'C6 win-back', v_ts, 'ausiris-demo-seed', 'AUSV2-C6-WB', true, jsonb_build_object('seed','SEED-AUS-V2'));
      INSERT INTO activity_ledger (merchant_id, user_id, activity_type_id, occurred_at, properties, utm_source, utm_campaign, attribution, mkt_campaign_id, source, external_ref)
      SELECT v_mid, v_user, (custom_ausiris_demo_cfg('activity_type','campaign_touch')->>'id')::uuid,
        v_ts - interval '2 days', '{}'::jsonb, 'email', 'aus-email-wb', '{}'::jsonb,
        (custom_ausiris_demo_cfg('mkt','aus-email-wb')->>'id')::uuid, 'seed', 'AUSV2-C6-TOUCH'
      WHERE NOT EXISTS (SELECT 1 FROM activity_ledger WHERE external_ref = 'AUSV2-C6-TOUCH');
    END IF;
  END IF;

  -- Re-roll C0 + C6 wallet headers
  WITH ordered AS (
    SELECT id, user_id, signed_amount,
           SUM(signed_amount) OVER (PARTITION BY user_id ORDER BY created_at, id) AS after
    FROM wallet_ledger
    WHERE merchant_id = v_mid AND user_id IN (
      SELECT id FROM user_accounts WHERE merchant_id = v_mid AND tel IN ('0812345678','0812345606')
    )
  )
  UPDATE wallet_ledger w
  SET balance_after = o.after, balance_before = o.after - w.signed_amount
  FROM ordered o WHERE w.id = o.id;

  UPDATE user_wallet uw
  SET points_balance = COALESCE((
    SELECT w.balance_after FROM wallet_ledger w
    WHERE w.user_id = uw.user_id AND w.merchant_id = v_mid
    ORDER BY w.created_at DESC, w.id DESC LIMIT 1
  ), 0)
  WHERE uw.merchant_id = v_mid AND uw.user_id IN (
    SELECT id FROM user_accounts WHERE merchant_id = v_mid AND tel IN ('0812345678','0812345606')
  );

  -- C0 Gold+ from extra spend
  UPDATE user_accounts SET
    tier_id = CASE
      WHEN (SELECT SUM(final_amount) FROM purchase_ledger WHERE user_id = user_accounts.id) >= 500000
        THEN (custom_ausiris_demo_cfg('id','tier_plat')->>'id')::uuid
      WHEN (SELECT SUM(final_amount) FROM purchase_ledger WHERE user_id = user_accounts.id) >= 80000
        THEN (custom_ausiris_demo_cfg('id','tier_gold')->>'id')::uuid
      ELSE tier_id
    END,
    channel_email = true,
    channel_line = true,
    email = COALESCE(email, 'thanawat.sukkasem.c0@ausiris.example'),
    line_id = COALESCE(line_id, 'U' || substr(md5('c0-line'), 1, 32))
  WHERE merchant_id = v_mid AND tel = '0812345678';

  INSERT INTO user_tags (user_id, tag_id, merchant_id, source_type)
  SELECT id, (custom_ausiris_demo_cfg('tag','App Engager')->>'id')::uuid, v_mid, 'demo_seed'
  FROM user_accounts WHERE merchant_id = v_mid AND tel IN ('0812345678','0812345608')
  ON CONFLICT (user_id, tag_id) DO NOTHING;

  RETURN jsonb_build_object('success', true, 'c0', '0812345678');
END;
$fn$;
