BEGIN;
UPDATE wallet_ledger SET deductible_balance = 3415.0 WHERE id = '7edfb541-5a36-45e1-b03a-a2f10e9c293c'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = '2e9794f1-5f7b-4e41-ab8d-43e6b2c03779'::uuid;
DO $v$
DECLARE w numeric; l numeric;
BEGIN
  SELECT points_balance INTO w FROM user_wallet WHERE user_id = '2e9794f1-5f7b-4e41-ab8d-43e6b2c03779'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid;
  SELECT coalesce(sum(deductible_balance),0) INTO l FROM wallet_ledger
    WHERE user_id = '2e9794f1-5f7b-4e41-ab8d-43e6b2c03779'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid
      AND currency = 'points' AND transaction_type = 'earn';
  IF abs(w - l) > 0.01 THEN
    RAISE EXCEPTION 'post-apply invariant user % wallet % lots %', '2e9794f1-5f7b-4e41-ab8d-43e6b2c03779', w, l;
  END IF;
END $v$;
COMMIT;
