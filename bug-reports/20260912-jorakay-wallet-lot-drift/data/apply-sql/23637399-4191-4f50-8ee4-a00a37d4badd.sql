BEGIN;
UPDATE wallet_ledger SET deductible_balance = 521.0 WHERE id = '048e2273-5624-4e0f-9cbd-723b82e4ccfa'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = '23637399-4191-4f50-8ee4-a00a37d4badd'::uuid;
UPDATE wallet_ledger SET deductible_balance = 159.0 WHERE id = '1f7ce012-3aa9-4d8e-8854-2914122d218c'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = '23637399-4191-4f50-8ee4-a00a37d4badd'::uuid;
UPDATE wallet_ledger SET deductible_balance = 384.0 WHERE id = 'fd421f52-56c2-4f39-99e2-bf5d1319657d'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = '23637399-4191-4f50-8ee4-a00a37d4badd'::uuid;
UPDATE wallet_ledger SET deductible_balance = 900.0 WHERE id = '87b19a8b-adbf-48eb-b82c-7248fde67ec5'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = '23637399-4191-4f50-8ee4-a00a37d4badd'::uuid;
UPDATE wallet_ledger SET deductible_balance = 50.0 WHERE id = 'd49cb155-a17a-4a76-8f2e-05949ab90bc0'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = '23637399-4191-4f50-8ee4-a00a37d4badd'::uuid;
UPDATE wallet_ledger SET deductible_balance = 75.0 WHERE id = '0bbe9c6b-e02f-46f7-9c2e-16362d169497'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = '23637399-4191-4f50-8ee4-a00a37d4badd'::uuid;
UPDATE wallet_ledger SET deductible_balance = 79.0 WHERE id = '6ee185ef-01a9-4e02-a9b6-cddb8b4cb95c'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = '23637399-4191-4f50-8ee4-a00a37d4badd'::uuid;
UPDATE wallet_ledger SET deductible_balance = 720.0 WHERE id = 'aac7f559-1fa1-45cb-bb1f-08fb02f4a41a'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = '23637399-4191-4f50-8ee4-a00a37d4badd'::uuid;
DO $v$
DECLARE w numeric; l numeric;
BEGIN
  SELECT points_balance INTO w FROM user_wallet WHERE user_id = '23637399-4191-4f50-8ee4-a00a37d4badd'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid;
  SELECT coalesce(sum(deductible_balance),0) INTO l FROM wallet_ledger
    WHERE user_id = '23637399-4191-4f50-8ee4-a00a37d4badd'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid
      AND currency = 'points' AND transaction_type = 'earn';
  IF abs(w - l) > 0.01 THEN
    RAISE EXCEPTION 'post-apply invariant user % wallet % lots %', '23637399-4191-4f50-8ee4-a00a37d4badd', w, l;
  END IF;
END $v$;
COMMIT;
