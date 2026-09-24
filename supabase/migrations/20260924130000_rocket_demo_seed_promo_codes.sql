-- Rocket Demo: promo code pools + realistic issued/used/expired states (idempotent via RKT2-* lots).
-- Run: SELECT custom_rocket_demo_seed_promo_codes();

CREATE OR REPLACE FUNCTION public.custom_rocket_demo_merchant_id()
 RETURNS uuid
 LANGUAGE sql
 STABLE
AS $function$
  SELECT id FROM merchant_master WHERE merchant_code = 'rocket-demo' LIMIT 1;
$function$;

CREATE OR REPLACE FUNCTION public.custom_rocket_demo_seed_promo_codes()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_mid uuid := custom_rocket_demo_merchant_id();
  v_codes int;
  v_issued int;
  v_used int;
  v_mv jsonb;
BEGIN
  IF v_mid IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'rocket-demo merchant not found');
  END IF;

  UPDATE reward_master
  SET assign_promocode = true
  WHERE merchant_id = v_mid
    AND (
      name ILIKE '%Shopee%' OR name ILIKE '%LAZADA%'
      OR name ILIKE '%STARBUCKS%' OR name ILIKE '%CENTRAL%'
      OR name ILIKE '%EVEANDBOY%'
    );

  INSERT INTO partner_merchant (merchant_id, partner_code, partner_name, active_status)
  VALUES
    (v_mid, 'RKT-SHP', 'Shopee', true),
    (v_mid, 'RKT-LZD', 'Lazada', true),
    (v_mid, 'RKT-CTL', 'Central', true),
    (v_mid, 'RKT-SBX', 'Starbucks', true),
    (v_mid, 'RKT-EVB', 'EVEANDBOY', true)
  ON CONFLICT (merchant_id, partner_code) DO UPDATE
    SET partner_name = EXCLUDED.partner_name, active_status = true, updated_at = now();

  UPDATE reward_redemptions_ledger
  SET promo_code = NULL, promo_code_id = NULL,
      used_status = false, used_at = NULL, use_expire_date = NULL
  WHERE merchant_id = v_mid
    AND promo_code_id IN (
      SELECT id FROM reward_promo_code WHERE merchant_id = v_mid AND lot_code LIKE 'RKT2-%'
    );

  DELETE FROM reward_promo_code
  WHERE merchant_id = v_mid AND lot_code LIKE 'RKT2-%';

  WITH spec (
    reward_name, partner_code, prefix, batch, lot, total, used_n, claimed_n, expired_n
  ) AS (
    VALUES
      ('Shopee Cash Coupon 200 THB',      'RKT-SHP', 'RKT-SHP-', 'Shopee partner lot Sep 2026',      'RKT2-SHP-202609', 50,  5, 18, 2),
      ('LAZADA Cash Coupon 200 THB',      'RKT-LZD', 'RKT-LZD-', 'Lazada partner lot Sep 2026',      'RKT2-LZD-202609', 80, 15, 25, 3),
      ('STARBUCKS Cash Coupon 200 THB',    'RKT-SBX', 'RKT-SBX-', 'Starbucks partner lot Sep 2026',   'RKT2-SBX-202609', 100, 22, 38, 5),
      ('CENTRAL Cash Coupon 100 THB',      'RKT-CTL', 'RKT-CTL-', 'Central partner lot Sep 2026',     'RKT2-CTL-202609', 80, 12, 24, 2),
      ('EVEANDBOY Cash Coupon 100 THB',    'RKT-EVB', 'RKT-EVB-', 'EVEANDBOY partner lot Sep 2026', 'RKT2-EVB-202609', 60, 10, 18, 2)
  ),
  resolved AS (
    SELECT
      rm.id AS reward_id,
      pm.id AS partner_id,
      s.*
    FROM spec s
    JOIN reward_master rm ON rm.merchant_id = v_mid AND rm.name = s.reward_name
    JOIN partner_merchant pm ON pm.merchant_id = v_mid AND pm.partner_code = s.partner_code
  )
  INSERT INTO reward_promo_code (
    merchant_id, reward_id, source_id, promo_code, name, lot_code, redeemed_status, created_at
  )
  SELECT
    v_mid,
    r.reward_id,
    r.partner_id,
    r.prefix || lpad(g.i::text, 4, '0'),
    r.batch,
    r.lot,
    g.i <= (r.used_n + r.claimed_n + r.expired_n),
    now() - interval '45 days' + (g.i || ' hours')::interval
  FROM resolved r
  CROSS JOIN LATERAL generate_series(1, r.total) AS g(i);

  GET DIAGNOSTICS v_codes = ROW_COUNT;

  WITH spec (reward_name, used_n, claimed_n, expired_n) AS (
    VALUES
      ('Shopee Cash Coupon 200 THB',      5, 18, 2),
      ('LAZADA Cash Coupon 200 THB',      15, 25, 3),
      ('STARBUCKS Cash Coupon 200 THB',    22, 38, 5),
      ('CENTRAL Cash Coupon 100 THB',      12, 24, 2),
      ('EVEANDBOY Cash Coupon 100 THB',    10, 18, 2)
  ),
  codes AS (
    SELECT
      rpc.id,
      rpc.promo_code,
      rpc.reward_id,
      rm.name AS reward_name,
      s.used_n, s.claimed_n, s.expired_n,
      row_number() OVER (PARTITION BY rpc.reward_id ORDER BY rpc.promo_code) AS rn
    FROM reward_promo_code rpc
    JOIN reward_master rm ON rm.id = rpc.reward_id
    JOIN spec s ON s.reward_name = rm.name
    WHERE rpc.merchant_id = v_mid
      AND rpc.lot_code LIKE 'RKT2-%'
      AND rpc.redeemed_status
  ),
  rdms AS (
    SELECT
      l.id AS redemption_id,
      l.user_id,
      l.reward_id,
      l.redeemed_at,
      row_number() OVER (
        PARTITION BY l.reward_id
        ORDER BY l.redeemed_at NULLS LAST, l.id
      ) AS rn
    FROM reward_redemptions_ledger l
    WHERE l.merchant_id = v_mid
      AND l.success IS DISTINCT FROM false
      AND COALESCE(l.cancelled, false) = false
      AND l.reward_id IN (SELECT DISTINCT reward_id FROM codes)
  )
  UPDATE reward_redemptions_ledger l
  SET
    promo_code = c.promo_code,
    promo_code_id = c.id,
    used_status = (c.rn <= c.used_n),
    used_at = CASE
      WHEN c.rn <= c.used_n THEN COALESCE(l.redeemed_at, now()) + interval '3 days'
      ELSE NULL
    END,
    use_expire_date = CASE
      WHEN c.rn > c.used_n AND c.rn <= (c.used_n + c.claimed_n + c.expired_n)
           AND c.rn > (c.used_n + c.claimed_n)
        THEN now() - interval '10 days'
      WHEN c.rn > c.used_n AND c.rn <= (c.used_n + c.claimed_n)
        THEN now() + interval '90 days'
      ELSE l.use_expire_date
    END
  FROM codes c
  JOIN rdms r ON r.reward_id = c.reward_id AND r.rn = c.rn
  WHERE l.id = r.redemption_id
    AND c.rn <= (c.used_n + c.claimed_n + c.expired_n);

  GET DIAGNOSTICS v_issued = ROW_COUNT;

  SELECT count(*) INTO v_used
  FROM reward_redemptions_ledger
  WHERE merchant_id = v_mid AND promo_code LIKE 'RKT-%' AND used_status;

  BEGIN
    PERFORM refresh_promo_code_summary();
    v_mv := jsonb_build_object('ok', true);
  EXCEPTION WHEN OTHERS THEN
    v_mv := jsonb_build_object('ok', false, 'error', SQLERRM);
  END;

  RETURN jsonb_build_object(
    'success', true,
    'merchant_id', v_mid,
    'codes', v_codes,
    'issued', v_issued,
    'used', v_used,
    'available', v_codes - v_issued,
    'partners', 5,
    'mv', v_mv
  );
END;
$function$;
