BEGIN;
UPDATE wallet_ledger SET deductible_balance = 510.0 WHERE id = 'ee0eedf1-940a-4578-af74-69bbc048558a'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = '07313983-05d3-46a1-8549-75fc6d087ec5'::uuid;
DO $v$
DECLARE w numeric; l numeric;
BEGIN
  SELECT points_balance INTO w FROM user_wallet WHERE user_id = '07313983-05d3-46a1-8549-75fc6d087ec5'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid;
  SELECT coalesce(sum(deductible_balance),0) INTO l FROM wallet_ledger
    WHERE user_id = '07313983-05d3-46a1-8549-75fc6d087ec5'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid
      AND currency = 'points' AND transaction_type = 'earn';
  IF abs(w - l) > 0.01 THEN
    RAISE EXCEPTION 'post-apply invariant user % wallet % lots %', '07313983-05d3-46a1-8549-75fc6d087ec5', w, l;
  END IF;
END $v$;
COMMIT;
