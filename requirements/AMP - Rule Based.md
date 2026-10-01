# AMP — Rule Based

> **Post-Confluent (2026-07-07):** Live event path is `chokepoint_event_outbox` → OutboxPublisher → `inngest-event-router-serve` (`amp-*-router`) → `amp-dispatch-realtime-event` → `inngest-amp-serve`. Debezium/Kafka/`AmpConsumer` sections below are **historical** unless noted. Canonical workflow tables are `workflow_master` / `workflow_node` / `workflow_edge` / `workflow_trigger` / `workflow_log` (not `amp_workflow*`).

## What This Document Covers

The rule-based automation layer of AMP: workflows, audiences, conditions, actions, messaging, and the event pipeline. For AI-powered agent decisioning, see `AMP - AI Decisioning.md`. For the Redis cache layer on config reads, see `AMP - Cache Layer.md`.

---

## Business Requirements

### Overview

The AMP module enables merchants to create automated marketing journeys that respond to customer behavior in real-time. Instead of manually sending campaigns or relying on batch processes, merchants can design visual workflows that automatically guide customers through personalized experiences based on their actions. Audiences provide reusable segments that can trigger or filter these workflows.

### Business Goals

1. **Reduce Manual Marketing Work** - Automate repetitive marketing tasks like welcome sequences, abandoned cart reminders, and re-engagement campaigns
2. **Improve Customer Experience** - Deliver timely, relevant messages based on actual customer behavior rather than generic batch sends
3. **Increase Conversion Rates** - Guide customers through optimized journeys with conditional logic and personalized content
4. **Enable Non-Technical Users** - Provide a visual drag-and-drop builder that marketing teams can use without developer support
5. **Measure Marketing Effectiveness** - Track funnel performance, message delivery rates, and customer journey analytics

### Use Cases

| Use Case | Trigger | Workflow Example |
|----------|---------|------------------|
| Welcome Series | New user signup | Send welcome email → Wait 2 days → Check if purchased → Send discount or tips |
| Abandoned Cart | Cart created, no purchase | Wait 1 hour → Send reminder → Wait 1 day → Send discount offer |
| Tier Upgrade Celebration | User reaches new tier | Send congratulations → Award bonus points → Send exclusive offer |
| Re-engagement | No activity for 30 days | Send "we miss you" email → Wait 3 days → Send special offer |
| Post-Purchase Follow-up | Purchase completed | Send receipt → Wait 7 days → Request review → Award points for review |
| Birthday Campaign | Birthday date match | Send birthday greeting → Award birthday points → Send birthday offer |

---

## Key Concepts

### Workflow

A workflow is an automated sequence of steps that executes when triggered by a customer action. Each workflow has:
- **Entry point** - The event that starts the workflow (e.g., purchase, signup)
- **Nodes** - Individual steps in the workflow (conditions, messages, waits, actions)
- **Edges** - Connections between nodes defining the flow path
- **Exit conditions** - How/when a customer leaves the workflow

### Node Types

| Node Type | Purpose | Examples |
|-----------|---------|----------|
| **Condition** | Branch based on customer data or behavior. The first condition node (no incoming edges) is the workflow entry point. | Check tier level, Check purchase history, Check tag |
| **Message** | Send communication to customer | Email, SMS, LINE, Push notification |
| **Wait** | Pause execution for a duration | Wait 3 days, Wait until specific time |
| **Action** | Perform CRM action | Award points, Assign tag, Update field |
| **API Call** | Call external service | Webhook, Third-party integration |
| **Agent** | AI-powered decision (see `AMP - AI Decisioning.md`) | Dynamic content, Smart recommendations |

> **Note:** The `trigger` node type has been removed (v60). Previously, workflows had a visual-only trigger node as the entry point. The executor now uses the first node with no incoming edges as the entry point — typically the first condition node. The `workflow_trigger` registry (which controls which CDC events start the workflow) is auto-derived from condition nodes' `collection` fields, not from a trigger node.

### Execution

An execution is a single customer's journey through a workflow:
- Each execution has a unique `inngest_run_id`
- A customer can have multiple executions of the same workflow (if allowed)
- Executions can be: `active` (in progress), `completed`, `failed`, or `exited`

### Event Sourcing

Execution tracking uses event sourcing pattern:
- Every status change is an INSERT (not UPDATE)
- Enables cumulative funnel analytics
- Full audit trail of customer journey
- Extensible without schema changes

### Message Delivery Funnel

For message nodes, we track delivery progression:

```
executed    → Inngest processed the node
    ↓
sent        → Message provider accepted (API returned 200)
    ↓
delivered   → Provider confirmed delivery (webhook)
    ↓
opened      → Customer opened/clicked (webhook, future feature)
```

Each status is a separate log entry, enabling funnel analysis:
- "1000 emails executed, 980 sent, 850 delivered, 320 opened"

> **Scope decision (2026-07-05):** per-message `delivered`/`opened` via LINE webhooks was descoped — LINE provides only channel-level aggregated delivery/read stats, no per-message webhook. Message engagement is instead tracked via per-recipient tracked links (see §Engagement Tracking below).

### Engagement Tracking (Link Clicks & Page Engagement) — Live 2026-07-05

Per-recipient link/click tracking plus page engagement (time on page, scroll depth) on Rocket Loyalty member-app pages.

**Send path:** `inngest-amp-serve` (v40) calls `fn_amp_wrap_tracked_links(p_messages, p_merchant_id, p_workflow_id, p_node_id, p_user_id, p_channel, p_resource_id)` before dispatching LINE/SMS messages to messaging-service. Every absolute http(s) URL (flex `uri` actions; URLs inside top-level text messages) is replaced with `https://wkevmsedchftztoolkmi.supabase.co/functions/v1/link-redirect/<token>` and one `amp_tracked_link` row is inserted per (recipient, link, send). Wrapping failures never block the send. After the `workflow_log` insert, tokens are backfilled with `workflow_log_id`.

**Click:** `link-redirect` edge function (public) — token lookup → insert `amp_engagement_event` (`event_type='click'`) → 302 to destination with `rct=<token>` appended.

**Page engagement (member app only):** the Rocket Loyalty app reads `rct`, then POSTs `page_view` / `page_time` (seconds) / `scroll_depth` (percent) to the `engagement-beacon` edge function (public, CORS-restricted to `*.rocket-loyalty.app`). Contract: `docs/AMP_ENGAGEMENT_BEACON_SPEC.md`. External destinations get click tracking only (no beacon).

**Tables:** `amp_tracked_link` (token PK, merchant/workflow/node/resource/user scope, destination_url, channel, workflow_log_id), `amp_engagement_event` (append-only; denormalized scope columns; `value` = seconds or percent; session_id). RLS merchant_isolation on both.

**Analytics surfaces (v2 contract, 2026-07-05):**
- `bff_get_workflow_node_stats` — per node: `engagement` is `null` for non-message nodes; for message nodes `{messages_sent, tracked_recipients, unique_clickers, total_clicks, click_through_rate (0–1, null when tracked_recipients=0), avg/median_page_time_seconds, avg/median_scroll_depth_percent, engaged_sessions}` (page metrics NULL when destination is not the member app)
- `bff_get_amp_node_link_stats(p_workflow_id, p_node_id, p_from_date?, p_to_date?)` — per-destination-URL breakdown for one node: `links[] {destination_url, link_label (flex button label where derivable), tracked_recipients, unique_clickers, total_clicks, click_through_rate, page metrics, engaged_sessions}`
- `bff_amp_analytics_workflow` — workflow-level `engagement` object (incl. `messages_sent`) + `message_nodes[]` (date-scoped per-node engagement rows) + `daily_clicks[] {date, clicks, unique_clickers}`; `action_funnel` no longer emits `delivered`/`opened` (never populated — delivery tracking descoped)
- `bff_get_resource_content_engagement(p_resource_id, p_from_date, p_to_date)` — shared-content totals + `by_workflow[] {workflow_id, workflow_name, workflow_is_active, last_sent_at, metrics}` + `links[]` per-URL breakdown
- `bff_amp_analytics_user_timeline` — timeline emits enriched `click` events only (`destination_url`, `link_label`, `node_name`, `workflow_name`, `channel`, plus the session's max `page_time_seconds` / `scroll_depth_percent` embedded); `total_clicks` in summary
- `engaged_sessions` definition: distinct (token, session) pairs that reported at least one `page_time` or `scroll_depth` beacon event (member-app landings only; no time threshold)
- `link_label`: captured at wrap time from the LINE action object's `label`; NULL for raw text URLs

**Condition splits on engagement (live 2026-07-06):** condition nodes support the `content_engagement` group type — branch on `clicked` (true/false), `page_time` ≥/≤ N seconds, or `scroll_depth` ≥/≤ N percent, scoped to a specific message node, any message in this workflow (both current-run-only via `inngest_run_id`), or any workflow (optional time range). Optional `link_label` filter. Split-only — excluded from audiences, entry matching, and count preview. Full JSON contract and semantics: `requirements/AMP_Condition_Contract.md` §4.5; builder UX: `docs/AMP_WORKFLOW_BUILDER_FE_SPEC.md` §Content Engagement Condition Mode. Executor (`inngest-amp-serve` v41) injects `_workflow_id`/`_inngest_run_id` into engagement groups before RPC delegation.

---

## Architecture Summary

The AMP Workflows module stores workflow definitions as directed graphs (nodes + edges) and tracks execution via event sourcing. The event pipeline flows through **chokepoint outbox → OutboxPublisher → Inngest AMP routers → `amp-dispatch-realtime-event` → `inngest-amp-serve`**. Supabase stores definitions and logs. Inngest handles durable orchestration.

**Key Design Decisions:**
- **Chokepoint/Inngest triggers** — domain writers emit to `chokepoint_event_outbox`; AMP routers dispatch matching workflows without per-table DB trigger functions
- **Unified rule-based + agentic nodes** — the same workflow graph supports both static rule nodes (condition, action) and AI-powered agent nodes (calls the MCA decision engine)
- **Redis cache layer for config reads** — workflow triggers, workflow graphs, agent configs, cost normalization, credentials, and seed tables are cached in Upstash Redis (`amp-cache`). Eliminates repetitive Postgres reads on the hot path. See `AMP - Cache Layer.md`.
- Single event log table (INSERT per status change)
- Cumulative funnel counts via event sourcing
- Workflow status derived from node events (no separate execution table)
- Extensible status values (no schema change for new statuses)

---

## Inngest Orchestration Engine

### What is Inngest?

Inngest is a **durable execution platform** that handles workflow orchestration. Think of it as a specialized system that:

1. **Receives events** - Gets notified when something happens in your system (e.g., user earns points)
2. **Executes workflows** - Runs the sequence of steps defined in your workflow
3. **Handles complexity** - Manages retries, failures, long waits, and parallel execution automatically
4. **Maintains state** - Remembers where each user is in their journey, even across server restarts

**Key capability: Durable Execution**

Unlike regular code that fails if the server crashes, Inngest automatically:
- Saves progress after each step
- Resumes from where it left off after failures
- Retries failed steps with exponential backoff
- Handles workflows that span days or weeks (wait nodes)

### Architecture: Component Responsibilities

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                                                                              │
│   ┌─────────────────────────────────────────────────────────────────────┐   │
│   │                         SUPABASE                                     │   │
│   │                                                                      │   │
│   │  ┌───────────────────┐     ┌─────────────────────────────────────┐  │   │
│   │  │  Database Tables  │     │        Edge Functions               │  │   │
│   │  │  - wallet_ledger  │     │                                     │  │   │
│   │  │  - purchase_ledger│     │  ┌─────────────────────────────┐    │  │   │
│   │  │  - amp_workflow   │     │  │ dispatch-workflow-trigger   │    │  │   │
│   │  │  - amp_workflow_  │     │  │ - Looks up matching triggers│    │  │   │
│   │  │    trigger        │     │  │ - Sends events to Inngest   │    │  │   │
│   │  │  - amp_workflow_  │     │  └──────────────┬──────────────┘    │  │   │
│   │  │    log            │     │                 │                   │  │   │
│   │  └────────┬──────────┘     │  ┌──────────────▼──────────────┐    │  │   │
│   │           │ CDC            │  │ inngest-amp-serve               │◀───┼───┼──┐
│   │           │ (Debezium)     │  │ - Workflow executor         │    │  │  │
│   │           │                │  │ - Node handlers (incl agent)│    │  │  │
│   │           │                │  │ - Calls channel functions   │    │  │  │
│   │           │                │  └──────────────┬──────────────┘    │  │  │
│   │           │                │                 │                   │  │  │
│   │           │                │  ┌──────────────▼──────────────┐    │  │  │
│   │           │                │  │ send-line-message           │    │  │  │
│   │           │                │  │ send-sms-8x8                │    │  │  │
│   │           │                │  │ crm-loyalty-actions (MCP)   │    │  │  │
│   │           │                │  └─────────────────────────────┘    │  │  │
│   └───────────┼────────────────┴─────────────────────────────────────┘  │  │
│               │                                                          │  │
│   ┌───────────▼────────────────────────────────────────────────────┐     │  │
│   │                    CONFLUENT KAFKA                               │     │  │
│   │  crm.public.wallet_ledger    crm.public.purchase_ledger         │     │  │
│   └───────────┬────────────────────────────────────────────────────┘     │  │
│               │                                                          │  │
│   ┌───────────▼────────────────────────────────────────────────────┐     │  │
│   │              RENDER: crm-event-processors                       │     │  │
│   │  amp-*-router / amp-dispatch-realtime-event                                                    │     │  │
│   │  - Subscribes to CDC topics                                     │     │  │
│   │  - Parses Debezium, filters inserts                             │     │  │
│   │  - Maps to standard payload                                     │     │  │
│   │  - POSTs to dispatch-workflow-trigger ──────────────────────────┼─────┘  │
│   └────────────────────────────────────────────────────────────────┘        │
│                                                                              │
│   ┌────────────────────────────────────────────────────────────────┐        │
│   │                      INNGEST CLOUD                              │        │
│   │  ┌────────────────────┐  ┌──────────────────────────────────┐  │        │
│   │  │   Event Queue      │  │   Scheduler                      │──┼────────┘
│   │  │   amp/workflow.    │  │   - Tracks wait steps             │  │
│   │  │   trigger events   │  │   - Resumes after delays          │  │
│   │  └────────────────────┘  └──────────────────────────────────┘  │
│   └────────────────────────────────────────────────────────────────┘
│                                                                              │
└──────────────────────────────────────────────────────────────────────────────┘
```

**Supabase responsibilities:**
- Store workflow definitions (what steps to execute)
- Store execution logs (what happened)
- Host Edge Functions: dispatch-workflow-trigger, inngest-amp-serve, channel functions, crm-loyalty-actions (MCP server)
- Source of CDC events via Debezium

**Confluent Kafka responsibilities:**
- Stream CDC events from Supabase tables (wallet_ledger, purchase_ledger)
- Buffer traffic bursts — decouples database write rate from processing rate
- Existing CDC connector (`PostgresCdcSourceV2Connector_0`) already streams these topics

**Render (crm-event-processors) responsibilities:**
- amp-*-router / amp-dispatch-realtime-event: consume CDC topics, parse Debezium format, filter, deduplicate, call dispatch-workflow-trigger
- Runs alongside existing consumers (tier-*-router, currency-*-router, inngest-reward-serve, etc.) in the same service

**Inngest responsibilities:**
- Receive events and queue them
- Call the Edge Function to execute steps
- Track workflow state and progress
- Handle retries, timeouts, and scheduling
- Resume workflows after wait periods

### The Generic Workflow Executor Pattern

Instead of writing separate code for each workflow, we use a **single generic Inngest function** that dynamically reads workflow definitions from the database. This is the "one generic code" approach.

**How it works:**

1. **Event arrives** - Inngest receives an `amp/workflow.trigger` event
2. **Load definition** - The executor loads the workflow graph via `fn_get_workflow_graph_cached` (Redis cache, 10-min TTL, falls back to Postgres on miss). See `AMP - Cache Layer.md`.
3. **Find start** - Locates the trigger node (entry point)
4. **Execute step by step** - For each node:
   - Determine node type (condition, message, wait, action)
   - Run the appropriate handler
   - Find the next node(s) using edges
   - Continue until no more nodes
5. **Log everything** - Each step inserts an event to `workflow_log`

**Benefits of this approach:**
- Add new workflows without deploying code
- Modify workflows instantly via database
- All workflow logic is data-driven
- Single codebase handles all workflow types

### Event Flow: From Database to Workflow

Here's the complete journey when a user earns points:

```
Step 1: User Action
────────────────────────────────────────────────────────────────────────
User earns 100 points → INSERT into wallet_ledger table


Step 2: Debezium CDC Captures Change
────────────────────────────────────────────────────────────────────────
Debezium reads the PostgreSQL WAL (write-ahead log) and streams the
change event to Confluent Kafka topic: crm.public.wallet_ledger
  - Zero impact on the original INSERT transaction
  - ~200-500ms latency from write to Kafka


Step 3: amp-*-router / amp-dispatch-realtime-event Processes CDC Event (Render)
────────────────────────────────────────────────────────────────────────
amp-*-router / amp-dispatch-realtime-event in crm-event-processors service:
  1. Receives Debezium message from Kafka
  2. Checks: op = 'c' (insert only)
  3. Checks: transaction_type = 'earn' (table-specific filter)
  4. Deduplicates via Redis (5-min window per record ID)
  5. Maps Debezium format to standard payload:
     {
       trigger_table: 'wallet_ledger',
       trigger_operation: 'INSERT',
       merchant_id, user_id, record_id,
       record_data: { amount, currency, transaction_type, source_type }
     }
  6. HTTP POSTs to dispatch-workflow-trigger edge function


Step 4: Dispatcher Edge Function Routes
────────────────────────────────────────────────────────────────────────
dispatch-workflow-trigger edge function:
  1. Queries workflow_trigger for matching workflows
     - trigger_table = 'wallet_ledger'
     - trigger_operation = 'INSERT'
     - merchant_id matches
     - is_active = true
     - Checks trigger_conditions against record_data
  2. Filters to only active workflows
  3. For each matching workflow, sends HTTP POST to Inngest Cloud


Step 5: Inngest Receives Event
────────────────────────────────────────────────────────────────────────
Event arrives at Inngest Cloud:
{
  "name": "amp/workflow.trigger",
  "data": {
    "workflow_id": "abc-123",
    "user_id": "user-456",
    "merchant_id": "merchant-789",
    "trigger_data": {
      "source": "wallet_ledger",
      "amount": 100,
      "transaction_type": "earn"
    }
  }
}


Step 6: Inngest Invokes Executor Edge Function
────────────────────────────────────────────────────────────────────────
Inngest calls Supabase Edge Function (inngest-amp-serve):
  - POST /functions/v1/inngest-amp-serve
  - Contains event payload and run metadata


Step 7: Workflow Executor Runs
────────────────────────────────────────────────────────────────────────
The workflowExecutor function:
  1. Loads workflow graph from Supabase (nodes + edges)
  2. Loads user context for variable substitution
  3. Finds trigger node → executes it → logs "node_executed"
  4. Follows edge to next node
  5. For each node type:
     - condition: Evaluates query, routes true/false
     - wait: Calls step.sleep(), Inngest resumes after duration
     - action: Calls channel functions (LINE, SMS, etc.)
     - agent: Invokes agent service (via step.invoke), gets AI decision,
       injects into context as {{agent.*}} variables, routes true/false
  6. Logs "execution_completed" when done


Step 8: Results Persisted
────────────────────────────────────────────────────────────────────────
All steps logged to workflow_log for:
  - Audit trail
  - Funnel analytics
  - Debugging
  - User journey tracking
```

### Adding New Trigger Sources

To trigger workflows from a new table (e.g., form_submissions, tier_change_ledger):

1. Ensure Debezium CDC streams the table (add to `table.include.list` on the CDC connector if not already)
2. Add the topic to `amp-*-router / amp-dispatch-realtime-event`'s subscription list in `crm-event-processors`
3. Add table-specific filter logic in `shouldDispatch()` and field mapping in `extractRecordData()`
4. Deploy the Render service

No changes needed to `dispatch-workflow-trigger`, `inngest-amp-serve`, or any Supabase functions.

### Node Handler Logic

The Edge Function contains handlers for each node type:

**Condition Node**
```
Purpose: Branch workflow based on user data
Logic:
  1. Read query config: {table, field, operator, value}
  2. Execute query against Supabase (e.g., SELECT points_balance FROM user_wallet)
  3. Compare result using operator (>, <, =, etc.)
  4. Return 'true' or 'false' handle
Output: Routes to different paths based on result
```

**Message Node**
```
Purpose: Send communication to user
Logic:
  1. Read channel config (email/sms/line)
  2. Load template and personalize
  3. Call messaging provider API (SendGrid/8x8/LINE)
  4. Store external_message_id for webhook tracking
  5. Log 'sent' status
Output: Continues to next node
```

**Wait Node**
```
Purpose: Pause workflow for specified duration
Logic:
  1. Read duration config (e.g., "3d" for 3 days)
  2. Call step.sleep() - Inngest handles the scheduling
  3. Inngest resumes the workflow after duration
Output: Continues to next node after wait completes
```

**Action Node**
```
Purpose: Perform CRM operation, send message, or modify user data
Logic:
  1. Read action_type and channel from node_config
  2. Substitute variables in content ({{user.firstname}}, etc.)
  3. Execute based on type:

     DB-native actions (via fn_execute_amp_action RPC — single DB call):
     ─────────────────────────────────────────────────────────────
     award_currency   → chokepoint_post_wallet_transaction (points or tickets)
     assign_tag       → user_tags upsert
     remove_tag       → user_tags delete
     assign_persona   → user_accounts update (captures previous)
     assign_earn_factor → earn_factor_user insert (with window_end)
     submit_form      → submit_form_response RPC
     add_to_audience  → fn_add_to_audience
     remove_from_audience → fn_remove_from_audience

     The DB function handles validation, execution, logging to
     workflow_log, and cost tracking — all in one call.

     Messaging (inline — requires HTTP to edge functions):
     ─────────────────────────────────────────────────────────────
     LINE Message (channel: "line"):
       - Call send-line-message edge function
       - Supports text, flex, image, template messages

     SMS (channel: "sms"):
       - Call send-sms-8x8 edge function

     Integration (inline — requires HTTP to external):
     ─────────────────────────────────────────────────────────────
     API Call (action_type: "api_call"):
       - Makes HTTP request to external URL
       - Supports GET/POST/PUT/DELETE
       - Variable substitution in URL and body

Output: Continues to next node
```

**Agent Node**
```
Purpose: AI-powered decision with observe-wait-act deliberation loop
Logic:
  1. Load reusable agent config from amp_agent (objective, tone, constraints,
     deliberation settings)
  2. Filter eligible actions via amp_agent_action (check eligibility_conditions)
  3. Run deliberation loop (up to max_deliberation_cycles):
     a. step.invoke → agent service on Render (with fresh user data + history)
     b. AI assesses timing and returns one of:
        - "act"  → execute action tools, break loop
        - "wait" → step.sleep(duration), continue loop with fresh data
        - "skip" → break loop, no action
     c. Log decision to workflow_log (agent_decided_act/wait/skip)
  4. Inject result into context as {{agent.*}} variables
Output: Routes true (action taken) or false (skipped/exhausted)
```
See `AMP - AI Decisioning.md` for full details on the MCP server, agent service, constraints, outcomes, and the deliberation loop design.

**Action Node Config Examples:**

```json
// --- Loyalty Actions ---

// Award Points
{ "action_type": "award_currency", "currency": "points", "amount": 100, "description": "Welcome bonus" }

// Award Tickets
{ "action_type": "award_currency", "currency": "ticket", "ticket_type_id": "uuid", "amount": 5 }

// Assign Tag
{ "action_type": "assign_tag", "tag_id": "uuid" }

// Remove Tag
{ "action_type": "remove_tag", "tag_id": "uuid" }

// Assign Persona
{ "action_type": "assign_persona", "persona_id": "uuid" }

// Assign Private Earn Factor (temporary earning boost)
{ "action_type": "assign_earn_factor", "earn_factor_id": "uuid", "window_end_days": 30 }

// Submit Form
{
  "action_type": "submit_form",
  "form_id": "uuid",
  "field_values": {
    "favorite_color": "blue",
    "age": 28,
    "interests": ["sports", "cooking"],
    "feedback": "{{user.firstname}} loves this"
  }
}

// --- Messaging ---

// LINE Text Message
{
  "channel": "line",
  "content": "Hi {{user.firstname}}! You earned {{trigger.amount}} points!"
}

// LINE Flex Message
{
  "channel": "line",
  "json_content": {
    "type": "flex",
    "altText": "Your reward",
    "contents": { /* flex message JSON */ }
  }
}

// SMS
{ "channel": "sms", "message": "Hi {{user.firstname}}, your code is {{trigger.code}}" }

// --- Integration ---

// API Call / Webhook
{
  "action_type": "api_call",
  "url": "https://api.example.com/notify",
  "method": "POST",
  "body": { "user_id": "{{user.id}}", "event": "workflow_triggered" }
}
```

### CDC Trigger Implementation

Workflow triggers use **chokepoint outbox → Inngest AMP routers** (not PostgreSQL DB triggers). The Debezium/Kafka path below is historical (decommissioned 2026-07-07).

```
CDC Source (Confluent Kafka Connect):
────────────────────────────────────────────────────────────────────────
Connector: PostgresCdcSourceV2Connector_0
Tables:    public.purchase_ledger, public.wallet_ledger
Topics:    crm.public.purchase_ledger, crm.public.wallet_ledger
Format:    JSON_SR (Schema Registry)
```

```
amp-*-router / amp-dispatch-realtime-event (Render: crm-event-processors):
────────────────────────────────────────────────────────────────────────
Consumer group: crm-event-processors-amp
Subscribes to: crm.public.purchase_ledger, crm.public.wallet_ledger
Processing:    eachBatch + pLimit (concurrency=5, configurable)

Per message:
1. Parse Debezium format (handles JSON_SR 5-byte header)
2. Filter: op = 'c' (inserts only)
3. Filter: table-specific (wallet: earn only, purchase: completed only)
4. Deduplicate via Redis (5-min window per record ID)
5. Map to dispatch-workflow-trigger payload
6. HTTP POST to dispatch-workflow-trigger edge function
```

```
Dispatcher Edge Function (dispatch-workflow-trigger):
────────────────────────────────────────────────────────────────────────
1. Receive standard payload from amp-*-router / amp-dispatch-realtime-event

2. Query workflow_trigger to find workflows matching:
   - Same table (wallet_ledger / purchase_ledger)
   - Same operation (INSERT)
   - Same merchant_id
   - Both trigger and workflow are active
   - Optional: trigger_conditions match record_data

3. For each matching workflow:
   - Build Inngest event payload
   - Send HTTP POST to Inngest Cloud (https://inn.gs/e/{EVENT_KEY})

4. Return summary of dispatched workflows
```

> **Cache optimization (v65):** Step 2 now uses `fn_get_active_triggers_cached` which reads from Upstash Redis (`amp-cache`, 10-min TTL) instead of querying `workflow_trigger` + `workflow_master` on every CDC event. Cache is invalidated by `bff_upsert_amp_workflow_with_graph` on workflow save. See `AMP - Cache Layer.md`.

**Why event pipeline instead of DB triggers? (historical CDC rationale; live = outbox/Inngest)**
- ✅ Multi-table support without creating per-table trigger functions
- ✅ Kafka absorbs traffic bursts — 10K events/second is buffered, processed at controlled rate
- ✅ Zero impact on database transaction latency (CDC reads WAL, not tables)
- ✅ Same CDC connector already used by tier-*-router and currency-*-router
- ✅ Adding new trigger sources = add topic subscription, no DB changes
- ✅ Consumer-side deduplication and filtering before dispatch
- ⚠️ ~200-500ms additional latency vs DB trigger (negligible for marketing workflows)

### Inngest Configuration

**Required secrets in Supabase Edge Functions:**

| Edge Function | Required Env Vars |
|---------------|-------------------|
| `dispatch-workflow-trigger` | `INNGEST_EVENT_KEY`, `SUPABASE_URL`, `SUPABASE_SERVICE_ROLE_KEY` |
| `inngest-amp-serve` | `INNGEST_SIGNING_KEY`, `SUPABASE_URL`, `SUPABASE_SERVICE_ROLE_KEY` |
| `send-line-message` | `SUPABASE_URL`, `SUPABASE_SERVICE_ROLE_KEY` |
| `send-sms-8x8` | `SUPABASE_URL`, `SUPABASE_SERVICE_ROLE_KEY` |

**Edge Function JWT Settings:**

| Edge Function | JWT Verification | Why |
|---------------|------------------|-----|
| `dispatch-workflow-trigger` | **Disabled** | Called from Render consumer (uses service role key in Authorization header) |
| `inngest-amp-serve` | **Disabled** | Inngest authenticates via signing key |
| `send-line-message` | **Disabled** | Called from inngest-amp-serve with service key |
| `send-sms-8x8` | **Disabled** | Called from inngest-amp-serve |
| `crm-loyalty-actions` | **Disabled** | MCP server, called from inngest-amp-serve + agent service |
| `line-webhook` | **Disabled** | Called from LINE servers (no JWT) |

**Serve paths:**
- `/functions/v1/dispatch-workflow-trigger` - Trigger dispatcher
- `/functions/v1/inngest-amp-serve` - Workflow executor
- `/functions/v1/send-line-message` - LINE messaging
- `/functions/v1/line-webhook` - LINE webhook receiver

### Error Handling and Retries

Inngest provides automatic retry behavior:

```
Default Retry Policy:
────────────────────────────────────────────────────────────────────────
Retries: 3 attempts
Backoff: Exponential (1s → 2s → 4s → 8s...)

What gets retried:
- Network failures
- 5xx server errors
- Function timeouts

What doesn't retry:
- 4xx client errors (bad request)
- Explicit failures thrown by code

Error logging:
- Failed steps logged to workflow_log with error_message
- execution_failed event logged for workflow-level failures
```

### Messaging Provider Integration

The action node handler routes to different channel functions:

```
Channel Routing:
────────────────────────────────────────────────────────────────────────
LINE   → send-line-message edge function → LINE Messaging API
SMS    → send-sms-8x8 edge function → 8x8 CPaaS API
Email  → (not yet implemented) → SendGrid API

Each provider call:
1. Loads merchant's API credentials from merchant_credentials table
2. Resolves user's channel ID (e.g., line_id from user_accounts)
3. Substitutes variables in message content
4. Sends via provider API
5. Captures external_message_id for delivery tracking
6. Logs to workflow_log with status 'sent'

Credentials Storage (merchant_credentials table):
────────────────────────────────────────────────────────────────────────
LINE credentials stored as:
{
  "channel_id": "...",              // LINE Login channel
  "channel_secret": "...",          // LINE Login secret
  "messaging_channel_id": "...",    // LINE Messaging channel
  "messaging_channel_secret": "...",
  "messaging_channel_access_token": "..."
}

Webhook handling:
────────────────────────────────────────────────────────────────────────
LINE webhooks received at: /functions/v1/line-webhook
- Delivery events: Aggregated (not per-message)
- Read events: Aggregated (not per-message)
- Follow/Unfollow: Can link LINE users to CRM users
```

> **Cache optimization (v65):** Credential lookups now use `fn_get_merchant_credentials_cached` (Redis, 30-min TTL). Cache is auto-invalidated by a DB trigger on `merchant_credentials` changes. See `AMP - Cache Layer.md`.

### Current Implementation Status

| Component | Status | Notes |
|-----------|--------|-------|
| **Edge Functions** | | |
| `inngest-amp-serve` | ✅ Deployed (v63) | Workflow executor. Rule-based actions call `fn_execute_amp_action` RPC directly (no MCP). Agent nodes: reads `amp_agent` deliberation settings, invokes agent service on Render which pre-fetches all data and runs AI. Entry point is first node with no incoming edges. |
| `dispatch-workflow-trigger` | ✅ Deployed | Trigger dispatcher, JWT disabled |
| `send-line-message` | ✅ Deployed | LINE Messaging API integration |
| `send-sms-8x8` | ✅ Deployed | SMS via 8x8 |
| `line-webhook` | ✅ Deployed | LINE webhook receiver |
| AI-related components | See `AMP - AI Decisioning.md` | MCP server + agent service merged into `amp-ai-service` v3 on Render. Edge function `crm-loyalty-actions` retired. |
| **Event Pipeline** | | |
| CDC Source Connector | ❌ Decommissioned (2026-07-07) | Replaced by chokepoint outbox → Inngest |
| amp-*-router / amp-dispatch-realtime-event (Render) | ✅ Live | Consumes CDC, dispatches to dispatch-workflow-trigger |
| DB Trigger (wallet_ledger) | ❌ Removed | AMP path: outbox → amp-*-router → amp-dispatch-realtime-event |
| workflow_trigger lookup | ✅ Working | Dynamic workflow routing |
| **Node Types** | | |
| Trigger/Entry Node | ❌ Removed (v60) | Replaced by using first condition node as entry point. Backward compat: old trigger nodes are skipped without a round-trip. |
| Condition Node (simple) | ✅ Working | Queries single table rows via PostgREST |
| Condition Node (aggregate) | ✅ Working | SUM/COUNT/AVG with joins and time ranges via `fn_evaluate_amp_condition_group` |
| Wait Node | ✅ Working | Inngest step.sleep, supports `{duration, unit}` format |
| Agent Node | ✅ Working | Deliberation loop: observe-wait-act cycles. Reads config from `amp_agent`, filters eligible actions, invokes agent service via `step.invoke` per cycle with `step.sleep` between waits. See AI Decisioning doc. |
| **Action Types — Loyalty** | | |
| Award Currency (points) | ✅ Working | Via `chokepoint_post_wallet_transaction` RPC, source_type='amp' |
| Award Currency (tickets) | ✅ Working | Via `chokepoint_post_wallet_transaction` RPC, requires ticket_type_id |
| Assign Tag | ✅ Working | Upsert to user_tags with source_type='amp', source_id=workflow_id |
| Remove Tag | ✅ Working | Delete from user_tags |
| Assign Persona | ✅ Working | Updates user_accounts.persona_id, logs previous value |
| Assign Private Earn Factor | ✅ Working | Inserts to earn_factor_user with calculated window_end, source_type='amp' |
| Submit Form | ✅ Working | Via `submit_form_response` RPC, source='amp' |
| **Action Types — Audience** | | |
| Add to Audience | ✅ Working (v61) | Direct RPC via `fn_execute_amp_action` → `fn_add_to_audience` |
| Remove from Audience | ✅ Working (v61) | Direct RPC via `fn_execute_amp_action` → `fn_remove_from_audience` |
| **Action Types — Messaging** | | |
| Send LINE Message | ✅ Working | Calls send-line-message with variable substitution |
| Send SMS | ✅ Working | Calls send-sms-8x8 |
| **Action Types — Integration** | | |
| API Call / Webhook | ✅ Working | HTTP requests to external URLs |
| **Database Functions — Workflow Engine** | | |
| `bff_upsert_amp_workflow_with_graph` | ✅ Working | Atomic save with auto-trigger detection |
| `bff_get_amp_workflow_full` | ✅ Working | Get workflow with nodes/edges for builder |
| `bff_duplicate_amp_workflow` | ✅ Working | Clone workflow with ID remapping |
| `bff_get_workflow_collections` | ✅ Working | Returns tables/fields for condition builder (with aggregate metadata) |
| `fn_evaluate_amp_condition_group` | ✅ Working | Evaluates simple or aggregate conditions via dynamic SQL |
| `api_log_amp_workflow_event` | ✅ Fixed | Accepts all event types |
| `fn_get_amp_workflow_entry_node` | ✅ Working | Find entry node (first node with no incoming edges — typically the first condition node) |
| `fn_get_amp_workflow_next_nodes` | ✅ Working | Graph traversal |
| **Database Functions — Builder UI** | | |
| `bff_get_amp_action_options` | ✅ Working | Returns ticket types, tags, personas, forms, private earn factors |
| `bff_get_amp_form_fields` | ✅ Working | Returns fields + options for a specific form template |
| **Source Tracking** | | |
| wallet_ledger | ✅ `source_type='amp'` | Via chokepoint_post_wallet_transaction, enum value added |
| user_tags | ✅ `source_type`, `source_id` columns | Added, nullable, backward compatible |
| earn_factor_user | ✅ `source_type`, `source_id` columns | Added, nullable, backward compatible |
| form_submissions | ✅ `source='amp'`, `source_id` | Via submit_form_response p_source_id param |
| user_accounts (persona) | ✅ Logged in workflow_log | Previous persona captured in event_data |
| **Engagement Tracking** | | |
| Tracked links (click) | ✅ Live 2026-07-05 | `fn_amp_wrap_tracked_links` in inngest-amp-serve v40 → `link-redirect` edge fn → `amp_engagement_event` |
| Page engagement beacon | ✅ Backend live | `engagement-beacon` edge fn; member-app JS integration pending (`docs/AMP_ENGAGEMENT_BEACON_SPEC.md`) |
| **Pending** | | |
| Webhook Delivery Tracking | ❌ Descoped 2026-07-05 | LINE has no per-message delivered/read webhook (aggregate-only); replaced by tracked-link engagement above |
| Analytics Views | ⬜ Not started | v_amp_workflow_performance, v_amp_workflow_action_funnel |
| Additional CDC Tables | ⬜ Not started | tier_change_ledger, form_submissions (add to CDC connector + consumer) |
| **Audiences** | | |
| `amp_audience_master` + `amp_audience_member` | ✅ Applied | Audience entity + membership tables |
| Audience BFF functions | ✅ Applied | Create, update, delete, activate, deactivate, list, get members |
| `amp_audience_member` outbox/Inngest | ⬜ Pending | No audience-member domain event on live path yet |
| Audience backfill job | ⬜ Pending | Inngest function for batch evaluation on activate |
| Audience condition in workflow builder UI | ⬜ Pending | WeWeb frontend component |
| **Workflow Classification** | | |
| `scope` + `domain` columns | ✅ Applied | `scope`: user/system. `domain`: campaign/audience |
| **Agent Config** | See `AMP - AI Decisioning.md` | `amp_agent` table, agent BFF functions, MCP server, agent service — all applied/live |
|| **Cache Layer** | See `AMP - Cache Layer.md` | |
|| Upstash Redis `amp-cache` | ✅ Created | ap-southeast-1. Isolated from existing 6 Redis databases. |
|| Cached getter functions (9) | ✅ Applied | Triggers, workflow graph, agent config, action types, outcome events, cost normalization, performance summary, constraint usage, merchant credentials. TTLs: 10min–24h. |
|| Cache invalidation (BFF + triggers) | ✅ Applied | BFF save functions bust cache keys. DB triggers on `entity_cost_normalization` and `merchant_credentials`. |
|| Render + Edge Function integration | ⬜ Pending | Add `@upstash/redis` to Render services; switch Edge Functions to cached RPCs. |

---

## Workflow Classification

Two dimensions on `workflow_master`:

| Column | Values | Purpose |
|---|---|---|
| `scope` | `'user'` (default), `'system'` | `user` = marketer-facing, `system` = infrastructure (hidden from UI) |
| `domain` | `'campaign'` (default), `'audience'` | What the workflow automates. Extensible to `'enrichment'`, `'scoring'`. |

All existing workflows default to `scope='user', domain='campaign'`.

---

## Audiences

### Core Concept

An audience is a saved set of conditions that defines a segment of users. Under the hood, it's backed by a **system workflow** — a 2-node workflow that evaluates conditions and adds qualifying users to a membership table.

Audiences are not a separate execution engine. They use the same CDC pipeline, the same condition grammar, and the same workflow executor as marketing workflows.

### How It Works

**Creation** — When a marketer creates an audience:

1. `bff_create_audience` inserts into `amp_audience_master` (name, description)
2. Auto-creates a system workflow (`scope='system'`, `domain='audience'`)
3. Auto-creates 2 nodes:
   - **Condition node** — evaluates the audience criteria (same grammar as workflow condition nodes)
   - **Action node** — `add_to_audience` action that inserts into `amp_audience_member`
4. Auto-creates edge: condition → (true handle) → action
5. Auto-derives `workflow_trigger` entries from which tables the conditions reference

The conditions live in the condition node — `amp_audience_master` does not duplicate them. The audience entity is metadata + a pointer to the system workflow.

**Activation** — When the audience is activated (`bff_activate_audience`):

1. **Backfill** (default-on) — a batch job evaluates conditions against all merchant users, adds qualifying users to `amp_audience_member`
2. **System workflow activated** — `amp_workflow.is_active = true`, triggers activated
3. **Real-time** — from this point, CDC events trigger the system workflow. When a user's data changes and they now meet the conditions, they're added to the audience.

**Real-Time Population** — Same CDC pipeline as any workflow:

```
Data change (purchase, points, tier)
  → Debezium CDC → Kafka → amp-*-router / amp-dispatch-realtime-event
  → dispatch-workflow-trigger matches the audience's system workflow
  → Inngest runs the 2-node workflow
  → Condition evaluates → passes → add_to_audience action fires
  → INSERT into amp_audience_member
```

**Marketing Workflows Using Audiences** — Workflows can use audiences as their entry trigger. When a user enters an audience, `amp_audience_member` gets an INSERT. This table is on the CDC pipeline, so:

```
amp_audience_member INSERT
  → CDC → Kafka → amp-*-router / amp-dispatch-realtime-event
  → dispatch-workflow-trigger matches marketing workflows targeting this audience
  → Marketing workflow starts for that user
```

The marketing workflow's `workflow_trigger` record:
```
trigger_table: 'amp_audience_member'
trigger_operation: 'INSERT'
trigger_conditions: { "audience_id": "<uuid>" }
```

**Audience as mid-journey condition** is also supported: a condition node can check "is user in audience X?" via membership lookup.

### Audience Tables

**`amp_audience_master`**

| Column | Type | Purpose |
|---|---|---|
| `id` | UUID PK | |
| `merchant_id` | UUID FK → merchant_master | Scoping |
| `name` | TEXT NOT NULL | "Lapsed VIPs", "High Spenders" |
| `description` | TEXT | |
| `workflow_id` | UUID FK → amp_workflow | The auto-created system workflow |
| `is_active` | BOOLEAN (default false) | Controls workflow activation |
| `member_count` | INTEGER (default 0) | Cached count, updated by fn_add/remove |
| `created_at` / `updated_at` | TIMESTAMPTZ | |

**`amp_audience_member`**

| Column | Type | Purpose |
|---|---|---|
| `id` | UUID PK | |
| `audience_id` | UUID FK → amp_audience_master (CASCADE) | |
| `user_id` | UUID FK → user_accounts | |
| `entered_at` | TIMESTAMPTZ | When they qualified |
| `exited_at` | TIMESTAMPTZ | NULL while active (future: set on disqualification) |
| `source_workflow_id` | UUID FK → amp_workflow | Which workflow added them |
| `created_at` | TIMESTAMPTZ | |

Partial unique index: `(audience_id, user_id) WHERE exited_at IS NULL` — a user can only be an active member once.

### Audience Action Types

**`add_to_audience`** — `{ "action_type": "add_to_audience", "audience_id": "uuid" }`. Executes `fn_add_to_audience`: upsert into `amp_audience_member`, increment `member_count`. Idempotent.

**`remove_from_audience`** — `{ "action_type": "remove_from_audience", "audience_id": "uuid" }`. Executes `fn_remove_from_audience`: sets `exited_at = now()`, decrements `member_count`. Soft delete.

### Audience Database Functions

| Function | Type | Purpose |
|---|---|---|
| `bff_create_audience(p_name, p_description, p_conditions)` | SECURITY DEFINER | Atomic: creates audience + system workflow + 2 nodes + edge + auto-triggers |
| `bff_update_audience(p_audience_id, p_name, p_description, p_conditions)` | SECURITY DEFINER | Updates audience metadata + syncs conditions to workflow + re-derives triggers |
| `bff_delete_audience(p_audience_id)` | SECURITY DEFINER | Requires deactivation first. Deletes audience + workflow cascade |
| `bff_activate_audience(p_audience_id, p_run_backfill)` | SECURITY DEFINER | Activates audience + workflow + triggers. Backfill flag for external job. |
| `bff_deactivate_audience(p_audience_id)` | SECURITY DEFINER | Deactivates without deleting members |
| `bff_list_audiences()` | SECURITY DEFINER | List all audiences for merchant with member counts |
| `bff_get_audience_members(p_audience_id, p_limit, p_offset, p_include_exited)` | SECURITY DEFINER | Paginated member list with user details |
| `fn_add_to_audience(p_audience_id, p_user_id, p_source_workflow_id)` | SECURITY INVOKER | Internal: insert member + increment count |
| `fn_remove_from_audience(p_audience_id, p_user_id)` | SECURITY INVOKER | Internal: soft exit + decrement count |

### Audience CDC Pipeline (Pending)

1. Add `amp_audience_member` to Debezium CDC connector's `table.include.list`
2. amp-*-router / amp-dispatch-realtime-event subscribes to `crm.public.amp_audience_member` topic
3. amp-*-router / amp-dispatch-realtime-event filter: `op = 'c'` (inserts only), maps `audience_id` to dispatch payload
4. `dispatch-workflow-trigger` matches marketing workflows with `trigger_table = 'amp_audience_member'`

### Audience RLS

Both tables have RLS enabled:
- `amp_audience_master`: merchant-scoped via `get_current_merchant_id()`
- `amp_audience_member`: merchant-scoped via subquery join to `amp_audience_master`
- Service role has full access on both

---

## Tables Overview

| Table | Purpose | Rows |
|-------|---------|------|
| `workflow_master` | Workflow definitions | 1 per workflow |
| `workflow_node` | Node definitions | N per workflow |
| `workflow_edge` | Node connections | M per workflow |
| `workflow_trigger` | CRM event → workflow routing | K per workflow |
| `workflow_log` | Event sourcing execution log | Many per execution |

---

## Phase 1: Workflow Definition Tables

### 1.1 `workflow_master`

```sql
CREATE TABLE amp_workflow (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  merchant_id UUID NOT NULL,
  workflow_code TEXT NOT NULL,
  name TEXT NOT NULL,
  description TEXT,
  is_active BOOLEAN DEFAULT false,
  created_at TIMESTAMPTZ DEFAULT now(),
  updated_at TIMESTAMPTZ DEFAULT now(),
  created_by UUID,
  
  CONSTRAINT fk_merchant FOREIGN KEY (merchant_id) REFERENCES merchant(id),
  CONSTRAINT uq_amp_workflow_code UNIQUE (merchant_id, workflow_code)
);

CREATE INDEX idx_amp_workflow_merchant ON amp_workflow(merchant_id);
CREATE INDEX idx_amp_workflow_active ON amp_workflow(merchant_id, is_active) WHERE is_active = true;
```

### 1.2 `workflow_node`

```sql
CREATE TABLE workflow_node (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  workflow_id UUID NOT NULL,
  merchant_id UUID NOT NULL,
  node_type TEXT NOT NULL,
  node_name TEXT,
  node_config JSONB NOT NULL DEFAULT '{}',
  position_x NUMERIC DEFAULT 0,
  position_y NUMERIC DEFAULT 0,
  created_at TIMESTAMPTZ DEFAULT now(),
  updated_at TIMESTAMPTZ DEFAULT now(),
  
  CONSTRAINT fk_workflow FOREIGN KEY (workflow_id) REFERENCES amp_workflow(id) ON DELETE CASCADE,
  CONSTRAINT fk_merchant FOREIGN KEY (merchant_id) REFERENCES merchant(id)
);

CREATE INDEX idx_workflow_node_workflow ON workflow_node(workflow_id);
CREATE INDEX idx_workflow_node_merchant ON workflow_node(merchant_id);
```

**Node Types:** `condition`, `message`, `wait`, `api_call`, `action`, `agent`

**Node Config Examples:**
- `condition`: `{query: {table, field, operator, value}}`
- `message`: `{channel: "email", template_id: "...", subject: "..."}`
- `wait`: `{duration: "3d"}`
- `action`: `{action_type: "award_points", params: {amount: 100}}`

### 1.3 `workflow_edge`

```sql
CREATE TABLE workflow_edge (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  workflow_id UUID NOT NULL,
  merchant_id UUID NOT NULL,
  from_node_id UUID NOT NULL,
  to_node_id UUID NOT NULL,
  source_handle TEXT DEFAULT 'default',
  edge_label TEXT,
  created_at TIMESTAMPTZ DEFAULT now(),
  
  CONSTRAINT fk_workflow FOREIGN KEY (workflow_id) REFERENCES amp_workflow(id) ON DELETE CASCADE,
  CONSTRAINT fk_from_node FOREIGN KEY (from_node_id) REFERENCES workflow_node(id) ON DELETE CASCADE,
  CONSTRAINT fk_to_node FOREIGN KEY (to_node_id) REFERENCES workflow_node(id) ON DELETE CASCADE,
  CONSTRAINT fk_merchant FOREIGN KEY (merchant_id) REFERENCES merchant(id)
);

CREATE INDEX idx_workflow_edge_workflow ON workflow_edge(workflow_id);
CREATE INDEX idx_workflow_edge_from ON workflow_edge(from_node_id);
```

**Source Handles:** `default`, `true`, `false` (for condition branching)

### 1.4 `workflow_trigger`

```sql
CREATE TABLE workflow_trigger (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  workflow_id UUID NOT NULL,
  merchant_id UUID NOT NULL,
  trigger_type TEXT NOT NULL,
  trigger_table TEXT NOT NULL,
  trigger_operation TEXT NOT NULL,
  trigger_conditions JSONB,
  is_active BOOLEAN DEFAULT true,
  created_at TIMESTAMPTZ DEFAULT now(),
  
  CONSTRAINT fk_workflow FOREIGN KEY (workflow_id) REFERENCES amp_workflow(id) ON DELETE CASCADE,
  CONSTRAINT fk_merchant FOREIGN KEY (merchant_id) REFERENCES merchant(id),
  CONSTRAINT chk_trigger_operation CHECK (trigger_operation IN ('INSERT', 'UPDATE', 'DELETE'))
);

CREATE INDEX idx_workflow_trigger_table ON workflow_trigger(trigger_table, trigger_operation);
CREATE INDEX idx_workflow_trigger_merchant ON workflow_trigger(merchant_id);
```

**Trigger Types:** `purchase_completed`, `tier_upgraded`, `points_earned`, `form_submitted`, `tag_assigned`, `custom`

---

## Phase 2: Event Log Table (Event Sourcing)

### 2.1 `workflow_log`

Single table for all execution events. INSERT per status change.

```sql
CREATE TABLE workflow_log (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  merchant_id UUID NOT NULL,
  workflow_id UUID NOT NULL,
  user_id UUID NOT NULL,
  inngest_run_id TEXT NOT NULL,
  
  -- Event identification
  event_type TEXT NOT NULL,
  
  -- Node context (NULL for workflow-level events)
  node_id UUID,
  node_type TEXT,
  action_type TEXT,
  status TEXT,
  
  -- Webhook matching
  external_message_id TEXT,
  
  -- Flexible payload
  event_data JSONB,
  error_message TEXT,
  
  created_at TIMESTAMPTZ DEFAULT now(),
  
  CONSTRAINT fk_workflow FOREIGN KEY (workflow_id) REFERENCES amp_workflow(id),
  CONSTRAINT fk_node FOREIGN KEY (node_id) REFERENCES workflow_node(id)
);

-- Query indexes
CREATE INDEX idx_workflow_log_merchant ON workflow_log(merchant_id);
CREATE INDEX idx_workflow_log_workflow ON workflow_log(workflow_id);
CREATE INDEX idx_workflow_log_run ON workflow_log(inngest_run_id);
CREATE INDEX idx_workflow_log_event_type ON workflow_log(event_type);
CREATE INDEX idx_workflow_log_user ON workflow_log(user_id);
CREATE INDEX idx_workflow_log_created ON workflow_log(created_at DESC);
CREATE INDEX idx_workflow_log_external_msg ON workflow_log(external_message_id) 
  WHERE external_message_id IS NOT NULL;
```

**Event Types:**

| event_type | When | node_id | status |
|------------|------|---------|--------|
| `execution_started` | Workflow begins | NULL | NULL |
| `node_executed` | Node runs | ✓ | `executed` |
| `action_sent` | Message accepted by provider | ✓ | `sent` |
| `action_delivered` | Webhook: delivered | ✓ | `delivered` |
| `action_opened` | Webhook: opened | ✓ | `opened` |
| `action_failed` | Node failed | ✓ | `failed` |
| `execution_completed` | Workflow finished | NULL | NULL |
| `execution_failed` | Workflow errored | NULL | NULL |
| `execution_exited` | User exited/cancelled | NULL | NULL |
| `agent_decided_act` | Agent decided to execute actions | ✓ | `acted` |
| `agent_decided_wait` | Agent decided to wait and reassess | ✓ | `waiting` |
| `agent_decided_skip` | Agent decided user is not a fit / deliberation exhausted | ✓ | `skipped` / `exhausted` |

---

## Phase 3: Analytics Views

### 3.1 `v_amp_workflow_performance`

```sql
CREATE VIEW v_amp_workflow_performance AS
SELECT 
  w.id as workflow_id,
  w.name as workflow_name,
  w.merchant_id,
  COUNT(*) FILTER (WHERE l.event_type = 'execution_started') as total_triggers,
  COUNT(DISTINCT l.user_id) FILTER (WHERE l.event_type = 'execution_started') as unique_users,
  COUNT(*) FILTER (WHERE l.event_type = 'execution_completed') as completed,
  COUNT(*) FILTER (WHERE l.event_type = 'execution_failed') as failed,
  COUNT(*) FILTER (WHERE l.event_type = 'execution_exited') as exited,
  COUNT(DISTINCT l.inngest_run_id) FILTER (
    WHERE l.event_type = 'execution_started' 
    AND l.inngest_run_id NOT IN (
      SELECT inngest_run_id FROM workflow_log 
      WHERE event_type IN ('execution_completed', 'execution_failed', 'execution_exited')
    )
  ) as in_flight
FROM amp_workflow w
LEFT JOIN workflow_log l ON l.workflow_id = w.id
GROUP BY w.id, w.name, w.merchant_id;
```

### 3.2 `v_amp_workflow_action_funnel`

```sql
CREATE VIEW v_amp_workflow_action_funnel AS
SELECT
  workflow_id,
  merchant_id,
  action_type,
  COUNT(*) FILTER (WHERE status = 'executed') as executed,
  COUNT(*) FILTER (WHERE status = 'sent') as sent,
  COUNT(*) FILTER (WHERE status = 'delivered') as delivered,
  COUNT(*) FILTER (WHERE status = 'opened') as opened,
  COUNT(*) FILTER (WHERE status = 'failed') as failed
FROM workflow_log
WHERE node_type = 'message'
GROUP BY workflow_id, merchant_id, action_type;
```

---

## Phase 4: Functions

### BFF Functions (WeWeb Admin)

| Function | Purpose |
|----------|---------|
| `bff_upsert_amp_workflow_with_graph(p_workflow, p_nodes[], p_edges[])` | Atomic save of workflow + nodes + edges |
| `bff_get_amp_workflow_full(p_workflow_id)` | Get workflow with nodes/edges for builder |
| `bff_duplicate_amp_workflow(p_workflow_id, p_new_name)` | Clone workflow |

### API Functions (External/Inngest)

| Function | Purpose |
|----------|---------|
| `api_log_amp_workflow_event(...)` | Insert event to log (called by Inngest) |
| `api_get_amp_workflow_definition(p_workflow_id)` | Get workflow graph for Inngest execution |

### Internal Functions

| Function | Purpose |
|----------|---------|
| `fn_get_amp_workflow_next_nodes(p_workflow_id, p_node_id, p_handle)` | Get next nodes from edges |
| `fn_get_amp_workflow_entry_node(p_workflow_id)` | Find node with no incoming edges |

---

## Phase 5: RLS Policies

Standard pattern for all tables:

```sql
ALTER TABLE amp_workflow ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Authenticated users can view merchant data"
ON amp_workflow FOR SELECT TO authenticated
USING (merchant_id = get_current_merchant_id());

CREATE POLICY "Authenticated users can manage merchant data"
ON amp_workflow FOR ALL TO authenticated
USING (merchant_id = get_current_merchant_id())
WITH CHECK (merchant_id = get_current_merchant_id());

CREATE POLICY "Service role has full access"
ON amp_workflow FOR ALL TO service_role
USING (true);
```

Apply to: `workflow_master`, `workflow_node`, `workflow_edge`, `workflow_trigger`, `workflow_log`

---

## Phase 6: Event Pipeline (HISTORICAL — CDC → Kafka; live = outbox → Inngest)

Database triggers have been replaced by a CDC-based event pipeline. See "CDC Trigger Implementation" section above for full details.

**Pipeline components:**
- Debezium CDC connector (`PostgresCdcSourceV2Connector_0`) streams table changes to Kafka
- `amp-*-router / amp-dispatch-realtime-event` in `crm-event-processors` (Render) consumes CDC topics
- Consumer calls `dispatch-workflow-trigger` edge function which routes to Inngest

**Source code:** `Rocket-CRM/crm-event-processors` → `src/consumers/amp-consumer.ts`

**Env vars on Render:**
- `AMP_CONCURRENCY` — parallel processing limit (default: 5)
- Standard Kafka/Supabase/Redis vars shared with other consumers

---

## Dashboard Queries

### Workflow Metrics (Top Section)

```sql
-- (1) # of workflow triggers
SELECT COUNT(*) 
FROM workflow_log 
WHERE event_type = 'execution_started' 
  AND workflow_id = $1 
  AND created_at BETWEEN $2 AND $3;

-- (2) # unique users entered
SELECT COUNT(DISTINCT user_id) 
FROM workflow_log 
WHERE event_type = 'execution_started' 
  AND workflow_id = $1;

-- (4) # completed
SELECT COUNT(*) 
FROM workflow_log 
WHERE event_type = 'execution_completed' 
  AND workflow_id = $1;

-- (5) Currently in flight
SELECT COUNT(DISTINCT inngest_run_id)
FROM workflow_log
WHERE workflow_id = $1
  AND event_type = 'execution_started'
  AND inngest_run_id NOT IN (
    SELECT inngest_run_id FROM workflow_log 
    WHERE event_type IN ('execution_completed', 'execution_failed', 'execution_exited')
  );
```

### Action Funnel (Bottom Section)

```sql
SELECT
  action_type,
  COUNT(*) FILTER (WHERE status = 'executed') as executed,
  COUNT(*) FILTER (WHERE status = 'sent') as sent,
  COUNT(*) FILTER (WHERE status = 'delivered') as delivered,
  COUNT(*) FILTER (WHERE status = 'opened') as opened
FROM workflow_log
WHERE merchant_id = get_current_merchant_id()
  AND node_type = 'message'
  AND created_at BETWEEN $1 AND $2
GROUP BY action_type;
```

### User Export

```sql
SELECT 
  u.full_name,
  l.user_id,
  MIN(l.created_at) FILTER (WHERE l.event_type = 'execution_started') as entry_date,
  MAX(l.created_at) FILTER (WHERE l.event_type = 'execution_exited') as exit_date,
  MAX(l.created_at) FILTER (WHERE l.event_type = 'execution_completed') as completion_date
FROM workflow_log l
JOIN user_accounts u ON u.id = l.user_id
WHERE l.workflow_id = $1
  AND l.merchant_id = get_current_merchant_id()
GROUP BY u.full_name, l.user_id, l.inngest_run_id;
```

---

## Migration Files

```
migrations/
├── 007_create_amp_workflow_tables.sql
├── 008_create_workflow_log.sql
├── 009_create_amp_workflow_rls.sql
├── 010_create_amp_workflow_views.sql          (pending - analytics views)
├── 011_create_amp_workflow_functions.sql
├── fix_api_log_amp_workflow_event_whitelist.sql  (applied)
├── drop_wallet_ledger_inngest_trigger.sql        (applied)
```

---

## Event Flow Example

**5-node workflow with 1 email node:**

```
Time    Event Type           node_id    status      external_message_id
─────────────────────────────────────────────────────────────────────────
00:00   execution_started    NULL       NULL        NULL
00:01   node_executed        node-1     executed    NULL         (condition)
00:02   node_executed        node-2     executed    NULL         (email node)
00:02   action_sent          node-2     sent        msg_abc123   (email accepted)
00:03   node_executed        node-3     executed    NULL         (wait node)
3 days  node_executed        node-4     executed    NULL         (condition)
3 days  node_executed        node-5     executed    NULL         (end node)
3 days  execution_completed  NULL       NULL        NULL

...async webhook 5 min later...
+5min   action_delivered     node-2     delivered   msg_abc123

...async webhook 2 hours later...
+2hr    action_opened        node-2     opened      msg_abc123
```

**Total rows for this execution: 10**

---

## Write Volume Estimate

| Scenario | Rows per Execution |
|----------|-------------------|
| Simple 3-node workflow | ~5 |
| 5-node with 1 message | ~10 |
| 10-node with 3 messages | ~20 |

For 10K executions/day with avg 10 rows = **100K inserts/day** (manageable)

---

## Workflow Triggers

`workflow_trigger` rows attach a workflow to a source. There are three trigger families. All three converge at Inngest (`amp/workflow.trigger`) and are executed per-user by `inngest-amp-serve`.

### Architecture Flow (all three lanes)

The three lanes share two important pieces:
1. **`fn_amp_find_matching_users`** — the bulk SQL matcher used by both the manual and scheduled lanes (the realtime lane doesn't need it; it has the user from the event payload).
2. **`amp-dispatch-workflow-batch`** — the Edge Function that fans out a `user_ids[]` array to per-user `amp/workflow.trigger` events on Inngest.

`bff_amp_batch_run` is the manual lane's auth/validation wrapper around the matcher — it does *not* match users itself; it delegates to `fn_amp_find_matching_users`.

```text
┌─ Realtime lane ──────┐  ┌─ Manual batch lane ────────┐  ┌─ Scheduled lane ─────────────────────────────┐
│ Kafka CDC event      │  │ Admin "Batch run" (FE)     │  │ pg_cron — every 1 min                        │
│       │              │  │       │                    │  │       │                                      │
│       ▼              │  │       ▼                    │  │       ▼                                      │
│ amp-*-router / amp-dispatch-realtime-event (Render) │  │ bff_amp_batch_run(wf_id)   │  │ fn_amp_run_due_scheduled_workflows(now)      │
│       │              │  │  • auth (merchant from JWT)│  │   ① SELECT FROM workflow_trigger             │
│       ▼              │  │  • workflow ownership      │  │       WHERE trigger_type='scheduled'         │
│ amp-dispatch-        │  │  • is_active check         │  │         AND is_active=true                   │
│ realtime-event       │  │  • inserts                 │  │         AND schedule_status='idle'           │
│ (Edge Function)      │  │    batch_run_requested log │  │         AND next_run_at <= now()             │
│       │              │  │       │                    │  │       FOR UPDATE SKIP LOCKED                 │
│       │ per-event,   │  │       │ internal call      │  │   ② claim: schedule_status='running'         │
│       │ single user  │  │       ▼                    │  │   ③ validate workflow.is_active              │
│       │ from payload │  │ ┌──────────────────────────┴──┴──┐ ④ read trigger_conditions.schedule        │
│       │              │  │ │                                │   + run_window (config only; see note)    │
│       │              │  │ │   fn_amp_find_matching_users   │ ⑤ internal call ──┐                       │
│       │              │  │ │   (workflow_id)                │◄──────────────────┘                       │
│       │              │  │ │                                │                                           │
│       │              │  │ │  • read first condition node   │                                           │
│       │              │  │ │  • build dynamic SQL by group  │                                           │
│       │              │  │ │  • merchant_id filter          │                                           │
│       │              │  │ │  • EXCEPT users already        │                                           │
│       │              │  │ │    enrolled (workflow_log      │                                           │
│       │              │  │ │    execution_started)          │                                           │
│       │              │  │ │  • returns TABLE(user_id)      │                                           │
│       │              │  │ └──────┬──────────────────┬──────┘                                           │
│       │              │  │        │ user_ids[] back  │ user_ids[] in cron scope                        │
│       │              │  │        ▼                  │   ⑥ pg_net POST { workflow_id, user_ids }        │
│       │              │  │ FE calls amp-dispatch-    │      → amp-dispatch-workflow-batch              │
│       │              │  │ workflow-batch with       │   ⑦ last_run_at=now();                          │
│       │              │  │ { workflow_id, user_ids } │      next_run_at=fn_amp_compute_next_run_at(    │
│       │              │  │        │                  │        schedule, now);                          │
│       │              │  │        │                  │      schedule_status='idle' | 'failed'          │
│       │              │  │        │                  │   ⑧ workflow_log INSERT one of:                 │
│       │              │  │        │                  │      scheduled_run_dispatched | _no_users |     │
│       │              │  │        │                  │      _failed                                    │
└───────┼──────────────┘  └────────┼──────────────────┴─────┼───────────────────────────────────────────┘
        │                          │                        │
        │                          ▼                        ▼
        │             amp-dispatch-workflow-batch  (Edge Function — fans out user_ids → Inngest events)
        │                          │
        └─────────────────────► Inngest cloud — `amp/workflow.trigger` × N users
                                   │
                                   ▼
                           inngest-amp-serve  (per-user durable execution: condition + action nodes)
```

Notes embedded in the flow:
- **`SKIP LOCKED`** lets concurrent cron ticks run safely if a previous tick is still claiming rows.
- **`run_window`** is config metadata on the trigger — *the cron does not filter by it*. It is reserved for the condition evaluator (planned). Today, choose a schedule cadence that matches the condition's expected window: a daily birthday workflow needs a daily schedule + a "birthday = today" condition; a weekly digest needs a weekly schedule + a "completed activity in last 7 days" condition.
- **The matching engine is shared.** Manual batch (via `bff_amp_batch_run`) and scheduled (via `fn_amp_run_due_scheduled_workflows`) both call the same `fn_amp_find_matching_users`. The realtime lane does not — it uses the event payload as the candidate user, then re-evaluates the entry condition inside Inngest per user.
- **`bff_amp_batch_run` is a wrapper, not a matcher.** It handles auth, ownership, the `is_active` check, and the audit log row, then delegates the actual user resolution to `fn_amp_find_matching_users`. The scheduled lane skips the BFF because there is no JWT context — pg_cron runs as superuser via `SECURITY DEFINER`.

### Trigger Type Families

| trigger_type | Caller chain | User discovery | Notes |
|---|---|---|---|
| `realtime` (legacy values: `purchase_completed`, `points_earned`, `form_completed`, `database`, `custom`) | amp-*-router / amp-dispatch-realtime-event (Render) → `amp-dispatch-realtime-event` Edge Function → Inngest | Single user from CDC event payload; workflows matched via `fn_get_active_triggers_cached` on `trigger_table` + `trigger_operation` + `trigger_conditions` | Re-evaluates entry condition inside Inngest per user. Does **not** call `fn_amp_find_matching_users`. |
| `manual` (admin "Batch run" button) | FE → `bff_amp_batch_run(workflow_id)` → FE → `amp-dispatch-workflow-batch` → Inngest | `bff_amp_batch_run` wraps auth + ownership + `is_active` check + audit log, then internally calls `fn_amp_find_matching_users(workflow_id)` and returns `user_ids[]` to the FE | The BFF is *not* itself a matcher — it delegates. Excludes users already in `workflow_log` with `event_type = 'execution_started'` (handled inside the matcher's `EXCEPT` clause). |
| `scheduled` | `pg_cron` → `fn_amp_run_due_scheduled_workflows()` → `pg_net` POST → `amp-dispatch-workflow-batch` → Inngest | Same `fn_amp_find_matching_users` matcher, called directly from the cron function (no BFF — no JWT context). Cron only checks `next_run_at <= now()` every minute; per-user qualification stays inside the matcher. | Skips the BFF because pg_cron runs as superuser via `SECURITY DEFINER`. |

For `scheduled` rows, set `trigger_table = 'scheduler'` and `trigger_operation = 'INSERT'` as sentinels (the existing NOT NULL + check constraints require non-null operation in {INSERT,UPDATE,DELETE}).

### Scheduled Trigger Schema

`workflow_trigger` columns added for scheduling:

| Column | Type | Purpose |
|---|---|---|
| `next_run_at` | `timestamptz` | When the scheduler should next evaluate this trigger. Auto-computed by `trg_workflow_trigger_set_next_run_at` on insert/update. |
| `last_run_at` | `timestamptz` | When the scheduler last evaluated this trigger. |
| `schedule_status` | `text` (`idle` | `running` | `failed`) | Claim/lock state. Default `idle`. |

Index: `idx_workflow_trigger_scheduled_due ON workflow_trigger (next_run_at) WHERE trigger_type = 'scheduled' AND is_active = true`.

### `trigger_conditions` JSONB Shape (scheduled)

```json
{
  "schedule": {
    "type": "daily" | "weekly" | "monthly" | "interval" | "one_off",
    "time_of_day": "02:00",
    "weekdays": [1, 3, 5],
    "day_of_month": 15,
    "interval_minutes": 60,
    "run_at": "2026-12-25T00:00:00Z",
    "timezone": "Asia/Bangkok"
  },
  "run_window": {
    "value": 1,
    "unit": "day"
  }
}
```

`run_window` is reserved for the condition evaluator and is **not** read by `fn_amp_run_due_scheduled_workflows`. The cron only checks `next_run_at`; window enforcement happens implicitly today via the condition node.

**Pairing rule (until `run_window` is wired into the condition evaluator):** the cadence on `schedule.type` must match the condition's window. Examples:
- Daily birthday campaign: `schedule.type = 'daily'` + entry condition `birthday = today`.
- Weekly digest of recent activity: `schedule.type = 'weekly'` + entry condition `completed activity in last 7 days`.
- Anniversary celebration: `schedule.type = 'daily'` + entry condition `signup_date anniversary today`.

Mismatches (e.g. weekly schedule with a "today" condition) will under- or over-fire. There is no scheduler-side guard against this yet; it is a build-time discipline.

### Functions

| Function | Purpose |
|---|---|
| `fn_amp_compute_next_run_at(p_schedule jsonb, p_from timestamptz)` | Returns next occurrence of the schedule after `p_from`. Supports `daily`, `weekly`, `monthly`, `interval`, `one_off`. Returns NULL for unsupported types or expired one-offs. |
| `trigger_workflow_trigger_set_next_run_at()` | BEFORE INSERT/UPDATE trigger on `workflow_trigger`. Auto-computes `next_run_at` when the row is new, schedule changes, or trigger reactivates. Clears `next_run_at` for non-scheduled types. |
| `fn_amp_run_due_scheduled_workflows(p_run_at timestamptz default now())` | Main scheduler. Locks due rows with `FOR UPDATE SKIP LOCKED`, calls `fn_amp_find_matching_users`, POSTs matched users to `amp-dispatch-workflow-batch` via `pg_net`, advances `next_run_at`. Logs `scheduled_run_dispatched` / `scheduled_run_no_users` / `scheduled_run_failed` to `workflow_log`. |
| `fn_amp_find_matching_users(p_workflow_id uuid)` (existing) | Bulk SQL entry resolver. Reads workflow's first condition node JSON, builds dynamic SQL (simple or aggregate), filters by merchant, applies `EXCEPT` against `workflow_log` for already-enrolled users, returns `TABLE(user_id uuid)`. Pure resolver — no side effects, no log writes. Shared by `bff_amp_batch_run` (manual lane) and `fn_amp_run_due_scheduled_workflows` (scheduled lane). |
| `bff_amp_batch_run(p_workflow_id uuid)` (existing) | Admin BFF wrapper. Resolves merchant from JWT, validates workflow ownership and `is_active`, internally calls `fn_amp_find_matching_users`, inserts a `batch_run_requested` row into `workflow_log`, returns `{ success, workflow_id, matching_users, user_ids[], message }`. The FE then calls `amp-dispatch-workflow-batch` with the returned `user_ids`. Not used by the scheduled lane. |

### pg_cron

Job `amp_run_due_scheduled_workflows` runs every minute:

```sql
select cron.schedule(
  'amp_run_due_scheduled_workflows',
  '* * * * *',
  $$select fn_amp_run_due_scheduled_workflows();$$
);
```

### Edge Functions

| Slug | verify_jwt | Caller | Replaces |
|---|---|---|---|
| `amp-dispatch-realtime-event` | false | Called from AMP routers on `inngest-event-router-serve` | `dispatch-workflow-trigger` (legacy slug, still deployed for backward compatibility) |
| `amp-dispatch-workflow-batch` | false | `bff_amp_batch_run`, `fn_amp_run_due_scheduled_workflows` | `amp-batch-dispatch` (legacy slug, still deployed for backward compatibility) |

Both renamed slugs were deployed as recreations of the original functions with identical behavior. The Render env var `AMP_REALTIME_DISPATCH_FUNCTION_SLUG` controls which realtime slug amp-*-router / amp-dispatch-realtime-event calls.

### Catch-Up Semantics

If pg_cron is down or backed up, when the scheduler resumes it runs each due trigger **once** and advances `next_run_at` from `now()`, not from the last theoretical occurrence. Missed individual occurrences are not backfilled.
























