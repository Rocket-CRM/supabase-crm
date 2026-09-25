BEGIN;
UPDATE wallet_ledger SET deductible_balance = 0.0 WHERE id = '172fd7f2-b870-41e2-b216-83d20f37b5f3'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = '2bec1b40-59f3-437e-837c-8efbeb58b416'::uuid;
UPDATE wallet_ledger SET deductible_balance = 0.0 WHERE id = 'ef33603d-9d3c-4a6f-81d8-8e6d7aa68934'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = '2bec1b40-59f3-437e-837c-8efbeb58b416'::uuid;
UPDATE wallet_ledger SET deductible_balance = 0.0 WHERE id = 'aa675036-6eec-467e-8fc3-529e65454c09'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = '2bec1b40-59f3-437e-837c-8efbeb58b416'::uuid;
UPDATE wallet_ledger SET deductible_balance = 210.0 WHERE id = '31a51a92-367d-4345-a87b-801ee6e05261'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = '2bec1b40-59f3-437e-837c-8efbeb58b416'::uuid;
DO $v$
DECLARE w numeric; l numeric;
BEGIN
  SELECT points_balance INTO w FROM user_wallet WHERE user_id = '2bec1b40-59f3-437e-837c-8efbeb58b416'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid;
  SELECT coalesce(sum(deductible_balance),0) INTO l FROM wallet_ledger
    WHERE user_id = '2bec1b40-59f3-437e-837c-8efbeb58b416'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid
      AND currency = 'points' AND transaction_type = 'earn';
  IF abs(w - l) > 0.01 THEN
    RAISE EXCEPTION 'post-apply invariant user % wallet % lots %', '2bec1b40-59f3-437e-837c-8efbeb58b416', w, l;
  END IF;
END $v$;
COMMIT;
