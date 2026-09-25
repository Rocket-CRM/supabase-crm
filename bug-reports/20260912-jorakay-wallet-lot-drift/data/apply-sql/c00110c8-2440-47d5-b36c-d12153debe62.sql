BEGIN;
UPDATE wallet_ledger SET deductible_balance = 104.0 WHERE id = '9000b8f3-c49c-42e9-8c5d-f20e91c330ec'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = 'c00110c8-2440-47d5-b36c-d12153debe62'::uuid;
UPDATE wallet_ledger SET deductible_balance = 140.0 WHERE id = '79d60703-89de-47ba-a63e-409e9e24de46'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = 'c00110c8-2440-47d5-b36c-d12153debe62'::uuid;
DO $v$
DECLARE w numeric; l numeric;
BEGIN
  SELECT points_balance INTO w FROM user_wallet WHERE user_id = 'c00110c8-2440-47d5-b36c-d12153debe62'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid;
  SELECT coalesce(sum(deductible_balance),0) INTO l FROM wallet_ledger
    WHERE user_id = 'c00110c8-2440-47d5-b36c-d12153debe62'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid
      AND currency = 'points' AND transaction_type = 'earn';
  IF abs(w - l) > 0.01 THEN
    RAISE EXCEPTION 'post-apply invariant user % wallet % lots %', 'c00110c8-2440-47d5-b36c-d12153debe62', w, l;
  END IF;
END $v$;
COMMIT;
