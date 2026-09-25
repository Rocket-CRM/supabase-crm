BEGIN;
UPDATE wallet_ledger SET deductible_balance = 405.0 WHERE id = 'aaa3cd85-d45e-47b0-8f46-23af52bc5ab8'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = 'd4a7bba0-10b5-4c44-a85d-4a0a301f31cc'::uuid;
UPDATE wallet_ledger SET deductible_balance = 195.0 WHERE id = '711a80d9-638f-4674-b854-e737931930dc'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = 'd4a7bba0-10b5-4c44-a85d-4a0a301f31cc'::uuid;
UPDATE wallet_ledger SET deductible_balance = 269.0 WHERE id = '94e66b24-5772-476c-bb0b-7de1a2405a1e'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = 'd4a7bba0-10b5-4c44-a85d-4a0a301f31cc'::uuid;
UPDATE wallet_ledger SET deductible_balance = 225.0 WHERE id = '21a64d28-48d4-4723-8dfc-e5a7c5a4a26a'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = 'd4a7bba0-10b5-4c44-a85d-4a0a301f31cc'::uuid;
UPDATE wallet_ledger SET deductible_balance = 95.0 WHERE id = 'ed97b4a0-0c2b-4426-b92b-3dc38b46aed2'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = 'd4a7bba0-10b5-4c44-a85d-4a0a301f31cc'::uuid;
UPDATE wallet_ledger SET deductible_balance = 119.0 WHERE id = '69791b5c-bd8f-4d08-bfff-4a486c8a9e36'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = 'd4a7bba0-10b5-4c44-a85d-4a0a301f31cc'::uuid;
UPDATE wallet_ledger SET deductible_balance = 379.0 WHERE id = '0fbc709c-b0d3-440d-bb87-13c686a76ee8'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = 'd4a7bba0-10b5-4c44-a85d-4a0a301f31cc'::uuid;
UPDATE wallet_ledger SET deductible_balance = 572.0 WHERE id = '7a2177f7-9fcf-4805-a723-e3f5f4d9d33c'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = 'd4a7bba0-10b5-4c44-a85d-4a0a301f31cc'::uuid;
UPDATE wallet_ledger SET deductible_balance = 22.0 WHERE id = 'e678c836-86f4-49bc-9c84-7d1a0ae3c79f'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = 'd4a7bba0-10b5-4c44-a85d-4a0a301f31cc'::uuid;
UPDATE wallet_ledger SET deductible_balance = 343.0 WHERE id = '433ea4ed-4125-4a04-975d-63070372fdf7'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = 'd4a7bba0-10b5-4c44-a85d-4a0a301f31cc'::uuid;
UPDATE wallet_ledger SET deductible_balance = 114.0 WHERE id = 'a4006435-8749-42cc-a80c-8f55ebd76a8c'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = 'd4a7bba0-10b5-4c44-a85d-4a0a301f31cc'::uuid;
UPDATE wallet_ledger SET deductible_balance = 329.0 WHERE id = 'f9362fbf-fa8e-4ce2-97d7-b8f650c770dc'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = 'd4a7bba0-10b5-4c44-a85d-4a0a301f31cc'::uuid;
DO $v$
DECLARE w numeric; l numeric;
BEGIN
  SELECT points_balance INTO w FROM user_wallet WHERE user_id = 'd4a7bba0-10b5-4c44-a85d-4a0a301f31cc'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid;
  SELECT coalesce(sum(deductible_balance),0) INTO l FROM wallet_ledger
    WHERE user_id = 'd4a7bba0-10b5-4c44-a85d-4a0a301f31cc'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid
      AND currency = 'points' AND transaction_type = 'earn';
  IF abs(w - l) > 0.01 THEN
    RAISE EXCEPTION 'post-apply invariant user % wallet % lots %', 'd4a7bba0-10b5-4c44-a85d-4a0a301f31cc', w, l;
  END IF;
END $v$;
COMMIT;
