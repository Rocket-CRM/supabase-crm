BEGIN;
UPDATE wallet_ledger SET deductible_balance = 0.0 WHERE id = 'bddff06e-d047-4d7e-b611-520e387b3f8d'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = 'aa7161bc-7cd6-4fec-bc36-83ebf135ad53'::uuid;
DO $v$
DECLARE w numeric; l numeric;
BEGIN
  SELECT points_balance INTO w FROM user_wallet WHERE user_id = 'aa7161bc-7cd6-4fec-bc36-83ebf135ad53'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid;
  SELECT coalesce(sum(deductible_balance),0) INTO l FROM wallet_ledger
    WHERE user_id = 'aa7161bc-7cd6-4fec-bc36-83ebf135ad53'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid
      AND currency = 'points' AND transaction_type = 'earn';
  IF abs(w - l) > 0.01 THEN
    RAISE EXCEPTION 'post-apply invariant user % wallet % lots %', 'aa7161bc-7cd6-4fec-bc36-83ebf135ad53', w, l;
  END IF;
END $v$;
COMMIT;
