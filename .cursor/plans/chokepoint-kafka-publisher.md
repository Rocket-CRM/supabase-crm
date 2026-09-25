# Chokepoint → Kafka publisher

**Status (2026-05-15 09:40 UTC+8):** Pipeline is **live in dual-run**. All 5 chokepoint topics are publishing, the OutboxPublisher worker is draining at sub-second latency, and all 5 consumers are reading both legacy CDC + new chokepoint topics with Redis dedup absorbing duplicates. **Step 11 decommission of the 4 CDC tables is gated on a 24h healthy soak** — earliest cut-over window opens 2026-05-16 09:30 UTC+8.

**Architecture:** silver tier (outbox table + custom KafkaJS worker on Render, no Debezium for the new path). Architecture choice driven by prior Debezium pain (transcript `d0b94926-01cb-456f-bc0c-d831110035a1`: 27 GB WAL slot bloat, "Unable to obtain valid replication slot" connector deaths, idle-in-transaction connections needing `kill-stuck-debezium` cron). Silver tier removes the logical replication slot entirely from the new pipeline, structurally immune to that failure mode.

**Scope:** all 4 existing chokepoints (`chokepoint_post_purchase_event`, `chokepoint_post_wallet_transaction`, `chokepoint_post_tier_change`, `chokepoint_post_user_event`) cut over from Debezium CDC to chokepoint→outbox→Kafka in one coordinated rollout. The DB infra is intentionally chokepoint-agnostic — one outbox table, one helper function, one worker, one cron — with topic routing decided per-event at emit time. `form_submissions` and the consumer-side `amp_workflow_log` stay on Debezium (no chokepoint exists for those domains yet).

---

## Timeline

| Date | Phase | What landed |
|---|---|---|
| 2026-05-13 | Phase A (purchase chokepoint) | `chokepoint_post_purchase_event` consolidated all writes to `purchase_ledger` + `purchase_items_ledger`. |
| 2026-05-13 | Phase B (per-item earning config) | `award_scope` + `allowed_item_statuses` columns + `calc_currency_for_purchase_item` function. |
| 2026-05-14 | Phase 1 (DB infra, additive) | `chokepoint_event_outbox` table + `fn_chokepoint_emit_event` helper + `chokepoint_outbox_cleanup` cron + `v_chokepoint_outbox_health` view. **No chokepoint behavior change.** |
| 2026-05-14 | Phase 1+B (consumer-side, drafted) | `outbox-publisher.ts` worker + dual-read in `currency`, `tier`, `mission`, `amp`, `outcome-attribution` consumers. All gated by `CHOKEPOINT_EVENTS_ENABLED=false` initially. |
| 2026-05-15 morning | Step 1-2 (Confluent) | 5 topics provisioned (6 partitions, 7d retention, gzip, delete cleanup). One `chokepoint-publisher` API key with WRITE+DESCRIBE on `crm.events.*` prefix. |
| 2026-05-15 morning | Step 3-6 (Render) | PR merged, env vars set, both flags flipped to `true`. Worker armed and idle (waiting on outbox emits). |
| 2026-05-15 ~09:00 | Step 7 (chokepoint emits) | 4 A5 migrations applied in order: A5a purchase, A5b wallet, A5c tier_change, A5d user. Each smoke-tested before moving to next. |
| 2026-05-15 ~09:20 | Step 8 (worker drain) | Synthetic outbox row drained in **235 ms** end-to-end (proves LISTEN/NOTIFY wired, not just polling fallback). |
| 2026-05-15 ~09:30 | Step 9 (dual-pipe correctness) | Synthetic create event with `skip_cdc=false` published 2 outbox rows (user + recursive tier_change) in 756 ms with no errors, no double-emit, no spurious workflow dispatch. |
| 2026-05-15 09:40 → 2026-05-16 09:40 | Step 10 (24h soak) | Passive observation against organic traffic. SLO gates listed below. |
| **2026-05-16 09:40+** | **Step 11 (decommission)** | **Single `ALTER PUBLICATION` drops 4 tables from `crm_cdc_publication`. Gated on Step 10 SLOs.** |

---

## Deployed architecture

### DB layer (`wkevmsedchftztoolkmi`)

```
┌─────────────────────────────────────────────────────────────────┐
│  4 chokepoint functions (single source of truth per domain)     │
│  - chokepoint_post_purchase_event       (12 event branches)     │
│  - chokepoint_post_wallet_transaction   (1 emit per call)       │
│  - chokepoint_post_tier_change          (1 emit per call)       │
│  - chokepoint_post_user_event           (4 branches, 3 emits)   │
└──────────────┬──────────────────────────────────────────────────┘
               │ each branch ends with:
               │   IF NOT v_skip_emit THEN
               │     PERFORM fn_chokepoint_emit_event(topic, key, payload);
               │   END IF;
               ▼
┌─────────────────────────────────────────────────────────────────┐
│  fn_chokepoint_emit_event(text, text, jsonb) → bigint           │
│  SECURITY DEFINER. Validates topic ~ '^crm\.events\.[a-z_]+$'.  │
│  INSERT INTO chokepoint_event_outbox + pg_notify(...).          │
└──────────────┬──────────────────────────────────────────────────┘
               ▼
┌─────────────────────────────────────────────────────────────────┐
│  public.chokepoint_event_outbox (single table for all 5 topics) │
│  id bigserial, topic, partition_key, payload jsonb, created_at, │
│  published_at, publish_attempts, last_error                     │
│  Partial indexes: (created_at) WHERE published_at IS NULL       │
│                   (published_at) WHERE published_at IS NOT NULL │
│  CHECK: topic ~ '^crm\.events\.[a-z_]+$'                        │
└──────────────┬──────────────────────────────────────────────────┘
               │ pg_notify('chokepoint_outbox_new', id::text)
               │   ↓ wakes the worker (sub-second)
               │ pg_cron 'chokepoint_outbox_cleanup' daily 03:00 UTC
               │   deletes published rows older than 7d
               ▼
```

### Render layer (`crm-event-processors`)

```
┌─────────────────────────────────────────────────────────────────┐
│  OutboxPublisher worker (src/workers/outbox-publisher.ts)       │
│  - LISTEN chokepoint_outbox_new + 1s polling fallback           │
│  - SELECT FOR UPDATE SKIP LOCKED ... LIMIT batch_size           │
│  - Routes by row's topic column → KafkaJS produce(acks=all)     │
│  - On success: UPDATE published_at = now(), publish_attempts++  │
│  - On failure: UPDATE last_error, publish_attempts++; retry up  │
│    to OUTBOX_PUBLISHER_MAX_ATTEMPTS                             │
│  - Uses dedicated Confluent API key (chokepoint-publisher),     │
│    distinct from the legacy consumer credentials                │
└──────────────┬──────────────────────────────────────────────────┘
               ▼
        Confluent Cloud (pkc-ox31np.ap-southeast-7.aws)
        ┌─────────────────────────────────────────────┐
        │  crm.events.purchase       (6 partitions)   │
        │  crm.events.purchase_item  (6 partitions)   │
        │  crm.events.wallet         (6 partitions)   │
        │  crm.events.tier_change    (6 partitions)   │
        │  crm.events.user           (6 partitions)   │
        │  All: 7d retention, gzip, delete cleanup    │
        └──────────────┬──────────────────────────────┘
                       ▼
┌─────────────────────────────────────────────────────────────────┐
│  5 consumers (all dual-reading legacy CDC + chokepoint topics): │
│  - CurrencyConsumer        ← purchase, purchase_item            │
│  - TierConsumer            ← purchase, wallet                   │
│  - MissionConsumer         ← purchase, wallet                   │
│  - AmpConsumer             ← purchase, purchase_item, wallet,   │
│                              tier_change, user                  │
│  - OutcomeAttribution      ← purchase, wallet                   │
│                                                                  │
│  Dedup keys 1:1 with legacy CDC paths so dual-run is absorbed   │
│  by Redis. Subscribed lines log chokepointEvents=true.          │
└─────────────────────────────────────────────────────────────────┘
```

`RewardConsumer` and `MarketplaceConsumer` are unchanged — they don't read any of the 4 chokepoint surfaces.

---

## Topic + partition map

| Topic | Partition key | Emitted by | Consumed by |
|---|---|---|---|
| `crm.events.purchase` | `purchase_id` | `chokepoint_post_purchase_event` | Currency, Tier, Mission, AMP, OutcomeAttribution |
| `crm.events.purchase_item` | `purchase_id` (parent + items co-partition) | `chokepoint_post_purchase_event` | Currency, AMP |
| `crm.events.wallet` | `user_id` | `chokepoint_post_wallet_transaction` | Tier, Mission, AMP, OutcomeAttribution |
| `crm.events.tier_change` | `user_id` | `chokepoint_post_tier_change` | AMP |
| `crm.events.user` | `user_id` | `chokepoint_post_user_event` | AMP |

All 5 topics: 6 partitions, 7-day retention, gzip compression, delete cleanup policy.

---

## Per-chokepoint emit specification

### `chokepoint_post_purchase_event` (12 branches)

| Event branch | Emits per call |
|---|---|
| `created` | 1× `crm.events.purchase` per inserted purchase + N× `crm.events.purchase_item` per inserted item |
| `updated` | 1× `crm.events.purchase` (only if `status` / `payment_status` / `*_amount` actually changed) |
| `completed` | 1× `crm.events.purchase` (only when row actually flipped) |
| `cancelled` | 1× `crm.events.purchase` (only when row actually flipped) |
| `refunded` | 1× `crm.events.purchase` for the original purchase status flip when fully refunded; the recursive `created` call for the debit row passes `_skip_emit=true` |
| `promo_applied` | 1× `crm.events.purchase` |
| `items_added` | N× `crm.events.purchase_item` per inserted item |
| `items_replaced` | N× `crm.events.purchase_item` per new item (no events for deleted items) |
| `item_quantity_completed` | K× `crm.events.purchase_item` only for items that flipped to `completed`; parent rollup emit fires via the recursive `completed` call |
| `item_completion_set` | K× `crm.events.purchase_item` only for items that flipped to `completed` on this call (forward only); parent rollup emit fires via the recursive `completed` call |
| `item_cancelled` | N× `crm.events.purchase_item` per item updated to `cancelled` |
| `item_refunded` | N× `crm.events.purchase_item` per item updated to `refunded` |

### `chokepoint_post_wallet_transaction` (points: 1 emit; tickets: N unit emits)

- **Points:** one `wallet_ledger` row → one `crm.events.wallet` emit at end of call (`amount = p_amount`).
- **Tickets:** `FOR 1..p_amount` inserts N ledger rows and emits **N** events inside the loop (`amount: 1`, plus `unit_index` / `unit_total` / `wallet_code`). Mission/tier/AMP sum per unit; LINE coalesce is in `notification-wallet-router` (skip `unit_index !== 1`, render `amount = unit_total`).
- Partition key `p_user_id` preserves per-user ordering.

### `chokepoint_post_tier_change` (1 emit per call)

The function inserts exactly one `tier_change_ledger` row per call → exactly one `crm.events.tier_change` emit at the end. Payload includes `skip_cdc` so AMP can reproduce the legacy `WHERE NOT skip_cdc` filter from the chokepoint side.

### `chokepoint_post_user_event` (3 emit sites covering 4 branches)

- `create` branch — dedicated emit before `RETURN`, with auto-tier-assigned `tier_id` snapshot.
- `hard_delete` branch — dedicated emit with `user_after = NULL` (row gone).
- `update` + `soft_delete` — shared trailing emit at the end, reading the post-mutation row. For `soft_delete` the snapshot reflects the auto-scrubbed PII (`firstname`/`lastname`/`email`/etc all NULL, `deleted_at` set). The original `p_event_type` is preserved in the payload's `event` field so consumers can distinguish.

All 4 branches gated on `COALESCE(p_metadata->>'_skip_emit','false') <> 'true'` so backfills and recursive calls don't double-emit.

---

## Payload contract

All payloads share the same outer envelope:

```jsonc
{
  "event":         "<verb>",                  // 'create', 'completed', 'tier_change', etc.
  "merchant_id":   "uuid",
  "occurred_at":   "2026-05-15T01:37:54Z",
  "source":        "chokepoint_post_<domain>_event",
  "skip_cdc":      false,                     // included in tier_change + user payloads for AMP filter parity
  // ...domain-specific fields below
}
```

### `crm.events.purchase` (and `.purchase_item`)

```jsonc
{
  "event":         "completed",
  "merchant_id":   "uuid",
  "purchase_id":   "uuid",
  "item_id":       "uuid",          // purchase_item topic only
  "user_id":       "uuid|null",     // pre-joined from purchase_ledger
  "earn_currency": true,            // pre-joined from purchase_ledger
  "status":        "completed",     // parent topic only
  "item_status":   "completed",     // item topic only
  "final_amount":  100,             // parent topic only
  "total_amount":  100,             // parent topic only
  "occurred_at":   "...",
  "source":        "chokepoint_post_purchase_event"
}
```

### `crm.events.wallet`

```jsonc
{
  "event":            "wallet_transaction",
  "merchant_id":      "uuid",
  "user_id":          "uuid",
  "wallet_ledger_id": "uuid",
  "currency":         "points",
  "component":        "base|adjustment|reversal|...",
  "transaction_type": "earn|burn|expire|...",
  "amount":           100,
  "source_type":      "purchase|manual|...",
  "source_id":        "uuid",
  "description":      "...",
  "target_entity_id": "uuid|null",
  "occurred_at":      "...",
  "source":           "chokepoint_post_wallet_transaction"
}
```

### `crm.events.tier_change`

```jsonc
{
  "event":                 "tier_change",
  "merchant_id":           "uuid",
  "user_id":               "uuid",
  "tier_change_ledger_id": "uuid",
  "from_tier_id":          "uuid|null",
  "to_tier_id":            "uuid|null",
  "change_type":           "initial|upgrade|downgrade|manual",
  "change_reason":         "...",
  "metadata":              { /* arbitrary */ },
  "skip_cdc":              false,    // AMP filters event with skip_cdc=true
  "occurred_at":           "...",
  "source":                "chokepoint_post_tier_change"
}
```

### `crm.events.user`

```jsonc
{
  "event":           "create|update|soft_delete|hard_delete",
  "user_event_type": "create|update|soft_delete|hard_delete",  // duplicate for filter convenience
  "merchant_id":     "uuid",
  "user_id":         "uuid",
  "changes":         { /* original p_changes from caller */ },
  "actor":           { "actor_id": "uuid|null" },
  "skip_cdc":        false,    // AMP fires only on event='create' AND skip_cdc=false
  "user_after":      { /* full user_accounts row snapshot, or null for hard_delete */ },
  "occurred_at":     "...",
  "source":          "chokepoint_post_user_event"
}
```

---

## Knobs (Render env vars on `crm-event-processors`)

```
KAFKA_OUTBOX_API_KEY              <secret>     # dedicated chokepoint-publisher key
KAFKA_OUTBOX_API_SECRET           <secret>     # dedicated chokepoint-publisher secret
SUPABASE_DB_DIRECT_URL            <secret>     # direct connection (NOT pooler) for LISTEN/NOTIFY
OUTBOX_PUBLISHER_BATCH_SIZE       500          # rows per drain cycle
OUTBOX_PUBLISHER_POLL_INTERVAL_MS 1000         # fallback when LISTEN misses
OUTBOX_PUBLISHER_MAX_ATTEMPTS     10           # before row is treated as poison
OUTBOX_PUBLISHER_WORK_POOL_MAX    4            # parallel publish workers
OUTBOX_PUBLISHER_ENABLED          true         # master kill switch for the worker
CHOKEPOINT_EVENTS_ENABLED         true         # master kill switch for consumer-side dual-read
```

Two-flag design intentional: `OUTBOX_PUBLISHER_ENABLED` controls whether the new pipeline publishes; `CHOKEPOINT_EVENTS_ENABLED` controls whether consumers act on it. Either can be flipped to `false` independently for emergency rollback without touching the other.

---

## Operational runbook

### Health snapshot (run any time)

```sql
SELECT * FROM public.v_chokepoint_outbox_health;
```

Per-topic + `__total__`. Healthy values: `unpublished_stale = 0`, `errored = 0`, `oldest_unpublished_age < 5s`, `max_attempts_unpublished IN (0, 1)`.

### Last 5 min per topic

```sql
SELECT topic,
       count(*) AS emitted,
       count(*) FILTER (WHERE published_at IS NOT NULL) AS published,
       count(*) FILTER (WHERE last_error IS NOT NULL) AS errored,
       round(avg(extract(epoch from (published_at - created_at)) * 1000)::numeric, 1) AS avg_lat_ms,
       max(now() - created_at) FILTER (WHERE published_at IS NULL) AS oldest_unpublished
  FROM public.chokepoint_event_outbox
 WHERE created_at > now() - interval '5 minutes'
 GROUP BY topic
 ORDER BY topic;
```

### Worst stuck rows (anything you should look at)

```sql
SELECT id, topic, partition_key, publish_attempts,
       left(last_error, 200) AS err, created_at, now() - created_at AS age
  FROM public.chokepoint_event_outbox
 WHERE published_at IS NULL AND created_at < now() - interval '5 minutes'
 ORDER BY id LIMIT 20;
```

### Rollback (per layer, independent)

| Failure | Action | Blast radius |
|---|---|---|
| Any A5 emit produces wrong payload | Roll back that specific A5 (function bodies captured pre-A5 in execution log; revert is one `CREATE OR REPLACE FUNCTION`) | Only that chokepoint stops emitting; other 3 chokepoints + worker + consumers unaffected |
| Worker crashes / can't publish | Set `OUTBOX_PUBLISHER_ENABLED=false`, restart Render | All 4 chokepoints still commit (atomicity at outbox INSERT preserved). Outbox grows; drain after fix. |
| Consumer breaks on chokepoint payload shape | Set `CHOKEPOINT_EVENTS_ENABLED=false`, restart | All consumers fall back to legacy CDC path. Old behavior fully restored. |
| Confluent down for one topic | KafkaJS retries; outbox queues for that topic; other 4 keep flowing | Per-topic transient backpressure |
| Wholesale rollback | Run Step 11 in reverse: `ALTER PUBLICATION crm_cdc_publication ADD TABLE ...` to restore CDC. Only relevant after Step 11 has fired. | Pre-Step-11 we just flip the two flags off. |

### `_skip_emit` escape hatch

All 4 chokepoints honor `COALESCE(p_metadata->>'_skip_emit','false') <> 'true'` (purchase uses `p_payload->>'_skip_emit'`). Pass `_skip_emit=true` from backfill scripts and recursive chokepoint-to-chokepoint calls to avoid double-emit. Already used by:

- `chokepoint_post_purchase_event` `refunded` branch (the recursive `created` call for the debit row sets it).
- Backfill scripts that need to populate ledger rows without re-firing AMP / Currency / Tier downstream.

---

## Step 10 SLO gate (24h soak, opens 2026-05-15 09:40 → closes 2026-05-16 09:40 UTC+8)

All conditions must hold for the full 24h before Step 11 fires:

- [ ] `unpublished_stale = 0` for every topic continuously
- [ ] `errored = 0` for every topic
- [ ] `oldest_unpublished_age < 5 seconds` typical
- [ ] `max_attempts_unpublished` in `{0, 1}`
- [ ] Confluent topic message rate ≈ chokepoint call rate per topic
- [ ] Redis dedup hit rate roughly **doubles** for each `(source_table, id)` pair (proves both pipelines fire and dedup absorbs)
- [ ] No double-awards in `wallet_ledger` (currency dedup absorbed)
- [ ] No duplicate AMP dispatches in `workflow_log` / `inngest_workflow_log` (AMP dedup absorbed)
- [ ] No duplicate tier evaluations
- [ ] No `OutboxPublisher` exceptions in Render logs over the full window

---

## Step 11 — Decommission CDC for the 4 cut-over tables

After Step 10 SLOs all green, single migration drops all 4 tables from the publication:

```sql
ALTER PUBLICATION crm_cdc_publication
  DROP TABLE purchase_ledger,
             wallet_ledger,
             tier_change_ledger,
             user_accounts;
```

After this:

- Debezium stops emitting to `crm.public.purchase_ledger`, `wallet_ledger`, `tier_change_ledger`, `user_accounts`.
- Consumers' fallback subscriptions on these topics stop receiving messages (the consumers stay subscribed; topics just go silent).
- `crm.events.*` becomes the sole source of truth for these 4 entity types.
- WAL retention pressure on `crm_cdc_slot` drops materially (these are 4 of the highest-volume tables).

**Optional follow-up PR (not urgent):** remove the legacy `crm.public.*` topics from each consumer's `subscribe()` topic list and remove the legacy switch branches. Keeps the codebase tidy; can ship anytime in the week after Step 11.

---

## Out of scope (intentional deferrals)

- **`form_submissions` and `amp_workflow_log`** stay on Debezium — they don't have a chokepoint today. Future work: build `chokepoint_post_form_submission_event` and `chokepoint_post_amp_workflow_event`, repeat this same pattern, then decommission their CDC paths.
- **Schema Registry for the new topics** — using raw JSON for now. Revisit if multi-language consumers appear.
- **Per-event-type topic splitting** — one event-name-per-topic is overkill; the `event` field discriminates within each topic.
- **`items_deleted` message variant for `items_replaced`** — neither current consumer cares; emitted only for new items, not for deleted ones.

---

## Reference: every change shipped under this initiative

### DB migrations (Phase 1, 2026-05-14)

- `chokepoint_event_outbox_table_v1` — outbox table + 2 partial indexes + topic CHECK
- `chokepoint_emit_event_helper_v1` — `fn_chokepoint_emit_event` SECURITY DEFINER helper
- `chokepoint_outbox_cleanup_cron_v1` — pg_cron `chokepoint_outbox_cleanup` daily 03:00 UTC, 7d retention
- `chokepoint_outbox_health_view_v1` — `v_chokepoint_outbox_health` per-topic + total

### DB migrations (Phase 2, 2026-05-15)

- `chokepoint_post_purchase_event_emit_v1` — emit calls into all 12 event branches
- `chokepoint_post_wallet_transaction_emit_v1` — single emit at end of function
- `chokepoint_post_tier_change_emit_v1` — single emit at end of function
- `chokepoint_post_user_event_emit_v1` — 3 emit sites covering all 4 branches

### Render-side (`Rocket-CRM/crm-event-processors`, 2026-05-14 → 2026-05-15)

- `src/workers/outbox-publisher.ts` — chokepoint-agnostic worker (LISTEN + poll + SKIP LOCKED + KafkaJS)
- `src/config.ts` — 5 topic constants + `outboxPublisher` env block + `flags.chokepointEventsEnabled`
- `src/index.ts` — gated `OutboxPublisher` instantiation + shutdown wiring
- `src/consumers/currency-consumer.ts` — dual-read of `crm.events.purchase` + `crm.events.purchase_item`
- `src/consumers/tier-consumer.ts` — dual-read of `crm.events.purchase` + `crm.events.wallet`
- `src/consumers/mission-consumer.ts` — dual-read with `extractChokepointSourceInfo` helper
- `src/consumers/amp-consumer.ts` — dual-read of all 5 chokepoint topics; per-topic dispatch with legacy-matching dedup keys
- `src/consumers/outcome-attribution-consumer.ts` — dual-read of `crm.events.purchase` + `crm.events.wallet`
- `package.json` — added `pg` + `@types/pg` for the worker's Postgres LISTEN
- `README.md` — Consumers table reflects all 7 consumers with legacy + chokepoint topic columns

### Confluent Cloud

- 5 topics created on `pkc-ox31np.ap-southeast-7.aws.confluent.cloud`
- 1 service account `chokepoint-publisher` + 1 API key with WRITE+DESCRIBE on `crm.events.*` prefix

### Workspace docs

- `requirements/REGISTRY_SUPABASE.md` — "Chokepoint Outbox" section added
- `requirements/REGISTRY_RENDER.md` — `chokepoint_outbox_cleanup` cron + worker line
- `requirements/CHANGELOG.md` — entries under 2026-05-14 (infra + drafted code) and 2026-05-15 (Phase 2 production activation)
- `.cursor/plans/chokepoint-kafka-publisher-morning-checklist.md` — full execution log of the 2026-05-15 cut-over sequence

Project ref: `wkevmsedchftztoolkmi`. All DB work via Supabase MCP.
