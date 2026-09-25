# CS AI — Pipeline Steps Reference

> Every incoming customer message runs through this fixed pipeline. Same sequence every time. What changes is what each step returns, which determines whether AI is needed or if rules handle it.

---

## Pipeline Overview

```
Message arrives → webhook saves to DB → Inngest event fired

inngest-cs-serve (Supabase) runs:

  ┌─ Steps 1-3 are IDENTICAL for every message, every channel, every merchant.
  │  They prepare data for the AI step. No intelligence, just data fetching.
  │
  CALL 1: load-context        → DB
  CALL 2: search-knowledge    → Embedding API + pgvector
  CALL 3: evaluate-rules      → DB (same engine as AMP workflows, domain='cs')
  │
  │  Note: Step 3 can short-circuit the entire pipeline. If a rule
  │  fully resolves (e.g., semantic Q&A match → auto-reply), the
  │  pipeline skips Step 4 and jumps straight to Step 5 (send-reply).
  │  No LLM involved at all in that case.
  └─

  ┌─ Step 4 is the ONLY step that involves AI.
  │  Everything before it is data prep. Everything after is cleanup.
  │
  CALL 4: agent.decide        → step.invoke → Render (AgentKit + LLM + MCP)
  └─

  ┌─ Steps 5-7 are IDENTICAL for every message.
  │  Send the reply, save state, wait or resolve. Mechanical.
  │
  CALL 5: send-reply          → Platform API
  CALL 6: save-state          → DB
  CALL 7: waitForEvent or resolve
  └─
```

---

## Step 0 — Webhook Entry (Supabase Edge Function)

**Runs on:** Supabase Edge Function (`webhook-shopee` / `webhook-line` / `webhook-whatsapp` / etc.)
**Technique:** Code — signature validation + DB calls
**Calls downstream:** Supabase DB functions → Inngest Cloud

```
Platform sends webhook POST
  │
  │  webhook-shopee validates Shopee signature (HMAC)
  │
  │  DB: cs_api_receive_message(merchant_id, 'shopee', 'buyer_789', message_text)
  │    → cs_fn_resolve_contact()       — find or create contact + platform identity
  │    → cs_fn_upsert_conversation()   — threading logic: new vs reopen vs append
  │    → cs_fn_insert_message()        — insert message row, update last_message_at
  │
  │  inngest.send({
  │    name: "cs/message.received",
  │    data: { conversation_id: "conv_001", message_id: "msg_001" }
  │  })
  │    → HTTP POST to Inngest Cloud (lightweight JSON, ~200 bytes)
  │
  Done. Edge function returns 200 to platform.
```

**Threading logic in `cs_fn_upsert_conversation`:**

| Current status | Customer messages again | What happens |
|---|---|---|
| Resolved, within threading interval | Same conversation **reopens** |
| Resolved, after threading interval | **New conversation** created |
| Open, within session timeout | Message **appended** |
| Open, after session timeout | Old closed, **new conversation** |
| Waiting on customer | Always **appended** |

---

## Step 1 — Load Context (no AI, just DB)

**Runs on:** inngest-cs-serve (Supabase Edge Function)
**Technique:** Single Supabase RPC — native DB access, no network hop
**Calls downstream:** Supabase DB

```
Inngest Cloud → HTTP POST → inngest-cs-serve

  DB: cs_fn_load_conversation_context(conv_001)
    → One function call, returns everything:

    {
      conversation: { id, channel, status, priority, assigned_agent },
      messages: [ last 10-20 messages ],
      contact: { name, tier, tags, language, platform_identities },
      memory: [ distilled facts from past conversations ],
      ticket: { id, type, status, priority } or null,
      config: {
        voice: 'formal_thai',
        guardrails: [ brand-level rules ],
        guidance_rules: [ cross-topic behavioral instructions ]
      },
      active_procedure_state: {
        procedure_id, current_step, data_collected
      } or null
    }

  Returns to Inngest Cloud → saved as step result
```

**What's in `active_procedure_state`:**
- On first message: `null` (no procedure yet)
- On follow-up turns: contains which AOP step we're on and all data collected so far
- This is how the pipeline "remembers" across turns — Inngest holds this between `waitForEvent` calls

---

## Step 2 — Search Knowledge (no AI reasoning, just embedding + vector search)

**Runs on:** inngest-cs-serve (Supabase Edge Function)
**Technique:** OpenAI Embedding API + pgvector cosine similarity
**Calls downstream:** OpenAI API (HTTP) → Supabase DB

```
Inngest Cloud → HTTP POST → inngest-cs-serve

  HTTP: OpenAI Embedding API
    → embed(customer_message_text)
    → Returns vector [0.023, -0.041, 0.089, ...]
    → ~100ms, ~$0.0001

  DB: cs_fn_search_knowledge(merchant_id, embedding_vector, top_k=5)
    → pgvector cosine similarity against cs_knowledge_embeddings
    → Returns top 5 matching knowledge chunks with scores:
        1. (0.91) "Refund policy: full refund within 7 days for damaged items..."
        2. (0.87) "For Shopee orders, refund is processed through seller center..."
        3. (0.84) "Gold tier customers are eligible for express refund..."
        4. (0.71) "Shipping policy for fragile items..."
        5. (0.65) "How to contact customer service..."

  Returns chunks to Inngest Cloud → saved as step result
```

**Why this runs before evaluate-rules:**
The embedding vector computed here is reused by evaluate-rules for semantic Q&A matching. Compute once, use twice.

**Skip condition:** If `active_procedure_state` exists (follow-up turn in a multi-step procedure), this step can be skipped — knowledge was already retrieved in the first turn.

---

## Step 3 — Evaluate Rules (no AI, same engine as AMP workflows)

**Runs on:** inngest-cs-serve (Supabase Edge Function)
**Technique:** Rule-based workflow engine — same condition grammar as AMP, `domain='cs'`
**Calls downstream:** Supabase DB

```
Inngest Cloud → HTTP POST → inngest-cs-serve

  DB: cs_fn_evaluate_rules(merchant_id, context, embedding_vector)
    → Loads active CS workflows (domain='cs') for this merchant
    → Walks workflow graph nodes, evaluates conditions:

    ┌─────────────────────────────────────────────────────────┐
    │ CONDITION TYPES AVAILABLE                                │
    │                                                         │
    │ Keyword:        message contains 'refund'               │
    │ Channel:        channel = 'shopee'                      │
    │ Customer:       tier = 'Gold', tag contains 'vip'       │
    │ Sentiment:      sentiment = 'angry' (pre-classified)    │
    │ Business hours: outside_hours = true                    │
    │ Order status:   order_status = 'delivered'              │
    │ Semantic match: cosine_similarity(embedding,            │
    │                   question_patterns) > 0.85             │
    │   ↑ This replaces the old "custom-answer" step.         │
    │     Admin writes Q&A pairs with 10+ example phrasings.  │
    │     question_patterns are pre-embedded. Matching is     │
    │     cosine similarity using the same embedding vector    │
    │     from Step 2. If above threshold → auto-reply with   │
    │     admin's exact answer.                                │
    └─────────────────────────────────────────────────────────┘

    ┌─────────────────────────────────────────────────────────┐
    │ ACTION TYPES AVAILABLE                                   │
    │                                                         │
    │ auto_reply:     send exact text (resolves conversation) │
    │ tag:            add/remove tag on conversation          │
    │ set_priority:   change priority level                   │
    │ assign:         route to agent / team / AI              │
    │ set_status:     pending, snoozed                        │
    │ escalate:       push to supervisor                      │
    │ internal_note:  add note only agents see                │
    │ webhook:        notify external system                  │
    │ notification:   Slack / Teams / LINE Notify             │
    │ close:          close the conversation                  │
    └─────────────────────────────────────────────────────────┘

  Example evaluation:

    Rule 1 (keyword): "IF contains 'refund' → tag:refund, priority:urgent"
      → MATCH → executes tag + set_priority

    Rule 2 (semantic): "IF semantic_match('return policy Q&A', 0.85) → auto_reply"
      → cosine similarity = 0.72 < 0.85 → NO MATCH
      → (customer is requesting a specific refund, not asking about policy)

    Rule 3 (channel + tier): "IF shopee AND Gold → assign:vip-team"
      → MATCH → executes assign

  → Returns: { resolved: false, actions_taken: ['tag:refund', 'priority:urgent', 'assign:vip-team'] }

  Returns to Inngest Cloud → saved as step result
```

**Short-circuit:** If any rule has an `auto_reply` action and fires → conversation is resolved here. Pipeline skips `agent.decide` and goes straight to `send-reply` with the rule's answer. No LLM involved.

---

## Step 4 — Agent Decide (AI — routes to Render via step.invoke)

**Runs on:** cs-ai-service on Render (AgentKit + LLM + MCP)
**Technique:** LLM reasoning with tool-calling loop
**Calls downstream:** LLM API (OpenAI/Anthropic) → MCP servers → external APIs

This is the only step that involves AI. It only runs if evaluate-rules did NOT fully resolve the conversation.

The function has 5 sub-steps inside. Steps 4a-4c are **code** (deterministic, no AgentKit). Only Step 4d is the **AgentKit loop** (LLM reasoning + MCP tools).

```
Inngest Cloud → inngest-cs-serve → step.invoke("cs/agent.decide")
  → Inngest Cloud routes to → Render cs-ai-service /api/inngest

  ┌─── cs-ai-service (Render) ──────────────────────────────────┐
  │                                                               │
  │  ── Steps 4a-4c are CODE, not AgentKit. ──────────────────── │
  │  Intent, AOP lookup, and code conditions are resolved         │
  │  BEFORE AgentKit starts. This ensures reliability —           │
  │  code can't hallucinate a procedure name or skip a step.      │
  │                                                               │
  │  STEP 4a — INTENT DETECTION (code + fast LLM)                │
  │                                                               │
  │  If first turn (no procedure_state):                          │
  │    Call fast LLM (gpt-4o-mini, structured JSON output):       │
  │      Input: customer message + conversation history           │
  │        + known intents from active AOPs as hints              │
  │      Output: { intent: "refund_request", confidence: 0.94 }  │
  │  If follow-up turn (procedure_state exists):                  │
  │    Skip — intent already known from first turn                │
  │                                                               │
  │  STEP 4b — AOP LOOKUP (code — just a DB query)               │
  │                                                               │
  │  DB: cs_fn_get_active_procedure(merchant_id, 'refund_request')│
  │    → Found: "Refund Request Handler" v3                       │
  │      Steps:                                                   │
  │        1. Collect order info                                  │
  │        2. Lookup order                                        │
  │        3. Check eligibility (CODE CONDITION: days <= 7)       │
  │        4. Confirm with customer                               │
  │        5. Process refund                                      │
  │        6. Goodwill gesture (if Gold tier)                     │
  │        7. Create ticket + resolve                             │
  │  If no AOP found → AgentKit will use knowledge base only      │
  │                                                               │
  │  STEP 4c — RESOLVE CURRENT STEP + CODE CONDITIONS (code)     │
  │                                                               │
  │  Determine which AOP step we're on:                           │
  │    First turn → start at Step 1                               │
  │    Follow-up → read procedure_state.current_step              │
  │  If current step has a CODE CONDITION:                        │
  │    Evaluate in code (NOT LLM): days <= 7 → eligible = true   │
  │    Result injected into prompt as fact. LLM cannot override.  │
  │                                                               │
  │  ── Everything above is CODE. AgentKit starts below. ──────  │
  │                                                               │
  │  STEP 4d — AGENTKIT REASONING LOOP (LLM + MCP tools)         │
  │                                                               │
  │  Code builds prompt with all pre-resolved data:               │
  │    System: brand voice + guardrails + guidance rules           │
  │    Context: customer profile + memory + conversation           │
  │    Knowledge: [matched chunks from Step 2]                     │
  │    AOP instruction: "Step 2: Use @Lookup Order to retrieve    │
  │      order details. If not found, ask customer to recheck."   │
  │    Code condition result: "eligible = true" (if applicable)   │
  │    Tools: [lookup_order, process_refund, cancel_order,        │
  │      create_voucher, award_points, assign_tag,                │
  │      escalate_to_human, create_ticket]                        │
  │                                                               │
  │  The LLM's ONLY job: "Given this step instruction and these   │
  │  tools, what should I do and say?" It does NOT figure out     │
  │  intent or find the AOP — code already did that.              │
  │                                                               │
  │  ─── AgentKit loop, iteration 1 ──────────────────────────    │
  │  │                                                             │
  │  │  LLM reasons: "AOP says lookup order. Customer gave 12345."│
  │  │    → tool_call: lookup_order(platform='shopee',             │
  │  │                              order_id='12345')              │
  │  │                                                             │
  │  │  AgentKit executes:                                         │
  │  │    → MCP: cs-actions (Render /mcp)                          │
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
  │  │  LLM has order data + code condition result from 4c:        │
  │  │    "eligible = true" (already evaluated by code)            │
  │  │                                                             │
  │  │  LLM reasons: "Eligible. AOP Step 4 says confirm first."   │
  │  │    → NO tool call. Compose confirmation message.            │
  │  │    → Final answer:                                          │
  │  │      {                                                      │
  │  │        customer_message: "สมชายครับ ตรวจสอบออเดอร์ #12345   │
  │  │          แล้วครับ (ครีมบำรุงผิว ฿590) อยู่ในระยะเวลา       │
  │  │          คืนเงินครับ ต้องการให้ดำเนินการคืนเงินเต็มจำนวน   │
  │  │          ฿590 เลยไหมครับ?",                                 │
  │  │        next_step: "wait_for_customer",                      │
  │  │        procedure_step: 4,                                   │
  │  │        data_collected: {                                    │
  │  │          order_id: "12345", amount: 590,                    │
  │  │          eligible: true, refund_type: "full"                │
  │  │        }                                                    │
  │  │      }                                                      │
  │  │                                                             │
  │  │  AgentKit: no more tool calls → exit loop                   │
  │                                                               │
  │  ── AgentKit done. Back to CODE. ────────────────────────── │
  │                                                               │
  │  STEP 4e — PARSE + RETURN (code)                              │
  │  Package result as JSON, return to Inngest Cloud               │
  └───────────────────────────────────────────────────────────────┘
```

**Turn 2 — Customer replies "Yes please proceed" (15 min later)**

Pipeline runs again: Steps 1-3 (load context, search knowledge, evaluate rules) execute as usual. Step 4 runs again on Render:

```
  ┌─── cs-ai-service (Render) — Turn 2 ────────────────────────┐
  │                                                               │
  │  4a — INTENT (code): Skip — procedure_state exists,           │
  │        intent already known: refund_request                    │
  │                                                               │
  │  4b — AOP LOOKUP (code): Load from procedure_state            │
  │        → "Refund Request Handler" v3, currently at Step 4      │
  │                                                               │
  │  4c — CURRENT STEP (code): Customer confirmed → advance to    │
  │        Step 5: "Process refund"                                │
  │        No code condition on this step.                         │
  │                                                               │
  │  ── AgentKit starts ────────────────────────────────────────  │
  │                                                               │
  │  4d — AGENTKIT LOOP                                           │
  │                                                               │
  │  ─── iteration 1 ─────────────────────────────────────────    │
  │  │  LLM: "Customer confirmed. Process the refund."             │
  │  │    → tool_call: process_refund(platform='shopee',           │
  │  │        order_id='12345', type='full', amount=590)           │
  │  │  AgentKit → MCP: cs-actions                                 │
  │  │    → Checks guardrail: ฿590 < ฿5000 limit ✓                │
  │  │    → HTTP: Shopee Refund API → { success: true }            │
  │  │                                                             │
  │  ─── iteration 2 ─────────────────────────────────────────    │
  │  │  LLM: "Refund done. Gold tier + damaged item → goodwill."   │
  │  │    → tool_call: award_points(user_id='crm_abc',             │
  │  │        amount=100, reason='goodwill')                        │
  │  │  AgentKit → MCP: crm-loyalty-actions                        │
  │  │    → CRM Bridge → post_wallet_transaction → { success }     │
  │  │                                                             │
  │  ─── iteration 3 ─────────────────────────────────────────    │
  │  │  LLM: "Create ticket for tracking."                         │
  │  │    → tool_call: create_ticket(conv_001, type='refund',      │
  │  │        priority='urgent', resolution='refunded')             │
  │  │  AgentKit → MCP: cs-actions                                 │
  │  │    → DB: cs_fn_create_ticket → { ticket_id: 'TKT_001' }    │
  │  │                                                             │
  │  ─── iteration 4 ─────────────────────────────────────────    │
  │  │  LLM: "All done. Compose final reply."                      │
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
  │  │  AgentKit: no more tool calls → exit loop                   │
  │                                                               │
  │  4e — PARSE + RETURN (code)                                   │
  └───────────────────────────────────────────────────────────────┘

Pipeline continues: Step 5 sends reply, Step 6 saves state,
Step 7 resolves → CSAT survey → memory extraction → done.
```

**Summary of what runs where inside Step 4:**

```
CODE (deterministic):     4a. Intent classification (fast LLM gpt-4o-mini, structured JSON)
CODE (deterministic):     4b. AOP lookup (DB query — can't hallucinate a procedure)
CODE (deterministic):     4c. Current step + code conditions (evaluated by code)
AGENTKIT (AI reasoning):  4d. LLM (gpt-4o) reasons within the step, calls MCP tools
CODE (deterministic):     4e. Parse result, return to Inngest
```

**Intent detection — registry + free-form:**

The LLM in 4a classifies the customer's intent as free text. It's not constrained to a fixed dropdown, but the prompt guides it toward known intents that have AOPs:

```
4a prompt: "Classify this customer's intent. Known intents with
  procedures: refund_request, order_tracking, product_inquiry,
  complaint, account_change, pre_sale_question.
  If none match, classify with your best description."
  Return JSON: { "intent": "...", "confidence": 0.0-1.0 }

4b then does:
  LLM said "refund_request"
    → DB: WHERE trigger_intent = 'refund_request' AND is_active = true
    → Found → load that AOP, pass to 4d

  LLM said "shipping_delay_complaint"
    → DB: WHERE trigger_intent = 'shipping_delay_complaint'
    → NOT found → tell 4d to use knowledge base + general reasoning

Admin can also force override: certain keywords or customer segments
  always trigger a specific procedure, bypassing 4a entirely.
```

Each `trigger_intent` maps to exactly one active procedure per merchant:
`UNIQUE (merchant_id, trigger_intent) WHERE is_active = true`

**AOP matching logic:**

| Situation | What happens |
|---|---|
| AOP found for intent | AI follows procedure step by step |
| Multiple AOPs match | Priority ranking or audience conditions pick one (e.g., different AOP for VIP vs standard) |
| No AOP found | AI uses knowledge base + general reasoning (no procedure to follow) |
| AOP step is ambiguous | LLM decides best action within the step's instructions |
| AOP step fails | Error handling path in AOP, or escalate to human |
| Admin override set | Forced procedure for keyword/segment, bypasses LLM intent classification |

**Guardrail enforcement inside AgentKit:**

| Level | Where | How |
|---|---|---|
| Brand guardrails | System prompt | LLM instructed: "never discuss competitors" (soft — prompt compliance) |
| Business-rule guardrails | MCP tool code | Code checks before API call: ฿590 < ฿5000 limit (hard — code blocks it) |
| Technical guardrails | MCP tool code | Rate limits, idempotency, parameter validation (hard) |
| Per-AOP policy | AOP step instructions | "If > 7 days, offer store credit instead" (soft — LLM follows instruction) |
| CODE CONDITIONS | Execution engine | Deterministic: `days <= 7` evaluated by code, result injected as fact (hard) |

---

## Step 5 — Send Reply (no AI, just platform API call)

**Runs on:** inngest-cs-serve (Supabase Edge Function)
**Technique:** HTTP call to platform chat API
**Calls downstream:** Platform API (Shopee / LINE / WhatsApp / etc.)

```
Inngest Cloud → HTTP POST → inngest-cs-serve

  Read agent.decide result → get customer_message + content type

  Route by channel:
    shopee  → HTTP: Shopee Chat API (POST /api/v2/sellerchat/send_message)
    line    → Edge Function: send-line-message → LINE Messaging API
    whatsapp → Edge Function: send-whatsapp-message → Twilio API
    email   → Edge Function: send-email → SendGrid/SES

  For this example:
    HTTP: Shopee Chat API
      POST /api/v2/sellerchat/send_message
      body: { to_id: 'buyer_789', content: 'สมชายครับ ตรวจสอบ...' }
    → Shopee delivers to customer

  Returns to Inngest Cloud → saved as step result
```

**Content type routing:**

| Content type | What's sent | Format |
|---|---|---|
| text | Plain text reply | String |
| product_card | Product recommendation | `{ type: 'product_card', item_id: 'SH_123' }` |
| order_card | Order status card | `{ type: 'order_card', order_id: '12345' }` |
| flex_message | Rich layout (LINE only) | LINE Flex Message JSON |
| image | Product photo, screenshot | URL to image |

All are just different payloads through the same send pipeline. No separate tool calls per content type.

---

## Step 6 — Save State (no AI, just DB writes)

**Runs on:** inngest-cs-serve (Supabase Edge Function)
**Technique:** Supabase RPC calls — native DB access
**Calls downstream:** Supabase DB

```
Inngest Cloud → HTTP POST → inngest-cs-serve

  DB: cs_fn_insert_message(conv_001, sender='ai', text='สมชายครับ ตรวจสอบ...')
    → Inserts AI reply as message row
    → Updates conversation.last_message_at

  DB: cs_fn_save_procedure_state(conv_001, {
    procedure_id: 'refund-handler-v3',
    current_step: 4,
    data_collected: { order_id: '12345', amount: 590, eligible: true }
  })
    → Saves where we are in the AOP for next turn

  DB: INSERT into cs_conversation_events
    → event_type: 'ai_replied'
    → Event sourcing log (same pattern as amp_workflow_log)

  Returns to Inngest Cloud → saved as step result
```

**What `procedure_state` contains (persisted across turns):**

```json
{
  "procedure_id": "refund-handler-v3",
  "procedure_name": "Refund Request Handler",
  "current_step": 4,
  "intent": "refund_request",
  "data_collected": {
    "order_id": "12345",
    "amount": 590,
    "eligible": true,
    "refund_type": "full",
    "delivered_at": "2026-03-31",
    "items": [{ "name": "Face Cream", "qty": 1 }]
  },
  "actions_taken": ["lookup_order"],
  "started_at": "2026-04-04T10:30:00Z"
}
```

This is how the AI "remembers" across turns. Next message → Step 1 loads this → Step 4 (AgentKit) picks up at AOP Step 4 with all data intact.

---

## Step 7 — Wait or Resolve

**Runs on:** inngest-cs-serve (Supabase Edge Function) → Inngest Cloud
**Technique:** Inngest durable wait (`step.waitForEvent`) or pipeline completion

### Path A — Wait for customer reply

```
  agent.decide returned next_step: "wait_for_customer"

  step.waitForEvent("customer-reply", {
    event: "cs/message.received",
    if: "async.data.conversation_id == 'conv_001'",
    timeout: "24h"
  })

  ╔══════════════════════════════════════════════════════════════╗
  ║  WAITING — nothing running anywhere                         ║
  ║  Inngest Cloud holds state. All step results saved.         ║
  ║  Server can restart. No resources consumed.                 ║
  ║                                                             ║
  ║  When customer replies → webhook → inngest.send() →         ║
  ║  Inngest Cloud resumes → pipeline starts over at Step 1     ║
  ║  with fresh context (now includes procedure_state)          ║
  ╚══════════════════════════════════════════════════════════════╝
```

### Path B — Resolve conversation

```
  agent.decide returned next_step: "resolve"

  step.run("update-resolved")
    DB: UPDATE cs_conversations SET status='resolved', resolved_at=now()
    DB: UPDATE cs_tickets SET status='resolved' (if ticket exists)
    DB: INSERT cs_conversation_events (event_type: 'resolved')

  step.run("trigger-csat")
    HTTP: Platform API → send CSAT survey message

  step.invoke("cs/agent.extract-memory") → Render
    AgentKit reads full transcript
    LLM extracts memory: { category, key, value, confidence }
    DB: INSERT into cs_customer_memory

  step.run("log-complete")
    DB: INSERT cs_conversation_events (event_type: 'execution_completed')
    Update analytics counters

  DONE.
```

### Path C — Escalate to human

```
  agent.decide returned next_step: "escalate"
  (or escalate_to_human tool was called inside AgentKit)

  step.run("assign-human")
    DB: cs_fn_auto_assign(merchant_id, conversation_id, skills_needed)
      → Finds best available agent (round-robin, respects max_concurrent)
    DB: UPDATE cs_conversations SET assigned_agent=agent_id, status='open'
    DB: INSERT cs_conversation_events (event_type: 'escalated_to_human',
      summary: 'AI summary of what happened so far')

  Human agent now sees conversation in their inbox with:
    - Full message history
    - AI's summary of what was attempted
    - Ticket (if created)
    - All data AI collected (order details, eligibility check, etc.)

  Pipeline ends. Human takes over.
```

---

## Full Pipeline per Technique

```
Step 0: webhook          → Code (signature validation + DB insert)
Step 1: load-context     → Supabase RPC (single DB call, no AI)
Step 2: search-knowledge → OpenAI Embedding API + pgvector (no AI reasoning)
Step 3: evaluate-rules   → Supabase RPC (AMP workflow engine, domain='cs')
                           Handles keyword, channel, tier, semantic Q&A conditions.
                           Can short-circuit → skip AI entirely.
Step 4: agent.decide     → AgentKit on Render (LLM + MCP tool loop)
                           Intent detection → AOP matching → step execution.
                           Only step that uses AI reasoning.
Step 5: send-reply       → Platform API (Shopee/LINE/WhatsApp/email)
Step 6: save-state       → Supabase RPC (message + procedure state + event log)
Step 7: wait/resolve     → Inngest waitForEvent or resolve + memory extraction
```

---

## Voice Pipeline — Graph Executor + Deterministic Prefetch

> Voice uses a different orchestration pattern for real-time latency (<1.5s).
> Same agent brain, same AOPs, same MCP tools. See `cs_voice_architecture.md`
> for the full spec and `cs_ai_message_journey.md` for call-by-call trace.

```
Voice uses ElevenLabs for STT/TTS only (no AI reasoning on ElevenLabs).
All decisioning on our infrastructure via Custom LLM mode.

  VOICE ENTRY: Phone → Twilio → ElevenLabs STT → text
               → Custom LLM endpoint (voice-custom-llm Edge Function)

  PER-TURN PIPELINE (5 phases):

  Phase 1: Route + Extract      → Deterministic (10-20ms)
    Load procedure_state → current step.
    Run entity_extractors from compiled_steps (regex/keyword, no LLM).
    Match intent if no active AOP.

  Phase 2: Prefetch (step-aware) → Code calls data tools directly (0-300ms)
    Read current step's data_needs[].
    Evaluate each "when" condition against extracted entities.
    Call matching data tools as code (NOT via LLM tool_call):
      context: always (~20ms)
      knowledge search: only if step declares it (~200ms)
      lookup_order: only if step declares it AND order_number extracted (~200ms)
    All declared sources in parallel (Promise.all).
    Empty data_needs → context only (~20ms). No wasted API calls.

  Phase 3: Walk AOP graph       → Deterministic (5-10ms)
    Evaluate code_conditions against collected + prefetched data.
    Determine which step to execute. Build step-focused LLM prompt.

  Phase 4: ONE LLM call         → LLM as Writer (500ms-1s)
    LLM receives ALL prefetched data as facts in the prompt.
    LLM never calls data tools — it just composes the response.
    Unlike chat Step 4 (AgentKit loops LLM→tool→LLM 2-4 times).

  Phase 5: Deliver + execute    → Async
    Stream response → ElevenLabs TTS (immediate).
    Execute action_tools from LLM response: refund, points, ticket (post-response).
    Save state non-blocking.

  POST-CALL: call.ended → Inngest cs/voice.post-call
    Same as chat: memory extraction, analytics. Plus: transcript, recording.
```

### Chat vs Voice Pipeline Comparison

```
                          CHAT (Inngest)              VOICE (Graph Executor)
Orchestrator:             Inngest Cloud               Graph on Render (direct)
Steps 1-3 execution:      Sequential (3 HTTP hops)    Parallel, step-aware prefetch
Data tool calls:           LLM discovers → tool_call   Code reads data_needs → calls directly
Agent reasoning:           AgentKit loop (2-4 LLM)     1 LLM call (writer mode)
Action execution:          Inside LLM loop (blocking)  After response (async)
Delivery:                  messaging-service → API     ElevenLabs TTS
State between turns:       Inngest waitForEvent        Continuous (same call)
State across sessions:     DB procedure_state          DB procedure_state (same)
AOPs:                      Same compiled_steps         Same compiled_steps
MCP tools:                 Same (via MCP protocol)     Same (direct import)
Post-resolution:           Inngest (memory, CSAT)      Inngest (memory, CSAT)
Latency per turn:          3-9s                        ~0.8-1.5s
```

### Deterministic Prefetch — Core Idea

```
Each AOP step declares data_needs[] — what data sources that step requires.
The graph executor reads this and calls data tools directly as code.
The LLM never makes data tool calls. It receives everything pre-loaded.

  DATA tools (in step.data_needs):
    Called by GRAPH EXECUTOR (code) before LLM call.
    lookup_order, search_knowledge, get_customer_profile, check_stock
    Same functions that MCP exposes — graph imports them directly.

  ACTION tools (in step.action_tools):
    LLM decides which to execute. Code runs them after response is sent.
    process_refund, award_points, create_ticket, escalate_to_human

  3-tier prefetch strategy:
    Tier 1: Step has data_needs with tools → code calls them → 1 LLM call (~1.1s)
    Tier 2: Step has knowledge-only or empty data_needs → context + KB → 1 LLM call (~0.8s)
    Tier 3: No AOP matched → defaults only → LLM explorer fallback → 2+ LLM calls (~2s)

When prefetch can't determine what's needed (~20% of turns):
  LLM falls back to "explorer" mode (discovers → tool call → 2nd LLM call).
  Adds ~0.5-1s. Filler phrase covers the gap on voice.
```
