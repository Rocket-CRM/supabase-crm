BEGIN;
UPDATE wallet_ledger SET deductible_balance = 75.0 WHERE id = 'bab24a83-83de-43aa-a93a-341c2474c38a'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = '373221c3-c3b2-4e82-ae2f-dc471078e042'::uuid;
DO $v$
DECLARE w numeric; l numeric;
BEGIN
  SELECT points_balance INTO w FROM user_wallet WHERE user_id = '373221c3-c3b2-4e82-ae2f-dc471078e042'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid;
  SELECT coalesce(sum(deductible_balance),0) INTO l FROM wallet_ledger
    WHERE user_id = '373221c3-c3b2-4e82-ae2f-dc471078e042'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid
      AND currency = 'points' AND transaction_type = 'earn';
  IF abs(w - l) > 0.01 THEN
    RAISE EXCEPTION 'post-apply invariant user % wallet % lots %', '373221c3-c3b2-4e82-ae2f-dc471078e042', w, l;
  END IF;
END $v$;
COMMIT;
