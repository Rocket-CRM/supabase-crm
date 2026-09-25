BEGIN;
UPDATE wallet_ledger SET deductible_balance = 450.0 WHERE id = 'b9a2eaf3-5f51-4e41-a523-59d76a8848c5'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = '8e9f72fb-b005-492d-8f90-dc9b81aca7bf'::uuid;
UPDATE wallet_ledger SET deductible_balance = 308.0 WHERE id = 'ee0a1997-5ea2-4f17-b82a-b7bc75e04f6d'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = '8e9f72fb-b005-492d-8f90-dc9b81aca7bf'::uuid;
UPDATE wallet_ledger SET deductible_balance = 902.0 WHERE id = '8287f4cb-3c03-4067-b675-adc563fa3064'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = '8e9f72fb-b005-492d-8f90-dc9b81aca7bf'::uuid;
UPDATE wallet_ledger SET deductible_balance = 116.0 WHERE id = '114d2867-10d0-4863-acce-cd3bc5d643da'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = '8e9f72fb-b005-492d-8f90-dc9b81aca7bf'::uuid;
UPDATE wallet_ledger SET deductible_balance = 206.0 WHERE id = '94b4d4ba-e721-4c78-a405-50c36b22de90'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = '8e9f72fb-b005-492d-8f90-dc9b81aca7bf'::uuid;
UPDATE wallet_ledger SET deductible_balance = 434.0 WHERE id = 'a31de377-d8ef-4cb4-a3c6-be144802a0fb'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = '8e9f72fb-b005-492d-8f90-dc9b81aca7bf'::uuid;
DO $v$
DECLARE w numeric; l numeric;
BEGIN
  SELECT points_balance INTO w FROM user_wallet WHERE user_id = '8e9f72fb-b005-492d-8f90-dc9b81aca7bf'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid;
  SELECT coalesce(sum(deductible_balance),0) INTO l FROM wallet_ledger
    WHERE user_id = '8e9f72fb-b005-492d-8f90-dc9b81aca7bf'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid
      AND currency = 'points' AND transaction_type = 'earn';
  IF abs(w - l) > 0.01 THEN
    RAISE EXCEPTION 'post-apply invariant user % wallet % lots %', '8e9f72fb-b005-492d-8f90-dc9b81aca7bf', w, l;
  END IF;
END $v$;
COMMIT;
