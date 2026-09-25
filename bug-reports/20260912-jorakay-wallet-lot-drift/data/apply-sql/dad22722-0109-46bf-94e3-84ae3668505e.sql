BEGIN;
UPDATE wallet_ledger SET deductible_balance = 7.0 WHERE id = 'af75d15e-cb51-48b1-aa6e-8a34d85a789e'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = 'dad22722-0109-46bf-94e3-84ae3668505e'::uuid;
UPDATE wallet_ledger SET deductible_balance = 1.0 WHERE id = 'e0f7aac4-6c08-453a-9fdc-04077dcada2b'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = 'dad22722-0109-46bf-94e3-84ae3668505e'::uuid;
UPDATE wallet_ledger SET deductible_balance = 30.0 WHERE id = '882a6794-7b69-4361-88d5-4e7b0a0afbe1'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = 'dad22722-0109-46bf-94e3-84ae3668505e'::uuid;
UPDATE wallet_ledger SET deductible_balance = 12.0 WHERE id = '8afe7647-54e2-4dc4-9773-16c2320c183d'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = 'dad22722-0109-46bf-94e3-84ae3668505e'::uuid;
UPDATE wallet_ledger SET deductible_balance = 68.0 WHERE id = '6f2bacb2-429e-41de-905f-537e20ff8917'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = 'dad22722-0109-46bf-94e3-84ae3668505e'::uuid;
DO $v$
DECLARE w numeric; l numeric;
BEGIN
  SELECT points_balance INTO w FROM user_wallet WHERE user_id = 'dad22722-0109-46bf-94e3-84ae3668505e'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid;
  SELECT coalesce(sum(deductible_balance),0) INTO l FROM wallet_ledger
    WHERE user_id = 'dad22722-0109-46bf-94e3-84ae3668505e'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid
      AND currency = 'points' AND transaction_type = 'earn';
  IF abs(w - l) > 0.01 THEN
    RAISE EXCEPTION 'post-apply invariant user % wallet % lots %', 'dad22722-0109-46bf-94e3-84ae3668505e', w, l;
  END IF;
END $v$;
COMMIT;
