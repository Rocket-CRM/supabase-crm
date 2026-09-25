BEGIN;
UPDATE wallet_ledger SET deductible_balance = 162.0 WHERE id = '969ce393-c5c2-474a-8131-fbc7665cea78'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = '000a4cba-d5e7-4c62-8a2a-c49437012e18'::uuid;
DO $v$
DECLARE w numeric; l numeric;
BEGIN
  SELECT points_balance INTO w FROM user_wallet WHERE user_id = '000a4cba-d5e7-4c62-8a2a-c49437012e18'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid;
  SELECT coalesce(sum(deductible_balance),0) INTO l FROM wallet_ledger
    WHERE user_id = '000a4cba-d5e7-4c62-8a2a-c49437012e18'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid
      AND currency = 'points' AND transaction_type = 'earn';
  IF abs(w - l) > 0.01 THEN
    RAISE EXCEPTION 'post-apply invariant user % wallet % lots %', '000a4cba-d5e7-4c62-8a2a-c49437012e18', w, l;
  END IF;
END $v$;
COMMIT;
