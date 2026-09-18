# CS AI Pipeline

**Deployed runtime** from inbound webhook through rules/custom answers, LLM + MCP tools, outbound send, and state persistence — shared procedure brain for chat; graph executor for voice.

Owner surfaces: `cs-ai-service` (Render), Supabase Edge `inngest-cs-serve`, channel webhooks, loyalty-admin **CS Inbox**

> **Contract doc** — Product vision and aspirational tables live in `CS_AI_System.md`; this file wins for stages, services, and entrypoints.

## Concept

**Prepare context** — Single Inngest step runs in parallel: full conversation bundle, custom-answer match, CS workflow rules.

**Short-circuit** — Matching rule or custom answer can reply without LLM.

**Agent turn (chat)** — Render AgentKit: intent + active AOP step, MCP tool loop on same service, parse reply + procedure state.

**Agent turn (voice)** — Graph executor: regex entity extract, prefetch `data_needs` as code, one LLM call, stream to TTS; actions async after speak.

**Loyalty bridge** — Points/tags/personas via `amp-ai-service` MCP (`CRM_MCP_URL`), not direct wallet writes from CS.

## Rules

- **Idempotent Inngest steps** — Retries must not double-send; message dedup on system/ai inserts (`CS_Conversations.md`).
- **Human takeover** — Pipeline skips autonomous outbound while conversation in human-only mode (inbox product rule).
- **Credentials** — Platform `OPENAI_API_KEY` on Render; ElevenLabs platform secret; per-merchant `cs_merchant_config.voice_config` for agent id and inbound numbers.
- **Chat latency target** — ~3–5s per turn with parallelized prepare-context (was ~5–9s sequential).
- **Voice latency target** — ~0.8–1.5s per turn with prefetch + single LLM call.

## Journeys

### Admin journey

No dedicated pipeline screen — behavior changes via **CS Brand Config**, **CS Knowledge**, **CS Procedures**, tool allowlists (`CS_Actions.md`), and CS workflows.

### Agent / member journey

1. Member sends message → edge validates → `cs_api_receive_message` → Inngest `cs/message.received`.
2. `inngest-cs-serve` prepare-context → optional auto-reply → else AgentKit turn → `cs-send-message` / adapter.
3. Agent may reply manually anytime; pipeline respects takeover flags.
4. Voice: caller speaks → ElevenLabs STT → `voice-custom-llm` edge → `/api/cs-voice-turn` → TTS (`CS_Voice.md`).

## System

### External services

| Service | Role |
| --- | --- |
| **cs-ai-service** (Render) | `/api/inngest` AgentKit + memory extractor; `/api/cs-voice-turn` graph executor; `/mcp` CS tools |
| **amp-ai-service** (Render) | Loyalty MCP when CS awards points/tags |
| **inngest-cs-serve** (Edge) | Orchestrates prepare-context, invoke Render, deliver, save state, wait |
| **messaging-service** (Render) | Outbound marketplace/LINE/etc. |
| Channel edges | `webhook-line`, `webhook-lazada-cs`, `webhook-doopage-cs`, Twilio voice/SMS |

Inngest app id: `cs-agent-service`. Platform secrets: `INNGEST_*`, `GRAPH_EXECUTOR_URL`, `ELEVENLABS_API_KEY` (Supabase vault).

### Functions (DB helpers in path)

`cs_fn_load_conversation_context`, `cs_fn_match_custom_answer`, `cs_fn_evaluate_rules`, `cs_fn_get_active_procedure`, `cs_fn_save_procedure_state`, `cs_fn_search_knowledge`, `cs_fn_insert_message`, `cs_fn_extract_customer_memory` (post-close).

### Flows — chat path

```
Webhook → cs_api_receive_message → inngest.send(cs/message.received)
→ step prepare-context (Promise.all: context, custom answer, rules)
→ if short-circuit: outbound reply, stop
→ step.invoke cs-ai-service AgentKit (intent, AOP step, MCP loop)
→ deliver-ai-reply → messaging-service
→ save procedure_state → wait for next message or resolve
```

**AgentKit loop (Render)** — Code: classify intent, load compiled steps, evaluate code conditions. LLM: reason within step, call MCP tools (`lookup_order`, `search_knowledge`, `process_refund`, `escalate_to_human`, `create_ticket`, …). Loyalty tools proxy to amp MCP.

### Flows — voice path

ElevenLabs handles STT/TTS only; reasoning on graph executor. Phases: entity extract → prefetch per `data_needs` → walk code conditions → one LLM call → stream TTS → async action tools. Post-call Inngest: memory extract, analytics (`cs/voice.call_ended`).

Tier table: tool prefetch (1 LLM) → knowledge-only (1 LLM) → no AOP explorer fallback (2+ LLM).

### MCP tool split

- **DATA tools** — Chat: LLM invokes via MCP. Voice: graph executor imports and calls directly.
- **ACTION tools** — Chat: inside AgentKit loop with guardrails. Voice: often after response spoken.

### Known gaps

- Diagram assets in repo may still show sequential DATA PREP — update to parallelized + dual path when publishing architecture slides.
- Exact MCP tool names must match deployed `/mcp` manifest — grep `cs-ai-service` repo when adding tools.
- `docs/cs_ai_pipeline_steps.md`, `docs/cs_graph_executor_implementation.md`, `docs/cs_voice_architecture.md` — engineering deep dives; keep in sync on stage renames.

## Related

- **CS_AI_System.md** — Vision, knowledge/guardrails product model (non-runtime).
- **CS_Voice.md** — `cs_voice_calls`, Twilio, ElevenLabs wiring.
- **CS_Actions.md** — Registry and marketplace bridges.
- **CS_Rules_Engine.md** — Pre-LLM `cs_fn_evaluate_rules`.
- **CS_Conversations.md** — Ingress and message dedup.
