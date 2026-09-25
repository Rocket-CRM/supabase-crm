BEGIN;
UPDATE wallet_ledger SET deductible_balance = 0.0 WHERE id = '9779f401-78ba-4fd6-b46a-d5fe8f9563ad'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = 'eac6f8e7-1c1d-4b0d-b460-1842b99b1722'::uuid;
UPDATE wallet_ledger SET deductible_balance = 0.0 WHERE id = '93d1a917-20e7-4da4-b111-5c216c571d33'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = 'eac6f8e7-1c1d-4b0d-b460-1842b99b1722'::uuid;
UPDATE wallet_ledger SET deductible_balance = 0.0 WHERE id = 'ad19b545-49ee-444c-9338-5d5520c793ef'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = 'eac6f8e7-1c1d-4b0d-b460-1842b99b1722'::uuid;
UPDATE wallet_ledger SET deductible_balance = 0.0 WHERE id = 'b177d0d8-a66d-4232-bd18-6fab3091fafb'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = 'eac6f8e7-1c1d-4b0d-b460-1842b99b1722'::uuid;
UPDATE wallet_ledger SET deductible_balance = 0.0 WHERE id = '29d53b3c-de8e-44bb-88c3-8c3e14211a03'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = 'eac6f8e7-1c1d-4b0d-b460-1842b99b1722'::uuid;
UPDATE wallet_ledger SET deductible_balance = 0.0 WHERE id = '4224f76b-f5cb-4f0f-a7bf-7698dcc03f4e'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = 'eac6f8e7-1c1d-4b0d-b460-1842b99b1722'::uuid;
UPDATE wallet_ledger SET deductible_balance = 8.0 WHERE id = '6d281e7c-0d28-4cdf-8534-8cd88d7ffec1'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = 'eac6f8e7-1c1d-4b0d-b460-1842b99b1722'::uuid;
DO $v$
DECLARE w numeric; l numeric;
BEGIN
  SELECT points_balance INTO w FROM user_wallet WHERE user_id = 'eac6f8e7-1c1d-4b0d-b460-1842b99b1722'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid;
  SELECT coalesce(sum(deductible_balance),0) INTO l FROM wallet_ledger
    WHERE user_id = 'eac6f8e7-1c1d-4b0d-b460-1842b99b1722'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid
      AND currency = 'points' AND transaction_type = 'earn';
  IF abs(w - l) > 0.01 THEN
    RAISE EXCEPTION 'post-apply invariant user % wallet % lots %', 'eac6f8e7-1c1d-4b0d-b460-1842b99b1722', w, l;
  END IF;
END $v$;
COMMIT;
