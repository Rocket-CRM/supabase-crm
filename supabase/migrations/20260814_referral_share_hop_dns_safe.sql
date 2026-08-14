-- Purchase share hop must not put dotted Shopify merchant_code in the hostname.
-- Host uses the first DNS label (wildcard *.rocket-loyalty.app); full code stays in the path.

CREATE OR REPLACE FUNCTION public.fn_referral_share_hop(p_merchant_id uuid)
RETURNS text
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path TO 'public'
AS $$
  SELECT CASE
    WHEN NULLIF(btrim(mm.merchant_code), '') IS NULL THEN NULL
    ELSE format(
      'https://%s.rocket-loyalty.app/r/%s',
      split_part(btrim(mm.merchant_code), '.', 1),
      btrim(mm.merchant_code)
    )
  END
  FROM public.merchant_master mm
  WHERE mm.id = p_merchant_id;
$$;

CREATE OR REPLACE FUNCTION public.bff_user_get_invite()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  v_auth_uid uuid; v_user_id uuid; v_merchant_id uuid; v_member_code text; v_share_url text; v_base text;
  v_limits jsonb; v_invites_total bigint; v_program public.referral_program; v_merchant_code text;
  v_shopify_url text; v_purchase_count bigint; v_offer jsonb; v_hop text;
BEGIN
  v_auth_uid := public.get_current_user_id();
  IF v_auth_uid IS NULL THEN RETURN jsonb_build_object('success', false, 'code', 'UNAUTHENTICATED', 'error', 'No authenticated user context'); END IF;
  SELECT ua.id, ua.merchant_id INTO v_user_id, v_merchant_id FROM public.user_accounts ua WHERE ua.auth_user_id = v_auth_uid;
  IF v_user_id IS NULL THEN RETURN jsonb_build_object('success', false, 'code', 'USER_NOT_FOUND', 'error', 'No user account linked'); END IF;
  SELECT * INTO v_program FROM public.referral_program WHERE merchant_id = v_merchant_id;
  IF v_program.id IS NULL OR NOT v_program.is_active THEN
    RETURN jsonb_build_object('success', false, 'code', 'REFERRAL_INACTIVE', 'error', 'Referral program inactive');
  END IF;
  v_member_code := public.fn_ensure_member_code(v_user_id, v_merchant_id);
  SELECT merchant_code INTO v_merchant_code FROM public.merchant_master WHERE id = v_merchant_id;
  v_base := public.fn_member_app_deep_link(v_merchant_id, 'home');
  IF v_base IS NOT NULL AND v_program.signup_enabled THEN
    v_share_url := rtrim(v_base, '/') || '/?invite=' || v_member_code;
  END IF;
  SELECT COUNT(*) INTO v_invites_total FROM public.referral_ledger WHERE inviter_user_id = v_user_id AND merchant_id = v_merchant_id AND kind = 'signup';
  SELECT COUNT(*) INTO v_purchase_count FROM public.referral_ledger WHERE inviter_user_id = v_user_id AND merchant_id = v_merchant_id AND kind = 'purchase' AND status = 'settled';
  SELECT COALESCE(jsonb_agg(jsonb_build_object('scope', tl.scope, 'count', tl.count, 'time_unit', tl.time_unit, 'used', (SELECT COUNT(*)::numeric FROM public.referral_ledger rl WHERE rl.merchant_id = v_merchant_id AND ((tl.scope = 'user' AND rl.inviter_user_id = v_user_id) OR tl.scope = 'total') AND rl.kind = 'signup' AND (CASE tl.time_unit WHEN 'day' THEN rl.created_at >= date_trunc('day', now()) WHEN 'week' THEN rl.created_at >= date_trunc('week', now()) WHEN 'month' THEN rl.created_at >= date_trunc('month', now()) WHEN 'year' THEN rl.created_at >= date_trunc('year', now()) ELSE true END))) ORDER BY tl.time_unit), '[]'::jsonb)
  INTO v_limits FROM public.transaction_limits tl WHERE tl.merchant_id = v_merchant_id AND tl.entity_type = 'referral' AND tl.entity_id IS NULL AND COALESCE(tl.active_status, true);
  v_hop := public.fn_referral_share_hop(v_merchant_id);
  IF v_program.purchase_enabled AND 'shopify' = ANY (COALESCE(v_program.platforms, '{}'::text[])) AND v_hop IS NOT NULL THEN
    v_shopify_url := v_hop || '?p=shopify&r=' || v_member_code;
  END IF;
  v_offer := COALESCE(v_program.friend_offer, '{}'::jsonb);
  RETURN jsonb_build_object('success', true, 'data', jsonb_build_object(
    'member_code', v_member_code, 'invite_code', v_member_code, 'share_url', v_share_url,
    'signup', jsonb_build_object('enabled', v_program.signup_enabled AND COALESCE(v_program.is_active, false), 'share_url', v_share_url),
    'purchase', jsonb_build_object(
      'enabled', v_program.purchase_enabled,
      'offer_summary', NULL,
      'shopify', jsonb_build_object('enabled', v_program.purchase_enabled AND 'shopify' = ANY (COALESCE(v_program.platforms,'{}'::text[])), 'share_url', v_shopify_url),
      'shopee', jsonb_build_object('enabled', v_program.purchase_enabled AND 'shopee' = ANY (COALESCE(v_program.platforms,'{}'::text[])), 'share_url', CASE WHEN v_program.purchase_enabled AND 'shopee' = ANY (COALESCE(v_program.platforms,'{}'::text[])) AND v_hop IS NOT NULL THEN v_hop || '?p=shopee&r=' || v_member_code ELSE NULL END)
    ),
    'invites_total', v_invites_total, 'limits', v_limits, 'stats', jsonb_build_object('completed_purchase', v_purchase_count),
    'friend_offer', v_offer
  ));
EXCEPTION WHEN OTHERS THEN
  RETURN jsonb_build_object('success', false, 'error', SQLERRM);
END;
$$;

GRANT EXECUTE ON FUNCTION public.fn_referral_share_hop(uuid) TO authenticated, service_role;
