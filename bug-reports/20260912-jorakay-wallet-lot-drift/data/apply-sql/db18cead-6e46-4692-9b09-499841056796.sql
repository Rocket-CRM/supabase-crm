BEGIN;
UPDATE wallet_ledger SET deductible_balance = 60.0 WHERE id = '7188bcce-77a2-4290-857a-3da3173f3ced'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = 'db18cead-6e46-4692-9b09-499841056796'::uuid;
DO $v$
DECLARE w numeric; l numeric;
BEGIN
  SELECT points_balance INTO w FROM user_wallet WHERE user_id = 'db18cead-6e46-4692-9b09-499841056796'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid;
  SELECT coalesce(sum(deductible_balance),0) INTO l FROM wallet_ledger
    WHERE user_id = 'db18cead-6e46-4692-9b09-499841056796'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid
      AND currency = 'points' AND transaction_type = 'earn';
  IF abs(w - l) > 0.01 THEN
    RAISE EXCEPTION 'post-apply invariant user % wallet % lots %', 'db18cead-6e46-4692-9b09-499841056796', w, l;
  END IF;
END $v$;
COMMIT;
