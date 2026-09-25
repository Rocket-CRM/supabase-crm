BEGIN;
UPDATE wallet_ledger SET deductible_balance = 0.0 WHERE id = '37666400-dace-4763-9794-e8775c3a69d1'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = '76fa88d8-bc11-442b-a82e-568f00ae858e'::uuid;
UPDATE wallet_ledger SET deductible_balance = 0.0 WHERE id = '91f48782-4d52-4bbd-a753-444cc9800048'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = '76fa88d8-bc11-442b-a82e-568f00ae858e'::uuid;
UPDATE wallet_ledger SET deductible_balance = 0.0 WHERE id = 'ce034de7-9a3c-4f48-8139-4edc60fe6430'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = '76fa88d8-bc11-442b-a82e-568f00ae858e'::uuid;
UPDATE wallet_ledger SET deductible_balance = 0.0 WHERE id = 'da086e49-f08e-4c71-a35d-71cd66691ffc'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = '76fa88d8-bc11-442b-a82e-568f00ae858e'::uuid;
UPDATE wallet_ledger SET deductible_balance = 0.0 WHERE id = '2e0f2210-0c10-4186-b0d0-2c44c2695735'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = '76fa88d8-bc11-442b-a82e-568f00ae858e'::uuid;
UPDATE wallet_ledger SET deductible_balance = 0.0 WHERE id = '1ce56762-91a3-4a32-8682-edd272fae811'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = '76fa88d8-bc11-442b-a82e-568f00ae858e'::uuid;
UPDATE wallet_ledger SET deductible_balance = 0.0 WHERE id = 'a96aa784-3d89-4a3c-99da-7b5db9e97ad4'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = '76fa88d8-bc11-442b-a82e-568f00ae858e'::uuid;
UPDATE wallet_ledger SET deductible_balance = 0.0 WHERE id = 'fda2c42a-edef-44c4-b17d-50b32347a403'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = '76fa88d8-bc11-442b-a82e-568f00ae858e'::uuid;
UPDATE wallet_ledger SET deductible_balance = 104.0 WHERE id = 'c0f0ff6b-8615-4882-82d3-3bde684e220b'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = '76fa88d8-bc11-442b-a82e-568f00ae858e'::uuid;
UPDATE wallet_ledger SET deductible_balance = 440.0 WHERE id = '2b324e93-bf5d-4e6f-8c71-9f31e3619916'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = '76fa88d8-bc11-442b-a82e-568f00ae858e'::uuid;
DO $v$
DECLARE w numeric; l numeric;
BEGIN
  SELECT points_balance INTO w FROM user_wallet WHERE user_id = '76fa88d8-bc11-442b-a82e-568f00ae858e'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid;
  SELECT coalesce(sum(deductible_balance),0) INTO l FROM wallet_ledger
    WHERE user_id = '76fa88d8-bc11-442b-a82e-568f00ae858e'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid
      AND currency = 'points' AND transaction_type = 'earn';
  IF abs(w - l) > 0.01 THEN
    RAISE EXCEPTION 'post-apply invariant user % wallet % lots %', '76fa88d8-bc11-442b-a82e-568f00ae858e', w, l;
  END IF;
END $v$;
COMMIT;
