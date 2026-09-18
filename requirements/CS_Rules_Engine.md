# CS Rules Engine

**Deterministic automation** on conversation events: triggers, conditions, and actions (auto-reply, assign, tag, escalate) — evaluated in the AI **prepare-context** step and event hooks.

Owner surfaces: loyalty-admin **CS Workflows**, Postgres `workflow_*` rows with CS domain, `cs_fn_evaluate_rules`

## Concept

**CS workflow** — Row on shared `workflow_master` (CS domain) with nodes/edges/triggers — same machinery as AMP, different templates and actions.

**Trigger** — Typically `message_received`; also assignment/status/SLA-adjacent events `(product-dependent)`.

**Condition** — Channel, tags, keywords, intent, sentiment, business hours, tier — as configured in workflow graph.

**Action** — Auto-reply, assign team/agent, tags, priority, internal note, webhook, start procedure `(verify node types in admin)`.

## Rules

- **`cs_fn_evaluate_rules(p_merchant_id, p_conversation_id, p_event_type)`** — Runtime entry; called in parallel during pipeline prepare-context.
- **Short-circuit** — Rule may emit deterministic reply → skip LLM (`CS_AI_Pipeline.md`).
- **Precedence** — Workflow ordering/priority configured in builder; first-match vs all-match is product setting — verify CS Workflows UI.
- **Complement AOPs** — Workflows = fast deterministic layer; procedures = multi-turn AI layer (`CS_Feature_Spec.md`).
- **Planned triggers** in old product spec (sentiment-only, external order webhooks) — implement only when node types exist in registry/UI.

## Journeys

### Admin journey

| Knob | Effect |
| --- | --- |
| Workflow active flag | Enables evaluation |
| Trigger + conditions | When rule runs |
| Action nodes | Side effects on conversation/ticket |

| Page | Owning repo | RPC |
| --- | --- | --- |
| **CS Workflows** | loyalty-admin | AMP/CS workflow BFFs (`workflow_master` upsert patterns) |

1. Clone template or build graph for routing/auto-reply.
2. Enable and monitor via workflow logs / analytics.
3. Test with sample conversation `(simulator — CS_Platform_Features.md)`.

### Agent journey

Rules run invisibly before AI turn; agent sees tags, assignment, or canned first message.

### Member journey

May receive auto-reply before human/AI if rule fires on inbound message.

## System

### Data model

Shared: `workflow_master`, `workflow_node`, `workflow_edge`, `workflow_trigger`, `workflow_log` with CS domain discriminator. Action types from `action_registry` / caller config (`CS_Actions.md`).

### Functions

| Function | Role |
| --- | --- |
| `cs_fn_evaluate_rules` | Evaluate CS workflows for merchant + conversation + event type |
| `cs_fn_auto_assign` | Target of some escalate/assign actions |

### Flows

Inbound message → prepare-context `Promise.all` includes rules → if action includes reply text, deliver and stop pipeline → else continue to AgentKit.

SLA approaching/breach may trigger workflow `(coordinate CS_SLA.md` + cron `cs_fn_check_sla_breaches`)`.

### External services

Inngest CS worker invokes DB; no separate rules microservice.

### Known gaps

- Visual rule builder parity with AMP canvas — confirm which trigger/condition nodes CS Workflows exposes in loyalty-admin.
- Section 3.x trigger catalog in legacy spec is **aspirational** until node registry lists each type.

## Related

- **CS_AI_Pipeline.md** — prepare-context short-circuit.
- **CS_Unified_Inbox.md** — Auto-ticket/assign outcomes.
- **CS_SLA.md** — Timer-based triggers.
- **AMP_Workflows.md** — Shared workflow engine.
