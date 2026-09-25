BEGIN;
UPDATE wallet_ledger SET deductible_balance = 308.0 WHERE id = '50cc2499-6202-4401-b4c8-9463b307c6d3'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = '18ae7a19-0965-40dc-b165-2d1147b22ddc'::uuid;
UPDATE wallet_ledger SET deductible_balance = 604.0 WHERE id = '244a8d9a-596c-409d-883a-6bdf78e73bae'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = '18ae7a19-0965-40dc-b165-2d1147b22ddc'::uuid;
DO $v$
DECLARE w numeric; l numeric;
BEGIN
  SELECT points_balance INTO w FROM user_wallet WHERE user_id = '18ae7a19-0965-40dc-b165-2d1147b22ddc'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid;
  SELECT coalesce(sum(deductible_balance),0) INTO l FROM wallet_ledger
    WHERE user_id = '18ae7a19-0965-40dc-b165-2d1147b22ddc'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid
      AND currency = 'points' AND transaction_type = 'earn';
  IF abs(w - l) > 0.01 THEN
    RAISE EXCEPTION 'post-apply invariant user % wallet % lots %', '18ae7a19-0965-40dc-b165-2d1147b22ddc', w, l;
  END IF;
END $v$;
COMMIT;
