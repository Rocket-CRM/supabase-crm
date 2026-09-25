BEGIN;
UPDATE wallet_ledger SET deductible_balance = 76.0 WHERE id = 'a14a6122-080a-4c95-9ee6-212c9500ac37'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = '3e091fa2-39fd-4b08-b3f1-7a23325d3fe3'::uuid;
UPDATE wallet_ledger SET deductible_balance = 96.0 WHERE id = '7ec46e1c-7adb-4b9c-b2bf-27034a597437'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = '3e091fa2-39fd-4b08-b3f1-7a23325d3fe3'::uuid;
UPDATE wallet_ledger SET deductible_balance = 168.0 WHERE id = '10109a32-1e20-4cf2-ac4a-47d700d2b550'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = '3e091fa2-39fd-4b08-b3f1-7a23325d3fe3'::uuid;
UPDATE wallet_ledger SET deductible_balance = 307.0 WHERE id = '0f6722eb-3f4f-42a7-8a22-0ff840362830'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = '3e091fa2-39fd-4b08-b3f1-7a23325d3fe3'::uuid;
DO $v$
DECLARE w numeric; l numeric;
BEGIN
  SELECT points_balance INTO w FROM user_wallet WHERE user_id = '3e091fa2-39fd-4b08-b3f1-7a23325d3fe3'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid;
  SELECT coalesce(sum(deductible_balance),0) INTO l FROM wallet_ledger
    WHERE user_id = '3e091fa2-39fd-4b08-b3f1-7a23325d3fe3'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid
      AND currency = 'points' AND transaction_type = 'earn';
  IF abs(w - l) > 0.01 THEN
    RAISE EXCEPTION 'post-apply invariant user % wallet % lots %', '3e091fa2-39fd-4b08-b3f1-7a23325d3fe3', w, l;
  END IF;
END $v$;
COMMIT;
