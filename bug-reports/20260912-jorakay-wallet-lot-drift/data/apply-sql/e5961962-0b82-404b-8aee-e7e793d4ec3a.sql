BEGIN;
UPDATE wallet_ledger SET deductible_balance = 0.0 WHERE id = '0023bdb6-2cd7-4dbf-abee-007cf62cf122'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = 'e5961962-0b82-404b-8aee-e7e793d4ec3a'::uuid;
UPDATE wallet_ledger SET deductible_balance = 0.0 WHERE id = '43e99477-7c18-4e7c-9676-eb864c76f906'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = 'e5961962-0b82-404b-8aee-e7e793d4ec3a'::uuid;
UPDATE wallet_ledger SET deductible_balance = 0.0 WHERE id = '1fa92b74-5dc5-491a-a6de-0ecc69d98b9c'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = 'e5961962-0b82-404b-8aee-e7e793d4ec3a'::uuid;
UPDATE wallet_ledger SET deductible_balance = 986.0 WHERE id = '10e05a7b-b941-469b-8023-a7f8e317b857'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = 'e5961962-0b82-404b-8aee-e7e793d4ec3a'::uuid;
DO $v$
DECLARE w numeric; l numeric;
BEGIN
  SELECT points_balance INTO w FROM user_wallet WHERE user_id = 'e5961962-0b82-404b-8aee-e7e793d4ec3a'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid;
  SELECT coalesce(sum(deductible_balance),0) INTO l FROM wallet_ledger
    WHERE user_id = 'e5961962-0b82-404b-8aee-e7e793d4ec3a'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid
      AND currency = 'points' AND transaction_type = 'earn';
  IF abs(w - l) > 0.01 THEN
    RAISE EXCEPTION 'post-apply invariant user % wallet % lots %', 'e5961962-0b82-404b-8aee-e7e793d4ec3a', w, l;
  END IF;
END $v$;
COMMIT;
