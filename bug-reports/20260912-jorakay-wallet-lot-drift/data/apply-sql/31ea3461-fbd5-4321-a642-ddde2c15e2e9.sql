BEGIN;
UPDATE wallet_ledger SET deductible_balance = 0.0 WHERE id = '71a80b5d-d614-40dd-a909-ea76a0aa45cd'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = '31ea3461-fbd5-4321-a642-ddde2c15e2e9'::uuid;
UPDATE wallet_ledger SET deductible_balance = 0.0 WHERE id = '39ce86af-5f44-4904-aa9a-97003418bb28'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = '31ea3461-fbd5-4321-a642-ddde2c15e2e9'::uuid;
UPDATE wallet_ledger SET deductible_balance = 0.0 WHERE id = '9d622025-2f4b-4659-a2fa-d5860fd58c4f'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = '31ea3461-fbd5-4321-a642-ddde2c15e2e9'::uuid;
UPDATE wallet_ledger SET deductible_balance = 0.0 WHERE id = 'e527ea57-1a0d-49db-b487-039b9a2cf7de'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = '31ea3461-fbd5-4321-a642-ddde2c15e2e9'::uuid;
UPDATE wallet_ledger SET deductible_balance = 65.0 WHERE id = 'ee35a692-dcae-4c5d-84bf-61e2f2e2adda'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = '31ea3461-fbd5-4321-a642-ddde2c15e2e9'::uuid;
DO $v$
DECLARE w numeric; l numeric;
BEGIN
  SELECT points_balance INTO w FROM user_wallet WHERE user_id = '31ea3461-fbd5-4321-a642-ddde2c15e2e9'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid;
  SELECT coalesce(sum(deductible_balance),0) INTO l FROM wallet_ledger
    WHERE user_id = '31ea3461-fbd5-4321-a642-ddde2c15e2e9'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid
      AND currency = 'points' AND transaction_type = 'earn';
  IF abs(w - l) > 0.01 THEN
    RAISE EXCEPTION 'post-apply invariant user % wallet % lots %', '31ea3461-fbd5-4321-a642-ddde2c15e2e9', w, l;
  END IF;
END $v$;
COMMIT;
