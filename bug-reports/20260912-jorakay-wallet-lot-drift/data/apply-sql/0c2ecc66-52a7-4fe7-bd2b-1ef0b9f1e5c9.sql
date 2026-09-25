BEGIN;
UPDATE wallet_ledger SET deductible_balance = 12.0 WHERE id = '040dbd68-fb07-42b2-8a9c-7003feabf83f'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = '0c2ecc66-52a7-4fe7-bd2b-1ef0b9f1e5c9'::uuid;
UPDATE wallet_ledger SET deductible_balance = 33.0 WHERE id = 'b98bbf81-4e47-471a-bf35-19d05ae50fbc'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = '0c2ecc66-52a7-4fe7-bd2b-1ef0b9f1e5c9'::uuid;
UPDATE wallet_ledger SET deductible_balance = 31.0 WHERE id = '983459b9-54b0-4e7e-9657-ede5f735a7dd'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = '0c2ecc66-52a7-4fe7-bd2b-1ef0b9f1e5c9'::uuid;
UPDATE wallet_ledger SET deductible_balance = 23.0 WHERE id = '9685be81-b8aa-43f2-948c-119e286972de'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = '0c2ecc66-52a7-4fe7-bd2b-1ef0b9f1e5c9'::uuid;
UPDATE wallet_ledger SET deductible_balance = 4.0 WHERE id = '741d3aa0-f030-47c9-a8ef-41f3e91e251c'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = '0c2ecc66-52a7-4fe7-bd2b-1ef0b9f1e5c9'::uuid;
UPDATE wallet_ledger SET deductible_balance = 10.0 WHERE id = '24450544-570d-4e59-93a4-928161952563'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = '0c2ecc66-52a7-4fe7-bd2b-1ef0b9f1e5c9'::uuid;
UPDATE wallet_ledger SET deductible_balance = 6.0 WHERE id = '20a5df70-3dba-4e13-88ef-317da9793100'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = '0c2ecc66-52a7-4fe7-bd2b-1ef0b9f1e5c9'::uuid;
DO $v$
DECLARE w numeric; l numeric;
BEGIN
  SELECT points_balance INTO w FROM user_wallet WHERE user_id = '0c2ecc66-52a7-4fe7-bd2b-1ef0b9f1e5c9'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid;
  SELECT coalesce(sum(deductible_balance),0) INTO l FROM wallet_ledger
    WHERE user_id = '0c2ecc66-52a7-4fe7-bd2b-1ef0b9f1e5c9'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid
      AND currency = 'points' AND transaction_type = 'earn';
  IF abs(w - l) > 0.01 THEN
    RAISE EXCEPTION 'post-apply invariant user % wallet % lots %', '0c2ecc66-52a7-4fe7-bd2b-1ef0b9f1e5c9', w, l;
  END IF;
END $v$;
COMMIT;
