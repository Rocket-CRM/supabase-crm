BEGIN;
UPDATE wallet_ledger SET deductible_balance = 621.0 WHERE id = '00161c3f-9e13-494e-8d6f-159443ece338'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = '8f2f4682-739b-460a-b8a7-358f9dde4ce1'::uuid;
DO $v$
DECLARE w numeric; l numeric;
BEGIN
  SELECT points_balance INTO w FROM user_wallet WHERE user_id = '8f2f4682-739b-460a-b8a7-358f9dde4ce1'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid;
  SELECT coalesce(sum(deductible_balance),0) INTO l FROM wallet_ledger
    WHERE user_id = '8f2f4682-739b-460a-b8a7-358f9dde4ce1'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid
      AND currency = 'points' AND transaction_type = 'earn';
  IF abs(w - l) > 0.01 THEN
    RAISE EXCEPTION 'post-apply invariant user % wallet % lots %', '8f2f4682-739b-460a-b8a7-358f9dde4ce1', w, l;
  END IF;
END $v$;
COMMIT;
