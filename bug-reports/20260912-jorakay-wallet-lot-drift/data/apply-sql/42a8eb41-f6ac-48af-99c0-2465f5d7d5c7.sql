BEGIN;
UPDATE wallet_ledger SET deductible_balance = 32.0 WHERE id = '1500beff-8e66-49a4-a63b-ae6d26948cad'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = '42a8eb41-f6ac-48af-99c0-2465f5d7d5c7'::uuid;
DO $v$
DECLARE w numeric; l numeric;
BEGIN
  SELECT points_balance INTO w FROM user_wallet WHERE user_id = '42a8eb41-f6ac-48af-99c0-2465f5d7d5c7'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid;
  SELECT coalesce(sum(deductible_balance),0) INTO l FROM wallet_ledger
    WHERE user_id = '42a8eb41-f6ac-48af-99c0-2465f5d7d5c7'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid
      AND currency = 'points' AND transaction_type = 'earn';
  IF abs(w - l) > 0.01 THEN
    RAISE EXCEPTION 'post-apply invariant user % wallet % lots %', '42a8eb41-f6ac-48af-99c0-2465f5d7d5c7', w, l;
  END IF;
END $v$;
COMMIT;
