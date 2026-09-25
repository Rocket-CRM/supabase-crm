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
