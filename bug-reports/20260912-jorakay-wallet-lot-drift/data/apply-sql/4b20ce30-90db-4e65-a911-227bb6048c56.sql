BEGIN;
UPDATE wallet_ledger SET deductible_balance = 0.0 WHERE id = '542d23eb-a78e-4165-a17e-d1fa5453842d'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = '4b20ce30-90db-4e65-a911-227bb6048c56'::uuid;
UPDATE wallet_ledger SET deductible_balance = 0.0 WHERE id = '57265e85-9fdc-48b4-8239-3810e483c630'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = '4b20ce30-90db-4e65-a911-227bb6048c56'::uuid;
UPDATE wallet_ledger SET deductible_balance = 0.0 WHERE id = '9743bee9-64a8-4c70-a57c-12c1fe891b7a'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = '4b20ce30-90db-4e65-a911-227bb6048c56'::uuid;
UPDATE wallet_ledger SET deductible_balance = 64.0 WHERE id = '7b0a7d31-ac79-480e-8b17-1c6594f5b2ae'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = '4b20ce30-90db-4e65-a911-227bb6048c56'::uuid;
UPDATE wallet_ledger SET deductible_balance = 580.0 WHERE id = '7aca75e4-575c-4a52-b2cb-207e5bd4c303'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = '4b20ce30-90db-4e65-a911-227bb6048c56'::uuid;
UPDATE wallet_ledger SET deductible_balance = 62.0 WHERE id = '72bbae1e-26ad-49ec-a80c-119cf3851d52'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = '4b20ce30-90db-4e65-a911-227bb6048c56'::uuid;
UPDATE wallet_ledger SET deductible_balance = 580.0 WHERE id = '5d99d272-ace3-48d6-9738-45eaac38f9aa'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = '4b20ce30-90db-4e65-a911-227bb6048c56'::uuid;
DO $v$
DECLARE w numeric; l numeric;
BEGIN
  SELECT points_balance INTO w FROM user_wallet WHERE user_id = '4b20ce30-90db-4e65-a911-227bb6048c56'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid;
  SELECT coalesce(sum(deductible_balance),0) INTO l FROM wallet_ledger
    WHERE user_id = '4b20ce30-90db-4e65-a911-227bb6048c56'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid
      AND currency = 'points' AND transaction_type = 'earn';
  IF abs(w - l) > 0.01 THEN
    RAISE EXCEPTION 'post-apply invariant user % wallet % lots %', '4b20ce30-90db-4e65-a911-227bb6048c56', w, l;
  END IF;
END $v$;
COMMIT;
