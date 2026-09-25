-- Referral state machine + durable Shopify reward-code delivery (outbox / Inngest).
-- Plan: shopify-loyalty/docs/SHOPIFY_REFERRAL_BUGS_FINAL_EXECUTION_PLAN.md

DO $$ BEGIN
  CREATE TYPE public.shopify_code_delivery_status AS ENUM ('pending', 'synced', 'failed');
EXCEPTION
  WHEN duplicate_object THEN NULL;
END $$;

ALTER TABLE public.reward_redemptions_ledger
  ADD COLUMN IF NOT EXISTS shopify_code_delivery_status public.shopify_code_delivery_status,
  ADD COLUMN IF NOT EXISTS shopify_code_delivery_attempts integer NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS shopify_code_delivery_last_error text,
  ADD COLUMN IF NOT EXISTS shopify_code_delivery_requested_at timestamptz,
  ADD COLUMN IF NOT EXISTS shopify_code_delivery_synced_at timestamptz,
  ADD COLUMN IF NOT EXISTS shopify_code_delivery_failed_at timestamptz;

CREATE OR REPLACE FUNCTION public.fn_reward_requires_shopify_code_delivery(p_reward_id uuid)
RETURNS boolean
LANGUAGE sql
STABLE
SET search_path TO 'public'
AS $$
  SELECT NULLIF(btrim(rm.external_id_shopify), '') IS NOT NULL
  FROM public.reward_master rm
  WHERE rm.id = p_reward_id;
$$;

CREATE OR REPLACE FUNCTION public.fn_shopify_redemption_code_member_visible(
  p_external_id_shopify text,
  p_external_ref_id text,
  p_delivery_status public.shopify_code_delivery_status
)
RETURNS boolean
LANGUAGE sql
IMMUTABLE
SET search_path TO 'public'
AS $$
  SELECT CASE
    WHEN NULLIF(btrim(p_external_id_shopify), '') IS NULL THEN true
    WHEN NULLIF(btrim(p_external_ref_id), '') IS NOT NULL THEN true
    WHEN p_delivery_status = 'synced'::public.shopify_code_delivery_status THEN true
    ELSE false
  END;
$$;

UPDATE public.reward_redemptions_ledger rrl
SET shopify_code_delivery_status = 'synced',
    shopify_code_delivery_synced_at = COALESCE(rrl.shopify_code_delivery_synced_at, rrl.created_at)
FROM public.reward_master rm
WHERE rm.id = rrl.reward_id
  AND NULLIF(btrim(rm.external_id_shopify), '') IS NOT NULL
  AND NULLIF(btrim(rrl.external_ref_id), '') IS NOT NULL
  AND rrl.shopify_code_delivery_status IS DISTINCT FROM 'synced';

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
    v_qualify := CASE p_platform
      WHEN 'shopify' THEN lower(COALESCE(p_payment_status, p_order_status, '')) IN ('paid', 'partially_paid', 'authorized')
      WHEN 'shopee' THEN upper(COALESCE(p_order_status, '')) = 'COMPLETED'
      ELSE false END;
    IF v_existing_status = 'attributed' AND v_qualify THEN
      RETURN public.fn_settle_referral(v_existing);
    END IF;
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

CREATE OR REPLACE FUNCTION public.fn_reconcile_missed_referral_purchases(p_merchant_id uuid DEFAULT NULL)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  r record;
  v_attr jsonb;
  v_attempted int := 0;
  v_attributed int := 0;
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
      AND (p_merchant_id IS NULL OR o.merchant_id = p_merchant_id)
      AND lower(COALESCE(o.payment_status, o.order_status, '')) IN ('paid', 'partially_paid', 'authorized')
      AND (
        NOT EXISTS (
          SELECT 1
          FROM public.referral_ledger rl
          WHERE rl.merchant_id = o.merchant_id
            AND rl.platform = o.platform
            AND rl.order_key = o.order_sn
            AND rl.kind = 'purchase'
        )
        OR EXISTS (
          SELECT 1
          FROM public.referral_ledger rl
          WHERE rl.merchant_id = o.merchant_id
            AND rl.platform = o.platform
            AND rl.order_key = o.order_sn
            AND rl.kind = 'purchase'
            AND rl.status = 'attributed'
        )
      )
      AND EXISTS (
        SELECT 1
        FROM public.referral_claim c
        WHERE c.merchant_id = o.merchant_id
          AND c.platform = o.platform
          AND c.completed_at IS NULL
          AND c.status IN ('open', 'expired')
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
    ORDER BY o.transaction_date ASC
    LIMIT 200
  LOOP
    v_attempted := v_attempted + 1;
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
    IF COALESCE(v_attr->>'success', 'false')::boolean
       AND (
         COALESCE(v_attr->>'code', '') IN ('OK', 'ATTRIBUTED', 'IDEMPOTENT')
         OR COALESCE(v_attr->>'code', '') LIKE 'BLOCKED_%'
       ) THEN
      v_attributed := v_attributed + 1;
    END IF;
  END LOOP;

  RETURN jsonb_build_object(
    'success', true,
    'attempted', v_attempted,
    'attributed', v_attributed
  );
END;
$$;

CREATE OR REPLACE FUNCTION public.fn_dispatch_outcome(
  p_user_id uuid,
  p_merchant_id uuid,
  p_outcome_type outcome_type_enum,
  p_entity_id uuid DEFAULT NULL::uuid,
  p_amount numeric DEFAULT NULL::numeric,
  p_source_type text DEFAULT NULL::text,
  p_source_id uuid DEFAULT NULL::uuid,
  p_metadata jsonb DEFAULT NULL::jsonb,
  p_dedup_key text DEFAULT NULL::text
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
AS $function$
DECLARE
  v_amount           numeric;
  v_window_end       timestamptz;
  v_source_enum      wallet_transaction_source_type;
  v_ticket_type_id   uuid;
  v_description      text;
  v_meta             jsonb;
  v_ledger_id        uuid;
  v_redeem_result    jsonb;
  v_redemption_id    uuid;
  v_redemption_ids   uuid[] := ARRAY[]::uuid[];
  v_ef_user_id       uuid;
  v_distribution_id  uuid;
  v_error            text;
  v_success          boolean := true;
  v_rid              uuid;
BEGIN
  v_amount := coalesce(p_amount, CASE p_outcome_type WHEN 'reward' THEN 1 ELSE 0 END);
  v_meta   := COALESCE(p_metadata, '{}'::jsonb);
  v_description := COALESCE(v_meta->>'description',
                            'Outcome from ' || COALESCE(p_source_type, 'system'));
  v_source_enum := COALESCE(p_source_type, 'campaign')::wallet_transaction_source_type;

  <<dispatch>>
  BEGIN
    CASE p_outcome_type

      WHEN 'points' THEN
        IF v_amount <= 0 THEN
          RAISE EXCEPTION 'Amount must be > 0 for points outcome';
        END IF;
        v_ledger_id := chokepoint_post_wallet_transaction(
          p_user_id,
          'points'::currency,
          v_source_enum,
          'base'::currency_component,
          'earn'::currency_transaction_type,
          v_amount::integer,
          COALESCE(p_source_id, p_user_id),
          p_merchant_id,
          v_description,
          v_meta || jsonb_build_object('source', p_source_type, 'dedup_key', p_dedup_key),
          NULL::uuid,
          p_dedup_key
        );

      WHEN 'tickets' THEN
        IF v_amount <= 0 THEN
          RAISE EXCEPTION 'Amount must be > 0 for tickets outcome';
        END IF;
        v_ticket_type_id := p_entity_id;
        IF v_ticket_type_id IS NULL THEN
          RAISE EXCEPTION 'ticket_type_id (p_entity_id) is required for tickets outcome';
        END IF;
        IF NOT EXISTS (
          SELECT 1 FROM ticket_type tt
          WHERE tt.id = v_ticket_type_id
            AND tt.merchant_id = p_merchant_id
            AND tt.active IS TRUE
        ) THEN
          RAISE EXCEPTION 'ticket_type_id % not found or inactive for merchant %',
                          v_ticket_type_id, p_merchant_id;
        END IF;
        v_ledger_id := chokepoint_post_wallet_transaction(
          p_user_id,
          'ticket'::currency,
          v_source_enum,
          'base'::currency_component,
          'earn'::currency_transaction_type,
          v_amount::integer,
          COALESCE(p_source_id, p_user_id),
          p_merchant_id,
          v_description,
          v_meta || jsonb_build_object('source', p_source_type, 'dedup_key', p_dedup_key),
          v_ticket_type_id,
          p_dedup_key
        );

      WHEN 'reward' THEN
        IF p_entity_id IS NULL THEN
          RAISE EXCEPTION 'reward_id (p_entity_id) is required for reward outcome';
        END IF;
        IF v_amount <= 0 THEN
          RAISE EXCEPTION 'quantity must be > 0 for reward outcome';
        END IF;
        SELECT redeem_reward_with_points(
                 p_reward_id    := p_entity_id,
                 p_quantity     := v_amount::integer,
                 p_user_id      := p_user_id,
                 p_merchant_id  := p_merchant_id,
                 p_mode         := 'direct',
                 p_source_type  := p_source_type,
                 p_source_id    := p_source_id
               ) INTO v_redeem_result;
        IF NOT coalesce((v_redeem_result->>'success')::boolean, false) THEN
          RAISE EXCEPTION 'redeem_reward_with_points failed: %',
                          COALESCE(v_redeem_result->>'error', v_redeem_result::text);
        END IF;
        FOR v_rid IN
          SELECT (elem->>'redemption_id')::uuid
          FROM jsonb_array_elements(COALESCE(v_redeem_result->'data'->'redemptions', '[]'::jsonb)) AS elem
          WHERE NULLIF(elem->>'redemption_id', '') IS NOT NULL
        LOOP
          v_redemption_ids := array_append(v_redemption_ids, v_rid);
        END LOOP;
        IF cardinality(v_redemption_ids) > 0 THEN
          v_redemption_id := v_redemption_ids[1];
        END IF;

      WHEN 'earn_factor' THEN
        IF p_entity_id IS NULL THEN
          RAISE EXCEPTION 'earn_factor_id (p_entity_id) is required for earn_factor outcome';
        END IF;
        v_window_end := now() + (COALESCE(NULLIF(v_meta->>'window_days',''), '30') || ' days')::interval;
        INSERT INTO earn_factor_user
          (earn_factor_id, user_id, merchant_id, window_end, source_type, source_id)
        VALUES
          (p_entity_id, p_user_id, p_merchant_id, v_window_end, p_source_type, p_source_id)
        RETURNING id INTO v_ef_user_id;

      ELSE
        RAISE EXCEPTION 'Unknown outcome_type: %', p_outcome_type;
    END CASE;
  EXCEPTION WHEN OTHERS THEN
    v_success := false;
    v_error   := SQLERRM;
  END;

  INSERT INTO outcome_distribution_log
    (user_id, merchant_id, source_type, source_id, outcome_type, entity_id, amount,
     wallet_ledger_id, redemption_id, earn_factor_user_id, success, error_message,
     distribution_metadata)
  VALUES
    (p_user_id, p_merchant_id, COALESCE(p_source_type,'system'), p_source_id, p_outcome_type,
     p_entity_id, v_amount, v_ledger_id, v_redemption_id, v_ef_user_id, v_success, v_error,
     v_meta)
  RETURNING id INTO v_distribution_id;

  RETURN jsonb_build_object(
    'success',          v_success,
    'outcome_type',     p_outcome_type,
    'transaction_id',   COALESCE(v_ledger_id, v_redemption_id),
    'wallet_ledger_id', v_ledger_id,
    'redemption_id',    v_redemption_id,
    'redemption_ids',   to_jsonb(v_redemption_ids),
    'earn_factor_user_id', v_ef_user_id,
    'distribution_id',  v_distribution_id,
    'error',            v_error
  );
END;
$function$;

-- Appended by build script: trigger, dispatch, requeue, reward history visibility

-- Appended by build script: trigger, dispatch, requeue, reward history visibility

CREATE OR REPLACE FUNCTION public.trigger_emit_redemption_event()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_event text;
  v_extras jsonb := '{}'::jsonb;
  v_skip_emit boolean := false;
  v_is_entitlement boolean;
  v_partition_key text;
  v_needs_shopify boolean;
BEGIN
  BEGIN
    v_skip_emit := COALESCE(current_setting('redemption.skip_emit', true), 'false') = 'true';
  EXCEPTION WHEN OTHERS THEN
    v_skip_emit := false;
  END;

  IF v_skip_emit THEN
    RETURN NULL;
  END IF;

  v_is_entitlement := COALESCE(NEW.source_type::text IN ('package_assignment','persona_entitlement'), false);
  v_needs_shopify := public.fn_reward_requires_shopify_code_delivery(NEW.reward_id);

  IF (TG_OP = 'INSERT') THEN
    IF v_is_entitlement THEN
      v_event := 'package_entitlement_created';
    ELSIF v_needs_shopify AND NULLIF(btrim(NEW.external_ref_id), '') IS NULL THEN
      PERFORM set_config('redemption.skip_emit', 'true', true);
      UPDATE public.reward_redemptions_ledger
      SET shopify_code_delivery_status = 'pending',
          shopify_code_delivery_requested_at = COALESCE(shopify_code_delivery_requested_at, now())
      WHERE id = NEW.id;
      PERFORM set_config('redemption.skip_emit', 'false', true);
      v_event := 'issue_requested';
    ELSE
      v_event := 'issued';
    END IF;
  ELSIF (TG_OP = 'UPDATE') THEN
    IF NEW.cancelled IS TRUE AND (OLD.cancelled IS DISTINCT FROM NEW.cancelled) THEN
      v_event := 'cancelled';
    ELSIF OLD.external_ref_id IS DISTINCT FROM NEW.external_ref_id
          AND NULLIF(btrim(NEW.external_ref_id), '') IS NOT NULL THEN
      PERFORM set_config('redemption.skip_emit', 'true', true);
      UPDATE public.reward_redemptions_ledger
      SET shopify_code_delivery_status = 'synced',
          shopify_code_delivery_synced_at = COALESCE(shopify_code_delivery_synced_at, now()),
          shopify_code_delivery_last_error = NULL
      WHERE id = NEW.id;
      PERFORM set_config('redemption.skip_emit', 'false', true);
      v_event := 'issued';
    ELSIF v_is_entitlement AND NEW.qty IS DISTINCT FROM OLD.qty THEN
      v_event := 'entitlement_total_adjusted';
      v_extras := jsonb_build_object('qty_change', NEW.qty - OLD.qty, 'qty_before', OLD.qty);
    ELSIF v_is_entitlement AND NEW.used_qty IS DISTINCT FROM OLD.used_qty THEN
      IF NEW.used_qty > OLD.used_qty THEN
        IF NEW.used_status IS TRUE
           AND (OLD.used_status IS DISTINCT FROM NEW.used_status)
           AND NEW.used_qty < NEW.qty THEN
          v_event := 'entitlement_expired';
        ELSE
          v_event := 'entitlement_used';
          v_extras := jsonb_build_object('qty_change', NEW.used_qty - OLD.used_qty);
        END IF;
      ELSE
        v_event := 'entitlement_use_reversed';
        v_extras := jsonb_build_object('qty_change', NEW.used_qty - OLD.used_qty);
      END IF;
    ELSIF OLD.used_status IS DISTINCT FROM NEW.used_status THEN
      IF NEW.used_status IS TRUE THEN
        IF v_is_entitlement AND NEW.used_qty < NEW.qty THEN
          v_event := 'entitlement_expired';
        ELSE
          v_event := 'used';
        END IF;
      ELSE
        v_event := 'unmarked_used';
      END IF;
    ELSE
      RETURN NULL;
    END IF;
  ELSE
    RETURN NULL;
  END IF;

  v_partition_key := COALESCE(NEW.user_id::text, NEW.id::text);

  PERFORM public.fn_chokepoint_emit_event(
    'crm.events.redemption',
    v_partition_key,
    jsonb_strip_nulls(jsonb_build_object(
      'event',                 v_event,
      'merchant_id',           NEW.merchant_id,
      'user_id',               NEW.user_id,
      'redemption_id',         NEW.id,
      'redemption_code',       NEW.code,
      'reward_id',             NEW.reward_id,
      'qty',                   NEW.qty,
      'used_qty',              NEW.used_qty,
      'used_at',               NEW.used_at,
      'used_store_id',         NEW.used_store_id,
      'redeemed_store_id',     NEW.redeemed_store_id,
      'fulfillment_status',    NEW.fulfillment_status,
      'use_expire_date',       NEW.use_expire_date,
      'redeemed_at',           NEW.redeemed_at,
      'redeemed_status',       NEW.redeemed_status,
      'used_status',           NEW.used_status,
      'cancelled',             NEW.cancelled,
      'cancelled_at',          NEW.cancelled_at,
      'cancelled_reason',      NEW.cancelled_reason,
      'cancelled_by',          NEW.cancelled_by,
      'source_type',           NEW.source_type::text,
      'source_id',             NEW.source_id,
      'package_assignment_id', NEW.package_assignment_id,
      'promo_code',            NEW.promo_code,
      'promo_code_id',         NEW.promo_code_id,
      'external_ref_id',       NEW.external_ref_id,
      'points_deducted',       NEW.points_deducted,
      'shopify_code_delivery_status', NEW.shopify_code_delivery_status::text,
      'occurred_at',           to_char(now() AT TIME ZONE 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS"Z"'),
      'source',                'trigger_emit_redemption_event'
    )) || COALESCE(v_extras, '{}'::jsonb)
  );

  RETURN NULL;
EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE 'trigger_emit_redemption_event: emit failed for redemption id=% event=%: %', NEW.id, COALESCE(v_event,'?'), SQLERRM;
  RETURN NULL;
END;
$function$;

CREATE OR REPLACE FUNCTION public.fn_requeue_shopify_code_delivery(p_limit integer DEFAULT 50)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_row record;
  v_count integer := 0;
BEGIN
  FOR v_row IN
    SELECT rrl.id
    FROM public.reward_redemptions_ledger rrl
    JOIN public.reward_master rm ON rm.id = rrl.reward_id
    WHERE NULLIF(btrim(rm.external_id_shopify), '') IS NOT NULL
      AND NULLIF(btrim(rrl.code), '') IS NOT NULL
      AND NULLIF(btrim(rrl.external_ref_id), '') IS NULL
      AND COALESCE(rrl.success, true) = true
      AND COALESCE(rrl.cancelled, false) = false
      AND COALESCE(rrl.shopify_code_delivery_status::text, 'pending') IN ('pending', 'failed')
    ORDER BY rrl.created_at ASC
    LIMIT greatest(p_limit, 1)
  LOOP
    PERFORM set_config('redemption.skip_emit', 'true', true);
    UPDATE public.reward_redemptions_ledger
    SET shopify_code_delivery_status = 'pending',
        shopify_code_delivery_requested_at = COALESCE(shopify_code_delivery_requested_at, now())
    WHERE id = v_row.id;
    PERFORM set_config('redemption.skip_emit', 'false', true);

    PERFORM public.fn_chokepoint_emit_event(
      'crm.events.redemption',
      v_row.id::text,
      jsonb_build_object(
        'event', 'issue_requested',
        'redemption_id', v_row.id,
        'source', 'fn_requeue_shopify_code_delivery',
        'occurred_at', to_char(now() AT TIME ZONE 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS"Z"')
      )
    );
    v_count := v_count + 1;
  END LOOP;

  RETURN jsonb_build_object('success', true, 'requeued', v_count);
END;
$function$;

REVOKE ALL ON FUNCTION public.fn_requeue_shopify_code_delivery(integer) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.fn_requeue_shopify_code_delivery(integer) TO service_role;




CREATE OR REPLACE FUNCTION public.bff_get_reward_history(p_filter text DEFAULT NULL::text, p_limit integer DEFAULT 50, p_offset integer DEFAULT 0, p_language text DEFAULT NULL::text)
 RETURNS TABLE(id uuid, title text, description text, status text, filter text, icon text, icon_bg text, image text, results jsonb, dates jsonb, details jsonb, metadata jsonb, action jsonb)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE v_merchant_id uuid; v_primary_color text; v_icon_url text; v_points_icon text; v_filter text; v_language text;
BEGIN
  v_merchant_id := get_current_merchant_id(); IF v_merchant_id IS NULL THEN RETURN; END IF;
  v_filter := NULLIF(TRIM(COALESCE(p_filter, '')), '');
  SELECT language_code INTO v_language FROM merchant_languages WHERE merchant_id = v_merchant_id AND is_default = true LIMIT 1;
  v_language := COALESCE(p_language, v_language, 'en');
  SELECT mds.primary_color INTO v_primary_color FROM merchant_display_settings mds WHERE mds.merchant_id = v_merchant_id;
  v_primary_color := COALESCE(v_primary_color, '#6366F1');
  v_icon_url := 'https://api.iconify.design/solar/gift-bold.svg?color=' || replace(v_primary_color, '#', '%23');
  v_points_icon := 'https://api.iconify.design/tabler/circle-letter-p-filled.svg?color=%23DAA520';
  RETURN QUERY
  WITH reward_trans AS (
    SELECT t.entity_id, MAX(CASE WHEN t.field_name = 'name' THEN t.translated_value END) as t_name
    FROM translations t WHERE t.entity_type = 'reward' AND t.language_code = v_language GROUP BY t.entity_id
  )
  SELECT rrl.id, COALESCE(rt.t_name, rm.name, 'Reward')::text,
    CASE WHEN public.fn_shopify_redemption_code_member_visible(rm.external_id_shopify, rrl.external_ref_id, rrl.shopify_code_delivery_status)
      THEN COALESCE(NULLIF(TRIM(rrl.promo_code), ''), rrl.code)::text ELSE ''::text END,
    (CASE WHEN rrl.used_status = true THEN 'used' WHEN rrl.redeemed_status = true AND COALESCE(rrl.used_status, false) = false AND ((rrl.use_expire_date IS NOT NULL AND rrl.use_expire_date <= NOW()) OR COALESCE(rm.active_status, true) = false OR (rm.use_expire_date IS NOT NULL AND rm.use_expire_date <= NOW())) THEN 'expired' WHEN rrl.redeemed_status = true AND COALESCE(rrl.used_status, false) = false THEN 'redeemed' ELSE 'pending' END)::text,
    (CASE WHEN rrl.used_status = true THEN 'used' WHEN rrl.redeemed_status = true AND COALESCE(rrl.used_status, false) = false AND ((rrl.use_expire_date IS NOT NULL AND rrl.use_expire_date <= NOW()) OR COALESCE(rm.active_status, true) = false OR (rm.use_expire_date IS NOT NULL AND rm.use_expire_date <= NOW())) THEN 'expired' WHEN rrl.redeemed_status = true AND COALESCE(rrl.used_status, false) = false THEN 'redeemed' ELSE 'pending' END)::text,
    v_icon_url, (v_primary_color||'26')::text, COALESCE((rm.image[1])::text, v_icon_url)::text,
    jsonb_build_array(jsonb_build_object('type','points','amount',round(-rrl.points_deducted),'label',round(rrl.points_deducted)::text,'icon',v_points_icon,'sign','negative')),
    (SELECT jsonb_agg(value) FROM jsonb_array_elements(jsonb_build_array(CASE WHEN rrl.redeemed_at IS NOT NULL THEN jsonb_build_object('key','redeemed_at','label','Redeemed','value',rrl.redeemed_at) END,CASE WHEN rrl.use_expire_date IS NOT NULL THEN jsonb_build_object('key','use_expire_date','label','Expires','value',rrl.use_expire_date) END,CASE WHEN rrl.used_at IS NOT NULL THEN jsonb_build_object('key','used_at','label','Used','value',rrl.used_at) END,jsonb_build_object('key','created_at','label','Created','value',rrl.created_at))) WHERE value IS NOT NULL AND value != 'null'::jsonb),
    (SELECT jsonb_agg(value) FROM jsonb_array_elements(jsonb_build_array(
      CASE WHEN public.fn_shopify_redemption_code_member_visible(rm.external_id_shopify, rrl.external_ref_id, rrl.shopify_code_delivery_status) AND rrl.code IS NOT NULL THEN jsonb_build_object('key','code','label','Code','value',rrl.code) END,
      CASE WHEN rrl.promo_code IS NOT NULL THEN jsonb_build_object('key','promo_code','label','Promo Code','value',rrl.promo_code) END,
      jsonb_build_object('key','qty','label','Quantity','value',rrl.qty::text),
      CASE WHEN rrl.fulfillment_status IS NOT NULL THEN jsonb_build_object('key','fulfillment_status','label','Fulfillment','value',rrl.fulfillment_status::text) END,
      CASE WHEN rm.fulfillment_method IS NOT NULL THEN jsonb_build_object('key','fulfillment_method','label','Fulfillment Method','value',rm.fulfillment_method::text) END,
      CASE WHEN rm.online_store IS NOT NULL AND array_length(rm.online_store, 1) > 0 THEN jsonb_build_object('key','online_store','label','Store','value',array_to_string(rm.online_store, ', ')) END,
      CASE WHEN rrl.selected_variants IS NOT NULL THEN jsonb_build_object('key','selected_variants','label','Variants','value',rrl.selected_variants) END)) WHERE value IS NOT NULL AND value != 'null'::jsonb),
    jsonb_build_object('reward_id', rrl.reward_id, 'fulfillment_method', rm.fulfillment_method, 'fulfillment_status', rrl.fulfillment_status, 'delivery_address', rrl.delivery_address, 'online_store', rm.online_store, 'external_ref_id', rrl.external_ref_id,
      'code', CASE WHEN public.fn_shopify_redemption_code_member_visible(rm.external_id_shopify, rrl.external_ref_id, rrl.shopify_code_delivery_status) THEN rrl.code ELSE NULL END,
      'promo_code', rrl.promo_code, 'selected_variants', rrl.selected_variants, 'shopify_code_delivery_status', rrl.shopify_code_delivery_status::text),
    CASE WHEN rrl.redeemed_status = true AND COALESCE(rrl.used_status, false) = false AND (rrl.use_expire_date IS NULL OR rrl.use_expire_date > NOW()) AND COALESCE(rm.active_status, true) = true AND (rm.use_expire_date IS NULL OR rm.use_expire_date > NOW()) AND rm.fulfillment_method = 'shipping' AND rrl.delivery_address IS NULL THEN jsonb_build_object('type', 'add_shipping_address', 'label', 'Add delivery address')
      WHEN rrl.redeemed_status = true AND COALESCE(rrl.used_status, false) = false AND (rrl.use_expire_date IS NULL OR rrl.use_expire_date > NOW()) AND COALESCE(rm.active_status, true) = true AND (rm.use_expire_date IS NULL OR rm.use_expire_date > NOW()) AND rm.fulfillment_method = 'shipping' AND rrl.delivery_address IS NOT NULL THEN jsonb_build_object('type', 'view_shipping', 'label', 'View delivery')
      WHEN rrl.redeemed_status = true AND COALESCE(rrl.used_status, false) = false AND (rrl.use_expire_date IS NULL OR rrl.use_expire_date > NOW()) AND COALESCE(rm.active_status, true) = true AND (rm.use_expire_date IS NULL OR rm.use_expire_date > NOW()) THEN jsonb_build_object('type', 'use_reward', 'label', 'Use')
      ELSE NULL END
  FROM reward_redemptions_ledger rrl LEFT JOIN reward_master rm ON rm.id = rrl.reward_id
  LEFT JOIN reward_trans rt ON rt.entity_id = rrl.reward_id
  WHERE rrl.merchant_id = v_merchant_id AND rrl.user_id = auth.uid() AND rrl.cancelled IS NOT TRUE AND (v_filter IS NULL OR (CASE WHEN rrl.used_status = true THEN 'used' WHEN rrl.redeemed_status = true AND COALESCE(rrl.used_status, false) = false AND ((rrl.use_expire_date IS NOT NULL AND rrl.use_expire_date <= NOW()) OR COALESCE(rm.active_status, true) = false OR (rm.use_expire_date IS NOT NULL AND rm.use_expire_date <= NOW())) THEN 'expired' WHEN rrl.redeemed_status = true AND COALESCE(rrl.used_status, false) = false THEN 'redeemed' ELSE 'pending' END) = v_filter)
  ORDER BY rrl.created_at DESC LIMIT p_limit OFFSET p_offset;
END; $function$;

