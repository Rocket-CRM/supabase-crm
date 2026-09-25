BEGIN;
UPDATE wallet_ledger SET deductible_balance = 392.0 WHERE id = '3baac979-4022-4736-b69d-3d09746aa2ce'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = '3c2527ee-11dd-4a52-b5df-1f6f06e7ecec'::uuid;
UPDATE wallet_ledger SET deductible_balance = 1380.0 WHERE id = 'a5069e94-b2e1-4199-9e22-670490b7b8a0'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = '3c2527ee-11dd-4a52-b5df-1f6f06e7ecec'::uuid;
UPDATE wallet_ledger SET deductible_balance = 344.0 WHERE id = 'c50410ca-123c-4388-b4dd-471d707a439f'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = '3c2527ee-11dd-4a52-b5df-1f6f06e7ecec'::uuid;
DO $v$
DECLARE w numeric; l numeric;
BEGIN
  SELECT points_balance INTO w FROM user_wallet WHERE user_id = '3c2527ee-11dd-4a52-b5df-1f6f06e7ecec'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid;
  SELECT coalesce(sum(deductible_balance),0) INTO l FROM wallet_ledger
    WHERE user_id = '3c2527ee-11dd-4a52-b5df-1f6f06e7ecec'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid
      AND currency = 'points' AND transaction_type = 'earn';
  IF abs(w - l) > 0.01 THEN
    RAISE EXCEPTION 'post-apply invariant user % wallet % lots %', '3c2527ee-11dd-4a52-b5df-1f6f06e7ecec', w, l;
  END IF;
END $v$;
COMMIT;
