BEGIN;
UPDATE wallet_ledger SET deductible_balance = 179.0 WHERE id = '071edb12-7654-40f9-b30f-332beb8c321f'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = 'd945a0eb-5a47-434b-882e-0f9b8f0fe3f0'::uuid;
UPDATE wallet_ledger SET deductible_balance = 25.0 WHERE id = '8d4c030c-3a90-483b-9a37-dd10fb72cbcd'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = 'd945a0eb-5a47-434b-882e-0f9b8f0fe3f0'::uuid;
DO $v$
DECLARE w numeric; l numeric;
BEGIN
  SELECT points_balance INTO w FROM user_wallet WHERE user_id = 'd945a0eb-5a47-434b-882e-0f9b8f0fe3f0'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid;
  SELECT coalesce(sum(deductible_balance),0) INTO l FROM wallet_ledger
    WHERE user_id = 'd945a0eb-5a47-434b-882e-0f9b8f0fe3f0'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid
      AND currency = 'points' AND transaction_type = 'earn';
  IF abs(w - l) > 0.01 THEN
    RAISE EXCEPTION 'post-apply invariant user % wallet % lots %', 'd945a0eb-5a47-434b-882e-0f9b8f0fe3f0', w, l;
  END IF;
END $v$;
COMMIT;
