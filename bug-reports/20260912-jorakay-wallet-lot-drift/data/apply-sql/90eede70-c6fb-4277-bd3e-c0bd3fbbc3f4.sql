BEGIN;
UPDATE wallet_ledger SET deductible_balance = 132.0 WHERE id = '65a9b717-e953-4563-849e-69e09ca19979'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = '90eede70-c6fb-4277-bd3e-c0bd3fbbc3f4'::uuid;
UPDATE wallet_ledger SET deductible_balance = 57.0 WHERE id = '7a5d3b8e-d764-4264-8644-9d89fdf78be3'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = '90eede70-c6fb-4277-bd3e-c0bd3fbbc3f4'::uuid;
DO $v$
DECLARE w numeric; l numeric;
BEGIN
  SELECT points_balance INTO w FROM user_wallet WHERE user_id = '90eede70-c6fb-4277-bd3e-c0bd3fbbc3f4'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid;
  SELECT coalesce(sum(deductible_balance),0) INTO l FROM wallet_ledger
    WHERE user_id = '90eede70-c6fb-4277-bd3e-c0bd3fbbc3f4'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid
      AND currency = 'points' AND transaction_type = 'earn';
  IF abs(w - l) > 0.01 THEN
    RAISE EXCEPTION 'post-apply invariant user % wallet % lots %', '90eede70-c6fb-4277-bd3e-c0bd3fbbc3f4', w, l;
  END IF;
END $v$;
COMMIT;
