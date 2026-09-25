BEGIN;
UPDATE wallet_ledger SET deductible_balance = 154.0 WHERE id = '4c306b1e-1ad7-426c-93a3-7aac4b360743'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = 'a75a274d-1bf2-421a-ae37-4c99ad6f2116'::uuid;
DO $v$
DECLARE w numeric; l numeric;
BEGIN
  SELECT points_balance INTO w FROM user_wallet WHERE user_id = 'a75a274d-1bf2-421a-ae37-4c99ad6f2116'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid;
  SELECT coalesce(sum(deductible_balance),0) INTO l FROM wallet_ledger
    WHERE user_id = 'a75a274d-1bf2-421a-ae37-4c99ad6f2116'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid
      AND currency = 'points' AND transaction_type = 'earn';
  IF abs(w - l) > 0.01 THEN
    RAISE EXCEPTION 'post-apply invariant user % wallet % lots %', 'a75a274d-1bf2-421a-ae37-4c99ad6f2116', w, l;
  END IF;
END $v$;
COMMIT;
BEGIN;
UPDATE wallet_ledger SET deductible_balance = 0.0 WHERE id = '80cfc38d-482f-4ff5-bf48-b3c06440437a'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = 'a89f1104-c0f2-42e3-9735-5cb96506f5ae'::uuid;
UPDATE wallet_ledger SET deductible_balance = 0.0 WHERE id = 'c09a2804-27e2-4f0e-83f4-86cc9441935f'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = 'a89f1104-c0f2-42e3-9735-5cb96506f5ae'::uuid;
UPDATE wallet_ledger SET deductible_balance = 470.0 WHERE id = 'dbc19908-5bde-4896-b3b9-cdd718635776'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = 'a89f1104-c0f2-42e3-9735-5cb96506f5ae'::uuid;
UPDATE user_wallet SET points_balance = 7402.0 WHERE user_id = 'a89f1104-c0f2-42e3-9735-5cb96506f5ae'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid;
DO $v$
DECLARE w numeric; l numeric;
BEGIN
  SELECT points_balance INTO w FROM user_wallet WHERE user_id = 'a89f1104-c0f2-42e3-9735-5cb96506f5ae'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid;
  SELECT coalesce(sum(deductible_balance),0) INTO l FROM wallet_ledger
    WHERE user_id = 'a89f1104-c0f2-42e3-9735-5cb96506f5ae'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid
      AND currency = 'points' AND transaction_type = 'earn';
  IF abs(w - l) > 0.01 THEN
    RAISE EXCEPTION 'post-apply invariant user % wallet % lots %', 'a89f1104-c0f2-42e3-9735-5cb96506f5ae', w, l;
  END IF;
END $v$;
COMMIT;
BEGIN;
UPDATE wallet_ledger SET deductible_balance = 280.0 WHERE id = '2961d2cb-8655-4667-b6ec-a13c4df46963'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = 'a8b16c7b-9930-4e67-8ae3-f8a219ca51c6'::uuid;
UPDATE wallet_ledger SET deductible_balance = 56.0 WHERE id = '2b8baf23-add6-41d0-87df-15fb4462010d'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = 'a8b16c7b-9930-4e67-8ae3-f8a219ca51c6'::uuid;
UPDATE wallet_ledger SET deductible_balance = 1825.0 WHERE id = 'e521b2bf-1642-4693-b973-a41ef1f1da1e'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = 'a8b16c7b-9930-4e67-8ae3-f8a219ca51c6'::uuid;
UPDATE wallet_ledger SET deductible_balance = 1825.0 WHERE id = '445d90f7-e0c6-480e-bf4e-fb6ac7fae18f'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = 'a8b16c7b-9930-4e67-8ae3-f8a219ca51c6'::uuid;
UPDATE wallet_ledger SET deductible_balance = 936.0 WHERE id = '5cad1a3a-316d-451b-95fb-68a687fe11ee'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = 'a8b16c7b-9930-4e67-8ae3-f8a219ca51c6'::uuid;
UPDATE wallet_ledger SET deductible_balance = 78.0 WHERE id = '921d4487-b8fd-4f83-8471-d29d4e7d4b1e'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = 'a8b16c7b-9930-4e67-8ae3-f8a219ca51c6'::uuid;
UPDATE wallet_ledger SET deductible_balance = 147.0 WHERE id = '45ea6170-56b5-40e0-87cf-7a867f4d67f7'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = 'a8b16c7b-9930-4e67-8ae3-f8a219ca51c6'::uuid;
UPDATE wallet_ledger SET deductible_balance = 63.0 WHERE id = 'ccf0af20-95e1-4f58-87e7-98f3a1c51341'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = 'a8b16c7b-9930-4e67-8ae3-f8a219ca51c6'::uuid;
UPDATE wallet_ledger SET deductible_balance = 500.0 WHERE id = 'd2e49ac5-0523-4735-8d8c-c7e4e234728d'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = 'a8b16c7b-9930-4e67-8ae3-f8a219ca51c6'::uuid;
UPDATE wallet_ledger SET deductible_balance = 1445.0 WHERE id = '3b7851e9-caad-47b0-b5f5-3e00f620172d'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = 'a8b16c7b-9930-4e67-8ae3-f8a219ca51c6'::uuid;
UPDATE wallet_ledger SET deductible_balance = 33.0 WHERE id = '6d264951-d62c-4ae4-8927-4120a21c608a'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = 'a8b16c7b-9930-4e67-8ae3-f8a219ca51c6'::uuid;
UPDATE wallet_ledger SET deductible_balance = 510.0 WHERE id = '23329ded-d964-4803-b24e-493c6f4ceb54'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = 'a8b16c7b-9930-4e67-8ae3-f8a219ca51c6'::uuid;
UPDATE wallet_ledger SET deductible_balance = 2059.0 WHERE id = '1d1c72b6-976e-4155-a133-4ada1cdadd1f'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = 'a8b16c7b-9930-4e67-8ae3-f8a219ca51c6'::uuid;
DO $v$
DECLARE w numeric; l numeric;
BEGIN
  SELECT points_balance INTO w FROM user_wallet WHERE user_id = 'a8b16c7b-9930-4e67-8ae3-f8a219ca51c6'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid;
  SELECT coalesce(sum(deductible_balance),0) INTO l FROM wallet_ledger
    WHERE user_id = 'a8b16c7b-9930-4e67-8ae3-f8a219ca51c6'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid
      AND currency = 'points' AND transaction_type = 'earn';
  IF abs(w - l) > 0.01 THEN
    RAISE EXCEPTION 'post-apply invariant user % wallet % lots %', 'a8b16c7b-9930-4e67-8ae3-f8a219ca51c6', w, l;
  END IF;
END $v$;
COMMIT;
BEGIN;
UPDATE wallet_ledger SET deductible_balance = 4.0 WHERE id = '050677b7-93cc-4ecf-b2e7-5cf68d55ea53'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = 'a9afdd18-4840-41a0-81c1-a75ef1fb2a14'::uuid;
DO $v$
DECLARE w numeric; l numeric;
BEGIN
  SELECT points_balance INTO w FROM user_wallet WHERE user_id = 'a9afdd18-4840-41a0-81c1-a75ef1fb2a14'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid;
  SELECT coalesce(sum(deductible_balance),0) INTO l FROM wallet_ledger
    WHERE user_id = 'a9afdd18-4840-41a0-81c1-a75ef1fb2a14'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid
      AND currency = 'points' AND transaction_type = 'earn';
  IF abs(w - l) > 0.01 THEN
    RAISE EXCEPTION 'post-apply invariant user % wallet % lots %', 'a9afdd18-4840-41a0-81c1-a75ef1fb2a14', w, l;
  END IF;
END $v$;
COMMIT;
BEGIN;
UPDATE wallet_ledger SET deductible_balance = 0.0 WHERE id = 'bddff06e-d047-4d7e-b611-520e387b3f8d'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = 'aa7161bc-7cd6-4fec-bc36-83ebf135ad53'::uuid;
DO $v$
DECLARE w numeric; l numeric;
BEGIN
  SELECT points_balance INTO w FROM user_wallet WHERE user_id = 'aa7161bc-7cd6-4fec-bc36-83ebf135ad53'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid;
  SELECT coalesce(sum(deductible_balance),0) INTO l FROM wallet_ledger
    WHERE user_id = 'aa7161bc-7cd6-4fec-bc36-83ebf135ad53'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid
      AND currency = 'points' AND transaction_type = 'earn';
  IF abs(w - l) > 0.01 THEN
    RAISE EXCEPTION 'post-apply invariant user % wallet % lots %', 'aa7161bc-7cd6-4fec-bc36-83ebf135ad53', w, l;
  END IF;
END $v$;
COMMIT;
BEGIN;
UPDATE wallet_ledger SET deductible_balance = 0.0 WHERE id = '232bfbcc-d9de-4b53-8354-de02da82a766'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = 'ab0eed90-6825-4c0c-bc94-f327cbc141e0'::uuid;
UPDATE wallet_ledger SET deductible_balance = 0.0 WHERE id = '6c81650a-5809-4c13-98b7-98b3b9630cfc'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = 'ab0eed90-6825-4c0c-bc94-f327cbc141e0'::uuid;
UPDATE wallet_ledger SET deductible_balance = 0.0 WHERE id = '72f4cdd0-4b5f-4385-93b0-ae7345f9fa41'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = 'ab0eed90-6825-4c0c-bc94-f327cbc141e0'::uuid;
UPDATE wallet_ledger SET deductible_balance = 0.0 WHERE id = '962a325f-81d0-4f02-a272-7fd52e922eaa'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = 'ab0eed90-6825-4c0c-bc94-f327cbc141e0'::uuid;
UPDATE wallet_ledger SET deductible_balance = 0.0 WHERE id = '63559fa6-d7e7-41e0-807a-9519ba65c027'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = 'ab0eed90-6825-4c0c-bc94-f327cbc141e0'::uuid;
UPDATE wallet_ledger SET deductible_balance = 7.0 WHERE id = '1d8140e8-8c76-4ffd-8e23-0a06ae0fa11c'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = 'ab0eed90-6825-4c0c-bc94-f327cbc141e0'::uuid;
DO $v$
DECLARE w numeric; l numeric;
BEGIN
  SELECT points_balance INTO w FROM user_wallet WHERE user_id = 'ab0eed90-6825-4c0c-bc94-f327cbc141e0'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid;
  SELECT coalesce(sum(deductible_balance),0) INTO l FROM wallet_ledger
    WHERE user_id = 'ab0eed90-6825-4c0c-bc94-f327cbc141e0'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid
      AND currency = 'points' AND transaction_type = 'earn';
  IF abs(w - l) > 0.01 THEN
    RAISE EXCEPTION 'post-apply invariant user % wallet % lots %', 'ab0eed90-6825-4c0c-bc94-f327cbc141e0', w, l;
  END IF;
END $v$;
COMMIT;
BEGIN;
UPDATE wallet_ledger SET deductible_balance = 6.0 WHERE id = '9ed87747-d607-4ef0-80be-32e4635ecbdd'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = 'ab7067cd-213a-4539-a05a-634f2f7a2617'::uuid;
UPDATE wallet_ledger SET deductible_balance = 16.0 WHERE id = 'ac6dd9ef-361a-4a89-b8b3-84e3f19f6c20'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = 'ab7067cd-213a-4539-a05a-634f2f7a2617'::uuid;
UPDATE wallet_ledger SET deductible_balance = 10.0 WHERE id = '702a80f4-3550-4dfa-80e3-f162a5fd0c64'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = 'ab7067cd-213a-4539-a05a-634f2f7a2617'::uuid;
UPDATE wallet_ledger SET deductible_balance = 21.0 WHERE id = '31641e68-79f6-4001-a34c-8c2350ca7028'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = 'ab7067cd-213a-4539-a05a-634f2f7a2617'::uuid;
UPDATE wallet_ledger SET deductible_balance = 92.0 WHERE id = '315abc74-2127-4a43-a029-6af9939a0e2c'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = 'ab7067cd-213a-4539-a05a-634f2f7a2617'::uuid;
UPDATE wallet_ledger SET deductible_balance = 21.0 WHERE id = '7186733f-c59a-4e36-9483-e5eb8d0c9548'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = 'ab7067cd-213a-4539-a05a-634f2f7a2617'::uuid;
UPDATE wallet_ledger SET deductible_balance = 21.0 WHERE id = '0f630542-caf6-4202-8c69-fcd3ab9b4558'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = 'ab7067cd-213a-4539-a05a-634f2f7a2617'::uuid;
UPDATE wallet_ledger SET deductible_balance = 6.0 WHERE id = '693dbb50-66ec-452d-83ac-a34aa6a4199d'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = 'ab7067cd-213a-4539-a05a-634f2f7a2617'::uuid;
UPDATE wallet_ledger SET deductible_balance = 20.0 WHERE id = 'c7f25459-7e8b-4b16-995b-ebbef0e1bbbe'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = 'ab7067cd-213a-4539-a05a-634f2f7a2617'::uuid;
UPDATE wallet_ledger SET deductible_balance = 4.0 WHERE id = '4f20e8e3-2de4-4ebf-97b1-d9ab1539de0c'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = 'ab7067cd-213a-4539-a05a-634f2f7a2617'::uuid;
UPDATE wallet_ledger SET deductible_balance = 20.0 WHERE id = 'f92ffe2d-316d-4d27-a2b6-bfb8bfdc957d'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = 'ab7067cd-213a-4539-a05a-634f2f7a2617'::uuid;
UPDATE wallet_ledger SET deductible_balance = 23.0 WHERE id = '8485c023-a2f0-4dd0-955b-81526bd8352e'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = 'ab7067cd-213a-4539-a05a-634f2f7a2617'::uuid;
DO $v$
DECLARE w numeric; l numeric;
BEGIN
  SELECT points_balance INTO w FROM user_wallet WHERE user_id = 'ab7067cd-213a-4539-a05a-634f2f7a2617'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid;
  SELECT coalesce(sum(deductible_balance),0) INTO l FROM wallet_ledger
    WHERE user_id = 'ab7067cd-213a-4539-a05a-634f2f7a2617'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid
      AND currency = 'points' AND transaction_type = 'earn';
  IF abs(w - l) > 0.01 THEN
    RAISE EXCEPTION 'post-apply invariant user % wallet % lots %', 'ab7067cd-213a-4539-a05a-634f2f7a2617', w, l;
  END IF;
END $v$;
COMMIT;
BEGIN;
UPDATE wallet_ledger SET deductible_balance = 57.0 WHERE id = '89ed6e90-c378-412d-b9a1-dfe2d432d47a'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = 'ac6af112-d0ca-44b7-b03b-5b9ccf08188a'::uuid;
DO $v$
DECLARE w numeric; l numeric;
BEGIN
  SELECT points_balance INTO w FROM user_wallet WHERE user_id = 'ac6af112-d0ca-44b7-b03b-5b9ccf08188a'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid;
  SELECT coalesce(sum(deductible_balance),0) INTO l FROM wallet_ledger
    WHERE user_id = 'ac6af112-d0ca-44b7-b03b-5b9ccf08188a'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid
      AND currency = 'points' AND transaction_type = 'earn';
  IF abs(w - l) > 0.01 THEN
    RAISE EXCEPTION 'post-apply invariant user % wallet % lots %', 'ac6af112-d0ca-44b7-b03b-5b9ccf08188a', w, l;
  END IF;
END $v$;
COMMIT;
BEGIN;
UPDATE wallet_ledger SET deductible_balance = 0.0 WHERE id = 'c8a5e4ef-035c-4944-8856-a77642d03bd8'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = 'aceddd39-a50e-4604-8ed6-766e4c10c5fc'::uuid;
UPDATE wallet_ledger SET deductible_balance = 996.0 WHERE id = 'b1ee5a1b-d0de-4dde-afa1-ee0ae31c1e9d'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = 'aceddd39-a50e-4604-8ed6-766e4c10c5fc'::uuid;
DO $v$
DECLARE w numeric; l numeric;
BEGIN
  SELECT points_balance INTO w FROM user_wallet WHERE user_id = 'aceddd39-a50e-4604-8ed6-766e4c10c5fc'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid;
  SELECT coalesce(sum(deductible_balance),0) INTO l FROM wallet_ledger
    WHERE user_id = 'aceddd39-a50e-4604-8ed6-766e4c10c5fc'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid
      AND currency = 'points' AND transaction_type = 'earn';
  IF abs(w - l) > 0.01 THEN
    RAISE EXCEPTION 'post-apply invariant user % wallet % lots %', 'aceddd39-a50e-4604-8ed6-766e4c10c5fc', w, l;
  END IF;
END $v$;
COMMIT;
BEGIN;
UPDATE wallet_ledger SET deductible_balance = 324.0 WHERE id = '4e662f4c-00c0-41b6-a11d-edb66d103a3f'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = 'b12070ac-a9be-4a4d-aac2-9a8f86f12706'::uuid;
DO $v$
DECLARE w numeric; l numeric;
BEGIN
  SELECT points_balance INTO w FROM user_wallet WHERE user_id = 'b12070ac-a9be-4a4d-aac2-9a8f86f12706'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid;
  SELECT coalesce(sum(deductible_balance),0) INTO l FROM wallet_ledger
    WHERE user_id = 'b12070ac-a9be-4a4d-aac2-9a8f86f12706'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid
      AND currency = 'points' AND transaction_type = 'earn';
  IF abs(w - l) > 0.01 THEN
    RAISE EXCEPTION 'post-apply invariant user % wallet % lots %', 'b12070ac-a9be-4a4d-aac2-9a8f86f12706', w, l;
  END IF;
END $v$;
COMMIT;
BEGIN;
UPDATE wallet_ledger SET deductible_balance = 69.0 WHERE id = 'b6dcb660-38a0-4c88-9705-788ab0f7ca22'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = 'b1519aa8-088f-47fb-9112-75a36865ce88'::uuid;
UPDATE wallet_ledger SET deductible_balance = 61.0 WHERE id = 'f9f7d261-f0bc-403b-8abc-ad6c566cf44b'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = 'b1519aa8-088f-47fb-9112-75a36865ce88'::uuid;
DO $v$
DECLARE w numeric; l numeric;
BEGIN
  SELECT points_balance INTO w FROM user_wallet WHERE user_id = 'b1519aa8-088f-47fb-9112-75a36865ce88'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid;
  SELECT coalesce(sum(deductible_balance),0) INTO l FROM wallet_ledger
    WHERE user_id = 'b1519aa8-088f-47fb-9112-75a36865ce88'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid
      AND currency = 'points' AND transaction_type = 'earn';
  IF abs(w - l) > 0.01 THEN
    RAISE EXCEPTION 'post-apply invariant user % wallet % lots %', 'b1519aa8-088f-47fb-9112-75a36865ce88', w, l;
  END IF;
END $v$;
COMMIT;
BEGIN;
UPDATE wallet_ledger SET deductible_balance = 125.0 WHERE id = 'f544fcb0-e1ab-4b93-937e-86e2bd3d41a9'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = 'b1e302da-8d97-46de-80dd-e8956425eeac'::uuid;
UPDATE wallet_ledger SET deductible_balance = 36.0 WHERE id = 'd74bf7f1-d8a9-4c26-b3b9-5e3ed0827e1d'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = 'b1e302da-8d97-46de-80dd-e8956425eeac'::uuid;
UPDATE wallet_ledger SET deductible_balance = 1.0 WHERE id = '3e674da9-29dd-452d-921c-8fe1583df745'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = 'b1e302da-8d97-46de-80dd-e8956425eeac'::uuid;
UPDATE wallet_ledger SET deductible_balance = 13.0 WHERE id = '7fb8c3c9-b762-4a8a-bba8-36ad2ebc6514'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = 'b1e302da-8d97-46de-80dd-e8956425eeac'::uuid;
UPDATE wallet_ledger SET deductible_balance = 4.0 WHERE id = '176716b6-e1ca-4de0-be55-ada4e9df7795'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = 'b1e302da-8d97-46de-80dd-e8956425eeac'::uuid;
DO $v$
DECLARE w numeric; l numeric;
BEGIN
  SELECT points_balance INTO w FROM user_wallet WHERE user_id = 'b1e302da-8d97-46de-80dd-e8956425eeac'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid;
  SELECT coalesce(sum(deductible_balance),0) INTO l FROM wallet_ledger
    WHERE user_id = 'b1e302da-8d97-46de-80dd-e8956425eeac'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid
      AND currency = 'points' AND transaction_type = 'earn';
  IF abs(w - l) > 0.01 THEN
    RAISE EXCEPTION 'post-apply invariant user % wallet % lots %', 'b1e302da-8d97-46de-80dd-e8956425eeac', w, l;
  END IF;
END $v$;
COMMIT;
BEGIN;
UPDATE wallet_ledger SET deductible_balance = 228.0 WHERE id = 'd45cfb90-f62a-434f-ab6e-c2a6ff3de709'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = 'b70ace42-b432-425c-b560-29d235ac262e'::uuid;
DO $v$
DECLARE w numeric; l numeric;
BEGIN
  SELECT points_balance INTO w FROM user_wallet WHERE user_id = 'b70ace42-b432-425c-b560-29d235ac262e'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid;
  SELECT coalesce(sum(deductible_balance),0) INTO l FROM wallet_ledger
    WHERE user_id = 'b70ace42-b432-425c-b560-29d235ac262e'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid
      AND currency = 'points' AND transaction_type = 'earn';
  IF abs(w - l) > 0.01 THEN
    RAISE EXCEPTION 'post-apply invariant user % wallet % lots %', 'b70ace42-b432-425c-b560-29d235ac262e', w, l;
  END IF;
END $v$;
COMMIT;
BEGIN;
UPDATE wallet_ledger SET deductible_balance = 15.0 WHERE id = 'c880d020-83cb-4a25-94fb-567defd395f6'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = 'b784671b-9957-46aa-8f8c-a25d5da2df44'::uuid;
DO $v$
DECLARE w numeric; l numeric;
BEGIN
  SELECT points_balance INTO w FROM user_wallet WHERE user_id = 'b784671b-9957-46aa-8f8c-a25d5da2df44'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid;
  SELECT coalesce(sum(deductible_balance),0) INTO l FROM wallet_ledger
    WHERE user_id = 'b784671b-9957-46aa-8f8c-a25d5da2df44'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid
      AND currency = 'points' AND transaction_type = 'earn';
  IF abs(w - l) > 0.01 THEN
    RAISE EXCEPTION 'post-apply invariant user % wallet % lots %', 'b784671b-9957-46aa-8f8c-a25d5da2df44', w, l;
  END IF;
END $v$;
COMMIT;
BEGIN;
UPDATE wallet_ledger SET deductible_balance = 272.0 WHERE id = '401bd253-890d-490f-bae5-6d93fd7c53b8'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = 'b941ce2b-978a-481b-9926-d155f5606896'::uuid;
UPDATE wallet_ledger SET deductible_balance = 397.0 WHERE id = 'df7fa792-1cb8-4eff-93eb-401bd4ee7003'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = 'b941ce2b-978a-481b-9926-d155f5606896'::uuid;
DO $v$
DECLARE w numeric; l numeric;
BEGIN
  SELECT points_balance INTO w FROM user_wallet WHERE user_id = 'b941ce2b-978a-481b-9926-d155f5606896'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid;
  SELECT coalesce(sum(deductible_balance),0) INTO l FROM wallet_ledger
    WHERE user_id = 'b941ce2b-978a-481b-9926-d155f5606896'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid
      AND currency = 'points' AND transaction_type = 'earn';
  IF abs(w - l) > 0.01 THEN
    RAISE EXCEPTION 'post-apply invariant user % wallet % lots %', 'b941ce2b-978a-481b-9926-d155f5606896', w, l;
  END IF;
END $v$;
COMMIT;
BEGIN;
UPDATE wallet_ledger SET deductible_balance = 0.0 WHERE id = '00bca89d-034f-44fd-82b4-2466843c1df9'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = 'b9e834c7-d060-4ae1-8609-b4abcdf3563c'::uuid;
UPDATE wallet_ledger SET deductible_balance = 0.0 WHERE id = '87a75200-c4a5-447f-9930-ef0eb27f7c5a'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = 'b9e834c7-d060-4ae1-8609-b4abcdf3563c'::uuid;
UPDATE wallet_ledger SET deductible_balance = 0.0 WHERE id = '26c4e43e-1dda-4736-8955-cace7e064633'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = 'b9e834c7-d060-4ae1-8609-b4abcdf3563c'::uuid;
UPDATE wallet_ledger SET deductible_balance = 0.0 WHERE id = '82bac54e-1878-4663-9d49-d1efa26ab551'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = 'b9e834c7-d060-4ae1-8609-b4abcdf3563c'::uuid;
UPDATE wallet_ledger SET deductible_balance = 0.0 WHERE id = 'ef4bbef4-07b0-4052-af39-9c8023a84aca'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = 'b9e834c7-d060-4ae1-8609-b4abcdf3563c'::uuid;
UPDATE wallet_ledger SET deductible_balance = 0.0 WHERE id = '3804b2e7-23bd-43fc-8972-7b02000a2353'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = 'b9e834c7-d060-4ae1-8609-b4abcdf3563c'::uuid;
UPDATE wallet_ledger SET deductible_balance = 0.0 WHERE id = 'cb54a86e-def0-47c6-bb71-9c792edf26a0'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = 'b9e834c7-d060-4ae1-8609-b4abcdf3563c'::uuid;
UPDATE wallet_ledger SET deductible_balance = 0.0 WHERE id = '2f1720d5-5b7c-4ecd-8ea6-6360f9b89497'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = 'b9e834c7-d060-4ae1-8609-b4abcdf3563c'::uuid;
UPDATE wallet_ledger SET deductible_balance = 0.0 WHERE id = '3e4ec2a9-be9c-4079-bc47-74ab6f994f72'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = 'b9e834c7-d060-4ae1-8609-b4abcdf3563c'::uuid;
UPDATE wallet_ledger SET deductible_balance = 0.0 WHERE id = '439365e9-83a1-4b49-8f44-84e4b6cd8052'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = 'b9e834c7-d060-4ae1-8609-b4abcdf3563c'::uuid;
UPDATE wallet_ledger SET deductible_balance = 0.0 WHERE id = '3480092f-0335-4588-9dcc-ba63c2119a8d'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = 'b9e834c7-d060-4ae1-8609-b4abcdf3563c'::uuid;
UPDATE wallet_ledger SET deductible_balance = 0.0 WHERE id = '2a63c2c2-8735-4580-a067-afe614854f08'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = 'b9e834c7-d060-4ae1-8609-b4abcdf3563c'::uuid;
UPDATE wallet_ledger SET deductible_balance = 0.0 WHERE id = '403e05ef-fad4-4299-b2ea-9e288ac14626'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = 'b9e834c7-d060-4ae1-8609-b4abcdf3563c'::uuid;
UPDATE wallet_ledger SET deductible_balance = 0.0 WHERE id = '5dabcf6b-2d86-4e15-be66-d4f42996974d'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = 'b9e834c7-d060-4ae1-8609-b4abcdf3563c'::uuid;
UPDATE wallet_ledger SET deductible_balance = 0.0 WHERE id = 'caa7fafb-fbbb-444a-9ee1-1a5bf3e1b8fc'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = 'b9e834c7-d060-4ae1-8609-b4abcdf3563c'::uuid;
UPDATE wallet_ledger SET deductible_balance = 0.0 WHERE id = '5b47a707-d7e1-468d-abe3-f29dd9e4683f'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = 'b9e834c7-d060-4ae1-8609-b4abcdf3563c'::uuid;
UPDATE wallet_ledger SET deductible_balance = 0.0 WHERE id = '8c6f8033-d7ca-47ba-ae8b-e0dc1416cbc7'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = 'b9e834c7-d060-4ae1-8609-b4abcdf3563c'::uuid;
UPDATE wallet_ledger SET deductible_balance = 0.0 WHERE id = '3afc5a89-0e1f-4623-a599-e2cca95d2125'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = 'b9e834c7-d060-4ae1-8609-b4abcdf3563c'::uuid;
UPDATE wallet_ledger SET deductible_balance = 0.0 WHERE id = '1526edac-1400-4dc9-9236-e7d9378e32d5'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = 'b9e834c7-d060-4ae1-8609-b4abcdf3563c'::uuid;
UPDATE wallet_ledger SET deductible_balance = 0.0 WHERE id = '04d27f69-82ee-4a1e-aef5-371065cb962b'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = 'b9e834c7-d060-4ae1-8609-b4abcdf3563c'::uuid;
UPDATE wallet_ledger SET deductible_balance = 925.0 WHERE id = '15f24dc4-d908-4dcd-8439-0ef6420c1fbd'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = 'b9e834c7-d060-4ae1-8609-b4abcdf3563c'::uuid;
DO $v$
DECLARE w numeric; l numeric;
BEGIN
  SELECT points_balance INTO w FROM user_wallet WHERE user_id = 'b9e834c7-d060-4ae1-8609-b4abcdf3563c'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid;
  SELECT coalesce(sum(deductible_balance),0) INTO l FROM wallet_ledger
    WHERE user_id = 'b9e834c7-d060-4ae1-8609-b4abcdf3563c'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid
      AND currency = 'points' AND transaction_type = 'earn';
  IF abs(w - l) > 0.01 THEN
    RAISE EXCEPTION 'post-apply invariant user % wallet % lots %', 'b9e834c7-d060-4ae1-8609-b4abcdf3563c', w, l;
  END IF;
END $v$;
COMMIT;
BEGIN;
UPDATE wallet_ledger SET deductible_balance = 104.0 WHERE id = '9000b8f3-c49c-42e9-8c5d-f20e91c330ec'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = 'c00110c8-2440-47d5-b36c-d12153debe62'::uuid;
UPDATE wallet_ledger SET deductible_balance = 140.0 WHERE id = '79d60703-89de-47ba-a63e-409e9e24de46'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = 'c00110c8-2440-47d5-b36c-d12153debe62'::uuid;
DO $v$
DECLARE w numeric; l numeric;
BEGIN
  SELECT points_balance INTO w FROM user_wallet WHERE user_id = 'c00110c8-2440-47d5-b36c-d12153debe62'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid;
  SELECT coalesce(sum(deductible_balance),0) INTO l FROM wallet_ledger
    WHERE user_id = 'c00110c8-2440-47d5-b36c-d12153debe62'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid
      AND currency = 'points' AND transaction_type = 'earn';
  IF abs(w - l) > 0.01 THEN
    RAISE EXCEPTION 'post-apply invariant user % wallet % lots %', 'c00110c8-2440-47d5-b36c-d12153debe62', w, l;
  END IF;
END $v$;
COMMIT;
BEGIN;
UPDATE wallet_ledger SET deductible_balance = 0.0 WHERE id = 'dde61b52-4865-4c76-ba26-9db16b456e5b'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = 'c0483745-a920-4af3-a5a9-f59defec06dc'::uuid;
UPDATE wallet_ledger SET deductible_balance = 0.0 WHERE id = 'ca686af1-dcf5-46b0-b736-ea4699596570'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = 'c0483745-a920-4af3-a5a9-f59defec06dc'::uuid;
UPDATE wallet_ledger SET deductible_balance = 0.0 WHERE id = 'f93d3754-364b-442d-9d0e-c54de47c862a'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = 'c0483745-a920-4af3-a5a9-f59defec06dc'::uuid;
UPDATE wallet_ledger SET deductible_balance = 0.0 WHERE id = '48ce7535-27ac-45ee-bb6f-2c26b69c5d98'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = 'c0483745-a920-4af3-a5a9-f59defec06dc'::uuid;
UPDATE wallet_ledger SET deductible_balance = 0.0 WHERE id = '03a4f9a5-d9c0-4c7b-b1e6-7ae001e96e5f'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = 'c0483745-a920-4af3-a5a9-f59defec06dc'::uuid;
DO $v$
DECLARE w numeric; l numeric;
BEGIN
  SELECT points_balance INTO w FROM user_wallet WHERE user_id = 'c0483745-a920-4af3-a5a9-f59defec06dc'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid;
  SELECT coalesce(sum(deductible_balance),0) INTO l FROM wallet_ledger
    WHERE user_id = 'c0483745-a920-4af3-a5a9-f59defec06dc'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid
      AND currency = 'points' AND transaction_type = 'earn';
  IF abs(w - l) > 0.01 THEN
    RAISE EXCEPTION 'post-apply invariant user % wallet % lots %', 'c0483745-a920-4af3-a5a9-f59defec06dc', w, l;
  END IF;
END $v$;
COMMIT;
BEGIN;
UPDATE wallet_ledger SET deductible_balance = 3.0 WHERE id = 'cbc672c2-40eb-49f4-9d33-380629dfbcb2'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = 'c10027e0-b861-4173-9d6b-6ad41627aaa5'::uuid;
UPDATE wallet_ledger SET deductible_balance = 1.0 WHERE id = '62097eab-4759-4a9d-8f91-4be577fb802c'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = 'c10027e0-b861-4173-9d6b-6ad41627aaa5'::uuid;
UPDATE wallet_ledger SET deductible_balance = 2.0 WHERE id = '283f47e9-a01f-4e26-a2ba-ca368f92e3cf'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = 'c10027e0-b861-4173-9d6b-6ad41627aaa5'::uuid;
UPDATE wallet_ledger SET deductible_balance = 6.0 WHERE id = '1e17b263-51c1-4297-9b98-a60a1f792526'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = 'c10027e0-b861-4173-9d6b-6ad41627aaa5'::uuid;
UPDATE wallet_ledger SET deductible_balance = 7.0 WHERE id = '58098f1e-7a0b-440f-b1bb-40d70d63be12'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = 'c10027e0-b861-4173-9d6b-6ad41627aaa5'::uuid;
DO $v$
DECLARE w numeric; l numeric;
BEGIN
  SELECT points_balance INTO w FROM user_wallet WHERE user_id = 'c10027e0-b861-4173-9d6b-6ad41627aaa5'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid;
  SELECT coalesce(sum(deductible_balance),0) INTO l FROM wallet_ledger
    WHERE user_id = 'c10027e0-b861-4173-9d6b-6ad41627aaa5'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid
      AND currency = 'points' AND transaction_type = 'earn';
  IF abs(w - l) > 0.01 THEN
    RAISE EXCEPTION 'post-apply invariant user % wallet % lots %', 'c10027e0-b861-4173-9d6b-6ad41627aaa5', w, l;
  END IF;
END $v$;
COMMIT;
BEGIN;
UPDATE wallet_ledger SET deductible_balance = 530.0 WHERE id = 'de5f460a-e6d1-4e7e-b690-84f845ecb1c6'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = 'c3a36840-ae4f-4995-9c2f-522410a8636f'::uuid;
UPDATE wallet_ledger SET deductible_balance = 530.0 WHERE id = '7e0ee72f-ea49-4551-aabd-70dd5a08d8c6'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = 'c3a36840-ae4f-4995-9c2f-522410a8636f'::uuid;
UPDATE wallet_ledger SET deductible_balance = 530.0 WHERE id = 'c77ee744-3866-4c4f-8a42-8e3f2247178e'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = 'c3a36840-ae4f-4995-9c2f-522410a8636f'::uuid;
UPDATE wallet_ledger SET deductible_balance = 530.0 WHERE id = 'bd5ebed4-30a5-44d6-a337-460d0008af2d'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = 'c3a36840-ae4f-4995-9c2f-522410a8636f'::uuid;
DO $v$
DECLARE w numeric; l numeric;
BEGIN
  SELECT points_balance INTO w FROM user_wallet WHERE user_id = 'c3a36840-ae4f-4995-9c2f-522410a8636f'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid;
  SELECT coalesce(sum(deductible_balance),0) INTO l FROM wallet_ledger
    WHERE user_id = 'c3a36840-ae4f-4995-9c2f-522410a8636f'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid
      AND currency = 'points' AND transaction_type = 'earn';
  IF abs(w - l) > 0.01 THEN
    RAISE EXCEPTION 'post-apply invariant user % wallet % lots %', 'c3a36840-ae4f-4995-9c2f-522410a8636f', w, l;
  END IF;
END $v$;
COMMIT;
