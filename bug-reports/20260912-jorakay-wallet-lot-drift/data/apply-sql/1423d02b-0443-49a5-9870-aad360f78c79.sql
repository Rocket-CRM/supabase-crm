BEGIN;
UPDATE wallet_ledger SET deductible_balance = 48.0 WHERE id = 'c65868d8-d64b-4eeb-ab79-871184a188c2'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = '1423d02b-0443-49a5-9870-aad360f78c79'::uuid;
DO $v$
DECLARE w numeric; l numeric;
BEGIN
  SELECT points_balance INTO w FROM user_wallet WHERE user_id = '1423d02b-0443-49a5-9870-aad360f78c79'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid;
  SELECT coalesce(sum(deductible_balance),0) INTO l FROM wallet_ledger
    WHERE user_id = '1423d02b-0443-49a5-9870-aad360f78c79'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid
      AND currency = 'points' AND transaction_type = 'earn';
  IF abs(w - l) > 0.01 THEN
    RAISE EXCEPTION 'post-apply invariant user % wallet % lots %', '1423d02b-0443-49a5-9870-aad360f78c79', w, l;
  END IF;
END $v$;
COMMIT;
