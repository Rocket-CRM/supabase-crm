BEGIN;
UPDATE wallet_ledger SET deductible_balance = 0.0 WHERE id = '82833062-fc6b-4b69-a618-b4d12d67dbea'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = '871d5b20-c8de-4fb4-8065-565dc8522f6e'::uuid;
UPDATE wallet_ledger SET deductible_balance = 0.0 WHERE id = 'f89144ed-9e20-4be6-92a4-be889c64d25e'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = '871d5b20-c8de-4fb4-8065-565dc8522f6e'::uuid;
UPDATE wallet_ledger SET deductible_balance = 0.0 WHERE id = '90ec418e-fb4c-4d48-9f2d-a37a33dc50ff'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = '871d5b20-c8de-4fb4-8065-565dc8522f6e'::uuid;
UPDATE wallet_ledger SET deductible_balance = 0.0 WHERE id = '2ff3eb59-f227-4883-9943-a5af69bd21b2'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = '871d5b20-c8de-4fb4-8065-565dc8522f6e'::uuid;
UPDATE wallet_ledger SET deductible_balance = 0.0 WHERE id = '882817a7-88e1-4a42-aa17-732012e6420b'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = '871d5b20-c8de-4fb4-8065-565dc8522f6e'::uuid;
UPDATE wallet_ledger SET deductible_balance = 0.0 WHERE id = '43e1bd85-0fa5-4c77-8e2b-b36eab56d4c1'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = '871d5b20-c8de-4fb4-8065-565dc8522f6e'::uuid;
UPDATE wallet_ledger SET deductible_balance = 0.0 WHERE id = 'ead2ac34-144b-4044-8fc7-f079cd9624c7'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = '871d5b20-c8de-4fb4-8065-565dc8522f6e'::uuid;
UPDATE wallet_ledger SET deductible_balance = 0.0 WHERE id = '39e67647-e094-4501-b6ba-5a776d4911c3'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = '871d5b20-c8de-4fb4-8065-565dc8522f6e'::uuid;
UPDATE wallet_ledger SET deductible_balance = 0.0 WHERE id = '2e47a389-70a5-4697-8938-f17087975cf5'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = '871d5b20-c8de-4fb4-8065-565dc8522f6e'::uuid;
UPDATE wallet_ledger SET deductible_balance = 159.0 WHERE id = '191bf497-0e69-4228-bd6f-0be0b9c27f89'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = '871d5b20-c8de-4fb4-8065-565dc8522f6e'::uuid;
DO $v$
DECLARE w numeric; l numeric;
BEGIN
  SELECT points_balance INTO w FROM user_wallet WHERE user_id = '871d5b20-c8de-4fb4-8065-565dc8522f6e'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid;
  SELECT coalesce(sum(deductible_balance),0) INTO l FROM wallet_ledger
    WHERE user_id = '871d5b20-c8de-4fb4-8065-565dc8522f6e'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid
      AND currency = 'points' AND transaction_type = 'earn';
  IF abs(w - l) > 0.01 THEN
    RAISE EXCEPTION 'post-apply invariant user % wallet % lots %', '871d5b20-c8de-4fb4-8065-565dc8522f6e', w, l;
  END IF;
END $v$;
COMMIT;
