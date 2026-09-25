BEGIN;
UPDATE wallet_ledger SET deductible_balance = 0.0 WHERE id = '65b463a2-5b04-4e72-9aec-0b06f40071aa'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = '6f19b2a6-a193-4180-a39c-e00f2e0f6d21'::uuid;
UPDATE wallet_ledger SET deductible_balance = 123.0 WHERE id = 'e11f320c-c79a-43fa-bce2-12c5e0c230a3'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = '6f19b2a6-a193-4180-a39c-e00f2e0f6d21'::uuid;
UPDATE wallet_ledger SET deductible_balance = 531.0 WHERE id = '6619394d-9ff4-4bae-8aa3-14020ae12b0e'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = '6f19b2a6-a193-4180-a39c-e00f2e0f6d21'::uuid;
DO $v$
DECLARE w numeric; l numeric;
BEGIN
  SELECT points_balance INTO w FROM user_wallet WHERE user_id = '6f19b2a6-a193-4180-a39c-e00f2e0f6d21'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid;
  SELECT coalesce(sum(deductible_balance),0) INTO l FROM wallet_ledger
    WHERE user_id = '6f19b2a6-a193-4180-a39c-e00f2e0f6d21'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid
      AND currency = 'points' AND transaction_type = 'earn';
  IF abs(w - l) > 0.01 THEN
    RAISE EXCEPTION 'post-apply invariant user % wallet % lots %', '6f19b2a6-a193-4180-a39c-e00f2e0f6d21', w, l;
  END IF;
END $v$;
COMMIT;
