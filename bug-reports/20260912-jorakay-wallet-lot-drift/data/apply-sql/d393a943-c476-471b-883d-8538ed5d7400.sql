BEGIN;
UPDATE wallet_ledger SET deductible_balance = 385.0 WHERE id = '78405f24-4352-48c0-acf8-9b50e107b973'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = 'd393a943-c476-471b-883d-8538ed5d7400'::uuid;
UPDATE wallet_ledger SET deductible_balance = 360.0 WHERE id = '94855c81-05d3-407e-a8ac-d9df2d1c00e1'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = 'd393a943-c476-471b-883d-8538ed5d7400'::uuid;
UPDATE wallet_ledger SET deductible_balance = 17.0 WHERE id = '15a20d7a-011d-438b-8995-748e44a17d09'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = 'd393a943-c476-471b-883d-8538ed5d7400'::uuid;
UPDATE wallet_ledger SET deductible_balance = 138.0 WHERE id = 'a0500c09-15e3-4473-9c06-65498934b419'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = 'd393a943-c476-471b-883d-8538ed5d7400'::uuid;
UPDATE wallet_ledger SET deductible_balance = 47.0 WHERE id = 'a4f9c43f-1c45-4085-a453-2b61b63e15cb'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = 'd393a943-c476-471b-883d-8538ed5d7400'::uuid;
DO $v$
DECLARE w numeric; l numeric;
BEGIN
  SELECT points_balance INTO w FROM user_wallet WHERE user_id = 'd393a943-c476-471b-883d-8538ed5d7400'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid;
  SELECT coalesce(sum(deductible_balance),0) INTO l FROM wallet_ledger
    WHERE user_id = 'd393a943-c476-471b-883d-8538ed5d7400'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid
      AND currency = 'points' AND transaction_type = 'earn';
  IF abs(w - l) > 0.01 THEN
    RAISE EXCEPTION 'post-apply invariant user % wallet % lots %', 'd393a943-c476-471b-883d-8538ed5d7400', w, l;
  END IF;
END $v$;
COMMIT;
