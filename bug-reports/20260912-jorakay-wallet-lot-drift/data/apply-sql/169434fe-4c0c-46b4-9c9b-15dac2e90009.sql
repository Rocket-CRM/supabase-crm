BEGIN;
UPDATE wallet_ledger SET deductible_balance = 0.0 WHERE id = '03abd4b1-f13b-4a68-933d-6085a8a7abb8'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = '169434fe-4c0c-46b4-9c9b-15dac2e90009'::uuid;
UPDATE wallet_ledger SET deductible_balance = 0.0 WHERE id = 'd1ad82ee-9b85-4ec8-9779-dc1df45aa81d'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = '169434fe-4c0c-46b4-9c9b-15dac2e90009'::uuid;
UPDATE wallet_ledger SET deductible_balance = 0.0 WHERE id = '9a541975-d76d-46a6-84b8-146c06658f92'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = '169434fe-4c0c-46b4-9c9b-15dac2e90009'::uuid;
UPDATE wallet_ledger SET deductible_balance = 0.0 WHERE id = 'c01ac315-4788-4a64-b71a-c78028ba7ece'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = '169434fe-4c0c-46b4-9c9b-15dac2e90009'::uuid;
UPDATE wallet_ledger SET deductible_balance = 0.0 WHERE id = 'cf0ff024-f367-4dd5-8c0c-1df044d0b46e'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = '169434fe-4c0c-46b4-9c9b-15dac2e90009'::uuid;
UPDATE wallet_ledger SET deductible_balance = 0.0 WHERE id = 'afceb66a-c8cd-4c52-bd31-d37c9327ce5f'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = '169434fe-4c0c-46b4-9c9b-15dac2e90009'::uuid;
UPDATE wallet_ledger SET deductible_balance = 0.0 WHERE id = 'dd701dd9-7895-4f79-9c67-878daa7dbcec'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = '169434fe-4c0c-46b4-9c9b-15dac2e90009'::uuid;
UPDATE wallet_ledger SET deductible_balance = 0.0 WHERE id = '309bfc09-cda2-4525-a04e-fed6bff18a1f'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = '169434fe-4c0c-46b4-9c9b-15dac2e90009'::uuid;
UPDATE wallet_ledger SET deductible_balance = 0.0 WHERE id = '678907c6-1871-46bd-8aa2-99068a6a69c4'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = '169434fe-4c0c-46b4-9c9b-15dac2e90009'::uuid;
UPDATE wallet_ledger SET deductible_balance = 0.0 WHERE id = 'b891d448-374b-481e-8c1e-40eea407fe68'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = '169434fe-4c0c-46b4-9c9b-15dac2e90009'::uuid;
UPDATE wallet_ledger SET deductible_balance = 0.0 WHERE id = 'd462085a-09de-4d6e-8e96-304ca6763f7e'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = '169434fe-4c0c-46b4-9c9b-15dac2e90009'::uuid;
UPDATE wallet_ledger SET deductible_balance = 0.0 WHERE id = 'b5bc1be7-a1e5-422c-adea-7b796a674095'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = '169434fe-4c0c-46b4-9c9b-15dac2e90009'::uuid;
UPDATE wallet_ledger SET deductible_balance = 0.0 WHERE id = '9a18a87a-85c7-451c-a968-8e57ef96ead6'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = '169434fe-4c0c-46b4-9c9b-15dac2e90009'::uuid;
UPDATE wallet_ledger SET deductible_balance = 483.0 WHERE id = 'e2394c41-f6b7-4787-a3a9-0d3c2a8ceee2'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = '169434fe-4c0c-46b4-9c9b-15dac2e90009'::uuid;
UPDATE user_wallet SET points_balance = 36954.0 WHERE user_id = '169434fe-4c0c-46b4-9c9b-15dac2e90009'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid;
DO $v$
DECLARE w numeric; l numeric;
BEGIN
  SELECT points_balance INTO w FROM user_wallet WHERE user_id = '169434fe-4c0c-46b4-9c9b-15dac2e90009'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid;
  SELECT coalesce(sum(deductible_balance),0) INTO l FROM wallet_ledger
    WHERE user_id = '169434fe-4c0c-46b4-9c9b-15dac2e90009'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid
      AND currency = 'points' AND transaction_type = 'earn';
  IF abs(w - l) > 0.01 THEN
    RAISE EXCEPTION 'post-apply invariant user % wallet % lots %', '169434fe-4c0c-46b4-9c9b-15dac2e90009', w, l;
  END IF;
END $v$;
COMMIT;
