BEGIN;
UPDATE wallet_ledger SET deductible_balance = 0.0 WHERE id = '6541777f-ac1b-431f-8006-fc70a46639cb'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = '60d71d67-6bb0-4c55-833a-75ceabd95e79'::uuid;
UPDATE wallet_ledger SET deductible_balance = 0.0 WHERE id = 'ff6dfa79-daa8-417a-ae5e-e52f393ecc35'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = '60d71d67-6bb0-4c55-833a-75ceabd95e79'::uuid;
UPDATE wallet_ledger SET deductible_balance = 0.0 WHERE id = 'cfd59a13-f9e4-469d-8c5a-2d44f8735e43'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = '60d71d67-6bb0-4c55-833a-75ceabd95e79'::uuid;
UPDATE wallet_ledger SET deductible_balance = 0.0 WHERE id = '01cce576-3385-4b53-b343-5e8d33b51198'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = '60d71d67-6bb0-4c55-833a-75ceabd95e79'::uuid;
UPDATE wallet_ledger SET deductible_balance = 0.0 WHERE id = 'cc232b16-c781-4037-a293-c789d7a0dcd0'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = '60d71d67-6bb0-4c55-833a-75ceabd95e79'::uuid;
DO $v$
DECLARE w numeric; l numeric;
BEGIN
  SELECT points_balance INTO w FROM user_wallet WHERE user_id = '60d71d67-6bb0-4c55-833a-75ceabd95e79'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid;
  SELECT coalesce(sum(deductible_balance),0) INTO l FROM wallet_ledger
    WHERE user_id = '60d71d67-6bb0-4c55-833a-75ceabd95e79'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid
      AND currency = 'points' AND transaction_type = 'earn';
  IF abs(w - l) > 0.01 THEN
    RAISE EXCEPTION 'post-apply invariant user % wallet % lots %', '60d71d67-6bb0-4c55-833a-75ceabd95e79', w, l;
  END IF;
END $v$;
COMMIT;
BEGIN;
UPDATE wallet_ledger SET deductible_balance = 0.0 WHERE id = '5b3e5a7a-c22a-4ada-a5b9-a1a4c16254db'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = '6529876b-b923-428c-830e-369c19b596a4'::uuid;
UPDATE wallet_ledger SET deductible_balance = 0.0 WHERE id = '91898399-fc42-4633-aedb-f648115371e9'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = '6529876b-b923-428c-830e-369c19b596a4'::uuid;
UPDATE wallet_ledger SET deductible_balance = 0.0 WHERE id = '0fe6b67d-0f2f-4edd-9876-c71ce053a431'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = '6529876b-b923-428c-830e-369c19b596a4'::uuid;
UPDATE wallet_ledger SET deductible_balance = 0.0 WHERE id = 'a34c4ec0-7e1f-4ebd-ada6-55df0828b1b4'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = '6529876b-b923-428c-830e-369c19b596a4'::uuid;
UPDATE wallet_ledger SET deductible_balance = 0.0 WHERE id = '3705851c-4ce3-46d3-a66d-3a45810fbdb3'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = '6529876b-b923-428c-830e-369c19b596a4'::uuid;
UPDATE wallet_ledger SET deductible_balance = 0.0 WHERE id = '433ed560-0808-4163-9745-fdf3281df80b'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = '6529876b-b923-428c-830e-369c19b596a4'::uuid;
UPDATE wallet_ledger SET deductible_balance = 4296.0 WHERE id = 'bd3666c2-dcdd-43c0-8ae1-d60db1894a13'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = '6529876b-b923-428c-830e-369c19b596a4'::uuid;
UPDATE wallet_ledger SET deductible_balance = 3450.0 WHERE id = '9744a62e-e0ce-4f72-9c54-0dbaa735f578'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = '6529876b-b923-428c-830e-369c19b596a4'::uuid;
UPDATE wallet_ledger SET deductible_balance = 875.0 WHERE id = '72ab5d72-8a75-4626-938f-d5fb7a4074d8'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = '6529876b-b923-428c-830e-369c19b596a4'::uuid;
UPDATE wallet_ledger SET deductible_balance = 1740.0 WHERE id = 'af2e4862-8cd2-42bb-aa64-4a3f57fed94d'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = '6529876b-b923-428c-830e-369c19b596a4'::uuid;
UPDATE wallet_ledger SET deductible_balance = 1675.0 WHERE id = '14b70d65-9926-423f-8a2a-c99c4443a25d'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = '6529876b-b923-428c-830e-369c19b596a4'::uuid;
UPDATE wallet_ledger SET deductible_balance = 1890.0 WHERE id = '5ab7aa0e-f5f3-48f0-840d-ab54858d3e7b'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = '6529876b-b923-428c-830e-369c19b596a4'::uuid;
UPDATE wallet_ledger SET deductible_balance = 1675.0 WHERE id = '2f098f8e-2117-4173-b2e2-9cfbd7ce4195'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = '6529876b-b923-428c-830e-369c19b596a4'::uuid;
UPDATE wallet_ledger SET deductible_balance = 875.0 WHERE id = 'b1c10386-ec2b-4c4b-b347-7eeac57e8f8f'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = '6529876b-b923-428c-830e-369c19b596a4'::uuid;
DO $v$
DECLARE w numeric; l numeric;
BEGIN
  SELECT points_balance INTO w FROM user_wallet WHERE user_id = '6529876b-b923-428c-830e-369c19b596a4'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid;
  SELECT coalesce(sum(deductible_balance),0) INTO l FROM wallet_ledger
    WHERE user_id = '6529876b-b923-428c-830e-369c19b596a4'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid
      AND currency = 'points' AND transaction_type = 'earn';
  IF abs(w - l) > 0.01 THEN
    RAISE EXCEPTION 'post-apply invariant user % wallet % lots %', '6529876b-b923-428c-830e-369c19b596a4', w, l;
  END IF;
END $v$;
COMMIT;
BEGIN;
UPDATE wallet_ledger SET deductible_balance = 13.0 WHERE id = '8842b952-8d3f-4b6a-bfd9-d86ea08d8c67'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = '65e0d8e2-b7e8-476a-934e-ee0b2613f6ca'::uuid;
UPDATE wallet_ledger SET deductible_balance = 4.0 WHERE id = '3aa9ff98-1d52-4fde-bdef-924aacb35b17'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = '65e0d8e2-b7e8-476a-934e-ee0b2613f6ca'::uuid;
UPDATE wallet_ledger SET deductible_balance = 33.0 WHERE id = '4db20a95-2d9b-4578-b048-088e1dd698de'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = '65e0d8e2-b7e8-476a-934e-ee0b2613f6ca'::uuid;
UPDATE wallet_ledger SET deductible_balance = 19.0 WHERE id = '78835071-a5c0-4356-bb8f-e1fff1841f4a'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = '65e0d8e2-b7e8-476a-934e-ee0b2613f6ca'::uuid;
UPDATE wallet_ledger SET deductible_balance = 52.0 WHERE id = 'c766ba0c-b394-40d8-b566-570ca9acc272'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = '65e0d8e2-b7e8-476a-934e-ee0b2613f6ca'::uuid;
UPDATE wallet_ledger SET deductible_balance = 13.0 WHERE id = '53349db0-acce-49d5-b1d6-ddf286b0fa83'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = '65e0d8e2-b7e8-476a-934e-ee0b2613f6ca'::uuid;
UPDATE wallet_ledger SET deductible_balance = 6.0 WHERE id = '8ddbef20-afa9-4052-af2c-85f6a5e9e2f9'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = '65e0d8e2-b7e8-476a-934e-ee0b2613f6ca'::uuid;
UPDATE wallet_ledger SET deductible_balance = 65.0 WHERE id = 'e541dbc5-7498-4edb-aa71-acafc73c09df'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = '65e0d8e2-b7e8-476a-934e-ee0b2613f6ca'::uuid;
DO $v$
DECLARE w numeric; l numeric;
BEGIN
  SELECT points_balance INTO w FROM user_wallet WHERE user_id = '65e0d8e2-b7e8-476a-934e-ee0b2613f6ca'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid;
  SELECT coalesce(sum(deductible_balance),0) INTO l FROM wallet_ledger
    WHERE user_id = '65e0d8e2-b7e8-476a-934e-ee0b2613f6ca'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid
      AND currency = 'points' AND transaction_type = 'earn';
  IF abs(w - l) > 0.01 THEN
    RAISE EXCEPTION 'post-apply invariant user % wallet % lots %', '65e0d8e2-b7e8-476a-934e-ee0b2613f6ca', w, l;
  END IF;
END $v$;
COMMIT;
BEGIN;
UPDATE user_wallet SET points_balance = 1979.0 WHERE user_id = '6761dc57-bcf6-4d5f-a1a0-16c0610a3ac3'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid;
DO $v$
DECLARE w numeric; l numeric;
BEGIN
  SELECT points_balance INTO w FROM user_wallet WHERE user_id = '6761dc57-bcf6-4d5f-a1a0-16c0610a3ac3'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid;
  SELECT coalesce(sum(deductible_balance),0) INTO l FROM wallet_ledger
    WHERE user_id = '6761dc57-bcf6-4d5f-a1a0-16c0610a3ac3'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid
      AND currency = 'points' AND transaction_type = 'earn';
  IF abs(w - l) > 0.01 THEN
    RAISE EXCEPTION 'post-apply invariant user % wallet % lots %', '6761dc57-bcf6-4d5f-a1a0-16c0610a3ac3', w, l;
  END IF;
END $v$;
COMMIT;
BEGIN;
UPDATE wallet_ledger SET deductible_balance = 172.0 WHERE id = '6be02717-6f23-4924-859b-690cadf631bf'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = '680b8024-e029-4ea4-8f2a-98ad3a284d14'::uuid;
UPDATE wallet_ledger SET deductible_balance = 232.0 WHERE id = '1fcf8f24-aa91-4c23-abc7-6339b86afb02'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = '680b8024-e029-4ea4-8f2a-98ad3a284d14'::uuid;
UPDATE wallet_ledger SET deductible_balance = 45.0 WHERE id = '8a310add-2a08-4228-99d0-8f832c1e3c35'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = '680b8024-e029-4ea4-8f2a-98ad3a284d14'::uuid;
UPDATE wallet_ledger SET deductible_balance = 101.0 WHERE id = '58705415-f7ab-41fb-940f-664bd899d620'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = '680b8024-e029-4ea4-8f2a-98ad3a284d14'::uuid;
DO $v$
DECLARE w numeric; l numeric;
BEGIN
  SELECT points_balance INTO w FROM user_wallet WHERE user_id = '680b8024-e029-4ea4-8f2a-98ad3a284d14'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid;
  SELECT coalesce(sum(deductible_balance),0) INTO l FROM wallet_ledger
    WHERE user_id = '680b8024-e029-4ea4-8f2a-98ad3a284d14'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid
      AND currency = 'points' AND transaction_type = 'earn';
  IF abs(w - l) > 0.01 THEN
    RAISE EXCEPTION 'post-apply invariant user % wallet % lots %', '680b8024-e029-4ea4-8f2a-98ad3a284d14', w, l;
  END IF;
END $v$;
COMMIT;
BEGIN;
UPDATE wallet_ledger SET deductible_balance = 118.0 WHERE id = '001a6d75-b6a4-42d1-83fb-9428dd8e6b17'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = '692c20ac-b496-4d26-a695-39bf755e61f2'::uuid;
DO $v$
DECLARE w numeric; l numeric;
BEGIN
  SELECT points_balance INTO w FROM user_wallet WHERE user_id = '692c20ac-b496-4d26-a695-39bf755e61f2'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid;
  SELECT coalesce(sum(deductible_balance),0) INTO l FROM wallet_ledger
    WHERE user_id = '692c20ac-b496-4d26-a695-39bf755e61f2'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid
      AND currency = 'points' AND transaction_type = 'earn';
  IF abs(w - l) > 0.01 THEN
    RAISE EXCEPTION 'post-apply invariant user % wallet % lots %', '692c20ac-b496-4d26-a695-39bf755e61f2', w, l;
  END IF;
END $v$;
COMMIT;
BEGIN;
UPDATE wallet_ledger SET deductible_balance = 351.0 WHERE id = 'dfe66d0e-e40a-4ea5-9af1-45f46920fdd2'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = '69a18985-553a-40b5-bfa2-605e6959a26e'::uuid;
DO $v$
DECLARE w numeric; l numeric;
BEGIN
  SELECT points_balance INTO w FROM user_wallet WHERE user_id = '69a18985-553a-40b5-bfa2-605e6959a26e'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid;
  SELECT coalesce(sum(deductible_balance),0) INTO l FROM wallet_ledger
    WHERE user_id = '69a18985-553a-40b5-bfa2-605e6959a26e'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid
      AND currency = 'points' AND transaction_type = 'earn';
  IF abs(w - l) > 0.01 THEN
    RAISE EXCEPTION 'post-apply invariant user % wallet % lots %', '69a18985-553a-40b5-bfa2-605e6959a26e', w, l;
  END IF;
END $v$;
COMMIT;
BEGIN;
UPDATE wallet_ledger SET deductible_balance = 62.0 WHERE id = 'bc767d2a-54ef-43aa-909c-c46ff123520c'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = '6a7bbfc6-50aa-4acb-9713-fc848f21dc14'::uuid;
DO $v$
DECLARE w numeric; l numeric;
BEGIN
  SELECT points_balance INTO w FROM user_wallet WHERE user_id = '6a7bbfc6-50aa-4acb-9713-fc848f21dc14'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid;
  SELECT coalesce(sum(deductible_balance),0) INTO l FROM wallet_ledger
    WHERE user_id = '6a7bbfc6-50aa-4acb-9713-fc848f21dc14'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid
      AND currency = 'points' AND transaction_type = 'earn';
  IF abs(w - l) > 0.01 THEN
    RAISE EXCEPTION 'post-apply invariant user % wallet % lots %', '6a7bbfc6-50aa-4acb-9713-fc848f21dc14', w, l;
  END IF;
END $v$;
COMMIT;
BEGIN;
UPDATE wallet_ledger SET deductible_balance = 396.0 WHERE id = 'a377e829-a948-411d-b5ea-1ddde650a90d'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = '6aacf6c5-4b10-40ea-a3e3-e9a056637a0b'::uuid;
UPDATE wallet_ledger SET deductible_balance = 60.0 WHERE id = '56b11ce5-de8b-4143-8a10-998471cb0b27'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = '6aacf6c5-4b10-40ea-a3e3-e9a056637a0b'::uuid;
DO $v$
DECLARE w numeric; l numeric;
BEGIN
  SELECT points_balance INTO w FROM user_wallet WHERE user_id = '6aacf6c5-4b10-40ea-a3e3-e9a056637a0b'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid;
  SELECT coalesce(sum(deductible_balance),0) INTO l FROM wallet_ledger
    WHERE user_id = '6aacf6c5-4b10-40ea-a3e3-e9a056637a0b'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid
      AND currency = 'points' AND transaction_type = 'earn';
  IF abs(w - l) > 0.01 THEN
    RAISE EXCEPTION 'post-apply invariant user % wallet % lots %', '6aacf6c5-4b10-40ea-a3e3-e9a056637a0b', w, l;
  END IF;
END $v$;
COMMIT;
BEGIN;
UPDATE wallet_ledger SET deductible_balance = 0.0 WHERE id = '259628e9-7747-4cfa-8ff8-09e42c09221f'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = '6ac3a95a-0f78-4603-800d-3354c9a2b345'::uuid;
UPDATE wallet_ledger SET deductible_balance = 0.0 WHERE id = '8e030e09-7466-4995-b799-d508d475f921'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = '6ac3a95a-0f78-4603-800d-3354c9a2b345'::uuid;
UPDATE wallet_ledger SET deductible_balance = 0.0 WHERE id = 'ee582c1f-8173-4af1-8711-1f7c3b33dfff'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = '6ac3a95a-0f78-4603-800d-3354c9a2b345'::uuid;
UPDATE wallet_ledger SET deductible_balance = 0.0 WHERE id = '67258ccc-8d00-4ecb-9e44-a96c6be0132c'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = '6ac3a95a-0f78-4603-800d-3354c9a2b345'::uuid;
UPDATE wallet_ledger SET deductible_balance = 0.0 WHERE id = '9938880e-0bc4-4d6c-8493-c4bb64987dca'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = '6ac3a95a-0f78-4603-800d-3354c9a2b345'::uuid;
UPDATE wallet_ledger SET deductible_balance = 0.0 WHERE id = 'c703a0ef-a838-470a-b5ca-f0bb938dc9ec'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = '6ac3a95a-0f78-4603-800d-3354c9a2b345'::uuid;
UPDATE wallet_ledger SET deductible_balance = 0.0 WHERE id = '5863dc1e-e9bd-4848-8e48-8bc64677e0fa'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = '6ac3a95a-0f78-4603-800d-3354c9a2b345'::uuid;
UPDATE wallet_ledger SET deductible_balance = 0.0 WHERE id = 'c7927c8b-b84c-4dde-bba3-4ce09c1ab570'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = '6ac3a95a-0f78-4603-800d-3354c9a2b345'::uuid;
UPDATE wallet_ledger SET deductible_balance = 0.0 WHERE id = '26de7792-738f-4d9a-9258-c67393caed7e'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = '6ac3a95a-0f78-4603-800d-3354c9a2b345'::uuid;
UPDATE wallet_ledger SET deductible_balance = 0.0 WHERE id = '7c9d6e71-5731-4c1d-8ab0-df6ceafc53bd'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = '6ac3a95a-0f78-4603-800d-3354c9a2b345'::uuid;
UPDATE wallet_ledger SET deductible_balance = 0.0 WHERE id = '276e76de-6ca0-4d32-8b75-22c5f9fcbb4e'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = '6ac3a95a-0f78-4603-800d-3354c9a2b345'::uuid;
UPDATE wallet_ledger SET deductible_balance = 0.0 WHERE id = '34c6e2c5-e83c-4f7b-bd5c-198494166b9c'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = '6ac3a95a-0f78-4603-800d-3354c9a2b345'::uuid;
UPDATE wallet_ledger SET deductible_balance = 0.0 WHERE id = '795d5d03-767a-43d3-837d-40a92b39bdb1'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = '6ac3a95a-0f78-4603-800d-3354c9a2b345'::uuid;
UPDATE wallet_ledger SET deductible_balance = 0.0 WHERE id = '785e7cba-056a-48ce-8366-4777ca64300b'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = '6ac3a95a-0f78-4603-800d-3354c9a2b345'::uuid;
UPDATE wallet_ledger SET deductible_balance = 0.0 WHERE id = '0b54fe90-cd14-4491-8448-18e8bc64017a'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = '6ac3a95a-0f78-4603-800d-3354c9a2b345'::uuid;
UPDATE wallet_ledger SET deductible_balance = 0.0 WHERE id = '5d6c3302-cca2-4ad0-a876-c5d61df0f8db'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = '6ac3a95a-0f78-4603-800d-3354c9a2b345'::uuid;
UPDATE wallet_ledger SET deductible_balance = 0.0 WHERE id = '87c896d7-cc69-4ff5-9e94-956b2f03e6d8'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = '6ac3a95a-0f78-4603-800d-3354c9a2b345'::uuid;
UPDATE wallet_ledger SET deductible_balance = 0.0 WHERE id = '3f01ca13-f5a7-4b6d-a559-8ba2061f59bf'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = '6ac3a95a-0f78-4603-800d-3354c9a2b345'::uuid;
UPDATE wallet_ledger SET deductible_balance = 0.0 WHERE id = 'ee8a0d48-715a-4cf9-a3a5-5c3d89202cb3'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = '6ac3a95a-0f78-4603-800d-3354c9a2b345'::uuid;
UPDATE wallet_ledger SET deductible_balance = 0.0 WHERE id = 'ee2e9574-e42c-46ee-acf3-5231cba7684d'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = '6ac3a95a-0f78-4603-800d-3354c9a2b345'::uuid;
UPDATE wallet_ledger SET deductible_balance = 0.0 WHERE id = '9371f431-2d3e-4f14-8f14-ff35b316a790'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = '6ac3a95a-0f78-4603-800d-3354c9a2b345'::uuid;
UPDATE wallet_ledger SET deductible_balance = 0.0 WHERE id = '92f268cb-f8d5-45f9-b320-5174dc218bae'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = '6ac3a95a-0f78-4603-800d-3354c9a2b345'::uuid;
UPDATE wallet_ledger SET deductible_balance = 0.0 WHERE id = 'cc1e73de-80df-483e-80e5-042d7c58ef35'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = '6ac3a95a-0f78-4603-800d-3354c9a2b345'::uuid;
UPDATE wallet_ledger SET deductible_balance = 0.0 WHERE id = '444c1566-0b7d-475e-8138-d55b54df2471'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = '6ac3a95a-0f78-4603-800d-3354c9a2b345'::uuid;
UPDATE wallet_ledger SET deductible_balance = 0.0 WHERE id = '76651ea3-2bd4-48dd-9129-a719f44c02b1'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = '6ac3a95a-0f78-4603-800d-3354c9a2b345'::uuid;
UPDATE wallet_ledger SET deductible_balance = 0.0 WHERE id = '1a78053a-7253-4a02-968b-2df74d738ff8'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = '6ac3a95a-0f78-4603-800d-3354c9a2b345'::uuid;
UPDATE wallet_ledger SET deductible_balance = 0.0 WHERE id = 'c633e32d-5412-44ae-a368-8e24f96dd5e0'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = '6ac3a95a-0f78-4603-800d-3354c9a2b345'::uuid;
DO $v$
DECLARE w numeric; l numeric;
BEGIN
  SELECT points_balance INTO w FROM user_wallet WHERE user_id = '6ac3a95a-0f78-4603-800d-3354c9a2b345'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid;
  SELECT coalesce(sum(deductible_balance),0) INTO l FROM wallet_ledger
    WHERE user_id = '6ac3a95a-0f78-4603-800d-3354c9a2b345'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid
      AND currency = 'points' AND transaction_type = 'earn';
  IF abs(w - l) > 0.01 THEN
    RAISE EXCEPTION 'post-apply invariant user % wallet % lots %', '6ac3a95a-0f78-4603-800d-3354c9a2b345', w, l;
  END IF;
END $v$;
COMMIT;
BEGIN;
UPDATE wallet_ledger SET deductible_balance = 6889.0 WHERE id = '3b1acfe5-4e31-44c1-8483-7c188771d61e'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = '6cce9025-1504-49f5-a51a-02c0aefd576b'::uuid;
UPDATE wallet_ledger SET deductible_balance = 618.0 WHERE id = '65f72556-b789-4f4b-ba32-36bc7b00765f'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = '6cce9025-1504-49f5-a51a-02c0aefd576b'::uuid;
UPDATE wallet_ledger SET deductible_balance = 360.0 WHERE id = 'dbb21154-64c3-4a26-841e-bf55322437f2'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = '6cce9025-1504-49f5-a51a-02c0aefd576b'::uuid;
UPDATE wallet_ledger SET deductible_balance = 360.0 WHERE id = 'c86bf6da-fe89-4e08-b030-63ec62fc063c'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = '6cce9025-1504-49f5-a51a-02c0aefd576b'::uuid;
DO $v$
DECLARE w numeric; l numeric;
BEGIN
  SELECT points_balance INTO w FROM user_wallet WHERE user_id = '6cce9025-1504-49f5-a51a-02c0aefd576b'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid;
  SELECT coalesce(sum(deductible_balance),0) INTO l FROM wallet_ledger
    WHERE user_id = '6cce9025-1504-49f5-a51a-02c0aefd576b'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid
      AND currency = 'points' AND transaction_type = 'earn';
  IF abs(w - l) > 0.01 THEN
    RAISE EXCEPTION 'post-apply invariant user % wallet % lots %', '6cce9025-1504-49f5-a51a-02c0aefd576b', w, l;
  END IF;
END $v$;
COMMIT;
BEGIN;
UPDATE wallet_ledger SET deductible_balance = 116.0 WHERE id = '0dd99d04-b15e-4fe8-b674-79d7f7264492'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = '6d40f5ec-da82-4a81-b382-6f508b344708'::uuid;
UPDATE wallet_ledger SET deductible_balance = 110.0 WHERE id = '21f2ec06-fd83-45c4-bafa-625844f24fd0'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = '6d40f5ec-da82-4a81-b382-6f508b344708'::uuid;
DO $v$
DECLARE w numeric; l numeric;
BEGIN
  SELECT points_balance INTO w FROM user_wallet WHERE user_id = '6d40f5ec-da82-4a81-b382-6f508b344708'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid;
  SELECT coalesce(sum(deductible_balance),0) INTO l FROM wallet_ledger
    WHERE user_id = '6d40f5ec-da82-4a81-b382-6f508b344708'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid
      AND currency = 'points' AND transaction_type = 'earn';
  IF abs(w - l) > 0.01 THEN
    RAISE EXCEPTION 'post-apply invariant user % wallet % lots %', '6d40f5ec-da82-4a81-b382-6f508b344708', w, l;
  END IF;
END $v$;
COMMIT;
BEGIN;
UPDATE wallet_ledger SET deductible_balance = 0.0 WHERE id = 'ed39b501-1a32-467f-b59a-8339bcbd7f9e'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = '6d4210a7-b37e-47b0-af1b-cbe8387bb12d'::uuid;
UPDATE wallet_ledger SET deductible_balance = 21.0 WHERE id = 'bd29e6f9-5333-4481-a116-c807748e1586'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = '6d4210a7-b37e-47b0-af1b-cbe8387bb12d'::uuid;
DO $v$
DECLARE w numeric; l numeric;
BEGIN
  SELECT points_balance INTO w FROM user_wallet WHERE user_id = '6d4210a7-b37e-47b0-af1b-cbe8387bb12d'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid;
  SELECT coalesce(sum(deductible_balance),0) INTO l FROM wallet_ledger
    WHERE user_id = '6d4210a7-b37e-47b0-af1b-cbe8387bb12d'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid
      AND currency = 'points' AND transaction_type = 'earn';
  IF abs(w - l) > 0.01 THEN
    RAISE EXCEPTION 'post-apply invariant user % wallet % lots %', '6d4210a7-b37e-47b0-af1b-cbe8387bb12d', w, l;
  END IF;
END $v$;
COMMIT;
BEGIN;
UPDATE wallet_ledger SET deductible_balance = 235.0 WHERE id = '208e1bdb-e6e1-4166-bd19-58f0d684fe21'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = '6d60ddf9-c4b2-4186-9714-6cfe86aca1d4'::uuid;
UPDATE wallet_ledger SET deductible_balance = 99.0 WHERE id = '48d3e978-bd17-4eb6-a454-450a785d5b1d'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = '6d60ddf9-c4b2-4186-9714-6cfe86aca1d4'::uuid;
UPDATE wallet_ledger SET deductible_balance = 317.0 WHERE id = '62a03967-2007-42c3-8bf9-67613727e0ac'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = '6d60ddf9-c4b2-4186-9714-6cfe86aca1d4'::uuid;
UPDATE wallet_ledger SET deductible_balance = 421.0 WHERE id = '67e1e25a-eade-4066-869d-ce49821fc50c'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = '6d60ddf9-c4b2-4186-9714-6cfe86aca1d4'::uuid;
UPDATE wallet_ledger SET deductible_balance = 301.0 WHERE id = '8b95f4c4-a653-4b67-bc03-8308b452b5ec'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = '6d60ddf9-c4b2-4186-9714-6cfe86aca1d4'::uuid;
UPDATE wallet_ledger SET deductible_balance = 160.0 WHERE id = '0ab79992-c65b-43d4-a97d-a0f47c322e1f'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = '6d60ddf9-c4b2-4186-9714-6cfe86aca1d4'::uuid;
UPDATE wallet_ledger SET deductible_balance = 496.0 WHERE id = 'dad6ab02-a4e8-4a4f-b0e3-333f2bb483fb'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = '6d60ddf9-c4b2-4186-9714-6cfe86aca1d4'::uuid;
UPDATE wallet_ledger SET deductible_balance = 270.0 WHERE id = '7a805d79-64cd-4e75-a40a-6cde178c4e21'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = '6d60ddf9-c4b2-4186-9714-6cfe86aca1d4'::uuid;
UPDATE wallet_ledger SET deductible_balance = 228.0 WHERE id = '4cf84317-2913-41ea-ba4f-f6540c82c49a'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = '6d60ddf9-c4b2-4186-9714-6cfe86aca1d4'::uuid;
UPDATE wallet_ledger SET deductible_balance = 726.0 WHERE id = '328ddec6-3d22-4895-a72f-8f12d636a21f'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = '6d60ddf9-c4b2-4186-9714-6cfe86aca1d4'::uuid;
UPDATE wallet_ledger SET deductible_balance = 188.0 WHERE id = '6fb56672-9d33-46b7-afd8-b646bd993586'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = '6d60ddf9-c4b2-4186-9714-6cfe86aca1d4'::uuid;
DO $v$
DECLARE w numeric; l numeric;
BEGIN
  SELECT points_balance INTO w FROM user_wallet WHERE user_id = '6d60ddf9-c4b2-4186-9714-6cfe86aca1d4'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid;
  SELECT coalesce(sum(deductible_balance),0) INTO l FROM wallet_ledger
    WHERE user_id = '6d60ddf9-c4b2-4186-9714-6cfe86aca1d4'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid
      AND currency = 'points' AND transaction_type = 'earn';
  IF abs(w - l) > 0.01 THEN
    RAISE EXCEPTION 'post-apply invariant user % wallet % lots %', '6d60ddf9-c4b2-4186-9714-6cfe86aca1d4', w, l;
  END IF;
END $v$;
COMMIT;
BEGIN;
UPDATE wallet_ledger SET deductible_balance = 246.0 WHERE id = '123f8f07-252a-4a62-bacb-dc8418d0ebcf'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = '6dbd4113-887a-4205-a3f8-2b0c31afa666'::uuid;
UPDATE wallet_ledger SET deductible_balance = 1062.0 WHERE id = '16bc2110-2540-42ac-85f4-c49aeeedee41'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = '6dbd4113-887a-4205-a3f8-2b0c31afa666'::uuid;
UPDATE wallet_ledger SET deductible_balance = 654.0 WHERE id = '38a4efb6-92b6-4342-85ba-663f4de0342e'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = '6dbd4113-887a-4205-a3f8-2b0c31afa666'::uuid;
UPDATE wallet_ledger SET deductible_balance = 1091.0 WHERE id = '132eb630-5a1a-49df-8aff-97aa45f15ff1'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = '6dbd4113-887a-4205-a3f8-2b0c31afa666'::uuid;
DO $v$
DECLARE w numeric; l numeric;
BEGIN
  SELECT points_balance INTO w FROM user_wallet WHERE user_id = '6dbd4113-887a-4205-a3f8-2b0c31afa666'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid;
  SELECT coalesce(sum(deductible_balance),0) INTO l FROM wallet_ledger
    WHERE user_id = '6dbd4113-887a-4205-a3f8-2b0c31afa666'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid
      AND currency = 'points' AND transaction_type = 'earn';
  IF abs(w - l) > 0.01 THEN
    RAISE EXCEPTION 'post-apply invariant user % wallet % lots %', '6dbd4113-887a-4205-a3f8-2b0c31afa666', w, l;
  END IF;
END $v$;
COMMIT;
BEGIN;
UPDATE wallet_ledger SET deductible_balance = 0.0 WHERE id = '65b463a2-5b04-4e72-9aec-0b06f40071aa'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = '6f19b2a6-a193-4180-a39c-e00f2e0f6d21'::uuid;
UPDATE wallet_ledger SET deductible_balance = 123.0 WHERE id = 'e11f320c-c79a-43fa-bce2-12c5e0c230a3'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = '6f19b2a6-a193-4180-a39c-e00f2e0f6d21'::uuid;
UPDATE wallet_ledger SET deductible_balance = 531.0 WHERE id = '6619394d-9ff4-4bae-8aa3-14020ae12b0e'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = '6f19b2a6-a193-4180-a39c-e00f2e0f6d21'::uuid;
DO $v$
DECLARE w numeric; l numeric;
BEGIN
  SELECT points_balance INTO w FROM user_wallet WHERE user_id = '6f19b2a6-a193-4180-a39c-e00f2e0f6d21'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid;
  SELECT coalesce(sum(deductible_balance),0) INTO l FROM wallet_ledger
    WHERE user_id = '6f19b2a6-a193-4180-a39c-e00f2e0f6d21'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid
      AND currency = 'points' AND transaction_type = 'earn';
  IF abs(w - l) > 0.01 THEN
    RAISE EXCEPTION 'post-apply invariant user % wallet % lots %', '6f19b2a6-a193-4180-a39c-e00f2e0f6d21', w, l;
  END IF;
END $v$;
COMMIT;
BEGIN;
UPDATE user_wallet SET points_balance = 1188.0 WHERE user_id = '6f264737-7583-48ab-ab51-28193e758805'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid;
DO $v$
DECLARE w numeric; l numeric;
BEGIN
  SELECT points_balance INTO w FROM user_wallet WHERE user_id = '6f264737-7583-48ab-ab51-28193e758805'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid;
  SELECT coalesce(sum(deductible_balance),0) INTO l FROM wallet_ledger
    WHERE user_id = '6f264737-7583-48ab-ab51-28193e758805'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid
      AND currency = 'points' AND transaction_type = 'earn';
  IF abs(w - l) > 0.01 THEN
    RAISE EXCEPTION 'post-apply invariant user % wallet % lots %', '6f264737-7583-48ab-ab51-28193e758805', w, l;
  END IF;
END $v$;
COMMIT;
BEGIN;
UPDATE wallet_ledger SET deductible_balance = 81.0 WHERE id = '110cfa8b-aecf-4785-8add-86fa710f923e'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = '6f3c7f2d-c6e7-405f-aefc-bdbe9c85d4de'::uuid;
DO $v$
DECLARE w numeric; l numeric;
BEGIN
  SELECT points_balance INTO w FROM user_wallet WHERE user_id = '6f3c7f2d-c6e7-405f-aefc-bdbe9c85d4de'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid;
  SELECT coalesce(sum(deductible_balance),0) INTO l FROM wallet_ledger
    WHERE user_id = '6f3c7f2d-c6e7-405f-aefc-bdbe9c85d4de'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid
      AND currency = 'points' AND transaction_type = 'earn';
  IF abs(w - l) > 0.01 THEN
    RAISE EXCEPTION 'post-apply invariant user % wallet % lots %', '6f3c7f2d-c6e7-405f-aefc-bdbe9c85d4de', w, l;
  END IF;
END $v$;
COMMIT;
BEGIN;
UPDATE wallet_ledger SET deductible_balance = 0.0 WHERE id = '7c548d0b-3f2a-4254-b8ff-674b03332d7d'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = '75b78f9f-5219-4021-9364-c24009c8264a'::uuid;
UPDATE wallet_ledger SET deductible_balance = 0.0 WHERE id = '3fe086ab-22de-4f91-a54c-666c2d4ef429'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = '75b78f9f-5219-4021-9364-c24009c8264a'::uuid;
UPDATE wallet_ledger SET deductible_balance = 0.0 WHERE id = '0ee77071-e6b7-44d1-9566-6f3fc8c1e00f'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = '75b78f9f-5219-4021-9364-c24009c8264a'::uuid;
UPDATE wallet_ledger SET deductible_balance = 0.0 WHERE id = '0f44c672-0317-4909-8d8c-be8b9f6ccef3'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = '75b78f9f-5219-4021-9364-c24009c8264a'::uuid;
UPDATE wallet_ledger SET deductible_balance = 0.0 WHERE id = '9630208c-d524-4915-916a-4a1db9fbff0d'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = '75b78f9f-5219-4021-9364-c24009c8264a'::uuid;
DO $v$
DECLARE w numeric; l numeric;
BEGIN
  SELECT points_balance INTO w FROM user_wallet WHERE user_id = '75b78f9f-5219-4021-9364-c24009c8264a'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid;
  SELECT coalesce(sum(deductible_balance),0) INTO l FROM wallet_ledger
    WHERE user_id = '75b78f9f-5219-4021-9364-c24009c8264a'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid
      AND currency = 'points' AND transaction_type = 'earn';
  IF abs(w - l) > 0.01 THEN
    RAISE EXCEPTION 'post-apply invariant user % wallet % lots %', '75b78f9f-5219-4021-9364-c24009c8264a', w, l;
  END IF;
END $v$;
COMMIT;
BEGIN;
UPDATE wallet_ledger SET deductible_balance = 0.0 WHERE id = '37666400-dace-4763-9794-e8775c3a69d1'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = '76fa88d8-bc11-442b-a82e-568f00ae858e'::uuid;
UPDATE wallet_ledger SET deductible_balance = 0.0 WHERE id = '91f48782-4d52-4bbd-a753-444cc9800048'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = '76fa88d8-bc11-442b-a82e-568f00ae858e'::uuid;
UPDATE wallet_ledger SET deductible_balance = 0.0 WHERE id = 'ce034de7-9a3c-4f48-8139-4edc60fe6430'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = '76fa88d8-bc11-442b-a82e-568f00ae858e'::uuid;
UPDATE wallet_ledger SET deductible_balance = 0.0 WHERE id = 'da086e49-f08e-4c71-a35d-71cd66691ffc'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = '76fa88d8-bc11-442b-a82e-568f00ae858e'::uuid;
UPDATE wallet_ledger SET deductible_balance = 0.0 WHERE id = '2e0f2210-0c10-4186-b0d0-2c44c2695735'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = '76fa88d8-bc11-442b-a82e-568f00ae858e'::uuid;
UPDATE wallet_ledger SET deductible_balance = 0.0 WHERE id = '1ce56762-91a3-4a32-8682-edd272fae811'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = '76fa88d8-bc11-442b-a82e-568f00ae858e'::uuid;
UPDATE wallet_ledger SET deductible_balance = 0.0 WHERE id = 'a96aa784-3d89-4a3c-99da-7b5db9e97ad4'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = '76fa88d8-bc11-442b-a82e-568f00ae858e'::uuid;
UPDATE wallet_ledger SET deductible_balance = 0.0 WHERE id = 'fda2c42a-edef-44c4-b17d-50b32347a403'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = '76fa88d8-bc11-442b-a82e-568f00ae858e'::uuid;
UPDATE wallet_ledger SET deductible_balance = 104.0 WHERE id = 'c0f0ff6b-8615-4882-82d3-3bde684e220b'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = '76fa88d8-bc11-442b-a82e-568f00ae858e'::uuid;
UPDATE wallet_ledger SET deductible_balance = 440.0 WHERE id = '2b324e93-bf5d-4e6f-8c71-9f31e3619916'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = '76fa88d8-bc11-442b-a82e-568f00ae858e'::uuid;
DO $v$
DECLARE w numeric; l numeric;
BEGIN
  SELECT points_balance INTO w FROM user_wallet WHERE user_id = '76fa88d8-bc11-442b-a82e-568f00ae858e'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid;
  SELECT coalesce(sum(deductible_balance),0) INTO l FROM wallet_ledger
    WHERE user_id = '76fa88d8-bc11-442b-a82e-568f00ae858e'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid
      AND currency = 'points' AND transaction_type = 'earn';
  IF abs(w - l) > 0.01 THEN
    RAISE EXCEPTION 'post-apply invariant user % wallet % lots %', '76fa88d8-bc11-442b-a82e-568f00ae858e', w, l;
  END IF;
END $v$;
COMMIT;
