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
