# CS Procedures

**Agent Operating Procedures (AOPs)** — versioned playbooks keyed by intent that constrain tools, steps, tone, and escalation for chat/voice AI.

Owner surfaces: loyalty-admin **CS Procedures**, `cs-ai-service` (AgentKit + graph executor)

## Concept

**Procedure** — `trigger_intent`, natural-language `raw_content`, machine `compiled_steps`, per-procedure `config` (tone, limits).

**Flexibility** — `strict`, `guided`, or `agentic` — how tightly the engine enforces step order vs LLM navigation.

**Procedure state** — JSON on `cs_conversations`: active step, variables, tool results between turns.

**Tool reference** — `@Tool Name` in AOP text resolves through action/MCP registry (`CS_Actions.md`).

**Compilation** — Authoring stays in prose; `cs_fn_compile_procedure` / admin upsert produces structured steps for prefetch and code conditions.

## Rules

- **`CODE CONDITION`** — Evaluated in code against collected variables; LLM cannot override branch outcomes.
- **Navigation** — LLM-driven step choice with procedure as guidance (Sierra/Decagon style), not rigid tree DFS; **Strict** mode approaches ordered enforcement.
- **Overrides** — Procedure `tone_override` beats channel config beats merchant brand voice.
- **Versioning** — Edit creates new row, increments `version`, deactivates prior; only one active row per `trigger_intent` per merchant.
- **Activation** — Activating one version deactivates siblings with same intent (`cs_bff_activate_procedure`).
- **Escalation steps** — Must call registered escalate tools; supervisor verification for high-risk actions (`CS_Actions.md`).

## Journeys

### Admin journey

| Knob | Effect |
| --- | --- |
| Trigger intent | Binds classification → procedure |
| Flexibility | Strict / guided / agentic |
| Raw content | LLM-readable steps and `@` tools |
| Compiled steps | Optional JSON from compile pipeline |
| Active flag | Which version runs in production |

| Page | Owning repo | BFF / RPC |
| --- | --- | --- |
| **CS Procedures** | loyalty-admin | `cs_bff_get_procedures`, `cs_bff_get_procedure`, `cs_bff_get_procedure_versions`, `cs_bff_upsert_procedure`, `cs_bff_activate_procedure`, `cs_bff_delete_procedure` |

1. Author AOP with steps, code conditions, and tool refs.
2. Save → new version; activate when ready.
3. Test via simulator / staging merchant (`CS_Platform_Features.md`).

### Agent journey

1. Pipeline or rules attach `active_procedure_id` after intent match.
2. AI advances steps; agent may takeover — human sends bypass autonomous loop per inbox rules.
3. State persisted between customer turns via `cs_fn_save_procedure_state`.

## System

### Data model

**`cs_procedures`** — `name`, `description`, `trigger_intent`, `flexibility`, `raw_content`, `compiled_steps` jsonb, `config` jsonb, `is_active`, `version`, `created_by`, timestamps.

**Conversation link** — `cs_conversations.active_procedure_id`, `procedure_state`.

### Compiled step shape (summary)

Steps include: index, name, `step_topic`, `tools`, variables in/out, `required_variables`, `data_needs` (knowledge/order prefetch), `action_tools`, `code_conditions`, branches, `skip_condition`. Optional `entity_extractors` and `default_data_needs` for unknown intents.

**Graph executor tiers** — (1) prefetch tool `data_needs` + one LLM call; (2) knowledge-only prefetch; (3) explorer mode with MCP tool loop when no AOP matches (voice path / fallback).

### Functions

| Function | Role |
| --- | --- |
| `cs_fn_get_active_procedure` | Resolve active row for merchant + intent |
| `cs_fn_compile_procedure` | Parse raw → compiled_steps |
| `cs_fn_save_procedure_state` | Persist runtime state on conversation |
| `cs_bff_upsert_procedure` | Create versioned row |
| `cs_bff_activate_procedure` | Toggle active + deactivate siblings |

### Flows

Chat: `inngest-cs-serve` loads context → optional knowledge search → `step.invoke` Render AgentKit with procedure + guardrails → save state → outbound send.

Voice: graph executor on `/api/cs-voice-turn` — deterministic prefetch + single LLM call (`CS_Voice.md`).

### Known gaps

- Full simulator UX may lag backend compile format — verify loyalty-admin procedure editor fields against live BFF payload.
- Grab-style tree planner explicitly **not** chosen — do not document DFS executor as shipped.

## Related

- **CS_Actions.md** — Tools referenced by `@` names.
- **CS_AI_Pipeline.md** — When procedures attach to a turn.
- **CS_Rules_Engine.md** — Auto-route intent before AOP lookup.
- **CS_Knowledge_Base.md** — Step `data_needs` knowledge hints.
