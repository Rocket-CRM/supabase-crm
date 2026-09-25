BEGIN;
UPDATE wallet_ledger SET deductible_balance = 0.0 WHERE id = 'd2b2f801-c32b-4d2c-b9eb-d1bbf4b71e51'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = '465dae9a-01fa-49ca-b3f1-957deb899d5d'::uuid;
UPDATE wallet_ledger SET deductible_balance = 0.0 WHERE id = '62680a55-8fe2-4c18-8365-ed74029d8189'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = '465dae9a-01fa-49ca-b3f1-957deb899d5d'::uuid;
UPDATE wallet_ledger SET deductible_balance = 0.0 WHERE id = '4b69365e-2922-46ef-b0ad-167ab14d9a8b'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = '465dae9a-01fa-49ca-b3f1-957deb899d5d'::uuid;
UPDATE wallet_ledger SET deductible_balance = 0.0 WHERE id = '8bf5dc53-3bb4-4a23-a2f0-13ff4dd8aded'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = '465dae9a-01fa-49ca-b3f1-957deb899d5d'::uuid;
UPDATE wallet_ledger SET deductible_balance = 0.0 WHERE id = 'b9c9214e-2259-4c5e-9688-b512b7efd988'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = '465dae9a-01fa-49ca-b3f1-957deb899d5d'::uuid;
UPDATE wallet_ledger SET deductible_balance = 0.0 WHERE id = '0e919a15-f9da-4b44-84f3-6adeaeb13e7d'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = '465dae9a-01fa-49ca-b3f1-957deb899d5d'::uuid;
UPDATE wallet_ledger SET deductible_balance = 0.0 WHERE id = 'c91d5dbf-3956-4fa6-8477-f9f86573cd9d'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = '465dae9a-01fa-49ca-b3f1-957deb899d5d'::uuid;
UPDATE wallet_ledger SET deductible_balance = 0.0 WHERE id = 'e7af1215-a1e7-41d4-ab82-36ddb4847b8d'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = '465dae9a-01fa-49ca-b3f1-957deb899d5d'::uuid;
UPDATE wallet_ledger SET deductible_balance = 0.0 WHERE id = '04d0eeaa-a664-4e93-ae03-78521783f813'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = '465dae9a-01fa-49ca-b3f1-957deb899d5d'::uuid;
UPDATE wallet_ledger SET deductible_balance = 0.0 WHERE id = '031828ff-7dbd-4595-bac5-7d763bd42d40'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = '465dae9a-01fa-49ca-b3f1-957deb899d5d'::uuid;
UPDATE wallet_ledger SET deductible_balance = 0.0 WHERE id = '29f102dc-dcf2-4911-b776-943f4db26209'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = '465dae9a-01fa-49ca-b3f1-957deb899d5d'::uuid;
UPDATE wallet_ledger SET deductible_balance = 0.0 WHERE id = 'd01b7a1b-7a6c-482c-b6b4-e31308c98311'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = '465dae9a-01fa-49ca-b3f1-957deb899d5d'::uuid;
UPDATE wallet_ledger SET deductible_balance = 0.0 WHERE id = '49bddcdd-0a1e-49b0-91ee-22051517c042'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = '465dae9a-01fa-49ca-b3f1-957deb899d5d'::uuid;
UPDATE wallet_ledger SET deductible_balance = 0.0 WHERE id = '315cad1e-d516-4e23-9be9-ed4121af6ec0'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = '465dae9a-01fa-49ca-b3f1-957deb899d5d'::uuid;
UPDATE wallet_ledger SET deductible_balance = 0.0 WHERE id = '5a695ef2-1f5b-4cdf-83ff-d33f6bfa97bb'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = '465dae9a-01fa-49ca-b3f1-957deb899d5d'::uuid;
UPDATE wallet_ledger SET deductible_balance = 23101.0 WHERE id = '7f6af194-f575-44ec-96e6-129943e6f185'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = '465dae9a-01fa-49ca-b3f1-957deb899d5d'::uuid;
DO $v$
DECLARE w numeric; l numeric;
BEGIN
  SELECT points_balance INTO w FROM user_wallet WHERE user_id = '465dae9a-01fa-49ca-b3f1-957deb899d5d'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid;
  SELECT coalesce(sum(deductible_balance),0) INTO l FROM wallet_ledger
    WHERE user_id = '465dae9a-01fa-49ca-b3f1-957deb899d5d'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid
      AND currency = 'points' AND transaction_type = 'earn';
  IF abs(w - l) > 0.01 THEN
    RAISE EXCEPTION 'post-apply invariant user % wallet % lots %', '465dae9a-01fa-49ca-b3f1-957deb899d5d', w, l;
  END IF;
END $v$;
COMMIT;
