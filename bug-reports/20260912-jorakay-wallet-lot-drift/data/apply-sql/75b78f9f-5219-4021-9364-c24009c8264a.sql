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
