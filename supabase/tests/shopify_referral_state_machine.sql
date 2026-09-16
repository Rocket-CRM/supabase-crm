-- Manual / branch verification for 20260916120000_shopify_referral_state_and_code_delivery.sql
-- Run on a non-production branch with referral fixtures.

-- 1) attributed → paid webhook settles once (simulate second call returns IDEMPOTENT or OK)
-- SELECT public.fn_attribute_referral('purchase', ... unpaid ...);
-- SELECT public.fn_attribute_referral('purchase', ... paid ...);

-- 2) reconciliation picks up attributed + paid orders
-- SELECT public.fn_reconcile_missed_referral_purchases('<merchant_id>');

-- 3) Shopify-linked redemption emits issue_requested then issued after external_ref_id
-- INSERT reward_redemptions_ledger ... ; inspect chokepoint_event_outbox topic crm.events.redemption
