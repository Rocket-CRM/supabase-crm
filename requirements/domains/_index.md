# Domain Pointer Index

> Keyword-to-domain router. Grep this file for a user's terms → domain → authoritative `requirements/<Domain>.md`. **Do not full-read this file** — it's ~22KB. Grep only.

The legacy per-domain slug files at `requirements/domains/<slug>.md` are being retired (Phase 6 of the agent context refactor). The Domain Map below now points directly at authoritative `requirements/<Domain>.md` docs. A few slugs remain because they don't have a 1:1 authoritative target yet — those rows are marked `(slug)` and link to the slug file.

## Domain Map

| Domain | Authoritative doc | Keywords |
|---|---|---|
| Tier | [Tier.md](../Tier.md) | tier, level, upgrade, downgrade, maintain, tier progress, tier conditions, ranking, entry tier, burn rate, point-to-discount, tier lock, window |
| Reward | [Reward.md](../Reward.md) | reward, redeem, redemption, voucher, coupon, promo code, points required, fulfillment, eligibility, stock, reward catalog, dynamic points, multi-quantity, variant, variant_config, selected_variants, admin push, claim link, QR claim, bff_admin_push_reward, reward_claim_link |}
| Event Promotion | [Event_Promotion.md](../Event_Promotion.md) | event_promo, event_promo_rule, event_promo_mapping, event_promo_claim, event promotion, merchant promo, activity_group promo |
| Syngenta Events | [Syngenta_Events.md](../Syngenta_Events.md) | syngenta_events_master, syngenta_event_registration_ledger, event_product_config, event_store_allowlist, syngenta event, field event, event coordinator, event owner, event team, participating retailer, retailer allowlist, fn_event_caller_role, admin_get_my_events |
| Currency | [Currency.md](../Currency.md) | points, tickets, balance, earn, burn, wallet, earn factor, multiplier, rate, expiry, TTL, fixed frequency, reversal, refund, wallet ledger, source type, ticket type |
| Activity Earning | [Activity_Based_Earning.md](../Activity_Based_Earning.md) | activity, upload, image upload, admin approval, exercise, POSM, activity matrix, field definitions, primary dimension, secondary field, currency config |
| Purchase Transaction | [Purchase_Transaction.md](../Purchase_Transaction.md) | purchase, transaction, order, payment, refund, credit, debit, line item, SKU, purchase ledger, purchase items, final amount, status, completed |
| Marketplace | [Marketplace.md](../Marketplace.md) | marketplace, lazada, shopee, tiktok, order_ledger_mkp, claim_marketplace_order, upsert_marketplace_order, get_shop_credentials, seller_id, webhook-marketplace, inngest-marketplace-serve, merchant_credentials external_id, marketplace claim, order claims |
| Shopify | [Shopify.md](../Shopify.md) | shopify, shopify_app, embedded admin, storefront widget, shopify-webhooks, auth-shopify-admin, shopify-token-refresh, loyalty entitlement, points-to-discount, rewarding-shopify, shopify billing |
| FuturePark | [FuturePark.md](../FuturePark.md) | futurepark, future park, OCR receipt, futurepark_redemptions, settlement, FP receipt |
| Receipt Upload Earning | [Receipt_Upload_Earning.md](../Receipt_Upload_Earning.md) | receipt upload, purchase_receipt_upload, OCR, receipt approval, receipt earning, generic receipt |
| Earn Channel | [Earn_Channel.md](../Earn_Channel.md) | earn channel, earn_channel, channel effective, earn from code, channel overlay, earn factor channel, earn_channel_registry, fn_get_effective_earn_channels |
| Stored Value Cards | [Stored_Value_Cards.md](../Stored_Value_Cards.md) | stored value card, cards, card_types, gift card, prepaid card |
| Store Credit | [Store_Credit.md](../Store_Credit.md) | store credit, store_credit, store_credit_promo, promo credit, credit balance |
| Package | [Package.md](../Package.md) | package, package_, entitlement package, package purchase |
| Persona Entitlement | [Persona_Entitlement.md](../Persona_Entitlement.md) | persona entitlement, persona_entitlement, entitlement grant |
| Shelved / demo features | [Shelved_Demo_Features.md](../Shelved_Demo_Features.md) | shelved, demo, not launched, future, package, store credit, SVC, stored value card, persona entitlement demo |
| Order Booking | [Order_Booking.md](../Order_Booking.md) | order booking, booking, reservation order |
| Consent | [Consent.md](../Consent.md) | consent, PDPA, consent ledger, consent version, privacy consent |
| Platform Plan Feature Registry | [Platform_Plan_Feature_Registry.md](../Platform_Plan_Feature_Registry.md) | platform plan, feature registry, plan entitlement, merchant plan, shopify plan |
| Central Outcome Dispatcher | [Central_Outcome_Dispatcher.md](../Central_Outcome_Dispatcher.md) | central outcome, fn_dispatch_outcome, outcome dispatcher, chokepoint outcome |
| CRM Event-Driven Architecture | [CRM_Event_Driven_Architecture.md](../CRM_Event_Driven_Architecture.md) | event driven, chokepoint, chokepoint_event_outbox, fn_chokepoint_emit_event, outbox publisher, Inngest router, crm.events, integration_outbox_cursor, CHOKEPOINT_EVENTS_ENABLED, OUTBOX_PUBLISH_TOPICS, crm-event-processors, inngest-event-router-serve |
| Open API | [Open_API.md](../Open_API.md) | open api, open-api, x-api-key, api-users, api-assets, api-purchases, api-redemptions, api-wallet, partner API |
| Analytics (BQ) | [Analytics.md](../Analytics.md) | analytics-query, bigquery, serving_loyalty, home.metrics, BQ dashboard, loyalty analytics |
| Check-in | [Checkin.md](../Checkin.md) | checkin, check-in, checkin_ledger, checkin_outcomes, process_checkin, streak, attendance |
| Notification Service | [Notification_Service.md](../Notification_Service.md) | notification, LINE push, flex message, notification_log, notification_event_catalog, merchant_notification_settings, notification_template, fn_resolve_notification_for_event, bff_get_notification_settings, NotificationConsumer, channel_line |
| AMP Workflows | [AMP_Workflows.md](../AMP_Workflows.md) | AMP, workflow, workflow_master, workflow_node, workflow_edge, workflow_trigger, workflow_log, audience, amp_audience_master, amp_audience_member, lifecycle automation, batch dispatch, node stats |
| Mission | [Mission.md](../Mission.md) | mission, quest, challenge, milestone, standard mission, condition, progress, waterfall, level, claim, join, accept, mission progress, conditions |
| Spin Wheel | [Spin_Wheel.md](../Spin_Wheel.md) | spin wheel, spin_wheel, gamification, wheel, prize, segment, weighted random, lottery, fn_spin_wheel, bff_list_spin_wheels |
| Leaderboard | [Leaderboard.md](../Leaderboard.md) | leaderboard, campaign_leaderboard, ranked table, top spender, participate, v_lb_, mv_lb_, source_kind, api_get_leaderboard_rows, api_join_leaderboard |
| Activity Log & Attribution | [Activity_Attribution.md](../Activity_Attribution.md) | activity log, activity_ledger, activity_type_master, activity_field_def, UTM, utm_source, utm_campaign, acquisition, attribution, marketing campaign, mkt_campaign, mkt_campaign_identifier, mkt_purchase_attribution, mkt_config, campaign ROI, u_shape, first touch, last touch, voucher code, line param, fn_log_user_activity, api_log_user_activity |
| RFM Scoring | [RFM_Scoring.md](../RFM_Scoring.md) | RFM, recency, frequency, monetary, rfm_config, rfm_user_score, segment map, champions, quintile, NTILE, fn_rfm_compute_scores, bff_get_rfm_settings, rfm distribution |
| Funnel | [Funnel.md](../Funnel.md) | funnel, journey stage, funnel_master, funnel_transition_ledger, funnel_sort_order, stage conversion, latest-stage-wins, fn_funnel_reconcile, bff_upsert_funnel, bff_get_funnel_metrics |
| Campaign Activity Grouping | [Campaign_Activity_Grouping.md](../Campaign_Activity_Grouping.md) | campaign, campaign_sub, campaign_activity, campaign_mapping, report grouping, bff_list_campaign_mappings, bff_upsert_campaign |
| Tag & Persona | [Tag_and_Persona.md](../Tag_and_Persona.md) | tag, persona, segment, persona group, user type, buyer, seller, VIP, classification, behavioral marker, assign persona, assign tag, user tags |
| Referral | [Referral.md](../Referral.md) | referral, invite, invite code, inviter, invitee, referrer, friend, referral code, signup referral, purchase referral, share hop, referral claim, referral limit, referral reward |
| Authentication | [Authentication.md](../Authentication.md) | auth, JWT, token, login, LINE, OTP, phone, access token, refresh token, custom JWT, merchant auth, secret, PGRST301 |
| Member Freeze | [Member_Freeze.md](../Member_Freeze.md) | freeze, frozen, is_freeze, suspend member, unfreeze, ACCOUNT_RESTRICTED, bff_admin_set_member_freeze, get_user_summary is_freeze, customer 360 freeze |
| Signup & Login | [Signup_Login.md](../Signup_Login.md) | signup, login, registration, profile form, form step, next step, OTP, LINE login, profile completion, missing fields, consent, PDPA |
| Signup Code Validation | [Signup_Login.md](../Signup_Login.md) | signup code, external code, dealer code, corporate code, tax id, code pool, code claim, validate code, signup_code_pool, signup_code_claims, fn_consume_signup_code, bff_validate_signup_code, external_code field type, persona-scoped signup, max_consumers, target_user_column |
| Forms & User Profile | [Forms.md](../Forms.md) | form, survey, field, custom field, default field, profile, user field config, form template, form field, form response, form submission, field type |
| Bulk Import Currency | [Bulk_Import_Currency.md](../Bulk_Import_Currency.md) | currency import, points import, ticket import, bulk_import_currency, import/bulk-currency, inngest-bulk-import-currency-serve, additive import, skip_emit, validate_only, row_offset, bulk dedup key |
| Customer Import / Export | [Customer_Import_System.md](../Customer_Import_System.md) | customer import, user import, bulk import, bulk upload, migration, csv import, csv export, user_import_staging, bulk_import_batches, bulk_upsert_customers_from_import, allow_bulk_import, skip_cdc, skip_side_effects, two-row header, ongoing import, migration mode, field selection, user_io_schemas |
| Store Classification | [Store_Attribute_Classification.md](../Store_Attribute_Classification.md) | store, store attribute, store category, store sub-attribute, attribute set, store classification, location, channel, store master, store code |
| Translation | [Translation_System.md](../Translation_System.md) | translation, language, i18n, multi-language, Thai, English, Japanese, Chinese, ui translation, entity translation, default language, fallback |
| Asset | [Asset.md](../Asset.md) | asset, asset_type, asset_tier_config, vehicle, car_plate, Exclusive Parking, Asset Group, VIP parking, custom_crm_asset_sync, bff_admin_get_user_assets, bff_admin_upsert_user_asset, plate unique, asset quota |
| Admin Panel | [Admin_Panel.md](../Admin_Panel.md) | admin_roles, admin_users, admin_role_permissions, admin_menu_config, admin_analytics_menu, platform_superadmin, is_platform_admin, superadmin, metabase_dashboard_id, role, permission, sidebar, menu, floating_menu, default_path, hide_sidebar |
| Display Settings | [Display_Settings.md](../Display_Settings.md) | display_settings, display_block_template, display_blocks, homepage, block_type, block_style, profile_card, banner, banner_hero, navigation, widget_config_template, merchant_widget_settings |
| CS (umbrella) | [CS_Feature_Spec.md](../CS_Feature_Spec.md) | customer service, cs module, omnichannel, cs inbox, agent workspace, cs composition |
| CS Conversations | [CS_Conversations.md](../CS_Conversations.md) | conversation, message, inbox, chat, reply, assign, resolve, close, reopen, ticket, priority, snoozed, pending, open, cs_conversations, cs_messages |
| CS Knowledge Base | [CS_Knowledge_Base.md](../CS_Knowledge_Base.md) | knowledge, article, embedding, faq, semantic_search, rag, vector, pgvector, chunk, cs_knowledge_articles, cs_knowledge_embeddings, source_type |
| CS Procedures (AOPs) | [CS_Procedures.md](../CS_Procedures.md) | procedure, aop, agent_operating_procedure, intent, trigger_intent, flexibility, strict, guided, agentic, compiled_steps, raw_content, tone_override |
| CS Channels & Customers | [CS_Channels.md](../CS_Channels.md) | channel, platform, shopee, lazada, tiktok, line, whatsapp, facebook, instagram, email, web_widget, voice, sms, twilio, phone_number, identity_resolution |
| CS Brand Configuration | [CS_Platform_Features.md](../CS_Platform_Features.md) | brand_config, voice, tone, guardrails, model_config, action_config, outbound, cs_brand_config, voice_preset, forbidden_phrases, escalation_threshold |
| CS Teams & Agent Profiles | [CS_Platform_Features.md](../CS_Platform_Features.md) | team, agent, agent_profile, online, away, offline, max_concurrent, skills, routing, round_robin, least_busy, cs_teams, cs_agent_profiles |
| CS Phone Number Purchasing | [CS_Phone_Number_Purchasing.md](../CS_Phone_Number_Purchasing.md) | twilio, phone_number, purchase_number, sms, voice, provider, adapter, subaccount, byot, master, cs_phone_numbers, webhook_twilio_sms, webhook_twilio_voice |
| CS Channel Connectors | [CS_Channel_Connectors.md](../CS_Channel_Connectors.md) | shopee_chat, lazada_chat, tiktok_chat, line_oa, whatsapp_business, facebook_messenger, instagram_dm, email, web_widget, voice, inbound_voice |
| CS Unified Inbox | [CS_Unified_Inbox.md](../CS_Unified_Inbox.md) | inbox, unified_inbox, conversation_view, ticket, ticket_lifecycle, views, filters, assignment, routing, round_robin, skills_based, agent_workload |
| CS SLA Management | [CS_SLA.md](../CS_SLA.md) | sla, response_time, resolution_time, business_hours, holiday, breach, escalation, sla_policy, timer, pause |
| CS Rules Engine | [CS_Rules_Engine.md](../CS_Rules_Engine.md) | rules, trigger, condition, action, auto_reply, auto_assign, auto_tag, auto_escalate, keyword_detection, intent_detection, sentiment_detection |
| CS AI System | [CS_AI_System.md](../CS_AI_System.md) | knowledge_library, customer_context, conversation_memory, agent_reasoning, guardrails, brand_voice, aop, procedure, copilot, testing, simulation |
| CS Actions | [CS_Actions.md](../CS_Actions.md) | marketplace_action, cancel_order, process_refund, create_voucher, shopify, loyalty_bridge, custom_api_builder, computer_use, browser_automation |
| CS Live Assist | [CS_Live_Assist.md](../CS_Live_Assist.md) | ai_draft, suggested_reply, conversation_summary, knowledge_assist, copilot_sidebar, action_suggestion, real_time_translation |
| CS Analytics & QA | [CS_Analytics.md](../CS_Analytics.md) | analytics, metrics, resolution_rate, csat, watchtower, auto_qa, scorecard, sentiment, unresolved_questions, knowledge_gap, coaching, nps, handle_time |
| CS Platform Features | [CS_Platform_Features.md](../CS_Platform_Features.md) | testing, simulation, a_b_experiment, notifications, time_tracking, self_service, customer_portal, web_form, knowledge_base_public, administration |
| CS Competitor Matrix | [CS_Competitor_Matrix.md](../CS_Competitor_Matrix.md) | sierra, decagon, intercom, zendesk, gorgias, duoke, zaapi, respond_io, oho_chat, zwiz, kore_ai, gowajee, competitor, benchmark |
| CS Voice | [CS_Voice.md](../CS_Voice.md) | voice, phone, call, inbound, outbound, stt, tts, speech_to_text, text_to_speech, elevenlabs, scribe, twilio, sip, telephony, recording, transcription |
| Resource Content (Shared) | [Resource_Content.md](../Resource_Content.md) | resource_content, content_resource, quick_reply, canned_response, saved_reply, media_resource, pdf, video, link, rich_content, content_library |
| Action Macro (Shared) | [Action_Macro.md](../Action_Macro.md) | action_macro, macro, macro_context, execute_macro, multi_step_action, parameterized_action, variable_definitions, variable_constraints, approval |
| BigCommerce Storefront API | [Ecommerce_Marketplace_Integration.md](../Ecommerce_Marketplace_Integration.md) (pointer; BC APIs in registries) | bigcommerce, storefront, api_bigcommerce_get_merchant_config, api_bigcommerce_get_user_profile, api_bigcommerce_get_user_rewards, mongoId, mongo_id, migrated user, storefront rewards |
| Custom Webhooks | [Custom_Webhooks.md](../Custom_Webhooks.md) | custom_webhook, hookdeck, zort, pipedream, createReceiptWorkflow, webhook proxy, custom_webhook_events |
| Outbound Integrations | [Outbound_Integrations.md](../Outbound_Integrations.md) | outbound webhook, klaviyo, X-Rocket-Signature, event_key, integration_delivery_log, integration_outbox_cursor, integration_sync_jobs, sync_new_members, merchant_credentials webhook, Rocket Points Balance |
| Universal Action System (Shared) `(slug)` | [universal-action-system-shared.md](universal-action-system-shared.md) | action_registry, action_category, action_caller_config, rule_type_registry, entity_registry, intent_registry, rules_code, rules_prompt, fn_execute |
| Internal Knowledge `(slug)` | [internal-knowledge.md](internal-knowledge.md) | internal_knowledge, feature knowledge, knowledge_blocks, feature_items, downstream agent context, slide_generation, frontend_context, implementation_brief |
| System Map | [architecture/System_Map.md](../architecture/System_Map.md) | repo, where does, runs on, edge function vs rpc, render, inngest, surface, frontend lives |

## Source Doc Cross-Reference

The authoritative `requirements/<Domain>.md` doc is the source of truth. Some legacy per-domain slug files at `requirements/domains/<slug>.md` still exist with unique Business-Rule summaries that haven't been merged yet — when you find one, **prefer the authoritative doc** and only consult the slug if the registry + authoritative grep came up empty. Slug files are being progressively retired.

## Domain Keyword Cross-Reference

A flat lookup for any term a frontend AI might encounter.

| Keyword | Domain |
|---|---|
| `tier` | Tier |
| `level` | Tier |
| `upgrade` | Tier |
| `downgrade` | Tier |
| `maintain` | Tier |
| `tier_progress` | Tier |
| `tier_conditions` | Tier |
| `ranking` | Tier |
| `entry_tier` | Tier |
| `burn_rate` | Tier |
| `point-to-discount` | Tier |
| `tier_lock` | Tier |
| `window_type` | Tier |
| `calendar_month` | Tier |
| `calendar_quarter` | Tier |
| `rolling` | Tier |
| `fixed_period` | Tier |
| `anniversary` | Tier |
| `persona_id` (on tier) | Tier |
| `reward` | Reward |
| `redeem` | Reward |
| `redemption` | Reward |
| `voucher` | Reward |
| `coupon` | Reward |
| `promo_code` | Reward |
| `promo code` | Reward |
| `event_promo` | Event Promotion |
| `event_promo_rule` | Event Promotion |
| `event_promo_mapping` | Event Promotion |
| `event_promo_claim` | Event Promotion |
| `event promotion` | Event Promotion |
| `merchant promo` | Event Promotion |
| `event promo` | Event Promotion |
| `activity_group promo` | Event Promotion |
| `syngenta_events_master` | Syngenta Events |
| `syngenta_event_registration_ledger` | Syngenta Events |
| `event_product_config` | Syngenta Events |
| `event_store_allowlist` | Syngenta Events |
| `syngenta event` | Syngenta Events |
| `field event` | Syngenta Events |
| `event coordinator` | Syngenta Events |
| `event owner` | Syngenta Events |
| `event team` | Syngenta Events |
| `participating retailer` | Syngenta Events |
| `retailer allowlist` | Syngenta Events |
| `fn_event_caller_role` | Syngenta Events |
| `admin_get_my_events` | Syngenta Events |
| `bff_invite_event_coordinator` | Syngenta Events |
| `bff_remove_event_coordinator` | Syngenta Events |
| `bff_list_event_team` | Syngenta Events |
| `bff_search_admin_users_for_event` | Syngenta Events |
| `bff_list_event_stores` | Syngenta Events |
| `bff_search_admin_stores` | Syngenta Events |
| `bff_upsert_event_stores` | Syngenta Events |
| `bff_list_event_products` | Syngenta Events |
| `bff_upsert_event_products` | Syngenta Events |
| `bff_list_event_orders` | Syngenta Events |
| `syngenta_event_action` | Syngenta Events |
| `syngenta_event_booking` | Syngenta Events |
| `points_required` | Reward |
| `fallback_points` | Reward |
| `fulfillment` | Reward |
| `fulfillment_status` | Reward |
| `eligibility` | Reward |
| `stock_control` | Reward |
| `reward_master` | Reward |
| `reward_catalog` | Reward |
| `dynamic_points` | Reward |
| `multi_quantity` | Reward |
| `used_status` | Reward |
| `redeemed_status` | Reward |
| `reward_points_conditions` | Reward |
| `reward_redemptions_ledger` | Reward |
| `online_store` | Reward |
| `shopify_discount` | Reward |
| `specificity` | Reward |
| `reward_group` | Reward |
| `group_limit` | Reward |
| `reward_group_ids` | Reward |
| `fn_check_reward_group_limits` | Reward |
| `bff_upsert_reward_group_with_limits` | Reward |
| `bff_list_reward_groups` | Reward |
| `points` | Currency |
| `tickets` | Currency |
| `balance` | Currency |
| `earn` | Currency |
| `burn` | Currency |
| `wallet` | Currency |
| `wallet_ledger` | Currency |
| `earn_factor` | Currency |
| `multiplier` | Currency |
| `rate` | Currency |
| `expiry` | Currency |
| `TTL` | Currency |
| `fixed_frequency` | Currency |
| `reversal` | Currency |
| `refund` (currency) | Currency |
| `source_type` | Currency |
| `ticket_type` | Currency |
| `credit_ticket` | Currency |
| `deductible_balance` | Currency |
| `signed_amount` | Currency |
| `component` | Currency |
| `base` | Currency |
| `bonus` | Currency |
| `adjustment` | Currency |
| `chokepoint_post_wallet_transaction` | Currency |
| `AMP` | AMP Workflows |
| `workflow_master` | AMP Workflows |
| `workflow_node` | AMP Workflows |
| `workflow_edge` | AMP Workflows |
| `workflow_trigger` | AMP Workflows |
| `workflow_log` | AMP Workflows |
| `audience` | AMP Workflows |
| `amp_audience_master` | AMP Workflows |
| `amp_audience_member` | AMP Workflows |
| `lifecycle automation` | AMP Workflows |
| `batch dispatch` | AMP Workflows |
| `node stats` | AMP Workflows |
| `activity` | Activity Earning |
| `upload` | Activity Earning |
| `image_upload` | Activity Earning |
| `admin_approval` | Activity Earning |
| `exercise` | Activity Earning |
| `POSM` | Activity Earning |
| `activity_matrix` | Activity Earning |
| `field_definitions` | Activity Earning |
| `primary_dimension` | Activity Earning |
| `secondary_field` | Activity Earning |
| `activity_currency_config` | Activity Earning |
| `activity_upload_ledger` | Activity Earning |
| `purchase` | Purchase Transaction |
| `transaction` | Purchase Transaction |
| `order` | Purchase Transaction |
| `payment` | Purchase Transaction |
| `refund` (transaction) | Purchase Transaction |
| `credit` | Purchase Transaction |
| `debit` | Purchase Transaction |
| `line_item` | Purchase Transaction |
| `SKU` | Purchase Transaction |
| `purchase_ledger` | Purchase Transaction |
| `purchase_items_ledger` | Purchase Transaction |
| `final_amount` | Purchase Transaction |
| `status` (purchase) | Purchase Transaction |
| `completed` | Purchase Transaction |
| `processing_method` | Purchase Transaction |
| `store_id` | Purchase Transaction |
| `seller_id` | Purchase Transaction |
| `transaction_number` | Purchase Transaction |
| `record_type` | Purchase Transaction |
| `mission` | Mission |
| `quest` | Mission |
| `challenge` | Mission |
| `milestone` | Mission |
| `standard_mission` | Mission |
| `condition_progress` | Mission |
| `waterfall` | Mission |
| `claim` | Mission |
| `join_mission` | Mission |
| `accept_mission` | Mission |
| `button_action` | Mission |
| `unclaimed_completions` | Mission |
| `lifetime_completions` | Mission |
| `mission_progress` | Mission |
| `tag` | Tag & Persona |
| `persona` | Tag & Persona |
| `persona_group` | Tag & Persona |
| `segment` | Tag & Persona |
| `user_type` | Tag & Persona |
| `buyer` | Tag & Persona |
| `seller` | Tag & Persona |
| `VIP` | Tag & Persona |
| `user_tags` | Tag & Persona |
| `assign_persona` | Tag & Persona |
| `assign_tag` | Tag & Persona |
| `referral` | Referral |
| `invite` | Referral |
| `invite_code` | Referral |
| `inviter` | Referral |
| `invitee` | Referral |
| `referrer` | Referral |
| `friend` | Referral |
| `referral_code` | Referral |
| `referral_claim` | Referral |
| `share_hop` | Referral |
| `referral_signup` | Referral |
| `referral_purchase` | Referral |
| `referral_limit` | Referral |
| `referral_ledger` | Referral |
| `auth` | Authentication |
| `JWT` | Authentication |
| `token` | Authentication |
| `login` | Authentication |
| `LINE` | Authentication |
| `line_login` | Authentication |
| `line_messaging` | Authentication |
| `OTP` | Authentication |
| `phone` | Authentication |
| `access_token` | Authentication |
| `refresh_token` | Authentication |
| `merchant_code` | Authentication |
| `bff-auth-complete` | Authentication |
| `next_step` | Signup & Login |
| `signup` | Signup & Login |
| `registration` | Signup & Login |
| `profile_form` | Signup & Login |
| `form_step` | Signup & Login |
| `profile_completion` | Signup & Login |
| `missing_fields` | Signup & Login |
| `consent` | Signup & Login |
| `PDPA` | Signup & Login |
| `is_signup_form_complete` | Signup & Login |
| `form` | Forms & User Profile |
| `field` | Forms & User Profile |
| `custom_field` | Forms & User Profile |
| `default_field` | Forms & User Profile |
| `profile` | Forms & User Profile |
| `user_field_config` | Forms & User Profile |
| `form_template` | Forms & User Profile |
| `form_field` | Forms & User Profile |
| `form_response` | Forms & User Profile |
| `form_submission` | Forms & User Profile |
| `field_type` | Forms & User Profile |
| `select` | Forms & User Profile |
| `multi_select` | Forms & User Profile |
| `conditional_field` | Forms & User Profile |
| `form_conditions` | Forms & User Profile |
| `address` | Forms & User Profile |
| `user_address` | Forms & User Profile |
| `store` | Store Classification |
| `store_attribute` | Store Classification |
| `store_category` | Store Classification |
| `store_sub_attribute` | Store Classification |
| `attribute_set` | Store Classification |
| `store_classification` | Store Classification |
| `location` | Store Classification |
| `channel` | Store Classification |
| `store_master` | Store Classification |
| `store_code` | Store Classification |
| `translation` | Translation |
| `language` | Translation |
| `i18n` | Translation |
| `multi_language` | Translation |
| `Thai` | Translation |
| `English` | Translation |
| `Japanese` | Translation |
| `Chinese` | Translation |
| `ui_translation` | Translation |
| `entity_translation` | Translation |
| `default_language` | Translation |
| `fallback` | Translation |
| `cs_conversations` | CS Conversations |
| `cs_messages` | CS Conversations |
| `cs_conversation_events` | CS Conversations |
| `conversation` | CS Conversations |
| `inbox` | CS Conversations |
| `chat` | CS Conversations |
| `reply` | CS Conversations |
| `assign` | CS Conversations |
| `resolve` | CS Conversations |
| `snoozed` | CS Conversations |
| `procedure_state` | CS Conversations |
| `cs_knowledge_articles` | CS Knowledge Base |
| `cs_knowledge_embeddings` | CS Knowledge Base |
| `knowledge` | CS Knowledge Base |
| `article` | CS Knowledge Base |
| `embedding` | CS Knowledge Base |
| `faq` | CS Knowledge Base |
| `custom_answer` | CS Knowledge Base |
| `semantic_search` | CS Knowledge Base |
| `rag` | CS Knowledge Base |
| `pgvector` | CS Knowledge Base |
| `cs_procedures` | CS Procedures |
| `procedure` | CS Procedures |
| `aop` | CS Procedures |
| `trigger_intent` | CS Procedures |
| `flexibility` | CS Procedures |
| `compiled_steps` | CS Procedures |
| `tone_override` | CS Procedures |
| `data_needs` | CS Procedures |
| `action_tools` | CS Procedures |
| `entity_extractors` | CS Procedures |
| `step_topic` | CS Procedures |
| `required_variables` | CS Procedures |
| `prefetch` | CS Procedures |
| `graph_executor` | CS Procedures / CS Voice |
| `deterministic_prefetch` | CS Procedures / CS Voice |
| `code_conditions` | CS Procedures |
| `args_from` | CS Procedures |
| `query_hints` | CS Procedures |
| `cs_channels` | CS Channels & Customers |
| `cs_customers` | CS Channels & Customers |
| `cs_platform_identities` | CS Channels & Customers |
| `cs_customer_memory` | CS Channels & Customers |
| `cs_phone_numbers` | CS Channels & Customers |
| `identity_resolution` | CS Channels & Customers |
| `platform_identity` | CS Channels & Customers |
| `crm_user_id` | CS Channels & Customers |
| `memory` | CS Channels & Customers |
| `cs_brand_config` | CS Brand Configuration |
| `voice_preset` | CS Brand Configuration |
| `guardrails` | CS Brand Configuration |
| `model_config` | CS Brand Configuration |
| `action_config` | CS Brand Configuration |
| `cs_teams` | CS Teams & Agent Profiles |
| `cs_agent_profiles` | CS Teams & Agent Profiles |
| `agent_profile` | CS Teams & Agent Profiles |
| `routing` | CS Teams & Agent Profiles |
| `round_robin` | CS Teams & Agent Profiles |
| `asset` | Asset |
| `asset_type` | Asset |
| `asset_tier_config` | Asset |
| `car_plate` | Asset |
| `Exclusive Parking` | Asset |
| `Asset Group` | Asset |
| `custom_crm_asset_sync` | Asset |
| `bff_admin_upsert_user_asset` | Asset |
| `admin_roles` | Admin Panel |
| `admin_users` | Admin Panel |
| `admin_role_permissions` | Admin Panel |
| `admin_menu_config` | Admin Panel |
| `admin_invitations` | Admin Panel |
| `admin_teams` | Admin Panel |
| `role_config` | Admin Panel |
| `default_path` | Admin Panel |
| `hide_sidebar` | Admin Panel |
| `hidden_menu_categories` | Admin Panel |
| `hidden_menu_items` | Admin Panel |
| `floating_menu` | Admin Panel |
| `role_code` | Admin Panel |
| `frontline` | Admin Panel |
| `bff_get_admin_profile` | Admin Panel |
| `bff_get_admin_menu` | Admin Panel |
| `bff_upsert_admin_role` | Admin Panel |
| `bff_get_admin_role` | Admin Panel |
| `admin_analytics_menu` | Admin Panel |
| `platform_superadmin` | Admin Panel |
| `is_platform_admin` | Admin Panel |
| `assert_platform_admin` | Admin Panel |
| `bff_get_analytics_menu` | Admin Panel |
| `superadmin_list_analytics_menu` | Admin Panel |
| `superadmin_upsert_analytics_menu` | Admin Panel |
| `superadmin_delete_analytics_menu` | Admin Panel |
| `superadmin_reorder_analytics_menu` | Admin Panel |
| `superadmin` | Admin Panel |
| `metabase_dashboard_id` | Admin Panel |
| `is_system_role` | Admin Panel |
| `display_settings` | Display Settings |
| `display_block_template` | Display Settings |
| `display_blocks` | Display Settings |
| `block_type` | Display Settings |
| `block_style` | Display Settings |
| `profile_card` | Display Settings |
| `banner_hero` | Display Settings |
| `bottom_menu` | Display Settings |
| `group_1` | Display Settings |
| `group_2` | Display Settings |
| `object` (group) | Display Settings |
| `entity` (item) | Display Settings |
| `enrichment` | Display Settings |
| `api_get_display_blocks_cached` | Display Settings |
| `bff_get_display_blocks_cached` | Display Settings |
| `admin_get_display_blocks` | Display Settings |
| `fn_enrich_display_config` | Display Settings |
| `get_entity_options_by_type` | Display Settings |
| `trigger_validate_display_settings_config` | Display Settings |
| `merchant_widget_settings` | Display Settings |
| `widget_config_template` | Display Settings |
| `widget_type` | Display Settings |
| `shopify_widget` | Display Settings |
| `admin_get_widget_settings` | Display Settings |
| `admin_upsert_widget_settings` | Display Settings |
| `admin_reset_widget_settings` | Display Settings |
| `bff_get_widget_settings` | Display Settings |
| `api_get_widget_settings_cached` | Display Settings |
| `get_widget_settings_menu` | Display Settings |
| `fn_validate_widget_config` | Display Settings |
| `fn_widget_config_with_defaults` | Display Settings |
| `fn_invalidate_widget_settings_cache` | Display Settings |
| `fn_resolve_widget_storage` | Display Settings |
| `points_unit_label` | Display Settings |
| `points_symbol_type` | Display Settings |
| `points_symbol_icon` | Display Settings |
| `points_symbol_image_url` | Display Settings |
| `admin_upsert_merchant_points_display` | Display Settings |
| `fn_resolve_widget_merchant_display` | Display Settings |
| `trigger_invalidate_widget_cache_on_merchant_display_change` | Display Settings |

| `shopify` | Shopify |
| `shopify_app` | Shopify |
| `shopify-webhooks` | Shopify |
| `auth-shopify-admin` | Shopify |
| `points-to-discount` | Shopify |
| `futurepark` | FuturePark |
| `futurepark_redemptions` | FuturePark |
| `receipt_upload` | Receipt Upload Earning |
| `purchase_receipt_upload` | Receipt Upload Earning |
| `earn_channel` | Earn Channel |
| `earn channel` | Earn Channel |
| `store_credit` | Store Credit |
| `store_credit_promo` | Store Credit |
| `package` (loyalty package) | Package |
| `persona_entitlement` | Persona Entitlement |
| `order_booking` | Order Booking |
| `consent_ledger` | Consent |
| `PDPA` | Consent |
| `platform_plan` | Platform Plan Feature Registry |
| `feature_registry` | Platform Plan Feature Registry |
| `fn_dispatch_outcome` | Central Outcome Dispatcher |
| `central_outcome` | Central Outcome Dispatcher |
| `open-api` | Open API |
| `x-api-key` | Open API |
| `api-users` | Open API |
| `api-wallet` | Open API |
| `analytics-query` | Analytics (BQ) |
| `serving_loyalty` | Analytics (BQ) |
| `home.metrics` | Analytics (BQ) |
| `bigquery` | Analytics (BQ) |
| `checkin` | Check-in |
| `check-in` | Check-in |
| `checkin_ledger` | Check-in |
| `process_checkin` | Check-in |
| `leaderboard` | Leaderboard |
| `campaign_leaderboard` | Leaderboard |
| `top spender` | Leaderboard |
| `api_get_leaderboard_rows` | Leaderboard |
| `api_join_leaderboard` | Leaderboard |
| `klaviyo` | Outbound Integrations |
| `outbound webhook` | Outbound Integrations |
| `X-Rocket-Signature` | Outbound Integrations |
| `integration_delivery_log` | Outbound Integrations |
| `integration_outbox_cursor` | Outbound Integrations |
| `integration_sync_jobs` | Outbound Integrations |
| `sync_new_members` | Outbound Integrations |
| `bff_integration_klaviyo_get_connection` | Outbound Integrations |
| `fn_integration_resolve_member_snapshot` | Outbound Integrations |

