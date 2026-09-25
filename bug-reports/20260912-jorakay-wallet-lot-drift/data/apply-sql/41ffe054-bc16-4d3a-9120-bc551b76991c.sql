BEGIN;
UPDATE wallet_ledger SET deductible_balance = 0.0 WHERE id = 'c5d08e49-c330-4494-a4ac-cabcc57d02b1'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = '41ffe054-bc16-4d3a-9120-bc551b76991c'::uuid;
UPDATE wallet_ledger SET deductible_balance = 0.0 WHERE id = 'b3dae78e-7c09-46ef-a1a4-bfed630f59d9'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = '41ffe054-bc16-4d3a-9120-bc551b76991c'::uuid;
UPDATE wallet_ledger SET deductible_balance = 0.0 WHERE id = 'c640ee7a-29fb-4433-a0ab-b0b5421fdc8a'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = '41ffe054-bc16-4d3a-9120-bc551b76991c'::uuid;
UPDATE wallet_ledger SET deductible_balance = 0.0 WHERE id = 'c72bba4d-4c96-4ca1-8a7d-c6095a107349'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = '41ffe054-bc16-4d3a-9120-bc551b76991c'::uuid;
UPDATE wallet_ledger SET deductible_balance = 0.0 WHERE id = '0978a2e2-58fd-4a4a-968b-24855e4df621'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = '41ffe054-bc16-4d3a-9120-bc551b76991c'::uuid;
UPDATE wallet_ledger SET deductible_balance = 0.0 WHERE id = 'f9f16f3b-611b-48f6-aa6d-dec8c69190e9'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = '41ffe054-bc16-4d3a-9120-bc551b76991c'::uuid;
UPDATE wallet_ledger SET deductible_balance = 0.0 WHERE id = 'f94f9b58-ff9d-447a-9bfc-a1ce0129899a'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = '41ffe054-bc16-4d3a-9120-bc551b76991c'::uuid;
UPDATE wallet_ledger SET deductible_balance = 0.0 WHERE id = 'aae7a004-450b-4bd1-abe9-79cc76f98886'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = '41ffe054-bc16-4d3a-9120-bc551b76991c'::uuid;
UPDATE wallet_ledger SET deductible_balance = 157.0 WHERE id = '09216f84-e207-4150-b82f-9e1fd1465242'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = '41ffe054-bc16-4d3a-9120-bc551b76991c'::uuid;
DO $v$
DECLARE w numeric; l numeric;
BEGIN
  SELECT points_balance INTO w FROM user_wallet WHERE user_id = '41ffe054-bc16-4d3a-9120-bc551b76991c'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid;
  SELECT coalesce(sum(deductible_balance),0) INTO l FROM wallet_ledger
    WHERE user_id = '41ffe054-bc16-4d3a-9120-bc551b76991c'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid
      AND currency = 'points' AND transaction_type = 'earn';
  IF abs(w - l) > 0.01 THEN
    RAISE EXCEPTION 'post-apply invariant user % wallet % lots %', '41ffe054-bc16-4d3a-9120-bc551b76991c', w, l;
  END IF;
END $v$;
COMMIT;
