# CRM Event-Driven Architecture

## Overview

**Live path (2026-07+):** chokepoint writers → `chokepoint_event_outbox` → **OutboxPublisher** (Render `crm-event-processors`, Inngest mode) → **Inngest** → **`inngest-event-router-serve`** (domain routers) → downstream workflows (`inngest-currency-serve`, notification engine, etc.). `KAFKA_CONSUMERS_ENABLED=false` for these domains.

**Historical path (below):** CDC → Kafka → `crm-event-processors` consumers. Kept for reference during decommission; do not treat as the live purchase/currency/tier/mission/notification pipeline.

See also `requirements/Inngest_Primer.md` (event vs function vs serve) and `requirements/architecture/event-chokepoints.md`.

---

## Live architecture (chokepoint outbox → Inngest)

```
chokepoint_post_*  (same DB transaction as ledger write)
        │
        ├─► ledger table
        └─► chokepoint_event_outbox  (topic: crm.events.*)
                │
                ▼
        OutboxPublisher (Render crm-event-processors)
                │  POST batches of up to 50 events/request (API chunking — NOT rate limiting)
                ▼
        Inngest  (crm/<domain>.event)
                │  registry from deploy sync: event name → function id → serve URL
                ▼
        inngest-event-router-serve  (many *-router functions; fan-out)
                │
                ├─► currency-*-router  → currency/award  → inngest-currency-serve
                ├─► tier-*-router      → process_tier_event
                ├─► mission-*-router   → mission/evaluate
                ├─► notification-*-router → processNotification (see Notification_Service.md)
                ├─► amp-*-router       → amp-dispatch-realtime-event
                └─► expiry-reminder-*  → clock scan (NOT outbox; see Notification_Service.md §Reminders)
```

### OutboxPublisher vs throttling

| Layer | Role |
|---|---|
| **OutboxPublisher** | Reliable, **fast** drain of `chokepoint_event_outbox`. Batches of 50 = Inngest API payload chunking. Loops immediately after a full batch. **Not** downstream rate limiting. |
| **Inngest function `concurrency`** | **Actual backpressure** on each router/workflow. Excess work queues in Inngest. |

Per-router concurrency caps on `inngest-event-router-serve` (representative):

| Router group | Inngest concurrency |
|---|---|
| `currency-*-router` | 10 |
| `tier-*-router` | 10 global + **1 per `user_id`** |
| `mission-*-router` | 5 |
| `outcome-*-router` | 3 |
| `notification-*-router` | 5 (per router id) |
| `amp-*-router` | 10 global + **5 per `merchant_id`** (`amp-user-router` also throttles 60 batches/min per merchant) |
| `expiry-reminder-merchant` | **1 per `merchant_id`**, 5 global |

**Idempotency** (separate from concurrency): deterministic Inngest event ids from outbox row id; per-router `idempotency` keys (e.g. `purchase_id:event`).

### One purchase example

`crm/purchase.event` invokes **multiple routers in parallel** (currency, tier, mission, notification, AMP, …). Each router is a separate Inngest function on the same serve URL. Currency may emit a **new** event `currency/award`, which Inngest routes to `inngest-currency-serve` (second hop).

---

## Architecture Components (historical — CDC / Kafka)

```
┌─────────────────────────────────────────────────────────────────────┐
│                         Supabase PostgreSQL                          │
│  Tables: purchase_ledger, wallet_ledger, referral_ledger, etc.     │
└────────────────────────┬────────────────────────────────────────────┘
                         │
                         │ (1) PostgreSQL Replication Slot
                         │     pg_replication_slots
                         │
                         ▼
┌─────────────────────────────────────────────────────────────────────┐
│              Confluent CDC Connector (crm-cdc-source)               │
│  Type: PostgreSQL CDC Source V2 (Debezium)                          │
│  - Monitors replication slot: crm_cdc_slot                          │
│  - Reads from publication: crm_cdc_publication                      │
│  - Snapshot mode: when_needed (recover from WAL loss)               │
└────────────────────────┬────────────────────────────────────────────┘
                         │
                         │ (2) Publishes Debezium events
                         │
                         ▼
┌─────────────────────────────────────────────────────────────────────┐
│                      Confluent Kafka Cluster                         │
│  Topics:                                                             │
│  - crm.public.purchase_ledger                                       │
│  - crm.public.wallet_ledger                                         │
│  - crm.public.form_submissions                                      │
│  - crm.public.referral_ledger                                       │
│  - crm.public.mission_claims                                        │
│  - crm.public.codes                                                 │
└────────────────────────┬────────────────────────────────────────────┘
                         │
                         │ (3) Consumers subscribe to topics
                         │
                         ▼
┌─────────────────────────────────────────────────────────────────────┐
│        Render Background Worker: crm-event-processors               │
│  Consumer Group: crm-event-processors                                │
│                                                                      │
│  ┌─────────────────────────────────────────────────────────────┐   │
│  │  CurrencyConsumer (crm-event-processors-currency)           │   │
│  │  - Subscribes: purchase_ledger                              │   │
│  │  - Concurrency: 5 parallel processes (eachBatch + p-limit)  │   │
│  │  - Deduplication: Redis (5-min window)                      │   │
│  │  - Output: Publishes to Inngest for delayed awards          │   │
│  └─────────────────────────────────────────────────────────────┘   │
│                                                                      │
│  ┌─────────────────────────────────────────────────────────────┐   │
│  │  TierConsumer (crm-event-processors-tier)                   │   │
│  │  - Subscribes: purchase_ledger, wallet_ledger               │   │
│  │  - Concurrency: 3 parallel processes (eachBatch + p-limit)  │   │
│  │  - Deduplication: Redis (5-min window)                      │   │
│  │  - Output: Direct tier upgrade or Inngest for delayed       │   │
│  └─────────────────────────────────────────────────────────────┘   │
│                                                                      │
│  ┌─────────────────────────────────────────────────────────────┐   │
│  │  MissionConsumer (crm-event-processors-mission)             │   │
│  │  - Subscribes: purchase_ledger, wallet_ledger,              │   │
│  │    form_submissions                                         │   │
│  │  - Evaluates mission progress and completion                │   │
│  │  - Output: Publishes mission evaluation to Inngest          │   │
│  └─────────────────────────────────────────────────────────────┘   │
│                                                                      │
│  ┌─────────────────────────────────────────────────────────────┐   │
│  │  AmpConsumer (crm-event-processors-amp)                     │   │
│  │  - Subscribes: purchase_ledger, wallet_ledger,              │   │
│  │    form_submissions, amp_workflow_log                       │   │
│  │  - Dispatches matching workflow triggers                    │   │
│  │  - Output: POST dispatch-workflow-trigger → Inngest AMP     │   │
│  └─────────────────────────────────────────────────────────────┘   │
│                                                                      │
│  (Additional consumers: RewardConsumer, MarketplaceConsumer)        │
└─────────────────────────┬───────────────────────────────────────────┘
                          │
                          │ (4) Publishes events
                          │
                          ▼
┌─────────────────────────────────────────────────────────────────────┐
│                      Inngest (Workflow Engine)                       │
│  Handles:                                                            │
│  - Delayed currency awards (scheduled/rolling days)                 │
│  - Delayed tier upgrades (start of month, etc.)                     │
│  - Cancellation on refund (cancelOn events)                         │
│  - Durable execution & retry logic                                  │
└─────────────────────────────────────────────────────────────────────┘
```

---

## How CDC Connector Works (crm-cdc-source)

### 1. **PostgreSQL Replication Setup**

The CDC connector relies on PostgreSQL's logical replication:

```sql
-- Publication (defines which tables to track, with row filters)
-- Row filters added April 2026 for migration safety — skip_cdc=true rows
-- never enter the replication stream.
CREATE PUBLICATION crm_cdc_publication 
FOR TABLE 
  public.purchase_ledger WHERE (skip_cdc IS NOT TRUE),
  public.wallet_ledger WHERE (skip_cdc IS NOT TRUE),
  public.tier_change_ledger WHERE (skip_cdc IS NOT TRUE),
  public.form_submissions WHERE (skip_cdc IS NOT TRUE),
  public.cdc_heartbeat;

-- Replication Slot (tracks position in WAL log)
-- Created automatically by the connector
SELECT * FROM pg_replication_slots WHERE slot_name = 'crm_cdc_slot';
```

**Key Concepts:**
- **Publication**: Defines which tables/operations (INSERT/UPDATE/DELETE) to capture. Supports row filters (PG 15+) to exclude rows matching a condition.
- **Row Filter (`skip_cdc`)**: All CDC-monitored tables have a `skip_cdc boolean NOT NULL DEFAULT false` column. Rows with `skip_cdc = true` are excluded at the WAL level — zero Kafka events. Used for data migration and historical imports.
- **Replication Slot**: Tracks the LSN (Log Sequence Number) position in the Write-Ahead Log (WAL)
- **WAL (Write-Ahead Log)**: PostgreSQL's transaction log - contains all database changes

### 2. **Debezium CDC Process**

The Confluent CDC connector is built on Debezium, which:

1. **Connects to PostgreSQL** via replication protocol
2. **Reads from replication slot** starting at the last committed LSN
3. **Parses WAL events** into structured change events
4. **Publishes to Kafka** with Debezium format:

```json
{
  "op": "c",  // c=create, u=update, d=delete
  "before": null,  // Previous row state (for updates/deletes)
  "after": {   // New row state
    "id": "123e4567-e89b-12d3-a456-426614174000",
    "user_id": "user_123",
    "merchant_id": "merchant_456",
    "final_amount": 100.00,
    "status": "completed",
    "earn_currency": true,
    "created_at": "2026-02-01T09:30:00Z"
  },
  "source": {
    "lsn": 123456789,  // Log Sequence Number
    "txId": 98765
  },
  "ts_ms": 1706777400000
}
```

### 3. **Configuration**

```json
{
  "name": "crm-cdc-source",
  "connector.class": "PostgresCdcSourceV2",
  "database.hostname": "db.wkevmsedchftztoolkmi.supabase.co",
  "database.port": "5432",
  "database.dbname": "postgres",
  "database.user": "postgres",
  "database.password": "********",
  
  "slot.name": "crm_cdc_slot",
  "publication.name": "crm_cdc_publication",
  "table.include.list": "public.purchase_ledger, public.wallet_ledger, public.tier_change_ledger, public.form_submissions, public.cdc_heartbeat",
  
  "snapshot.mode": "when_needed",  // CRITICAL: Allows recovery from WAL loss
  "topic.prefix": "crm",           // Creates topics: crm.public.purchase_ledger
  
  "kafka.api.key": "HHYCUOC5MCWE5NP4",
  "kafka.api.secret": "********",
  "tasks.max": "1"
}
```

**Important Settings:**
- `snapshot.mode: when_needed` - If the LSN is no longer available (WAL purged), the connector takes a fresh snapshot
- `snapshot.mode: never` - Fails if LSN is lost (caused our original issue)

---

## Render Consumer (crm-event-processors)

### Architecture

The consumer service runs as a **Render Background Worker** (Node.js):

**Repository:** `Rocket-CRM/crm-event-processors`  
**Service:** `srv-d56v5pogjchc7399dfqg` on Render

### Consumer Topic Map

| Consumer | Topics | Output |
|----------|--------|--------|
| CurrencyConsumer | `crm.public.purchase_ledger` | Publishes `currency/award` events |
| TierConsumer | `crm.public.purchase_ledger`, `crm.public.wallet_ledger` | Direct tier processing or `tier/upgrade` events |
| MissionConsumer | `crm.public.purchase_ledger`, `crm.public.wallet_ledger`, `crm.public.form_submissions` | Publishes `mission/evaluate` events |
| AmpConsumer | `crm.public.purchase_ledger`, `crm.public.wallet_ledger`, `crm.public.form_submissions`, `crm.public.amp_workflow_log` | Calls `dispatch-workflow-trigger`, which emits `amp/workflow.trigger` |

`form_submissions` events are used for form/survey completion behavior, including hidden system workflows such as "complete survey, get currency".

### AMP Workflow Executor

Supabase Edge Function: `inngest-amp-serve`

The executor handles Inngest event `amp/workflow.trigger`.

Current workflow tables:
- `workflow_master`
- `workflow_node`
- `workflow_edge`
- `workflow_log`

Do not use old `amp_workflow*` table names. The live database does not expose compatibility views for those names.

For AMP wallet actions, the executor substitutes `{{trigger.*}}` and `{{user.*}}` templates in action config before calling `fn_execute_amp_action`. This supports survey reward dedup keys:
- `survey_reward:{{trigger.form_id}}:{{user.id}}`
- `survey_reward:{{trigger.form_id}}:{{trigger.record_id}}:{{user.id}}`

### Key Features

#### 1. **Batch + Parallel Processing**

Using KafkaJS's `eachBatch` with `p-limit` for controlled concurrency:

```typescript
// CurrencyConsumer example
await this.consumer.run({
  partitionsConsumedConcurrently: 1,  // Process 1 partition at a time
  eachBatch: async ({ batch, resolveOffset, heartbeat, isRunning, isStale }) => {
    // Process messages in parallel with concurrency limit (5)
    const tasks = batch.messages.map((message) =>
      this.limit(async () => {
        // Parse Debezium message
        const debezium = parseDebeziumMessage(message.value);
        
        // Process currency award
        await this.processCurrencyAward(...);
        
        // Mark offset as processed
        resolveOffset(message.offset);
        await heartbeat();  // Prevent rebalancing
      })
    );
    
    await Promise.all(tasks);
  },
});
```

**Performance:**
- **Sequential (old):** 5-10 messages/sec
- **Batch + Parallel (new):** 30-40 messages/sec (**6-8x faster**)

#### 2. **Deduplication**

Redis-based deduplication (5-minute window) prevents duplicate processing:

```typescript
const dedupKey = currencyDedupKey('purchase', purchaseId);
const duplicate = await isDuplicate(dedupKey, 300); // 300 seconds

if (duplicate) {
  console.log('Duplicate detected, skipping');
  return;
}
```

#### 3. **Event Loop Keep-Alive**

Critical fix to prevent Node.js from exiting:

```typescript
// src/index.ts
async function main() {
  // Start all consumers
  await consumers.currency.start();
  await consumers.tier.start();
  // ...
  
  // CRITICAL: Keep process alive - consumers run indefinitely
  await new Promise(() => {}); // Never resolves
}
```

Without this, Node.js exits after `main()` completes, causing premature `SIGTERM`.

---

## The Rebalancing Issue & Root Cause

### Timeline of Events

#### **Phase 1: Initial Symptoms** (Jan 30-31)
- ❌ Render logs showed continuous `ERROR: The group is rebalancing`
- ❌ Consumers kept rejoining, no messages processed
- ❌ Service received repeated `SIGTERM` signals and restarted

#### **Phase 2: Initial Debugging** (Jan 31)
Attempted fixes:
1. ✅ Added proper `heartbeat()` calls in consumer code
2. ✅ Fixed Node.js keep-alive logic (`await new Promise(() => {})`)
3. ✅ Changed consumer group ID to isolate testing
4. ❌ Rebalancing continued despite all fixes

#### **Phase 3: Discovery** (Feb 1)
- 🔍 Found Confluent CDC connector `crm-cdc-source` in **FAILED** state
- 🔍 Connector was crashing repeatedly with:
  - `ConnectException: Unable to obtain valid replication slot`
  - `DebeziumException: LSN no longer available`

#### **Phase 4: Root Cause Analysis** (Feb 1)

**The CDC connector was the culprit:**

1. **Stale Replication Slot**
   ```sql
   SELECT * FROM pg_replication_slots WHERE slot_name = 'crm_cdc_slot';
   -- Slot was "active: false" and "restart_lsn" was old
   ```

2. **LSN Expired**
   - Connector config had `snapshot.mode: never`
   - PostgreSQL had purged old WAL data (LSN no longer available)
   - Connector couldn't resume from its last offset

3. **Missing Kafka ACLs**
   - API key `HHYCUOC5MCWE5NP4` lacked topic-level permissions
   - Connector couldn't write to `crm.*` topics
   - Authorization errors caused repeated failures

**Why This Caused Rebalancing:**

When a Kafka connector crashes and restarts:
1. **Connector drops and recreates consumer connections**
2. **This triggers cluster-wide consumer group rebalancing**
3. **All consumers in the cluster (including crm-event-processors) must rejoin**
4. **Crashing every ~1 hour = continuous rebalancing**

### The Fix

#### **Step 1: Drop Stale Replication Slot**
```sql
SELECT pg_drop_replication_slot('crm_cdc_slot');
```

#### **Step 2: Delete Broken Connector**
```bash
# Via Confluent Cloud UI or API
DELETE /connectors/crm-cdc-source
```

#### **Step 3: Recreate Connector with Correct Config**
Key changes:
- ✅ `snapshot.mode: when_needed` (instead of `never`)
- ✅ Fresh start (no corrupted offset)
- ✅ Proper slot/publication names

#### **Step 4: Add Kafka ACLs**
In Confluent Cloud → API Keys → `HHYCUOC5MCWE5NP4`:
- ✅ Add `READ` permission for `crm.*` topics
- ✅ Add `WRITE` permission for `crm.*` topics
- ✅ Add `CREATE` permission for `crm.*` topics

#### **Step 5: Verify Connector Health**
```bash
# Connector status: RUNNING
# Task status: RUNNING
# No errors in logs
```

---

## Results After Fix

### Connector Health ✅
- **Status:** RUNNING
- **Tasks:** 1/1 running
- **Errors:** None
- **Messages flowing:** Yes (confirmed via consumer logs)

### Consumer Performance ✅
- **Rebalancing:** None (0 errors in 30+ minutes)
- **Throughput:** 30-40 messages/sec (6-8x improvement)
- **Stability:** No `SIGTERM` or premature exits
- **Backlog:** Catching up on ~10 hours of missed events

### System Architecture ✅
- **CDC → Kafka:** Working
- **Kafka → Consumers:** Working
- **Consumers → Inngest:** Working
- **End-to-end latency:** <2 seconds (real-time)

---

## Key Lessons Learned

### 1. **CDC Connector is Critical Infrastructure**
- A failing CDC connector impacts the entire event-driven system
- Monitor connector health separately from consumer health
- Connector crashes cause cluster-wide rebalancing

### 2. **Snapshot Mode Matters**
- `snapshot.mode: never` is fragile - fails on WAL purge
- `snapshot.mode: when_needed` is resilient - recovers automatically
- Always plan for WAL retention expiration

### 3. **Kafka ACLs Must Match Service Accounts**
- Topic-level ACLs are required even if organization-level roles exist
- Missing permissions cause silent authorization failures
- Always verify ACLs after connector creation

### 4. **Debugging Kafka Issues**
- Check connector health FIRST before debugging consumer code
- Use Confluent Cloud UI to inspect connector status and logs
- Rebalancing can be caused by upstream issues, not just consumer code

### 5. **Node.js Event Loop for Long-Running Processes**
- Must explicitly keep event loop alive: `await new Promise(() => {})`
- Without this, Node.js exits after `main()` completes
- Causes mysterious `SIGTERM` signals on Render

---

## Monitoring & Observability

### Key Metrics to Monitor

#### **CDC Connector**
- Connector status (RUNNING/FAILED)
- Task status (RUNNING/FAILED)
- Connector lag (time behind database)
- Replication slot active status

#### **Kafka Topics**
- Message throughput (messages/sec)
- Topic lag (unconsumed messages)
- Consumer group lag per partition

#### **Consumers (Render)**
- Processing throughput (messages/sec)
- Rebalancing frequency (should be 0)
- Error rate
- Deduplication hit rate

#### **PostgreSQL**
- Replication slot lag: `pg_replication_slots.restart_lsn`
- WAL disk usage: `pg_current_wal_lsn()` vs `restart_lsn`
- Active replication connections

### Alerting Rules

```yaml
alerts:
  - name: CDC Connector Down
    condition: connector.status != RUNNING
    severity: critical
    
  - name: Consumer Lag High
    condition: consumer.lag > 1000 messages
    severity: warning
    
  - name: Replication Slot Inactive
    condition: pg_replication_slots.active = false
    severity: critical
    
  - name: Consumer Rebalancing
    condition: consumer.rebalances > 0 in last 5 minutes
    severity: warning
```

---

## Future Improvements

### 1. **RisingWave Integration** (Planned)
- Use Kafka topics as source for real-time materialized views
- Provide AI agents with always-up-to-date context
- Enable real-time analytics dashboards

### 2. **Dead Letter Queue**
- Handle permanently failed messages
- Manual retry/inspection workflow

### 3. **Consumer Autoscaling**
- Scale consumers based on Kafka lag
- Render supports horizontal scaling

### 4. **Enhanced Observability**
- Datadog/Grafana dashboards
- Distributed tracing (OpenTelemetry)
- Kafka lag metrics in Prometheus

---

## Quick Reference

### Useful Commands

```sql
-- Check replication slots
SELECT * FROM pg_replication_slots;

-- Check WAL position
SELECT pg_current_wal_lsn();

-- Drop replication slot (if needed)
SELECT pg_drop_replication_slot('crm_cdc_slot');

-- Check publication
SELECT * FROM pg_publication WHERE pubname = 'crm_cdc_publication';
```

### Environment Variables (Render)

```bash
KAFKA_BOOTSTRAP_SERVERS=pkc-*.confluent.cloud:9092
KAFKA_API_KEY=***
KAFKA_API_SECRET=***

SUPABASE_URL=https://wkevmsedchftztoolkmi.supabase.co
SUPABASE_SERVICE_ROLE_KEY=***

REDIS_URL=rediss://***
CRM_CACHE_REDIS_URL=rediss://***

INNGEST_EVENT_KEY=***

CONSUMER_GROUP_ID=crm-event-processors
CURRENCY_CONCURRENCY=5
TIER_CONCURRENCY=3
```

### Useful Links

- **Render Service:** https://dashboard.render.com/worker/srv-d56v5pogjchc7399dfqg
- **Confluent Cloud:** https://confluent.cloud
- **GitHub Repo:** https://github.com/Rocket-CRM/crm-event-processors
- **Supabase Dashboard:** https://supabase.com/dashboard/project/wkevmsedchftztoolkmi

---

## Support & Troubleshooting

### Common Issues

#### Issue: "The group is rebalancing"
**Symptoms:** Continuous rebalancing errors in logs  
**Root Cause:** CDC connector crashing, network issues, or heartbeat timeouts  
**Fix:** Check CDC connector health first, then consumer heartbeat() calls

#### Issue: "Unable to obtain valid replication slot"
**Symptoms:** CDC connector fails on startup  
**Root Cause:** Stale or broken replication slot in PostgreSQL  
**Fix:** Drop and recreate the slot via connector recreation

#### Issue: "LSN no longer available"
**Symptoms:** CDC connector can't resume from last offset  
**Root Cause:** WAL retention expired, `snapshot.mode: never`  
**Fix:** Recreate connector with `snapshot.mode: when_needed`

#### Issue: Node.js process exits with SIGTERM
**Symptoms:** Render service exits every few minutes  
**Root Cause:** Missing event loop keep-alive (`await new Promise(() => {})`)  
**Fix:** Add infinite promise to keep event loop alive

---

**Last Updated:** Feb 1, 2026  
**Version:** 2.0 (Batch + Parallel Processing)
