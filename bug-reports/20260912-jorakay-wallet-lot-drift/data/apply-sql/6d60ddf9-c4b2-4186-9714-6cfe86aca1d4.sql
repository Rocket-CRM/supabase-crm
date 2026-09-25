BEGIN;
UPDATE wallet_ledger SET deductible_balance = 235.0 WHERE id = '208e1bdb-e6e1-4166-bd19-58f0d684fe21'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = '6d60ddf9-c4b2-4186-9714-6cfe86aca1d4'::uuid;
UPDATE wallet_ledger SET deductible_balance = 99.0 WHERE id = '48d3e978-bd17-4eb6-a454-450a785d5b1d'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = '6d60ddf9-c4b2-4186-9714-6cfe86aca1d4'::uuid;
UPDATE wallet_ledger SET deductible_balance = 317.0 WHERE id = '62a03967-2007-42c3-8bf9-67613727e0ac'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = '6d60ddf9-c4b2-4186-9714-6cfe86aca1d4'::uuid;
UPDATE wallet_ledger SET deductible_balance = 421.0 WHERE id = '67e1e25a-eade-4066-869d-ce49821fc50c'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = '6d60ddf9-c4b2-4186-9714-6cfe86aca1d4'::uuid;
UPDATE wallet_ledger SET deductible_balance = 301.0 WHERE id = '8b95f4c4-a653-4b67-bc03-8308b452b5ec'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = '6d60ddf9-c4b2-4186-9714-6cfe86aca1d4'::uuid;
UPDATE wallet_ledger SET deductible_balance = 160.0 WHERE id = '0ab79992-c65b-43d4-a97d-a0f47c322e1f'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = '6d60ddf9-c4b2-4186-9714-6cfe86aca1d4'::uuid;
UPDATE wallet_ledger SET deductible_balance = 496.0 WHERE id = 'dad6ab02-a4e8-4a4f-b0e3-333f2bb483fb'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = '6d60ddf9-c4b2-4186-9714-6cfe86aca1d4'::uuid;
UPDATE wallet_ledger SET deductible_balance = 270.0 WHERE id = '7a805d79-64cd-4e75-a40a-6cde178c4e21'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = '6d60ddf9-c4b2-4186-9714-6cfe86aca1d4'::uuid;
UPDATE wallet_ledger SET deductible_balance = 228.0 WHERE id = '4cf84317-2913-41ea-ba4f-f6540c82c49a'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = '6d60ddf9-c4b2-4186-9714-6cfe86aca1d4'::uuid;
UPDATE wallet_ledger SET deductible_balance = 726.0 WHERE id = '328ddec6-3d22-4895-a72f-8f12d636a21f'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = '6d60ddf9-c4b2-4186-9714-6cfe86aca1d4'::uuid;
UPDATE wallet_ledger SET deductible_balance = 188.0 WHERE id = '6fb56672-9d33-46b7-afd8-b646bd993586'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = '6d60ddf9-c4b2-4186-9714-6cfe86aca1d4'::uuid;
DO $v$
DECLARE w numeric; l numeric;
BEGIN
  SELECT points_balance INTO w FROM user_wallet WHERE user_id = '6d60ddf9-c4b2-4186-9714-6cfe86aca1d4'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid;
  SELECT coalesce(sum(deductible_balance),0) INTO l FROM wallet_ledger
    WHERE user_id = '6d60ddf9-c4b2-4186-9714-6cfe86aca1d4'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid
      AND currency = 'points' AND transaction_type = 'earn';
  IF abs(w - l) > 0.01 THEN
    RAISE EXCEPTION 'post-apply invariant user % wallet % lots %', '6d60ddf9-c4b2-4186-9714-6cfe86aca1d4', w, l;
  END IF;
END $v$;
COMMIT;
