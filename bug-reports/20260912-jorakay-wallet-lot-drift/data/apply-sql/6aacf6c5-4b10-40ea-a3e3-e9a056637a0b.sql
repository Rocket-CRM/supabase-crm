BEGIN;
UPDATE wallet_ledger SET deductible_balance = 396.0 WHERE id = 'a377e829-a948-411d-b5ea-1ddde650a90d'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = '6aacf6c5-4b10-40ea-a3e3-e9a056637a0b'::uuid;
UPDATE wallet_ledger SET deductible_balance = 60.0 WHERE id = '56b11ce5-de8b-4143-8a10-998471cb0b27'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = '6aacf6c5-4b10-40ea-a3e3-e9a056637a0b'::uuid;
DO $v$
DECLARE w numeric; l numeric;
BEGIN
  SELECT points_balance INTO w FROM user_wallet WHERE user_id = '6aacf6c5-4b10-40ea-a3e3-e9a056637a0b'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid;
  SELECT coalesce(sum(deductible_balance),0) INTO l FROM wallet_ledger
    WHERE user_id = '6aacf6c5-4b10-40ea-a3e3-e9a056637a0b'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid
      AND currency = 'points' AND transaction_type = 'earn';
  IF abs(w - l) > 0.01 THEN
    RAISE EXCEPTION 'post-apply invariant user % wallet % lots %', '6aacf6c5-4b10-40ea-a3e3-e9a056637a0b', w, l;
  END IF;
END $v$;
COMMIT;
