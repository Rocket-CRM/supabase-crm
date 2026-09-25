-- Durable terminal failure records for async redemptions (HTTP status polling).
-- Success remains on reward_redemptions_ledger where event_id = ledger.id.
-- Additive only: widget / loyalty-user Realtime broadcasts are unchanged.

CREATE TABLE IF NOT EXISTS public.redemption_request_outcome (
  event_id uuid PRIMARY KEY,
  user_id uuid NOT NULL REFERENCES public.user_accounts(id) ON DELETE CASCADE,
  merchant_id uuid NOT NULL REFERENCES public.merchant_master(id) ON DELETE CASCADE,
  reward_id uuid NOT NULL REFERENCES public.reward_master(id) ON DELETE CASCADE,
  status text NOT NULL DEFAULT 'failed' CHECK (status = 'failed'),
  title text NOT NULL,
  description text NOT NULL DEFAULT '',
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS redemption_request_outcome_user_idx
  ON public.redemption_request_outcome (user_id, created_at DESC);

ALTER TABLE public.redemption_request_outcome ENABLE ROW LEVEL SECURITY;

CREATE POLICY redemption_request_outcome_member_select
  ON public.redemption_request_outcome
  FOR SELECT
  TO authenticated
  USING (
    user_id IN (
      SELECT ua.id
      FROM public.user_accounts ua
      WHERE ua.deleted_at IS NULL
        AND ua.is_active IS NOT FALSE
        AND (
          ua.auth_user_id = public.get_current_user_id()
          OR ua.id = public.get_current_user_id()
        )
    )
    AND merchant_id = public.get_current_merchant_id()
  );

CREATE OR REPLACE FUNCTION public.fn_record_redemption_request_failure(
  p_event_id uuid,
  p_user_id uuid,
  p_merchant_id uuid,
  p_reward_id uuid,
  p_title text,
  p_description text DEFAULT ''
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
BEGIN
  INSERT INTO public.redemption_request_outcome (
    event_id,
    user_id,
    merchant_id,
    reward_id,
    status,
    title,
    description
  ) VALUES (
    p_event_id,
    p_user_id,
    p_merchant_id,
    p_reward_id,
    'failed',
    COALESCE(NULLIF(trim(p_title), ''), 'Redemption failed'),
    COALESCE(p_description, '')
  )
  ON CONFLICT (event_id) DO UPDATE
  SET
    title = EXCLUDED.title,
    description = EXCLUDED.description;
END;
$function$;

REVOKE ALL ON FUNCTION public.fn_record_redemption_request_failure(uuid, uuid, uuid, uuid, text, text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.fn_record_redemption_request_failure(uuid, uuid, uuid, uuid, text, text) TO service_role;

REVOKE ALL ON TABLE public.redemption_request_outcome FROM PUBLIC;
GRANT SELECT ON TABLE public.redemption_request_outcome TO authenticated;
GRANT ALL ON TABLE public.redemption_request_outcome TO service_role;

CREATE OR REPLACE FUNCTION public.bff_user_get_redemption_request_status(p_event_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_auth_uid uuid;
  v_user_id uuid;
  v_merchant_id uuid;
  v_failure record;
  v_ledger record;
  v_reward_name text;
  v_code text;
BEGIN
  IF p_event_id IS NULL THEN
    RETURN fn_response_error('Validation error', 'event_id is required', 'VALIDATION_ERROR');
  END IF;

  v_auth_uid := public.get_current_user_id();
  IF v_auth_uid IS NULL THEN
    RETURN fn_response_error('Unauthenticated', 'No authenticated user context', 'UNAUTHENTICATED');
  END IF;

  SELECT ua.id, ua.merchant_id
  INTO v_user_id, v_merchant_id
  FROM public.user_accounts ua
  WHERE ua.deleted_at IS NULL
    AND ua.is_active IS NOT FALSE
    AND (ua.auth_user_id = v_auth_uid OR ua.id = v_auth_uid)
  LIMIT 1;

  IF v_user_id IS NULL THEN
    RETURN fn_response_error('User not found', 'No user account is linked to this authenticated user', 'USER_NOT_FOUND');
  END IF;

  SELECT rro.title, rro.description, rro.reward_id
  INTO v_failure
  FROM public.redemption_request_outcome rro
  WHERE rro.event_id = p_event_id
    AND rro.user_id = v_user_id
    AND rro.merchant_id = v_merchant_id
    AND rro.status = 'failed';

  IF FOUND THEN
    SELECT rm.name INTO v_reward_name FROM public.reward_master rm WHERE rm.id = v_failure.reward_id;
    RETURN fn_response_success(NULL, NULL, jsonb_build_object(
      'status', 'failed',
      'request_id', p_event_id::text,
      'code', NULL,
      'expires_at', NULL,
      'reward_name', v_reward_name,
      'title', v_failure.title,
      'description', v_failure.description
    ));
  END IF;

  SELECT
    rrl.id,
    rrl.promo_code,
    rrl.code,
    rrl.use_expire_date,
    rrl.redeemed_status,
    rrl.reward_id
  INTO v_ledger
  FROM public.reward_redemptions_ledger rrl
  WHERE rrl.id = p_event_id
    AND rrl.user_id = v_user_id
    AND rrl.merchant_id = v_merchant_id
  LIMIT 1;

  IF FOUND THEN
    SELECT rm.name INTO v_reward_name FROM public.reward_master rm WHERE rm.id = v_ledger.reward_id;
    v_code := COALESCE(NULLIF(trim(v_ledger.promo_code), ''), NULLIF(trim(v_ledger.code), ''));

    IF COALESCE(v_ledger.redeemed_status, false) AND v_code IS NOT NULL THEN
      RETURN fn_response_success(NULL, NULL, jsonb_build_object(
        'status', 'issued',
        'request_id', p_event_id::text,
        'code', v_code,
        'expires_at', v_ledger.use_expire_date,
        'reward_name', v_reward_name,
        'title', NULL,
        'description', NULL
      ));
    END IF;

    RETURN fn_response_success(NULL, NULL, jsonb_build_object(
      'status', 'pending',
      'request_id', p_event_id::text,
      'code', NULL,
      'expires_at', NULL,
      'reward_name', v_reward_name,
      'title', NULL,
      'description', NULL
    ));
  END IF;

  RETURN fn_response_success(NULL, NULL, jsonb_build_object(
    'status', 'pending',
    'request_id', p_event_id::text,
    'code', NULL,
    'expires_at', NULL,
    'reward_name', NULL,
    'title', NULL,
    'description', NULL
  ));
EXCEPTION WHEN OTHERS THEN
  RETURN fn_response_error('Error checking redemption status', SQLERRM, SQLSTATE);
END;
$function$;

GRANT EXECUTE ON FUNCTION public.bff_user_get_redemption_request_status(uuid)
  TO postgres, authenticated, service_role;

COMMENT ON TABLE public.redemption_request_outcome IS
  'Terminal async redemption failures keyed by event_id. Success rows live on reward_redemptions_ledger.';
COMMENT ON FUNCTION public.bff_user_get_redemption_request_status(uuid) IS
  'Member-scoped redemption request status for HTTP polling (issued | pending | failed).';
