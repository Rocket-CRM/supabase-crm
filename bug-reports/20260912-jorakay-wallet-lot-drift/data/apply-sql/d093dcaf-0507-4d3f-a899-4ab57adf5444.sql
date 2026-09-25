BEGIN;
UPDATE wallet_ledger SET deductible_balance = 0.0 WHERE id = '478e07f0-81eb-4483-9341-65f70f357479'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = 'd093dcaf-0507-4d3f-a899-4ab57adf5444'::uuid;
UPDATE wallet_ledger SET deductible_balance = 807.0 WHERE id = '14b23cc6-187b-4135-a8be-1d7b8cffc00a'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = 'd093dcaf-0507-4d3f-a899-4ab57adf5444'::uuid;
DO $v$
DECLARE w numeric; l numeric;
BEGIN
  SELECT points_balance INTO w FROM user_wallet WHERE user_id = 'd093dcaf-0507-4d3f-a899-4ab57adf5444'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid;
  SELECT coalesce(sum(deductible_balance),0) INTO l FROM wallet_ledger
    WHERE user_id = 'd093dcaf-0507-4d3f-a899-4ab57adf5444'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid
      AND currency = 'points' AND transaction_type = 'earn';
  IF abs(w - l) > 0.01 THEN
    RAISE EXCEPTION 'post-apply invariant user % wallet % lots %', 'd093dcaf-0507-4d3f-a899-4ab57adf5444', w, l;
  END IF;
END $v$;
COMMIT;
