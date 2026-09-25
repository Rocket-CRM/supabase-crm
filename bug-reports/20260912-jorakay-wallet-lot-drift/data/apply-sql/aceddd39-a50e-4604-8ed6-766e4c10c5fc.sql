BEGIN;
UPDATE wallet_ledger SET deductible_balance = 0.0 WHERE id = 'c8a5e4ef-035c-4944-8856-a77642d03bd8'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = 'aceddd39-a50e-4604-8ed6-766e4c10c5fc'::uuid;
UPDATE wallet_ledger SET deductible_balance = 996.0 WHERE id = 'b1ee5a1b-d0de-4dde-afa1-ee0ae31c1e9d'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = 'aceddd39-a50e-4604-8ed6-766e4c10c5fc'::uuid;
DO $v$
DECLARE w numeric; l numeric;
BEGIN
  SELECT points_balance INTO w FROM user_wallet WHERE user_id = 'aceddd39-a50e-4604-8ed6-766e4c10c5fc'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid;
  SELECT coalesce(sum(deductible_balance),0) INTO l FROM wallet_ledger
    WHERE user_id = 'aceddd39-a50e-4604-8ed6-766e4c10c5fc'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid
      AND currency = 'points' AND transaction_type = 'earn';
  IF abs(w - l) > 0.01 THEN
    RAISE EXCEPTION 'post-apply invariant user % wallet % lots %', 'aceddd39-a50e-4604-8ed6-766e4c10c5fc', w, l;
  END IF;
END $v$;
COMMIT;
