-- Gorgias helpdesk integration: OAuth credential storage, ticket sidebar lookup, goodwill earn.

INSERT INTO public.integration_type_master (
  integration_key, display_name, description,
  platform_key, platform_name, platform_order,
  public_fields, sensitive_fields
)
SELECT
  'gorgias',
  'Gorgias',
  'Points, tier, referral on tickets; agents award goodwill pts',
  'gorgias',
  'Gorgias',
  8,
  ARRAY['account_subdomain']::text[],
  ARRAY['access_token', 'refresh_token', 'inbound_secret']::text[]
WHERE NOT EXISTS (
  SELECT 1
  FROM public.integration_type_master existing
  WHERE existing.integration_key = 'gorgias'
);

CREATE UNIQUE INDEX IF NOT EXISTS merchant_credentials_one_gorgias_uidx
  ON public.merchant_credentials (merchant_id)
  WHERE service_name = 'gorgias';

-- Map internal member snapshot → Gorgias widget JSON (paths under `loyalty.*`).
CREATE OR REPLACE FUNCTION public.fn_integration_gorgias_map_snapshot(p_snapshot jsonb)
RETURNS jsonb
LANGUAGE sql
IMMUTABLE
AS $function$
  SELECT jsonb_build_object(
    'loyalty', jsonb_build_object(
      'points_balance', p_snapshot->>'points_balance',
      'points_as_cash', p_snapshot->>'points_as_cash',
      'store_credit_balance', NULL,
      'status', p_snapshot->>'status',
      'referral_url', p_snapshot->'referral_url',
      'vip_tier_name', p_snapshot->>'current_tier_name',
      'vip_tier_id', p_snapshot->>'current_tier_id',
      'next_vip_tier_name', p_snapshot->>'next_tier_name',
      'amount_needed_for_next_vip_tier', p_snapshot->>'amount_needed_for_next_tier',
      'points_to_next_reward', p_snapshot->'points_to_next_reward',
      'date_of_birth', p_snapshot->>'birth_date',
      'member_joined_date', p_snapshot->>'joined_at',
      'membership_tier_name', NULL,
      'membership_status', NULL,
      'membership_next_billing_date', NULL,
      'membership_pending_cancellation_date', NULL,
      'membership_last_joined_date', NULL,
      'store_credit_code', NULL
    )
  );
$function$;

CREATE OR REPLACE FUNCTION public.fn_integration_gorgias_resolve_by_email(
  p_merchant_id uuid,
  p_email text,
  p_inbound_secret text
)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_cred record;
  v_user_id uuid;
  v_snapshot jsonb;
BEGIN
  IF p_merchant_id IS NULL OR NULLIF(TRIM(p_email), '') IS NULL THEN
    RETURN NULL;
  END IF;

  SELECT
    mc.id,
    mc.is_active,
    mc.credentials
  INTO v_cred
  FROM public.merchant_credentials mc
  WHERE mc.merchant_id = p_merchant_id
    AND mc.service_name = 'gorgias'
    AND mc.is_active IS TRUE
  ORDER BY mc.updated_at DESC NULLS LAST
  LIMIT 1;

  IF v_cred.id IS NULL THEN
    RETURN NULL;
  END IF;

  IF COALESCE(v_cred.credentials->>'inbound_secret', '') <> COALESCE(p_inbound_secret, '') THEN
    RETURN NULL;
  END IF;

  SELECT ua.id
  INTO v_user_id
  FROM public.user_accounts ua
  WHERE ua.merchant_id = p_merchant_id
    AND ua.deleted_at IS NULL
    AND NULLIF(TRIM(ua.email), '') IS NOT NULL
    AND lower(ua.email) = lower(trim(p_email))
  ORDER BY ua.updated_at DESC NULLS LAST
  LIMIT 1;

  IF v_user_id IS NULL THEN
    RETURN jsonb_build_object('loyalty', jsonb_build_object());
  END IF;

  v_snapshot := public.fn_integration_resolve_member_snapshot(p_merchant_id, v_user_id);
  IF v_snapshot IS NULL THEN
    RETURN jsonb_build_object('loyalty', jsonb_build_object());
  END IF;

  RETURN public.fn_integration_gorgias_map_snapshot(v_snapshot);
END;
$function$;

CREATE OR REPLACE FUNCTION public.fn_integration_gorgias_award_points(
  p_merchant_id uuid,
  p_email text,
  p_inbound_secret text,
  p_points integer,
  p_reason text DEFAULT NULL,
  p_ticket_id text DEFAULT NULL,
  p_agent_email text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_cred record;
  v_user_id uuid;
  v_reason text;
  v_ledger_id uuid;
  v_balance numeric;
  v_dedup text;
BEGIN
  IF p_merchant_id IS NULL OR NULLIF(TRIM(p_email), '') IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'reason', 'missing_input');
  END IF;

  IF p_points IS NULL OR p_points <= 0 THEN
    RETURN jsonb_build_object('ok', false, 'reason', 'invalid_points');
  END IF;

  SELECT mc.id, mc.credentials
  INTO v_cred
  FROM public.merchant_credentials mc
  WHERE mc.merchant_id = p_merchant_id
    AND mc.service_name = 'gorgias'
    AND mc.is_active IS TRUE
  ORDER BY mc.updated_at DESC NULLS LAST
  LIMIT 1;

  IF v_cred.id IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'reason', 'not_connected');
  END IF;

  IF COALESCE(v_cred.credentials->>'inbound_secret', '') <> COALESCE(p_inbound_secret, '') THEN
    RETURN jsonb_build_object('ok', false, 'reason', 'unauthorized');
  END IF;

  SELECT ua.id
  INTO v_user_id
  FROM public.user_accounts ua
  WHERE ua.merchant_id = p_merchant_id
    AND ua.deleted_at IS NULL
    AND NULLIF(TRIM(ua.email), '') IS NOT NULL
    AND lower(ua.email) = lower(trim(p_email))
  ORDER BY ua.updated_at DESC NULLS LAST
  LIMIT 1;

  IF v_user_id IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'reason', 'member_not_found');
  END IF;

  v_reason := COALESCE(NULLIF(TRIM(p_reason), ''), 'Gorgias goodwill points');

  v_dedup := 'gorgias:' || COALESCE(NULLIF(TRIM(p_ticket_id), ''), 'ticket') || ':' ||
    to_char(now() AT TIME ZONE 'utc', 'YYYYMMDDHH24MISS') || ':' || p_points::text;

  v_ledger_id := public.chokepoint_post_wallet_transaction(
    p_user_id := v_user_id,
    p_currency := 'points',
    p_source_type := 'manual',
    p_component := 'bonus',
    p_transaction_type := 'earn',
    p_amount := p_points,
    p_transaction_id := v_cred.id,
    p_merchant_id := p_merchant_id,
    p_description := v_reason,
    p_metadata := jsonb_build_object(
      'provider', 'gorgias',
      'ticket_id', p_ticket_id,
      'agent_email', p_agent_email,
      'reason', v_reason
    ),
    p_dedup_key := v_dedup
  );

  SELECT COALESCE(uw.points_balance, 0)
  INTO v_balance
  FROM public.user_wallet uw
  WHERE uw.user_id = v_user_id
    AND uw.merchant_id = p_merchant_id;

  RETURN jsonb_build_object(
    'ok', true,
    'ledger_id', v_ledger_id,
    'points_awarded', p_points,
    'new_balance', COALESCE(v_balance, 0)
  );
EXCEPTION
  WHEN OTHERS THEN
    RETURN jsonb_build_object('ok', false, 'reason', SQLERRM);
END;
$function$;

CREATE OR REPLACE FUNCTION public.bff_integration_gorgias_get_connection(
  p_language text DEFAULT 'en'::text
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_lang text;
  v_merchant_id uuid;
  v_cred record;
  v_has_token boolean;
BEGIN
  v_lang := fn_normalize_ui_language(p_language);
  v_merchant_id := get_current_merchant_id();
  IF v_merchant_id IS NULL THEN
    RETURN fn_response_error(
      fn_admin_envelope_message('merchant_context_not_found_title', v_lang),
      fn_admin_envelope_message('unable_identify_merchant_token_desc', v_lang)
    );
  END IF;

  SELECT
    mc.id,
    mc.is_active,
    mc.health_status,
    mc.last_health_check,
    mc.expires_at,
    mc.credentials
  INTO v_cred
  FROM public.merchant_credentials mc
  WHERE mc.merchant_id = v_merchant_id
    AND mc.service_name = 'gorgias'
  ORDER BY mc.updated_at DESC NULLS LAST
  LIMIT 1;

  v_has_token := COALESCE(NULLIF(TRIM(v_cred.credentials->>'access_token'), ''), '') <> '';

  RETURN fn_response_success(
    NULL,
    NULL,
    jsonb_build_object(
      'connected', COALESCE(v_cred.is_active, false) AND v_has_token,
      'account_subdomain', v_cred.credentials->>'account_subdomain',
      'health_status', COALESCE(v_cred.health_status, 'disconnected'),
      'last_health_check', v_cred.last_health_check,
      'expires_at', v_cred.expires_at,
      'credential_id', v_cred.id
    )
  );
END;
$function$;

CREATE OR REPLACE FUNCTION public.bff_integration_gorgias_disconnect(
  p_language text DEFAULT 'en'::text
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_lang text;
  v_merchant_id uuid;
  v_id uuid;
BEGIN
  v_lang := fn_normalize_ui_language(p_language);
  v_merchant_id := get_current_merchant_id();
  IF v_merchant_id IS NULL THEN
    RETURN fn_response_error(
      fn_admin_envelope_message('merchant_context_not_found_title', v_lang),
      fn_admin_envelope_message('unable_identify_merchant_token_desc', v_lang)
    );
  END IF;

  UPDATE public.merchant_credentials
     SET is_active = false,
         health_status = 'disconnected',
         last_health_check = now(),
         updated_at = now()
   WHERE merchant_id = v_merchant_id
     AND service_name = 'gorgias'
     AND is_active IS TRUE
   RETURNING id INTO v_id;

  IF v_id IS NULL THEN
    RETURN fn_response_error('Not connected', 'Gorgias is not connected for this merchant');
  END IF;

  RETURN fn_response_success(
    'Disconnected',
    'Gorgias will stop showing Rocket loyalty data until you reconnect.',
    jsonb_build_object('credential_id', v_id, 'connected', false)
  );
END;
$function$;

REVOKE ALL ON FUNCTION public.fn_integration_gorgias_map_snapshot(jsonb) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.fn_integration_gorgias_resolve_by_email(uuid, text, text) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.fn_integration_gorgias_award_points(uuid, text, text, integer, text, text, text) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.bff_integration_gorgias_get_connection(text) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.bff_integration_gorgias_disconnect(text) FROM PUBLIC, anon;

GRANT EXECUTE ON FUNCTION public.fn_integration_gorgias_map_snapshot(jsonb) TO service_role;
GRANT EXECUTE ON FUNCTION public.fn_integration_gorgias_resolve_by_email(uuid, text, text) TO service_role;
GRANT EXECUTE ON FUNCTION public.fn_integration_gorgias_award_points(uuid, text, text, integer, text, text, text) TO service_role;
GRANT EXECUTE ON FUNCTION public.bff_integration_gorgias_get_connection(text) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.bff_integration_gorgias_disconnect(text) TO authenticated, service_role;
