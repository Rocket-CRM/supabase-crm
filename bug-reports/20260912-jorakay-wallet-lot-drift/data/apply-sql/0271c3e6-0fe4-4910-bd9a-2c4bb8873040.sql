BEGIN;
UPDATE wallet_ledger SET deductible_balance = 1.0 WHERE id = '2e19c896-6dea-4e39-86a5-43b0f09604cb'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = '0271c3e6-0fe4-4910-bd9a-2c4bb8873040'::uuid;
DO $v$
DECLARE w numeric; l numeric;
BEGIN
  SELECT points_balance INTO w FROM user_wallet WHERE user_id = '0271c3e6-0fe4-4910-bd9a-2c4bb8873040'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid;
  SELECT coalesce(sum(deductible_balance),0) INTO l FROM wallet_ledger
    WHERE user_id = '0271c3e6-0fe4-4910-bd9a-2c4bb8873040'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid
      AND currency = 'points' AND transaction_type = 'earn';
  IF abs(w - l) > 0.01 THEN
    RAISE EXCEPTION 'post-apply invariant user % wallet % lots %', '0271c3e6-0fe4-4910-bd9a-2c4bb8873040', w, l;
  END IF;
END $v$;
COMMIT;
