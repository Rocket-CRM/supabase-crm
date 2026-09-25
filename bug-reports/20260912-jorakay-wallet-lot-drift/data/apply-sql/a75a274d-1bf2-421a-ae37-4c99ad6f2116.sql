BEGIN;
UPDATE wallet_ledger SET deductible_balance = 154.0 WHERE id = '4c306b1e-1ad7-426c-93a3-7aac4b360743'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = 'a75a274d-1bf2-421a-ae37-4c99ad6f2116'::uuid;
DO $v$
DECLARE w numeric; l numeric;
BEGIN
  SELECT points_balance INTO w FROM user_wallet WHERE user_id = 'a75a274d-1bf2-421a-ae37-4c99ad6f2116'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid;
  SELECT coalesce(sum(deductible_balance),0) INTO l FROM wallet_ledger
    WHERE user_id = 'a75a274d-1bf2-421a-ae37-4c99ad6f2116'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid
      AND currency = 'points' AND transaction_type = 'earn';
  IF abs(w - l) > 0.01 THEN
    RAISE EXCEPTION 'post-apply invariant user % wallet % lots %', 'a75a274d-1bf2-421a-ae37-4c99ad6f2116', w, l;
  END IF;
END $v$;
COMMIT;
