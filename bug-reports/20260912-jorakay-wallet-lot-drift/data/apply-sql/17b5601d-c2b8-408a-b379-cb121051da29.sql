BEGIN;
UPDATE wallet_ledger SET deductible_balance = 0.0 WHERE id = '3e68139a-3cf3-4a7f-82d8-62d5e01fa5b0'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = '17b5601d-c2b8-408a-b379-cb121051da29'::uuid;
UPDATE wallet_ledger SET deductible_balance = 0.0 WHERE id = 'a912a00d-9c8f-42e3-99e8-7d0bdb6f2610'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = '17b5601d-c2b8-408a-b379-cb121051da29'::uuid;
UPDATE wallet_ledger SET deductible_balance = 0.0 WHERE id = '5cd31692-0c41-480a-8264-7889d8ba255c'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = '17b5601d-c2b8-408a-b379-cb121051da29'::uuid;
UPDATE wallet_ledger SET deductible_balance = 2157.0 WHERE id = '7e185d93-1744-4856-b14b-3504490fc8f0'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND user_id = '17b5601d-c2b8-408a-b379-cb121051da29'::uuid;
DO $v$
DECLARE w numeric; l numeric;
BEGIN
  SELECT points_balance INTO w FROM user_wallet WHERE user_id = '17b5601d-c2b8-408a-b379-cb121051da29'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid;
  SELECT coalesce(sum(deductible_balance),0) INTO l FROM wallet_ledger
    WHERE user_id = '17b5601d-c2b8-408a-b379-cb121051da29'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid
      AND currency = 'points' AND transaction_type = 'earn';
  IF abs(w - l) > 0.01 THEN
    RAISE EXCEPTION 'post-apply invariant user % wallet % lots %', '17b5601d-c2b8-408a-b379-cb121051da29', w, l;
  END IF;
END $v$;
COMMIT;
