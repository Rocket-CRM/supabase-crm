BEGIN;
UPDATE wallet_ledger SET deductible_balance = 0.0 WHERE id = '232bfbcc-d9de-4b53-8354-de02da82a766'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = 'ab0eed90-6825-4c0c-bc94-f327cbc141e0'::uuid;
UPDATE wallet_ledger SET deductible_balance = 0.0 WHERE id = '6c81650a-5809-4c13-98b7-98b3b9630cfc'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = 'ab0eed90-6825-4c0c-bc94-f327cbc141e0'::uuid;
UPDATE wallet_ledger SET deductible_balance = 0.0 WHERE id = '72f4cdd0-4b5f-4385-93b0-ae7345f9fa41'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = 'ab0eed90-6825-4c0c-bc94-f327cbc141e0'::uuid;
UPDATE wallet_ledger SET deductible_balance = 0.0 WHERE id = '962a325f-81d0-4f02-a272-7fd52e922eaa'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = 'ab0eed90-6825-4c0c-bc94-f327cbc141e0'::uuid;
UPDATE wallet_ledger SET deductible_balance = 0.0 WHERE id = '63559fa6-d7e7-41e0-807a-9519ba65c027'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = 'ab0eed90-6825-4c0c-bc94-f327cbc141e0'::uuid;
UPDATE wallet_ledger SET deductible_balance = 7.0 WHERE id = '1d8140e8-8c76-4ffd-8e23-0a06ae0fa11c'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = 'ab0eed90-6825-4c0c-bc94-f327cbc141e0'::uuid;
DO $v$
DECLARE w numeric; l numeric;
BEGIN
  SELECT points_balance INTO w FROM user_wallet WHERE user_id = 'ab0eed90-6825-4c0c-bc94-f327cbc141e0'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid;
  SELECT coalesce(sum(deductible_balance),0) INTO l FROM wallet_ledger
    WHERE user_id = 'ab0eed90-6825-4c0c-bc94-f327cbc141e0'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid
      AND currency = 'points' AND transaction_type = 'earn';
  IF abs(w - l) > 0.01 THEN
    RAISE EXCEPTION 'post-apply invariant user % wallet % lots %', 'ab0eed90-6825-4c0c-bc94-f327cbc141e0', w, l;
  END IF;
END $v$;
COMMIT;
