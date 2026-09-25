-- Referral rebuild engine: attribute / issue / settle / clawback + public claim.

CREATE OR REPLACE FUNCTION public.fn_normalize_referral_phone(p_phone text)
RETURNS text
LANGUAGE sql
IMMUTABLE
AS $$
  SELECT NULLIF(regexp_replace(COALESCE(p_phone, ''), '[^0-9]', '', 'g'), '');
$$;

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

  UPDATE public.referral_claim c
  SET status = 'expired', updated_at = now()
  WHERE c.merchant_id = p_merchant_id
    AND c.status = 'open'
    AND NOT EXISTS (
      SELECT 1 FROM public.referral_code rc
      WHERE rc.claim_id = c.id AND rc.status IN ('pending_mint', 'minted')
    );
END;
$$;

CREATE OR REPLACE FUNCTION public.fn_is_referral_program_active(p_merchant_id uuid)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path TO 'public'
AS $$
  SELECT EXISTS (
    SELECT 1
    FROM public.referral_program rp
    WHERE rp.merchant_id = p_merchant_id
      AND rp.is_active = true
      AND (rp.signup_enabled = true OR rp.purchase_enabled = true)
  );
$$;

CREATE OR REPLACE FUNCTION public.fn_process_referral_rewards(p_ledger_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  v_ledger record;
  v_outcome record;
  v_target_user_id uuid;
  v_result jsonb;
  v_meta jsonb;
  v_dedup text;
  v_kind text;
BEGIN
  SELECT * INTO v_ledger FROM public.referral_ledger WHERE id = p_ledger_id;
  IF NOT FOUND THEN RETURN; END IF;

  v_kind := COALESCE(v_ledger.kind, 'signup');

  IF EXISTS (
    SELECT 1 FROM public.outcome_distribution_log odl
    WHERE odl.source_type = 'referral'
      AND odl.source_id = p_ledger_id
      AND odl.success = true
  ) THEN
    RETURN;
  END IF;

  FOR v_outcome IN
    SELECT * FROM public.referral_outcomes
    WHERE merchant_id = v_ledger.merchant_id
      AND COALESCE(kind, 'signup') = v_kind
      AND (
        v_kind = 'signup'
        OR (v_kind = 'purchase' AND party = 'inviter')
      )
    ORDER BY party, created_at, id
  LOOP
    v_target_user_id := CASE v_outcome.party
      WHEN 'invitee' THEN v_ledger.invitee_user_id
      WHEN 'inviter' THEN v_ledger.inviter_user_id
      ELSE NULL
    END;
    IF v_target_user_id IS NULL THEN CONTINUE; END IF;

    v_dedup := format('referral:%s:%s:%s', p_ledger_id, v_outcome.party, v_outcome.id);
    v_meta := jsonb_build_object(
      'party', v_outcome.party,
      'kind', v_kind,
      'referral_outcome_id', v_outcome.id,
      'inviter_user_id', v_ledger.inviter_user_id,
      'invitee_user_id', v_ledger.invitee_user_id,
      'invite_code', v_ledger.invite_code,
      'description', format('Referral %s %s reward', v_kind, v_outcome.party)
    );
    IF v_outcome.valid_for_days IS NOT NULL THEN
      v_meta := v_meta || jsonb_build_object('window_days', v_outcome.valid_for_days::text);
    END IF;

    v_result := public.fn_dispatch_outcome(
      p_user_id := v_target_user_id,
      p_merchant_id := v_ledger.merchant_id,
      p_outcome_type := v_outcome.outcome_type,
      p_entity_id := v_outcome.entity_id,
      p_amount := v_outcome.amount,
      p_source_type := 'referral',
      p_source_id := p_ledger_id,
      p_metadata := v_meta,
      p_dedup_key := v_dedup
    );
    IF NOT COALESCE((v_result->>'success')::boolean, false) THEN
      RAISE WARNING 'Referral outcome failed ledger=% outcome=%: %',
        p_ledger_id, v_outcome.id, COALESCE(v_result->>'error', v_result::text);
    END IF;
  END LOOP;
END;
$$;

CREATE OR REPLACE FUNCTION public.fn_settle_referral(p_ledger_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  v_ledger record;
BEGIN
  SELECT * INTO v_ledger FROM public.referral_ledger WHERE id = p_ledger_id FOR UPDATE;
  IF NOT FOUND THEN
    RETURN jsonb_build_object('success', false, 'code', 'NOT_FOUND');
  END IF;
  IF v_ledger.status = 'settled' THEN
    RETURN jsonb_build_object('success', true, 'code', 'ALREADY_SETTLED', 'ledger_id', p_ledger_id);
  END IF;
  IF v_ledger.status = 'clawed_back' THEN
    RETURN jsonb_build_object('success', false, 'code', 'CLAWED_BACK', 'ledger_id', p_ledger_id);
  END IF;

  PERFORM public.fn_process_referral_rewards(p_ledger_id);

  UPDATE public.referral_ledger
  SET status = 'settled', settled_at = COALESCE(settled_at, now()), updated_at = now()
  WHERE id = p_ledger_id;

  RETURN jsonb_build_object('success', true, 'code', 'SETTLED', 'ledger_id', p_ledger_id);
END;
$$;

CREATE OR REPLACE FUNCTION public.fn_clawback_referral(p_ledger_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  v_ledger record;
  v_log record;
BEGIN
  SELECT * INTO v_ledger FROM public.referral_ledger WHERE id = p_ledger_id FOR UPDATE;
  IF NOT FOUND THEN
    RETURN jsonb_build_object('success', false, 'code', 'NOT_FOUND');
  END IF;
  IF v_ledger.status = 'clawed_back' THEN
    RETURN jsonb_build_object('success', true, 'code', 'ALREADY_CLAWED', 'ledger_id', p_ledger_id);
  END IF;

  FOR v_log IN
    SELECT * FROM public.outcome_distribution_log
    WHERE source_type = 'referral' AND source_id = p_ledger_id AND success = true
  LOOP
    BEGIN
      IF v_log.outcome_type::text = 'points' AND v_log.amount IS NOT NULL THEN
        PERFORM public.reverse_points(
          v_log.user_id, v_ledger.merchant_id, v_log.amount::integer,
          'referral_clawback', p_ledger_id
        );
      ELSIF v_log.outcome_type::text = 'tickets' AND v_log.entity_id IS NOT NULL AND v_log.amount IS NOT NULL THEN
        PERFORM public.reverse_tickets(
          v_log.user_id, v_ledger.merchant_id, v_log.entity_id, v_log.amount::integer,
          'referral_clawback', p_ledger_id
        );
      END IF;
    EXCEPTION WHEN OTHERS THEN
      RAISE WARNING 'Referral clawback reverse failed ledger=% log=%: %', p_ledger_id, v_log.id, SQLERRM;
    END;
  END LOOP;

  UPDATE public.referral_ledger
  SET status = 'clawed_back', clawed_back_at = now(), updated_at = now()
  WHERE id = p_ledger_id;

  RETURN jsonb_build_object('success', true, 'code', 'CLAWED', 'ledger_id', p_ledger_id);
END;
$$;

CREATE OR REPLACE FUNCTION public.fn_attribute_referral(
  p_kind text,
  p_merchant_id uuid DEFAULT NULL,
  p_invitee_user_id uuid DEFAULT NULL,
  p_invite_code text DEFAULT NULL,
  p_platform text DEFAULT NULL,
  p_order_key text DEFAULT NULL,
  p_order_status text DEFAULT NULL,
  p_payment_status text DEFAULT NULL,
  p_buyer_email text DEFAULT NULL,
  p_buyer_phone text DEFAULT NULL,
  p_buyer_external_id text DEFAULT NULL,
  p_codes text[] DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  v_program public.referral_program;
  v_invitee record;
  v_inviter record;
  v_ledger_id uuid;
  v_existing uuid;
  v_limit record;
  v_limit_window timestamptz;
  v_used numeric;
  v_code text;
  v_claim public.referral_claim;
  v_rc public.referral_code;
  v_email text;
  v_phone text;
  v_codes text[];
  v_cancel boolean;
  v_qualify boolean;
  v_status text;
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
    IF NOT FOUND THEN
      RETURN jsonb_build_object('success', false, 'code', 'INVITEE_NOT_FOUND', 'error', 'Invitee user not found');
    END IF;

    SELECT * INTO v_program FROM public.referral_program WHERE merchant_id = v_invitee.merchant_id;
    IF v_program.id IS NULL OR NOT v_program.is_active OR NOT v_program.signup_enabled THEN
      RETURN jsonb_build_object('success', false, 'code', 'REFERRAL_INACTIVE', 'error', 'Referral program inactive');
    END IF;

    SELECT * INTO v_inviter
    FROM public.user_accounts
    WHERE merchant_id = v_invitee.merchant_id AND member_code = v_code;
    IF NOT FOUND THEN
      RETURN jsonb_build_object('success', false, 'code', 'INVALID_INVITE_CODE', 'error', 'Invalid invite code');
    END IF;
    IF v_inviter.id = v_invitee.id THEN
      RETURN jsonb_build_object('success', false, 'code', 'SELF_REFERRAL', 'error', 'Cannot refer yourself');
    END IF;
    IF EXISTS (
      SELECT 1 FROM public.referral_ledger
      WHERE invitee_user_id = p_invitee_user_id AND merchant_id = v_invitee.merchant_id AND kind = 'signup'
    ) THEN
      RETURN jsonb_build_object('success', false, 'code', 'ALREADY_REFERRED', 'error', 'User already referred');
    END IF;

    FOR v_limit IN
      SELECT * FROM public.transaction_limits
      WHERE merchant_id = v_invitee.merchant_id
        AND entity_type = 'referral' AND entity_id IS NULL
        AND COALESCE(active_status, true)
        AND (window_start IS NULL OR window_start <= now())
        AND (window_end IS NULL OR window_end >= now())
    LOOP
      v_limit_window := CASE v_limit.time_unit
        WHEN 'day' THEN date_trunc('day', now())
        WHEN 'week' THEN date_trunc('week', now())
        WHEN 'month' THEN date_trunc('month', now())
        WHEN 'year' THEN date_trunc('year', now())
        ELSE NULL
      END;
      IF v_limit.scope = 'user' THEN
        SELECT COUNT(*)::numeric INTO v_used FROM public.referral_ledger rl
        WHERE rl.inviter_user_id = v_inviter.id AND rl.merchant_id = v_invitee.merchant_id
          AND rl.kind = 'signup'
          AND (v_limit_window IS NULL OR rl.created_at >= v_limit_window);
      ELSIF v_limit.scope = 'total' THEN
        SELECT COUNT(*)::numeric INTO v_used FROM public.referral_ledger rl
        WHERE rl.merchant_id = v_invitee.merchant_id AND rl.kind = 'signup'
          AND (v_limit_window IS NULL OR rl.created_at >= v_limit_window);
      ELSE
        CONTINUE;
      END IF;
      IF v_used >= v_limit.count THEN
        RETURN jsonb_build_object(
          'success', false, 'code', 'LIMIT_EXCEEDED', 'error', 'Referral limit exceeded',
          'limit_scope', v_limit.scope, 'time_unit', v_limit.time_unit, 'count', v_limit.count, 'used', v_used
        );
      END IF;
    END LOOP;

    INSERT INTO public.referral_ledger (
      merchant_id, inviter_user_id, invitee_user_id, invite_code, signed_up_at,
      kind, status, settled_at
    ) VALUES (
      v_invitee.merchant_id, v_inviter.id, p_invitee_user_id, v_code, now(),
      'signup', 'settled', now()
    ) RETURNING id INTO v_ledger_id;

    PERFORM public.fn_process_referral_rewards(v_ledger_id);
    RETURN jsonb_build_object(
      'success', true, 'code', 'OK', 'ledger_id', v_ledger_id,
      'inviter_user_id', v_inviter.id, 'invitee_user_id', p_invitee_user_id
    );
  END IF;

  -- purchase
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

  SELECT id INTO v_existing
  FROM public.referral_ledger
  WHERE merchant_id = p_merchant_id AND kind = 'purchase' AND platform = p_platform AND order_key = p_order_key
  LIMIT 1;

  v_cancel := lower(COALESCE(p_order_status, '')) IN ('cancelled', 'canceled', 'refunded', 'voided', 'in_cancel', 'to_return', 'returned')
    OR lower(COALESCE(p_payment_status, '')) IN ('refunded', 'voided', 'cancelled');

  IF v_existing IS NOT NULL THEN
    IF v_cancel THEN
      RETURN public.fn_clawback_referral(v_existing);
    END IF;
    RETURN jsonb_build_object('success', true, 'code', 'IDEMPOTENT', 'ledger_id', v_existing);
  END IF;

  IF v_cancel THEN
    RETURN jsonb_build_object('success', false, 'code', 'MISS');
  END IF;

  -- SMART: open claim matching buyer, else minted code on the order
  IF v_email IS NOT NULL THEN
    SELECT * INTO v_claim FROM public.referral_claim
    WHERE merchant_id = p_merchant_id AND platform = p_platform AND status = 'open'
      AND friend_email = v_email
    ORDER BY created_at ASC LIMIT 1;
  END IF;
  IF v_claim.id IS NULL AND v_phone IS NOT NULL THEN
    SELECT * INTO v_claim FROM public.referral_claim
    WHERE merchant_id = p_merchant_id AND platform = p_platform AND status = 'open'
      AND friend_phone = v_phone
    ORDER BY created_at ASC LIMIT 1;
  END IF;
  IF v_claim.id IS NULL AND NULLIF(p_buyer_external_id, '') IS NOT NULL THEN
    SELECT * INTO v_claim FROM public.referral_claim
    WHERE merchant_id = p_merchant_id AND platform = p_platform AND status = 'open'
      AND friend_shopify_customer_id = p_buyer_external_id
    ORDER BY created_at ASC LIMIT 1;
  END IF;
  IF v_claim.id IS NULL AND array_length(v_codes, 1) IS NOT NULL THEN
    SELECT rc.* INTO v_rc FROM public.referral_code rc
    WHERE rc.merchant_id = p_merchant_id AND rc.platform = p_platform
      AND rc.status IN ('minted', 'used')
      AND rc.code = ANY (v_codes)
    ORDER BY rc.created_at ASC LIMIT 1;
    IF v_rc.id IS NOT NULL THEN
      SELECT * INTO v_claim FROM public.referral_claim WHERE id = v_rc.claim_id;
    END IF;
  END IF;

  IF v_claim.id IS NULL THEN
    RETURN jsonb_build_object('success', false, 'code', 'MISS');
  END IF;

  -- First qualifying order per claim
  IF EXISTS (
    SELECT 1 FROM public.referral_ledger
    WHERE claim_id = v_claim.id AND kind = 'purchase' AND status IN ('attributed', 'settled')
  ) THEN
    RETURN jsonb_build_object('success', false, 'code', 'CLAIM_ALREADY_USED');
  END IF;

  INSERT INTO public.referral_ledger (
    merchant_id, inviter_user_id, invite_code, kind, status, platform,
    claim_id, code_id, order_key, friend_email, friend_phone
  ) VALUES (
    p_merchant_id, v_claim.referrer_user_id, NULL, 'purchase', 'attributed', p_platform,
    v_claim.id, v_rc.id, p_order_key, v_email, v_phone
  ) RETURNING id INTO v_ledger_id;

  UPDATE public.referral_claim
  SET status = 'completed', ledger_id = v_ledger_id, completed_at = now(), updated_at = now()
  WHERE id = v_claim.id;

  IF v_rc.id IS NOT NULL THEN
    UPDATE public.referral_code SET status = 'used', updated_at = now() WHERE id = v_rc.id;
  ELSIF array_length(v_codes, 1) IS NOT NULL THEN
    UPDATE public.referral_code
    SET status = 'used', updated_at = now()
    WHERE claim_id = v_claim.id AND code = ANY (v_codes) AND status = 'minted';
  END IF;

  v_qualify := CASE p_platform
    WHEN 'shopify' THEN lower(COALESCE(p_payment_status, p_order_status, '')) IN ('paid', 'partially_paid', 'authorized')
    WHEN 'shopee' THEN upper(COALESCE(p_order_status, '')) = 'COMPLETED'
    ELSE false
  END;

  IF v_qualify THEN
    RETURN public.fn_settle_referral(v_ledger_id);
  END IF;

  RETURN jsonb_build_object('success', true, 'code', 'ATTRIBUTED', 'ledger_id', v_ledger_id);
EXCEPTION WHEN unique_violation THEN
  RETURN jsonb_build_object('success', true, 'code', 'IDEMPOTENT');
END;
$$;

CREATE OR REPLACE FUNCTION public.fn_process_referral_signup(
  p_invitee_user_id uuid,
  p_invite_code character varying
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
BEGIN
  RETURN public.fn_attribute_referral(
    p_kind := 'signup',
    p_invitee_user_id := p_invitee_user_id,
    p_invite_code := p_invite_code
  );
END;
$$;

CREATE OR REPLACE FUNCTION public.fn_issue_referral_code(
  p_merchant_id uuid,
  p_claim_id uuid,
  p_platform text,
  p_ttl_hours integer DEFAULT 24
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  v_claim public.referral_claim;
  v_alphabet text := 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
  v_len int;
  v_code text;
  v_i int;
  v_try int;
  v_expires timestamptz;
  v_id uuid;
BEGIN
  SELECT * INTO v_claim FROM public.referral_claim WHERE id = p_claim_id AND merchant_id = p_merchant_id;
  IF NOT FOUND THEN
    RETURN jsonb_build_object('success', false, 'code', 'CLAIM_NOT_FOUND');
  END IF;

  v_len := CASE WHEN p_platform = 'shopee' THEN 5 ELSE 10 END;
  v_expires := now() + make_interval(hours => GREATEST(COALESCE(p_ttl_hours, 24), 1));

  FOR v_try IN 1..8 LOOP
    v_code := '';
    FOR v_i IN 1..v_len LOOP
      v_code := v_code || substr(v_alphabet, 1 + floor(random() * length(v_alphabet))::int, 1);
    END LOOP;
    BEGIN
      INSERT INTO public.referral_code (
        merchant_id, claim_id, referrer_user_id, platform, code, expires_at, status
      ) VALUES (
        p_merchant_id, p_claim_id, v_claim.referrer_user_id, p_platform, v_code, v_expires, 'pending_mint'
      ) RETURNING id INTO v_id;
      RETURN jsonb_build_object(
        'success', true, 'code', 'OK',
        'referral_code_id', v_id,
        'commerce_code', v_code,
        'expires_at', v_expires
      );
    EXCEPTION WHEN unique_violation THEN
      CONTINUE;
    END;
  END LOOP;

  RETURN jsonb_build_object('success', false, 'code', 'CODE_COLLISION');
END;
$$;
