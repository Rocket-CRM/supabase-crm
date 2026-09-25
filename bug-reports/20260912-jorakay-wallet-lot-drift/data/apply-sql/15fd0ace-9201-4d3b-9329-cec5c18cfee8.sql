BEGIN;
UPDATE user_wallet SET points_balance = 10670.0 WHERE user_id = '15fd0ace-9201-4d3b-9329-cec5c18cfee8'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid;
DO $v$
DECLARE w numeric; l numeric;
BEGIN
  SELECT points_balance INTO w FROM user_wallet WHERE user_id = '15fd0ace-9201-4d3b-9329-cec5c18cfee8'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid;
  SELECT coalesce(sum(deductible_balance),0) INTO l FROM wallet_ledger
    WHERE user_id = '15fd0ace-9201-4d3b-9329-cec5c18cfee8'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid
      AND currency = 'points' AND transaction_type = 'earn';
  IF abs(w - l) > 0.01 THEN
    RAISE EXCEPTION 'post-apply invariant user % wallet % lots %', '15fd0ace-9201-4d3b-9329-cec5c18cfee8', w, l;
  END IF;
END $v$;
COMMIT;
