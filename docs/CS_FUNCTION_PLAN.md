# CS Module — Function & Component Plan

> **Context:** Schema (17 cs_ tables) created. 31 DB functions deployed. 4 edge functions deployed (inngest-cs-serve, webhook-shopee, embed-knowledge, cs-loyalty-bridge). Remaining: 4 webhook templates (lazada/tiktok/line/whatsapp) + Render AgentKit agents + MCP tools.

---

## Architecture Summary

```
┌─────────────────────────────────────────────────────────────────┐
│ SUPABASE                                                        │
│                                                                 │
│ DB Functions (31 total)                                         │
│ ├── cs_api_*  (1)  — webhook entry point                       │
│ ├── cs_fn_*   (18) — pipeline, business logic, helpers          │
│ └── cs_bff_*  (12) — admin panel (multi-table joins only)       │
│                                                                 │
│ Edge Functions (8 total)                                        │
│ ├── inngest-cs-serve     — Inngest orchestrator (native DB)     │
│ ├── webhook-shopee/lazada/tiktok/line/whatsapp  — 5 receivers   │
│ ├── embed-knowledge      — auto-embedding pipeline              │
│ └── cs-loyalty-bridge    — cross-project CRM bridge             │
│                                                                 │
│ Direct CRUD via Supabase client + RLS (no functions needed)     │
│ └── 12 tables: config, guardrails, SLA, hours, sources, etc.   │
│                                                                 │
├─────────────────────────────────────────────────────────────────┤
│ INNGEST CLOUD                                                   │
│ ├── Routes cs/* events to inngest-cs-serve (edge function)      │
│ ├── Routes cs/agent.* events to amp-ai-service (Render)         │
│ └── Manages step state, retries, waitForEvent, crons            │
│                                                                 │
├─────────────────────────────────────────────────────────────────┤
│ RENDER — amp-ai-service (EXISTING, expanded)                    │
│                                                                 │
│ /api/inngest — AgentKit functions:                              │
│ ├── marketing-decision-agent  (existing, AMP)                   │
│ ├── cs-conversation-agent     (new, CS)                         │
│ └── cs-memory-extractor       (new, CS)                         │
│                                                                 │
│ /mcp — Combined MCP server:                                     │
│ ├── CRM tools (existing): award_points, assign_tag, send_line   │
│ └── CS tools (new): lookup_order, cancel_order, process_refund, │
│     create_marketplace_voucher, search_knowledge,               │
│     escalate_to_human, create_ticket, close_conversation        │
│                                                                 │
│ /health                                                         │
└─────────────────────────────────────────────────────────────────┘
```

### How Components Connect (inbound message flow)

```
Shopee webhook
  → Edge: webhook-shopee
    → DB: cs_api_receive_message()  (native)
    → emit Inngest event: cs/message.received

  → Inngest Cloud calls → Edge: inngest-cs-serve
    → step.run("load-context")       → DB: cs_fn_load_conversation_context()
    → step.run("custom-answer")      → DB: cs_fn_match_custom_answer()
    → step.run("search-knowledge")   → embed query via OpenAI → DB: cs_fn_search_knowledge()
    → step.run("evaluate-rules")     → DB: cs_fn_evaluate_rules()

    → step.invoke("cs/agent.decide") → Inngest routes to Render
      → AgentKit: LLM reasons → calls MCP tools → loops → returns decision

    → step.run("send-reply")         → fetch platform API
    → step.run("save-state")         → DB: cs_fn_save_procedure_state()
    → step.waitForEvent or resolve
```

---

## DB Functions — Pipeline (19)

Called by edge functions, Inngest steps, and other functions. Not called directly by FE.

### Inbound Message Processing

| # | Function | Called by | Purpose |
|---|---|---|---|
| 1 | `cs_api_receive_message` | Webhook edge functions | Master inbound: resolve contact + upsert conversation + insert message. Returns conversation_id, contact_id, is_new_conversation. |
| 2 | `cs_fn_resolve_contact` | `cs_api_receive_message` | Find or create cs_contacts + cs_platform_identities from merchant_id + platform_type + platform_user_id. |
| 3 | `cs_fn_upsert_conversation` | `cs_api_receive_message` | Threading logic: check session_timeout, threading_interval, status to decide new vs reopen vs append. |
| 4 | `cs_fn_insert_message` | `cs_api_receive_message`, `cs_bff_send_message` | Insert message + update conversation.last_message_at + insert conversation event. |

### AI Pipeline Support

| # | Function | Called by | Purpose |
|---|---|---|---|
| 5 | `cs_fn_load_conversation_context` | Inngest step | Single call returns everything AI needs: conversation + last N messages + contact + memory + ticket + config + guardrails + active procedure. Structured jsonb. |
| 6 | `cs_fn_match_custom_answer` | Inngest step | Check message against custom answer question_patterns. Returns match or null. Checked before AI. |
| 7 | `cs_fn_search_knowledge` | Inngest step | pgvector cosine similarity: accept embedding vector + merchant_id, return top K chunks with article metadata. |
| 8 | `cs_fn_evaluate_rules` | Inngest step | Load active CS workflows (domain='cs'), evaluate conditions against context, return actions to execute. |
| 9 | `cs_fn_get_active_procedure` | Inngest step | Lookup active procedure for merchant + intent. |
| 10 | `cs_fn_auto_assign` | Inngest step, `cs_bff_update_conversation` | Find best agent: round-robin within team, respects max_concurrent, skills, online status. |

### State Management

| # | Function | Called by | Purpose |
|---|---|---|---|
| 11 | `cs_fn_save_procedure_state` | Inngest step | Save AOP execution state (current step, collected data, tool results) to cs_conversations.procedure_state. |
| 12 | `cs_fn_resolve_conversation` | Inngest step, `cs_bff_update_conversation` | Set status=resolved, resolved_at, log event, check if linked ticket auto-resolves. |
| 13 | `cs_fn_extract_customer_memory` | Inngest step (post-resolution) | Batch upsert memory entries: insert new, update existing (match on contact_id + category + key). |

### Tickets

| # | Function | Called by | Purpose |
|---|---|---|---|
| 14 | `cs_fn_create_ticket` | Inngest step, `cs_bff_update_ticket` | Generate ticket number + assign SLA + insert ticket + ticket event. Returns ticket_id. |
| 15 | `cs_fn_generate_ticket_number` | `cs_fn_create_ticket` | Sequential "TKT-2026-00001" per merchant with advisory lock. |
| 16 | `cs_fn_assign_sla` | `cs_fn_create_ticket` | Match ticket against SLA policy conditions, calculate deadline using business hours. |
| 17 | `cs_fn_calculate_sla_deadline` | `cs_fn_assign_sla` | Pure calc: start_time + target_minutes + business hours schedule → deadline timestamp. |
| 18 | `cs_fn_check_sla_breaches` | Inngest cron step | Find tickets/conversations approaching or past SLA deadline. Returns list for escalation. |

### Identity

| # | Function | Called by | Purpose |
|---|---|---|---|
| 19 | `cs_fn_merge_contacts` | Admin action | Re-point platform_identities, conversations, tickets, memory from secondary → primary. Soft-delete secondary. |

---

## DB Functions — Admin BFF (12)

Called by admin panel FE. Only functions that need multi-table joins or business logic with side effects. Everything else is direct CRUD.

### Conversations (unified inbox)

| # | Function | Purpose |
|---|---|---|
| 20 | `cs_bff_list_conversations` | Joins conversations + contacts (name, phone) + last message preview + SLA status. Filters: status, channel, priority, assignee, team, tags. Pagination. |
| 21 | `cs_bff_get_conversation_details` | Conversation + all messages (jsonb_agg) + contact + linked ticket + procedure state. |
| 22 | `cs_bff_update_conversation` | Single function for all updates: status, priority, tags, assignee, team, custom_fields, intent. Logs events for each change. Sets resolved_at when status→resolved. |
| 23 | `cs_bff_send_message` | Insert message (sender_type='agent' or 'note') + log event + update last_message_at. |

### Contacts

| # | Function | Purpose |
|---|---|---|
| 24 | `cs_bff_get_contact_details` | Contact + all platform_identities + customer memory + recent conversation summaries. Agent workspace sidebar. |

### Tickets

| # | Function | Purpose |
|---|---|---|
| 25 | `cs_bff_list_tickets` | Tickets + contact name + computed SLA status (on-track / at-risk / breached). Filters: type, status, priority, assignee, SLA status. |
| 26 | `cs_bff_get_ticket_details` | Ticket + linked conversations (summaries) + ticket events timeline + contact + parent/children. |
| 27 | `cs_bff_update_ticket` | Upsert: if no ticket_id → create (calls cs_fn_create_ticket). If ticket_id → update fields + log events + update timestamps (first_response_at, resolved_at, closed_at). |

### Knowledge & Procedures

| # | Function | Purpose |
|---|---|---|
| 28 | `cs_bff_upsert_knowledge_article` | Validates custom answer patterns. On insert/update may trigger re-embedding via pgmq. |
| 29 | `cs_bff_upsert_procedure` | Versioning: insert new row with version+1, deactivate old. Validate trigger_intent uniqueness. |
| 30 | `cs_bff_activate_procedure` | Toggle is_active. Deactivate other versions with same trigger_intent for this merchant. |

### Agents

| # | Function | Purpose |
|---|---|---|
| 31 | `cs_bff_list_agents` | admin_users + current open conversation count (subquery) + team + online status. Supervisor dashboard. |

---

## Edge Functions (8)

| # | Function | Purpose | JWT |
|---|---|---|---|
| 1 | `inngest-cs-serve` | Inngest serve endpoint. Registers all CS Inngest functions. Inngest Cloud calls this for step execution. Native Supabase client for DB steps, `step.invoke` for AI steps. | Disabled (Inngest signing key) |
| 2 | `webhook-shopee` | Parse Shopee chat webhook → validate signature → `cs_api_receive_message` → emit `cs/message.received` | Disabled (Shopee signature) |
| 3 | `webhook-lazada` | Same for Lazada | Disabled |
| 4 | `webhook-tiktok` | Same for TikTok Shop | Disabled |
| 5 | `webhook-line` | Same for LINE (may extend existing `line-webhook`) | Disabled |
| 6 | `webhook-whatsapp` | Same for WhatsApp | Disabled |
| 7 | `embed-knowledge` | Auto-embedding: pgmq → chunk text → OpenAI embedding API → write to cs_knowledge_embeddings | Disabled |
| 8 | `cs-loyalty-bridge` | Cross-project calls to CRM Supabase for loyalty data | Disabled (service key) |

---

## Inngest Functions (5, registered in `inngest-cs-serve`)

| # | Function | Trigger | Steps (runs on edge function) |
|---|---|---|---|
| 1 | `cs/conversation.process` | Event: `cs/message.received` | load-context → custom-answer-check → search-knowledge → evaluate-rules → `step.invoke("cs/agent.decide")` → send-reply → save-state |
| 2 | `cs/procedure.execute` | Event: `cs/procedure.start` | load-context → `step.invoke("cs/agent.decide")` → send-reply → save-state → `step.waitForEvent` → repeat |
| 3 | `cs/sla.check` | Cron: every 5 min | `cs_fn_check_sla_breaches()` → escalate / notify for each |
| 4 | `cs/memory.extract` | Event: `cs/conversation.resolved` | `step.invoke("cs/agent.extract-memory")` → `cs_fn_extract_customer_memory()` |
| 5 | `cs/knowledge.sync` | Event: `cs/knowledge.sync.requested` | Crawl source URL → parse content → write articles → trigger embedding |

---

## Render — `amp-ai-service` Additions

Existing Render service expanded. No new deployment.

### New AgentKit Functions (registered at `/api/inngest`)

| # | Function | Triggered by | Purpose |
|---|---|---|---|
| 1 | `cs-conversation-agent` | `cs/agent.decide` | AgentKit agent: receives context, calls LLM, LLM calls MCP tools, loops until final answer. Returns reply + actions_taken + data_collected + next_step. |
| 2 | `cs-memory-extractor` | `cs/agent.extract-memory` | LLM reads conversation transcript, extracts structured memory entries (category, key, value, confidence). |

### New MCP Tools (added to existing `/mcp` server)

| # | Tool | Category | What it does |
|---|---|---|---|
| 1 | `lookup_order` | Marketplace | Query Shopee/Lazada/TikTok order API |
| 2 | `cancel_order` | Marketplace | Cancel order via platform API |
| 3 | `process_refund` | Marketplace | Process refund via platform API |
| 4 | `create_marketplace_voucher` | Marketplace | Create platform-specific voucher |
| 5 | `send_product_card` | Marketplace | Send product card in marketplace chat |
| 6 | `search_knowledge` | Knowledge | Embed query via OpenAI + call `cs_fn_search_knowledge` via Supabase |
| 7 | `escalate_to_human` | CS Internal | Assign conversation to agent with AI summary |
| 8 | `create_ticket` | CS Internal | Create ticket via `cs_fn_create_ticket` |
| 9 | `trigger_csat` | CS Internal | Send CSAT survey |
| 10 | `close_conversation` | CS Internal | Resolve via `cs_fn_resolve_conversation` |

---

## Direct CRUD (no function — Supabase client + RLS)

| Table | Operations | Notes |
|---|---|---|
| `cs_merchant_config` | get, upsert | One row per merchant |
| `cs_merchant_guardrails` | list, insert, update, delete | Individual guardrail rules |
| `cs_sla_policies` | list, insert, update, delete | |
| `cs_business_hours` | list, insert, update, delete | Schedule + holidays |
| `cs_knowledge_sources` | list, insert, update | Source lifecycle |
| `cs_knowledge_articles` | list, get single | Basic read for edit form. Upsert uses BFF (validation). |
| `cs_procedures` | list | Basic table read. Upsert/activate use BFF (versioning). |
| `cs_action_config` | list, update | Toggle enable/disable, set constraints |
| `cs_contacts` | basic list | Search by name/phone/email |
| `cs_customer_memory` | list by contact_id, delete | PDPA delete-all |
| `admin_users` CS columns | update | cs_online_status, cs_max_concurrent, cs_skills |
| `admin_teams` | list, insert, update | |

---

## Build Order

```
Phase A — Foundation (no dependencies)
  DB: cs_fn_resolve_contact, cs_fn_generate_ticket_number,
      cs_fn_calculate_sla_deadline, cs_fn_search_knowledge,
      cs_fn_match_custom_answer

Phase B — Core Pipeline (depends on A)
  DB: cs_fn_upsert_conversation, cs_fn_insert_message,
      cs_api_receive_message, cs_fn_assign_sla,
      cs_fn_create_ticket, cs_fn_auto_assign
  Edge: webhook-shopee (first channel)

Phase C — AI Pipeline (depends on B)
  DB: cs_fn_load_conversation_context, cs_fn_get_active_procedure,
      cs_fn_evaluate_rules, cs_fn_save_procedure_state
  Edge: inngest-cs-serve
  Render: cs-conversation-agent + CS MCP tools

Phase D — Resolution (depends on C)
  DB: cs_fn_resolve_conversation, cs_fn_extract_customer_memory,
      cs_fn_check_sla_breaches, cs_fn_merge_contacts
  Render: cs-memory-extractor

Phase E — Admin BFFs (parallel, depends on tables only)
  DB: All 12 cs_bff_* functions — can build in parallel per area

Phase F — Remaining Edge Functions
  Edge: webhook-lazada, webhook-tiktok, webhook-line, webhook-whatsapp,
        embed-knowledge, cs-loyalty-bridge
```

---

## Total Component Count

| Layer | Count |
|---|---|
| DB Functions (pipeline) | 19 |
| DB Functions (admin BFF) | 12 |
| Edge Functions | 8 |
| Inngest Functions | 5 |
| Render AgentKit agents | 2 |
| Render MCP tools (new) | 10 |
| **Total** | **56** |
