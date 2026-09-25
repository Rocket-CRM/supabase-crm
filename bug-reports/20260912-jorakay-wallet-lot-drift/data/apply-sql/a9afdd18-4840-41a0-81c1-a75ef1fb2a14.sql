BEGIN;
UPDATE wallet_ledger SET deductible_balance = 4.0 WHERE id = '050677b7-93cc-4ecf-b2e7-5cf68d55ea53'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = 'a9afdd18-4840-41a0-81c1-a75ef1fb2a14'::uuid;
DO $v$
DECLARE w numeric; l numeric;
BEGIN
  SELECT points_balance INTO w FROM user_wallet WHERE user_id = 'a9afdd18-4840-41a0-81c1-a75ef1fb2a14'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid;
  SELECT coalesce(sum(deductible_balance),0) INTO l FROM wallet_ledger
    WHERE user_id = 'a9afdd18-4840-41a0-81c1-a75ef1fb2a14'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid
      AND currency = 'points' AND transaction_type = 'earn';
  IF abs(w - l) > 0.01 THEN
    RAISE EXCEPTION 'post-apply invariant user % wallet % lots %', 'a9afdd18-4840-41a0-81c1-a75ef1fb2a14', w, l;
  END IF;
END $v$;
COMMIT;
