BEGIN;
UPDATE wallet_ledger SET deductible_balance = 0.0 WHERE id = '4bfffadc-c114-4ff2-9001-6dffe6f44525'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = '31705816-258b-4edc-b26b-e4e645cc80df'::uuid;
UPDATE wallet_ledger SET deductible_balance = 0.0 WHERE id = 'e1edbf72-7d8e-40ee-8052-06024459a86e'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = '31705816-258b-4edc-b26b-e4e645cc80df'::uuid;
UPDATE wallet_ledger SET deductible_balance = 0.0 WHERE id = '6a8a943a-de68-48fb-b693-dcf133f7e8d0'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = '31705816-258b-4edc-b26b-e4e645cc80df'::uuid;
UPDATE wallet_ledger SET deductible_balance = 0.0 WHERE id = '82ef18e8-66fd-43e1-8541-21bd8758c3ef'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = '31705816-258b-4edc-b26b-e4e645cc80df'::uuid;
UPDATE wallet_ledger SET deductible_balance = 0.0 WHERE id = '96b6a316-0960-47e1-adec-d31c087535bf'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = '31705816-258b-4edc-b26b-e4e645cc80df'::uuid;
UPDATE wallet_ledger SET deductible_balance = 0.0 WHERE id = '2d55ad16-735e-41a4-8849-58c39cbfea6e'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = '31705816-258b-4edc-b26b-e4e645cc80df'::uuid;
UPDATE wallet_ledger SET deductible_balance = 436.0 WHERE id = 'e58343d9-4321-433d-b318-bcd36d73cb7c'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = '31705816-258b-4edc-b26b-e4e645cc80df'::uuid;
DO $v$
DECLARE w numeric; l numeric;
BEGIN
  SELECT points_balance INTO w FROM user_wallet WHERE user_id = '31705816-258b-4edc-b26b-e4e645cc80df'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid;
  SELECT coalesce(sum(deductible_balance),0) INTO l FROM wallet_ledger
    WHERE user_id = '31705816-258b-4edc-b26b-e4e645cc80df'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid
      AND currency = 'points' AND transaction_type = 'earn';
  IF abs(w - l) > 0.01 THEN
    RAISE EXCEPTION 'post-apply invariant user % wallet % lots %', '31705816-258b-4edc-b26b-e4e645cc80df', w, l;
  END IF;
END $v$;
COMMIT;
