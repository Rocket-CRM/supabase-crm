-- Customer 360 wallet lots: resolve wallet burn + redemption ledger links for tooltips.

DROP FUNCTION IF EXISTS public.bff_admin_get_member_wallet_lots(uuid, integer, integer);

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
  redeemed_at timestamp with time zone,
  redeemed_wallet_burn_id uuid,
  redeemed_wallet_source_type text,
  redeemed_wallet_description text,
  redemption_ledger_id uuid,
  redemption_code text,
  expired_amount integer,
  expired_at timestamp with time zone,
  expired_wallet_burn_id uuid,
  expired_wallet_description text,
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
    CASE
      WHEN GREATEST(
        0,
        wl.amount::numeric
          - COALESCE(wl.deductible_balance, 0)
          - COALESCE(wl.expired_amount, 0)::numeric
      ) > 0 THEN COALESCE(rb.created_at, wl.last_deducted_at)
      ELSE NULL::timestamptz
    END AS redeemed_at,
    rb.id AS redeemed_wallet_burn_id,
    rb.source_type::text AS redeemed_wallet_source_type,
    rb.description AS redeemed_wallet_description,
    CASE
      WHEN rb.source_type = 'reward_redemption'::wallet_transaction_source_type THEN rb.source_id
      ELSE NULL::uuid
    END AS redemption_ledger_id,
    rrl.code AS redemption_code,
    COALESCE(wl.expired_amount, 0) AS expired_amount,
    CASE
      WHEN COALESCE(wl.expired_amount, 0) > 0 THEN COALESCE(eb.created_at, wl.expiry_processed_at)
      ELSE NULL::timestamptz
    END AS expired_at,
    eb.id AS expired_wallet_burn_id,
    eb.description AS expired_wallet_description,
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
  LEFT JOIN LATERAL (
    SELECT b.id, b.source_type, b.source_id, b.description, b.created_at
    FROM wallet_ledger b
    WHERE b.merchant_id = wl.merchant_id
      AND b.user_id = wl.user_id
      AND b.currency = 'points'
      AND b.transaction_type = 'burn'::currency_transaction_type
      AND b.source_type IS DISTINCT FROM 'expiry'::wallet_transaction_source_type
      AND (
        wl.last_deducted_at IS NOT NULL
        AND b.created_at >= wl.last_deducted_at - interval '2 seconds'
        AND b.created_at <= wl.last_deducted_at + interval '30 minutes'
      )
    ORDER BY b.created_at ASC
    LIMIT 1
  ) rb ON true
  LEFT JOIN reward_redemptions_ledger rrl
    ON rrl.id = rb.source_id
   AND rb.source_type = 'reward_redemption'::wallet_transaction_source_type
   AND rrl.merchant_id = wl.merchant_id
  LEFT JOIN LATERAL (
    SELECT b.id, b.description, b.created_at
    FROM wallet_ledger b
    WHERE b.merchant_id = wl.merchant_id
      AND b.user_id = wl.user_id
      AND b.currency = 'points'
      AND b.transaction_type = 'burn'::currency_transaction_type
      AND b.source_type = 'expiry'::wallet_transaction_source_type
      AND wl.expiry_processed_at IS NOT NULL
      AND b.created_at >= wl.expiry_processed_at - interval '2 seconds'
      AND b.created_at <= wl.expiry_processed_at + interval '30 minutes'
    ORDER BY b.created_at ASC
    LIMIT 1
  ) eb ON true
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

GRANT EXECUTE ON FUNCTION public.bff_admin_get_member_wallet_lots(uuid, integer, integer) TO authenticated;
GRANT EXECUTE ON FUNCTION public.bff_admin_get_member_wallet_lots(uuid, integer, integer) TO service_role;
