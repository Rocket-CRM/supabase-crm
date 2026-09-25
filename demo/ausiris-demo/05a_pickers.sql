CREATE OR REPLACE FUNCTION public.custom_ausiris_demo_pick_sku(p_arch text, p_buy_i int, p_key text, p_named text)
RETURNS text
LANGUAGE sql
STABLE
AS $$
  SELECT CASE
    WHEN p_named = 'C11' THEN (ARRAY['AUS-SLV-BAR-10G','AUS-SLV-COIN-1OZ','AUS-SLV-BAR-10G'])[1 + (p_buy_i % 2)]
    WHEN p_arch = 'whale_trader' THEN (ARRAY['AUS-SPOT-965-1B','AUS-SPOT-965-2B','AUS-SPOT-999-1B','AUS-SPOT-965-050B'])[1 + ((p_buy_i + (custom_ausiris_demo_rand(p_key)*4)::int) % 4)]
    WHEN p_arch = 'loyal_saver' THEN (ARRAY['AUS-SAVE-DCA-500','AUS-SAVE-DCA-1000','AUS-SAVE-DCA-3000'])[1 + ((p_buy_i + (custom_ausiris_demo_rand(p_key)*3)::int) % 3)]
    WHEN p_arch = 'bar_shopper' THEN
      CASE WHEN custom_ausiris_demo_rand(p_key) < 0.16
        THEN (ARRAY['AUS-SLV-BAR-10G','AUS-SLV-COIN-1OZ'])[1 + (p_buy_i % 2)]
        ELSE (ARRAY['AUS-BAR-1G','AUS-BAR-5G','AUS-BAR-1SL'])[1 + (p_buy_i % 3)]
      END
    WHEN p_arch = 'jewelry_gifter' THEN (ARRAY['IRIS-NL-MOTHER','IRIS-RG-MINI','IRIS-ER-GIFT','IRIS-NL-DAILY','IRIS-BR-LIVE'])[1 + (p_buy_i % 5)]
    WHEN p_arch = 'cooling_vip' THEN (ARRAY['AUS-SPOT-965-1B','AUS-SPOT-965-2B','AUS-SPOT-965-050B'])[1 + (p_buy_i % 3)]
    WHEN p_arch = 'hibernating' THEN (ARRAY['AUS-BAR-1G','AUS-SAVE-DCA-500','IRIS-RG-MINI'])[1 + (p_buy_i % 3)]
    WHEN p_arch = 'first_purchase' THEN (ARRAY['AUS-SAVE-DCA-1000','AUS-BAR-1G'])[1 + (p_buy_i % 2)]
    WHEN p_arch = 'omni_program' THEN (ARRAY['AUS-SAVE-DCA-1000','AUS-SAVE-DCA-3000','AUS-BAR-1G','AUS-BAR-5G','AUS-SPOT-965-025B'])[1 + (p_buy_i % 5)]
    ELSE 'AUS-BAR-1G'
  END;
$$;

-- Assortment: trading=spot, Plus=saving, Express/POS gold/Lazada=bars,
-- Shopee=bars+jewelry, TikTok/Live=jewelry, silver POS=silver, vending=1g/5g bar + silver.
CREATE OR REPLACE FUNCTION public.custom_ausiris_demo_store_for_sku(p_sku text, p_named text, p_key text)
RETURNS text
LANGUAGE sql
STABLE
AS $$
  SELECT CASE
    WHEN p_named = 'C11' THEN CASE WHEN custom_ausiris_demo_rand(p_key) < 0.5 THEN 'AUS-POS-SLV-TDP' ELSE 'AUS-VD-TDP' END
    WHEN p_sku LIKE 'AUS-SPOT%' THEN 'AUS-NEXT-APP'
    WHEN p_sku LIKE 'AUS-SAVE%' THEN 'AUS-PLUS-APP'
    WHEN p_sku LIKE 'AUS-BAR%' THEN
      CASE
        WHEN p_sku IN ('AUS-BAR-1G','AUS-BAR-5G') AND custom_ausiris_demo_rand(p_key || ':vd') < 0.08 THEN 'AUS-VD-TDP'
        ELSE (ARRAY['AUS-EXPRESS-WEB','AUS-SHOPEE','AUS-LAZADA','AUS-POS-SIAM','AUS-POS-SILOM','AUS-POS-CNX'])
          [1 + (floor(custom_ausiris_demo_rand(p_key || ':st') * 6))::int]
      END
    WHEN p_sku LIKE 'IRIS%' THEN
      CASE
        WHEN p_sku LIKE '%LIVE%' THEN 'AUS-IRIS-LIVE'
        WHEN custom_ausiris_demo_rand(p_key || ':lv') < 0.32 THEN 'AUS-IRIS-LIVE'
        WHEN custom_ausiris_demo_rand(p_key || ':sh') < 0.12 THEN 'AUS-SHOPEE'
        ELSE 'AUS-TIKTOK'
      END
    WHEN p_sku LIKE 'AUS-SLV%' THEN
      CASE WHEN custom_ausiris_demo_rand(p_key || ':sv') < 0.38 THEN 'AUS-VD-TDP' ELSE 'AUS-POS-SLV-TDP' END
    ELSE 'AUS-POS-SILOM'
  END;
$$;

CREATE OR REPLACE FUNCTION public.custom_ausiris_demo_earn_channel_for_store(p_store_code text)
RETURNS uuid
LANGUAGE sql
STABLE
AS $$
  SELECT (custom_ausiris_demo_cfg('id', 'earn_channel_' || CASE p_store_code
    WHEN 'AUS-NEXT-APP' THEN 'trading'
    WHEN 'AUS-PLUS-APP' THEN 'gold_saving'
    WHEN 'AUS-EXPRESS-WEB' THEN 'web'
    WHEN 'AUS-VD-TDP' THEN 'vending'
    WHEN 'AUS-SHOPEE' THEN 'marketplace'
    WHEN 'AUS-LAZADA' THEN 'marketplace'
    WHEN 'AUS-TIKTOK' THEN 'marketplace'
    WHEN 'AUS-IRIS-LIVE' THEN 'live'
    ELSE 'pos'
  END)->>'id')::uuid;
$$;

-- Restamp existing AUSV2 purchases onto the brief's channels. Named-tour rows keep their stores.
CREATE OR REPLACE FUNCTION public.custom_ausiris_demo_remap_purchase_channels()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $fn$
DECLARE
  v_mid uuid := custom_ausiris_demo_merchant_id();
  v_moved int;
  v_stamped int;
  v_silver int := 0;
  v_wallet int;
BEGIN
  PERFORM custom_ausiris_demo_set_ctx();
  PERFORM custom_ausiris_demo_bootstrap_store_channels();

  WITH picked AS (
    SELECT
      p.id,
      custom_ausiris_demo_store_for_sku(
        p.metadata->>'sku',
        u.acquisition_attribution->>'named',
        p.external_ref
      ) AS store_code
    FROM purchase_ledger p
    JOIN user_accounts u ON u.id = p.user_id
    WHERE p.merchant_id = v_mid
      AND p.external_ref LIKE 'AUSV2-PUR-%'
  )
  UPDATE purchase_ledger p
  SET store_code = sm.store_code,
      store_id = sm.id,
      earning_channel_id = custom_ausiris_demo_earn_channel_for_store(sm.store_code),
      updated_at = now()
  FROM picked s
  JOIN store_master sm ON sm.merchant_id = v_mid AND sm.store_code = s.store_code
  WHERE p.id = s.id
    AND (p.store_code IS DISTINCT FROM sm.store_code
         OR p.earning_channel_id IS DISTINCT FROM custom_ausiris_demo_earn_channel_for_store(sm.store_code));
  GET DIAGNOSTICS v_moved = ROW_COUNT;

  UPDATE purchase_ledger p
  SET earning_channel_id = custom_ausiris_demo_earn_channel_for_store(p.store_code),
      updated_at = now()
  WHERE p.merchant_id = v_mid
    AND p.external_ref LIKE 'AUSV2%'
    AND p.earning_channel_id IS DISTINCT FROM custom_ausiris_demo_earn_channel_for_store(p.store_code);
  GET DIAGNOSTICS v_stamped = ROW_COUNT;

  -- Silver volume: extra row for a slice of bar/hibernating members (idempotent).
  WITH ins AS (
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
      u.id,
      'AUSV2-SLV-' || substr(u.id::text, 1, 8),
      v_ts, v_ts,
      (sk.payload->>'price')::numeric, 0, 0, (sk.payload->>'price')::numeric,
      'paid', 'sale', 'silver', 'completed', 'credit',
      false, v_ts, true,
      'AUSV2-SLV-' || u.id::text,
      'AUSV2-SLV-' || u.id::text,
      sm.id, sm.store_code,
      custom_ausiris_demo_earn_channel_for_store(sm.store_code),
      'THB',
      jsonb_build_object('seed','SEED-AUS-V2','line_of_business','silver','sku', v_sku),
      v_ts, now(), 'ausiris-demo-seed'
    FROM user_accounts u
    CROSS JOIN LATERAL (
      SELECT CASE WHEN custom_ausiris_demo_rand(u.id::text || ':slvsku') < 0.55
        THEN 'AUS-SLV-COIN-1OZ' ELSE 'AUS-SLV-BAR-10G' END AS sku_code
    ) pick
    JOIN custom_ausiris_demo_config sk ON sk.kind = 'sku' AND sk.code = pick.sku_code
    CROSS JOIN LATERAL (
      SELECT custom_ausiris_demo_store_for_sku(pick.sku_code, u.acquisition_attribution->>'named', 'AUSV2-SLV-' || u.id::text) AS store_code
    ) st
    JOIN store_master sm ON sm.merchant_id = v_mid AND sm.store_code = st.store_code
    CROSS JOIN LATERAL (
      SELECT LEAST(
        now(),
        GREATEST(u.created_at, now() - ((20 + floor(custom_ausiris_demo_rand(u.id::text || ':slvday') * 90))::int || ' days')::interval)
      ) AS v_ts
    ) ts
    CROSS JOIN LATERAL (SELECT pick.sku_code AS v_sku) sku_n
    WHERE u.merchant_id = v_mid
      AND u.external_user_id LIKE 'AUSV2-%'
      AND u.acquisition_attribution->>'archetype' IN ('bar_shopper','hibernating')
      AND custom_ausiris_demo_rand(u.id::text || ':slv') < 0.22
      AND NOT EXISTS (
        SELECT 1 FROM purchase_ledger p
        WHERE p.merchant_id = v_mid AND p.external_ref = 'AUSV2-SLV-' || u.id::text
      )
    RETURNING id, user_id, final_amount, completed_at, metadata, store_id
  )
  SELECT count(*) INTO v_silver FROM ins;

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
  WHERE p.merchant_id = v_mid
    AND p.external_ref LIKE 'AUSV2-SLV-%'
    AND NOT EXISTS (
      SELECT 1 FROM purchase_items_ledger i WHERE i.transaction_id = p.id
    );

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
  WHERE p.merchant_id = v_mid
    AND p.external_ref LIKE 'AUSV2-SLV-%'
    AND NOT EXISTS (
      SELECT 1 FROM wallet_ledger w WHERE w.dedup_key = 'AUSV2-WLT-' || p.id::text
    );
  GET DIAGNOSTICS v_wallet = ROW_COUNT;

  UPDATE user_wallet uw
  SET points_balance = COALESCE(s.bal, 0)
  FROM (
    SELECT u.id AS user_id, COALESCE(SUM(w.signed_amount), 0) AS bal
    FROM user_accounts u
    LEFT JOIN wallet_ledger w ON w.user_id = u.id AND w.merchant_id = v_mid AND w.currency = 'points'
    WHERE u.merchant_id = v_mid AND u.external_user_id LIKE 'AUSV2-%'
    GROUP BY u.id
  ) s
  WHERE uw.user_id = s.user_id AND uw.merchant_id = v_mid
    AND uw.points_balance IS DISTINCT FROM COALESCE(s.bal, 0);

  RETURN jsonb_build_object(
    'success', true,
    'bulk_store_moves', v_moved,
    'earn_channel_stamps', v_stamped,
    'silver_purchases', v_silver,
    'silver_wallet', v_wallet
  );
END;
$fn$;
