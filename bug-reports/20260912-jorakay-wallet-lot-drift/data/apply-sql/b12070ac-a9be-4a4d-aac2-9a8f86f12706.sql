BEGIN;
UPDATE wallet_ledger SET deductible_balance = 324.0 WHERE id = '4e662f4c-00c0-41b6-a11d-edb66d103a3f'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = 'b12070ac-a9be-4a4d-aac2-9a8f86f12706'::uuid;
DO $v$
DECLARE w numeric; l numeric;
BEGIN
  SELECT points_balance INTO w FROM user_wallet WHERE user_id = 'b12070ac-a9be-4a4d-aac2-9a8f86f12706'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid;
  SELECT coalesce(sum(deductible_balance),0) INTO l FROM wallet_ledger
    WHERE user_id = 'b12070ac-a9be-4a4d-aac2-9a8f86f12706'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid
      AND currency = 'points' AND transaction_type = 'earn';
  IF abs(w - l) > 0.01 THEN
    RAISE EXCEPTION 'post-apply invariant user % wallet % lots %', 'b12070ac-a9be-4a4d-aac2-9a8f86f12706', w, l;
  END IF;
END $v$;
COMMIT;
