BEGIN;
UPDATE wallet_ledger SET deductible_balance = 57.0 WHERE id = '89ed6e90-c378-412d-b9a1-dfe2d432d47a'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = 'ac6af112-d0ca-44b7-b03b-5b9ccf08188a'::uuid;
DO $v$
DECLARE w numeric; l numeric;
BEGIN
  SELECT points_balance INTO w FROM user_wallet WHERE user_id = 'ac6af112-d0ca-44b7-b03b-5b9ccf08188a'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid;
  SELECT coalesce(sum(deductible_balance),0) INTO l FROM wallet_ledger
    WHERE user_id = 'ac6af112-d0ca-44b7-b03b-5b9ccf08188a'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid
      AND currency = 'points' AND transaction_type = 'earn';
  IF abs(w - l) > 0.01 THEN
    RAISE EXCEPTION 'post-apply invariant user % wallet % lots %', 'ac6af112-d0ca-44b7-b03b-5b9ccf08188a', w, l;
  END IF;
END $v$;
COMMIT;
