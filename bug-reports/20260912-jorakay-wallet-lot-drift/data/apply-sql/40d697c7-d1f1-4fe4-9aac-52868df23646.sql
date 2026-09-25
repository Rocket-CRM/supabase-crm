BEGIN;
UPDATE wallet_ledger SET deductible_balance = 491.0 WHERE id = '797402cd-416c-45d5-8fc4-1bc2866ebe23'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = '40d697c7-d1f1-4fe4-9aac-52868df23646'::uuid;
UPDATE wallet_ledger SET deductible_balance = 512.0 WHERE id = '9affb557-20fa-4dfd-946b-76d4f01f97eb'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = '40d697c7-d1f1-4fe4-9aac-52868df23646'::uuid;
DO $v$
DECLARE w numeric; l numeric;
BEGIN
  SELECT points_balance INTO w FROM user_wallet WHERE user_id = '40d697c7-d1f1-4fe4-9aac-52868df23646'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid;
  SELECT coalesce(sum(deductible_balance),0) INTO l FROM wallet_ledger
    WHERE user_id = '40d697c7-d1f1-4fe4-9aac-52868df23646'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid
      AND currency = 'points' AND transaction_type = 'earn';
  IF abs(w - l) > 0.01 THEN
    RAISE EXCEPTION 'post-apply invariant user % wallet % lots %', '40d697c7-d1f1-4fe4-9aac-52868df23646', w, l;
  END IF;
END $v$;
COMMIT;
