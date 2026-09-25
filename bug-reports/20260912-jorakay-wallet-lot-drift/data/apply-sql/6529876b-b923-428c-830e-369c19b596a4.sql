BEGIN;
UPDATE wallet_ledger SET deductible_balance = 0.0 WHERE id = '5b3e5a7a-c22a-4ada-a5b9-a1a4c16254db'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = '6529876b-b923-428c-830e-369c19b596a4'::uuid;
UPDATE wallet_ledger SET deductible_balance = 0.0 WHERE id = '91898399-fc42-4633-aedb-f648115371e9'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = '6529876b-b923-428c-830e-369c19b596a4'::uuid;
UPDATE wallet_ledger SET deductible_balance = 0.0 WHERE id = '0fe6b67d-0f2f-4edd-9876-c71ce053a431'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = '6529876b-b923-428c-830e-369c19b596a4'::uuid;
UPDATE wallet_ledger SET deductible_balance = 0.0 WHERE id = 'a34c4ec0-7e1f-4ebd-ada6-55df0828b1b4'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = '6529876b-b923-428c-830e-369c19b596a4'::uuid;
UPDATE wallet_ledger SET deductible_balance = 0.0 WHERE id = '3705851c-4ce3-46d3-a66d-3a45810fbdb3'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = '6529876b-b923-428c-830e-369c19b596a4'::uuid;
UPDATE wallet_ledger SET deductible_balance = 0.0 WHERE id = '433ed560-0808-4163-9745-fdf3281df80b'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = '6529876b-b923-428c-830e-369c19b596a4'::uuid;
UPDATE wallet_ledger SET deductible_balance = 4296.0 WHERE id = 'bd3666c2-dcdd-43c0-8ae1-d60db1894a13'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = '6529876b-b923-428c-830e-369c19b596a4'::uuid;
UPDATE wallet_ledger SET deductible_balance = 3450.0 WHERE id = '9744a62e-e0ce-4f72-9c54-0dbaa735f578'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = '6529876b-b923-428c-830e-369c19b596a4'::uuid;
UPDATE wallet_ledger SET deductible_balance = 875.0 WHERE id = '72ab5d72-8a75-4626-938f-d5fb7a4074d8'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = '6529876b-b923-428c-830e-369c19b596a4'::uuid;
UPDATE wallet_ledger SET deductible_balance = 1740.0 WHERE id = 'af2e4862-8cd2-42bb-aa64-4a3f57fed94d'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = '6529876b-b923-428c-830e-369c19b596a4'::uuid;
UPDATE wallet_ledger SET deductible_balance = 1675.0 WHERE id = '14b70d65-9926-423f-8a2a-c99c4443a25d'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = '6529876b-b923-428c-830e-369c19b596a4'::uuid;
UPDATE wallet_ledger SET deductible_balance = 1890.0 WHERE id = '5ab7aa0e-f5f3-48f0-840d-ab54858d3e7b'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = '6529876b-b923-428c-830e-369c19b596a4'::uuid;
UPDATE wallet_ledger SET deductible_balance = 1675.0 WHERE id = '2f098f8e-2117-4173-b2e2-9cfbd7ce4195'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = '6529876b-b923-428c-830e-369c19b596a4'::uuid;
UPDATE wallet_ledger SET deductible_balance = 875.0 WHERE id = 'b1c10386-ec2b-4c4b-b347-7eeac57e8f8f'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = '6529876b-b923-428c-830e-369c19b596a4'::uuid;
DO $v$
DECLARE w numeric; l numeric;
BEGIN
  SELECT points_balance INTO w FROM user_wallet WHERE user_id = '6529876b-b923-428c-830e-369c19b596a4'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid;
  SELECT coalesce(sum(deductible_balance),0) INTO l FROM wallet_ledger
    WHERE user_id = '6529876b-b923-428c-830e-369c19b596a4'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid
      AND currency = 'points' AND transaction_type = 'earn';
  IF abs(w - l) > 0.01 THEN
    RAISE EXCEPTION 'post-apply invariant user % wallet % lots %', '6529876b-b923-428c-830e-369c19b596a4', w, l;
  END IF;
END $v$;
COMMIT;
