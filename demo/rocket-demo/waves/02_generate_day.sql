-- Day generator: signups → purchases/items → points → redemptions → tier touch → run_log
CREATE OR REPLACE FUNCTION public.custom_internal_demo_pick_archetype(p_key text)
RETURNS text
LANGUAGE plpgsql
STABLE
AS $fn$
DECLARE
  v_roll double precision := custom_internal_demo_rand(p_key || ':arch');
  v_cum double precision := 0;
  r record;
BEGIN
  FOR r IN
    SELECT code, coalesce((payload->>'weight')::double precision, 0.2) AS w
    FROM custom_internal_demo_config
    WHERE kind = 'archetype' AND is_active
    ORDER BY sort_order
  LOOP
    v_cum := v_cum + r.w;
    IF v_roll <= v_cum THEN
      RETURN r.code;
    END IF;
  END LOOP;
  RETURN 'occasional';
END;
$fn$;

CREATE OR REPLACE FUNCTION public.custom_internal_demo_campaign_boost(p_date date)
RETURNS double precision
LANGUAGE plpgsql
STABLE
AS $fn$
DECLARE
  v_settings jsonb := custom_internal_demo_settings();
  v_anchor date := coalesce((v_settings->>'seed_anchor')::date, current_date);
  v_boost double precision := 1.0;
  r record;
  v_start date;
  v_end date;
BEGIN
  FOR r IN
    SELECT payload
    FROM custom_internal_demo_config
    WHERE kind = 'campaign' AND is_active
  LOOP
    v_start := v_anchor + ((r.payload->>'start_offset_days')::int);
    v_end := v_anchor + ((r.payload->>'end_offset_days')::int);
    IF p_date BETWEEN v_start AND v_end THEN
      v_boost := greatest(v_boost, coalesce((r.payload->>'propensity_boost')::double precision, 1.0));
    END IF;
  END LOOP;
  RETURN v_boost;
END;
$fn$;

CREATE OR REPLACE FUNCTION public.custom_internal_demo_target_members(p_day_index int, p_target int)
RETURNS int
LANGUAGE sql
IMMUTABLE
AS $$
  -- Smooth growth from ~12% to 100% of target across seed window
  SELECT greatest(
    1,
    least(
      p_target,
      (0.12 * p_target + 0.88 * p_target * power(least(greatest(p_day_index, 0), 180)::numeric / 180.0, 1.15))::int
    )
  );
$$;

CREATE OR REPLACE FUNCTION public.custom_internal_demo_generate_day(
  p_date date,
  p_mode text DEFAULT 'backfill' -- backfill | live
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $fn$
DECLARE
  v_settings jsonb := custom_internal_demo_settings();
  v_merchant_id uuid;
  v_seed_tag text := 'SEED-RKT';
  v_target int := 2500;
  v_seed_days int := 180;
  v_points_per_thb numeric := 0.1;
  v_anchor date;
  v_day_index int;
  v_noise double precision;
  v_campaign_boost double precision;
  v_dow_factor double precision;
  v_current_members int;
  v_target_members int;
  v_new_signups int;
  v_counts jsonb := '{}'::jsonb;
  v_signups int := 0;
  v_purchases int := 0;
  v_items int := 0;
  v_wallet int := 0;
  v_redeems int := 0;
  v_tier_updates int := 0;
  v_errors text[] := ARRAY[]::text[];
  v_user_id uuid;
  v_arch text;
  v_arch_payload jsonb;
  v_gn jsonb;
  v_sn jsonb;
  v_gn_n int;
  v_sn_n int;
  v_gn_i int;
  v_sn_i int;
  v_firstname text;
  v_lastname text;
  v_firstname_th text;
  v_lastname_th text;
  v_gender text;
  v_email text;
  v_tel text;
  v_ts timestamptz;
  v_member record;
  v_roll double precision;
  v_prop double precision;
  v_days_since int;
  v_decay double precision;
  v_basket numeric;
  v_purchase_id uuid;
  v_store_id uuid;
  v_store_ids uuid[];
  v_usage_store_ids uuid[];
  v_use_store_id uuid;
  v_uses int := 0;
  v_earn_channel_id uuid;
  v_redemption record;
  v_use_lag int;
  v_use_ts timestamptz;
  v_sku record;
  v_line_count int;
  v_line_total numeric;
  v_qty numeric;
  v_final numeric;
  v_points int;
  v_wallet_bal int;
  v_reward record;
  v_code text;
  v_tier_member uuid;
  v_tier_silver uuid;
  v_tier_gold uuid;
  v_tier_plat uuid;
  v_lifetime numeric;
  v_new_tier uuid;
  v_i int;
  v_mode text := lower(coalesce(p_mode, 'backfill'));
BEGIN
  IF v_settings IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'settings missing');
  END IF;

  v_merchant_id := (v_settings->>'merchant_id')::uuid;
  v_seed_tag := coalesce(v_settings->>'seed_tag', 'SEED-RKT');
  v_target := coalesce((v_settings->>'target_members')::int, 2500);
  v_seed_days := coalesce((v_settings->>'seed_days')::int, 180);
  v_points_per_thb := coalesce((v_settings->>'points_per_thb')::numeric, 0.1);
  v_anchor := coalesce((v_settings->>'seed_anchor')::date, current_date);
  v_day_index := (p_date - (v_anchor - v_seed_days));
  v_tier_member := (v_settings->>'tier_member_id')::uuid;
  v_tier_silver := (v_settings->>'tier_silver_id')::uuid;
  v_tier_gold := (v_settings->>'tier_gold_id')::uuid;
  v_tier_plat := (v_settings->>'tier_platinum_id')::uuid;
  v_earn_channel_id := (v_settings->>'earn_channel_id')::uuid;
  SELECT array_agg(x::uuid) INTO v_store_ids
  FROM jsonb_array_elements_text(coalesce(v_settings->'store_ids', '[]'::jsonb)) AS t(x);
  SELECT array_agg(x::uuid) INTO v_usage_store_ids
  FROM jsonb_array_elements_text(coalesce(v_settings->'usage_store_ids', '[]'::jsonb)) AS t(x);
  IF v_usage_store_ids IS NULL OR coalesce(array_length(v_usage_store_ids, 1), 0) = 0 THEN
    -- Fallback: any non-marketplace / non-online RKT store
    SELECT array_agg(id ORDER BY store_code) INTO v_usage_store_ids
    FROM store_master
    WHERE merchant_id = v_merchant_id
      AND store_code LIKE 'RKT-%'
      AND store_code NOT IN ('RKT-ONLINE', 'RKT-SHOPEE', 'RKT-LAZ', 'RKT-TT');
  END IF;

  -- Idempotency
  IF EXISTS (
    SELECT 1 FROM custom_internal_demo_config
    WHERE kind = 'run_log' AND code = p_date::text
  ) THEN
    RETURN jsonb_build_object('success', true, 'skipped', true, 'date', p_date, 'reason', 'already_ran');
  END IF;

  IF v_tier_member IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'bootstrap required (tier_member_id missing)');
  END IF;

  v_noise := 0.85 + 0.30 * custom_internal_demo_rand(p_date::text || ':noise');
  v_campaign_boost := custom_internal_demo_campaign_boost(p_date);
  -- Weekend busier
  v_dow_factor := CASE EXTRACT(DOW FROM p_date)::int
    WHEN 0 THEN 1.15
    WHEN 5 THEN 1.10
    WHEN 6 THEN 1.20
    WHEN 1 THEN 0.90
    ELSE 1.0
  END;

  SELECT count(*) INTO v_gn_n FROM custom_internal_demo_config WHERE kind='given_name' AND is_active;
  SELECT count(*) INTO v_sn_n FROM custom_internal_demo_config WHERE kind='surname' AND is_active;

  -- Wave 1: signups toward growth curve
  SELECT count(*) INTO v_current_members
  FROM user_accounts
  WHERE merchant_id = v_merchant_id AND role = 'user' AND deleted_at IS NULL;

  v_target_members := custom_internal_demo_target_members(v_day_index, v_target);
  -- daily mode: small trickle of new signups
  IF v_mode = 'live' THEN
    v_new_signups := greatest(0, round(coalesce((v_settings->>'daily_new_signups_mean')::numeric, 8)
      * v_noise * v_dow_factor * v_campaign_boost / 1.2)::int);
    v_new_signups := least(v_new_signups, 25);
  ELSE
    v_new_signups := greatest(0, v_target_members - v_current_members);
    -- Cap per day to avoid bursts, but allow early catch-up toward ~300 cohort
    v_new_signups := least(v_new_signups, 120);
  END IF;

  FOR v_i IN 1..v_new_signups LOOP
    BEGIN
      v_user_id := gen_random_uuid();
      v_arch := custom_internal_demo_pick_archetype(v_user_id::text || p_date::text);
      v_gn_i := 1 + floor(custom_internal_demo_rand(v_user_id::text || ':gn') * v_gn_n)::int;
      v_sn_i := 1 + floor(custom_internal_demo_rand(v_user_id::text || ':sn') * v_sn_n)::int;
      SELECT payload INTO v_gn FROM (
        SELECT payload, row_number() OVER (ORDER BY sort_order, code) AS rn
        FROM custom_internal_demo_config WHERE kind='given_name' AND is_active
      ) s WHERE rn = least(v_gn_i, v_gn_n);
      SELECT payload INTO v_sn FROM (
        SELECT payload, row_number() OVER (ORDER BY sort_order, code) AS rn
        FROM custom_internal_demo_config WHERE kind='surname' AND is_active
      ) s WHERE rn = least(v_sn_i, v_sn_n);

      v_firstname := v_gn->>'romanized';
      v_lastname := v_sn->>'romanized';
      v_firstname_th := v_gn->>'thai';
      v_lastname_th := v_sn->>'thai';
      v_gender := coalesce(v_gn->>'gender', 'u');
      v_email := lower(v_firstname || '.' || v_lastname || '.' || substr(replace(v_user_id::text,'-',''),1,6) || '@gmail.com');
      v_tel := '08' || lpad((10000000 + floor(custom_internal_demo_rand(v_user_id::text||':tel') * 89999999))::int::text, 8, '0');
      v_ts := p_date::timestamptz + make_interval(hours => (8 + floor(custom_internal_demo_rand(v_user_id::text||':h')*12)::int),
                                                  mins => floor(custom_internal_demo_rand(v_user_id::text||':m')*60)::int);

      INSERT INTO user_accounts (
        id, merchant_id, role, user_type, firstname, lastname,fullname, email, tel, gender,
        tier_id, is_active, is_signup_form_complete, created_at, acquired_at, updated_at,
        acquisition_source, skip_cdc
      ) VALUES (
        v_user_id, v_merchant_id, 'user', 'buyer',
        v_firstname_th, v_lastname_th, v_firstname || ' ' || v_lastname,
        v_email, v_tel, v_gender,
        v_tier_member, true, true, v_ts, v_ts, v_ts,
        (ARRAY['line','instagram','friend','store','google'])[1 + floor(custom_internal_demo_rand(v_user_id::text||':acq')*5)::int],
        true
      );

      PERFORM fn_ensure_member_code(v_user_id, v_merchant_id);

      INSERT INTO user_wallet (user_id, merchant_id, points_balance, ticket_balance, created_at)
      VALUES (v_user_id, v_merchant_id, 0, 0, v_ts)
      ON CONFLICT DO NOTHING;

      INSERT INTO custom_internal_demo_config (kind, code, payload, is_active, sort_order)
      VALUES (
        'member_state', v_user_id::text,
        jsonb_build_object(
          'user_id', v_user_id,
          'archetype', v_arch,
          'signup_date', p_date,
          'phase', custom_internal_demo_rand(v_user_id::text || ':phase')
        ),
        true, 0
      )
      ON CONFLICT (kind, code) DO NOTHING;

      v_signups := v_signups + 1;
    EXCEPTION WHEN OTHERS THEN
      v_errors := array_append(v_errors, 'signup:' || SQLERRM);
    END;
  END LOOP;

  -- Wave 3–5: purchases, points, redemptions for existing members
  FOR v_member IN
    SELECT ua.id AS user_id,
           ua.created_at,
           coalesce(ms.payload->>'archetype', 'occasional') AS archetype,
           coalesce((ms.payload->>'phase')::double precision, 0.5) AS phase,
           coalesce(uw.points_balance, 0) AS points_balance
    FROM user_accounts ua
    LEFT JOIN custom_internal_demo_config ms
      ON ms.kind = 'member_state' AND ms.code = ua.id::text
    LEFT JOIN user_wallet uw
      ON uw.user_id = ua.id AND uw.merchant_id = v_merchant_id
    WHERE ua.merchant_id = v_merchant_id
      AND ua.role = 'user'
      AND ua.deleted_at IS NULL
      AND ua.created_at::date <= p_date
  LOOP
    SELECT payload INTO v_arch_payload
    FROM custom_internal_demo_config
    WHERE kind = 'archetype' AND code = v_member.archetype
    LIMIT 1;

    IF v_arch_payload IS NULL THEN
      CONTINUE;
    END IF;

    v_days_since := greatest(0, p_date - v_member.created_at::date);
    v_decay := exp(-v_days_since::double precision / greatest((v_arch_payload->>'decay_days')::double precision, 30));
    -- one_timer cools hard after first weeks
    IF v_member.archetype = 'one_timer' AND v_days_since > 21 THEN
      v_decay := v_decay * 0.15;
    END IF;
    IF v_member.archetype = 'lapsed_winback' THEN
      IF v_days_since BETWEEN 45 AND 90 THEN
        v_decay := v_decay * 1.8; -- winback window
      ELSIF v_days_since < 30 THEN
        v_decay := v_decay * 0.5;
      END IF;
    END IF;

    -- Purchase draw
    v_roll := custom_internal_demo_rand(v_member.user_id::text || p_date::text || ':buy');
    v_prop := coalesce((v_arch_payload->>'purchase_propensity')::double precision, 0.05)
              * v_decay * v_dow_factor * v_campaign_boost * v_noise
              * (0.85 + 0.3 * v_member.phase);

    IF v_roll < v_prop THEN
      BEGIN
        v_ts := p_date::timestamptz + make_interval(
          hours => (10 + floor(custom_internal_demo_rand(v_member.user_id::text||p_date::text||':ph')*10)::int),
          mins => floor(custom_internal_demo_rand(v_member.user_id::text||p_date::text||':pm')*60)::int
        );
        -- log-normal-ish basket from mean
        v_basket := (v_arch_payload->>'basket_mean')::numeric
          * exp(0.35 * (custom_internal_demo_rand(v_member.user_id::text||p_date::text||':ln') - 0.5) * 2.5);
        v_basket := greatest(149, least(8000, round(v_basket)));

        IF v_store_ids IS NOT NULL AND array_length(v_store_ids,1) > 0 THEN
          v_store_id := v_store_ids[1 + floor(custom_internal_demo_rand(v_member.user_id::text||p_date::text||':st') * array_length(v_store_ids,1))::int];
        END IF;

        v_purchase_id := gen_random_uuid();
        v_code := 'SEED-RKT-PUR-' || to_char(p_date, 'YYYYMMDD') || '-' || substr(replace(v_member.user_id::text,'-',''),1,8);

        INSERT INTO purchase_ledger (
          id, merchant_id, user_id, transaction_number, transaction_date, completed_at,
          total_amount, discount_amount, tax_amount, final_amount,
          payment_status, transaction_type, status, record_type,
          earn_currency, currency_processed_at, skip_cdc,
          external_ref, dedup_key, store_id, earning_channel_id,
          currency, metadata, created_at, updated_at, api_source
        ) VALUES (
          v_purchase_id, v_merchant_id, v_member.user_id, v_code, v_ts, v_ts,
          v_basket, 0, 0, v_basket,
          'paid', 'sale', 'completed', 'credit',
          false, v_ts, true,
          v_code, v_code, v_store_id, v_earn_channel_id,
          'THB', jsonb_build_object('seed', v_seed_tag, 'mode', v_mode),
          v_ts, v_ts, 'rocket-demo-seed'
        );

        -- 1–3 line items
        v_line_count := 1 + floor(custom_internal_demo_rand(v_member.user_id::text||p_date::text||':lc') * 3)::int;
        v_final := 0;
        FOR v_i IN 1..v_line_count LOOP
          SELECT payload INTO v_sku
          FROM (
            SELECT payload, row_number() OVER (ORDER BY sort_order) AS rn,
                   count(*) OVER () AS n
            FROM custom_internal_demo_config WHERE kind='product' AND is_active
          ) s
          WHERE rn = 1 + floor(custom_internal_demo_rand(v_member.user_id::text||p_date::text||':sku'||v_i::text) * s.n)::int
          LIMIT 1;

          v_qty := 1;
          v_line_total := coalesce((v_sku.payload->>'price')::numeric, 300) * v_qty;
          v_final := v_final + v_line_total;

          INSERT INTO purchase_items_ledger (
            transaction_id, merchant_id, sku_id, sku_code, product_name,
            quantity, unit_price, discount_amount, tax_amount, line_total,
            status, completed_at, currency_processed_at, created_at, updated_at
          ) VALUES (
            v_purchase_id, v_merchant_id,
            (v_sku.payload->>'sku_id')::uuid,
            v_sku.payload->>'sku_code',
            v_sku.payload->>'name',
            v_qty, (v_sku.payload->>'price')::numeric, 0, 0, v_line_total,
            'completed', v_ts, v_ts, v_ts, v_ts
          );
          v_items := v_items + 1;
        END LOOP;

        -- Align header amount to items
        IF v_final > 0 THEN
          UPDATE purchase_ledger
          SET total_amount = v_final, final_amount = v_final
          WHERE id = v_purchase_id;
          v_basket := v_final;
        END IF;

        v_purchases := v_purchases + 1;

        -- Points earn (backfill direct; live uses chokepoint)
        v_points := greatest(1, round(v_basket * v_points_per_thb)::int);
        SELECT coalesce(points_balance, 0) INTO v_wallet_bal
        FROM user_wallet WHERE user_id = v_member.user_id AND merchant_id = v_merchant_id;

        IF v_mode = 'live' THEN
          BEGIN
            PERFORM chokepoint_post_wallet_transaction(
              p_user_id := v_member.user_id,
              p_currency := 'points',
              p_source_type := 'purchase',
              p_component := 'base',
              p_transaction_type := 'earn',
              p_amount := v_points,
              p_transaction_id := v_purchase_id,
              p_merchant_id := v_merchant_id,
              p_description := 'Purchase earn',
              p_dedup_key := 'SEED-RKT-WLT-' || v_purchase_id::text
            );
            v_wallet := v_wallet + 1;
          EXCEPTION WHEN OTHERS THEN
            v_errors := array_append(v_errors, 'wallet_live:' || SQLERRM);
          END;
        ELSE
          INSERT INTO wallet_ledger (
            merchant_id, user_id, currency, transaction_type, source_type, component,
            amount, signed_amount, balance_before, balance_after,
            source_id, description, created_at, created_by, dedup_key, skip_cdc, metadata
          ) VALUES (
            v_merchant_id, v_member.user_id, 'points', 'earn', 'purchase', 'base',
            v_points, v_points, v_wallet_bal, v_wallet_bal + v_points,
            v_purchase_id, 'Purchase earn', v_ts, 'rocket-demo-seed',
            'SEED-RKT-WLT-' || v_purchase_id::text, true,
            jsonb_build_object('seed', v_seed_tag)
          );
          UPDATE user_wallet
          SET points_balance = points_balance + v_points
          WHERE user_id = v_member.user_id AND merchant_id = v_merchant_id;
          IF NOT FOUND THEN
            INSERT INTO user_wallet (user_id, merchant_id, points_balance, ticket_balance, created_at)
            VALUES (v_member.user_id, v_merchant_id, v_points, 0, v_ts);
          END IF;
          v_wallet := v_wallet + 1;
          v_wallet_bal := v_wallet_bal + v_points;
        END IF;
      EXCEPTION WHEN OTHERS THEN
        v_errors := array_append(v_errors, 'purchase:' || SQLERRM);
      END;
    END IF;

    -- Redemption draw (needs balance)
    SELECT coalesce(points_balance, 0) INTO v_wallet_bal
    FROM user_wallet WHERE user_id = v_member.user_id AND merchant_id = v_merchant_id;

    v_roll := custom_internal_demo_rand(v_member.user_id::text || p_date::text || ':rdm');
    v_prop := coalesce((v_arch_payload->>'redeem_propensity')::double precision, 0.02)
              * v_decay * v_noise;

    IF v_roll < v_prop AND v_wallet_bal >= 150 THEN
      BEGIN
        SELECT rm.id, rm.name, coalesce(rpc.points_required, rm.fallback_points) AS pts
        INTO v_reward
        FROM reward_master rm
        JOIN reward_points_conditions rpc ON rpc.reward_id = rm.id AND rpc.active_status
        WHERE rm.merchant_id = v_merchant_id AND rm.active_status
          AND coalesce(rpc.points_required, rm.fallback_points) <= v_wallet_bal
        ORDER BY custom_internal_demo_rand(v_member.user_id::text || p_date::text || rm.id::text)
        LIMIT 1;

        IF v_reward.id IS NOT NULL THEN
          v_ts := p_date::timestamptz + make_interval(hours => 16, mins => floor(custom_internal_demo_rand(v_member.user_id::text||p_date::text||':rm')*40)::int);
          v_code := 'SEED-RKT-RDM-' || to_char(p_date,'YYYYMMDD') || '-' || substr(replace(v_member.user_id::text,'-',''),1,8);

          IF v_mode = 'live' THEN
            BEGIN
              PERFORM redeem_reward_with_points(
                p_reward_id := v_reward.id,
                p_quantity := 1,
                p_user_id := v_member.user_id,
                p_merchant_id := v_merchant_id
              );
              v_redeems := v_redeems + 1;
            EXCEPTION WHEN OTHERS THEN
              v_errors := array_append(v_errors, 'redeem_live:' || SQLERRM);
            END;
          ELSE
            INSERT INTO reward_redemptions_ledger (
              merchant_id, user_id, reward_id, qty, points_deducted,
              redeemed_status, used_status, success, cancelled,
              redeemed_at, created_at, code, source_type, external_ref_id
            ) VALUES (
              v_merchant_id, v_member.user_id, v_reward.id, 1, v_reward.pts,
              true, false, true, false,
              v_ts, v_ts, v_code, 'reward_redemption', v_code
            );

            INSERT INTO wallet_ledger (
              merchant_id, user_id, currency, transaction_type, source_type, component,
              amount, signed_amount, balance_before, balance_after,
              description, created_at, created_by, dedup_key, skip_cdc, metadata
            ) VALUES (
              v_merchant_id, v_member.user_id, 'points', 'burn', 'reward_redemption', 'base',
              v_reward.pts::int, -v_reward.pts::int, v_wallet_bal, v_wallet_bal - v_reward.pts::int,
              'Redeem ' || v_reward.name, v_ts, 'rocket-demo-seed',
              v_code, true, jsonb_build_object('seed', v_seed_tag)
            );
            UPDATE user_wallet
            SET points_balance = points_balance - v_reward.pts::int
            WHERE user_id = v_member.user_id AND merchant_id = v_merchant_id;
            v_redeems := v_redeems + 1;
          END IF;
        END IF;
      EXCEPTION WHEN OTHERS THEN
        v_errors := array_append(v_errors, 'redeem:' || SQLERRM);
      END;
    END IF;
  END LOOP;

  -- Wave 6b: mark matured My Rewards coupons as used at lifestyle retailers
  IF v_usage_store_ids IS NOT NULL AND coalesce(array_length(v_usage_store_ids, 1), 0) > 0 THEN
    FOR v_redemption IN
      SELECT r.id, r.code, r.user_id, r.redeemed_at
      FROM reward_redemptions_ledger r
      WHERE r.merchant_id = v_merchant_id
        AND coalesce(r.success, true)
        AND coalesce(r.cancelled, false) = false
        AND coalesce(r.used_status, false) = false
        AND r.redeemed_at::date <= (p_date - 2)
        AND r.redeemed_at::date >= (p_date - 21)
      ORDER BY r.redeemed_at
      LIMIT CASE WHEN v_mode = 'live' THEN 40 ELSE 800 END
    LOOP
      BEGIN
        v_use_lag := 2 + floor(
          custom_internal_demo_rand(v_redemption.id::text || ':lag') * 12
        )::int;
        IF v_redemption.redeemed_at::date + v_use_lag > p_date THEN
          CONTINUE;
        END IF;
        -- ~62% of matured coupons are used; rest stay open in wallet
        IF custom_internal_demo_rand(v_redemption.id::text || p_date::text || ':use') >= 0.62 THEN
          CONTINUE;
        END IF;

        v_use_ts := p_date::timestamptz + make_interval(
          hours => 11 + floor(custom_internal_demo_rand(v_redemption.id::text || ':uh') * 8)::int,
          mins => floor(custom_internal_demo_rand(v_redemption.id::text || ':um') * 50)::int
        );
        v_use_store_id := v_usage_store_ids[
          1 + floor(
            custom_internal_demo_rand(v_redemption.id::text || p_date::text || ':ust')
            * array_length(v_usage_store_ids, 1)
          )::int
        ];

        IF v_mode = 'live' THEN
          PERFORM api_mark_redemption_used(
            p_redemption_id := v_redemption.id,
            p_redemption_code := v_redemption.code,
            p_user_id := v_redemption.user_id,
            p_notes := 'rocket-demo-daily-use',
            p_language := 'en',
            p_merchant_id := v_merchant_id,
            p_store_id := v_use_store_id
          );
        ELSE
          UPDATE reward_redemptions_ledger
          SET used_status = true,
              used_at = v_use_ts,
              used_store_id = v_use_store_id,
              used_qty = coalesce(used_qty, qty, 1),
              fulfillment_status = 'completed'
          WHERE id = v_redemption.id
            AND coalesce(used_status, false) = false;
        END IF;
        v_uses := v_uses + 1;
      EXCEPTION WHEN OTHERS THEN
        v_errors := array_append(v_errors, 'use:' || SQLERRM);
      END;
    END LOOP;
  END IF;

  -- Wave 7: lightweight tier assignment from lifetime spend
  FOR v_member IN
    SELECT ua.id AS user_id,
           coalesce(sum(pl.final_amount), 0) AS lifetime
    FROM user_accounts ua
    LEFT JOIN purchase_ledger pl
      ON pl.user_id = ua.id AND pl.merchant_id = v_merchant_id AND pl.status = 'completed'
    WHERE ua.merchant_id = v_merchant_id AND ua.role = 'user' AND ua.deleted_at IS NULL
    GROUP BY ua.id
  LOOP
    v_new_tier := CASE
      WHEN v_member.lifetime >= 15000 THEN v_tier_plat
      WHEN v_member.lifetime >= 6000 THEN v_tier_gold
      WHEN v_member.lifetime >= 2000 THEN v_tier_silver
      ELSE v_tier_member
    END;
    UPDATE user_accounts
    SET tier_id = v_new_tier, updated_at = now()
    WHERE id = v_member.user_id
      AND merchant_id = v_merchant_id
      AND coalesce(tier_id, '00000000-0000-0000-0000-000000000000'::uuid) IS DISTINCT FROM v_new_tier;
    IF FOUND THEN
      v_tier_updates := v_tier_updates + 1;
    END IF;
  END LOOP;

  -- Wave 8: engagement trickle (surveys / missions / spins / tags)
  BEGIN
    v_counts := custom_internal_demo_generate_day_engagement(p_date, v_mode);
  EXCEPTION WHEN OTHERS THEN
    v_errors := array_append(v_errors, 'engagement:' || SQLERRM);
    v_counts := '{}'::jsonb;
  END;

  v_counts := jsonb_build_object(
    'signups', v_signups,
    'purchases', v_purchases,
    'items', v_items,
    'wallet', v_wallet,
    'redeems', v_redeems,
    'uses', v_uses,
    'tier_updates', v_tier_updates,
    'engagement', v_counts,
    'target_members', v_target_members,
    'current_members_before', v_current_members,
    'mode', v_mode,
    'errors', to_jsonb(v_errors)
  );

  INSERT INTO custom_internal_demo_config (kind, code, payload, is_active, sort_order)
  VALUES (
    'run_log', p_date::text,
    jsonb_build_object(
      'date', p_date,
      'counts', v_counts,
      'ok', coalesce(array_length(v_errors,1), 0) < 20,
      'finished_at', now()
    ),
    true, 0
  )
  ON CONFLICT (kind, code) DO UPDATE
  SET payload = EXCLUDED.payload, updated_at = now();

  RETURN jsonb_build_object('success', true, 'date', p_date, 'counts', v_counts);
END;
$fn$;
