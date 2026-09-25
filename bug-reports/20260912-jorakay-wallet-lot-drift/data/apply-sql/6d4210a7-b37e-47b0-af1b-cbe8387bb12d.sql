BEGIN;
UPDATE wallet_ledger SET deductible_balance = 0.0 WHERE id = 'ed39b501-1a32-467f-b59a-8339bcbd7f9e'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = '6d4210a7-b37e-47b0-af1b-cbe8387bb12d'::uuid;
UPDATE wallet_ledger SET deductible_balance = 21.0 WHERE id = 'bd29e6f9-5333-4481-a116-c807748e1586'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = '6d4210a7-b37e-47b0-af1b-cbe8387bb12d'::uuid;
DO $v$
DECLARE w numeric; l numeric;
BEGIN
  SELECT points_balance INTO w FROM user_wallet WHERE user_id = '6d4210a7-b37e-47b0-af1b-cbe8387bb12d'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid;
  SELECT coalesce(sum(deductible_balance),0) INTO l FROM wallet_ledger
    WHERE user_id = '6d4210a7-b37e-47b0-af1b-cbe8387bb12d'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid
      AND currency = 'points' AND transaction_type = 'earn';
  IF abs(w - l) > 0.01 THEN
    RAISE EXCEPTION 'post-apply invariant user % wallet % lots %', '6d4210a7-b37e-47b0-af1b-cbe8387bb12d', w, l;
  END IF;
END $v$;
COMMIT;
