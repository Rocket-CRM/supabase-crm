BEGIN;
UPDATE wallet_ledger SET deductible_balance = 226.0 WHERE id = '61762d97-ad48-4639-b686-717e08fd1e17'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = 'e6ff7132-45f1-4b05-858b-2e0746633a25'::uuid;
DO $v$
DECLARE w numeric; l numeric;
BEGIN
  SELECT points_balance INTO w FROM user_wallet WHERE user_id = 'e6ff7132-45f1-4b05-858b-2e0746633a25'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid;
  SELECT coalesce(sum(deductible_balance),0) INTO l FROM wallet_ledger
    WHERE user_id = 'e6ff7132-45f1-4b05-858b-2e0746633a25'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid
      AND currency = 'points' AND transaction_type = 'earn';
  IF abs(w - l) > 0.01 THEN
    RAISE EXCEPTION 'post-apply invariant user % wallet % lots %', 'e6ff7132-45f1-4b05-858b-2e0746633a25', w, l;
  END IF;
END $v$;
COMMIT;
BEGIN;
UPDATE wallet_ledger SET deductible_balance = 0.0 WHERE id = '9779f401-78ba-4fd6-b46a-d5fe8f9563ad'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = 'eac6f8e7-1c1d-4b0d-b460-1842b99b1722'::uuid;
UPDATE wallet_ledger SET deductible_balance = 0.0 WHERE id = '93d1a917-20e7-4da4-b111-5c216c571d33'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = 'eac6f8e7-1c1d-4b0d-b460-1842b99b1722'::uuid;
UPDATE wallet_ledger SET deductible_balance = 0.0 WHERE id = 'ad19b545-49ee-444c-9338-5d5520c793ef'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = 'eac6f8e7-1c1d-4b0d-b460-1842b99b1722'::uuid;
UPDATE wallet_ledger SET deductible_balance = 0.0 WHERE id = 'b177d0d8-a66d-4232-bd18-6fab3091fafb'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = 'eac6f8e7-1c1d-4b0d-b460-1842b99b1722'::uuid;
UPDATE wallet_ledger SET deductible_balance = 0.0 WHERE id = '29d53b3c-de8e-44bb-88c3-8c3e14211a03'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = 'eac6f8e7-1c1d-4b0d-b460-1842b99b1722'::uuid;
UPDATE wallet_ledger SET deductible_balance = 0.0 WHERE id = '4224f76b-f5cb-4f0f-a7bf-7698dcc03f4e'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = 'eac6f8e7-1c1d-4b0d-b460-1842b99b1722'::uuid;
UPDATE wallet_ledger SET deductible_balance = 8.0 WHERE id = '6d281e7c-0d28-4cdf-8534-8cd88d7ffec1'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = 'eac6f8e7-1c1d-4b0d-b460-1842b99b1722'::uuid;
DO $v$
DECLARE w numeric; l numeric;
BEGIN
  SELECT points_balance INTO w FROM user_wallet WHERE user_id = 'eac6f8e7-1c1d-4b0d-b460-1842b99b1722'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid;
  SELECT coalesce(sum(deductible_balance),0) INTO l FROM wallet_ledger
    WHERE user_id = 'eac6f8e7-1c1d-4b0d-b460-1842b99b1722'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid
      AND currency = 'points' AND transaction_type = 'earn';
  IF abs(w - l) > 0.01 THEN
    RAISE EXCEPTION 'post-apply invariant user % wallet % lots %', 'eac6f8e7-1c1d-4b0d-b460-1842b99b1722', w, l;
  END IF;
END $v$;
COMMIT;
BEGIN;
UPDATE wallet_ledger SET deductible_balance = 22.0 WHERE id = '42bd15d2-adbf-42b7-bb5d-70dfbe60de01'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = 'f58dfe80-7d93-4ff5-9f3d-2a8603527518'::uuid;
UPDATE wallet_ledger SET deductible_balance = 33.0 WHERE id = 'b62fd1be-b958-4b56-8234-bb5692e1c3dd'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = 'f58dfe80-7d93-4ff5-9f3d-2a8603527518'::uuid;
UPDATE wallet_ledger SET deductible_balance = 13.0 WHERE id = 'fd6d2302-d8f7-4ec8-8c2a-0a15228a70f7'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = 'f58dfe80-7d93-4ff5-9f3d-2a8603527518'::uuid;
UPDATE wallet_ledger SET deductible_balance = 18.0 WHERE id = '6386bc66-d24d-405c-b621-f01c271c9534'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = 'f58dfe80-7d93-4ff5-9f3d-2a8603527518'::uuid;
DO $v$
DECLARE w numeric; l numeric;
BEGIN
  SELECT points_balance INTO w FROM user_wallet WHERE user_id = 'f58dfe80-7d93-4ff5-9f3d-2a8603527518'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid;
  SELECT coalesce(sum(deductible_balance),0) INTO l FROM wallet_ledger
    WHERE user_id = 'f58dfe80-7d93-4ff5-9f3d-2a8603527518'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid
      AND currency = 'points' AND transaction_type = 'earn';
  IF abs(w - l) > 0.01 THEN
    RAISE EXCEPTION 'post-apply invariant user % wallet % lots %', 'f58dfe80-7d93-4ff5-9f3d-2a8603527518', w, l;
  END IF;
END $v$;
COMMIT;
BEGIN;
UPDATE wallet_ledger SET deductible_balance = 5.0 WHERE id = 'a002ed44-93e8-489f-8ede-e30c159d4036'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = 'f596f347-c4e9-466e-955c-15cce84ecb25'::uuid;
UPDATE wallet_ledger SET deductible_balance = 95.0 WHERE id = 'fea66481-81c8-407d-ab86-0c6b9befbbb3'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = 'f596f347-c4e9-466e-955c-15cce84ecb25'::uuid;
DO $v$
DECLARE w numeric; l numeric;
BEGIN
  SELECT points_balance INTO w FROM user_wallet WHERE user_id = 'f596f347-c4e9-466e-955c-15cce84ecb25'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid;
  SELECT coalesce(sum(deductible_balance),0) INTO l FROM wallet_ledger
    WHERE user_id = 'f596f347-c4e9-466e-955c-15cce84ecb25'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid
      AND currency = 'points' AND transaction_type = 'earn';
  IF abs(w - l) > 0.01 THEN
    RAISE EXCEPTION 'post-apply invariant user % wallet % lots %', 'f596f347-c4e9-466e-955c-15cce84ecb25', w, l;
  END IF;
END $v$;
COMMIT;
BEGIN;
UPDATE wallet_ledger SET deductible_balance = 32.0 WHERE id = '86d18865-36a5-44ec-8bb9-7b75cc0e3f2d'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = 'f59ba826-7f68-451d-9968-c8029f70397e'::uuid;
UPDATE wallet_ledger SET deductible_balance = 33.0 WHERE id = '65d33065-49bb-43cb-a1f0-c71183b857c0'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = 'f59ba826-7f68-451d-9968-c8029f70397e'::uuid;
UPDATE wallet_ledger SET deductible_balance = 2.0 WHERE id = '1140b720-67a8-4cd2-82c0-28a9df66a8cb'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = 'f59ba826-7f68-451d-9968-c8029f70397e'::uuid;
DO $v$
DECLARE w numeric; l numeric;
BEGIN
  SELECT points_balance INTO w FROM user_wallet WHERE user_id = 'f59ba826-7f68-451d-9968-c8029f70397e'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid;
  SELECT coalesce(sum(deductible_balance),0) INTO l FROM wallet_ledger
    WHERE user_id = 'f59ba826-7f68-451d-9968-c8029f70397e'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid
      AND currency = 'points' AND transaction_type = 'earn';
  IF abs(w - l) > 0.01 THEN
    RAISE EXCEPTION 'post-apply invariant user % wallet % lots %', 'f59ba826-7f68-451d-9968-c8029f70397e', w, l;
  END IF;
END $v$;
COMMIT;
BEGIN;
UPDATE wallet_ledger SET deductible_balance = 1.0 WHERE id = '18c539d1-a9a1-4fcb-bad7-6017d6649c06'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = 'f7560608-89bd-4735-969e-1586c0299814'::uuid;
DO $v$
DECLARE w numeric; l numeric;
BEGIN
  SELECT points_balance INTO w FROM user_wallet WHERE user_id = 'f7560608-89bd-4735-969e-1586c0299814'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid;
  SELECT coalesce(sum(deductible_balance),0) INTO l FROM wallet_ledger
    WHERE user_id = 'f7560608-89bd-4735-969e-1586c0299814'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid
      AND currency = 'points' AND transaction_type = 'earn';
  IF abs(w - l) > 0.01 THEN
    RAISE EXCEPTION 'post-apply invariant user % wallet % lots %', 'f7560608-89bd-4735-969e-1586c0299814', w, l;
  END IF;
END $v$;
COMMIT;
BEGIN;
UPDATE wallet_ledger SET deductible_balance = 32.0 WHERE id = '91532f19-a87d-44b0-9641-5928d1dde4dd'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = 'f97ac591-9387-462f-9a78-b2a4ed1f7ab7'::uuid;
DO $v$
DECLARE w numeric; l numeric;
BEGIN
  SELECT points_balance INTO w FROM user_wallet WHERE user_id = 'f97ac591-9387-462f-9a78-b2a4ed1f7ab7'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid;
  SELECT coalesce(sum(deductible_balance),0) INTO l FROM wallet_ledger
    WHERE user_id = 'f97ac591-9387-462f-9a78-b2a4ed1f7ab7'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid
      AND currency = 'points' AND transaction_type = 'earn';
  IF abs(w - l) > 0.01 THEN
    RAISE EXCEPTION 'post-apply invariant user % wallet % lots %', 'f97ac591-9387-462f-9a78-b2a4ed1f7ab7', w, l;
  END IF;
END $v$;
COMMIT;
BEGIN;
UPDATE wallet_ledger SET deductible_balance = 410.0 WHERE id = 'a5c2f79c-4031-4055-9b97-46a6bdfc3493'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = 'fb282052-f769-49b2-a0f8-0697bebb14e9'::uuid;
UPDATE wallet_ledger SET deductible_balance = 162.0 WHERE id = 'ab25fcb7-beb7-4edf-b066-3091c4eac1eb'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = 'fb282052-f769-49b2-a0f8-0697bebb14e9'::uuid;
DO $v$
DECLARE w numeric; l numeric;
BEGIN
  SELECT points_balance INTO w FROM user_wallet WHERE user_id = 'fb282052-f769-49b2-a0f8-0697bebb14e9'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid;
  SELECT coalesce(sum(deductible_balance),0) INTO l FROM wallet_ledger
    WHERE user_id = 'fb282052-f769-49b2-a0f8-0697bebb14e9'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid
      AND currency = 'points' AND transaction_type = 'earn';
  IF abs(w - l) > 0.01 THEN
    RAISE EXCEPTION 'post-apply invariant user % wallet % lots %', 'fb282052-f769-49b2-a0f8-0697bebb14e9', w, l;
  END IF;
END $v$;
COMMIT;
BEGIN;
UPDATE wallet_ledger SET deductible_balance = 16.0 WHERE id = '96747fa1-8df8-463d-ad2a-34832ae4a3d0'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = 'fc12adec-2891-4b0d-aa04-238e9691a816'::uuid;
DO $v$
DECLARE w numeric; l numeric;
BEGIN
  SELECT points_balance INTO w FROM user_wallet WHERE user_id = 'fc12adec-2891-4b0d-aa04-238e9691a816'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid;
  SELECT coalesce(sum(deductible_balance),0) INTO l FROM wallet_ledger
    WHERE user_id = 'fc12adec-2891-4b0d-aa04-238e9691a816'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid
      AND currency = 'points' AND transaction_type = 'earn';
  IF abs(w - l) > 0.01 THEN
    RAISE EXCEPTION 'post-apply invariant user % wallet % lots %', 'fc12adec-2891-4b0d-aa04-238e9691a816', w, l;
  END IF;
END $v$;
COMMIT;
BEGIN;
UPDATE wallet_ledger SET deductible_balance = 0.0 WHERE id = '67410c2e-0e3e-408e-a6c7-a38e009f260f'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = 'fc18f25e-eb61-4b9e-957d-1f74af4be191'::uuid;
UPDATE wallet_ledger SET deductible_balance = 0.0 WHERE id = '9b84f964-df69-4f32-ac4a-b0f0e6e336ac'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = 'fc18f25e-eb61-4b9e-957d-1f74af4be191'::uuid;
UPDATE wallet_ledger SET deductible_balance = 0.0 WHERE id = '49a384f7-9a27-4edb-97c0-b2838182d8fe'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = 'fc18f25e-eb61-4b9e-957d-1f74af4be191'::uuid;
UPDATE wallet_ledger SET deductible_balance = 0.0 WHERE id = 'ebabbf03-f1c1-4abb-a8c1-72af62f242e3'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = 'fc18f25e-eb61-4b9e-957d-1f74af4be191'::uuid;
UPDATE wallet_ledger SET deductible_balance = 678.0 WHERE id = '7bd8e257-1cb1-474d-9472-b507af4b1923'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = 'fc18f25e-eb61-4b9e-957d-1f74af4be191'::uuid;
UPDATE wallet_ledger SET deductible_balance = 710.0 WHERE id = '40790208-4196-4683-be5d-3df5387f7eda'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = 'fc18f25e-eb61-4b9e-957d-1f74af4be191'::uuid;
DO $v$
DECLARE w numeric; l numeric;
BEGIN
  SELECT points_balance INTO w FROM user_wallet WHERE user_id = 'fc18f25e-eb61-4b9e-957d-1f74af4be191'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid;
  SELECT coalesce(sum(deductible_balance),0) INTO l FROM wallet_ledger
    WHERE user_id = 'fc18f25e-eb61-4b9e-957d-1f74af4be191'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid
      AND currency = 'points' AND transaction_type = 'earn';
  IF abs(w - l) > 0.01 THEN
    RAISE EXCEPTION 'post-apply invariant user % wallet % lots %', 'fc18f25e-eb61-4b9e-957d-1f74af4be191', w, l;
  END IF;
END $v$;
COMMIT;
BEGIN;
UPDATE wallet_ledger SET deductible_balance = 1251.0 WHERE id = 'a8daeb5c-197a-4c51-9574-b94120d28f8a'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = 'fdd5b2a3-10ff-48f8-ba12-ea38e3846d0c'::uuid;
UPDATE wallet_ledger SET deductible_balance = 83.0 WHERE id = 'f149bde8-173b-49c8-8041-22f42cd0a129'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = 'fdd5b2a3-10ff-48f8-ba12-ea38e3846d0c'::uuid;
DO $v$
DECLARE w numeric; l numeric;
BEGIN
  SELECT points_balance INTO w FROM user_wallet WHERE user_id = 'fdd5b2a3-10ff-48f8-ba12-ea38e3846d0c'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid;
  SELECT coalesce(sum(deductible_balance),0) INTO l FROM wallet_ledger
    WHERE user_id = 'fdd5b2a3-10ff-48f8-ba12-ea38e3846d0c'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid
      AND currency = 'points' AND transaction_type = 'earn';
  IF abs(w - l) > 0.01 THEN
    RAISE EXCEPTION 'post-apply invariant user % wallet % lots %', 'fdd5b2a3-10ff-48f8-ba12-ea38e3846d0c', w, l;
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
  '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid, 'ff4f10c8-d9de-47d7-8f5b-081b5e8c782f'::uuid,   'points'::currency, 'earn'::currency_transaction_type,
  'base'::currency_component,
  50, 50, 50,
  50, 50,
  'manual'::wallet_transaction_source_type, 'Legacy wallet balance', '{"backfill": "jorakay_wallet_lot_drift_20260912", "reason": "orphan_wallet_no_points_ledger"}'::jsonb,
  NULL, NULL,
  'ff4f10c8-d9de-47d7-8f5b-081b5e8c782f', 'jorakay-orphan-65b1c15b12e71882a728dda6', '2026-06-15T00:00:00+00:00'::timestamptz, false
WHERE NOT EXISTS (
  SELECT 1 FROM wallet_ledger wl
  WHERE wl.merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND wl.dedup_key = 'jorakay-orphan-65b1c15b12e71882a728dda6'
);;
DO $v$
DECLARE w numeric; l numeric;
BEGIN
  SELECT points_balance INTO w FROM user_wallet WHERE user_id = 'ff4f10c8-d9de-47d7-8f5b-081b5e8c782f'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid;
  SELECT coalesce(sum(deductible_balance),0) INTO l FROM wallet_ledger
    WHERE user_id = 'ff4f10c8-d9de-47d7-8f5b-081b5e8c782f'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid
      AND currency = 'points' AND transaction_type = 'earn';
  IF abs(w - l) > 0.01 THEN
    RAISE EXCEPTION 'post-apply invariant user % wallet % lots %', 'ff4f10c8-d9de-47d7-8f5b-081b5e8c782f', w, l;
  END IF;
END $v$;
COMMIT;
BEGIN;
UPDATE user_wallet SET points_balance = 128882.0 WHERE user_id = 'ff511b13-f049-40fd-925f-0ef12ee595cb'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid;
DO $v$
DECLARE w numeric; l numeric;
BEGIN
  SELECT points_balance INTO w FROM user_wallet WHERE user_id = 'ff511b13-f049-40fd-925f-0ef12ee595cb'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid;
  SELECT coalesce(sum(deductible_balance),0) INTO l FROM wallet_ledger
    WHERE user_id = 'ff511b13-f049-40fd-925f-0ef12ee595cb'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid
      AND currency = 'points' AND transaction_type = 'earn';
  IF abs(w - l) > 0.01 THEN
    RAISE EXCEPTION 'post-apply invariant user % wallet % lots %', 'ff511b13-f049-40fd-925f-0ef12ee595cb', w, l;
  END IF;
END $v$;
COMMIT;
