-- Shared points expiry read engine: buckets + envelope, BFF wiring.

-- ---------------------------------------------------------------------------
-- Display gate (custom mode OR merchant expiry active)
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.fn_loyalty_expiry_display_enabled(p_merchant_id uuid)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path TO 'public'
AS $$
  SELECT COALESCE(mm.points_expiry_active, false)
      OR public.fn_loyalty_is_custom_expiry(p_merchant_id)
  FROM public.merchant_master mm
  WHERE mm.id = p_merchant_id;
$$;

-- ---------------------------------------------------------------------------
-- Unified expiry buckets: custom cache or standard ledger lots
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.fn_loyalty_expiry_buckets_for_user(
  p_user_id uuid,
  p_merchant_id uuid,
  p_as_of_date date DEFAULT (timezone('Asia/Bangkok', now()))::date
)
RETURNS TABLE(expiry_date date, amount numeric)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
BEGIN
  IF public.fn_loyalty_is_custom_expiry(p_merchant_id) THEN
    RETURN QUERY
    SELECT c.expiry_date, c.amount::numeric
    FROM public.user_points_expiry_cache c
    WHERE c.merchant_id = p_merchant_id
      AND c.user_id = p_user_id
      AND c.expiry_date > p_as_of_date
      AND c.amount > 0;
  ELSE
    RETURN QUERY
    SELECT wl.expiry_date,
           SUM(GREATEST(wl.deductible_balance, 0))::numeric AS amount
    FROM public.wallet_ledger wl
    WHERE wl.merchant_id = p_merchant_id
      AND wl.user_id = p_user_id
      AND wl.currency = 'points'
      AND wl.transaction_type = 'earn'
      AND wl.expiry_date IS NOT NULL
      AND wl.expiry_date > p_as_of_date
      AND wl.deductible_balance > 0
    GROUP BY wl.expiry_date
    HAVING SUM(GREATEST(wl.deductible_balance, 0)) > 0;
  END IF;
END;
$function$;

-- ---------------------------------------------------------------------------
-- Fast calc envelope (single bucket read)
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.fn_loyalty_expiry_envelope(
  p_user_id uuid,
  p_merchant_id uuid,
  p_as_of_date date DEFAULT (timezone('Asia/Bangkok', now()))::date
)
RETURNS jsonb
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path TO 'public'
AS $$
  WITH b AS (
    SELECT expiry_date, amount
    FROM public.fn_loyalty_expiry_buckets_for_user(p_user_id, p_merchant_id, p_as_of_date)
  ),
  next_row AS (
    SELECT expiry_date, SUM(amount) AS amount
    FROM b
    GROUP BY expiry_date
    ORDER BY expiry_date
    LIMIT 1
  ),
  month_rows AS (
    SELECT
      date_trunc('month', expiry_date)::date AS month_start,
      SUM(amount) AS amount
    FROM b
    GROUP BY 1
  )
  SELECT jsonb_build_object(
    'next',
    COALESCE(
      (
        SELECT jsonb_build_object(
          'expiry_date', nr.expiry_date,
          'amount', nr.amount
        )
        FROM next_row nr
      ),
      jsonb_build_object('expiry_date', NULL, 'amount', 0)
    ),
    'within_30_days',
    jsonb_build_object(
      'amount',
      COALESCE(
        (
          SELECT SUM(b2.amount)
          FROM b b2
          WHERE b2.expiry_date > p_as_of_date
            AND b2.expiry_date <= p_as_of_date + 30
        ),
        0
      )
    ),
    'calendar_month',
    jsonb_build_object(
      'amount',
      COALESCE(
        (
          SELECT SUM(b2.amount)
          FROM b b2
          WHERE b2.expiry_date >= date_trunc('month', p_as_of_date)::date
            AND b2.expiry_date <= (
              date_trunc('month', p_as_of_date) + interval '1 month' - interval '1 day'
            )::date
        ),
        0
      )
    ),
    'calendar_year',
    jsonb_build_object(
      'amount',
      COALESCE(
        (
          SELECT SUM(b2.amount)
          FROM b b2
          WHERE b2.expiry_date >= make_date(EXTRACT(year FROM p_as_of_date)::int, 1, 1)
            AND b2.expiry_date <= make_date(EXTRACT(year FROM p_as_of_date)::int, 12, 31)
        ),
        0
      )
    ),
    'months',
    COALESCE(
      (
        SELECT jsonb_agg(
          jsonb_build_object(
            'month', to_char(mr.month_start, 'YYYY-MM-01'),
            'amount', mr.amount
          )
          ORDER BY mr.month_start
        )
        FROM month_rows mr
      ),
      '[]'::jsonb
    )
  );
$$;

-- ---------------------------------------------------------------------------
-- Back-compat helpers
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.fn_loyalty_next_expiry_for_user(
  p_user_id uuid,
  p_merchant_id uuid,
  p_today date DEFAULT (timezone('Asia/Bangkok', now()))::date
)
RETURNS TABLE(next_expiry_date date, amount numeric)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path TO 'public'
AS $$
  SELECT
    (e.expiry ->> 'expiry_date')::date,
    COALESCE((e.expiry ->> 'amount')::numeric, 0)
  FROM (
    SELECT public.fn_loyalty_expiry_envelope(p_user_id, p_merchant_id, p_today) -> 'next' AS expiry
  ) e
  WHERE (e.expiry ->> 'expiry_date') IS NOT NULL;
$$;

CREATE OR REPLACE FUNCTION public.fn_loyalty_points_expiry_months_for_user(
  p_user_id uuid,
  p_merchant_id uuid,
  p_today date DEFAULT (timezone('Asia/Bangkok', now()))::date
)
RETURNS jsonb
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path TO 'public'
AS $$
  SELECT COALESCE(
    public.fn_loyalty_expiry_envelope(p_user_id, p_merchant_id, p_today) -> 'months',
    '[]'::jsonb
  );
$$;

-- ---------------------------------------------------------------------------
-- Wallet overlay for admin member 360
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.fn_loyalty_wallet_expiry_overlay(
  p_user_id uuid,
  p_merchant_id uuid,
  p_wallet jsonb,
  p_as_of_date date DEFAULT (timezone('Asia/Bangkok', now()))::date
)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_exp jsonb;
BEGIN
  IF NOT public.fn_loyalty_expiry_display_enabled(p_merchant_id) THEN
    RETURN p_wallet;
  END IF;

  v_exp := public.fn_loyalty_expiry_envelope(p_user_id, p_merchant_id, p_as_of_date);

  RETURN COALESCE(p_wallet, '{}'::jsonb) || jsonb_build_object(
    'expiring_soon_amount',
    COALESCE((v_exp -> 'within_30_days' ->> 'amount')::numeric, 0),
    'expiring_soon_date',
    NULLIF(v_exp -> 'next' ->> 'expiry_date', '')::date,
    'points_expiry',
    v_exp
  );
END;
$function$;

-- ---------------------------------------------------------------------------
-- Member: get_user_summary
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.get_user_summary()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
    v_auth_user_id uuid;
    v_user_id uuid;
    v_merchant_id uuid;
    v_current_tier_id uuid;
    v_current_position integer;
    v_user_type user_type;
    v_persona_id uuid;
    v_cfg record;
    v_next_tier_id uuid;
    v_next_tier_name text;
    v_upgrade_metric text;
    v_upgrade_threshold numeric;
    v_upgrade_window_months smallint;
    v_upgrade_progress_percent numeric;
    v_upgrade_progress numeric;
    v_points_expiry_active boolean;
    v_next_expiry_date date;
    v_points_expiring_on_next_date numeric;
    v_points_expiry_amount numeric;
    v_points_expiry jsonb;
    v_as_of_date date := (timezone('Asia/Bangkok', now()))::date;
    v_maintain_metric text;
    v_ticket_type_id uuid;
    v_ticket_type_name text;
    v_result jsonb;
BEGIN
    v_auth_user_id := auth.uid();

    IF v_auth_user_id IS NULL THEN
        RETURN jsonb_build_object('error', 'Not authenticated');
    END IF;

    SELECT ua.id, ua.merchant_id, ua.tier_id, ua.user_type, ua.persona_id
    INTO v_user_id, v_merchant_id, v_current_tier_id, v_user_type, v_persona_id
    FROM user_accounts ua
    WHERE ua.auth_user_id = v_auth_user_id;

    IF v_user_id IS NULL THEN
        RETURN jsonb_build_object('error', 'User account not found');
    END IF;

    SELECT mm.points_expiry_active INTO v_points_expiry_active
    FROM merchant_master mm
    WHERE mm.id = v_merchant_id;

    SELECT * INTO v_cfg
    FROM tier_program_config
    WHERE merchant_id = v_merchant_id AND user_type = v_user_type;

    IF FOUND THEN
        v_upgrade_metric := v_cfg.metric::text;
        v_upgrade_window_months := CASE
            WHEN v_cfg.period_type = 'rolling' THEN v_cfg.rolling_months
            ELSE 12::smallint
        END;
    END IF;

    SELECT max(l.ladder_position) FILTER (WHERE l.tier_id = v_current_tier_id)
    INTO v_current_position
    FROM fn_tier_ladder_for_user(v_user_id, v_merchant_id) l;

    SELECT l.tier_id, l.upgrade_amount, tmx.tier_name
    INTO v_next_tier_id, v_upgrade_threshold, v_next_tier_name
    FROM fn_tier_ladder_for_user(v_user_id, v_merchant_id) l
    JOIN tier_master tmx ON tmx.id = l.tier_id
    WHERE l.ladder_position > COALESCE(v_current_position, 0)
    ORDER BY l.ladder_position ASC
    LIMIT 1;

    SELECT tp.upgrade_progress_percent, tp.maintain_metric_needed::text
    INTO v_upgrade_progress_percent, v_maintain_metric
    FROM tier_progress tp
    WHERE tp.user_id = v_user_id
      AND tp.merchant_id = v_merchant_id
      AND tp.next_tier_id IS NOT DISTINCT FROM v_next_tier_id;

    IF v_maintain_metric IS NULL THEN
        SELECT tp.maintain_metric_needed::text
        INTO v_maintain_metric
        FROM tier_progress tp
        WHERE tp.user_id = v_user_id
          AND tp.merchant_id = v_merchant_id;
    END IF;

    IF v_next_tier_id IS NOT NULL AND v_upgrade_progress_percent IS NULL THEN
        v_upgrade_progress_percent := 0;
    END IF;

    IF v_upgrade_threshold IS NOT NULL AND v_upgrade_progress_percent IS NOT NULL THEN
        v_upgrade_progress := ROUND(v_upgrade_threshold * v_upgrade_progress_percent / 100);
    END IF;

    IF v_upgrade_metric = 'ticket' OR v_maintain_metric = 'ticket' THEN
        SELECT tt.id, tt.name
        INTO v_ticket_type_id, v_ticket_type_name
        FROM ticket_type tt
        WHERE tt.merchant_id = v_merchant_id
          AND tt.active = true
          AND tt.is_credit = false
        ORDER BY tt.created_at ASC, tt.name ASC
        LIMIT 1;
    END IF;

    IF public.fn_loyalty_expiry_display_enabled(v_merchant_id) THEN
        v_points_expiry := public.fn_loyalty_expiry_envelope(v_user_id, v_merchant_id, v_as_of_date);
        v_next_expiry_date := NULLIF(v_points_expiry -> 'next' ->> 'expiry_date', '')::date;
        v_points_expiring_on_next_date := COALESCE((v_points_expiry -> 'next' ->> 'amount')::numeric, 0);
        v_points_expiry_amount := COALESCE((v_points_expiry -> 'within_30_days' ->> 'amount')::numeric, 0);
    END IF;

    SELECT jsonb_build_object(
        'id', ua.id,
        'user_id', ua.id,
        'mongo_id', ua.mongo_id,
        'member_code', ua.member_code,
        'fullname', ua.fullname,
        'firstname', ua.firstname,
        'lastname', ua.lastname,
        'email', ua.email,
        'tel', ua.tel,
        'line_id', ua.line_id,
        'image', ua.image,
        'birth_date', ua.birth_date,
        'is_freeze', COALESCE(ua.is_freeze, false),
        'profile_complete', true,
        'persona_id', pm.id,
        'persona_name', pm.persona_name,
        'persona_icon', pm.image,
        'tier_id', tm.id,
        'tier_name', tm.tier_name,
        'tier_icon', tm.icon,
        'tier_color', tm.color,
        'next_tier_id', v_next_tier_id,
        'next_tier_name', v_next_tier_name,
        'points_balance', COALESCE(uw.points_balance, 0),
        'points_expiry_date', v_next_expiry_date,
        'points_expiring_on_next_date', v_points_expiring_on_next_date,
        'points_expiry_amount', v_points_expiry_amount,
        'points_expiry', v_points_expiry,
        'upgrade_metric', v_upgrade_metric,
        'upgrade_metric_label', CASE WHEN v_upgrade_metric = 'ticket' THEN v_ticket_type_name ELSE NULL END,
        'upgrade_ticket_type_id', CASE WHEN v_upgrade_metric = 'ticket' THEN v_ticket_type_id ELSE NULL END,
        'upgrade_progress', v_upgrade_progress,
        'upgrade_progress_percent', v_upgrade_progress_percent,
        'upgrade_threshold', v_upgrade_threshold,
        'upgrade_window_months', v_upgrade_window_months,
        'upgrade_deadline', tp.upgrade_deadline,
        'amount_to_next_tier', CASE
            WHEN v_upgrade_threshold IS NOT NULL AND v_upgrade_progress_percent IS NOT NULL
            THEN GREATEST(0, ROUND(v_upgrade_threshold - (v_upgrade_threshold * v_upgrade_progress_percent / 100)))
            ELSE v_upgrade_threshold
        END,
        'maintain_metric', tp.maintain_metric_needed,
        'maintain_metric_label', CASE WHEN tp.maintain_metric_needed::text = 'ticket' THEN v_ticket_type_name ELSE NULL END,
        'maintain_ticket_type_id', CASE WHEN tp.maintain_metric_needed::text = 'ticket' THEN v_ticket_type_id ELSE NULL END,
        'maintain_progress', tp.maintain_progress,
        'maintain_deadline', tp.maintain_deadline,
        'unredeemed_rewards_count', (
            SELECT COUNT(*)::int
            FROM reward_redemptions_ledger rrl
            WHERE rrl.user_id = v_user_id
              AND rrl.merchant_id = v_merchant_id
              AND rrl.redeemed_status = true
              AND rrl.used_status = false
              AND COALESCE(rrl.cancelled, false) = false
        )
    ) INTO v_result
    FROM user_accounts ua
    LEFT JOIN persona_master pm ON pm.id = ua.persona_id
    LEFT JOIN tier_master tm ON tm.id = ua.tier_id
    LEFT JOIN tier_progress tp ON tp.user_id = ua.id AND tp.merchant_id = ua.merchant_id
    LEFT JOIN user_wallet uw ON uw.user_id = ua.id AND uw.merchant_id = ua.merchant_id
    WHERE ua.id = v_user_id;

    RETURN COALESCE(v_result, jsonb_build_object('error', 'Failed to build summary'));
END;
$function$;

-- ---------------------------------------------------------------------------
-- Member: points expiry schedule BFF
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.bff_get_points_expiry_schedule()
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_merchant_id uuid;
  v_user_id uuid;
  v_exp jsonb;
  v_as_of_date date := (timezone('Asia/Bangkok', now()))::date;
BEGIN
  v_merchant_id := get_current_merchant_id();
  IF v_merchant_id IS NULL THEN
    RETURN fn_response_error('No merchant context', NULL, NULL);
  END IF;

  SELECT ua.id INTO v_user_id
  FROM user_accounts ua
  WHERE ua.merchant_id = v_merchant_id
    AND (ua.auth_user_id = auth.uid() OR ua.id = auth.uid())
  LIMIT 1;
  IF v_user_id IS NULL THEN
    RETURN fn_response_error('User account not found', NULL, NULL);
  END IF;

  IF NOT public.fn_loyalty_expiry_display_enabled(v_merchant_id) THEN
    RETURN fn_response_success(
      NULL,
      NULL,
      jsonb_build_object('months', '[]'::jsonb, 'expiry', NULL)
    );
  END IF;

  v_exp := public.fn_loyalty_expiry_envelope(v_user_id, v_merchant_id, v_as_of_date);

  RETURN fn_response_success(
    NULL,
    NULL,
    jsonb_build_object(
      'months', COALESCE(v_exp -> 'months', '[]'::jsonb),
      'expiry', v_exp
    )
  );
END;
$function$;

-- ---------------------------------------------------------------------------
-- Admin: customer 360 wrapper — overlay wallet expiry from shared engine
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.bff_admin_get_member_360(
  p_user_id uuid,
  p_months integer DEFAULT 12,
  p_activity_limit integer DEFAULT 50
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_result jsonb;
  v_merchant_id uuid;
  v_lock boolean;
  v_until timestamptz;
  v_wallet jsonb;
BEGIN
  v_result := public.bff_admin_get_member_360_base(p_user_id, p_months, p_activity_limit);
  IF COALESCE((v_result->>'success')::boolean, false) IS DISTINCT FROM true THEN
    RETURN v_result;
  END IF;

  v_merchant_id := get_current_merchant_id();
  IF v_merchant_id IS NULL THEN
    RETURN v_result;
  END IF;

  v_wallet := public.fn_loyalty_wallet_expiry_overlay(
    p_user_id,
    v_merchant_id,
    v_result #> '{data,wallet}'
  );
  v_result := jsonb_set(v_result, '{data,wallet}', v_wallet, true);

  v_result := jsonb_set(
    v_result,
    '{data,notes}',
    COALESCE(public.fn_admin_list_user_notes(p_user_id, v_merchant_id, 50), '[]'::jsonb),
    true
  );

  SELECT ua.tier_lock_downgrade, ua.tier_locked_downgrade_until
  INTO v_lock, v_until
  FROM public.user_accounts ua
  WHERE ua.id = p_user_id AND ua.merchant_id = v_merchant_id;

  IF FOUND THEN
    v_result := jsonb_set(
      v_result,
      '{data,profile,tier_lock_downgrade}',
      to_jsonb(COALESCE(v_lock, false)),
      true
    );
    v_result := jsonb_set(
      v_result,
      '{data,profile,tier_locked_downgrade_until}',
      COALESCE(to_jsonb(v_until), 'null'::jsonb),
      true
    );
  END IF;

  RETURN v_result;
END;
$function$;

-- ---------------------------------------------------------------------------
-- Admin: front line member
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.bff_admin_get_frontline_member(
  p_user_id uuid,
  p_language text DEFAULT NULL::text
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_merchant_id uuid;
  v_language text;
  v_wallet jsonb;
  v_tier_progress jsonb;
  v_pending_tier_id uuid;
  v_pending_tier_name text;
  v_profile jsonb;
  v_notes jsonb;
  v_incomplete boolean := false;
  v_persona_id uuid;
  v_exp jsonb;
  v_as_of_date date := (timezone('Asia/Bangkok', now()))::date;
  v_points_expiring_date date;
  v_points_expiring_amount numeric := 0;
BEGIN
  v_merchant_id := get_current_merchant_id();
  IF v_merchant_id IS NULL THEN
    RETURN fn_response_error('Unauthorized', 'Merchant context required');
  END IF;

  IF NOT (
    check_admin_permission('front_line', 'read')
    OR check_admin_permission('customer-360', 'read')
  ) THEN
    RETURN fn_response_error(
      'Permission denied',
      'front_line.read or customer-360.read required'
    );
  END IF;

  v_language := fn_normalize_ui_language(p_language);

  IF NOT EXISTS (
    SELECT 1
    FROM user_accounts ua
    WHERE ua.id = p_user_id
      AND ua.merchant_id = v_merchant_id
      AND ua.deleted_at IS NULL
  ) THEN
    RETURN fn_response_error('Not found', 'Member not found');
  END IF;

  SELECT jsonb_build_object(
    'user_id', ua.id,
    'fullname', ua.fullname,
    'firstname', ua.firstname,
    'lastname', ua.lastname,
    'email', ua.email,
    'tel', ua.tel,
    'line_id', ua.line_id,
    'image', ua.image,
    'birth_date', ua.birth_date,
    'nationality', NULL,
    'user_type', ua.user_type::text,
    'created_at', ua.created_at,
    'tier_name', COALESCE(tt.translated_value, tm.tier_name),
    'tier_color', tm.color,
    'tier_icon', tm.icon,
    'persona_id', ua.persona_id,
    'persona_name', COALESCE(pt.translated_value, pm.persona_name, pgm.group_name),
    'external_id', ua.external_user_id,
    'member_code', ua.member_code,
    'is_freeze', COALESCE(ua.is_freeze, false),
    'tags', COALESCE((
      SELECT jsonb_agg(jsonb_build_object('id', tg.id, 'tag_name', tg.tag_name))
      FROM user_tags ut
      JOIN tag_master tg ON tg.id = ut.tag_id AND tg.merchant_id = ua.merchant_id
      WHERE ut.user_id = ua.id
    ), '[]'::jsonb)
  ),
  ua.persona_id
  INTO v_profile, v_persona_id
  FROM user_accounts ua
  LEFT JOIN tier_master tm
    ON tm.id = ua.tier_id AND tm.merchant_id = ua.merchant_id
  LEFT JOIN translations tt
    ON tt.entity_type = 'tier'
   AND tt.entity_id = tm.id
   AND tt.language_code = v_language
   AND tt.field_name = 'tier_name'
  LEFT JOIN persona_master pm
    ON pm.id = ua.persona_id AND pm.merchant_id = ua.merchant_id
  LEFT JOIN translations pt
    ON pt.entity_type = 'persona'
   AND pt.entity_id = pm.id
   AND pt.language_code = v_language
   AND pt.field_name = 'persona_name'
  LEFT JOIN persona_group_master pgm
    ON pgm.id = COALESCE(pm.group_id, ua.persona_id)
   AND pgm.merchant_id = ua.merchant_id
  WHERE ua.id = p_user_id
    AND ua.merchant_id = v_merchant_id;

  v_wallet := fn_wallet_today_stats(p_user_id);
  v_tier_progress := fn_admin_get_tier_progress_enriched(p_user_id, v_merchant_id);
  v_notes := fn_admin_list_user_notes(p_user_id, v_merchant_id, 20);

  IF public.fn_loyalty_expiry_display_enabled(v_merchant_id) THEN
    v_exp := public.fn_loyalty_expiry_envelope(p_user_id, v_merchant_id, v_as_of_date);
    v_points_expiring_date := NULLIF(v_exp -> 'next' ->> 'expiry_date', '')::date;
    v_points_expiring_amount := COALESCE((v_exp -> 'next' ->> 'amount')::numeric, 0);
  END IF;

  SELECT tpu.to_tier_id, COALESCE(tt.translated_value, tm.tier_name)
  INTO v_pending_tier_id, v_pending_tier_name
  FROM tier_pending_upgrades tpu
  JOIN tier_master tm
    ON tm.id = tpu.to_tier_id AND tm.merchant_id = v_merchant_id
  LEFT JOIN translations tt
    ON tt.entity_type = 'tier'
   AND tt.entity_id = tm.id
   AND tt.language_code = v_language
   AND tt.field_name = 'tier_name'
  WHERE tpu.user_id = p_user_id
    AND tpu.merchant_id = v_merchant_id
  ORDER BY tpu.effective_at ASC
  LIMIT 1;

  IF v_pending_tier_id IS NOT NULL THEN
    v_tier_progress := COALESCE(v_tier_progress, '{}'::jsonb) || jsonb_build_object(
      'next_tier_id', v_pending_tier_id,
      'next_tier_name', v_pending_tier_name,
      'upgrade_progress_percent', 100,
      'amount_to_next_tier', 0,
      'is_upgrade_pending', true
    );
  ELSE
    v_tier_progress := COALESCE(v_tier_progress, '{}'::jsonb) || jsonb_build_object(
      'is_upgrade_pending', false
    );
  END IF;

  SELECT EXISTS (
    SELECT 1
    FROM user_field_config ufc
    JOIN user_accounts ua
      ON ua.id = p_user_id AND ua.merchant_id = ufc.merchant_id
    WHERE ufc.merchant_id = v_merchant_id
      AND COALESCE(ufc.active_status, true)
      AND COALESCE(ufc.is_required, false)
      AND (
        ufc.persona_ids IS NULL
        OR cardinality(ufc.persona_ids) = 0
        OR ua.persona_id = ANY (ufc.persona_ids)
      )
      AND NULLIF(btrim(
        CASE ufc.field_key
          WHEN 'firstname' THEN ua.firstname
          WHEN 'lastname' THEN ua.lastname
          WHEN 'fullname' THEN ua.fullname
          WHEN 'phone' THEN ua.tel
          WHEN 'tel' THEN ua.tel
          WHEN 'email' THEN ua.email
          WHEN 'birth_date' THEN ua.birth_date::text
          WHEN 'gender' THEN ua.gender
          WHEN 'id_card' THEN ua.id_card
          WHEN 'line_id' THEN ua.line_id
          WHEN 'external_user_id' THEN ua.external_user_id
          WHEN 'image' THEN ua.image
          ELSE 'x'
        END
      ), '') IS NULL
  )
  INTO v_incomplete;

  RETURN fn_response_success(
    'OK',
    NULL,
    jsonb_build_object(
      'profile', v_profile,
      'notes', COALESCE(v_notes, '[]'::jsonb),
      'points_balance', COALESCE((v_wallet->>'points_balance')::numeric, 0),
      'today_earned', COALESCE((v_wallet->>'today_earned')::numeric, 0),
      'today_used', COALESCE((v_wallet->>'today_used')::numeric, 0),
      'tier_progress', v_tier_progress,
      'points_expiring_date', v_points_expiring_date,
      'points_expiring_amount', v_points_expiring_amount,
      'points_expiry', v_exp,
      'profile_incomplete', COALESCE(v_incomplete, false)
    )
  );
END;
$function$;
