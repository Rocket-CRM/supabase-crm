BEGIN;
UPDATE wallet_ledger SET deductible_balance = 50.0 WHERE id = '07e4bfa2-e55a-4ab0-94f4-f7727b49bba3'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = 'd319b760-5a40-4641-b25d-a668a4c07721'::uuid;
DO $v$
DECLARE w numeric; l numeric;
BEGIN
  SELECT points_balance INTO w FROM user_wallet WHERE user_id = 'd319b760-5a40-4641-b25d-a668a4c07721'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid;
  SELECT coalesce(sum(deductible_balance),0) INTO l FROM wallet_ledger
    WHERE user_id = 'd319b760-5a40-4641-b25d-a668a4c07721'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid
      AND currency = 'points' AND transaction_type = 'earn';
  IF abs(w - l) > 0.01 THEN
    RAISE EXCEPTION 'post-apply invariant user % wallet % lots %', 'd319b760-5a40-4641-b25d-a668a4c07721', w, l;
  END IF;
END $v$;
COMMIT;
