# CS Actions Config — List + Config

## What This Is

Action configuration — the registry of things the AI agent and rules engine can DO. Each action is a connection to an external system (marketplace API, CRM bridge, messaging platform) with configurable business-rule guardrails and technical parameters.

Actions are the `@Tool` references in AOPs (e.g., `@Process Refund`, `@Cancel Order`, `@Create Voucher`). This page manages which actions are available, their guardrail limits, and custom API actions.

- **List page** — View all available actions, enable/disable, see guardrail summary
- **Config page** — Configure guardrails, parameters, and test an action

The AI in this project should use its own judgment for what UI layout produces the best UX for **configuring AI agent action permissions and guardrails**. Study how Decagon's action connectors, Intercom's external actions, or Zapier's integration setup approach this — then decide the best structure.

---

## FE Project Context

| Layer | Tech |
|---|---|
| Framework | Next.js 16 (App Router, React 19) |
| UI | Shopify Polaris v13 (the only component library) |
| Backend | All data via `supabase.rpc()` |
| Auth | Supabase Auth, JWT carries merchant context |
| Forms | `react-hook-form` + `zod` |

### Routes

```
src/app/(admin)/cs-actions/            → Actions list
src/app/(admin)/cs-actions/[id]/       → Action config (guardrails + settings)
```

---

## Backend Connection — Tables & RPCs

### Core Tables

**`cs_action_config`** — Per-merchant action configuration (seeded automatically)

| Column | Type | Notes |
|---|---|---|
| `id` | uuid PK | |
| `merchant_id` | uuid FK | |
| `action_type` | text | `cs_cancel_order`, `cs_process_refund`, `cs_create_voucher`, `cs_award_points`, etc. References `workflow_action_type_config.action_type` |
| `name` | text | Display name: "Process Refund" |
| `is_enabled` | boolean | Can the AI/rules use this action? |
| `is_custom` | boolean | true = merchant-created custom API action |
| `variable_config` | jsonb | Parameter values and defaults |
| `action_constraints` | jsonb | Business guardrails: `{max_amount: 5000, require_supervisor_above: 5000, allowed_statuses: ["delivered"], max_per_customer_per_month: 2}` |
| `api_config` | jsonb | For custom actions: `{endpoint, method, auth, parameter_mapping, headers}`. Null for predefined actions. |
| `sort_order` | int | |
| `created_at` | timestamptz | |
| `updated_at` | timestamptz | |

**`workflow_action_type_config`** — Action type registry (shared, domain='cs')

| Column | Type | Notes |
|---|---|---|
| `action_type` | text | `cs_cancel_order`, `cs_process_refund`, etc. |
| `domain` | text | `cs` |
| `name` | text | Display name |
| `description` | text | What this action does |
| `applicable_variables` | jsonb | Parameter schema: what inputs this action accepts |
| `applicable_guardrails` | jsonb | Guardrail schema: what limits can be configured |
| `required_credential` | text | Which platform credential is needed (e.g., `shopee`, `line`, `crm_bridge`) |

### RPCs

| RPC | Purpose | Notes |
|---|---|---|
| `cs_bff_get_actions` | List all actions for this merchant | Returns cs_action_config rows + registry metadata (description, parameter schema, guardrail schema). Grouped by category (marketplace, messaging, CRM, CS internal, custom). |
| `cs_bff_get_action` | Get action for config | Params: action_config_id. Returns full config + applicable variables schema + applicable guardrails schema. |
| `cs_bff_upsert_action_config` | Update action config | Params: action_config_id, is_enabled, variable_config, action_constraints. For predefined actions, only guardrails and enable/disable are editable. |
| `cs_bff_create_custom_action` | Create custom API action | Params: name, api_config (endpoint, method, auth, parameter_mapping), variable_config, action_constraints. Creates both registry entry and merchant config. |
| `cs_bff_test_action` | Test action execution | Params: action_config_id, test_parameters. Executes in sandbox mode (no real side effects). Returns success/failure + response. |
| `cs_bff_get_action_stats` | Action usage statistics | Params: action_config_id, date_range. Returns: execution count, success rate, avg latency, failure reasons. |

---

## Key Domain Concepts the UI Must Support

### 1. Action Categories

Actions are organized by what system they connect to:

| Category | Actions | Connected System |
|---|---|---|
| **Marketplace** | Cancel Order, Process Refund, Accept Return, Create Marketplace Voucher, Send Product Card, Send Order Card | Shopee / Lazada / TikTok APIs (depends on which channel the conversation is on) |
| **CRM / Loyalty** | Award Points, Create Loyalty Voucher, Assign Tag, Remove Tag, Update Persona | CRM bridge API → existing CRM functions |
| **Messaging** | Send LINE Message, Send WhatsApp Message, Send Email | Messaging platform APIs |
| **CS Internal** | Escalate to Human, Create Ticket, Close Conversation, Trigger CSAT Survey | Internal CS functions |
| **Custom** | Merchant-defined API actions | Any HTTP API |

### 2. Business-Rule Guardrails (CX Team Configures)

Each action has guardrails the CX team sets via UI (dropdowns, number inputs, toggles):

| Action | Example Guardrails |
|---|---|
| `@Process Refund` | max_amount = 5000 THB, require_supervisor_above = 5000, allowed_order_statuses = ["delivered"] |
| `@Create Voucher` | max_value = 1000, max_per_customer_per_month = 2 |
| `@Cancel Order` | blocked_statuses = ["shipped", "delivered"] |
| `@Award Points` | max_points = 500, reason_required = true |

Guardrails are hard-enforced in the MCP tool code — even if the AI tries to exceed a limit, the tool rejects it.

### 3. Predefined vs Custom Actions

**Predefined actions** — come pre-registered when the merchant connects a platform or enables CS. Merchant can configure guardrails and enable/disable, but can't change the core logic.

**Custom actions** — merchant creates a new API action from scratch:
- Define HTTP endpoint, method, headers, auth
- Map parameters (what the AI collects from the conversation maps to which API fields)
- Set guardrails (limits, validation)
- Test with sample data

### 4. Action Seeding

When a merchant connects Shopee, the system auto-creates rows for all Shopee-related actions (Cancel Order, Process Refund, Create Voucher, etc.) with default guardrail values. The merchant then customizes guardrails to match their business policy.

### 5. Supervisor Verification

For high-risk actions (configurable), a separate AI model verifies the proposed action before execution. The config includes which action types require supervisor verification.

---

## Key UX Requirements

1. The list page should group actions by category. Clearly show which are enabled vs disabled. Guardrail summary at a glance (e.g., "Refund: max 5,000 THB").

2. Guardrail configuration should use structured inputs matching the guardrail type (number input for max_amount, multi-select for allowed_statuses, toggle for require_supervisor).

3. Custom action builder should feel like an API integration wizard — not code editing. Step through: endpoint → auth → parameters → guardrails → test.

4. Action testing should show the full request/response for verification.

---

## What NOT to Build (Backend Handles These)

- Action execution at runtime — MCP tools on cs-ai-service handle execution
- Guardrail enforcement — MCP tool code validates limits before executing
- Platform API credential management — handled in Channels config
- Supervisor verification model calls — backend AI service handles
- Action seeding on platform connection — backend auto-creates config rows
