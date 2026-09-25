BEGIN;
UPDATE wallet_ledger SET deductible_balance = 351.0 WHERE id = 'dfe66d0e-e40a-4ea5-9af1-45f46920fdd2'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = '69a18985-553a-40b5-bfa2-605e6959a26e'::uuid;
DO $v$
DECLARE w numeric; l numeric;
BEGIN
  SELECT points_balance INTO w FROM user_wallet WHERE user_id = '69a18985-553a-40b5-bfa2-605e6959a26e'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid;
  SELECT coalesce(sum(deductible_balance),0) INTO l FROM wallet_ledger
    WHERE user_id = '69a18985-553a-40b5-bfa2-605e6959a26e'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid
      AND currency = 'points' AND transaction_type = 'earn';
  IF abs(w - l) > 0.01 THEN
    RAISE EXCEPTION 'post-apply invariant user % wallet % lots %', '69a18985-553a-40b5-bfa2-605e6959a26e', w, l;
  END IF;
END $v$;
COMMIT;
