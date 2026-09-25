BEGIN;
UPDATE wallet_ledger SET deductible_balance = 55.0 WHERE id = 'e2efee2f-572c-44f8-9bf1-62ef3db43777'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = '4506ca7e-dc61-4d4b-b0ae-a11cea60aa62'::uuid;
UPDATE wallet_ledger SET deductible_balance = 75.0 WHERE id = '48c15a99-027a-4742-85bf-d2c96a6ca6af'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = '4506ca7e-dc61-4d4b-b0ae-a11cea60aa62'::uuid;
UPDATE wallet_ledger SET deductible_balance = 9.0 WHERE id = '397349d0-373c-40dc-8c6b-22c52bef0010'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = '4506ca7e-dc61-4d4b-b0ae-a11cea60aa62'::uuid;
UPDATE wallet_ledger SET deductible_balance = 76.0 WHERE id = 'ff718739-04b8-4226-acb9-ed54db279b3e'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = '4506ca7e-dc61-4d4b-b0ae-a11cea60aa62'::uuid;
UPDATE wallet_ledger SET deductible_balance = 5.0 WHERE id = 'ebe23c4c-ab14-4a87-9ce4-f4828cc92777'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = '4506ca7e-dc61-4d4b-b0ae-a11cea60aa62'::uuid;
DO $v$
DECLARE w numeric; l numeric;
BEGIN
  SELECT points_balance INTO w FROM user_wallet WHERE user_id = '4506ca7e-dc61-4d4b-b0ae-a11cea60aa62'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid;
  SELECT coalesce(sum(deductible_balance),0) INTO l FROM wallet_ledger
    WHERE user_id = '4506ca7e-dc61-4d4b-b0ae-a11cea60aa62'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid
      AND currency = 'points' AND transaction_type = 'earn';
  IF abs(w - l) > 0.01 THEN
    RAISE EXCEPTION 'post-apply invariant user % wallet % lots %', '4506ca7e-dc61-4d4b-b0ae-a11cea60aa62', w, l;
  END IF;
END $v$;
COMMIT;
