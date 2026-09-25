BEGIN;
UPDATE wallet_ledger SET deductible_balance = 2186.0 WHERE id = '6f580c03-e0b5-49f8-b62e-e4e1efa87633'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = 'e667c9d3-1dbe-4173-b075-42fca35106eb'::uuid;
UPDATE wallet_ledger SET deductible_balance = 133.0 WHERE id = '53e6df5c-04b4-4f36-a951-bdf035d0732f'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = 'e667c9d3-1dbe-4173-b075-42fca35106eb'::uuid;
DO $v$
DECLARE w numeric; l numeric;
BEGIN
  SELECT points_balance INTO w FROM user_wallet WHERE user_id = 'e667c9d3-1dbe-4173-b075-42fca35106eb'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid;
  SELECT coalesce(sum(deductible_balance),0) INTO l FROM wallet_ledger
    WHERE user_id = 'e667c9d3-1dbe-4173-b075-42fca35106eb'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid
      AND currency = 'points' AND transaction_type = 'earn';
  IF abs(w - l) > 0.01 THEN
    RAISE EXCEPTION 'post-apply invariant user % wallet % lots %', 'e667c9d3-1dbe-4173-b075-42fca35106eb', w, l;
  END IF;
END $v$;
COMMIT;
