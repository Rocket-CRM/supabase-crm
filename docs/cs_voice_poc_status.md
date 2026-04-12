# CS Voice POC — Status & Issues Log

> **Date:** 2026-04-05
> **ElevenLabs Agent:** `agent_0501kneww6ene0h98pfxcgmcqyqk` (Rocket-AI-CS)
> **Render Service:** `cs-ai-service` v1.2.0 (`https://cs-ai-service.onrender.com`)
> **Edge Functions:** `voice-custom-llm` v12, `webhook-elevenlabs` v1, `voice-debug` v1

---

## Architecture (Verified Working)

```
ElevenLabs (Custom LLM mode, V3 Conversational, Anna - Thailand Female)
  ↓ STT: transcribes Thai/English speech
  ↓ sends text in OpenAI Chat Completions format
  ↓
voice-custom-llm Edge Function (Supabase)
  ↓ finds/creates voice conversation
  ↓ loads procedure_state from cs_conversations
  ↓
POST /api/cs-voice-turn on cs-ai-service (Render)
  ↓ Phase 1: entity extraction + keyword intent matching
  ↓ Phase 2: step-aware prefetch (data_needs)
  ↓ Phase 3: AOP graph walk (code_conditions)
  ↓ Phase 4: LLM call (Haiku 4.5)
  ↓ returns: response_text + updated_state + actions
  ↓
voice-custom-llm Edge Function
  ↓ saves procedure_state (direct update)
  ↓ saves messages (direct insert)
  ↓ returns SSE response
  ↓
ElevenLabs
  ↓ TTS: speaks Thai response
  ↓ VAD/turn-taking/barge-in: manages call flow
```

---

## What Works

| Feature | Status | Notes |
|---|---|---|
| Thai STT | Working | ElevenLabs Scribe, Original ASR model |
| Thai TTS | Working | V3 Conversational model, Anna - Thailand Female voice |
| VAD / turn-taking / barge-in | Working | ElevenLabs handles audio layer |
| AOP matching | Working | Keyword intent matching: "refund" → Return Handler |
| Procedure state persistence | Working | Saves to cs_conversations.procedure_state between turns |
| Data collection | Working | LLM collects order_number, customer_name, product_condition etc. |
| ค่ะ particle | Working | Prompt enforces feminine particles |
| Anti-hallucination | Working | Prompt says "ORDER DATA NOT AVAILABLE" when no order lookup |
| Graph executor | Working | Tier 2 execution, AOP-guided prompts |
| ElevenLabs preview testing | Working | Auto-creates conversation for preview mode |

---

## Known Issues (Fix Next Session)

### 1. Step Advancement (Critical)

**Problem:** Graph executor stays on `current_step: 1` even after the LLM collects all required data (order number, customer name, product condition).

**Root cause:** The AOP walker (`aop-walker.ts`) checks `required_variables` against `dataCollected`, but `dataCollected` only contains entity-extracted variables (from regex/keyword). The LLM returns collected data in its `data_collected` JSON field, which gets saved to `procedure_state.data_collected` — but this is NOT fed back into the walker's variable pool on the next turn.

**Fix:** In `graph-executor.ts`, when loading `procedure_state` on follow-up turns, merge `procedure_state.data_collected` into the `dataCollected` variable that the AOP walker reads:

```typescript
if (procedure_state) {
    dataCollected = { ...(procedure_state.data_collected || {}) };
    // ^ This line already exists but data_collected from LLM
    //   uses different variable names than required_variables expects
}
```

The deeper issue: the LLM uses descriptive names (`customer_name`, `product_condition`) but `required_variables` expects specific names from `code_conditions` (`purchase_channel`, `days_since_purchase`, `is_defective`). The variable names don't match.

**Solution options:**
- A) Add a mapping layer between LLM data_collected keys and AOP required_variables
- B) Have the prompt instruct the LLM to use the exact variable names from `variables_out`
- C) Let the LLM explicitly output `current_step` to advance, instead of relying on the walker

### 2. LLM Latency (~2.5s)

**Problem:** Haiku 4.5 is deployed (`VOICE_LLM_MODEL=claude-haiku-4-5-20251001`) but responses take ~2.5s.

**Possible causes:**
- Conversation history in prompt (24+ old messages were bloating it, now cleaned)
- System prompt is large (AOP raw_content + guardrails + anti-hallucination + customer context)
- Haiku 4.5 might genuinely be ~2s for structured JSON output
- Render cold start on first request

**Fix:** Test with clean conversation (no history). If still slow, reduce prompt size. Consider GPT-4o-mini as alternative.

### 3. Edge Function Uses Direct DB Access

**Problem:** `voice-custom-llm` uses `.from().update()` and `.from().insert()` instead of RPC functions. Bypasses business logic (event logging, timestamp updates).

**Fix:** Revert to RPC calls now that root cause is fixed:
- `cs_fn_save_procedure_state` — works (tested directly)
- `cs_fn_insert_message` — requires `p_merchant_id` (now available from context)

### 4. Messages Not Saving (msg_count: 0)

**Problem:** Latest test shows `msg_count: 0` despite direct inserts.

**Possible cause:** `cs_messages` table might have NOT NULL columns that the direct insert doesn't provide. Or RLS is blocking despite service role key.

**Fix:** Check cs_messages required columns, revert to `cs_fn_insert_message` RPC.

### 5. Thai Language in ElevenLabs

**Problem:** Thai not available in the ElevenLabs language dropdown (only 31 languages in Multilingual v2). Workaround: V3 Conversational model auto-detects Thai from text.

**Status:** Working with V3 Conversational. Language dropdown left as English but agent speaks Thai correctly.

---

## Root Causes Found (This Session)

| Issue | Root cause | Fix applied |
|---|---|---|
| AOP never matched (Tier 3 always) | `cs_fn_load_conversation_context` didn't include `merchant_id` in conversation object | Added `merchant_id` to function return |
| Procedure state not saving | Edge function used fire-and-forget `Promise.all` — Deno terminated before saves completed | Changed to `await` before returning response |
| Error message every turn | Haiku model name `claude-3-5-haiku-20241022` was retired Feb 2026 | Updated to `claude-haiku-4-5-20251001` |
| Render not deploying new code | Auto-deploy processed commit but used cached build artifacts | Manual "Clear build cache & deploy" fixed it |
| ครับ/ค่ะ mixing | No gender instruction in system prompt | Added "You are female, always use ค่ะ" |
| Hallucinating order data | No guardrail about missing data | Added "ORDER DATA NOT AVAILABLE" in prompt when no prefetch |
| New conversation every turn | Edge function used module-level variable (stateless in Deno) | Changed to DB lookup for existing open conversation |
| Messages not saving | `cs_fn_insert_message` requires `p_merchant_id`, not passed | Added merchant_id to RPC call / switched to direct insert |

---

## Infrastructure

### Supabase Secrets (configured)

| Secret | Status |
|---|---|
| `ELEVENLABS_API_KEY` | Set (platform-level) |
| `GRAPH_EXECUTOR_URL` | Set → `https://cs-ai-service.onrender.com` |
| `INNGEST_SIGNING_KEY` | Already existed |
| `INNGEST_EVENT_KEY` | Already existed |

### ElevenLabs Agent Config

| Setting | Value |
|---|---|
| Agent name | Rocket-AI-CS |
| Agent ID | `agent_0501kneww6ene0h98pfxcgmcqyqk` |
| LLM | Custom LLM |
| Server URL | `https://wkevmsedchftztoolkmi.supabase.co/functions/v1/voice-custom-llm` |
| Model ID | `cs-voice-agent` |
| Voice | Anna - Thailand Female |
| TTS model | V3 Conversational (Alpha) |
| ASR model | Original ASR |
| Language | English (Thai auto-detected by V3) |
| Interruptible | On |

### Render cs-ai-service

| Detail | Value |
|---|---|
| URL | `https://cs-ai-service.onrender.com` |
| Version | 1.2.0 |
| Voice LLM | `claude-haiku-4-5-20251001` |
| AgentKit LLM | `claude-sonnet-4-20250514` |
| Auto-deploy | Needs manual trigger or clear cache for code updates |

### DB Migrations Applied (this session)

| Migration | Purpose |
|---|---|
| `add_tool_type_to_action_config` | tool_type column for data/action/delivery classification |
| `create_cs_fn_compile_procedure` | AOP compiler with data_needs, action_tools, entity_extractors |
| `create_cs_voice_calls_and_config` | cs_voice_calls table + voice_config column |
| `create_voice_db_functions` | 5 voice DB functions |
| `update_bff_upsert_procedure_auto_compile` | Auto-compiles on procedure save |
| `fix_compiler_dedup_and_hints` | Deduplicated required_variables + query_hints |
| `fix_context_missing_merchant_id` | Added merchant_id to cs_fn_load_conversation_context return |

---

## Debug Tools

### voice-debug Edge Function

Test graph executor directly without ElevenLabs:

```
https://wkevmsedchftztoolkmi.supabase.co/functions/v1/voice-debug?msg=I%20want%20a%20refund
```

Shows: tier, AOP matched, updated_state, LLM timing, raw response.

### Render Health

```
https://cs-ai-service.onrender.com/health
```

Shows: version, voice LLM model, AgentKit model.
