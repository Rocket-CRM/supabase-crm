-- Yuanta Demo — rich brokerage AOPs (non-loyalty). Run once per environment.
-- Merchant: fe754adc-766b-4553-abda-7bc80dcc9724

UPDATE cs_procedures
SET is_active = false, updated_at = now()
WHERE merchant_id = 'fe754adc-766b-4553-abda-7bc80dcc9724'
  AND trigger_intent IN (
    'loyalty_points_balance', 'loyalty_tier_status', 'reward_redemption_assist',
    'physical_reward_delivery_status', 'promotion_campaign_faq', 'ysinvest_app_help',
    'account_profile_non_trade'
  );

-- Shared compiled graph skeleton builder applied per procedure below via INSERT
