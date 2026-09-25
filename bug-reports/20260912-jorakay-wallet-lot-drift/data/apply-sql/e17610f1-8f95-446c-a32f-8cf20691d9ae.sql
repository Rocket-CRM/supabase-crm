BEGIN;
UPDATE wallet_ledger SET deductible_balance = 351.0 WHERE id = '48950ad3-ea96-45ba-85cf-990e4ab3a9fd'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = 'e17610f1-8f95-446c-a32f-8cf20691d9ae'::uuid;
UPDATE wallet_ledger SET deductible_balance = 20.0 WHERE id = '64213f8c-0bc5-4a8e-9933-7c917eada2c1'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = 'e17610f1-8f95-446c-a32f-8cf20691d9ae'::uuid;
DO $v$
DECLARE w numeric; l numeric;
BEGIN
  SELECT points_balance INTO w FROM user_wallet WHERE user_id = 'e17610f1-8f95-446c-a32f-8cf20691d9ae'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid;
  SELECT coalesce(sum(deductible_balance),0) INTO l FROM wallet_ledger
    WHERE user_id = 'e17610f1-8f95-446c-a32f-8cf20691d9ae'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid
      AND currency = 'points' AND transaction_type = 'earn';
  IF abs(w - l) > 0.01 THEN
    RAISE EXCEPTION 'post-apply invariant user % wallet % lots %', 'e17610f1-8f95-446c-a32f-8cf20691d9ae', w, l;
  END IF;
END $v$;
COMMIT;
