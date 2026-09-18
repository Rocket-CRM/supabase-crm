# CS AI System

Product vision for CS AI: knowledge-backed, procedure-guided replies with guardrails, live-data tools, and human copilot — **composition of config + retrieval + AOP + MCP**, not a single “CS agent” row (contrast AMP `amp_agent`).

Owner surfaces: loyalty-admin (**CS Knowledge**, **CS Procedures**, **CS Brand Config**), **CS Inbox**, member channels

> **Vision doc — not runtime contract.** Deployed stages, services, and tool names: **`CS_AI_Pipeline.md`**. Schema details: modular `CS_*.md` + registry.

## Concept

**Knowledge library** — Unstructured FAQs in articles/embeddings; **never** treat embeddings as source of truth for order status, inventory, or refunds — use tools.

**Customer context** — Tiered: contact profile, recent messages, optional loyalty snapshot, on-demand memory and history.

**Procedure (AOP)** — Intent-specific playbook the model follows; engine enforces code conditions and tool allowlists.

**Guidance & guardrails** — Merchant-wide tone/topic rules (`cs_merchant_config`, `cs_merchant_guardrails`) plus per-procedure policy text.

**Custom answers** — Pattern-matched authoritative replies before generation.

**Copilot** — Agent-facing drafts and sidebar assist `(partially shipped)` — **`CS_Live_Assist.md`**.

**Multi-model strategy (evolution)** — Phase 1: frontier model + context injection; later optional specialized classifiers (intent, hallucination check) as data volume grows — infrastructure in Render, not separate DB “sub-agent” rows.

## Rules

- Retrieval for prose policies; MCP/tools for transactional and marketplace APIs.
- Per-brand isolation on knowledge, procedures, config, memory.
- Custom answers and matched rules outrank generic generation.
- Knowledge-gap / watchtower signals are **advisory** — admins publish content deliberately.
- Product catalog **descriptions** may live in knowledge; **listings and orders** are channel-scoped tool reads.
- Supervisor / verification passes apply to high-risk actions (refunds, cancellations) per action config.

## Journeys

### Admin journey

| Knob | Effect |
| --- | --- |
| Knowledge & sources | Retrieval corpus |
| Custom answers | Deterministic overrides |
| Guardrails | Topic / escalation rows |
| Procedures | Intent playbooks |
| Brand voice & models | Defaults and pipeline model picks |

| Page | Owning repo | Truth doc |
| --- | --- | --- |
| **CS Knowledge** | loyalty-admin | `CS_Knowledge_Base.md` |
| **CS Procedures** | loyalty-admin | `CS_Procedures.md` |
| **CS Brand Config** | loyalty-admin | `CS_Platform_Features.md`, `CS_AI_Pipeline.md` |

1. Publish active knowledge; mark custom answers for top intents.
2. Author procedures with `@` tools and code conditions.
3. Configure guardrails and voice; validate in inbox with test traffic.
4. Review analytics gaps (`CS_Analytics.md`) — do not auto-publish from signals alone.

### Agent journey

1. Open thread — see AI draft or run knowledge search in content panel (partial copilot).
2. Edit and send; tool-heavy steps may already have run in autonomous mode before takeover.
3. Escalation preserves summary context on case log/events.
4. Close — memory extraction async per pipeline.

### Member journey

1. Messages on channel → AI or human replies after pipeline or agent send.
2. No separate “AI settings” UI for members.

## System

### Composition (runtime)

At turn time the pipeline assembles: `cs_fn_load_merchant_ai_config` + guardrails + retrieval (`cs_fn_search_knowledge`, custom answer match) + active procedure (`cs_fn_get_active_procedure`) + action registry (`cs_fn_load_action_config`) + contact memory + messages. Execution on **`cs-ai-service`** (AgentKit chat, graph executor voice) — see **`CS_AI_Pipeline.md`**.

### Vision components → owning doc

| Component | Doc |
| --- | --- |
| Articles, embeddings, sources | `CS_Knowledge_Base.md` |
| AOP authoring, compile, state | `CS_Procedures.md` |
| Tools, refunds, loyalty bridge | `CS_Actions.md` |
| Pre-LLM automation | `CS_Rules_Engine.md` |
| Contact memory extract | `CS_Channels.md` |
| Copilot UX | `CS_Live_Assist.md` |
| Umbrella rename map | `CS_Feature_Spec.md` |

### Flows (conceptual)

**Reasoning** — Classify intent → bind procedure step → LLM within step constraints → optional MCP loop → guardrail/supervisor checks on actions → outbound message.

**Memory** — Post-resolution extractor distills durable facts to `cs_customer_memory`; injected on next contact.

**Testing / simulation** — Target: procedure sandbox and regression suites (`CS_Platform_Features.md`); not all vision scenarios shipped.

### Known gaps

- Legacy plan §4 (800+ lines) described aspirational UI (simulation lab, advanced copilot, fine-tuned model fleet) — **removed from this file**; do not treat removed prose as deployed.
- `cs_brand_config` naming in old plans → live `cs_merchant_config` + `cs_merchant_guardrails`.
- When vision and pipeline disagree, **`CS_AI_Pipeline.md` wins**.

## Related

- **CS_AI_Pipeline.md** — Deployed path (mandatory for engineering).
- **CS_Feature_Spec.md** — Module map and composition principle.
- **CS_Procedures.md** / **CS_Knowledge_Base.md** — Authoring surfaces.
- **CS_Live_Assist.md** — Copilot shipped vs planned.
