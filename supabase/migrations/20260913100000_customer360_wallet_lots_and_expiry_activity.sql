-- Customer 360: distinguish points expiry in activity stream + wallet earn-lot breakdown for admins.

-- 1) Activity stream: event_type points_expiry + human title
DO $$
DECLARE
  v_def text;
  v_old text;
  v_new text;
BEGIN
  SELECT pg_get_functiondef(oid) INTO v_def
  FROM pg_proc
  WHERE proname = 'bff_admin_get_member_360_base'
    AND pg_function_is_visible(oid)
  LIMIT 1;

  IF v_def IS NULL THEN
    RAISE EXCEPTION 'bff_admin_get_member_360_base not found';
  END IF;

  v_old := 'CASE WHEN wl.component = ''reversal''::currency_component THEN ''points_revert'' WHEN wl.source_type = ''redemption_cancellation''::wallet_transaction_source_type THEN ''points_revert'' WHEN wl.transaction_type = ''earn'' THEN ''points_earn'' ELSE ''points_burn'' END AS event_type';
  v_new := 'CASE WHEN wl.component = ''reversal''::currency_component THEN ''points_revert'' WHEN wl.source_type = ''redemption_cancellation''::wallet_transaction_source_type THEN ''points_revert'' WHEN wl.source_type = ''expiry''::wallet_transaction_source_type THEN ''points_expiry'' WHEN wl.transaction_type = ''earn'' THEN ''points_earn'' ELSE ''points_burn'' END AS event_type';

  v_def := replace(v_def, v_old, v_new);

  v_old := 'CASE WHEN wl.transaction_type = ''earn'' THEN ''+'' || wl.amount || '' points'' ELSE ''-'' || wl.amount || '' points'' END AS title';
  v_new := 'CASE WHEN wl.source_type = ''expiry''::wallet_transaction_source_type THEN ''Points expired'' WHEN wl.transaction_type = ''earn'' THEN ''+'' || wl.amount || '' points'' ELSE ''-'' || wl.amount || '' points'' END AS title';

  v_def := replace(v_def, v_old, v_new);

  IF v_def = pg_get_functiondef((SELECT oid FROM pg_proc WHERE proname = 'bff_admin_get_member_360_base' LIMIT 1)) THEN
    RAISE EXCEPTION 'bff_admin_get_member_360_base activity CASE not updated';
  END IF;

  EXECUTE v_def;
END;
$$;

-- 2) Paginated earn-lot rows for Customer 360 wallet breakdown
CREATE OR REPLACE FUNCTION public.bff_admin_get_member_wallet_lots(
  p_user_id uuid,
  p_limit integer DEFAULT 50,
  p_offset integer DEFAULT 0
)
RETURNS TABLE(
  id uuid,
  earned_at timestamp with time zone,
  amount integer,
  expiry_date date,
  deductible_balance numeric,
  redeemed_amount numeric,
  expired_amount integer,
  source_type text,
  description text,
  lot_status text,
  total_count bigint
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_merchant_id uuid;
  v_limit integer;
  v_offset integer;
BEGIN
  v_merchant_id := get_current_merchant_id();
  IF v_merchant_id IS NULL THEN
    RAISE EXCEPTION 'Unauthorized: merchant context required'
      USING ERRCODE = 'P0001';
  END IF;

  IF NOT (
    check_admin_permission('customer-360', 'read')
    OR check_admin_permission('front_line', 'read')
  ) THEN
    RAISE EXCEPTION 'Permission denied: customer-360.read or front_line.read required'
      USING ERRCODE = 'P0001';
  END IF;

  IF p_user_id IS NULL THEN
    RAISE EXCEPTION 'p_user_id is required'
      USING ERRCODE = 'P0001';
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM user_accounts ua
    WHERE ua.id = p_user_id
      AND ua.merchant_id = v_merchant_id
  ) THEN
    RAISE EXCEPTION 'User not found in this merchant'
      USING ERRCODE = 'P0001';
  END IF;

  v_limit := LEAST(GREATEST(COALESCE(p_limit, 50), 1), 200);
  v_offset := GREATEST(COALESCE(p_offset, 0), 0);

  RETURN QUERY
  SELECT
    wl.id,
    wl.created_at AS earned_at,
    wl.amount,
    wl.expiry_date,
    COALESCE(wl.deductible_balance, 0) AS deductible_balance,
    GREATEST(
      0,
      wl.amount::numeric
        - COALESCE(wl.deductible_balance, 0)
        - COALESCE(wl.expired_amount, 0)::numeric
    ) AS redeemed_amount,
    COALESCE(wl.expired_amount, 0) AS expired_amount,
    wl.source_type::text AS source_type,
    wl.description,
    CASE
      WHEN COALESCE(wl.deductible_balance, 0) > 0
        AND wl.expiry_date IS NOT NULL
        AND wl.expiry_date <= CURRENT_DATE
        THEN 'expired_balance'
      WHEN COALESCE(wl.deductible_balance, 0) > 0 THEN 'active'
      WHEN COALESCE(wl.expired_amount, 0) > 0 THEN 'expired'
      ELSE 'depleted'
    END AS lot_status,
    COUNT(*) OVER()::bigint AS total_count
  FROM wallet_ledger wl
  WHERE wl.merchant_id = v_merchant_id
    AND wl.user_id = p_user_id
    AND wl.currency = 'points'
    AND wl.transaction_type = 'earn'
    AND wl.amount > 0
  ORDER BY wl.expiry_date ASC NULLS LAST, wl.created_at ASC
  LIMIT v_limit
  OFFSET v_offset;
END;
$function$;

COMMENT ON FUNCTION public.bff_admin_get_member_wallet_lots(uuid, integer, integer) IS
  'Customer 360: paginated points earn lots with redeemed vs expired breakdown per lot.';

GRANT EXECUTE ON FUNCTION public.bff_admin_get_member_wallet_lots(uuid, integer, integer) TO authenticated;
GRANT EXECUTE ON FUNCTION public.bff_admin_get_member_wallet_lots(uuid, integer, integer) TO service_role;
