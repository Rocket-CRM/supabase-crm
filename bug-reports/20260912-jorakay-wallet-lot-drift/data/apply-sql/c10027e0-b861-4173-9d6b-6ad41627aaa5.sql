BEGIN;
UPDATE wallet_ledger SET deductible_balance = 3.0 WHERE id = 'cbc672c2-40eb-49f4-9d33-380629dfbcb2'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = 'c10027e0-b861-4173-9d6b-6ad41627aaa5'::uuid;
UPDATE wallet_ledger SET deductible_balance = 1.0 WHERE id = '62097eab-4759-4a9d-8f91-4be577fb802c'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = 'c10027e0-b861-4173-9d6b-6ad41627aaa5'::uuid;
UPDATE wallet_ledger SET deductible_balance = 2.0 WHERE id = '283f47e9-a01f-4e26-a2ba-ca368f92e3cf'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = 'c10027e0-b861-4173-9d6b-6ad41627aaa5'::uuid;
UPDATE wallet_ledger SET deductible_balance = 6.0 WHERE id = '1e17b263-51c1-4297-9b98-a60a1f792526'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = 'c10027e0-b861-4173-9d6b-6ad41627aaa5'::uuid;
UPDATE wallet_ledger SET deductible_balance = 7.0 WHERE id = '58098f1e-7a0b-440f-b1bb-40d70d63be12'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = 'c10027e0-b861-4173-9d6b-6ad41627aaa5'::uuid;
DO $v$
DECLARE w numeric; l numeric;
BEGIN
  SELECT points_balance INTO w FROM user_wallet WHERE user_id = 'c10027e0-b861-4173-9d6b-6ad41627aaa5'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid;
  SELECT coalesce(sum(deductible_balance),0) INTO l FROM wallet_ledger
    WHERE user_id = 'c10027e0-b861-4173-9d6b-6ad41627aaa5'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid
      AND currency = 'points' AND transaction_type = 'earn';
  IF abs(w - l) > 0.01 THEN
    RAISE EXCEPTION 'post-apply invariant user % wallet % lots %', 'c10027e0-b861-4173-9d6b-6ad41627aaa5', w, l;
  END IF;
END $v$;
COMMIT;
