-- Phase 7–8 closeout: catalog + menu, member removal audit/scrub, retire receipt review audit insert.

-- Resource catalog (role builder + profile permissions)
CREATE OR REPLACE FUNCTION public.fn_admin_role_resource_catalog()
 RETURNS TABLE(resource_code text, display_name text, category text)
 LANGUAGE sql
 STABLE
 SET search_path TO 'public'
AS $function$
  VALUES
    ('currency', 'Currency', 'loyalty'),
    ('reward', 'Reward', 'loyalty'),
    ('promo_code', 'Promo Code', 'loyalty'),
    ('tier', 'Tier', 'loyalty'),
    ('persona', 'Persona', 'loyalty'),
    ('store_credit_promo', 'Store Credit Promo', 'loyalty'),
    ('earn_channel', 'Earning Channel', 'earning_config'),
    ('earn_code', 'Code Claiming', 'earning_config'),
    ('earn_code_import', 'Code Import', 'earning_config'),
    ('earn_marketplace', 'Marketplace Orders', 'earning_config'),
    ('mission', 'Mission', 'campaigns'),
    ('earn_code_activate', 'Code Activation', 'operations'),
    ('purchase_approval', 'Purchase Approval', 'operations'),
    ('front_line', 'Front Line', 'frontline'),
    ('frontline_upload_receipt', 'Upload Receipt', 'frontline'),
    ('frontline_redemption_reward', 'Redemption Reward', 'frontline'),
    ('frontline_burn_points_discount', 'Burn Points for Discount', 'frontline'),
    ('frontline_adjust_points', 'Adjust Points', 'frontline'),
    ('frontline_claim_mission', 'Claim Mission', 'frontline'),
    ('frontline_asset_group', 'Asset Group', 'frontline'),
    ('frontline_store_credit', 'Store Credit', 'frontline'),
    ('frontline_checkin', 'Check-in', 'frontline'),
    ('frontline_edit_member_profile', 'Edit Member Profile', 'frontline'),
    ('user', 'User Management', 'settings'),
    ('form', 'Form', 'settings'),
    ('display', 'Display Settings', 'settings'),
    ('global_setting', 'Global Settings', 'settings'),
    ('store', 'Store', 'settings'),
    ('store_attribute', 'Store Attribute', 'settings'),
    ('asset', 'Asset', 'functional'),
    ('customer-360', 'Customer 360', 'functional'),
    ('audit_log', 'Activity Log', 'functional'),
    ('role', 'Role', 'admin'),
    ('team', 'Team', 'admin'),
    ('invite', 'Invitation', 'admin'),
    ('api_key', 'API Key', 'admin'),
    ('report', 'Report', 'analytics'),
    ('event', 'Event', 'event'),
    ('grower_registration', 'Grower Registration', 'event'),
    ('rice_survey', 'Rice Survey', 'event'),
    ('cs_conversation', 'Conversations', 'cs'),
    ('cs_knowledge', 'Knowledge Base', 'cs'),
    ('cs_procedure', 'Procedures', 'cs'),
    ('cs_channel', 'Channels', 'cs'),
    ('cs_brand_config', 'Brand Config', 'cs'),
    ('cs_team', 'CS Teams', 'cs'),
    ('cs_role', 'CS Roles', 'cs'),
    ('cs_analytics', 'CS Analytics', 'cs'),
    ('cs_call_log', 'Call Logs', 'cs')
$function$;

INSERT INTO public.admin_menu_config
  (id, label, href, image, active_image, badge, category, resource, parent_id, display_order, active_status, feature_group, feature_key)
VALUES
  (
    'activity-log',
    'Activity log',
    '/activity-log',
    '',
    NULL,
    NULL,
    'functional',
    'audit_log',
    NULL,
    95,
    true,
    NULL,
    NULL
  )
ON CONFLICT (id) DO UPDATE SET
  label         = EXCLUDED.label,
  href          = EXCLUDED.href,
  category      = EXCLUDED.category,
  resource      = EXCLUDED.resource,
  display_order = EXCLUDED.display_order,
  active_status = EXCLUDED.active_status;

-- Member removal: log admin action + scrub member PII from prior audit payloads
CREATE OR REPLACE FUNCTION public.admin_remove_user(p_user_id uuid, p_reason text DEFAULT 'Admin request'::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
DECLARE
  v_merchant_id uuid;
  v_admin_id uuid;
  v_user record;
  v_snapshot jsonb;
  v_affected jsonb := '{}'::jsonb;
  v_wallet_balance int;
  v_cnt int;
BEGIN
  v_merchant_id := get_current_merchant_id();
  IF v_merchant_id IS NULL THEN
    RETURN fn_response_error('Unauthorized', 'Merchant context required');
  END IF;

  SELECT id INTO v_admin_id
  FROM admin_users
  WHERE auth_user_id = auth.uid() AND active_status = true;
  IF v_admin_id IS NULL THEN
    RETURN fn_response_error('Forbidden', 'Admin access required');
  END IF;

  SELECT * INTO v_user FROM user_accounts WHERE id = p_user_id AND merchant_id = v_merchant_id;
  IF NOT FOUND THEN
    RETURN fn_response_error('Not Found', 'User not found in this merchant');
  END IF;
  IF v_user.deleted_at IS NOT NULL THEN
    RETURN fn_response_error('Conflict', 'User has already been removed');
  END IF;

  v_snapshot := jsonb_build_object(
    'fullname', v_user.fullname, 'firstname', v_user.firstname, 'lastname', v_user.lastname,
    'email', v_user.email, 'tel', v_user.tel, 'line_id', v_user.line_id,
    'birth_date', v_user.birth_date, 'gender', v_user.gender, 'external_user_id', v_user.external_user_id,
    'tier_id', v_user.tier_id, 'persona_id', v_user.persona_id, 'created_at', v_user.created_at
  );

  SELECT COALESCE(points_balance, 0) INTO v_wallet_balance
  FROM user_wallet WHERE user_id = p_user_id AND merchant_id = v_merchant_id;
  IF v_wallet_balance IS NULL THEN v_wallet_balance := 0; END IF;
  v_snapshot := v_snapshot || jsonb_build_object('points_balance', v_wallet_balance);

  DELETE FROM refresh_tokens WHERE user_id = p_user_id;
  GET DIAGNOSTICS v_cnt = ROW_COUNT;
  v_affected := v_affected || jsonb_build_object('refresh_tokens_deleted', v_cnt);

  DELETE FROM user_sessions WHERE user_id = p_user_id;
  GET DIAGNOSTICS v_cnt = ROW_COUNT;
  v_affected := v_affected || jsonb_build_object('sessions_deleted', v_cnt);

  IF v_wallet_balance > 0 THEN
    PERFORM chokepoint_post_wallet_transaction(
      p_user_id := p_user_id, p_currency := 'points'::currency,
      p_source_type := 'account_removal'::wallet_transaction_source_type,
      p_component := 'adjustment'::currency_component,
      p_transaction_type := 'burn'::currency_transaction_type,
      p_amount := v_wallet_balance,
      p_transaction_id := p_user_id, p_merchant_id := v_merchant_id,
      p_description := 'Account removed — balance forfeited',
      p_dedup_key := 'remove_user_' || p_user_id::text
    );
    v_affected := v_affected || jsonb_build_object('points_forfeited', v_wallet_balance);
  END IF;

  UPDATE user_ticket_balances SET balance = 0
  WHERE user_id = p_user_id AND merchant_id = v_merchant_id AND balance > 0;
  GET DIAGNOSTICS v_cnt = ROW_COUNT;
  v_affected := v_affected || jsonb_build_object('ticket_balances_zeroed', v_cnt);

  UPDATE user_benefit SET status = 'revoked'
  WHERE user_id = p_user_id AND merchant_id = v_merchant_id AND status = 'active';
  GET DIAGNOSTICS v_cnt = ROW_COUNT;
  v_affected := v_affected || jsonb_build_object('benefits_revoked', v_cnt);

  WITH removed AS (
    UPDATE amp_audience_member m
    SET exited_at = now()
    FROM amp_audience_master a
    WHERE a.id = m.audience_id
      AND a.merchant_id = v_merchant_id
      AND m.user_id = p_user_id
      AND m.exited_at IS NULL
    RETURNING m.audience_id
  ),
  counts AS (
    SELECT audience_id, count(*)::integer AS removed_count
    FROM removed
    GROUP BY audience_id
  ),
  decremented AS (
    UPDATE amp_audience_master a
    SET member_count = GREATEST(a.member_count - counts.removed_count, 0),
        updated_at = now()
    FROM counts
    WHERE a.id = counts.audience_id
    RETURNING counts.removed_count
  )
  SELECT COALESCE(sum(removed_count), 0)::integer INTO v_cnt
  FROM decremented;
  v_affected := v_affected || jsonb_build_object('audience_memberships_removed', v_cnt);

  PERFORM public.chokepoint_post_user_event(
    p_event_type := 'soft_delete',
    p_merchant_id := v_merchant_id,
    p_user_id := p_user_id,
    p_skip_side_effects := true,
    p_actor := jsonb_build_object('actor_id', v_admin_id, 'actor_type', 'admin', 'reason', p_reason)
  );

  DELETE FROM user_address WHERE user_id = p_user_id;
  GET DIAGNOSTICS v_cnt = ROW_COUNT;
  v_affected := v_affected || jsonb_build_object('addresses_deleted', v_cnt);

  DELETE FROM user_communication_preferences WHERE user_id = p_user_id;
  GET DIAGNOSTICS v_cnt = ROW_COUNT;
  v_affected := v_affected || jsonb_build_object('comm_prefs_deleted', v_cnt);

  DELETE FROM user_notes WHERE user_id = p_user_id AND merchant_id = v_merchant_id;
  GET DIAGNOSTICS v_cnt = ROW_COUNT;
  v_affected := v_affected || jsonb_build_object('notes_deleted', v_cnt);

  INSERT INTO user_removal_log (merchant_id, user_id, removed_by, reason, snapshot, affected_summary)
  VALUES (v_merchant_id, p_user_id, v_admin_id, p_reason, v_snapshot, v_affected);

  PERFORM fn_log_admin_action(
    'member.remove',
    'member',
    p_user_id,
    jsonb_build_object('reason', p_reason),
    v_snapshot,
    NULL,
    v_affected,
    p_reason,
    'admin_remove_user'
  );

  PERFORM fn_scrub_admin_audit_log_for_member(p_user_id);

  RETURN jsonb_build_object(
    'success', true,
    'data', jsonb_build_object(
      'user_id', p_user_id, 'removed_at', now(), 'removed_by', v_admin_id, 'reason', p_reason, 'affected', v_affected
    )
  );
END;
$function$;
