BEGIN;
UPDATE wallet_ledger SET deductible_balance = 5.0 WHERE id = 'a002ed44-93e8-489f-8ede-e30c159d4036'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = 'f596f347-c4e9-466e-955c-15cce84ecb25'::uuid;
UPDATE wallet_ledger SET deductible_balance = 95.0 WHERE id = 'fea66481-81c8-407d-ab86-0c6b9befbbb3'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = 'f596f347-c4e9-466e-955c-15cce84ecb25'::uuid;
DO $v$
DECLARE w numeric; l numeric;
BEGIN
  SELECT points_balance INTO w FROM user_wallet WHERE user_id = 'f596f347-c4e9-466e-955c-15cce84ecb25'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid;
  SELECT coalesce(sum(deductible_balance),0) INTO l FROM wallet_ledger
    WHERE user_id = 'f596f347-c4e9-466e-955c-15cce84ecb25'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid
      AND currency = 'points' AND transaction_type = 'earn';
  IF abs(w - l) > 0.01 THEN
    RAISE EXCEPTION 'post-apply invariant user % wallet % lots %', 'f596f347-c4e9-466e-955c-15cce84ecb25', w, l;
  END IF;
END $v$;
COMMIT;
