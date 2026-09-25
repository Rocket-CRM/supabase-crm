BEGIN;
UPDATE wallet_ledger SET deductible_balance = 20.0 WHERE id = '37f9c0cc-3e97-4537-8b78-2be3331ef532'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = '5c4bd772-99e3-43a7-8e74-9bd70d73d96c'::uuid;
DO $v$
DECLARE w numeric; l numeric;
BEGIN
  SELECT points_balance INTO w FROM user_wallet WHERE user_id = '5c4bd772-99e3-43a7-8e74-9bd70d73d96c'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid;
  SELECT coalesce(sum(deductible_balance),0) INTO l FROM wallet_ledger
    WHERE user_id = '5c4bd772-99e3-43a7-8e74-9bd70d73d96c'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid
      AND currency = 'points' AND transaction_type = 'earn';
  IF abs(w - l) > 0.01 THEN
    RAISE EXCEPTION 'post-apply invariant user % wallet % lots %', '5c4bd772-99e3-43a7-8e74-9bd70d73d96c', w, l;
  END IF;
END $v$;
COMMIT;
