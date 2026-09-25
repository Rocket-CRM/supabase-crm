BEGIN;
UPDATE wallet_ledger SET deductible_balance = 12683.0 WHERE id = 'd8f1c10a-7cc6-4b29-bb91-f33f9d9171d7'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = '7e16a591-c38f-4c79-904a-bc99e2b1eab1'::uuid;
DO $v$
DECLARE w numeric; l numeric;
BEGIN
  SELECT points_balance INTO w FROM user_wallet WHERE user_id = '7e16a591-c38f-4c79-904a-bc99e2b1eab1'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid;
  SELECT coalesce(sum(deductible_balance),0) INTO l FROM wallet_ledger
    WHERE user_id = '7e16a591-c38f-4c79-904a-bc99e2b1eab1'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid
      AND currency = 'points' AND transaction_type = 'earn';
  IF abs(w - l) > 0.01 THEN
    RAISE EXCEPTION 'post-apply invariant user % wallet % lots %', '7e16a591-c38f-4c79-904a-bc99e2b1eab1', w, l;
  END IF;
END $v$;
COMMIT;
