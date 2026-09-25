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
