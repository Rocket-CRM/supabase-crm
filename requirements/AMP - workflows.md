# Autonomous Marketing Platform (AMP) - Workflows Module

## Business Requirements

### Overview

The AMP Workflows module enables merchants to create automated marketing journeys that respond to customer behavior in real-time. Instead of manually sending campaigns or relying on batch processes, merchants can design visual workflows that automatically guide customers through personalized experiences based on their actions.

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
| **Trigger** | Entry point that starts the workflow | Purchase completed, Form submitted, Tier upgraded |
| **Condition** | Branch based on customer data or behavior | Check tier level, Check purchase history, Check tag |
| **Message** | Send communication to customer | Email, SMS, LINE, Push notification |
| **Wait** | Pause execution for a duration | Wait 3 days, Wait until specific time |
| **Action** | Perform CRM action | Award points, Assign tag, Update field |
| **API Call** | Call external service | Webhook, Third-party integration |
| **Agent** | AI-powered decision or content | Dynamic content, Smart recommendations |

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

---

## Architecture Summary

The AMP Workflows module stores workflow definitions as directed graphs (nodes + edges) and tracks execution via event sourcing. Inngest handles orchestration; Supabase stores definitions and logs.

**Key Design Decisions:**
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

### Architecture: Separation of Concerns

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                              YOUR SYSTEM                                     │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│   ┌─────────────────────────────┐      ┌─────────────────────────────────┐  │
│   │       SUPABASE              │      │         INNGEST CLOUD           │  │
│   │                             │      │                                 │  │
│   │  ┌───────────────────────┐  │      │  ┌───────────────────────────┐  │  │
│   │  │   Database Tables     │  │      │  │   Event Queue             │  │  │
│   │  │   - amp_workflow      │  │      │  │   - Receives events       │  │  │
│   │  │   - amp_workflow_node │  │      │  │   - Routes to functions   │  │  │
│   │  │   - amp_workflow_edge │  │      │  │   - Manages retries       │  │  │
│   │  │   - amp_workflow_log  │  │      │  └───────────────────────────┘  │  │
│   │  └───────────────────────┘  │      │                                 │  │
│   │                             │      │  ┌───────────────────────────┐  │  │
│   │  ┌───────────────────────┐  │      │  │   Scheduler               │  │  │
│   │  │   Database Triggers   │──┼──────┼─▶│   - Tracks wait steps     │  │  │
│   │  │   - wallet_ledger     │  │      │  │   - Resumes after delays  │  │  │
│   │  │   - purchase_ledger   │  │      │  │   - Handles long sleeps   │  │  │
│   │  │   - form_submissions  │  │      │  └───────────────────────────┘  │  │
│   │  └───────────────────────┘  │      │                                 │  │
│   │                             │      └─────────────┬───────────────────┘  │
│   │  ┌───────────────────────┐  │                    │                      │
│   │  │   Edge Function       │◀─┼────────────────────┘                      │
│   │  │   (inngest-serve)     │  │      Calls Edge Function                  │
│   │  │   - Workflow Executor │  │      for each workflow step               │
│   │  │   - Node Handlers     │  │                                           │
│   │  └───────────────────────┘  │                                           │
│   │                             │                                           │
│   └─────────────────────────────┘                                           │
│                                                                              │
└─────────────────────────────────────────────────────────────────────────────┘
```

**Supabase responsibilities:**
- Store workflow definitions (what steps to execute)
- Store execution logs (what happened)
- Fire database triggers when CRM events occur
- Host the Edge Function that contains workflow logic

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
2. **Load definition** - The executor queries Supabase for the workflow graph (nodes + edges)
3. **Find start** - Locates the trigger node (entry point)
4. **Execute step by step** - For each node:
   - Determine node type (condition, message, wait, action)
   - Run the appropriate handler
   - Find the next node(s) using edges
   - Continue until no more nodes
5. **Log everything** - Each step inserts an event to `amp_workflow_log`

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


Step 2: Database Trigger Fires
────────────────────────────────────────────────────────────────────────
PostgreSQL trigger fn_inngest_on_wallet_transaction() runs:
  - Sends HTTP POST to dispatch-workflow-trigger edge function via pg_net
  - Passes: trigger_table, trigger_operation, merchant_id, user_id, record_data


Step 3: Dispatcher Edge Function Processes
────────────────────────────────────────────────────────────────────────
dispatch-workflow-trigger edge function:
  1. Queries amp_workflow_trigger for matching workflows
     - trigger_table = 'wallet_ledger'
     - trigger_operation = 'INSERT'  
     - merchant_id matches
     - is_active = true
     - Checks trigger_conditions against record_data
  2. Filters to only active workflows
  3. For each matching workflow, sends HTTP POST to Inngest Cloud


Step 4: Inngest Receives Event
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


Step 5: Inngest Invokes Executor Edge Function
────────────────────────────────────────────────────────────────────────
Inngest calls your Supabase Edge Function (inngest-serve):
  - POST /functions/v1/inngest-serve
  - Contains event payload and run metadata


Step 6: Workflow Executor Runs
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
  6. Logs "execution_completed" when done


Step 7: Results Persisted
────────────────────────────────────────────────────────────────────────
All steps logged to amp_workflow_log for:
  - Audit trail
  - Funnel analytics
  - Debugging
  - User journey tracking
```

### Architecture Diagram (Updated)

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                              YOUR SYSTEM                                     │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│   ┌─────────────────────────────────────────────────────────────────────┐   │
│   │                         SUPABASE                                     │   │
│   │                                                                      │   │
│   │  ┌───────────────────┐     ┌─────────────────────────────────────┐  │   │
│   │  │  Database Tables  │     │        Edge Functions               │  │   │
│   │  │  - wallet_ledger  │     │                                     │  │   │
│   │  │  - amp_workflow   │     │  ┌─────────────────────────────┐    │  │   │
│   │  │  - amp_workflow_  │     │  │ dispatch-workflow-trigger   │    │  │   │
│   │  │    trigger        │     │  │ - Looks up matching triggers│    │  │   │
│   │  │  - amp_workflow_  │     │  │ - Sends events to Inngest   │    │  │   │
│   │  │    log            │     │  └──────────────┬──────────────┘    │  │   │
│   │  └────────┬──────────┘     │                 │                   │  │   │
│   │           │                │  ┌──────────────▼──────────────┐    │  │   │
│   │  ┌────────▼──────────┐     │  │ inngest-serve               │◀───┼───┼───┐
│   │  │  DB Trigger       │     │  │ - Workflow executor         │    │  │   │
│   │  │  (pg_net)         │─────┼─▶│ - Node handlers             │    │  │   │
│   │  │                   │     │  │ - Calls channel functions   │    │  │   │
│   │  └───────────────────┘     │  └──────────────┬──────────────┘    │  │   │
│   │                            │                 │                   │  │   │
│   │                            │  ┌──────────────▼──────────────┐    │  │   │
│   │                            │  │ send-line-message           │    │  │   │
│   │                            │  │ send-sms-8x8                │    │  │   │
│   │                            │  │ (channel functions)         │    │  │   │
│   │                            │  └─────────────────────────────┘    │  │   │
│   │                            │                                     │  │   │
│   └────────────────────────────┴─────────────────────────────────────┘  │   │
│                                                                          │   │
└──────────────────────────────────────────────────────────────────────────┘   │
                                                                               │
┌──────────────────────────────────────────────────────────────────────────┐   │
│                          INNGEST CLOUD                                   │   │
│                                                                          │   │
│  ┌────────────────────┐    ┌────────────────────────────────────────┐   │   │
│  │   Event Queue      │    │   Scheduler                            │   │   │
│  │   - Receives       │    │   - Tracks wait steps                  │───┘   │
│  │     amp/workflow.  │    │   - Resumes after delays               │       │
│  │     trigger events │    │   - Handles retries                    │       │
│  └────────────────────┘    └────────────────────────────────────────┘       │
│                                                                              │
└──────────────────────────────────────────────────────────────────────────────┘
```

### Node Handler Logic

The Edge Function contains handlers for each node type:

**Trigger Node**
```
Purpose: Entry point, captures initial event data
Logic: Logs the trigger event, extracts user_id and merchant_id
Output: Passes trigger_data to next node
```

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
Purpose: Perform CRM operation or send message
Logic:
  1. Read action_type and channel from node_config
  2. Substitute variables in content ({{user.first_name}}, etc.)
  3. Execute based on type:
     
     LINE Message (channel: "line"):
       - Call send-line-message edge function
       - Supports text, flex, image, template messages
       - Logs message_id for tracking
     
     SMS (channel: "sms"):
       - Call send-sms-8x8 edge function
       - Substitutes variables in message
     
     Award Points (action_type: "award_points"):
       - Insert to wallet_ledger
       - Supports amount and currency_type
     
     Assign Tag (action_type: "assign_tag"):
       - Upsert to user_tags
       - Links tag_id to user
     
     API Call (action_type: "api_call"):
       - Makes HTTP request to external URL
       - Supports GET/POST/PUT/DELETE
       - Variable substitution in URL and body
  
  4. Log result with status (executed/sent/failed)
Output: Continues to next node
```

**Action Node Config Examples:**

```json
// LINE Text Message
{
  "channel": "line",
  "messages": [{
    "type": "text",
    "text": "Hi {{user.first_name}}! You earned {{trigger.amount}} points!"
  }]
}

// LINE Flex Message
{
  "channel": "line",
  "messages": [{
    "type": "flex",
    "altText": "Your reward",
    "contents": { /* flex message JSON */ }
  }]
}

// SMS
{
  "channel": "sms",
  "message": "Hi {{user.first_name}}, your code is {{trigger.code}}"
}

// Award Points
{
  "action_type": "award_points",
  "amount": 100,
  "currency_type": "points"
}

// Assign Tag
{
  "action_type": "assign_tag",
  "tag_id": "uuid-of-tag"
}

// Webhook/API Call
{
  "action_type": "api_call",
  "url": "https://api.example.com/notify",
  "method": "POST",
  "body": { "user_id": "{{user.id}}", "event": "workflow_triggered" }
}
```

### Database Trigger Implementation

The PostgreSQL trigger uses `pg_net` extension to call an edge function (not Inngest directly):

```
Trigger Function Logic (fn_inngest_on_wallet_transaction):
────────────────────────────────────────────────────────────────────────
1. When INSERT happens on wallet_ledger

2. Check if transaction_type = 'earn'

3. Send HTTP POST to dispatch-workflow-trigger edge function via pg_net:
   - trigger_table: 'wallet_ledger'
   - trigger_operation: 'INSERT'
   - merchant_id, user_id, record_id
   - record_data: {amount, currency, transaction_type, source_type, description}

4. Return NEW to complete the trigger (non-blocking, pg_net is async)
```

```
Dispatcher Edge Function Logic (dispatch-workflow-trigger):
────────────────────────────────────────────────────────────────────────
1. Receive payload from pg_net

2. Query amp_workflow_trigger to find workflows matching:
   - Same table (wallet_ledger)
   - Same operation (INSERT)
   - Same merchant_id
   - Both trigger and workflow are active
   - Optional: trigger_conditions match record_data

3. For each matching workflow:
   - Build Inngest event payload
   - Send HTTP POST to Inngest Cloud (https://inn.gs/e/{EVENT_KEY})

4. Return summary of dispatched workflows
```

**Why Edge Function in the Middle?**
- ✅ Secrets (INNGEST_EVENT_KEY) stored in env vars, not database
- ✅ Full logging in Supabase dashboard for debugging
- ✅ Easy to modify routing logic without database migrations
- ✅ Can add rate limiting, batching, filtering
- ⚠️ Slight latency increase (~50-200ms) but pg_net is async anyway

### Inngest Configuration

**Required secrets in Supabase Edge Functions:**

| Edge Function | Required Env Vars |
|---------------|-------------------|
| `dispatch-workflow-trigger` | `INNGEST_EVENT_KEY`, `SUPABASE_URL`, `SUPABASE_SERVICE_ROLE_KEY` |
| `inngest-serve` | `INNGEST_SIGNING_KEY`, `SUPABASE_URL`, `SUPABASE_SERVICE_ROLE_KEY` |
| `send-line-message` | `SUPABASE_URL`, `SUPABASE_SERVICE_ROLE_KEY` |
| `send-sms-8x8` | `SUPABASE_URL`, `SUPABASE_SERVICE_ROLE_KEY` |

**Edge Function JWT Settings:**

| Edge Function | JWT Verification | Why |
|---------------|------------------|-----|
| `dispatch-workflow-trigger` | **Disabled** | Called from pg_net (no JWT) |
| `inngest-serve` | **Disabled** | Inngest authenticates via signing key |
| `send-line-message` | Enabled | Called from inngest-serve with service key |
| `send-sms-8x8` | Disabled | Already deployed this way |
| `line-webhook` | **Disabled** | Called from LINE servers (no JWT) |

**Serve paths:**
- `/functions/v1/dispatch-workflow-trigger` - Trigger dispatcher
- `/functions/v1/inngest-serve` - Workflow executor
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
- Failed steps logged to amp_workflow_log with error_message
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
6. Logs to amp_workflow_log with status 'sent'

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

### Current Implementation Status

| Component | Status | Notes |
|-----------|--------|-------|
| **Edge Functions** | | |
| `inngest-serve` | ✅ Deployed | Workflow executor with full node handlers |
| `dispatch-workflow-trigger` | ✅ Deployed | Trigger dispatcher (needs JWT disabled) |
| `send-line-message` | ✅ Deployed | LINE Messaging API integration |
| `send-sms-8x8` | ✅ Existing | SMS via 8x8 |
| `line-webhook` | ✅ Deployed | LINE webhook receiver (needs JWT disabled) |
| **Database** | | |
| Database Trigger (wallet_ledger) | ✅ Active | Calls dispatch-workflow-trigger |
| amp_workflow_trigger lookup | ✅ Working | Dynamic workflow routing |
| **Node Types** | | |
| Trigger/Entry Node | ✅ Working | Logs entry, passes context |
| Condition Node | ✅ Working | Queries user data, evaluates operators |
| Wait Node | ✅ Working | Inngest handles long waits via step.sleep |
| Action Node - LINE | ✅ Working | Calls send-line-message with variable substitution |
| Action Node - SMS | ✅ Working | Calls send-sms-8x8 |
| Action Node - Award Points | ✅ Working | Inserts to wallet_ledger |
| Action Node - Assign Tag | ✅ Working | Upserts to user_tags |
| Action Node - API Call | ✅ Working | Makes HTTP requests to external URLs |
| **Pending** | | |
| Webhook Handlers | ⬜ Not started | For delivery/open tracking |
| Additional Triggers | ⬜ Not started | purchase_ledger, forms, etc. |
| Analytics Views | ⬜ Not started | v_amp_workflow_performance, v_amp_workflow_action_funnel |

### Required Setup Steps

1. **Disable JWT verification** on these edge functions:
   - `dispatch-workflow-trigger`
   - `inngest-serve`
   - `line-webhook`

2. **Set environment variables** in Supabase Dashboard → Edge Functions → Secrets:
   - `INNGEST_EVENT_KEY` - Your Inngest event key (for dispatch-workflow-trigger)
   - `INNGEST_SIGNING_KEY` - Your Inngest signing key (for inngest-serve)

---

## Tables Overview

| Table | Purpose | Rows |
|-------|---------|------|
| `amp_workflow` | Workflow definitions | 1 per workflow |
| `amp_workflow_node` | Node definitions | N per workflow |
| `amp_workflow_edge` | Node connections | M per workflow |
| `amp_workflow_trigger` | CRM event → workflow routing | K per workflow |
| `amp_workflow_log` | Event sourcing execution log | Many per execution |

---

## Phase 1: Workflow Definition Tables

### 1.1 `amp_workflow`

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

### 1.2 `amp_workflow_node`

```sql
CREATE TABLE amp_workflow_node (
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

CREATE INDEX idx_amp_workflow_node_workflow ON amp_workflow_node(workflow_id);
CREATE INDEX idx_amp_workflow_node_merchant ON amp_workflow_node(merchant_id);
```

**Node Types:** `trigger`, `condition`, `message`, `wait`, `api_call`, `action`, `agent`

**Node Config Examples:**
- `condition`: `{query: {table, field, operator, value}}`
- `message`: `{channel: "email", template_id: "...", subject: "..."}`
- `wait`: `{duration: "3d"}`
- `action`: `{action_type: "award_points", params: {amount: 100}}`

### 1.3 `amp_workflow_edge`

```sql
CREATE TABLE amp_workflow_edge (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  workflow_id UUID NOT NULL,
  merchant_id UUID NOT NULL,
  from_node_id UUID NOT NULL,
  to_node_id UUID NOT NULL,
  source_handle TEXT DEFAULT 'default',
  edge_label TEXT,
  created_at TIMESTAMPTZ DEFAULT now(),
  
  CONSTRAINT fk_workflow FOREIGN KEY (workflow_id) REFERENCES amp_workflow(id) ON DELETE CASCADE,
  CONSTRAINT fk_from_node FOREIGN KEY (from_node_id) REFERENCES amp_workflow_node(id) ON DELETE CASCADE,
  CONSTRAINT fk_to_node FOREIGN KEY (to_node_id) REFERENCES amp_workflow_node(id) ON DELETE CASCADE,
  CONSTRAINT fk_merchant FOREIGN KEY (merchant_id) REFERENCES merchant(id)
);

CREATE INDEX idx_amp_workflow_edge_workflow ON amp_workflow_edge(workflow_id);
CREATE INDEX idx_amp_workflow_edge_from ON amp_workflow_edge(from_node_id);
```

**Source Handles:** `default`, `true`, `false` (for condition branching)

### 1.4 `amp_workflow_trigger`

```sql
CREATE TABLE amp_workflow_trigger (
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

CREATE INDEX idx_amp_workflow_trigger_table ON amp_workflow_trigger(trigger_table, trigger_operation);
CREATE INDEX idx_amp_workflow_trigger_merchant ON amp_workflow_trigger(merchant_id);
```

**Trigger Types:** `purchase_completed`, `tier_upgraded`, `points_earned`, `form_submitted`, `tag_assigned`, `custom`

---

## Phase 2: Event Log Table (Event Sourcing)

### 2.1 `amp_workflow_log`

Single table for all execution events. INSERT per status change.

```sql
CREATE TABLE amp_workflow_log (
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
  CONSTRAINT fk_node FOREIGN KEY (node_id) REFERENCES amp_workflow_node(id)
);

-- Query indexes
CREATE INDEX idx_amp_workflow_log_merchant ON amp_workflow_log(merchant_id);
CREATE INDEX idx_amp_workflow_log_workflow ON amp_workflow_log(workflow_id);
CREATE INDEX idx_amp_workflow_log_run ON amp_workflow_log(inngest_run_id);
CREATE INDEX idx_amp_workflow_log_event_type ON amp_workflow_log(event_type);
CREATE INDEX idx_amp_workflow_log_user ON amp_workflow_log(user_id);
CREATE INDEX idx_amp_workflow_log_created ON amp_workflow_log(created_at DESC);
CREATE INDEX idx_amp_workflow_log_external_msg ON amp_workflow_log(external_message_id) 
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
      SELECT inngest_run_id FROM amp_workflow_log 
      WHERE event_type IN ('execution_completed', 'execution_failed', 'execution_exited')
    )
  ) as in_flight
FROM amp_workflow w
LEFT JOIN amp_workflow_log l ON l.workflow_id = w.id
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
FROM amp_workflow_log
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

Apply to: `amp_workflow`, `amp_workflow_node`, `amp_workflow_edge`, `amp_workflow_trigger`, `amp_workflow_log`

---

## Phase 6: Database Triggers (CRM Events)

```sql
CREATE OR REPLACE FUNCTION fn_dispatch_amp_workflow_event()
RETURNS TRIGGER AS $$
BEGIN
  -- Find matching workflow triggers and dispatch to Inngest
  -- Implementation calls Inngest HTTP endpoint
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Apply to CRM tables
CREATE TRIGGER trg_amp_workflow_on_purchase
AFTER INSERT ON purchase_ledger
FOR EACH ROW EXECUTE FUNCTION fn_dispatch_amp_workflow_event();

CREATE TRIGGER trg_amp_workflow_on_wallet
AFTER INSERT ON wallet_ledger
FOR EACH ROW EXECUTE FUNCTION fn_dispatch_amp_workflow_event();
```

---

## Dashboard Queries

### Workflow Metrics (Top Section)

```sql
-- (1) # of workflow triggers
SELECT COUNT(*) 
FROM amp_workflow_log 
WHERE event_type = 'execution_started' 
  AND workflow_id = $1 
  AND created_at BETWEEN $2 AND $3;

-- (2) # unique users entered
SELECT COUNT(DISTINCT user_id) 
FROM amp_workflow_log 
WHERE event_type = 'execution_started' 
  AND workflow_id = $1;

-- (4) # completed
SELECT COUNT(*) 
FROM amp_workflow_log 
WHERE event_type = 'execution_completed' 
  AND workflow_id = $1;

-- (5) Currently in flight
SELECT COUNT(DISTINCT inngest_run_id)
FROM amp_workflow_log
WHERE workflow_id = $1
  AND event_type = 'execution_started'
  AND inngest_run_id NOT IN (
    SELECT inngest_run_id FROM amp_workflow_log 
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
FROM amp_workflow_log
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
FROM amp_workflow_log l
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
├── 008_create_amp_workflow_log.sql
├── 009_create_amp_workflow_rls.sql
├── 010_create_amp_workflow_views.sql
├── 011_create_amp_workflow_functions.sql
├── 012_create_amp_workflow_triggers.sql
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
































