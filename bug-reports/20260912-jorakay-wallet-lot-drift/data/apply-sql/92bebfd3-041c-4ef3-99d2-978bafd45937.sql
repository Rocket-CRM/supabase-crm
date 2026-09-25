BEGIN;
UPDATE wallet_ledger SET deductible_balance = 5.0 WHERE id = '3ab3935e-da27-4973-b73d-b9f60e65f08e'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = '92bebfd3-041c-4ef3-99d2-978bafd45937'::uuid;
DO $v$
DECLARE w numeric; l numeric;
BEGIN
  SELECT points_balance INTO w FROM user_wallet WHERE user_id = '92bebfd3-041c-4ef3-99d2-978bafd45937'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid;
  SELECT coalesce(sum(deductible_balance),0) INTO l FROM wallet_ledger
    WHERE user_id = '92bebfd3-041c-4ef3-99d2-978bafd45937'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid
      AND currency = 'points' AND transaction_type = 'earn';
  IF abs(w - l) > 0.01 THEN
    RAISE EXCEPTION 'post-apply invariant user % wallet % lots %', '92bebfd3-041c-4ef3-99d2-978bafd45937', w, l;
  END IF;
END $v$;
COMMIT;
