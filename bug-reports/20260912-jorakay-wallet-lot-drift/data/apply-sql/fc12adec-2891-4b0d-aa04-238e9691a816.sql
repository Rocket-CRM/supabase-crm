BEGIN;
UPDATE wallet_ledger SET deductible_balance = 16.0 WHERE id = '96747fa1-8df8-463d-ad2a-34832ae4a3d0'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = 'fc12adec-2891-4b0d-aa04-238e9691a816'::uuid;
DO $v$
DECLARE w numeric; l numeric;
BEGIN
  SELECT points_balance INTO w FROM user_wallet WHERE user_id = 'fc12adec-2891-4b0d-aa04-238e9691a816'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid;
  SELECT coalesce(sum(deductible_balance),0) INTO l FROM wallet_ledger
    WHERE user_id = 'fc12adec-2891-4b0d-aa04-238e9691a816'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid
      AND currency = 'points' AND transaction_type = 'earn';
  IF abs(w - l) > 0.01 THEN
    RAISE EXCEPTION 'post-apply invariant user % wallet % lots %', 'fc12adec-2891-4b0d-aa04-238e9691a816', w, l;
  END IF;
END $v$;
COMMIT;
