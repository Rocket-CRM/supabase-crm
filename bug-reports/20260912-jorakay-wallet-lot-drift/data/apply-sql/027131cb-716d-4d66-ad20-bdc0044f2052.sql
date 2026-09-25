BEGIN;
UPDATE wallet_ledger SET deductible_balance = 26.0 WHERE id = 'a7669ce7-73ea-4093-9aa5-32f419785eb4'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = '027131cb-716d-4d66-ad20-bdc0044f2052'::uuid;
DO $v$
DECLARE w numeric; l numeric;
BEGIN
  SELECT points_balance INTO w FROM user_wallet WHERE user_id = '027131cb-716d-4d66-ad20-bdc0044f2052'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid;
  SELECT coalesce(sum(deductible_balance),0) INTO l FROM wallet_ledger
    WHERE user_id = '027131cb-716d-4d66-ad20-bdc0044f2052'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid
      AND currency = 'points' AND transaction_type = 'earn';
  IF abs(w - l) > 0.01 THEN
    RAISE EXCEPTION 'post-apply invariant user % wallet % lots %', '027131cb-716d-4d66-ad20-bdc0044f2052', w, l;
  END IF;
END $v$;
COMMIT;
