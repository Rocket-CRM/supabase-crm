BEGIN;
UPDATE wallet_ledger SET deductible_balance = 13.0 WHERE id = '8842b952-8d3f-4b6a-bfd9-d86ea08d8c67'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = '65e0d8e2-b7e8-476a-934e-ee0b2613f6ca'::uuid;
UPDATE wallet_ledger SET deductible_balance = 4.0 WHERE id = '3aa9ff98-1d52-4fde-bdef-924aacb35b17'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = '65e0d8e2-b7e8-476a-934e-ee0b2613f6ca'::uuid;
UPDATE wallet_ledger SET deductible_balance = 33.0 WHERE id = '4db20a95-2d9b-4578-b048-088e1dd698de'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = '65e0d8e2-b7e8-476a-934e-ee0b2613f6ca'::uuid;
UPDATE wallet_ledger SET deductible_balance = 19.0 WHERE id = '78835071-a5c0-4356-bb8f-e1fff1841f4a'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = '65e0d8e2-b7e8-476a-934e-ee0b2613f6ca'::uuid;
UPDATE wallet_ledger SET deductible_balance = 52.0 WHERE id = 'c766ba0c-b394-40d8-b566-570ca9acc272'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = '65e0d8e2-b7e8-476a-934e-ee0b2613f6ca'::uuid;
UPDATE wallet_ledger SET deductible_balance = 13.0 WHERE id = '53349db0-acce-49d5-b1d6-ddf286b0fa83'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = '65e0d8e2-b7e8-476a-934e-ee0b2613f6ca'::uuid;
UPDATE wallet_ledger SET deductible_balance = 6.0 WHERE id = '8ddbef20-afa9-4052-af2c-85f6a5e9e2f9'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = '65e0d8e2-b7e8-476a-934e-ee0b2613f6ca'::uuid;
UPDATE wallet_ledger SET deductible_balance = 65.0 WHERE id = 'e541dbc5-7498-4edb-aa71-acafc73c09df'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = '65e0d8e2-b7e8-476a-934e-ee0b2613f6ca'::uuid;
DO $v$
DECLARE w numeric; l numeric;
BEGIN
  SELECT points_balance INTO w FROM user_wallet WHERE user_id = '65e0d8e2-b7e8-476a-934e-ee0b2613f6ca'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid;
  SELECT coalesce(sum(deductible_balance),0) INTO l FROM wallet_ledger
    WHERE user_id = '65e0d8e2-b7e8-476a-934e-ee0b2613f6ca'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid
      AND currency = 'points' AND transaction_type = 'earn';
  IF abs(w - l) > 0.01 THEN
    RAISE EXCEPTION 'post-apply invariant user % wallet % lots %', '65e0d8e2-b7e8-476a-934e-ee0b2613f6ca', w, l;
  END IF;
END $v$;
COMMIT;
