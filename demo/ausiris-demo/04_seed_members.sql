-- Wipe prior SEED-AUS-V2 facts for this merchant only. Keeps rewards, tiers, catalog, test user.

CREATE OR REPLACE FUNCTION public.custom_ausiris_demo_reset_facts()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $fn$
DECLARE
  v_mid uuid := custom_ausiris_demo_merchant_id();
  v_n int;
BEGIN
  PERFORM custom_ausiris_demo_set_ctx();
  PERFORM set_config('redemption.skip_emit', 'true', true);

  DELETE FROM mkt_purchase_attribution WHERE merchant_id = v_mid;
  DELETE FROM rfm_user_score WHERE merchant_id = v_mid;
  DELETE FROM funnel_transition_ledger WHERE merchant_id = v_mid;
  DELETE FROM amp_audience_member aam
  USING amp_audience_master a
  WHERE aam.audience_id = a.id AND a.merchant_id = v_mid;

  DELETE FROM mission_log_completion WHERE merchant_id = v_mid
    AND user_id IN (SELECT id FROM user_accounts WHERE merchant_id = v_mid AND external_user_id LIKE 'AUSV2-%');
  DELETE FROM mission_progress WHERE user_id IN (
    SELECT id FROM user_accounts WHERE merchant_id = v_mid AND external_user_id LIKE 'AUSV2-%'
  );

  DELETE FROM activity_ledger WHERE merchant_id = v_mid AND (external_ref LIKE 'AUSV2-%' OR source = 'seed');
  DELETE FROM reward_redemptions_ledger WHERE merchant_id = v_mid AND (external_ref_id LIKE 'AUSV2-%' OR code LIKE 'AUSV2-%');
  DELETE FROM wallet_ledger WHERE merchant_id = v_mid AND (dedup_key LIKE 'AUSV2-%' OR metadata->>'seed' = 'SEED-AUS-V2');
  DELETE FROM purchase_items_ledger WHERE merchant_id = v_mid AND transaction_id IN (
    SELECT id FROM purchase_ledger WHERE merchant_id = v_mid AND (external_ref LIKE 'AUSV2-%' OR metadata->>'seed' = 'SEED-AUS-V2')
  );
  DELETE FROM purchase_ledger WHERE merchant_id = v_mid AND (external_ref LIKE 'AUSV2-%' OR metadata->>'seed' = 'SEED-AUS-V2');
  DELETE FROM user_tags WHERE merchant_id = v_mid AND user_id IN (
    SELECT id FROM user_accounts WHERE merchant_id = v_mid AND external_user_id LIKE 'AUSV2-%'
  );
  DELETE FROM user_wallet WHERE merchant_id = v_mid AND user_id IN (
    SELECT id FROM user_accounts WHERE merchant_id = v_mid AND external_user_id LIKE 'AUSV2-%'
  );
  DELETE FROM user_accounts WHERE merchant_id = v_mid AND external_user_id LIKE 'AUSV2-%';

  GET DIAGNOSTICS v_n = ROW_COUNT;
  RETURN jsonb_build_object('success', true, 'deleted_members', v_n);
END;
$fn$;

CREATE OR REPLACE FUNCTION public.custom_ausiris_demo_pick_archetype(p_key text)
RETURNS text
LANGUAGE plpgsql
STABLE
AS $$
DECLARE
  v_r double precision := custom_ausiris_demo_rand(p_key);
  v_acc double precision := 0;
  r record;
BEGIN
  FOR r IN
    SELECT code, (payload->>'weight')::double precision AS w
    FROM custom_ausiris_demo_config
    WHERE kind = 'archetype' AND is_active
    ORDER BY sort_order
  LOOP
    v_acc := v_acc + COALESCE(r.w, 0);
    IF v_r < v_acc THEN
      RETURN r.code;
    END IF;
  END LOOP;
  RETURN 'bar_shopper';
END;
$$;

CREATE OR REPLACE FUNCTION public.custom_ausiris_demo_seed_members(p_count integer DEFAULT 10000)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $fn$
DECLARE
  v_mid uuid := custom_ausiris_demo_merchant_id();
  v_tier_silver uuid := (custom_ausiris_demo_cfg('id', 'tier_silver')->>'id')::uuid;
  v_n int;
BEGIN
  PERFORM custom_ausiris_demo_set_ctx();
  PERFORM custom_ausiris_demo_reset_facts();

  WITH
  given AS (
    SELECT row_number() OVER (ORDER BY sort_order) - 1 AS rn, payload
    FROM custom_ausiris_demo_config WHERE kind = 'given_name' AND is_active
  ),
  sur AS (
    SELECT row_number() OVER (ORDER BY sort_order) - 1 AS rn, payload
    FROM custom_ausiris_demo_config WHERE kind = 'surname' AND is_active
  ),
  nick AS (
    SELECT row_number() OVER (ORDER BY sort_order) - 1 AS rn, payload
    FROM custom_ausiris_demo_config WHERE kind = 'nickname' AND is_active
  ),
  gc AS (SELECT count(*)::int AS n FROM given),
  sc AS (SELECT count(*)::int AS n FROM sur),
  nc AS (SELECT count(*)::int AS n FROM nick),
  named AS (
    SELECT (payload->>'seq')::int AS seq, code AS named_code, payload
    FROM custom_ausiris_demo_config WHERE kind = 'named' AND is_active
  ),
  src AS (
    SELECT
      i,
      n.named_code,
      n.payload AS named_payload,
      COALESCE(n.payload->>'archetype', custom_ausiris_demo_pick_archetype('arch-' || i::text)) AS archetype,
      g.payload AS gpay,
      s.payload AS spay,
      k.payload AS npay,
      CASE
        WHEN n.named_code = 'C9' THEN 175
        WHEN n.named_code = 'C0' THEN 155
        WHEN n.named_code = 'C10' THEN 159
        WHEN n.named_code IN ('C5', 'C6') THEN 40
        WHEN n.named_code = 'C7' THEN 5
        WHEN i <= 1200 THEN 0
        ELSE LEAST(180, round(180 * power((i - 1200)::numeric / GREATEST(p_count - 1200, 1), 0.72))::int)
      END AS day_off
    FROM generate_series(1, p_count) AS t(i)
    CROSS JOIN gc
    CROSS JOIN sc
    CROSS JOIN nc
    JOIN given g ON g.rn = (i - 1) % gc.n
    JOIN sur s ON s.rn = ((i - 1) / gc.n) % sc.n
    JOIN nick k ON k.rn = (i - 1) % nc.n
    LEFT JOIN named n ON n.seq = i
  )
  INSERT INTO user_accounts (
    id, merchant_id, role, user_type, firstname, lastname, fullname,
    email, tel, gender, birth_date, line_id,
    tier_id, persona_id, is_active, is_signup_form_complete,
    channel_email, channel_line, channel_sms, channel_push,
    created_at, acquired_at, updated_at,
    acquisition_source, acquisition_utm_source, acquisition_utm_medium,
    acquisition_utm_campaign, acquisition_campaign_id,
    external_user_id, skip_cdc, acquisition_attribution
  )
  SELECT
    gen_random_uuid(),
    v_mid,
    'user',
    'buyer',
    CASE WHEN custom_ausiris_demo_rand('th-'||i) < 0.55 THEN src.gpay->>'thai' ELSE src.gpay->>'romanized' END,
    CASE WHEN custom_ausiris_demo_rand('th-'||i) < 0.55 THEN src.spay->>'thai' ELSE src.spay->>'romanized' END,
    (src.gpay->>'romanized') || ' ' || (src.spay->>'romanized') || ' (' || (src.npay->>'romanized') || ')',
    CASE WHEN custom_ausiris_demo_rand('em-'||i) < 0.40
         THEN lower(src.gpay->>'romanized') || '.' || lower(src.spay->>'romanized') || i::text || '@ausiris.example'
         ELSE NULL END,
    COALESCE(src.named_payload->>'phone', '082' || lpad(i::text, 7, '0')),
    COALESCE(src.gpay->>'gender', 'u'),
    CASE WHEN custom_ausiris_demo_rand('bd-'||i) < 0.30
         THEN date '1978-01-01' + ((custom_ausiris_demo_rand('bdx-'||i) * 10000)::int)
         ELSE NULL END,
    CASE WHEN custom_ausiris_demo_rand('ln-'||i) < 0.75
         THEN 'U' || substr(md5('line-'||i::text), 1, 32)
         ELSE NULL END,
    v_tier_silver,
    CASE src.archetype
      WHEN 'whale_trader' THEN (custom_ausiris_demo_cfg('persona','aus-trader')->>'id')::uuid
      WHEN 'loyal_saver' THEN (custom_ausiris_demo_cfg('persona','aus-saver')->>'id')::uuid
      WHEN 'bar_shopper' THEN (custom_ausiris_demo_cfg('persona','aus-bar')->>'id')::uuid
      WHEN 'jewelry_gifter' THEN (custom_ausiris_demo_cfg('persona','aus-jewel')->>'id')::uuid
      WHEN 'cooling_vip' THEN (custom_ausiris_demo_cfg('persona','aus-lapsed')->>'id')::uuid
      WHEN 'hibernating' THEN (custom_ausiris_demo_cfg('persona','aus-lapsed')->>'id')::uuid
      WHEN 'omni_program' THEN (custom_ausiris_demo_cfg('persona','aus-saver')->>'id')::uuid
      WHEN 'first_purchase' THEN (custom_ausiris_demo_cfg('persona','aus-saver')->>'id')::uuid
      ELSE (custom_ausiris_demo_cfg('persona','aus-trader')->>'id')::uuid
    END,
    true,
    true,
    custom_ausiris_demo_rand('em-'||i) < 0.40,
    custom_ausiris_demo_rand('ln-'||i) < 0.75,
    false,
    true,
    ((current_date - 180 + src.day_off)::timestamp + (custom_ausiris_demo_rand('hr-'||i) * 20 || ' hours')::interval) AT TIME ZONE 'Asia/Bangkok',
    ((current_date - 180 + src.day_off)::timestamp + (custom_ausiris_demo_rand('hr-'||i) * 20 || ' hours')::interval) AT TIME ZONE 'Asia/Bangkok',
    now(),
    CASE
      WHEN src.archetype IN ('jewelry_gifter') THEN 'facebook'
      WHEN src.archetype IN ('new_lead', 'high_intent_unpaid') THEN 'tiktok'
      WHEN src.archetype IN ('loyal_saver', 'omni_program') THEN 'line'
      WHEN src.archetype IN ('whale_trader') THEN 'google'
      ELSE 'organic'
    END,
    CASE
      WHEN src.archetype IN ('jewelry_gifter') THEN 'facebook'
      WHEN src.archetype IN ('new_lead', 'high_intent_unpaid') THEN 'tiktok'
      WHEN src.archetype IN ('loyal_saver', 'omni_program') THEN 'line'
      WHEN src.archetype IN ('whale_trader') THEN 'google'
      ELSE 'direct'
    END,
    CASE
      WHEN src.archetype IN ('jewelry_gifter') THEN 'cpc'
      WHEN src.archetype IN ('new_lead') THEN 'cpc'
      WHEN src.archetype IN ('loyal_saver', 'omni_program') THEN 'push'
      ELSE 'none'
    END,
    CASE
      WHEN src.archetype IN ('jewelry_gifter') THEN 'aus-fb-mother'
      WHEN src.archetype IN ('new_lead', 'high_intent_unpaid') THEN 'aus-tt-teaser'
      WHEN src.archetype IN ('loyal_saver', 'omni_program') THEN 'aus-line-gold'
      WHEN src.archetype IN ('whale_trader') THEN 'aus-g-brand'
      WHEN src.archetype IN ('bar_shopper') THEN 'aus-line-bar'
      ELSE NULL
    END,
    CASE
      WHEN src.archetype IN ('jewelry_gifter') THEN (custom_ausiris_demo_cfg('mkt','aus-fb-mother')->>'id')::uuid
      WHEN src.archetype IN ('new_lead', 'high_intent_unpaid') THEN (custom_ausiris_demo_cfg('mkt','aus-tt-teaser')->>'id')::uuid
      WHEN src.archetype IN ('loyal_saver', 'omni_program') THEN (custom_ausiris_demo_cfg('mkt','aus-line-gold')->>'id')::uuid
      WHEN src.archetype IN ('whale_trader') THEN (custom_ausiris_demo_cfg('mkt','aus-g-brand')->>'id')::uuid
      WHEN src.archetype IN ('bar_shopper') THEN (custom_ausiris_demo_cfg('mkt','aus-line-bar')->>'id')::uuid
      ELSE NULL
    END,
    'AUSV2-' || lpad(i::text, 5, '0'),
    true,
    jsonb_build_object(
      'seed', 'SEED-AUS-V2',
      'archetype', src.archetype,
      'named', src.named_code,
      'seq', i
    )
  FROM src;

  GET DIAGNOSTICS v_n = ROW_COUNT;

  INSERT INTO user_wallet (user_id, merchant_id, points_balance, ticket_balance, created_at)
  SELECT id, v_mid, 0, 0, created_at
  FROM user_accounts
  WHERE merchant_id = v_mid AND external_user_id LIKE 'AUSV2-%'
  ON CONFLICT (user_id, merchant_id) DO NOTHING;

  PERFORM fn_ensure_member_code(u.id, v_mid)
  FROM user_accounts u
  WHERE u.merchant_id = v_mid AND u.external_user_id LIKE 'AUSV2-%' AND u.member_code IS NULL;

  RETURN jsonb_build_object('success', true, 'members', v_n);
END;
$fn$;
