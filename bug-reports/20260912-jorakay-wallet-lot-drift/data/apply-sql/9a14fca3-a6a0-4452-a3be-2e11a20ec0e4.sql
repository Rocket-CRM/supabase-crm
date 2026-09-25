BEGIN;
UPDATE wallet_ledger SET deductible_balance = 0.0 WHERE id = 'efe587b3-da53-4111-bdf4-f94804a2eab7'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = '9a14fca3-a6a0-4452-a3be-2e11a20ec0e4'::uuid;
UPDATE wallet_ledger SET deductible_balance = 0.0 WHERE id = '77d08d0f-9757-46b5-8127-b1c15bf7bd51'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = '9a14fca3-a6a0-4452-a3be-2e11a20ec0e4'::uuid;
UPDATE wallet_ledger SET deductible_balance = 0.0 WHERE id = '33872c6c-2397-4b17-95e2-79ece0d27f22'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = '9a14fca3-a6a0-4452-a3be-2e11a20ec0e4'::uuid;
UPDATE wallet_ledger SET deductible_balance = 0.0 WHERE id = 'ddcdd455-efeb-4f85-9530-e5a8b0b89507'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = '9a14fca3-a6a0-4452-a3be-2e11a20ec0e4'::uuid;
UPDATE wallet_ledger SET deductible_balance = 0.0 WHERE id = '28d38ee5-e66a-4837-b32b-63b8e3bfa57e'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = '9a14fca3-a6a0-4452-a3be-2e11a20ec0e4'::uuid;
UPDATE wallet_ledger SET deductible_balance = 0.0 WHERE id = '5fda565c-3a23-4ff9-bb50-1cc1152e88e7'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = '9a14fca3-a6a0-4452-a3be-2e11a20ec0e4'::uuid;
UPDATE wallet_ledger SET deductible_balance = 0.0 WHERE id = '70632592-608a-4666-8e53-9c76517a6808'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = '9a14fca3-a6a0-4452-a3be-2e11a20ec0e4'::uuid;
UPDATE wallet_ledger SET deductible_balance = 0.0 WHERE id = 'c824a3f6-8f42-4216-85a4-8082080c874d'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = '9a14fca3-a6a0-4452-a3be-2e11a20ec0e4'::uuid;
UPDATE wallet_ledger SET deductible_balance = 0.0 WHERE id = '37ab4efa-c9a0-47e1-b90b-fc623061934c'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = '9a14fca3-a6a0-4452-a3be-2e11a20ec0e4'::uuid;
UPDATE wallet_ledger SET deductible_balance = 0.0 WHERE id = 'c17b742e-b5ba-474b-8315-8cc62ec86ceb'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = '9a14fca3-a6a0-4452-a3be-2e11a20ec0e4'::uuid;
UPDATE wallet_ledger SET deductible_balance = 0.0 WHERE id = '5b12968c-cb73-4327-b475-687b815a0e39'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = '9a14fca3-a6a0-4452-a3be-2e11a20ec0e4'::uuid;
UPDATE wallet_ledger SET deductible_balance = 0.0 WHERE id = 'c2320fe4-2ad5-42da-92d9-f90384580f5a'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = '9a14fca3-a6a0-4452-a3be-2e11a20ec0e4'::uuid;
UPDATE wallet_ledger SET deductible_balance = 0.0 WHERE id = 'f286c184-7b0d-4d75-9bcd-bec276ac93ea'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = '9a14fca3-a6a0-4452-a3be-2e11a20ec0e4'::uuid;
UPDATE wallet_ledger SET deductible_balance = 21.0 WHERE id = 'effdb266-09b1-450e-8d97-36c88cf5deff'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = '9a14fca3-a6a0-4452-a3be-2e11a20ec0e4'::uuid;
DO $v$
DECLARE w numeric; l numeric;
BEGIN
  SELECT points_balance INTO w FROM user_wallet WHERE user_id = '9a14fca3-a6a0-4452-a3be-2e11a20ec0e4'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid;
  SELECT coalesce(sum(deductible_balance),0) INTO l FROM wallet_ledger
    WHERE user_id = '9a14fca3-a6a0-4452-a3be-2e11a20ec0e4'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid
      AND currency = 'points' AND transaction_type = 'earn';
  IF abs(w - l) > 0.01 THEN
    RAISE EXCEPTION 'post-apply invariant user % wallet % lots %', '9a14fca3-a6a0-4452-a3be-2e11a20ec0e4', w, l;
  END IF;
END $v$;
COMMIT;
