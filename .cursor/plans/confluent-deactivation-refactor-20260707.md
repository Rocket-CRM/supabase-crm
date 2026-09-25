# Confluent Deactivation — Impact, Architecture, De-Kafka Plan

**Incident:** Confluent Cloud account deactivated (unrecoverable) ~2026-07-07 07:34 UTC. All Kafka topics on `pkc-ox31np.ap-southeast-7.aws.confluent.cloud` are gone.

**Decision:** Do not replace Confluent with another broker. Move each pipeline to Inngest (request-shaped work + chokepoint fan-out routers).

**Last updated:** 2026-07-08 (AMP routers shipped — v3)

---

## Status summary (2026-07-08)

| Pipeline | Replacement | Status |
|---|---|---|
| Reward redemptions | `crm-api` → Inngest → `inngest-reward-serve` | **LIVE** |
| Chokepoint → currency | OutboxPublisher → Inngest → `inngest-event-router-serve` (currency routers) → `currency/award` → `inngest-currency-serve` | **LIVE** |
| Chokepoint → tier / mission / outcome / notification | Same OutboxPublisher → `inngest-event-router-serve` v2 (14 functions) | **LIVE** — outbox 0 unpublished on all six topics |
| Chokepoint → AMP realtime | `inngest-event-router-serve` v3 — 5 AMP routers → `amp-dispatch-realtime-event` | **LIVE** (2026-07-08) — app re-synced, 19 functions registered |
| Marketplace webhooks | `MARKETPLACE_INGEST_MODE=inngest` on edge fns → `inngest-marketplace-serve` | **LIVE** — see §9 orphan-shop note |
| RisingWave / CDC consumers | Retire | **P3** — dead since 2026-06-04 |
| Cleanup (Kafka env vars, SDK bumps, retire dead consumers) | — | **OPEN** |

**Inngest apps to know:**

| App | Sync URL |
|---|---|
| `crm-reward-service` | `https://wkevmsedchftztoolkmi.supabase.co/functions/v1/inngest-reward-serve` |
| `crm-event-router` | `https://wkevmsedchftztoolkmi.supabase.co/functions/v1/inngest-event-router-serve` |
| marketplace (existing) | `https://wkevmsedchftztoolkmi.supabase.co/functions/v1/inngest-marketplace-serve` |

**Render env (`crm-event-processors`):**

- `OUTBOX_PUBLISHER_ENABLED=true`
- `OUTBOX_PUBLISH_TOPICS=crm.events.purchase,crm.events.purchase_item,crm.events.wallet,crm.events.tier_change,crm.events.user,crm.events.redemption`
- `KAFKA_CONSUMERS_ENABLED=false` (default)

---

## 1. Affected areas at incident (2026-07-07)

| # | Area | Was | Now (2026-07-08) |
|---|---|---|---|
| 1 | Reward redemptions | DOWN (Kafka dead) | **Inngest** — `inngest-reward-serve` |
| 2 | Chokepoint fan-out | Backing up in outbox | **Inngest routers** — outbox drained, 0 unpublished |
| 3 | Marketplace webhooks | Kafka publish failing | **Inngest** — `MARKETPLACE_INGEST_MODE=inngest` |
| 4 | RisingWave | Dead since 2026-06-04 | Unchanged — retire docs |
| 5 | Legacy CDC consumers | Dead since 2026-06-04 | Unchanged — code retained as reference |

Volume reality check: redemption flash 8.7K/hr and chokepoint ~6K events/week were well within Inngest capacity. Kafka was never load-constrained.

---

## 2. Redemption architecture (LIVE)

```
FE ──POST /redemptions──▶ crm-api (Render)
                             │  POST inn.gs/e/{INNGEST_EVENT_KEY}  reward/redemption.requested
                             ▼
                        Inngest Cloud
                             ▼
              inngest-reward-serve (edge fn, SDK 3.54.0)
                             │  redeem_reward_with_points (p_event_id idempotency)
                             ▼
              reward_redemptions_ledger ──▶ Realtime postgres_changes ──▶ FE (success)
                             ├─ business rejection ──▶ broadcast redemption_failed on redemption:{user_id}
                             ├─ chokepoint ──▶ chokepoint_event_outbox (crm.events.redemption)
                             └─ Shopify discount sync (fire-and-forget)
```

FE contract unchanged: submit → `postgres_changes` INSERT (success) + broadcast `redemption:{user_id}` (failure).

---

## 3. Chokepoint fan-out architecture (LIVE)

**Decision (2026-07-07):** outbox → Inngest fan-out, not per-consumer Postgres cursors. Outbox is the durability seam; Inngest owns retries/isolation/dashboard.

```
chokepoint fns → fn_chokepoint_emit_event → chokepoint_event_outbox   (UNCHANGED)
                                              │  LISTEN/NOTIFY + poll
                                              ▼
                        OutboxPublisher (crm-event-processors, Inngest mode)
                        topic crm.events.<domain> → event crm/<domain>.event
                        allowlist: OUTBOX_PUBLISH_TOPICS
                                              ▼
                                        Inngest Cloud
                                              ▼
                        inngest-event-router-serve (app crm-event-router, 14 functions)
        ┌──────────┬──────────┬──────────┬──────────────┬────────────────┐
        ▼          ▼          ▼          ▼              ▼
     currency    tier      mission   outcome-attrib   notification
     routers     routers   routers      router          routers (LINE)
        │
        └─ currency/award → inngest-currency-serve (UNCHANGED)
```

**Key rules:** keep outbox (never `fn_emit_inngest_event` for chokepoint events); tier uses per-user concurrency key `user_id` limit 1; idempotency expressions replace Redis dedup keys.

**Routers shipped (v2, 2026-07-07):**

| Router | Events in | Downstream |
|---|---|---|
| `currency-purchase-router` / `currency-purchase-item-router` | `crm/purchase.event`, `crm/purchase_item.event` | `currency/award` |
| `tier-purchase-router` / `tier-wallet-router` | purchase, wallet (earn only) | `process_tier_event` RPC |
| `mission-purchase-router` / `mission-wallet-router` | purchase (completed), wallet (earn) | `mission/evaluate` per active mission |
| `outcome-purchase-router` / `outcome-wallet-router` | purchase (completed), wallet (earn/redeem) | `amp_outcome_attribution` insert |
| `notification-*-router` (6) | purchase, purchase_item, wallet, tier_change, user, redemption | `fn_resolve_notification_for_event` → LINE push → `notification_log` |
| `amp-{purchase,purchase-item,wallet,tier,user}-router` (5, v3 2026-07-08) | purchase (completed), purchase_item (completed), wallet (earn), tier_change (!skip_cdc), user (create, !skip_cdc) | `amp-dispatch-realtime-event` → `amp/workflow.trigger` → `inngest-amp-serve` |

**AMP router burst handling (v3):** `amp-user-router` uses `batchEvents` (100/batch, 5s timeout, keyed `merchant_id` — one batch per merchant), `throttle` 60 batch-starts/min/merchant (lossless FIFO), per-merchant concurrency 5. Batching is incompatible with Inngest `idempotency`, so signup dedup is in-handler (per-batch `user_id` set) + `inngest-amp-serve` re-enrollment gate. Other 4 AMP routers use idempotency keys matching legacy Redis dedup (`purchase_id:status`, `item_id:item_status`, `wallet_ledger_id`, `tier_change_ledger_id`). Trigger matching itself is cheap: `amp-dispatch-realtime-event` calls `fn_get_active_triggers_cached` (per-merchant 600s cache).

**NOT ported (CDC-only, still dead):** form_submissions (`form_completed` triggers, 7 active), amp_workflow_log `add_to_audience` (audience-add triggers), referral, email outcome events — no chokepoint topic; need `fn_chokepoint_emit_event` calls at their write sites + outbox topic allowlisting.

**Verified 2026-07-07:** `v_chokepoint_outbox_health` → 0 unpublished on all published topics; `notification_log` resumed (~211 sent in 15 min during backlog drain).

---

## 4. Marketplace architecture (LIVE)

Edge webhooks already existed — cutover was one Supabase secret:

- `MARKETPLACE_INGEST_MODE=inngest` (added 2026-07-07)
- `INNGEST_EVENT_KEY` — already present project-wide (confirmed via `inngest-marketplace-serve` `has_event_key: true` + Vault `inngest_event_key`)

```
TikTok/Shopee/Lazada ──POST──▶ webhook-marketplace-{platform} (edge fn)
                                    │ normalize + filter UNPAID
                                    │ POST inn.gs/e/{INNGEST_EVENT_KEY}  marketplace/order-received
                                    ▼
                               Inngest Cloud
                                    ▼
                          inngest-marketplace-serve (batching, rate limit, concurrency)
```

No Render service or new endpoint needed. `MarketplaceConsumer` on Render is dead (`KAFKA_CONSUMERS_ENABLED=false`).

**Verified 2026-07-07:** Inngest publish responses `{"ids":[...],"status":200}` on filtered events; Lazada 100% publish success in soak window.

### Orphan TikTok shop (action item)

Shop `7494921743206681041` drives ~80% of TikTok webhook volume (~31K hits / 24h, ~9K distinct orders) but has **no row in `merchant_credentials`** and `get_shop_credentials` fails. TikTok sends legitimately (`source-service: oec.open.gw_event_consumer`, `x-tt-signature`). Webhooks publish to Inngest successfully; **`inngest-marketplace-serve` cannot process** without credentials.

Likely cause: TikTok Open Platform uses one app-level webhook URL — all authorized shops hit the same endpoint; this shop was never onboarded in CRM (or credentials removed).

**Options:** onboard shop under correct merchant in `merchant_credentials`, disconnect in TikTok Seller Center, or add edge-fn guard to skip publish for unknown `shop_id` (saves Inngest volume).

Active TikTok shops in CRM: Munasoul `7495900767072258467`, Chy `7495786747810777646`, Biowoman `7494547804992932567`, Double A `7494918523226393149`, Sleepingclound `7496054762932308455`, New CRM `7495709562522995045`.

---

## 5. Completed work log

### Redemption (Phase 1)
- [x] `inngest-reward-serve` deployed (SDK 3.54.0, `verify_jwt=false`)
- [x] `crm-api` switched from KafkaJS to Inngest event send
- [x] Inngest app `crm-reward-service` synced

### Currency / OutboxPublisher (Phase 2)
- [x] PR #6 `outbox-publisher-inngest` merged — OutboxPublisher → Inngest; `KAFKA_CONSUMERS_ENABLED=false`
- [x] `inngest-event-router-serve` v1 — currency routers
- [x] Outbox backlog reset + drain verified

### Tier / Mission / Outcome / Notification (Phase 3)
- [x] `inngest-event-router-serve` v2 — 14 functions, multi-file `lib/*` layout
- [x] Inngest `crm-event-router` re-synced
- [x] `OUTBOX_PUBLISH_TOPICS` extended on Render; outbox 0 unpublished

### Marketplace (Phase 4)
- [x] `MARKETPLACE_INGEST_MODE=inngest` on Supabase edge secrets
- [x] `INNGEST_EVENT_KEY` confirmed present
- [x] Webhook → Inngest publish verified in `custom_webhook_events`

### Docs
- [x] `REGISTRY_RENDER.md`, `CHANGELOG.md` (2026-07-07 entries)

---

## 6. Open / cleanup

| Item | Owner | Notes |
|---|---|---|
| ~~AMP router~~ | ~~Agent~~ | **DONE 2026-07-08** — v3 shipped, 5 AMP routers live (see §3). |
| **AMP CDC-only trigger sources** | Agent | form_submissions (7 active `form_completed` triggers) + amp_workflow_log `add_to_audience` workflows silently not firing since 2026-06-04. Needs chokepoint emits at write sites + new outbox topics. Prioritize if merchants rely on form/audience triggers. |
| **Orphan TikTok shop** | Ops | Identify merchant for `7494921743206681041` or block unknown shops at edge fn. |
| **Strip Kafka env** | Ops | Remove `KAFKA_*` from Render (`crm-api`, `crm-event-processors`) and Supabase edge secrets after soak. |
| **Remove dead Render consumers** | Agent | AMP router shipped — `crm-event-processors` can now shrink to OutboxPublisher only. |
| **`inngest-amp-serve` executor caps** | Agent | Rides with SDK bump: add per-merchant `concurrency` key + optional throttle on message-send steps (LINE rate limits) so 10K matched runs drain gently. |
| **Inngest SDK bump** | Agent | Remaining `inngest-*-serve` on SDK 3.22.0 → ≥3.54.0 (CVE-2026-42047 blocks re-sync). Reward + event-router already on 3.54.0. Bundle with executor caps row above. |
| **RisingWave retirement** | Ops | Confirm `amp-decision-engine` no longer queries RisingWave; retire docs. |
| **Notification stale guard** | Optional | Max-age filter on notification routers if backlog drain sent late LINE messages (211 sent during drain — monitor merchant complaints). |

---

## 7. Reference — crm-api Inngest publish (redemption)

```ts
const INNGEST_EVENT_KEY = process.env.INNGEST_EVENT_KEY || '';

async function publishRedemptionEvent(payload: {
  event_id: string; user_id: string; reward_id: string;
  quantity: number; merchant_id: string; timestamp: string;
}): Promise<void> {
  const res = await fetch(`https://inn.gs/e/${INNGEST_EVENT_KEY}`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ name: 'reward/redemption.requested', data: payload }),
  });
  if (!res.ok) throw new Error(`inngest_publish_failed: ${res.status} ${await res.text()}`);
}
```

---

## 8. Reference — OutboxPublisher Inngest mode

- Topic → event: `crm.events.purchase` → `crm/purchase.event` (`topicToEventName` in `crm-event-processors/src/workers/outbox-publisher.ts`)
- Event id: `chokepoint-outbox-<row-id>` (deterministic)
- Batch: 50 events per Inngest POST
- Allowlist: `OUTBOX_PUBLISH_TOPICS` env (comma-separated); topics not listed stay unpublished safely
- `src/clients/inngest.ts` → `publishToInngest(name, data)` helper

---

## 9. Decision record — why Inngest over outbox cursors

The outbox table is the durable log in both designs. Inngest fan-out was chosen because: (1) consumers were already thin routers feeding Inngest workflows; (2) volume (~7K/week) is far below custom-queue justification; (3) one transport/dashboard for redemption, marketplace, currency, missions, AMP, bulk import, export; (4) outbox remains the seam to swap transports later without touching chokepoints.

Cursor option would only win at ~100× volume or zero external-service dependency requirement.
