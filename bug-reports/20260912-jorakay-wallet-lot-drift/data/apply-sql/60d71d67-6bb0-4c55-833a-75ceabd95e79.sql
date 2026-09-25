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
