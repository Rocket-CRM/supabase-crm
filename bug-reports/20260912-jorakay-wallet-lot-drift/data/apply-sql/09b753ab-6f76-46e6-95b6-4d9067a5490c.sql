BEGIN;
UPDATE wallet_ledger SET deductible_balance = 0.0 WHERE id = '55ab5e09-202a-4976-9e24-31c113bb7332'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = '09b753ab-6f76-46e6-95b6-4d9067a5490c'::uuid;
UPDATE wallet_ledger SET deductible_balance = 0.0 WHERE id = '70bc7d08-3930-41b6-9167-154f75b87f72'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = '09b753ab-6f76-46e6-95b6-4d9067a5490c'::uuid;
UPDATE wallet_ledger SET deductible_balance = 0.0 WHERE id = 'a443994a-5275-4999-a95f-86fab22d7fb8'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = '09b753ab-6f76-46e6-95b6-4d9067a5490c'::uuid;
UPDATE wallet_ledger SET deductible_balance = 0.0 WHERE id = 'aaa4fac8-4e06-42bc-a403-b8fb26de0b65'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = '09b753ab-6f76-46e6-95b6-4d9067a5490c'::uuid;
UPDATE wallet_ledger SET deductible_balance = 0.0 WHERE id = '15c2b571-0f46-46fe-af54-fb5f11ef8c8f'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = '09b753ab-6f76-46e6-95b6-4d9067a5490c'::uuid;
UPDATE wallet_ledger SET deductible_balance = 63.0 WHERE id = '978d4161-bff8-4c50-8a17-fa60dd74a926'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = '09b753ab-6f76-46e6-95b6-4d9067a5490c'::uuid;
DO $v$
DECLARE w numeric; l numeric;
BEGIN
  SELECT points_balance INTO w FROM user_wallet WHERE user_id = '09b753ab-6f76-46e6-95b6-4d9067a5490c'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid;
  SELECT coalesce(sum(deductible_balance),0) INTO l FROM wallet_ledger
    WHERE user_id = '09b753ab-6f76-46e6-95b6-4d9067a5490c'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid
      AND currency = 'points' AND transaction_type = 'earn';
  IF abs(w - l) > 0.01 THEN
    RAISE EXCEPTION 'post-apply invariant user % wallet % lots %', '09b753ab-6f76-46e6-95b6-4d9067a5490c', w, l;
  END IF;
END $v$;
COMMIT;
