BEGIN;
UPDATE wallet_ledger SET deductible_balance = 79.0 WHERE id = '1a6d92c0-e825-4eb7-b059-33e5d0d0bb42'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = '491b5e4f-bc49-43bb-920c-ed40018230f0'::uuid;
DO $v$
DECLARE w numeric; l numeric;
BEGIN
  SELECT points_balance INTO w FROM user_wallet WHERE user_id = '491b5e4f-bc49-43bb-920c-ed40018230f0'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid;
  SELECT coalesce(sum(deductible_balance),0) INTO l FROM wallet_ledger
    WHERE user_id = '491b5e4f-bc49-43bb-920c-ed40018230f0'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid
      AND currency = 'points' AND transaction_type = 'earn';
  IF abs(w - l) > 0.01 THEN
    RAISE EXCEPTION 'post-apply invariant user % wallet % lots %', '491b5e4f-bc49-43bb-920c-ed40018230f0', w, l;
  END IF;
END $v$;
COMMIT;
