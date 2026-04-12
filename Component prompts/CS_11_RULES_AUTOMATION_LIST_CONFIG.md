# CS Rules / Automation — List + Config

## What This Is

Deterministic automation rules for the CS module. Rules fire BEFORE the AI agent — they handle fast, predictable automations like auto-tagging, auto-routing, auto-replies, and SLA escalation. Think of these as "if X happens, then do Y" without AI involvement.

CS rules use the **same workflow infrastructure** as loyalty marketing automation (`workflow_master`, `workflow_node`, `workflow_edge`), filtered by `domain='cs'`. The visual builder works identically — different trigger events and action node types.

- **List page** — Browse, toggle, reorder rules
- **Config page** — Visual rule builder (trigger → conditions → actions)

The AI in this project should use its own judgment for what UI layout and builder experience produce the best UX for **building no-code automation rules for customer service**. Study how Zendesk Triggers, Freshdesk Automations, or Intercom Workflows approach visual rule building — then decide the best structure.

---

## FE Project Context

| Layer | Tech |
|---|---|
| Framework | Next.js 16 (App Router, React 19) |
| UI | Shopify Polaris v13 (the only component library) |
| Flow diagrams | **XYFlow (React Flow)** — available if the AI decides a visual canvas is the best UX |
| Backend | All data via `supabase.rpc()` |
| Auth | Supabase Auth, JWT carries merchant context |
| Forms | `react-hook-form` + `zod` |

### Routes

```
src/app/(admin)/cs-rules/              → Rules list
src/app/(admin)/cs-rules/[id]/         → Rule builder (create/edit)
```

---

## Backend Connection — Tables & RPCs

### Core Tables (Shared Workflow Infrastructure)

**`workflow_master`** — A CS rule is a workflow with `domain='cs'`

| Column | CS Usage | Notes |
|---|---|---|
| `domain` | `'cs'` | Filters CS rules from loyalty workflows |
| `scope` | `'conversation'` | CS rules target conversations (not users) |
| `name` | Rule name | "Auto-reply to tracking inquiries" |
| `run_mode` | Same as loyalty | `once_per_trigger`, `every_time` |
| `is_active` | Toggle | |
| `config` | CS-specific config | `{channels: ["shopee","lazada"]}` |

**`workflow_trigger`** — CS trigger events

| trigger_type | Fires When |
|---|---|
| `cs_message_received` | Customer sends a message |
| `cs_conversation_created` | New conversation starts |
| `cs_status_changed` | Conversation status changes |
| `cs_sla_approaching` | SLA deadline within threshold |
| `cs_sla_breached` | SLA deadline passed |
| `cs_customer_identified` | Customer identity resolved |
| `cs_intent_detected` | AI detects a specific intent |
| `cs_sentiment_detected` | AI detects negative/angry sentiment |

**`workflow_node`** — CS node types

| node_type | What It Does | Config |
|---|---|---|
| `condition` | If/else branching | Same condition grammar as loyalty: field comparisons, AND/OR logic |
| `cs_auto_reply` | Send canned reply | `{template, variables}` |
| `cs_assign` | Route to agent/team | `{target_type, target_id, method: round_robin/least_busy/skills}` |
| `cs_set_priority` | Change priority | `{priority}` |
| `cs_tag` | Tag conversation | `{add: [], remove: []}` |
| `cs_escalate` | Escalate with summary | `{target_team, summary_template}` |
| `cs_invoke_ai` | Hand off to AI + procedure | `{procedure_id, flexibility}` |
| `cs_close` | Close conversation | `{resolution}` |
| `cs_notify` | Send notification | `{channel: slack/line_notify/email, template}` |
| `cs_create_ticket` | Create ticket from conversation | `{ticket_type, priority}` |
| `wait` | Delay before next step | Same as loyalty |

**`workflow_edge`** — Node connections (from_node_id → to_node_id)

**`workflow_log`** — Execution log for audit/analytics

### RPCs — List Page

| RPC | Purpose | Notes |
|---|---|---|
| `cs_bff_get_rules` | List CS rules | Returns workflow_master rows where domain='cs'. Includes: name, trigger_type, is_active, execution count, last fired. |
| `cs_bff_toggle_rule` | Enable/disable rule | Params: workflow_id, is_active |
| `cs_bff_reorder_rules` | Change rule priority | Params: ordered list of workflow_ids |
| `cs_bff_get_rule_stats` | Rule activity stats | Per-rule: fire count, last fired, success/skip/fail counts |

### RPCs — Config Page

| RPC | Purpose | Notes |
|---|---|---|
| `cs_bff_get_rule` | Get rule for edit | Params: workflow_id or null (new). Returns: workflow_master + trigger + all nodes + all edges. |
| `cs_bff_upsert_rule` | Save rule | Params: full rule payload (trigger, nodes, edges). Same upsert pattern as loyalty workflows. |
| `cs_bff_delete_rule` | Delete rule | Params: workflow_id |
| `cs_bff_test_rule` | Simulate rule | Params: workflow_id + sample conversation data. Backend evaluates conditions and reports which actions would fire. |
| `cs_bff_get_rule_templates` | Pre-built templates | Returns starter templates: "Auto-close after confirmation", "Route VIP to VIP team", "Notify supervisor on SLA breach" |

---

## Key Domain Concepts the UI Must Support

### 1. Rule Structure

Every rule follows: **Trigger → Condition(s) → Action(s)**

Example: "When a customer sends a message on Shopee, AND the customer has VIP tag, AND no agent is assigned → auto-reply with VIP greeting, assign to VIP team, set priority to high"

### 2. Condition Builder

The condition builder uses the same grammar as loyalty workflow conditions. Supports:
- Field comparisons: `channel = 'shopee'`, `priority = 'urgent'`
- Customer attributes: `customer.tags CONTAINS 'vip'`, `customer.tier = 'Gold'`
- Conversation state: `assigned_agent_id IS NULL`, `status = 'open'`
- Message content: `message CONTAINS keyword`, `intent = 'refund_request'`
- Temporal: `time_since_last_response > 30 minutes`
- Logical operators: AND, OR, NOT

### 3. Visual Builder vs Form Builder

The AI should decide the best builder UX:
- **Visual canvas** (like React Flow / XYFlow) — nodes connected by edges, drag-and-drop. Good for complex multi-branch rules.
- **Form-based builder** — step-by-step form: select trigger, add conditions, add actions. Good for simple linear rules.
- **Hybrid** — simple form for basic rules, visual canvas for advanced.

XYFlow is available in the project. Use it if it produces a better UX for rule building.

### 4. Rule Templates

Pre-built starting points for common rules:
- Auto-close after customer confirms resolution
- Route by channel (Shopee → ecommerce team, voice → call center)
- Notify supervisor on SLA breach
- Auto-tag by intent (refund_request → tag: refund)
- After-hours auto-reply
- VIP routing (VIP customers → VIP team)

### 5. Rule Priority and Execution

Rules execute in priority order. Can be configured as:
- **First match wins** — first matching rule fires, rest skip
- **Execute all matching** — all matching rules fire in priority order

### 6. Rule Testing

Simulate a rule with sample data: "If a message came in from Shopee, from a VIP customer, with intent 'refund' — which conditions match and which actions would fire?" Show a trace of the evaluation.

---

## Key UX Requirements

1. The list page should make it easy to see which rules are active, what they do at a glance, and how often they fire.

2. The builder must be accessible to non-technical CX team members — no code, no JSON.

3. Condition builder should use dropdowns and structured inputs — the user selects fields, operators, and values.

4. Rule testing should be inline — simulate without leaving the builder page.

---

## What NOT to Build (Backend Handles These)

- Rule evaluation at runtime — backend/Inngest evaluates rules on each message
- Interaction with AI agent — if a rule fires `cs_invoke_ai`, backend routes to AI service
- Platform API calls for auto-reply delivery — backend handles
- Condition grammar parsing — backend evaluates the JSONB conditions
