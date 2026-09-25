BEGIN;
UPDATE wallet_ledger SET deductible_balance = 52.0 WHERE id = '5746807e-1125-44f1-b231-b8854682138d'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = '2e2b645b-4a92-4f2f-80cc-23af189d7808'::uuid;
UPDATE wallet_ledger SET deductible_balance = 52.0 WHERE id = '1d8fb514-1e35-4d61-9bf9-9f507cf924c4'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = '2e2b645b-4a92-4f2f-80cc-23af189d7808'::uuid;
UPDATE wallet_ledger SET deductible_balance = 6.0 WHERE id = 'b8bc9b99-c38d-4452-8108-b00ee8e2ebd1'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = '2e2b645b-4a92-4f2f-80cc-23af189d7808'::uuid;
DO $v$
DECLARE w numeric; l numeric;
BEGIN
  SELECT points_balance INTO w FROM user_wallet WHERE user_id = '2e2b645b-4a92-4f2f-80cc-23af189d7808'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid;
  SELECT coalesce(sum(deductible_balance),0) INTO l FROM wallet_ledger
    WHERE user_id = '2e2b645b-4a92-4f2f-80cc-23af189d7808'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid
      AND currency = 'points' AND transaction_type = 'earn';
  IF abs(w - l) > 0.01 THEN
    RAISE EXCEPTION 'post-apply invariant user % wallet % lots %', '2e2b645b-4a92-4f2f-80cc-23af189d7808', w, l;
  END IF;
END $v$;
COMMIT;
