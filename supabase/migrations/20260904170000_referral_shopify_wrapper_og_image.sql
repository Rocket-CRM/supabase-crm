-- Referral Shopify share: OG preview image + full wrapper fields on claim page.

ALTER TABLE public.referral_program
  ALTER COLUMN shopify_wrapper SET DEFAULT jsonb_build_object(
    'landing_url', null,
    'share_message', null,
    'popup_title', null,
    'popup_button', null,
    'og_title', null,
    'og_description', null,
    'og_image_url', null
  );

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
  v_wrapper jsonb;
  v_shop_domain text;
  v_store_name text;
BEGIN
  SELECT id, name INTO v_merchant_id, v_store_name
  FROM public.merchant_master
  WHERE merchant_code = btrim(p_merchant_code);
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
  v_wrapper := COALESCE(v_program.shopify_wrapper, '{}'::jsonb);
  SELECT mc.credentials->>'shop_domain' INTO v_shop_domain
  FROM public.merchant_credentials mc
  WHERE mc.merchant_id = v_merchant_id
    AND mc.service_name = 'shopify_app'
    AND mc.is_active = true
  LIMIT 1;
  RETURN jsonb_build_object(
    'success', true, 'code', 'OK',
    'data', jsonb_build_object(
      'merchant_id', v_merchant_id,
      'store_name', v_store_name,
      'platform', p_platform,
      'ttl_hours', COALESCE((v_offer->>'ttl_hours')::int, 24),
      'discount_type', v_offer->>'discount_type',
      'value', v_offer->'value',
      'min_spend', v_offer->'min_spend',
      'landing_url', NULLIF(v_wrapper->>'landing_url', ''),
      'shop_domain', v_shop_domain,
      'og_title', NULLIF(v_wrapper->>'og_title', ''),
      'og_description', NULLIF(v_wrapper->>'og_description', ''),
      'og_image_url', NULLIF(v_wrapper->>'og_image_url', ''),
      'share_message', NULLIF(v_wrapper->>'share_message', ''),
      'popup_title', NULLIF(v_wrapper->>'popup_title', ''),
      'popup_button', NULLIF(v_wrapper->>'popup_button', '')
    )
  );
END;
$$;
