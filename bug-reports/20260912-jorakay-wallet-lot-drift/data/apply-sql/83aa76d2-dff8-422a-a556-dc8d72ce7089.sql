BEGIN;
UPDATE wallet_ledger SET deductible_balance = 1563.0 WHERE id = '5f4d1e99-175e-4a75-9219-f86db88f95dc'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = '83aa76d2-dff8-422a-a556-dc8d72ce7089'::uuid;
DO $v$
DECLARE w numeric; l numeric;
BEGIN
  SELECT points_balance INTO w FROM user_wallet WHERE user_id = '83aa76d2-dff8-422a-a556-dc8d72ce7089'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid;
  SELECT coalesce(sum(deductible_balance),0) INTO l FROM wallet_ledger
    WHERE user_id = '83aa76d2-dff8-422a-a556-dc8d72ce7089'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid
      AND currency = 'points' AND transaction_type = 'earn';
  IF abs(w - l) > 0.01 THEN
    RAISE EXCEPTION 'post-apply invariant user % wallet % lots %', '83aa76d2-dff8-422a-a556-dc8d72ce7089', w, l;
  END IF;
END $v$;
COMMIT;
