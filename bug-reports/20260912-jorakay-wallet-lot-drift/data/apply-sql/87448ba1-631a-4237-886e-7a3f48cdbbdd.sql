BEGIN;
UPDATE wallet_ledger SET deductible_balance = 0.0 WHERE id = '5dadb3cd-0b77-42c4-b583-4e085695e518'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = '87448ba1-631a-4237-886e-7a3f48cdbbdd'::uuid;
UPDATE wallet_ledger SET deductible_balance = 0.0 WHERE id = '4b13d5b9-4b74-41d0-86be-c0fc32be3d7d'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = '87448ba1-631a-4237-886e-7a3f48cdbbdd'::uuid;
UPDATE wallet_ledger SET deductible_balance = 37.0 WHERE id = '6ca93b35-d99b-4764-b30c-9effb448c0f7'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = '87448ba1-631a-4237-886e-7a3f48cdbbdd'::uuid;
DO $v$
DECLARE w numeric; l numeric;
BEGIN
  SELECT points_balance INTO w FROM user_wallet WHERE user_id = '87448ba1-631a-4237-886e-7a3f48cdbbdd'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid;
  SELECT coalesce(sum(deductible_balance),0) INTO l FROM wallet_ledger
    WHERE user_id = '87448ba1-631a-4237-886e-7a3f48cdbbdd'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid
      AND currency = 'points' AND transaction_type = 'earn';
  IF abs(w - l) > 0.01 THEN
    RAISE EXCEPTION 'post-apply invariant user % wallet % lots %', '87448ba1-631a-4237-886e-7a3f48cdbbdd', w, l;
  END IF;
END $v$;
COMMIT;
