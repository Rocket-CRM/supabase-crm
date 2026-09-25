BEGIN;
UPDATE wallet_ledger SET deductible_balance = 0.0 WHERE id = '8b38df78-a9f3-4b31-8e32-f0c03ff64167'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = '4f63443d-b500-447e-ac1e-0c62a15e19d0'::uuid;
UPDATE wallet_ledger SET deductible_balance = 0.0 WHERE id = '142748dc-7161-4b7d-844b-f7500c29f7f5'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = '4f63443d-b500-447e-ac1e-0c62a15e19d0'::uuid;
UPDATE wallet_ledger SET deductible_balance = 1199.0 WHERE id = '27edd66d-ca06-412f-aad9-d00a2c7af690'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = '4f63443d-b500-447e-ac1e-0c62a15e19d0'::uuid;
DO $v$
DECLARE w numeric; l numeric;
BEGIN
  SELECT points_balance INTO w FROM user_wallet WHERE user_id = '4f63443d-b500-447e-ac1e-0c62a15e19d0'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid;
  SELECT coalesce(sum(deductible_balance),0) INTO l FROM wallet_ledger
    WHERE user_id = '4f63443d-b500-447e-ac1e-0c62a15e19d0'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid
      AND currency = 'points' AND transaction_type = 'earn';
  IF abs(w - l) > 0.01 THEN
    RAISE EXCEPTION 'post-apply invariant user % wallet % lots %', '4f63443d-b500-447e-ac1e-0c62a15e19d0', w, l;
  END IF;
END $v$;
COMMIT;
