BEGIN;
UPDATE wallet_ledger SET deductible_balance = 180.0 WHERE id = 'a5edb512-1fbb-481f-a934-d47e6d12759b'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = '9b5ae71d-5085-40af-a26a-cd1f0d6e27d7'::uuid;
UPDATE wallet_ledger SET deductible_balance = 300.0 WHERE id = '350777b2-ee9b-48c1-996b-bda418569e5e'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = '9b5ae71d-5085-40af-a26a-cd1f0d6e27d7'::uuid;
DO $v$
DECLARE w numeric; l numeric;
BEGIN
  SELECT points_balance INTO w FROM user_wallet WHERE user_id = '9b5ae71d-5085-40af-a26a-cd1f0d6e27d7'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid;
  SELECT coalesce(sum(deductible_balance),0) INTO l FROM wallet_ledger
    WHERE user_id = '9b5ae71d-5085-40af-a26a-cd1f0d6e27d7'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid
      AND currency = 'points' AND transaction_type = 'earn';
  IF abs(w - l) > 0.01 THEN
    RAISE EXCEPTION 'post-apply invariant user % wallet % lots %', '9b5ae71d-5085-40af-a26a-cd1f0d6e27d7', w, l;
  END IF;
END $v$;
COMMIT;
