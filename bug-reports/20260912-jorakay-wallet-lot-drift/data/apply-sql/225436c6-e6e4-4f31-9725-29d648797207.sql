BEGIN;
UPDATE wallet_ledger SET deductible_balance = 10.0 WHERE id = '9c84c260-63c7-4e59-b42d-48df3044774f'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = '225436c6-e6e4-4f31-9725-29d648797207'::uuid;
DO $v$
DECLARE w numeric; l numeric;
BEGIN
  SELECT points_balance INTO w FROM user_wallet WHERE user_id = '225436c6-e6e4-4f31-9725-29d648797207'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid;
  SELECT coalesce(sum(deductible_balance),0) INTO l FROM wallet_ledger
    WHERE user_id = '225436c6-e6e4-4f31-9725-29d648797207'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid
      AND currency = 'points' AND transaction_type = 'earn';
  IF abs(w - l) > 0.01 THEN
    RAISE EXCEPTION 'post-apply invariant user % wallet % lots %', '225436c6-e6e4-4f31-9725-29d648797207', w, l;
  END IF;
END $v$;
COMMIT;
