BEGIN;
UPDATE wallet_ledger SET deductible_balance = 0.0 WHERE id = 'cc448652-bf10-40dd-9d2d-a988e5295baf'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = '509d2ec8-bc6f-4e8b-b69b-a130363090d8'::uuid;
UPDATE wallet_ledger SET deductible_balance = 0.0 WHERE id = '64938f4a-9c1c-49fa-af1a-5dd099891720'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = '509d2ec8-bc6f-4e8b-b69b-a130363090d8'::uuid;
UPDATE wallet_ledger SET deductible_balance = 0.0 WHERE id = '631af3af-3bef-4f10-a3a5-c1fce5576cbd'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = '509d2ec8-bc6f-4e8b-b69b-a130363090d8'::uuid;
UPDATE wallet_ledger SET deductible_balance = 0.0 WHERE id = 'e6ba0268-53d5-4bd2-9f2c-d8ccc8bae295'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = '509d2ec8-bc6f-4e8b-b69b-a130363090d8'::uuid;
UPDATE wallet_ledger SET deductible_balance = 0.0 WHERE id = '377880c8-fbaa-45fc-ba1e-ef6120ae6ec5'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = '509d2ec8-bc6f-4e8b-b69b-a130363090d8'::uuid;
UPDATE wallet_ledger SET deductible_balance = 135.0 WHERE id = '1826af62-4eb6-499a-ba6e-0698902a73e6'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = '509d2ec8-bc6f-4e8b-b69b-a130363090d8'::uuid;
UPDATE wallet_ledger SET deductible_balance = 640.0 WHERE id = 'aa8b0ffe-3b37-47a6-87b1-5f773be5e4ac'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = '509d2ec8-bc6f-4e8b-b69b-a130363090d8'::uuid;
DO $v$
DECLARE w numeric; l numeric;
BEGIN
  SELECT points_balance INTO w FROM user_wallet WHERE user_id = '509d2ec8-bc6f-4e8b-b69b-a130363090d8'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid;
  SELECT coalesce(sum(deductible_balance),0) INTO l FROM wallet_ledger
    WHERE user_id = '509d2ec8-bc6f-4e8b-b69b-a130363090d8'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid
      AND currency = 'points' AND transaction_type = 'earn';
  IF abs(w - l) > 0.01 THEN
    RAISE EXCEPTION 'post-apply invariant user % wallet % lots %', '509d2ec8-bc6f-4e8b-b69b-a130363090d8', w, l;
  END IF;
END $v$;
COMMIT;
