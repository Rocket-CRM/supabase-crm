-- Supports shopify-sweep-points-discount, which otherwise seq-scans ~13M wallet_ledger
-- rows twice per run and exceeds the statement timeout.
CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_wallet_ledger_shopify_points_discount
  ON public.wallet_ledger (created_at)
  WHERE (metadata->>'type') IN ('shopify_points_to_discount', 'shopify_points_to_discount_reversal');
