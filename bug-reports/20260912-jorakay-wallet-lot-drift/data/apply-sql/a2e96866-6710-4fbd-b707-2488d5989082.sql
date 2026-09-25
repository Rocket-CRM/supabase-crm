BEGIN;
UPDATE wallet_ledger SET deductible_balance = 0.0 WHERE id = '0ca5b120-0f58-43b7-bdba-24bbf02b188e'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = 'a2e96866-6710-4fbd-b707-2488d5989082'::uuid;
UPDATE wallet_ledger SET deductible_balance = 0.0 WHERE id = 'ff3b2e7c-5379-409b-81e8-6cc6bc12a5f5'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = 'a2e96866-6710-4fbd-b707-2488d5989082'::uuid;
UPDATE wallet_ledger SET deductible_balance = 0.0 WHERE id = 'c0d093c1-e997-4e1f-b4c3-bbcf5928c319'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = 'a2e96866-6710-4fbd-b707-2488d5989082'::uuid;
UPDATE wallet_ledger SET deductible_balance = 0.0 WHERE id = 'd277e67d-8a39-4021-8e3f-e4402a7cdeb1'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = 'a2e96866-6710-4fbd-b707-2488d5989082'::uuid;
UPDATE wallet_ledger SET deductible_balance = 52.0 WHERE id = '2d999d3e-c300-47b0-8316-92bc6fb93f8f'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = 'a2e96866-6710-4fbd-b707-2488d5989082'::uuid;
UPDATE wallet_ledger SET deductible_balance = 22.0 WHERE id = '3489afc6-02f8-4e00-97fa-7f16040f55ae'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = 'a2e96866-6710-4fbd-b707-2488d5989082'::uuid;
DO $v$
DECLARE w numeric; l numeric;
BEGIN
  SELECT points_balance INTO w FROM user_wallet WHERE user_id = 'a2e96866-6710-4fbd-b707-2488d5989082'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid;
  SELECT coalesce(sum(deductible_balance),0) INTO l FROM wallet_ledger
    WHERE user_id = 'a2e96866-6710-4fbd-b707-2488d5989082'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid
      AND currency = 'points' AND transaction_type = 'earn';
  IF abs(w - l) > 0.01 THEN
    RAISE EXCEPTION 'post-apply invariant user % wallet % lots %', 'a2e96866-6710-4fbd-b707-2488d5989082', w, l;
  END IF;
END $v$;
COMMIT;
