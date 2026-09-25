BEGIN;
UPDATE wallet_ledger SET deductible_balance = 0.0 WHERE id = 'ea430c8e-805f-4b5b-800b-17757e53226c'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = 'd5312302-f9a8-49e6-bdc0-e3b49c4c1757'::uuid;
UPDATE wallet_ledger SET deductible_balance = 0.0 WHERE id = '122461b4-d3ab-4832-88f8-012c60b68910'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = 'd5312302-f9a8-49e6-bdc0-e3b49c4c1757'::uuid;
UPDATE wallet_ledger SET deductible_balance = 0.0 WHERE id = '2c8c64d7-c6ea-4799-9290-078f947a8949'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = 'd5312302-f9a8-49e6-bdc0-e3b49c4c1757'::uuid;
UPDATE wallet_ledger SET deductible_balance = 0.0 WHERE id = 'a52edf01-5d5e-4bd7-86f7-87ea4431a538'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = 'd5312302-f9a8-49e6-bdc0-e3b49c4c1757'::uuid;
UPDATE wallet_ledger SET deductible_balance = 74.0 WHERE id = '5d93643e-4c30-4825-9ee2-c7b312ddf601'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = 'd5312302-f9a8-49e6-bdc0-e3b49c4c1757'::uuid;
UPDATE wallet_ledger SET deductible_balance = 107.0 WHERE id = '2059a042-d4d0-466b-b445-779f49b81718'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = 'd5312302-f9a8-49e6-bdc0-e3b49c4c1757'::uuid;
UPDATE wallet_ledger SET deductible_balance = 2842.0 WHERE id = '7dcfed60-b3c9-4ed1-9abb-2d6ec3a59b04'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = 'd5312302-f9a8-49e6-bdc0-e3b49c4c1757'::uuid;
UPDATE wallet_ledger SET deductible_balance = 425.0 WHERE id = 'bd81c0d8-9ccb-4031-a375-cd55d4696002'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = 'd5312302-f9a8-49e6-bdc0-e3b49c4c1757'::uuid;
UPDATE wallet_ledger SET deductible_balance = 418.0 WHERE id = 'b12823ee-4bbb-4820-aa9e-017dc1937983'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = 'd5312302-f9a8-49e6-bdc0-e3b49c4c1757'::uuid;
DO $v$
DECLARE w numeric; l numeric;
BEGIN
  SELECT points_balance INTO w FROM user_wallet WHERE user_id = 'd5312302-f9a8-49e6-bdc0-e3b49c4c1757'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid;
  SELECT coalesce(sum(deductible_balance),0) INTO l FROM wallet_ledger
    WHERE user_id = 'd5312302-f9a8-49e6-bdc0-e3b49c4c1757'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid
      AND currency = 'points' AND transaction_type = 'earn';
  IF abs(w - l) > 0.01 THEN
    RAISE EXCEPTION 'post-apply invariant user % wallet % lots %', 'd5312302-f9a8-49e6-bdc0-e3b49c4c1757', w, l;
  END IF;
END $v$;
COMMIT;
