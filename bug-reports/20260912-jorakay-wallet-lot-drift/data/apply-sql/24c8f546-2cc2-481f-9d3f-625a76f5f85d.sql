BEGIN;
UPDATE wallet_ledger SET deductible_balance = 2460.0 WHERE id = '6b22dc38-c5e8-4770-b138-b33ee3c9b21e'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = '24c8f546-2cc2-481f-9d3f-625a76f5f85d'::uuid;
UPDATE wallet_ledger SET deductible_balance = 54.0 WHERE id = '923925bb-5d34-4bf6-aa2a-cfc2bade17fb'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = '24c8f546-2cc2-481f-9d3f-625a76f5f85d'::uuid;
DO $v$
DECLARE w numeric; l numeric;
BEGIN
  SELECT points_balance INTO w FROM user_wallet WHERE user_id = '24c8f546-2cc2-481f-9d3f-625a76f5f85d'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid;
  SELECT coalesce(sum(deductible_balance),0) INTO l FROM wallet_ledger
    WHERE user_id = '24c8f546-2cc2-481f-9d3f-625a76f5f85d'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid
      AND currency = 'points' AND transaction_type = 'earn';
  IF abs(w - l) > 0.01 THEN
    RAISE EXCEPTION 'post-apply invariant user % wallet % lots %', '24c8f546-2cc2-481f-9d3f-625a76f5f85d', w, l;
  END IF;
END $v$;
COMMIT;
