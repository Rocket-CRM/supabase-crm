BEGIN;
UPDATE wallet_ledger SET deductible_balance = 1251.0 WHERE id = 'a8daeb5c-197a-4c51-9574-b94120d28f8a'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = 'fdd5b2a3-10ff-48f8-ba12-ea38e3846d0c'::uuid;
UPDATE wallet_ledger SET deductible_balance = 83.0 WHERE id = 'f149bde8-173b-49c8-8041-22f42cd0a129'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = 'fdd5b2a3-10ff-48f8-ba12-ea38e3846d0c'::uuid;
DO $v$
DECLARE w numeric; l numeric;
BEGIN
  SELECT points_balance INTO w FROM user_wallet WHERE user_id = 'fdd5b2a3-10ff-48f8-ba12-ea38e3846d0c'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid;
  SELECT coalesce(sum(deductible_balance),0) INTO l FROM wallet_ledger
    WHERE user_id = 'fdd5b2a3-10ff-48f8-ba12-ea38e3846d0c'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid
      AND currency = 'points' AND transaction_type = 'earn';
  IF abs(w - l) > 0.01 THEN
    RAISE EXCEPTION 'post-apply invariant user % wallet % lots %', 'fdd5b2a3-10ff-48f8-ba12-ea38e3846d0c', w, l;
  END IF;
END $v$;
COMMIT;
