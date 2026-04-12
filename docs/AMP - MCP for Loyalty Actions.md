# AMP — MCP for Loyalty Actions

## Overview

`crm-loyalty-actions` is an MCP server that exposes the CRM's loyalty actions and real-time user data as a standard MCP interface — usable by our internal AI agent (via Inngest/Groq), external workflow tools (n8n), or any MCP-compatible client (Cursor, Claude Desktop).

**Deployment:** Merged into `amp-ai-service` Render service (Node.js, Singapore). Previously a standalone Supabase Edge Function — migrated for persistent connection pooling, zero cold starts, and same-process access from AgentKit.

**Endpoint:**
```
https://amp-ai-service.onrender.com/mcp
```

**Version:** 14.0.0
**Protocol:** MCP over Streamable HTTP (JSON-RPC 2.0)
**Runtime:** Node.js on Render (persistent process)
**SDK:** `@modelcontextprotocol/sdk@1.25.3` + Express + Zod v4

**Architecture (v14):**
- MCP server is a **thin wrapper** over `data-fetchers.ts` — shared functions used by both MCP (3rd party) and agent service (internal pre-fetch)
- Action tools accept optional `agent_id` — validates scope via `fn_validate_agent_action_scope` DB function before executing
- DB-native actions (9 of 11) execute via `fn_execute_amp_action` RPC
- `list_agent_actions` accepts `user_id` — filters by both agent scope AND user eligibility via `fn_get_eligible_agent_actions` DB function. Returns outcomes alongside actions.
- Internal agent service does NOT use MCP for reads — calls `data-fetchers.ts` directly and embeds data in the AI prompt. MCP read tools exist for 3rd party clients only.
- Persistent RisingWave + Supabase connection pools
- Auth: `AsyncLocalStorage` for concurrent request safety. Localhost bypasses auth (internal).

---

## Architecture

```
┌──────────────────────────────────────────────────────────────┐
│ crm-loyalty-actions (Supabase Edge Function)                  │
│                                                               │
│  ┌─────────────────────────────────────────────────────────┐ │
│  │ RESOURCES (read-only context)                            │ │
│  │                                                          │ │
│  │  user://{user_id}/context                                │ │
│  │    └─► RisingWave: user_stats + user_chronology          │ │
│  │                                                          │ │
│  │  agent://{agent_id}/actions              ← NEW v10       │ │
│  │    └─► Supabase: amp_agent + amp_agent_action            │ │
│  │        + filtered merchant entities (tags, personas...)   │ │
│  │                                                          │ │
│  │  agent://{agent_id}/performance          ← NEW v10       │ │
│  │    └─► Supabase: amp_workflow_log aggregated across       │ │
│  │        all workflows using this agent                     │ │
│  │                                                          │ │
│  │  merchant://{merchant_id}/actions  (external clients)    │ │
│  │    └─► Supabase: tag_master, persona_master,             │ │
│  │        ticket_type, earn_factor, form_templates           │ │
│  │                                                          │ │
│  │  workflow://{workflow_id}/constraints                     │ │
│  │    └─► Supabase: amp_workflow.config + amp_workflow_log   │ │
│  │                                                          │ │
│  │  workflow://{workflow_id}/performance                     │ │
│  │    └─► Supabase: amp_workflow_log aggregation             │ │
│  └─────────────────────────────────────────────────────────┘ │
│                                                               │
│  ┌─────────────────────────────────────────────────────────┐ │
│  │ TOOLS (actions that cause effects)                       │ │
│  │                                                          │ │
│  │  award_points        → post_wallet_transaction RPC       │ │
│  │  award_tickets       → post_wallet_transaction RPC       │ │
│  │  assign_tag          → user_tags upsert                  │ │
│  │  remove_tag          → user_tags delete                  │ │
│  │  assign_persona      → user_accounts update              │ │
│  │  assign_earn_factor  → earn_factor_user insert           │ │
│  │  send_line_message   → send-line-message edge fn         │ │
│  │  send_sms            → send-sms-8x8 edge fn             │ │
│  │  submit_form         → submit_form_response RPC          │ │
│  │  add_to_audience     → fn_add_to_audience RPC            │ │
│  │  remove_from_audience → fn_remove_from_audience RPC      │ │
│  └─────────────────────────────────────────────────────────┘ │
│                                                               │
│  Auth: Service role key (internal) or merchant API key        │
│  Logging: amp_workflow_log (when workflow_id provided)        │
└──────────────────────────────────────────────────────────────┘
```

---

## Resources

Resources are read-only data endpoints. MCP clients discover them via `resources/templates/list` and fetch them via `resources/read`. The host application fetches relevant resources and puts the data into the AI's prompt before the AI starts reasoning about which tools to call.

### `user://{user_id}/context`

Real-time user profile from the streaming state engine (RisingWave).

**Source:** RisingWave materialized views `user_stats` + `user_chronology`

**What it returns:**
- `stats` — aggregated metrics: total_purchases, lifetime_value, avg_purchase_value, total_points_earned, total_points_spent, current_balance, last_purchase_at, last_activity_at
- `history` — last 20 events as a JSON array, newest first. Each event has type (purchase/currency_earned/currency_spent), timestamp, and event data

**How the AI uses it:** Understand who this user is, their spending patterns, point balance, and recent behavior. Determines conversion likelihood, user value, and urgency.

**Example fetch:**
```json
{"jsonrpc": "2.0", "id": 1, "method": "resources/read", "params": {"uri": "user://d6c9c7b3-f427-4328-a743-979191daf5ab/context"}}
```

---

### `agent://{agent_id}/actions` — NEW v10

Agent-scoped actions — returns ONLY the actions this agent is configured to use. Replaces `merchant://{merchant_id}/actions` for internal agent calls.

**Source:** `amp_agent` + `amp_agent_action` + filtered merchant entities

**What it returns:**
- `agent_id`, `agent_name`, `merchant_id` — agent identity
- `objective`, `tone`, `context_hint` — agent personality config
- `max_actions_per_execution` — loop control
- `allowed_actions` — array of configured actions, each with:
  - `action_type` — e.g., `award_points`, `assign_tag`
  - `name` — human label (e.g., "Welcome bonus points")
  - `variable_config` — ranges the AI can pick from (e.g., `{amount: {min: 50, max: 500}}`)
  - `guardrail_config` — per-action limits (e.g., `{max_amount_per_execution: 500}`)
  - `eligibility_conditions` — user must meet these to receive this action
- `core_action_types` — flat list of allowed action type strings
- `tags` — only tags referenced by agent actions (not the full merchant catalog)
- `persona_groups` — only personas referenced by agent actions
- `private_earn_factors`, `ticket_types`, `forms` — same scoping

**How the AI uses it:** The AI sees *exactly* what it's allowed to use. No over-fetching, no prompt engineering to constrain. The AI picks from `allowed_actions`, respects `variable_config` ranges, and checks `eligibility_conditions` before executing.

**Why this exists:** Previously `merchant://{merchant_id}/actions` returned the full catalog and relied on prompt engineering to constrain. Agent-scoped actions enforce the boundary structurally — the data isn't in the context.

---

### `agent://{agent_id}/performance` — NEW v10

Aggregate performance metrics across all workflows using this agent.

**Source:** `amp_agent` + `amp_workflow_node` (to find workflows) + `amp_workflow_log` aggregation

**What it returns:**
- `agent_id`, `agent_name` — identity
- `workflows_using_agent` — count of workflows referencing this agent
- `executions` — started, completed, failed, completion_rate (last 7 days)
- `actions_breakdown` — per action_type: executed, sent, failed, total_cost
- `campaign_kpi` — target from agent config

**How the AI uses it:** Understand which of its available actions historically perform best. If `award_points` has higher success rate than `send_line_message`, prefer it when both are viable. Cross-workflow learning.

---

### `merchant://{merchant_id}/actions` (external clients)

All loyalty actions available for a merchant. **Use `agent://{agent_id}/actions` instead for internal agent calls.**

**Source:** Supabase tables: `tag_master`, `persona_group_master`, `persona_master`, `earn_factor`, `earn_factor_group`, `ticket_type`, `form_templates`

**What it returns:**
- `core_actions` — 11 always-available action types with descriptions and parameter lists
- `tags` — merchant's full tag catalog (id + tag_name)
- `persona_groups` — all persona groups with nested personas (id + persona_name)
- `private_earn_factors` — all available earning boosts (type, amount, group_name)
- `ticket_types` — all raffle/draw ticket types (id, name, code)
- `forms` — all published form templates (id, name, code, category)

**How external clients use it:** n8n and other MCP clients that bring their own AI and their own filtering use this to see the full merchant catalog.

---

### `workflow://{workflow_id}/constraints?user_id={user_id}&merchant_id={merchant_id}`

Frequency limits, budget status, and cost model for a workflow execution.

**Source:** `amp_workflow.config` (limits) + `amp_workflow_log` (usage counts)

**What it returns:**
- `frequency` — limits (max_per_user_per_day, cooldown_hours) + current usage (actions_today, actions_this_week, last_action_at, allowed true/false)
- `budget` — configured limits + remaining budget
- `cost_model` — unit costs per action type

**How the AI uses it:** Check limits before taking action. If `allowed: false`, the AI skips action tools. If budget is low, the AI picks lower-cost actions.

**Note:** Frequency defaults are applied if no `config` JSONB exists on `amp_workflow` yet. Budget and cost model return placeholder notes until `entity_cost_normalization` table and `amp_workflow.config` column are created.

---

### `workflow://{workflow_id}/performance`

Campaign execution metrics for the last 7 days.

**Source:** `amp_workflow_log` aggregation + `amp_workflow.config.campaign_kpi`

**What it returns:**
- `executions` — started, completed, failed, completion_rate
- `actions_breakdown` — per action_type: executed/sent/failed counts
- `campaign_kpi` — target conversion rate and desired outcome (if configured)

**How the AI uses it:** Understand what's working. If campaign is below target, be more aggressive. If a specific action type has higher conversion, prefer it. If above target, conserve budget.

---

## Tools

Tools are actions that cause effects. The AI decides when to call them during reasoning. Each tool validates parameters, executes the action via existing Supabase RPCs or table operations, and logs to `amp_workflow_log` when `workflow_id` is provided.

### award_points

Award loyalty points to a user's wallet. Points are immediately available for redemption.

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| user_id | string | Yes | The user UUID |
| merchant_id | string | Yes | The merchant UUID |
| amount | number | Yes | Points to award (must be > 0) |
| description | string | No | Reason for the award |
| workflow_id | string | No | Enables cost tracking and logging |

**Executes:** `post_wallet_transaction` RPC with `p_currency: "points"`, `p_source_type: "amp"`
**Cost implication:** Proportional to amount (1 unit per point)

---

### award_tickets

Award raffle or lucky draw tickets.

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| user_id | string | Yes | The user UUID |
| merchant_id | string | Yes | The merchant UUID |
| ticket_type_id | string | Yes | From `merchant://{id}/actions` ticket_types |
| amount | number | Yes | Tickets to award |
| workflow_id | string | No | Enables tracking |

**Executes:** `post_wallet_transaction` RPC with `p_currency: "ticket"`, `p_target_entity_id: ticket_type_id`

---

### assign_tag

Assign a segmentation tag to a user. Idempotent — assigning the same tag twice has no effect.

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| user_id | string | Yes | The user UUID |
| merchant_id | string | Yes | The merchant UUID |
| tag_id | string | Yes | From `merchant://{id}/actions` tags |
| workflow_id | string | No | Enables tracking |

**Executes:** `user_tags` upsert with `source_type: "amp"`
**Cost:** Zero

---

### remove_tag

Remove a segmentation tag from a user.

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| user_id | string | Yes | The user UUID |
| merchant_id | string | Yes | The merchant UUID |
| tag_id | string | Yes | Tag UUID to remove |
| workflow_id | string | No | Enables tracking |

**Executes:** `user_tags` delete
**Cost:** Zero

---

### assign_persona

Change the user's persona classification. One persona per user — replaces previous.

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| user_id | string | Yes | The user UUID |
| merchant_id | string | Yes | The merchant UUID |
| persona_id | string | Yes | From `merchant://{id}/actions` persona_groups → personas |
| workflow_id | string | No | Enables tracking |

**Executes:** `user_accounts` update. Returns `previous_persona_id` for audit.
**Cost:** Zero

---

### assign_earn_factor

Give a user a temporary earning boost (e.g. 2x points for 7 days).

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| user_id | string | Yes | The user UUID |
| merchant_id | string | Yes | The merchant UUID |
| earn_factor_id | string | Yes | From `merchant://{id}/actions` private_earn_factors |
| days | number | Yes | Duration of the boost |
| workflow_id | string | No | Enables tracking |

**Executes:** `earn_factor_user` insert with calculated `window_end`
**Cost:** Zero (but high perceived value — good for re-engagement)

---

### send_line_message

Send a text message via LINE.

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| user_id | string | Yes | The user UUID |
| merchant_id | string | Yes | The merchant UUID |
| message | string | Yes | Message text — write in campaign's tone |
| workflow_id | string | No | Enables tracking |

**Executes:** `send-line-message` edge function. Requires user to have linked LINE account.
**Cost:** Per message

---

### send_sms

Send an SMS message.

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| user_id | string | Yes | The user UUID |
| merchant_id | string | Yes | The merchant UUID |
| message | string | Yes | SMS text — keep concise (160 chars) |
| workflow_id | string | No | Enables tracking |

**Executes:** `send-sms-8x8` edge function. Requires user to have phone number.
**Cost:** Per message (higher than LINE)

---

### submit_form

Submit a form response on behalf of a user.

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| user_id | string | Yes | The user UUID |
| merchant_id | string | Yes | The merchant UUID |
| form_id | string | Yes | From `merchant://{id}/actions` forms |
| field_values | object | Yes | Key-value pairs of field names and values |
| workflow_id | string | No | Enables tracking |

**Executes:** `submit_form_response` RPC
**Cost:** Zero

---

## Authentication

**Internal (inngest-serve, Groq loop):**
Uses the Supabase service role key in the Authorization header. Full access, no merchant scoping needed — merchant_id comes from tool/resource parameters.

**External (n8n, Claude Desktop, etc.):**
Uses a merchant API key from `merchant_api_keys` table. The MCP server validates the key, resolves the merchant, and scopes all queries/actions to that merchant.

---

## Logging

When `workflow_id` is provided, every action tool writes to `amp_workflow_log`:
- `event_type`: "action_executed"
- `action_type`: the specific action (award_currency, assign_tag, etc.)
- `status`: "executed", "sent", or "failed"
- `event_data`: action parameters + `source: "mcp"`
- `inngest_run_id`: synthetic ID (`mcp-{timestamp}`)

When `workflow_id` is not provided (external calls without workflow context), no logging occurs (FK constraint on workflow_id).

---

## Client Connection Examples

**Cursor / Claude Desktop:**
```json
{
  "mcpServers": {
    "crm-loyalty": {
      "url": "https://wkevmsedchftztoolkmi.supabase.co/functions/v1/crm-loyalty-actions"
    }
  }
}
```

**n8n MCP Client node:**
```
Server URL: https://wkevmsedchftztoolkmi.supabase.co/functions/v1/crm-loyalty-actions
Auth Header: Bearer <merchant-api-key>
```

**curl — list resource templates:**
```bash
curl -X POST 'https://wkevmsedchftztoolkmi.supabase.co/functions/v1/crm-loyalty-actions' \
  -H 'Content-Type: application/json' \
  -H 'Accept: application/json, text/event-stream' \
  -d '{"jsonrpc": "2.0", "id": 1, "method": "resources/templates/list"}'
```

**curl — read a resource:**
```bash
curl -X POST 'https://wkevmsedchftztoolkmi.supabase.co/functions/v1/crm-loyalty-actions' \
  -H 'Content-Type: application/json' \
  -H 'Accept: application/json, text/event-stream' \
  -d '{"jsonrpc": "2.0", "id": 1, "method": "resources/read", "params": {"uri": "user://USER_UUID/context"}}'
```

**curl — list tools:**
```bash
curl -X POST 'https://wkevmsedchftztoolkmi.supabase.co/functions/v1/crm-loyalty-actions' \
  -H 'Content-Type: application/json' \
  -H 'Accept: application/json, text/event-stream' \
  -d '{"jsonrpc": "2.0", "id": 1, "method": "tools/list"}'
```

**curl — call a tool:**
```bash
curl -X POST 'https://wkevmsedchftztoolkmi.supabase.co/functions/v1/crm-loyalty-actions' \
  -H 'Content-Type: application/json' \
  -H 'Accept: application/json, text/event-stream' \
  -d '{"jsonrpc": "2.0", "id": 1, "method": "tools/call", "params": {"name": "assign_tag", "arguments": {"user_id": "USER_UUID", "merchant_id": "MERCHANT_UUID", "tag_id": "TAG_UUID"}}}'
```

---

## Dependencies

| Dependency | Version | Purpose |
|-----------|---------|---------|
| `@modelcontextprotocol/sdk` | 1.25.3 | MCP server framework |
| `hono` | ^4.9.7 | HTTP routing |
| `zod` | ^4.1.13 | Parameter validation |
| `@supabase/supabase-js` | 2.46.0 | Supabase client |
| `postgres` (deno.land/x) | 0.17.0 | RisingWave connection |

---

## Environment Variables

All secrets are project-wide on Supabase (shared with other edge functions):

| Variable | Source |
|----------|--------|
| `SUPABASE_URL` | Auto-set by Supabase |
| `SUPABASE_SERVICE_ROLE_KEY` | Auto-set by Supabase |
| `RISINGWAVE_HOST` | Set manually for amp-decision-engine, shared |
| `RISINGWAVE_PORT` | 4566 |
| `RISINGWAVE_USER` | Set manually |
| `RISINGWAVE_PASSWORD` | Set manually |
| `RISINGWAVE_DB` | dev |

---

## Current Status

| Item | Status |
|------|--------|
| Resources (6 read endpoints) | Live v10 — added `agent://{agent_id}/actions` + `agent://{agent_id}/performance` |
| Read tools (6 — for AgentKit/AI) | Live v10 — added `list_agent_actions` + `get_agent_performance` |
| Action tools (11 endpoints) | Live v10 — includes audience actions |
| Agent-scoped filtering | Live v10 — AI only sees actions configured in `amp_agent_action`, no prompt engineering |
| `inngest-serve` MCP routing | Live v58 — rule-based actions + agent node deliberation loop via `step.invoke` + `step.sleep` |
| AgentKit agent service | Live — Render, Singapore, registered with Inngest Cloud |
| Schema changes | Applied — `amp_workflow.config`, `amp_workflow_log.cost`, `entity_cost_normalization` |
| End-to-end test | Passed — AI reads real data, reasons, executes actions, adapts on failure |

## Bug Fixes Applied (v6)

| Bug | Cause | Fix |
|-----|-------|-----|
| `award_points` — `source_id NOT NULL` | `p_transaction_id` passed as `null` when no `workflow_id` | Default to `user_id` when `workflow_id` is null |
| `assign_tag` — `assigned_at not in schema cache` | `user_tags` table has `created_at`, not `assigned_at` | Removed `assigned_at` from upsert |

## Design Note: Resources AND Tools

AgentKit (and most LLM tool-calling APIs) only discover **tools** via `tools/list`. They do NOT fetch MCP resources. So the MCP server exposes read data as both:
- **Resources** — for external MCP clients (n8n, Claude Desktop) that support the full MCP protocol
- **Tools** — for AI agents via AgentKit/Groq that only see tools

Both use the same shared helper functions internally. No code duplication.

## What's Next

| Item | Status |
|------|--------|
| Debug RisingWave data flow | Pending — Kafka sources exist but no data populating yet |
| Outcome tracking job | Pending — scheduled function to compute conversions |
| LINE flex message support | Pending — add `messages_json` param for rich messages |
