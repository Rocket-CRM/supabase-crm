BEGIN;
UPDATE wallet_ledger SET deductible_balance = 226.0 WHERE id = '61762d97-ad48-4639-b686-717e08fd1e17'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = 'e6ff7132-45f1-4b05-858b-2e0746633a25'::uuid;
DO $v$
DECLARE w numeric; l numeric;
BEGIN
  SELECT points_balance INTO w FROM user_wallet WHERE user_id = 'e6ff7132-45f1-4b05-858b-2e0746633a25'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid;
  SELECT coalesce(sum(deductible_balance),0) INTO l FROM wallet_ledger
    WHERE user_id = 'e6ff7132-45f1-4b05-858b-2e0746633a25'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid
      AND currency = 'points' AND transaction_type = 'earn';
  IF abs(w - l) > 0.01 THEN
    RAISE EXCEPTION 'post-apply invariant user % wallet % lots %', 'e6ff7132-45f1-4b05-858b-2e0746633a25', w, l;
  END IF;
END $v$;
COMMIT;
