BEGIN;
UPDATE wallet_ledger SET deductible_balance = 0.0 WHERE id = '7abd7320-eb69-42d1-9436-ecf8e4fb42c6'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = '1ffbad86-6119-47b3-b152-77f4713a0f48'::uuid;
DO $v$
DECLARE w numeric; l numeric;
BEGIN
  SELECT points_balance INTO w FROM user_wallet WHERE user_id = '1ffbad86-6119-47b3-b152-77f4713a0f48'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid;
  SELECT coalesce(sum(deductible_balance),0) INTO l FROM wallet_ledger
    WHERE user_id = '1ffbad86-6119-47b3-b152-77f4713a0f48'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid
      AND currency = 'points' AND transaction_type = 'earn';
  IF abs(w - l) > 0.01 THEN
    RAISE EXCEPTION 'post-apply invariant user % wallet % lots %', '1ffbad86-6119-47b3-b152-77f4713a0f48', w, l;
  END IF;
END $v$;
COMMIT;
