BEGIN;
UPDATE wallet_ledger SET deductible_balance = 0.0 WHERE id = '804c84f2-1e90-47a9-b954-faa27c01a1b7'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = '94e8def6-2b61-4229-afc5-bd2dc289280f'::uuid;
UPDATE wallet_ledger SET deductible_balance = 34.0 WHERE id = 'def0ac64-a4c8-4ec2-aaee-51b5763738fd'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = '94e8def6-2b61-4229-afc5-bd2dc289280f'::uuid;
DO $v$
DECLARE w numeric; l numeric;
BEGIN
  SELECT points_balance INTO w FROM user_wallet WHERE user_id = '94e8def6-2b61-4229-afc5-bd2dc289280f'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid;
  SELECT coalesce(sum(deductible_balance),0) INTO l FROM wallet_ledger
    WHERE user_id = '94e8def6-2b61-4229-afc5-bd2dc289280f'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid
      AND currency = 'points' AND transaction_type = 'earn';
  IF abs(w - l) > 0.01 THEN
    RAISE EXCEPTION 'post-apply invariant user % wallet % lots %', '94e8def6-2b61-4229-afc5-bd2dc289280f', w, l;
  END IF;
END $v$;
COMMIT;
