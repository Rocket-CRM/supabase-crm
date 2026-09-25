BEGIN;
UPDATE wallet_ledger SET deductible_balance = 6.0 WHERE id = '9ed87747-d607-4ef0-80be-32e4635ecbdd'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = 'ab7067cd-213a-4539-a05a-634f2f7a2617'::uuid;
UPDATE wallet_ledger SET deductible_balance = 16.0 WHERE id = 'ac6dd9ef-361a-4a89-b8b3-84e3f19f6c20'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = 'ab7067cd-213a-4539-a05a-634f2f7a2617'::uuid;
UPDATE wallet_ledger SET deductible_balance = 10.0 WHERE id = '702a80f4-3550-4dfa-80e3-f162a5fd0c64'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = 'ab7067cd-213a-4539-a05a-634f2f7a2617'::uuid;
UPDATE wallet_ledger SET deductible_balance = 21.0 WHERE id = '31641e68-79f6-4001-a34c-8c2350ca7028'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = 'ab7067cd-213a-4539-a05a-634f2f7a2617'::uuid;
UPDATE wallet_ledger SET deductible_balance = 92.0 WHERE id = '315abc74-2127-4a43-a029-6af9939a0e2c'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = 'ab7067cd-213a-4539-a05a-634f2f7a2617'::uuid;
UPDATE wallet_ledger SET deductible_balance = 21.0 WHERE id = '7186733f-c59a-4e36-9483-e5eb8d0c9548'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = 'ab7067cd-213a-4539-a05a-634f2f7a2617'::uuid;
UPDATE wallet_ledger SET deductible_balance = 21.0 WHERE id = '0f630542-caf6-4202-8c69-fcd3ab9b4558'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = 'ab7067cd-213a-4539-a05a-634f2f7a2617'::uuid;
UPDATE wallet_ledger SET deductible_balance = 6.0 WHERE id = '693dbb50-66ec-452d-83ac-a34aa6a4199d'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = 'ab7067cd-213a-4539-a05a-634f2f7a2617'::uuid;
UPDATE wallet_ledger SET deductible_balance = 20.0 WHERE id = 'c7f25459-7e8b-4b16-995b-ebbef0e1bbbe'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = 'ab7067cd-213a-4539-a05a-634f2f7a2617'::uuid;
UPDATE wallet_ledger SET deductible_balance = 4.0 WHERE id = '4f20e8e3-2de4-4ebf-97b1-d9ab1539de0c'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = 'ab7067cd-213a-4539-a05a-634f2f7a2617'::uuid;
UPDATE wallet_ledger SET deductible_balance = 20.0 WHERE id = 'f92ffe2d-316d-4d27-a2b6-bfb8bfdc957d'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = 'ab7067cd-213a-4539-a05a-634f2f7a2617'::uuid;
UPDATE wallet_ledger SET deductible_balance = 23.0 WHERE id = '8485c023-a2f0-4dd0-955b-81526bd8352e'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = 'ab7067cd-213a-4539-a05a-634f2f7a2617'::uuid;
DO $v$
DECLARE w numeric; l numeric;
BEGIN
  SELECT points_balance INTO w FROM user_wallet WHERE user_id = 'ab7067cd-213a-4539-a05a-634f2f7a2617'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid;
  SELECT coalesce(sum(deductible_balance),0) INTO l FROM wallet_ledger
    WHERE user_id = 'ab7067cd-213a-4539-a05a-634f2f7a2617'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid
      AND currency = 'points' AND transaction_type = 'earn';
  IF abs(w - l) > 0.01 THEN
    RAISE EXCEPTION 'post-apply invariant user % wallet % lots %', 'ab7067cd-213a-4539-a05a-634f2f7a2617', w, l;
  END IF;
END $v$;
COMMIT;
