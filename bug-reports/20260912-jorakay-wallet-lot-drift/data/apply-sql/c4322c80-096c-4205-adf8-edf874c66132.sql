BEGIN;
UPDATE wallet_ledger SET deductible_balance = 0.0 WHERE id = '78b2cd34-81c9-45bb-bcf7-81abcba8dc62'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = 'c4322c80-096c-4205-adf8-edf874c66132'::uuid;
UPDATE wallet_ledger SET deductible_balance = 213.0 WHERE id = '1e87914d-e9b5-487d-9cfd-bf94fb795fed'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = 'c4322c80-096c-4205-adf8-edf874c66132'::uuid;
DO $v$
DECLARE w numeric; l numeric;
BEGIN
  SELECT points_balance INTO w FROM user_wallet WHERE user_id = 'c4322c80-096c-4205-adf8-edf874c66132'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid;
  SELECT coalesce(sum(deductible_balance),0) INTO l FROM wallet_ledger
    WHERE user_id = 'c4322c80-096c-4205-adf8-edf874c66132'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid
      AND currency = 'points' AND transaction_type = 'earn';
  IF abs(w - l) > 0.01 THEN
    RAISE EXCEPTION 'post-apply invariant user % wallet % lots %', 'c4322c80-096c-4205-adf8-edf874c66132', w, l;
  END IF;
END $v$;
COMMIT;
