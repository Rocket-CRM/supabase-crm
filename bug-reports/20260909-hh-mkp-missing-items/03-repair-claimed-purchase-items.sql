-- Step 5: rebuild purchase_items_ledger for Her Hyness claimed marketplace orders whose purchase
-- was created while order_items_ledger_mkp was empty (claim copied zero items).
-- Run ONLY after Tier 1 (claimed) item repair reports remaining.claimed = 0.
-- Mirrors what claim -> fn_marketplace_order_items_payload -> api_create_purchase would have written:
--   sku_id/sku_code resolved against product_sku_master (NULL when the marketplace SKU is unknown — same as healthy rows),
--   line_total = COALESCE(earnable_amount, line_total), discount = gross - line_total, status completed.
-- Idempotent: only purchases that still have zero purchase_items_ledger rows are touched.

-- 5a. Preview (read-only). Expect ~142 Shopee + ~182 TikTok purchases.
WITH target AS (
  SELECT p.id AS transaction_id, p.transaction_number, o.id AS order_id
  FROM purchase_ledger p
  JOIN order_ledger_mkp o
    ON o.merchant_id = p.merchant_id
   AND o.platform = lower(split_part(p.transaction_number, '-', 2))
   AND o.order_sn = substr(p.transaction_number,
                           char_length(split_part(p.transaction_number, '-', 1)) + char_length(split_part(p.transaction_number, '-', 2)) + 3)
  WHERE p.merchant_id = 'ffe8519e-49a2-467b-a0ec-57d28ba8be49'
    AND p.transaction_source ILIKE 'marketplace%'
    AND p.transaction_number ~ '^MKP-(SHOPEE|TIKTOK|LAZADA)-'
    AND p.created_at >= '2026-09-03 15:25:00+00'
    AND NOT EXISTS (SELECT 1 FROM purchase_items_ledger pi WHERE pi.transaction_id = p.id)
)
SELECT split_part(transaction_number, '-', 2) AS platform,
       COUNT(*) AS purchases_without_items,
       COUNT(*) FILTER (WHERE EXISTS (SELECT 1 FROM order_items_ledger_mkp i WHERE i.order_id = target.order_id)) AS repairable_now
FROM target GROUP BY 1;

-- 5b. Apply (needs explicit approval). Same target CTE; inserts one purchase item per marketplace line.
WITH target AS (
  SELECT p.id AS transaction_id, p.merchant_id, p.completed_at, o.id AS order_id
  FROM purchase_ledger p
  JOIN order_ledger_mkp o
    ON o.merchant_id = p.merchant_id
   AND o.platform = lower(split_part(p.transaction_number, '-', 2))
   AND o.order_sn = substr(p.transaction_number,
                           char_length(split_part(p.transaction_number, '-', 1)) + char_length(split_part(p.transaction_number, '-', 2)) + 3)
  WHERE p.merchant_id = 'ffe8519e-49a2-467b-a0ec-57d28ba8be49'
    AND p.transaction_source ILIKE 'marketplace%'
    AND p.transaction_number ~ '^MKP-(SHOPEE|TIKTOK|LAZADA)-'
    AND p.created_at >= '2026-09-03 15:25:00+00'
    AND NOT EXISTS (SELECT 1 FROM purchase_items_ledger pi WHERE pi.transaction_id = p.id)
    AND EXISTS (SELECT 1 FROM order_items_ledger_mkp i WHERE i.order_id = o.id)
), ins AS (
  INSERT INTO purchase_items_ledger (
    transaction_id, merchant_id, sku_id, sku_code, product_name, variant_name,
    quantity, unit_price, discount_amount, tax_amount, line_total,
    item_type, status, completed_at, completed_by_source, quantity_completed)
  SELECT t.transaction_id, t.merchant_id, s.id, s.sku_code, NULL, NULL,
         oi.quantity, oi.unit_price,
         GREATEST((oi.unit_price * oi.quantity) - COALESCE(oi.earnable_amount, oi.line_total), 0), 0,
         COALESCE(oi.earnable_amount, oi.line_total),
         'product', 'completed'::purchase_status, COALESCE(t.completed_at, now()),
         'repair_20260909_mkp_items', oi.quantity
  FROM target t
  JOIN order_items_ledger_mkp oi ON oi.order_id = t.order_id
  LEFT JOIN product_sku_master s
    ON s.merchant_id = t.merchant_id
   AND s.sku_code = COALESCE(oi.platform_sku, oi.variant_sku, oi.platform_item_id)
  RETURNING transaction_id
)
SELECT COUNT(*) AS item_rows_inserted, COUNT(DISTINCT transaction_id) AS purchases_repaired FROM ins;

-- 5c. Verify: should return 0.
SELECT COUNT(*) AS still_without_items
FROM purchase_ledger p
WHERE p.merchant_id = 'ffe8519e-49a2-467b-a0ec-57d28ba8be49'
  AND p.transaction_number ~ '^MKP-(SHOPEE|TIKTOK)-'
  AND p.created_at >= '2026-09-03 15:25:00+00'
  AND NOT EXISTS (SELECT 1 FROM purchase_items_ledger pi WHERE pi.transaction_id = p.id);
