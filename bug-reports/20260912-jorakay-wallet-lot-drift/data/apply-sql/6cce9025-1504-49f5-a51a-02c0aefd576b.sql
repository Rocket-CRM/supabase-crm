BEGIN;
UPDATE wallet_ledger SET deductible_balance = 6889.0 WHERE id = '3b1acfe5-4e31-44c1-8483-7c188771d61e'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = '6cce9025-1504-49f5-a51a-02c0aefd576b'::uuid;
UPDATE wallet_ledger SET deductible_balance = 618.0 WHERE id = '65f72556-b789-4f4b-ba32-36bc7b00765f'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = '6cce9025-1504-49f5-a51a-02c0aefd576b'::uuid;
UPDATE wallet_ledger SET deductible_balance = 360.0 WHERE id = 'dbb21154-64c3-4a26-841e-bf55322437f2'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = '6cce9025-1504-49f5-a51a-02c0aefd576b'::uuid;
UPDATE wallet_ledger SET deductible_balance = 360.0 WHERE id = 'c86bf6da-fe89-4e08-b030-63ec62fc063c'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = '6cce9025-1504-49f5-a51a-02c0aefd576b'::uuid;
DO $v$
DECLARE w numeric; l numeric;
BEGIN
  SELECT points_balance INTO w FROM user_wallet WHERE user_id = '6cce9025-1504-49f5-a51a-02c0aefd576b'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid;
  SELECT coalesce(sum(deductible_balance),0) INTO l FROM wallet_ledger
    WHERE user_id = '6cce9025-1504-49f5-a51a-02c0aefd576b'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid
      AND currency = 'points' AND transaction_type = 'earn';
  IF abs(w - l) > 0.01 THEN
    RAISE EXCEPTION 'post-apply invariant user % wallet % lots %', '6cce9025-1504-49f5-a51a-02c0aefd576b', w, l;
  END IF;
END $v$;
COMMIT;
