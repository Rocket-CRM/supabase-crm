BEGIN;
UPDATE wallet_ledger SET deductible_balance = 188.0 WHERE id = '29676bac-e4bc-4fb1-94f2-fbfa29fc930c'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = '41534223-f441-42ad-9ddf-ab7876e8555a'::uuid;
UPDATE wallet_ledger SET deductible_balance = 26.0 WHERE id = '73348721-cfa6-4d1c-9cf2-64920b42ea98'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = '41534223-f441-42ad-9ddf-ab7876e8555a'::uuid;
UPDATE wallet_ledger SET deductible_balance = 57.0 WHERE id = '5760343a-152e-4082-990d-6de2f98836d1'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = '41534223-f441-42ad-9ddf-ab7876e8555a'::uuid;
UPDATE wallet_ledger SET deductible_balance = 40.0 WHERE id = 'f3339076-e6ad-48e2-aa1d-cb2327d86d29'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = '41534223-f441-42ad-9ddf-ab7876e8555a'::uuid;
DO $v$
DECLARE w numeric; l numeric;
BEGIN
  SELECT points_balance INTO w FROM user_wallet WHERE user_id = '41534223-f441-42ad-9ddf-ab7876e8555a'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid;
  SELECT coalesce(sum(deductible_balance),0) INTO l FROM wallet_ledger
    WHERE user_id = '41534223-f441-42ad-9ddf-ab7876e8555a'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid
      AND currency = 'points' AND transaction_type = 'earn';
  IF abs(w - l) > 0.01 THEN
    RAISE EXCEPTION 'post-apply invariant user % wallet % lots %', '41534223-f441-42ad-9ddf-ab7876e8555a', w, l;
  END IF;
END $v$;
COMMIT;
