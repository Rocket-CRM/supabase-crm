# AMP — AI Decisioning

## What This Document Covers

The AI decisioning layer for AMP, including the agentic architecture. How the AI agent makes per-user marketing decisions using real-time data, available loyalty actions, campaign performance, and constraints — via an MCP server for tools/resources and Inngest AgentKit for the agentic loop.

> **Post-Confluent:** Outcome attribution is written by `outcome-{purchase,wallet}-router` on `inngest-event-router-serve` (replaces Kafka `OutcomeAttributionConsumer`). RisingWave section below still mentions Confluent Kafka sources — **confirm with ops** whether those sources remain after Confluent deactivation.

For rule-based workflows, audiences, conditions, actions, and the event pipeline, see `AMP - Rule Based.md`. For the Redis cache layer on config reads, see `AMP - Cache Layer.md`.

---

## Vision

Unlike traditional CDPs (which just move data) or traditional Marketing Automation (which relies on static rules), this system uses **Real-Time Stream Processing** combined with **Agentic AI Reasoning** to make decisions.

**Core Philosophy:** "Don't just predict scores. Understand context, reason about intent, and generate actions."

| Dimension | Traditional CDP / Hightouch | AMP AI Decisioning |
| :--- | :--- | :--- |
| **Data Freshness** | **Batch** (15m–1hr latency). "Zero Copy" relies on slow Warehouse queries. | **Streaming** (ms latency). RisingWave maintains live state. |
| **Context** | **Snapshot**. "User has 500 points." | **Narrative**. "User has 500 points AND just complained about shipping." |
| **Decision Logic** | **Discriminative**. "If Score > 0.8, Send Template A." | **Generative**. "Score is 0.8, but context implies 'Fit Anxiety'. Send Size Guide." |
| **Asset Selection** | **Hard Rules**. "Category = Shoes". | **Semantic Search**. "Find rewards that match 'Camping Vibe'." |

---

## Architecture Overview

### How It Works

1. `inngest-amp-serve` (Supabase Edge Function) walks a workflow graph and hits an agent node
2. `inngest-amp-serve` reads `amp_agent` for deliberation settings (max_cycles, wait caps), then invokes the agent service on Render via Inngest `step.invoke`
3. The agent service **pre-fetches all read data** directly (no AI tool calls). All config reads go through Upstash Redis cache (`amp-cache`) first — Postgres only on cache miss. See `AMP - Cache Layer.md`.
   - User context from RisingWave (persistent connection pool)
   - Agent config + actions from `fn_get_agent_config_cached` → Redis (10-min TTL)
   - Eligible actions from `fn_get_eligible_agent_actions` DB function (agent scope + user eligibility)
   - Goal performance from `fn_get_agent_performance_cached` → Redis (10-min TTL)
   - Constraints from `fn_get_constraint_usage_cached` → Redis (10-min TTL)
   - Cost normalization from `fn_get_cost_normalization_cached` → Redis (30-min TTL)
   - Action type schemas from `fn_get_action_type_config_cached` → Redis (24h TTL)
4. All data is **embedded in the prompt** — the AI doesn't need to fetch anything
5. AgentKit sends the rich prompt to Groq/Llama 4 Maverick with only **action tool** definitions
6. Groq reasons with the pre-fetched data and decides ACT / WAIT / SKIP:
   - If ACT → calls action tools via MCP (same process, localhost). Action tools validate `agent_id` scope before executing.
   - If WAIT/SKIP → returns structured JSON decision (guaranteed by `response_format: json_object`)
7. `inngest-amp-serve` gets the result back, injects into workflow context as `{{agent.*}}` variables
8. Routes: action taken → true handle, no action → false handle

### Component Diagram

```
inngest-amp-serve (Supabase Edge Function — workflow executor)
    │
    │ step.invoke("marketing-decision-agent")
    │ Sends: user_id, merchant_id, workflow_id, agent_config, deliberation_history
    ▼
amp-ai-service (Render — Node.js, single service)
    │
    │ STEP 1: PRE-FETCH (code, not AI — via amp-cache Redis)
    │   data-fetchers.ts called directly (same process):
    │     fetchUserContext(user_id)           → RisingWave pool
    │     fetchAgentConfig(agent_id)          → amp-cache Redis (10m TTL)
    │     fetchEligibleAgentActions(agent_id) → amp-cache → DB function on miss
    │     fetchAgentGoalPerformance(agent_id) → amp-cache Redis (10m TTL)
    │     fetchConstraints(agent_id, user_id) → amp-cache Redis (10m TTL)
    │     fetchCostNormalization(merchant_id) → amp-cache Redis (30m TTL)
    │
    │ STEP 2: BUILD PROMPT with all data embedded
    │
    │ STEP 3: AgentKit → Groq (AI only calls ACTION tools)
    │
    ├──► Groq API (Llama 4 Maverick)
    │      - Receives: prompt with ALL context + action tool definitions
    │      - Returns: structured JSON (response_format: json_object)
    │      - Only calls action tools if ACT decision
    │
    └──► MCP server (same Render process, localhost /mcp)
           │
           │ ACTION TOOLS (validate agent_id scope, then execute):
           │   award_points       → fn_execute_amp_action RPC
           │   award_tickets      → fn_execute_amp_action RPC
           │   assign_tag         → fn_execute_amp_action RPC
           │   remove_tag         → fn_execute_amp_action RPC
           │   assign_persona     → fn_execute_amp_action RPC
           │   assign_earn_factor → fn_execute_amp_action RPC
           │   submit_form        → fn_execute_amp_action RPC
           │   add_to_audience    → fn_execute_amp_action RPC
           │   remove_from_audience → fn_execute_amp_action RPC
           │   send_line_message  → send-line-message edge fn
           │   send_sms           → send-sms-8x8 edge fn
           │
           │ READ TOOLS (for 3rd party clients only):
           │   get_user_context, list_agent_actions,
           │   get_agent_goal_performance, get_constraints, etc.
           │
           │ Same data-fetchers.ts functions power both paths.
```

### Internal (AMP) vs External (n8n)

```
INTERNAL                              EXTERNAL
────────────────────────              ────────────────────────
inngest-amp-serve                     n8n workflow
    │                                     │
    │ step.invoke to agent service        │ n8n AI agent node
    ▼                                     ▼
AgentKit (our system instruction)     n8n's own LLM + system instruction
    │                                     │
    │ MCP resources + tools               │ MCP resources + tools
    ▼                                     ▼
crm-loyalty-actions ◄────── same MCP server, same auth, same constraints
```

The MCP server is a stateless tool/resource layer. For internal use, AgentKit on Render orchestrates the Groq loop. For external use, the client brings their own AI. Both call the same MCP server.

---

## Component 1: MCP Server (`crm-loyalty-actions`)

**Deployed:** Merged into `amp-ai-service` Render service (v4.0.0, Node.js). Previously a Supabase Edge Function — migrated for persistent connection pooling and zero cold starts.

**Endpoint:** `https://amp-ai-service.onrender.com/mcp`

**Protocol:** MCP over Streamable HTTP (JSON-RPC 2.0)

**SDK:** `@modelcontextprotocol/sdk@1.25.3` + Express + Zod v4

**Key change (v15):** `guardrail_config` on `action_registry / amp_agent` renamed to `action_constraints`. `get_constraints` tool signature changed from `(workflow_id, user_id)` to `(agent_id, user_id)` — reads from pre-computed `amp_constraint_usage` cache table instead of live log scans. Resource template updated from `workflow://{workflow_id}/constraints` to `agent://{agent_id}/constraints`.

Exposes read-only **resources** for AI context and **tools** for actions. No AI or LLM inside it. See `docs/AMP - MCP for Loyalty Actions.md` for full details on every resource and tool.

### Resources (read-only context)

| Resource URI Template | Source | Purpose |
|---|---|---|
| `user://{user_id}/context` | RisingWave: `user_stats` + `user_chronology` | User stats (LTV, purchases, balance) + last 20 events |
| `agent://{agent_id}/actions` | `amp_agent` + `action_registry / amp_agent` + filtered merchant entities | **Agent-scoped** actions with variable ranges, `action_constraints`, eligibility. Internal agents use this. |
| `agent://{agent_id}/goal-performance` | `amp_agent_performance_summary` | Outcome conversion rates, per-action effectiveness |
| `agent://{agent_id}/constraints?user_id={user_id}` | `amp_agent.constraints` + `amp_constraint_usage` cache | Agent-level frequency/budget limits with current usage |
| `merchant://{merchant_id}/actions` | Supabase: tag_master, persona_master, ticket_type, earn_factor, form_templates | Full merchant catalog (external clients only — n8n, Claude Desktop) |
| `workflow://{workflow_id}/performance` | Supabase: workflow_log aggregation | Campaign execution metrics |

### Read Tools (context for AI)

AgentKit only discovers **tools**, not MCP resources. So all read data is exposed as both resources (for external MCP clients) and tools (for AgentKit/Groq).

| Tool | Purpose | Used by |
|---|---|---|
| `get_user_context` | Real-time user stats + last 20 events | Internal + external |
| `list_agent_actions` | **Agent-scoped** — returns only the actions this agent is configured to use, with variable ranges, `action_constraints`, eligibility, and resolved entity UUIDs | Internal agents only |
| `get_agent_performance` | Aggregate performance across all workflows using this agent — per-action-type effectiveness, cost totals, last 7 days | Internal agents only |
| `list_available_actions` | Full merchant catalog (unfiltered) — all tags, personas, earn factors, tickets, forms | External clients (n8n) |
| `get_constraints` | Agent-level frequency/budget limits with current usage from cache. Input: `(agent_id, user_id)`. Returns: constraint list with headroom, cooldown status, scheduling controls. | Internal + external |
| `get_campaign_performance` | Workflow-level execution metrics for last 7 days | Internal + external |

### Action Tools

| Tool | Executes | Cost |
|---|---|---|
| `award_points` | `chokepoint_post_wallet_transaction` RPC | Proportional to amount |
| `award_tickets` | `chokepoint_post_wallet_transaction` RPC (currency=ticket) | Per ticket type |
| `assign_tag` | `user_tags` upsert | Zero |
| `remove_tag` | `user_tags` delete | Zero |
| `assign_persona` | `user_accounts` update | Zero |
| `assign_earn_factor` | `earn_factor_user` insert | Zero |
| `send_line_message` | `send-line-message` edge fn | Per message |
| `send_sms` | `send-sms-8x8` edge fn | Per message |
| `submit_form` | `submit_form_response` RPC | Zero |
| `add_to_audience` | `fn_add_to_audience` RPC | Zero |
| `remove_from_audience` | `fn_remove_from_audience` RPC | Zero |

Every action tool validates parameters, executes via existing Supabase RPCs/tables, and logs to `workflow_log` when `workflow_id` is provided.

### Agent-Scoped Action Filtering (v10)

**The problem:** Previously, the AI called `list_available_actions(merchant_id)` which returned the merchant's entire catalog — every tag, persona, earn factor, ticket type, and form ever created. The only constraint was a text instruction in the system prompt saying "only use actions from your allowed list." This was prompt engineering — the AI had full visibility into things it shouldn't use, and hallucination or overstep was possible.

**The solution:** `list_agent_actions(agent_id, user_id)` replaces `list_available_actions` for internal agent calls. The MCP server filters by both agent scope AND user eligibility:

1. Queries `amp_agent` by ID → gets `merchant_id` and `allowed_action_types`
2. Queries `action_registry / amp_agent` where `agent_id` matches and `is_enabled = true` → gets the specific configured actions
3. For each agent action, resolves only the referenced entities:
   - If `variable_config.tag_id` is a specific UUID → fetches only that tag
   - If no specific entity (AI picks) → fetches the merchant's catalog for that entity type
   - Same logic for personas, earn factors, ticket types, forms
4. Returns: agent config + allowed actions with variable ranges + guardrails + eligibility conditions + filtered entity UUIDs

**What the AI sees:** Only the actions the marketer explicitly configured for this agent. If the agent has one `assign_tag` action with `tag_id: "abc"`, the AI sees one tag — not the merchant's 50 tags. The constraint is structural, not instructional.

**Backward compatibility:** `list_available_actions` (merchant-scoped) remains for external MCP clients (n8n, Claude Desktop) that bring their own AI. Internal agents use `list_agent_actions`; external clients use `list_available_actions`.

**Agent performance learning:** `get_agent_performance(agent_id)` aggregates across all workflows that reference this agent (found via `amp_workflow_node.node_config->>'agent_config_id'`). Returns per-action-type effectiveness so the AI can prefer historically successful action types. This is cross-workflow learning — an agent used in 5 different campaigns builds a shared effectiveness profile.

---

## Component 2: Agent Service + MCP Server (`amp-ai-service`)

**Deployment:** Render web service (Node.js), region: Singapore. Hosts both the AI agent service AND the MCP server in one process.

**Repo:** `Rocket-CRM/amp-ai-service`

**Render service ID:** `srv-d6db3s4tgctc73f1fni0`

**URL:** `https://amp-ai-service.onrender.com`

**Routes:**
- `/api/inngest` — Inngest function endpoint (agent deliberation)
- `/mcp` — MCP server for external clients (n8n, Claude Desktop)
- `/health` — Health check

**Status:** Live v3.0.0

### How It Works

Uses Inngest AgentKit to create a marketing decision agent:

```typescript
const model = openai({
  model: "meta-llama/llama-4-maverick-17b-128e-instruct",
  baseUrl: "https://api.groq.com/openai/v1/",
  apiKey: process.env.GROQ_API_KEY,
});

const marketingAgent = createAgent({
  name: "Marketing Decision Agent",
  system: SYSTEM_INSTRUCTION,
  model,
  mcpServers: [{
    name: "crm",
    transport: { type: "streamable-http", url: MCP_SERVER_URL },
  }],
});
```

AgentKit handles:
- Connecting to MCP server (auto-discovers resources + tools)
- Passing tool definitions to Groq in OpenAI-compatible format
- Executing tool calls when Groq requests them
- Feeding results back to Groq
- Looping until Groq returns a final answer
- Durable execution via Inngest (retries, state persistence)

### Model Configuration

Uses Groq's OpenAI-compatible endpoint with `baseUrl`. Any OpenAI-compatible provider works:
- Groq cloud: `baseUrl: "https://api.groq.com/openai/v1/"`
- Self-hosted Ollama: `baseUrl: "http://your-server:11434/v1/"`
- Self-hosted vLLM: `baseUrl: "http://gpu-server:8000/v1/"`

Model is configurable via `LLM_MODEL` and `LLM_BASE_URL` environment variables.

### Inngest Function

The agent service registers one Inngest function: `marketing-decision-agent`, triggered by `amp/agent.decide` events. `inngest-amp-serve` invokes this via `step.invoke`.

### Environment Variables

| Variable | Value |
|----------|-------|
| `GROQ_API_KEY` | Groq API key |
| `LLM_BASE_URL` | `https://api.groq.com/openai/v1/` |
| `LLM_MODEL` | `meta-llama/llama-4-maverick-17b-128e-instruct` |
| `MCP_SERVER_URL` | `https://wkevmsedchftztoolkmi.supabase.co/functions/v1/crm-loyalty-actions` |
| `INNGEST_SIGNING_KEY` | From Inngest Cloud |
| `INNGEST_EVENT_KEY` | From Inngest Cloud |

---

## Component 3: Workflow Executor (`inngest-amp-serve`)

**Deployed:** Supabase Edge Function v61, project `wkevmsedchftztoolkmi`

### Action Routing

Rule-based action nodes call `fn_execute_amp_action` (PostgreSQL function) directly — no MCP overhead. The DB function handles validation, execution, logging, and cost tracking for all DB-native actions. Variable substitution (`{{user.firstname}}`, etc.) happens in `inngest-amp-serve` before calling the RPC.

Messaging and external calls that require HTTP stay inline in `inngest-amp-serve`.

| Action | Route |
|---|---|
| award_points, award_tickets, award_currency | `fn_execute_amp_action` RPC (direct) |
| assign_tag, remove_tag | `fn_execute_amp_action` RPC (direct) |
| assign_persona | `fn_execute_amp_action` RPC (direct) |
| assign_earn_factor | `fn_execute_amp_action` RPC (direct) |
| submit_form | `fn_execute_amp_action` RPC (direct) |
| add_to_audience, remove_from_audience | `fn_execute_amp_action` RPC (direct) |
| send_line (text + flex) | Inline → `send-line-message` edge function |
| send_sms | Inline → `send-sms-8x8` edge function |
| api_call / webhook | Inline → external HTTP |
| agent node | Deliberation loop via `step.invoke` to agent service. Agent service calls MCP for tool discovery + execution. |

> **Note (v61):** MCP server (`crm-loyalty-actions`) is now exclusively used by AI agents and external clients (n8n, Claude Desktop). Rule-based workflow actions bypass MCP entirely, calling `fn_execute_amp_action` directly. Both paths share the same underlying DB functions (`chokepoint_post_wallet_transaction`, `fn_add_to_audience`, etc.), so behavior is identical — the difference is only in compute cost (1 edge function instead of 2).

---

## Component 4: Real-Time State Engine (RisingWave)

**Instance:** RisingWave Cloud, ap-southeast-1

**Connected to (ops — verify post-Confluent):** historically Confluent Kafka topics `crm.public.wallet_ledger` + `crm.public.purchase_ledger`. Confirm RisingWave source wiring is still live.

**Materialized Views:**

| View | Purpose | Queried by |
|------|---------|------------|
| `unified_event_stream` | Normalizes wallet + purchase CDC into one stream | Feeds downstream views |
| `event_chronology` | Last 20 events per user, ranked | Feeds user_chronology |
| `user_stats` | Aggregated metrics per user (LTV, purchases, balance) | MCP resource `user://{user_id}/context` |
| `user_chronology` | Single row per user with `history` JSON array | MCP resource `user://{user_id}/context` |

See `docs/AMP - risingwave-setup.md` and `docs/risingwave-setup.sql` for full SQL and setup details.

---

## Component 5: Goal & Objective Configuration

### Agent Node Config (`amp_workflow_node.node_config`)

Agent nodes reference a reusable `amp_agent` by ID:

```json
{ "agent_config_id": "uuid-of-reusable-agent" }
```

When `inngest-amp-serve` hits an agent node, it reads `agent_config_id`, fetches the full `amp_agent` row, and passes it to the agent service. The agent's `objective`, `tone`, `context_hint`, and `allowed_action_types` all come from the `amp_agent` entity — not from inline node config.

The agent service then passes `agent_id` to the MCP server via `list_agent_actions(agent_id)`, which returns only the actions the marketer configured for this agent. The AI never needs to know the merchant_id for action discovery — it's resolved server-side from the agent record.

**Objective values:** `re_engage`, `drive_purchase`, `redeem_points`, `tier_upgrade`, `win_back`, `upsell`

**Tone values:** `urgent`, `friendly`, `exclusive`, `celebratory`

These are stored on `amp_agent.objective` and `amp_agent.tone`. Passed to Groq as part of the user message.

---

## Component 6: Constraint Configuration

### Agent-Level Constraints

Constraints live exclusively on `amp_agent.constraints` (JSONB array). They apply to the agent across all workflows that use it. Each rule: `"No more than [limit] [metric] per [scope] per [time_window]"`.

```json
[
  { "metric": "actions", "limit": 3, "scope": "per_user", "time_window": "per_week" },
  { "metric": "points",  "limit": 500, "scope": "per_user", "time_window": "per_month" },
  { "metric": "cost",    "limit": 1000, "scope": "per_agent", "time_window": "per_month" }
]
```

**Metric options:**

| Metric | What it counts | Computed from |
|---|---|---|
| `actions` | Any successful action | COUNT `event_type='action_executed'` AND `status='executed'` |
| `points` | Points awarded | SUM `cost` WHERE `action_type IN ('award_points','award_currency')` AND `currency='points'` |
| `tickets` | Tickets awarded | SUM `cost` WHERE `action_type IN ('award_tickets','award_currency')` AND `currency='ticket'` |
| `messages` | LINE + SMS sent | COUNT WHERE `action_type IN ('send_line_message','send_sms')` |
| `cost` | Normalized cost | SUM `cost` from `workflow_log` |

**Scope options:** `per_user` (per individual user), `per_agent` (total across all users for this agent)

**Time window options:** `per_day` (rolling 24h), `per_week` (rolling 7d), `per_month` (rolling 30d)

### Constraint Usage Cache (`amp_constraint_usage`)

Pre-computed usage table refreshed every 10 minutes by `fn_refresh_constraint_usage` (pg_cron). The agent service reads from this table via `fn_get_constraint_usage_cached` — Redis cache (10-min TTL) in front, no live log scans, no direct Postgres reads on the hot path. See `AMP - Cache Layer.md`.

```
amp_constraint_usage
  agent_id       → FK to amp_agent
  scope          → 'per_user' | 'per_agent'
  user_id        → populated for per_user, NULL for per_agent
  metric         → 'actions' | 'points' | 'tickets' | 'messages' | 'cost'
  time_window    → 'per_day' | 'per_week' | 'per_month'
  current_value  → pre-computed count/sum
  window_start   → rolling window start timestamp
  computed_at    → last refresh timestamp (stale >10min is still safe — conservative)
```

Rows older than 32 days are automatically cleaned up by the refresh function.

### Scheduling Controls

`cooldown_hours`, `quiet_hours`, `blackout_dates` live at **both** levels:

- **Rule-based nodes** use `amp_workflow.config` values.
- **Agent nodes** use `amp_agent` values. The agent's scheduling settings always take precedence over workflow-level settings for agent nodes.

### Action-Level Constraints (`action_registry / amp_agent.action_constraints`)

Per-action execution limits — enforced at action-tool level, not by the constraint cache. These are guardrails on a single tool call (e.g., can't award more than 500 points in one execution):

```json
{ "max_amount_per_execution": 500, "budget_limit": 1000, "budget_window": "per_month" }
```

### Cost Tracking

`workflow_log.cost` column — populated by every MCP action tool on execution. Costs:

| Action | Cost |
|---|---|
| `award_points` | 1 per point (cost = amount) |
| `award_tickets` | 1 per ticket (cost = amount) |
| `send_line_message` | 1 per message |
| `send_sms` | 2 per message |
| All others (tags, personas, forms, earn factors) | 0 |

Configurable via `entity_cost_normalization` table (✅ applied + seeded). Cost lookups use `fn_get_cost_normalization_cached` (Redis, 30-min TTL). See `AMP - Cache Layer.md`.

### Backward Compatibility

The MCP server auto-converts old hardcoded constraint format to the new flexible format:

```json
// Old format (still works)
{ "frequency": { "max_per_user_per_day": 3, "max_per_user_per_week": 10 }, "budget": { "max_cost_per_user_per_month": 500 } }

// Converted to
{ "constraints": [
    { "metric": "actions", "limit": 3, "scope": "per_user", "window": "per_day" },
    { "metric": "actions", "limit": 10, "scope": "per_user", "window": "per_week" },
    { "metric": "cost", "limit": 500, "scope": "per_user", "window": "per_month" }
  ]
}
```

### Two-Layer Enforcement

1. **AI reads constraints** via `get_constraints` tool → self-regulates (picks affordable action, respects headroom)
2. **MCP action tools enforce** → hard stop before execution (rejects if any constraint would be violated, returns error with details, AI picks alternative or stops)

Both layers use the same `fetchConstraints` + `computeUsage` logic. The `get_constraints` tool accepts optional `node_id` to return both workflow-level and node-level constraints with computed usage.

---

## System Instruction

Hardcoded in `crm-agent-service/src/system-prompt.ts`. The AI's default posture is **observational** — it assesses timing rather than acting by default.

**6-step reasoning process:**

1. **Gather data** — call `get_user_context`, `list_agent_actions(agent_id, user_id)`, `get_agent_goal_performance(agent_id)`, and `get_constraints`
2. **Read deliberation history** — if cycle > 0, compare what was previously "watched for" against current user data
3. **Assess timing** — user recency, trajectory, campaign state vs target, constraint headroom, context hint
4. **Decide** — one of three outcomes:
   - **ACT** (~15-20%) — timing is right, execute action tools, return structured JSON
   - **WAIT** (~60-70%) — not yet, return `wait_duration` and `watching_for`
   - **SKIP** (~10-20%) — user doesn't fit, return reasoning
5. **If acting** — pick from `allowed_actions`, respect `variable_config` ranges and `eligibility_conditions`, stay within constraints
6. **Respond** — structured JSON: `{"decision":"act"|"wait"|"skip", "reasoning":"...", ...}`

The AI calls `list_agent_actions(agent_id, user_id)` (not `list_available_actions`). The MCP server calls `fn_get_eligible_agent_actions` which filters by both agent config AND user eligibility conditions. No prompt engineering for action filtering — ineligible actions are structurally removed before the AI sees them.

---

## Component 7: Agent Config as First-Class Entity (`amp_agent`)

### Why

Previously, agent configuration (objective, tone, constraints, allowed actions) was embedded inline in `amp_workflow_node.node_config`. This caused:
- No reuse — every workflow duplicates the same agent config
- No proper UI — complex config crammed into a sidebar
- No independent performance tracking across workflows

### How It Works

`amp_agent` is a standalone entity with its own builder UI (Configuration, Guardrails, Outcomes tabs). Workflow agent nodes reference it by ID:

```json
// Agent node's node_config (lightweight reference)
{ "agent_config_id": "uuid-of-reusable-agent" }
```

When `inngest-amp-serve` hits an agent node:
1. Read `node_config.agent_config_id`
2. Fetch `amp_agent` row
3. Merge agent config into the payload sent to the agent service
4. Agent service receives the same payload shape — no changes needed

### Table: `amp_agent`

| Column | Type | Purpose |
|---|---|---|
| `id` | UUID PK | |
| `merchant_id` | UUID FK → merchant_master | Scoping |
| `name` | TEXT NOT NULL | "Re-engage Lapsed VIPs" |
| `description` | TEXT | |
| `objective` | TEXT | `re_engage`, `drive_purchase`, `redeem_points`, `tier_upgrade`, `win_back`, `upsell` |
| `tone` | TEXT | `urgent`, `friendly`, `exclusive`, `celebratory` |
| `context_hint` | TEXT | Marketer-provided context for the AI |
| `max_actions_per_execution` | INTEGER (default 3) | AI loop control |
| `allowed_action_types` | JSONB (default `[]`) | Which MCP tools the AI may use |
| `constraints` | JSONB (default `[]`) | ~~Removed — constraints now live on `amp_agent.constraints` only~~ |
| `cooldown_hours` | NUMERIC | Min gap between actions per user (rule-based workflows only; agent nodes use `amp_agent.cooldown_hours`) |
| `quiet_hours` | JSONB | `{enabled, start, end, timezone}` |
| `blackout_dates` | JSONB (default `[]`) | Dates when no actions execute |
| `is_active` | BOOLEAN (default true) | |
| `created_at` / `updated_at` | TIMESTAMPTZ | |

RLS: merchant-scoped via `get_current_merchant_id()`, service_role full access.

### Agent Actions (`action_registry / amp_agent`)

Each agent has a list of actions the AI can choose from. Each action references an action type from `amp_action_type_config` and has its own:

- **Variable config** — ranges/possible values the AI can pick from (vs static values in rule-based workflows)
- **Action constraints** — per-action limits (max amount per execution, budget, timeline). Enforced at action-tool level.
- **Eligibility conditions** — same condition grammar as workflow builder. User must meet these to receive this action.
- **Enabled/disabled** — toggle without removing

Example agent action for "Welcome Points":
```json
{
  "action_type": "award_points",
  "name": "Welcome bonus points",
  "variable_config": { "amount": {"min": 50, "max": 500}, "currency": "points" },
  "action_constraints": { "max_amount_per_execution": 500, "budget_limit": 1000, "budget_window": "per_month" },
  "eligibility_conditions": { "groups": [{"type": "simple", "collection": "user_accounts", "conditions": [{"field": "points_balance", "operator": "less_than", "value": "1000"}]}] }
}
```

### Agent Outcomes (`amp_agent_outcome`)

Multiple outcomes per agent, each defining what counts as success or failure. Outcomes are the **scorecard** — the measurable definition of whether the agent is working. Distinct from `objective` (which defines the AI's strategic approach).

- **Outcome** = "What we measure" (backward-looking). Used by the tracking job, performance dashboard, and AI learning.
- **Objective** = "How we approach" (forward-looking). Shapes the AI's reasoning style. Two agents with the same outcome (purchase) but different objectives (re_engage vs upsell) reason differently.

| Field | Type | Purpose |
|---|---|---|
| `event_type` | TEXT | What event to track (e.g., `purchase_completed`, `email_clicked`) |
| `event_filter` | JSONB | Optional filter on event properties (same condition grammar) |
| `classification` | TEXT | `best` > `very_good` > `good` > `bad` > `very_bad` > `worst` |
| `weight_column` | TEXT | Optional column for outcome weighting (e.g., `final_amount`) |
| `attribution_window_hours` | INTEGER | Hours after action to attribute an outcome. Default populated from `amp_outcome_event_config` at creation time. Per-outcome, not per-agent — different outcomes need different windows. |
| `counting_method` | TEXT | `'cumulative'` (count every event) or `'binary'` (happened or didn't). Default from seed table. |
| `target_conversion_rate` | NUMERIC | Target rate for this outcome (e.g., `0.20` = 20%). Meaningful on primary outcome. |
| `is_primary` | BOOLEAN | One per agent. The main KPI the AI optimizes for. Drives the "vs goal" metric. Enforced by partial unique index. |

Example outcomes for a cross-sell agent:
- "Purchases" — event: `purchase_completed`, classification: `best`, weight: `final_amount`, attribution: 168h, primary: true, target: 0.20
- "Email Click" — event: `email_clicked`, classification: `very_good`, attribution: 2h
- "Unsubscribe" — event: `unsubscribed`, classification: `worst`, attribution: 24h

### Action Type Config (`amp_action_type_config`)

Seed table defining the schema for each action type. Shared by both workflow builder (static values) and agent builder (ranges). Contains `applicable_variables` (what parameters, data types, required/optional) and `applicable_action_constraints` (what limits can be configured).

Seeded action types: `award_points`, `award_tickets`, `assign_tag`, `remove_tag`, `assign_persona`, `assign_earn_factor`, `submit_form`, `send_line_message`, `send_sms`, `add_to_audience`, `remove_from_audience`.

### Outcome Event Config (`amp_outcome_event_config`)

**UI-only seed table.** Drives the Outcomes tab in the agent builder UI — replaces hardcoded frontend constants. **Not used at runtime.** The tracking job reads `amp_agent_outcome` directly; this table only pre-populates form defaults.

| Column | Type | Purpose |
|---|---|---|
| `event_type` | TEXT PK | Internal key (e.g. `purchase_completed`) |
| `display_label` | TEXT | Human-readable label for dropdown (e.g. "Purchase Completed") |
| `description` | TEXT | Helper text shown in UI |
| `default_classification` | TEXT | Suggested classification when marketer adds this outcome |
| `weight_columns` | JSONB | `[{key, label}]` — numeric columns available for weighting. Empty array = weight not applicable |
| `filterable_fields` | JSONB | `[{key, label, type, operators}]` — fields available in Event Filter condition builder |
| `attribution_window_hours` | INTEGER | Default hours — copied to `amp_agent_outcome` at creation time |
| `counting_method` | TEXT | Default method — copied to `amp_agent_outcome` at creation time |
| `is_active` | BOOLEAN | Toggle visibility without deleting |
| `sort_order` | INTEGER | Controls dropdown ordering |

Seeded event types:
- `purchase_completed` — weight: final_amount, total_amount. Classification: best. Attribution: 7d. Cumulative.
- `points_earned` — weight: amount, balance_after. Classification: very_good. Attribution: 3d. Cumulative.
- `points_redeemed` — weight: amount. Classification: good. Attribution: 3d. Cumulative.
- `form_submitted` — no weight. Classification: good. Attribution: 3d. Binary.
- `email_clicked` — no weight. Classification: very_good. Attribution: 2h. Binary.
- `email_opened` — no weight. Classification: good. Attribution: 2h. Binary.
- `tag_assigned` — no weight. Classification: good. Attribution: 3d. Binary.
- `unsubscribed` — no weight. Classification: worst. Attribution: 24h. Binary.

Frontend reads this table on init (same as `amp_action_type_config`) and uses it to:
1. Populate the Event Type dropdown (replaces hardcoded `eventTypeOptions`)
2. Show Weight Column as a dropdown filtered by selected event type (replaces free-text input)
3. Auto-set classification default when a new outcome is added
4. Pre-fill `attribution_window_hours` and `counting_method` (marketer can override)
5. Provide event-type-specific fields to the Event Filter condition builder

### Outcome Attribution & Performance Tracking

**Two-layer architecture for measuring agent effectiveness:**

**Layer 1: Individual Attribution (`amp_outcome_attribution`)**

Per-user, per-action attribution records. Written by the `outcome-*-router` (Inngest) when outcome events occur. Each row says: "User X was actioned by agent Y at time T1. Outcome Z occurred at time T2, within the attribution window."

| Column | Type | Purpose |
|---|---|---|
| `agent_id` | UUID FK | Which agent |
| `agent_outcome_id` | UUID FK | Which outcome definition |
| `user_id` | UUID | Which user |
| `action_log_id` | UUID FK → `workflow_log` | The agent action being attributed to |
| `action_type` | TEXT | What action was taken |
| `action_at` | TIMESTAMPTZ | When the agent acted |
| `outcome_event_type` | TEXT | What outcome occurred |
| `outcome_source_table` | TEXT | Source table (purchase_ledger, wallet_ledger, etc.) |
| `outcome_source_id` | UUID | FK to the actual source record |
| `outcome_at` | TIMESTAMPTZ | When the outcome occurred |
| `outcome_value` | NUMERIC | Value from weight_column (e.g., purchase amount) |
| `attribution_window_hours` | INTEGER | Window used for this attribution |
| `hours_to_outcome` | NUMERIC | Actual time gap between action and outcome |
| `classification` | TEXT | Copied from outcome definition |

**Layer 2: Aggregate Performance (`amp_agent_performance_summary`)**

Precomputed by hourly pg_cron job (`fn_aggregate_agent_performance`). GROUP BY on `amp_outcome_attribution` — never touches source tables.

| Column | Type | Purpose |
|---|---|---|
| `agent_id` | UUID FK | Which agent |
| `period_start` / `period_end` | TIMESTAMPTZ | Rolling 7-day window |
| `total_users_actioned` | INTEGER | Users who received agent actions in period |
| `primary_outcome_type` | TEXT | Event type of primary outcome |
| `primary_conversion_rate` | NUMERIC | Actual conversion rate |
| `primary_target_rate` | NUMERIC | Target from outcome definition |
| `primary_total_value` | NUMERIC | Sum of outcome values |
| `primary_avg_hours` | NUMERIC | Average time to conversion |
| `outcome_breakdown` | JSONB | Per-outcome: `[{event_type, classification, converted_users, conversion_rate, total_value}]` |
| `action_type_breakdown` | JSONB | Per-action: `[{action_type, times_used, primary_conversion_rate}]` |
| `negative_outcome_rate` | NUMERIC | Rate of bad/worst outcomes |

**Data flow:**

```
Outcome event (purchase, points, email click, unsub)
  → outbox → Inngest → outcome-*-router
  → Point query: "was this user recently actioned by an agent?"
  → Write to amp_outcome_attribution

  ↓ hourly pg_cron

fn_aggregate_agent_performance
  → GROUP BY amp_outcome_attribution
  → Upsert amp_agent_performance_summary

  ↓ on-demand

get_agent_goal_performance (MCP tool)
  → Reads amp_agent_performance_summary + amp_agent_outcome definitions
  → Returns: outcomes + targets + actual rates + per-action effectiveness
```

**MCP Tool: `get_agent_goal_performance`** (replaces `get_agent_performance`)

Returns outcome definitions (goals), conversion rates vs targets, per-action-type effectiveness. Reads from precomputed summary table. Response shape:

```json
{
  "agent_id": "uuid",
  "agent_name": "Re-engage Lapsed VIPs",
  "objective": "re_engage",
  "period": "last_7_days",
  "total_users_actioned": 100,
  "outcomes": [
    {
      "event_type": "purchase_completed",
      "is_primary": true,
      "attribution_window_hours": 168,
      "target_conversion_rate": 0.20,
      "actual_conversion_rate": 0.12,
      "converted_users": 12,
      "total_value": 45000
    }
  ],
  "per_action_type": [
    { "action_type": "award_points", "times_used": 40, "primary_conversion_rate": 0.25 },
    { "action_type": "send_line_message", "times_used": 60, "primary_conversion_rate": 0.10 }
  ],
  "primary_summary": {
    "conversion_rate": 0.12,
    "target_rate": 0.20,
    "vs_target": "below"
  },
  "negative_outcome_rate": 0.03
}
```

**AI tools for deliberation (4 total):**

| # | Tool | Question it answers |
|---|---|---|
| 1 | `get_user_context` | "Who is this user?" |
| 2 | `list_agent_actions` | "What can I do?" |
| 3 | `get_agent_goal_performance` | "What am I measured against, and how well am I doing?" |
| 4 | `get_constraints` | "What are my limits?" |

`get_campaign_performance` remains available for dashboard and external clients but is not part of the AI's deliberation tool set.

### Two-Level Guardrails

- **Agent level** (`amp_agent.constraints`, `quiet_hours`, `blackout_dates`, `cooldown_hours`) — applies across all actions
- **Action level** (`action_registry / amp_agent.guardrail_config`) — specific to that action

Both enforced — the stricter one wins. Guardrails = limits on what/how much. Scheduling = limits on when.

### Structured Agent Output

Agent responses include structured fields so downstream workflow nodes can branch on specifics:

| Variable | Type | Purpose |
|---|---|---|
| `{{agent.action_taken}}` | boolean | true/false routing (existing) |
| `{{agent.action_type}}` | string | What action was taken: `award_points`, `send_line_message`, etc. |
| `{{agent.action_details}}` | object | Action parameters: `{amount: 100, currency: "points"}` |
| `{{agent.message}}` | string | Personalized message text (existing) |
| `{{agent.reasoning}}` | string | AI's reasoning (existing) |

Downstream condition nodes can branch on `{{agent.action_type}}` — "did the agent award points or just tag the user?"

---

## Component 8: Deliberation Loop (Observe-Wait-Act)

### Why

The original agent model was single-shot: trigger fires → AI decides → acts or doesn't → done. This is fundamentally wrong for marketing:

- If the AI is inclined to act, it fires on too many triggers — spammy.
- If the AI is conservative, it does nothing and the workflow ends — lost opportunity.

Real marketing is **patient observation**. A marketer sees a trigger, watches the customer for a few days, and acts only when the timing is right. Most of the time, the right decision is "not now."

### How It Works

The agent node in the workflow graph now runs a **deliberation loop** — multiple assessment cycles with Inngest-managed waits between them. On each cycle, the AI fetches fresh user data and decides: act, wait, or skip.

```
Agent Node Execution Flow:
──────────────────────────
1. Load agent config from amp_agent (max_deliberation_cycles, constraints, etc.)
2. For each cycle (0 to max_deliberation_cycles - 1):
   a. step.invoke → agent service on Render (with fresh MCP data + deliberation history)
   b. AI returns one of:
      - "act"  → execute action tools, break loop, route true
      - "wait" → step.sleep(duration), continue loop
      - "skip" → break loop, route false
   c. Log decision to workflow_log
3. If max cycles reached without action → route false ("deliberation_exhausted")
```

**Expected distribution across all triggers:** ~15-20% act, ~60-70% wait (eventually act or skip), ~10-20% skip immediately.

### Inngest Step Structure

Inngest sees all steps as flat — it doesn't distinguish the deliberation loop from the outer workflow loop. Each step has a unique ID:

```
step.run("agent-config-{nodeId}")         ← load agent config
step.invoke("agent-{nodeId}-cycle-0")     ← first assessment
step.run("log-agent-{nodeId}-cycle-0")    ← log decision
step.sleep("agent-{nodeId}-wait-0","3d")  ← AI said "wait 3 days"
step.invoke("agent-{nodeId}-cycle-1")     ← second assessment (fresh data)
step.run("log-agent-{nodeId}-cycle-1")    ← log decision
step.invoke("agent-{nodeId}-cycle-2")     ← third assessment → "act"
step.run("log-agent-{nodeId}-cycle-2")    ← log final decision
```

On resume after sleep, Inngest replays all memoized steps instantly and executes only the current pending step. The deliberation history rebuilds from cached step.invoke results — no database reads needed for the loop itself.

### Deliberation History

History is passed to the AI as part of the user message, not fetched from a database:

1. `inngest-amp-serve` builds a local array from cached step.invoke results
2. Array is included in the step.invoke payload to the agent service
3. Agent service formats it into the Groq prompt as text
4. AI reads the history and compares "what I was watching for" against fresh user data
5. `workflow_log` rows are written in parallel for merchant visibility (not read by AI)

### Agent Config Fields for Deliberation

| Column | Type | Default | Purpose |
|---|---|---|---|
| `max_deliberation_cycles` | INTEGER | 3 | Max observe-wait-decide cycles before giving up |
| `default_wait_duration` | TEXT | `'2d'` | Inngest sleep duration if AI doesn't specify |
| `max_wait_duration` | TEXT | `'7d'` | Cap on any single wait the AI can request |
| `deliberation_timeout` | TEXT | `'14d'` | Total time budget across all cycles |

### Log Event Types for Deliberation

| event_type | status | When |
|---|---|---|
| `agent_decided_act` | `acted` | AI decided to execute actions |
| `agent_decided_wait` | `waiting` | AI decided to wait and reassess |
| `agent_decided_skip` | `skipped` | AI decided user is not a fit |
| `agent_decided_skip` | `exhausted` | Max cycles reached with no action |

Each log entry includes in `event_data`: `cycle`, `decision`, `reasoning`, `watching_for`, `wait_duration`, `actions_taken`.

### Merchant Visibility

**Per-customer timeline:** Query `workflow_log` for a user + workflow, filter by `event_type LIKE 'agent_decided_%'`, order by `created_at`. Shows: "Cycle 0: waited 3 days watching for redemption → Cycle 1: waited 2 days → Cycle 2: acted, awarded 200 points + LINE message."

**Aggregate dashboard:** Count distinct `(workflow_id, user_id, inngest_run_id)` grouped by final decision status. Shows: "340 currently deliberating, 380 acted, 480 skipped, avg 4.2 days to decision."

### System Prompt Changes

The AI's default posture is now **observational, not action-seeking**. The system instruction explicitly states:
- "Your role is to ASSESS whether now is the right moment — not to act by default."
- "Most of the time, the right decision is to WAIT and reassess later."
- Expected distribution: 15-20% act, 60-70% wait, 10-20% skip.

The AI must return structured JSON: `{"decision":"act"|"wait"|"skip", "reasoning":"...", ...}`. For "wait", it also returns `wait_duration` and `watching_for`.

---

## Schema Changes (applied)

| Change | Table | Purpose |
|--------|-------|---------|
| Add `config` JSONB column | `workflow_master` | Workflow-level: campaign_kpi, budget, frequency |
| Add `cost` NUMERIC column | `workflow_log` | Cost tracking per action execution |
| Create `entity_cost_normalization` | New table | Polymorphic cost mapping (action_type → unit cost) |
| Add `scope` TEXT column | `workflow_master` | `'user'` (marketer-facing) or `'system'` (infrastructure) |
| Add `domain` TEXT column | `workflow_master` | `'campaign'` or `'audience'` (extensible) |
| Create `amp_audience_master` | New table | Audience definitions with link to system workflow |
| Create `amp_audience_member` | New table | Audience membership with soft exit support |
| Create `amp_agent` | New table | Reusable agent configurations |
| Create `amp_action_type_config` | New seed table | Action type schemas (variables + guardrails) shared by workflow builder + agent builder |
| Create `action_registry / amp_agent` | New table | Per-action config within agent (variables, guardrails, eligibility) |
| Create `amp_agent_outcome` | New table | Outcome tracking with classification and weighting |
| Create `amp_outcome_event_config` | New seed table | Outcome event type schemas (weight columns, filterable fields, attribution, defaults) for agent builder UI |
| Add deliberation columns | `amp_agent` | `max_deliberation_cycles` (INT, default 3), `default_wait_duration` (TEXT, default '2d'), `max_wait_duration` (TEXT, default '7d'), `deliberation_timeout` (TEXT, default '14d') |
| Add goal tracking columns | `amp_agent_outcome` | `attribution_window_hours` (INT, default 168), `counting_method` (TEXT, default 'cumulative'), `target_conversion_rate` (NUMERIC), `is_primary` (BOOL, default false). Partial unique index on `(agent_id) WHERE is_primary = true`. |
| Create `amp_outcome_attribution` | New table | Per-user, per-action outcome attribution. Written by Inngest outcome routers. Indexed on agent_id, user_id, action_log_id. RLS: merchant-scoped. |
| Create `amp_agent_performance_summary` | New table | Precomputed aggregate performance per agent per period. Written by hourly pg_cron. Unique on `(agent_id, period_start, period_end)`. |
| Create `fn_aggregate_agent_performance` | Function + pg_cron | Hourly aggregation: GROUP BY `amp_outcome_attribution` → upsert `amp_agent_performance_summary`. Scheduled via `cron.schedule('aggregate-agent-performance', '0 * * * *', ...)`. |
| Update `bff_upsert_agent_with_children` | Function | Handles new outcome columns: attribution_window_hours, counting_method, target_conversion_rate, is_primary |

---

## Authentication

**Internal (inngest-amp-serve → MCP server):** Supabase service role key in Authorization header.

**External (n8n → MCP server):** Merchant API key from `merchant_api_keys` table (already exists). MCP server validates key, resolves merchant, scopes all queries/actions.

---

## Implementation Status

| Component | Status | Version/Location |
|-----------|--------|-----------------|
| **Core AI Components** | | |
| `crm-loyalty-actions` MCP server | ✅ Live v15 | On Render (merged into `amp-ai-service`). `get_constraints(agent_id, user_id)` reads `amp_constraint_usage` — 2 queries, zero log reads at runtime. `action_constraints` (renamed from `guardrail_config`). Action tools validate `agent_id` scope. All DB-native actions via `fn_execute_amp_action`. `/mcp` route for 3rd party. |
| `amp-ai-service` agent + MCP service | ✅ Live v4.0.0 | Render, Singapore. Config reads cached via Upstash Redis `amp-cache` (agent config, constraints, performance, cost normalization, action types — all 10-min+ TTL). `last_action_at` for cooldown read from summary table, never from log. Persistent connection pools. See `AMP - Cache Layer.md`. |
| `inngest-amp-serve` (renamed from `inngest-amp-serve`) | ✅ Live v1 | Inngest Cloud App URL updated. Deliberation loop: observe-wait-act cycles. Reads `amp_agent` for deliberation settings only. |
| RisingWave state engine | ⚠ Verify | RisingWave Cloud, ap-southeast-1. Doc historically: Kafka sources → `user_stats` / `user_chronology` for MCP `get_user_context`. Re-confirm after Confluent deactivation. |
| **Agent Schema** | | |
| `amp_agent` table + RLS | ✅ Applied | Reusable agent configs. `constraints` (JSONB array) owns all frequency/budget rules. `cooldown_hours`, `quiet_hours`, `blackout_dates` for scheduling (agent wins over workflow for agent nodes). |
| `action_registry / amp_agent` table | ✅ Applied | Per-action variable config, `action_constraints` (renamed from `guardrail_config`), eligibility conditions. |
| `amp_agent_outcome` table | ✅ Applied | Outcome definitions with classification, weighting, `attribution_window_hours`, `counting_method`, `target_conversion_rate`, `is_primary`. |
| `amp_action_type_config` seed table | ✅ Applied | Action type schemas (variables + `applicable_action_constraints`). |
| `amp_constraint_usage` table | ✅ Applied | Pre-computed summary table. Refreshed every 10 min by `fn_refresh_constraint_usage`. Columns: `(agent_id, scope, user_id, metric, time_window, current_value, window_start, last_action_at, computed_at)`. `last_action_at` eliminates cooldown log read at runtime. `cost` metric uses `SUM(normalized_cost)` — monetary THB value. |
| `amp_outcome_event_config` seed table | ✅ Applied | UI-only. Outcome event type schemas for agent builder form defaults. |
| Agent BFF functions | ✅ Applied | `bff_upsert_agent_with_children` (updated for new outcome columns, now invalidates `amp-cache` agent key on save), `bff_get_agent_full`, `bff_list_agents`, `bff_delete_agent` |
| `entity_cost_normalization` | ✅ Applied + Seeded | Polymorphic cost mapping. Read by `fn_execute_amp_action` to compute `normalized_cost` before writing the log. Seeded for New CRM: points=0.10 THB, tickets (per type), LINE=0.30 THB, SMS=0.80 THB. `fn_execute_amp_action` falls back to `unit_cost=1.0` if no row found. |
| `workflow_log.normalized_cost` | ✅ Applied | Monetary cost column (THB) written by `fn_execute_amp_action` alongside flat `cost` (units). Used by `fn_refresh_constraint_usage` for `metric='cost'` in summary table. |
| **Goal Tracking** | | |
| `amp_outcome_attribution` table | ✅ Applied | Per-user attribution rows. Written by `outcome-*-router`. |
| `amp_agent_performance_summary` table | ✅ Applied | Precomputed aggregates. Written by hourly pg_cron. |
| `fn_aggregate_agent_performance` + pg_cron | ✅ Applied | Hourly aggregation job. GROUP BY attribution table → summary table. |
| `outcome-*-router` | ✅ Live | `inngest-event-router-serve`. Attributes purchase/wallet outcomes to recent agent actions → `amp_outcome_attribution`. |
| **Pending** | | |
| Delete `amp-decision-engine` + `inngest-amp-serve` | Pending — manual | Delete both from Supabase dashboard → Edge Functions. Both fully superseded. |
| Inngest router for `form_submissions` | Pending | No form_submitted outcome attribution until a form event is published to outbox/Inngest. |
| RisingWave agent views | Pending | `user_agent_usage`, `agent_campaign_state`, extend `event_chronology` with AMP actions |
| LINE flex message support in MCP | Pending | Add `messages_json` parameter to `send_line_message` MCP tool |
| Deliberation dashboard | Pending | WeWeb components for per-customer timeline and aggregate agent performance views |
|| **Cache Layer** | See `AMP - Cache Layer.md` | |
|| Upstash Redis `amp-cache` + cached getter functions | ✅ Applied | 9 functions, BFF invalidation, DB trigger invalidation. All config reads now cache-aside. |
|| `amp-ai-service` cache integration | ⬜ Pending | Add `@upstash/redis` to Render service, swap `fetchX` calls to check Redis first |

---

## What's Next

1. **Delete `amp-decision-engine` + `inngest-amp-serve`** — Supabase dashboard → Edge Functions, delete both
2. **Integrate `amp-cache` into `amp-ai-service`** — add `@upstash/redis`, use cached getters for agent config, performance, constraints, cost, action types. See `AMP - Cache Layer.md`.
3. **Add form_submissions to chokepoint/Inngest** — enables form outcome attribution
4. **RisingWave agent views** — `user_agent_usage`, `agent_campaign_state`, extend `event_chronology`
5. **LINE flex message support** — add `messages_json` parameter to `send_line_message` MCP tool
6. **Deliberation dashboard** — WeWeb per-customer timeline + aggregate agent performance views
