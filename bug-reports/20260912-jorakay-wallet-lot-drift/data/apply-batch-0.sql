BEGIN;
UPDATE wallet_ledger SET deductible_balance = 162.0 WHERE id = '969ce393-c5c2-474a-8131-fbc7665cea78'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = '000a4cba-d5e7-4c62-8a2a-c49437012e18'::uuid;
DO $v$
DECLARE w numeric; l numeric;
BEGIN
  SELECT points_balance INTO w FROM user_wallet WHERE user_id = '000a4cba-d5e7-4c62-8a2a-c49437012e18'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid;
  SELECT coalesce(sum(deductible_balance),0) INTO l FROM wallet_ledger
    WHERE user_id = '000a4cba-d5e7-4c62-8a2a-c49437012e18'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid
      AND currency = 'points' AND transaction_type = 'earn';
  IF abs(w - l) > 0.01 THEN
    RAISE EXCEPTION 'post-apply invariant user % wallet % lots %', '000a4cba-d5e7-4c62-8a2a-c49437012e18', w, l;
  END IF;
END $v$;
COMMIT;
BEGIN;
UPDATE wallet_ledger SET deductible_balance = 26.0 WHERE id = 'a7669ce7-73ea-4093-9aa5-32f419785eb4'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = '027131cb-716d-4d66-ad20-bdc0044f2052'::uuid;
DO $v$
DECLARE w numeric; l numeric;
BEGIN
  SELECT points_balance INTO w FROM user_wallet WHERE user_id = '027131cb-716d-4d66-ad20-bdc0044f2052'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid;
  SELECT coalesce(sum(deductible_balance),0) INTO l FROM wallet_ledger
    WHERE user_id = '027131cb-716d-4d66-ad20-bdc0044f2052'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid
      AND currency = 'points' AND transaction_type = 'earn';
  IF abs(w - l) > 0.01 THEN
    RAISE EXCEPTION 'post-apply invariant user % wallet % lots %', '027131cb-716d-4d66-ad20-bdc0044f2052', w, l;
  END IF;
END $v$;
COMMIT;
BEGIN;
UPDATE wallet_ledger SET deductible_balance = 1.0 WHERE id = '2e19c896-6dea-4e39-86a5-43b0f09604cb'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = '0271c3e6-0fe4-4910-bd9a-2c4bb8873040'::uuid;
DO $v$
DECLARE w numeric; l numeric;
BEGIN
  SELECT points_balance INTO w FROM user_wallet WHERE user_id = '0271c3e6-0fe4-4910-bd9a-2c4bb8873040'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid;
  SELECT coalesce(sum(deductible_balance),0) INTO l FROM wallet_ledger
    WHERE user_id = '0271c3e6-0fe4-4910-bd9a-2c4bb8873040'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid
      AND currency = 'points' AND transaction_type = 'earn';
  IF abs(w - l) > 0.01 THEN
    RAISE EXCEPTION 'post-apply invariant user % wallet % lots %', '0271c3e6-0fe4-4910-bd9a-2c4bb8873040', w, l;
  END IF;
END $v$;
COMMIT;
BEGIN;
UPDATE wallet_ledger SET deductible_balance = 0.0 WHERE id = '1d492714-e37a-4788-a902-fe84ccbe5c50'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = '0277d347-51c5-4ee7-b445-975cb01a799d'::uuid;
UPDATE wallet_ledger SET deductible_balance = 0.0 WHERE id = 'a46963bb-aea2-4585-bfd8-50a5af4f0c91'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = '0277d347-51c5-4ee7-b445-975cb01a799d'::uuid;
UPDATE wallet_ledger SET deductible_balance = 0.0 WHERE id = 'a56ddb13-a96e-4946-b3f9-ea988536bf69'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = '0277d347-51c5-4ee7-b445-975cb01a799d'::uuid;
UPDATE wallet_ledger SET deductible_balance = 0.0 WHERE id = '5d21c250-c03a-4623-aa76-dd167ff2701d'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = '0277d347-51c5-4ee7-b445-975cb01a799d'::uuid;
UPDATE wallet_ledger SET deductible_balance = 0.0 WHERE id = 'e74964ca-c3f3-477c-80b0-29b361fdbcc2'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = '0277d347-51c5-4ee7-b445-975cb01a799d'::uuid;
UPDATE wallet_ledger SET deductible_balance = 82.0 WHERE id = '06c5f3ec-7e0e-437c-ab83-579079adaf1a'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = '0277d347-51c5-4ee7-b445-975cb01a799d'::uuid;
UPDATE wallet_ledger SET deductible_balance = 358.0 WHERE id = '9f11a94a-a055-4fea-a0e0-d97c82fa8b2e'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = '0277d347-51c5-4ee7-b445-975cb01a799d'::uuid;
DO $v$
DECLARE w numeric; l numeric;
BEGIN
  SELECT points_balance INTO w FROM user_wallet WHERE user_id = '0277d347-51c5-4ee7-b445-975cb01a799d'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid;
  SELECT coalesce(sum(deductible_balance),0) INTO l FROM wallet_ledger
    WHERE user_id = '0277d347-51c5-4ee7-b445-975cb01a799d'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid
      AND currency = 'points' AND transaction_type = 'earn';
  IF abs(w - l) > 0.01 THEN
    RAISE EXCEPTION 'post-apply invariant user % wallet % lots %', '0277d347-51c5-4ee7-b445-975cb01a799d', w, l;
  END IF;
END $v$;
COMMIT;
BEGIN;
UPDATE wallet_ledger SET deductible_balance = 166.0 WHERE id = 'f379d00a-96ed-4497-8769-85d2f73e2db5'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = '0687be3a-c330-4f48-a942-5d64d702f016'::uuid;
UPDATE wallet_ledger SET deductible_balance = 129.0 WHERE id = '084956bf-2735-488a-ad78-4f477ccffc44'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = '0687be3a-c330-4f48-a942-5d64d702f016'::uuid;
UPDATE wallet_ledger SET deductible_balance = 90.0 WHERE id = 'dd95d43f-c98d-4945-b82b-692c49c2e56d'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = '0687be3a-c330-4f48-a942-5d64d702f016'::uuid;
UPDATE wallet_ledger SET deductible_balance = 20.0 WHERE id = '3e396085-e7ae-43c4-9666-0f0ef8604534'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = '0687be3a-c330-4f48-a942-5d64d702f016'::uuid;
UPDATE wallet_ledger SET deductible_balance = 10.0 WHERE id = 'b4e8cb64-5647-48bf-9af2-784010c8a936'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = '0687be3a-c330-4f48-a942-5d64d702f016'::uuid;
UPDATE wallet_ledger SET deductible_balance = 40.0 WHERE id = '8faa4006-38db-47c3-a827-6e63ab047212'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = '0687be3a-c330-4f48-a942-5d64d702f016'::uuid;
UPDATE wallet_ledger SET deductible_balance = 23.0 WHERE id = '2e943c41-dc1a-4be2-9e1f-02efd5f79cc5'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = '0687be3a-c330-4f48-a942-5d64d702f016'::uuid;
UPDATE wallet_ledger SET deductible_balance = 13.0 WHERE id = '19ba4be7-20a6-46f1-b12d-1ee4fada43d7'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = '0687be3a-c330-4f48-a942-5d64d702f016'::uuid;
UPDATE wallet_ledger SET deductible_balance = 93.0 WHERE id = '66894cca-0129-431d-b614-d42bec1ef970'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = '0687be3a-c330-4f48-a942-5d64d702f016'::uuid;
UPDATE wallet_ledger SET deductible_balance = 55.0 WHERE id = '446a1840-d0a5-4173-a6e7-bb6e092a8534'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = '0687be3a-c330-4f48-a942-5d64d702f016'::uuid;
UPDATE wallet_ledger SET deductible_balance = 54.0 WHERE id = 'fab233cf-2695-441a-8106-446163aa9c19'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = '0687be3a-c330-4f48-a942-5d64d702f016'::uuid;
UPDATE wallet_ledger SET deductible_balance = 81.0 WHERE id = 'de7f827f-6369-4ae8-8359-9bb15b44ea0f'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = '0687be3a-c330-4f48-a942-5d64d702f016'::uuid;
UPDATE wallet_ledger SET deductible_balance = 14.0 WHERE id = 'e92af145-8024-4e28-a0ee-f31364d1ef9e'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = '0687be3a-c330-4f48-a942-5d64d702f016'::uuid;
UPDATE wallet_ledger SET deductible_balance = 106.0 WHERE id = '5af3d757-cd87-49b3-bd58-d6fa563ced42'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = '0687be3a-c330-4f48-a942-5d64d702f016'::uuid;
UPDATE wallet_ledger SET deductible_balance = 4.0 WHERE id = '080add53-eda0-414f-a297-6da52f84198b'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = '0687be3a-c330-4f48-a942-5d64d702f016'::uuid;
UPDATE wallet_ledger SET deductible_balance = 34.0 WHERE id = '9f4e803a-cb19-44bc-b755-ed313e23391b'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = '0687be3a-c330-4f48-a942-5d64d702f016'::uuid;
UPDATE wallet_ledger SET deductible_balance = 69.0 WHERE id = '1bedcae6-5a23-40a6-9d93-9e4e0a3fc350'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = '0687be3a-c330-4f48-a942-5d64d702f016'::uuid;
UPDATE wallet_ledger SET deductible_balance = 18.0 WHERE id = 'e445380f-8c43-482b-8ebd-e22a90288260'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = '0687be3a-c330-4f48-a942-5d64d702f016'::uuid;
DO $v$
DECLARE w numeric; l numeric;
BEGIN
  SELECT points_balance INTO w FROM user_wallet WHERE user_id = '0687be3a-c330-4f48-a942-5d64d702f016'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid;
  SELECT coalesce(sum(deductible_balance),0) INTO l FROM wallet_ledger
    WHERE user_id = '0687be3a-c330-4f48-a942-5d64d702f016'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid
      AND currency = 'points' AND transaction_type = 'earn';
  IF abs(w - l) > 0.01 THEN
    RAISE EXCEPTION 'post-apply invariant user % wallet % lots %', '0687be3a-c330-4f48-a942-5d64d702f016', w, l;
  END IF;
END $v$;
COMMIT;
BEGIN;
UPDATE wallet_ledger SET deductible_balance = 510.0 WHERE id = 'ee0eedf1-940a-4578-af74-69bbc048558a'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = '07313983-05d3-46a1-8549-75fc6d087ec5'::uuid;
DO $v$
DECLARE w numeric; l numeric;
BEGIN
  SELECT points_balance INTO w FROM user_wallet WHERE user_id = '07313983-05d3-46a1-8549-75fc6d087ec5'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid;
  SELECT coalesce(sum(deductible_balance),0) INTO l FROM wallet_ledger
    WHERE user_id = '07313983-05d3-46a1-8549-75fc6d087ec5'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid
      AND currency = 'points' AND transaction_type = 'earn';
  IF abs(w - l) > 0.01 THEN
    RAISE EXCEPTION 'post-apply invariant user % wallet % lots %', '07313983-05d3-46a1-8549-75fc6d087ec5', w, l;
  END IF;
END $v$;
COMMIT;
BEGIN;
UPDATE wallet_ledger SET deductible_balance = 0.0 WHERE id = '55ab5e09-202a-4976-9e24-31c113bb7332'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = '09b753ab-6f76-46e6-95b6-4d9067a5490c'::uuid;
UPDATE wallet_ledger SET deductible_balance = 0.0 WHERE id = '70bc7d08-3930-41b6-9167-154f75b87f72'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = '09b753ab-6f76-46e6-95b6-4d9067a5490c'::uuid;
UPDATE wallet_ledger SET deductible_balance = 0.0 WHERE id = 'a443994a-5275-4999-a95f-86fab22d7fb8'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = '09b753ab-6f76-46e6-95b6-4d9067a5490c'::uuid;
UPDATE wallet_ledger SET deductible_balance = 0.0 WHERE id = 'aaa4fac8-4e06-42bc-a403-b8fb26de0b65'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = '09b753ab-6f76-46e6-95b6-4d9067a5490c'::uuid;
UPDATE wallet_ledger SET deductible_balance = 0.0 WHERE id = '15c2b571-0f46-46fe-af54-fb5f11ef8c8f'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = '09b753ab-6f76-46e6-95b6-4d9067a5490c'::uuid;
UPDATE wallet_ledger SET deductible_balance = 63.0 WHERE id = '978d4161-bff8-4c50-8a17-fa60dd74a926'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = '09b753ab-6f76-46e6-95b6-4d9067a5490c'::uuid;
DO $v$
DECLARE w numeric; l numeric;
BEGIN
  SELECT points_balance INTO w FROM user_wallet WHERE user_id = '09b753ab-6f76-46e6-95b6-4d9067a5490c'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid;
  SELECT coalesce(sum(deductible_balance),0) INTO l FROM wallet_ledger
    WHERE user_id = '09b753ab-6f76-46e6-95b6-4d9067a5490c'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid
      AND currency = 'points' AND transaction_type = 'earn';
  IF abs(w - l) > 0.01 THEN
    RAISE EXCEPTION 'post-apply invariant user % wallet % lots %', '09b753ab-6f76-46e6-95b6-4d9067a5490c', w, l;
  END IF;
END $v$;
COMMIT;
BEGIN;
UPDATE wallet_ledger SET deductible_balance = 158.0 WHERE id = 'ecc68ef7-fd00-4a8a-9b52-22b86f1d5eef'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = '0c03aeb9-727e-451d-80cb-f6eb767af872'::uuid;
UPDATE wallet_ledger SET deductible_balance = 495.0 WHERE id = '79781fb5-4b29-4758-b68f-2830d7081302'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = '0c03aeb9-727e-451d-80cb-f6eb767af872'::uuid;
UPDATE wallet_ledger SET deductible_balance = 94.0 WHERE id = 'eed72e8f-ed12-4bbc-9972-15c6d38a01ce'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = '0c03aeb9-727e-451d-80cb-f6eb767af872'::uuid;
UPDATE wallet_ledger SET deductible_balance = 120.0 WHERE id = '8fb46586-6382-4357-b137-f37b46a15180'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = '0c03aeb9-727e-451d-80cb-f6eb767af872'::uuid;
UPDATE wallet_ledger SET deductible_balance = 240.0 WHERE id = '953b490e-38b1-4ca3-904e-c3160eaa9e2d'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = '0c03aeb9-727e-451d-80cb-f6eb767af872'::uuid;
UPDATE wallet_ledger SET deductible_balance = 398.0 WHERE id = '040246b4-e581-4c80-9b4d-ddfc90baebbe'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = '0c03aeb9-727e-451d-80cb-f6eb767af872'::uuid;
UPDATE wallet_ledger SET deductible_balance = 195.0 WHERE id = '23bb5ed9-ad3c-412a-9e6d-6c31aa0d7d5d'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = '0c03aeb9-727e-451d-80cb-f6eb767af872'::uuid;
DO $v$
DECLARE w numeric; l numeric;
BEGIN
  SELECT points_balance INTO w FROM user_wallet WHERE user_id = '0c03aeb9-727e-451d-80cb-f6eb767af872'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid;
  SELECT coalesce(sum(deductible_balance),0) INTO l FROM wallet_ledger
    WHERE user_id = '0c03aeb9-727e-451d-80cb-f6eb767af872'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid
      AND currency = 'points' AND transaction_type = 'earn';
  IF abs(w - l) > 0.01 THEN
    RAISE EXCEPTION 'post-apply invariant user % wallet % lots %', '0c03aeb9-727e-451d-80cb-f6eb767af872', w, l;
  END IF;
END $v$;
COMMIT;
BEGIN;
UPDATE wallet_ledger SET deductible_balance = 12.0 WHERE id = '040dbd68-fb07-42b2-8a9c-7003feabf83f'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = '0c2ecc66-52a7-4fe7-bd2b-1ef0b9f1e5c9'::uuid;
UPDATE wallet_ledger SET deductible_balance = 33.0 WHERE id = 'b98bbf81-4e47-471a-bf35-19d05ae50fbc'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = '0c2ecc66-52a7-4fe7-bd2b-1ef0b9f1e5c9'::uuid;
UPDATE wallet_ledger SET deductible_balance = 31.0 WHERE id = '983459b9-54b0-4e7e-9657-ede5f735a7dd'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = '0c2ecc66-52a7-4fe7-bd2b-1ef0b9f1e5c9'::uuid;
UPDATE wallet_ledger SET deductible_balance = 23.0 WHERE id = '9685be81-b8aa-43f2-948c-119e286972de'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = '0c2ecc66-52a7-4fe7-bd2b-1ef0b9f1e5c9'::uuid;
UPDATE wallet_ledger SET deductible_balance = 4.0 WHERE id = '741d3aa0-f030-47c9-a8ef-41f3e91e251c'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = '0c2ecc66-52a7-4fe7-bd2b-1ef0b9f1e5c9'::uuid;
UPDATE wallet_ledger SET deductible_balance = 10.0 WHERE id = '24450544-570d-4e59-93a4-928161952563'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = '0c2ecc66-52a7-4fe7-bd2b-1ef0b9f1e5c9'::uuid;
UPDATE wallet_ledger SET deductible_balance = 6.0 WHERE id = '20a5df70-3dba-4e13-88ef-317da9793100'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = '0c2ecc66-52a7-4fe7-bd2b-1ef0b9f1e5c9'::uuid;
DO $v$
DECLARE w numeric; l numeric;
BEGIN
  SELECT points_balance INTO w FROM user_wallet WHERE user_id = '0c2ecc66-52a7-4fe7-bd2b-1ef0b9f1e5c9'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid;
  SELECT coalesce(sum(deductible_balance),0) INTO l FROM wallet_ledger
    WHERE user_id = '0c2ecc66-52a7-4fe7-bd2b-1ef0b9f1e5c9'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid
      AND currency = 'points' AND transaction_type = 'earn';
  IF abs(w - l) > 0.01 THEN
    RAISE EXCEPTION 'post-apply invariant user % wallet % lots %', '0c2ecc66-52a7-4fe7-bd2b-1ef0b9f1e5c9', w, l;
  END IF;
END $v$;
COMMIT;
BEGIN;
UPDATE wallet_ledger SET deductible_balance = 48.0 WHERE id = 'c65868d8-d64b-4eeb-ab79-871184a188c2'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = '1423d02b-0443-49a5-9870-aad360f78c79'::uuid;
DO $v$
DECLARE w numeric; l numeric;
BEGIN
  SELECT points_balance INTO w FROM user_wallet WHERE user_id = '1423d02b-0443-49a5-9870-aad360f78c79'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid;
  SELECT coalesce(sum(deductible_balance),0) INTO l FROM wallet_ledger
    WHERE user_id = '1423d02b-0443-49a5-9870-aad360f78c79'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid
      AND currency = 'points' AND transaction_type = 'earn';
  IF abs(w - l) > 0.01 THEN
    RAISE EXCEPTION 'post-apply invariant user % wallet % lots %', '1423d02b-0443-49a5-9870-aad360f78c79', w, l;
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
  '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid, '14d69324-43b1-4968-ac10-6d036faa3eb6'::uuid,   'points'::currency, 'earn'::currency_transaction_type,
  'base'::currency_component,
  400, 400, 400,
  400, 400,
  'manual'::wallet_transaction_source_type, 'Legacy wallet balance', '{"backfill": "jorakay_wallet_lot_drift_20260912", "reason": "orphan_wallet_no_points_ledger"}'::jsonb,
  NULL, NULL,
  '14d69324-43b1-4968-ac10-6d036faa3eb6', 'jorakay-orphan-6563f123ffd7efcec974f172', '2026-06-15T00:00:00+00:00'::timestamptz, false
WHERE NOT EXISTS (
  SELECT 1 FROM wallet_ledger wl
  WHERE wl.merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND wl.dedup_key = 'jorakay-orphan-6563f123ffd7efcec974f172'
);;
DO $v$
DECLARE w numeric; l numeric;
BEGIN
  SELECT points_balance INTO w FROM user_wallet WHERE user_id = '14d69324-43b1-4968-ac10-6d036faa3eb6'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid;
  SELECT coalesce(sum(deductible_balance),0) INTO l FROM wallet_ledger
    WHERE user_id = '14d69324-43b1-4968-ac10-6d036faa3eb6'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid
      AND currency = 'points' AND transaction_type = 'earn';
  IF abs(w - l) > 0.01 THEN
    RAISE EXCEPTION 'post-apply invariant user % wallet % lots %', '14d69324-43b1-4968-ac10-6d036faa3eb6', w, l;
  END IF;
END $v$;
COMMIT;
BEGIN;
UPDATE user_wallet SET points_balance = 10670.0 WHERE user_id = '15fd0ace-9201-4d3b-9329-cec5c18cfee8'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid;
DO $v$
DECLARE w numeric; l numeric;
BEGIN
  SELECT points_balance INTO w FROM user_wallet WHERE user_id = '15fd0ace-9201-4d3b-9329-cec5c18cfee8'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid;
  SELECT coalesce(sum(deductible_balance),0) INTO l FROM wallet_ledger
    WHERE user_id = '15fd0ace-9201-4d3b-9329-cec5c18cfee8'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid
      AND currency = 'points' AND transaction_type = 'earn';
  IF abs(w - l) > 0.01 THEN
    RAISE EXCEPTION 'post-apply invariant user % wallet % lots %', '15fd0ace-9201-4d3b-9329-cec5c18cfee8', w, l;
  END IF;
END $v$;
COMMIT;
BEGIN;
UPDATE wallet_ledger SET deductible_balance = 139.0 WHERE id = '1be6d8c8-4dc4-4e63-98cc-5ac05a06b500'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = '167d1b6d-fa75-4924-9cfe-459eb8a1128d'::uuid;
UPDATE wallet_ledger SET deductible_balance = 84.0 WHERE id = '59aa8f87-3476-43f9-b0a8-51c0073b27a9'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = '167d1b6d-fa75-4924-9cfe-459eb8a1128d'::uuid;
UPDATE wallet_ledger SET deductible_balance = 137.0 WHERE id = '69aa7c2f-1f7a-4305-832f-7feafcce6c56'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = '167d1b6d-fa75-4924-9cfe-459eb8a1128d'::uuid;
UPDATE wallet_ledger SET deductible_balance = 40.0 WHERE id = 'bea55ad8-38da-440e-979d-18ac77b14976'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = '167d1b6d-fa75-4924-9cfe-459eb8a1128d'::uuid;
UPDATE wallet_ledger SET deductible_balance = 37.0 WHERE id = '1df56545-4324-4c2a-9cdb-7a5ba9db0d7b'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = '167d1b6d-fa75-4924-9cfe-459eb8a1128d'::uuid;
DO $v$
DECLARE w numeric; l numeric;
BEGIN
  SELECT points_balance INTO w FROM user_wallet WHERE user_id = '167d1b6d-fa75-4924-9cfe-459eb8a1128d'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid;
  SELECT coalesce(sum(deductible_balance),0) INTO l FROM wallet_ledger
    WHERE user_id = '167d1b6d-fa75-4924-9cfe-459eb8a1128d'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid
      AND currency = 'points' AND transaction_type = 'earn';
  IF abs(w - l) > 0.01 THEN
    RAISE EXCEPTION 'post-apply invariant user % wallet % lots %', '167d1b6d-fa75-4924-9cfe-459eb8a1128d', w, l;
  END IF;
END $v$;
COMMIT;
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
BEGIN;
UPDATE wallet_ledger SET deductible_balance = 0.0 WHERE id = '80350bf4-0e37-4210-93a4-0691d4f90b5c'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = '16b6dfbd-2f08-4f25-979f-b795f5d6f1ff'::uuid;
UPDATE wallet_ledger SET deductible_balance = 0.0 WHERE id = 'ba25ddda-65b4-40c9-9e84-a5461c4a4daf'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = '16b6dfbd-2f08-4f25-979f-b795f5d6f1ff'::uuid;
DO $v$
DECLARE w numeric; l numeric;
BEGIN
  SELECT points_balance INTO w FROM user_wallet WHERE user_id = '16b6dfbd-2f08-4f25-979f-b795f5d6f1ff'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid;
  SELECT coalesce(sum(deductible_balance),0) INTO l FROM wallet_ledger
    WHERE user_id = '16b6dfbd-2f08-4f25-979f-b795f5d6f1ff'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid
      AND currency = 'points' AND transaction_type = 'earn';
  IF abs(w - l) > 0.01 THEN
    RAISE EXCEPTION 'post-apply invariant user % wallet % lots %', '16b6dfbd-2f08-4f25-979f-b795f5d6f1ff', w, l;
  END IF;
END $v$;
COMMIT;
BEGIN;
UPDATE wallet_ledger SET deductible_balance = 0.0 WHERE id = '3e68139a-3cf3-4a7f-82d8-62d5e01fa5b0'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = '17b5601d-c2b8-408a-b379-cb121051da29'::uuid;
UPDATE wallet_ledger SET deductible_balance = 0.0 WHERE id = 'a912a00d-9c8f-42e3-99e8-7d0bdb6f2610'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = '17b5601d-c2b8-408a-b379-cb121051da29'::uuid;
UPDATE wallet_ledger SET deductible_balance = 0.0 WHERE id = '5cd31692-0c41-480a-8264-7889d8ba255c'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = '17b5601d-c2b8-408a-b379-cb121051da29'::uuid;
UPDATE wallet_ledger SET deductible_balance = 2157.0 WHERE id = '7e185d93-1744-4856-b14b-3504490fc8f0'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = '17b5601d-c2b8-408a-b379-cb121051da29'::uuid;
DO $v$
DECLARE w numeric; l numeric;
BEGIN
  SELECT points_balance INTO w FROM user_wallet WHERE user_id = '17b5601d-c2b8-408a-b379-cb121051da29'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid;
  SELECT coalesce(sum(deductible_balance),0) INTO l FROM wallet_ledger
    WHERE user_id = '17b5601d-c2b8-408a-b379-cb121051da29'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid
      AND currency = 'points' AND transaction_type = 'earn';
  IF abs(w - l) > 0.01 THEN
    RAISE EXCEPTION 'post-apply invariant user % wallet % lots %', '17b5601d-c2b8-408a-b379-cb121051da29', w, l;
  END IF;
END $v$;
COMMIT;
BEGIN;
UPDATE wallet_ledger SET deductible_balance = 0.0 WHERE id = 'b9707c96-563d-4f25-90f5-fc2e05c56ec1'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = '17d52d2b-9325-479b-ba6b-f604f70c38e1'::uuid;
UPDATE wallet_ledger SET deductible_balance = 0.0 WHERE id = 'c59d6c63-9ce3-4170-8cec-0977cd8c31d8'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = '17d52d2b-9325-479b-ba6b-f604f70c38e1'::uuid;
UPDATE wallet_ledger SET deductible_balance = 16.0 WHERE id = '15e7dbf9-0f6e-42ce-bca6-bfc2b566b255'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = '17d52d2b-9325-479b-ba6b-f604f70c38e1'::uuid;
DO $v$
DECLARE w numeric; l numeric;
BEGIN
  SELECT points_balance INTO w FROM user_wallet WHERE user_id = '17d52d2b-9325-479b-ba6b-f604f70c38e1'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid;
  SELECT coalesce(sum(deductible_balance),0) INTO l FROM wallet_ledger
    WHERE user_id = '17d52d2b-9325-479b-ba6b-f604f70c38e1'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid
      AND currency = 'points' AND transaction_type = 'earn';
  IF abs(w - l) > 0.01 THEN
    RAISE EXCEPTION 'post-apply invariant user % wallet % lots %', '17d52d2b-9325-479b-ba6b-f604f70c38e1', w, l;
  END IF;
END $v$;
COMMIT;
BEGIN;
UPDATE wallet_ledger SET deductible_balance = 308.0 WHERE id = '50cc2499-6202-4401-b4c8-9463b307c6d3'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = '18ae7a19-0965-40dc-b165-2d1147b22ddc'::uuid;
UPDATE wallet_ledger SET deductible_balance = 604.0 WHERE id = '244a8d9a-596c-409d-883a-6bdf78e73bae'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = '18ae7a19-0965-40dc-b165-2d1147b22ddc'::uuid;
DO $v$
DECLARE w numeric; l numeric;
BEGIN
  SELECT points_balance INTO w FROM user_wallet WHERE user_id = '18ae7a19-0965-40dc-b165-2d1147b22ddc'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid;
  SELECT coalesce(sum(deductible_balance),0) INTO l FROM wallet_ledger
    WHERE user_id = '18ae7a19-0965-40dc-b165-2d1147b22ddc'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid
      AND currency = 'points' AND transaction_type = 'earn';
  IF abs(w - l) > 0.01 THEN
    RAISE EXCEPTION 'post-apply invariant user % wallet % lots %', '18ae7a19-0965-40dc-b165-2d1147b22ddc', w, l;
  END IF;
END $v$;
COMMIT;
BEGIN;
UPDATE wallet_ledger SET deductible_balance = 0.0 WHERE id = '45421af4-337b-4a6d-ae1b-cf442626f968'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = '192f7286-372e-439c-8659-5a9d0c08d89a'::uuid;
UPDATE wallet_ledger SET deductible_balance = 0.0 WHERE id = 'acfc85c4-d5ec-4312-a30f-569c376b9ade'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = '192f7286-372e-439c-8659-5a9d0c08d89a'::uuid;
UPDATE wallet_ledger SET deductible_balance = 0.0 WHERE id = 'e89606d0-fe5f-403e-8c62-550ba546c520'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = '192f7286-372e-439c-8659-5a9d0c08d89a'::uuid;
UPDATE wallet_ledger SET deductible_balance = 0.0 WHERE id = '629b69c9-f835-4707-9bf9-647393a98654'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = '192f7286-372e-439c-8659-5a9d0c08d89a'::uuid;
UPDATE wallet_ledger SET deductible_balance = 0.0 WHERE id = 'dd97a121-00ee-40d1-8648-9975e3d6508c'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = '192f7286-372e-439c-8659-5a9d0c08d89a'::uuid;
UPDATE wallet_ledger SET deductible_balance = 0.0 WHERE id = '74a5be13-3fd1-443c-a5cc-17f2af04ec59'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = '192f7286-372e-439c-8659-5a9d0c08d89a'::uuid;
UPDATE wallet_ledger SET deductible_balance = 0.0 WHERE id = 'dfe251c7-cce0-4f8d-805e-ecaa379754e2'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = '192f7286-372e-439c-8659-5a9d0c08d89a'::uuid;
UPDATE wallet_ledger SET deductible_balance = 19.0 WHERE id = 'ba58ee98-cb8b-4c84-9ac7-880b29754a57'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = '192f7286-372e-439c-8659-5a9d0c08d89a'::uuid;
UPDATE wallet_ledger SET deductible_balance = 244.0 WHERE id = '6cd78084-dd83-4bdf-a642-8bf1fd39ca2a'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = '192f7286-372e-439c-8659-5a9d0c08d89a'::uuid;
DO $v$
DECLARE w numeric; l numeric;
BEGIN
  SELECT points_balance INTO w FROM user_wallet WHERE user_id = '192f7286-372e-439c-8659-5a9d0c08d89a'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid;
  SELECT coalesce(sum(deductible_balance),0) INTO l FROM wallet_ledger
    WHERE user_id = '192f7286-372e-439c-8659-5a9d0c08d89a'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid
      AND currency = 'points' AND transaction_type = 'earn';
  IF abs(w - l) > 0.01 THEN
    RAISE EXCEPTION 'post-apply invariant user % wallet % lots %', '192f7286-372e-439c-8659-5a9d0c08d89a', w, l;
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
  '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid, '1a0a3ce3-2873-4f06-9e1a-f0f5139fbc55'::uuid,   'points'::currency, 'earn'::currency_transaction_type,
  'base'::currency_component,
  50, 50, 50,
  50, 50,
  'manual'::wallet_transaction_source_type, 'Legacy wallet balance', '{"backfill": "jorakay_wallet_lot_drift_20260912", "reason": "orphan_wallet_no_points_ledger"}'::jsonb,
  NULL, NULL,
  '1a0a3ce3-2873-4f06-9e1a-f0f5139fbc55', 'jorakay-orphan-65b1c02512e71882a727eb8c', '2026-06-15T00:00:00+00:00'::timestamptz, false
WHERE NOT EXISTS (
  SELECT 1 FROM wallet_ledger wl
  WHERE wl.merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND wl.dedup_key = 'jorakay-orphan-65b1c02512e71882a727eb8c'
);;
DO $v$
DECLARE w numeric; l numeric;
BEGIN
  SELECT points_balance INTO w FROM user_wallet WHERE user_id = '1a0a3ce3-2873-4f06-9e1a-f0f5139fbc55'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid;
  SELECT coalesce(sum(deductible_balance),0) INTO l FROM wallet_ledger
    WHERE user_id = '1a0a3ce3-2873-4f06-9e1a-f0f5139fbc55'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid
      AND currency = 'points' AND transaction_type = 'earn';
  IF abs(w - l) > 0.01 THEN
    RAISE EXCEPTION 'post-apply invariant user % wallet % lots %', '1a0a3ce3-2873-4f06-9e1a-f0f5139fbc55', w, l;
  END IF;
END $v$;
COMMIT;
