BEGIN;
UPDATE wallet_ledger SET deductible_balance = 1.0 WHERE id = '18c539d1-a9a1-4fcb-bad7-6017d6649c06'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = 'f7560608-89bd-4735-969e-1586c0299814'::uuid;
DO $v$
DECLARE w numeric; l numeric;
BEGIN
  SELECT points_balance INTO w FROM user_wallet WHERE user_id = 'f7560608-89bd-4735-969e-1586c0299814'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid;
  SELECT coalesce(sum(deductible_balance),0) INTO l FROM wallet_ledger
    WHERE user_id = 'f7560608-89bd-4735-969e-1586c0299814'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid
      AND currency = 'points' AND transaction_type = 'earn';
  IF abs(w - l) > 0.01 THEN
    RAISE EXCEPTION 'post-apply invariant user % wallet % lots %', 'f7560608-89bd-4735-969e-1586c0299814', w, l;
  END IF;
END $v$;
COMMIT;
