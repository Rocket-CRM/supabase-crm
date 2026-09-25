BEGIN;
UPDATE wallet_ledger SET deductible_balance = 246.0 WHERE id = '123f8f07-252a-4a62-bacb-dc8418d0ebcf'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = '6dbd4113-887a-4205-a3f8-2b0c31afa666'::uuid;
UPDATE wallet_ledger SET deductible_balance = 1062.0 WHERE id = '16bc2110-2540-42ac-85f4-c49aeeedee41'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = '6dbd4113-887a-4205-a3f8-2b0c31afa666'::uuid;
UPDATE wallet_ledger SET deductible_balance = 654.0 WHERE id = '38a4efb6-92b6-4342-85ba-663f4de0342e'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = '6dbd4113-887a-4205-a3f8-2b0c31afa666'::uuid;
UPDATE wallet_ledger SET deductible_balance = 1091.0 WHERE id = '132eb630-5a1a-49df-8aff-97aa45f15ff1'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = '6dbd4113-887a-4205-a3f8-2b0c31afa666'::uuid;
DO $v$
DECLARE w numeric; l numeric;
BEGIN
  SELECT points_balance INTO w FROM user_wallet WHERE user_id = '6dbd4113-887a-4205-a3f8-2b0c31afa666'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid;
  SELECT coalesce(sum(deductible_balance),0) INTO l FROM wallet_ledger
    WHERE user_id = '6dbd4113-887a-4205-a3f8-2b0c31afa666'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid
      AND currency = 'points' AND transaction_type = 'earn';
  IF abs(w - l) > 0.01 THEN
    RAISE EXCEPTION 'post-apply invariant user % wallet % lots %', '6dbd4113-887a-4205-a3f8-2b0c31afa666', w, l;
  END IF;
END $v$;
COMMIT;
