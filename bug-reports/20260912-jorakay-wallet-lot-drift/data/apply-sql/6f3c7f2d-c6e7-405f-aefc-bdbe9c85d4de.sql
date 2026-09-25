BEGIN;
UPDATE wallet_ledger SET deductible_balance = 81.0 WHERE id = '110cfa8b-aecf-4785-8add-86fa710f923e'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = '6f3c7f2d-c6e7-405f-aefc-bdbe9c85d4de'::uuid;
DO $v$
DECLARE w numeric; l numeric;
BEGIN
  SELECT points_balance INTO w FROM user_wallet WHERE user_id = '6f3c7f2d-c6e7-405f-aefc-bdbe9c85d4de'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid;
  SELECT coalesce(sum(deductible_balance),0) INTO l FROM wallet_ledger
    WHERE user_id = '6f3c7f2d-c6e7-405f-aefc-bdbe9c85d4de'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid
      AND currency = 'points' AND transaction_type = 'earn';
  IF abs(w - l) > 0.01 THEN
    RAISE EXCEPTION 'post-apply invariant user % wallet % lots %', '6f3c7f2d-c6e7-405f-aefc-bdbe9c85d4de', w, l;
  END IF;
END $v$;
COMMIT;
