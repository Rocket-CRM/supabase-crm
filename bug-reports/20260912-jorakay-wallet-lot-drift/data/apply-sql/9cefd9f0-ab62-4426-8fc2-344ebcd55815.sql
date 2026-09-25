BEGIN;
UPDATE wallet_ledger SET deductible_balance = 3737.0 WHERE id = '61fb5a01-1f2a-4553-8366-2962e01cbf2f'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = '9cefd9f0-ab62-4426-8fc2-344ebcd55815'::uuid;
DO $v$
DECLARE w numeric; l numeric;
BEGIN
  SELECT points_balance INTO w FROM user_wallet WHERE user_id = '9cefd9f0-ab62-4426-8fc2-344ebcd55815'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid;
  SELECT coalesce(sum(deductible_balance),0) INTO l FROM wallet_ledger
    WHERE user_id = '9cefd9f0-ab62-4426-8fc2-344ebcd55815'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid
      AND currency = 'points' AND transaction_type = 'earn';
  IF abs(w - l) > 0.01 THEN
    RAISE EXCEPTION 'post-apply invariant user % wallet % lots %', '9cefd9f0-ab62-4426-8fc2-344ebcd55815', w, l;
  END IF;
END $v$;
COMMIT;
