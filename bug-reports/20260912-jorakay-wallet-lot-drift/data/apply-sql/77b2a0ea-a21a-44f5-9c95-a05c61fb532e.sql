BEGIN;
UPDATE wallet_ledger SET deductible_balance = 33.0 WHERE id = '07245c9f-b464-4fc3-9715-c08d1207535c'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = '77b2a0ea-a21a-44f5-9c95-a05c61fb532e'::uuid;
DO $v$
DECLARE w numeric; l numeric;
BEGIN
  SELECT points_balance INTO w FROM user_wallet WHERE user_id = '77b2a0ea-a21a-44f5-9c95-a05c61fb532e'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid;
  SELECT coalesce(sum(deductible_balance),0) INTO l FROM wallet_ledger
    WHERE user_id = '77b2a0ea-a21a-44f5-9c95-a05c61fb532e'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid
      AND currency = 'points' AND transaction_type = 'earn';
  IF abs(w - l) > 0.01 THEN
    RAISE EXCEPTION 'post-apply invariant user % wallet % lots %', '77b2a0ea-a21a-44f5-9c95-a05c61fb532e', w, l;
  END IF;
END $v$;
COMMIT;
