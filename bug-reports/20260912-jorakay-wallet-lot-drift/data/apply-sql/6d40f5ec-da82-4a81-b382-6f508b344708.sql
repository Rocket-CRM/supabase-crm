BEGIN;
UPDATE wallet_ledger SET deductible_balance = 116.0 WHERE id = '0dd99d04-b15e-4fe8-b674-79d7f7264492'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = '6d40f5ec-da82-4a81-b382-6f508b344708'::uuid;
UPDATE wallet_ledger SET deductible_balance = 110.0 WHERE id = '21f2ec06-fd83-45c4-bafa-625844f24fd0'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = '6d40f5ec-da82-4a81-b382-6f508b344708'::uuid;
DO $v$
DECLARE w numeric; l numeric;
BEGIN
  SELECT points_balance INTO w FROM user_wallet WHERE user_id = '6d40f5ec-da82-4a81-b382-6f508b344708'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid;
  SELECT coalesce(sum(deductible_balance),0) INTO l FROM wallet_ledger
    WHERE user_id = '6d40f5ec-da82-4a81-b382-6f508b344708'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid
      AND currency = 'points' AND transaction_type = 'earn';
  IF abs(w - l) > 0.01 THEN
    RAISE EXCEPTION 'post-apply invariant user % wallet % lots %', '6d40f5ec-da82-4a81-b382-6f508b344708', w, l;
  END IF;
END $v$;
COMMIT;
