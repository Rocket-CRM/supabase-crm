BEGIN;
UPDATE wallet_ledger SET deductible_balance = 172.0 WHERE id = '6be02717-6f23-4924-859b-690cadf631bf'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = '680b8024-e029-4ea4-8f2a-98ad3a284d14'::uuid;
UPDATE wallet_ledger SET deductible_balance = 232.0 WHERE id = '1fcf8f24-aa91-4c23-abc7-6339b86afb02'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = '680b8024-e029-4ea4-8f2a-98ad3a284d14'::uuid;
UPDATE wallet_ledger SET deductible_balance = 45.0 WHERE id = '8a310add-2a08-4228-99d0-8f832c1e3c35'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = '680b8024-e029-4ea4-8f2a-98ad3a284d14'::uuid;
UPDATE wallet_ledger SET deductible_balance = 101.0 WHERE id = '58705415-f7ab-41fb-940f-664bd899d620'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = '680b8024-e029-4ea4-8f2a-98ad3a284d14'::uuid;
DO $v$
DECLARE w numeric; l numeric;
BEGIN
  SELECT points_balance INTO w FROM user_wallet WHERE user_id = '680b8024-e029-4ea4-8f2a-98ad3a284d14'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid;
  SELECT coalesce(sum(deductible_balance),0) INTO l FROM wallet_ledger
    WHERE user_id = '680b8024-e029-4ea4-8f2a-98ad3a284d14'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid
      AND currency = 'points' AND transaction_type = 'earn';
  IF abs(w - l) > 0.01 THEN
    RAISE EXCEPTION 'post-apply invariant user % wallet % lots %', '680b8024-e029-4ea4-8f2a-98ad3a284d14', w, l;
  END IF;
END $v$;
COMMIT;
