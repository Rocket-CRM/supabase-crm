BEGIN;
UPDATE wallet_ledger SET deductible_balance = 158.0 WHERE id = 'ecc68ef7-fd00-4a8a-9b52-22b86f1d5eef'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = '0c03aeb9-727e-451d-80cb-f6eb767af872'::uuid;
UPDATE wallet_ledger SET deductible_balance = 495.0 WHERE id = '79781fb5-4b29-4758-b68f-2830d7081302'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = '0c03aeb9-727e-451d-80cb-f6eb767af872'::uuid;
UPDATE wallet_ledger SET deductible_balance = 94.0 WHERE id = 'eed72e8f-ed12-4bbc-9972-15c6d38a01ce'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = '0c03aeb9-727e-451d-80cb-f6eb767af872'::uuid;
UPDATE wallet_ledger SET deductible_balance = 120.0 WHERE id = '8fb46586-6382-4357-b137-f37b46a15180'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = '0c03aeb9-727e-451d-80cb-f6eb767af872'::uuid;
UPDATE wallet_ledger SET deductible_balance = 240.0 WHERE id = '953b490e-38b1-4ca3-904e-c3160eaa9e2d'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = '0c03aeb9-727e-451d-80cb-f6eb767af872'::uuid;
UPDATE wallet_ledger SET deductible_balance = 398.0 WHERE id = '040246b4-e581-4c80-9b4d-ddfc90baebbe'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = '0c03aeb9-727e-451d-80cb-f6eb767af872'::uuid;
UPDATE wallet_ledger SET deductible_balance = 195.0 WHERE id = '23bb5ed9-ad3c-412a-9e6d-6c31aa0d7d5d'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = '0c03aeb9-727e-451d-80cb-f6eb767af872'::uuid;
DO $v$
DECLARE w numeric; l numeric;
BEGIN
  SELECT points_balance INTO w FROM user_wallet WHERE user_id = '0c03aeb9-727e-451d-80cb-f6eb767af872'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid;
  SELECT coalesce(sum(deductible_balance),0) INTO l FROM wallet_ledger
    WHERE user_id = '0c03aeb9-727e-451d-80cb-f6eb767af872'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid
      AND currency = 'points' AND transaction_type = 'earn';
  IF abs(w - l) > 0.01 THEN
    RAISE EXCEPTION 'post-apply invariant user % wallet % lots %', '0c03aeb9-727e-451d-80cb-f6eb767af872', w, l;
  END IF;
END $v$;
COMMIT;
