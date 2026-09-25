BEGIN;
UPDATE wallet_ledger SET deductible_balance = 0.0 WHERE id = 'd30b928e-a07d-4ce5-997e-5538814480a4'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = '2d8a6fd7-32ee-47c9-8a2d-2b2b672a9c7e'::uuid;
DO $v$
DECLARE w numeric; l numeric;
BEGIN
  SELECT points_balance INTO w FROM user_wallet WHERE user_id = '2d8a6fd7-32ee-47c9-8a2d-2b2b672a9c7e'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid;
  SELECT coalesce(sum(deductible_balance),0) INTO l FROM wallet_ledger
    WHERE user_id = '2d8a6fd7-32ee-47c9-8a2d-2b2b672a9c7e'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid
      AND currency = 'points' AND transaction_type = 'earn';
  IF abs(w - l) > 0.01 THEN
    RAISE EXCEPTION 'post-apply invariant user % wallet % lots %', '2d8a6fd7-32ee-47c9-8a2d-2b2b672a9c7e', w, l;
  END IF;
END $v$;
COMMIT;
