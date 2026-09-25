BEGIN;
UPDATE wallet_ledger SET deductible_balance = 10546.0 WHERE id = '1d5bdfe3-8c25-4f98-9833-dfcccdcf8cab'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = '5a7f8d5c-7152-41a0-b9de-13823334931b'::uuid;
UPDATE wallet_ledger SET deductible_balance = 448.0 WHERE id = '4e36172e-3dd2-4c46-991e-ca85ce3ed9ac'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = '5a7f8d5c-7152-41a0-b9de-13823334931b'::uuid;
DO $v$
DECLARE w numeric; l numeric;
BEGIN
  SELECT points_balance INTO w FROM user_wallet WHERE user_id = '5a7f8d5c-7152-41a0-b9de-13823334931b'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid;
  SELECT coalesce(sum(deductible_balance),0) INTO l FROM wallet_ledger
    WHERE user_id = '5a7f8d5c-7152-41a0-b9de-13823334931b'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid
      AND currency = 'points' AND transaction_type = 'earn';
  IF abs(w - l) > 0.01 THEN
    RAISE EXCEPTION 'post-apply invariant user % wallet % lots %', '5a7f8d5c-7152-41a0-b9de-13823334931b', w, l;
  END IF;
END $v$;
COMMIT;
