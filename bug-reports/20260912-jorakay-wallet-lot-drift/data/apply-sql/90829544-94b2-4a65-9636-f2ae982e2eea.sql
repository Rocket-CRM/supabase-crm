BEGIN;
UPDATE wallet_ledger SET deductible_balance = 0.0 WHERE id = 'cb412ffe-0cd9-4e93-bba5-7a1caff4cc79'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = '90829544-94b2-4a65-9636-f2ae982e2eea'::uuid;
UPDATE wallet_ledger SET deductible_balance = 12.0 WHERE id = '6403b6b2-6e8c-42ac-8a5a-140b59535929'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = '90829544-94b2-4a65-9636-f2ae982e2eea'::uuid;
DO $v$
DECLARE w numeric; l numeric;
BEGIN
  SELECT points_balance INTO w FROM user_wallet WHERE user_id = '90829544-94b2-4a65-9636-f2ae982e2eea'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid;
  SELECT coalesce(sum(deductible_balance),0) INTO l FROM wallet_ledger
    WHERE user_id = '90829544-94b2-4a65-9636-f2ae982e2eea'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid
      AND currency = 'points' AND transaction_type = 'earn';
  IF abs(w - l) > 0.01 THEN
    RAISE EXCEPTION 'post-apply invariant user % wallet % lots %', '90829544-94b2-4a65-9636-f2ae982e2eea', w, l;
  END IF;
END $v$;
COMMIT;
