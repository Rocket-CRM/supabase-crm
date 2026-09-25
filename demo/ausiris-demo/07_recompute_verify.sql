CREATE OR REPLACE FUNCTION public.custom_ausiris_demo_recompute()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $fn$
DECLARE
  v_mid uuid := custom_ausiris_demo_merchant_id();
  v_rfm jsonb;
  v_funnel jsonb;
  v_amp jsonb;
  v_mkt jsonb;
  v_funnel_id uuid := (custom_ausiris_demo_cfg('id','funnel')->>'id')::uuid;
BEGIN
  PERFORM custom_ausiris_demo_set_ctx();

  v_rfm := fn_rfm_compute_scores(v_mid);

  INSERT INTO user_tags (user_id, tag_id, merchant_id, source_type)
  SELECT s.user_id, (custom_ausiris_demo_cfg('tag','VIP Trader')->>'id')::uuid, v_mid, 'demo_seed'
  FROM rfm_user_score s
  WHERE s.merchant_id = v_mid AND s.rfm_segment = 'Champions'
  ON CONFLICT (user_id, tag_id) DO NOTHING;

  INSERT INTO user_tags (user_id, tag_id, merchant_id, source_type)
  SELECT s.user_id, (custom_ausiris_demo_cfg('tag','At Risk')->>'id')::uuid, v_mid, 'demo_seed'
  FROM rfm_user_score s
  WHERE s.merchant_id = v_mid AND s.rfm_segment = 'At Risk'
  ON CONFLICT (user_id, tag_id) DO NOTHING;

  INSERT INTO user_tags (user_id, tag_id, merchant_id, source_type)
  SELECT s.user_id, (custom_ausiris_demo_cfg('tag','Hibernating')->>'id')::uuid, v_mid, 'demo_seed'
  FROM rfm_user_score s
  WHERE s.merchant_id = v_mid AND s.rfm_segment = 'Hibernating'
  ON CONFLICT (user_id, tag_id) DO NOTHING;

  INSERT INTO user_tags (user_id, tag_id, merchant_id, source_type)
  SELECT s.user_id, (custom_ausiris_demo_cfg('tag','Lost')->>'id')::uuid, v_mid, 'demo_seed'
  FROM rfm_user_score s
  WHERE s.merchant_id = v_mid AND s.rfm_segment = 'Lost'
  ON CONFLICT (user_id, tag_id) DO NOTHING;

  v_mkt := fn_mkt_compute_purchase_attribution();
  IF v_funnel_id IS NOT NULL THEN
    v_funnel := fn_funnel_reconcile(v_funnel_id);
  ELSE
    v_funnel := fn_funnel_reconcile_all();
  END IF;
  v_amp := fn_amp_reconcile_dynamic_audiences();
  PERFORM custom_ausiris_demo_fill_amp();
  PERFORM custom_ausiris_demo_fill_attribution();

  RETURN jsonb_build_object(
    'success', true,
    'rfm', v_rfm,
    'funnel', v_funnel,
    'amp', v_amp,
    'mkt_global', true,
    'mkt', v_mkt
  );
END;
$fn$;

-- AMP reconcile does not expand tag/purchase-aggregate audiences; stamp membership for the walk.
CREATE OR REPLACE FUNCTION public.custom_ausiris_demo_fill_amp()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $fn$
DECLARE
  v_mid uuid := custom_ausiris_demo_merchant_id();
  v_funnel_id uuid := (custom_ausiris_demo_cfg('id','funnel')->>'id')::uuid;
  v_n int;
BEGIN
  PERFORM custom_ausiris_demo_set_ctx();

  DELETE FROM amp_audience_member aam
  USING amp_audience_master a
  WHERE aam.audience_id = a.id
    AND a.merchant_id = v_mid
    AND a.funnel_id IS NULL
    AND a.name LIKE 'Ausiris %';

  INSERT INTO amp_audience_member (id, audience_id, user_id, entered_at)
  SELECT gen_random_uuid(), a.id, u.id, now()
  FROM amp_audience_master a
  JOIN user_accounts u ON u.merchant_id = v_mid AND u.external_user_id LIKE 'AUSV2-%'
  WHERE a.merchant_id = v_mid AND a.name = 'Ausiris VIP exclusive'
    AND (
      u.tier_id = (custom_ausiris_demo_cfg('id','tier_plat')->>'id')::uuid
      OR EXISTS (
        SELECT 1 FROM user_tags t
        WHERE t.user_id = u.id
          AND t.tag_id = (custom_ausiris_demo_cfg('tag','VIP Trader')->>'id')::uuid
      )
    );

  INSERT INTO amp_audience_member (id, audience_id, user_id, entered_at)
  SELECT gen_random_uuid(), a.id, u.id, now()
  FROM amp_audience_master a
  JOIN user_accounts u ON u.merchant_id = v_mid AND u.external_user_id LIKE 'AUSV2-%'
  WHERE a.merchant_id = v_mid AND a.name = 'Ausiris Win-back'
    AND EXISTS (
      SELECT 1 FROM user_tags t
      WHERE t.user_id = u.id
        AND t.tag_id = (custom_ausiris_demo_cfg('tag','At Risk')->>'id')::uuid
    );

  INSERT INTO amp_audience_member (id, audience_id, user_id, entered_at)
  SELECT gen_random_uuid(), a.id, u.id, now()
  FROM amp_audience_master a
  JOIN user_accounts u ON u.merchant_id = v_mid AND u.external_user_id LIKE 'AUSV2-%'
  WHERE a.merchant_id = v_mid AND a.name = 'Ausiris Reactivation'
    AND EXISTS (
      SELECT 1 FROM user_tags t
      WHERE t.user_id = u.id
        AND t.tag_id IN (
          (custom_ausiris_demo_cfg('tag','Hibernating')->>'id')::uuid,
          (custom_ausiris_demo_cfg('tag','Lost')->>'id')::uuid
        )
    );

  INSERT INTO amp_audience_member (id, audience_id, user_id, entered_at)
  SELECT gen_random_uuid(), a.id, u.id, now()
  FROM amp_audience_master a
  JOIN user_accounts u ON u.merchant_id = v_mid AND u.external_user_id LIKE 'AUSV2-%'
  WHERE a.merchant_id = v_mid AND a.name = 'Ausiris High-intent unpaid'
    AND EXISTS (
      SELECT 1 FROM user_tags t
      WHERE t.user_id = u.id
        AND t.tag_id = (custom_ausiris_demo_cfg('tag','App Engager')->>'id')::uuid
    )
    AND NOT EXISTS (
      SELECT 1 FROM purchase_ledger p WHERE p.user_id = u.id AND p.merchant_id = v_mid
    );

  INSERT INTO amp_audience_member (id, audience_id, user_id, entered_at)
  SELECT gen_random_uuid(), a.id, u.id, now()
  FROM amp_audience_master a
  JOIN user_accounts u ON u.merchant_id = v_mid AND u.external_user_id LIKE 'AUSV2-%'
    AND u.created_at >= (current_date - 14)
  WHERE a.merchant_id = v_mid AND a.name = 'Ausiris Welcome';

  INSERT INTO amp_audience_member (id, audience_id, user_id, entered_at)
  SELECT gen_random_uuid(), a.id, am.user_id, now()
  FROM amp_audience_master a
  JOIN amp_audience_master fp ON fp.merchant_id = v_mid AND fp.funnel_id = v_funnel_id AND fp.name = 'First Purchase'
  JOIN amp_audience_member am ON am.audience_id = fp.id AND am.exited_at IS NULL
  WHERE a.merchant_id = v_mid AND a.name = 'Ausiris Convert to repeat';

  INSERT INTO amp_audience_member (id, audience_id, user_id, entered_at)
  SELECT gen_random_uuid(), a.id, x.user_id, now()
  FROM amp_audience_master a
  JOIN (
    SELECT DISTINCT p.user_id
    FROM purchase_ledger p
    JOIN purchase_items_ledger i ON i.transaction_id = p.id
    JOIN custom_ausiris_demo_config cfg ON cfg.kind = 'sku' AND (cfg.payload->>'id')::uuid = i.sku_id
    WHERE p.merchant_id = v_mid AND cfg.payload->>'lob' = 'gold_saving'
      AND p.created_at >= now() - interval '90 days'
  ) x ON true
  JOIN amp_audience_master prog ON prog.merchant_id = v_mid AND prog.funnel_id = v_funnel_id AND prog.name = 'Program Member'
  JOIN amp_audience_member pm ON pm.audience_id = prog.id AND pm.user_id = x.user_id AND pm.exited_at IS NULL
  WHERE a.merchant_id = v_mid AND a.name = 'Ausiris Savers special';

  INSERT INTO amp_audience_member (id, audience_id, user_id, entered_at)
  SELECT gen_random_uuid(), a.id, x.user_id, now()
  FROM amp_audience_master a
  JOIN (
    SELECT DISTINCT p.user_id
    FROM purchase_ledger p
    JOIN purchase_items_ledger i ON i.transaction_id = p.id
    JOIN custom_ausiris_demo_config cfg ON cfg.kind = 'sku' AND (cfg.payload->>'id')::uuid = i.sku_id
    WHERE p.merchant_id = v_mid AND cfg.payload->>'lob' = 'small_bar'
      AND p.created_at >= now() - interval '60 days'
    UNION
    SELECT DISTINCT mlc.user_id
    FROM mission_log_completion mlc
    WHERE mlc.merchant_id = v_mid
      AND mlc.mission_id = (custom_ausiris_demo_cfg('mission','aus-bar-collect')->>'id')::uuid
      AND mlc.completed_at >= now() - interval '60 days'
  ) x ON true
  WHERE a.merchant_id = v_mid AND a.name = 'Ausiris Bar / mission';

  INSERT INTO amp_audience_member (id, audience_id, user_id, entered_at)
  SELECT gen_random_uuid(), a.id, x.user_id, now()
  FROM amp_audience_master a
  JOIN (
    SELECT DISTINCT p.user_id
    FROM purchase_ledger p
    JOIN purchase_items_ledger i ON i.transaction_id = p.id
    JOIN custom_ausiris_demo_config cfg ON cfg.kind = 'sku' AND (cfg.payload->>'id')::uuid = i.sku_id
    WHERE p.merchant_id = v_mid AND cfg.payload->>'lob' = 'jewelry'
      AND p.created_at >= now() - interval '30 days'
  ) x ON true
  WHERE a.merchant_id = v_mid AND a.name = 'Ausiris Jewelry 30d';

  UPDATE amp_audience_master a
  SET member_count = (
    SELECT count(*) FROM amp_audience_member am
    WHERE am.audience_id = a.id AND am.exited_at IS NULL
  )
  WHERE a.merchant_id = v_mid AND a.funnel_id IS NULL AND a.name LIKE 'Ausiris %';

  SELECT count(*) INTO v_n FROM amp_audience_member aam
  JOIN amp_audience_master a ON a.id = aam.audience_id
  WHERE a.merchant_id = v_mid AND a.funnel_id IS NULL AND a.name LIKE 'Ausiris %' AND aam.exited_at IS NULL;

  RETURN jsonb_build_object('success', true, 'amp_members', v_n);
END;
$fn$;

-- Seed writes UTM text but campaign UUIDs are null after a masters re-run
-- (DELETE mkt_campaign nulls FKs). Fill ROI from purchase metadata and
-- re-stamp activities/members so the report + compute path have IDs.
-- Advances this merchant's watermark so nightly global compute does not
-- delete these fill rows (it recomputes created_at > watermark, 20k/run).
CREATE OR REPLACE FUNCTION public.custom_ausiris_demo_fill_attribution()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $fn$
DECLARE
  v_mid uuid := custom_ausiris_demo_merchant_id();
  v_n int;
  v_act int;
  v_acq int;
  v_tt uuid := (custom_ausiris_demo_cfg('mkt','aus-tt-teaser')->>'id')::uuid;
BEGIN
  PERFORM custom_ausiris_demo_set_ctx();

  UPDATE activity_ledger al
  SET mkt_campaign_id = i.campaign_id
  FROM mkt_campaign_identifier i
  WHERE al.merchant_id = v_mid
    AND al.mkt_campaign_id IS NULL
    AND al.utm_campaign IS NOT NULL
    AND i.merchant_id = v_mid
    AND i.key_type = 'utm_campaign'
    AND i.key_value = al.utm_campaign;
  GET DIAGNOSTICS v_act = ROW_COUNT;

  UPDATE user_accounts u
  SET acquisition_campaign_id = i.campaign_id
  FROM mkt_campaign_identifier i
  WHERE u.merchant_id = v_mid
    AND u.acquisition_campaign_id IS NULL
    AND u.acquisition_utm_campaign IS NOT NULL
    AND i.merchant_id = v_mid
    AND i.key_type = 'utm_campaign'
    AND i.key_value = u.acquisition_utm_campaign;
  GET DIAGNOSTICS v_acq = ROW_COUNT;

  DELETE FROM mkt_purchase_attribution WHERE merchant_id = v_mid;

  INSERT INTO mkt_purchase_attribution (
    merchant_id, purchase_id, user_id, campaign_id, attributed_amount, model, touch_count, computed_at
  )
  SELECT
    v_mid, p.id, p.user_id, (cfg.payload->>'id')::uuid, p.final_amount, 'u_shape', 1, now()
  FROM purchase_ledger p
  JOIN custom_ausiris_demo_config cfg
    ON cfg.kind = 'mkt' AND cfg.code = p.metadata->>'utm_campaign'
  WHERE p.merchant_id = v_mid
    AND (p.external_ref LIKE 'AUSV2%' OR p.metadata->>'seed' = 'SEED-AUS-V2')
    AND p.metadata->>'utm_campaign' IS NOT NULL
    AND (cfg.payload->>'id') IS NOT NULL;

  INSERT INTO mkt_purchase_attribution (
    merchant_id, purchase_id, user_id, campaign_id, attributed_amount, model, touch_count, computed_at
  )
  SELECT v_mid, p.id, p.user_id, v_tt, p.final_amount, 'u_shape', 1, now()
  FROM purchase_ledger p
  WHERE v_tt IS NOT NULL
    AND p.merchant_id = v_mid
    AND (p.external_ref LIKE 'AUSV2%' OR p.metadata->>'seed' = 'SEED-AUS-V2')
    AND p.metadata->>'utm_campaign' IS NULL
    AND p.metadata->>'line_of_business' = 'spot_gold'
    AND NOT EXISTS (
      SELECT 1 FROM mkt_purchase_attribution a WHERE a.purchase_id = p.id
    )
  ORDER BY md5(p.id::text)
  LIMIT 50;

  GET DIAGNOSTICS v_n = ROW_COUNT;

  UPDATE mkt_config
  SET attribution_watermark = GREATEST(
        now(),
        (SELECT COALESCE(max(created_at), now()) FROM purchase_ledger WHERE merchant_id = v_mid)
      ),
      updated_at = now()
  WHERE merchant_id = v_mid;

  RETURN jsonb_build_object(
    'success', true,
    'activities_stamped', v_act,
    'members_stamped', v_acq,
    'tiktok_rows', v_n,
    'total', (SELECT count(*) FROM mkt_purchase_attribution WHERE merchant_id = v_mid)
  );
END;
$fn$;

CREATE OR REPLACE FUNCTION public.custom_ausiris_demo_verify()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $fn$
DECLARE
  v_mid uuid := custom_ausiris_demo_merchant_id();
  v_c0 uuid;
  v_c8 uuid;
  v_ok boolean := true;
  v_fail text[] := ARRAY[]::text[];
  v_out jsonb := '{}'::jsonb;
  v_n bigint;
  v_mismatch bigint;
  v_seg jsonb;
  v_funnel_id uuid := (custom_ausiris_demo_cfg('id','funnel')->>'id')::uuid;
  v_line numeric;
  v_fb numeric;
  v_tt numeric;
BEGIN
  SELECT id INTO v_c0 FROM user_accounts WHERE merchant_id = v_mid AND tel = '0812345678' LIMIT 1;
  SELECT id INTO v_c8 FROM user_accounts WHERE merchant_id = v_mid AND tel = '0812345608' LIMIT 1;

  SELECT count(*) INTO v_n FROM user_accounts WHERE merchant_id = v_mid AND external_user_id LIKE 'AUSV2-%';
  v_out := v_out || jsonb_build_object('members_seeded', v_n, 'members_total',
    (SELECT count(*) FROM user_accounts WHERE merchant_id = v_mid));
  IF v_n < 9995 OR v_n > 10005 THEN
    v_ok := false; v_fail := v_fail || ARRAY['members'];
  END IF;

  SELECT count(*) INTO v_mismatch
  FROM purchase_items_ledger pil
  JOIN purchase_ledger pl ON pl.id = pil.transaction_id
  LEFT JOIN product_sku_master sku ON sku.id = pil.sku_id
  WHERE pl.merchant_id = v_mid AND pl.external_ref LIKE 'AUSV2%'
    AND (pil.sku_id IS NULL OR sku.id IS NULL);
  v_out := v_out || jsonb_build_object('orphan_skus', v_mismatch);
  IF v_mismatch > 0 THEN v_ok := false; v_fail := v_fail || ARRAY['sku_fk']; END IF;

  SELECT count(*) INTO v_mismatch FROM purchase_ledger p
  WHERE p.merchant_id = v_mid AND p.external_ref LIKE 'AUSV2%'
    AND NOT EXISTS (SELECT 1 FROM purchase_items_ledger i WHERE i.transaction_id = p.id);
  v_out := v_out || jsonb_build_object('purchases_without_items', v_mismatch);
  IF v_mismatch > 0 THEN v_ok := false; v_fail := v_fail || ARRAY['no_items']; END IF;

  SELECT count(*) INTO v_mismatch
  FROM purchase_ledger p
  WHERE p.merchant_id = v_mid AND p.external_ref LIKE 'AUSV2%'
    AND abs(p.final_amount - COALESCE((SELECT SUM(line_total) FROM purchase_items_ledger i WHERE i.transaction_id = p.id), 0)) > 0.01;
  v_out := v_out || jsonb_build_object('header_item_mismatch', v_mismatch);
  IF v_mismatch > 0 THEN v_ok := false; v_fail := v_fail || ARRAY['header_sum']; END IF;

  -- Wallet sample: C0 + 20 random
  SELECT count(*) INTO v_mismatch
  FROM (
    SELECT uw.user_id,
           uw.points_balance AS header,
           COALESCE((SELECT SUM(signed_amount) FROM wallet_ledger w WHERE w.user_id = uw.user_id AND w.merchant_id = v_mid), 0) AS ledger_sum
    FROM user_wallet uw
    WHERE uw.merchant_id = v_mid AND uw.user_id IN (
      SELECT v_c0
      UNION ALL
      SELECT id FROM (
        SELECT id FROM user_accounts
        WHERE merchant_id = v_mid AND external_user_id LIKE 'AUSV2-%'
        ORDER BY md5(id::text)
        LIMIT 20
      ) z
    )
  ) s
  WHERE s.header IS DISTINCT FROM s.ledger_sum;
  v_out := v_out || jsonb_build_object('wallet_mismatch', v_mismatch);
  IF v_mismatch > 0 THEN v_ok := false; v_fail := v_fail || ARRAY['wallet']; END IF;

  SELECT jsonb_object_agg(rfm_segment, cnt) INTO v_seg
  FROM (SELECT rfm_segment, count(*) AS cnt FROM rfm_user_score WHERE merchant_id = v_mid GROUP BY 1) x;
  v_out := v_out || jsonb_build_object('rfm', v_seg);
  IF v_seg IS NULL
     OR COALESCE((v_seg->>'Champions')::int,0) = 0
     OR COALESCE((v_seg->>'Lost')::int,0) = 0
     OR COALESCE((v_seg->>'At Risk')::int,0) = 0
     OR COALESCE((v_seg->>'Hibernating')::int,0) = 0
     OR COALESCE((v_seg->>'Regulars')::int,0) = 0
     OR COALESCE((v_seg->>'Loyal')::int,0) = 0
     OR COALESCE((v_seg->>'Promising')::int,0) = 0
     OR COALESCE((v_seg->>'Need Attention')::int,0) = 0
     OR COALESCE((v_seg->>'Big Spenders')::int,0) = 0
  THEN
    v_ok := false; v_fail := v_fail || ARRAY['rfm_segments'];
  END IF;

  v_out := v_out || jsonb_build_object('funnel', (
    SELECT jsonb_object_agg(name, cnt) FROM (
      SELECT a.name, count(*) FILTER (WHERE am.exited_at IS NULL) AS cnt
      FROM amp_audience_master a
      LEFT JOIN amp_audience_member am ON am.audience_id = a.id
      WHERE a.merchant_id = v_mid AND a.funnel_id = v_funnel_id
      GROUP BY a.name
    ) f
  ));
  IF EXISTS (
    SELECT 1 FROM amp_audience_master a
    WHERE a.merchant_id = v_mid AND a.funnel_id = v_funnel_id
      AND NOT EXISTS (SELECT 1 FROM amp_audience_member am WHERE am.audience_id = a.id AND am.exited_at IS NULL)
  ) THEN
    v_ok := false; v_fail := v_fail || ARRAY['funnel_empty_stage'];
  END IF;

  -- latest-wins: Program members should not also sit in Repeat as current
  SELECT count(*) INTO v_mismatch
  FROM amp_audience_member r
  JOIN amp_audience_master ra ON ra.id = r.audience_id AND ra.name = 'Repeat Buyer' AND ra.funnel_id = v_funnel_id
  JOIN amp_audience_member p ON p.user_id = r.user_id AND p.exited_at IS NULL
  JOIN amp_audience_master pa ON pa.id = p.audience_id AND pa.name = 'Program Member' AND pa.funnel_id = v_funnel_id
  WHERE r.exited_at IS NULL;
  v_out := v_out || jsonb_build_object('program_also_repeat', v_mismatch);
  IF v_mismatch > 0 THEN v_ok := false; v_fail := v_fail || ARRAY['funnel_latest_wins']; END IF;

  v_out := v_out || jsonb_build_object('amp', (
    SELECT jsonb_object_agg(name, cnt) FROM (
      SELECT a.name, count(*) FILTER (WHERE am.exited_at IS NULL) AS cnt
      FROM amp_audience_master a
      LEFT JOIN amp_audience_member am ON am.audience_id = a.id
      WHERE a.merchant_id = v_mid AND a.funnel_id IS NULL AND a.name LIKE 'Ausiris %'
      GROUP BY a.name
    ) x
  ));
  IF EXISTS (
    SELECT 1 FROM amp_audience_master a
    WHERE a.merchant_id = v_mid AND a.funnel_id IS NULL AND a.name LIKE 'Ausiris %'
      AND NOT EXISTS (SELECT 1 FROM amp_audience_member am WHERE am.audience_id = a.id AND am.exited_at IS NULL)
  ) THEN
    v_ok := false; v_fail := v_fail || ARRAY['amp_empty'];
  END IF;

  SELECT COALESCE(SUM(attributed_amount),0) INTO v_line
  FROM mkt_purchase_attribution a
  JOIN mkt_campaign c ON c.id = a.campaign_id
  WHERE a.merchant_id = v_mid AND c.name ILIKE '%Gold Saving%';
  SELECT COALESCE(SUM(attributed_amount),0) INTO v_fb
  FROM mkt_purchase_attribution a
  JOIN mkt_campaign c ON c.id = a.campaign_id
  WHERE a.merchant_id = v_mid AND c.name ILIKE '%Mother%';
  SELECT COALESCE(SUM(attributed_amount),0) INTO v_tt
  FROM mkt_purchase_attribution a
  JOIN mkt_campaign c ON c.id = a.campaign_id
  WHERE a.merchant_id = v_mid AND c.name ILIKE '%TikTok Gold Teaser%';
  v_out := v_out || jsonb_build_object('attr_line_saving', v_line, 'attr_fb_mother', v_fb, 'attr_tt_teaser', v_tt);
  IF NOT (v_tt < v_line AND v_tt < v_fb) THEN
    v_ok := false; v_fail := v_fail || ARRAY['tiktok_roi'];
  END IF;

  v_out := v_out || jsonb_build_object('c0', jsonb_build_object(
    'phone', '0812345678',
    'user_id', v_c0,
    'activity_types', (SELECT count(DISTINCT t.code) FROM activity_ledger a JOIN activity_type_master t ON t.id = a.activity_type_id WHERE a.user_id = v_c0),
    'earns', (SELECT count(*) FROM wallet_ledger WHERE user_id = v_c0 AND transaction_type = 'earn'),
    'burns', (SELECT count(*) FROM wallet_ledger WHERE user_id = v_c0 AND transaction_type = 'burn'),
    'redemptions', (SELECT count(*) FROM reward_redemptions_ledger WHERE user_id = v_c0),
    'lobs', (SELECT count(DISTINCT transaction_source) FROM purchase_ledger WHERE user_id = v_c0),
    'has_acquisition', (SELECT acquisition_campaign_id IS NOT NULL FROM user_accounts WHERE id = v_c0),
    'attributed', (SELECT count(*) FROM mkt_purchase_attribution WHERE user_id = v_c0)
  ));
  IF v_c0 IS NULL
     OR (SELECT count(DISTINCT t.code) FROM activity_ledger a JOIN activity_type_master t ON t.id = a.activity_type_id WHERE a.user_id = v_c0) < 6
     OR (SELECT count(*) FROM wallet_ledger WHERE user_id = v_c0 AND transaction_type = 'earn') < 1
     OR (SELECT count(*) FROM wallet_ledger WHERE user_id = v_c0 AND transaction_type = 'burn') < 1
     OR (SELECT count(*) FROM reward_redemptions_ledger WHERE user_id = v_c0) < 2
     OR (SELECT count(DISTINCT transaction_source) FROM purchase_ledger WHERE user_id = v_c0) < 2
     OR (SELECT count(*) FROM mkt_purchase_attribution WHERE user_id = v_c0) < 2
  THEN
    v_ok := false; v_fail := v_fail || ARRAY['c0'];
  END IF;

  v_out := v_out || jsonb_build_object('c8', jsonb_build_object(
    'phone', '0812345608',
    'activities', (SELECT count(*) FROM activity_ledger WHERE user_id = v_c8),
    'purchases', (SELECT count(*) FROM purchase_ledger WHERE user_id = v_c8)
  ));
  IF v_c8 IS NULL
     OR (SELECT count(*) FROM activity_ledger WHERE user_id = v_c8) = 0
     OR (SELECT count(*) FROM purchase_ledger WHERE user_id = v_c8) <> 0
  THEN
    v_ok := false; v_fail := v_fail || ARRAY['c8'];
  END IF;

  v_out := v_out || jsonb_build_object('grouping', (
    SELECT jsonb_object_agg(x.name, x.cnt) FROM (
      SELECT c.name, count(*) AS cnt
      FROM campaign c
      JOIN campaign_activity ca ON ca.campaign_id = c.id
      JOIN campaign_mapping cm ON cm.campaign_activity_id = ca.id
      WHERE c.merchant_id = v_mid
      GROUP BY c.name
    ) x
  ));
  IF (SELECT count(*) FROM campaign WHERE merchant_id = v_mid) < 4
     OR EXISTS (
       SELECT 1 FROM campaign c
       WHERE c.merchant_id = v_mid
         AND NOT EXISTS (
           SELECT 1 FROM campaign_activity ca JOIN campaign_mapping cm ON cm.campaign_activity_id = ca.id
           WHERE ca.campaign_id = c.id
         )
     )
  THEN
    v_ok := false; v_fail := v_fail || ARRAY['grouping'];
  END IF;

  SELECT count(*) INTO v_n FROM v_lb_ausiris_gold_spend WHERE merchant_id = v_mid;
  v_out := v_out || jsonb_build_object('lb_gold_rows', v_n,
    'lb_save_rows', (SELECT count(*) FROM v_lb_ausiris_saving_streak WHERE merchant_id = v_mid));
  IF v_n = 0 THEN v_ok := false; v_fail := v_fail || ARRAY['leaderboard']; END IF;

  v_out := v_out || jsonb_build_object(
    'earn_channels', (
      SELECT jsonb_object_agg(e.channel_code, cnt)
      FROM (
        SELECT e.channel_code, count(p.id) AS cnt
        FROM earn_channel e
        LEFT JOIN purchase_ledger p ON p.earning_channel_id = e.id AND p.merchant_id = e.merchant_id AND p.external_ref LIKE 'AUSV2%'
        WHERE e.merchant_id = v_mid
          AND e.channel_code IN ('trading','gold_saving','web','pos','vending','marketplace','live')
        GROUP BY e.channel_code
      ) x
      JOIN earn_channel e ON e.merchant_id = v_mid AND e.channel_code = x.channel_code
    ),
    'stores', (
      SELECT jsonb_object_agg(sm.store_code, cnt)
      FROM (
        SELECT sm.store_code, count(p.id) AS cnt
        FROM store_master sm
        LEFT JOIN purchase_ledger p ON p.store_id = sm.id AND p.external_ref LIKE 'AUSV2%'
        WHERE sm.merchant_id = v_mid
        GROUP BY sm.store_code
      ) x
      JOIN store_master sm ON sm.merchant_id = v_mid AND sm.store_code = x.store_code
    )
  );

  SELECT count(*) INTO v_mismatch
  FROM purchase_ledger p
  WHERE p.merchant_id = v_mid AND p.external_ref LIKE 'AUSV2%'
    AND (
      (p.store_code = 'AUS-NEXT-APP' AND COALESCE(p.metadata->>'sku','') NOT LIKE 'AUS-SPOT%')
      OR (p.store_code = 'AUS-PLUS-APP' AND COALESCE(p.metadata->>'sku','') NOT LIKE 'AUS-SAVE%')
      OR (p.store_code IN ('AUS-POS-SILOM','AUS-POS-SIAM','AUS-POS-CNX','AUS-EXPRESS-WEB','AUS-LAZADA')
          AND COALESCE(p.metadata->>'sku','') NOT LIKE 'AUS-BAR%')
      OR (p.store_code = 'AUS-POS-SLV-TDP' AND COALESCE(p.metadata->>'sku','') NOT LIKE 'AUS-SLV%')
      OR (p.store_code = 'AUS-VD-TDP'
          AND COALESCE(p.metadata->>'sku','') NOT LIKE 'AUS-SLV%'
          AND COALESCE(p.metadata->>'sku','') NOT IN ('AUS-BAR-1G','AUS-BAR-5G'))
      OR (p.store_code IN ('AUS-TIKTOK','AUS-IRIS-LIVE') AND COALESCE(p.metadata->>'sku','') NOT LIKE 'IRIS%')
      OR (p.store_code = 'AUS-SHOPEE'
          AND COALESCE(p.metadata->>'sku','') NOT LIKE 'AUS-BAR%'
          AND COALESCE(p.metadata->>'sku','') NOT LIKE 'IRIS%')
    );
  v_out := v_out || jsonb_build_object('channel_sku_mismatch', v_mismatch);
  IF v_mismatch > 0 THEN v_ok := false; v_fail := v_fail || ARRAY['channel_sku']; END IF;

  IF COALESCE((v_out->'earn_channels'->>'pos')::int, 0) > 0
     AND COALESCE((v_out->'earn_channels'->>'trading')::int, 0) = 0 THEN
    v_ok := false; v_fail := v_fail || ARRAY['channels_all_pos'];
  END IF;

  v_out := v_out || jsonb_build_object('workflows', (
    SELECT jsonb_build_object(
      'user_workflows', count(*),
      'started', (
        SELECT count(*) FROM workflow_log l
        JOIN workflow_master w ON w.id = l.workflow_id
        WHERE w.merchant_id = v_mid AND w.scope = 'user' AND l.event_type = 'execution_started'
      ),
      'days', (
        SELECT count(DISTINCT (l.created_at AT TIME ZONE 'Asia/Bangkok')::date)
        FROM workflow_log l
        JOIN workflow_master w ON w.id = l.workflow_id
        WHERE w.merchant_id = v_mid AND w.scope = 'user' AND l.event_type = 'execution_started'
      ),
      'clicks', (
        SELECT count(*) FROM amp_engagement_event e
        WHERE e.merchant_id = v_mid AND e.event_type = 'click' AND e.metadata->>'seed' = 'SEED-AUS-V2'
      )
    )
    FROM workflow_master
    WHERE merchant_id = v_mid AND scope = 'user' AND workflow_code LIKE 'aus-wf-%'
  ));
  IF (SELECT count(*) FROM workflow_master
      WHERE merchant_id = v_mid AND scope = 'user' AND workflow_code LIKE 'aus-wf-%') < 3
     OR (SELECT count(DISTINCT (l.created_at AT TIME ZONE 'Asia/Bangkok')::date)
         FROM workflow_log l
         JOIN workflow_master w ON w.id = l.workflow_id
         WHERE w.merchant_id = v_mid AND w.scope = 'user' AND l.event_type = 'execution_started') < 60
  THEN
    v_ok := false; v_fail := v_fail || ARRAY['workflows'];
  END IF;

  v_out := v_out || jsonb_build_object(
    'passed', v_ok,
    'failed_checks', to_jsonb(v_fail),
    'c0_phone', '0812345678',
    'walk_order', jsonb_build_array(
      'Marketing campaigns', 'Reports ROI', 'Acquisition', 'Funnel', 'RFM',
      'Audience builder', 'AMP analytics', 'C0 360', 'C5/C6 win-back', 'C8 unpaid'
    )
  );
  RETURN v_out;
END;
$fn$;

CREATE OR REPLACE FUNCTION public.custom_ausiris_demo_run()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $fn$
DECLARE
  v_m jsonb;
  v_c jsonb;
  v_e jsonb;
  v_u jsonb;
  v_l jsonb;
  v_n jsonb;
  v_ch jsonb;
  v_p jsonb;
  v_r jsonb;
  v_w jsonb;
  v_v jsonb;
BEGIN
  PERFORM custom_ausiris_demo_set_ctx();
  v_m := custom_ausiris_demo_bootstrap_masters();
  IF COALESCE((v_m->>'success')::boolean, false) IS DISTINCT FROM true THEN
    RETURN jsonb_build_object('success', false, 'step', 'masters', 'detail', v_m);
  END IF;
  v_c := custom_ausiris_demo_bootstrap_consent();
  IF COALESCE((v_c->>'success')::boolean, false) IS DISTINCT FROM true THEN
    RETURN jsonb_build_object('success', false, 'step', 'consent', 'detail', v_c);
  END IF;
  v_e := custom_ausiris_demo_bootstrap_engagement();
  IF COALESCE((v_e->>'success')::boolean, false) IS DISTINCT FROM true THEN
    RETURN jsonb_build_object('success', false, 'step', 'engagement', 'detail', v_e);
  END IF;
  v_u := custom_ausiris_demo_seed_members(10000);
  IF COALESCE((v_u->>'success')::boolean, false) IS DISTINCT FROM true THEN
    RETURN jsonb_build_object('success', false, 'step', 'members', 'detail', v_u);
  END IF;
  v_l := custom_ausiris_demo_seed_ledgers();
  IF COALESCE((v_l->>'success')::boolean, false) IS DISTINCT FROM true THEN
    RETURN jsonb_build_object('success', false, 'step', 'ledgers', 'detail', v_l);
  END IF;
  v_n := custom_ausiris_demo_seed_named_tour();
  IF COALESCE((v_n->>'success')::boolean, false) IS DISTINCT FROM true THEN
    RETURN jsonb_build_object('success', false, 'step', 'named', 'detail', v_n);
  END IF;
  v_ch := custom_ausiris_demo_remap_purchase_channels();
  IF COALESCE((v_ch->>'success')::boolean, false) IS DISTINCT FROM true THEN
    RETURN jsonb_build_object('success', false, 'step', 'channels', 'detail', v_ch);
  END IF;
  v_p := custom_ausiris_demo_seed_promo_codes();
  IF COALESCE((v_p->>'success')::boolean, false) IS DISTINCT FROM true THEN
    RETURN jsonb_build_object('success', false, 'step', 'promo', 'detail', v_p);
  END IF;
  v_r := custom_ausiris_demo_recompute();
  v_w := custom_ausiris_demo_seed_workflows();
  IF COALESCE((v_w->>'success')::boolean, false) IS DISTINCT FROM true THEN
    RETURN jsonb_build_object('success', false, 'step', 'workflows', 'detail', v_w);
  END IF;
  v_v := custom_ausiris_demo_verify();
  RETURN jsonb_build_object(
    'success', COALESCE((v_v->>'passed')::boolean, false),
    'masters', v_m,
    'consent', v_c,
    'engagement', v_e,
    'members', v_u,
    'ledgers', v_l,
    'named', v_n,
    'channels', v_ch,
    'promo', v_p,
    'recompute', v_r,
    'workflows', v_w,
    'verify', v_v
  );
END;
$fn$;
