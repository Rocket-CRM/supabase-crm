BEGIN;
UPDATE wallet_ledger SET deductible_balance = 500.0 WHERE id = '05891ec5-94bc-432e-8807-a46614e95bd5'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = '1eb8999f-342f-4125-8270-daa7e3b1d570'::uuid;
DO $v$
DECLARE w numeric; l numeric;
BEGIN
  SELECT points_balance INTO w FROM user_wallet WHERE user_id = '1eb8999f-342f-4125-8270-daa7e3b1d570'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid;
  SELECT coalesce(sum(deductible_balance),0) INTO l FROM wallet_ledger
    WHERE user_id = '1eb8999f-342f-4125-8270-daa7e3b1d570'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid
      AND currency = 'points' AND transaction_type = 'earn';
  IF abs(w - l) > 0.01 THEN
    RAISE EXCEPTION 'post-apply invariant user % wallet % lots %', '1eb8999f-342f-4125-8270-daa7e3b1d570', w, l;
  END IF;
END $v$;
COMMIT;
