-- Referral: decouple friend-code TTL from purchase attribution window (30 days).
-- Friend discount codes may expire; claims stay attributable until the window ends.

CREATE OR REPLACE FUNCTION public.fn_expire_stale_referral_codes(p_merchant_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
BEGIN
  UPDATE public.referral_code
  SET status = 'expired', updated_at = now()
  WHERE merchant_id = p_merchant_id
    AND status IN ('pending_mint', 'minted')
    AND expires_at <= now();

  -- Expire claims only after the full attribution window, not when the friend code TTL ends.
  UPDATE public.referral_claim c
  SET status = 'expired', updated_at = now()
  WHERE c.merchant_id = p_merchant_id
    AND c.status = 'open'
    AND c.created_at <= now() - interval '30 days'
    AND NOT EXISTS (
      SELECT 1
      FROM public.referral_ledger rl
      WHERE rl.claim_id = c.id
        AND rl.kind = 'purchase'
        AND rl.status IN ('attributed', 'settled', 'blocked')
    );
END;
$$;

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
  p_codes text[] DEFAULT NULL::text[],
  p_buyer_orders_count integer DEFAULT NULL::integer
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
  v_cancel boolean; v_qualify boolean; v_block_reason text; v_canon text; v_existing_status text;
  v_attrib_window interval := interval '30 days';
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
    IF public.fn_canonicalize_email(v_inviter.email) IS NOT NULL
       AND public.fn_canonicalize_email(v_invitee.email) = public.fn_canonicalize_email(v_inviter.email) THEN
      RETURN jsonb_build_object('success', false, 'code', 'SELF_REFERRAL', 'error', 'Cannot refer yourself');
    END IF;
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
  v_canon := public.fn_canonicalize_email(v_email);
  v_phone := public.fn_normalize_referral_phone(p_buyer_phone);
  v_codes := COALESCE(p_codes, '{}'::text[]);
  SELECT id, status INTO v_existing, v_existing_status FROM public.referral_ledger
  WHERE merchant_id = p_merchant_id AND kind = 'purchase' AND platform = p_platform AND order_key = p_order_key LIMIT 1;
  v_cancel := lower(COALESCE(p_order_status, '')) IN ('cancelled', 'canceled', 'refunded', 'voided', 'in_cancel', 'to_return', 'returned')
    OR lower(COALESCE(p_payment_status, '')) IN ('refunded', 'voided', 'cancelled');
  IF v_existing IS NOT NULL THEN
    IF v_existing_status = 'blocked' THEN
      RETURN jsonb_build_object('success', true, 'code', COALESCE((SELECT block_reason FROM public.referral_ledger WHERE id = v_existing), 'BLOCKED'), 'ledger_id', v_existing);
    END IF;
    IF v_cancel THEN RETURN public.fn_clawback_referral(v_existing); END IF;
    RETURN jsonb_build_object('success', true, 'code', 'IDEMPOTENT', 'ledger_id', v_existing);
  END IF;
  IF v_cancel THEN RETURN jsonb_build_object('success', false, 'code', 'MISS'); END IF;
  IF v_canon IS NOT NULL THEN
    SELECT * INTO v_claim FROM public.referral_claim
    WHERE merchant_id = p_merchant_id AND platform = p_platform
      AND status IN ('open', 'expired')
      AND completed_at IS NULL
      AND created_at > now() - v_attrib_window
      AND public.fn_canonicalize_email(friend_email) = v_canon
    ORDER BY created_at ASC LIMIT 1;
  END IF;
  IF v_claim.id IS NULL AND v_phone IS NOT NULL THEN
    SELECT * INTO v_claim FROM public.referral_claim
    WHERE merchant_id = p_merchant_id AND platform = p_platform
      AND status IN ('open', 'expired')
      AND completed_at IS NULL
      AND created_at > now() - v_attrib_window
      AND friend_phone = v_phone
    ORDER BY created_at ASC LIMIT 1;
  END IF;
  IF v_claim.id IS NULL AND NULLIF(p_buyer_external_id, '') IS NOT NULL THEN
    SELECT * INTO v_claim FROM public.referral_claim
    WHERE merchant_id = p_merchant_id AND platform = p_platform
      AND status IN ('open', 'expired')
      AND completed_at IS NULL
      AND created_at > now() - v_attrib_window
      AND friend_shopify_customer_id = p_buyer_external_id
    ORDER BY created_at ASC LIMIT 1;
  END IF;
  IF v_claim.id IS NULL AND array_length(v_codes, 1) IS NOT NULL THEN
    SELECT rc.* INTO v_rc FROM public.referral_code rc
    INNER JOIN public.referral_claim c ON c.id = rc.claim_id
    WHERE rc.merchant_id = p_merchant_id AND rc.platform = p_platform
      AND rc.status IN ('minted', 'used', 'expired')
      AND rc.code = ANY (v_codes)
      AND c.completed_at IS NULL
      AND c.created_at > now() - v_attrib_window
    ORDER BY rc.created_at ASC LIMIT 1;
    IF v_rc.id IS NOT NULL THEN SELECT * INTO v_claim FROM public.referral_claim WHERE id = v_rc.claim_id; END IF;
  END IF;
  IF v_claim.id IS NULL THEN RETURN jsonb_build_object('success', false, 'code', 'MISS'); END IF;
  IF EXISTS (SELECT 1 FROM public.referral_ledger WHERE claim_id = v_claim.id AND kind = 'purchase' AND status IN ('attributed', 'settled', 'blocked')) THEN
    RETURN jsonb_build_object('success', false, 'code', 'CLAIM_ALREADY_USED');
  END IF;

  SELECT * INTO v_inviter FROM public.user_accounts WHERE id = v_claim.referrer_user_id;
  v_block_reason := NULL;
  IF v_inviter.id IS NOT NULL THEN
    IF v_canon IS NOT NULL AND public.fn_canonicalize_email(v_inviter.email) = v_canon THEN
      v_block_reason := 'BLOCKED_SELF';
    ELSIF v_phone IS NOT NULL AND public.fn_normalize_referral_phone(v_inviter.tel) = v_phone THEN
      v_block_reason := 'BLOCKED_SELF';
    ELSIF NULLIF(p_buyer_external_id, '') IS NOT NULL AND (
      COALESCE(v_inviter.marketplace_external_ids->>'shopify', '') = p_buyer_external_id
      OR COALESCE(v_inviter.external_user_id, '') = p_buyer_external_id
    ) THEN
      v_block_reason := 'BLOCKED_SELF';
    END IF;
  END IF;
  IF v_block_reason IS NULL THEN
    IF COALESCE(p_buyer_orders_count, 0) >= 2 THEN
      v_block_reason := 'BLOCKED_EXISTING';
    ELSIF EXISTS (
      SELECT 1 FROM public.order_ledger_mkp o
      WHERE o.merchant_id = p_merchant_id
        AND o.platform = p_platform
        AND o.order_sn IS DISTINCT FROM p_order_key
        AND lower(COALESCE(o.order_status, '')) NOT IN ('cancelled', 'canceled', 'refunded', 'voided', 'in_cancel', 'to_return', 'returned')
        AND (
          (v_canon IS NOT NULL AND public.fn_canonicalize_email(o.buyer_email) = v_canon)
          OR (NULLIF(p_buyer_external_id, '') IS NOT NULL AND o.external_user_id = p_buyer_external_id)
        )
    ) THEN
      v_block_reason := 'BLOCKED_EXISTING';
    END IF;
  END IF;

  INSERT INTO public.referral_ledger (merchant_id, inviter_user_id, invite_code, kind, status, platform, claim_id, code_id, order_key, friend_email, friend_phone, block_reason)
  VALUES (
    p_merchant_id, v_claim.referrer_user_id, NULL, 'purchase',
    CASE WHEN v_block_reason IS NOT NULL THEN 'blocked' ELSE 'attributed' END,
    p_platform, v_claim.id, v_rc.id, p_order_key, v_email, v_phone, v_block_reason
  )
  RETURNING id INTO v_ledger_id;
  UPDATE public.referral_claim SET status = 'completed', ledger_id = v_ledger_id, completed_at = now(), updated_at = now() WHERE id = v_claim.id;
  IF v_rc.id IS NOT NULL THEN
    UPDATE public.referral_code SET status = 'used', updated_at = now() WHERE id = v_rc.id;
  ELSIF array_length(v_codes, 1) IS NOT NULL THEN
    UPDATE public.referral_code SET status = 'used', updated_at = now()
    WHERE claim_id = v_claim.id AND code = ANY (v_codes) AND status IN ('minted', 'expired');
  END IF;
  IF v_block_reason IS NOT NULL THEN
    RETURN jsonb_build_object('success', true, 'code', v_block_reason, 'ledger_id', v_ledger_id);
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

-- Re-open claims that were expired only because the friend code TTL ended.
UPDATE public.referral_claim
SET status = 'open', updated_at = now()
WHERE status = 'expired'
  AND completed_at IS NULL
  AND created_at > now() - interval '30 days';

-- Re-attribute qualifying Shopify orders that were missed while claims were expired.
DO $repair$
DECLARE
  r record;
  v_attr jsonb;
BEGIN
  FOR r IN
    SELECT
      o.merchant_id,
      o.platform,
      o.order_sn,
      o.order_status,
      o.payment_status,
      o.buyer_email,
      o.buyer_phone,
      o.external_user_id,
      o.discount_codes
    FROM public.order_ledger_mkp o
    WHERE o.platform = 'shopify'
      AND lower(COALESCE(o.payment_status, o.order_status, '')) IN ('paid', 'partially_paid', 'authorized')
      AND NOT EXISTS (
        SELECT 1
        FROM public.referral_ledger rl
        WHERE rl.merchant_id = o.merchant_id
          AND rl.platform = o.platform
          AND rl.order_key = o.order_sn
          AND rl.kind = 'purchase'
      )
      AND EXISTS (
        SELECT 1
        FROM public.referral_claim c
        WHERE c.merchant_id = o.merchant_id
          AND c.platform = o.platform
          AND c.completed_at IS NULL
          AND c.created_at > now() - interval '30 days'
          AND (
            (o.buyer_email IS NOT NULL AND public.fn_canonicalize_email(c.friend_email) = public.fn_canonicalize_email(o.buyer_email))
            OR (
              o.discount_codes IS NOT NULL
              AND EXISTS (
                SELECT 1
                FROM public.referral_code rc
                WHERE rc.claim_id = c.id AND rc.code = ANY (o.discount_codes)
              )
            )
          )
      )
  LOOP
    v_attr := public.fn_attribute_referral(
      p_kind := 'purchase',
      p_merchant_id := r.merchant_id,
      p_platform := r.platform,
      p_order_key := r.order_sn,
      p_order_status := r.order_status,
      p_payment_status := r.payment_status,
      p_buyer_email := r.buyer_email,
      p_buyer_phone := r.buyer_phone,
      p_buyer_external_id := r.external_user_id,
      p_codes := COALESCE(r.discount_codes, '{}'::text[])
    );
    RAISE NOTICE 'referral_repair order_sn=% result=%', r.order_sn, v_attr;
  END LOOP;
END
$repair$;
