# Resource Content & Action Macro — Schema Proposal

> **Status:** Draft — awaiting approval  
> **Scope:** Two new shared concepts: (1) reusable sendable content, (2) parameterized multi-step action sequences with context-specific guardrails  
> **Naming:** "Macro" = macroinstruction — one action that expands into multiple actions. Standard CS industry term (Zendesk, Intercom, Freshdesk all use it).

---

## 1. Two Gaps in the Platform

**Gap 1 — Content Levers.** The platform has well-defined value levers (points, vouchers, multipliers) and classification levers (tags, personas) — each with dedicated tables that multiple modules reference. But there's no equivalent for **sendable content** — reusable text, media, and links that agents, CS AI, or AMP can deliver to customers.

**Gap 2 — Shared Action Sequences.** Today, each module defines its own action execution model independently:
- AMP rules: static values baked into `workflow_node.node_config`
- AMP AI: individual actions via `amp_agent_action` with variable ranges + constraints
- CS AI: individual tools via `cs_action_config`
- CS Agent: nothing — no structured way to execute multi-step actions

But the underlying actions are the same (issue voucher, assign tag, send message). What's missing is a **shared, reusable, parameterized action sequence** that all modules can reference — with each module applying its own guardrails to the parameters.

---

## 2. Concept: Action Macro

A macro is a reusable template for "do these steps with these parameters." One instruction that expands into multiple actions — with variables that get filled in at execution time.

**Who fills in the variables and what limits apply depends on the context:**

| Context | Who fills in variables | Where guardrails live |
|---|---|---|
| **CS Agent** | Agent types value into a form field | Role-based limits (agent ≤ ฿200, supervisor ≤ ฿1000) |
| **CS AI** | AI decides value based on conversation | CS-level variable constraints + approval thresholds |
| **AMP AI Agent** | AI decides value based on user data | `amp_agent_action` variable_config + action_constraints (existing pattern) |
| **AMP Rule** | Static values set by marketer at build time | No runtime guardrails — values fixed |

**The macro defines the ceiling. Each context can only narrow, never widen.**

### Example: "Service Recovery" Macro

**Definition** (shared, lives in `action_macro`):
```
Steps:
  1. Send resource → {{apology_reply}}       (type: resource_content, required)
  2. Create voucher → amount: {{voucher_amount}} (type: numeric, min: 0, max: 5000)
  3. Assign tag → {{recovery_tag}}            (type: tag, required)
  4. Add internal note → "Service recovery executed: ฿{{voucher_amount}} voucher issued"
  5. Trigger CSAT survey
```

**When CS Agent executes it:**
- Sees a form: picks the apology message, types voucher amount, picks the tag
- Role "cs_agent" can only enter voucher_amount up to ฿200
- Role "cs_supervisor" can go up to ฿1000
- No approval needed for agent within their limit

**When CS AI executes it:**
- AI picks the apology from allowed resources, decides voucher amount
- CS AI config says: max ฿200 auto, ฿201–500 requires supervisor approval, >฿500 blocked
- AI must confirm with customer before executing

**When AMP AI Agent uses it:**
- Agent's `amp_agent_action` row says: voucher_amount range 50–300, budget ฿10,000/month
- AI picks optimal value per user within the narrowed range
- Existing constraint system (cooldowns, budgets, quiet hours) applies

**When AMP Rule references it:**
- Workflow builder sets static values: voucher_amount = 100, specific tag, specific reply
- Executes deterministically on trigger

---

## 3. Schema

### 3.1 `resource_content_category` — Organizing the Content Library

| Column | Type | Default | Notes |
|---|---|---|---|
| `id` | uuid | gen_random_uuid() | PK |
| `merchant_id` | uuid NOT NULL | — | FK → merchant_master |
| `category_name` | text NOT NULL | — | Display name |
| `parent_id` | uuid | NULL | FK → self (one level nesting) |
| `sort_order` | integer | 0 | |
| `is_active` | boolean | true | |
| `created_at` | timestamptz | now() | |
| `updated_at` | timestamptz | now() | |

### 3.2 `resource_content` — The Content Library

Every piece of reusable sendable content. This is to "things you send" what `tag_master` is to "labels you assign."

| Column | Type | Default | Notes |
|---|---|---|---|
| `id` | uuid | gen_random_uuid() | PK |
| `merchant_id` | uuid NOT NULL | — | FK → merchant_master |
| `resource_type` | text NOT NULL | — | `quick_reply`, `media`, `link`, `rich_content` |
| `resource_code` | text | NULL | Human-readable identifier (unique per merchant) |
| `name` | text NOT NULL | — | Admin/agent display name |
| `content` | text | NULL | Text body (primary for quick_reply, description for others) |
| `media_url` | text | NULL | Supabase Storage URL (for media type) |
| `media_mime_type` | text | NULL | e.g. `application/pdf`, `video/mp4` |
| `link_url` | text | NULL | External URL (for link type) |
| `thumbnail_url` | text | NULL | Preview image |
| `file_size_bytes` | integer | NULL | For media type |
| `rich_content` | jsonb | '{}' | Structured blocks for rich_content type |
| `category_id` | uuid | NULL | FK → resource_content_category |
| `language` | text | NULL | ISO language code |
| `search_tags` | text[] | '{}' | Freeform tags for search/filter |
| `allowed_channels` | text[] | NULL | Channel restrictions. NULL = all. |
| `is_active` | boolean | true | |
| `sort_order` | integer | 0 | |
| `metadata` | jsonb | '{}' | Extensible |
| `created_by` | uuid | NULL | Admin who created it |
| `created_at` | timestamptz | now() | |
| `updated_at` | timestamptz | now() | |

### 3.3 `action_macro` — Reusable Parameterized Action Sequences

The shared definition. No module-specific prefix — used by AMP, CS, and Loyalty.

| Column | Type | Default | Notes |
|---|---|---|---|
| `id` | uuid | gen_random_uuid() | PK |
| `merchant_id` | uuid NOT NULL | — | FK → merchant_master |
| `macro_code` | text | NULL | Human-readable identifier |
| `name` | text NOT NULL | — | Display name ("Service Recovery", "VIP Welcome") |
| `description` | text | NULL | What this macro does |
| `steps` | jsonb NOT NULL | — | Ordered array of action steps (§4.1) |
| `variable_definitions` | jsonb NOT NULL | '{}' | Schema for all variables (§4.2) — the ceiling |
| `tags` | text[] | '{}' | Organizational tags for search/filter |
| `is_active` | boolean | true | |
| `sort_order` | integer | 0 | |
| `created_by` | uuid | NULL | |
| `created_at` | timestamptz | now() | |
| `updated_at` | timestamptz | now() | |

### 3.4 `action_macro_context` — Per-Context Guardrails

This is the binding table. Each row says "this macro is available in this context, with these constraints." One macro can have multiple context bindings.

| Column | Type | Default | Notes |
|---|---|---|---|
| `id` | uuid | gen_random_uuid() | PK |
| `merchant_id` | uuid NOT NULL | — | FK → merchant_master |
| `macro_id` | uuid NOT NULL | — | FK → action_macro |
| `context_type` | text NOT NULL | — | `cs_agent`, `cs_ai`, `amp_agent`, `amp_rule` |
| `context_ref_id` | uuid | NULL | Optional FK — role_id for cs_agent, agent_id for amp_agent |
| `variable_constraints` | jsonb NOT NULL | '{}' | Per-variable overrides (§4.3) — can only narrow |
| `requires_approval` | boolean | false | Requires human approval before execution |
| `approval_threshold` | jsonb | NULL | Conditional approval (§4.4) |
| `is_enabled` | boolean | true | |
| `sort_order` | integer | 0 | |
| `created_at` | timestamptz | now() | |
| `updated_at` | timestamptz | now() | |

**Unique constraint:** `(merchant_id, macro_id, context_type, context_ref_id)`

---

## 4. JSONB Structures

### 4.1 `steps` (action_macro.steps)

Ordered array of actions. Variables use `{{variable_name}}` syntax. Fixed values are inline.

```json
[
  {
    "action": "send_resource",
    "params": { "resource_id": "{{apology_reply}}" }
  },
  {
    "action": "create_voucher",
    "params": { "amount": "{{voucher_amount}}", "voucher_type": "fixed_amount" }
  },
  {
    "action": "assign_tag",
    "params": { "tag_id": "{{recovery_tag}}" }
  },
  {
    "action": "add_note",
    "params": { "content": "Service recovery: ฿{{voucher_amount}} voucher issued" }
  },
  {
    "action": "trigger_csat"
  }
]
```

**Supported step actions** (all map to existing platform capabilities):

| Category | action | params |
|---|---|---|
| **Value** | `award_currency` | `amount`, `currency` (points/ticket), `description` |
| | `create_voucher` | `amount`, `voucher_type`, `reward_id` |
| | `assign_earn_factor` | `earn_factor_id`, `window_end_days` |
| | `process_refund` | `amount`, `reason` |
| **Classification** | `assign_tag` | `tag_id` |
| | `remove_tag` | `tag_id` |
| | `assign_persona` | `persona_id` |
| | `add_to_audience` | `audience_id` |
| **Content** | `send_resource` | `resource_id` (FK → resource_content) |
| | `send_text` | `content` (inline text, for simple cases) |
| | `send_message` | `channel`, `template_id` or `content` |
| **System** | `close_conversation` | — |
| | `set_priority` | `priority` |
| | `add_note` | `content` (internal note) |
| | `create_ticket` | `subject`, `priority` |
| | `escalate_to_human` | `reason` |
| | `trigger_csat` | — |
| **Integration** | `api_call` | `url`, `method`, `body` |

### 4.2 `variable_definitions` (action_macro.variable_definitions)

Defines the schema for each variable — type, label, constraints, default. This is the **ceiling** — no execution context can exceed these limits.

```json
{
  "voucher_amount": {
    "type": "numeric",
    "label": "Voucher Amount (฿)",
    "min": 0,
    "max": 5000,
    "default": 100,
    "required": true
  },
  "apology_reply": {
    "type": "resource_content",
    "label": "Apology Message",
    "resource_type_filter": "quick_reply",
    "category_filter": "apology",
    "required": true
  },
  "recovery_tag": {
    "type": "tag",
    "label": "Recovery Tag",
    "default": "uuid-of-default-tag",
    "required": true
  }
}
```

**Variable types:**

| type | What it references | Rendered as |
|---|---|---|
| `numeric` | A number (amount, quantity) | Number input with min/max |
| `text` | Free text | Text input |
| `tag` | `tag_master.id` | Tag picker dropdown |
| `persona` | `persona_master.id` | Persona picker |
| `resource_content` | `resource_content.id` | Resource picker (filtered by resource_type_filter) |
| `reward` | `reward_master.id` | Reward/voucher template picker |
| `audience` | `amp_audience_master.id` | Audience picker |
| `enum` | Fixed set of options | Dropdown |
| `boolean` | true/false | Toggle |

### 4.3 `variable_constraints` (action_macro_context.variable_constraints)

Per-context overrides. Can only **narrow** the macro's ceiling, never widen.

**CS Agent (role: cs_agent):**
```json
{
  "voucher_amount": { "max": 200 },
  "recovery_tag": { "fixed": "uuid-always-this-tag" }
}
```
Agent can enter up to ฿200. Tag is pre-selected, not editable.

**CS Agent (role: cs_supervisor):**
```json
{
  "voucher_amount": { "max": 1000 }
}
```
Supervisor can go higher. Other variables unconstrained (within macro ceiling).

**CS AI:**
```json
{
  "voucher_amount": { "min": 50, "max": 500 },
  "apology_reply": { "allowed_ids": ["uuid-1", "uuid-2", "uuid-3"] }
}
```
AI picks from 50–500. Only certain apology messages allowed.

**AMP AI Agent:**
```json
{
  "voucher_amount": { "min": 50, "max": 300 }
}
```
AMP agent works within a tighter range.

### 4.4 `approval_threshold` (action_macro_context.approval_threshold)

Conditional approval — macro executes automatically below threshold, requires approval above.

```json
{
  "variable": "voucher_amount",
  "auto_approve_max": 200,
  "approval_role": "cs_supervisor",
  "blocked_above": 1000
}
```

Meaning:
- ≤ ฿200 → executes immediately (no approval)
- ฿201–1000 → queued for supervisor approval
- > ฿1000 → blocked entirely

---

## 5. How Each Module Binds to Macros

### 5.1 CS Agent

Agent workspace shows available macros as action buttons (filtered by their role's `action_macro_context` rows). Clicking opens a form with the variable fields, pre-filled with defaults, constrained by role limits. Agent fills in, submits, macro executes.

**No new table needed for agent execution** — the `action_macro_context` row with `context_type = 'cs_agent'` and `context_ref_id = role_id` controls access and limits. The execution engine reads the macro steps and processes them in order.

### 5.2 CS AI

The CS AI sees macros as composite tools. When the AI decides "this situation calls for service recovery," it calls `execute_macro(macro_id, variables)`. The execution engine:

1. Loads the macro
2. Loads the `action_macro_context` for `context_type = 'cs_ai'`
3. Validates all variables against context constraints
4. Checks approval threshold — auto-approve or queue for human
5. Executes steps in order

**Integration with existing CS AI guardrails:** `cs_merchant_guardrails` continues to handle global AI behavior rules (tone, escalation triggers, etc.). Macro-level guardrails handle action-specific limits. They compose — global guardrails can block the AI from even considering a macro ("never issue vouchers to customers who've had 3 vouchers this month"), while macro guardrails control the parameters when it does.

### 5.3 AMP AI Agent

A macro appears as a new action type in `amp_agent_action`:

```json
{
  "action_type": "execute_macro",
  "name": "Service Recovery",
  "variable_config": {
    "macro_id": "uuid-of-macro",
    "voucher_amount": { "min": 50, "max": 300 }
  },
  "action_constraints": {
    "budget_limit": 10000,
    "budget_window": "per_month",
    "max_per_user": 1
  }
}
```

This uses the **existing `amp_agent_action` pattern** — no new tables. The `variable_config` narrows macro variables for this agent's context. The `action_constraints` apply AMP-level budget/frequency limits. The execution engine reads the macro and processes steps, with variables resolved from the AI's chosen values.

### 5.4 AMP Rule-Based

A workflow action node references a macro with all variables fixed:

```json
{
  "node_type": "action",
  "node_config": {
    "action_type": "execute_macro",
    "macro_id": "uuid",
    "variables": {
      "voucher_amount": 100,
      "apology_reply": "uuid-of-specific-reply",
      "recovery_tag": "uuid-of-specific-tag"
    }
  }
}
```

No runtime decisions, no guardrails needed — the marketer chose all values at build time. Validated against macro ceiling at save time.

---

## 6. Guardrail Architecture Summary

Three layers, progressively narrowing:

```
┌─────────────────────────────────────────────┐
│  LAYER 1: Macro Definition (ceiling)        │
│  action_macro.variable_definitions          │
│  "voucher_amount: 0–5000"                   │
│  Defined by: Admin who creates the macro    │
│  Applies to: Everyone, always               │
├─────────────────────────────────────────────┤
│  LAYER 2: Context Binding (narrowing)       │
│  action_macro_context.variable_constraints  │
│  "CS AI: 50–500" / "Agent: 0–200"          │
│  Defined by: Admin configuring the context  │
│  Applies to: Specific actor type + role     │
├─────────────────────────────────────────────┤
│  LAYER 3: Execution Guardrails (runtime)    │
│  AMP: amp_agent.constraints (budget, freq)  │
│  CS AI: cs_merchant_guardrails (global)     │
│  CS Agent: role permissions (RBAC)          │
│  Defined by: Existing per-module systems    │
│  Applies to: Specific execution instance    │
└─────────────────────────────────────────────┘
```

**Layer 1** prevents anyone from issuing a ฿10,000 voucher regardless of context.
**Layer 2** gives CS AI a range of 50–500, while CS agents get 0–200.
**Layer 3** checks runtime conditions — has the AMP budget been exhausted? Is the CS AI globally blocked from issuing vouchers this month? Does the agent's role even have permission to execute actions?

All three must pass. The tightest constraint wins.

---

## 7. The Unified Merchant Toolkit (Updated)

### Value Levers

| Entity | Source table | AMP Rule | AMP AI | CS AI | CS Agent |
|---|---|---|---|---|---|
| Points | wallet config | direct | direct | via bridge | via bridge |
| Tickets | wallet config | direct | direct | — | — |
| Voucher templates | `reward_master` | direct | direct | via bridge | via bridge |
| Earn multipliers | earn factor | direct | direct | — | — |
| Refund | platform APIs | — | — | direct | direct |
| Platform vouchers | Shopee/Lazada/TikTok | — | — | direct | direct |

### Classification Levers

| Entity | Source table | AMP Rule | AMP AI | CS AI | CS Agent |
|---|---|---|---|---|---|
| Tags | `tag_master` | direct | direct | via bridge | via bridge |
| Personas | `persona_master` | direct | direct | via bridge | via bridge |
| Audiences | `amp_audience_master` | direct | — | — | — |

### Content Levers (NEW)

| Entity | Source table | AMP Rule | AMP AI | CS AI | CS Agent |
|---|---|---|---|---|---|
| Quick replies | **`resource_content`** | — | send_resource | send_resource | browse + send |
| Media (PDF, video) | **`resource_content`** | message ref | send_resource | send_resource | browse + send |
| Links | **`resource_content`** | message ref | send_resource | send_resource | browse + send |
| Rich content | **`resource_content`** | message ref | send_resource | send_resource | browse + send |
| Knowledge articles | `cs_knowledge_articles` | — | — | AI retrieval | search |

### Action Sequences (NEW)

| Entity | Source table | AMP Rule | AMP AI | CS AI | CS Agent |
|---|---|---|---|---|---|
| Macros | **`action_macro`** | static vars | AI decides vars | AI decides vars | agent fills vars |
| Guardrails | **`action_macro_context`** | validate at save | Layer 2 constraints | Layer 2 constraints | role-based limits |

### Existing Single Actions (unchanged)

| Entity | Source table | Purpose |
|---|---|---|
| AMP action types | `amp_agent_action` | Individual actions for AMP AI agent |
| CS action tools | `cs_action_config` | Individual tools for CS AI |
| Workflow actions | `workflow_node` | Static actions in rule-based flows |

**Macros compose single actions into reusable sequences. They don't replace individual actions — they bundle them.**

---

## 8. What Does NOT Change

- **`amp_agent_action`** — stays as-is. Gains a new `action_type: 'execute_macro'` option (just a new value, no schema change).
- **`cs_action_config`** — stays as-is. One new row for `send_resource` tool.
- **`workflow_node`** — stays as-is. Macro reference goes in existing `node_config` jsonb.
- **`cs_merchant_guardrails`** — stays as-is. Continues to handle global CS AI behavior.
- **`cs_messages`** — stays as-is. Resource/macro references in existing `metadata` jsonb.
- **All loyalty entities** — untouched.
- **Customer assets** (`asset`, `asset_type`) — completely separate concept, untouched.

---

## 9. Migration Priority

| Phase | What | Why |
|---|---|---|
| 1 | `resource_content_category` + `resource_content` + RLS | Foundation — the content library |
| 2 | `action_macro` + `action_macro_context` + RLS | Foundation — the macro engine |
| 3 | Macro execution engine (shared function) | Process steps, validate constraints, check approval |
| 4 | CS Agent UI: resource browser + macro form | Primary consumers — agents use both daily |
| 5 | CS AI integration: `send_resource` + `execute_macro` tools | AI can send content and run macros |
| 6 | AMP integration: macro action type in agent + workflow builder | Marketers can use shared macros |
| 7 | Approval workflow | Conditional approval for above-threshold executions |

---

## 10. Relationship to Existing Concepts

### Macros vs CS Procedures (AOPs)

Procedures are **AI reasoning workflows** — branching decision trees that guide the AI through a conversation ("if customer has no order number, ask for it; if order is >30 days old, explain policy; if order is returnable, offer refund or exchange"). They're about *how the AI thinks*.

Macros are **action execution bundles** — do these specific things with these parameters. They're about *what gets done*. A procedure might *invoke* a macro as one of its actions: "if customer accepts refund → execute 'Process Refund' macro."

### Macros vs AMP Workflow Nodes

A workflow is a graph of conditions, waits, and actions triggered by events. A macro is a flat sequence of actions triggered by a human or AI decision. A workflow action node might execute a macro (instead of a single inline action).

### Custom Answers vs Quick Replies (resource_content)

Custom answers (`cs_knowledge_articles.is_custom_answer = true`) are AI intent-matching overrides — the AI recognizes a question pattern and serves a specific answer. Quick replies (`resource_content.resource_type = 'quick_reply'`) are agent-facing content — the agent picks them from a library. A custom answer can reference a resource_content attachment ("when asked about returns, use this answer AND attach the returns PDF").
