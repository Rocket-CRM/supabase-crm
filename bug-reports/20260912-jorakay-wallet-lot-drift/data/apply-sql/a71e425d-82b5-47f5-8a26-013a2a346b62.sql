BEGIN;
UPDATE wallet_ledger SET deductible_balance = 42.0 WHERE id = '578d7ac5-1a0c-40f6-857d-d27ced95d459'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = 'a71e425d-82b5-47f5-8a26-013a2a346b62'::uuid;
UPDATE wallet_ledger SET deductible_balance = 5.0 WHERE id = '000957b9-63a5-4a9c-b8c6-a703c11fb83f'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = 'a71e425d-82b5-47f5-8a26-013a2a346b62'::uuid;
UPDATE wallet_ledger SET deductible_balance = 41.0 WHERE id = 'ab492e9c-133c-48e4-80da-799b6f6e02ba'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = 'a71e425d-82b5-47f5-8a26-013a2a346b62'::uuid;
UPDATE wallet_ledger SET deductible_balance = 17.0 WHERE id = '8a94985e-0b27-41f5-a504-91fd0964addd'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = 'a71e425d-82b5-47f5-8a26-013a2a346b62'::uuid;
UPDATE wallet_ledger SET deductible_balance = 15.0 WHERE id = '598b588d-44db-48ad-8939-8728c8bf4f08'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = 'a71e425d-82b5-47f5-8a26-013a2a346b62'::uuid;
DO $v$
DECLARE w numeric; l numeric;
BEGIN
  SELECT points_balance INTO w FROM user_wallet WHERE user_id = 'a71e425d-82b5-47f5-8a26-013a2a346b62'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid;
  SELECT coalesce(sum(deductible_balance),0) INTO l FROM wallet_ledger
    WHERE user_id = 'a71e425d-82b5-47f5-8a26-013a2a346b62'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid
      AND currency = 'points' AND transaction_type = 'earn';
  IF abs(w - l) > 0.01 THEN
    RAISE EXCEPTION 'post-apply invariant user % wallet % lots %', 'a71e425d-82b5-47f5-8a26-013a2a346b62', w, l;
  END IF;
END $v$;
COMMIT;
