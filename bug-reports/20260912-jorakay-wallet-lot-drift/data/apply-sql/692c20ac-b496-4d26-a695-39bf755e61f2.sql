BEGIN;
UPDATE wallet_ledger SET deductible_balance = 118.0 WHERE id = '001a6d75-b6a4-42d1-83fb-9428dd8e6b17'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = '692c20ac-b496-4d26-a695-39bf755e61f2'::uuid;
DO $v$
DECLARE w numeric; l numeric;
BEGIN
  SELECT points_balance INTO w FROM user_wallet WHERE user_id = '692c20ac-b496-4d26-a695-39bf755e61f2'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid;
  SELECT coalesce(sum(deductible_balance),0) INTO l FROM wallet_ledger
    WHERE user_id = '692c20ac-b496-4d26-a695-39bf755e61f2'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid
      AND currency = 'points' AND transaction_type = 'earn';
  IF abs(w - l) > 0.01 THEN
    RAISE EXCEPTION 'post-apply invariant user % wallet % lots %', '692c20ac-b496-4d26-a695-39bf755e61f2', w, l;
  END IF;
END $v$;
COMMIT;
