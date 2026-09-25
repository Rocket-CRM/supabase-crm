BEGIN;
UPDATE wallet_ledger SET deductible_balance = 322.0 WHERE id = 'ce929497-8e80-4ead-bec0-bdd52b592c24'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = 'cf3e4ac5-31ca-491d-b599-a8f9b9ac20b2'::uuid;
DO $v$
DECLARE w numeric; l numeric;
BEGIN
  SELECT points_balance INTO w FROM user_wallet WHERE user_id = 'cf3e4ac5-31ca-491d-b599-a8f9b9ac20b2'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid;
  SELECT coalesce(sum(deductible_balance),0) INTO l FROM wallet_ledger
    WHERE user_id = 'cf3e4ac5-31ca-491d-b599-a8f9b9ac20b2'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid
      AND currency = 'points' AND transaction_type = 'earn';
  IF abs(w - l) > 0.01 THEN
    RAISE EXCEPTION 'post-apply invariant user % wallet % lots %', 'cf3e4ac5-31ca-491d-b599-a8f9b9ac20b2', w, l;
  END IF;
END $v$;
COMMIT;
