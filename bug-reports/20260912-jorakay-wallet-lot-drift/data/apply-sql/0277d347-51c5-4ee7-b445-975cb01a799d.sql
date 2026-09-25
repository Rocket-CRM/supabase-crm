BEGIN;
UPDATE wallet_ledger SET deductible_balance = 0.0 WHERE id = '1d492714-e37a-4788-a902-fe84ccbe5c50'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = '0277d347-51c5-4ee7-b445-975cb01a799d'::uuid;
UPDATE wallet_ledger SET deductible_balance = 0.0 WHERE id = 'a46963bb-aea2-4585-bfd8-50a5af4f0c91'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = '0277d347-51c5-4ee7-b445-975cb01a799d'::uuid;
UPDATE wallet_ledger SET deductible_balance = 0.0 WHERE id = 'a56ddb13-a96e-4946-b3f9-ea988536bf69'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = '0277d347-51c5-4ee7-b445-975cb01a799d'::uuid;
UPDATE wallet_ledger SET deductible_balance = 0.0 WHERE id = '5d21c250-c03a-4623-aa76-dd167ff2701d'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = '0277d347-51c5-4ee7-b445-975cb01a799d'::uuid;
UPDATE wallet_ledger SET deductible_balance = 0.0 WHERE id = 'e74964ca-c3f3-477c-80b0-29b361fdbcc2'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = '0277d347-51c5-4ee7-b445-975cb01a799d'::uuid;
UPDATE wallet_ledger SET deductible_balance = 82.0 WHERE id = '06c5f3ec-7e0e-437c-ab83-579079adaf1a'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = '0277d347-51c5-4ee7-b445-975cb01a799d'::uuid;
UPDATE wallet_ledger SET deductible_balance = 358.0 WHERE id = '9f11a94a-a055-4fea-a0e0-d97c82fa8b2e'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = '0277d347-51c5-4ee7-b445-975cb01a799d'::uuid;
DO $v$
DECLARE w numeric; l numeric;
BEGIN
  SELECT points_balance INTO w FROM user_wallet WHERE user_id = '0277d347-51c5-4ee7-b445-975cb01a799d'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid;
  SELECT coalesce(sum(deductible_balance),0) INTO l FROM wallet_ledger
    WHERE user_id = '0277d347-51c5-4ee7-b445-975cb01a799d'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid
      AND currency = 'points' AND transaction_type = 'earn';
  IF abs(w - l) > 0.01 THEN
    RAISE EXCEPTION 'post-apply invariant user % wallet % lots %', '0277d347-51c5-4ee7-b445-975cb01a799d', w, l;
  END IF;
END $v$;
COMMIT;
