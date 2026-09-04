-- Referral domain events on the chokepoint outbox (notification v1).
-- Emit-only: existing writers still own referral_ledger / referral_claim rows.
-- Events: applied, claimed, settled, clawed_back. Catalog maps settled+claimed only.

CREATE OR REPLACE FUNCTION public.chokepoint_post_referral_event(
  p_event text,
  p_merchant_id uuid,
  p_user_id uuid,
  p_referral_ledger_id uuid DEFAULT NULL,
  p_claim_id uuid DEFAULT NULL,
  p_recipient_role text DEFAULT NULL,
  p_skip_emit boolean DEFAULT false,
  p_extras jsonb DEFAULT '{}'::jsonb
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_event text := lower(trim(p_event));
  v_role text := lower(trim(p_recipient_role));
  v_ledger public.referral_ledger;
  v_claim public.referral_claim;
  v_payload jsonb;
  v_outbox_id bigint;
  v_partition text;
BEGIN
  IF v_event IS NULL OR v_event NOT IN ('applied', 'claimed', 'settled', 'clawed_back') THEN
    RAISE EXCEPTION 'chokepoint_post_referral_event: invalid event %', p_event
      USING ERRCODE = '22023';
  END IF;

  IF p_merchant_id IS NULL THEN
    RAISE EXCEPTION 'chokepoint_post_referral_event: merchant_id required'
      USING ERRCODE = '22023';
  END IF;

  IF v_role IS NOT NULL AND v_role NOT IN ('referrer', 'friend') THEN
    RAISE EXCEPTION 'chokepoint_post_referral_event: invalid recipient_role %', p_recipient_role
      USING ERRCODE = '22023';
  END IF;

  IF v_event IN ('applied', 'settled', 'clawed_back') THEN
    IF p_referral_ledger_id IS NULL THEN
      RAISE EXCEPTION 'chokepoint_post_referral_event: referral_ledger_id required for %', v_event
        USING ERRCODE = '22023';
    END IF;
    SELECT * INTO v_ledger
    FROM public.referral_ledger
    WHERE id = p_referral_ledger_id
      AND merchant_id = p_merchant_id;
    IF NOT FOUND THEN
      RAISE EXCEPTION 'chokepoint_post_referral_event: ledger % not found for merchant',
        p_referral_ledger_id
        USING ERRCODE = 'P0002';
    END IF;
  END IF;

  IF v_event = 'claimed' THEN
    IF p_claim_id IS NULL THEN
      RAISE EXCEPTION 'chokepoint_post_referral_event: claim_id required for claimed'
        USING ERRCODE = '22023';
    END IF;
    SELECT * INTO v_claim
    FROM public.referral_claim
    WHERE id = p_claim_id
      AND merchant_id = p_merchant_id;
    IF NOT FOUND THEN
      RAISE EXCEPTION 'chokepoint_post_referral_event: claim % not found for merchant',
        p_claim_id
        USING ERRCODE = 'P0002';
    END IF;
  END IF;

  IF p_skip_emit THEN
    RETURN jsonb_build_object(
      'success', true,
      'event', v_event,
      'referral_ledger_id', p_referral_ledger_id,
      'claim_id', p_claim_id,
      'emitted', false
    );
  END IF;

  v_partition := COALESCE(p_user_id::text, p_claim_id::text, p_referral_ledger_id::text);
  IF v_partition IS NULL THEN
    RETURN jsonb_build_object(
      'success', true,
      'event', v_event,
      'emitted', false,
      'skip_reason', 'missing_partition_key'
    );
  END IF;

  v_payload := jsonb_strip_nulls(
    jsonb_build_object(
      'event', v_event,
      'merchant_id', p_merchant_id,
      'user_id', p_user_id,
      'referral_ledger_id', COALESCE(p_referral_ledger_id, v_ledger.id),
      'claim_id', COALESCE(p_claim_id, v_ledger.claim_id, v_claim.id),
      'recipient_role', v_role,
      'kind', COALESCE(v_ledger.kind, CASE WHEN v_event = 'claimed' THEN 'purchase' ELSE NULL END),
      'status', v_ledger.status,
      'platform', COALESCE(v_ledger.platform, v_claim.platform),
      'invite_code', v_ledger.invite_code,
      'inviter_user_id', COALESCE(v_ledger.inviter_user_id, v_claim.referrer_user_id),
      'invitee_user_id', v_ledger.invitee_user_id,
      'friend_email', COALESCE(v_ledger.friend_email, v_claim.friend_email),
      'friend_phone', COALESCE(v_ledger.friend_phone, v_claim.friend_phone),
      'occurred_at', to_jsonb(now()),
      'source', 'chokepoint_post_referral_event'
    ) || COALESCE(p_extras, '{}'::jsonb)
  );

  BEGIN
    v_outbox_id := public.fn_chokepoint_emit_event(
      'crm.events.referral',
      v_partition,
      v_payload
    );
  EXCEPTION WHEN OTHERS THEN
    RAISE NOTICE 'chokepoint_post_referral_event emit failed: %', SQLERRM;
    RETURN jsonb_build_object(
      'success', true,
      'event', v_event,
      'referral_ledger_id', p_referral_ledger_id,
      'claim_id', p_claim_id,
      'emitted', false,
      'emit_error', SQLERRM
    );
  END;

  RETURN jsonb_build_object(
    'success', true,
    'event', v_event,
    'referral_ledger_id', p_referral_ledger_id,
    'claim_id', p_claim_id,
    'recipient_role', v_role,
    'emitted', true,
    'outbox_id', v_outbox_id
  );
END;
$function$;

GRANT EXECUTE ON FUNCTION public.chokepoint_post_referral_event(
  text, uuid, uuid, uuid, uuid, text, boolean, jsonb
) TO PUBLIC;

CREATE OR REPLACE FUNCTION public.fn_settle_referral(p_ledger_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE v_ledger record;
BEGIN
  SELECT * INTO v_ledger FROM public.referral_ledger WHERE id = p_ledger_id FOR UPDATE;
  IF NOT FOUND THEN RETURN jsonb_build_object('success', false, 'code', 'NOT_FOUND'); END IF;
  IF v_ledger.status = 'settled' THEN RETURN jsonb_build_object('success', true, 'code', 'ALREADY_SETTLED', 'ledger_id', p_ledger_id); END IF;
  IF v_ledger.status = 'clawed_back' THEN RETURN jsonb_build_object('success', false, 'code', 'CLAWED_BACK', 'ledger_id', p_ledger_id); END IF;
  PERFORM public.fn_process_referral_rewards(p_ledger_id);
  UPDATE public.referral_ledger SET status = 'settled', settled_at = COALESCE(settled_at, now()), updated_at = now() WHERE id = p_ledger_id;
  PERFORM public.chokepoint_post_referral_event(
    'settled', v_ledger.merchant_id, v_ledger.inviter_user_id, p_ledger_id, v_ledger.claim_id, 'referrer');
  IF COALESCE(v_ledger.kind, 'signup') = 'signup' AND v_ledger.invitee_user_id IS NOT NULL THEN
    PERFORM public.chokepoint_post_referral_event(
      'settled', v_ledger.merchant_id, v_ledger.invitee_user_id, p_ledger_id, v_ledger.claim_id, 'friend');
  END IF;
  RETURN jsonb_build_object('success', true, 'code', 'SETTLED', 'ledger_id', p_ledger_id);
END;
$function$;

CREATE OR REPLACE FUNCTION public.fn_clawback_referral(p_ledger_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE v_ledger record; v_log record;
BEGIN
  SELECT * INTO v_ledger FROM public.referral_ledger WHERE id = p_ledger_id FOR UPDATE;
  IF NOT FOUND THEN RETURN jsonb_build_object('success', false, 'code', 'NOT_FOUND'); END IF;
  IF v_ledger.status = 'clawed_back' THEN RETURN jsonb_build_object('success', true, 'code', 'ALREADY_CLAWED', 'ledger_id', p_ledger_id); END IF;
  FOR v_log IN SELECT * FROM public.outcome_distribution_log WHERE source_type = 'referral' AND source_id = p_ledger_id AND success = true
  LOOP
    BEGIN
      IF v_log.outcome_type::text = 'points' AND v_log.amount IS NOT NULL THEN
        PERFORM public.reverse_points(v_log.user_id, v_ledger.merchant_id, v_log.amount::integer, 'referral_clawback', p_ledger_id);
      ELSIF v_log.outcome_type::text = 'tickets' AND v_log.entity_id IS NOT NULL AND v_log.amount IS NOT NULL THEN
        PERFORM public.reverse_tickets(v_log.user_id, v_ledger.merchant_id, v_log.entity_id, v_log.amount::integer, 'referral_clawback', p_ledger_id);
      END IF;
    EXCEPTION WHEN OTHERS THEN
      RAISE WARNING 'Referral clawback reverse failed ledger=% log=%: %', p_ledger_id, v_log.id, SQLERRM;
    END;
  END LOOP;
  UPDATE public.referral_ledger SET status = 'clawed_back', clawed_back_at = now(), updated_at = now() WHERE id = p_ledger_id;
  PERFORM public.chokepoint_post_referral_event(
    'clawed_back', v_ledger.merchant_id, v_ledger.inviter_user_id, p_ledger_id, v_ledger.claim_id, 'referrer');
  RETURN jsonb_build_object('success', true, 'code', 'CLAWED', 'ledger_id', p_ledger_id);
END;
$function$;

CREATE OR REPLACE FUNCTION public.api_claim_referral(
  p_merchant_id uuid DEFAULT NULL::uuid,
  p_merchant_code text DEFAULT NULL::text,
  p_referrer_code text DEFAULT NULL::text,
  p_platform text DEFAULT NULL::text,
  p_email text DEFAULT NULL::text,
  p_phone text DEFAULT NULL::text,
  p_friend_name text DEFAULT NULL::text
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_merchant_id uuid; v_program public.referral_program; v_referrer record; v_email text; v_phone text;
  v_offer jsonb; v_ttl int; v_shop_cap int; v_ref_cap int; v_live_shop int; v_live_ref int;
  v_claim_id uuid; v_issued jsonb; v_mother text; v_friend_user_id uuid;
BEGIN
  v_merchant_id := p_merchant_id;
  IF v_merchant_id IS NULL AND NULLIF(btrim(p_merchant_code), '') IS NOT NULL THEN
    SELECT id INTO v_merchant_id FROM public.merchant_master WHERE merchant_code = btrim(p_merchant_code);
  END IF;
  IF v_merchant_id IS NULL THEN RETURN jsonb_build_object('success', false, 'code', 'NO_MERCHANT'); END IF;
  IF p_platform IS NULL OR p_platform NOT IN ('shopify', 'shopee') THEN RETURN jsonb_build_object('success', false, 'code', 'INVALID_PLATFORM'); END IF;
  IF NULLIF(btrim(p_referrer_code), '') IS NULL THEN RETURN jsonb_build_object('success', false, 'code', 'INVALID_REFERRER'); END IF;
  v_email := NULLIF(lower(btrim(COALESCE(p_email, ''))), '');
  v_phone := public.fn_normalize_referral_phone(p_phone);
  IF p_platform = 'shopify' AND v_email IS NULL THEN RETURN jsonb_build_object('success', false, 'code', 'EMAIL_REQUIRED'); END IF;
  IF p_platform = 'shopee' AND v_phone IS NULL THEN RETURN jsonb_build_object('success', false, 'code', 'PHONE_REQUIRED'); END IF;
  SELECT * INTO v_program FROM public.referral_program WHERE merchant_id = v_merchant_id;
  IF v_program.id IS NULL OR NOT v_program.is_active OR NOT v_program.purchase_enabled OR NOT (p_platform = ANY (COALESCE(v_program.platforms, '{}'::text[]))) THEN
    RETURN jsonb_build_object('success', false, 'code', 'REFERRAL_INACTIVE');
  END IF;
  SELECT * INTO v_referrer FROM public.user_accounts WHERE merchant_id = v_merchant_id AND member_code = btrim(p_referrer_code);
  IF NOT FOUND THEN RETURN jsonb_build_object('success', false, 'code', 'INVALID_REFERRER'); END IF;
  IF v_email IS NOT NULL AND lower(COALESCE(v_referrer.email, '')) = v_email THEN RETURN jsonb_build_object('success', false, 'code', 'SELF_REFERRAL'); END IF;
  IF v_phone IS NOT NULL AND public.fn_normalize_referral_phone(v_referrer.tel) = v_phone THEN RETURN jsonb_build_object('success', false, 'code', 'SELF_REFERRAL'); END IF;
  IF p_platform = 'shopify' AND v_email IS NOT NULL AND EXISTS (SELECT 1 FROM public.user_accounts ua WHERE ua.merchant_id = v_merchant_id AND lower(ua.email) = v_email) THEN
    RETURN jsonb_build_object('success', false, 'code', 'EXISTING_CUSTOMER');
  END IF;
  IF EXISTS (SELECT 1 FROM public.referral_claim c WHERE c.merchant_id = v_merchant_id AND c.platform = p_platform AND c.status IN ('open', 'completed') AND ((v_email IS NOT NULL AND c.friend_email = v_email) OR (v_phone IS NOT NULL AND c.friend_phone = v_phone))) THEN
    RETURN jsonb_build_object('success', false, 'code', 'ALREADY_CLAIMED');
  END IF;
  PERFORM public.fn_expire_stale_referral_codes(v_merchant_id);
  v_offer := COALESCE(v_program.friend_offer, '{}'::jsonb);
  v_ttl := GREATEST(COALESCE((v_offer->>'ttl_hours')::int, 24), 1);
  v_shop_cap := GREATEST(COALESCE((v_offer->>'shop_live_unused_cap')::int, 800), 1);
  v_ref_cap := GREATEST(COALESCE((v_offer->>'per_referrer_live_unused_cap')::int, 5), 1);
  SELECT COUNT(*)::int INTO v_live_shop FROM public.referral_code WHERE merchant_id = v_merchant_id AND platform = p_platform AND status IN ('pending_mint', 'minted') AND expires_at > now();
  IF v_live_shop >= v_shop_cap THEN RETURN jsonb_build_object('success', false, 'code', 'SHOP_CAP'); END IF;
  SELECT COUNT(*)::int INTO v_live_ref FROM public.referral_code WHERE merchant_id = v_merchant_id AND platform = p_platform AND referrer_user_id = v_referrer.id AND status IN ('pending_mint', 'minted') AND expires_at > now();
  IF v_live_ref >= v_ref_cap THEN RETURN jsonb_build_object('success', false, 'code', 'REFERRER_CAP'); END IF;
  INSERT INTO public.referral_claim (merchant_id, referrer_user_id, platform, friend_email, friend_phone, status)
  VALUES (v_merchant_id, v_referrer.id, p_platform, v_email, v_phone, 'open') RETURNING id INTO v_claim_id;
  v_issued := public.fn_issue_referral_code(v_merchant_id, v_claim_id, p_platform, v_ttl);
  IF NOT COALESCE((v_issued->>'success')::boolean, false) THEN
    UPDATE public.referral_claim SET status = 'aborted', updated_at = now() WHERE id = v_claim_id;
    RETURN jsonb_build_object('success', false, 'code', COALESCE(v_issued->>'code', 'ISSUE_FAILED'));
  END IF;
  v_mother := v_program.shopify_mother_discount_id;
  SELECT ua.id INTO v_friend_user_id
  FROM public.user_accounts ua
  WHERE ua.merchant_id = v_merchant_id
    AND (
      (v_email IS NOT NULL AND lower(ua.email) = v_email)
      OR (v_phone IS NOT NULL AND public.fn_normalize_referral_phone(ua.tel) = v_phone)
    )
  LIMIT 1;
  PERFORM public.chokepoint_post_referral_event(
    'claimed',
    v_merchant_id,
    v_friend_user_id,
    NULL,
    v_claim_id,
    'friend',
    false,
    jsonb_build_object(
      'kind', 'purchase',
      'platform', p_platform,
      'inviter_user_id', v_referrer.id,
      'friend_email', v_email,
      'friend_phone', v_phone
    )
  );
  RETURN jsonb_build_object('success', true, 'code', 'OK', 'data', jsonb_build_object('claim_id', v_claim_id, 'referral_code_id', v_issued->>'referral_code_id', 'commerce_code', v_issued->>'commerce_code', 'expires_at', v_issued->>'expires_at', 'platform', p_platform, 'merchant_id', v_merchant_id, 'shopify_mother_discount_id', v_mother, 'friend_offer', v_offer, 'ttl_hours', v_ttl));
END;
$function$;

CREATE OR REPLACE FUNCTION public.fn_attribute_referral(
  p_kind text,
  p_merchant_id uuid DEFAULT NULL::uuid,
  p_invitee_user_id uuid DEFAULT NULL::uuid,
  p_invite_code text DEFAULT NULL::text,
  p_platform text DEFAULT NULL::text,
  p_order_key text DEFAULT NULL::text,
  p_order_status text DEFAULT NULL::text,
  p_payment_status text DEFAULT NULL::text,
  p_buyer_email text DEFAULT NULL::text,
  p_buyer_phone text DEFAULT NULL::text,
  p_buyer_external_id text DEFAULT NULL::text,
  p_codes text[] DEFAULT NULL::text[]
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_program public.referral_program; v_invitee record; v_inviter record; v_ledger_id uuid; v_existing uuid;
  v_limit record; v_limit_window timestamptz; v_used numeric; v_code text;
  v_claim public.referral_claim; v_rc public.referral_code; v_email text; v_phone text; v_codes text[];
  v_cancel boolean; v_qualify boolean;
BEGIN
  IF p_kind IS NULL OR p_kind NOT IN ('signup', 'purchase') THEN
    RETURN jsonb_build_object('success', false, 'code', 'INVALID_INPUT', 'error', 'kind must be signup|purchase');
  END IF;

  IF p_kind = 'signup' THEN
    IF p_invitee_user_id IS NULL OR NULLIF(btrim(p_invite_code), '') IS NULL THEN
      RETURN jsonb_build_object('success', false, 'code', 'INVALID_INPUT', 'error', 'invitee_user_id and invite_code required');
    END IF;
    v_code := btrim(p_invite_code);
    SELECT * INTO v_invitee FROM public.user_accounts WHERE id = p_invitee_user_id;
    IF NOT FOUND THEN RETURN jsonb_build_object('success', false, 'code', 'INVITEE_NOT_FOUND', 'error', 'Invitee user not found'); END IF;
    SELECT * INTO v_program FROM public.referral_program WHERE merchant_id = v_invitee.merchant_id;
    IF v_program.id IS NULL OR NOT v_program.is_active OR NOT v_program.signup_enabled THEN
      RETURN jsonb_build_object('success', false, 'code', 'REFERRAL_INACTIVE', 'error', 'Referral program inactive');
    END IF;
    SELECT * INTO v_inviter FROM public.user_accounts WHERE merchant_id = v_invitee.merchant_id AND member_code = v_code;
    IF NOT FOUND THEN RETURN jsonb_build_object('success', false, 'code', 'INVALID_INVITE_CODE', 'error', 'Invalid invite code'); END IF;
    IF v_inviter.id = v_invitee.id THEN RETURN jsonb_build_object('success', false, 'code', 'SELF_REFERRAL', 'error', 'Cannot refer yourself'); END IF;
    IF EXISTS (SELECT 1 FROM public.referral_ledger WHERE invitee_user_id = p_invitee_user_id AND merchant_id = v_invitee.merchant_id AND kind = 'signup') THEN
      RETURN jsonb_build_object('success', false, 'code', 'ALREADY_REFERRED', 'error', 'User already referred');
    END IF;
    FOR v_limit IN
      SELECT * FROM public.transaction_limits
      WHERE merchant_id = v_invitee.merchant_id AND entity_type = 'referral' AND entity_id IS NULL
        AND COALESCE(active_status, true) AND (window_start IS NULL OR window_start <= now()) AND (window_end IS NULL OR window_end >= now())
    LOOP
      v_limit_window := CASE v_limit.time_unit WHEN 'day' THEN date_trunc('day', now()) WHEN 'week' THEN date_trunc('week', now()) WHEN 'month' THEN date_trunc('month', now()) WHEN 'year' THEN date_trunc('year', now()) ELSE NULL END;
      IF v_limit.scope = 'user' THEN
        SELECT COUNT(*)::numeric INTO v_used FROM public.referral_ledger rl
        WHERE rl.inviter_user_id = v_inviter.id AND rl.merchant_id = v_invitee.merchant_id AND rl.kind = 'signup' AND (v_limit_window IS NULL OR rl.created_at >= v_limit_window);
      ELSIF v_limit.scope = 'total' THEN
        SELECT COUNT(*)::numeric INTO v_used FROM public.referral_ledger rl
        WHERE rl.merchant_id = v_invitee.merchant_id AND rl.kind = 'signup' AND (v_limit_window IS NULL OR rl.created_at >= v_limit_window);
      ELSE CONTINUE;
      END IF;
      IF v_used >= v_limit.count THEN
        RETURN jsonb_build_object('success', false, 'code', 'LIMIT_EXCEEDED', 'error', 'Referral limit exceeded', 'limit_scope', v_limit.scope, 'time_unit', v_limit.time_unit, 'count', v_limit.count, 'used', v_used);
      END IF;
    END LOOP;
    INSERT INTO public.referral_ledger (merchant_id, inviter_user_id, invitee_user_id, invite_code, signed_up_at, kind, status)
    VALUES (v_invitee.merchant_id, v_inviter.id, p_invitee_user_id, v_code, now(), 'signup', 'applied')
    RETURNING id INTO v_ledger_id;
    PERFORM public.chokepoint_post_referral_event(
      'applied', v_invitee.merchant_id, p_invitee_user_id, v_ledger_id, NULL, 'friend');
    PERFORM public.fn_settle_referral(v_ledger_id);
    RETURN jsonb_build_object('success', true, 'code', 'OK', 'ledger_id', v_ledger_id, 'inviter_user_id', v_inviter.id, 'invitee_user_id', p_invitee_user_id);
  END IF;

  IF p_merchant_id IS NULL OR NULLIF(p_platform, '') IS NULL OR NULLIF(p_order_key, '') IS NULL THEN
    RETURN jsonb_build_object('success', false, 'code', 'INVALID_INPUT', 'error', 'merchant, platform, order_key required');
  END IF;
  SELECT * INTO v_program FROM public.referral_program WHERE merchant_id = p_merchant_id;
  IF v_program.id IS NULL OR NOT v_program.is_active OR NOT v_program.purchase_enabled THEN
    RETURN jsonb_build_object('success', false, 'code', 'MISS');
  END IF;
  IF NOT (p_platform = ANY (COALESCE(v_program.platforms, '{}'::text[]))) THEN
    RETURN jsonb_build_object('success', false, 'code', 'MISS');
  END IF;
  v_email := NULLIF(lower(btrim(COALESCE(p_buyer_email, ''))), '');
  v_phone := public.fn_normalize_referral_phone(p_buyer_phone);
  v_codes := COALESCE(p_codes, '{}'::text[]);
  SELECT id INTO v_existing FROM public.referral_ledger
  WHERE merchant_id = p_merchant_id AND kind = 'purchase' AND platform = p_platform AND order_key = p_order_key LIMIT 1;
  v_cancel := lower(COALESCE(p_order_status, '')) IN ('cancelled', 'canceled', 'refunded', 'voided', 'in_cancel', 'to_return', 'returned')
    OR lower(COALESCE(p_payment_status, '')) IN ('refunded', 'voided', 'cancelled');
  IF v_existing IS NOT NULL THEN
    IF v_cancel THEN RETURN public.fn_clawback_referral(v_existing); END IF;
    RETURN jsonb_build_object('success', true, 'code', 'IDEMPOTENT', 'ledger_id', v_existing);
  END IF;
  IF v_cancel THEN RETURN jsonb_build_object('success', false, 'code', 'MISS'); END IF;
  IF v_email IS NOT NULL THEN
    SELECT * INTO v_claim FROM public.referral_claim
    WHERE merchant_id = p_merchant_id AND platform = p_platform AND status = 'open' AND friend_email = v_email
    ORDER BY created_at ASC LIMIT 1;
  END IF;
  IF v_claim.id IS NULL AND v_phone IS NOT NULL THEN
    SELECT * INTO v_claim FROM public.referral_claim
    WHERE merchant_id = p_merchant_id AND platform = p_platform AND status = 'open' AND friend_phone = v_phone
    ORDER BY created_at ASC LIMIT 1;
  END IF;
  IF v_claim.id IS NULL AND NULLIF(p_buyer_external_id, '') IS NOT NULL THEN
    SELECT * INTO v_claim FROM public.referral_claim
    WHERE merchant_id = p_merchant_id AND platform = p_platform AND status = 'open' AND friend_shopify_customer_id = p_buyer_external_id
    ORDER BY created_at ASC LIMIT 1;
  END IF;
  IF v_claim.id IS NULL AND array_length(v_codes, 1) IS NOT NULL THEN
    SELECT rc.* INTO v_rc FROM public.referral_code rc
    WHERE rc.merchant_id = p_merchant_id AND rc.platform = p_platform AND rc.status IN ('minted', 'used') AND rc.code = ANY (v_codes)
    ORDER BY rc.created_at ASC LIMIT 1;
    IF v_rc.id IS NOT NULL THEN SELECT * INTO v_claim FROM public.referral_claim WHERE id = v_rc.claim_id; END IF;
  END IF;
  IF v_claim.id IS NULL THEN RETURN jsonb_build_object('success', false, 'code', 'MISS'); END IF;
  IF EXISTS (SELECT 1 FROM public.referral_ledger WHERE claim_id = v_claim.id AND kind = 'purchase' AND status IN ('attributed', 'settled')) THEN
    RETURN jsonb_build_object('success', false, 'code', 'CLAIM_ALREADY_USED');
  END IF;
  INSERT INTO public.referral_ledger (merchant_id, inviter_user_id, invite_code, kind, status, platform, claim_id, code_id, order_key, friend_email, friend_phone)
  VALUES (p_merchant_id, v_claim.referrer_user_id, NULL, 'purchase', 'attributed', p_platform, v_claim.id, v_rc.id, p_order_key, v_email, v_phone)
  RETURNING id INTO v_ledger_id;
  UPDATE public.referral_claim SET status = 'completed', ledger_id = v_ledger_id, completed_at = now(), updated_at = now() WHERE id = v_claim.id;
  IF v_rc.id IS NOT NULL THEN
    UPDATE public.referral_code SET status = 'used', updated_at = now() WHERE id = v_rc.id;
  ELSIF array_length(v_codes, 1) IS NOT NULL THEN
    UPDATE public.referral_code SET status = 'used', updated_at = now() WHERE claim_id = v_claim.id AND code = ANY (v_codes) AND status = 'minted';
  END IF;
  PERFORM public.chokepoint_post_referral_event(
    'applied', p_merchant_id, v_claim.referrer_user_id, v_ledger_id, v_claim.id, 'referrer');
  v_qualify := CASE p_platform
    WHEN 'shopify' THEN lower(COALESCE(p_payment_status, p_order_status, '')) IN ('paid', 'partially_paid', 'authorized')
    WHEN 'shopee' THEN upper(COALESCE(p_order_status, '')) = 'COMPLETED'
    ELSE false END;
  IF v_qualify THEN RETURN public.fn_settle_referral(v_ledger_id); END IF;
  RETURN jsonb_build_object('success', true, 'code', 'ATTRIBUTED', 'ledger_id', v_ledger_id);
EXCEPTION WHEN unique_violation THEN
  RETURN jsonb_build_object('success', true, 'code', 'IDEMPOTENT');
END;
$function$;

INSERT INTO public.notification_event_catalog (
  event_key, sub_event, source_topic, description,
  available_fields, default_selected_fields, default_enabled, default_enabled_email, is_active
) VALUES
  (
    'referral', 'completed', 'crm.events.referral',
    'Referrer rewarded for a successful referral',
    '["kind","status","platform","invite_code"]'::jsonb,
    '["kind","status"]'::jsonb,
    true, false, true
  ),
  (
    'referral', 'friend_rewarded', 'crm.events.referral',
    'Friend received their referral reward',
    '["kind","status","platform","invite_code"]'::jsonb,
    '["kind","status"]'::jsonb,
    true, false, true
  )
ON CONFLICT (event_key, sub_event) DO UPDATE SET
  source_topic = EXCLUDED.source_topic,
  description = EXCLUDED.description,
  available_fields = EXCLUDED.available_fields,
  default_selected_fields = EXCLUDED.default_selected_fields,
  updated_at = now();

INSERT INTO public.notification_template (
  merchant_id, event_key, sub_event, channel, is_active, flex_template, email_template
) VALUES
  (
    NULL, 'referral', 'completed', 'line', true,
    '{"type":"bubble","size":"kilo","body":{"type":"box","layout":"vertical","spacing":"md","contents":[{"type":"text","text":"Referral completed","weight":"bold","size":"lg"},{"type":"text","text":"You earned a reward for a successful referral.","wrap":true,"size":"sm","color":"#666666"},{"type":"box","layout":"baseline","spacing":"sm","_field":"kind","contents":[{"type":"text","text":"Type","size":"sm","color":"#666666","flex":0},{"type":"text","text":"${kind}","size":"sm","wrap":true,"align":"end"}]},{"type":"box","layout":"baseline","spacing":"sm","_field":"status","contents":[{"type":"text","text":"Status","size":"sm","color":"#666666","flex":0},{"type":"text","text":"${status}","size":"sm","wrap":true,"align":"end"}]}]}}'::jsonb,
    NULL
  ),
  (
    NULL, 'referral', 'friend_rewarded', 'line', true,
    '{"type":"bubble","size":"kilo","body":{"type":"box","layout":"vertical","spacing":"md","contents":[{"type":"text","text":"You received a referral reward","weight":"bold","size":"lg"},{"type":"text","text":"A friend referred you — your reward is ready.","wrap":true,"size":"sm","color":"#666666"},{"type":"box","layout":"baseline","spacing":"sm","_field":"kind","contents":[{"type":"text","text":"Type","size":"sm","color":"#666666","flex":0},{"type":"text","text":"${kind}","size":"sm","wrap":true,"align":"end"}]},{"type":"box","layout":"baseline","spacing":"sm","_field":"status","contents":[{"type":"text","text":"Status","size":"sm","color":"#666666","flex":0},{"type":"text","text":"${status}","size":"sm","wrap":true,"align":"end"}]}]}}'::jsonb,
    NULL
  ),
  (
    NULL, 'referral', 'completed', 'email', true, NULL,
    '{"subject":"You earned a referral reward","title":"Referral completed","description":"You earned a reward for a successful referral.","button":"View rewards","banner_url":null}'::jsonb
  ),
  (
    NULL, 'referral', 'friend_rewarded', 'email', true, NULL,
    '{"subject":"You received a referral reward","title":"You received a referral reward","description":"A friend referred you — your reward is ready.","button":"View rewards","banner_url":null}'::jsonb
  )
ON CONFLICT DO NOTHING;

