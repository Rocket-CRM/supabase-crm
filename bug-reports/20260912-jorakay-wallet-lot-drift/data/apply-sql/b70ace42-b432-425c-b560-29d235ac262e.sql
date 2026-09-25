BEGIN;
UPDATE wallet_ledger SET deductible_balance = 228.0 WHERE id = 'd45cfb90-f62a-434f-ab6e-c2a6ff3de709'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = 'b70ace42-b432-425c-b560-29d235ac262e'::uuid;
DO $v$
DECLARE w numeric; l numeric;
BEGIN
  SELECT points_balance INTO w FROM user_wallet WHERE user_id = 'b70ace42-b432-425c-b560-29d235ac262e'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid;
  SELECT coalesce(sum(deductible_balance),0) INTO l FROM wallet_ledger
    WHERE user_id = 'b70ace42-b432-425c-b560-29d235ac262e'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid
      AND currency = 'points' AND transaction_type = 'earn';
  IF abs(w - l) > 0.01 THEN
    RAISE EXCEPTION 'post-apply invariant user % wallet % lots %', 'b70ace42-b432-425c-b560-29d235ac262e', w, l;
  END IF;
END $v$;
COMMIT;
