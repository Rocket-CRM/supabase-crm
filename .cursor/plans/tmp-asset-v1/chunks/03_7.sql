CREATE OR REPLACE FUNCTION public.apply_tier_change(
  p_user_id uuid,
  p_merchant_id uuid,
  p_to_tier_id uuid,
  p_change_type text DEFAULT 'upgrade'::text,
  p_pending_id uuid DEFAULT NULL::uuid
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_current_tier_id uuid;
  v_user_type public.user_type;
  v_maintain_deadline date;
  v_maintain_window_type public.tier_evaluation_window_type;
  v_asset_result jsonb;
BEGIN
  IF p_change_type NOT IN ('upgrade', 'downgrade', 'assign_entry', 'manual') THEN
    RAISE EXCEPTION 'invalid tier change type: %', p_change_type;
  END IF;

  SELECT ua.tier_id, ua.user_type
  INTO v_current_tier_id, v_user_type
  FROM public.user_accounts ua
  WHERE ua.id = p_user_id AND ua.merchant_id = p_merchant_id;

  SELECT cmd.deadline, cmd.window_type
  INTO v_maintain_deadline, v_maintain_window_type
  FROM public.calculate_maintain_deadline(p_merchant_id, v_user_type, CURRENT_DATE) cmd;

  PERFORM public.chokepoint_post_user_event(
    p_event_type := 'update',
    p_merchant_id := p_merchant_id,
    p_user_id := p_user_id,
    p_changes := jsonb_build_object('tier_id', p_to_tier_id),
    p_metadata := jsonb_build_object(
      'tier_change_type', p_change_type,
      'tier_change_reason', format('Tier %s applied', p_change_type)
    )
  );

  INSERT INTO public.tier_evaluation_tracking (
    user_id, merchant_id, tier_achieved_at, maintain_deadline,
    maintain_window_type, updated_at
  ) VALUES (
    p_user_id, p_merchant_id, NOW(), v_maintain_deadline,
    v_maintain_window_type, NOW()
  )
  ON CONFLICT (user_id, merchant_id) DO UPDATE SET
    tier_achieved_at = NOW(),
    maintain_deadline = EXCLUDED.maintain_deadline,
    maintain_window_type = EXCLUDED.maintain_window_type,
    updated_at = NOW();

  PERFORM public.ensure_tier_progress(p_user_id, p_merchant_id);

  DELETE FROM public.tier_pending_upgrades
  WHERE user_id = p_user_id AND merchant_id = p_merchant_id;

  -- After tier is applied, shrink active assets to new quotas (FIFO)
  IF p_change_type IN ('downgrade', 'manual', 'assign_entry') THEN
    v_asset_result := public.fn_asset_enforce_quota_after_tier_change(p_merchant_id, p_user_id);
  END IF;

  RETURN jsonb_build_object(
    'success', true,
    'user_id', p_user_id,
    'change_type', p_change_type,
    'from_tier_id', v_current_tier_id,
    'to_tier_id', p_to_tier_id,
    'maintain_deadline', v_maintain_deadline,
    'asset_quota_enforcement', v_asset_result
  );
END;
$function$;
