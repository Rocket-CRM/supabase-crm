BEGIN;
UPDATE wallet_ledger SET deductible_balance = 33.0 WHERE id = '07245c9f-b464-4fc3-9715-c08d1207535c'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = '77b2a0ea-a21a-44f5-9c95-a05c61fb532e'::uuid;
DO $v$
DECLARE w numeric; l numeric;
BEGIN
  SELECT points_balance INTO w FROM user_wallet WHERE user_id = '77b2a0ea-a21a-44f5-9c95-a05c61fb532e'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid;
  SELECT coalesce(sum(deductible_balance),0) INTO l FROM wallet_ledger
    WHERE user_id = '77b2a0ea-a21a-44f5-9c95-a05c61fb532e'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid
      AND currency = 'points' AND transaction_type = 'earn';
  IF abs(w - l) > 0.01 THEN
    RAISE EXCEPTION 'post-apply invariant user % wallet % lots %', '77b2a0ea-a21a-44f5-9c95-a05c61fb532e', w, l;
  END IF;
END $v$;
COMMIT;
BEGIN;
UPDATE wallet_ledger SET deductible_balance = 12683.0 WHERE id = 'd8f1c10a-7cc6-4b29-bb91-f33f9d9171d7'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = '7e16a591-c38f-4c79-904a-bc99e2b1eab1'::uuid;
DO $v$
DECLARE w numeric; l numeric;
BEGIN
  SELECT points_balance INTO w FROM user_wallet WHERE user_id = '7e16a591-c38f-4c79-904a-bc99e2b1eab1'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid;
  SELECT coalesce(sum(deductible_balance),0) INTO l FROM wallet_ledger
    WHERE user_id = '7e16a591-c38f-4c79-904a-bc99e2b1eab1'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid
      AND currency = 'points' AND transaction_type = 'earn';
  IF abs(w - l) > 0.01 THEN
    RAISE EXCEPTION 'post-apply invariant user % wallet % lots %', '7e16a591-c38f-4c79-904a-bc99e2b1eab1', w, l;
  END IF;
END $v$;
COMMIT;
BEGIN;
UPDATE wallet_ledger SET deductible_balance = 89.0 WHERE id = '207edc4d-91b3-47cf-8d04-02b1587875d6'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = '80e712c9-ef6e-4d0e-a2c5-ceed05184d8b'::uuid;
UPDATE wallet_ledger SET deductible_balance = 118.0 WHERE id = '0d173bf2-701e-4eb5-9cb4-36a2495aeae3'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = '80e712c9-ef6e-4d0e-a2c5-ceed05184d8b'::uuid;
UPDATE wallet_ledger SET deductible_balance = 2.0 WHERE id = 'dda75392-88c3-4b56-8430-802375366699'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = '80e712c9-ef6e-4d0e-a2c5-ceed05184d8b'::uuid;
UPDATE wallet_ledger SET deductible_balance = 5.0 WHERE id = 'dbc8f0ec-86eb-4ed1-87e1-2dd52ff4bbe1'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = '80e712c9-ef6e-4d0e-a2c5-ceed05184d8b'::uuid;
UPDATE wallet_ledger SET deductible_balance = 4.0 WHERE id = 'e7e0bd73-5138-4445-b6cb-57bc970e40c1'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = '80e712c9-ef6e-4d0e-a2c5-ceed05184d8b'::uuid;
UPDATE wallet_ledger SET deductible_balance = 3.0 WHERE id = '96da8e32-8bd1-4938-be93-549088f0cfae'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = '80e712c9-ef6e-4d0e-a2c5-ceed05184d8b'::uuid;
UPDATE wallet_ledger SET deductible_balance = 4.0 WHERE id = 'c065faae-c6b8-417b-b2e2-d42cec1280de'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = '80e712c9-ef6e-4d0e-a2c5-ceed05184d8b'::uuid;
UPDATE wallet_ledger SET deductible_balance = 28.0 WHERE id = '850cf58a-1d80-48ba-8ca5-a6feb65c11c9'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = '80e712c9-ef6e-4d0e-a2c5-ceed05184d8b'::uuid;
UPDATE wallet_ledger SET deductible_balance = 7.0 WHERE id = 'cd14e61e-e757-412c-8859-be7a81014138'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = '80e712c9-ef6e-4d0e-a2c5-ceed05184d8b'::uuid;
UPDATE wallet_ledger SET deductible_balance = 6.0 WHERE id = '7a66d93b-4375-44eb-bff8-a38e38d6b097'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = '80e712c9-ef6e-4d0e-a2c5-ceed05184d8b'::uuid;
UPDATE wallet_ledger SET deductible_balance = 86.0 WHERE id = '4ba139e1-a065-4ee2-9218-1e352c56feb3'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = '80e712c9-ef6e-4d0e-a2c5-ceed05184d8b'::uuid;
UPDATE wallet_ledger SET deductible_balance = 7.0 WHERE id = '4c80717d-15e1-410c-9d2f-98a2e6a70c1b'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = '80e712c9-ef6e-4d0e-a2c5-ceed05184d8b'::uuid;
UPDATE wallet_ledger SET deductible_balance = 9.0 WHERE id = '5d97b3f2-b299-482c-bdfd-a4bbcd0bcda1'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = '80e712c9-ef6e-4d0e-a2c5-ceed05184d8b'::uuid;
UPDATE wallet_ledger SET deductible_balance = 13.0 WHERE id = '4f24a337-0d9e-4889-827d-5a1dfc8be90d'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = '80e712c9-ef6e-4d0e-a2c5-ceed05184d8b'::uuid;
UPDATE wallet_ledger SET deductible_balance = 9.0 WHERE id = '6f78c6d5-9f4e-4f81-b8b0-4ed3651f605b'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = '80e712c9-ef6e-4d0e-a2c5-ceed05184d8b'::uuid;
UPDATE wallet_ledger SET deductible_balance = 11.0 WHERE id = '098a1b94-2f84-4a7d-a546-6a37962cf650'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = '80e712c9-ef6e-4d0e-a2c5-ceed05184d8b'::uuid;
UPDATE wallet_ledger SET deductible_balance = 6.0 WHERE id = '252c6eae-9525-41f4-b897-ac3bc0a44f55'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = '80e712c9-ef6e-4d0e-a2c5-ceed05184d8b'::uuid;
UPDATE wallet_ledger SET deductible_balance = 3.0 WHERE id = '014f027e-349a-4a80-ab94-53d72b9dfad6'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = '80e712c9-ef6e-4d0e-a2c5-ceed05184d8b'::uuid;
UPDATE wallet_ledger SET deductible_balance = 13.0 WHERE id = '39581a49-168f-4bcb-80ed-c7eb75cf944b'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = '80e712c9-ef6e-4d0e-a2c5-ceed05184d8b'::uuid;
UPDATE wallet_ledger SET deductible_balance = 51.0 WHERE id = '9ffbaa1a-424a-4cf5-9457-91ea8cb7b0a2'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = '80e712c9-ef6e-4d0e-a2c5-ceed05184d8b'::uuid;
UPDATE wallet_ledger SET deductible_balance = 9.0 WHERE id = 'cd51883a-d31e-49dd-a2ef-eddf12a3c7c9'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = '80e712c9-ef6e-4d0e-a2c5-ceed05184d8b'::uuid;
UPDATE wallet_ledger SET deductible_balance = 2.0 WHERE id = '5c236f63-7c9d-4f07-90a6-039df39a00b8'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = '80e712c9-ef6e-4d0e-a2c5-ceed05184d8b'::uuid;
UPDATE wallet_ledger SET deductible_balance = 47.0 WHERE id = '841eeb3d-6e67-44bb-8416-31e13710eb3e'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = '80e712c9-ef6e-4d0e-a2c5-ceed05184d8b'::uuid;
UPDATE wallet_ledger SET deductible_balance = 15.0 WHERE id = 'a8718d45-8ea9-4543-bbc1-4ca7ee38bf0c'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = '80e712c9-ef6e-4d0e-a2c5-ceed05184d8b'::uuid;
UPDATE wallet_ledger SET deductible_balance = 8.0 WHERE id = '1578be57-165a-4889-afa0-00e8e85a7c01'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = '80e712c9-ef6e-4d0e-a2c5-ceed05184d8b'::uuid;
UPDATE wallet_ledger SET deductible_balance = 29.0 WHERE id = '92fd1b01-b2ef-402e-a650-285ed7f45feb'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = '80e712c9-ef6e-4d0e-a2c5-ceed05184d8b'::uuid;
UPDATE wallet_ledger SET deductible_balance = 13.0 WHERE id = 'b70df773-b872-44f1-97b7-d86314153bef'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = '80e712c9-ef6e-4d0e-a2c5-ceed05184d8b'::uuid;
UPDATE wallet_ledger SET deductible_balance = 42.0 WHERE id = 'a0e1bc60-0ae4-4db9-ae76-4b97c2c8ad8c'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = '80e712c9-ef6e-4d0e-a2c5-ceed05184d8b'::uuid;
UPDATE wallet_ledger SET deductible_balance = 24.0 WHERE id = '03c18928-17e1-4d2b-9c00-056365960f80'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = '80e712c9-ef6e-4d0e-a2c5-ceed05184d8b'::uuid;
UPDATE wallet_ledger SET deductible_balance = 7.0 WHERE id = 'e848f048-746d-41a0-b17f-a730157c1589'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = '80e712c9-ef6e-4d0e-a2c5-ceed05184d8b'::uuid;
DO $v$
DECLARE w numeric; l numeric;
BEGIN
  SELECT points_balance INTO w FROM user_wallet WHERE user_id = '80e712c9-ef6e-4d0e-a2c5-ceed05184d8b'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid;
  SELECT coalesce(sum(deductible_balance),0) INTO l FROM wallet_ledger
    WHERE user_id = '80e712c9-ef6e-4d0e-a2c5-ceed05184d8b'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid
      AND currency = 'points' AND transaction_type = 'earn';
  IF abs(w - l) > 0.01 THEN
    RAISE EXCEPTION 'post-apply invariant user % wallet % lots %', '80e712c9-ef6e-4d0e-a2c5-ceed05184d8b', w, l;
  END IF;
END $v$;
COMMIT;
BEGIN;
UPDATE wallet_ledger SET deductible_balance = 0.0 WHERE id = 'dcaf5979-1349-404e-9851-c89096218d70'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = '82f36c1a-6de9-4ff7-9c24-3aee6e073221'::uuid;
UPDATE wallet_ledger SET deductible_balance = 0.0 WHERE id = '7a75d420-a49f-4ef5-be42-5a5e1bd69019'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = '82f36c1a-6de9-4ff7-9c24-3aee6e073221'::uuid;
UPDATE wallet_ledger SET deductible_balance = 0.0 WHERE id = 'a6f860f6-ad88-4e66-a3f3-4230bb2969a4'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = '82f36c1a-6de9-4ff7-9c24-3aee6e073221'::uuid;
UPDATE wallet_ledger SET deductible_balance = 0.0 WHERE id = 'b9e2091c-4869-4a0a-966d-c089e81fb69f'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = '82f36c1a-6de9-4ff7-9c24-3aee6e073221'::uuid;
UPDATE wallet_ledger SET deductible_balance = 0.0 WHERE id = '8bf55d71-658c-49d3-a40e-3710d849ecc8'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = '82f36c1a-6de9-4ff7-9c24-3aee6e073221'::uuid;
UPDATE wallet_ledger SET deductible_balance = 348.0 WHERE id = '705d1acd-c83d-478f-b7fb-9971efcd9195'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = '82f36c1a-6de9-4ff7-9c24-3aee6e073221'::uuid;
UPDATE wallet_ledger SET deductible_balance = 148.0 WHERE id = '6bdeb51b-f907-4aa9-b4b0-6e1e9bf8c658'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = '82f36c1a-6de9-4ff7-9c24-3aee6e073221'::uuid;
DO $v$
DECLARE w numeric; l numeric;
BEGIN
  SELECT points_balance INTO w FROM user_wallet WHERE user_id = '82f36c1a-6de9-4ff7-9c24-3aee6e073221'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid;
  SELECT coalesce(sum(deductible_balance),0) INTO l FROM wallet_ledger
    WHERE user_id = '82f36c1a-6de9-4ff7-9c24-3aee6e073221'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid
      AND currency = 'points' AND transaction_type = 'earn';
  IF abs(w - l) > 0.01 THEN
    RAISE EXCEPTION 'post-apply invariant user % wallet % lots %', '82f36c1a-6de9-4ff7-9c24-3aee6e073221', w, l;
  END IF;
END $v$;
COMMIT;
BEGIN;
UPDATE wallet_ledger SET deductible_balance = 1563.0 WHERE id = '5f4d1e99-175e-4a75-9219-f86db88f95dc'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = '83aa76d2-dff8-422a-a556-dc8d72ce7089'::uuid;
DO $v$
DECLARE w numeric; l numeric;
BEGIN
  SELECT points_balance INTO w FROM user_wallet WHERE user_id = '83aa76d2-dff8-422a-a556-dc8d72ce7089'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid;
  SELECT coalesce(sum(deductible_balance),0) INTO l FROM wallet_ledger
    WHERE user_id = '83aa76d2-dff8-422a-a556-dc8d72ce7089'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid
      AND currency = 'points' AND transaction_type = 'earn';
  IF abs(w - l) > 0.01 THEN
    RAISE EXCEPTION 'post-apply invariant user % wallet % lots %', '83aa76d2-dff8-422a-a556-dc8d72ce7089', w, l;
  END IF;
END $v$;
COMMIT;
BEGIN;
UPDATE wallet_ledger SET deductible_balance = 0.0 WHERE id = '82833062-fc6b-4b69-a618-b4d12d67dbea'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = '871d5b20-c8de-4fb4-8065-565dc8522f6e'::uuid;
UPDATE wallet_ledger SET deductible_balance = 0.0 WHERE id = 'f89144ed-9e20-4be6-92a4-be889c64d25e'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = '871d5b20-c8de-4fb4-8065-565dc8522f6e'::uuid;
UPDATE wallet_ledger SET deductible_balance = 0.0 WHERE id = '90ec418e-fb4c-4d48-9f2d-a37a33dc50ff'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = '871d5b20-c8de-4fb4-8065-565dc8522f6e'::uuid;
UPDATE wallet_ledger SET deductible_balance = 0.0 WHERE id = '2ff3eb59-f227-4883-9943-a5af69bd21b2'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = '871d5b20-c8de-4fb4-8065-565dc8522f6e'::uuid;
UPDATE wallet_ledger SET deductible_balance = 0.0 WHERE id = '882817a7-88e1-4a42-aa17-732012e6420b'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = '871d5b20-c8de-4fb4-8065-565dc8522f6e'::uuid;
UPDATE wallet_ledger SET deductible_balance = 0.0 WHERE id = '43e1bd85-0fa5-4c77-8e2b-b36eab56d4c1'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = '871d5b20-c8de-4fb4-8065-565dc8522f6e'::uuid;
UPDATE wallet_ledger SET deductible_balance = 0.0 WHERE id = 'ead2ac34-144b-4044-8fc7-f079cd9624c7'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = '871d5b20-c8de-4fb4-8065-565dc8522f6e'::uuid;
UPDATE wallet_ledger SET deductible_balance = 0.0 WHERE id = '39e67647-e094-4501-b6ba-5a776d4911c3'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = '871d5b20-c8de-4fb4-8065-565dc8522f6e'::uuid;
UPDATE wallet_ledger SET deductible_balance = 0.0 WHERE id = '2e47a389-70a5-4697-8938-f17087975cf5'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = '871d5b20-c8de-4fb4-8065-565dc8522f6e'::uuid;
UPDATE wallet_ledger SET deductible_balance = 159.0 WHERE id = '191bf497-0e69-4228-bd6f-0be0b9c27f89'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = '871d5b20-c8de-4fb4-8065-565dc8522f6e'::uuid;
DO $v$
DECLARE w numeric; l numeric;
BEGIN
  SELECT points_balance INTO w FROM user_wallet WHERE user_id = '871d5b20-c8de-4fb4-8065-565dc8522f6e'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid;
  SELECT coalesce(sum(deductible_balance),0) INTO l FROM wallet_ledger
    WHERE user_id = '871d5b20-c8de-4fb4-8065-565dc8522f6e'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid
      AND currency = 'points' AND transaction_type = 'earn';
  IF abs(w - l) > 0.01 THEN
    RAISE EXCEPTION 'post-apply invariant user % wallet % lots %', '871d5b20-c8de-4fb4-8065-565dc8522f6e', w, l;
  END IF;
END $v$;
COMMIT;
BEGIN;
UPDATE wallet_ledger SET deductible_balance = 0.0 WHERE id = '5dadb3cd-0b77-42c4-b583-4e085695e518'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = '87448ba1-631a-4237-886e-7a3f48cdbbdd'::uuid;
UPDATE wallet_ledger SET deductible_balance = 0.0 WHERE id = '4b13d5b9-4b74-41d0-86be-c0fc32be3d7d'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = '87448ba1-631a-4237-886e-7a3f48cdbbdd'::uuid;
UPDATE wallet_ledger SET deductible_balance = 37.0 WHERE id = '6ca93b35-d99b-4764-b30c-9effb448c0f7'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = '87448ba1-631a-4237-886e-7a3f48cdbbdd'::uuid;
DO $v$
DECLARE w numeric; l numeric;
BEGIN
  SELECT points_balance INTO w FROM user_wallet WHERE user_id = '87448ba1-631a-4237-886e-7a3f48cdbbdd'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid;
  SELECT coalesce(sum(deductible_balance),0) INTO l FROM wallet_ledger
    WHERE user_id = '87448ba1-631a-4237-886e-7a3f48cdbbdd'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid
      AND currency = 'points' AND transaction_type = 'earn';
  IF abs(w - l) > 0.01 THEN
    RAISE EXCEPTION 'post-apply invariant user % wallet % lots %', '87448ba1-631a-4237-886e-7a3f48cdbbdd', w, l;
  END IF;
END $v$;
COMMIT;
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
BEGIN;
UPDATE wallet_ledger SET deductible_balance = 621.0 WHERE id = '00161c3f-9e13-494e-8d6f-159443ece338'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = '8f2f4682-739b-460a-b8a7-358f9dde4ce1'::uuid;
DO $v$
DECLARE w numeric; l numeric;
BEGIN
  SELECT points_balance INTO w FROM user_wallet WHERE user_id = '8f2f4682-739b-460a-b8a7-358f9dde4ce1'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid;
  SELECT coalesce(sum(deductible_balance),0) INTO l FROM wallet_ledger
    WHERE user_id = '8f2f4682-739b-460a-b8a7-358f9dde4ce1'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid
      AND currency = 'points' AND transaction_type = 'earn';
  IF abs(w - l) > 0.01 THEN
    RAISE EXCEPTION 'post-apply invariant user % wallet % lots %', '8f2f4682-739b-460a-b8a7-358f9dde4ce1', w, l;
  END IF;
END $v$;
COMMIT;
BEGIN;
UPDATE wallet_ledger SET deductible_balance = 0.0 WHERE id = 'cb412ffe-0cd9-4e93-bba5-7a1caff4cc79'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = '90829544-94b2-4a65-9636-f2ae982e2eea'::uuid;
UPDATE wallet_ledger SET deductible_balance = 12.0 WHERE id = '6403b6b2-6e8c-42ac-8a5a-140b59535929'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = '90829544-94b2-4a65-9636-f2ae982e2eea'::uuid;
DO $v$
DECLARE w numeric; l numeric;
BEGIN
  SELECT points_balance INTO w FROM user_wallet WHERE user_id = '90829544-94b2-4a65-9636-f2ae982e2eea'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid;
  SELECT coalesce(sum(deductible_balance),0) INTO l FROM wallet_ledger
    WHERE user_id = '90829544-94b2-4a65-9636-f2ae982e2eea'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid
      AND currency = 'points' AND transaction_type = 'earn';
  IF abs(w - l) > 0.01 THEN
    RAISE EXCEPTION 'post-apply invariant user % wallet % lots %', '90829544-94b2-4a65-9636-f2ae982e2eea', w, l;
  END IF;
END $v$;
COMMIT;
BEGIN;
UPDATE wallet_ledger SET deductible_balance = 132.0 WHERE id = '65a9b717-e953-4563-849e-69e09ca19979'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = '90eede70-c6fb-4277-bd3e-c0bd3fbbc3f4'::uuid;
UPDATE wallet_ledger SET deductible_balance = 57.0 WHERE id = '7a5d3b8e-d764-4264-8644-9d89fdf78be3'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = '90eede70-c6fb-4277-bd3e-c0bd3fbbc3f4'::uuid;
DO $v$
DECLARE w numeric; l numeric;
BEGIN
  SELECT points_balance INTO w FROM user_wallet WHERE user_id = '90eede70-c6fb-4277-bd3e-c0bd3fbbc3f4'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid;
  SELECT coalesce(sum(deductible_balance),0) INTO l FROM wallet_ledger
    WHERE user_id = '90eede70-c6fb-4277-bd3e-c0bd3fbbc3f4'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid
      AND currency = 'points' AND transaction_type = 'earn';
  IF abs(w - l) > 0.01 THEN
    RAISE EXCEPTION 'post-apply invariant user % wallet % lots %', '90eede70-c6fb-4277-bd3e-c0bd3fbbc3f4', w, l;
  END IF;
END $v$;
COMMIT;
BEGIN;
UPDATE wallet_ledger SET deductible_balance = 5.0 WHERE id = '3ab3935e-da27-4973-b73d-b9f60e65f08e'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = '92bebfd3-041c-4ef3-99d2-978bafd45937'::uuid;
DO $v$
DECLARE w numeric; l numeric;
BEGIN
  SELECT points_balance INTO w FROM user_wallet WHERE user_id = '92bebfd3-041c-4ef3-99d2-978bafd45937'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid;
  SELECT coalesce(sum(deductible_balance),0) INTO l FROM wallet_ledger
    WHERE user_id = '92bebfd3-041c-4ef3-99d2-978bafd45937'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid
      AND currency = 'points' AND transaction_type = 'earn';
  IF abs(w - l) > 0.01 THEN
    RAISE EXCEPTION 'post-apply invariant user % wallet % lots %', '92bebfd3-041c-4ef3-99d2-978bafd45937', w, l;
  END IF;
END $v$;
COMMIT;
BEGIN;
INSERT INTO wallet_ledger (
  merchant_id, user_id, currency, transaction_type, component,
  amount, signed_amount, balance_before, balance_after, deductible_balance,
  source_type, description, metadata, target_entity_id, expiry_date,
  created_by, dedup_key, created_at, skip_cdc
) SELECT
  '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid, '932b88ec-4e56-447f-9f81-9136a93c8520'::uuid,   'points'::currency, 'earn'::currency_transaction_type,
  'base'::currency_component,
  50, 50, 50,
  50, 50,
  'manual'::wallet_transaction_source_type, 'Legacy wallet balance', '{"backfill": "jorakay_wallet_lot_drift_20260912", "reason": "orphan_wallet_no_points_ledger"}'::jsonb,
  NULL, NULL,
  '932b88ec-4e56-447f-9f81-9136a93c8520', 'jorakay-orphan-65b1c1fd12e71882a7296505', '2026-06-15T00:00:00+00:00'::timestamptz, false
WHERE NOT EXISTS (
  SELECT 1 FROM wallet_ledger wl
  WHERE wl.merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND wl.dedup_key = 'jorakay-orphan-65b1c1fd12e71882a7296505'
);;
DO $v$
DECLARE w numeric; l numeric;
BEGIN
  SELECT points_balance INTO w FROM user_wallet WHERE user_id = '932b88ec-4e56-447f-9f81-9136a93c8520'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid;
  SELECT coalesce(sum(deductible_balance),0) INTO l FROM wallet_ledger
    WHERE user_id = '932b88ec-4e56-447f-9f81-9136a93c8520'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid
      AND currency = 'points' AND transaction_type = 'earn';
  IF abs(w - l) > 0.01 THEN
    RAISE EXCEPTION 'post-apply invariant user % wallet % lots %', '932b88ec-4e56-447f-9f81-9136a93c8520', w, l;
  END IF;
END $v$;
COMMIT;
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
BEGIN;
UPDATE wallet_ledger SET deductible_balance = 0.0 WHERE id = 'efe587b3-da53-4111-bdf4-f94804a2eab7'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = '9a14fca3-a6a0-4452-a3be-2e11a20ec0e4'::uuid;
UPDATE wallet_ledger SET deductible_balance = 0.0 WHERE id = '77d08d0f-9757-46b5-8127-b1c15bf7bd51'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = '9a14fca3-a6a0-4452-a3be-2e11a20ec0e4'::uuid;
UPDATE wallet_ledger SET deductible_balance = 0.0 WHERE id = '33872c6c-2397-4b17-95e2-79ece0d27f22'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = '9a14fca3-a6a0-4452-a3be-2e11a20ec0e4'::uuid;
UPDATE wallet_ledger SET deductible_balance = 0.0 WHERE id = 'ddcdd455-efeb-4f85-9530-e5a8b0b89507'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = '9a14fca3-a6a0-4452-a3be-2e11a20ec0e4'::uuid;
UPDATE wallet_ledger SET deductible_balance = 0.0 WHERE id = '28d38ee5-e66a-4837-b32b-63b8e3bfa57e'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = '9a14fca3-a6a0-4452-a3be-2e11a20ec0e4'::uuid;
UPDATE wallet_ledger SET deductible_balance = 0.0 WHERE id = '5fda565c-3a23-4ff9-bb50-1cc1152e88e7'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = '9a14fca3-a6a0-4452-a3be-2e11a20ec0e4'::uuid;
UPDATE wallet_ledger SET deductible_balance = 0.0 WHERE id = '70632592-608a-4666-8e53-9c76517a6808'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = '9a14fca3-a6a0-4452-a3be-2e11a20ec0e4'::uuid;
UPDATE wallet_ledger SET deductible_balance = 0.0 WHERE id = 'c824a3f6-8f42-4216-85a4-8082080c874d'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = '9a14fca3-a6a0-4452-a3be-2e11a20ec0e4'::uuid;
UPDATE wallet_ledger SET deductible_balance = 0.0 WHERE id = '37ab4efa-c9a0-47e1-b90b-fc623061934c'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = '9a14fca3-a6a0-4452-a3be-2e11a20ec0e4'::uuid;
UPDATE wallet_ledger SET deductible_balance = 0.0 WHERE id = 'c17b742e-b5ba-474b-8315-8cc62ec86ceb'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = '9a14fca3-a6a0-4452-a3be-2e11a20ec0e4'::uuid;
UPDATE wallet_ledger SET deductible_balance = 0.0 WHERE id = '5b12968c-cb73-4327-b475-687b815a0e39'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = '9a14fca3-a6a0-4452-a3be-2e11a20ec0e4'::uuid;
UPDATE wallet_ledger SET deductible_balance = 0.0 WHERE id = 'c2320fe4-2ad5-42da-92d9-f90384580f5a'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = '9a14fca3-a6a0-4452-a3be-2e11a20ec0e4'::uuid;
UPDATE wallet_ledger SET deductible_balance = 0.0 WHERE id = 'f286c184-7b0d-4d75-9bcd-bec276ac93ea'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = '9a14fca3-a6a0-4452-a3be-2e11a20ec0e4'::uuid;
UPDATE wallet_ledger SET deductible_balance = 21.0 WHERE id = 'effdb266-09b1-450e-8d97-36c88cf5deff'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = '9a14fca3-a6a0-4452-a3be-2e11a20ec0e4'::uuid;
DO $v$
DECLARE w numeric; l numeric;
BEGIN
  SELECT points_balance INTO w FROM user_wallet WHERE user_id = '9a14fca3-a6a0-4452-a3be-2e11a20ec0e4'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid;
  SELECT coalesce(sum(deductible_balance),0) INTO l FROM wallet_ledger
    WHERE user_id = '9a14fca3-a6a0-4452-a3be-2e11a20ec0e4'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid
      AND currency = 'points' AND transaction_type = 'earn';
  IF abs(w - l) > 0.01 THEN
    RAISE EXCEPTION 'post-apply invariant user % wallet % lots %', '9a14fca3-a6a0-4452-a3be-2e11a20ec0e4', w, l;
  END IF;
END $v$;
COMMIT;
BEGIN;
UPDATE wallet_ledger SET deductible_balance = 1748.0 WHERE id = '98e7010d-7b68-4e36-ad2d-4714cd47c52c'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = '9b5110f9-c175-4ade-817e-28f19d217b1a'::uuid;
UPDATE wallet_ledger SET deductible_balance = 81.0 WHERE id = '554b5861-6fe4-4550-9c95-484a2761f35c'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = '9b5110f9-c175-4ade-817e-28f19d217b1a'::uuid;
UPDATE wallet_ledger SET deductible_balance = 928.0 WHERE id = '194b2231-bf24-44c9-93d5-69187bfbd29d'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = '9b5110f9-c175-4ade-817e-28f19d217b1a'::uuid;
DO $v$
DECLARE w numeric; l numeric;
BEGIN
  SELECT points_balance INTO w FROM user_wallet WHERE user_id = '9b5110f9-c175-4ade-817e-28f19d217b1a'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid;
  SELECT coalesce(sum(deductible_balance),0) INTO l FROM wallet_ledger
    WHERE user_id = '9b5110f9-c175-4ade-817e-28f19d217b1a'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid
      AND currency = 'points' AND transaction_type = 'earn';
  IF abs(w - l) > 0.01 THEN
    RAISE EXCEPTION 'post-apply invariant user % wallet % lots %', '9b5110f9-c175-4ade-817e-28f19d217b1a', w, l;
  END IF;
END $v$;
COMMIT;
BEGIN;
UPDATE wallet_ledger SET deductible_balance = 180.0 WHERE id = 'a5edb512-1fbb-481f-a934-d47e6d12759b'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = '9b5ae71d-5085-40af-a26a-cd1f0d6e27d7'::uuid;
UPDATE wallet_ledger SET deductible_balance = 300.0 WHERE id = '350777b2-ee9b-48c1-996b-bda418569e5e'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = '9b5ae71d-5085-40af-a26a-cd1f0d6e27d7'::uuid;
DO $v$
DECLARE w numeric; l numeric;
BEGIN
  SELECT points_balance INTO w FROM user_wallet WHERE user_id = '9b5ae71d-5085-40af-a26a-cd1f0d6e27d7'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid;
  SELECT coalesce(sum(deductible_balance),0) INTO l FROM wallet_ledger
    WHERE user_id = '9b5ae71d-5085-40af-a26a-cd1f0d6e27d7'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid
      AND currency = 'points' AND transaction_type = 'earn';
  IF abs(w - l) > 0.01 THEN
    RAISE EXCEPTION 'post-apply invariant user % wallet % lots %', '9b5ae71d-5085-40af-a26a-cd1f0d6e27d7', w, l;
  END IF;
END $v$;
COMMIT;
BEGIN;
UPDATE wallet_ledger SET deductible_balance = 3737.0 WHERE id = '61fb5a01-1f2a-4553-8366-2962e01cbf2f'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = '9cefd9f0-ab62-4426-8fc2-344ebcd55815'::uuid;
DO $v$
DECLARE w numeric; l numeric;
BEGIN
  SELECT points_balance INTO w FROM user_wallet WHERE user_id = '9cefd9f0-ab62-4426-8fc2-344ebcd55815'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid;
  SELECT coalesce(sum(deductible_balance),0) INTO l FROM wallet_ledger
    WHERE user_id = '9cefd9f0-ab62-4426-8fc2-344ebcd55815'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid
      AND currency = 'points' AND transaction_type = 'earn';
  IF abs(w - l) > 0.01 THEN
    RAISE EXCEPTION 'post-apply invariant user % wallet % lots %', '9cefd9f0-ab62-4426-8fc2-344ebcd55815', w, l;
  END IF;
END $v$;
COMMIT;
BEGIN;
UPDATE wallet_ledger SET deductible_balance = 0.0 WHERE id = '0ca5b120-0f58-43b7-bdba-24bbf02b188e'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = 'a2e96866-6710-4fbd-b707-2488d5989082'::uuid;
UPDATE wallet_ledger SET deductible_balance = 0.0 WHERE id = 'ff3b2e7c-5379-409b-81e8-6cc6bc12a5f5'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = 'a2e96866-6710-4fbd-b707-2488d5989082'::uuid;
UPDATE wallet_ledger SET deductible_balance = 0.0 WHERE id = 'c0d093c1-e997-4e1f-b4c3-bbcf5928c319'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = 'a2e96866-6710-4fbd-b707-2488d5989082'::uuid;
UPDATE wallet_ledger SET deductible_balance = 0.0 WHERE id = 'd277e67d-8a39-4021-8e3f-e4402a7cdeb1'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = 'a2e96866-6710-4fbd-b707-2488d5989082'::uuid;
UPDATE wallet_ledger SET deductible_balance = 52.0 WHERE id = '2d999d3e-c300-47b0-8316-92bc6fb93f8f'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = 'a2e96866-6710-4fbd-b707-2488d5989082'::uuid;
UPDATE wallet_ledger SET deductible_balance = 22.0 WHERE id = '3489afc6-02f8-4e00-97fa-7f16040f55ae'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = 'a2e96866-6710-4fbd-b707-2488d5989082'::uuid;
DO $v$
DECLARE w numeric; l numeric;
BEGIN
  SELECT points_balance INTO w FROM user_wallet WHERE user_id = 'a2e96866-6710-4fbd-b707-2488d5989082'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid;
  SELECT coalesce(sum(deductible_balance),0) INTO l FROM wallet_ledger
    WHERE user_id = 'a2e96866-6710-4fbd-b707-2488d5989082'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid
      AND currency = 'points' AND transaction_type = 'earn';
  IF abs(w - l) > 0.01 THEN
    RAISE EXCEPTION 'post-apply invariant user % wallet % lots %', 'a2e96866-6710-4fbd-b707-2488d5989082', w, l;
  END IF;
END $v$;
COMMIT;
BEGIN;
UPDATE wallet_ledger SET deductible_balance = 42.0 WHERE id = '578d7ac5-1a0c-40f6-857d-d27ced95d459'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = 'a71e425d-82b5-47f5-8a26-013a2a346b62'::uuid;
UPDATE wallet_ledger SET deductible_balance = 5.0 WHERE id = '000957b9-63a5-4a9c-b8c6-a703c11fb83f'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = 'a71e425d-82b5-47f5-8a26-013a2a346b62'::uuid;
UPDATE wallet_ledger SET deductible_balance = 41.0 WHERE id = 'ab492e9c-133c-48e4-80da-799b6f6e02ba'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = 'a71e425d-82b5-47f5-8a26-013a2a346b62'::uuid;
UPDATE wallet_ledger SET deductible_balance = 17.0 WHERE id = '8a94985e-0b27-41f5-a504-91fd0964addd'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = 'a71e425d-82b5-47f5-8a26-013a2a346b62'::uuid;
UPDATE wallet_ledger SET deductible_balance = 15.0 WHERE id = '598b588d-44db-48ad-8939-8728c8bf4f08'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = 'a71e425d-82b5-47f5-8a26-013a2a346b62'::uuid;
DO $v$
DECLARE w numeric; l numeric;
BEGIN
  SELECT points_balance INTO w FROM user_wallet WHERE user_id = 'a71e425d-82b5-47f5-8a26-013a2a346b62'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid;
  SELECT coalesce(sum(deductible_balance),0) INTO l FROM wallet_ledger
    WHERE user_id = 'a71e425d-82b5-47f5-8a26-013a2a346b62'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid
      AND currency = 'points' AND transaction_type = 'earn';
  IF abs(w - l) > 0.01 THEN
    RAISE EXCEPTION 'post-apply invariant user % wallet % lots %', 'a71e425d-82b5-47f5-8a26-013a2a346b62', w, l;
  END IF;
END $v$;
COMMIT;
