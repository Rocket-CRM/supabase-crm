-- Enrich Rocket Demo engagement: personas, tags, surveys, mission progress, spins, earn bonus samples.
-- Idempotent via custom_internal_demo_config enrich_log / engagement_v1.
-- Requires engagement masters in settings (forms, missions, spin wheels, personas, tags).
-- Run: SELECT custom_internal_demo_enrich_engagement();

CREATE OR REPLACE FUNCTION public.custom_internal_demo_enrich_engagement()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $fn$
DECLARE
  v_settings jsonb := custom_internal_demo_settings();
  v_merchant_id uuid;
  v_persona jsonb;
  v_tags jsonb;
  v_forms jsonb;
  v_fields jsonb;
  v_missions jsonb;
  v_spins jsonb;
  v_persona_beauty uuid;
  v_persona_skincare uuid;
  v_persona_gift uuid;
  v_persona_wellness uuid;
  v_tag_vip uuid;
  v_tag_new uuid;
  v_tag_risk uuid;
  v_tag_fragrance uuid;
  v_tag_app uuid;
  v_form_pref uuid;
  v_form_nps uuid;
  v_ff_interest uuid;
  v_ff_category uuid;
  v_ff_concern uuid;
  v_ff_nps uuid;
  v_ff_comment uuid;
  v_mission_spend uuid;
  v_mission_survey uuid;
  v_spin_weekend uuid;
  v_cond_spend uuid;
  v_cond_survey uuid;
  v_mult_factor_id uuid;
  v_count_persona int := 0;
  v_count_tags int := 0;
  v_count_pref int := 0;
  v_count_nps int := 0;
  v_count_mp_spend int := 0;
  v_count_mp_survey int := 0;
  v_count_spins int := 0;
  v_count_spin_fail int := 0;
  v_count_bonus int := 0;
  r record;
  v_arch text;
  v_pick uuid;
  v_hash numeric;
  v_sub_id uuid;
  v_interest text;
  v_cat text;
  v_concern text;
  v_spend numeric;
  v_progress numeric;
  v_completed boolean;
  v_cp jsonb;
  v_bal numeric;
  v_bonus numeric;
  v_result jsonb;
BEGIN
  IF EXISTS (
    SELECT 1 FROM custom_internal_demo_config
    WHERE kind = 'enrich_log' AND code = 'engagement_v1' AND is_active
  ) THEN
    RETURN jsonb_build_object('success', true, 'skipped', true, 'reason', 'already_enriched');
  END IF;

  IF v_settings IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'settings missing');
  END IF;

  v_merchant_id := (v_settings->>'merchant_id')::uuid;
  v_persona := v_settings->'persona_ids';
  v_tags := v_settings->'tag_ids';
  v_forms := v_settings->'form_ids';
  v_fields := v_settings->'form_field_ids';
  v_missions := v_settings->'mission_ids';
  v_spins := v_settings->'spin_wheel_ids';

  IF v_persona IS NULL OR v_forms IS NULL OR v_missions IS NULL OR v_spins IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'engagement masters missing in settings');
  END IF;

  v_persona_beauty := (v_persona->>'beauty')::uuid;
  v_persona_skincare := (v_persona->>'skincare')::uuid;
  v_persona_gift := (v_persona->>'gift')::uuid;
  v_persona_wellness := (v_persona->>'wellness')::uuid;
  v_tag_vip := (v_tags->>'vip')::uuid;
  v_tag_new := (v_tags->>'new_member')::uuid;
  v_tag_risk := (v_tags->>'at_risk')::uuid;
  v_tag_fragrance := (v_tags->>'fragrance')::uuid;
  v_tag_app := (v_tags->>'app_engager')::uuid;
  v_form_pref := (v_forms->>'preference')::uuid;
  v_form_nps := (v_forms->>'nps')::uuid;
  v_ff_interest := (v_fields->>'interest')::uuid;
  v_ff_category := (v_fields->>'favorite_category')::uuid;
  v_ff_concern := (v_fields->>'skin_concern')::uuid;
  v_ff_nps := (v_fields->>'nps_score')::uuid;
  v_ff_comment := (v_fields->>'nps_comment')::uuid;
  v_mission_spend := (v_missions->>'spend_3k')::uuid;
  v_mission_survey := (v_missions->>'survey_pref')::uuid;
  v_spin_weekend := (v_spins->>'weekend')::uuid;

  SELECT id INTO v_cond_spend
  FROM mission_conditions
  WHERE mission_id = v_mission_spend
  ORDER BY created_at
  LIMIT 1;

  SELECT id INTO v_cond_survey
  FROM mission_conditions
  WHERE mission_id = v_mission_survey
  ORDER BY created_at
  LIMIT 1;

  SELECT ef.id INTO v_mult_factor_id
  FROM earn_factor ef
  WHERE ef.merchant_id = v_merchant_id
    AND ef.earn_factor_group_id = (v_settings->>'earn_factor_group_id')::uuid
    AND ef.earn_factor_type = 'multiplier'
  ORDER BY ef.earn_factor_amount DESC NULLS LAST
  LIMIT 1;

  -- 1) Personas for users without persona
  FOR r IN
    SELECT ua.id,
           coalesce(ms.payload->>'archetype', NULL) AS archetype
    FROM user_accounts ua
    LEFT JOIN custom_internal_demo_config ms
      ON ms.kind = 'member_state' AND ms.code = ua.id::text AND ms.is_active
    WHERE ua.merchant_id = v_merchant_id
      AND ua.persona_id IS NULL
      AND coalesce(ua.is_active, true)
  LOOP
    v_arch := r.archetype;
    v_hash := abs(('x' || substr(md5(r.id::text || 'persona'), 1, 8))::bit(32)::int / 2147483647.0);

    IF v_arch = 'whale' THEN
      v_pick := CASE WHEN v_hash < 0.55 THEN v_persona_beauty
                     WHEN v_hash < 0.85 THEN v_persona_gift
                     ELSE v_persona_skincare END;
    ELSIF v_arch = 'regular' THEN
      v_pick := CASE WHEN v_hash < 0.45 THEN v_persona_skincare
                     WHEN v_hash < 0.75 THEN v_persona_beauty
                     ELSE v_persona_wellness END;
    ELSIF v_arch = 'lapsed_winback' THEN
      v_pick := CASE WHEN v_hash < 0.4 THEN v_persona_beauty
                     WHEN v_hash < 0.7 THEN v_persona_wellness
                     ELSE v_persona_gift END;
    ELSIF v_arch = 'one_timer' THEN
      v_pick := CASE WHEN v_hash < 0.4 THEN v_persona_gift
                     WHEN v_hash < 0.7 THEN v_persona_wellness
                     ELSE v_persona_skincare END;
    ELSIF v_arch = 'occasional' THEN
      v_pick := CASE WHEN v_hash < 0.35 THEN v_persona_wellness
                     WHEN v_hash < 0.65 THEN v_persona_skincare
                     WHEN v_hash < 0.85 THEN v_persona_beauty
                     ELSE v_persona_gift END;
    ELSE
      v_pick := (ARRAY[v_persona_beauty, v_persona_skincare, v_persona_gift, v_persona_wellness])[
        1 + (abs(('x' || substr(md5(r.id::text), 1, 8))::bit(32)::int) % 4)
      ];
    END IF;

    UPDATE user_accounts SET persona_id = v_pick, updated_at = now() WHERE id = r.id;
    v_count_persona := v_count_persona + 1;
  END LOOP;

  -- 2) Tags
  -- VIP ~8% of whales / high spenders
  INSERT INTO user_tags (user_id, tag_id, merchant_id, source_type)
  SELECT ua.id, v_tag_vip, v_merchant_id, 'demo_seed'
  FROM user_accounts ua
  LEFT JOIN custom_internal_demo_config ms
    ON ms.kind = 'member_state' AND ms.code = ua.id::text
  LEFT JOIN LATERAL (
    SELECT coalesce(sum(pl.final_amount), 0) AS lifetime_spend
    FROM purchase_ledger pl
    WHERE pl.user_id = ua.id AND pl.merchant_id = v_merchant_id AND pl.status = 'completed'
  ) sp ON true
  WHERE ua.merchant_id = v_merchant_id
    AND (
      ms.payload->>'archetype' = 'whale'
      OR sp.lifetime_spend >= 15000
    )
    AND abs(('x' || substr(md5(ua.id::text || 'vip'), 1, 8))::bit(32)::int / 2147483647.0) < 0.08
  ON CONFLICT (user_id, tag_id) DO NOTHING;
  GET DIAGNOSTICS v_count_tags = ROW_COUNT;

  -- At Risk for lapsed
  INSERT INTO user_tags (user_id, tag_id, merchant_id, source_type)
  SELECT ua.id, v_tag_risk, v_merchant_id, 'demo_seed'
  FROM user_accounts ua
  JOIN custom_internal_demo_config ms
    ON ms.kind = 'member_state' AND ms.code = ua.id::text
  WHERE ua.merchant_id = v_merchant_id
    AND ms.payload->>'archetype' = 'lapsed_winback'
  ON CONFLICT (user_id, tag_id) DO NOTHING;

  -- Fragrance ~20%
  INSERT INTO user_tags (user_id, tag_id, merchant_id, source_type)
  SELECT ua.id, v_tag_fragrance, v_merchant_id, 'demo_seed'
  FROM user_accounts ua
  WHERE ua.merchant_id = v_merchant_id
    AND abs(('x' || substr(md5(ua.id::text || 'frag'), 1, 8))::bit(32)::int / 2147483647.0) < 0.20
  ON CONFLICT (user_id, tag_id) DO NOTHING;

  -- App Engager ~40%
  INSERT INTO user_tags (user_id, tag_id, merchant_id, source_type)
  SELECT ua.id, v_tag_app, v_merchant_id, 'demo_seed'
  FROM user_accounts ua
  WHERE ua.merchant_id = v_merchant_id
    AND abs(('x' || substr(md5(ua.id::text || 'app'), 1, 8))::bit(32)::int / 2147483647.0) < 0.40
  ON CONFLICT (user_id, tag_id) DO NOTHING;

  -- New Member last 30d
  INSERT INTO user_tags (user_id, tag_id, merchant_id, source_type)
  SELECT ua.id, v_tag_new, v_merchant_id, 'demo_seed'
  FROM user_accounts ua
  WHERE ua.merchant_id = v_merchant_id
    AND ua.created_at >= now() - interval '30 days'
  ON CONFLICT (user_id, tag_id) DO NOTHING;

  SELECT count(*) INTO v_count_tags
  FROM user_tags ut
  JOIN tag_master tm ON tm.id = ut.tag_id
  WHERE ut.merchant_id = v_merchant_id AND tm.tag_name LIKE 'SEED-RKT %';

  -- 3) Preference survey ~30%
  FOR r IN
    SELECT ua.id
    FROM user_accounts ua
    WHERE ua.merchant_id = v_merchant_id
      AND abs(('x' || substr(md5(ua.id::text || 'pref'), 1, 8))::bit(32)::int / 2147483647.0) < 0.30
      AND NOT EXISTS (
        SELECT 1 FROM form_submissions fs
        WHERE fs.form_id = v_form_pref AND fs.user_id = ua.id
      )
  LOOP
    v_interest := (ARRAY['skincare','makeup','fragrance','wellness'])[
      1 + (abs(('x' || substr(md5(r.id::text || 'i'), 1, 8))::bit(32)::int) % 4)
    ];
    v_cat := (ARRAY['treat','protect','cleanse','body'])[
      1 + (abs(('x' || substr(md5(r.id::text || 'c'), 1, 8))::bit(32)::int) % 4)
    ];
    v_concern := (ARRAY['dryness','dullness','acne','aging'])[
      1 + (abs(('x' || substr(md5(r.id::text || 'k'), 1, 8))::bit(32)::int) % 4)
    ];

    INSERT INTO form_submissions (
      form_id, merchant_id, user_id, submission_number, status, submitted_at, source, skip_cdc
    ) VALUES (
      v_form_pref, v_merchant_id, r.id,
      'SEED-PREF-' || r.id::text,
      'completed', now() - ((abs(('x' || substr(md5(r.id::text), 1, 4))::bit(16)::int) % 60) || ' days')::interval,
      'demo_seed', true
    ) RETURNING id INTO v_sub_id;

    INSERT INTO form_responses (submission_id, field_id, text_value, ref_userid) VALUES
      (v_sub_id, v_ff_interest, v_interest, r.id),
      (v_sub_id, v_ff_category, v_cat, r.id),
      (v_sub_id, v_ff_concern, v_concern, r.id);

    v_count_pref := v_count_pref + 1;
  END LOOP;

  -- NPS ~10%
  FOR r IN
    SELECT ua.id
    FROM user_accounts ua
    WHERE ua.merchant_id = v_merchant_id
      AND abs(('x' || substr(md5(ua.id::text || 'nps'), 1, 8))::bit(32)::int / 2147483647.0) < 0.10
      AND NOT EXISTS (
        SELECT 1 FROM form_submissions fs
        WHERE fs.form_id = v_form_nps AND fs.user_id = ua.id
      )
  LOOP
    INSERT INTO form_submissions (
      form_id, merchant_id, user_id, submission_number, status, submitted_at, source, skip_cdc
    ) VALUES (
      v_form_nps, v_merchant_id, r.id,
      'SEED-NPS-' || r.id::text,
      'completed', now() - ((abs(('x' || substr(md5(r.id::text || 'n'), 1, 4))::bit(16)::int) % 45) || ' days')::interval,
      'demo_seed', true
    ) RETURNING id INTO v_sub_id;

    INSERT INTO form_responses (submission_id, field_id, text_value, ref_userid) VALUES
      (v_sub_id, v_ff_nps, (5 + (abs(('x' || substr(md5(r.id::text || 's'), 1, 8))::bit(32)::int) % 6))::text, r.id),
      (v_sub_id, v_ff_comment, 'Great experience', r.id);

    v_count_nps := v_count_nps + 1;
  END LOOP;

  -- 4) Mission progress — spend mission
  FOR r IN
    SELECT ua.id,
           coalesce(sum(pl.final_amount) FILTER (WHERE pl.status = 'completed'), 0) AS lifetime_spend
    FROM user_accounts ua
    LEFT JOIN purchase_ledger pl
      ON pl.user_id = ua.id AND pl.merchant_id = v_merchant_id
    WHERE ua.merchant_id = v_merchant_id
    GROUP BY ua.id
    HAVING coalesce(sum(pl.final_amount) FILTER (WHERE pl.status = 'completed'), 0) > 0
  LOOP
    v_spend := r.lifetime_spend;
    v_progress := least(v_spend, 3000);
    v_completed := v_spend >= 3000;
    v_cp := jsonb_build_object(
      v_cond_spend::text,
      jsonb_build_object(
        'current', v_progress,
        'target', 3000,
        'completed', v_completed
      )
    );

    INSERT INTO mission_progress (
      user_id, mission_id, current_progress, current_target_value,
      period_completions, lifetime_completions, period_claims, lifetime_claims,
      unclaimed_completions, condition_progress, is_active,
      last_progress_at, last_completed_at, accepted_at
    ) VALUES (
      r.id, v_mission_spend, v_progress, 3000,
      CASE WHEN v_completed THEN 1 ELSE 0 END,
      CASE WHEN v_completed THEN 1 ELSE 0 END,
      CASE WHEN v_completed THEN 1 ELSE 0 END,
      CASE WHEN v_completed THEN 1 ELSE 0 END,
      0, v_cp, true,
      now(),
      CASE WHEN v_completed THEN now() ELSE NULL END,
      now() - interval '30 days'
    )
    ON CONFLICT (user_id, mission_id) DO UPDATE SET
      current_progress = EXCLUDED.current_progress,
      current_target_value = EXCLUDED.current_target_value,
      period_completions = EXCLUDED.period_completions,
      lifetime_completions = EXCLUDED.lifetime_completions,
      condition_progress = EXCLUDED.condition_progress,
      last_progress_at = EXCLUDED.last_progress_at,
      last_completed_at = COALESCE(mission_progress.last_completed_at, EXCLUDED.last_completed_at),
      updated_at = now();

    v_count_mp_spend := v_count_mp_spend + 1;
  END LOOP;

  -- Survey mission for pref submitters
  INSERT INTO mission_progress (
    user_id, mission_id, current_progress, current_target_value,
    period_completions, lifetime_completions, period_claims, lifetime_claims,
    unclaimed_completions, condition_progress, is_active,
    last_progress_at, last_completed_at, accepted_at
  )
  SELECT
    fs.user_id,
    v_mission_survey,
    1, 1, 1, 1, 1, 1, 0,
    jsonb_build_object(
      v_cond_survey::text,
      jsonb_build_object('current', 1, 'target', 1, 'completed', true)
    ),
    true,
    fs.submitted_at,
    fs.submitted_at,
    fs.submitted_at
  FROM form_submissions fs
  WHERE fs.form_id = v_form_pref
    AND fs.merchant_id = v_merchant_id
    AND fs.user_id IS NOT NULL
  ON CONFLICT (user_id, mission_id) DO UPDATE SET
    current_progress = 1,
    lifetime_completions = greatest(mission_progress.lifetime_completions, 1),
    condition_progress = EXCLUDED.condition_progress,
    last_completed_at = coalesce(mission_progress.last_completed_at, EXCLUDED.last_completed_at),
    updated_at = now();

  GET DIAGNOSTICS v_count_mp_survey = ROW_COUNT;

  -- 5) Spin wheel for up to 150 users with points >= 50
  FOR r IN
    SELECT uw.user_id
    FROM user_wallet uw
    WHERE uw.merchant_id = v_merchant_id
      AND coalesce(uw.points_balance, 0) >= 50
    ORDER BY md5(uw.user_id::text || 'spin')
    LIMIT 150
  LOOP
    BEGIN
      v_result := fn_spin_wheel(r.user_id, v_merchant_id, v_spin_weekend);
      IF coalesce((v_result->>'success')::boolean, false) THEN
        v_count_spins := v_count_spins + 1;
      ELSE
        v_count_spin_fail := v_count_spin_fail + 1;
      END IF;
    EXCEPTION WHEN OTHERS THEN
      v_count_spin_fail := v_count_spin_fail + 1;
    END;
  END LOOP;

  -- 6) Earn bonus sample rows for ~500 recent weekend purchases
  FOR r IN
    SELECT pl.id, pl.user_id, pl.final_amount, pl.transaction_date
    FROM purchase_ledger pl
    WHERE pl.merchant_id = v_merchant_id
      AND pl.status = 'completed'
      AND extract(dow from pl.transaction_date) IN (0, 6)
      AND pl.transaction_date >= now() - interval '120 days'
      AND NOT EXISTS (
        SELECT 1 FROM wallet_ledger wl
        WHERE wl.dedup_key = 'SEED-RKT-BONUS-' || pl.id::text
      )
    ORDER BY pl.transaction_date DESC
    LIMIT 500
  LOOP
    SELECT points_balance INTO v_bal
    FROM user_wallet
    WHERE user_id = r.user_id AND merchant_id = v_merchant_id;

    v_bal := coalesce(v_bal, 0);
    v_bonus := greatest(5, least(50, round(coalesce(r.final_amount, 0) * 0.01)));

    INSERT INTO wallet_ledger (
      merchant_id, user_id, currency, transaction_type, source_type, source_id,
      signed_amount, amount, balance_before, balance_after,
      description, metadata, skip_cdc, dedup_key, created_at
    ) VALUES (
      v_merchant_id, r.user_id, 'points', 'earn', 'purchase', r.id,
      v_bonus, v_bonus, v_bal, v_bal + v_bonus,
      'Demo weekend earn bonus',
      jsonb_build_object(
        'earn_factor_id', v_mult_factor_id,
        'demo_seed', true,
        'bonus_type', 'weekend_multiplier_sample'
      ),
      true,
      'SEED-RKT-BONUS-' || r.id::text,
      r.transaction_date
    );

    -- Keep wallet balance roughly in sync for demo
    UPDATE user_wallet
    SET points_balance = coalesce(points_balance, 0) + v_bonus
    WHERE user_id = r.user_id AND merchant_id = v_merchant_id;

    v_count_bonus := v_count_bonus + 1;
  END LOOP;

  INSERT INTO custom_internal_demo_config (kind, code, payload, is_active, sort_order)
  VALUES (
    'enrich_log',
    'engagement_v1',
    jsonb_build_object(
      'ran_at', now(),
      'counts', jsonb_build_object(
        'personas_assigned', v_count_persona,
        'tag_assignments', v_count_tags,
        'pref_submissions', v_count_pref,
        'nps_submissions', v_count_nps,
        'mission_progress_spend', v_count_mp_spend,
        'mission_progress_survey', v_count_mp_survey,
        'spins_ok', v_count_spins,
        'spins_fail', v_count_spin_fail,
        'earn_bonus_rows', v_count_bonus
      )
    ),
    true,
    1
  );

  RETURN jsonb_build_object(
    'success', true,
    'counts', jsonb_build_object(
      'personas_assigned', v_count_persona,
      'tag_assignments', v_count_tags,
      'pref_submissions', v_count_pref,
      'nps_submissions', v_count_nps,
      'mission_progress_spend', v_count_mp_spend,
      'mission_progress_survey', v_count_mp_survey,
      'spins_ok', v_count_spins,
      'spins_fail', v_count_spin_fail,
      'earn_bonus_rows', v_count_bonus
    )
  );
EXCEPTION WHEN OTHERS THEN
  RETURN jsonb_build_object('success', false, 'error', SQLERRM, 'state', SQLSTATE);
END;
$fn$;
