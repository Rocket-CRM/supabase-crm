-- Referral fraud gates: canonical self-email, disposable domains, existing shopper,
-- withhold referrer payout when the buyer is the referrer or not a first order.

CREATE TABLE IF NOT EXISTS public.disposable_email_domains (
  domain text PRIMARY KEY
);

ALTER TABLE public.disposable_email_domains ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.disposable_email_domains FROM PUBLIC, anon, authenticated;
GRANT SELECT ON public.disposable_email_domains TO service_role;

INSERT INTO public.disposable_email_domains (domain) VALUES
  ('0-mail.com'),('10minutemail.com'),('10minutemail.net'),('10minemail.com'),
  ('1secmail.com'),('20minutemail.com'),('33mail.com'),('anonbox.net'),
  ('bccto.me'),('burnermail.io'),('byom.de'),('ccmail.uk'),
  ('discard.email'),('discardmail.com'),('dispostable.com'),('dodgeit.com'),
  ('emailondeck.com'),('fakeinbox.com'),('fakemailgenerator.com'),('fakemail.net'),
  ('getairmail.com'),('getnada.com'),('gettempmail.com'),('ghostmail.com'),
  ('guerrillamail.com'),('guerrillamail.de'),('guerrillamail.net'),('guerrillamail.org'),
  ('guerrillamailblock.com'),('grr.la'),('sharklasers.com'),('pokemail.net'),
  ('spam4.me'),('inboxkitten.com'),('incognitomail.org'),('jetable.org'),
  ('mailcatch.com'),('maildrop.cc'),('mailinator.com'),('mailinator.net'),
  ('mailinator.org'),('mailinator2.com'),('mailnesia.com'),('mailnull.com'),
  ('mailtemp.info'),('meltmail.com'),('mintemail.com'),('mohmal.com'),
  ('mytemp.email'),('nada.email'),('nowmymail.com'),('putthisinyourspamdatabase.com'),
  ('sharklasers.com'),('spamgourmet.com'),('spamhole.com'),('spamavert.com'),
  ('temp-mail.org'),('temp-mail.io'),('tempail.com'),('tempinbox.com'),
  ('tempmail.com'),('tempmail.dev'),('tempmail.ninja'),('tempmailo.com'),
  ('tempr.email'),('throwaway.email'),('throwawaymail.com'),('trash-mail.com'),
  ('trashmail.com'),('trashmail.net'),('trashmail.org'),('yopmail.com'),
  ('yopmail.fr'),('yopmail.net'),('minutemail.com'),
  ('minuteinbox.com'),('emailfake.com'),('generator.email'),('tmpmail.org'),
  ('tmpeml.com'),('tmpbox.net'),('moakt.com'),('moakt.cc'),
  ('dropmail.me'),('einrot.com'),('emkei.cz'),('fakemailgenerator.net'),
  ('getnada.net'),('harakirimail.com'),('mailforspam.com'),('mailinator.co.uk'),
  ('mintemail.net'),('tempmailaddress.com'),('temporary-mail.net'),('trashymail.com')
ON CONFLICT (domain) DO NOTHING;

CREATE OR REPLACE FUNCTION public.fn_canonicalize_email(p_email text)
RETURNS text
LANGUAGE plpgsql
IMMUTABLE
SET search_path TO 'public'
AS $function$
DECLARE
  v text;
  v_at int;
  v_local text;
  v_domain text;
BEGIN
  v := lower(btrim(COALESCE(p_email, '')));
  IF v = '' THEN RETURN NULL; END IF;
  v_at := position('@' IN v);
  IF v_at < 2 THEN RETURN v; END IF;
  v_local := left(v, v_at - 1);
  v_domain := substring(v FROM v_at + 1);
  IF v_domain = '' THEN RETURN v; END IF;
  IF position('+' IN v_local) > 0 THEN
    v_local := split_part(v_local, '+', 1);
  END IF;
  IF v_domain IN ('gmail.com', 'googlemail.com') THEN
    v_local := replace(v_local, '.', '');
    v_domain := 'gmail.com';
  END IF;
  IF v_local = '' THEN RETURN NULL; END IF;
  RETURN v_local || '@' || v_domain;
END;
$function$;

CREATE OR REPLACE FUNCTION public.fn_is_disposable_email(p_email text)
RETURNS boolean
LANGUAGE plpgsql
STABLE
SET search_path TO 'public'
AS $function$
DECLARE
  v_domain text;
  v_labels text[];
  v_parent text;
BEGIN
  v_domain := lower(btrim(split_part(COALESCE(p_email, ''), '@', 2)));
  IF v_domain = '' THEN RETURN false; END IF;
  IF EXISTS (SELECT 1 FROM public.disposable_email_domains d WHERE d.domain = v_domain) THEN
    RETURN true;
  END IF;
  v_labels := string_to_array(v_domain, '.');
  IF array_length(v_labels, 1) >= 3 THEN
    v_parent := v_labels[array_length(v_labels, 1) - 1] || '.' || v_labels[array_length(v_labels, 1)];
    IF EXISTS (SELECT 1 FROM public.disposable_email_domains d WHERE d.domain = v_parent) THEN
      RETURN true;
    END IF;
  END IF;
  RETURN false;
END;
$function$;

REVOKE ALL ON FUNCTION public.fn_canonicalize_email(text) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.fn_is_disposable_email(text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.fn_canonicalize_email(text) TO service_role;
GRANT EXECUTE ON FUNCTION public.fn_is_disposable_email(text) TO service_role;

ALTER TABLE public.referral_ledger
  ADD COLUMN IF NOT EXISTS block_reason text;

COMMENT ON COLUMN public.referral_ledger.block_reason IS
  'When status=blocked: BLOCKED_SELF (buyer is referrer) or BLOCKED_EXISTING (not first order).';

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
  v_canon text; v_referrer_canon text;
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

  IF v_email IS NOT NULL AND public.fn_is_disposable_email(v_email) THEN
    RETURN jsonb_build_object('success', false, 'code', 'DISPOSABLE_EMAIL');
  END IF;

  v_canon := public.fn_canonicalize_email(v_email);
  v_referrer_canon := public.fn_canonicalize_email(v_referrer.email);
  IF v_canon IS NOT NULL AND v_referrer_canon IS NOT NULL AND v_canon = v_referrer_canon THEN
    RETURN jsonb_build_object('success', false, 'code', 'SELF_REFERRAL');
  END IF;
  IF v_phone IS NOT NULL AND public.fn_normalize_referral_phone(v_referrer.tel) = v_phone THEN
    RETURN jsonb_build_object('success', false, 'code', 'SELF_REFERRAL');
  END IF;

  IF p_platform = 'shopify' AND v_canon IS NOT NULL AND EXISTS (
    SELECT 1 FROM public.user_accounts ua
    WHERE ua.merchant_id = v_merchant_id
      AND ua.deleted_at IS NULL
      AND public.fn_canonicalize_email(ua.email) = v_canon
  ) THEN
    RETURN jsonb_build_object('success', false, 'code', 'EXISTING_CUSTOMER');
  END IF;
  IF p_platform = 'shopify' AND v_canon IS NOT NULL AND EXISTS (
    SELECT 1 FROM public.order_ledger_mkp o
    WHERE o.merchant_id = v_merchant_id
      AND o.platform = 'shopify'
      AND public.fn_canonicalize_email(o.buyer_email) = v_canon
      AND lower(COALESCE(o.order_status, '')) NOT IN ('cancelled', 'canceled', 'refunded', 'voided')
  ) THEN
    RETURN jsonb_build_object('success', false, 'code', 'EXISTING_CUSTOMER');
  END IF;
  IF p_platform = 'shopee' AND v_phone IS NOT NULL AND EXISTS (
    SELECT 1 FROM public.user_accounts ua
    WHERE ua.merchant_id = v_merchant_id
      AND ua.deleted_at IS NULL
      AND public.fn_normalize_referral_phone(ua.tel) = v_phone
  ) THEN
    RETURN jsonb_build_object('success', false, 'code', 'EXISTING_CUSTOMER');
  END IF;
  IF p_platform = 'shopee' AND v_phone IS NOT NULL AND EXISTS (
    SELECT 1 FROM public.order_ledger_mkp o
    WHERE o.merchant_id = v_merchant_id
      AND o.platform = 'shopee'
      AND public.fn_normalize_referral_phone(o.buyer_phone) = v_phone
      AND lower(COALESCE(o.order_status, '')) NOT IN ('cancelled', 'canceled', 'refunded', 'voided', 'in_cancel', 'to_return', 'returned')
  ) THEN
    RETURN jsonb_build_object('success', false, 'code', 'EXISTING_CUSTOMER');
  END IF;

  IF EXISTS (
    SELECT 1 FROM public.referral_claim c
    WHERE c.merchant_id = v_merchant_id
      AND c.platform = p_platform
      AND c.status IN ('open', 'completed')
      AND (
        (v_canon IS NOT NULL AND public.fn_canonicalize_email(c.friend_email) = v_canon)
        OR (v_phone IS NOT NULL AND c.friend_phone = v_phone)
      )
  ) THEN
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
      (v_canon IS NOT NULL AND public.fn_canonicalize_email(ua.email) = v_canon)
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
  IF v_ledger.status = 'blocked' THEN
    RETURN jsonb_build_object('success', true, 'code', 'BLOCKED', 'ledger_id', p_ledger_id);
  END IF;
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

DROP FUNCTION IF EXISTS public.fn_attribute_referral(text, uuid, uuid, text, text, text, text, text, text, text, text, text[]);

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
    WHERE merchant_id = p_merchant_id AND platform = p_platform AND status = 'open'
      AND public.fn_canonicalize_email(friend_email) = v_canon
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
    UPDATE public.referral_code SET status = 'used', updated_at = now() WHERE claim_id = v_claim.id AND code = ANY (v_codes) AND status = 'minted';
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


CREATE OR REPLACE FUNCTION public.upsert_marketplace_order(p_order jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE v_existing_id uuid; v_order_id uuid; v_action text; v_items_inserted int:=0; v_order_sn text; v_codes text[]; v_attr jsonb; v_synced boolean:=false;
BEGIN
 v_order_sn:=p_order->>'order_sn';
 IF p_order?'discount_codes' AND jsonb_typeof(p_order->'discount_codes')='array' THEN SELECT COALESCE(array_agg(x),'{}'::text[]) INTO v_codes FROM jsonb_array_elements_text(p_order->'discount_codes') x WHERE NULLIF(btrim(x),'') IS NOT NULL; ELSE v_codes:='{}'::text[]; END IF;
 SELECT id,COALESCE(synced_to_transaction,false) INTO v_existing_id,v_synced FROM order_ledger_mkp WHERE order_sn=v_order_sn AND platform=p_order->>'platform';
 IF v_existing_id IS NOT NULL THEN
  UPDATE order_ledger_mkp SET order_status=p_order->>'order_status',update_time=(p_order->>'update_time')::timestamptz,payment_status=p_order->>'payment_status',buyer_phone=COALESCE(p_order->>'buyer_phone',buyer_phone),buyer_email=COALESCE(p_order->>'buyer_email',buyer_email),total_amount=CASE WHEN NOT v_synced THEN COALESCE((p_order->>'total_amount')::numeric,total_amount) ELSE total_amount END,shipping_fee=CASE WHEN NOT v_synced THEN COALESCE((p_order->>'shipping_fee')::numeric,shipping_fee) ELSE shipping_fee END,discount_amount=CASE WHEN NOT v_synced THEN COALESCE((p_order->>'discount_amount')::numeric,discount_amount) ELSE discount_amount END,tax_amount=CASE WHEN NOT v_synced THEN COALESCE((p_order->>'tax_amount')::numeric,tax_amount) ELSE tax_amount END,final_amount=CASE WHEN NOT v_synced THEN COALESCE((p_order->>'final_amount')::numeric,final_amount) ELSE final_amount END,earnable_amount=CASE WHEN NOT v_synced THEN COALESCE((p_order->>'earnable_amount')::numeric,earnable_amount) ELSE earnable_amount END,financial_details=CASE WHEN NOT v_synced THEN COALESCE(p_order->'financial_details',financial_details) ELSE financial_details END,payment_method=CASE WHEN NOT v_synced THEN COALESCE(p_order->>'payment_method',payment_method) ELSE payment_method END,discount_codes=CASE WHEN v_codes<>'{}'::text[] THEN v_codes ELSE discount_codes END,updated_at=now() WHERE id=v_existing_id;
  v_order_id:=v_existing_id; v_action:='updated';
 ELSE
  INSERT INTO order_ledger_mkp(merchant_id,platform,shop_id,order_sn,external_user_id,buyer_username,buyer_phone,buyer_email,order_status,transaction_date,update_time,currency,total_amount,shipping_fee,discount_amount,tax_amount,final_amount,earnable_amount,financial_details,payment_method,payment_status,status,discount_codes)
  VALUES((p_order->>'merchant_id')::uuid,p_order->>'platform',p_order->>'shop_id',v_order_sn,p_order->>'external_user_id',p_order->>'buyer_username',p_order->>'buyer_phone',p_order->>'buyer_email',p_order->>'order_status',(p_order->>'transaction_date')::timestamptz,(p_order->>'update_time')::timestamptz,COALESCE(p_order->>'currency','THB'),(p_order->>'total_amount')::numeric,COALESCE((p_order->>'shipping_fee')::numeric,0),COALESCE((p_order->>'discount_amount')::numeric,0),COALESCE((p_order->>'tax_amount')::numeric,0),(p_order->>'final_amount')::numeric,(p_order->>'earnable_amount')::numeric,COALESCE(p_order->'financial_details','{}'::jsonb),p_order->>'payment_method',p_order->>'payment_status','completed',COALESCE(v_codes,'{}'::text[])) RETURNING id INTO v_order_id;
  v_action:='inserted';
 END IF;
 IF NOT v_synced AND p_order?'items' AND jsonb_typeof(p_order->'items')='array' AND jsonb_array_length(p_order->'items')>0 THEN
  INSERT INTO order_items_ledger_mkp(order_id,merchant_id,platform,order_sn,platform_item_id,variant_id,platform_sku,variant_sku,item_name,variant_name,quantity,currency,unit_price,discount_amount,line_total,earnable_amount,financial_details)
  SELECT v_order_id,(p_order->>'merchant_id')::uuid,p_order->>'platform',v_order_sn,item->>'platform_item_id',item->>'variant_id',item->>'platform_sku',item->>'variant_sku',item->>'item_name',item->>'variant_name',(item->>'quantity')::numeric,COALESCE(item->>'currency','THB'),(item->>'unit_price')::numeric,COALESCE((item->>'discount_amount')::numeric,0),(item->>'line_total')::numeric,(item->>'earnable_amount')::numeric,COALESCE(item->'financial_details','{}'::jsonb)
  FROM (
    SELECT DISTINCT ON (item->>'platform_item_id') item
    FROM jsonb_array_elements(p_order->'items') WITH ORDINALITY AS t(item, ord)
    ORDER BY item->>'platform_item_id', ord DESC
  ) deduped
  ON CONFLICT(platform,platform_item_id,order_id) DO UPDATE SET quantity=EXCLUDED.quantity,unit_price=EXCLUDED.unit_price,discount_amount=EXCLUDED.discount_amount,line_total=EXCLUDED.line_total,earnable_amount=EXCLUDED.earnable_amount,financial_details=EXCLUDED.financial_details;
  GET DIAGNOSTICS v_items_inserted=ROW_COUNT;
 END IF;
 BEGIN v_attr:=public.fn_attribute_referral(p_kind:='purchase',p_merchant_id:=(p_order->>'merchant_id')::uuid,p_platform:=p_order->>'platform',p_order_key:=v_order_sn,p_order_status:=p_order->>'order_status',p_payment_status:=p_order->>'payment_status',p_buyer_email:=p_order->>'buyer_email',p_buyer_phone:=p_order->>'buyer_phone',p_buyer_external_id:=p_order->>'external_user_id',p_codes:=COALESCE(v_codes,'{}'::text[]),p_buyer_orders_count:=NULLIF(p_order->>'buyer_orders_count','')::integer); EXCEPTION WHEN OTHERS THEN v_attr:=jsonb_build_object('success',false,'error',SQLERRM); END;
 RETURN jsonb_build_object('success',true,'code',CASE WHEN v_action='inserted' THEN 'CREATED' ELSE 'UPDATED' END,'title',CASE WHEN v_action='inserted' THEN 'Order Created' ELSE 'Order Updated' END,'description',format('Order %s %s with %s items',v_order_sn,v_action,v_items_inserted),'action',v_action,'order_id',v_order_id,'order_sn',v_order_sn,'items_count',v_items_inserted,'referral',v_attr);
END;
$function$;

CREATE OR REPLACE FUNCTION public.bff_list_referral_ledger(p_limit integer DEFAULT 50, p_offset integer DEFAULT 0, p_inviter_user_id uuid DEFAULT NULL::uuid, p_invitee_user_id uuid DEFAULT NULL::uuid, p_kind text DEFAULT NULL::text, p_platform text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_merchant_id uuid; v_rows jsonb; v_total bigint; v_limit integer; v_offset integer;
BEGIN
  IF NOT EXISTS (SELECT 1 FROM public.admin_users WHERE auth_user_id = auth.uid() AND active_status = true) THEN
    RETURN public.fn_response_error('Forbidden', 'Admin access required', 'FORBIDDEN');
  END IF;
  v_merchant_id := public.get_current_merchant_id();
  IF v_merchant_id IS NULL THEN RETURN public.fn_response_error('No merchant', 'No merchant context', 'NO_MERCHANT'); END IF;
  v_limit := GREATEST(1, LEAST(COALESCE(p_limit, 50), 200));
  v_offset := GREATEST(0, COALESCE(p_offset, 0));
  SELECT COUNT(*) INTO v_total FROM public.referral_ledger rl
  WHERE rl.merchant_id = v_merchant_id
    AND (p_inviter_user_id IS NULL OR rl.inviter_user_id = p_inviter_user_id)
    AND (p_invitee_user_id IS NULL OR rl.invitee_user_id = p_invitee_user_id)
    AND (p_kind IS NULL OR rl.kind = p_kind)
    AND (p_platform IS NULL OR rl.platform = p_platform);
  SELECT COALESCE(jsonb_agg(row_data ORDER BY created_at DESC), '[]'::jsonb) INTO v_rows FROM (
    SELECT jsonb_build_object(
      'id', rl.id, 'kind', rl.kind, 'status', rl.status, 'platform', rl.platform,
      'inviter_user_id', rl.inviter_user_id, 'invitee_user_id', rl.invitee_user_id,
      'invite_code', rl.invite_code, 'friend_email', rl.friend_email, 'friend_phone', rl.friend_phone,
      'order_key', rl.order_key, 'signed_up_at', rl.signed_up_at, 'created_at', rl.created_at,
      'block_reason', rl.block_reason,
      'commerce_code', (SELECT rc.code FROM public.referral_code rc WHERE rc.id = rl.code_id)
    ) AS row_data, rl.created_at
    FROM public.referral_ledger rl
    WHERE rl.merchant_id = v_merchant_id
      AND (p_inviter_user_id IS NULL OR rl.inviter_user_id = p_inviter_user_id)
      AND (p_invitee_user_id IS NULL OR rl.invitee_user_id = p_invitee_user_id)
      AND (p_kind IS NULL OR rl.kind = p_kind)
      AND (p_platform IS NULL OR rl.platform = p_platform)
    ORDER BY rl.created_at DESC LIMIT v_limit OFFSET v_offset
  ) t;
  RETURN public.fn_response_success('Referral ledger', 'Loaded', jsonb_build_object('total', v_total, 'limit', v_limit, 'offset', v_offset, 'rows', v_rows));
EXCEPTION WHEN OTHERS THEN
  RETURN public.fn_response_error('Error', SQLERRM, 'INTERNAL_ERROR');
END;
$function$;
