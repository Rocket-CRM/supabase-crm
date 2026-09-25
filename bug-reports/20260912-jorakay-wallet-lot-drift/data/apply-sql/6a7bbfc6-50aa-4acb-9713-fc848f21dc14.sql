BEGIN;
UPDATE wallet_ledger SET deductible_balance = 62.0 WHERE id = 'bc767d2a-54ef-43aa-909c-c46ff123520c'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = '6a7bbfc6-50aa-4acb-9713-fc848f21dc14'::uuid;
DO $v$
DECLARE w numeric; l numeric;
BEGIN
  SELECT points_balance INTO w FROM user_wallet WHERE user_id = '6a7bbfc6-50aa-4acb-9713-fc848f21dc14'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid;
  SELECT coalesce(sum(deductible_balance),0) INTO l FROM wallet_ledger
    WHERE user_id = '6a7bbfc6-50aa-4acb-9713-fc848f21dc14'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid
      AND currency = 'points' AND transaction_type = 'earn';
  IF abs(w - l) > 0.01 THEN
    RAISE EXCEPTION 'post-apply invariant user % wallet % lots %', '6a7bbfc6-50aa-4acb-9713-fc848f21dc14', w, l;
  END IF;
END $v$;
COMMIT;
