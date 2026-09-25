BEGIN;
UPDATE wallet_ledger SET deductible_balance = 103.0 WHERE id = '2f4ea2d7-8ebf-48d4-846c-c47163b05c79'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = '2a301e35-7fcd-4023-a36e-df3b57b5c563'::uuid;
DO $v$
DECLARE w numeric; l numeric;
BEGIN
  SELECT points_balance INTO w FROM user_wallet WHERE user_id = '2a301e35-7fcd-4023-a36e-df3b57b5c563'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid;
  SELECT coalesce(sum(deductible_balance),0) INTO l FROM wallet_ledger
    WHERE user_id = '2a301e35-7fcd-4023-a36e-df3b57b5c563'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid
      AND currency = 'points' AND transaction_type = 'earn';
  IF abs(w - l) > 0.01 THEN
    RAISE EXCEPTION 'post-apply invariant user % wallet % lots %', '2a301e35-7fcd-4023-a36e-df3b57b5c563', w, l;
  END IF;
END $v$;
COMMIT;
