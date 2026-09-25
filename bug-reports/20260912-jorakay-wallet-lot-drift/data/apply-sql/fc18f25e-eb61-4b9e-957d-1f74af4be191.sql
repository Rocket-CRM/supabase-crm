BEGIN;
UPDATE wallet_ledger SET deductible_balance = 0.0 WHERE id = '67410c2e-0e3e-408e-a6c7-a38e009f260f'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = 'fc18f25e-eb61-4b9e-957d-1f74af4be191'::uuid;
UPDATE wallet_ledger SET deductible_balance = 0.0 WHERE id = '9b84f964-df69-4f32-ac4a-b0f0e6e336ac'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = 'fc18f25e-eb61-4b9e-957d-1f74af4be191'::uuid;
UPDATE wallet_ledger SET deductible_balance = 0.0 WHERE id = '49a384f7-9a27-4edb-97c0-b2838182d8fe'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = 'fc18f25e-eb61-4b9e-957d-1f74af4be191'::uuid;
UPDATE wallet_ledger SET deductible_balance = 0.0 WHERE id = 'ebabbf03-f1c1-4abb-a8c1-72af62f242e3'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = 'fc18f25e-eb61-4b9e-957d-1f74af4be191'::uuid;
UPDATE wallet_ledger SET deductible_balance = 678.0 WHERE id = '7bd8e257-1cb1-474d-9472-b507af4b1923'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = 'fc18f25e-eb61-4b9e-957d-1f74af4be191'::uuid;
UPDATE wallet_ledger SET deductible_balance = 710.0 WHERE id = '40790208-4196-4683-be5d-3df5387f7eda'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = 'fc18f25e-eb61-4b9e-957d-1f74af4be191'::uuid;
DO $v$
DECLARE w numeric; l numeric;
BEGIN
  SELECT points_balance INTO w FROM user_wallet WHERE user_id = 'fc18f25e-eb61-4b9e-957d-1f74af4be191'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid;
  SELECT coalesce(sum(deductible_balance),0) INTO l FROM wallet_ledger
    WHERE user_id = 'fc18f25e-eb61-4b9e-957d-1f74af4be191'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid
      AND currency = 'points' AND transaction_type = 'earn';
  IF abs(w - l) > 0.01 THEN
    RAISE EXCEPTION 'post-apply invariant user % wallet % lots %', 'fc18f25e-eb61-4b9e-957d-1f74af4be191', w, l;
  END IF;
END $v$;
COMMIT;
