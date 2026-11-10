-- Package 2: member totals — point earned/used sums at v_wallet_ledger_flow

CREATE OR REPLACE FUNCTION public.bff_admin_get_member_360_base(p_user_id uuid, p_months integer DEFAULT 12, p_activity_limit integer DEFAULT 50)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
DECLARE
  v_merchant_id uuid;
  v_user record;
  v_result jsonb;
  v_profile jsonb;
  v_tier_progress jsonb;
  v_wallet jsonb;
  v_points_monthly jsonb;
  v_points_by_source jsonb;
  v_redemption_summary jsonb;
  v_redemptions_by_reward jsonb;
  v_redemptions_monthly jsonb;
  v_purchase_summary jsonb;
  v_purchases_monthly jsonb;
  v_referral jsonb;
  v_activity_stream jsonb;
  v_activity_counts jsonb;
  v_checkin jsonb;
  v_tier_history jsonb;
  v_removal_info jsonb;
  v_rfm jsonb;
  v_acquisition jsonb;
  v_cutoff timestamptz;
BEGIN
  v_merchant_id := get_current_merchant_id();
  IF v_merchant_id IS NULL THEN
    RETURN fn_response_error('Unauthorized', 'Merchant context required');
  END IF;

  IF NOT (
    check_admin_permission('customer-360', 'read')
    OR check_admin_permission('front_line', 'read')
  ) THEN
    RETURN fn_response_error(
      'Permission denied',
      'customer-360.read or front_line.read required'
    );
  END IF;

  v_cutoff := now() - (p_months || ' months')::interval;

  SELECT jsonb_build_object(
    'user_id', ua.id, 'fullname', ua.fullname, 'firstname', ua.firstname, 'lastname', ua.lastname,
    'email', ua.email, 'tel', ua.tel, 'line_id', ua.line_id, 'image', ua.image,
    'user_type', ua.user_type, 'user_stage', ua.user_stage, 'birth_date', ua.birth_date, 'gender', ua.gender,
    'external_user_id', ua.external_user_id, 'created_at', ua.created_at, 'deleted_at', ua.deleted_at,
    'is_freeze', COALESCE(ua.is_freeze, false),
    'tier_id', ua.tier_id, 'tier_name', tm.tier_name, 'tier_color', tm.color, 'tier_icon', tm.icon,
    'persona_id', ua.persona_id, 'persona_name', COALESCE(pm.persona_name, CASE WHEN pm.id IS NULL THEN pgm.group_name END), 'persona_group_name', CASE WHEN pm.id IS NOT NULL THEN pgm.group_name END,
    'contract_type', pgm.contract_type, 'company_name', pgm.company_name, 'contract_status', pgm.contract_status,
    'tags', COALESCE((SELECT jsonb_agg(jsonb_build_object('id', tg.id, 'tag_name', tg.tag_name)) FROM user_tags ut JOIN tag_master tg ON tg.id = ut.tag_id WHERE ut.user_id = ua.id AND ut.merchant_id = v_merchant_id), '[]'::jsonb)
  ) INTO v_profile
  FROM user_accounts ua
  LEFT JOIN tier_master tm ON tm.id = ua.tier_id
  LEFT JOIN persona_master pm ON pm.id = ua.persona_id AND pm.merchant_id = ua.merchant_id
  LEFT JOIN persona_group_master pgm ON pgm.id = COALESCE(pm.group_id, ua.persona_id) AND pgm.merchant_id = ua.merchant_id
  WHERE ua.id = p_user_id AND ua.merchant_id = v_merchant_id;

  IF v_profile IS NULL THEN
    RETURN fn_response_error('Not Found', 'User not found in this merchant');
  END IF;

  IF (v_profile->>'deleted_at') IS NOT NULL THEN
    RETURN fn_response_error('Not Found', 'User not found in this merchant');
  END IF;

  v_tier_progress := public.fn_admin_get_tier_progress_enriched(p_user_id, v_merchant_id);

  IF v_tier_progress IS NULL THEN v_tier_progress := '{}'::jsonb; END IF;

  SELECT COALESCE(jsonb_agg(row_to_json(th)::jsonb ORDER BY th.created_at DESC), '[]'::jsonb) INTO v_tier_history
  FROM (
    SELECT tcl.id, tcl.change_type, tcl.change_reason, tcl.created_at,
      ft.tier_name AS from_tier_name, ft.color AS from_tier_color, tt.tier_name AS to_tier_name, tt.color AS to_tier_color
    FROM tier_change_ledger tcl
    LEFT JOIN tier_master ft ON ft.id = tcl.from_tier_id
    LEFT JOIN tier_master tt ON tt.id = tcl.to_tier_id
    WHERE tcl.user_id = p_user_id AND tcl.merchant_id = v_merchant_id
    ORDER BY tcl.created_at DESC LIMIT 20
  ) th;

  SELECT jsonb_build_object(
    'points_balance', COALESCE(uw.points_balance, 0),
    'ticket_balances', COALESCE((SELECT jsonb_agg(jsonb_build_object('ticket_type_id', tb.ticket_type_id, 'ticket_code', tb.ticket_code, 'name', tb.name, 'balance', tb.balance)) FROM get_all_user_ticket_balances(p_user_id, v_merchant_id, false) tb), '[]'::jsonb),
    'lifetime_earned', GREATEST(0, COALESCE((SELECT SUM(earned_delta) FROM v_wallet_ledger_flow WHERE user_id = p_user_id AND merchant_id = v_merchant_id AND currency = 'points'), 0)),
    'lifetime_burned', GREATEST(0, COALESCE((SELECT SUM(used_delta) FROM v_wallet_ledger_flow WHERE user_id = p_user_id AND merchant_id = v_merchant_id AND currency = 'points'), 0)),
    'expiring_soon_amount', COALESCE((SELECT SUM(GREATEST(deductible_balance, 0)) FROM wallet_ledger WHERE user_id = p_user_id AND merchant_id = v_merchant_id AND currency = 'points' AND transaction_type = 'earn' AND expiry_date IS NOT NULL AND expiry_date <= (current_date + interval '30 days') AND expiry_date > current_date AND deductible_balance > 0), 0),
    'expiring_soon_date', (SELECT MIN(expiry_date) FROM wallet_ledger WHERE user_id = p_user_id AND merchant_id = v_merchant_id AND currency = 'points' AND transaction_type = 'earn' AND expiry_date IS NOT NULL AND expiry_date > current_date AND deductible_balance > 0)
  ) INTO v_wallet FROM user_wallet uw WHERE uw.user_id = p_user_id AND uw.merchant_id = v_merchant_id;

  IF v_wallet IS NULL THEN
    v_wallet := jsonb_build_object('points_balance', 0, 'ticket_balances', '[]'::jsonb, 'lifetime_earned', 0, 'lifetime_burned', 0, 'expiring_soon_amount', 0, 'expiring_soon_date', null);
  END IF;

  SELECT COALESCE(jsonb_agg(row_to_json(pm)::jsonb ORDER BY pm.month), '[]'::jsonb) INTO v_points_monthly
  FROM (
    SELECT date_trunc('month', wl.created_at)::date AS month,
      GREATEST(0, COALESCE(SUM(wl.earned_delta), 0)) AS earned,
      GREATEST(0, COALESCE(SUM(wl.used_delta), 0)) AS burned
    FROM v_wallet_ledger_flow wl
    WHERE wl.user_id = p_user_id AND wl.merchant_id = v_merchant_id AND wl.currency = 'points' AND wl.created_at >= v_cutoff
    GROUP BY date_trunc('month', wl.created_at)::date ORDER BY month
  ) pm;

  SELECT COALESCE(jsonb_agg(row_to_json(ps)::jsonb ORDER BY ps.total_earned DESC), '[]'::jsonb) INTO v_points_by_source
  FROM (
    SELECT wl.source_type::text AS source_type, SUM(wl.earned_delta) AS total_earned
    FROM v_wallet_ledger_flow wl
    WHERE wl.user_id = p_user_id AND wl.merchant_id = v_merchant_id AND wl.currency = 'points'
    GROUP BY wl.source_type
    HAVING SUM(wl.earned_delta) > 0
    ORDER BY total_earned DESC
  ) ps;

  SELECT jsonb_build_object('total_count', COUNT(*), 'total_points_spent', COALESCE(SUM(rrl.points_deducted), 0), 'total_qty', COALESCE(SUM(rrl.qty), 0))
  INTO v_redemption_summary
  FROM reward_redemptions_ledger rrl
  WHERE rrl.user_id = p_user_id AND rrl.merchant_id = v_merchant_id
    AND (rrl.source_type = 'reward_redemption' OR (rrl.source_type IS NULL AND COALESCE(rrl.points_deducted, 0) > 0))
    AND COALESCE(rrl.cancelled, false) = false;

  SELECT COALESCE(jsonb_agg(row_to_json(rb)::jsonb ORDER BY rb.count DESC), '[]'::jsonb) INTO v_redemptions_by_reward
  FROM (
    SELECT rm.name AS reward_name, rm.image AS reward_image, COUNT(*) AS count, COALESCE(SUM(rrl.points_deducted), 0) AS points_spent
    FROM reward_redemptions_ledger rrl JOIN reward_master rm ON rm.id = rrl.reward_id
    WHERE rrl.user_id = p_user_id AND rrl.merchant_id = v_merchant_id
      AND (rrl.source_type = 'reward_redemption' OR (rrl.source_type IS NULL AND COALESCE(rrl.points_deducted, 0) > 0))
      AND COALESCE(rrl.cancelled, false) = false
    GROUP BY rm.id, rm.name, rm.image ORDER BY count DESC LIMIT 10
  ) rb;

  SELECT COALESCE(jsonb_agg(row_to_json(rm2)::jsonb ORDER BY rm2.month), '[]'::jsonb) INTO v_redemptions_monthly
  FROM (
    SELECT date_trunc('month', rrl.created_at)::date AS month, COUNT(*) AS count, COALESCE(SUM(rrl.points_deducted), 0) AS points_spent
    FROM reward_redemptions_ledger rrl
    WHERE rrl.user_id = p_user_id AND rrl.merchant_id = v_merchant_id
      AND (rrl.source_type = 'reward_redemption' OR (rrl.source_type IS NULL AND COALESCE(rrl.points_deducted, 0) > 0))
      AND COALESCE(rrl.cancelled, false) = false
      AND rrl.created_at >= v_cutoff
    GROUP BY date_trunc('month', rrl.created_at)::date ORDER BY month
  ) rm2;

  SELECT jsonb_build_object(
    'lifetime_spend', COALESCE(SUM(pl.final_amount), 0), 'order_count', COUNT(*),
    'avg_order_value', CASE WHEN COUNT(*) > 0 THEN ROUND(COALESCE(SUM(pl.final_amount), 0) / COUNT(*), 2) ELSE 0 END,
    'last_purchase_at', MAX(pl.transaction_date)
  ) INTO v_purchase_summary
  FROM purchase_ledger pl
  WHERE pl.user_id = p_user_id AND pl.merchant_id = v_merchant_id AND pl.record_type = 'credit' AND pl.status = 'completed';

  SELECT COALESCE(jsonb_agg(row_to_json(pm2)::jsonb ORDER BY pm2.month), '[]'::jsonb) INTO v_purchases_monthly
  FROM (
    SELECT date_trunc('month', pl.transaction_date)::date AS month, COALESCE(SUM(pl.final_amount), 0) AS spend, COUNT(*) AS orders
    FROM purchase_ledger pl
    WHERE pl.user_id = p_user_id AND pl.merchant_id = v_merchant_id AND pl.record_type = 'credit' AND pl.status = 'completed' AND pl.transaction_date >= v_cutoff
    GROUP BY date_trunc('month', pl.transaction_date)::date ORDER BY month
  ) pm2;

  SELECT jsonb_build_object(
    'invite_code', (SELECT ua.member_code FROM user_accounts ua WHERE ua.id = p_user_id AND ua.merchant_id = v_merchant_id),
    'invites_sent', (SELECT COUNT(*) FROM referral_ledger rl WHERE rl.inviter_user_id = p_user_id AND rl.merchant_id = v_merchant_id),
    'signed_up', (SELECT COUNT(*) FROM referral_ledger rl WHERE rl.inviter_user_id = p_user_id AND rl.merchant_id = v_merchant_id AND rl.signed_up_at IS NOT NULL),
    'first_purchase', 0,
    'points_from_referrals', COALESCE((SELECT SUM(wl.signed_amount) FROM wallet_ledger wl WHERE wl.user_id = p_user_id AND wl.merchant_id = v_merchant_id AND wl.source_type = 'referral' AND wl.transaction_type = 'earn'), 0)
  ) INTO v_referral;

  -- Ledger-derived check-in summary (no checkin_streaks cache table)
  SELECT jsonb_build_object(
    'total_checkins', COALESCE((
      SELECT COUNT(*)::int FROM public.checkin_ledger cl
      WHERE cl.user_id = p_user_id AND cl.merchant_id = v_merchant_id
    ), 0),
    'current_streak', COALESCE((
      SELECT MAX(s.current_streak)
      FROM public.checkin c
      CROSS JOIN LATERAL public.fn_compute_checkin_streak(p_user_id, c.id) s
      WHERE c.merchant_id = v_merchant_id AND c.active_status = true
    ), 0),
    'longest_streak', COALESCE((
      SELECT MAX(s.longest_streak)
      FROM public.checkin c
      CROSS JOIN LATERAL public.fn_compute_checkin_streak(p_user_id, c.id) s
      WHERE c.merchant_id = v_merchant_id
    ), 0),
    'last_checkin_date', (
      SELECT MAX(cl.checkin_date) FROM public.checkin_ledger cl
      WHERE cl.user_id = p_user_id AND cl.merchant_id = v_merchant_id
    )
  ) INTO v_checkin;

  -- RFM badge (present only when the merchant has RFM computed for this member)
  SELECT jsonb_build_object(
    'segment', rs.rfm_segment, 'r_score', rs.r_score, 'f_score', rs.f_score, 'm_score', rs.m_score,
    'recency_days', rs.recency_days, 'frequency', rs.frequency, 'monetary', rs.monetary,
    'computed_at', rs.computed_at
  ) INTO v_rfm
  FROM rfm_user_score rs WHERE rs.user_id = p_user_id AND rs.merchant_id = v_merchant_id;

  -- Acquisition attribution (write-once columns on the profile)
  SELECT CASE WHEN ua.acquired_at IS NULL AND ua.acquisition_source IS NULL THEN NULL ELSE jsonb_build_object(
    'acquisition_source', ua.acquisition_source,
    'utm_source', ua.acquisition_utm_source,
    'utm_medium', ua.acquisition_utm_medium,
    'utm_campaign', ua.acquisition_utm_campaign,
    'utm_term', ua.acquisition_utm_term,
    'utm_content', ua.acquisition_utm_content,
    'campaign_id', ua.acquisition_campaign_id,
    'campaign_name', mc.name,
    'custom_attribution', ua.acquisition_attribution,
    'acquired_at', ua.acquired_at
  ) END INTO v_acquisition
  FROM user_accounts ua
  LEFT JOIN mkt_campaign mc ON mc.id = ua.acquisition_campaign_id
  WHERE ua.id = p_user_id AND ua.merchant_id = v_merchant_id;

  SELECT COALESCE(jsonb_agg(row_to_json(a)::jsonb ORDER BY a.timestamp DESC), '[]'::jsonb) INTO v_activity_stream
  FROM (
    (SELECT 'purchase' AS event_type, pl.id AS event_id, 'Purchase #' || COALESCE(pl.transaction_number, pl.id::text) AS title, COALESCE(sm.store_name::text, pl.store_code, '') AS description, pl.final_amount AS amount, null::text AS currency_name, pl.transaction_date AS timestamp FROM purchase_ledger pl LEFT JOIN store_master sm ON sm.id = pl.store_id WHERE pl.user_id = p_user_id AND pl.merchant_id = v_merchant_id AND pl.record_type = 'credit' ORDER BY pl.transaction_date DESC LIMIT p_activity_limit)
    UNION ALL
    (SELECT CASE WHEN wl.component = 'reversal'::currency_component THEN 'points_revert' WHEN wl.source_type = 'redemption_cancellation'::wallet_transaction_source_type THEN 'points_revert' WHEN wl.source_type = 'expiry'::wallet_transaction_source_type THEN 'points_expiry' WHEN wl.transaction_type = 'earn' THEN 'points_earn' ELSE 'points_burn' END AS event_type, wl.id AS event_id, CASE WHEN wl.source_type = 'expiry'::wallet_transaction_source_type THEN 'Points expired' WHEN wl.transaction_type = 'earn' THEN '+' || wl.amount || ' points' ELSE '-' || wl.amount || ' points' END AS title, COALESCE(wl.description, wl.source_type::text) AS description, wl.signed_amount::numeric AS amount, 'points' AS currency_name, wl.created_at AS timestamp FROM wallet_ledger wl WHERE wl.user_id = p_user_id AND wl.merchant_id = v_merchant_id AND wl.currency = 'points' ORDER BY wl.created_at DESC LIMIT p_activity_limit)
    UNION ALL
    (SELECT 'redemption' AS event_type, rrl.id AS event_id, rm.name AS title, CASE WHEN rrl.points_deducted > 0 THEN '-' || rrl.points_deducted || ' points' ELSE 'Free redemption' END AS description, rrl.points_deducted AS amount, null AS currency_name, rrl.created_at AS timestamp FROM reward_redemptions_ledger rrl JOIN reward_master rm ON rm.id = rrl.reward_id WHERE rrl.user_id = p_user_id AND rrl.merchant_id = v_merchant_id AND (rrl.source_type = 'reward_redemption' OR (rrl.source_type IS NULL AND COALESCE(rrl.points_deducted, 0) > 0)) AND COALESCE(rrl.cancelled, false) = false ORDER BY rrl.created_at DESC LIMIT p_activity_limit)
    UNION ALL
    (SELECT 'tier_change' AS event_type, tcl.id AS event_id, COALESCE(tcl.change_type::text, '') || ': ' || COALESCE(tt.tier_name, '') AS title, 'From ' || COALESCE(ft.tier_name, 'none') AS description, null AS amount, null AS currency_name, tcl.created_at AS timestamp FROM tier_change_ledger tcl LEFT JOIN tier_master ft ON ft.id = tcl.from_tier_id LEFT JOIN tier_master tt ON tt.id = tcl.to_tier_id WHERE tcl.user_id = p_user_id AND tcl.merchant_id = v_merchant_id ORDER BY tcl.created_at DESC LIMIT p_activity_limit)
    UNION ALL
    (SELECT 'package_assigned' AS event_type, pa.id AS event_id, pkm.name AS title, 'Source: ' || pa.source_type AS description, null AS amount, null AS currency_name, pa.created_at AS timestamp FROM package_assignment pa JOIN package_master pkm ON pkm.id = pa.package_id WHERE pa.user_id = p_user_id AND pa.merchant_id = v_merchant_id ORDER BY pa.created_at DESC LIMIT p_activity_limit)
    UNION ALL
    (SELECT 'referral' AS event_type, rl.id AS event_id, 'Referral: ' || COALESCE(inv_ua.fullname, 'Unknown') AS title, CASE WHEN rl.signed_up_at IS NOT NULL THEN 'Signed up' ELSE 'Invited' END AS description, null AS amount, null AS currency_name, COALESCE(rl.signed_up_at, rl.created_at) AS timestamp FROM referral_ledger rl LEFT JOIN user_accounts inv_ua ON inv_ua.id = rl.invitee_user_id WHERE rl.inviter_user_id = p_user_id AND rl.merchant_id = v_merchant_id ORDER BY COALESCE(rl.signed_up_at, rl.created_at) DESC LIMIT p_activity_limit)
    UNION ALL
    (SELECT 'mission_complete' AS event_type, mlc.id AS event_id, m.mission_name AS title, 'Completion #' || mlc.completion_number AS description, null AS amount, null AS currency_name, mlc.completed_at AS timestamp FROM mission_log_completion mlc JOIN mission m ON m.id = mlc.mission_id WHERE mlc.user_id = p_user_id AND mlc.merchant_id = v_merchant_id ORDER BY mlc.completed_at DESC LIMIT p_activity_limit)
    UNION ALL
    (SELECT 'checkin' AS event_type, cl.id AS event_id, 'Check-in Day ' || cl.streak_day AS title, COALESCE(c.name, '') AS description, COALESCE((SELECT SUM((elem->>'amount')::numeric) FROM jsonb_array_elements(COALESCE(cl.matched_outcomes, '[]'::jsonb)) elem WHERE elem->>'outcome_type' = 'points' AND COALESCE((elem->>'success')::boolean, true) = true), 0) AS amount, 'points' AS currency_name, cl.checkin_timestamp AS timestamp FROM checkin_ledger cl LEFT JOIN checkin c ON c.id = cl.checkin_id WHERE cl.user_id = p_user_id AND cl.merchant_id = v_merchant_id ORDER BY cl.checkin_timestamp DESC LIMIT p_activity_limit)
    UNION ALL
    
    (SELECT 'activity' AS event_type, al.id AS event_id, atm.name AS title,
       NULLIF(concat_ws(' · ',
         CASE WHEN al.utm_source IS NOT NULL THEN 'via ' || al.utm_source END,
         CASE WHEN al.utm_campaign IS NOT NULL THEN 'campaign ' || al.utm_campaign END,
         CASE WHEN mc.name IS NOT NULL THEN 'mkt ' || mc.name END,
         al.properties->>'page_path'), '') AS description,
       null AS amount, null AS currency_name, al.occurred_at AS timestamp
     FROM activity_ledger al
     JOIN activity_type_master atm ON atm.id = al.activity_type_id
     LEFT JOIN mkt_campaign mc ON mc.id = al.mkt_campaign_id
     WHERE al.user_id = p_user_id AND al.merchant_id = v_merchant_id
     ORDER BY al.occurred_at DESC LIMIT p_activity_limit)
    ORDER BY timestamp DESC LIMIT p_activity_limit
  ) a;

  SELECT jsonb_build_object(
    'purchase', (SELECT COUNT(*) FROM purchase_ledger WHERE user_id = p_user_id AND merchant_id = v_merchant_id AND record_type = 'credit'),
    'points', (SELECT COUNT(*) FROM wallet_ledger WHERE user_id = p_user_id AND merchant_id = v_merchant_id AND currency = 'points'),
    'redemption', (SELECT COUNT(*) FROM reward_redemptions_ledger WHERE user_id = p_user_id AND merchant_id = v_merchant_id AND (source_type = 'reward_redemption' OR (source_type IS NULL AND COALESCE(points_deducted, 0) > 0)) AND COALESCE(cancelled, false) = false),
    'tier_change', (SELECT COUNT(*) FROM tier_change_ledger WHERE user_id = p_user_id AND merchant_id = v_merchant_id),
    'package', (SELECT COUNT(*) FROM package_assignment WHERE user_id = p_user_id AND merchant_id = v_merchant_id),
    'referral', (SELECT COUNT(*) FROM referral_ledger WHERE inviter_user_id = p_user_id AND merchant_id = v_merchant_id),
    'mission_complete', (SELECT COUNT(*) FROM mission_log_completion WHERE user_id = p_user_id AND merchant_id = v_merchant_id),
    'checkin', (SELECT COUNT(*) FROM checkin_ledger WHERE user_id = p_user_id AND merchant_id = v_merchant_id),
    'activity', (SELECT COUNT(*) FROM activity_ledger WHERE user_id = p_user_id AND merchant_id = v_merchant_id)
  ) INTO v_activity_counts;

  v_result := jsonb_build_object('success', true, 'data', jsonb_build_object(
    'profile', v_profile, 'removal_info', COALESCE(v_removal_info, null),
    'tier_progress', v_tier_progress, 'tier_history', v_tier_history, 'wallet', v_wallet,
    'points_monthly', v_points_monthly, 'points_by_source', v_points_by_source,
    'redemption_summary', v_redemption_summary, 'redemptions_by_reward', v_redemptions_by_reward, 'redemptions_monthly', v_redemptions_monthly,
    'purchase_summary', v_purchase_summary, 'purchases_monthly', v_purchases_monthly,
    'referral', v_referral, 'checkin', v_checkin,
    'rfm', v_rfm, 'acquisition', v_acquisition,
    'attributed_campaigns', (
      SELECT COALESCE(jsonb_agg(jsonb_build_object(
        'purchase_id', a.purchase_id,
        'transaction_date', pl.transaction_date,
        'attributed_amount', a.attributed_amount,
        'campaign_id', a.campaign_id,
        'campaign_name', mc.name,
        'model', a.model
      ) ORDER BY pl.transaction_date DESC), '[]'::jsonb)
      FROM mkt_purchase_attribution a
      JOIN purchase_ledger pl ON pl.id = a.purchase_id
      LEFT JOIN mkt_campaign mc ON mc.id = a.campaign_id
      WHERE a.user_id = p_user_id AND a.merchant_id = v_merchant_id
        AND pl.transaction_date >= v_cutoff
      LIMIT 20
    ),
    'funnel_stage', (
      SELECT jsonb_build_object(
        'funnel_id', f.id,
        'funnel_name', f.name,
        'stage_audience_id', a.id,
        'stage_name', a.name,
        'sort_order', a.funnel_sort_order
      )
      FROM amp_audience_member am
      JOIN amp_audience_master a ON a.id = am.audience_id AND a.funnel_id IS NOT NULL
      JOIN funnel_master f ON f.id = a.funnel_id AND f.merchant_id = v_merchant_id
      WHERE am.user_id = p_user_id AND am.exited_at IS NULL
      ORDER BY a.funnel_sort_order DESC
      LIMIT 1
    ),
    'activity_stream', v_activity_stream, 'activity_counts', v_activity_counts
  ));

  RETURN v_result;
END;
$function$;

CREATE OR REPLACE FUNCTION public.fn_wallet_today_stats(p_user_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_merchant_id uuid;
  v_ctx_merchant uuid;
  v_tz text;
  v_local_date date;
  v_start timestamptz;
  v_end timestamptz;
  v_earned numeric := 0;
  v_used numeric := 0;
  v_balance integer := 0;
BEGIN
  SELECT ua.merchant_id
  INTO v_merchant_id
  FROM user_accounts ua
  WHERE ua.id = p_user_id
    AND ua.deleted_at IS NULL;

  IF v_merchant_id IS NULL THEN
    RETURN jsonb_build_object(
      'points_balance', 0,
      'today_earned', 0,
      'today_used', 0
    );
  END IF;

  v_ctx_merchant := get_current_merchant_id();
  IF v_ctx_merchant IS NOT NULL AND v_ctx_merchant IS DISTINCT FROM v_merchant_id THEN
    RETURN jsonb_build_object(
      'points_balance', 0,
      'today_earned', 0,
      'today_used', 0
    );
  END IF;

  v_tz := fn_mission_merchant_tz(v_merchant_id);
  v_local_date := (timezone(v_tz, now()))::date;
  v_start := v_local_date::timestamp AT TIME ZONE v_tz;
  v_end := (v_local_date + 1)::timestamp AT TIME ZONE v_tz;

  SELECT COALESCE(uw.points_balance, 0)
  INTO v_balance
  FROM user_wallet uw
  WHERE uw.user_id = p_user_id
    AND uw.merchant_id = v_merchant_id;

  SELECT
    GREATEST(0, COALESCE(SUM(wl.earned_delta), 0)),
    GREATEST(0, COALESCE(SUM(wl.used_delta), 0))
  INTO v_earned, v_used
  FROM v_wallet_ledger_flow wl
  WHERE wl.user_id = p_user_id
    AND wl.merchant_id = v_merchant_id
    AND wl.currency = 'points'
    AND wl.created_at >= v_start
    AND wl.created_at < v_end;

  RETURN jsonb_build_object(
    'points_balance', COALESCE(v_balance, 0),
    'today_earned', COALESCE(v_earned, 0),
    'today_used', COALESCE(v_used, 0)
  );
END;
$function$;
