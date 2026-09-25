BEGIN;
UPDATE wallet_ledger SET deductible_balance = 32.0 WHERE id = '91532f19-a87d-44b0-9641-5928d1dde4dd'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = 'f97ac591-9387-462f-9a78-b2a4ed1f7ab7'::uuid;
DO $v$
DECLARE w numeric; l numeric;
BEGIN
  SELECT points_balance INTO w FROM user_wallet WHERE user_id = 'f97ac591-9387-462f-9a78-b2a4ed1f7ab7'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid;
  SELECT coalesce(sum(deductible_balance),0) INTO l FROM wallet_ledger
    WHERE user_id = 'f97ac591-9387-462f-9a78-b2a4ed1f7ab7'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid
      AND currency = 'points' AND transaction_type = 'earn';
  IF abs(w - l) > 0.01 THEN
    RAISE EXCEPTION 'post-apply invariant user % wallet % lots %', 'f97ac591-9387-462f-9a78-b2a4ed1f7ab7', w, l;
  END IF;
END $v$;
COMMIT;
