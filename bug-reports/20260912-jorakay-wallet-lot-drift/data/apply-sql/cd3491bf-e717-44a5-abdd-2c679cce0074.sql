BEGIN;
UPDATE wallet_ledger SET deductible_balance = 142.0 WHERE id = '8f640b6b-5a45-448a-afc9-6ce27ac56aa0'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = 'cd3491bf-e717-44a5-abdd-2c679cce0074'::uuid;
UPDATE wallet_ledger SET deductible_balance = 237.0 WHERE id = '7a0f62ea-dbf1-4266-a54f-9b0ed9806d34'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = 'cd3491bf-e717-44a5-abdd-2c679cce0074'::uuid;
DO $v$
DECLARE w numeric; l numeric;
BEGIN
  SELECT points_balance INTO w FROM user_wallet WHERE user_id = 'cd3491bf-e717-44a5-abdd-2c679cce0074'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid;
  SELECT coalesce(sum(deductible_balance),0) INTO l FROM wallet_ledger
    WHERE user_id = 'cd3491bf-e717-44a5-abdd-2c679cce0074'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid
      AND currency = 'points' AND transaction_type = 'earn';
  IF abs(w - l) > 0.01 THEN
    RAISE EXCEPTION 'post-apply invariant user % wallet % lots %', 'cd3491bf-e717-44a5-abdd-2c679cce0074', w, l;
  END IF;
END $v$;
COMMIT;
