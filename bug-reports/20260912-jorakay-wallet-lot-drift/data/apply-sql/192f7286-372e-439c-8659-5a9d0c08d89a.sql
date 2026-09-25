BEGIN;
UPDATE wallet_ledger SET deductible_balance = 0.0 WHERE id = '45421af4-337b-4a6d-ae1b-cf442626f968'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = '192f7286-372e-439c-8659-5a9d0c08d89a'::uuid;
UPDATE wallet_ledger SET deductible_balance = 0.0 WHERE id = 'acfc85c4-d5ec-4312-a30f-569c376b9ade'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = '192f7286-372e-439c-8659-5a9d0c08d89a'::uuid;
UPDATE wallet_ledger SET deductible_balance = 0.0 WHERE id = 'e89606d0-fe5f-403e-8c62-550ba546c520'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = '192f7286-372e-439c-8659-5a9d0c08d89a'::uuid;
UPDATE wallet_ledger SET deductible_balance = 0.0 WHERE id = '629b69c9-f835-4707-9bf9-647393a98654'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = '192f7286-372e-439c-8659-5a9d0c08d89a'::uuid;
UPDATE wallet_ledger SET deductible_balance = 0.0 WHERE id = 'dd97a121-00ee-40d1-8648-9975e3d6508c'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = '192f7286-372e-439c-8659-5a9d0c08d89a'::uuid;
UPDATE wallet_ledger SET deductible_balance = 0.0 WHERE id = '74a5be13-3fd1-443c-a5cc-17f2af04ec59'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = '192f7286-372e-439c-8659-5a9d0c08d89a'::uuid;
UPDATE wallet_ledger SET deductible_balance = 0.0 WHERE id = 'dfe251c7-cce0-4f8d-805e-ecaa379754e2'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = '192f7286-372e-439c-8659-5a9d0c08d89a'::uuid;
UPDATE wallet_ledger SET deductible_balance = 19.0 WHERE id = 'ba58ee98-cb8b-4c84-9ac7-880b29754a57'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = '192f7286-372e-439c-8659-5a9d0c08d89a'::uuid;
UPDATE wallet_ledger SET deductible_balance = 244.0 WHERE id = '6cd78084-dd83-4bdf-a642-8bf1fd39ca2a'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = '192f7286-372e-439c-8659-5a9d0c08d89a'::uuid;
DO $v$
DECLARE w numeric; l numeric;
BEGIN
  SELECT points_balance INTO w FROM user_wallet WHERE user_id = '192f7286-372e-439c-8659-5a9d0c08d89a'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid;
  SELECT coalesce(sum(deductible_balance),0) INTO l FROM wallet_ledger
    WHERE user_id = '192f7286-372e-439c-8659-5a9d0c08d89a'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid
      AND currency = 'points' AND transaction_type = 'earn';
  IF abs(w - l) > 0.01 THEN
    RAISE EXCEPTION 'post-apply invariant user % wallet % lots %', '192f7286-372e-439c-8659-5a9d0c08d89a', w, l;
  END IF;
END $v$;
COMMIT;
