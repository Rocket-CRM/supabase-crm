BEGIN;
UPDATE wallet_ledger SET deductible_balance = 139.0 WHERE id = '1be6d8c8-4dc4-4e63-98cc-5ac05a06b500'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = '167d1b6d-fa75-4924-9cfe-459eb8a1128d'::uuid;
UPDATE wallet_ledger SET deductible_balance = 84.0 WHERE id = '59aa8f87-3476-43f9-b0a8-51c0073b27a9'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = '167d1b6d-fa75-4924-9cfe-459eb8a1128d'::uuid;
UPDATE wallet_ledger SET deductible_balance = 137.0 WHERE id = '69aa7c2f-1f7a-4305-832f-7feafcce6c56'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = '167d1b6d-fa75-4924-9cfe-459eb8a1128d'::uuid;
UPDATE wallet_ledger SET deductible_balance = 40.0 WHERE id = 'bea55ad8-38da-440e-979d-18ac77b14976'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = '167d1b6d-fa75-4924-9cfe-459eb8a1128d'::uuid;
UPDATE wallet_ledger SET deductible_balance = 37.0 WHERE id = '1df56545-4324-4c2a-9cdb-7a5ba9db0d7b'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = '167d1b6d-fa75-4924-9cfe-459eb8a1128d'::uuid;
DO $v$
DECLARE w numeric; l numeric;
BEGIN
  SELECT points_balance INTO w FROM user_wallet WHERE user_id = '167d1b6d-fa75-4924-9cfe-459eb8a1128d'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid;
  SELECT coalesce(sum(deductible_balance),0) INTO l FROM wallet_ledger
    WHERE user_id = '167d1b6d-fa75-4924-9cfe-459eb8a1128d'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid
      AND currency = 'points' AND transaction_type = 'earn';
  IF abs(w - l) > 0.01 THEN
    RAISE EXCEPTION 'post-apply invariant user % wallet % lots %', '167d1b6d-fa75-4924-9cfe-459eb8a1128d', w, l;
  END IF;
END $v$;
COMMIT;
