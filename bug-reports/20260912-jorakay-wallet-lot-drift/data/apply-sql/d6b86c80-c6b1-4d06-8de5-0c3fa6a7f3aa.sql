BEGIN;
UPDATE wallet_ledger SET deductible_balance = 21.0 WHERE id = '07fecfd0-689e-4a36-9a45-abf4e3a1b355'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = 'd6b86c80-c6b1-4d06-8de5-0c3fa6a7f3aa'::uuid;
UPDATE wallet_ledger SET deductible_balance = 75.0 WHERE id = 'd282a5d4-306d-4c66-8f88-e824ef971562'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = 'd6b86c80-c6b1-4d06-8de5-0c3fa6a7f3aa'::uuid;
UPDATE wallet_ledger SET deductible_balance = 63.0 WHERE id = '96627d61-ae2e-4592-a900-66efc075db13'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = 'd6b86c80-c6b1-4d06-8de5-0c3fa6a7f3aa'::uuid;
UPDATE wallet_ledger SET deductible_balance = 114.0 WHERE id = '976b26c3-d32c-446e-8c4b-c61130feb66c'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = 'd6b86c80-c6b1-4d06-8de5-0c3fa6a7f3aa'::uuid;
DO $v$
DECLARE w numeric; l numeric;
BEGIN
  SELECT points_balance INTO w FROM user_wallet WHERE user_id = 'd6b86c80-c6b1-4d06-8de5-0c3fa6a7f3aa'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid;
  SELECT coalesce(sum(deductible_balance),0) INTO l FROM wallet_ledger
    WHERE user_id = 'd6b86c80-c6b1-4d06-8de5-0c3fa6a7f3aa'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid
      AND currency = 'points' AND transaction_type = 'earn';
  IF abs(w - l) > 0.01 THEN
    RAISE EXCEPTION 'post-apply invariant user % wallet % lots %', 'd6b86c80-c6b1-4d06-8de5-0c3fa6a7f3aa', w, l;
  END IF;
END $v$;
COMMIT;
