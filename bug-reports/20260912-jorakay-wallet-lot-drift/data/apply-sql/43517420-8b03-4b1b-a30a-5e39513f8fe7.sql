BEGIN;
UPDATE wallet_ledger SET deductible_balance = 141.0 WHERE id = 'fc6e3d8f-f36e-4c55-acc7-88bea766aa17'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = '43517420-8b03-4b1b-a30a-5e39513f8fe7'::uuid;
DO $v$
DECLARE w numeric; l numeric;
BEGIN
  SELECT points_balance INTO w FROM user_wallet WHERE user_id = '43517420-8b03-4b1b-a30a-5e39513f8fe7'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid;
  SELECT coalesce(sum(deductible_balance),0) INTO l FROM wallet_ledger
    WHERE user_id = '43517420-8b03-4b1b-a30a-5e39513f8fe7'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid
      AND currency = 'points' AND transaction_type = 'earn';
  IF abs(w - l) > 0.01 THEN
    RAISE EXCEPTION 'post-apply invariant user % wallet % lots %', '43517420-8b03-4b1b-a30a-5e39513f8fe7', w, l;
  END IF;
END $v$;
COMMIT;
