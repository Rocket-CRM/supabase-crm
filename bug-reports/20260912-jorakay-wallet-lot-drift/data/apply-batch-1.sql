BEGIN;
UPDATE wallet_ledger SET deductible_balance = 500.0 WHERE id = '05891ec5-94bc-432e-8807-a46614e95bd5'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = '1eb8999f-342f-4125-8270-daa7e3b1d570'::uuid;
DO $v$
DECLARE w numeric; l numeric;
BEGIN
  SELECT points_balance INTO w FROM user_wallet WHERE user_id = '1eb8999f-342f-4125-8270-daa7e3b1d570'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid;
  SELECT coalesce(sum(deductible_balance),0) INTO l FROM wallet_ledger
    WHERE user_id = '1eb8999f-342f-4125-8270-daa7e3b1d570'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid
      AND currency = 'points' AND transaction_type = 'earn';
  IF abs(w - l) > 0.01 THEN
    RAISE EXCEPTION 'post-apply invariant user % wallet % lots %', '1eb8999f-342f-4125-8270-daa7e3b1d570', w, l;
  END IF;
END $v$;
COMMIT;
BEGIN;
UPDATE wallet_ledger SET deductible_balance = 0.0 WHERE id = '7abd7320-eb69-42d1-9436-ecf8e4fb42c6'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = '1ffbad86-6119-47b3-b152-77f4713a0f48'::uuid;
DO $v$
DECLARE w numeric; l numeric;
BEGIN
  SELECT points_balance INTO w FROM user_wallet WHERE user_id = '1ffbad86-6119-47b3-b152-77f4713a0f48'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid;
  SELECT coalesce(sum(deductible_balance),0) INTO l FROM wallet_ledger
    WHERE user_id = '1ffbad86-6119-47b3-b152-77f4713a0f48'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid
      AND currency = 'points' AND transaction_type = 'earn';
  IF abs(w - l) > 0.01 THEN
    RAISE EXCEPTION 'post-apply invariant user % wallet % lots %', '1ffbad86-6119-47b3-b152-77f4713a0f48', w, l;
  END IF;
END $v$;
COMMIT;
BEGIN;
UPDATE wallet_ledger SET deductible_balance = 10.0 WHERE id = '9c84c260-63c7-4e59-b42d-48df3044774f'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = '225436c6-e6e4-4f31-9725-29d648797207'::uuid;
DO $v$
DECLARE w numeric; l numeric;
BEGIN
  SELECT points_balance INTO w FROM user_wallet WHERE user_id = '225436c6-e6e4-4f31-9725-29d648797207'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid;
  SELECT coalesce(sum(deductible_balance),0) INTO l FROM wallet_ledger
    WHERE user_id = '225436c6-e6e4-4f31-9725-29d648797207'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid
      AND currency = 'points' AND transaction_type = 'earn';
  IF abs(w - l) > 0.01 THEN
    RAISE EXCEPTION 'post-apply invariant user % wallet % lots %', '225436c6-e6e4-4f31-9725-29d648797207', w, l;
  END IF;
END $v$;
COMMIT;
BEGIN;
UPDATE wallet_ledger SET deductible_balance = 521.0 WHERE id = '048e2273-5624-4e0f-9cbd-723b82e4ccfa'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = '23637399-4191-4f50-8ee4-a00a37d4badd'::uuid;
UPDATE wallet_ledger SET deductible_balance = 159.0 WHERE id = '1f7ce012-3aa9-4d8e-8854-2914122d218c'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = '23637399-4191-4f50-8ee4-a00a37d4badd'::uuid;
UPDATE wallet_ledger SET deductible_balance = 384.0 WHERE id = 'fd421f52-56c2-4f39-99e2-bf5d1319657d'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = '23637399-4191-4f50-8ee4-a00a37d4badd'::uuid;
UPDATE wallet_ledger SET deductible_balance = 900.0 WHERE id = '87b19a8b-adbf-48eb-b82c-7248fde67ec5'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = '23637399-4191-4f50-8ee4-a00a37d4badd'::uuid;
UPDATE wallet_ledger SET deductible_balance = 50.0 WHERE id = 'd49cb155-a17a-4a76-8f2e-05949ab90bc0'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = '23637399-4191-4f50-8ee4-a00a37d4badd'::uuid;
UPDATE wallet_ledger SET deductible_balance = 75.0 WHERE id = '0bbe9c6b-e02f-46f7-9c2e-16362d169497'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = '23637399-4191-4f50-8ee4-a00a37d4badd'::uuid;
UPDATE wallet_ledger SET deductible_balance = 79.0 WHERE id = '6ee185ef-01a9-4e02-a9b6-cddb8b4cb95c'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = '23637399-4191-4f50-8ee4-a00a37d4badd'::uuid;
UPDATE wallet_ledger SET deductible_balance = 720.0 WHERE id = 'aac7f559-1fa1-45cb-bb1f-08fb02f4a41a'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = '23637399-4191-4f50-8ee4-a00a37d4badd'::uuid;
DO $v$
DECLARE w numeric; l numeric;
BEGIN
  SELECT points_balance INTO w FROM user_wallet WHERE user_id = '23637399-4191-4f50-8ee4-a00a37d4badd'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid;
  SELECT coalesce(sum(deductible_balance),0) INTO l FROM wallet_ledger
    WHERE user_id = '23637399-4191-4f50-8ee4-a00a37d4badd'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid
      AND currency = 'points' AND transaction_type = 'earn';
  IF abs(w - l) > 0.01 THEN
    RAISE EXCEPTION 'post-apply invariant user % wallet % lots %', '23637399-4191-4f50-8ee4-a00a37d4badd', w, l;
  END IF;
END $v$;
COMMIT;
BEGIN;
UPDATE wallet_ledger SET deductible_balance = 10.0 WHERE id = '2c2b54e6-2dce-42b7-9f1e-b36117f2a525'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = '238eb951-801d-4cb7-945c-2f1556e464bf'::uuid;
UPDATE wallet_ledger SET deductible_balance = 3.0 WHERE id = '76b9e7b3-3811-462a-8476-5048c430278c'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = '238eb951-801d-4cb7-945c-2f1556e464bf'::uuid;
UPDATE wallet_ledger SET deductible_balance = 7.0 WHERE id = 'e3a32674-c7b4-4f8c-b4f3-d291060726d4'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = '238eb951-801d-4cb7-945c-2f1556e464bf'::uuid;
UPDATE wallet_ledger SET deductible_balance = 16.0 WHERE id = '17e78163-6c57-45f9-b9de-cba273fe425a'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = '238eb951-801d-4cb7-945c-2f1556e464bf'::uuid;
UPDATE wallet_ledger SET deductible_balance = 7.0 WHERE id = 'f8ee567d-335e-4a7b-bc5d-855dd4e1aeb2'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = '238eb951-801d-4cb7-945c-2f1556e464bf'::uuid;
UPDATE wallet_ledger SET deductible_balance = 9.0 WHERE id = '321ec738-6a06-4b89-84a7-f786a6d00f34'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = '238eb951-801d-4cb7-945c-2f1556e464bf'::uuid;
UPDATE wallet_ledger SET deductible_balance = 1.0 WHERE id = 'a620b59a-3683-408e-af93-5b5d167405b8'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = '238eb951-801d-4cb7-945c-2f1556e464bf'::uuid;
UPDATE wallet_ledger SET deductible_balance = 1.0 WHERE id = '10edf30f-d4c9-45a7-b531-e9c5da48d06b'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = '238eb951-801d-4cb7-945c-2f1556e464bf'::uuid;
UPDATE wallet_ledger SET deductible_balance = 1.0 WHERE id = 'd1c7f704-ecdb-48d4-99d0-45c11254950a'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = '238eb951-801d-4cb7-945c-2f1556e464bf'::uuid;
UPDATE wallet_ledger SET deductible_balance = 1.0 WHERE id = '1a24976a-4792-46b6-9112-55dcb087878e'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = '238eb951-801d-4cb7-945c-2f1556e464bf'::uuid;
UPDATE wallet_ledger SET deductible_balance = 8.0 WHERE id = '0f9a52e6-87ca-4b8e-9a97-3d2f4af709bb'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = '238eb951-801d-4cb7-945c-2f1556e464bf'::uuid;
UPDATE wallet_ledger SET deductible_balance = 5.0 WHERE id = 'e34aeeb9-be97-4e49-ab3a-f491cd2cd30f'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = '238eb951-801d-4cb7-945c-2f1556e464bf'::uuid;
UPDATE wallet_ledger SET deductible_balance = 1.0 WHERE id = 'cc5dfee2-8cbf-453a-9437-b331b00802b7'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = '238eb951-801d-4cb7-945c-2f1556e464bf'::uuid;
UPDATE wallet_ledger SET deductible_balance = 8.0 WHERE id = '45fe95b2-80f0-462c-8569-b29a333167f8'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = '238eb951-801d-4cb7-945c-2f1556e464bf'::uuid;
UPDATE wallet_ledger SET deductible_balance = 3.0 WHERE id = '69ab31cb-8615-4359-8fb5-6d77e4dc57d4'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = '238eb951-801d-4cb7-945c-2f1556e464bf'::uuid;
UPDATE wallet_ledger SET deductible_balance = 2.0 WHERE id = '5ad2632e-90de-4673-9981-48b5bbd633c0'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = '238eb951-801d-4cb7-945c-2f1556e464bf'::uuid;
UPDATE wallet_ledger SET deductible_balance = 9.0 WHERE id = '63c3b207-feca-4321-974e-17dedb4491a6'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = '238eb951-801d-4cb7-945c-2f1556e464bf'::uuid;
UPDATE wallet_ledger SET deductible_balance = 1.0 WHERE id = 'aabc8e9b-4b1f-48b8-951a-019a52cb039e'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = '238eb951-801d-4cb7-945c-2f1556e464bf'::uuid;
UPDATE wallet_ledger SET deductible_balance = 11.0 WHERE id = 'b5377b10-91d9-4610-a69b-a6de289af0fa'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = '238eb951-801d-4cb7-945c-2f1556e464bf'::uuid;
UPDATE wallet_ledger SET deductible_balance = 3.0 WHERE id = '277844c3-91ff-41c9-80eb-1d715e0b4806'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = '238eb951-801d-4cb7-945c-2f1556e464bf'::uuid;
UPDATE wallet_ledger SET deductible_balance = 71.0 WHERE id = 'a0a6e827-95ee-4aff-b191-483f97b6fd85'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = '238eb951-801d-4cb7-945c-2f1556e464bf'::uuid;
UPDATE wallet_ledger SET deductible_balance = 37.0 WHERE id = 'f0d7afa0-d616-4f15-bb7b-2e66909652c4'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = '238eb951-801d-4cb7-945c-2f1556e464bf'::uuid;
UPDATE wallet_ledger SET deductible_balance = 23.0 WHERE id = '54198f5b-ea35-47ec-a9b3-9bb9689c4415'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = '238eb951-801d-4cb7-945c-2f1556e464bf'::uuid;
UPDATE wallet_ledger SET deductible_balance = 5.0 WHERE id = '38dc3223-d0ae-4c54-bd25-fd2402cb6563'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = '238eb951-801d-4cb7-945c-2f1556e464bf'::uuid;
UPDATE wallet_ledger SET deductible_balance = 32.0 WHERE id = '3f3e502b-9825-45b8-902c-3393f7e9e930'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = '238eb951-801d-4cb7-945c-2f1556e464bf'::uuid;
UPDATE wallet_ledger SET deductible_balance = 10.0 WHERE id = '57548a4b-3148-45cd-973f-e2578b2dcc26'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = '238eb951-801d-4cb7-945c-2f1556e464bf'::uuid;
UPDATE wallet_ledger SET deductible_balance = 9.0 WHERE id = 'eed940da-795e-4c16-9e91-c9e77222713e'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = '238eb951-801d-4cb7-945c-2f1556e464bf'::uuid;
UPDATE wallet_ledger SET deductible_balance = 25.0 WHERE id = '28accfcd-7c51-4bf0-a776-a1dc95242236'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = '238eb951-801d-4cb7-945c-2f1556e464bf'::uuid;
UPDATE wallet_ledger SET deductible_balance = 4.0 WHERE id = '1e0986d3-19b7-49f6-89fe-2291be42d5f1'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = '238eb951-801d-4cb7-945c-2f1556e464bf'::uuid;
UPDATE wallet_ledger SET deductible_balance = 52.0 WHERE id = '4a1041e8-b620-4aa4-b1fd-1e9e08ce5e07'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = '238eb951-801d-4cb7-945c-2f1556e464bf'::uuid;
UPDATE wallet_ledger SET deductible_balance = 85.0 WHERE id = 'f0fb77e2-ed24-46b7-872c-310a72464264'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = '238eb951-801d-4cb7-945c-2f1556e464bf'::uuid;
UPDATE wallet_ledger SET deductible_balance = 5.0 WHERE id = '1d0f9696-cc1d-4ba2-b402-9bfaeec29338'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = '238eb951-801d-4cb7-945c-2f1556e464bf'::uuid;
DO $v$
DECLARE w numeric; l numeric;
BEGIN
  SELECT points_balance INTO w FROM user_wallet WHERE user_id = '238eb951-801d-4cb7-945c-2f1556e464bf'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid;
  SELECT coalesce(sum(deductible_balance),0) INTO l FROM wallet_ledger
    WHERE user_id = '238eb951-801d-4cb7-945c-2f1556e464bf'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid
      AND currency = 'points' AND transaction_type = 'earn';
  IF abs(w - l) > 0.01 THEN
    RAISE EXCEPTION 'post-apply invariant user % wallet % lots %', '238eb951-801d-4cb7-945c-2f1556e464bf', w, l;
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
  '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid, '242404b5-772c-4820-acf0-fea8df090da1'::uuid,   'points'::currency, 'earn'::currency_transaction_type,
  'base'::currency_component,
  50, 50, 50,
  50, 50,
  'manual'::wallet_transaction_source_type, 'Legacy wallet balance', '{"backfill": "jorakay_wallet_lot_drift_20260912", "reason": "orphan_wallet_no_points_ledger"}'::jsonb,
  NULL, NULL,
  '242404b5-772c-4820-acf0-fea8df090da1', 'jorakay-orphan-65b1be9912e71882a7271072', '2026-06-15T00:00:00+00:00'::timestamptz, false
WHERE NOT EXISTS (
  SELECT 1 FROM wallet_ledger wl
  WHERE wl.merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND wl.dedup_key = 'jorakay-orphan-65b1be9912e71882a7271072'
);;
DO $v$
DECLARE w numeric; l numeric;
BEGIN
  SELECT points_balance INTO w FROM user_wallet WHERE user_id = '242404b5-772c-4820-acf0-fea8df090da1'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid;
  SELECT coalesce(sum(deductible_balance),0) INTO l FROM wallet_ledger
    WHERE user_id = '242404b5-772c-4820-acf0-fea8df090da1'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid
      AND currency = 'points' AND transaction_type = 'earn';
  IF abs(w - l) > 0.01 THEN
    RAISE EXCEPTION 'post-apply invariant user % wallet % lots %', '242404b5-772c-4820-acf0-fea8df090da1', w, l;
  END IF;
END $v$;
COMMIT;
BEGIN;
UPDATE wallet_ledger SET deductible_balance = 2460.0 WHERE id = '6b22dc38-c5e8-4770-b138-b33ee3c9b21e'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = '24c8f546-2cc2-481f-9d3f-625a76f5f85d'::uuid;
UPDATE wallet_ledger SET deductible_balance = 54.0 WHERE id = '923925bb-5d34-4bf6-aa2a-cfc2bade17fb'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = '24c8f546-2cc2-481f-9d3f-625a76f5f85d'::uuid;
DO $v$
DECLARE w numeric; l numeric;
BEGIN
  SELECT points_balance INTO w FROM user_wallet WHERE user_id = '24c8f546-2cc2-481f-9d3f-625a76f5f85d'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid;
  SELECT coalesce(sum(deductible_balance),0) INTO l FROM wallet_ledger
    WHERE user_id = '24c8f546-2cc2-481f-9d3f-625a76f5f85d'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid
      AND currency = 'points' AND transaction_type = 'earn';
  IF abs(w - l) > 0.01 THEN
    RAISE EXCEPTION 'post-apply invariant user % wallet % lots %', '24c8f546-2cc2-481f-9d3f-625a76f5f85d', w, l;
  END IF;
END $v$;
COMMIT;
BEGIN;
UPDATE wallet_ledger SET deductible_balance = 103.0 WHERE id = '2f4ea2d7-8ebf-48d4-846c-c47163b05c79'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = '2a301e35-7fcd-4023-a36e-df3b57b5c563'::uuid;
DO $v$
DECLARE w numeric; l numeric;
BEGIN
  SELECT points_balance INTO w FROM user_wallet WHERE user_id = '2a301e35-7fcd-4023-a36e-df3b57b5c563'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid;
  SELECT coalesce(sum(deductible_balance),0) INTO l FROM wallet_ledger
    WHERE user_id = '2a301e35-7fcd-4023-a36e-df3b57b5c563'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid
      AND currency = 'points' AND transaction_type = 'earn';
  IF abs(w - l) > 0.01 THEN
    RAISE EXCEPTION 'post-apply invariant user % wallet % lots %', '2a301e35-7fcd-4023-a36e-df3b57b5c563', w, l;
  END IF;
END $v$;
COMMIT;
BEGIN;
UPDATE wallet_ledger SET deductible_balance = 0.0 WHERE id = '172fd7f2-b870-41e2-b216-83d20f37b5f3'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = '2bec1b40-59f3-437e-837c-8efbeb58b416'::uuid;
UPDATE wallet_ledger SET deductible_balance = 0.0 WHERE id = 'ef33603d-9d3c-4a6f-81d8-8e6d7aa68934'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = '2bec1b40-59f3-437e-837c-8efbeb58b416'::uuid;
UPDATE wallet_ledger SET deductible_balance = 0.0 WHERE id = 'aa675036-6eec-467e-8fc3-529e65454c09'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = '2bec1b40-59f3-437e-837c-8efbeb58b416'::uuid;
UPDATE wallet_ledger SET deductible_balance = 210.0 WHERE id = '31a51a92-367d-4345-a87b-801ee6e05261'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = '2bec1b40-59f3-437e-837c-8efbeb58b416'::uuid;
DO $v$
DECLARE w numeric; l numeric;
BEGIN
  SELECT points_balance INTO w FROM user_wallet WHERE user_id = '2bec1b40-59f3-437e-837c-8efbeb58b416'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid;
  SELECT coalesce(sum(deductible_balance),0) INTO l FROM wallet_ledger
    WHERE user_id = '2bec1b40-59f3-437e-837c-8efbeb58b416'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid
      AND currency = 'points' AND transaction_type = 'earn';
  IF abs(w - l) > 0.01 THEN
    RAISE EXCEPTION 'post-apply invariant user % wallet % lots %', '2bec1b40-59f3-437e-837c-8efbeb58b416', w, l;
  END IF;
END $v$;
COMMIT;
BEGIN;
UPDATE wallet_ledger SET deductible_balance = 0.0 WHERE id = 'd30b928e-a07d-4ce5-997e-5538814480a4'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = '2d8a6fd7-32ee-47c9-8a2d-2b2b672a9c7e'::uuid;
DO $v$
DECLARE w numeric; l numeric;
BEGIN
  SELECT points_balance INTO w FROM user_wallet WHERE user_id = '2d8a6fd7-32ee-47c9-8a2d-2b2b672a9c7e'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid;
  SELECT coalesce(sum(deductible_balance),0) INTO l FROM wallet_ledger
    WHERE user_id = '2d8a6fd7-32ee-47c9-8a2d-2b2b672a9c7e'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid
      AND currency = 'points' AND transaction_type = 'earn';
  IF abs(w - l) > 0.01 THEN
    RAISE EXCEPTION 'post-apply invariant user % wallet % lots %', '2d8a6fd7-32ee-47c9-8a2d-2b2b672a9c7e', w, l;
  END IF;
END $v$;
COMMIT;
BEGIN;
UPDATE wallet_ledger SET deductible_balance = 52.0 WHERE id = '5746807e-1125-44f1-b231-b8854682138d'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = '2e2b645b-4a92-4f2f-80cc-23af189d7808'::uuid;
UPDATE wallet_ledger SET deductible_balance = 52.0 WHERE id = '1d8fb514-1e35-4d61-9bf9-9f507cf924c4'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = '2e2b645b-4a92-4f2f-80cc-23af189d7808'::uuid;
UPDATE wallet_ledger SET deductible_balance = 6.0 WHERE id = 'b8bc9b99-c38d-4452-8108-b00ee8e2ebd1'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = '2e2b645b-4a92-4f2f-80cc-23af189d7808'::uuid;
DO $v$
DECLARE w numeric; l numeric;
BEGIN
  SELECT points_balance INTO w FROM user_wallet WHERE user_id = '2e2b645b-4a92-4f2f-80cc-23af189d7808'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid;
  SELECT coalesce(sum(deductible_balance),0) INTO l FROM wallet_ledger
    WHERE user_id = '2e2b645b-4a92-4f2f-80cc-23af189d7808'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid
      AND currency = 'points' AND transaction_type = 'earn';
  IF abs(w - l) > 0.01 THEN
    RAISE EXCEPTION 'post-apply invariant user % wallet % lots %', '2e2b645b-4a92-4f2f-80cc-23af189d7808', w, l;
  END IF;
END $v$;
COMMIT;
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
BEGIN;
UPDATE wallet_ledger SET deductible_balance = 3415.0 WHERE id = '7edfb541-5a36-45e1-b03a-a2f10e9c293c'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = '2e9794f1-5f7b-4e41-ab8d-43e6b2c03779'::uuid;
DO $v$
DECLARE w numeric; l numeric;
BEGIN
  SELECT points_balance INTO w FROM user_wallet WHERE user_id = '2e9794f1-5f7b-4e41-ab8d-43e6b2c03779'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid;
  SELECT coalesce(sum(deductible_balance),0) INTO l FROM wallet_ledger
    WHERE user_id = '2e9794f1-5f7b-4e41-ab8d-43e6b2c03779'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid
      AND currency = 'points' AND transaction_type = 'earn';
  IF abs(w - l) > 0.01 THEN
    RAISE EXCEPTION 'post-apply invariant user % wallet % lots %', '2e9794f1-5f7b-4e41-ab8d-43e6b2c03779', w, l;
  END IF;
END $v$;
COMMIT;
BEGIN;
UPDATE wallet_ledger SET deductible_balance = 0.0 WHERE id = '4bfffadc-c114-4ff2-9001-6dffe6f44525'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = '31705816-258b-4edc-b26b-e4e645cc80df'::uuid;
UPDATE wallet_ledger SET deductible_balance = 0.0 WHERE id = 'e1edbf72-7d8e-40ee-8052-06024459a86e'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = '31705816-258b-4edc-b26b-e4e645cc80df'::uuid;
UPDATE wallet_ledger SET deductible_balance = 0.0 WHERE id = '6a8a943a-de68-48fb-b693-dcf133f7e8d0'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = '31705816-258b-4edc-b26b-e4e645cc80df'::uuid;
UPDATE wallet_ledger SET deductible_balance = 0.0 WHERE id = '82ef18e8-66fd-43e1-8541-21bd8758c3ef'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = '31705816-258b-4edc-b26b-e4e645cc80df'::uuid;
UPDATE wallet_ledger SET deductible_balance = 0.0 WHERE id = '96b6a316-0960-47e1-adec-d31c087535bf'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = '31705816-258b-4edc-b26b-e4e645cc80df'::uuid;
UPDATE wallet_ledger SET deductible_balance = 0.0 WHERE id = '2d55ad16-735e-41a4-8849-58c39cbfea6e'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = '31705816-258b-4edc-b26b-e4e645cc80df'::uuid;
UPDATE wallet_ledger SET deductible_balance = 436.0 WHERE id = 'e58343d9-4321-433d-b318-bcd36d73cb7c'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = '31705816-258b-4edc-b26b-e4e645cc80df'::uuid;
DO $v$
DECLARE w numeric; l numeric;
BEGIN
  SELECT points_balance INTO w FROM user_wallet WHERE user_id = '31705816-258b-4edc-b26b-e4e645cc80df'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid;
  SELECT coalesce(sum(deductible_balance),0) INTO l FROM wallet_ledger
    WHERE user_id = '31705816-258b-4edc-b26b-e4e645cc80df'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid
      AND currency = 'points' AND transaction_type = 'earn';
  IF abs(w - l) > 0.01 THEN
    RAISE EXCEPTION 'post-apply invariant user % wallet % lots %', '31705816-258b-4edc-b26b-e4e645cc80df', w, l;
  END IF;
END $v$;
COMMIT;
BEGIN;
UPDATE wallet_ledger SET deductible_balance = 0.0 WHERE id = '71a80b5d-d614-40dd-a909-ea76a0aa45cd'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = '31ea3461-fbd5-4321-a642-ddde2c15e2e9'::uuid;
UPDATE wallet_ledger SET deductible_balance = 0.0 WHERE id = '39ce86af-5f44-4904-aa9a-97003418bb28'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = '31ea3461-fbd5-4321-a642-ddde2c15e2e9'::uuid;
UPDATE wallet_ledger SET deductible_balance = 0.0 WHERE id = '9d622025-2f4b-4659-a2fa-d5860fd58c4f'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = '31ea3461-fbd5-4321-a642-ddde2c15e2e9'::uuid;
UPDATE wallet_ledger SET deductible_balance = 0.0 WHERE id = 'e527ea57-1a0d-49db-b487-039b9a2cf7de'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = '31ea3461-fbd5-4321-a642-ddde2c15e2e9'::uuid;
UPDATE wallet_ledger SET deductible_balance = 65.0 WHERE id = 'ee35a692-dcae-4c5d-84bf-61e2f2e2adda'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = '31ea3461-fbd5-4321-a642-ddde2c15e2e9'::uuid;
DO $v$
DECLARE w numeric; l numeric;
BEGIN
  SELECT points_balance INTO w FROM user_wallet WHERE user_id = '31ea3461-fbd5-4321-a642-ddde2c15e2e9'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid;
  SELECT coalesce(sum(deductible_balance),0) INTO l FROM wallet_ledger
    WHERE user_id = '31ea3461-fbd5-4321-a642-ddde2c15e2e9'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid
      AND currency = 'points' AND transaction_type = 'earn';
  IF abs(w - l) > 0.01 THEN
    RAISE EXCEPTION 'post-apply invariant user % wallet % lots %', '31ea3461-fbd5-4321-a642-ddde2c15e2e9', w, l;
  END IF;
END $v$;
COMMIT;
BEGIN;
UPDATE wallet_ledger SET deductible_balance = 48.0 WHERE id = '6801b785-1c1c-4ebb-a811-17557d79091d'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = '366d7c0b-498b-483d-9965-f8dede770702'::uuid;
DO $v$
DECLARE w numeric; l numeric;
BEGIN
  SELECT points_balance INTO w FROM user_wallet WHERE user_id = '366d7c0b-498b-483d-9965-f8dede770702'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid;
  SELECT coalesce(sum(deductible_balance),0) INTO l FROM wallet_ledger
    WHERE user_id = '366d7c0b-498b-483d-9965-f8dede770702'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid
      AND currency = 'points' AND transaction_type = 'earn';
  IF abs(w - l) > 0.01 THEN
    RAISE EXCEPTION 'post-apply invariant user % wallet % lots %', '366d7c0b-498b-483d-9965-f8dede770702', w, l;
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
  '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid, '3673c7b3-86ac-4648-97b5-4bb916a05747'::uuid,   'points'::currency, 'earn'::currency_transaction_type,
  'base'::currency_component,
  50, 50, 50,
  50, 50,
  'manual'::wallet_transaction_source_type, 'Legacy wallet balance', '{"backfill": "jorakay_wallet_lot_drift_20260912", "reason": "orphan_wallet_no_points_ledger"}'::jsonb,
  NULL, NULL,
  '3673c7b3-86ac-4648-97b5-4bb916a05747', 'jorakay-orphan-65b1c2c812e71882a72a4356', '2026-06-15T00:00:00+00:00'::timestamptz, false
WHERE NOT EXISTS (
  SELECT 1 FROM wallet_ledger wl
  WHERE wl.merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND wl.dedup_key = 'jorakay-orphan-65b1c2c812e71882a72a4356'
);;
DO $v$
DECLARE w numeric; l numeric;
BEGIN
  SELECT points_balance INTO w FROM user_wallet WHERE user_id = '3673c7b3-86ac-4648-97b5-4bb916a05747'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid;
  SELECT coalesce(sum(deductible_balance),0) INTO l FROM wallet_ledger
    WHERE user_id = '3673c7b3-86ac-4648-97b5-4bb916a05747'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid
      AND currency = 'points' AND transaction_type = 'earn';
  IF abs(w - l) > 0.01 THEN
    RAISE EXCEPTION 'post-apply invariant user % wallet % lots %', '3673c7b3-86ac-4648-97b5-4bb916a05747', w, l;
  END IF;
END $v$;
COMMIT;
BEGIN;
UPDATE wallet_ledger SET deductible_balance = 75.0 WHERE id = 'bab24a83-83de-43aa-a93a-341c2474c38a'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = '373221c3-c3b2-4e82-ae2f-dc471078e042'::uuid;
DO $v$
DECLARE w numeric; l numeric;
BEGIN
  SELECT points_balance INTO w FROM user_wallet WHERE user_id = '373221c3-c3b2-4e82-ae2f-dc471078e042'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid;
  SELECT coalesce(sum(deductible_balance),0) INTO l FROM wallet_ledger
    WHERE user_id = '373221c3-c3b2-4e82-ae2f-dc471078e042'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid
      AND currency = 'points' AND transaction_type = 'earn';
  IF abs(w - l) > 0.01 THEN
    RAISE EXCEPTION 'post-apply invariant user % wallet % lots %', '373221c3-c3b2-4e82-ae2f-dc471078e042', w, l;
  END IF;
END $v$;
COMMIT;
BEGIN;
UPDATE wallet_ledger SET deductible_balance = 0.0 WHERE id = 'f714feef-66c0-41a7-8070-fdf05ba04883'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = '39e0724c-b6b9-4822-88fb-688156626a1e'::uuid;
UPDATE wallet_ledger SET deductible_balance = 0.0 WHERE id = '639c561b-c70c-49ee-b4e4-d42f64ad4df0'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = '39e0724c-b6b9-4822-88fb-688156626a1e'::uuid;
UPDATE wallet_ledger SET deductible_balance = 0.0 WHERE id = 'e87d75dc-4ea4-4bf5-828a-cc80fd642436'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = '39e0724c-b6b9-4822-88fb-688156626a1e'::uuid;
UPDATE wallet_ledger SET deductible_balance = 0.0 WHERE id = 'cd996414-66c6-40d1-a443-15b8970c6fbf'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = '39e0724c-b6b9-4822-88fb-688156626a1e'::uuid;
UPDATE wallet_ledger SET deductible_balance = 0.0 WHERE id = '9a9f9898-e131-4c59-99cd-dcad99765273'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = '39e0724c-b6b9-4822-88fb-688156626a1e'::uuid;
UPDATE wallet_ledger SET deductible_balance = 0.0 WHERE id = 'ff24aac0-db4a-4248-91c7-ac6fd4f9eb15'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = '39e0724c-b6b9-4822-88fb-688156626a1e'::uuid;
UPDATE wallet_ledger SET deductible_balance = 0.0 WHERE id = '1118445d-3f8c-4be1-bc45-8373c6129034'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = '39e0724c-b6b9-4822-88fb-688156626a1e'::uuid;
UPDATE wallet_ledger SET deductible_balance = 0.0 WHERE id = 'aafb09fb-d485-4e51-83b3-99e969b2c848'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = '39e0724c-b6b9-4822-88fb-688156626a1e'::uuid;
UPDATE wallet_ledger SET deductible_balance = 0.0 WHERE id = 'ea9ae894-926c-45dd-bb52-187679813cbf'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = '39e0724c-b6b9-4822-88fb-688156626a1e'::uuid;
DO $v$
DECLARE w numeric; l numeric;
BEGIN
  SELECT points_balance INTO w FROM user_wallet WHERE user_id = '39e0724c-b6b9-4822-88fb-688156626a1e'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid;
  SELECT coalesce(sum(deductible_balance),0) INTO l FROM wallet_ledger
    WHERE user_id = '39e0724c-b6b9-4822-88fb-688156626a1e'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid
      AND currency = 'points' AND transaction_type = 'earn';
  IF abs(w - l) > 0.01 THEN
    RAISE EXCEPTION 'post-apply invariant user % wallet % lots %', '39e0724c-b6b9-4822-88fb-688156626a1e', w, l;
  END IF;
END $v$;
COMMIT;
BEGIN;
UPDATE wallet_ledger SET deductible_balance = 0.0 WHERE id = '3e96ccef-664f-42db-ac60-5c27b9c61f00'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = '3ad89e23-176b-45f2-a538-7c3ebfb0f122'::uuid;
UPDATE wallet_ledger SET deductible_balance = 0.0 WHERE id = 'decc4f0f-9348-40cd-bb83-adc1c692928e'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = '3ad89e23-176b-45f2-a538-7c3ebfb0f122'::uuid;
UPDATE wallet_ledger SET deductible_balance = 0.0 WHERE id = '8de8bfce-1cd7-4620-9366-ba3888bc28b5'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = '3ad89e23-176b-45f2-a538-7c3ebfb0f122'::uuid;
UPDATE wallet_ledger SET deductible_balance = 1940.0 WHERE id = 'c76904bf-649d-493a-a7e3-9375b77fd3b6'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = '3ad89e23-176b-45f2-a538-7c3ebfb0f122'::uuid;
DO $v$
DECLARE w numeric; l numeric;
BEGIN
  SELECT points_balance INTO w FROM user_wallet WHERE user_id = '3ad89e23-176b-45f2-a538-7c3ebfb0f122'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid;
  SELECT coalesce(sum(deductible_balance),0) INTO l FROM wallet_ledger
    WHERE user_id = '3ad89e23-176b-45f2-a538-7c3ebfb0f122'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid
      AND currency = 'points' AND transaction_type = 'earn';
  IF abs(w - l) > 0.01 THEN
    RAISE EXCEPTION 'post-apply invariant user % wallet % lots %', '3ad89e23-176b-45f2-a538-7c3ebfb0f122', w, l;
  END IF;
END $v$;
COMMIT;
