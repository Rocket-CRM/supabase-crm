BEGIN;
UPDATE wallet_ledger SET deductible_balance = 280.0 WHERE id = '2961d2cb-8655-4667-b6ec-a13c4df46963'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = 'a8b16c7b-9930-4e67-8ae3-f8a219ca51c6'::uuid;
UPDATE wallet_ledger SET deductible_balance = 56.0 WHERE id = '2b8baf23-add6-41d0-87df-15fb4462010d'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = 'a8b16c7b-9930-4e67-8ae3-f8a219ca51c6'::uuid;
UPDATE wallet_ledger SET deductible_balance = 1825.0 WHERE id = 'e521b2bf-1642-4693-b973-a41ef1f1da1e'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = 'a8b16c7b-9930-4e67-8ae3-f8a219ca51c6'::uuid;
UPDATE wallet_ledger SET deductible_balance = 1825.0 WHERE id = '445d90f7-e0c6-480e-bf4e-fb6ac7fae18f'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = 'a8b16c7b-9930-4e67-8ae3-f8a219ca51c6'::uuid;
UPDATE wallet_ledger SET deductible_balance = 936.0 WHERE id = '5cad1a3a-316d-451b-95fb-68a687fe11ee'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = 'a8b16c7b-9930-4e67-8ae3-f8a219ca51c6'::uuid;
UPDATE wallet_ledger SET deductible_balance = 78.0 WHERE id = '921d4487-b8fd-4f83-8471-d29d4e7d4b1e'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = 'a8b16c7b-9930-4e67-8ae3-f8a219ca51c6'::uuid;
UPDATE wallet_ledger SET deductible_balance = 147.0 WHERE id = '45ea6170-56b5-40e0-87cf-7a867f4d67f7'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = 'a8b16c7b-9930-4e67-8ae3-f8a219ca51c6'::uuid;
UPDATE wallet_ledger SET deductible_balance = 63.0 WHERE id = 'ccf0af20-95e1-4f58-87e7-98f3a1c51341'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = 'a8b16c7b-9930-4e67-8ae3-f8a219ca51c6'::uuid;
UPDATE wallet_ledger SET deductible_balance = 500.0 WHERE id = 'd2e49ac5-0523-4735-8d8c-c7e4e234728d'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = 'a8b16c7b-9930-4e67-8ae3-f8a219ca51c6'::uuid;
UPDATE wallet_ledger SET deductible_balance = 1445.0 WHERE id = '3b7851e9-caad-47b0-b5f5-3e00f620172d'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = 'a8b16c7b-9930-4e67-8ae3-f8a219ca51c6'::uuid;
UPDATE wallet_ledger SET deductible_balance = 33.0 WHERE id = '6d264951-d62c-4ae4-8927-4120a21c608a'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = 'a8b16c7b-9930-4e67-8ae3-f8a219ca51c6'::uuid;
UPDATE wallet_ledger SET deductible_balance = 510.0 WHERE id = '23329ded-d964-4803-b24e-493c6f4ceb54'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = 'a8b16c7b-9930-4e67-8ae3-f8a219ca51c6'::uuid;
UPDATE wallet_ledger SET deductible_balance = 2059.0 WHERE id = '1d1c72b6-976e-4155-a133-4ada1cdadd1f'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = 'a8b16c7b-9930-4e67-8ae3-f8a219ca51c6'::uuid;
DO $v$
DECLARE w numeric; l numeric;
BEGIN
  SELECT points_balance INTO w FROM user_wallet WHERE user_id = 'a8b16c7b-9930-4e67-8ae3-f8a219ca51c6'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid;
  SELECT coalesce(sum(deductible_balance),0) INTO l FROM wallet_ledger
    WHERE user_id = 'a8b16c7b-9930-4e67-8ae3-f8a219ca51c6'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid
      AND currency = 'points' AND transaction_type = 'earn';
  IF abs(w - l) > 0.01 THEN
    RAISE EXCEPTION 'post-apply invariant user % wallet % lots %', 'a8b16c7b-9930-4e67-8ae3-f8a219ca51c6', w, l;
  END IF;
END $v$;
COMMIT;
