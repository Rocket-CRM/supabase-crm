BEGIN;
UPDATE wallet_ledger SET deductible_balance = 0.0 WHERE id = 'e4627ba1-d1dc-482c-89fe-9229d8379d55'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = '2e91acdf-db08-4029-b85e-ae90586ae21e'::uuid;
UPDATE wallet_ledger SET deductible_balance = 1889.0 WHERE id = '0227c013-dac5-4b15-a9a4-aca760696071'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = '2e91acdf-db08-4029-b85e-ae90586ae21e'::uuid;
DO $v$
DECLARE w numeric; l numeric;
BEGIN
  SELECT points_balance INTO w FROM user_wallet WHERE user_id = '2e91acdf-db08-4029-b85e-ae90586ae21e'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid;
  SELECT coalesce(sum(deductible_balance),0) INTO l FROM wallet_ledger
    WHERE user_id = '2e91acdf-db08-4029-b85e-ae90586ae21e'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid
      AND currency = 'points' AND transaction_type = 'earn';
  IF abs(w - l) > 0.01 THEN
    RAISE EXCEPTION 'post-apply invariant user % wallet % lots %', '2e91acdf-db08-4029-b85e-ae90586ae21e', w, l;
  END IF;
END $v$;
COMMIT;
