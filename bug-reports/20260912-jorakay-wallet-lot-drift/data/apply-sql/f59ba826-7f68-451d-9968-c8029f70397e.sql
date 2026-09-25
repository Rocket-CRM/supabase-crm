BEGIN;
UPDATE wallet_ledger SET deductible_balance = 32.0 WHERE id = '86d18865-36a5-44ec-8bb9-7b75cc0e3f2d'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = 'f59ba826-7f68-451d-9968-c8029f70397e'::uuid;
UPDATE wallet_ledger SET deductible_balance = 33.0 WHERE id = '65d33065-49bb-43cb-a1f0-c71183b857c0'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = 'f59ba826-7f68-451d-9968-c8029f70397e'::uuid;
UPDATE wallet_ledger SET deductible_balance = 2.0 WHERE id = '1140b720-67a8-4cd2-82c0-28a9df66a8cb'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = 'f59ba826-7f68-451d-9968-c8029f70397e'::uuid;
DO $v$
DECLARE w numeric; l numeric;
BEGIN
  SELECT points_balance INTO w FROM user_wallet WHERE user_id = 'f59ba826-7f68-451d-9968-c8029f70397e'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid;
  SELECT coalesce(sum(deductible_balance),0) INTO l FROM wallet_ledger
    WHERE user_id = 'f59ba826-7f68-451d-9968-c8029f70397e'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid
      AND currency = 'points' AND transaction_type = 'earn';
  IF abs(w - l) > 0.01 THEN
    RAISE EXCEPTION 'post-apply invariant user % wallet % lots %', 'f59ba826-7f68-451d-9968-c8029f70397e', w, l;
  END IF;
END $v$;
COMMIT;
