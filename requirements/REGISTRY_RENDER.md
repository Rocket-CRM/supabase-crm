# Render & Edge Registry

> Hand-maintained. No generator — see `.cursor/rules/06-update-docs.mdc`.
> Any task that adds, renames, or deletes an edge function, queue, pg_cron job, or Render service MUST update this file in the same task.
>
> Live truth lives in:
> - Supabase Dashboard → Edge Functions (and `mcp_supabase_list_edge_functions`)
> - `SELECT * FROM cron.job` (pg_cron)
> - `SELECT * FROM pgmq.list_queues()` (PGMQ)
> - Render dashboard (Render services — see below)
>
> Legend: `E:` = Supabase edge function, `R:` = Render service, `C:` = pg_cron job, `Q:` = PGMQ queue.

---

## Auth (LINE / JWT / OTP / Login)

E: auth (jwt)
E: auth-hook-admin-sync (jwt)
E: auth-line (public)
E: auth-line-login (public) [TOMBSTONE — returns 410 Gone, retired 2026-05-14]
E: auth-login (jwt)
E: auth-logout (jwt)
E: auth-refresh (jwt)
E: auth-register (jwt)
E: auth-send-otp (jwt)
E: auth-shopify-admin (public)
E: auth-shopify-verify (public)
E: auth-supabase-only (jwt)
E: auth-user-crm-v1 (public)
E: auth-webhook-sync (jwt)
E: bff-auth-complete (public)
E: bff-profile-lookup (public)
E: check-jwt-claims (jwt)
E: custom-auth (jwt)
E: public-auth (jwt)
E: validate-auth (jwt)
E: validate-token-basic (public)

---

## Currency / Wallet / Points

E: currency-calculator-direct (jwt)
E: points-calculator-direct (jwt)
E: process-direct-earn (jwt)
E: publish-currency-event (jwt)
E: wallet-api (jwt)
E: wallet-transactions (jwt)
C: daily-currency-expiry — `0 19 * * *` → `SELECT process_expiry_if_needed()`
C: refresh-earn-factor-users — `* * * * *` → `SELECT refresh_earn_factor_users_with_log()`
C: refresh-earn-factors — `*/5 * * * *` → `SELECT refresh_earn_factor_caches()`
C: refresh-earn-factors-complete — `*/5 * * * *` → `SELECT refresh_earn_factors_complete_with_log()`

---

## Reward / Redemption / Promo Code

E: bff-get-redemption-detail (jwt)
E: bff-mark-redemption-used (jwt)
E: claim-codes (jwt)
E: claim-codes-award-points-create-receipt (jwt)
E: check-codes-duplicates (jwt)
E: process-codes-duplicates (jwt)
E: validate-codes (jwt)
E: validate-codes-multi (jwt)
E: validate-codes-public (jwt)
E: validate-merchant-prefix (public)
E: delete-merchant-codes (jwt)
E: download-filtered-codes (jwt)
E: import-codes-from-base64 (jwt)
E: import-codes-streaming (jwt)
E: report-code-problem (jwt)
C: refresh-promo-code-summary — `*/5 * * * *` → `REFRESH MV mv_reward_promo_code_summary_internal`
C: refresh_mv_codes_claimed — `0 * * * *` → `REFRESH MV mv_codes_claimed`

---

## Mission

C: mission-daily-global-reset — `0 0 * * *` → `fn_batch_reset_global_missions('daily')`
C: mission-monthly-global-reset — `0 0 1 * *` → `fn_batch_reset_global_missions('monthly')`
C: refresh-mission-conditions-mv — `0 1 * * *` → `REFRESH MV mv_mission_conditions_expanded`

---

## Receipt / OCR

E: admin-receipt-approve (public)
E: admin-receipt-batch-confirm (public)
E: admin-receipt-batch-confirm-v2 (public)
E: admin-receipt-batch-preview (public)
E: admin-receipt-batch-preview-v2 (public)
E: approve-receipts-admin (jwt)
E: clear-receipt-preview (public)
E: forward-receipt (jwt)
E: forward-receipt-with-points (jwt)
E: receipt-preview-v2 (public) — **MUST deploy with `--no-verify-jwt`**; see `00-core.mdc`
E: receipt-recalculate-duplicates (public)
E: receipt-upload-user (public)
E: scanner (public)
E: upload-receipts-auto (jwt)
E: upload-receipts-auto-confirm (public)
E: upload-receipts-auto-preview (public)
E: custom-futurepark-confirm-status (public)
E: custom-futurepark-ocr-eval (public)

---

## AMP / Workflows

E: amp-analysis-apply (public)
E: amp-analysis-message (public)
E: amp-analysis-tools (jwt)
E: amp-batch-dispatch (public)
E: amp-dispatch-realtime-event (public)
E: amp-dispatch-workflow-batch (public)
E: amp-export-node-users (public)
E: dispatch-workflow-trigger (public)
E: inngest-amp-serve (public)
C: amp_run_due_scheduled_workflows — `* * * * *` → `fn_amp_run_due_scheduled_workflows()`

---

## CS (Conversations / Messaging / Voice)

E: cs-loyalty-bridge (public)
E: cs-phone-numbers (jwt)
E: cs-send-message (public)
E: cs-web-push (public, `verify_jwt: false`) — Web Push to `cs_agent_push_subscriptions`; auth via vault `cs_web_push_secret` header. Triggered on assigned + inbound contact messages. See `CS_Platform_Features.md` §9.1.
E: cs-test-delivery (public)
E: line-webhook (public)
E: webhook-line (public)
E: send-line-message (public)
E: send-sms-8x8 (public)
E: voice-custom-llm (public)
E: voice-debug (public)
E: webhook-twilio-sms (public)
E: webhook-twilio-voice (public)
E: webhook-elevenlabs (public)
E: inngest-cs-serve (public)
C: aggregate-agent-performance — `0 * * * *` → `fn_aggregate_agent_performance()`

---

## Marketplace (Shopee / Lazada / TikTok / Shopify / BigCommerce)

E: marketplace-batch-checker (public)
E: marketplace-lazada-exchange-token (public)
E: marketplace-lazada-get-auth-url (public)
E: marketplace-process-orders (public)
E: marketplace-shopee-exchange-token (public)
E: marketplace-shopee-get-auth-url (public)
E: marketplace-shopee-get-auth-url-simple (public)
E: marketplace-tiktok-exchange-token (public)
E: marketplace-tiktok-get-auth-url (public)
E: marketplace-token-refresh (public)
E: webhook-shopee (public)
E: shopify-create-discount-code (jwt)
E: shopify-get-discount-products (public)
E: shopify-list-discounts (public)
E: shopify-points-to-discount (public)
E: shopify-proxy (public)
E: shopify-register-webhooks (jwt) — admin/service-only; idempotent register of orders/* webhooks per shop, stamps `merchant_credentials.webhook_url` + `credentials.webhook_endpoint`
E: shopify-token-refresh (public)
E: shopify-webhooks (public) — receives orders/{create,paid,fulfilled,cancelled,updated} from Shopify; HMAC-verified via `api_secret`; normalizes → `upsert_marketplace_order` → `fn_match_marketplace_user` → `fn_claim_marketplace_order_service` (auto-claim when buyer matches). On `orders/paid` also runs the **loyalty entitlement consume path**: reads `_loyalty_intent_id` (canonical) — falls back to `loyalty_intent_id` and legacy `loyalty_intent_id__` for in-flight widget variants — from `note_attributes`, requires a `Loyalty Redemption` discount line on the order, then GraphQL-reads the customer metafield `loyalty.discount_entitlement` and flips `status:"active"` → `status:"consumed"` (adds `consumed_at`, `order_id`) only when the metafield's `intent_id` matches the cart attribute. Idempotent (no-op when already `consumed`). Consume failures log but never fail the webhook (capture + earn-back already succeeded).
E: bigcommerce-get-merchant-config (public)
E: bigcommerce-get-merchant-config-full (public)
E: bigcommerce-get-user-profile (jwt)
E: bigcommerce-get-user-rewards (jwt)
E: bigcommerce-setup-integration (jwt)
E: inngest-marketplace-serve (public)
C: marketplace-batch-checker — `* * * * *` → POST to edge fn marketplace-batch-checker
C: marketplace-token-refresh — `59 * * * *` → POST to edge fn marketplace-token-refresh
C: shopify-token-refresh — `*/30 * * * *` → POST to edge fn shopify-token-refresh

---

## Knowledge / Embeddings

E: embed-jobs (jwt)
E: embed-knowledge (public)
E: embed-text (jwt)
Q: internal_knowledge_embedding_jobs
C: process-internal-knowledge-embeddings — `10 seconds` → `util.process_embeddings()`

---

## Admin / User / Merchant Management

E: admin-batch-create-users (jwt)
E: admin-batch-create-users-csv (jwt)
E: admin-profile-sync (jwt)
E: admin-user-import-kickoff (jwt)
E: create-merchant (public)
E: get-merchant-config (public)
E: get-merchant-display-settings (jwt)
E: bff-get-merchant-frontend-config (public)
E: get-user-profile (jwt)
E: debug-csv-upload (jwt)

---

## Display / Form / Translation

E: form-submission (public)
E: get-merchant-display-settings (jwt)
E: upsert-display-blocks (public)
E: futurepark_ui_translation (public)

---

## Bulk Import / Customer Import

E: inngest-bulk-import-currency-serve (public)
E: inngest-bulk-import-customers-serve (public)
E: inngest-bulk-import-purchase-serve (public)
E: inngest-bulk-import-redemptions-serve (public)

---

## Inngest (other)

E: inngest-currency-serve (public)
E: inngest-mission-serve (public)
E: internal-proposal-inngest (public)

---

## Purchase / Transaction

E: purchase-orchestrator (jwt)
E: test-purchase-from-edge (jwt)
E: installments-webhook (jwt)
E: stripe-webhook (public)

---

## Futurepark (custom)

E: futurepark-parking-discount (jwt)
E: futurepark-redeem-parking-privilege (public)
E: futurepark-redeem-reward (public)

---

## CRM / Loyalty actions

E: crm-loyalty-actions (public)
E: browse-platform-catalog (jwt)
E: event-router (public)

---

## Rocket Agent (test orchestration)

E: rocket-agent-collect-test-results (public)
E: rocket-agent-trigger-admin-test (public)
E: rocket-agent-trigger-user-test (public)
E: rocket-api-proxy (public)
E: collect-test-results (public)
E: trigger-admin-test (public)
E: trigger-nightly-test (public)
E: trigger-user-test (public)
E: test-admin-login (jwt)
E: test-user-create (jwt)
C: rocket-agent-admin-test — `0 18 * * *` (inactive) → POST to rocket-agent-trigger-admin-test
C: rocket-agent-user-test — `0 19 * * *` (inactive) → POST to rocket-agent-trigger-user-test
C: rocket-agent-collect-results — `0 20 * * *` (inactive) → POST to rocket-agent-collect-test-results

---

## Integrations / Webhooks (misc)

E: database-webhook-handler (jwt)
E: integration-config-api (jwt)
E: metabase-embed (public)
E: metabase-sdk-auth (public)
E: metabase-sso (public)
E: send-email (public)
E: queue-processor (jwt)
E: smooth-processor (jwt)
E: sql-proxy (jwt)

---

## Misc / WIP / Test

E: hello (jwt)
E: hello-world (jwt)
E: placeholder (jwt)
E: first_api (jwt)

---

## Operational pg_cron jobs (infrastructure)

C: cdc-heartbeat — `* * * * *` → heartbeat ping for Debezium CDC
C: kill-stuck-debezium — `*/5 * * * *` (inactive) → kill idle-in-transaction Debezium sessions >5 min
C: wal-lag-alert — `0 */8 * * *` → alert via Lark if `crm_cdc_slot` lag >2 GB
C: refresh-constraint-usage — `*/10 * * * *` → `fn_refresh_constraint_usage()`
C: refresh-form-aggregation — `*/10 * * * *` → `fn_refresh_form_response_aggregation()`
C: chokepoint_outbox_cleanup — `0 3 * * *` → `DELETE FROM public.chokepoint_event_outbox WHERE published_at < now() - 7d` (housekeeping for chokepoint→Kafka outbox)

---

## Render Services

> **Hand-maintained.** Add each Render service below as `R: <name> — <one-line purpose>`. Update on every add/rename/delete.

R: amp-ai-service — Inngest-driven AMP worker (marketing agent + analysis: recommendation generation, distil, refresh crons); source in `amp-analysis-service/` per its README
R: crm-event-processors — Kafka consumers (Currency, Tier, Mission, AMP, OutcomeAttribution, Reward, Marketplace, Notification) reading CDC topics from Confluent Cloud + chokepoint event topics (`crm.events.purchase{,_item}`, `crm.events.wallet`, `crm.events.tier_change`, `crm.events.user`, `crm.events.redemption` — DB layer live 2026-05-16; consumer-side (`AmpConsumer` + `OutcomeAttributionConsumer`) extended 2026-05-16 with subscribe/predicate/dispatch for redemption events; **Confluent topic provisioning + Render redeploy is the last R-2 step in `.cursor/plans/chokepoint-redemption-event.md`**) when `CHOKEPOINT_EVENTS_ENABLED=true`. `NotificationConsumer` (gated by `NOTIFICATION_CONSUMER_ENABLED`) subscribes to `crm.events.{purchase,purchase_item,wallet,tier_change,user,redemption}`, maps purchase `created`/`completed`, purchase_item item-completion events, and existing wallet/tier/signup/redemption catalog rows; enriches `detail_url` (loyalty-app deep links) + `hero_image_url` (reward/tier/merchant branding); calls `fn_resolve_notification_for_event`, renders flex v2 templates (hero + footer CTA + richer rows), pushes to LINE Messaging API (override via `MESSAGING_SERVICE_URL`), writes `public.notification_log`. Also hosts the OutboxPublisher worker (drains `public.chokepoint_event_outbox` to Kafka via LISTEN/NOTIFY + KafkaJS, gated by `OUTBOX_PUBLISHER_ENABLED`); source in `crm-event-processors/`
R: mcp-crm-server — read-only MCP server exposing Supabase CRM data via Cursor MCP; source in `mcp-crm-server/`
R: n8n-replacement — receipt + contact webhook handler that proxies to CRM/HubSpot; source in `n8n-replacement/`

> Bootstrapped from repo-local source directories (`amp-analysis-service/`, `crm-event-processors/`, `mcp-crm-server/`, `n8n-replacement/`). Cross-check against the Render dashboard; if a deployed service isn't listed here, add it.
