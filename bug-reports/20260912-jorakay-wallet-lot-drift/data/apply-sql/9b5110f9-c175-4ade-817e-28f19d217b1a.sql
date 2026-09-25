BEGIN;
UPDATE wallet_ledger SET deductible_balance = 1748.0 WHERE id = '98e7010d-7b68-4e36-ad2d-4714cd47c52c'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = '9b5110f9-c175-4ade-817e-28f19d217b1a'::uuid;
UPDATE wallet_ledger SET deductible_balance = 81.0 WHERE id = '554b5861-6fe4-4550-9c95-484a2761f35c'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = '9b5110f9-c175-4ade-817e-28f19d217b1a'::uuid;
UPDATE wallet_ledger SET deductible_balance = 928.0 WHERE id = '194b2231-bf24-44c9-93d5-69187bfbd29d'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = '9b5110f9-c175-4ade-817e-28f19d217b1a'::uuid;
DO $v$
DECLARE w numeric; l numeric;
BEGIN
  SELECT points_balance INTO w FROM user_wallet WHERE user_id = '9b5110f9-c175-4ade-817e-28f19d217b1a'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid;
  SELECT coalesce(sum(deductible_balance),0) INTO l FROM wallet_ledger
    WHERE user_id = '9b5110f9-c175-4ade-817e-28f19d217b1a'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid
      AND currency = 'points' AND transaction_type = 'earn';
  IF abs(w - l) > 0.01 THEN
    RAISE EXCEPTION 'post-apply invariant user % wallet % lots %', '9b5110f9-c175-4ade-817e-28f19d217b1a', w, l;
  END IF;
END $v$;
COMMIT;
