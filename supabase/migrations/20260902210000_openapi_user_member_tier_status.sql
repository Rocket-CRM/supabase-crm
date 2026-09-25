-- Open API: member_status + cache-backed tier block on GET /api-users.
-- Progress reads tier_progress only (no evaluate / on-demand refresh).

-- ---------------------------------------------------------------------------
-- Shared cache reader (admin + Open API).
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.fn_get_tier_progress_from_cache(
  p_user_id uuid,
  p_merchant_id uuid
)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_tp record;
  v_upgrade_metric text;
  v_progress numeric;
  v_amount_to_next numeric;
  v_percent numeric;
BEGIN
  SELECT tpc.metric::text
  INTO v_upgrade_metric
  FROM public.user_accounts ua
  LEFT JOIN public.tier_program_config tpc
    ON tpc.merchant_id = ua.merchant_id
   AND tpc.user_type = ua.user_type
  WHERE ua.id = p_user_id
    AND ua.merchant_id = p_merchant_id;

  SELECT
    tp.current_tier_id,
    tp.next_tier_id,
    tp.upgrade_metric_needed,
    tp.upgrade_progress_percent,
    tp.upgrade_deadline,
    tp.maintain_progress,
    tp.maintain_metric_needed,
    tp.maintain_deadline,
    tp.upgrade_metric_current,
    tp.upgrade_threshold,
    ct.tier_name AS current_tier_name,
    ct.icon AS current_tier_icon,
    ct.color AS current_tier_color,
    nt.tier_name AS next_tier_name
  INTO v_tp
  FROM public.tier_progress tp
  LEFT JOIN public.tier_master ct
    ON ct.id = COALESCE(
      tp.current_tier_id,
      (SELECT ua.tier_id FROM public.user_accounts ua WHERE ua.id = p_user_id AND ua.merchant_id = p_merchant_id)
    )
  LEFT JOIN public.tier_master nt ON nt.id = tp.next_tier_id
  WHERE tp.user_id = p_user_id
    AND tp.merchant_id = p_merchant_id;

  IF NOT FOUND THEN
    RETURN '{}'::jsonb;
  END IF;

  v_percent := v_tp.upgrade_progress_percent;
  IF v_tp.next_tier_id IS NOT NULL AND v_percent IS NULL THEN
    v_percent := 0;
  END IF;

  v_progress := v_tp.upgrade_metric_current;
  IF v_progress IS NULL
     AND v_tp.upgrade_threshold IS NOT NULL
     AND v_percent IS NOT NULL THEN
    v_progress := ROUND(v_tp.upgrade_threshold * v_percent / 100.0);
  END IF;

  IF v_tp.upgrade_threshold IS NOT NULL THEN
    v_amount_to_next := GREATEST(
      0,
      v_tp.upgrade_threshold - COALESCE(v_progress, 0)
    );
  END IF;

  RETURN jsonb_build_object(
    'current_tier_id', COALESCE(
      v_tp.current_tier_id,
      (SELECT ua.tier_id FROM public.user_accounts ua WHERE ua.id = p_user_id AND ua.merchant_id = p_merchant_id)
    ),
    'current_tier_name', v_tp.current_tier_name,
    'current_tier_icon', v_tp.current_tier_icon,
    'current_tier_color', v_tp.current_tier_color,
    'next_tier_id', v_tp.next_tier_id,
    'next_tier_name', v_tp.next_tier_name,
    'upgrade_progress_percent', v_percent,
    'upgrade_metric_needed', COALESCE(v_tp.upgrade_metric_needed::text, v_upgrade_metric),
    'upgrade_deadline', v_tp.upgrade_deadline,
    'maintain_progress', v_tp.maintain_progress,
    'maintain_metric_needed', v_tp.maintain_metric_needed,
    'maintain_deadline', v_tp.maintain_deadline,
    'upgrade_metric', v_upgrade_metric,
    'upgrade_threshold', v_tp.upgrade_threshold,
    'upgrade_progress', v_progress,
    'amount_to_next_tier', v_amount_to_next
  );
END;
$function$;

CREATE OR REPLACE FUNCTION public.fn_admin_get_tier_progress_enriched(
  p_user_id uuid,
  p_merchant_id uuid
)
RETURNS jsonb
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
  SELECT public.fn_get_tier_progress_from_cache(p_user_id, p_merchant_id);
$function$;

-- ---------------------------------------------------------------------------
-- Open API helpers.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.fn_open_api_member_status(
  p_is_freeze boolean,
  p_is_active boolean
)
RETURNS text
LANGUAGE sql
IMMUTABLE
AS $function$
  SELECT CASE
    WHEN COALESCE(p_is_freeze, false) THEN 'suspended'
    WHEN p_is_active = false THEN 'inactive'
    ELSE 'active'
  END;
$function$;

CREATE OR REPLACE FUNCTION public.fn_open_api_user_tier_block(
  p_user_id uuid,
  p_merchant_id uuid
)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_tier_id uuid;
  v_tier_name text;
  v_user_type public.user_type;
  v_program_metric text;
  v_cache jsonb;
  v_effective_at timestamptz;
  v_threshold_metric text;
  v_threshold_amount numeric;
  v_progress jsonb;
  v_progress_metric text;
BEGIN
  SELECT ua.tier_id, tm.tier_name, ua.user_type
  INTO v_tier_id, v_tier_name, v_user_type
  FROM public.user_accounts ua
  LEFT JOIN public.tier_master tm ON tm.id = ua.tier_id
  WHERE ua.id = p_user_id
    AND ua.merchant_id = p_merchant_id;

  IF v_tier_id IS NULL THEN
    RETURN NULL;
  END IF;

  SELECT tpc.metric::text
  INTO v_program_metric
  FROM public.tier_program_config tpc
  WHERE tpc.merchant_id = p_merchant_id
    AND tpc.user_type = v_user_type;

  SELECT tet.tier_achieved_at
  INTO v_effective_at
  FROM public.tier_evaluation_tracking tet
  WHERE tet.user_id = p_user_id
    AND tet.merchant_id = p_merchant_id;

  SELECT tc.metric::text, tc.amount
  INTO v_threshold_metric, v_threshold_amount
  FROM public.tier_conditions tc
  WHERE tc.tier_id = v_tier_id
    AND tc.merchant_id = p_merchant_id
    AND tc.condition_type = 'upgrade'
    AND COALESCE(tc.active_status, true) = true
  ORDER BY tc.amount DESC NULLS LAST
  LIMIT 1;

  v_cache := public.fn_get_tier_progress_from_cache(p_user_id, p_merchant_id);

  IF v_cache <> '{}'::jsonb AND v_cache ? 'next_tier_id' AND v_cache->>'next_tier_id' IS NOT NULL THEN
    v_progress_metric := COALESCE(
      v_cache->>'upgrade_metric_needed',
      v_cache->>'upgrade_metric',
      v_threshold_metric,
      v_program_metric
    );

    v_progress := jsonb_strip_nulls(jsonb_build_object(
      'metric', v_progress_metric,
      'current_amount', NULLIF(v_cache->>'upgrade_progress', '')::numeric,
      'percent', NULLIF(v_cache->>'upgrade_progress_percent', '')::numeric,
      'next_tier_id', v_cache->'next_tier_id',
      'next_tier_name', v_cache->>'next_tier_name',
      'next_tier_threshold_amount', NULLIF(v_cache->>'upgrade_threshold', '')::numeric
    ));
  END IF;

  RETURN jsonb_strip_nulls(jsonb_build_object(
    'tier_id', v_tier_id,
    'tier_code', v_tier_id,
    'tier_name', COALESCE(v_cache->>'current_tier_name', v_tier_name),
    'effective_at', v_effective_at,
    'current_tier_threshold', CASE
      WHEN v_threshold_amount IS NOT NULL THEN jsonb_build_object(
        'metric', COALESCE(v_threshold_metric, v_program_metric),
        'amount', v_threshold_amount
      )
      ELSE NULL
    END,
    'progress', v_progress
  ));
END;
$function$;

-- ---------------------------------------------------------------------------
-- Extend api_get_user (additive; include_tier=false preserves legacy shape).
-- ---------------------------------------------------------------------------
DROP FUNCTION IF EXISTS public.api_get_user(uuid, uuid, text, text, text, text);

CREATE OR REPLACE FUNCTION public.api_get_user(
  p_merchant_id uuid,
  p_user_id uuid DEFAULT NULL::uuid,
  p_external_user_id text DEFAULT NULL::text,
  p_email text DEFAULT NULL::text,
  p_tel text DEFAULT NULL::text,
  p_line_id text DEFAULT NULL::text,
  p_include_tier boolean DEFAULT true
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
    v_user_id UUID;
    v_user RECORD;
    v_addresses JSONB;
    v_latest_profile JSONB;
    v_points_balance NUMERIC;
    v_ticket_balances JSONB;
    v_user_payload JSONB;
BEGIN
    v_user_id := api_find_user(
        p_merchant_id => p_merchant_id,
        p_user_id => p_user_id,
        p_external_user_id => p_external_user_id,
        p_email => p_email,
        p_tel => p_tel,
        p_line_id => p_line_id
    );

    IF v_user_id IS NULL THEN
        RETURN jsonb_build_object('success', false, 'error', 'User not found', 'code', 'USER_NOT_FOUND');
    END IF;

    SELECT * INTO v_user FROM user_accounts WHERE id = v_user_id;

    SELECT COALESCE(points_balance, 0) INTO v_points_balance
    FROM user_wallet
    WHERE user_id = v_user_id AND merchant_id = p_merchant_id;

    IF v_points_balance IS NULL THEN
        v_points_balance := 0;
    END IF;

    SELECT COALESCE(jsonb_agg(
      jsonb_build_object(
        'ticket_type_id', s.entity_id,
        'ticket_code', s.entity_code,
        'name', s.entity_name,
        'balance', s.balance
      )
      ORDER BY s.entity_name
    ), '[]'::jsonb)
    INTO v_ticket_balances
    FROM get_user_wallet_summary(v_user_id, p_merchant_id) s
    WHERE s.currency_type = 'ticket';

    SELECT jsonb_agg(jsonb_build_object(
        'address_line_1', addressline_1, 'address_line_2', addressline_2,
        'state', state, 'city', city, 'district', district,
        'subdistrict', subdistrict, 'postcode', postcode
    )) INTO v_addresses
    FROM user_address WHERE user_id = v_user_id AND merchant_id = p_merchant_id;

    SELECT jsonb_object_agg(ff.field_key, COALESCE(fr.text_value, fr.array_value::text)) INTO v_latest_profile
    FROM (
        SELECT id, form_id, submitted_at FROM form_submissions
        WHERE user_id = v_user_id AND merchant_id = p_merchant_id
        ORDER BY submitted_at DESC LIMIT 1
    ) fs
    JOIN form_responses fr ON fr.submission_id = fs.id
    JOIN form_fields ff ON fr.field_id = ff.id;

    v_user_payload := jsonb_build_object(
        'user_id', v_user.id, 'external_user_id', v_user.external_user_id,
        'fullname', v_user.fullname, 'firstname', v_user.firstname, 'lastname', v_user.lastname,
        'email', v_user.email, 'tel', v_user.tel,
        'line_id', v_user.line_id, 'id_card', v_user.id_card, 'birth_date', v_user.birth_date,
        'user_type', v_user.user_type, 'user_stage', v_user.user_stage,
        'tier_id', v_user.tier_id, 'persona_id', v_user.persona_id,
        'points_balance', v_points_balance,
        'ticket_balances', COALESCE(v_ticket_balances, '[]'::jsonb),
        'channel_email', v_user.channel_email,
        'channel_sms', v_user.channel_sms, 'channel_line', v_user.channel_line,
        'channel_push', v_user.channel_push, 'created_at', v_user.created_at,
        'addresses', COALESCE(v_addresses, '[]'::jsonb),
        'custom_fields', COALESCE(v_latest_profile, '{}'::jsonb)
    );

    IF p_include_tier THEN
        v_user_payload := v_user_payload || jsonb_build_object(
            'member_status', public.fn_open_api_member_status(v_user.is_freeze, v_user.is_active),
            'tier', public.fn_open_api_user_tier_block(v_user_id, p_merchant_id)
        );
    END IF;

    RETURN jsonb_build_object(
        'success', true,
        'user', v_user_payload
    );

EXCEPTION WHEN OTHERS THEN
    RETURN jsonb_build_object('success', false, 'error', 'Failed to retrieve user', 'code', 'USER_FETCH_FAILED', 'details', SQLERRM);
END;
$function$;

GRANT EXECUTE ON FUNCTION public.fn_get_tier_progress_from_cache(uuid, uuid) TO anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.fn_open_api_member_status(boolean, boolean) TO anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.fn_open_api_user_tier_block(uuid, uuid) TO anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.api_get_user(uuid, uuid, text, text, text, text, boolean) TO anon, authenticated, service_role;
