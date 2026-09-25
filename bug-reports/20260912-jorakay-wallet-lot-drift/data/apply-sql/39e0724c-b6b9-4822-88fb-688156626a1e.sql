BEGIN;
UPDATE wallet_ledger SET deductible_balance = 0.0 WHERE id = 'f714feef-66c0-41a7-8070-fdf05ba04883'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = '39e0724c-b6b9-4822-88fb-688156626a1e'::uuid;
UPDATE wallet_ledger SET deductible_balance = 0.0 WHERE id = '639c561b-c70c-49ee-b4e4-d42f64ad4df0'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = '39e0724c-b6b9-4822-88fb-688156626a1e'::uuid;
UPDATE wallet_ledger SET deductible_balance = 0.0 WHERE id = 'e87d75dc-4ea4-4bf5-828a-cc80fd642436'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = '39e0724c-b6b9-4822-88fb-688156626a1e'::uuid;
UPDATE wallet_ledger SET deductible_balance = 0.0 WHERE id = 'cd996414-66c6-40d1-a443-15b8970c6fbf'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = '39e0724c-b6b9-4822-88fb-688156626a1e'::uuid;
UPDATE wallet_ledger SET deductible_balance = 0.0 WHERE id = '9a9f9898-e131-4c59-99cd-dcad99765273'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = '39e0724c-b6b9-4822-88fb-688156626a1e'::uuid;
UPDATE wallet_ledger SET deductible_balance = 0.0 WHERE id = 'ff24aac0-db4a-4248-91c7-ac6fd4f9eb15'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = '39e0724c-b6b9-4822-88fb-688156626a1e'::uuid;
UPDATE wallet_ledger SET deductible_balance = 0.0 WHERE id = '1118445d-3f8c-4be1-bc45-8373c6129034'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = '39e0724c-b6b9-4822-88fb-688156626a1e'::uuid;
UPDATE wallet_ledger SET deductible_balance = 0.0 WHERE id = 'aafb09fb-d485-4e51-83b3-99e969b2c848'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = '39e0724c-b6b9-4822-88fb-688156626a1e'::uuid;
UPDATE wallet_ledger SET deductible_balance = 0.0 WHERE id = 'ea9ae894-926c-45dd-bb52-187679813cbf'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = '39e0724c-b6b9-4822-88fb-688156626a1e'::uuid;
DO $v$
DECLARE w numeric; l numeric;
BEGIN
  SELECT points_balance INTO w FROM user_wallet WHERE user_id = '39e0724c-b6b9-4822-88fb-688156626a1e'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid;
  SELECT coalesce(sum(deductible_balance),0) INTO l FROM wallet_ledger
    WHERE user_id = '39e0724c-b6b9-4822-88fb-688156626a1e'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid
      AND currency = 'points' AND transaction_type = 'earn';
  IF abs(w - l) > 0.01 THEN
    RAISE EXCEPTION 'post-apply invariant user % wallet % lots %', '39e0724c-b6b9-4822-88fb-688156626a1e', w, l;
  END IF;
END $v$;
COMMIT;
