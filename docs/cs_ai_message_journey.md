# CS AI — Message Journey (Detailed Call-by-Call)

> Same style as AMP workflow execution trace. Shows every Inngest Cloud ↔ inngest-cs-serve call, and the AgentKit inner loop on Render.

---

## SETUP

```
Customer "สมชาย" (Gold tier) messages on Shopee:
"I want a refund for order 12345, the item was damaged"

Merchant has:
  - Brand guardrails: max refund 5,000 THB, formal Thai
  - CS workflows (same engine as AMP, domain='cs'):
      Rule 1: IF message contains 'refund' → tag:refund, priority:urgent
      Rule 2: IF semantic_match('return policy', threshold:0.85) → auto-reply [exact answer]
  - Knowledge base: refund policy articles (vector search via pgvector)
  - No specific AOP for refund yet (AI uses knowledge + reasoning)
```

---

## WEBHOOK ENTRY POINT

```
Shopee platform sends webhook POST to Supabase

  → Edge Function: webhook-shopee
      Validates Shopee signature
      Calls DB: cs_api_receive_message(merchant_id, 'shopee', 'buyer_789', message_text)
        → internally calls: cs_fn_resolve_contact()     → finds contact_id
        → internally calls: cs_fn_upsert_conversation()  → creates conv_001 (new session)
        → internally calls: cs_fn_insert_message()        → inserts message row
      Sends to Inngest Cloud:
        inngest.send({ name: "cs/message.received", data: { conversation_id: "conv_001" } })
```

---

## TURN 1 — "I want a refund for order 12345, the item was damaged"

```
═══════════════════════════════════════════════════════════════════
INNGEST CLOUD receives "cs/message.received"
    Looks up: who listens for this event?
    Found: cs/conversation.process → registered at inngest-cs-serve (Supabase)
═══════════════════════════════════════════════════════════════════

Each call, Inngest sends all previous step results to
inngest-cs-serve. Completed steps return instantly from cache.
Only ONE new step executes per call.

──────────────────────────────────────────────────────────────────
CALL 1    DO: step.run("load-context")
──────────────────────────────────────────────────────────────────

  Inngest Cloud → HTTP POST → inngest-cs-serve (Supabase)

  inngest-cs-serve executes:
  │
  │  DB: cs_fn_load_conversation_context(conv_001)
  │    → Supabase RPC (native, no network hop)
  │    → Returns JSON:
  │        conversation: { id: conv_001, channel: 'shopee', status: 'open' }
  │        messages: [ "I want a refund for order 12345..." ]
  │        contact: { name: 'สมชาย', tier: 'Gold', tags: ['high-value'] }
  │        memory: [ { key: 'delivery', value: 'Ship to office' } ]
  │        ticket: null
  │        config: { voice: 'formal_thai', guardrails: [...] }
  │        active_procedure_state: null
  │
  inngest-cs-serve returns result → Inngest Cloud saves it

──────────────────────────────────────────────────────────────────
CALL 2    DO: step.run("search-knowledge")
──────────────────────────────────────────────────────────────────

  Inngest Cloud → HTTP POST → inngest-cs-serve (Supabase)
  (CALL 1 result replayed from cache — not re-executed)

  inngest-cs-serve executes:
  │
  │  HTTP: OpenAI Embedding API
  │    → embed('I want a refund for order 12345, the item was damaged')
  │    → Returns vector [0.023, -0.041, 0.089, ...]
  │
  │  DB: cs_fn_search_knowledge(merchant_id, embedding_vector, top_k=3)
  │    → pgvector cosine similarity search
  │    → Returns 3 chunks:
  │        1. "Refund policy: full refund within 7 days for damaged items..."
  │        2. "Shopee refunds processed through seller center..."
  │        3. "Gold tier: express refund eligible..."
  │
  inngest-cs-serve returns chunks → Inngest Cloud saves it

──────────────────────────────────────────────────────────────────
CALL 3    DO: step.run("evaluate-rules")
          Same engine as AMP workflows (domain='cs')
          Handles BOTH keyword rules AND semantic Q&A matching
──────────────────────────────────────────────────────────────────

  Inngest Cloud → HTTP POST → inngest-cs-serve (Supabase)
  (CALL 1-2 results replayed from cache)

  inngest-cs-serve executes:
  │
  │  DB: cs_fn_evaluate_rules(merchant_id, context, embedding_vector)
  │    → Loads active CS workflows (domain='cs') for this merchant
  │    → Walks workflow nodes, evaluates conditions:
  │
  │        Rule 1 (keyword condition):
  │          "IF message contains 'refund' → tag:refund, priority:urgent"
  │          → MATCH → executes: tag conversation, set priority
  │
  │        Rule 2 (semantic_match condition):
  │          "IF semantic_match('return policy', threshold:0.85) → auto-reply"
  │          → cosine similarity: 0.72 < 0.85 threshold
  │          → NO MATCH (message is about a specific refund, not asking policy)
  │
  │    → No rule fully resolves it (no auto-reply sent)
  │    → Returns { resolved: false, actions: ['tag:refund', 'priority:urgent'] }
  │
  inngest-cs-serve returns → Inngest Cloud saves it
  Rules did NOT resolve → continue to AI

──────────────────────────────────────────────────────────────────
CALL 4    DO: step.invoke("cs/agent.decide")
          THIS IS THE AI STEP — ROUTES TO RENDER
──────────────────────────────────────────────────────────────────

  Inngest Cloud → HTTP POST → inngest-cs-serve (Supabase)
  (CALL 1-3 results replayed from cache)

  inngest-cs-serve says: step.invoke("cs/agent.decide") with payload:
    { context, knowledge_chunks, rules_result, procedure_state: null }
  Returns invoke request → Inngest Cloud

  Inngest Cloud looks up: cs/agent.decide → registered at cs-ai-service (Render)
  Inngest Cloud → HTTP POST → cs-ai-service /api/inngest (Render)

  ┌─── cs-ai-service (Render) ──────────────────────────────────┐
  │                                                               │
  │  AgentKit receives: context + knowledge + no active procedure │
  │                                                               │
  │  BUILD PROMPT:                                                │
  │    System: "You are CS agent for [Brand]. Formal Thai.        │
  │      Guardrails: max refund 5000 THB, never blame customer.   │
  │      Customer: สมชาย, Gold tier, memory: prefers office       │
  │      delivery."                                               │
  │    Knowledge: [3 refund policy chunks]                        │
  │    Tools: [lookup_order, process_refund, cancel_order,        │
  │      create_voucher, award_points, assign_tag,                │
  │      escalate_to_human, create_ticket]                        │
  │    Message: "I want a refund for order 12345, item damaged"   │
  │                                                               │
  │  ─── AgentKit loop, iteration 1 ──────────────────────────    │
  │  │                                                             │
  │  │  AgentKit calls LLM (OpenAI)                               │
  │  │  LLM reasons: "Need to look up order first."               │
  │  │    → tool_call: lookup_order(platform='shopee',             │
  │  │                              order_id='12345')              │
  │  │                                                             │
  │  │  AgentKit executes tool:                                    │
  │  │    → MCP Server: cs-actions (localhost /mcp on Render)      │
  │  │      → HTTP: Shopee Order API                               │
  │  │        GET /api/v2/order/get_order_detail?order_sn=12345    │
  │  │      → Returns: { status: 'delivered',                      │
  │  │          delivered_at: '2026-03-31', total: 590,            │
  │  │          items: [{ name: 'Face Cream', qty: 1 }] }         │
  │  │                                                             │
  │  │  AgentKit feeds result back to LLM                          │
  │  │                                                             │
  │  ─── AgentKit loop, iteration 2 ──────────────────────────    │
  │  │                                                             │
  │  │  LLM now has order data. Reasons:                           │
  │  │    "Delivered 4 days ago. Within 7-day policy.              │
  │  │     Damaged item. Gold tier = express. ฿590 < ฿5000 limit. │
  │  │     I should confirm with customer before processing."      │
  │  │                                                             │
  │  │  LLM responds: NO tool call. Final answer:                  │
  │  │    {                                                        │
  │  │      customer_message: "สมชายครับ ตรวจสอบออเดอร์ #12345     │
  │  │        แล้วครับ (ครีมบำรุงผิว ฿590) อยู่ในระยะเวลา         │
  │  │        คืนเงินครับ ต้องการให้ดำเนินการคืนเงินเต็มจำนวน     │
  │  │        ฿590 เลยไหมครับ?",                                   │
  │  │      tool_calls: [],                                        │
  │  │      next_step: "wait_for_customer",                        │
  │  │      data_collected: { order_id: "12345", amount: 590,      │
  │  │        eligible: true, refund_type: "full" }                │
  │  │    }                                                        │
  │  │                                                             │
  │  │  AgentKit: no more tool calls → exit loop                   │
  │                                                               │
  │  cs-ai-service returns decision → HTTP response               │
  └───────────────────────────────────────────────────────────────┘

  Inngest Cloud receives decision, routes back to inngest-cs-serve

──────────────────────────────────────────────────────────────────
CALL 5    DO: step.run("send-reply")
──────────────────────────────────────────────────────────────────

  Inngest Cloud → HTTP POST → inngest-cs-serve (Supabase)
  (CALL 1-4 results replayed from cache)

  inngest-cs-serve executes:
  │
  │  HTTP: Shopee Chat API
  │    POST /api/v2/sellerchat/send_message
  │    body: { to_id: 'buyer_789', message: 'สมชายครับ ตรวจสอบ...' }
  │    → Shopee delivers message to customer's chat
  │
  inngest-cs-serve returns → Inngest Cloud saves it

──────────────────────────────────────────────────────────────────
CALL 6    DO: step.run("save-state")
──────────────────────────────────────────────────────────────────

  Inngest Cloud → HTTP POST → inngest-cs-serve (Supabase)
  (CALL 1-5 results replayed from cache)

  inngest-cs-serve executes:
  │
  │  DB: cs_fn_insert_message(conv_001, sender='ai', text='สมชายครับ ตรวจสอบ...')
  │  DB: cs_fn_save_procedure_state(conv_001, {
  │        current_step: 'confirm_with_customer',
  │        data_collected: { order_id: '12345', amount: 590, eligible: true }
  │      })
  │  DB: INSERT into cs_conversation_events (event_type: 'ai_replied', ...)
  │
  inngest-cs-serve returns → Inngest Cloud saves it

──────────────────────────────────────────────────────────────────
CALL 7    DO: step.waitForEvent("customer-reply")
──────────────────────────────────────────────────────────────────

  Inngest Cloud → HTTP POST → inngest-cs-serve (Supabase)

  inngest-cs-serve says:
  │  step.waitForEvent("customer-reply", {
  │    event: "cs/message.received",
  │    if: "async.data.conversation_id == 'conv_001'",
  │    timeout: "24h"
  │  })

  inngest-cs-serve returns → Inngest Cloud parks the execution

  ╔══════════════════════════════════════════════════════════════╗
  ║  WAITING — nothing running anywhere                         ║
  ║  Inngest Cloud holds state. All step results saved.         ║
  ║  Server can restart. No resources consumed.                 ║
  ╚══════════════════════════════════════════════════════════════╝
```

---

## TURN 2 — Customer replies "Yes please proceed" (15 minutes later)

```
═══════════════════════════════════════════════════════════════════
Shopee webhook → webhook-shopee edge function
  → DB: cs_api_receive_message() → inserts message
  → inngest.send({ name: "cs/message.received", data: { conversation_id: "conv_001" } })

Inngest Cloud receives event
  → "I'm waiting for cs/message.received on conv_001!" → RESUME
═══════════════════════════════════════════════════════════════════

inngest-cs-serve wakes up with ALL Turn 1 results from cache.
Starts fresh step sequence for Turn 2.

──────────────────────────────────────────────────────────────────
CALL 8    DO: step.run("load-context")  [Turn 2]
──────────────────────────────────────────────────────────────────

  Inngest Cloud → HTTP POST → inngest-cs-serve (Supabase)

  inngest-cs-serve executes:
  │
  │  DB: cs_fn_load_conversation_context(conv_001)
  │    → Now returns 3 messages + saved procedure state:
  │        messages: [
  │          customer: "I want a refund for order 12345...",
  │          ai: "สมชายครับ ตรวจสอบออเดอร์...",
  │          customer: "Yes please proceed"
  │        ]
  │        active_procedure_state: {
  │          current_step: 'confirm_with_customer',
  │          data_collected: { order_id: '12345', amount: 590, eligible: true }
  │        }
  │
  inngest-cs-serve returns → Inngest Cloud saves it

──────────────────────────────────────────────────────────────────
CALL 9    DO: step.run("search-knowledge")  → skipped (procedure in progress)
CALL 10   DO: step.run("evaluate-rules")  → { resolved: false } (no new triggers)
──────────────────────────────────────────────────────────────────

  Two quick calls, both return fast. No new matches.

──────────────────────────────────────────────────────────────────
CALL 11   DO: step.invoke("cs/agent.decide")  [Turn 2]
          ROUTES TO RENDER — THE MULTI-TOOL-CALL STEP
──────────────────────────────────────────────────────────────────

  Inngest Cloud → inngest-cs-serve → step.invoke → Inngest Cloud
  Inngest Cloud → HTTP POST → cs-ai-service /api/inngest (Render)

  ┌─── cs-ai-service (Render) ──────────────────────────────────┐
  │                                                               │
  │  AgentKit receives: context + procedure_state + latest msg    │
  │    Customer said: "Yes please proceed"                        │
  │    State: confirm_with_customer, order 12345, ฿590, eligible  │
  │                                                               │
  │  BUILD PROMPT:                                                │
  │    "Customer confirmed refund. Procedure state shows          │
  │     order 12345, ฿590, eligible. Process it."                 │
  │                                                               │
  │  ─── AgentKit loop, iteration 1 ──────────────────────────    │
  │  │                                                             │
  │  │  LLM reasons: "Customer confirmed. Process refund."         │
  │  │    → tool_call: process_refund(platform='shopee',           │
  │  │        order_id='12345', type='full', amount=590)           │
  │  │                                                             │
  │  │  AgentKit executes:                                         │
  │  │    → MCP: cs-actions (Render /mcp)                          │
  │  │      → Checks business guardrail: ฿590 < ฿5000 limit ✓     │
  │  │      → HTTP: Shopee Refund API                              │
  │  │        POST /api/v2/order/handle_buyer_cancellation         │
  │  │      → Returns: { success: true, refund_id: 'RF_001' }     │
  │  │                                                             │
  │  │  AgentKit feeds result back to LLM                          │
  │  │                                                             │
  │  ─── AgentKit loop, iteration 2 ──────────────────────────    │
  │  │                                                             │
  │  │  LLM reasons: "Refund done. Gold tier + damaged item →      │
  │  │    offer goodwill points per brand policy."                  │
  │  │    → tool_call: award_points(user_id='crm_abc',             │
  │  │        amount=100, reason='goodwill - damaged item')         │
  │  │                                                             │
  │  │  AgentKit executes:                                         │
  │  │    → MCP: crm-loyalty-actions (amp-ai-service /mcp)         │
  │  │      → HTTP: CRM Bridge → CRM Supabase project              │
  │  │        → post_wallet_transaction(user_id, 100, 'goodwill')  │
  │  │      → Returns: { success: true, new_balance: 12500 }       │
  │  │                                                             │
  │  │  AgentKit feeds result back to LLM                          │
  │  │                                                             │
  │  ─── AgentKit loop, iteration 3 ──────────────────────────    │
  │  │                                                             │
  │  │  LLM reasons: "Refund + points done. Create ticket for      │
  │  │    tracking."                                                │
  │  │    → tool_call: create_ticket(conversation_id='conv_001',   │
  │  │        type='refund', priority='urgent',                     │
  │  │        resolution='refunded',                                │
  │  │        description='Damaged Face Cream, full refund ฿590')  │
  │  │                                                             │
  │  │  AgentKit executes:                                         │
  │  │    → MCP: cs-actions (Render /mcp)                          │
  │  │      → DB: cs_fn_create_ticket(...)                          │
  │  │      → Returns: { ticket_id: 'TKT_001' }                    │
  │  │                                                             │
  │  │  AgentKit feeds result back to LLM                          │
  │  │                                                             │
  │  ─── AgentKit loop, iteration 4 ──────────────────────────    │
  │  │                                                             │
  │  │  LLM reasons: "All done. Compose final reply."              │
  │  │    → NO tool call. Final answer:                             │
  │  │    {                                                        │
  │  │      customer_message: "ดำเนินการคืนเงิน ฿590              │
  │  │        เรียบร้อยแล้วครับ จะได้รับเงินคืนภายใน              │
  │  │        3-5 วันทำการ และมอบ 100 คะแนนพิเศษให้               │
  │  │        เป็นการขออภัยครับ ขอบคุณครับ",                       │
  │  │      actions_taken: ["process_refund",                       │
  │  │        "award_points", "create_ticket"],                     │
  │  │      next_step: "resolve"                                    │
  │  │    }                                                        │
  │  │                                                             │
  │  │  AgentKit: no more tool calls → exit loop                   │
  │                                                               │
  │  cs-ai-service returns decision                               │
  └───────────────────────────────────────────────────────────────┘

  Inngest Cloud receives, routes back to inngest-cs-serve

──────────────────────────────────────────────────────────────────
CALL 12   DO: step.run("send-reply")
──────────────────────────────────────────────────────────────────

  Inngest Cloud → HTTP POST → inngest-cs-serve (Supabase)

  inngest-cs-serve executes:
  │
  │  HTTP: Shopee Chat API
  │    POST /api/v2/sellerchat/send_message
  │    body: { message: 'ดำเนินการคืนเงิน ฿590 เรียบร้อยแล้วครับ...' }
  │    → Delivered to customer
  │
  inngest-cs-serve returns → Inngest Cloud saves it

──────────────────────────────────────────────────────────────────
CALL 13   DO: step.run("save-state")
──────────────────────────────────────────────────────────────────

  inngest-cs-serve executes:
  │
  │  DB: cs_fn_insert_message(conv_001, sender='ai', text='ดำเนินการคืนเงิน...')
  │  DB: UPDATE cs_conversations SET status = 'resolved', resolved_at = now()
  │  DB: UPDATE cs_tickets SET status = 'resolved' WHERE id = 'TKT_001'
  │  DB: INSERT cs_conversation_events (event_type: 'resolved', ...)
  │
  inngest-cs-serve returns → Inngest Cloud saves it

──────────────────────────────────────────────────────────────────
CALL 14   DO: step.run("trigger-csat")
──────────────────────────────────────────────────────────────────

  inngest-cs-serve executes:
  │
  │  HTTP: Shopee Chat API → send CSAT survey message
  │
  inngest-cs-serve returns → Inngest Cloud saves it

──────────────────────────────────────────────────────────────────
CALL 15   DO: step.invoke("cs/agent.extract-memory")
          ROUTES TO RENDER — MEMORY EXTRACTION
──────────────────────────────────────────────────────────────────

  Inngest Cloud → Render cs-ai-service

  ┌─── cs-ai-service (Render) ──────────────────────────────────┐
  │                                                               │
  │  AgentKit receives: full conversation transcript (3 messages) │
  │                                                               │
  │  LLM extracts memory:                                         │
  │    { category: 'issue', key: 'product_quality',               │
  │      value: 'Had damaged Face Cream, received full refund',   │
  │      confidence: 0.9 }                                        │
  │                                                               │
  │  Returns memory entries                                       │
  └───────────────────────────────────────────────────────────────┘

  Inngest Cloud → inngest-cs-serve
  │  DB: INSERT into cs_customer_memory (...)
  │

──────────────────────────────────────────────────────────────────
CALL 16   DO: step.run("log-complete")
──────────────────────────────────────────────────────────────────

  inngest-cs-serve executes:
  │  DB: INSERT cs_conversation_events (event_type: 'execution_completed')
  │  Update analytics counters
  │

      DONE. 16 calls total across 2 turns.
```

---

## SUMMARY — CHAT PATH (Inngest Pipeline)

```
Fixed pipeline (every message, same sequence):
  load-context     → search-knowledge → evaluate-rules → agent.decide
  → send-reply → save-state → [waitForEvent or resolve]

Outer loop steps (inngest-cs-serve on Supabase — no AI):
  load-context       → cs_fn_load_conversation_context     (Supabase RPC)
  search-knowledge   → OpenAI embed + cs_fn_search_knowledge  (embedding API + pgvector)
  evaluate-rules     → cs_fn_evaluate_rules                 (Supabase RPC)
                       Same AMP workflow engine (domain='cs').
                       Handles keyword rules AND semantic Q&A matching.
                       Semantic match = cosine similarity on question_patterns
                       from admin-written Q&A pairs (replaces custom-answer).
  send-reply         → Shopee/LINE/WhatsApp API             (HTTP call)
  save-state         → cs_fn_save_procedure_state           (Supabase RPC)
  trigger-csat       → Platform API                         (HTTP call)
  waitForEvent       → Inngest parks execution              (no compute)

AI steps (cs-ai-service on Render, via step.invoke):
  cs/agent.decide          → AgentKit + LLM + MCP tool loop
  cs/agent.extract-memory  → AgentKit + LLM memory extraction

MCP tool calls (inside AgentKit loop on Render):
  cs-actions (Render /mcp):
    lookup_order       → Shopee/Lazada/TikTok Order API
    process_refund     → Marketplace Refund API
    create_ticket      → DB: cs_fn_create_ticket
    escalate_to_human  → DB: cs_fn_auto_assign
    close_conversation → DB: UPDATE cs_conversations

  crm-loyalty-actions (amp-ai-service /mcp — separate Render service):
    award_points       → CRM Bridge → post_wallet_transaction
    assign_tag         → CRM Bridge → fn_execute_amp_action
    assign_persona     → CRM Bridge → fn_execute_amp_action

No AI. No MCP. No Render — except for the 2 step.invoke calls.
Everything else is Supabase edge function ↔ Supabase DB (native).

Chat latency: ~5-9s per turn (acceptable for async messaging).
```

---

## VOICE PATH — Graph Executor + Deterministic Prefetch

> Voice uses ElevenLabs for STT/TTS only. All AI decisioning stays on our
> infrastructure. Same agent, same AOPs, same tools — different orchestration
> pattern optimized for real-time (<1.5s) response.

### Architecture

```
ElevenLabs (dumb pipe — ears and mouth only):
  Scribe v2 STT → transcribed text → Custom LLM endpoint (your Edge Function)
  TTS ← response text ← Custom LLM endpoint
  Also handles: telephony (Twilio SIP), turn-taking, VAD, barge-in

Your infrastructure (the brain):
  voice-custom-llm Edge Function
    → Graph Executor on Render (replaces AgentKit loop for voice)
    → Same MCP tools, same DB functions, same knowledge base
```

### Core Idea: Deterministic Prefetch

```
CHAT (current — LLM is "explorer"):
  LLM call 1: "I need order data"  → tool_call: lookup_order  → ~1.5s
  AgentKit executes tool via MCP                                → ~200ms
  LLM call 2: "Now I can answer"                               → ~1.5s
  Total: ~3.2s, 2 LLM calls (LLM discovers what it needs)

VOICE (new — code is "explorer", LLM is "writer"):
  Graph: reads step.data_needs → needs lookup_order             → ~5ms
  Graph: regex extracts order_number = "12345" from message     → ~5ms
  Graph: calls lookup_order("12345") directly as code           ┐
  Graph: calls search_knowledge("refund policy") as code        ├ ~300ms
  Graph: loads conversation context from DB                     ┘ (parallel)
  LLM call 1: "Here's everything, compose response"            → ~800ms
  Total: ~1.1s, 1 LLM call (code already fetched everything)
```

Each AOP step declares data_needs[] — what data sources that step requires.
The graph executor reads this and calls those tool functions directly as
code (same functions that MCP exposes, imported on the same Render service).
The LLM never makes data tool calls. It receives a complete picture.

How the graph executor calls tools without LLM:
  MCP tools are just functions. AgentKit (chat) calls them because the LLM
  generates a tool_call. Graph executor (voice) calls them because code
  reads data_needs and invokes the function directly. The tools don't care
  who calls them — they receive arguments and return data.

Two types of tool calls:
  DATA tools (in step.data_needs): lookup_order, search_knowledge, check_stock
    → Called by GRAPH EXECUTOR (code) before LLM. Step-aware: only what the
      current step declares. Empty data_needs = no calls, no wasted compute.
  ACTION tools (in step.action_tools): process_refund, award_points, create_ticket
    → Decided by LLM, executed by code AFTER response is sent (async).

### Step-Level Prefetch (Not Blanket)

Each step fetches only what it declares. No wasted API calls:

```
Step "Acknowledge Feelings"  → data_needs: []
  Prefetch: context only (1 DB call, ~20ms)
  No embedding, no marketplace API, no knowledge search.

Step "Explain & Offer Tips"  → data_needs: [knowledge("blind box policy")]
  Prefetch: context + knowledge search (~200ms)
  Still no marketplace API — step doesn't need order data.

Step "Lookup Order"  → data_needs: [lookup_order, knowledge("refund policy")]
  Prefetch: context + Shopee order API + knowledge (~300ms, parallel)
  Full data pre-load for this step.
```

### Fallback: LLM as Explorer

Prefetch covers ~80% of turns. When the graph can't determine what data
is needed, the response depends on the tier:

```
TIER 2 — AOP active, step has no data_needs (conversation-only):

  Customer: "มีปัญหาค่ะ" (vague — "I have a problem")
  Graph: entity_extractors find nothing
  Step: "Acknowledge Feelings" → data_needs: []
  Prefetch: context only (~20ms)
  LLM: 1 call, asks clarifying question                       → ~800ms total
    "เป็นปัญหาเกี่ยวกับสินค้า การจัดส่ง หรือเรื่องอื่นคะ"

  --- next turn ---

  Customer: "order 12345 ส่งช้า" (now has entities)
  Graph: regex → order_number = "12345", keyword → delivery
  Step: "Lookup Order" → data_needs: [lookup_order, knowledge]
  Prefetch: context + Shopee API + knowledge search             → ~300ms
  LLM: 1 call, everything pre-loaded                           → ~800ms total

TIER 3 — No AOP matched (unknown intent, explorer fallback):

  Customer: "ดูโปรโมชั่น TikTok หน่อย" (unpredictable)
  Graph: no AOP for this intent, no data_needs to read
  Prefetch: context + default_data_needs.no_entities
  LLM call 1: discovers it needs promotion data → tool_call    → ~1s
  Tool executes                                                 → ~200ms
  LLM call 2: "Here's the answer"                              → ~800ms
  Total: ~2s — slower but acceptable for voice with filler
```

### Voice Turn Trace — Same Refund Scenario

```
═══════════════════════════════════════════════════════════════════
VOICE ENTRY: Customer calls +66-2-XXX-XXXX
═══════════════════════════════════════════════════════════════════

  Phone → Twilio → ElevenLabs (STT active, TTS ready)

  ElevenLabs sends call.started webhook → webhook-elevenlabs Edge Function:
    Resolve contact by phone: cs_fn_resolve_contact(phone='+66812345678')
      → Found: สมชาย, Gold tier, crm_user_id = 'crm_abc'
    Create conversation: cs_fn_upsert_conversation(modality='voice')
      → conv_002 created
    Create voice call: INSERT cs_voice_calls (conversation_id, phone_from, ...)
    Map session: elevenlabs_session_id → conv_002
    Pass context to ElevenAgents: { contact_name: 'สมชาย', tier: 'Gold' }

  ElevenLabs speaks greeting (from system prompt, context-aware):
    "สวัสดีค่ะ คุณสมชาย มีอะไรให้ช่วยคะ"

═══════════════════════════════════════════════════════════════════
VOICE TURN 1: "order 12345 ของเสียหาย อยากขอคืนเงิน"
═══════════════════════════════════════════════════════════════════

  ElevenLabs Scribe v2 transcribes → sends text to Custom LLM endpoint

  voice-custom-llm Edge Function receives text:
    │
    │ PHASE 1 — Route + Extract (deterministic, ~20ms)
    │   AOP step: none active → check intent
    │   Run entity_extractors from compiled_steps:
    │     regex: order_number = '12345'
    │     keyword: intent_keyword = 'คืนเงิน' → return_request
    │   cs_fn_get_active_procedure(merchant_id, 'return_request')
    │     → Return and Exchange Handler (strict), compiled_steps loaded
    │   Current step: Step 1 "Understand Request"
    │     variables_out needed: [return_type, product_type, order_number...]
    │     order_number already extracted by regex → partially collected
    │
    │ PHASE 2 — Prefetch: step-aware, only what's declared (~300ms)
    │   Step 1 data_needs: []  ← conversation-only step, no data tools
    │   BUT graph looks ahead: Step 2 data_needs includes lookup_order
    │     AND order_number is already extracted → prefetch eligible
    │   Graph calls data tools directly as code (NOT via LLM):
    │   ├── cs_fn_load_conversation_context(conv_002)              ~20ms
    │   │     → { contact: สมชาย, Gold, messages: [...], procedure_state: null }
    │   ├── lookup_order('12345') — code calls tool function       ~200ms
    │   │     → { status: 'delivered', total: 590, items: ['Face Cream'] }
    │   └── search_knowledge("refund damaged item") — code calls   ~200ms
    │         → 3 chunks: refund policy, Shopee refund, Gold express
    │   All 3 in parallel (max = ~200ms)
    │   Note: if Step 1 had NO look-ahead match, only context fetched (~20ms)
    │
    │ PHASE 3 — Walk AOP graph (deterministic, ~10ms)
    │   Step 1 "Understand Request":
    │     variables_out: order_number=12345 (from regex), return_type=refund (keyword)
    │     Most variables collected → skip to Step 2
    │   Step 2 "Check Return Eligibility":
    │     required_variables check: purchase_channel, days_since_purchase
    │     From prefetched order: purchase_channel='online', days_since=4
    │     code_condition: purchase_channel='online' AND days_since=4 ≤ 7
    │     → MATCH → goto Step 5 "Approve Return"
    │   Graph says: execute Step 5 with all collected data
    │
    │ PHASE 4 — ONE LLM call (writer mode, ~800ms)
    │   System: "You are on Step 5 'Approve Return' of Return Handler.
    │     Tone: empathetic, patient, solution-oriented.
    │     Customer: สมชาย, Gold tier.
    │     Order 12345: Face Cream, ฿590, delivered 4 days ago.  [prefetched]
    │     Policy: Full refund within 7 days for damaged items.  [prefetched]
    │     Gold tier: express refund eligible.                    [prefetched]
    │     Confirm with customer before processing."
    │   User message: "order 12345 ของเสียหาย อยากขอคืนเงิน"
    │
    │   LLM responds (ONE call, no tool loop — all data was pre-loaded):
    │     "สมชายครับ ตรวจสอบออเดอร์ 12345 แล้วครับ ครีมบำรุงผิว ราคา 590 บาท
    │      อยู่ในระยะเวลาคืนเงินครับ ต้องการให้ดำเนินการคืนเงินเต็มจำนวน
    │      590 บาทเลยไหมครับ?"
    │
    │ PHASE 5 — Deliver + save (async, non-blocking)
    │   Stream response text → ElevenLabs TTS speaks it
    │   Async: cs_fn_insert_message(conv_002, 'ai', response)
    │   Async: cs_fn_save_procedure_state(conv_002, {
    │     current_step: 5, data: { order_id: '12345', amount: 590, eligible: true }
    │   })
    │
    │ Total: ~1.0s (20ms extract + 200ms prefetch + 800ms LLM)

═══════════════════════════════════════════════════════════════════
VOICE TURN 2: "ครับ เอาเลย" (Yes, proceed)
═══════════════════════════════════════════════════════════════════

  ElevenLabs transcribes → voice-custom-llm Edge Function:
    │
    │ PHASE 1 — Route + Extract (deterministic, ~10ms)
    │   Load procedure_state: Step 5 "Approve Return", data_collected has order data
    │   Run entity_extractors: no new entities (just "ครับ เอาเลย")
    │   Current step: still Step 5, customer confirmed
    │
    │ PHASE 2 — Prefetch: step-aware (~20ms)
    │   Step 5 data_needs: [] (no data tools — order data already in procedure_state)
    │   Fetch: context only (~20ms)
    │     → includes procedure_state with order_id, amount, eligible from Turn 1
    │   No marketplace API calls, no knowledge search — step doesn't need them
    │
    │ PHASE 3 — Walk AOP graph (~5ms)
    │   Step 5 "Approve Return": customer confirmed → action_tools applicable
    │   action_tools: [process_refund (requires_confirmation: true → confirmed)]
    │   Graph: step instructions say "process refund, then wrap up"
    │
    │ PHASE 4 — ONE LLM call (~800ms)
    │   System: "Customer confirmed refund. Order 12345, ฿590, eligible.
    │     Process refund. Gold tier → award goodwill points. Create ticket.
    │     Compose confirmation message.
    │     Return list of actions to execute from action_tools."
    │
    │   LLM responds (no data tool calls — just writes response + action list):
    │     {
    │       message: "ดำเนินการคืนเงิน 590 บาทเรียบร้อยแล้วครับ
    │         จะได้รับเงินคืนภายใน 3-5 วันทำการ และมอบ 100 คะแนน
    │         พิเศษให้เป็นการขออภัยครับ",
    │       actions: [
    │         { tool: "process_refund", args: { order_id: "12345", amount: 590 } },
    │         { tool: "award_points", args: { user_id: "crm_abc", amount: 100 } },
    │         { tool: "create_ticket", args: { type: "refund", priority: "urgent" } }
    │       ],
    │       next_step: "resolve"
    │     }
    │
    │ PHASE 5 — Deliver immediately, execute actions after
    │   Stream response → ElevenLabs TTS speaks it (~100ms to first audio)
    │   THEN code executes action_tools in parallel (customer already hears response):
    │     ├── process_refund(590)     → Shopee API    ~300ms
    │     ├── award_points(100)       → CRM Bridge    ~200ms
    │     └── create_ticket(...)      → DB            ~100ms
    │   Save state, resolve conversation
    │
    │ Total: ~0.8s to voice (actions execute in background)

═══════════════════════════════════════════════════════════════════
VOICE CALL ENDS: Customer says "ไม่มีแล้ว ขอบคุณครับ"
═══════════════════════════════════════════════════════════════════

  ElevenLabs sends call.ended webhook → webhook-elevenlabs:
    UPDATE cs_voice_calls SET
      call_status = 'completed',
      duration_seconds = 47,
      recording_url = 'https://...',
      full_transcript = '...',
      disposition = 'resolved'

  Emit Inngest event: cs/voice.call_ended → post-call processing:
    cs/voice.post-call (Inngest function, async):
      step.invoke("cs/agent.extract-memory") → same as chat
      step.run("save-transcript") → full transcript to cs_voice_calls
      step.run("log-analytics") → call duration, turns, resolution
```

### Latency Comparison

```
                        CHAT (Inngest)    VOICE (Graph + Prefetch)
Turn 1 (with order):   ~5.5s              ~1.0s  (Tier 1: data_needs has tools)
Turn 1 (convo only):   ~5.5s              ~0.8s  (Tier 2: empty data_needs)
Turn 2 (confirm):      ~8-9s              ~0.8s  (Tier 2: context only, no data fetch)
LLM calls per turn:    2-4                1 (Tier 1+2) or 2+ (Tier 3 fallback)
Data tool calls by:    LLM (via MCP)      Code (direct import)
HTTP round-trips:      7 per turn         1 per turn
Prefetch miss:         N/A                ~2s (Tier 3: explorer fallback)
```

### When Prefetch Works vs Falls Back

```
TIER 1 — DATA TOOLS PREFETCHED (~30% of turns, AOP steps with data_needs):
  ✓ Step data_needs: [lookup_order] + regex extracted order_number
    → Graph calls lookup_order("12345") as code → result in LLM prompt
  ✓ Step data_needs: [knowledge, check_stock] + keyword extracted product
    → Graph calls both in parallel → results in LLM prompt
  ✓ Step data_needs: [lookup_order, knowledge("refund policy")]
    → Graph calls order API + knowledge search in parallel

TIER 2 — CONVERSATION ONLY (~50% of turns, AOP steps with empty/knowledge data_needs):
  ✓ Step data_needs: []  → context only (~20ms). No wasted calls.
    Empathy steps, acknowledgment, collecting info from customer.
  ✓ Step data_needs: [knowledge("blind box policy")]
    → Context + targeted knowledge search (~200ms). No order API.
  ✓ Code_conditions evaluated deterministically — no LLM needed for routing.

TIER 3 — EXPLORER FALLBACK (~20% of turns, no AOP or unpredictable):
  ✗ No AOP matched ("ดูโปรโมชั่น TikTok หน่อย")
    → LLM discovers it needs search_promotions → extra tool call → +1s
  ✗ Ambiguous first message ("มีปัญหาค่ะ") with no AOP context
    → LLM asks clarifying question (no extra tool call, just no shortcut)
  ✗ Mid-conversation topic change with no matching AOP step
    → New entity extraction on next turn once intent is clear

Explorer fallback adds ~0.5-1s (one extra LLM call). Still acceptable for
voice with filler phrases ("ขอเช็คให้สักครู่นะคะ") covering the gap.
```
