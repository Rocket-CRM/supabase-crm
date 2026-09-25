BEGIN;
UPDATE wallet_ledger SET deductible_balance = 0.0 WHERE id = 'b9707c96-563d-4f25-90f5-fc2e05c56ec1'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = '17d52d2b-9325-479b-ba6b-f604f70c38e1'::uuid;
UPDATE wallet_ledger SET deductible_balance = 0.0 WHERE id = 'c59d6c63-9ce3-4170-8cec-0977cd8c31d8'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = '17d52d2b-9325-479b-ba6b-f604f70c38e1'::uuid;
UPDATE wallet_ledger SET deductible_balance = 16.0 WHERE id = '15e7dbf9-0f6e-42ce-bca6-bfc2b566b255'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = '17d52d2b-9325-479b-ba6b-f604f70c38e1'::uuid;
DO $v$
DECLARE w numeric; l numeric;
BEGIN
  SELECT points_balance INTO w FROM user_wallet WHERE user_id = '17d52d2b-9325-479b-ba6b-f604f70c38e1'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid;
  SELECT coalesce(sum(deductible_balance),0) INTO l FROM wallet_ledger
    WHERE user_id = '17d52d2b-9325-479b-ba6b-f604f70c38e1'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid
      AND currency = 'points' AND transaction_type = 'earn';
  IF abs(w - l) > 0.01 THEN
    RAISE EXCEPTION 'post-apply invariant user % wallet % lots %', '17d52d2b-9325-479b-ba6b-f604f70c38e1', w, l;
  END IF;
END $v$;
COMMIT;
