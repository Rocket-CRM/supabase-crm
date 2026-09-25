BEGIN;
UPDATE wallet_ledger SET deductible_balance = 0.0 WHERE id = '80cfc38d-482f-4ff5-bf48-b3c06440437a'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = 'a89f1104-c0f2-42e3-9735-5cb96506f5ae'::uuid;
UPDATE wallet_ledger SET deductible_balance = 0.0 WHERE id = 'c09a2804-27e2-4f0e-83f4-86cc9441935f'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = 'a89f1104-c0f2-42e3-9735-5cb96506f5ae'::uuid;
UPDATE wallet_ledger SET deductible_balance = 470.0 WHERE id = 'dbc19908-5bde-4896-b3b9-cdd718635776'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = 'a89f1104-c0f2-42e3-9735-5cb96506f5ae'::uuid;
UPDATE user_wallet SET points_balance = 7402.0 WHERE user_id = 'a89f1104-c0f2-42e3-9735-5cb96506f5ae'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid;
DO $v$
DECLARE w numeric; l numeric;
BEGIN
  SELECT points_balance INTO w FROM user_wallet WHERE user_id = 'a89f1104-c0f2-42e3-9735-5cb96506f5ae'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid;
  SELECT coalesce(sum(deductible_balance),0) INTO l FROM wallet_ledger
    WHERE user_id = 'a89f1104-c0f2-42e3-9735-5cb96506f5ae'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid
      AND currency = 'points' AND transaction_type = 'earn';
  IF abs(w - l) > 0.01 THEN
    RAISE EXCEPTION 'post-apply invariant user % wallet % lots %', 'a89f1104-c0f2-42e3-9735-5cb96506f5ae', w, l;
  END IF;
END $v$;
COMMIT;
