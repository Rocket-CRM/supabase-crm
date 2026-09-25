BEGIN;
UPDATE wallet_ledger SET deductible_balance = 0.0 WHERE id = '80350bf4-0e37-4210-93a4-0691d4f90b5c'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = '16b6dfbd-2f08-4f25-979f-b795f5d6f1ff'::uuid;
UPDATE wallet_ledger SET deductible_balance = 0.0 WHERE id = 'ba25ddda-65b4-40c9-9e84-a5461c4a4daf'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = '16b6dfbd-2f08-4f25-979f-b795f5d6f1ff'::uuid;
DO $v$
DECLARE w numeric; l numeric;
BEGIN
  SELECT points_balance INTO w FROM user_wallet WHERE user_id = '16b6dfbd-2f08-4f25-979f-b795f5d6f1ff'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid;
  SELECT coalesce(sum(deductible_balance),0) INTO l FROM wallet_ledger
    WHERE user_id = '16b6dfbd-2f08-4f25-979f-b795f5d6f1ff'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid
      AND currency = 'points' AND transaction_type = 'earn';
  IF abs(w - l) > 0.01 THEN
    RAISE EXCEPTION 'post-apply invariant user % wallet % lots %', '16b6dfbd-2f08-4f25-979f-b795f5d6f1ff', w, l;
  END IF;
END $v$;
COMMIT;
