# AMP — RisingWave State Engine Setup

## Role in the Architecture

RisingWave is the **real-time state engine** for the AMP AI decisioning layer. Its job is to maintain a continuously updated "living state" for every user — aggregated stats and recent event history — so that when the AI decision engine is triggered, it can retrieve full user context in milliseconds without querying the transactional Supabase database.

```
Supabase PostgreSQL
        │
        │  WAL (Write-Ahead Log)
        ▼
Debezium CDC Connector (Confluent)
        │
        │  Kafka topics (Debezium JSON format)
        ▼
Confluent Kafka  ──────────────────────────────────────────────────────┐
  crm.public.wallet_ledger                                             │
  crm.public.purchase_ledger                                           │
  crm.public.tier_change_ledger                                        │
  amp_raw_events                                                       │
        │                                                              │
        │  RisingWave pulls (consumer group: rw-consumer-*)            │
        ▼                                                              │
RisingWave Cloud (ap-southeast-1)                                      │
  wallet_events TABLE ──► unified_event_stream ──► event_chronology    │
  purchase_events TABLE ──►                    ──► user_stats          │
                                               ──► user_chronology     │
        │                                                              │
        │  SELECT * FROM user_stats WHERE user_id = $1                 │
        │  SELECT * FROM user_chronology WHERE user_id = $1            │
        ▼                                                              │
amp-decision-engine (Supabase Edge Function)                           │
        │                                                              │
        │  Builds AI prompt with user context                          │
        ▼                                                              │
Groq / Llama 4 Maverick                                                │
        │                                                              │
        │  Returns decision JSON                                       │
        ▼                                                              │
inngest-serve (Supabase Edge Function)  ◄──────────────────────────────┘
  Injects agent.* variables into workflow context
  Routes workflow: action != "no_action" → true handle
```

---

## How RisingWave Connects to Kafka

RisingWave acts as a **Kafka consumer** — it pulls data from Confluent rather than Confluent pushing to it. Each `CREATE TABLE` statement in RisingWave registers a new consumer that subscribes to a Kafka topic and ingests messages continuously.

**Connection details:**
| Property | Value |
|----------|-------|
| Connector | `kafka` |
| Bootstrap server | `pkc-ox31np.ap-southeast-7.aws.confluent.cloud:9092` |
| Security | `SASL_SSL` / `PLAIN` |
| API Key | `HPOXXGZ3OXIYNTB7` |
| Format | `FORMAT DEBEZIUM ENCODE JSON` |
| Startup mode | `earliest` (backfills from Kafka retention) |

**Confluent ACLs required** (set on API key `HPOXXGZ3OXIYNTB7`):

| Resource | Pattern | Operation |
|----------|---------|-----------|
| Cluster | — | DESCRIBE / ALLOW |
| Topic | `crm.` (PREFIXED) | READ / ALLOW |
| Topic | `crm.` (PREFIXED) | DESCRIBE / ALLOW |
| Topic | `amp_raw_events` (LITERAL) | READ / ALLOW |
| Consumer group | `rw-consumer` (PREFIXED) | READ / ALLOW |

**Why Debezium format?**
Debezium CDC messages carry `before`/`after` payloads and an `op` field (`c`=create, `u`=update, `d`=delete). With `FORMAT DEBEZIUM`, RisingWave parses this envelope internally and maintains the table as a live snapshot — inserts add rows, updates modify in-place, deletes remove rows. Since `wallet_ledger` is append-only, it simply grows continuously.

---

## How RisingWave Connects to amp-decision-engine

The edge function connects to RisingWave using the **PostgreSQL wire protocol** — RisingWave is Postgres-compatible on port 4566.

**Supabase secrets set on `amp-decision-engine`:**
| Secret | Value |
|--------|-------|
| `RISINGWAVE_HOST` | `rwc-g1ji1dlhdmfj39rjvfv1u1v961-my-project.prod-aws-apse1-eks-a.risingwave.cloud` |
| `RISINGWAVE_PORT` | `4566` |
| `RISINGWAVE_USER` | `databaseuser` |
| `RISINGWAVE_PASSWORD` | (set) |
| `RISINGWAVE_DB` | `dev` |

The edge function runs two queries per AI decision call:
```sql
SELECT * FROM user_stats WHERE user_id = $1
SELECT * FROM user_chronology WHERE user_id = $1
```
Both return sub-10ms because RisingWave keeps these as pre-computed materialized views in memory — no aggregation happens at query time.

---

## View Architecture

```
wallet_events (CDC TABLE)      purchase_events (CDC TABLE)
       │                               │
       └──────────────┬────────────────┘
                      ▼
           unified_event_stream (MV)
           Normalizes: purchase / currency_earned / currency_spent
                      │
          ┌───────────┴───────────┐
          ▼                       ▼
   event_chronology (MV)    user_stats (MV)
   Last 20 events/user      Aggregates per user
   ranked by timestamp       (totals, balance, LTV)
          │
          ▼
   user_chronology (MV)
   One row per user
   history: JSONB array
```

---

## SQL — Final Working Version

### Section 1: CDC Tables

```sql
CREATE TABLE IF NOT EXISTS wallet_events (
    id               VARCHAR PRIMARY KEY,
    user_id          VARCHAR,
    merchant_id      VARCHAR,
    currency         VARCHAR,
    transaction_type VARCHAR,
    amount           INT,
    balance_before   INT,
    balance_after    INT,
    source_type      VARCHAR,
    source_id        VARCHAR,
    component        VARCHAR,
    created_at       TIMESTAMPTZ
) WITH (
    connector                    = 'kafka',
    topic                        = 'crm.public.wallet_ledger',
    properties.bootstrap.server  = 'pkc-ox31np.ap-southeast-7.aws.confluent.cloud:9092',
    properties.security.protocol = 'SASL_SSL',
    properties.sasl.mechanism    = 'PLAIN',
    properties.sasl.username     = 'HPOXXGZ3OXIYNTB7',
    properties.sasl.password     = 'cfltiEqWH661Q6TTJC8TpHlQYSZw9NdZtMWjHcw0xRsnEki5INx+Y8J4z5HNPJrg',
    scan.startup.mode            = 'earliest'
) FORMAT DEBEZIUM ENCODE JSON;

CREATE TABLE IF NOT EXISTS purchase_events (
    id                  VARCHAR PRIMARY KEY,
    user_id             VARCHAR,
    merchant_id         VARCHAR,
    transaction_number  VARCHAR,
    transaction_date    TIMESTAMPTZ,
    total_amount        DECIMAL,
    final_amount        DECIMAL,
    status              VARCHAR,
    store_id            VARCHAR,
    created_at          TIMESTAMPTZ
) WITH (
    connector                    = 'kafka',
    topic                        = 'crm.public.purchase_ledger',
    properties.bootstrap.server  = 'pkc-ox31np.ap-southeast-7.aws.confluent.cloud:9092',
    properties.security.protocol = 'SASL_SSL',
    properties.sasl.mechanism    = 'PLAIN',
    properties.sasl.username     = 'HPOXXGZ3OXIYNTB7',
    properties.sasl.password     = 'cfltiEqWH661Q6TTJC8TpHlQYSZw9NdZtMWjHcw0xRsnEki5INx+Y8J4z5HNPJrg',
    scan.startup.mode            = 'earliest'
) FORMAT DEBEZIUM ENCODE JSON;
```

**Key syntax lessons:**
- `CREATE TABLE` not `CREATE SOURCE` for Debezium format
- No `INCLUDE KEY` / `rw_key` — Debezium format forbids extra columns
- All IDs as `VARCHAR` — UUID type not supported in RisingWave
- Enum columns (currency, transaction_type, status, etc.) → `VARCHAR`

---

### Section 2: Unified Event Stream

```sql
CREATE MATERIALIZED VIEW IF NOT EXISTS unified_event_stream AS

    SELECT
        user_id, merchant_id,
        'purchase' AS event_type,
        id AS event_id,
        transaction_date AS event_timestamp,
        JSONB_BUILD_OBJECT(
            'final_amount', final_amount, 'total_amount', total_amount,
            'store_id', store_id, 'transaction_number', transaction_number,
            'status', status
        ) AS event_data
    FROM purchase_events
    WHERE status = 'completed' AND user_id IS NOT NULL

    UNION ALL

    SELECT
        user_id, merchant_id,
        'currency_earned' AS event_type,
        id AS event_id, created_at AS event_timestamp,
        JSONB_BUILD_OBJECT(
            'currency', currency, 'amount', amount,
            'source_type', source_type, 'component', component,
            'balance_after', balance_after
        ) AS event_data
    FROM wallet_events
    WHERE transaction_type = 'earn' AND user_id IS NOT NULL

    UNION ALL

    SELECT
        user_id, merchant_id,
        'currency_spent' AS event_type,
        id AS event_id, created_at AS event_timestamp,
        JSONB_BUILD_OBJECT(
            'currency', currency, 'amount', amount,
            'source_type', source_type, 'component', component,
            'balance_after', balance_after
        ) AS event_data
    FROM wallet_events
    WHERE transaction_type IN ('burn', 'redeem', 'expire') AND user_id IS NOT NULL;
```

---

### Section 3: Event Chronology

```sql
CREATE MATERIALIZED VIEW IF NOT EXISTS event_chronology AS
SELECT user_id, merchant_id, event_type, event_id, event_timestamp, event_data, event_rank
FROM (
    SELECT
        user_id, merchant_id, event_type, event_id, event_timestamp, event_data,
        ROW_NUMBER() OVER (
            PARTITION BY user_id, merchant_id
            ORDER BY event_timestamp DESC
        ) AS event_rank
    FROM unified_event_stream
) ranked
WHERE event_rank <= 20;
```

**Key lesson:** `QUALIFY` clause not supported — use subquery with `WHERE` on the window function result.

---

### Section 4: User Stats

```sql
CREATE MATERIALIZED VIEW IF NOT EXISTS user_stats AS
SELECT
    user_id,
    merchant_id,
    COUNT(*) FILTER (WHERE event_type = 'purchase') AS total_purchases,
    COALESCE(SUM((event_data->>'final_amount')::NUMERIC) FILTER (WHERE event_type = 'purchase'), 0) AS lifetime_value,
    MAX(event_timestamp) FILTER (WHERE event_type = 'purchase') AS last_purchase_at,
    COALESCE(AVG((event_data->>'final_amount')::NUMERIC) FILTER (WHERE event_type = 'purchase'), 0) AS avg_purchase_value,
    COALESCE(SUM((event_data->>'amount')::INT) FILTER (WHERE event_type = 'currency_earned'), 0) AS total_points_earned,
    COALESCE(SUM((event_data->>'amount')::INT) FILTER (WHERE event_type = 'currency_spent'), 0) AS total_points_spent,
    COALESCE(MAX((event_data->>'balance_after')::INT) FILTER (WHERE event_type IN ('currency_earned', 'currency_spent')), 0) AS current_balance,
    MAX(event_timestamp) AS last_activity_at
FROM unified_event_stream
GROUP BY user_id, merchant_id;
```

**Key lesson:** `NOW()` is not allowed in SELECT for streaming queries — only in WHERE/HAVING/ON/FROM. `days_since_last_purchase`, `purchases_last_30_days`, and `churn_risk` were removed. The AI reasons from `last_purchase_at` directly.

---

### Section 5: User Chronology

```sql
CREATE MATERIALIZED VIEW IF NOT EXISTS user_chronology AS
SELECT
    user_id,
    merchant_id,
    JSONB_AGG(
        JSONB_BUILD_OBJECT(
            'type',      event_type,
            'timestamp', event_timestamp,
            'data',      event_data
        ) ORDER BY event_timestamp DESC
    ) AS history,
    COUNT(*) AS event_count,
    MAX(event_timestamp) AS latest_event_at
FROM event_chronology
GROUP BY user_id, merchant_id;
```

This is the view consumed most heavily by the AI. The edge function does:
```typescript
userChronology?.history?.slice(0, 10)
```
Each element in `history` is `{ type, timestamp, data }` — the AI uses this to understand the sequence of user behaviour before making a decision.

---

## What's Next (Gaps vs. Full Vision)

| Gap | Current State | Full Vision |
|-----|--------------|-------------|
| Assets | 10 hardcoded items in edge function code | Assets table in RisingWave/Supabase with vector embeddings + semantic search |
| Tool calling | AI gets flat prompt, picks from list | AI invokes `search_assets()` tool, iterates with results |
| Tier events | `tier_change_ledger` topic exists but no RisingWave source yet | Add `tier_events` CDC table + `tier_changed` event type |
| ML scores | Not ingested | Churn/propensity scores from warehouse streamed via `amp_raw_events` |
| Contact centre | Not connected | Support ticket events via `amp_raw_events` topic |
