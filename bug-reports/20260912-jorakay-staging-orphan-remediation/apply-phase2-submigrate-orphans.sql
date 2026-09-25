-- Phase 2: sub-migrate staging orphans (jorakay only). Direct SQL — no APIs, no user_wallet updates.
-- Run in order: purchases → receipts → earns → receipt link.
-- Optional: set migration.batch_min / migration.batch_max for chunked runs.

-- === 2a purchases (stg_sf_bills → purchase_ledger) ===
INSERT INTO purchase_ledger (
  mongo_id, merchant_id, transaction_number, transaction_date,
  total_amount, final_amount, discount_amount, discount_regular, discount_points,
  promo_code, tax_amount,
  payment_method, payment_status, store_id, store_code, user_id,
  status, transaction_type, transaction_source, currency,
  skip_cdc, processing_method, earn_currency, dedup_key, api_source, record_type
)
SELECT stg.mongo_id, mm.id,
  NULLIF(stg.raw->>'order_code', ''),
  COALESCE(
    NULLIF(stg.raw->>'created_date', '')::timestamptz,
    NULLIF(stg.raw->>'updated_date', '')::timestamptz,
    stg.created_at,
    stg.updated_at
  ),
  COALESCE((stg.raw->>'grand_total')::numeric, 0),
  COALESCE((stg.raw->>'net')::numeric, 0),
  (stg.raw->>'sum_discount')::numeric,
  (stg.raw->>'discount_regular')::numeric,
  (stg.raw->>'discount_in_baht_by_point')::numeric,
  NULLIF(btrim(stg.raw->'bigcommerce_coupon'->>'alien_code'), ''),
  (stg.raw->>'vat_total')::numeric,
  stg.raw->'payment_detail'->>'payment_type',
  CASE WHEN (stg.raw->'payment_detail'->>'is_paid')::boolean IS TRUE THEN 'paid' ELSE 'pending' END,
  sm.id, stg.raw->>'store_code', ua.id,
  CASE stg.raw->>'status'
    WHEN 'complete' THEN 'completed'
    WHEN 'pending' THEN 'pending'
    WHEN 'cancel' THEN 'cancelled'
    ELSE 'completed'
  END::purchase_status,
  CASE
    WHEN stg.raw->>'is_external_bill' IS NULL THEN 'pos'
    WHEN (stg.raw->>'is_external_bill')::boolean IS FALSE THEN 'pos'
    WHEN stg.raw->'source_detail'->>'source' = 'third party' THEN 'marketplace'
    ELSE 'receipt_upload'
  END,
  NULLIF(stg.raw->'source_detail'->>'channel', ''),
  stg.raw->>'currency',
  true, 'skip', false, 'legacy:'||stg.mongo_id, 'migration', 'credit'::purchase_record_type
FROM stg_sf_bills stg
JOIN merchant_master mm ON mm.id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid
LEFT JOIN store_master sm ON sm.mongo_id = stg.raw->>'store_id'
LEFT JOIN user_accounts ua ON ua.mongo_id = stg.raw->>'profile_id' AND ua.merchant_id = mm.id
WHERE stg.merchant_ref = '649e9524f43a5fc2f9705850'
  AND COALESCE((stg.raw->>'is_delete')::boolean, false) IS NOT TRUE
  AND COALESCE((stg.raw->>'is_bill_refund')::boolean, false) IS NOT TRUE
  AND COALESCE((stg.raw->>'is_refunded')::boolean, false) IS NOT TRUE
  AND NOT EXISTS (
    SELECT 1 FROM purchase_ledger pl
    WHERE pl.merchant_id = mm.id AND pl.mongo_id = stg.mongo_id
  )
  AND (
    COALESCE(current_setting('migration.batch_min', true), '') = ''
    OR stg.mongo_id >= current_setting('migration.batch_min', true)
  )
  AND (
    COALESCE(current_setting('migration.batch_max', true), '') = ''
    OR stg.mongo_id <= current_setting('migration.batch_max', true)
  );

-- === 2b receipt uploads ===
INSERT INTO purchase_receipt_upload (
  mongo_id, merchant_id, user_id, image, status,
  approved_method, store_id, estimated_points, user_tel, user_full_name, created_at, updated_at
)
SELECT stg.mongo_id, mm.id, ua.id,
  CASE WHEN stg.raw->'imageUrl' IS NOT NULL AND jsonb_array_length(stg.raw->'imageUrl')>0
    THEN COALESCE(stg.raw->'imageUrl'->>0, '') ELSE '' END,
  CASE stg.raw->>'status' WHEN 'approve' THEN 'approved' WHEN 'reject' THEN 'rejected' ELSE 'pending' END,
  CASE WHEN stg.raw->>'uploadType'='ADMIN' THEN 'admin' ELSE NULL END,
  sm.id, COALESCE(ROUND((stg.raw->>'point')::numeric)::integer, 0),
  stg.raw->>'userTel', stg.raw->>'userName',
  (stg.raw->>'createdAt')::timestamptz, (stg.raw->>'updatedAt')::timestamptz
FROM stg_mongo_receipts stg
JOIN merchant_master mm ON mm.id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid
LEFT JOIN user_accounts ua ON ua.mongo_id = stg.raw->>'userId' AND ua.merchant_id = mm.id
LEFT JOIN store_master sm ON sm.mongo_id = 'crm_ch:' || (stg.raw->'store'->>'_id')
WHERE stg.merchant_ref = '649e9524f43a5fc2f9705850'
  AND NOT EXISTS (
    SELECT 1 FROM purchase_receipt_upload pr
    WHERE pr.merchant_id = mm.id AND pr.mongo_id = stg.mongo_id
  );

-- === 2c wallet earns (positive GIVEN, resolvable user only) — does NOT touch user_wallet ===
INSERT INTO wallet_ledger (
  mongo_id, merchant_id, user_id, amount, signed_amount,
  deductible_balance, transaction_type, expiry_date, source_type,
  source_id, target_entity_id,
  description, created_at, created_by, currency, component,
  dedup_key, expired_amount, skip_cdc, reference_id, metadata
)
SELECT
  stg.mongo_id, mm.id, ua.id,
  ABS(ROUND((stg.raw->>'point')::numeric)::integer),
  ROUND((stg.raw->>'point')::numeric)::integer,
  COALESCE((stg.raw->>'balance')::numeric, 0),
  'earn'::currency_transaction_type,
  CASE WHEN stg.raw->>'expiredDate' IS NOT NULL AND (stg.raw->>'expiredDate')::numeric != -1
    THEN (to_timestamp((stg.raw->>'expiredDate')::numeric / 1000))::date ELSE NULL END,
  CASE
    WHEN stg.raw->>'giveFrom' IN ('SCAN_QR_RECEIPT','UPLOAD_RECEIPT','POS_CLIENT_ECOMMERCE','POS_STORE_FRONT','POS_CLIENT_ORDER','THIRD_PARTY','LAZADA_ORDER','TIKTOK_ORDER') THEN 'purchase'::wallet_transaction_source_type
    WHEN stg.raw->>'giveFrom' IN ('WELCOME_POINT','CAMPAIGN') THEN 'campaign'::wallet_transaction_source_type
    WHEN stg.raw->>'giveFrom' IN ('INVITER_FRIEND_COLLECT','INVITE_FRIEND_COLLECT','INVITER_SELLER_COLLECT') THEN 'referral'::wallet_transaction_source_type
    WHEN stg.raw->>'giveFrom' IN ('SURVEY','EVENT_ACTIVITY') THEN 'activity'::wallet_transaction_source_type
    ELSE 'manual'::wallet_transaction_source_type
  END,
  (SELECT pl.id FROM purchase_ledger pl WHERE pl.mongo_id = stg.raw->>'productOrderId' AND pl.merchant_id = mm.id LIMIT 1),
  NULL,
  stg.raw->>'note',
  (stg.raw->>'createdAt')::timestamptz,
  stg.raw->>'merchantUserId',
  'points'::currency, 'base'::currency_component,
  'legacy:' || stg.mongo_id, 0, true,
  CASE WHEN stg.raw->>'referenceId' ~ '^[0-9a-f]{8}-[0-9a-f]{4}-' THEN (stg.raw->>'referenceId')::uuid ELSE NULL END,
  jsonb_build_object('jorakay_orphan_remediation', '20260912')
    || CASE WHEN (stg.raw->>'sale')::numeric > 0 THEN jsonb_build_object('sale_amount',(stg.raw->>'sale')::numeric) ELSE '{}'::jsonb END
FROM stg_mongo_points stg
JOIN merchant_master mm ON mm.id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid
JOIN user_accounts ua ON ua.mongo_id = stg.raw->>'userId' AND ua.merchant_id = mm.id
WHERE stg.merchant_ref = '649e9524f43a5fc2f9705850'
  AND stg.raw->>'type' = 'GIVEN'
  AND COALESCE((stg.raw->>'balance')::numeric, 0) > 0
  AND NOT EXISTS (
    SELECT 1 FROM wallet_ledger wl
    WHERE wl.merchant_id = mm.id AND wl.mongo_id = stg.mongo_id AND wl.transaction_type = 'earn'
  )
  AND (
    COALESCE(current_setting('migration.batch_min', true), '') = ''
    OR stg.mongo_id >= current_setting('migration.batch_min', true)
  )
  AND (
    COALESCE(current_setting('migration.batch_max', true), '') = ''
    OR stg.mongo_id <= current_setting('migration.batch_max', true)
  );

-- === 2d link receipt upload → purchase (receiptId match) ===
UPDATE purchase_receipt_upload pru SET purchase_ledger_id = pl.id
FROM stg_mongo_receipts stg, purchase_ledger pl
WHERE stg.mongo_id = pru.mongo_id
  AND pl.transaction_number = (stg.raw->>'receiptId')
  AND pl.merchant_id = pru.merchant_id
  AND pru.merchant_id = '7522af2c-a7f6-4ab8-8493-6875a3b19544'::uuid
  AND pru.purchase_ledger_id IS NULL
  AND (stg.raw->>'receiptId') IS NOT NULL
  AND (stg.raw->>'receiptId') != ''
  AND stg.merchant_ref = '649e9524f43a5fc2f9705850';
