BEGIN;
INSERT INTO wallet_ledger (
  merchant_id, user_id, currency, transaction_type, component,
  amount, signed_amount, balance_before, balance_after, deductible_balance,
  source_type, description, metadata, target_entity_id, expiry_date,
  created_by, dedup_key, created_at, skip_cdc
) SELECT
  '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid, '4201b34a-019d-49fe-b6f5-5d3c300a2e2d'::uuid,   'points'::currency, 'earn'::currency_transaction_type,
  'base'::currency_component,
  50, 50, 50,
  50, 50,
  'manual'::wallet_transaction_source_type, 'Legacy wallet balance', '{"backfill": "jorakay_wallet_lot_drift_20260912", "reason": "orphan_wallet_no_points_ledger"}'::jsonb,
  NULL, NULL,
  '4201b34a-019d-49fe-b6f5-5d3c300a2e2d', 'jorakay-orphan-65b1c32412e71882a72ae409', '2026-06-15T00:00:00+00:00'::timestamptz, false
WHERE NOT EXISTS (
  SELECT 1 FROM wallet_ledger wl
  WHERE wl.merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid AND wl.dedup_key = 'jorakay-orphan-65b1c32412e71882a72ae409'
);;
DO $v$
DECLARE w numeric; l numeric;
BEGIN
  SELECT points_balance INTO w FROM user_wallet WHERE user_id = '4201b34a-019d-49fe-b6f5-5d3c300a2e2d'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid;
  SELECT coalesce(sum(deductible_balance),0) INTO l FROM wallet_ledger
    WHERE user_id = '4201b34a-019d-49fe-b6f5-5d3c300a2e2d'::uuid AND merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid
      AND currency = 'points' AND transaction_type = 'earn';
  IF abs(w - l) > 0.01 THEN
    RAISE EXCEPTION 'post-apply invariant user % wallet % lots %', '4201b34a-019d-49fe-b6f5-5d3c300a2e2d', w, l;
  END IF;
END $v$;
COMMIT;
