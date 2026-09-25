BEGIN;
UPDATE wallet_ledger SET deductible_balance = 392.0 WHERE id = '3baac979-4022-4736-b69d-3d09746aa2ce'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = '3c2527ee-11dd-4a52-b5df-1f6f06e7ecec'::uuid;
UPDATE wallet_ledger SET deductible_balance = 1380.0 WHERE id = 'a5069e94-b2e1-4199-9e22-670490b7b8a0'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = '3c2527ee-11dd-4a52-b5df-1f6f06e7ecec'::uuid;
UPDATE wallet_ledger SET deductible_balance = 344.0 WHERE id = 'c50410ca-123c-4388-b4dd-471d707a439f'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = '3c2527ee-11dd-4a52-b5df-1f6f06e7ecec'::uuid;
DO $v$
DECLARE w numeric; l numeric;
BEGIN
  SELECT points_balance INTO w FROM user_wallet WHERE user_id = '3c2527ee-11dd-4a52-b5df-1f6f06e7ecec'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid;
  SELECT coalesce(sum(deductible_balance),0) INTO l FROM wallet_ledger
    WHERE user_id = '3c2527ee-11dd-4a52-b5df-1f6f06e7ecec'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid
      AND currency = 'points' AND transaction_type = 'earn';
  IF abs(w - l) > 0.01 THEN
    RAISE EXCEPTION 'post-apply invariant user % wallet % lots %', '3c2527ee-11dd-4a52-b5df-1f6f06e7ecec', w, l;
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
  '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid, '3d50e13c-a20a-4610-9e3b-e0d368739817'::uuid,   'points'::currency, 'earn'::currency_transaction_type,
  'base'::currency_component,
  50, 50, 50,
  50, 50,
  'manual'::wallet_transaction_source_type, 'Legacy wallet balance', '{"backfill": "jorakay_wallet_lot_drift_20260912", "reason": "orphan_wallet_no_points_ledger"}'::jsonb,
  NULL, NULL,
  '3d50e13c-a20a-4610-9e3b-e0d368739817', 'jorakay-orphan-65b1c02912e71882a727ec85', '2026-06-15T00:00:00+00:00'::timestamptz, false
WHERE NOT EXISTS (
  SELECT 1 FROM wallet_ledger wl
  WHERE wl.merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND wl.dedup_key = 'jorakay-orphan-65b1c02912e71882a727ec85'
);;
DO $v$
DECLARE w numeric; l numeric;
BEGIN
  SELECT points_balance INTO w FROM user_wallet WHERE user_id = '3d50e13c-a20a-4610-9e3b-e0d368739817'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid;
  SELECT coalesce(sum(deductible_balance),0) INTO l FROM wallet_ledger
    WHERE user_id = '3d50e13c-a20a-4610-9e3b-e0d368739817'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid
      AND currency = 'points' AND transaction_type = 'earn';
  IF abs(w - l) > 0.01 THEN
    RAISE EXCEPTION 'post-apply invariant user % wallet % lots %', '3d50e13c-a20a-4610-9e3b-e0d368739817', w, l;
  END IF;
END $v$;
COMMIT;
BEGIN;
UPDATE wallet_ledger SET deductible_balance = 76.0 WHERE id = 'a14a6122-080a-4c95-9ee6-212c9500ac37'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = '3e091fa2-39fd-4b08-b3f1-7a23325d3fe3'::uuid;
UPDATE wallet_ledger SET deductible_balance = 96.0 WHERE id = '7ec46e1c-7adb-4b9c-b2bf-27034a597437'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = '3e091fa2-39fd-4b08-b3f1-7a23325d3fe3'::uuid;
UPDATE wallet_ledger SET deductible_balance = 168.0 WHERE id = '10109a32-1e20-4cf2-ac4a-47d700d2b550'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = '3e091fa2-39fd-4b08-b3f1-7a23325d3fe3'::uuid;
UPDATE wallet_ledger SET deductible_balance = 307.0 WHERE id = '0f6722eb-3f4f-42a7-8a22-0ff840362830'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = '3e091fa2-39fd-4b08-b3f1-7a23325d3fe3'::uuid;
DO $v$
DECLARE w numeric; l numeric;
BEGIN
  SELECT points_balance INTO w FROM user_wallet WHERE user_id = '3e091fa2-39fd-4b08-b3f1-7a23325d3fe3'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid;
  SELECT coalesce(sum(deductible_balance),0) INTO l FROM wallet_ledger
    WHERE user_id = '3e091fa2-39fd-4b08-b3f1-7a23325d3fe3'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid
      AND currency = 'points' AND transaction_type = 'earn';
  IF abs(w - l) > 0.01 THEN
    RAISE EXCEPTION 'post-apply invariant user % wallet % lots %', '3e091fa2-39fd-4b08-b3f1-7a23325d3fe3', w, l;
  END IF;
END $v$;
COMMIT;
BEGIN;
UPDATE wallet_ledger SET deductible_balance = 491.0 WHERE id = '797402cd-416c-45d5-8fc4-1bc2866ebe23'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = '40d697c7-d1f1-4fe4-9aac-52868df23646'::uuid;
UPDATE wallet_ledger SET deductible_balance = 512.0 WHERE id = '9affb557-20fa-4dfd-946b-76d4f01f97eb'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = '40d697c7-d1f1-4fe4-9aac-52868df23646'::uuid;
DO $v$
DECLARE w numeric; l numeric;
BEGIN
  SELECT points_balance INTO w FROM user_wallet WHERE user_id = '40d697c7-d1f1-4fe4-9aac-52868df23646'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid;
  SELECT coalesce(sum(deductible_balance),0) INTO l FROM wallet_ledger
    WHERE user_id = '40d697c7-d1f1-4fe4-9aac-52868df23646'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid
      AND currency = 'points' AND transaction_type = 'earn';
  IF abs(w - l) > 0.01 THEN
    RAISE EXCEPTION 'post-apply invariant user % wallet % lots %', '40d697c7-d1f1-4fe4-9aac-52868df23646', w, l;
  END IF;
END $v$;
COMMIT;
BEGIN;
UPDATE wallet_ledger SET deductible_balance = 188.0 WHERE id = '29676bac-e4bc-4fb1-94f2-fbfa29fc930c'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = '41534223-f441-42ad-9ddf-ab7876e8555a'::uuid;
UPDATE wallet_ledger SET deductible_balance = 26.0 WHERE id = '73348721-cfa6-4d1c-9cf2-64920b42ea98'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = '41534223-f441-42ad-9ddf-ab7876e8555a'::uuid;
UPDATE wallet_ledger SET deductible_balance = 57.0 WHERE id = '5760343a-152e-4082-990d-6de2f98836d1'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = '41534223-f441-42ad-9ddf-ab7876e8555a'::uuid;
UPDATE wallet_ledger SET deductible_balance = 40.0 WHERE id = 'f3339076-e6ad-48e2-aa1d-cb2327d86d29'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = '41534223-f441-42ad-9ddf-ab7876e8555a'::uuid;
DO $v$
DECLARE w numeric; l numeric;
BEGIN
  SELECT points_balance INTO w FROM user_wallet WHERE user_id = '41534223-f441-42ad-9ddf-ab7876e8555a'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid;
  SELECT coalesce(sum(deductible_balance),0) INTO l FROM wallet_ledger
    WHERE user_id = '41534223-f441-42ad-9ddf-ab7876e8555a'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid
      AND currency = 'points' AND transaction_type = 'earn';
  IF abs(w - l) > 0.01 THEN
    RAISE EXCEPTION 'post-apply invariant user % wallet % lots %', '41534223-f441-42ad-9ddf-ab7876e8555a', w, l;
  END IF;
END $v$;
COMMIT;
BEGIN;
UPDATE wallet_ledger SET deductible_balance = 0.0 WHERE id = 'c5d08e49-c330-4494-a4ac-cabcc57d02b1'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = '41ffe054-bc16-4d3a-9120-bc551b76991c'::uuid;
UPDATE wallet_ledger SET deductible_balance = 0.0 WHERE id = 'b3dae78e-7c09-46ef-a1a4-bfed630f59d9'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = '41ffe054-bc16-4d3a-9120-bc551b76991c'::uuid;
UPDATE wallet_ledger SET deductible_balance = 0.0 WHERE id = 'c640ee7a-29fb-4433-a0ab-b0b5421fdc8a'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = '41ffe054-bc16-4d3a-9120-bc551b76991c'::uuid;
UPDATE wallet_ledger SET deductible_balance = 0.0 WHERE id = 'c72bba4d-4c96-4ca1-8a7d-c6095a107349'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = '41ffe054-bc16-4d3a-9120-bc551b76991c'::uuid;
UPDATE wallet_ledger SET deductible_balance = 0.0 WHERE id = '0978a2e2-58fd-4a4a-968b-24855e4df621'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = '41ffe054-bc16-4d3a-9120-bc551b76991c'::uuid;
UPDATE wallet_ledger SET deductible_balance = 0.0 WHERE id = 'f9f16f3b-611b-48f6-aa6d-dec8c69190e9'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = '41ffe054-bc16-4d3a-9120-bc551b76991c'::uuid;
UPDATE wallet_ledger SET deductible_balance = 0.0 WHERE id = 'f94f9b58-ff9d-447a-9bfc-a1ce0129899a'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = '41ffe054-bc16-4d3a-9120-bc551b76991c'::uuid;
UPDATE wallet_ledger SET deductible_balance = 0.0 WHERE id = 'aae7a004-450b-4bd1-abe9-79cc76f98886'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = '41ffe054-bc16-4d3a-9120-bc551b76991c'::uuid;
UPDATE wallet_ledger SET deductible_balance = 157.0 WHERE id = '09216f84-e207-4150-b82f-9e1fd1465242'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = '41ffe054-bc16-4d3a-9120-bc551b76991c'::uuid;
DO $v$
DECLARE w numeric; l numeric;
BEGIN
  SELECT points_balance INTO w FROM user_wallet WHERE user_id = '41ffe054-bc16-4d3a-9120-bc551b76991c'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid;
  SELECT coalesce(sum(deductible_balance),0) INTO l FROM wallet_ledger
    WHERE user_id = '41ffe054-bc16-4d3a-9120-bc551b76991c'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid
      AND currency = 'points' AND transaction_type = 'earn';
  IF abs(w - l) > 0.01 THEN
    RAISE EXCEPTION 'post-apply invariant user % wallet % lots %', '41ffe054-bc16-4d3a-9120-bc551b76991c', w, l;
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
  '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid, '4201b34a-019d-49fe-b6f5-5d3c300a2e2d'::uuid,   'points'::currency, 'earn'::currency_transaction_type,
  'base'::currency_component,
  50, 50, 50,
  50, 50,
  'manual'::wallet_transaction_source_type, 'Legacy wallet balance', '{"backfill": "jorakay_wallet_lot_drift_20260912", "reason": "orphan_wallet_no_points_ledger"}'::jsonb,
  NULL, NULL,
  '4201b34a-019d-49fe-b6f5-5d3c300a2e2d', 'jorakay-orphan-65b1c32412e71882a72ae409', '2026-06-15T00:00:00+00:00'::timestamptz, false
WHERE NOT EXISTS (
  SELECT 1 FROM wallet_ledger wl
  WHERE wl.merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND wl.dedup_key = 'jorakay-orphan-65b1c32412e71882a72ae409'
);;
DO $v$
DECLARE w numeric; l numeric;
BEGIN
  SELECT points_balance INTO w FROM user_wallet WHERE user_id = '4201b34a-019d-49fe-b6f5-5d3c300a2e2d'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid;
  SELECT coalesce(sum(deductible_balance),0) INTO l FROM wallet_ledger
    WHERE user_id = '4201b34a-019d-49fe-b6f5-5d3c300a2e2d'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid
      AND currency = 'points' AND transaction_type = 'earn';
  IF abs(w - l) > 0.01 THEN
    RAISE EXCEPTION 'post-apply invariant user % wallet % lots %', '4201b34a-019d-49fe-b6f5-5d3c300a2e2d', w, l;
  END IF;
END $v$;
COMMIT;
BEGIN;
UPDATE wallet_ledger SET deductible_balance = 32.0 WHERE id = '1500beff-8e66-49a4-a63b-ae6d26948cad'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = '42a8eb41-f6ac-48af-99c0-2465f5d7d5c7'::uuid;
DO $v$
DECLARE w numeric; l numeric;
BEGIN
  SELECT points_balance INTO w FROM user_wallet WHERE user_id = '42a8eb41-f6ac-48af-99c0-2465f5d7d5c7'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid;
  SELECT coalesce(sum(deductible_balance),0) INTO l FROM wallet_ledger
    WHERE user_id = '42a8eb41-f6ac-48af-99c0-2465f5d7d5c7'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid
      AND currency = 'points' AND transaction_type = 'earn';
  IF abs(w - l) > 0.01 THEN
    RAISE EXCEPTION 'post-apply invariant user % wallet % lots %', '42a8eb41-f6ac-48af-99c0-2465f5d7d5c7', w, l;
  END IF;
END $v$;
COMMIT;
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
BEGIN;
UPDATE wallet_ledger SET deductible_balance = 0.0 WHERE id = 'b8544f6e-8485-4458-950c-a5e6dc1b9b2f'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = '44bda93e-b7c2-4715-be2d-2a7f1723ace8'::uuid;
UPDATE wallet_ledger SET deductible_balance = 2.0 WHERE id = 'fdc4bff6-de41-415b-baa5-002da23d1e52'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = '44bda93e-b7c2-4715-be2d-2a7f1723ace8'::uuid;
UPDATE wallet_ledger SET deductible_balance = 14.0 WHERE id = '25bb2f89-2375-4f34-89ad-b9571838cf83'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = '44bda93e-b7c2-4715-be2d-2a7f1723ace8'::uuid;
DO $v$
DECLARE w numeric; l numeric;
BEGIN
  SELECT points_balance INTO w FROM user_wallet WHERE user_id = '44bda93e-b7c2-4715-be2d-2a7f1723ace8'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid;
  SELECT coalesce(sum(deductible_balance),0) INTO l FROM wallet_ledger
    WHERE user_id = '44bda93e-b7c2-4715-be2d-2a7f1723ace8'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid
      AND currency = 'points' AND transaction_type = 'earn';
  IF abs(w - l) > 0.01 THEN
    RAISE EXCEPTION 'post-apply invariant user % wallet % lots %', '44bda93e-b7c2-4715-be2d-2a7f1723ace8', w, l;
  END IF;
END $v$;
COMMIT;
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
BEGIN;
UPDATE wallet_ledger SET deductible_balance = 79.0 WHERE id = '1a6d92c0-e825-4eb7-b059-33e5d0d0bb42'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = '491b5e4f-bc49-43bb-920c-ed40018230f0'::uuid;
DO $v$
DECLARE w numeric; l numeric;
BEGIN
  SELECT points_balance INTO w FROM user_wallet WHERE user_id = '491b5e4f-bc49-43bb-920c-ed40018230f0'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid;
  SELECT coalesce(sum(deductible_balance),0) INTO l FROM wallet_ledger
    WHERE user_id = '491b5e4f-bc49-43bb-920c-ed40018230f0'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid
      AND currency = 'points' AND transaction_type = 'earn';
  IF abs(w - l) > 0.01 THEN
    RAISE EXCEPTION 'post-apply invariant user % wallet % lots %', '491b5e4f-bc49-43bb-920c-ed40018230f0', w, l;
  END IF;
END $v$;
COMMIT;
BEGIN;
UPDATE wallet_ledger SET deductible_balance = 11.0 WHERE id = '4930af0c-4e60-4115-b8f0-c39ee54fda44'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = '4a9af9e7-5e90-4a6a-852c-499129660405'::uuid;
UPDATE wallet_ledger SET deductible_balance = 31.0 WHERE id = '0262a813-5fbf-4175-8b91-b1602951f3f5'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = '4a9af9e7-5e90-4a6a-852c-499129660405'::uuid;
UPDATE wallet_ledger SET deductible_balance = 15.0 WHERE id = 'e10e9200-8f35-4eac-87c1-5a5bfa72d7e5'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = '4a9af9e7-5e90-4a6a-852c-499129660405'::uuid;
UPDATE wallet_ledger SET deductible_balance = 4.0 WHERE id = '1b6f07c9-0c0b-44c6-bc01-d72946435dfc'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = '4a9af9e7-5e90-4a6a-852c-499129660405'::uuid;
UPDATE wallet_ledger SET deductible_balance = 1.0 WHERE id = '84bf2d4f-56f0-4ef7-ac6b-13d0ab742603'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = '4a9af9e7-5e90-4a6a-852c-499129660405'::uuid;
UPDATE wallet_ledger SET deductible_balance = 3.0 WHERE id = '97a3eda5-14ca-4fc8-a676-6a878371cc51'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = '4a9af9e7-5e90-4a6a-852c-499129660405'::uuid;
UPDATE wallet_ledger SET deductible_balance = 4.0 WHERE id = 'a2867f38-fe37-46c7-8650-0fb6eecaf9e6'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = '4a9af9e7-5e90-4a6a-852c-499129660405'::uuid;
UPDATE wallet_ledger SET deductible_balance = 11.0 WHERE id = '248cc522-8701-4d62-8705-c53a9de2c2a6'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = '4a9af9e7-5e90-4a6a-852c-499129660405'::uuid;
UPDATE wallet_ledger SET deductible_balance = 25.0 WHERE id = '2964263b-39ff-410b-835c-c0d0a61e2f73'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = '4a9af9e7-5e90-4a6a-852c-499129660405'::uuid;
UPDATE wallet_ledger SET deductible_balance = 31.0 WHERE id = 'f10a4461-cbf3-4227-975d-8834a5df2347'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = '4a9af9e7-5e90-4a6a-852c-499129660405'::uuid;
UPDATE wallet_ledger SET deductible_balance = 15.0 WHERE id = 'fdb6b923-52db-458c-9194-4875f8fc6c00'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = '4a9af9e7-5e90-4a6a-852c-499129660405'::uuid;
UPDATE wallet_ledger SET deductible_balance = 13.0 WHERE id = '4f45ed48-5e0b-4bc0-ad6e-2397b33b0364'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = '4a9af9e7-5e90-4a6a-852c-499129660405'::uuid;
UPDATE wallet_ledger SET deductible_balance = 31.0 WHERE id = '5c931f9f-283d-4fb4-afb4-1ec080319b4d'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = '4a9af9e7-5e90-4a6a-852c-499129660405'::uuid;
UPDATE wallet_ledger SET deductible_balance = 68.0 WHERE id = 'b7e54fe7-b93f-4bad-9543-5a45f717d234'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = '4a9af9e7-5e90-4a6a-852c-499129660405'::uuid;
UPDATE wallet_ledger SET deductible_balance = 102.0 WHERE id = 'd48b8b7a-b01d-4611-a496-10c1674d7d6a'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = '4a9af9e7-5e90-4a6a-852c-499129660405'::uuid;
UPDATE wallet_ledger SET deductible_balance = 26.0 WHERE id = 'f341303f-f561-4e73-bdf7-56f1606f7bcb'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = '4a9af9e7-5e90-4a6a-852c-499129660405'::uuid;
UPDATE wallet_ledger SET deductible_balance = 226.0 WHERE id = '2f76df88-1553-402e-ba46-833beb090e66'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = '4a9af9e7-5e90-4a6a-852c-499129660405'::uuid;
UPDATE wallet_ledger SET deductible_balance = 907.0 WHERE id = '98786517-a772-4841-8d55-a8bd9573d12a'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = '4a9af9e7-5e90-4a6a-852c-499129660405'::uuid;
UPDATE wallet_ledger SET deductible_balance = 256.0 WHERE id = '27c953df-fee5-4d3a-affb-073eb6e33ddf'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = '4a9af9e7-5e90-4a6a-852c-499129660405'::uuid;
UPDATE wallet_ledger SET deductible_balance = 8.0 WHERE id = '78bf95c3-75f5-4cbf-a536-9efc8c6b8b29'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = '4a9af9e7-5e90-4a6a-852c-499129660405'::uuid;
UPDATE wallet_ledger SET deductible_balance = 29.0 WHERE id = '97a92abd-d97a-43fe-8268-9749f052b9bf'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = '4a9af9e7-5e90-4a6a-852c-499129660405'::uuid;
UPDATE wallet_ledger SET deductible_balance = 2.0 WHERE id = '91692a83-2321-4417-ad8e-7d6a72ee5dee'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = '4a9af9e7-5e90-4a6a-852c-499129660405'::uuid;
UPDATE wallet_ledger SET deductible_balance = 22.0 WHERE id = 'ee78d521-5b18-406c-8820-f7f8c5358832'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = '4a9af9e7-5e90-4a6a-852c-499129660405'::uuid;
UPDATE wallet_ledger SET deductible_balance = 19.0 WHERE id = 'd410fabc-0322-4c34-a116-05c7dd148587'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = '4a9af9e7-5e90-4a6a-852c-499129660405'::uuid;
UPDATE wallet_ledger SET deductible_balance = 15.0 WHERE id = '63f04762-6cfd-430e-b18a-89e5d8710ed1'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = '4a9af9e7-5e90-4a6a-852c-499129660405'::uuid;
UPDATE wallet_ledger SET deductible_balance = 62.0 WHERE id = '43fe409c-a6f7-44ea-8a8f-2302119a80a9'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = '4a9af9e7-5e90-4a6a-852c-499129660405'::uuid;
UPDATE wallet_ledger SET deductible_balance = 6.0 WHERE id = 'c4028c27-f83e-499b-9a9e-9a136fec7f45'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = '4a9af9e7-5e90-4a6a-852c-499129660405'::uuid;
UPDATE wallet_ledger SET deductible_balance = 41.0 WHERE id = '98fb3f3c-cdc6-418f-a6fa-a361d2e9da23'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = '4a9af9e7-5e90-4a6a-852c-499129660405'::uuid;
UPDATE wallet_ledger SET deductible_balance = 40.0 WHERE id = 'a27166fc-0363-407f-b531-b0a6972e790f'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = '4a9af9e7-5e90-4a6a-852c-499129660405'::uuid;
UPDATE wallet_ledger SET deductible_balance = 8.0 WHERE id = '9dcdf4f6-b847-4425-8aac-b041919ed2f9'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = '4a9af9e7-5e90-4a6a-852c-499129660405'::uuid;
UPDATE wallet_ledger SET deductible_balance = 9.0 WHERE id = '85df89de-5478-422c-8ac2-11b84e5fbb37'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = '4a9af9e7-5e90-4a6a-852c-499129660405'::uuid;
UPDATE wallet_ledger SET deductible_balance = 61.0 WHERE id = 'b2833efa-d950-4f4b-afbe-846e166b2b0d'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = '4a9af9e7-5e90-4a6a-852c-499129660405'::uuid;
UPDATE wallet_ledger SET deductible_balance = 95.0 WHERE id = '779e2dfd-90bb-4666-9b13-298786f5fd13'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = '4a9af9e7-5e90-4a6a-852c-499129660405'::uuid;
UPDATE wallet_ledger SET deductible_balance = 15.0 WHERE id = '2c8713cf-b2e5-4739-ad32-6bd921a0f058'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = '4a9af9e7-5e90-4a6a-852c-499129660405'::uuid;
UPDATE wallet_ledger SET deductible_balance = 39.0 WHERE id = '457ade18-14bd-464b-94f6-f40a49c96b87'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = '4a9af9e7-5e90-4a6a-852c-499129660405'::uuid;
UPDATE wallet_ledger SET deductible_balance = 5.0 WHERE id = 'a27dfa13-2c6d-4786-8d90-0fc059b7dec5'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = '4a9af9e7-5e90-4a6a-852c-499129660405'::uuid;
UPDATE wallet_ledger SET deductible_balance = 5.0 WHERE id = '6bf1f4c2-e232-4d51-a8c7-ab189834348b'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = '4a9af9e7-5e90-4a6a-852c-499129660405'::uuid;
UPDATE wallet_ledger SET deductible_balance = 67.0 WHERE id = '43b5629f-7f97-4824-8a90-12565c9a16cb'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = '4a9af9e7-5e90-4a6a-852c-499129660405'::uuid;
UPDATE wallet_ledger SET deductible_balance = 29.0 WHERE id = 'c6d57d58-c76d-4499-8249-bbb861d45587'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = '4a9af9e7-5e90-4a6a-852c-499129660405'::uuid;
UPDATE wallet_ledger SET deductible_balance = 20.0 WHERE id = '6b146a15-8d61-406d-9d6b-f1b51ceaf1a2'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = '4a9af9e7-5e90-4a6a-852c-499129660405'::uuid;
UPDATE wallet_ledger SET deductible_balance = 39.0 WHERE id = 'db898956-ecf4-4d61-9963-36788ea4442e'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = '4a9af9e7-5e90-4a6a-852c-499129660405'::uuid;
UPDATE wallet_ledger SET deductible_balance = 78.0 WHERE id = '5e8149ab-35ce-40f1-86d0-638e47423e97'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = '4a9af9e7-5e90-4a6a-852c-499129660405'::uuid;
DO $v$
DECLARE w numeric; l numeric;
BEGIN
  SELECT points_balance INTO w FROM user_wallet WHERE user_id = '4a9af9e7-5e90-4a6a-852c-499129660405'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid;
  SELECT coalesce(sum(deductible_balance),0) INTO l FROM wallet_ledger
    WHERE user_id = '4a9af9e7-5e90-4a6a-852c-499129660405'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid
      AND currency = 'points' AND transaction_type = 'earn';
  IF abs(w - l) > 0.01 THEN
    RAISE EXCEPTION 'post-apply invariant user % wallet % lots %', '4a9af9e7-5e90-4a6a-852c-499129660405', w, l;
  END IF;
END $v$;
COMMIT;
BEGIN;
UPDATE wallet_ledger SET deductible_balance = 0.0 WHERE id = '542d23eb-a78e-4165-a17e-d1fa5453842d'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = '4b20ce30-90db-4e65-a911-227bb6048c56'::uuid;
UPDATE wallet_ledger SET deductible_balance = 0.0 WHERE id = '57265e85-9fdc-48b4-8239-3810e483c630'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = '4b20ce30-90db-4e65-a911-227bb6048c56'::uuid;
UPDATE wallet_ledger SET deductible_balance = 0.0 WHERE id = '9743bee9-64a8-4c70-a57c-12c1fe891b7a'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = '4b20ce30-90db-4e65-a911-227bb6048c56'::uuid;
UPDATE wallet_ledger SET deductible_balance = 64.0 WHERE id = '7b0a7d31-ac79-480e-8b17-1c6594f5b2ae'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = '4b20ce30-90db-4e65-a911-227bb6048c56'::uuid;
UPDATE wallet_ledger SET deductible_balance = 580.0 WHERE id = '7aca75e4-575c-4a52-b2cb-207e5bd4c303'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = '4b20ce30-90db-4e65-a911-227bb6048c56'::uuid;
UPDATE wallet_ledger SET deductible_balance = 62.0 WHERE id = '72bbae1e-26ad-49ec-a80c-119cf3851d52'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = '4b20ce30-90db-4e65-a911-227bb6048c56'::uuid;
UPDATE wallet_ledger SET deductible_balance = 580.0 WHERE id = '5d99d272-ace3-48d6-9738-45eaac38f9aa'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = '4b20ce30-90db-4e65-a911-227bb6048c56'::uuid;
DO $v$
DECLARE w numeric; l numeric;
BEGIN
  SELECT points_balance INTO w FROM user_wallet WHERE user_id = '4b20ce30-90db-4e65-a911-227bb6048c56'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid;
  SELECT coalesce(sum(deductible_balance),0) INTO l FROM wallet_ledger
    WHERE user_id = '4b20ce30-90db-4e65-a911-227bb6048c56'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid
      AND currency = 'points' AND transaction_type = 'earn';
  IF abs(w - l) > 0.01 THEN
    RAISE EXCEPTION 'post-apply invariant user % wallet % lots %', '4b20ce30-90db-4e65-a911-227bb6048c56', w, l;
  END IF;
END $v$;
COMMIT;
BEGIN;
UPDATE wallet_ledger SET deductible_balance = 0.0 WHERE id = '8b38df78-a9f3-4b31-8e32-f0c03ff64167'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = '4f63443d-b500-447e-ac1e-0c62a15e19d0'::uuid;
UPDATE wallet_ledger SET deductible_balance = 0.0 WHERE id = '142748dc-7161-4b7d-844b-f7500c29f7f5'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = '4f63443d-b500-447e-ac1e-0c62a15e19d0'::uuid;
UPDATE wallet_ledger SET deductible_balance = 1199.0 WHERE id = '27edd66d-ca06-412f-aad9-d00a2c7af690'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = '4f63443d-b500-447e-ac1e-0c62a15e19d0'::uuid;
DO $v$
DECLARE w numeric; l numeric;
BEGIN
  SELECT points_balance INTO w FROM user_wallet WHERE user_id = '4f63443d-b500-447e-ac1e-0c62a15e19d0'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid;
  SELECT coalesce(sum(deductible_balance),0) INTO l FROM wallet_ledger
    WHERE user_id = '4f63443d-b500-447e-ac1e-0c62a15e19d0'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid
      AND currency = 'points' AND transaction_type = 'earn';
  IF abs(w - l) > 0.01 THEN
    RAISE EXCEPTION 'post-apply invariant user % wallet % lots %', '4f63443d-b500-447e-ac1e-0c62a15e19d0', w, l;
  END IF;
END $v$;
COMMIT;
BEGIN;
UPDATE wallet_ledger SET deductible_balance = 0.0 WHERE id = 'cc448652-bf10-40dd-9d2d-a988e5295baf'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = '509d2ec8-bc6f-4e8b-b69b-a130363090d8'::uuid;
UPDATE wallet_ledger SET deductible_balance = 0.0 WHERE id = '64938f4a-9c1c-49fa-af1a-5dd099891720'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = '509d2ec8-bc6f-4e8b-b69b-a130363090d8'::uuid;
UPDATE wallet_ledger SET deductible_balance = 0.0 WHERE id = '631af3af-3bef-4f10-a3a5-c1fce5576cbd'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = '509d2ec8-bc6f-4e8b-b69b-a130363090d8'::uuid;
UPDATE wallet_ledger SET deductible_balance = 0.0 WHERE id = 'e6ba0268-53d5-4bd2-9f2c-d8ccc8bae295'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = '509d2ec8-bc6f-4e8b-b69b-a130363090d8'::uuid;
UPDATE wallet_ledger SET deductible_balance = 0.0 WHERE id = '377880c8-fbaa-45fc-ba1e-ef6120ae6ec5'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = '509d2ec8-bc6f-4e8b-b69b-a130363090d8'::uuid;
UPDATE wallet_ledger SET deductible_balance = 135.0 WHERE id = '1826af62-4eb6-499a-ba6e-0698902a73e6'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = '509d2ec8-bc6f-4e8b-b69b-a130363090d8'::uuid;
UPDATE wallet_ledger SET deductible_balance = 640.0 WHERE id = 'aa8b0ffe-3b37-47a6-87b1-5f773be5e4ac'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = '509d2ec8-bc6f-4e8b-b69b-a130363090d8'::uuid;
DO $v$
DECLARE w numeric; l numeric;
BEGIN
  SELECT points_balance INTO w FROM user_wallet WHERE user_id = '509d2ec8-bc6f-4e8b-b69b-a130363090d8'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid;
  SELECT coalesce(sum(deductible_balance),0) INTO l FROM wallet_ledger
    WHERE user_id = '509d2ec8-bc6f-4e8b-b69b-a130363090d8'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid
      AND currency = 'points' AND transaction_type = 'earn';
  IF abs(w - l) > 0.01 THEN
    RAISE EXCEPTION 'post-apply invariant user % wallet % lots %', '509d2ec8-bc6f-4e8b-b69b-a130363090d8', w, l;
  END IF;
END $v$;
COMMIT;
BEGIN;
UPDATE wallet_ledger SET deductible_balance = 0.0 WHERE id = '5a8ff594-6840-4c3a-9540-625ba91591f1'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = '53f473d1-d30a-413b-a43c-7e2991109f92'::uuid;
DO $v$
DECLARE w numeric; l numeric;
BEGIN
  SELECT points_balance INTO w FROM user_wallet WHERE user_id = '53f473d1-d30a-413b-a43c-7e2991109f92'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid;
  SELECT coalesce(sum(deductible_balance),0) INTO l FROM wallet_ledger
    WHERE user_id = '53f473d1-d30a-413b-a43c-7e2991109f92'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid
      AND currency = 'points' AND transaction_type = 'earn';
  IF abs(w - l) > 0.01 THEN
    RAISE EXCEPTION 'post-apply invariant user % wallet % lots %', '53f473d1-d30a-413b-a43c-7e2991109f92', w, l;
  END IF;
END $v$;
COMMIT;
BEGIN;
UPDATE wallet_ledger SET deductible_balance = 10546.0 WHERE id = '1d5bdfe3-8c25-4f98-9833-dfcccdcf8cab'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = '5a7f8d5c-7152-41a0-b9de-13823334931b'::uuid;
UPDATE wallet_ledger SET deductible_balance = 448.0 WHERE id = '4e36172e-3dd2-4c46-991e-ca85ce3ed9ac'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = '5a7f8d5c-7152-41a0-b9de-13823334931b'::uuid;
DO $v$
DECLARE w numeric; l numeric;
BEGIN
  SELECT points_balance INTO w FROM user_wallet WHERE user_id = '5a7f8d5c-7152-41a0-b9de-13823334931b'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid;
  SELECT coalesce(sum(deductible_balance),0) INTO l FROM wallet_ledger
    WHERE user_id = '5a7f8d5c-7152-41a0-b9de-13823334931b'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid
      AND currency = 'points' AND transaction_type = 'earn';
  IF abs(w - l) > 0.01 THEN
    RAISE EXCEPTION 'post-apply invariant user % wallet % lots %', '5a7f8d5c-7152-41a0-b9de-13823334931b', w, l;
  END IF;
END $v$;
COMMIT;
BEGIN;
UPDATE wallet_ledger SET deductible_balance = 20.0 WHERE id = '37f9c0cc-3e97-4537-8b78-2be3331ef532'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = '5c4bd772-99e3-43a7-8e74-9bd70d73d96c'::uuid;
DO $v$
DECLARE w numeric; l numeric;
BEGIN
  SELECT points_balance INTO w FROM user_wallet WHERE user_id = '5c4bd772-99e3-43a7-8e74-9bd70d73d96c'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid;
  SELECT coalesce(sum(deductible_balance),0) INTO l FROM wallet_ledger
    WHERE user_id = '5c4bd772-99e3-43a7-8e74-9bd70d73d96c'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid
      AND currency = 'points' AND transaction_type = 'earn';
  IF abs(w - l) > 0.01 THEN
    RAISE EXCEPTION 'post-apply invariant user % wallet % lots %', '5c4bd772-99e3-43a7-8e74-9bd70d73d96c', w, l;
  END IF;
END $v$;
COMMIT;
