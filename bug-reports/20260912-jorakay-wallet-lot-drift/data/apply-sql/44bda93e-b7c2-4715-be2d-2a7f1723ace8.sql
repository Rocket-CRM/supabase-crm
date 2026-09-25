BEGIN;
UPDATE wallet_ledger SET deductible_balance = 0.0 WHERE id = 'b8544f6e-8485-4458-950c-a5e6dc1b9b2f'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = '44bda93e-b7c2-4715-be2d-2a7f1723ace8'::uuid;
UPDATE wallet_ledger SET deductible_balance = 2.0 WHERE id = 'fdc4bff6-de41-415b-baa5-002da23d1e52'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = '44bda93e-b7c2-4715-be2d-2a7f1723ace8'::uuid;
UPDATE wallet_ledger SET deductible_balance = 14.0 WHERE id = '25bb2f89-2375-4f34-89ad-b9571838cf83'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = '44bda93e-b7c2-4715-be2d-2a7f1723ace8'::uuid;
DO $v$
DECLARE w numeric; l numeric;
BEGIN
  SELECT points_balance INTO w FROM user_wallet WHERE user_id = '44bda93e-b7c2-4715-be2d-2a7f1723ace8'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid;
  SELECT coalesce(sum(deductible_balance),0) INTO l FROM wallet_ledger
    WHERE user_id = '44bda93e-b7c2-4715-be2d-2a7f1723ace8'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid
      AND currency = 'points' AND transaction_type = 'earn';
  IF abs(w - l) > 0.01 THEN
    RAISE EXCEPTION 'post-apply invariant user % wallet % lots %', '44bda93e-b7c2-4715-be2d-2a7f1723ace8', w, l;
  END IF;
END $v$;
COMMIT;
