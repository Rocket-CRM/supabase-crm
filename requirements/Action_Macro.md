# Action Macro

Shared, reusable multi-step action sequences for CS and AMP — one named playbook that expands into ordered steps, with variables filled in at run time by humans, CS AI, or AMP automation.

Owner surfaces: loyalty-admin (macro builder / list, planned), CS Inbox & Live Assist (agent + AI), AMP rule workflows and AI agents

## Concept

An **action macro** is a merchant-defined playbook: a display name, an ordered list of steps (each step names a single action and its parameters), and a **variable schema** that describes what callers may supply at execution time (amounts, tag IDs, content resource picks, and so on).

A **context binding** publishes that macro for a specific execution surface — human CS agent, CS AI, AMP AI agent, or AMP rule workflow — and may tighten variable limits, require supervisor approval, or scope the binding to a role or agent. The same macro definition can have multiple bindings (for example, stricter limits for autonomous AI than for a senior agent).

**Variables** are named inputs referenced inside step parameters as `{{variable_name}}`. The macro’s variable schema sets the **ceiling** (max amounts, allowed types, defaults). Context bindings may only **narrow** that ceiling; they cannot grant wider limits than the macro allows.

**Context types** (where a macro may run):

| Context type | Who runs it | Typical `context_ref_id` |
| --- | --- | --- |
| `cs_agent` | Human agent in CS Inbox / Live Assist | CS role id (optional) — limits which roles see the macro |
| `cs_ai` | Autonomous or copilot CS AI | Usually null — merchant-wide AI policy |
| `amp_agent` | AMP AI decisioning agent | `amp_agent.id` — per-agent tool allowlist |
| `amp_rule` | Rule-based workflow action node | Usually null — variables often pre-filled in the workflow |

Macros are **shared infrastructure**: they are not a loyalty member product. Members never browse or trigger macros directly; they only see outcomes (messages, points, tags) produced by steps.

## Rules

### Guardrails (three layers)

1. **Macro ceiling** — `variable_definitions` on the macro row is the absolute limit. No context binding may widen min/max, add required variables the macro did not define, or allow types outside the macro schema.
2. **Context binding** — `variable_constraints` on the context row may only tighten (lower max, raise min, restrict enum choices, force defaults). Upsert validation must reject bindings that exceed the macro ceiling.
3. **Runtime module policy** — Existing CS guardrails, AMP agent/action constraints, and role RBAC still apply after variables are resolved. The strictest applicable limit wins.

### Variable validation

- If the caller omits a variable marked `required` in the macro schema → validation fails; execution does not start.
- If a value is outside the effective range (macro ceiling ∩ context constraints) → validation fails.
- Resolved values (defaults applied, types coerced per schema) are returned to the approval check and step dispatch.

Example (narrowing only): macro allows `voucher_amount` max 5000; `cs_ai` binding sets max 500 → AI cannot pass 501 even though the macro ceiling is higher.

### Approval

- Each context binding may set `requires_approval` and/or `approval_threshold` (JSON).
- **Approval threshold** shape: variable name, `auto_approve_max`, optional `approval_role`, optional `blocked_above`. Values above `blocked_above` are rejected; between auto-approve and blocked may return `requires_approval` without executing steps.
- If status is `blocked` → caller receives an error envelope; no steps run.
- If status is `requires_approval` → caller receives success with `pending_approval` payload (resolved variables included); steps do not run until a separate approval path executes (approval workflow not fully specified here).

### Step execution

- Steps run in array order after validation and approval pass.
- Each step’s `params` object is scanned; string values matching `{{name}}` are replaced with resolved variables before dispatch.
- Inactive macros (`is_active = false`) cannot execute.
- CS conversation steps (`send_resource`, `send_text`, `add_note`, `close_conversation`, etc.) require `p_conversation_id`; without it, loyalty/value steps may still run but conversation mutations are skipped.

### Context availability

- A macro is runnable in a context only when an **enabled** `action_macro_context` row exists for that `context_type` (and matching `context_ref_id` when the binding is scoped).
- `bff_list_macros(p_context_type)` returns macros available for admin pickers filtered by context.

## Journeys

### Admin journey

| Page / surface | Owning repo | BFF / RPC |
| --- | --- | --- |
| Action Macro list & builder (planned) | loyalty-admin | `bff_list_macros`, `bff_get_macro_details`, `bff_upsert_macro_with_contexts`, `bff_delete_macro` |

| Knob | Effect on behaviour |
| --- | --- |
| Macro name, code, description | Identity in admin and execution logs |
| Steps (ordered JSON) | Sequence of actions executed at run time |
| Variable definitions | Ceiling for all contexts; drives agent/AI forms |
| Tags, sort order, active flag | Discovery ordering; inactive macros hidden from execution |
| Per-context rows | Which surfaces may run the macro; narrowed variables; approval |
| `context_type` + optional `context_ref_id` | Limits macro to CS role or AMP agent when set |
| `requires_approval` / `approval_threshold` | Supervisor gate for high-risk variable values |

1. Open **Action Macro** list (builder UI not yet wired in loyalty-admin as of verification — BFFs exist in generated types only).
2. Create or edit a macro: define steps and variable schema (`bff_get_macro_details` in `new` / `edit` mode).
3. Add one or more **context bindings** (same upsert payload `p_contexts` array): choose `cs_agent`, `cs_ai`, `amp_agent`, or `amp_rule`; tighten variables; set approval rules.
4. Save via `bff_upsert_macro_with_contexts` (parent macro + child contexts in one call).
5. In CS action settings or AMP agent/workflow configuration, attach enabled macros for that context (see **CS_Actions.md**, **AMP - AI Decisioning.md**, **AMP - Rule Based.md**).

### Member journey

None — macros are operator and automation infrastructure only.

### Operator journey

Covers CS agents, CS AI, and AMP when they run a macro (not merchant admin configuration).

| Actor | Surface | Entry |
| --- | --- | --- |
| CS agent | CS Inbox / Live Assist | Macro action control; fills variable form within role binding |
| CS AI | CS AI pipeline / MCP tools | Composite tool; variables chosen inside context constraints |
| AMP AI agent | Agent action of type execute macro | Tool invocation with `variable_config` / action constraints |
| AMP rule | Workflow action node | Pre-filled variables; no interactive form |

1. Caller selects macro enabled for its `context_type` (and `context_ref_id` when scoped).
2. Caller supplies runtime variables (or workflow stores pre-filled values).
3. System calls `fn_execute_macro` with macro id, context, merchant, target user, variables, and optional `conversation_id` / `workflow_id`.
4. On validation failure or block → error shown to operator or logged on conversation; no partial loyalty writes from failed validation.
5. On `requires_approval` → operator sees pending approval state; steps do not run.
6. On success → step results returned; CS sees new messages/notes; loyalty steps reflect wallet/tag changes via AMP action dispatch.

## System

### Data model

**`action_macro`** — Macro definition (merchant-scoped playbook).

| Column | Role |
| --- | --- |
| `id` | Primary key |
| `merchant_id` | Tenant scope (nullable in DB; BFFs should enforce merchant from JWT) |
| `domain` | Partition label; default `shared` (CS + AMP infrastructure) |
| `macro_code` | Optional stable code for integrations |
| `name`, `description` | Admin display |
| `steps` | JSON array: `{ "action", "params"? }` per step |
| `variable_definitions` | JSON schema ceiling for runtime variables |
| `tags`, `sort_order`, `is_active` | List UX and eligibility |
| `created_by`, `created_at`, `updated_at` | Audit; `set_updated_at` trigger |

**`action_macro_context`** — Per-surface binding and guardrails (CASCADE delete with macro).

| Column | Role |
| --- | --- |
| `id` | Primary key |
| `merchant_id`, `macro_id` | Tenant + parent macro |
| `context_type` | `cs_agent` \| `cs_ai` \| `amp_agent` \| `amp_rule` |
| `context_ref_id` | Optional scope: CS role id or `amp_agent` id |
| `variable_constraints` | JSON narrowing overrides |
| `requires_approval`, `approval_threshold` | Approval gate |
| `is_enabled`, `sort_order` | Binding active flag and ordering |
| `created_at`, `updated_at` | Audit; `set_updated_at` trigger |

### Steps and variables (JSON contracts)

**Steps** — Ordered array. Parameters may embed variables:

```json
[
  { "action": "send_resource", "params": { "resource_id": "{{apology_reply}}" } },
  { "action": "create_voucher", "params": { "amount": "{{voucher_amount}}" } },
  { "action": "assign_tag", "params": { "tag_id": "{{recovery_tag}}" } },
  { "action": "add_note", "params": { "content": "Recovery: ฿{{voucher_amount}} issued" } },
  { "action": "trigger_csat" }
]
```

**Variable definitions** — Per-variable metadata, for example:

```json
{
  "voucher_amount": {
    "type": "numeric",
    "label": "Voucher Amount (฿)",
    "min": 0,
    "max": 5000,
    "default": 100,
    "required": true
  }
}
```

Supported variable types: `numeric`, `text`, `tag`, `persona`, `resource_content`, `reward`, `audience`, `enum`, `boolean`.

**Approval threshold** example:

```json
{
  "variable": "voucher_amount",
  "auto_approve_max": 200,
  "approval_role": "cs_supervisor",
  "blocked_above": 1000
}
```

### Step action catalog

| Category | `action` | `params` | Live dispatch (`fn_execute_macro`) |
| --- | --- | --- | --- |
| Value | `award_currency` | `amount`, `currency`, `description` | `fn_execute_amp_action` |
| Value | `create_voucher` | `amount`, `voucher_type`, `reward_id` | Maps to `award_currency` with `currency: voucher` via `fn_execute_amp_action` |
| Value | `assign_earn_factor` | `earn_factor_id`, `window_end_days` | `fn_execute_amp_action` |
| Value | `process_refund` | `amount`, `reason` | **Not implemented** — skipped as unknown |
| Classification | `assign_tag`, `remove_tag`, `assign_persona`, `add_to_audience`, `remove_from_audience` | ids per action | `fn_execute_amp_action` |
| Content | `send_resource` | `resource_id` → `resource_content` | Inserts `cs_messages` with resource metadata when `p_conversation_id` set |
| Content | `send_text` | `content` | Inserts `cs_messages` (text) |
| Content | `send_message` | `channel`, `template_id` or `content` | **Not implemented** — skipped as unknown |
| System | `close_conversation` | — | Updates `cs_conversations.status` |
| System | `set_priority` | `priority` | Merges into `cs_conversations.metadata` |
| System | `add_note` | `content` | Inserts `cs_messages` (`message_type: note`) |
| System | `create_ticket` | `subject`, `priority` | Stub — returns queued note only |
| System | `escalate_to_human` | `reason` | Sets escalation flags in conversation metadata |
| System | `trigger_csat` | — | Stub — returns triggered note only |
| Integration | `api_call` | `url`, `method`, `body` | Stub — edge execution not wired from SQL |

Loyalty/value/classification steps delegate to **`fn_execute_amp_action`**, which is the same AMP action path used elsewhere (wallet, tags, earn factor, audiences). Point/ticket/reward side effects follow existing chokepoints documented in **Central_Outcome_Dispatcher.md** — this doc does not duplicate dispatch semantics.

Content steps use **`resource_content`** for `send_resource` (name/content, type, media/link URLs) and write outbound **`cs_messages`** rows tagged with `metadata.source = macro`.

### Functions

| Function | Role |
| --- | --- |
| `bff_upsert_macro_with_contexts` | Create/update macro + `p_contexts` children (with-children upsert) |
| `bff_get_macro_details` | Load macro + contexts (`p_mode` `new` / `edit`) |
| `bff_list_macros` | List macros; optional `p_context_type` filter |
| `bff_delete_macro` | Delete macro (contexts cascade) |
| `fn_validate_macro_variables` | Layer 1 + 2 validation; returns `resolved_variables` |
| `fn_check_macro_approval` | Threshold evaluation → `approved` / `requires_approval` / `blocked` |
| `fn_execute_macro` | Orchestrate validate → approve → resolve placeholders → per-step dispatch |

`fn_execute_macro` signature (live): `p_macro_id`, `p_context_type`, `p_context_ref_id`, `p_user_id`, `p_merchant_id`, `p_variables`, `p_conversation_id`, `p_workflow_id` → `jsonb` (`fn_response_*` envelope).

### Flows

**Admin save**

1. Admin UI → `bff_upsert_macro_with_contexts` (macro fields + contexts JSON).
2. Server validates merchant, persists `action_macro` and `action_macro_context` rows.

**Execution**

1. Caller → `fn_execute_macro(...)`.
2. Load active macro `steps`.
3. `fn_validate_macro_variables` → on failure, `VALIDATION_ERROR`.
4. `fn_check_macro_approval` on resolved variables → `blocked` or `pending_approval` short-circuit.
5. For each step: resolve `{{var}}` in params → `CASE` dispatch (AMP action vs `cs_messages` vs conversation update).
6. Return aggregated `step_results` on success.

**Cross-module attachment (product layer)**

| Context | Attachment pattern |
| --- | --- |
| CS agent | Macro buttons in inbox; role-filtered bindings |
| CS AI | Macro as composite MCP/tool; variables within `cs_ai` binding |
| AMP AI agent | Agent action `execute_macro` (see AMP AI doc) |
| AMP rule | Workflow node `execute_macro` with pre-filled variables |

### Known gaps

- **loyalty-admin UI** — BFFs are present in generated Supabase types; no dedicated macro list/builder routes found in app source (grep verification). Admin journey above reflects contract + planned UI.
- **Step stubs** — `trigger_csat`, `create_ticket`, `api_call` return placeholder results inside `fn_execute_macro`; no queue/edge handoff in SQL.
- **Catalog vs implementation** — `process_refund`, `send_message` appear in product catalog but are not handled in the live `CASE` (unknown → skipped).
- **Approval execution** — `requires_approval` response is defined; post-approval re-invocation path not documented here.
- **Design note** — Early schema discussion: `docs/Content_Resource_Schema_Proposal.md` (historical; live tables verified via Supabase MCP).

## Related

- **CS_Actions.md** — Callable action registry and caller config for CS AI/agents; macros complement single-action tools.
- **Resource_Content.md** — Content library rows referenced by `send_resource` steps.
- **Central_Outcome_Dispatcher.md** — How value steps that call `fn_execute_amp_action` grant points, tickets, rewards, or earn factors (link for grants only; macro orchestration stays here).
- **AMP - Rule Based.md** — Workflow action nodes including execute-macro style automation.
- **AMP - AI Decisioning.md** — AI agent actions, guardrails, and tool constraints when macros are exposed to agents.
- **CS_Live_Assist.md** — Agent workspace macros and copilot suggestions in conversation UI.
