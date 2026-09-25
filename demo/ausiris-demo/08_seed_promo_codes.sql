-- Partner-voucher promo pool for Ausiris. Idempotent. Does not touch other merchants.
-- Click-in statuses come from v_reward_promo_code_list: Available / Claimed / Used / Usage Expired.

CREATE OR REPLACE FUNCTION public.custom_ausiris_demo_seed_promo_codes()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $fn$
DECLARE
  v_mid uuid := custom_ausiris_demo_merchant_id();
  v_codes int;
  v_issued int;
  v_used int;
  v_mv jsonb;
BEGIN
  PERFORM custom_ausiris_demo_set_ctx();

  -- Unique codes on partner e-vouchers only. Stamping + first-time 50% stay shared.
  UPDATE reward_master
  SET assign_promocode = true
  WHERE merchant_id = v_mid
    AND (
      name ILIKE '%Shopee%' OR name ILIKE '%Lazada%'
      OR name ILIKE '%Starbucks%' OR name ILIKE '%Central%'
      OR name ILIKE '%E-Coupon%'
    );

  INSERT INTO partner_merchant (merchant_id, partner_code, partner_name, active_status)
  VALUES
    (v_mid, 'AUS-SHP', 'Shopee', true),
    (v_mid, 'AUS-LZD', 'Lazada', true),
    (v_mid, 'AUS-CTL', 'Central', true),
    (v_mid, 'AUS-SBX', 'Starbucks', true),
    (v_mid, 'AUS-ECN', 'Partner E-Coupon', true)
  ON CONFLICT (merchant_id, partner_code) DO UPDATE
    SET partner_name = EXCLUDED.partner_name, active_status = true, updated_at = now();

  -- Clear prior seed so re-run is safe (FK: redemptions.promo_code_id → reward_promo_code)
  UPDATE reward_redemptions_ledger
  SET promo_code = NULL, promo_code_id = NULL,
      used_status = false, used_at = NULL, use_expire_date = NULL
  WHERE merchant_id = v_mid
    AND promo_code_id IN (
      SELECT id FROM reward_promo_code WHERE merchant_id = v_mid AND lot_code LIKE 'AUSV2-%'
    );

  DELETE FROM reward_promo_code
  WHERE merchant_id = v_mid AND lot_code LIKE 'AUSV2-%';

  WITH spec (
    reward_name, partner_code, prefix, batch, lot, total, used_n, claimed_n, expired_n
  ) AS (
    VALUES
      ('Shopee E-Voucher 20 บาท',    'AUS-SHP', 'AUS-SHP-', 'Shopee partner lot Aug 2026',    'AUSV2-SHP-202608', 80, 12, 20, 3),
      ('Lazada E-Voucher 20 บาท',    'AUS-LZD', 'AUS-LZD-', 'Lazada partner lot Aug 2026',    'AUSV2-LZD-202608', 80, 12, 20, 3),
      ('Central E-Voucher 50 บาท',   'AUS-CTL', 'AUS-CTL-', 'Central partner lot Aug 2026',   'AUSV2-CTL-202608', 70, 10, 18, 2),
      ('Starbucks E-Voucher 50 บาท', 'AUS-SBX', 'AUS-SBX-', 'Starbucks partner lot Aug 2026', 'AUSV2-SBX-202608', 70, 10, 18, 2),
      ('E-Coupon มูลค่า 100 บาท',     'AUS-ECN', 'AUS-ECN-', 'E-Coupon partner lot Aug 2026',  'AUSV2-ECN-202608', 60,  8, 15, 2)
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
    now() - interval '40 days' + (g.i || ' hours')::interval
  FROM resolved r
  CROSS JOIN LATERAL generate_series(1, r.total) AS g(i);

  GET DIAGNOSTICS v_codes = ROW_COUNT;

  -- Attach issued codes to existing redemptions. C0 Shopee gets a Claimed (still-to-use) code.
  WITH spec (reward_name, used_n, claimed_n, expired_n) AS (
    VALUES
      ('Shopee E-Voucher 20 บาท',    12, 20, 3),
      ('Lazada E-Voucher 20 บาท',    12, 20, 3),
      ('Central E-Voucher 50 บาท',   10, 18, 2),
      ('Starbucks E-Voucher 50 บาท', 10, 18, 2),
      ('E-Coupon มูลค่า 100 บาท',      8, 15, 2)
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
      AND rpc.lot_code LIKE 'AUSV2-%'
      AND rpc.redeemed_status
  ),
  rdms AS (
    SELECT
      l.id AS redemption_id,
      l.reward_id,
      l.redeemed_at,
      row_number() OVER (
        PARTITION BY l.reward_id
        ORDER BY CASE WHEN l.external_ref_id = 'AUSV2-C0-RDM-SHOPEE' THEN 0 ELSE 1 END,
                 l.redeemed_at, l.id
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
      WHEN c.rn <= c.used_n THEN COALESCE(l.redeemed_at, now()) + interval '2 days'
      ELSE NULL
    END,
    use_expire_date = CASE
      WHEN c.rn > c.used_n AND c.rn <= (c.used_n + c.claimed_n + c.expired_n)
           AND c.rn > (c.used_n + c.claimed_n)
        THEN now() - interval '7 days'
      WHEN c.rn > c.used_n AND c.rn <= (c.used_n + c.claimed_n)
        THEN now() + interval '60 days'
      ELSE l.use_expire_date
    END
  FROM codes c
  JOIN rdms r ON r.reward_id = c.reward_id AND r.rn = c.rn
  WHERE l.id = r.redemption_id
    AND c.rn <= (c.used_n + c.claimed_n + c.expired_n);

  GET DIAGNOSTICS v_issued = ROW_COUNT;

  -- C0 walk: Shopee voucher is claimed, still to use (not consumed).
  UPDATE reward_redemptions_ledger
  SET used_status = false, used_at = NULL, use_expire_date = now() + interval '60 days'
  WHERE merchant_id = v_mid AND external_ref_id = 'AUSV2-C0-RDM-SHOPEE';

  SELECT count(*) INTO v_used
  FROM reward_redemptions_ledger
  WHERE merchant_id = v_mid AND promo_code LIKE 'AUS-%' AND used_status;

  BEGIN
    PERFORM refresh_promo_code_summary();
    v_mv := jsonb_build_object('ok', true);
  EXCEPTION WHEN OTHERS THEN
    v_mv := jsonb_build_object('ok', false, 'error', SQLERRM);
  END;

  RETURN jsonb_build_object(
    'success', true,
    'codes', v_codes,
    'issued', v_issued,
    'used', v_used,
    'available', v_codes - v_issued,
    'partners', 5,
    'mv', v_mv
  );
END;
$fn$;
