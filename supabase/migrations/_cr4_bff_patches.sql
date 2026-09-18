-- Applied to prod via deploy runbook

CREATE OR REPLACE FUNCTION public.bff_get_mission_detail(p_mission_id uuid, p_user_id uuid DEFAULT NULL::uuid, p_language text DEFAULT 'en'::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
DECLARE
  v_lang text;
  v_user_id UUID;
  v_merchant_id UUID;
  v_is_admin BOOLEAN := FALSE;
  v_mission RECORD;
  v_progress RECORD;
  v_conditions JSONB;
  v_outcomes JSONB;
  v_completion_history JSONB;
  v_stats JSONB;
  v_completion_pct NUMERIC;
  v_conditions_completed INT;
  v_total_conditions INT;
  v_access JSONB;
  v_unclaimed INT;
  v_claim_quota JSONB;
BEGIN
  v_lang := fn_normalize_ui_language(p_language);
  IF p_user_id IS NOT NULL THEN
    SELECT EXISTS (SELECT 1 FROM admin_users WHERE auth_user_id = auth.uid() AND active_status = true) INTO v_is_admin;
    IF NOT v_is_admin THEN
      RETURN jsonb_build_object('success', false, 'title', fn_mission_envelope_message('permission_denied_title', v_lang), 'description', 'Only admins can view other users'' mission details', 'data', null);
    END IF;
    v_user_id := p_user_id;
  ELSE
    v_user_id := auth.uid();
    IF v_user_id IS NULL THEN
      RETURN jsonb_build_object('success', false, 'title', fn_mission_envelope_message('auth_required_title', v_lang), 'description', 'You must be logged in to view mission details', 'data', null);
    END IF;
  END IF;

  v_merchant_id := get_current_merchant_id();
  IF v_merchant_id IS NULL THEN
    RETURN jsonb_build_object('success', false, 'title', fn_mission_envelope_message('merchant_required_title', v_lang), 'description', 'Unable to determine merchant from authentication context', 'data', null);
  END IF;

  SELECT m.* INTO v_mission FROM mission m WHERE m.id = p_mission_id AND m.merchant_id = v_merchant_id;
  IF NOT FOUND THEN
    RETURN jsonb_build_object('success', false, 'title', fn_mission_envelope_message('mission_not_found_title', v_lang), 'description', 'The requested mission does not exist or you do not have access', 'data', null);
  END IF;

  v_access := fn_mission_access_state(p_mission_id, v_user_id, v_merchant_id, now());
  IF NOT v_is_admin
     AND COALESCE((v_access->>'is_visible')::boolean, false) IS NOT TRUE
     AND NOT (COALESCE(v_access->'reason_codes', '[]'::jsonb) ? 'after_end') THEN
    RETURN jsonb_build_object('success', false, 'title', fn_mission_envelope_message('mission_not_found_title', v_lang), 'description', 'The requested mission does not exist or you do not have access', 'data', null,
      'reason_codes', v_access->'reason_codes');
  END IF;

  SELECT mp.id, mp.current_progress, mp.condition_progress, mp.lifetime_completions,
    mp.unclaimed_completions, mp.accepted_at, mp.last_progress_at, mp.last_completed_at,
    mp.period_completions, mp.period_claims, mp.is_active
  INTO v_progress FROM mission_progress mp WHERE mp.user_id = v_user_id AND mp.mission_id = p_mission_id;

  SELECT COUNT(*)::integer INTO v_unclaimed
  FROM mission_log_completion mlc
  WHERE mlc.user_id = v_user_id
    AND mlc.mission_id = p_mission_id
    AND mlc.outcomes_distributed IS DISTINCT FROM true;

  v_claim_quota := fn_mission_claim_quota(v_user_id, p_mission_id, COALESCE(v_unclaimed, 0));

  IF v_mission.mission_type = 'milestone' THEN
    SELECT jsonb_agg(
      jsonb_build_object(
        'condition_id', mc.id, 'condition_type', mc.condition_type::text, 'measurement_type', mc.measurement_type::text,
        'target_value', mc.target_value,
        'current_value', COALESCE((v_progress.condition_progress->('level_' || mc.milestone_level)->>'current')::numeric, 0),
        'percentage', CASE WHEN mc.target_value > 0 THEN LEAST(ROUND(COALESCE((v_progress.condition_progress->('level_' || mc.milestone_level)->>'current')::numeric, 0) / mc.target_value * 100), 100) ELSE 100 END,
        'is_completed', (v_progress.condition_progress->('level_' || mc.milestone_level)->>'completed_at') IS NOT NULL,
        'completed_at', v_progress.condition_progress->('level_' || mc.milestone_level)->>'completed_at',
        'description', mc.description,
        'has_filters', (mc.product_ids IS NOT NULL OR mc.sku_ids IS NOT NULL OR mc.category_ids IS NOT NULL OR mc.brand_ids IS NOT NULL),
        'milestone_level', mc.milestone_level, 'milestone_name', mc.milestone_name, 'milestone_badge_url', mc.milestone_badge_url,
        'outcomes', (
          SELECT COALESCE(jsonb_agg(jsonb_build_object(
            'outcome_type', mo.outcome_type::text, 'amount', mo.amount, 'entity_id', mo.entity_id,
            'entity_name', CASE mo.outcome_type::text
              WHEN 'points' THEN mo.amount || ' พอยท์'
              WHEN 'tickets' THEN mo.amount || ' ' || COALESCE(tt.name, 'ตั๋ว')
              WHEN 'reward' THEN rm.name ELSE mo.outcome_type::text END,
            'entity_image', CASE WHEN mo.outcome_type::text = 'reward' AND rm.image IS NOT NULL THEN rm.image[1] ELSE NULL END, 'fulfillment_method', CASE WHEN mo.outcome_type = 'reward' THEN rm.fulfillment_method::text ELSE NULL END
          ) ORDER BY mo.outcome_type), '[]'::jsonb)
          FROM mission_outcomes mo
          LEFT JOIN reward_master rm ON mo.outcome_type = 'reward' AND rm.id = mo.entity_id
          LEFT JOIN ticket_type tt ON mo.outcome_type = 'tickets' AND tt.id = mo.entity_id
          WHERE mo.mission_id = p_mission_id AND mo.milestone_level = mc.milestone_level
        )
      ) ORDER BY mc.milestone_level
    ) INTO v_conditions
    FROM mission_conditions mc WHERE mc.mission_id = p_mission_id AND mc.milestone_level IS NOT NULL;
    v_outcomes := '[]'::jsonb;
    SELECT
      COALESCE(ROUND(COUNT(*) FILTER (WHERE (v_progress.condition_progress->('level_' || mc.milestone_level)->>'completed_at') IS NOT NULL)::numeric / NULLIF(COUNT(*), 0)::numeric * 100), 0),
      COUNT(*) FILTER (WHERE (v_progress.condition_progress->('level_' || mc.milestone_level)->>'completed_at') IS NOT NULL),
      COUNT(*)
    INTO v_completion_pct, v_conditions_completed, v_total_conditions
    FROM mission_conditions mc WHERE mc.mission_id = p_mission_id AND mc.milestone_level IS NOT NULL;
  ELSE
    SELECT jsonb_agg(
      jsonb_build_object(
        'condition_id', mc.id, 'condition_type', mc.condition_type::text, 'measurement_type', mc.measurement_type::text,
        'target_value', mc.target_value,
        'current_value', COALESCE((v_progress.condition_progress->(mc.id::text)->>'current')::numeric, 0),
        'percentage', CASE WHEN mc.target_value > 0 THEN LEAST(ROUND(COALESCE((v_progress.condition_progress->(mc.id::text)->>'current')::numeric, 0) / mc.target_value * 100), 100) ELSE 100 END,
        'is_completed', CASE WHEN mc.target_value > 0 THEN COALESCE((v_progress.condition_progress->(mc.id::text)->>'current')::numeric, 0) >= mc.target_value ELSE true END,
        'operator', mc.operator::text, 'description', mc.description,
        'has_filters', (mc.product_ids IS NOT NULL OR mc.sku_ids IS NOT NULL OR mc.category_ids IS NOT NULL OR mc.brand_ids IS NOT NULL)
      ) ORDER BY mc.created_at
    ) INTO v_conditions FROM mission_conditions mc WHERE mc.mission_id = p_mission_id;

    SELECT jsonb_agg(jsonb_build_object(
      'outcome_type', mo.outcome_type::text, 'amount', mo.amount, 'entity_id', mo.entity_id,
      'entity_name', CASE mo.outcome_type::text
        WHEN 'points' THEN mo.amount || ' พอยท์'
        WHEN 'tickets' THEN mo.amount || ' ' || COALESCE(tt.name, 'ตั๋ว')
        WHEN 'reward' THEN rm.name ELSE mo.outcome_type::text END,
      'entity_image', CASE WHEN mo.outcome_type::text = 'reward' AND rm.image IS NOT NULL THEN rm.image[1] ELSE NULL END, 'fulfillment_method', CASE WHEN mo.outcome_type = 'reward' THEN rm.fulfillment_method::text ELSE NULL END
    ) ORDER BY mo.outcome_type)
    INTO v_outcomes FROM mission_outcomes mo
    LEFT JOIN reward_master rm ON mo.outcome_type = 'reward' AND rm.id = mo.entity_id
    LEFT JOIN ticket_type tt ON mo.outcome_type = 'tickets' AND tt.id = mo.entity_id
    WHERE mo.mission_id = p_mission_id;

    SELECT
      CASE WHEN EXISTS (SELECT 1 FROM mission_conditions mc2 WHERE mc2.mission_id = p_mission_id AND mc2.operator::text = 'OR') THEN
        COALESCE(MAX(LEAST(CASE WHEN mc.target_value > 0 THEN COALESCE((v_progress.condition_progress->(mc.id::text)->>'current')::numeric, 0) / mc.target_value * 100 ELSE 100 END, 100)), 0)
      ELSE
        COALESCE(ROUND(AVG(LEAST(CASE WHEN mc.target_value > 0 THEN COALESCE((v_progress.condition_progress->(mc.id::text)->>'current')::numeric, 0) / mc.target_value * 100 ELSE 100 END, 100))), 0)
      END,
      COUNT(*) FILTER (WHERE CASE WHEN mc.target_value > 0 THEN COALESCE((v_progress.condition_progress->(mc.id::text)->>'current')::numeric, 0) >= mc.target_value ELSE true END),
      COUNT(*)
    INTO v_completion_pct, v_conditions_completed, v_total_conditions FROM mission_conditions mc WHERE mc.mission_id = p_mission_id;
  END IF;

  SELECT jsonb_agg(jsonb_build_object(
    'completion_id', mlc.id, 'completion_number', mlc.completion_number, 'milestone_level', mlc.milestone_level,
    'progress_used', mlc.progress_used, 'is_claimed', mlc.is_claimed, 'completed_at', mlc.completed_at, 'claimed_at', mlc.claimed_at
  ) ORDER BY mlc.completed_at DESC)
  INTO v_completion_history
  FROM (SELECT * FROM mission_log_completion WHERE user_id = v_user_id AND mission_id = p_mission_id ORDER BY completed_at DESC LIMIT 10) mlc;

  v_stats := jsonb_build_object(
    'total_target', (SELECT SUM(target_value) FROM mission_conditions WHERE mission_id = p_mission_id),
    'completion_percentage', v_completion_pct, 'conditions_completed', v_conditions_completed, 'total_conditions', v_total_conditions,
    'levels_completed', CASE WHEN v_mission.mission_type = 'milestone' THEN v_conditions_completed ELSE NULL END,
    'total_levels', CASE WHEN v_mission.mission_type = 'milestone' THEN v_total_conditions ELSE NULL END,
    'can_claim', COALESCE((v_access->>'can_claim')::boolean, false),
    'can_accept', COALESCE((v_access->>'can_join')::boolean, false) AND v_progress.accepted_at IS NULL AND v_mission.progress_activation_type = 'manual',
    'can_progress', COALESCE((v_access->>'can_progress')::boolean, false),
    'exclusivity_locked', COALESCE((v_access->>'exclusivity_locked')::boolean, false),
    'is_fully_completed', v_conditions_completed = v_total_conditions AND v_total_conditions > 0,
    'button_action', CASE
      WHEN COALESCE((v_access->>'exclusivity_locked')::boolean, false) THEN 'exclusivity_locked'
      WHEN COALESCE((v_access->>'can_claim')::boolean, false) THEN 'claim_outcome'
      WHEN COALESCE((v_access->>'can_join')::boolean, false) AND v_progress.accepted_at IS NULL AND v_mission.progress_activation_type = 'manual' THEN 'join_mission'
      WHEN v_conditions_completed = v_total_conditions AND v_total_conditions > 0 THEN 'claimed'
      WHEN v_progress.id IS NOT NULL THEN 'view_progress' ELSE 'view_details' END
  );

  RETURN jsonb_build_object(
    'success', true, 'title', fn_mission_envelope_message('mission_details_retrieved_title', v_lang), 'description', null,
    'data', jsonb_build_object(
      'user_id', v_user_id,
      'access_state', v_access,
      'mission', jsonb_build_object(
        'id', v_mission.id, 'code', v_mission.mission_code, 'name', v_mission.mission_name,
        'description', v_mission.mission_description, 'description_goal', v_mission.description_goal,
        'description_tc', v_mission.description_tc, 'type', v_mission.mission_type::text, 'images', v_mission.images,
        'activation_type', v_mission.progress_activation_type::text, 'claim_type', v_mission.claim_type::text,
        'reset_frequency', v_mission.progress_reset_frequency::text, 'reset_mode', v_mission.reset_mode,
        'allow_loop', v_mission.allow_progress_loop, 'max_loops', v_mission.max_loops_per_transaction,
        'carry_over_progress', v_mission.carry_over_progress,
        'milestone_allow_skip', v_mission.milestone_allow_skip, 'start_date', v_mission.start_date,
        'end_date', v_mission.end_date, 'claim_end_date', v_mission.claim_end_date,
        'preview_advance_days', v_mission.preview_advance_days, 'is_active', v_mission.is_active,
        'eligible_persona_ids', v_mission.eligible_persona_ids,
        'eligible_persona_group_ids', v_mission.eligible_persona_group_ids,
        'signup_window_start', v_mission.signup_window_start,
        'signup_window_end', v_mission.signup_window_end
      ),
      'progress', jsonb_build_object(
        'is_accepted', v_progress.accepted_at IS NOT NULL, 'accepted_at', v_progress.accepted_at,
        'lifetime_completions', COALESCE(v_progress.lifetime_completions, 0),
        'unclaimed_completions', COALESCE(v_unclaimed, 0),
        'claimable_now', (v_claim_quota->>'claimable_now')::integer,
        'claim_limit_time_unit', NULLIF(v_claim_quota->>'claim_limit_time_unit', ''),
        'claim_limit_max', NULLIF(v_claim_quota->>'claim_limit_max', '')::integer,
        'claim_limit_scope', NULLIF(v_claim_quota->>'claim_limit_scope', ''),
        'period_completions', COALESCE(v_progress.period_completions, 0),
        'period_claims', COALESCE(v_progress.period_claims, 0),
        'last_progress_at', v_progress.last_progress_at, 'last_completed_at', v_progress.last_completed_at
      ),
      'conditions', COALESCE(v_conditions, '[]'::jsonb),
      'outcomes', COALESCE(v_outcomes, '[]'::jsonb),
      'completion_history', COALESCE(v_completion_history, '[]'::jsonb),
      'stats', v_stats
    )
  );
END;
$function$


CREATE OR REPLACE FUNCTION public.bff_claim_mission(p_mission_id uuid, p_user_id uuid DEFAULT NULL::uuid, p_milestone_level integer DEFAULT NULL::integer, p_quantity integer DEFAULT 1)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
DECLARE
  v_target_user_id UUID;
  v_merchant_id UUID;
  v_caller_id UUID;
  v_is_admin BOOLEAN := FALSE;
  v_admin_user_id UUID;
  v_mission RECORD;
  v_access JSONB;
  v_distribute JSONB;
  v_mis_txn TEXT;
  v_qty INTEGER := 1;
  v_rewards_count INTEGER := 0;
  v_points_total INTEGER := 0;
  v_tickets_total INTEGER := 0;
  v_claim_quota JSONB;
  v_unclaimed_quota INTEGER;
BEGIN
  v_caller_id := auth.uid();
  v_merchant_id := get_current_merchant_id();
  IF v_merchant_id IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'no_merchant_context', 'message', 'Merchant context required');
  END IF;

  IF p_quantity IS NULL OR p_quantity < 1 THEN
    RETURN jsonb_build_object('success', false, 'error', 'invalid_quantity', 'message', 'Quantity must be at least 1');
  END IF;

  IF p_user_id IS NULL THEN
    v_target_user_id := v_caller_id;
    IF v_target_user_id IS NULL THEN
      RETURN jsonb_build_object('success', false, 'error', 'authentication_required', 'message', 'User must be authenticated');
    END IF;
  ELSE
    SELECT au.id INTO v_admin_user_id
    FROM admin_users au
    WHERE au.auth_user_id = v_caller_id AND au.merchant_id = v_merchant_id AND au.active_status = true
    LIMIT 1;
    v_is_admin := v_admin_user_id IS NOT NULL;
    IF NOT v_is_admin THEN
      RETURN jsonb_build_object('success', false, 'error', 'admin_required', 'message', 'Admin access required to claim on behalf of users');
    END IF;
    v_target_user_id := p_user_id;
  END IF;

  IF NOT v_is_admin AND public.fn_is_user_frozen(v_target_user_id) THEN
    RETURN public.fn_account_restricted_error();
  END IF;

  SELECT m.* INTO v_mission
  FROM mission m WHERE m.id = p_mission_id AND m.merchant_id = v_merchant_id;
  IF NOT FOUND THEN
    RETURN jsonb_build_object('success', false, 'error', 'mission_not_found', 'message', 'Mission not found');
  END IF;

  v_access := fn_mission_access_state(p_mission_id, v_target_user_id, v_merchant_id, now());
  IF COALESCE((v_access->>'can_claim')::boolean, false) IS NOT TRUE
     AND COALESCE((v_access->>'exclusivity_locked')::boolean, false) THEN
    RETURN jsonb_build_object(
      'success', false, 'error', 'exclusivity_locked',
      'message', 'Another mission in this claim group was already claimed',
      'access_state', v_access
    );
  END IF;
  IF COALESCE((v_access->>'can_claim')::boolean, false) IS NOT TRUE THEN
    RETURN jsonb_build_object(
      'success', false, 'error', 'cannot_claim',
      'message', 'Mission is not claimable',
      'reason_codes', v_access->'reason_codes',
      'access_state', v_access
    );
  END IF;

  IF p_milestone_level IS NOT NULL AND v_mission.mission_type != 'milestone' THEN
    RETURN jsonb_build_object('success', false, 'error', 'invalid_parameter', 'message', 'milestone_level can only be used with milestone missions');
  END IF;

  v_distribute := fn_process_mission_outcomes_batch(
    v_target_user_id,
    p_mission_id,
    v_merchant_id,
    p_quantity,
    p_milestone_level
  );

  IF NOT COALESCE((v_distribute->>'success')::boolean, false) THEN
    v_claim_quota := NULL;
    IF COALESCE(v_distribute->>'error', '') = 'claim_limit_exceeded' THEN
      SELECT COUNT(*)::integer INTO v_unclaimed_quota
      FROM mission_log_completion mlc
      WHERE mlc.user_id = v_target_user_id
        AND mlc.mission_id = p_mission_id
        AND mlc.outcomes_distributed IS DISTINCT FROM true;
      v_claim_quota := fn_mission_claim_quota(v_target_user_id, p_mission_id, COALESCE(v_unclaimed_quota, 0));
    END IF;
    RETURN jsonb_build_object(
      'success', false,
      'error', COALESCE(v_distribute->>'error', 'claim_failed'),
      'message', CASE COALESCE(v_distribute->>'error', '')
        WHEN 'no_unclaimed_completions' THEN 'No unclaimed mission completions found'
        WHEN 'claim_limit_exceeded' THEN 'Claim limit exceeded'
        WHEN 'exclusivity_locked' THEN 'Another mission in this claim group was already claimed'
        WHEN 'invalid_quantity' THEN 'Quantity must be at least 1'
        ELSE 'Failed to process mission claim'
      END,
      'allowed', NULLIF(v_distribute->>'allowed', '')::integer,
      'claim_limit_scope', v_claim_quota->>'claim_limit_scope',
      'claim_limit_time_unit', NULLIF(v_claim_quota->>'claim_limit_time_unit', ''),
      'claim_limit_max', NULLIF(v_claim_quota->>'claim_limit_max', '')::integer,
      'reason_codes', v_access->'reason_codes',
      'data', v_distribute
    );
  END IF;

  v_qty := COALESCE((v_distribute->>'quantity_claimed')::integer, p_quantity);

  SELECT
    COUNT(*) FILTER (WHERE outcome_type = 'reward'),
    COALESCE(SUM(amount) FILTER (WHERE outcome_type = 'points'), 0)::integer,
    COALESCE(SUM(amount) FILTER (WHERE outcome_type = 'tickets'), 0)::integer
  INTO v_rewards_count, v_points_total, v_tickets_total
  FROM outcome_distribution_log
  WHERE user_id = v_target_user_id AND source_type = 'mission' AND source_id = p_mission_id
    AND distributed_at >= NOW() - INTERVAL '1 minute' AND success = true;

  IF v_mission.claim_type IS DISTINCT FROM 'auto' THEN
    v_mis_txn := 'MIS-'
      || to_char((timezone(public.fn_mission_merchant_tz(v_merchant_id), now())), 'YYYYMMDD')
      || '-'
      || lpad((floor(random() * 100000000))::bigint::text, 8, '0')
      || '-'
      || substr(replace(v_merchant_id::text, '-', ''), 1, 4);
    INSERT INTO public.frontline_mission_claim_log (
      merchant_id, user_id, mission_id, admin_user_id, store_id,
      action, quantity_claimed, transaction_number, claimed_at,
      mission_name, mission_summary, reward_redemption_summary,
      redemptions, completion_ids, notes
    ) VALUES (
      v_merchant_id, v_target_user_id, p_mission_id, v_admin_user_id, NULL,
      'claim', v_qty, v_mis_txn, now(),
      v_mission.mission_name, '{}'::jsonb, NULL,
      '[]'::jsonb, ARRAY[]::uuid[], NULL
    );
  END IF;

  RETURN jsonb_build_object(
    'success', true,
    'message', CASE WHEN p_milestone_level IS NOT NULL THEN format('Milestone %s claimed successfully', p_milestone_level) ELSE 'Mission claimed successfully' END,
    'data', jsonb_build_object(
      'mission_id', p_mission_id,
      'mission_name', v_mission.mission_name,
      'user_id', v_target_user_id,
      'claimed_by', CASE WHEN v_is_admin THEN 'admin' ELSE 'user' END,
      'milestone_level', p_milestone_level,
      'quantity_claimed', v_qty,
      'outcomes', jsonb_build_object(
        'rewards_granted', v_rewards_count,
        'points_pending', v_points_total,
        'tickets_pending', v_tickets_total
      ),
      'note', CASE WHEN v_points_total > 0 OR v_tickets_total > 0 THEN 'Currency awards may be delayed based on merchant settings' ELSE NULL END
    )
  );
END;
$function$
