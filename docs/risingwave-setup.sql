-- ============================================================
-- RisingWave Setup SQL for AMP Decision Engine
-- Project: CRM (wkevmsedchftztoolkmi)
-- Last updated: 2026-02-22
-- Status: PRODUCTION — all statements verified working
--
-- Lessons learned during setup:
--   - Use CREATE TABLE (not CREATE SOURCE) for FORMAT DEBEZIUM
--   - No INCLUDE KEY / rw_key — FORMAT DEBEZIUM forbids extra columns
--   - UUID type not supported — use VARCHAR for all IDs
--   - QUALIFY clause not supported — use subquery + WHERE instead
--   - NOW() not allowed in SELECT for streaming — remove from aggregates
-- ============================================================


-- ============================================================
-- SECTION 1: CDC TABLES
-- RisingWave connects to Confluent Kafka as a consumer.
-- Each CREATE TABLE subscribes to one Kafka topic.
-- FORMAT DEBEZIUM: RisingWave parses the Debezium CDC envelope
-- internally — columns map directly to the source table schema.
-- ============================================================

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


-- ============================================================
-- SECTION 2: UNIFIED EVENT STREAM
-- Merges wallet + purchase CDC into one normalized event stream.
-- Columns accessed directly (no after->>'field' syntax needed).
-- ============================================================

CREATE MATERIALIZED VIEW IF NOT EXISTS unified_event_stream AS

    SELECT
        user_id,
        merchant_id,
        'purchase'          AS event_type,
        id                  AS event_id,
        transaction_date    AS event_timestamp,
        JSONB_BUILD_OBJECT(
            'final_amount',       final_amount,
            'total_amount',       total_amount,
            'store_id',           store_id,
            'transaction_number', transaction_number,
            'status',             status
        )                   AS event_data
    FROM purchase_events
    WHERE status = 'completed'
      AND user_id IS NOT NULL

    UNION ALL

    SELECT
        user_id,
        merchant_id,
        'currency_earned'   AS event_type,
        id                  AS event_id,
        created_at          AS event_timestamp,
        JSONB_BUILD_OBJECT(
            'currency',      currency,
            'amount',        amount,
            'source_type',   source_type,
            'component',     component,
            'balance_after', balance_after
        )                   AS event_data
    FROM wallet_events
    WHERE transaction_type = 'earn'
      AND user_id IS NOT NULL

    UNION ALL

    SELECT
        user_id,
        merchant_id,
        'currency_spent'    AS event_type,
        id                  AS event_id,
        created_at          AS event_timestamp,
        JSONB_BUILD_OBJECT(
            'currency',      currency,
            'amount',        amount,
            'source_type',   source_type,
            'component',     component,
            'balance_after', balance_after
        )                   AS event_data
    FROM wallet_events
    WHERE transaction_type IN ('burn', 'redeem', 'expire')
      AND user_id IS NOT NULL;


-- ============================================================
-- SECTION 3: EVENT CHRONOLOGY (intermediate)
-- Last 20 events per user, ranked newest-first.
-- Uses subquery + WHERE instead of QUALIFY (not supported).
-- ============================================================

CREATE MATERIALIZED VIEW IF NOT EXISTS event_chronology AS
SELECT user_id, merchant_id, event_type, event_id, event_timestamp, event_data, event_rank
FROM (
    SELECT
        user_id,
        merchant_id,
        event_type,
        event_id,
        event_timestamp,
        event_data,
        ROW_NUMBER() OVER (
            PARTITION BY user_id, merchant_id
            ORDER BY event_timestamp DESC
        ) AS event_rank
    FROM unified_event_stream
) ranked
WHERE event_rank <= 20;


-- ============================================================
-- SECTION 4: USER STATS
-- Name: user_stats — matches amp-decision-engine query exactly.
-- Edge fn: SELECT * FROM user_stats WHERE user_id = $1
-- Note: NOW() not allowed in SELECT for streaming queries.
-- days_since_last_purchase and churn_risk omitted — AI reasons
-- from last_purchase_at timestamp directly.
-- ============================================================

CREATE MATERIALIZED VIEW IF NOT EXISTS user_stats AS
SELECT
    user_id,
    merchant_id,
    COUNT(*) FILTER (WHERE event_type = 'purchase')
        AS total_purchases,
    COALESCE(SUM((event_data->>'final_amount')::NUMERIC)
        FILTER (WHERE event_type = 'purchase'), 0)
        AS lifetime_value,
    MAX(event_timestamp) FILTER (WHERE event_type = 'purchase')
        AS last_purchase_at,
    COALESCE(AVG((event_data->>'final_amount')::NUMERIC)
        FILTER (WHERE event_type = 'purchase'), 0)
        AS avg_purchase_value,
    COALESCE(SUM((event_data->>'amount')::INT)
        FILTER (WHERE event_type = 'currency_earned'), 0)
        AS total_points_earned,
    COALESCE(SUM((event_data->>'amount')::INT)
        FILTER (WHERE event_type = 'currency_spent'), 0)
        AS total_points_spent,
    COALESCE(MAX((event_data->>'balance_after')::INT)
        FILTER (WHERE event_type IN ('currency_earned', 'currency_spent')), 0)
        AS current_balance,
    MAX(event_timestamp)
        AS last_activity_at
FROM unified_event_stream
GROUP BY user_id, merchant_id;


-- ============================================================
-- SECTION 5: USER CHRONOLOGY
-- Name: user_chronology — matches amp-decision-engine query exactly.
-- Edge fn: SELECT * FROM user_chronology WHERE user_id = $1
-- Edge fn accesses: userChronology?.history (JSONB array, newest first)
-- Returns ONE row per user.
-- ============================================================

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
    )                    AS history,
    COUNT(*)             AS event_count,
    MAX(event_timestamp) AS latest_event_at
FROM event_chronology
GROUP BY user_id, merchant_id;


-- ============================================================
-- SECTION 6: AMP WORKFLOW LOG CDC TABLE
-- Subscribes to crm.public.amp_workflow_log Kafka topic.
-- Prerequisite: add public.amp_workflow_log to Debezium connector table.include.list
-- ============================================================

CREATE TABLE IF NOT EXISTS amp_workflow_log_events (
    id                  VARCHAR PRIMARY KEY,
    merchant_id         VARCHAR,
    workflow_id         VARCHAR,
    user_id             VARCHAR,
    inngest_run_id      VARCHAR,
    event_type          VARCHAR,
    node_id             VARCHAR,
    node_type           VARCHAR,
    action_type         VARCHAR,
    status              VARCHAR,
    cost                DECIMAL,
    action_channel      VARCHAR,
    created_at          TIMESTAMPTZ
) WITH (
    connector                    = 'kafka',
    topic                        = 'crm.public.amp_workflow_log',
    properties.bootstrap.server  = 'pkc-ox31np.ap-southeast-7.aws.confluent.cloud:9092',
    properties.security.protocol = 'SASL_SSL',
    properties.sasl.mechanism    = 'PLAIN',
    properties.sasl.username     = 'HPOXXGZ3OXIYNTB7',
    properties.sasl.password     = 'cfltiEqWH661Q6TTJC8TpHlQYSZw9NdZtMWjHcw0xRsnEki5INx+Y8J4z5HNPJrg',
    scan.startup.mode            = 'earliest'
) FORMAT DEBEZIUM ENCODE JSON;


-- ============================================================
-- SECTION 7: USER AGENT USAGE
-- Per-user per-workflow action/cost/message counts.
-- Used by MCP constraint check instead of direct DB queries.
-- Note: time-window filtering done at read time by MCP since
-- NOW() not allowed in streaming materialized views.
-- ============================================================

CREATE MATERIALIZED VIEW IF NOT EXISTS user_agent_usage AS
SELECT
    user_id,
    workflow_id,
    COUNT(*)                                                AS total_actions,
    COALESCE(SUM(cost), 0)                                  AS total_cost,
    COUNT(*) FILTER (WHERE action_type IN ('send_line_message', 'send_sms'))
                                                            AS total_messages,
    MAX(created_at)                                         AS last_action_at
FROM amp_workflow_log_events
WHERE event_type = 'action_executed'
  AND action_type IS NOT NULL
GROUP BY user_id, workflow_id;


-- ============================================================
-- SECTION 8: AGENT CAMPAIGN STATE
-- Per-workflow aggregate: users entered, actioned, cost, converted.
-- Used by MCP agent performance resource.
-- ============================================================

CREATE MATERIALIZED VIEW IF NOT EXISTS agent_campaign_state AS
SELECT
    workflow_id,
    COUNT(DISTINCT user_id) FILTER (WHERE event_type = 'execution_started')
                                                            AS users_entered,
    COUNT(DISTINCT user_id) FILTER (WHERE event_type = 'action_executed')
                                                            AS users_actioned,
    COUNT(*) FILTER (WHERE event_type = 'action_executed')  AS total_actions,
    COALESCE(SUM(cost) FILTER (WHERE event_type = 'action_executed'), 0)
                                                            AS total_cost,
    COUNT(DISTINCT user_id) FILTER (WHERE event_type = 'outcome_achieved')
                                                            AS users_converted
FROM amp_workflow_log_events
GROUP BY workflow_id;


-- ============================================================
-- SECTION 9: AMP ACTION STREAM
-- AMP actions as events for user chronology.
-- AI sees its own past actions in user history.
-- To fully integrate, update event_chronology to UNION this
-- with unified_event_stream, or query separately.
-- ============================================================

CREATE MATERIALIZED VIEW IF NOT EXISTS amp_action_stream AS
SELECT
    user_id,
    merchant_id,
    'amp_action'        AS event_type,
    id                  AS event_id,
    created_at          AS event_timestamp,
    JSONB_BUILD_OBJECT(
        'action_type',    action_type,
        'channel',        action_channel,
        'cost',           cost,
        'workflow_id',    workflow_id,
        'status',         status
    )                   AS event_data
FROM amp_workflow_log_events
WHERE event_type = 'action_executed'
  AND action_type IS NOT NULL
  AND user_id IS NOT NULL;


-- ============================================================
-- VERIFICATION
-- ============================================================
-- SELECT * FROM rw_tables;
-- SELECT name FROM rw_materialized_views;
-- SELECT * FROM user_stats LIMIT 5;
-- SELECT user_id, event_count, latest_event_at FROM user_chronology LIMIT 5;
-- SELECT * FROM user_agent_usage LIMIT 5;
-- SELECT * FROM agent_campaign_state LIMIT 5;
-- SELECT * FROM amp_action_stream LIMIT 5;
