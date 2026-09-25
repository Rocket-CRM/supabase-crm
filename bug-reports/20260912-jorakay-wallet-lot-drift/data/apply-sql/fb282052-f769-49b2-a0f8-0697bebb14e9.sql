BEGIN;
UPDATE wallet_ledger SET deductible_balance = 410.0 WHERE id = 'a5c2f79c-4031-4055-9b97-46a6bdfc3493'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = 'fb282052-f769-49b2-a0f8-0697bebb14e9'::uuid;
UPDATE wallet_ledger SET deductible_balance = 162.0 WHERE id = 'ab25fcb7-beb7-4edf-b066-3091c4eac1eb'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = 'fb282052-f769-49b2-a0f8-0697bebb14e9'::uuid;
DO $v$
DECLARE w numeric; l numeric;
BEGIN
  SELECT points_balance INTO w FROM user_wallet WHERE user_id = 'fb282052-f769-49b2-a0f8-0697bebb14e9'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid;
  SELECT coalesce(sum(deductible_balance),0) INTO l FROM wallet_ledger
    WHERE user_id = 'fb282052-f769-49b2-a0f8-0697bebb14e9'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid
      AND currency = 'points' AND transaction_type = 'earn';
  IF abs(w - l) > 0.01 THEN
    RAISE EXCEPTION 'post-apply invariant user % wallet % lots %', 'fb282052-f769-49b2-a0f8-0697bebb14e9', w, l;
  END IF;
END $v$;
COMMIT;
