-- One-shot: mark historical Rocket Demo redemptions as used at lifestyle retailers.
-- Idempotent via enrich_log code redemption_usage_v1.
CREATE OR REPLACE FUNCTION public.custom_internal_demo_enrich_redemption_usage()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $fn$
DECLARE
  v_settings jsonb := custom_internal_demo_settings();
  v_merchant_id uuid;
  v_usage_store_ids uuid[];
  v_updated int := 0;
  v_candidates int := 0;
  v_redemption record;
  v_use_store_id uuid;
  v_use_lag int;
  v_use_ts timestamptz;
BEGIN
  IF v_settings IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'settings missing');
  END IF;
  v_merchant_id := (v_settings->>'merchant_id')::uuid;

  IF EXISTS (
    SELECT 1 FROM custom_internal_demo_config
    WHERE kind = 'enrich_log' AND code = 'redemption_usage_v1'
  ) THEN
    RETURN jsonb_build_object('success', true, 'skipped', true, 'reason', 'already_enriched');
  END IF;

  SELECT array_agg(x::uuid) INTO v_usage_store_ids
  FROM jsonb_array_elements_text(coalesce(v_settings->'usage_store_ids', '[]'::jsonb)) AS t(x);

  IF v_usage_store_ids IS NULL OR coalesce(array_length(v_usage_store_ids, 1), 0) = 0 THEN
    SELECT array_agg(sm.id ORDER BY sm.store_code) INTO v_usage_store_ids
    FROM store_master sm
    WHERE sm.merchant_id = v_merchant_id
      AND sm.store_code LIKE 'RKT-%'
      AND sm.store_code NOT IN ('RKT-ONLINE', 'RKT-SHOPEE', 'RKT-LAZ', 'RKT-TT');
  END IF;

  IF v_usage_store_ids IS NULL OR coalesce(array_length(v_usage_store_ids, 1), 0) = 0 THEN
    RETURN jsonb_build_object('success', false, 'error', 'usage_store_ids missing — run bootstrap first');
  END IF;

  SELECT count(*) INTO v_candidates
  FROM reward_redemptions_ledger r
  WHERE r.merchant_id = v_merchant_id
    AND coalesce(r.success, true)
    AND coalesce(r.cancelled, false) = false
    AND coalesce(r.used_status, false) = false;

  FOR v_redemption IN
    SELECT r.id, r.redeemed_at
    FROM reward_redemptions_ledger r
    WHERE r.merchant_id = v_merchant_id
      AND coalesce(r.success, true)
      AND coalesce(r.cancelled, false) = false
      AND coalesce(r.used_status, false) = false
  LOOP
    -- leave ~35% open in wallet for funnel demos
    IF custom_internal_demo_rand(v_redemption.id::text || ':enrich-use') >= 0.65 THEN
      CONTINUE;
    END IF;

    v_use_lag := 2 + floor(custom_internal_demo_rand(v_redemption.id::text || ':enrich-lag') * 14)::int;
    v_use_ts := v_redemption.redeemed_at + make_interval(
      days => v_use_lag,
      hours => 10 + floor(custom_internal_demo_rand(v_redemption.id::text || ':enrich-h') * 8)::int
    );
    IF v_use_ts > now() THEN
      v_use_ts := now() - make_interval(hours => 1 + floor(custom_internal_demo_rand(v_redemption.id::text || ':enrich-now') * 48)::int);
    END IF;

    v_use_store_id := v_usage_store_ids[
      1 + floor(
        custom_internal_demo_rand(v_redemption.id::text || ':enrich-store')
        * array_length(v_usage_store_ids, 1)
      )::int
    ];

    UPDATE reward_redemptions_ledger
    SET used_status = true,
        used_at = v_use_ts,
        used_store_id = v_use_store_id,
        used_qty = coalesce(used_qty, qty, 1),
        fulfillment_status = 'completed'
    WHERE id = v_redemption.id
      AND coalesce(used_status, false) = false;

    IF FOUND THEN
      v_updated := v_updated + 1;
    END IF;
  END LOOP;

  INSERT INTO custom_internal_demo_config (kind, code, payload, is_active, sort_order)
  VALUES (
    'enrich_log', 'redemption_usage_v1',
    jsonb_build_object(
      'candidates', v_candidates,
      'updated', v_updated,
      'usage_stores', coalesce(array_length(v_usage_store_ids, 1), 0),
      'finished_at', now()
    ),
    true, 0
  )
  ON CONFLICT (kind, code) DO UPDATE
  SET payload = EXCLUDED.payload, updated_at = now();

  RETURN jsonb_build_object(
    'success', true,
    'candidates', v_candidates,
    'updated', v_updated,
    'usage_stores', coalesce(array_length(v_usage_store_ids, 1), 0)
  );
END;
$fn$;
