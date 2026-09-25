# Outbound integrations — Webhook + Klaviyo (v1 plan)

**Status:** Final — approved for build 2026-09-06 (see "Review adjustments" at the end)  
**Date:** 2026-09-06  
**Owners:** `crm-event-processors` (workers), `supabase-crm` (schema, RPCs, Edge), `loyalty-admin` (UI — separate repo)

---

## Goal

Ship outbound integrations from the existing loyalty outbox:

1. **Custom webhooks** — merchant pastes URL + signing secret; receives canonical loyalty events.
2. **Klaviyo (native, v1)** — OAuth connect, full profile upsert, loyalty metrics, Sync all backfill.

**Not in scope:** a shared “integration engine” that routes all partners through one dispatcher. Partners are separate modules; only the outbox bus and credential storage are shared.

**Inngest:** stays on internal domain routers (currency, tier, mission, AMP, notifications). Partner firehose does **not** go through Inngest.

---

## Architecture

```
chokepoint_event_outbox
        │
        ├─► OutboxPublisher → Inngest → internal routers          (unchanged)
        │
        ├─► integration_webhook_publisher                         (outbox, cursor: webhook)
        │
        └─► integration_klaviyo_event_consumer                    (outbox, cursor: klaviyo_events)

integration_klaviyo_sync_worker                                   (integration_sync_jobs — not outbox)

Edge:
  integration-klaviyo-oauth-start
  integration-klaviyo-oauth-callback

Admin BFF RPCs (loyalty-admin calls these)
```

### Klaviyo — three entry points, one client

| Entry | Handler | Calls |
|-------|---------|-------|
| **OAuth** | Edge + BFF RPCs | OAuth kit → store tokens → fetch account name |
| **Sync all** | `integration_klaviyo_sync_worker` | `fn_integration_resolve_member_snapshot` → `profile-map` → **Bulk Import Profiles** job |
| **Events** | `integration_klaviyo_event_consumer` | resolve → **one** Klaviyo call (Create Event with profile inline, or Create/Update Profile) |

All Klaviyo API work lives in **`integration/klaviyo/client.ts`** (create event, create-or-update profile, bulk import job submit/poll, token refresh, get account). Not shared with webhook.

**Klaviyo API model (verified against Klaviyo docs, revision 2026-01-15):**

- `POST /api/events/` **creates or updates the profile inline** — profile properties ride on the event. Metric events are therefore **one call**, not "profile upsert then metric". Set `unique_id` = outbox row id so a retry never double-counts.
- Profile-only touches (burn / expire / adjustment / user update) → `POST /api/profile-import/` (create-or-update by email). One call.
- **Sync all** → `POST /api/profile-bulk-import-jobs/` (≤10,000 profiles / 5 MB per job; rate 10/s). Submit chunks, poll job status, record import errors. Do **not** loop per-profile upserts for backfill — Klaviyo's own loyalty guide says bulk import for state, events only for the hot path.
- OAuth is **authorization code + PKCE** (`code_verifier` required at token exchange). Access token ~1 h; **refresh token rotates on every use** — persist the new refresh token every time or the merchant is silently disconnected.
- Scopes: `profiles:write`, `events:write`, `lists:write` (bulk import requires it), `accounts:read` (account name on connect).

### OAuth kit (shared helpers — not one function)

Extract when Klaviyo ships; generalize when partner #2 uses OAuth.

| Kit module | Runtime | Responsibility |
|------------|---------|----------------|
| `generateOAuthState(merchant_id, integration_key)` | Edge | Signed state; also generates PKCE pair and parks `code_verifier` in the merchant's credential row (`credentials.oauth_pending = { state, code_verifier, expires_at }`, row created `is_active=false` if absent). No new table. |
| `verifyOAuthState(state)` | Edge | Recover `merchant_id`, load + clear `oauth_pending`, reject if expired |
| `storeIntegrationTokens(...)` | Edge | Write tokens into `merchant_credentials.credentials`, set `expires_at`, `is_active=true`, `health_status='connected'` |
| `getValidAccessToken(credential)` | Render | Read; refresh if expired/401 via **`fn_integration_lock_credential`** (`SELECT … FOR UPDATE` on the row) so the event consumer and the sync worker never race the rotating refresh token |
| `refreshAccessToken(integration_key, refresh_token)` | Render | Partner token URL from config; persist **both** new tokens in the same locked transaction |

Disconnect is a BFF RPC (`is_active=false`), not a kit function — see BFF table. Klaviyo `/oauth/revoke` on disconnect is a v2 nicety.

Partner-specific: auth URL, token URL, scopes, callback parsing — `integration/klaviyo/oauth-config.ts` + Edge handlers.

**Location:** start/callback/store = `supabase/functions/_shared/integration-oauth/` (Edge). Read/refresh = `crm-event-processors/src/integration/_oauth/` (Render). Two runtimes, so two thin files — the token shape in `credentials` jsonb is the shared contract, not a shared module.

---

## Design principles (L1 / L2 alignment)

| Principle | Decision |
|-----------|----------|
| Complexity budget | No retry table, no scheduled retry v1 — the cursor **always advances**; retry is in-process only (3 attempts inside the same delivery), final outcome logged. No shared router engine. |
| Unify + discriminator | One `integration_delivery_log`, one `integration_outbox_cursor`, one `integration_sync_jobs` — keyed by `integration_key`. **One** member resolver `fn_integration_resolve_member_snapshot` for both lanes — not a per-partner resolver. |
| Reuse existing config | `integration_type_master` + `integration_field_definitions` + `merchant_credentials` + `bff_get/upsert_integration_config`. Non-token settings (`subscribed_events`, `sync_new_members`, `webhook_url`, `signing_secret`) are **field definitions** on the type — no bespoke setter RPCs. |
| Shared abstraction when 2+ need it | OAuth kit + `event-keys.ts` + outbox-read helper — not a partner registry. |
| One write path for tokens | OAuth kit → `merchant_credentials.credentials` only; refresh under row lock. |
| Security at boundary | Admin BFF: `get_current_merchant_id()`. Resolve/lock RPCs: service_role only. Webhook URL: https only, private/loopback IPs rejected at save and at send. |
| Name capability, place it | Webhook lane + Klaviyo lane — not “IntegrationPublisher engine”. |
| Follow repo layout | `crm-event-processors`: long-running loops in `src/workers/`, partner modules in `src/integration/<partner>/`, env flags per lane (`INTEGRATION_WEBHOOK_ENABLED`, `INTEGRATION_KLAVIYO_ENABLED`) like `NOTIFICATION_CONSUMER_ENABLED`. |

---

## Naming convention

Pattern: **`integration` → `partner` → `purpose`**

### Render workers (`crm-event-processors`)

| Path | Purpose |
|------|---------|
| `workers/integration-webhook-publisher.ts` | Outbox loop (entry, wired in `index.ts` behind `INTEGRATION_WEBHOOK_ENABLED`) |
| `workers/integration-klaviyo-event-consumer.ts` | Outbox loop (entry, behind `INTEGRATION_KLAVIYO_ENABLED`) |
| `workers/integration-klaviyo-sync-worker.ts` | Polls `integration_sync_jobs` (same flag) |
| `integration/webhook/deliver.ts` | Envelope + HMAC + URL guard |
| `integration/klaviyo/client.ts` | Klaviyo API: create event, create-or-update profile, bulk import, refresh, account |
| `integration/klaviyo/event-map.ts` | v1 metric rules (`event_key` → metric name or profile-only) |
| `integration/klaviyo/profile-map.ts` | member snapshot → Rocket * property names |
| `integration/klaviyo/oauth-config.ts` | URLs, scopes |
| `integration/_oauth/*` | Token read/refresh (Render half of the kit) |
| `integration/_shared/event-keys.ts` | Raw outbox row → `event_key` (the public contract vocabulary) |
| `integration/_shared/outbox-read.ts` | Batch read + cursor + lag window |
| `integration/_shared/delivery-log.ts` | Log final outcome, circuit-break |
| `integration/_shared/with-retry.ts` | In-process retry: 3 attempts, 1 s → 2 s, honours `Retry-After` on 429 |

### Edge Functions

| Slug | `verify_jwt` | Purpose |
|------|--------------|---------|
| `integration-klaviyo-oauth-start` | admin JWT | Return `authorization_url` |
| `integration-klaviyo-oauth-callback` | `false` | Verify state + PKCE, exchange code, store tokens, fetch account name, redirect to admin |

### Admin BFF RPCs (`bff_*`)

| Function | Purpose |
|----------|---------|
| `bff_integration_klaviyo_get_connection` | connected, account name, health, `sync_new_members`, **latest sync job** (state + progress) — FE polls this during Sync all |
| `bff_integration_klaviyo_disconnect` | `is_active=false`; consumers and sync stop |
| `bff_integration_klaviyo_start_sync_all` | Insert `integration_sync_jobs` row (reject if one is already queued/running) → `{ job_id }` |

Everything else rides the existing Integration Hub: **`bff_get_integration_config` / `bff_upsert_integration_config`** already resolve the merchant, look up `integration_type_master`, and merge typed fields into `merchant_credentials.credentials` by `integration_field_definitions`. Add field-definition rows for `klaviyo` (`sync_new_members` boolean) and `webhook` (`webhook_url`, `subscribed_events` array, `signing_secret` sensitive). No `set_sync_new_members`, `get_sync_status`, or `get_contract` RPCs — the v1 property/metric list is a static FE constant mirrored from `event-map.ts` and documented in `requirements/`.

### Internal RPCs (`fn_*`, service_role)

| Function | Purpose |
|----------|---------|
| `fn_integration_resolve_member_snapshot(p_merchant_id, p_user_id)` | **One** live member snapshot for both lanes: identity (email/phone/name/dob/joined), points balance, burn rate (`fn_resolve_burn_rate`), status, current/next tier + amount needed, referral URL, next expiry amount/date, points-to-next-reward. Build from the same pieces `bff_admin_get_member_360` uses — extract, do not copy. Returns NULL email as a field; the caller decides to skip. |
| `fn_integration_lock_credential(p_credential_id)` | `SELECT … FOR UPDATE` wrapper used by token refresh (Render holds the txn while refreshing) |

Webhook enrichment is the same snapshot embedded as `data.member`; Klaviyo maps it through `profile-map.ts`. A "lighter" webhook resolver is a premature optimisation at ~5k outbox rows/day.

### Schema

| Object | Notes |
|--------|-------|
| `integration_type_master` | Rows: `integration_key = 'klaviyo'` (`platform_key='klaviyo'`), `'webhook'` (`platform_key='webhook'`); `public_fields` / `sensitive_fields` set so the Hub masks tokens and the secret |
| `integration_field_definitions` | `klaviyo.sync_new_members` (boolean); `webhook.webhook_url`, `webhook.subscribed_events` (array), `webhook.signing_secret` (sensitive) |
| `merchant_credentials` | Reuse as-is — **no new columns**. `service_name` = integration_key. `credentials` jsonb holds tokens + typed config (Hub convention); existing `is_active`, `expires_at`, `health_status`, `last_health_check` carry connection state. The legacy `webhook_url` column is left unused (one home for config = jsonb). **v1 = one webhook endpoint per merchant** (one row) so the generic upsert RPC, which updates the latest row per `service_name`, stays correct. Multi-endpoint is v2. |
| `integration_delivery_log` | One row per (outbox row × credential), written once with the **final** outcome: `integration_key`, `merchant_id`, `credential_id`, `outbox_id bigint`, `event_key`, `status` (`delivered` / `failed`), `attempts` (1–3), `last_error`, `response_status`. Skipped rows are **not** logged. Index `(merchant_id, created_at DESC)`. 30-day purge via pg_cron, same shape as `chokepoint_outbox_cleanup`. `status` is kept so a v2 scheduled retry is a `next_retry_at` column, not a redesign. |
| `integration_outbox_cursor` | `consumer_key` PK (`webhook`, `klaviyo_events`), `last_id bigint`, `updated_at`. Precedent: `shopify_subscription_job_cursor`. RLS on, no merchant policy (service_role only). |
| `integration_sync_jobs` | `integration_key`, `merchant_id`, `status` (`queued` / `running` / `done` / `failed`), `members_total`, `members_synced`, `members_skipped_no_email`, `last_error`, `started_at`, `finished_at`, `partner_job_ids jsonb`. Plural per `codes_import_jobs`. |

Standard columns per L2: `id uuid`, `merchant_id`, `created_at`, RLS merchant isolation on log + jobs.

---

## Flow summaries

### Outbox read (shared — `outbox-read.ts`)

Both outbox lanes read the same way; this is where the two cursor pitfalls are handled.

- `SELECT … FROM chokepoint_event_outbox WHERE id > $last_id AND created_at <= now() - interval '10 seconds' ORDER BY id LIMIT $batch`. The **lag window** matters: `id` comes from the sequence at INSERT time but rows commit in any order, so a plain `id > last_id` can skip a row whose transaction commits late. Chokepoint transactions are short plpgsql; 10 s covers them.
- Independent of `published_at` (the Inngest publisher's marker). Integration lanes never write the outbox.
- `merchant_id` is in `payload` on every topic (verified live) — that is the merchant key for credential lookup.
- Retention: `chokepoint_outbox_cleanup` deletes rows 7 days after `published_at`. A consumer that lags > 7 days loses events, so cursor age is a health signal (log a warning when `max(id) - last_id` stays large or the newest processed `created_at` is > 1 day old).
- Cursor advances to the batch's max `id` **every batch**, regardless of delivery outcome (see Health / retry).

### `integration_webhook_publisher` (outbox only)

1. **Read batch** after cursor `webhook` (shared reader above).
2. **Skip** merchants with no active `webhook` credential (in-memory cache, ~60 s TTL, invalidated by the same cache path the Hub already uses).
3. **Canonicalize** — raw row → `event_key`; unmapped → skip. **`integration/_shared/event-keys.ts`**
4. **Dispatch** — keep the credential where `event_key ∈ credentials.subscribed_events`.
5. **Enrich** — **`fn_integration_resolve_member_snapshot`** → `data.member`
6. **Transform + send** — **`integration/webhook/deliver.ts`**: body `{ id, type, version, occurred_at, merchant_id, data: { event, member } }`; `id` = `outbox_id:credential_id` (deterministic so the receiver can dedupe retries). Headers `X-Rocket-Event`, `X-Rocket-Delivery`, `X-Rocket-Signature: t=<unix>,v1=<hmac_sha256(secret, "<t>.<body>")>`. https only, resolved IP must be public, 10 s timeout, no redirects, any non-2xx = failure.
7. **Log** — one `integration_delivery_log` row with the final outcome (`delivered` / `failed`, `attempts`); advance cursor; circuit-break per credential.

### `integration_klaviyo_event_consumer` (outbox only)

1. **Read batch** after cursor `klaviyo_events`.
2. **Skip** merchants without an active `klaviyo` credential (`is_active = false` after disconnect).
3. **Canonicalize + v1 filter** — **`event-keys.ts`** + **`event-map.ts`** (metric | profile-only | ignore). `user.create` honours `sync_new_members`.
4. **Resolve snapshot** — **`fn_integration_resolve_member_snapshot`**; no email → skip (not logged).
5. **One Klaviyo call** — metric applies → `POST /api/events/` with metric name, `unique_id` = outbox id, full Rocket * properties inline (`profile-map.ts`). Profile-only → `POST /api/profile-import/`. **`client.ts`**
6. **Log**; cursor; health. 401 → refresh under `fn_integration_lock_credential` and retry once (counts as one of the 3 attempts); second 401 → `failed`, counts toward the circuit-break.

Profile-only (no metric): wallet burn / expire / adjustment; user update.

### `integration_klaviyo_sync_worker` (not outbox)

1. Claim a `queued` job from **`integration_sync_jobs`** (`FOR UPDATE SKIP LOCKED` → `running`).
2. Walk members with email in keyset chunks; **`fn_integration_resolve_member_snapshot`** per member → `profile-map.ts`.
3. Submit each chunk (≤10,000 profiles / ≤5 MB) as a **Bulk Import Profiles** job; store partner job ids; poll to completion; count import errors as skipped.
4. Update job progress (`members_total`, `members_synced`, `members_skipped_no_email`, `last_error`) → `done` / `failed`. One active job per merchant.

### OAuth (not outbox)

1. Admin clicks Connect → Edge `integration-klaviyo-oauth-start` (admin JWT) → generates state + PKCE pair, parks `oauth_pending` on the credential row → returns `authorization_url`.
2. Klaviyo consent → Edge `integration-klaviyo-oauth-callback` (`verify_jwt=false`) → verifies state, exchanges `code` + `code_verifier`, stores tokens, calls `GET /api/accounts/` for the account name, sets `is_active=true`, `health_status='connected'`, default `sync_new_members=true`.
3. Redirect back to the admin Integration page.
4. Disconnect (BFF) → `is_active = false`; consumers and sync stop. Reconnect requires a fresh OAuth; events emitted while disconnected are not replayed — merchant runs Sync all.

Sample metrics on connect are **cut** from v1: Klaviyo has no create-metric API, and firing synthetic events pollutes a real profile. Metrics appear on the first real event.

---

## Klaviyo product rules (v1 contract)

### Identity

- Match by **email** only. No email → skip. Never create Klaviyo profile without email.

### Operating model

- One merchant-triggered **Sync all** backfill, then event-driven.
- **Create-if-missing** on every write path.
- **Full profile on every write** — every Klaviyo call carries the full Rocket property set (inline on the event, or as the profile body). Never a metric without properties. Load **live** member state at send time via `fn_integration_resolve_member_snapshot`; do not trust the outbox payload alone for balance, tier, referral URL, expiry, points-to-next-reward.

### Tokens

- Per merchant in `merchant_credentials`, `service_name = 'klaviyo'`, tokens in `credentials` jsonb.
- OAuth only (no API key paste). Refresh on expiry/401 under a row lock; persist the rotated refresh token every time. Disconnect stops all writes.

### Profile properties (always send on every Klaviyo touch)

| Klaviyo property | Source |
|------------------|--------|
| Rocket Points Balance | current points |
| Rocket Points as Cash Balance | points × burn rate (omit if no burn rate) |
| Rocket Loyalty Status | member status |
| Rocket Referral URL | referral link |
| Rocket VIP Tier Name / ID | current tier |
| Rocket Next VIP Tier Name | next tier if any |
| Rocket Amount Needed for Next VIP Tier | remaining to next |
| Rocket Date of Birth | birthday |
| Rocket Member Joined Date | loyalty join |
| Rocket Points Next Expiry Amount / Date | if expiry enabled |
| Rocket Points to Next Reward | cheapest visible reward − balance |

Also: standard Klaviyo fields `email` (required), `first_name`, `last_name`, `phone` when available.

**Do not send:** store credit, membership billing, preference questions, credits-as-currency, SMS/email consent.

### v1 metrics (exact names)

Map from **existing** outbox topics only — no new chokepoints.

| Metric | When |
|--------|------|
| Rocket Points Earned | `crm.events.wallet`, earn + base component. Not for adjustment. Birthday source also fires Rocket Birthday Reward Issued. |
| Rocket Reward Redeemed | `crm.events.redemption`, issued |
| Rocket VIP Tier Achieved | `crm.events.tier_change`, upgrade |
| Rocket VIP Tier Downgraded | `crm.events.tier_change`, downgrade |
| Rocket Referral Friend Claimed | `crm.events.referral`, claimed, friend |
| Rocket Referral Completed | `crm.events.referral`, settled, advocate |
| Rocket Member Activated | `crm.events.user`, create |
| Rocket Birthday Reward Issued | wallet earn with birthday source and/or birthday redemption — skip if indistinguishable |

**Profile-only (no metric):** wallet burn / expire / adjustment; user update.

**Not v1:** expiry warning metrics (clock job); Referral Invite Sent (`referral.shared` not emitted).

### Sync all + sync new members

- **Sync all:** walk members with email; Bulk Import Profiles jobs; progress pollable via `bff_integration_klaviyo_get_connection`. State backfill only — never replay historical events as metrics.
- **sync_new_members** (default on after connect): when on, user-create outbox path upserts profile; when off, new members wait for Sync all or a later loyalty event (event path still create-if-missing).

### Out of scope (v1)

- SMS/email list subscribe
- Award points from Klaviyo flow
- Customer Hub / Klaviyo marketplace listing
- Membership, store credit, gift card, cashback properties
- Recharge; Klaviyo Reviews inbound

---

## Event → destination mapping (where logic lives)

| Question | Location |
|----------|----------|
| What happened? (`event_key`) | **`integration/_shared/event-keys.ts`** — a **new, public, versioned vocabulary** (`points.earned`, `reward.redeemed`, `tier.upgraded`, `referral.completed`, `member.created`, …). The notification router's coarse keys (`currency`, `tier`, `signup`) are a reference for payload semantics, not the source; the webhook contract is finer than notifications need. |
| Which partners get this event? | **`merchant_credentials.credentials.subscribed_events`** (webhook) / `event-map.ts` (Klaviyo) |
| Shared fields before partner shape | **`fn_integration_resolve_member_snapshot`** |
| Webhook JSON + HMAC | **`integration/webhook/deliver.ts`** |
| Klaviyo profile + metrics | **`integration/klaviyo/client.ts`**, **`event-map.ts`**, **`profile-map.ts`** |

---

## What to change when

| Change | Touch |
|--------|-------|
| Merchant toggles events | `subscribed_events` via **`bff_upsert_integration_config('webhook', …)`** (Hub form) |
| New loyalty outbox shape | **`event-keys.ts`**, then merchant opt-in |
| New Klaviyo metric | **`event-map.ts`** |
| New Rocket * property | **`fn_integration_resolve_member_snapshot`** (data) + **`profile-map.ts`** (name) — webhook gets it for free in `data.member` |
| Merchant changes webhook URL | Re-save in Hub (same row) — **`deliver.ts`** unchanged. Multiple endpoints per merchant = v2 (needs a per-row Hub UI and a unique index like the marketplace rows). |
| New partner type (e.g. Judge.me) | New folder under **`integration/<partner>/`**, own worker if needed, **`integration_type_master`** + field-definition rows |
| Second OAuth partner | Reuse **`_oauth/`** kit; add partner config + Edge callbacks |
| Second backfill partner | Reuse **`integration_sync_jobs`** with new `integration_key` |

---

## Health / retry (v1)

- **Cursor always advances.** Holding the cursor back for a failed delivery would let one merchant's dead URL stall every merchant on the lane (one scalar cursor per consumer = head-of-line blocking).
- **Retry is in-process only.** `with-retry.ts` wraps every partner call: up to 3 attempts, 1 s then 2 s, honours `Retry-After` on 429, retries on network error / 429 / 5xx only (4xx other than 401/429 is final). Same snapshot, same body, same `unique_id` / `X-Rocket-Delivery` — the receiver can dedupe. Then one log row with the final outcome.
- **No scheduled retry in v1.** An endpoint or Klaviyo outage longer than a few seconds loses those events; the merchant sees "degraded" and, for Klaviyo, runs Sync all to restore profile state. Lost metrics are not replayed. This is a deliberate v1 cut, not an oversight — v2 adds `next_retry_at` to the log and a drain pass if real merchants hit it.
- **Circuit-break per credential:** N (=20) consecutive `failed` outcomes → `health_status='degraded'`, `last_health_check=now()`; lane skips the credential and stops logging for it. Merchant sees "degraded" in the Hub and re-saves (webhook) or reconnects (Klaviyo) to reset to `connected`. `is_active` stays true — `is_active=false` means the merchant disconnected, not that we gave up.

---

## Build order

1. **Schema (one migration, needs approval):** `integration_type_master` + `integration_field_definitions` rows for `klaviyo` / `webhook`; `integration_delivery_log`, `integration_outbox_cursor`, `integration_sync_jobs`; pg_cron purge for the log.
2. **`fn_integration_resolve_member_snapshot`** — extracted from the `bff_admin_get_member_360` building blocks; `fn_integration_lock_credential`.
3. **`integration/_shared`:** `event-keys.ts` (contract vocabulary), `outbox-read.ts` (lag window + cursor), `with-retry.ts` (in-process retry), `delivery-log.ts` (final outcome + circuit-break).
4. **Webhook lane:** `workers/integration-webhook-publisher.ts` + `deliver.ts` — prove with a request-bin URL saved through the existing Hub form (this also validates the field definitions).
5. **Klaviyo client:** `client.ts`, `profile-map.ts`, `event-map.ts`, `oauth-config.ts`.
6. **OAuth:** Edge start/callback + `_shared/integration-oauth/` + `bff_integration_klaviyo_get_connection` / `disconnect` — connect the QA account.
7. **`workers/integration-klaviyo-event-consumer.ts`** — real event → profile + metric in Klaviyo.
8. **`workers/integration-klaviyo-sync-worker.ts`** + `bff_integration_klaviyo_start_sync_all` (bulk import).
9. **Closeout:** `requirements/` domain doc (contract vocabulary, Rocket * properties, v1 metrics), `REGISTRY_SUPABASE` / `REGISTRY_RENDER`, `CHANGELOG`.

OAuth moves ahead of the event consumer because the consumer cannot be tested without a token.

---

## Success (QA Shopify merchant)

1. Connect OAuth → `connected = true`
2. Sync all → members with email in Klaviyo with Rocket * properties
3. Real points earn → balance updates + “Rocket Points Earned” on person
4. Member not in Klaviyo who then earns → profile created with full properties, then event
5. Disconnect → further writes stop

---

## Repos touched

| Repo | Changes |
|------|---------|
| `supabase-crm` | Migrations, RPCs, Edge functions, requirements doc |
| `crm-event-processors` | Webhook + Klaviyo workers, OAuth kit, adapters |
| `loyalty-admin` | UI (separate thread — calls BFF RPCs only) |

---

## References

- Existing outbox: `crm-event-processors/src/workers/outbox-publisher.ts`
- Notification event-key mapping: `supabase-crm/.cursor/deploy/inngest-event-router-serve/lib/notification-router.ts`
- Integration Hub: `integration_type_master`, `bff_get_integration_config`, `bff_upsert_integration_config`
- Thread decision: no Inngest on partner lane; no shared IntegrationPublisher engine; Klaviyo OAuth/sync/events as three entry points sharing one client.
- Klaviyo docs (revision 2026-01-15): Set up OAuth (PKCE, rotating refresh), Create Event (inline profile upsert, `unique_id`), Bulk Import Profiles (10k / 5 MB / `lists:write`), Guide to integrating a loyalty platform.
- Live precedents: `shopify_subscription_job_cursor`, `codes_import_jobs`, `chokepoint_outbox_cleanup` (7-day post-publish retention), `bff_upsert_integration_config` (latest-row-per-`service_name` merge into `credentials`).

---

## Review adjustments (2026-09-06)

What changed from the first draft and why — so the next thread does not re-litigate.

| Draft | Now | Why |
|-------|-----|-----|
| Failed deliveries hold the cursor back | Cursor always advances; retry is **in-process only** (3 attempts, `Retry-After` honoured); one final log row per delivery; no scheduled retry | One scalar cursor per lane means a held id blocks every merchant. In-process retry covers 429s and blips — the common failures — with no schedule state. Scheduled retry from the log was considered and deferred to v2 (owner decision 2026-09-06). |
| Plain `id > last_id` read | `+ created_at <= now() - 10 s` lag window; cursor-age warning | Sequence ids commit out of order; outbox rows are purged 7 days after publish. |
| `fn_integration_klaviyo_resolve_profile` + `fn_integration_webhook_resolve_event` | One `fn_integration_resolve_member_snapshot` | L1 shared-abstraction rule; both lanes need the same member state; `bff_admin_get_member_360` already computes it. |
| Profile upsert then metric (two calls) | One `POST /api/events/` with profile inline, `unique_id` = outbox id | Klaviyo Create Event upserts the profile; halves calls and gives retry idempotency. |
| Sync all = per-profile upsert loop | Bulk Import Profiles jobs | Klaviyo's recommended backfill path; 10k profiles per request. |
| `sync_new_members`, `subscribed_events` as columns; 6 Klaviyo BFF RPCs | Field definitions on the integration type; 3 BFF RPCs | The Hub RPCs already merge typed fields into `credentials`; no new columns, no bespoke setters. |
| "New webhook URL = new row" | One endpoint per merchant in v1 | `bff_upsert_integration_config` updates the latest row per `service_name`; multi-row would silently break the Hub form. |
| OAuth kit "and/or" across two runtimes | Edge half (start/callback/store) + Render half (read/refresh under row lock) | PKCE `code_verifier` must be parked between start and callback; rotating refresh tokens need a single locked refresh path. |
| Sample metrics on connect | Cut | No create-metric API; synthetic events pollute a real profile. |
| `integration_sync_job` | `integration_sync_jobs`; workers under `src/workers/` with per-lane env flags | Match live table naming and the `crm-event-processors` layout. |
