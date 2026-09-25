-- Public claim + confirm/abort. Called by shopify-proxy and Shopee landing.

CREATE OR REPLACE FUNCTION public.api_get_referral_claim_page(
  p_merchant_code text,
  p_platform text,
  p_referrer_code text
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  v_merchant_id uuid;
  v_program public.referral_program;
  v_referrer record;
  v_offer jsonb;
BEGIN
  SELECT id INTO v_merchant_id FROM public.merchant_master WHERE merchant_code = btrim(p_merchant_code);
  IF v_merchant_id IS NULL THEN
    RETURN jsonb_build_object('success', false, 'code', 'MERCHANT_NOT_FOUND');
  END IF;
  SELECT * INTO v_program FROM public.referral_program WHERE merchant_id = v_merchant_id;
  IF v_program.id IS NULL OR NOT v_program.is_active OR NOT v_program.purchase_enabled
     OR NOT (p_platform = ANY (COALESCE(v_program.platforms, '{}'::text[]))) THEN
    RETURN jsonb_build_object('success', false, 'code', 'REFERRAL_INACTIVE');
  END IF;
  SELECT id, member_code INTO v_referrer
  FROM public.user_accounts
  WHERE merchant_id = v_merchant_id AND member_code = btrim(p_referrer_code);
  IF NOT FOUND THEN
    RETURN jsonb_build_object('success', false, 'code', 'INVALID_REFERRER');
  END IF;
  v_offer := COALESCE(v_program.friend_offer, '{}'::jsonb);
  RETURN jsonb_build_object(
    'success', true, 'code', 'OK',
    'data', jsonb_build_object(
      'merchant_id', v_merchant_id,
      'platform', p_platform,
      'ttl_hours', COALESCE((v_offer->>'ttl_hours')::int, 24),
      'discount_type', v_offer->>'discount_type',
      'value', v_offer->'value',
      'min_spend', v_offer->'min_spend'
    )
  );
END;
$$;

CREATE OR REPLACE FUNCTION public.api_claim_referral(
  p_merchant_id uuid DEFAULT NULL,
  p_merchant_code text DEFAULT NULL,
  p_referrer_code text DEFAULT NULL,
  p_platform text DEFAULT NULL,
  p_email text DEFAULT NULL,
  p_phone text DEFAULT NULL,
  p_friend_name text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  v_merchant_id uuid;
  v_program public.referral_program;
  v_referrer record;
  v_email text;
  v_phone text;
  v_offer jsonb;
  v_ttl int;
  v_shop_cap int;
  v_ref_cap int;
  v_live_shop int;
  v_live_ref int;
  v_claim_id uuid;
  v_issued jsonb;
  v_mother text;
BEGIN
  v_merchant_id := p_merchant_id;
  IF v_merchant_id IS NULL AND NULLIF(btrim(p_merchant_code), '') IS NOT NULL THEN
    SELECT id INTO v_merchant_id FROM public.merchant_master WHERE merchant_code = btrim(p_merchant_code);
  END IF;
  IF v_merchant_id IS NULL THEN
    RETURN jsonb_build_object('success', false, 'code', 'NO_MERCHANT');
  END IF;
  IF p_platform IS NULL OR p_platform NOT IN ('shopify', 'shopee') THEN
    RETURN jsonb_build_object('success', false, 'code', 'INVALID_PLATFORM');
  END IF;
  IF NULLIF(btrim(p_referrer_code), '') IS NULL THEN
    RETURN jsonb_build_object('success', false, 'code', 'INVALID_REFERRER');
  END IF;

  v_email := NULLIF(lower(btrim(COALESCE(p_email, ''))), '');
  v_phone := public.fn_normalize_referral_phone(p_phone);
  IF p_platform = 'shopify' AND v_email IS NULL THEN
    RETURN jsonb_build_object('success', false, 'code', 'EMAIL_REQUIRED');
  END IF;
  IF p_platform = 'shopee' AND v_phone IS NULL THEN
    RETURN jsonb_build_object('success', false, 'code', 'PHONE_REQUIRED');
  END IF;

  SELECT * INTO v_program FROM public.referral_program WHERE merchant_id = v_merchant_id;
  IF v_program.id IS NULL OR NOT v_program.is_active OR NOT v_program.purchase_enabled
     OR NOT (p_platform = ANY (COALESCE(v_program.platforms, '{}'::text[]))) THEN
    RETURN jsonb_build_object('success', false, 'code', 'REFERRAL_INACTIVE');
  END IF;

  SELECT * INTO v_referrer
  FROM public.user_accounts
  WHERE merchant_id = v_merchant_id AND member_code = btrim(p_referrer_code);
  IF NOT FOUND THEN
    RETURN jsonb_build_object('success', false, 'code', 'INVALID_REFERRER');
  END IF;

  IF v_email IS NOT NULL AND lower(COALESCE(v_referrer.email, '')) = v_email THEN
    RETURN jsonb_build_object('success', false, 'code', 'SELF_REFERRAL');
  END IF;
  IF v_phone IS NOT NULL AND public.fn_normalize_referral_phone(v_referrer.tel) = v_phone THEN
    RETURN jsonb_build_object('success', false, 'code', 'SELF_REFERRAL');
  END IF;

  IF p_platform = 'shopify' AND v_email IS NOT NULL AND EXISTS (
    SELECT 1 FROM public.user_accounts ua
    WHERE ua.merchant_id = v_merchant_id AND lower(ua.email) = v_email
  ) THEN
    RETURN jsonb_build_object('success', false, 'code', 'EXISTING_CUSTOMER');
  END IF;

  IF EXISTS (
    SELECT 1 FROM public.referral_claim c
    WHERE c.merchant_id = v_merchant_id AND c.platform = p_platform
      AND c.status IN ('open', 'completed')
      AND (
        (v_email IS NOT NULL AND c.friend_email = v_email)
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

  SELECT COUNT(*)::int INTO v_live_shop
  FROM public.referral_code
  WHERE merchant_id = v_merchant_id AND platform = p_platform
    AND status IN ('pending_mint', 'minted') AND expires_at > now();
  IF v_live_shop >= v_shop_cap THEN
    RETURN jsonb_build_object('success', false, 'code', 'SHOP_CAP');
  END IF;

  SELECT COUNT(*)::int INTO v_live_ref
  FROM public.referral_code
  WHERE merchant_id = v_merchant_id AND platform = p_platform
    AND referrer_user_id = v_referrer.id
    AND status IN ('pending_mint', 'minted') AND expires_at > now();
  IF v_live_ref >= v_ref_cap THEN
    RETURN jsonb_build_object('success', false, 'code', 'REFERRER_CAP');
  END IF;

  INSERT INTO public.referral_claim (
    merchant_id, referrer_user_id, platform, friend_email, friend_phone, status
  ) VALUES (
    v_merchant_id, v_referrer.id, p_platform, v_email, v_phone, 'open'
  ) RETURNING id INTO v_claim_id;

  v_issued := public.fn_issue_referral_code(v_merchant_id, v_claim_id, p_platform, v_ttl);
  IF NOT COALESCE((v_issued->>'success')::boolean, false) THEN
    UPDATE public.referral_claim SET status = 'aborted', updated_at = now() WHERE id = v_claim_id;
    RETURN jsonb_build_object('success', false, 'code', COALESCE(v_issued->>'code', 'ISSUE_FAILED'));
  END IF;

  v_mother := v_program.shopify_mother_discount_id;

  RETURN jsonb_build_object(
    'success', true, 'code', 'OK',
    'data', jsonb_build_object(
      'claim_id', v_claim_id,
      'referral_code_id', v_issued->>'referral_code_id',
      'commerce_code', v_issued->>'commerce_code',
      'expires_at', v_issued->>'expires_at',
      'platform', p_platform,
      'merchant_id', v_merchant_id,
      'shopify_mother_discount_id', v_mother,
      'friend_offer', v_offer,
      'ttl_hours', v_ttl
    )
  );
END;
$$;

CREATE OR REPLACE FUNCTION public.api_confirm_referral_mint(
  p_referral_code_id uuid,
  p_platform_voucher_id text DEFAULT NULL,
  p_platform_discount_id text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
BEGIN
  UPDATE public.referral_code
  SET status = 'minted',
      platform_voucher_id = COALESCE(p_platform_voucher_id, platform_voucher_id),
      platform_discount_id = COALESCE(p_platform_discount_id, platform_discount_id),
      updated_at = now()
  WHERE id = p_referral_code_id AND status IN ('pending_mint', 'minted');
  IF NOT FOUND THEN
    RETURN jsonb_build_object('success', false, 'code', 'NOT_FOUND');
  END IF;
  RETURN jsonb_build_object('success', true, 'code', 'OK');
END;
$$;

CREATE OR REPLACE FUNCTION public.api_abort_referral_claim(p_claim_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
BEGIN
  UPDATE public.referral_code SET status = 'aborted', updated_at = now()
  WHERE claim_id = p_claim_id AND status IN ('pending_mint', 'minted');
  UPDATE public.referral_claim SET status = 'aborted', updated_at = now()
  WHERE id = p_claim_id AND status = 'open';
  RETURN jsonb_build_object('success', true, 'code', 'OK');
END;
$$;

GRANT EXECUTE ON FUNCTION public.api_get_referral_claim_page(text, text, text) TO anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.api_claim_referral(uuid, text, text, text, text, text, text) TO anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.api_confirm_referral_mint(uuid, text, text) TO anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.api_abort_referral_claim(uuid) TO anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.fn_attribute_referral(text, uuid, uuid, text, text, text, text, text, text, text, text, text[]) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.fn_issue_referral_code(uuid, uuid, text, integer) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.fn_settle_referral(uuid) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.fn_clawback_referral(uuid) TO authenticated, service_role;
