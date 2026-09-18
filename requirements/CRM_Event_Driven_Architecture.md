# CRM Event-Driven Architecture

Platform-wide pattern: canonical database writers emit durable events so currency, tiers, missions, notifications, AMP, and partner integrations can react without blocking the member-facing transaction.

Owner surfaces: (infrastructure — no dedicated admin UI) loyalty-admin and loyalty-user only see downstream effects; operators configure Render/Inngest env and monitor workers.

## Concept

Loyalty behaviour is split into a **fast path** (commit the business fact in Postgres) and a **slow path** (fan out reactions). The fast path must stay predictable: one authoritative write per domain, then a guaranteed event record in the same database transaction.

**Chokepoint** — The single function allowed to insert or update a canonical ledger row (purchase, wallet line, tier change, member account, receipt, referral ledger, etc.). Every BFF, edge function, import, and cron must call that function instead of writing the table directly.

**Transactional outbox** — A row in a shared outbox table written inside the chokepoint transaction. If the business change rolls back, no outbox row exists. If it commits, the event exists for downstream workers to read.

**Core automation bus** — Reactions that stay inside Rocket (earn points, evaluate tier, missions, LINE/email notifications, AMP triggers, outcome attribution). An outbox publisher on Render drains eligible rows into **Inngest**; edge-hosted **router functions** match each incoming event name and invoke the right engine (currency serve, tier RPC, notification resolver, etc.). Routers may **bounce back** new Inngest events (for example delayed `currency/award` at 08:00) that engine serves execute later.

**Partner integration bus** — The same outbox table, but **separate workers** with **separate cursors** (custom webhook, Klaviyo). They map internal topics to public `event_key` vocabulary, enrich with a live member snapshot, and POST to merchant credentials. This path does **not** use Inngest.

**Retired path (historical)** — Before 2026-07-07, ledger changes were also captured by Debezium CDC into Confluent Kafka; `crm-event-processors` consumers read Kafka topics. Confluent was deactivated; **live core processing is outbox → Inngest**. CDC cron jobs may still exist for housekeeping or analytics publications; they are not the operational source of truth for chokepoint domain events.

## Rules

### Chokepoint and emit

- Each covered domain has exactly one canonical writer (function-level chokepoint or, for redemption, an AFTER trigger on `reward_redemptions_ledger` that derives lifecycle verbs from column diffs).
- Direct INSERT/UPDATE on canonical ledger tables from other code is forbidden; grants and convention both enforce this for member accounts.
- `fn_chokepoint_emit_event` (or equivalent inline emit inside the chokepoint) inserts one outbox row per emitted event with topic `crm.events.<domain>`, a `partition_key` for ordering (typically user id, purchase id, or redemption id), and a JSON payload aligned with the old CDC shape where routers still expect it.
- `p_skip_emit`, payload `_skip_emit`, or domain-specific skip flags suppress emit for backfills and recursive chokepoint-to-chokepoint calls so the same business action does not double-publish.
- Outbox `topic` must match `^crm\.events\.[a-z_]+$` (table CHECK).

### Core publisher (Inngest)

- Only topics listed in Render env `OUTBOX_PUBLISH_TOPICS` are sent to Inngest. Unlisted topics remain in the outbox unpublished (durable, replayable) until a router exists and ops adds the topic — publishing without a listener would drop work silently.
- Default allowlist in code (when env unset): `crm.events.purchase`, `crm.events.purchase_item`, `crm.events.wallet`, `crm.events.tier_change`, `crm.events.user`, `crm.events.redemption`, `crm.events.receipt`. **`crm.events.referral` is not in that default** — production must include it explicitly for referral notifications and Klaviyo referral metrics.
- Publisher marks a row `published_at` after Inngest accepts the batch. Failed sends increment `publish_attempts` and store `last_error`; retries stop after `OUTBOX_PUBLISHER_MAX_ATTEMPTS`.
- Delivery is **at-least-once** from the outbox; each Inngest event uses deterministic id `chokepoint-outbox-<row-id>` so duplicates dedupe in Inngest.
- Wake-up: `pg_notify('chokepoint_outbox_new', …)` after insert, plus polling fallback (`OUTBOX_PUBLISHER_POLL_INTERVAL_MS`). Workers use `FOR UPDATE SKIP LOCKED` for horizontal scale.
- Inngest event naming: `crm.events.purchase` → `crm/purchase.event` (domain segment from topic).

### Inngest routers and engines

- `inngest-event-router-serve` registers one Inngest function per router (currency, tier, mission, outcome, notification-*, AMP, Shopify redemption issue). Inngest invokes matching functions for each `crm/<domain>.event` (fan-out: one purchase event may hit currency, tier, mission, notification, AMP routers in parallel).
- Router idempotency replaces legacy Kafka consumer Redis dedup (24h window). Tier evaluation may use per-user concurrency keys where ordering matters.
- **Not** routed here: expiry reminders (scheduled scan, Render cron `expiry-reminder-batch`); AMP triggers that still depend on CDC-only sources (`form_submissions`, `amp_workflow_log` audience adds) until chokepoint emits exist at those write sites.

### Partner integration publishers

- Consumers read `chokepoint_event_outbox` where `id > integration_outbox_cursor.last_id` and `created_at <= now() - 10 seconds` (lag avoids reading in-flight transactions).
- Cursor keys are per worker (`integration-webhook`, `integration-klaviyo`, etc.); advancing the cursor is independent of `published_at` on the core Inngest path.
- Rows with no mapped public `event_key` are skipped but the cursor still advances past them.
- Merchant must have active credentials and subscribed keys; missing email or required identity → skip with logged reason, not silent success.
- Shopify install does not change the bus contract; wallet/referral emits from Judge.me earn or Gorgias goodwill still flow through the same outbox if integrations are connected (`requirements/reference/SHOPIFY_REFERRALS_ONSITE_INTEGRATIONS.md` Part 3.5 — detail in `Outbound_Integrations.md`).

### Housekeeping

- pg_cron `chokepoint_outbox_cleanup` (daily): delete rows with `published_at` older than 7 days (core path retention; integration cursors are logical positions, not row deletes).
- `integration_delivery_log` retention: separate pg_cron cleanup (30 days) — see `Outbound_Integrations.md`.

### Example (non-obvious)

A purchase completes → `chokepoint_post_purchase_event` commits ledger + outbox rows for parent and/or line items → OutboxPublisher sends `crm/purchase.event` → `currency-purchase-router` computes earn rows and emits `currency/award` with `sleepUntil` → `inngest-currency-serve` waits, then calls `chokepoint_post_wallet_transaction` → wallet chokepoint commits ledger + `crm.events.wallet` outbox row → cycle repeats for tier/mission/notification routers on the wallet event.

## Journeys

There is no merchant settings page for the event bus. Journeys below are **operator / engineer** and **indirect member** effects.

| Actor | Repo / tier | What they touch |
| --- | --- | --- |
| Platform operator | Render `crm-event-processors` | Env: `OUTBOX_PUBLISHER_ENABLED`, `OUTBOX_PUBLISH_TOPICS`, `INTEGRATION_*_ENABLED`, `SUPABASE_DB_DIRECT_URL` |
| Platform operator | Supabase Edge | Deploy `inngest-event-router-serve`, `inngest-currency-serve`, `inngest-mission-serve` |
| Merchant staff | loyalty-admin | Configures notifications, integrations, earn rules — those domains decide *whether* a reaction fires, not the bus itself |
| Member | loyalty-user | Sees points, tier, messages after async routers finish |

### Operator journey (core path health)

1. Confirm `OUTBOX_PUBLISHER_ENABLED=true` and `INNGEST_EVENT_KEY` set on `crm-event-processors`.
2. Confirm `OUTBOX_PUBLISH_TOPICS` includes every topic with a deployed router (purchase, purchase_item, wallet, tier_change, user, redemption, receipt, and referral when referral notifications are required).
3. Confirm `inngest-event-router-serve` is deployed and Inngest app synced (signing key, serve URL).
4. On backlog: check unpublished rows (`published_at IS NULL`, `publish_attempts` below max), publisher logs, and Inngest function failures per router name.
5. On duplicate side effects: verify idempotency keys and that backfills used `_skip_emit` / `p_skip_emit`.

### Operator journey (partner path health)

1. Confirm `INTEGRATION_WEBHOOK_ENABLED` and/or `INTEGRATION_KLAVIYO_ENABLED` on the same Render service.
2. In admin **Integrations**, merchant connects webhook or Klaviyo (credentials in `merchant_credentials`).
3. Monitor `integration_delivery_log` and credential degraded state; cursor lag warnings in worker logs (>5000 id gap or stale `created_at`).

### Member journey

1. Member completes an action visible in the app (buy, earn, redeem, sign up).
2. UI may show the committed ledger state immediately; points/tier/messages that depend on routers may appear after seconds (or after a scheduled `sleepUntil`).
3. If async processing fails, the member still keeps the committed purchase/wallet fact; operations fix forward via logs and replay policies — not by editing the outbox from the member UI.

## System

### Data model

| Object | Role |
| --- | --- |
| `chokepoint_event_outbox` | Transactional bus: `topic`, `partition_key`, `payload`, `created_at`; core publisher sets `published_at`, `publish_attempts`, `last_error` |
| `integration_outbox_cursor` | Per-integration-worker read position (`consumer_key`, `last_id`) |
| `integration_delivery_log` | Per `(outbox_id, credential_id)` delivery outcome for partners |
| Canonical ledgers | `purchase_ledger`, `purchase_items_ledger`, `wallet_ledger`, `tier_change_ledger`, `user_accounts`, `reward_redemptions_ledger`, receipt/referral tables — written only through chokepoints (or redemption emit trigger) |

### Functions (chokepoint writers and emit)

| Function | Ledger / subject | Emit topic(s) |
| --- | --- | --- |
| `chokepoint_post_purchase_event` | Purchase parent + line items | `crm.events.purchase`, `crm.events.purchase_item` |
| `chokepoint_post_wallet_transaction` | Wallet lines | `crm.events.wallet` |
| `chokepoint_post_tier_change` | Tier change ledger | `crm.events.tier_change` |
| `chokepoint_post_user_event` | Member accounts | `crm.events.user` |
| `chokepoint_post_receipt_event` | Receipt upload lifecycle | `crm.events.receipt` |
| `chokepoint_post_referral_event` | Referral ledger / claims | `crm.events.referral` |
| `trigger_emit_redemption_event` (on `reward_redemptions_ledger`) | Redemption lifecycle | `crm.events.redemption` |
| `fn_chokepoint_emit_event` | — | Inserts outbox row + `pg_notify` |

Convention and migration status per domain: `requirements/architecture/event-chokepoints.md`.

### Flows

**End-to-end (core)**

```
Caller (BFF / api_* / edge / import)
  → chokepoint_post_*  (ledger COMMIT + fn_chokepoint_emit_event)
  → chokepoint_event_outbox
  → OutboxPublisher (crm-event-processors, LISTEN/NOTIFY + poll, batches of 50 to Inngest API)
  → Inngest cloud (crm/<domain>.event)
  → inngest-event-router-serve (parallel routers per domain)
       ├─ currency-* → inngest-currency-serve → chokepoint_post_wallet_transaction (delayed awards)
       ├─ tier-* → process_tier_event / tier serve
       ├─ mission-* → inngest-mission-serve
       ├─ outcome-* → outcome attribution
       ├─ notification-* → fn_resolve_notification_for_event → LINE / email
       ├─ amp-* → amp-dispatch-realtime-event
       └─ shopify-redemption-issue (Shopify fulfillment edge case)
```

**End-to-end (partners — same outbox, different readers)**

```
chokepoint_event_outbox
  → IntegrationWebhookPublisher / IntegrationKlaviyoEventConsumer (cursor tail, 10s lag)
  → event_keyFromOutbox + fn_integration_resolve_member_snapshot
  → HTTPS to merchant webhook or Klaviyo APIs
  → integration_delivery_log
```

**Bulk and imports** — Same chokepoints; imports set skip-emit flags when replay would duplicate earn (see `Bulk_Import_Currency.md`, `Purchase_Import_System.md`).

### External services

| Service | Role |
| --- | --- |
| Render `crm-event-processors` | `OutboxPublisher`, integration publishers, expiry-reminder-batch, loyalty-cache crons; legacy Kafka consumer processes optional when `CHOKEPOINT_EVENTS_ENABLED=true` (Confluent deactivated — do not plan new work on Kafka path) |
| Supabase Edge `inngest-event-router-serve` | Inngest serve endpoint for all `*-router` functions |
| Supabase Edge `inngest-currency-serve`, `inngest-mission-serve` | Durable engine steps (sleep, retry, wallet chokepoint callbacks) |
| Inngest Cloud | Registry, fan-out, idempotency, scheduling |
| pg_cron | `chokepoint_outbox_cleanup`; legacy `cdc-heartbeat` / WAL alerts if CDC publication still monitored |

Env reference (Render): `OUTBOX_PUBLISHER_ENABLED`, `SUPABASE_DB_DIRECT_URL`, `INNGEST_EVENT_KEY`, `OUTBOX_PUBLISH_TOPICS`, `OUTBOX_PUBLISHER_BATCH_SIZE` (default 500 drain; Inngest POST chunks 50 events), `INTEGRATION_WEBHOOK_ENABLED`, `INTEGRATION_KLAVIYO_ENABLED`.

### Known gaps

- **Registry / README drift** — `REGISTRY_RENDER.md` and `crm-event-processors/README.md` still describe Kafka as the OutboxPublisher target and active CDC consumers; live publisher code is Inngest-only (`outbox-publisher.ts`, 2026-07-07).
- **Referral notification router** — DB catalog + `chokepoint_post_referral_event` live; `notification-referral-router` exists in `.cursor/deploy/inngest-event-router-serve` but may be absent from `supabase/functions/inngest-event-router-serve` until merged and redeployed (`Notification_Service.md`).
- **Referral topic allowlist** — Default `OUTBOX_PUBLISH_TOPICS` in repo omits `crm.events.referral`; production Render env must set it explicitly.
- **CDC-only AMP sources** — Form completion and audience-add workflow logs still lack chokepoint emits; AMP routers on Inngest do not replace those until emit sites exist (`inngest-event-router-serve/index.ts` header comment).
- **Mission completed emit** — `mission_log_completion` trigger exists; mission fan-out on Inngest is primarily purchase/wallet/purchase_item routers — confirm mission-specific outbox topic if product adds direct `crm.events.mission` consumers.

## Related

- Chokepoint migration convention — `requirements/architecture/event-chokepoints.md`
- Where code runs — `requirements/architecture/System_Map.md`
- Partner delivery contract — `requirements/Outbound_Integrations.md`, `requirements/Third_Party_Integrations.md`
- Notification mapping from topics — `requirements/Notification_Service.md` § System
- Purchase/wallet earn detail — `requirements/Purchase_Transaction.md`, `requirements/Currency.md`
- Central outcome fan-out — `requirements/Central_Outcome_Dispatcher.md`
