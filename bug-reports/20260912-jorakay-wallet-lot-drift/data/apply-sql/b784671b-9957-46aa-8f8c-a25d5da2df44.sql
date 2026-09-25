BEGIN;
UPDATE wallet_ledger SET deductible_balance = 15.0 WHERE id = 'c880d020-83cb-4a25-94fb-567defd395f6'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = 'b784671b-9957-46aa-8f8c-a25d5da2df44'::uuid;
DO $v$
DECLARE w numeric; l numeric;
BEGIN
  SELECT points_balance INTO w FROM user_wallet WHERE user_id = 'b784671b-9957-46aa-8f8c-a25d5da2df44'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid;
  SELECT coalesce(sum(deductible_balance),0) INTO l FROM wallet_ledger
    WHERE user_id = 'b784671b-9957-46aa-8f8c-a25d5da2df44'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid
      AND currency = 'points' AND transaction_type = 'earn';
  IF abs(w - l) > 0.01 THEN
    RAISE EXCEPTION 'post-apply invariant user % wallet % lots %', 'b784671b-9957-46aa-8f8c-a25d5da2df44', w, l;
  END IF;
END $v$;
COMMIT;
