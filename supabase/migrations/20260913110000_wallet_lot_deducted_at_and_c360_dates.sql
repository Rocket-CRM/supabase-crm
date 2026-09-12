-- Track last FIFO redemption deduction per earn lot; surface redeemed/expired timestamps in Customer 360.

ALTER TABLE public.wallet_ledger
  ADD COLUMN IF NOT EXISTS last_deducted_at timestamp with time zone;

COMMENT ON COLUMN public.wallet_ledger.last_deducted_at IS
  'Last time FIFO burn allocation reduced deductible_balance on this earn lot (non-expiry burns).';

-- Patch FIFO allocator to stamp last_deducted_at on each lot touch.
DO $$
DECLARE
  v_def text;
  v_old text;
  v_new text;
BEGIN
  SELECT pg_get_functiondef(oid) INTO v_def
  FROM pg_proc
  WHERE proname = 'fn_allocate_fifo_burn'
    AND pronamespace = (SELECT oid FROM pg_namespace WHERE nspname = 'util')
  LIMIT 1;

  IF v_def IS NULL THEN
    RAISE EXCEPTION 'util.fn_allocate_fifo_burn not found';
  END IF;

  v_old := E'    UPDATE public.wallet_ledger\n    SET deductible_balance = deductible_balance - v_deduct\n    WHERE id = v_lot.id;';
  v_new := E'    UPDATE public.wallet_ledger\n    SET deductible_balance = deductible_balance - v_deduct,\n        last_deducted_at = now()\n    WHERE id = v_lot.id;';

  v_def := replace(v_def, v_old, v_new);

  IF v_def = pg_get_functiondef((SELECT oid FROM pg_proc WHERE proname = 'fn_allocate_fifo_burn' AND pronamespace = (SELECT oid FROM pg_namespace WHERE nspname = 'util') LIMIT 1)) THEN
    RAISE EXCEPTION 'util.fn_allocate_fifo_burn last_deducted_at patch not applied';
  END IF;

  EXECUTE v_def;
END;
$$;

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
  expired_amount integer,
  expired_at timestamp with time zone,
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
      ) > 0 THEN wl.last_deducted_at
      ELSE NULL::timestamptz
    END AS redeemed_at,
    COALESCE(wl.expired_amount, 0) AS expired_amount,
    CASE
      WHEN COALESCE(wl.expired_amount, 0) > 0 THEN wl.expiry_processed_at
      ELSE NULL::timestamptz
    END AS expired_at,
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
