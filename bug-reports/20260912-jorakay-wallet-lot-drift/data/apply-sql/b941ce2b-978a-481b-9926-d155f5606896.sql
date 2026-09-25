BEGIN;
UPDATE wallet_ledger SET deductible_balance = 272.0 WHERE id = '401bd253-890d-490f-bae5-6d93fd7c53b8'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = 'b941ce2b-978a-481b-9926-d155f5606896'::uuid;
UPDATE wallet_ledger SET deductible_balance = 397.0 WHERE id = 'df7fa792-1cb8-4eff-93eb-401bd4ee7003'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = 'b941ce2b-978a-481b-9926-d155f5606896'::uuid;
DO $v$
DECLARE w numeric; l numeric;
BEGIN
  SELECT points_balance INTO w FROM user_wallet WHERE user_id = 'b941ce2b-978a-481b-9926-d155f5606896'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid;
  SELECT coalesce(sum(deductible_balance),0) INTO l FROM wallet_ledger
    WHERE user_id = 'b941ce2b-978a-481b-9926-d155f5606896'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid
      AND currency = 'points' AND transaction_type = 'earn';
  IF abs(w - l) > 0.01 THEN
    RAISE EXCEPTION 'post-apply invariant user % wallet % lots %', 'b941ce2b-978a-481b-9926-d155f5606896', w, l;
  END IF;
END $v$;
COMMIT;
