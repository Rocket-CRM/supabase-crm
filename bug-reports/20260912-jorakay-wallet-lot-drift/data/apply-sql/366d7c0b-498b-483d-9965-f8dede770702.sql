BEGIN;
UPDATE wallet_ledger SET deductible_balance = 48.0 WHERE id = '6801b785-1c1c-4ebb-a811-17557d79091d'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = '366d7c0b-498b-483d-9965-f8dede770702'::uuid;
DO $v$
DECLARE w numeric; l numeric;
BEGIN
  SELECT points_balance INTO w FROM user_wallet WHERE user_id = '366d7c0b-498b-483d-9965-f8dede770702'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid;
  SELECT coalesce(sum(deductible_balance),0) INTO l FROM wallet_ledger
    WHERE user_id = '366d7c0b-498b-483d-9965-f8dede770702'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid
      AND currency = 'points' AND transaction_type = 'earn';
  IF abs(w - l) > 0.01 THEN
    RAISE EXCEPTION 'post-apply invariant user % wallet % lots %', '366d7c0b-498b-483d-9965-f8dede770702', w, l;
  END IF;
END $v$;
COMMIT;
