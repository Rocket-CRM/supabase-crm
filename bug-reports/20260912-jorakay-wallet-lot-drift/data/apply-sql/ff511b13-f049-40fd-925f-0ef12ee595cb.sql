BEGIN;
UPDATE user_wallet SET points_balance = 128882.0 WHERE user_id = 'ff511b13-f049-40fd-925f-0ef12ee595cb'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid;
DO $v$
DECLARE w numeric; l numeric;
BEGIN
  SELECT points_balance INTO w FROM user_wallet WHERE user_id = 'ff511b13-f049-40fd-925f-0ef12ee595cb'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid;
  SELECT coalesce(sum(deductible_balance),0) INTO l FROM wallet_ledger
    WHERE user_id = 'ff511b13-f049-40fd-925f-0ef12ee595cb'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid
      AND currency = 'points' AND transaction_type = 'earn';
  IF abs(w - l) > 0.01 THEN
    RAISE EXCEPTION 'post-apply invariant user % wallet % lots %', 'ff511b13-f049-40fd-925f-0ef12ee595cb', w, l;
  END IF;
END $v$;
COMMIT;
