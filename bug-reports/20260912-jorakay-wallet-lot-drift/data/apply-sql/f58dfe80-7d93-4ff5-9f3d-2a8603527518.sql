BEGIN;
UPDATE wallet_ledger SET deductible_balance = 22.0 WHERE id = '42bd15d2-adbf-42b7-bb5d-70dfbe60de01'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = 'f58dfe80-7d93-4ff5-9f3d-2a8603527518'::uuid;
UPDATE wallet_ledger SET deductible_balance = 33.0 WHERE id = 'b62fd1be-b958-4b56-8234-bb5692e1c3dd'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = 'f58dfe80-7d93-4ff5-9f3d-2a8603527518'::uuid;
UPDATE wallet_ledger SET deductible_balance = 13.0 WHERE id = 'fd6d2302-d8f7-4ec8-8c2a-0a15228a70f7'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = 'f58dfe80-7d93-4ff5-9f3d-2a8603527518'::uuid;
UPDATE wallet_ledger SET deductible_balance = 18.0 WHERE id = '6386bc66-d24d-405c-b621-f01c271c9534'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = 'f58dfe80-7d93-4ff5-9f3d-2a8603527518'::uuid;
DO $v$
DECLARE w numeric; l numeric;
BEGIN
  SELECT points_balance INTO w FROM user_wallet WHERE user_id = 'f58dfe80-7d93-4ff5-9f3d-2a8603527518'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid;
  SELECT coalesce(sum(deductible_balance),0) INTO l FROM wallet_ledger
    WHERE user_id = 'f58dfe80-7d93-4ff5-9f3d-2a8603527518'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid
      AND currency = 'points' AND transaction_type = 'earn';
  IF abs(w - l) > 0.01 THEN
    RAISE EXCEPTION 'post-apply invariant user % wallet % lots %', 'f58dfe80-7d93-4ff5-9f3d-2a8603527518', w, l;
  END IF;
END $v$;
COMMIT;
