-- Daily engagement trickle for Rocket Demo (surveys, mission progress, spins, tag drift).
-- Called from custom_internal_demo_generate_day after commerce waves.
CREATE OR REPLACE FUNCTION public.custom_internal_demo_generate_day_engagement(
  p_date date,
  p_mode text DEFAULT 'live'
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $body$
DECLARE
  v_settings jsonb := custom_internal_demo_settings();
  v_merchant_id uuid;
  v_seed_tag text := 'SEED-RKT';
  v_personas jsonb;
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
  v_earn_bonus_factor uuid;
  v_member record;
  v_roll double precision;
  v_survey_n int := 0;
  v_nps_n int := 0;
  v_mission_n int := 0;
  v_spin_n int := 0;
  v_tag_n int := 0;
  v_errors text[] := ARRAY[]::text[];
  v_sub_id uuid;
  v_ts timestamptz;
  v_interest text;
  v_cat text;
  v_concern text;
  v_spin_result jsonb;
  v_mode text := lower(coalesce(p_mode, 'live'));
  v_cap_survey int;
  v_cap_spin int;
  v_sub_num text;
BEGIN
  IF v_settings IS NULL OR v_settings->'form_ids' IS NULL THEN
    RETURN jsonb_build_object('success', true, 'skipped', true, 'reason', 'engagement masters missing');
  END IF;

  v_merchant_id := (v_settings->>'merchant_id')::uuid;
  v_seed_tag := coalesce(v_settings->>'seed_tag', 'SEED-RKT');
  v_personas := v_settings->'persona_ids';
  v_tags := v_settings->'tag_ids';
  v_forms := v_settings->'form_ids';
  v_fields := v_settings->'form_field_ids';
  v_missions := v_settings->'mission_ids';
  v_spins := v_settings->'spin_wheel_ids';

  v_persona_beauty := (v_personas->>'beauty')::uuid;
  v_persona_skincare := (v_personas->>'skincare')::uuid;
  v_persona_gift := (v_personas->>'gift')::uuid;
  v_persona_wellness := (v_personas->>'wellness')::uuid;
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

  SELECT id INTO v_cond_spend FROM mission_conditions WHERE mission_id = v_mission_spend LIMIT 1;
  SELECT id INTO v_cond_survey FROM mission_conditions WHERE mission_id = v_mission_survey LIMIT 1;
  SELECT ef.id INTO v_earn_bonus_factor
  FROM earn_factor ef
  JOIN earn_factor_group eg ON eg.id = ef.earn_factor_group_id
  WHERE eg.merchant_id = v_merchant_id AND eg.name = 'Rocket Club Earning 2026'
    AND ef.earn_factor_type = 'multiplier'
  ORDER BY ef.earn_factor_amount DESC
  LIMIT 1;

  v_cap_survey := CASE WHEN v_mode = 'live' THEN 40 ELSE 120 END;
  v_cap_spin := CASE WHEN v_mode = 'live' THEN 15 ELSE 40 END;

  -- Assign persona + New Member tag to brand-new signups missing persona
  FOR v_member IN
    SELECT ua.id AS user_id,
           coalesce(ms.payload->>'archetype', 'occasional') AS archetype
    FROM user_accounts ua
    LEFT JOIN custom_internal_demo_config ms
      ON ms.kind = 'member_state' AND ms.code = ua.id::text
    WHERE ua.merchant_id = v_merchant_id
      AND ua.role = 'user'
      AND ua.deleted_at IS NULL
      AND ua.persona_id IS NULL
      AND ua.created_at::date = p_date
    LIMIT 200
  LOOP
    UPDATE user_accounts
    SET persona_id = CASE
          WHEN v_member.archetype = 'whale' THEN v_persona_beauty
          WHEN v_member.archetype = 'regular' THEN v_persona_skincare
          WHEN v_member.archetype = 'lapsed_winback' THEN v_persona_wellness
          WHEN custom_internal_demo_rand(v_member.user_id::text || p_date::text || ':pers') < 0.35 THEN v_persona_gift
          ELSE v_persona_skincare
        END
    WHERE id = v_member.user_id;

    IF v_tag_new IS NOT NULL THEN
      INSERT INTO user_tags (user_id, tag_id, merchant_id, source_type)
      VALUES (v_member.user_id, v_tag_new, v_merchant_id, 'rocket-demo-seed')
      ON CONFLICT DO NOTHING;
      v_tag_n := v_tag_n + 1;
    END IF;
  END LOOP;

  -- Survey / NPS / mission / spin trickle over a sample of members
  FOR v_member IN
    SELECT ua.id AS user_id,
           coalesce(ms.payload->>'archetype', 'occasional') AS archetype,
           coalesce(uw.points_balance, 0) AS points_balance,
           coalesce((
             SELECT sum(pl.final_amount) FROM purchase_ledger pl
             WHERE pl.user_id = ua.id AND pl.merchant_id = v_merchant_id AND pl.status = 'completed'
           ), 0) AS lifetime_spend
    FROM user_accounts ua
    LEFT JOIN custom_internal_demo_config ms
      ON ms.kind = 'member_state' AND ms.code = ua.id::text
    LEFT JOIN user_wallet uw
      ON uw.user_id = ua.id AND uw.merchant_id = v_merchant_id
    WHERE ua.merchant_id = v_merchant_id
      AND ua.role = 'user'
      AND ua.deleted_at IS NULL
      AND ua.created_at::date <= p_date
    ORDER BY custom_internal_demo_rand(ua.id::text || p_date::text || ':ord')
    LIMIT CASE WHEN v_mode = 'live' THEN 400 ELSE 1200 END
  LOOP
    v_ts := p_date::timestamptz + make_interval(
      hours => (10 + floor(custom_internal_demo_rand(v_member.user_id::text || p_date::text || ':eh') * 10)::int),
      mins => floor(custom_internal_demo_rand(v_member.user_id::text || p_date::text || ':em') * 60)::int
    );

    -- Preference survey
    v_roll := custom_internal_demo_rand(v_member.user_id::text || p_date::text || ':survey');
    IF v_survey_n < v_cap_survey
       AND v_roll < (CASE v_member.archetype WHEN 'whale' THEN 0.08 WHEN 'regular' THEN 0.05 ELSE 0.025 END)
       AND NOT EXISTS (
         SELECT 1 FROM form_submissions fs
         WHERE fs.form_id = v_form_pref AND fs.user_id = v_member.user_id
       )
    THEN
      BEGIN
        v_sub_num := 'SEED-RKT-PREF-' || replace(v_member.user_id::text, '-', '');
        INSERT INTO form_submissions (
          form_id, merchant_id, user_id, submission_number, status,
          created_at, submitted_at, source, skip_cdc
        ) VALUES (
          v_form_pref, v_merchant_id, v_member.user_id, v_sub_num, 'completed',
          v_ts, v_ts, 'rocket-demo-seed', true
        ) RETURNING id INTO v_sub_id;

        v_interest := (ARRAY['skincare','makeup','fragrance','wellness'])[
          1 + floor(custom_internal_demo_rand(v_member.user_id::text || ':int') * 4)::int];
        v_cat := (ARRAY['treat','protect','cleanse','body'])[
          1 + floor(custom_internal_demo_rand(v_member.user_id::text || ':cat') * 4)::int];
        v_concern := (ARRAY['dryness','dullness','acne','aging'])[
          1 + floor(custom_internal_demo_rand(v_member.user_id::text || ':con') * 4)::int];

        INSERT INTO form_responses (submission_id, field_id, text_value) VALUES
          (v_sub_id, v_ff_interest, v_interest),
          (v_sub_id, v_ff_category, v_cat),
          (v_sub_id, v_ff_concern, v_concern);

        IF v_interest = 'fragrance' AND v_tag_fragrance IS NOT NULL THEN
          INSERT INTO user_tags (user_id, tag_id, merchant_id, source_type)
          VALUES (v_member.user_id, v_tag_fragrance, v_merchant_id, 'rocket-demo-seed')
          ON CONFLICT DO NOTHING;
          v_tag_n := v_tag_n + 1;
        END IF;

        IF v_mission_survey IS NOT NULL AND v_cond_survey IS NOT NULL THEN
          INSERT INTO mission_progress (
            user_id, mission_id, current_progress, current_target_value,
            period_completions, lifetime_completions, condition_progress,
            last_progress_at, last_completed_at, is_active, accepted_at
          ) VALUES (
            v_member.user_id, v_mission_survey, 1, 1, 1, 1,
            jsonb_build_object(v_cond_survey::text, 1),
            v_ts, v_ts, true, v_ts
          )
          ON CONFLICT DO NOTHING;
          v_mission_n := v_mission_n + 1;
        END IF;
        v_survey_n := v_survey_n + 1;
      EXCEPTION WHEN OTHERS THEN
        v_errors := array_append(v_errors, 'survey:' || SQLERRM);
      END;
    END IF;

    -- NPS trickle
    v_roll := custom_internal_demo_rand(v_member.user_id::text || p_date::text || ':nps');
    IF v_nps_n < (v_cap_survey / 3)
       AND v_roll < 0.015
       AND NOT EXISTS (
         SELECT 1 FROM form_submissions fs
         WHERE fs.form_id = v_form_nps AND fs.user_id = v_member.user_id
           AND fs.created_at::date = p_date
       )
    THEN
      BEGIN
        v_sub_num := 'SEED-RKT-NPS-' || to_char(p_date, 'YYYYMMDD') || '-' || replace(v_member.user_id::text, '-', '');
        INSERT INTO form_submissions (
          form_id, merchant_id, user_id, submission_number, status,
          created_at, submitted_at, source, skip_cdc
        ) VALUES (
          v_form_nps, v_merchant_id, v_member.user_id, v_sub_num, 'completed',
          v_ts, v_ts, 'rocket-demo-seed', true
        ) RETURNING id INTO v_sub_id;
        INSERT INTO form_responses (submission_id, field_id, text_value) VALUES
          (v_sub_id, v_ff_nps, (6 + floor(custom_internal_demo_rand(v_member.user_id::text || ':score') * 5)::int)::text),
          (v_sub_id, v_ff_comment, 'Seed NPS');
        v_nps_n := v_nps_n + 1;
      EXCEPTION WHEN OTHERS THEN
        v_errors := array_append(v_errors, 'nps:' || SQLERRM);
      END;
    END IF;

    -- Spend mission progress sync
    IF v_mission_spend IS NOT NULL AND v_cond_spend IS NOT NULL AND v_member.lifetime_spend > 0 THEN
      BEGIN
        INSERT INTO mission_progress (
          user_id, mission_id, current_progress, current_target_value,
          period_completions, lifetime_completions, condition_progress,
          last_progress_at, last_completed_at, is_active, accepted_at
        ) VALUES (
          v_member.user_id, v_mission_spend,
          least(v_member.lifetime_spend, 3000), 3000,
          CASE WHEN v_member.lifetime_spend >= 3000 THEN 1 ELSE 0 END,
          CASE WHEN v_member.lifetime_spend >= 3000 THEN 1 ELSE 0 END,
          jsonb_build_object(v_cond_spend::text, least(v_member.lifetime_spend, 3000)),
          v_ts,
          CASE WHEN v_member.lifetime_spend >= 3000 THEN v_ts ELSE NULL END,
          true, v_ts
        )
        ON CONFLICT (user_id, mission_id) DO UPDATE SET
          current_progress = EXCLUDED.current_progress,
          condition_progress = EXCLUDED.condition_progress,
          period_completions = EXCLUDED.period_completions,
          lifetime_completions = EXCLUDED.lifetime_completions,
          last_progress_at = EXCLUDED.last_progress_at,
          last_completed_at = COALESCE(EXCLUDED.last_completed_at, mission_progress.last_completed_at),
          updated_at = now();
        v_mission_n := v_mission_n + 1;
      EXCEPTION WHEN OTHERS THEN
        v_errors := array_append(v_errors, 'mission:' || SQLERRM);
      END;
    END IF;

    -- Spin (live prefers real RPC; keep volume low)
    v_roll := custom_internal_demo_rand(v_member.user_id::text || p_date::text || ':spin');
    IF v_spin_n < v_cap_spin
       AND v_spin_weekend IS NOT NULL
       AND v_member.points_balance >= 50
       AND v_roll < (CASE v_member.archetype WHEN 'whale' THEN 0.04 WHEN 'regular' THEN 0.02 ELSE 0.01 END)
    THEN
      BEGIN
        v_spin_result := fn_spin_wheel(v_member.user_id, v_merchant_id, v_spin_weekend);
        IF coalesce((v_spin_result->>'success')::boolean, false)
           OR v_spin_result ? 'segment_id'
           OR NOT (v_spin_result ? 'error') THEN
          v_spin_n := v_spin_n + 1;
        END IF;
      EXCEPTION WHEN OTHERS THEN
        v_errors := array_append(v_errors, 'spin:' || SQLERRM);
      END;
    END IF;

    -- Light tag drift
    IF v_tag_app IS NOT NULL
       AND custom_internal_demo_rand(v_member.user_id::text || p_date::text || ':app') < 0.01
    THEN
      INSERT INTO user_tags (user_id, tag_id, merchant_id, source_type)
      VALUES (v_member.user_id, v_tag_app, v_merchant_id, 'rocket-demo-seed')
      ON CONFLICT DO NOTHING;
      v_tag_n := v_tag_n + 1;
    END IF;
  END LOOP;

  RETURN jsonb_build_object(
    'success', true,
    'surveys', v_survey_n,
    'nps', v_nps_n,
    'mission_touches', v_mission_n,
    'spins', v_spin_n,
    'tag_touches', v_tag_n,
    'errors', to_jsonb(v_errors)
  );
END;
$body$;
