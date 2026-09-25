BEGIN;
UPDATE wallet_ledger SET deductible_balance = 0.0 WHERE id = '3e96ccef-664f-42db-ac60-5c27b9c61f00'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = '3ad89e23-176b-45f2-a538-7c3ebfb0f122'::uuid;
UPDATE wallet_ledger SET deductible_balance = 0.0 WHERE id = 'decc4f0f-9348-40cd-bb83-adc1c692928e'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = '3ad89e23-176b-45f2-a538-7c3ebfb0f122'::uuid;
UPDATE wallet_ledger SET deductible_balance = 0.0 WHERE id = '8de8bfce-1cd7-4620-9366-ba3888bc28b5'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = '3ad89e23-176b-45f2-a538-7c3ebfb0f122'::uuid;
UPDATE wallet_ledger SET deductible_balance = 1940.0 WHERE id = 'c76904bf-649d-493a-a7e3-9375b77fd3b6'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = '3ad89e23-176b-45f2-a538-7c3ebfb0f122'::uuid;
DO $v$
DECLARE w numeric; l numeric;
BEGIN
  SELECT points_balance INTO w FROM user_wallet WHERE user_id = '3ad89e23-176b-45f2-a538-7c3ebfb0f122'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid;
  SELECT coalesce(sum(deductible_balance),0) INTO l FROM wallet_ledger
    WHERE user_id = '3ad89e23-176b-45f2-a538-7c3ebfb0f122'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid
      AND currency = 'points' AND transaction_type = 'earn';
  IF abs(w - l) > 0.01 THEN
    RAISE EXCEPTION 'post-apply invariant user % wallet % lots %', '3ad89e23-176b-45f2-a538-7c3ebfb0f122', w, l;
  END IF;
END $v$;
COMMIT;
