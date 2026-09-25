BEGIN;
UPDATE wallet_ledger SET deductible_balance = 0.0 WHERE id = 'dcaf5979-1349-404e-9851-c89096218d70'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = '82f36c1a-6de9-4ff7-9c24-3aee6e073221'::uuid;
UPDATE wallet_ledger SET deductible_balance = 0.0 WHERE id = '7a75d420-a49f-4ef5-be42-5a5e1bd69019'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = '82f36c1a-6de9-4ff7-9c24-3aee6e073221'::uuid;
UPDATE wallet_ledger SET deductible_balance = 0.0 WHERE id = 'a6f860f6-ad88-4e66-a3f3-4230bb2969a4'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = '82f36c1a-6de9-4ff7-9c24-3aee6e073221'::uuid;
UPDATE wallet_ledger SET deductible_balance = 0.0 WHERE id = 'b9e2091c-4869-4a0a-966d-c089e81fb69f'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = '82f36c1a-6de9-4ff7-9c24-3aee6e073221'::uuid;
UPDATE wallet_ledger SET deductible_balance = 0.0 WHERE id = '8bf55d71-658c-49d3-a40e-3710d849ecc8'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = '82f36c1a-6de9-4ff7-9c24-3aee6e073221'::uuid;
UPDATE wallet_ledger SET deductible_balance = 348.0 WHERE id = '705d1acd-c83d-478f-b7fb-9971efcd9195'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = '82f36c1a-6de9-4ff7-9c24-3aee6e073221'::uuid;
UPDATE wallet_ledger SET deductible_balance = 148.0 WHERE id = '6bdeb51b-f907-4aa9-b4b0-6e1e9bf8c658'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = '82f36c1a-6de9-4ff7-9c24-3aee6e073221'::uuid;
DO $v$
DECLARE w numeric; l numeric;
BEGIN
  SELECT points_balance INTO w FROM user_wallet WHERE user_id = '82f36c1a-6de9-4ff7-9c24-3aee6e073221'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid;
  SELECT coalesce(sum(deductible_balance),0) INTO l FROM wallet_ledger
    WHERE user_id = '82f36c1a-6de9-4ff7-9c24-3aee6e073221'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid
      AND currency = 'points' AND transaction_type = 'earn';
  IF abs(w - l) > 0.01 THEN
    RAISE EXCEPTION 'post-apply invariant user % wallet % lots %', '82f36c1a-6de9-4ff7-9c24-3aee6e073221', w, l;
  END IF;
END $v$;
COMMIT;
