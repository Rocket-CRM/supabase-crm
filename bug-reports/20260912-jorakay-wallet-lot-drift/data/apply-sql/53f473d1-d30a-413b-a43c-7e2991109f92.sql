BEGIN;
UPDATE wallet_ledger SET deductible_balance = 0.0 WHERE id = '5a8ff594-6840-4c3a-9540-625ba91591f1'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = '53f473d1-d30a-413b-a43c-7e2991109f92'::uuid;
DO $v$
DECLARE w numeric; l numeric;
BEGIN
  SELECT points_balance INTO w FROM user_wallet WHERE user_id = '53f473d1-d30a-413b-a43c-7e2991109f92'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid;
  SELECT coalesce(sum(deductible_balance),0) INTO l FROM wallet_ledger
    WHERE user_id = '53f473d1-d30a-413b-a43c-7e2991109f92'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid
      AND currency = 'points' AND transaction_type = 'earn';
  IF abs(w - l) > 0.01 THEN
    RAISE EXCEPTION 'post-apply invariant user % wallet % lots %', '53f473d1-d30a-413b-a43c-7e2991109f92', w, l;
  END IF;
END $v$;
COMMIT;
