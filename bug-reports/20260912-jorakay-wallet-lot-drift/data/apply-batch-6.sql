BEGIN;
UPDATE wallet_ledger SET deductible_balance = 0.0 WHERE id = '78b2cd34-81c9-45bb-bcf7-81abcba8dc62'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = 'c4322c80-096c-4205-adf8-edf874c66132'::uuid;
UPDATE wallet_ledger SET deductible_balance = 213.0 WHERE id = '1e87914d-e9b5-487d-9cfd-bf94fb795fed'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = 'c4322c80-096c-4205-adf8-edf874c66132'::uuid;
DO $v$
DECLARE w numeric; l numeric;
BEGIN
  SELECT points_balance INTO w FROM user_wallet WHERE user_id = 'c4322c80-096c-4205-adf8-edf874c66132'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid;
  SELECT coalesce(sum(deductible_balance),0) INTO l FROM wallet_ledger
    WHERE user_id = 'c4322c80-096c-4205-adf8-edf874c66132'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid
      AND currency = 'points' AND transaction_type = 'earn';
  IF abs(w - l) > 0.01 THEN
    RAISE EXCEPTION 'post-apply invariant user % wallet % lots %', 'c4322c80-096c-4205-adf8-edf874c66132', w, l;
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
  '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid, 'c4482a47-51c1-42b8-910d-707cf14ad3b1'::uuid,   'points'::currency, 'earn'::currency_transaction_type,
  'base'::currency_component,
  50, 50, 50,
  50, 50,
  'manual'::wallet_transaction_source_type, 'Legacy wallet balance', '{"backfill": "jorakay_wallet_lot_drift_20260912", "reason": "orphan_wallet_no_points_ledger"}'::jsonb,
  NULL, NULL,
  'c4482a47-51c1-42b8-910d-707cf14ad3b1', 'jorakay-orphan-65b1c0c612e71882a72856c8', '2026-06-15T00:00:00+00:00'::timestamptz, false
WHERE NOT EXISTS (
  SELECT 1 FROM wallet_ledger wl
  WHERE wl.merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND wl.dedup_key = 'jorakay-orphan-65b1c0c612e71882a72856c8'
);;
DO $v$
DECLARE w numeric; l numeric;
BEGIN
  SELECT points_balance INTO w FROM user_wallet WHERE user_id = 'c4482a47-51c1-42b8-910d-707cf14ad3b1'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid;
  SELECT coalesce(sum(deductible_balance),0) INTO l FROM wallet_ledger
    WHERE user_id = 'c4482a47-51c1-42b8-910d-707cf14ad3b1'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid
      AND currency = 'points' AND transaction_type = 'earn';
  IF abs(w - l) > 0.01 THEN
    RAISE EXCEPTION 'post-apply invariant user % wallet % lots %', 'c4482a47-51c1-42b8-910d-707cf14ad3b1', w, l;
  END IF;
END $v$;
COMMIT;
BEGIN;
UPDATE wallet_ledger SET deductible_balance = 142.0 WHERE id = '8f640b6b-5a45-448a-afc9-6ce27ac56aa0'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = 'cd3491bf-e717-44a5-abdd-2c679cce0074'::uuid;
UPDATE wallet_ledger SET deductible_balance = 237.0 WHERE id = '7a0f62ea-dbf1-4266-a54f-9b0ed9806d34'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = 'cd3491bf-e717-44a5-abdd-2c679cce0074'::uuid;
DO $v$
DECLARE w numeric; l numeric;
BEGIN
  SELECT points_balance INTO w FROM user_wallet WHERE user_id = 'cd3491bf-e717-44a5-abdd-2c679cce0074'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid;
  SELECT coalesce(sum(deductible_balance),0) INTO l FROM wallet_ledger
    WHERE user_id = 'cd3491bf-e717-44a5-abdd-2c679cce0074'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid
      AND currency = 'points' AND transaction_type = 'earn';
  IF abs(w - l) > 0.01 THEN
    RAISE EXCEPTION 'post-apply invariant user % wallet % lots %', 'cd3491bf-e717-44a5-abdd-2c679cce0074', w, l;
  END IF;
END $v$;
COMMIT;
BEGIN;
UPDATE wallet_ledger SET deductible_balance = 0.0 WHERE id = '7b0abf63-0825-48e9-a30f-1bcd4f7d806a'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = 'ce63af19-54ff-4d31-abfa-94ff390bb6df'::uuid;
UPDATE wallet_ledger SET deductible_balance = 0.0 WHERE id = 'a630af94-0a38-40be-800b-7144f8b3e105'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = 'ce63af19-54ff-4d31-abfa-94ff390bb6df'::uuid;
UPDATE wallet_ledger SET deductible_balance = 470.0 WHERE id = '868c5c0f-b6bd-4fa0-9ee4-4a44439bd88a'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = 'ce63af19-54ff-4d31-abfa-94ff390bb6df'::uuid;
UPDATE wallet_ledger SET deductible_balance = 340.0 WHERE id = '90aec12e-a609-4ef1-a218-fa12db2565dc'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = 'ce63af19-54ff-4d31-abfa-94ff390bb6df'::uuid;
DO $v$
DECLARE w numeric; l numeric;
BEGIN
  SELECT points_balance INTO w FROM user_wallet WHERE user_id = 'ce63af19-54ff-4d31-abfa-94ff390bb6df'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid;
  SELECT coalesce(sum(deductible_balance),0) INTO l FROM wallet_ledger
    WHERE user_id = 'ce63af19-54ff-4d31-abfa-94ff390bb6df'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid
      AND currency = 'points' AND transaction_type = 'earn';
  IF abs(w - l) > 0.01 THEN
    RAISE EXCEPTION 'post-apply invariant user % wallet % lots %', 'ce63af19-54ff-4d31-abfa-94ff390bb6df', w, l;
  END IF;
END $v$;
COMMIT;
BEGIN;
UPDATE wallet_ledger SET deductible_balance = 322.0 WHERE id = 'ce929497-8e80-4ead-bec0-bdd52b592c24'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = 'cf3e4ac5-31ca-491d-b599-a8f9b9ac20b2'::uuid;
DO $v$
DECLARE w numeric; l numeric;
BEGIN
  SELECT points_balance INTO w FROM user_wallet WHERE user_id = 'cf3e4ac5-31ca-491d-b599-a8f9b9ac20b2'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid;
  SELECT coalesce(sum(deductible_balance),0) INTO l FROM wallet_ledger
    WHERE user_id = 'cf3e4ac5-31ca-491d-b599-a8f9b9ac20b2'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid
      AND currency = 'points' AND transaction_type = 'earn';
  IF abs(w - l) > 0.01 THEN
    RAISE EXCEPTION 'post-apply invariant user % wallet % lots %', 'cf3e4ac5-31ca-491d-b599-a8f9b9ac20b2', w, l;
  END IF;
END $v$;
COMMIT;
BEGIN;
UPDATE wallet_ledger SET deductible_balance = 0.0 WHERE id = '478e07f0-81eb-4483-9341-65f70f357479'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = 'd093dcaf-0507-4d3f-a899-4ab57adf5444'::uuid;
UPDATE wallet_ledger SET deductible_balance = 807.0 WHERE id = '14b23cc6-187b-4135-a8be-1d7b8cffc00a'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = 'd093dcaf-0507-4d3f-a899-4ab57adf5444'::uuid;
DO $v$
DECLARE w numeric; l numeric;
BEGIN
  SELECT points_balance INTO w FROM user_wallet WHERE user_id = 'd093dcaf-0507-4d3f-a899-4ab57adf5444'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid;
  SELECT coalesce(sum(deductible_balance),0) INTO l FROM wallet_ledger
    WHERE user_id = 'd093dcaf-0507-4d3f-a899-4ab57adf5444'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid
      AND currency = 'points' AND transaction_type = 'earn';
  IF abs(w - l) > 0.01 THEN
    RAISE EXCEPTION 'post-apply invariant user % wallet % lots %', 'd093dcaf-0507-4d3f-a899-4ab57adf5444', w, l;
  END IF;
END $v$;
COMMIT;
BEGIN;
UPDATE wallet_ledger SET deductible_balance = 21.0 WHERE id = '43b758b0-569a-49b5-a157-14b724003502'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = 'd1bca277-2aba-4bb9-9ea2-cbe7109264da'::uuid;
UPDATE wallet_ledger SET deductible_balance = 23.0 WHERE id = '71f29151-82bd-4195-b8ea-a3aafeaed8b3'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = 'd1bca277-2aba-4bb9-9ea2-cbe7109264da'::uuid;
UPDATE wallet_ledger SET deductible_balance = 15.0 WHERE id = '6c4b3587-e889-499e-89b4-ae8425f1ee82'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = 'd1bca277-2aba-4bb9-9ea2-cbe7109264da'::uuid;
UPDATE wallet_ledger SET deductible_balance = 20.0 WHERE id = 'dad9535b-ae42-467c-80c2-3176b52faa41'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = 'd1bca277-2aba-4bb9-9ea2-cbe7109264da'::uuid;
DO $v$
DECLARE w numeric; l numeric;
BEGIN
  SELECT points_balance INTO w FROM user_wallet WHERE user_id = 'd1bca277-2aba-4bb9-9ea2-cbe7109264da'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid;
  SELECT coalesce(sum(deductible_balance),0) INTO l FROM wallet_ledger
    WHERE user_id = 'd1bca277-2aba-4bb9-9ea2-cbe7109264da'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid
      AND currency = 'points' AND transaction_type = 'earn';
  IF abs(w - l) > 0.01 THEN
    RAISE EXCEPTION 'post-apply invariant user % wallet % lots %', 'd1bca277-2aba-4bb9-9ea2-cbe7109264da', w, l;
  END IF;
END $v$;
COMMIT;
BEGIN;
UPDATE wallet_ledger SET deductible_balance = 50.0 WHERE id = '07e4bfa2-e55a-4ab0-94f4-f7727b49bba3'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = 'd319b760-5a40-4641-b25d-a668a4c07721'::uuid;
DO $v$
DECLARE w numeric; l numeric;
BEGIN
  SELECT points_balance INTO w FROM user_wallet WHERE user_id = 'd319b760-5a40-4641-b25d-a668a4c07721'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid;
  SELECT coalesce(sum(deductible_balance),0) INTO l FROM wallet_ledger
    WHERE user_id = 'd319b760-5a40-4641-b25d-a668a4c07721'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid
      AND currency = 'points' AND transaction_type = 'earn';
  IF abs(w - l) > 0.01 THEN
    RAISE EXCEPTION 'post-apply invariant user % wallet % lots %', 'd319b760-5a40-4641-b25d-a668a4c07721', w, l;
  END IF;
END $v$;
COMMIT;
BEGIN;
UPDATE wallet_ledger SET deductible_balance = 385.0 WHERE id = '78405f24-4352-48c0-acf8-9b50e107b973'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = 'd393a943-c476-471b-883d-8538ed5d7400'::uuid;
UPDATE wallet_ledger SET deductible_balance = 360.0 WHERE id = '94855c81-05d3-407e-a8ac-d9df2d1c00e1'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = 'd393a943-c476-471b-883d-8538ed5d7400'::uuid;
UPDATE wallet_ledger SET deductible_balance = 17.0 WHERE id = '15a20d7a-011d-438b-8995-748e44a17d09'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = 'd393a943-c476-471b-883d-8538ed5d7400'::uuid;
UPDATE wallet_ledger SET deductible_balance = 138.0 WHERE id = 'a0500c09-15e3-4473-9c06-65498934b419'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = 'd393a943-c476-471b-883d-8538ed5d7400'::uuid;
UPDATE wallet_ledger SET deductible_balance = 47.0 WHERE id = 'a4f9c43f-1c45-4085-a453-2b61b63e15cb'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = 'd393a943-c476-471b-883d-8538ed5d7400'::uuid;
DO $v$
DECLARE w numeric; l numeric;
BEGIN
  SELECT points_balance INTO w FROM user_wallet WHERE user_id = 'd393a943-c476-471b-883d-8538ed5d7400'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid;
  SELECT coalesce(sum(deductible_balance),0) INTO l FROM wallet_ledger
    WHERE user_id = 'd393a943-c476-471b-883d-8538ed5d7400'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid
      AND currency = 'points' AND transaction_type = 'earn';
  IF abs(w - l) > 0.01 THEN
    RAISE EXCEPTION 'post-apply invariant user % wallet % lots %', 'd393a943-c476-471b-883d-8538ed5d7400', w, l;
  END IF;
END $v$;
COMMIT;
BEGIN;
UPDATE wallet_ledger SET deductible_balance = 405.0 WHERE id = 'aaa3cd85-d45e-47b0-8f46-23af52bc5ab8'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = 'd4a7bba0-10b5-4c44-a85d-4a0a301f31cc'::uuid;
UPDATE wallet_ledger SET deductible_balance = 195.0 WHERE id = '711a80d9-638f-4674-b854-e737931930dc'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = 'd4a7bba0-10b5-4c44-a85d-4a0a301f31cc'::uuid;
UPDATE wallet_ledger SET deductible_balance = 269.0 WHERE id = '94e66b24-5772-476c-bb0b-7de1a2405a1e'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = 'd4a7bba0-10b5-4c44-a85d-4a0a301f31cc'::uuid;
UPDATE wallet_ledger SET deductible_balance = 225.0 WHERE id = '21a64d28-48d4-4723-8dfc-e5a7c5a4a26a'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = 'd4a7bba0-10b5-4c44-a85d-4a0a301f31cc'::uuid;
UPDATE wallet_ledger SET deductible_balance = 95.0 WHERE id = 'ed97b4a0-0c2b-4426-b92b-3dc38b46aed2'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = 'd4a7bba0-10b5-4c44-a85d-4a0a301f31cc'::uuid;
UPDATE wallet_ledger SET deductible_balance = 119.0 WHERE id = '69791b5c-bd8f-4d08-bfff-4a486c8a9e36'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = 'd4a7bba0-10b5-4c44-a85d-4a0a301f31cc'::uuid;
UPDATE wallet_ledger SET deductible_balance = 379.0 WHERE id = '0fbc709c-b0d3-440d-bb87-13c686a76ee8'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = 'd4a7bba0-10b5-4c44-a85d-4a0a301f31cc'::uuid;
UPDATE wallet_ledger SET deductible_balance = 572.0 WHERE id = '7a2177f7-9fcf-4805-a723-e3f5f4d9d33c'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = 'd4a7bba0-10b5-4c44-a85d-4a0a301f31cc'::uuid;
UPDATE wallet_ledger SET deductible_balance = 22.0 WHERE id = 'e678c836-86f4-49bc-9c84-7d1a0ae3c79f'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = 'd4a7bba0-10b5-4c44-a85d-4a0a301f31cc'::uuid;
UPDATE wallet_ledger SET deductible_balance = 343.0 WHERE id = '433ea4ed-4125-4a04-975d-63070372fdf7'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = 'd4a7bba0-10b5-4c44-a85d-4a0a301f31cc'::uuid;
UPDATE wallet_ledger SET deductible_balance = 114.0 WHERE id = 'a4006435-8749-42cc-a80c-8f55ebd76a8c'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = 'd4a7bba0-10b5-4c44-a85d-4a0a301f31cc'::uuid;
UPDATE wallet_ledger SET deductible_balance = 329.0 WHERE id = 'f9362fbf-fa8e-4ce2-97d7-b8f650c770dc'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = 'd4a7bba0-10b5-4c44-a85d-4a0a301f31cc'::uuid;
DO $v$
DECLARE w numeric; l numeric;
BEGIN
  SELECT points_balance INTO w FROM user_wallet WHERE user_id = 'd4a7bba0-10b5-4c44-a85d-4a0a301f31cc'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid;
  SELECT coalesce(sum(deductible_balance),0) INTO l FROM wallet_ledger
    WHERE user_id = 'd4a7bba0-10b5-4c44-a85d-4a0a301f31cc'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid
      AND currency = 'points' AND transaction_type = 'earn';
  IF abs(w - l) > 0.01 THEN
    RAISE EXCEPTION 'post-apply invariant user % wallet % lots %', 'd4a7bba0-10b5-4c44-a85d-4a0a301f31cc', w, l;
  END IF;
END $v$;
COMMIT;
BEGIN;
UPDATE wallet_ledger SET deductible_balance = 0.0 WHERE id = 'ea430c8e-805f-4b5b-800b-17757e53226c'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = 'd5312302-f9a8-49e6-bdc0-e3b49c4c1757'::uuid;
UPDATE wallet_ledger SET deductible_balance = 0.0 WHERE id = '122461b4-d3ab-4832-88f8-012c60b68910'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = 'd5312302-f9a8-49e6-bdc0-e3b49c4c1757'::uuid;
UPDATE wallet_ledger SET deductible_balance = 0.0 WHERE id = '2c8c64d7-c6ea-4799-9290-078f947a8949'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = 'd5312302-f9a8-49e6-bdc0-e3b49c4c1757'::uuid;
UPDATE wallet_ledger SET deductible_balance = 0.0 WHERE id = 'a52edf01-5d5e-4bd7-86f7-87ea4431a538'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = 'd5312302-f9a8-49e6-bdc0-e3b49c4c1757'::uuid;
UPDATE wallet_ledger SET deductible_balance = 74.0 WHERE id = '5d93643e-4c30-4825-9ee2-c7b312ddf601'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = 'd5312302-f9a8-49e6-bdc0-e3b49c4c1757'::uuid;
UPDATE wallet_ledger SET deductible_balance = 107.0 WHERE id = '2059a042-d4d0-466b-b445-779f49b81718'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = 'd5312302-f9a8-49e6-bdc0-e3b49c4c1757'::uuid;
UPDATE wallet_ledger SET deductible_balance = 2842.0 WHERE id = '7dcfed60-b3c9-4ed1-9abb-2d6ec3a59b04'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = 'd5312302-f9a8-49e6-bdc0-e3b49c4c1757'::uuid;
UPDATE wallet_ledger SET deductible_balance = 425.0 WHERE id = 'bd81c0d8-9ccb-4031-a375-cd55d4696002'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = 'd5312302-f9a8-49e6-bdc0-e3b49c4c1757'::uuid;
UPDATE wallet_ledger SET deductible_balance = 418.0 WHERE id = 'b12823ee-4bbb-4820-aa9e-017dc1937983'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = 'd5312302-f9a8-49e6-bdc0-e3b49c4c1757'::uuid;
DO $v$
DECLARE w numeric; l numeric;
BEGIN
  SELECT points_balance INTO w FROM user_wallet WHERE user_id = 'd5312302-f9a8-49e6-bdc0-e3b49c4c1757'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid;
  SELECT coalesce(sum(deductible_balance),0) INTO l FROM wallet_ledger
    WHERE user_id = 'd5312302-f9a8-49e6-bdc0-e3b49c4c1757'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid
      AND currency = 'points' AND transaction_type = 'earn';
  IF abs(w - l) > 0.01 THEN
    RAISE EXCEPTION 'post-apply invariant user % wallet % lots %', 'd5312302-f9a8-49e6-bdc0-e3b49c4c1757', w, l;
  END IF;
END $v$;
COMMIT;
BEGIN;
UPDATE wallet_ledger SET deductible_balance = 21.0 WHERE id = '07fecfd0-689e-4a36-9a45-abf4e3a1b355'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = 'd6b86c80-c6b1-4d06-8de5-0c3fa6a7f3aa'::uuid;
UPDATE wallet_ledger SET deductible_balance = 75.0 WHERE id = 'd282a5d4-306d-4c66-8f88-e824ef971562'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = 'd6b86c80-c6b1-4d06-8de5-0c3fa6a7f3aa'::uuid;
UPDATE wallet_ledger SET deductible_balance = 63.0 WHERE id = '96627d61-ae2e-4592-a900-66efc075db13'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = 'd6b86c80-c6b1-4d06-8de5-0c3fa6a7f3aa'::uuid;
UPDATE wallet_ledger SET deductible_balance = 114.0 WHERE id = '976b26c3-d32c-446e-8c4b-c61130feb66c'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = 'd6b86c80-c6b1-4d06-8de5-0c3fa6a7f3aa'::uuid;
DO $v$
DECLARE w numeric; l numeric;
BEGIN
  SELECT points_balance INTO w FROM user_wallet WHERE user_id = 'd6b86c80-c6b1-4d06-8de5-0c3fa6a7f3aa'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid;
  SELECT coalesce(sum(deductible_balance),0) INTO l FROM wallet_ledger
    WHERE user_id = 'd6b86c80-c6b1-4d06-8de5-0c3fa6a7f3aa'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid
      AND currency = 'points' AND transaction_type = 'earn';
  IF abs(w - l) > 0.01 THEN
    RAISE EXCEPTION 'post-apply invariant user % wallet % lots %', 'd6b86c80-c6b1-4d06-8de5-0c3fa6a7f3aa', w, l;
  END IF;
END $v$;
COMMIT;
BEGIN;
UPDATE wallet_ledger SET deductible_balance = 179.0 WHERE id = '071edb12-7654-40f9-b30f-332beb8c321f'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = 'd945a0eb-5a47-434b-882e-0f9b8f0fe3f0'::uuid;
UPDATE wallet_ledger SET deductible_balance = 25.0 WHERE id = '8d4c030c-3a90-483b-9a37-dd10fb72cbcd'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = 'd945a0eb-5a47-434b-882e-0f9b8f0fe3f0'::uuid;
DO $v$
DECLARE w numeric; l numeric;
BEGIN
  SELECT points_balance INTO w FROM user_wallet WHERE user_id = 'd945a0eb-5a47-434b-882e-0f9b8f0fe3f0'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid;
  SELECT coalesce(sum(deductible_balance),0) INTO l FROM wallet_ledger
    WHERE user_id = 'd945a0eb-5a47-434b-882e-0f9b8f0fe3f0'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid
      AND currency = 'points' AND transaction_type = 'earn';
  IF abs(w - l) > 0.01 THEN
    RAISE EXCEPTION 'post-apply invariant user % wallet % lots %', 'd945a0eb-5a47-434b-882e-0f9b8f0fe3f0', w, l;
  END IF;
END $v$;
COMMIT;
BEGIN;
UPDATE wallet_ledger SET deductible_balance = 7.0 WHERE id = 'af75d15e-cb51-48b1-aa6e-8a34d85a789e'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = 'dad22722-0109-46bf-94e3-84ae3668505e'::uuid;
UPDATE wallet_ledger SET deductible_balance = 1.0 WHERE id = 'e0f7aac4-6c08-453a-9fdc-04077dcada2b'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = 'dad22722-0109-46bf-94e3-84ae3668505e'::uuid;
UPDATE wallet_ledger SET deductible_balance = 30.0 WHERE id = '882a6794-7b69-4361-88d5-4e7b0a0afbe1'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = 'dad22722-0109-46bf-94e3-84ae3668505e'::uuid;
UPDATE wallet_ledger SET deductible_balance = 12.0 WHERE id = '8afe7647-54e2-4dc4-9773-16c2320c183d'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = 'dad22722-0109-46bf-94e3-84ae3668505e'::uuid;
UPDATE wallet_ledger SET deductible_balance = 68.0 WHERE id = '6f2bacb2-429e-41de-905f-537e20ff8917'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = 'dad22722-0109-46bf-94e3-84ae3668505e'::uuid;
DO $v$
DECLARE w numeric; l numeric;
BEGIN
  SELECT points_balance INTO w FROM user_wallet WHERE user_id = 'dad22722-0109-46bf-94e3-84ae3668505e'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid;
  SELECT coalesce(sum(deductible_balance),0) INTO l FROM wallet_ledger
    WHERE user_id = 'dad22722-0109-46bf-94e3-84ae3668505e'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid
      AND currency = 'points' AND transaction_type = 'earn';
  IF abs(w - l) > 0.01 THEN
    RAISE EXCEPTION 'post-apply invariant user % wallet % lots %', 'dad22722-0109-46bf-94e3-84ae3668505e', w, l;
  END IF;
END $v$;
COMMIT;
BEGIN;
UPDATE wallet_ledger SET deductible_balance = 60.0 WHERE id = '7188bcce-77a2-4290-857a-3da3173f3ced'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = 'db18cead-6e46-4692-9b09-499841056796'::uuid;
DO $v$
DECLARE w numeric; l numeric;
BEGIN
  SELECT points_balance INTO w FROM user_wallet WHERE user_id = 'db18cead-6e46-4692-9b09-499841056796'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid;
  SELECT coalesce(sum(deductible_balance),0) INTO l FROM wallet_ledger
    WHERE user_id = 'db18cead-6e46-4692-9b09-499841056796'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid
      AND currency = 'points' AND transaction_type = 'earn';
  IF abs(w - l) > 0.01 THEN
    RAISE EXCEPTION 'post-apply invariant user % wallet % lots %', 'db18cead-6e46-4692-9b09-499841056796', w, l;
  END IF;
END $v$;
COMMIT;
BEGIN;
UPDATE wallet_ledger SET deductible_balance = 351.0 WHERE id = '48950ad3-ea96-45ba-85cf-990e4ab3a9fd'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = 'e17610f1-8f95-446c-a32f-8cf20691d9ae'::uuid;
UPDATE wallet_ledger SET deductible_balance = 20.0 WHERE id = '64213f8c-0bc5-4a8e-9933-7c917eada2c1'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = 'e17610f1-8f95-446c-a32f-8cf20691d9ae'::uuid;
DO $v$
DECLARE w numeric; l numeric;
BEGIN
  SELECT points_balance INTO w FROM user_wallet WHERE user_id = 'e17610f1-8f95-446c-a32f-8cf20691d9ae'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid;
  SELECT coalesce(sum(deductible_balance),0) INTO l FROM wallet_ledger
    WHERE user_id = 'e17610f1-8f95-446c-a32f-8cf20691d9ae'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid
      AND currency = 'points' AND transaction_type = 'earn';
  IF abs(w - l) > 0.01 THEN
    RAISE EXCEPTION 'post-apply invariant user % wallet % lots %', 'e17610f1-8f95-446c-a32f-8cf20691d9ae', w, l;
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
  '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid, 'e244f0b8-ff81-49ad-8005-3d938c5c9ccc'::uuid,   'points'::currency, 'earn'::currency_transaction_type,
  'base'::currency_component,
  50, 50, 50,
  50, 50,
  'manual'::wallet_transaction_source_type, 'Legacy wallet balance', '{"backfill": "jorakay_wallet_lot_drift_20260912", "reason": "orphan_wallet_no_points_ledger"}'::jsonb,
  NULL, NULL,
  'e244f0b8-ff81-49ad-8005-3d938c5c9ccc', 'jorakay-orphan-65b1c10712e71882a7288863', '2026-06-15T00:00:00+00:00'::timestamptz, false
WHERE NOT EXISTS (
  SELECT 1 FROM wallet_ledger wl
  WHERE wl.merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND wl.dedup_key = 'jorakay-orphan-65b1c10712e71882a7288863'
);;
DO $v$
DECLARE w numeric; l numeric;
BEGIN
  SELECT points_balance INTO w FROM user_wallet WHERE user_id = 'e244f0b8-ff81-49ad-8005-3d938c5c9ccc'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid;
  SELECT coalesce(sum(deductible_balance),0) INTO l FROM wallet_ledger
    WHERE user_id = 'e244f0b8-ff81-49ad-8005-3d938c5c9ccc'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid
      AND currency = 'points' AND transaction_type = 'earn';
  IF abs(w - l) > 0.01 THEN
    RAISE EXCEPTION 'post-apply invariant user % wallet % lots %', 'e244f0b8-ff81-49ad-8005-3d938c5c9ccc', w, l;
  END IF;
END $v$;
COMMIT;
BEGIN;
UPDATE wallet_ledger SET deductible_balance = 101.0 WHERE id = 'a3e7f96c-0aef-4304-8a16-7c6d3a55139b'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = 'e4314cd7-0eff-4763-bf35-5a2016bdef97'::uuid;
UPDATE wallet_ledger SET deductible_balance = 31.0 WHERE id = 'e341f51f-994e-4509-9ddf-c3f23d7b1db7'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = 'e4314cd7-0eff-4763-bf35-5a2016bdef97'::uuid;
UPDATE wallet_ledger SET deductible_balance = 31.0 WHERE id = '7944d27a-5416-42da-8018-63396b66ca76'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = 'e4314cd7-0eff-4763-bf35-5a2016bdef97'::uuid;
UPDATE wallet_ledger SET deductible_balance = 343.0 WHERE id = 'f8a175e0-ef43-45c1-b270-a6e04a132eb7'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = 'e4314cd7-0eff-4763-bf35-5a2016bdef97'::uuid;
DO $v$
DECLARE w numeric; l numeric;
BEGIN
  SELECT points_balance INTO w FROM user_wallet WHERE user_id = 'e4314cd7-0eff-4763-bf35-5a2016bdef97'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid;
  SELECT coalesce(sum(deductible_balance),0) INTO l FROM wallet_ledger
    WHERE user_id = 'e4314cd7-0eff-4763-bf35-5a2016bdef97'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid
      AND currency = 'points' AND transaction_type = 'earn';
  IF abs(w - l) > 0.01 THEN
    RAISE EXCEPTION 'post-apply invariant user % wallet % lots %', 'e4314cd7-0eff-4763-bf35-5a2016bdef97', w, l;
  END IF;
END $v$;
COMMIT;
BEGIN;
UPDATE wallet_ledger SET deductible_balance = 0.0 WHERE id = '0023bdb6-2cd7-4dbf-abee-007cf62cf122'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = 'e5961962-0b82-404b-8aee-e7e793d4ec3a'::uuid;
UPDATE wallet_ledger SET deductible_balance = 0.0 WHERE id = '43e99477-7c18-4e7c-9676-eb864c76f906'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = 'e5961962-0b82-404b-8aee-e7e793d4ec3a'::uuid;
UPDATE wallet_ledger SET deductible_balance = 0.0 WHERE id = '1fa92b74-5dc5-491a-a6de-0ecc69d98b9c'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = 'e5961962-0b82-404b-8aee-e7e793d4ec3a'::uuid;
UPDATE wallet_ledger SET deductible_balance = 986.0 WHERE id = '10e05a7b-b941-469b-8023-a7f8e317b857'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = 'e5961962-0b82-404b-8aee-e7e793d4ec3a'::uuid;
DO $v$
DECLARE w numeric; l numeric;
BEGIN
  SELECT points_balance INTO w FROM user_wallet WHERE user_id = 'e5961962-0b82-404b-8aee-e7e793d4ec3a'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid;
  SELECT coalesce(sum(deductible_balance),0) INTO l FROM wallet_ledger
    WHERE user_id = 'e5961962-0b82-404b-8aee-e7e793d4ec3a'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid
      AND currency = 'points' AND transaction_type = 'earn';
  IF abs(w - l) > 0.01 THEN
    RAISE EXCEPTION 'post-apply invariant user % wallet % lots %', 'e5961962-0b82-404b-8aee-e7e793d4ec3a', w, l;
  END IF;
END $v$;
COMMIT;
BEGIN;
UPDATE wallet_ledger SET deductible_balance = 2186.0 WHERE id = '6f580c03-e0b5-49f8-b62e-e4e1efa87633'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = 'e667c9d3-1dbe-4173-b075-42fca35106eb'::uuid;
UPDATE wallet_ledger SET deductible_balance = 133.0 WHERE id = '53e6df5c-04b4-4f36-a951-bdf035d0732f'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = 'e667c9d3-1dbe-4173-b075-42fca35106eb'::uuid;
DO $v$
DECLARE w numeric; l numeric;
BEGIN
  SELECT points_balance INTO w FROM user_wallet WHERE user_id = 'e667c9d3-1dbe-4173-b075-42fca35106eb'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid;
  SELECT coalesce(sum(deductible_balance),0) INTO l FROM wallet_ledger
    WHERE user_id = 'e667c9d3-1dbe-4173-b075-42fca35106eb'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid
      AND currency = 'points' AND transaction_type = 'earn';
  IF abs(w - l) > 0.01 THEN
    RAISE EXCEPTION 'post-apply invariant user % wallet % lots %', 'e667c9d3-1dbe-4173-b075-42fca35106eb', w, l;
  END IF;
END $v$;
COMMIT;
