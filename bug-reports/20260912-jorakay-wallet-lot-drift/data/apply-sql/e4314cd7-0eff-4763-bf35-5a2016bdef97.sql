BEGIN;
UPDATE wallet_ledger SET deductible_balance = 101.0 WHERE id = 'a3e7f96c-0aef-4304-8a16-7c6d3a55139b'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = 'e4314cd7-0eff-4763-bf35-5a2016bdef97'::uuid;
UPDATE wallet_ledger SET deductible_balance = 31.0 WHERE id = 'e341f51f-994e-4509-9ddf-c3f23d7b1db7'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = 'e4314cd7-0eff-4763-bf35-5a2016bdef97'::uuid;
UPDATE wallet_ledger SET deductible_balance = 31.0 WHERE id = '7944d27a-5416-42da-8018-63396b66ca76'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = 'e4314cd7-0eff-4763-bf35-5a2016bdef97'::uuid;
UPDATE wallet_ledger SET deductible_balance = 343.0 WHERE id = 'f8a175e0-ef43-45c1-b270-a6e04a132eb7'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = 'e4314cd7-0eff-4763-bf35-5a2016bdef97'::uuid;
DO $v$
DECLARE w numeric; l numeric;
BEGIN
  SELECT points_balance INTO w FROM user_wallet WHERE user_id = 'e4314cd7-0eff-4763-bf35-5a2016bdef97'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid;
  SELECT coalesce(sum(deductible_balance),0) INTO l FROM wallet_ledger
    WHERE user_id = 'e4314cd7-0eff-4763-bf35-5a2016bdef97'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid
      AND currency = 'points' AND transaction_type = 'earn';
  IF abs(w - l) > 0.01 THEN
    RAISE EXCEPTION 'post-apply invariant user % wallet % lots %', 'e4314cd7-0eff-4763-bf35-5a2016bdef97', w, l;
  END IF;
END $v$;
COMMIT;
