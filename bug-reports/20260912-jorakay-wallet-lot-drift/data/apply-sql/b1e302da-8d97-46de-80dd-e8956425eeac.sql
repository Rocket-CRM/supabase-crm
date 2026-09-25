BEGIN;
UPDATE wallet_ledger SET deductible_balance = 125.0 WHERE id = 'f544fcb0-e1ab-4b93-937e-86e2bd3d41a9'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = 'b1e302da-8d97-46de-80dd-e8956425eeac'::uuid;
UPDATE wallet_ledger SET deductible_balance = 36.0 WHERE id = 'd74bf7f1-d8a9-4c26-b3b9-5e3ed0827e1d'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = 'b1e302da-8d97-46de-80dd-e8956425eeac'::uuid;
UPDATE wallet_ledger SET deductible_balance = 1.0 WHERE id = '3e674da9-29dd-452d-921c-8fe1583df745'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = 'b1e302da-8d97-46de-80dd-e8956425eeac'::uuid;
UPDATE wallet_ledger SET deductible_balance = 13.0 WHERE id = '7fb8c3c9-b762-4a8a-bba8-36ad2ebc6514'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = 'b1e302da-8d97-46de-80dd-e8956425eeac'::uuid;
UPDATE wallet_ledger SET deductible_balance = 4.0 WHERE id = '176716b6-e1ca-4de0-be55-ada4e9df7795'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = 'b1e302da-8d97-46de-80dd-e8956425eeac'::uuid;
DO $v$
DECLARE w numeric; l numeric;
BEGIN
  SELECT points_balance INTO w FROM user_wallet WHERE user_id = 'b1e302da-8d97-46de-80dd-e8956425eeac'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid;
  SELECT coalesce(sum(deductible_balance),0) INTO l FROM wallet_ledger
    WHERE user_id = 'b1e302da-8d97-46de-80dd-e8956425eeac'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid
      AND currency = 'points' AND transaction_type = 'earn';
  IF abs(w - l) > 0.01 THEN
    RAISE EXCEPTION 'post-apply invariant user % wallet % lots %', 'b1e302da-8d97-46de-80dd-e8956425eeac', w, l;
  END IF;
END $v$;
COMMIT;
