# CS Voice Architecture — ElevenLabs STT/TTS + Graph Executor

> **Decision:** ElevenLabs for STT (Scribe v2) and TTS only. All AI decisioning on our infrastructure. Same agent, same AOPs, same tools as chat — different orchestration for real-time latency.
>
> **Pattern:** Decagon model — ElevenLabs as dumb pipe (ears + mouth), our graph executor as the brain.

---

## Architecture Overview

```
CHAT PATH (existing, unchanged):
  Platform webhook → Edge Function → DB → Inngest → inngest-cs-serve
    → [load-context → search-knowledge → evaluate-rules] sequential steps
    → step.invoke("agent.decide") → Render cs-ai-service (AgentKit + MCP)
    → send-reply via messaging-service → save-state
    Latency: 3-9s (acceptable for async chat)

VOICE PATH (new, same agent brain):
  Phone → Twilio → ElevenLabs (STT/TTS/VAD/telephony)
    → Custom LLM endpoint → voice-custom-llm Edge Function
    → Graph Executor on Render (parallel prefetch + single LLM call)
    → Same MCP tools on Render
    → Response text → ElevenLabs TTS → caller hears it
    Latency: ~1-1.5s (real-time voice)

POST-CALL (shared with chat):
  call.ended webhook → Inngest cs/voice.post-call
    → extract memory, save transcript, log analytics
```

---

## ElevenLabs Scope — STT/TTS Only

ElevenLabs handles voice infrastructure. It does NOT handle any reasoning.

```
ElevenLabs provides:                    ElevenLabs does NOT do:
  ✓ Scribe v2 STT (3.1% WER Thai)       ✗ Any reasoning or decision-making
  ✓ TTS (best-in-class voice quality)    ✗ Tool calling
  ✓ Voice Activity Detection (VAD)       ✗ Knowledge search
  ✓ Turn-taking / barge-in handling      ✗ AOP execution
  ✓ Telephony (Twilio SIP integration)   ✗ State management
  ✓ Audio streaming                      ✗ Customer data access
  ✓ Custom LLM mode (routes to us)
```

**Integration mode:** Custom LLM. ElevenLabs sends transcribed text to our endpoint in OpenAI Chat Completions format. We return response text. ElevenLabs speaks it.

**Thai STT:** ElevenLabs Scribe v2 — 3.1% WER on Thai (FLEURS benchmark). Best available. Handles Thai-English code-switching.

---

## Core Idea: Deterministic Prefetch

The performance difference between chat (3-9s) and voice (~1.1s) comes from one change: **the graph executor reads the AOP step's `data_needs` and fetches everything as code before the LLM call.** The LLM never makes data tool calls — it receives a complete picture and writes the response in one shot.

```
CHAT — LLM as Explorer (discovers needs mid-reasoning):
  LLM call 1: "I need order data" → tool_call: lookup_order      ~1.5s
  AgentKit executes tool via MCP                                   ~200ms
  LLM call 2: "Now I can answer"                                  ~1.5s
  Total agent: ~3.2s, 2 LLM calls

VOICE — Code as Explorer, LLM as Writer (everything pre-loaded):
  Graph: AOP step data_needs says "lookup_order"                   ~5ms
  Graph: regex extracts order_number = "12345" from message        ~5ms
  Graph: calls lookup_order("12345") directly as code              ┐
  Graph: calls search_knowledge("refund policy") directly as code  ├ ~300ms parallel
  Graph: loads conversation context from DB                        ┘
  LLM call 1: "Here's everything. Compose response."              ~800ms
  Total: ~1.1s, 1 LLM call
```

### How the Graph Executor Calls Tools

MCP tools are just functions exposed over a protocol. Any code can call them — not just LLMs. The graph executor and AgentKit both run on `cs-ai-service` (Render). The graph executor imports the same tool functions and calls them directly:

```
cs-ai-service (Render — Rocket-CRM/cs-ai-service)
  ├── /api/inngest        ← AgentKit (chat): LLM generates tool_call → AgentKit
  │                          invokes MCP tool → feeds result back to LLM
  │
  ├── /api/cs-voice-turn  ← Graph executor (voice): code reads data_needs →
  │                          code calls tool function directly → injects result
  │                          into LLM prompt → 1 LLM call
  │
  └── /mcp                ← CS MCP server: same tool functions called by both paths
        lookup_order()       Tools don't know or care who called them.
        search_knowledge()   They receive arguments, return data.
        process_refund()
        escalate_to_human()

amp-ai-service (Render — separate service, Rocket-CRM/amp-ai-service)
  └── /mcp                ← CRM/loyalty MCP: points, tags, personas
        award_points()       cs-ai-service calls this for loyalty actions
        assign_tag()
        assign_persona()
```

### Two Types of Tool Calls

| Type | Examples | Who calls it | When |
|---|---|---|---|
| **DATA tools** (read-only) | lookup_order, search_knowledge, get_customer_profile, check_stock, recent_orders | **Graph executor** (deterministic code) | Before LLM call — results injected into prompt |
| **ACTION tools** (write) | process_refund, award_points, create_ticket, escalate_to_human | **LLM** decides which, **code** executes | After LLM responds, async |

### Step-Level Prefetch (Not Blanket)

Each AOP step declares what data it needs in `data_needs`. Steps with no data requirements fetch nothing extra — no wasted API calls.

```
Step "Acknowledge Feelings":
  data_needs: []
  → Prefetch: context only (1 DB call, ~20ms). No embedding, no API calls.

Step "Explain & Offer Tips":
  data_needs: [{ source: "knowledge", query_hints: ["blind box policy"] }]
  → Prefetch: context + knowledge search (~200ms)

Step "Lookup Order":
  data_needs: [{ source: "lookup_order", args_from: { order_id: "order_number" } },
               { source: "knowledge", query_hints: ["refund policy"] }]
  → Prefetch: context + order API + knowledge search (~300ms, parallel)
```

### 3-Tier Prefetch Strategy

| Tier | Scenario | What the graph executor does | Latency |
|---|---|---|---|
| **Tier 1** | AOP step has `data_needs` with tool sources | Calls data tools directly as code. LLM receives everything. 1 LLM call. | ~1.1s |
| **Tier 2** | AOP step has knowledge-only or empty `data_needs` | Fetches knowledge (if declared) or just context. Walks code_conditions deterministically. LLM focused on current step. 1 LLM call. | ~0.8s |
| **Tier 3** | No AOP matched (unknown intent) | Fetches context + `default_data_needs`. LLM in explorer mode — may discover it needs tool calls. 2+ LLM calls. | ~2s |

### When Prefetch Misses

Prefetch works ~80% of turns. When it can't determine what data is needed:

- **Ambiguous message** ("มีปัญหาค่ะ"): No entities, no clear intent. Graph fetches context only. LLM asks clarifying question. ~800ms. No wasted calls.
- **Unpredictable data need** ("ดูโปรโมชั่น TikTok"): No AOP for this. LLM discovers it needs promotion data → falls back to explorer mode → tool call → 2nd LLM call. ~2s total. Filler phrase covers the gap.
- **Entities found but step doesn't need them**: Graph only fetches what `data_needs` declares. Extracted entities are stored for future steps, not fetched eagerly.
- **No entities found, AOP active**: Graph checks `default_data_needs.no_entities` (e.g., recent 3 orders). Provides fallback context without over-fetching.

---

## Graph Executor — AOP as Flowchart

The graph executor replaces AgentKit's tool-call loop for voice. It walks the AOP's `compiled_steps` deterministically and calls data tools directly as code.

```
AOP compiled_steps IS the graph:

  ┌──────────────────────────────────────────────────────────────┐
  │ 1. Understand Request                                        │
  │    variables_out: [return_type, product_type, order_number]  │
  │    data_needs: []  ← conversation only, no prefetch          │
  └──────────┬───────────────────────────────────────────────────┘
             ↓
  ┌──────────────────────────────────────────────────────────────┐
  │ 2. Check Eligibility                                         │
  │    required_variables: [purchase_channel, days_since_purchase]│
  │    data_needs: [knowledge("return policy")]                  │
  │    code_conditions evaluate against collected data            │
  └──┬────┬────┬────┬───────────────────────────────────────────┘
     ↓    ↓    ↓    ↓
  [Deny] [Defect] [Approve] [Expired]
     └────┴────┴───────┘
             ↓
  ┌──────────────────────────────────────────────────────────────┐
  │ 7. Wrap Up                                                   │
  │    data_needs: []  ← conversation only                       │
  └──────────────────────────────────────────────────────────────┘

Graph executor algorithm:
  1. Load procedure_state → determine current step
  2. Run entity_extractors against message (regex/keyword, no LLM)
  3. Read current step's data_needs
  4. Evaluate each data_need's "when" condition against extracted entities
  5. Call matching data tools directly as code (parallel)
  6. Evaluate code_conditions against collected + prefetched data (deterministic)
  7. Build focused LLM prompt: step_topic + step instructions + prefetched data
  8. ONE LLM call → response text + action tool list
  9. Stream response to caller
  10. Execute action_tools async (post-response)
  11. Save state for next turn
```

### Per-Turn Phases

```
Every voice turn runs these 5 phases:

PHASE 1 — Route + Extract (deterministic, ~10-20ms)
  Load procedure_state → current step index
  Run entity_extractors from compiled_steps:
    regex: order_number = "12345"
    keyword: product_type = "blind_box"
  Match intent if no active AOP (keyword heuristic → cs_fn_get_active_procedure)

PHASE 2 — Prefetch (step-aware, only what's declared, parallel)
  Read current step's data_needs[]:
    ALWAYS: conversation context (1 DB call, ~20ms)
    If data_needs includes knowledge source → embed + pgvector (~200ms)
    If data_needs includes lookup_order AND order_number extracted → Shopee API (~200ms)
    If data_needs includes check_stock AND product extracted → Inventory API (~150ms)
  All declared sources fetched in parallel (Promise.all)
  Empty data_needs → context only (~20ms)

  ┌────────────────────────────────────────────────────────┐
  │ Step "Acknowledge Feelings"  data_needs: []            │
  │   → Fetches: context only                   ~20ms      │
  │                                                        │
  │ Step "Explain & Offer Tips"  data_needs: [knowledge]   │
  │   → Fetches: context + knowledge search     ~200ms     │
  │                                                        │
  │ Step "Lookup Order"  data_needs: [lookup_order, know.] │
  │   → Fetches: context + order + knowledge    ~300ms     │
  └────────────────────────────────────────────────────────┘

PHASE 3 — Walk AOP graph (deterministic, ~5-10ms)
  Evaluate code_conditions against collected variables + prefetched data
  Determine which step to execute (may skip ahead if conditions are met)
  Build step-specific instruction using step_topic + raw_content for that step

PHASE 4 — ONE LLM call (writer mode, ~500ms-1s)
  System prompt: step instructions + tone + guardrails (context-compressed)
  Injected data: all prefetched results as facts (not for the LLM to discover)
  Message: customer's transcribed text
  LLM returns: response text + action tool list (from action_tools candidates)

PHASE 5 — Deliver + execute (partially async)
  Stream response text to ElevenLabs TTS (immediate, ~100ms to first audio)
  Execute action_tools in parallel: process_refund, award_points, etc. (post-response)
  Save procedure_state + message to DB (async, non-blocking)
```

---

## Entity Extraction (No LLM)

Entities are extracted using `entity_extractors` from the AOP's `compiled_steps`. These are regex and keyword patterns that run before any LLM call:

```
Defined in compiled_steps.entity_extractors[]:

  { variable: "order_number",  pattern: /\b(PM-?\d{4,8}|\d{5,8})\b/,  type: "regex" }
  { variable: "product_type",  keywords: ["blind box", "MEGA", "กล่องสุ่ม"],  type: "keyword" }
  { variable: "intent_keyword", keywords: ["คืนเงิน", "refund", "return"],  type: "keyword" }

Per-merchant patterns (from cs_merchant_config or procedure config):
  Phone numbers:   /\+?\d{9,12}/
  Product SKUs:    merchant-specific patterns
```

Extracted variables serve three purposes:
1. **Trigger data_needs**: `order_number IS NOT NULL` → graph executor calls `lookup_order("12345")`
2. **Populate tool arguments**: `args_from: { order_id: "order_number" }` resolves to `{ order_id: "12345" }`
3. **Route to AOP**: intent keywords help match procedure when no AOP is active yet

When extraction finds nothing → graph executor checks `default_data_needs.no_entities` (e.g., recent 3 orders). If that's also empty, only context is fetched. The LLM works with what it has — no wasted API calls.

---

## New Components

### Edge Functions

| Function | Purpose |
|---|---|
| `voice-custom-llm` | ElevenLabs Custom LLM endpoint. Receives transcribed text, runs graph executor logic (prefetch + LLM call), returns response text. Streaming support. |
| `webhook-elevenlabs` | Handles call lifecycle: `call.started` (resolve contact, create conversation + voice call record, map session), `call.ended` (save transcript, recording, duration, emit post-call event). |

### Render: Graph Executor Endpoint

New endpoint on `cs-ai-service` (repo: `Rocket-CRM/cs-ai-service`): `POST /api/cs-voice-turn`

Replaces AgentKit's multi-iteration LLM loop with single-pass deterministic execution:

```
Input:  { message_text, conversation_id, procedure_state }
Output: { response_text (streaming), action_tools[], updated_state }

Algorithm:
  1. Load procedure_state → current step
  2. Run entity_extractors against message_text
  3. Read step.data_needs → evaluate "when" conditions
  4. Call matching data tools directly as imported functions (parallel)
     → lookup_order(), search_knowledge(), etc. — same functions MCP exposes
  5. Evaluate code_conditions against collected variables
  6. Build step-focused LLM prompt (context compression: only current step + data)
  7. ONE LLM call → stream response text + action list
  8. Return response immediately
  9. Execute action_tools async (process_refund, award_points, etc.)
```

Both AgentKit (chat) and graph executor (voice) run on the same Render service and call the same tool functions. AgentKit routes through MCP protocol (LLM generates tool_call → AgentKit invokes). Graph executor calls the functions directly as code imports — no MCP protocol overhead, no LLM involvement for data fetching.

MCP tools remain unchanged — adding a new tool benefits both paths automatically.

### DB: `cs_voice_calls` Table

Voice-specific telephony metadata. 1:1 with `cs_conversations` for voice calls.

```
cs_voice_calls:
  id, conversation_id, merchant_id
  elevenlabs_agent_id, elevenlabs_call_id
  phone_from, phone_to, direction (inbound/outbound)
  sip_call_id
  call_status (ringing/in_progress/completed/failed/no_answer)
  started_at, answered_at, ended_at, duration_seconds
  recording_url, full_transcript
  transferred_to, transfer_summary
  disposition (resolved/escalated/voicemail/abandoned/callback_requested)
  created_at, updated_at
```

### DB: `cs_merchant_config` — voice_config column

```sql
ALTER TABLE cs_merchant_config ADD COLUMN voice_config jsonb DEFAULT '{}'::jsonb;
```

Structure:
```json
{
  "elevenlabs_agent_id": "agent_xxxx",
  "voice_id": "voice_xxxx",
  "greeting_mode": "personalized",
  "language": "th",
  "max_call_duration_seconds": 600,
  "silence_timeout_seconds": 10,
  "inbound_phone_numbers": ["+6621234567"]
}
```

### DB Functions

| Function | Type | Purpose |
|---|---|---|
| `cs_fn_create_voice_call` | Backend | Insert cs_voice_calls, link to conversation |
| `cs_fn_update_voice_call` | Backend | Update status, duration, recording, transcript |
| `cs_bff_get_voice_calls` | BFF | Admin: list voice calls with filters |
| `cs_bff_get_voice_call_details` | BFF | Admin: call details + transcript + recording |
| `cs_bff_upsert_voice_config` | BFF | Admin: save voice settings |

### Inngest Function

| Function | Event | Purpose |
|---|---|---|
| `cs/voice.post-call` | `cs/voice.call_ended` | Save full transcript, extract memory, trigger CSAT (SMS/LINE), log analytics |

### Credentials

ElevenLabs API key is a **platform-level secret**, not per-merchant. Stored as a Supabase edge function secret (`ELEVENLABS_API_KEY`), not in `merchant_credentials`.

Per-merchant config (agent ID, phone numbers, voice settings) is stored in `cs_merchant_config.voice_config`.

```
Platform-level (Supabase secrets):
  ELEVENLABS_API_KEY         → one account for entire platform
  GRAPH_EXECUTOR_URL         → Render AI service URL
  INNGEST_SIGNING_KEY        → already configured
  INNGEST_EVENT_KEY          → already configured

Per-merchant (cs_merchant_config.voice_config):
  elevenlabs_agent_id        → different voice/behavior per brand
  voice_id                   → TTS voice selection
  inbound_phone_numbers      → each brand has own phone number
  greeting_mode, language, max_call_duration_seconds
```

---

## Implementation Plan

### Phase 1 — ElevenLabs Setup (1-2 days)
- Create ElevenLabs account, configure agent with Custom LLM mode
- Get Twilio phone number (Thai regulatory docs required)
- Import Twilio number into ElevenLabs
- Configure voice (Thai female/male), language, VAD settings
- Test with simple echo endpoint (Custom LLM returns static response)

### Phase 2 — DB Migration (30 min)
- Create `cs_voice_calls` table
- Add `voice_config` column to `cs_merchant_config`
- Add ElevenLabs credential to `merchant_credentials`

### Phase 3 — Webhook + Session Mapping (2-3 days)
- `webhook-elevenlabs` Edge Function
  - call.started: resolve contact by phone, create conversation (modality='voice'), create voice call record, map ElevenLabs session to conversation_id
  - call.ended: update voice call (duration, recording, transcript), emit Inngest event

### Phase 4 — Graph Executor on Render (3-5 days)
- New endpoint: `POST /api/cs-voice-turn` on cs-ai-service
- Entity extraction (regex/keyword)
- Parallel prefetch (context + KB + order + AOP)
- AOP graph walking (compiled_steps navigation, code_condition evaluation)
- Single LLM call with focused prompt
- Streaming response support (OpenAI Chat Completions format)
- Async action tool execution

### Phase 5 — Custom LLM Edge Function (2-3 days)
- `voice-custom-llm` Edge Function
  - Receives OpenAI format from ElevenLabs
  - Resolves session → conversation_id
  - Calls graph executor on Render
  - Streams response back to ElevenLabs
  - Async: save message to DB

### Phase 6 — DB Functions + Post-Call (1-2 days)
- `cs_fn_create_voice_call`, `cs_fn_update_voice_call`
- `cs_bff_get_voice_calls`, `cs_bff_get_voice_call_details`
- `cs_bff_upsert_voice_config`
- Inngest `cs/voice.post-call` (transcript save, memory extraction, analytics)

### Phase 7 — Frontend (3-5 days)
- Voice calls in inbox (phone icon, duration badge)
- Call detail view: transcript viewer, audio player, AI summary
- Voice config in brand settings (voice selection, greeting, phone numbers)

### Phase 8 — Testing + Optimization (2-3 days)
- End-to-end call testing (Thai + English)
- Latency measurement per phase
- Filler phrase tuning (system prompt)
- AOP coverage testing (all 6 active AOPs on voice)
- Fallback testing (ambiguous messages, no entities)

**Total: ~3-4 weeks to production voice.**

---

## Chat Path — Optional Optimization

The graph executor pattern also speeds up chat by eliminating Inngest step overhead:

| Optimization | Impact | Effort |
|---|---|---|
| Parallelize load-context + search-knowledge in Inngest (Promise.all) | 5.5s → 4s | 1 hour |
| Collapse first 3 steps into one Inngest step with internal parallelism | 4s → 3s | Half day |
| Route chat through graph executor too (bypass Inngest for real-time) | 3s → 1.5s | 1 week |

Phase 3 (chat through graph executor) would give you one brain for both channels — same as Decagon. Optional, evaluate after voice is live.
