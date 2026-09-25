BEGIN;
UPDATE wallet_ledger SET deductible_balance = 530.0 WHERE id = 'de5f460a-e6d1-4e7e-b690-84f845ecb1c6'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = 'c3a36840-ae4f-4995-9c2f-522410a8636f'::uuid;
UPDATE wallet_ledger SET deductible_balance = 530.0 WHERE id = '7e0ee72f-ea49-4551-aabd-70dd5a08d8c6'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = 'c3a36840-ae4f-4995-9c2f-522410a8636f'::uuid;
UPDATE wallet_ledger SET deductible_balance = 530.0 WHERE id = 'c77ee744-3866-4c4f-8a42-8e3f2247178e'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = 'c3a36840-ae4f-4995-9c2f-522410a8636f'::uuid;
UPDATE wallet_ledger SET deductible_balance = 530.0 WHERE id = 'bd5ebed4-30a5-44d6-a337-460d0008af2d'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = 'c3a36840-ae4f-4995-9c2f-522410a8636f'::uuid;
DO $v$
DECLARE w numeric; l numeric;
BEGIN
  SELECT points_balance INTO w FROM user_wallet WHERE user_id = 'c3a36840-ae4f-4995-9c2f-522410a8636f'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid;
  SELECT coalesce(sum(deductible_balance),0) INTO l FROM wallet_ledger
    WHERE user_id = 'c3a36840-ae4f-4995-9c2f-522410a8636f'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid
      AND currency = 'points' AND transaction_type = 'earn';
  IF abs(w - l) > 0.01 THEN
    RAISE EXCEPTION 'post-apply invariant user % wallet % lots %', 'c3a36840-ae4f-4995-9c2f-522410a8636f', w, l;
  END IF;
END $v$;
COMMIT;
