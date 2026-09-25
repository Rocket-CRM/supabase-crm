BEGIN;
UPDATE wallet_ledger SET deductible_balance = 21.0 WHERE id = '43b758b0-569a-49b5-a157-14b724003502'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = 'd1bca277-2aba-4bb9-9ea2-cbe7109264da'::uuid;
UPDATE wallet_ledger SET deductible_balance = 23.0 WHERE id = '71f29151-82bd-4195-b8ea-a3aafeaed8b3'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = 'd1bca277-2aba-4bb9-9ea2-cbe7109264da'::uuid;
UPDATE wallet_ledger SET deductible_balance = 15.0 WHERE id = '6c4b3587-e889-499e-89b4-ae8425f1ee82'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = 'd1bca277-2aba-4bb9-9ea2-cbe7109264da'::uuid;
UPDATE wallet_ledger SET deductible_balance = 20.0 WHERE id = 'dad9535b-ae42-467c-80c2-3176b52faa41'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = 'd1bca277-2aba-4bb9-9ea2-cbe7109264da'::uuid;
DO $v$
DECLARE w numeric; l numeric;
BEGIN
  SELECT points_balance INTO w FROM user_wallet WHERE user_id = 'd1bca277-2aba-4bb9-9ea2-cbe7109264da'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid;
  SELECT coalesce(sum(deductible_balance),0) INTO l FROM wallet_ledger
    WHERE user_id = 'd1bca277-2aba-4bb9-9ea2-cbe7109264da'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid
      AND currency = 'points' AND transaction_type = 'earn';
  IF abs(w - l) > 0.01 THEN
    RAISE EXCEPTION 'post-apply invariant user % wallet % lots %', 'd1bca277-2aba-4bb9-9ea2-cbe7109264da', w, l;
  END IF;
END $v$;
COMMIT;
