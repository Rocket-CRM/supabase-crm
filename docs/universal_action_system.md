# Universal Action System — Architecture Reference

> **Purpose:** Single source of truth for how actions, entities, macros, guardrails, intents, and callers fit together across all modules (CS, Loyalty/AMP, future modules).
>
> **Status:** Architecture agreed. Partial implementation in place. Migration from module-specific naming to universal naming pending.

---

## 1. Core Concept

Multiple callers (AI agents, rule engines, human agents, external partners) need to execute the same set of actions (cancel order, award points, send message) across multiple domains (CS, Loyalty, Content). The action system is the **universal foundation** that all callers share.

**The action system is NOT owned by any module.** AMP is a caller. CS AI is a caller. A human agent clicking a button is a caller. The actions, entities, guardrails, and macros exist independently of who invokes them.

---

## 2. Object Model

### Core Concepts

| Concept | What it is | Example |
|---|---|---|
| **Entity** | A thing that exists — serves as a target (operated on), context (consulted), or material (consumed) | Order #250, Knowledge article "Return Policy", LINE template |
| **Action** | A specific named operation on an entity | `cancel_order`, `award_points`, `search_knowledge` |
| **Action Category** | A behavioral pattern for a group of actions — defines how they should be approached, not what they do | `destructive`, `read`, `creative`, `delivery` |
| **Action Execution** | A record of an action that happened | "Cancelled order #250 at 18:40" |
| **Macro** | A sequence of actions exposed as a single tool — callers can't tell the difference | "Full Cancel and Refund" = lookup → cancel → refund |
| **Intent** | What the customer wants — maps to actions | "cancel_order", "return_request" |
| **Procedure** | A conversation flow for handling an intent — system default or merchant-specific (AOP) | "Cancel Order AOP: ask order number → verify → lookup → confirm → cancel" |
| **Rules** | Constraints that govern action execution at three levels — each level can only narrow, never widen | Category: "destructive requires confirmation". Caller: "max refund ฿5,000". Runtime: "already cancelled" |
| **Caller** | Who invokes an action | CS AI Agent, AMP Rule Engine, Human Agent |
| **Interface** | How a caller accesses actions — generated from registries at runtime | MCP tools, AgentKit `createTool()`, UI buttons, workflow nodes |

### Entity roles

Entities serve three distinct roles depending on how actions use them:

| Role | What it means | Entities | Example actions |
|---|---|---|---|
| **Target** | Directly operated on or modified by an action | order, customer, wallet, tag, ticket, conversation, voucher, persona, audience | cancel_order, award_points, assign_tag |
| **Context** | Information the AI consults to reason — never shown raw to customers | knowledge | search_knowledge |
| **Material** | Content consumed by delivery actions — the "what to send" | resource (templates, messages, media) | send_line_message, send_sms |

A single entity can serve multiple roles. `product` is a target (check_product_stock) and context (recommend_products draws on product knowledge).

### Object relationships

```
[ Action ]  ──belongs to──▶  [ Action Category ]
            ──operates on──▶  [ Entity ]
            ──governed by──▶  [ Rules ]  (inherited from category + own action-specific rules)

[ Action Category ]  ──defines──▶  [ Rules (Level 1: system defaults) ]
                      ├─ rules_prompt   →  upstream thinking guidance (consumed by AI)
                      └─ rules          →  downstream enforcement flags (consumed by code)

[ Macro ]  =  Sequence of  [ Action, Action, ... ]
              Exposed at same level as actions — callers can't tell the difference

[ Intent ]  ──maps to──▶  [ Action(s) ]  (entities implied by the actions)
            ──resolved by──▶  [ Procedure ]  (if merchant AOP exists for this intent)

[ Procedure ]  ──triggered by──▶  [ Intent ]  (via trigger_intent)
               ──guides execution of──▶  [ Action(s) ]
               ──defines──▶  conversation flow, step instructions, compiled conditions

[ Caller ]  ──invokes──▶  [ Action ] or [ Macro ]
            ──through──▶  [ Interface ]  (MCP tools, UI buttons, workflow nodes)
            ──constrained by──▶  [ Rules (Level 2: caller config) ]

[ Entity ]  ──three roles──▶  Target (operated on), Context (consulted), Material (consumed)

[ Rules ]  ──three levels, each can only narrow──▶
   Level 1 (System)   →  action_category.rules_code + action_registry.rules_code       [platform engineers]
   Level 2 (Caller)   →  action_caller_config.rules_code + merchant config             [CX team per merchant]
   Level 3 (Runtime)  →  idempotency, rate limits, platform health, balances  [computed by system]
```

### Rules — three types

Every rule in the system is one of three types based on how it's consumed:

| Type | Consumed by | Form | Where it lives | Example |
|---|---|---|---|---|
| `rules_prompt` | LLM only | Natural language thinking pattern — guidance before acting | `action_category.rules_prompt`, `cs_procedures.raw_content`, `cs_merchant_config` | `"Lookup state first. Verify identity. Present impact. Get confirmation. Execute."` |
| `rules_code` | Code only | Structured flags — enforcement during execution | `action_category.rules_code`, `action_registry.rules_code`, `action_caller_config.rules_code` | `{ requires_confirmation: true, requires_lookup_first: true, max_amount: 5000 }` |
| `rules` | Both LLM + Code | Prompt-injected guidance with code-level keyword/trigger enforcement | `cs_merchant_guardrails` | `"Never discuss competitors"` — LLM self-censors, code auto-tags violations |

`rules_prompt` can't "fail" — the AI might ignore it, but `rules_code` catches that. The system never relies on AI compliance alone for safety-critical rules.

### 2.1 Entities — what the system knows about

| Entity | Where it lives | Platform-dependent? | Examples |
|---|---|---|---|
| `order` | Platform API (live) | Yes | Shopee order, BigCommerce order |
| `product` | Platform API (live) + Knowledge base (cached descriptions) | Price/stock: yes. Knowledge: no | SKU, catalog item |
| `customer` | Internal DB (`cs_contacts`, `user_master`) | No — unified | Contact, CRM user |
| `conversation` | Internal DB (`cs_conversations`) | No | Chat thread |
| `ticket` | Internal DB (`cs_tickets`) | No | Support case |
| `knowledge` | Internal DB (`cs_knowledge_articles`) | No | FAQ, policy, product guide |
| `promotion` | Platform API (live) | Yes | Shopee voucher, BigCommerce coupon |
| `voucher` | Platform API or CRM | Depends | Platform coupon vs loyalty voucher |
| `shipment` | Platform API (live) | Yes | Tracking, carrier |
| `wallet` | Internal DB (`wallet_ledger`) | No | Points, tickets |
| `tag` | Internal DB (`tag_master`, `user_tags`) | No | User classification |
| `persona` | Internal DB (`persona_master`) | No | User profile type |
| `audience` | Internal DB (`amp_audience_master`) | No | Segment for targeting |
| `resource` | Internal DB (content resources) | No | Messages, templates, media |

### Knowledge and Resource — how content is accessed

Knowledge (context) and Resource (material) entities are accessed differently by AI vs human callers, and searching vs sending use different functions:

| Content type | AI can search | AI can send | Human can search | Human can send |
|---|---|---|---|---|
| Knowledge articles | `cs_fn_search_knowledge` (embeddings) | N/A — reference only | `cs_fn_search_knowledge_articles` (text) | N/A — reference only |
| Resources (quick reply, media, etc.) | `cs_fn_search_resources` | `cs_fn_send_resource` | `cs_fn_search_resources` (same function) | `cs_fn_send_resource` (same function) |
| Pattern auto-match | `cs_fn_match_resource` | — | — | — |

AI uses vector search (embeddings) for knowledge. Humans use text search. Resources use the same functions for both callers. Pattern auto-match is AI-only — automatically suggests a resource when the message matches a pattern.

### 2.2 Action Categories — how actions behave

Categories define **rules** at two levels:
- **Upstream (rules_prompt):** Natural language thinking pattern — consumed by AI callers to reason about actions
- **Downstream (rules):** Structured enforcement — consumed by code to block invalid execution

Both express the same rules, different audiences. The category sets defaults; individual actions can add specifics on top.

| Category | Rules prompt (for AI) | Rules (for code) | Description |
|---|---|---|---|
| `read` | Call directly. Present results factually. Never fabricate. | — | Read-only data retrieval |
| `destructive` | Lookup current state first. Verify identity if configured. Present what will happen. Get explicit confirmation. Execute. | requires_lookup_first, requires_confirmation, idempotency_check | Irreversible changes to existing entities |
| `mutative` | Lookup current state first. Present proposed change. Get confirmation. Execute. | requires_lookup_first, requires_confirmation | Reversible changes to existing entities |
| `creative` | Collect all required info. Present summary. Get confirmation for high-value items. Execute. | requires_confirmation (above threshold) | Creates new entities |
| `delivery` | Check rate limits and quiet hours. Execute. | rate_limit, quiet_hours | Sends content to external channels |
| `internal` | Execute based on context. No customer confirmation needed. | — | Internal system operations |

### 2.3 Actions — what the system can do

Each action operates on an entity, belongs to a category, and lives in a domain.

**CS Domain:**

| Action | Entity | Category | Platform? |
|---|---|---|---|
| `lookup_order` | order | read | Yes |
| `get_recent_orders` | order | read | Yes |
| `get_order_shipping` | shipment | read | Yes |
| `search_products` | product | read | Yes |
| `check_product_stock` | product | read | Yes |
| `get_product_price` | product | read | Yes |
| `check_promotion` | promotion | read | Yes |
| `recommend_products` | product | read | Yes |
| `get_customer_profile` | customer | read | No |
| `search_knowledge` | knowledge | read | No |
| `cancel_order` | order | destructive | Yes |
| `process_refund` | order | destructive | Yes |
| `update_order` | order | mutative | Yes |
| `apply_coupon` | order + promotion | mutative | Yes |
| `create_order` | order | creative | Yes (subset) |
| `create_voucher` | voucher | creative | Depends |
| `send_message` | conversation | delivery | Channel-dependent |
| `escalate_to_human` | conversation | internal | No |
| `create_ticket` | ticket | internal | No |
| `close_conversation` | conversation | internal | No |
| `trigger_csat_survey` | conversation | internal | No |

**Loyalty Domain:**

| Action | Entity | Category | Platform? |
|---|---|---|---|
| `award_points` | wallet | creative | No |
| `award_tickets` | wallet | creative | No |
| `assign_tag` | tag | mutative | No |
| `remove_tag` | tag | destructive | No |
| `assign_persona` | persona | mutative | No |
| `assign_earn_factor` | wallet | creative | No |
| `send_line_message` | resource | delivery | No (LINE only) |
| `send_sms` | resource | delivery | No (SMS only) |
| `submit_form` | resource | creative | No |
| `add_to_audience` | audience | mutative | No |
| `remove_from_audience` | audience | destructive | No |

### 2.4 Entity → Action Map

| Entity | Read | Destructive | Mutative | Creative |
|---|---|---|---|---|
| order | lookup_order, get_recent_orders | cancel_order, process_refund | update_order, apply_coupon | create_order |
| product | search_products, check_product_stock, get_product_price, recommend_products | — | — | — |
| customer | get_customer_profile | — | assign_persona, assign_tag | — |
| shipment | get_order_shipping | — | — | — |
| promotion | check_promotion | — | — | — |
| voucher | — | — | — | create_voucher |
| wallet | — | — | — | award_points, award_tickets, assign_earn_factor |
| tag | — | remove_tag | assign_tag | — |
| audience | — | remove_from_audience | add_to_audience | — |
| knowledge | search_knowledge | — | — | — |
| conversation | — | — | — | send_message, escalate_to_human, close_conversation |
| ticket | — | — | — | create_ticket |

### 2.5 Macros — pre-composed action sequences

A macro is a named sequence of actions with injectable parameters. The executor (`fn_execute_macro`) loops through the steps and calls `fn_execute_action` for each one. Not code — just a list of instructions.

Macros and actions are exposed at the **same level** to callers. The caller sees a flat list of tools. It doesn't know which is a single action and which is a macro underneath.

| Macro | Steps | Domain |
|---|---|---|
| `full_cancel_and_refund` | lookup_order → cancel_order → process_refund(full) | CS |
| `goodwill_gesture` | create_voucher → send_message | CS |
| `replacement_order` | lookup_order → create_order (same items) → cancel_order (original) | CS |
| `order_status_check` | lookup_order → get_order_shipping | CS |
| `escalate_with_context` | create_ticket → escalate_to_human | CS |
| `loyalty_reward` | award_points → send_line_message | Loyalty |
| `re_engage_lapsed` | assign_tag → assign_earn_factor → send_line_message | Loyalty |

### 2.6 Intents — what the customer wants

Intents map customer requests to **actions** (entities are already implied by the actions).

Intents exist at two levels:
- **System intents** — common across all merchants (cancel_order, return_request, etc.). Every merchant gets these.
- **Merchant intents** — domain-specific to one merchant (blind_box_complaint for POP MART). Structured data, not freeform.

Procedures (AOPs) **reference** intents from the registry via `trigger_intent`. Procedures don't define intents — intents exist independently.

| Scope | Intent | Description | Typical actions |
|---|---|---|---|
| System | `cancel_order` | Customer wants to cancel an existing order | lookup_order, cancel_order |
| System | `return_request` | Customer wants to return an item or get a refund | lookup_order, process_refund, create_voucher |
| System | `order_tracking` | Customer wants to know delivery status | lookup_order, get_order_shipping |
| System | `product_inquiry` | Customer asking about a product | search_knowledge, search_products, get_product_price |
| System | `complaint` | Customer has a general complaint | search_knowledge, create_ticket, escalate_to_human |
| System | `promo_inquiry` | Customer asking about promotions | check_promotion |
| System | `general_inquiry` | General question or greeting | search_knowledge |
| Merchant | `blind_box_complaint` | Customer upset about duplicate blind box figures | search_knowledge |

**Who classifies the intent?** The LLM — not keyword matching. See section 6.

**What if no intent matches?** The AI runs without a procedure, picking actions from the available tools guided by action category thinking. No fabricated intent is generated.

**What if multiple intents match?** The classifier returns ONE intent (the primary). Secondary intents are handled in follow-up turns.

---

## 3. Callers — who invokes actions

| Caller | Module | Interface |
|---|---|---|
| CS AI Agent | CS | AgentKit `createTool()` — native tool_use blocks |
| CS Human Agent | CS | Admin UI buttons/palette |
| CS Rules Engine | CS | Workflow nodes (domain='cs') |
| CS Voice Agent | CS | Graph executor + LLM |
| AMP Rule Engine | Loyalty | Workflow nodes (domain='loyalty') |
| AMP AI Agent | Loyalty | MCP tools via `crm-loyalty-actions` |
| Admin | Shared | Direct RPC / Admin UI |
| External Partner | Shared | MCP tools with API key |

**MCP tools are a generated interface format**, not a separate concept. Actions and macros both become MCP tools at runtime. The generation chain:

```
action_registry + macro_registry → caller config (action_caller_config)
  → tool definitions (generated at runtime by service layer)
```

---

## 4. Rules System — three levels

The word "rules" replaces "guardrails" — it covers both upstream guidance (what to do) and downstream enforcement (what to block).

Each level can only narrow, never widen.

| Level | Question | Where it lives | Who controls |
|---|---|---|---|
| **1 — System rules** | "What universal behavior does this action require?" | `action_category.rules_prompt` + `action_category.rules_code` + `action_registry.rules_code` | Platform engineers |
| **2 — Caller rules** | "What is THIS caller allowed?" | `action_caller_config.rules_code` + `cs_merchant_guardrails` + `cs_procedures` | CX team per merchant/agent |
| **3 — Runtime rules** | "Even if config says yes, should the system block?" | Computed from logs, balances, rate limits | System (code) |

**Flow:** Level 1 → 2 → 3. The dispatcher enforces none of these — the service layer enforces before dispatching.

### Complete rules reference

Every rule source in the system — where it lives, how it's consumed, and what happens when it fails.

#### Level 1 — System rules (platform engineers, universal)

| Rule Source | Table / Field | Scope | Type | Injected Where | Purpose | On Failure | Example |
|---|---|---|---|---|---|---|---|
| Category thinking | `action_category.rules_prompt` | Per category | `rules_prompt` | System prompt at conversation start | Teach AI how to think before acting | Can't fail — guidance. Code enforcement catches what AI ignores. | `"Lookup state → verify identity → present impact → get confirmation → execute"` |
| Category enforcement | `action_category.rules_code` | Per category | `rules_code` | Handler checks before execution | Universal safety net — hard blocks | `{ blocked, message }` — AI reads message, adapts, retries | `{ requires_confirmation: true, requires_lookup_first: true }` |
| Action-specific enforcement | `action_registry.rules_code` | Per action | `rules_code` | Merged with category rules, same handler | Extra hard blocks for one action | `{ blocked, message }` — AI adapts and retries | `process_refund` adds `{ requires_amount_validation: true }` on top of destructive defaults |
| Param schema | `action_registry.applicable_variables` | Per action | `rules_code` | Startup → tool params. Execution → validates | Define what inputs an action accepts | AgentKit rejects before handler; LLM retries | `{ order_number: "string", platform: ["bigcommerce","shopee"] }` |

#### Level 2 — Caller rules (CX team, per merchant)

| Rule Source | Table / Field | Scope | Type | Injected Where | Purpose | On Failure | Example |
|---|---|---|---|---|---|---|---|
| Action rules | `action_caller_config.rules_code` | Merchant + action | `rules_code` | Handler checks after Level 1 passes | Business limits for a specific action for this merchant | `{ blocked, message }` — AI escalates | Merchant X's `cancel_order`: `{ blocked_statuses: ["shipped","delivered"] }` |
| Action variable overrides | `action_caller_config.variable_config` | Merchant + action | `rules_code` | Startup → narrows tool options | Hide irrelevant options for a specific action | Silent — invalid options never presented to AI | Merchant X's `cancel_order`: `{ platform: { allowed: ["bigcommerce"] } }` |
| Procedure steps | `cs_procedures.raw_content` | Merchant + intent | `rules_prompt` | Prompt when intent matches merchant AOP | Conversation flow for handling a specific intent | Can't fail — guidance. AI follows steps. | Merchant X's `cancel_order` AOP: "Ask order number → ask platform → lookup → if shipped, explain can't cancel" |
| Behavioral rules | `cs_merchant_guardrails` | Merchant (all conversations) | `rules` | System prompt + keyword check in evaluate-rules | What the AI must never say or do — every response | LLM self-censors. Code auto-tags. Supervisor flags violations. | `"Never discuss competitors"`, `"If legal threat, escalate immediately"` |
| Brand voice | `cs_merchant_config` | Merchant (all conversations) | `rules_prompt` | System prompt | How the AI speaks — every response | Reviewed post-conversation via QA | `"Formal Thai, end with ค่ะ/ครับ"` |
| Intent description | `intent_registry.description` | Per intent (system or merchant) | `rules_prompt` | Classifier LLM as multiple-choice | Help classifier pick the right intent | Low confidence → AI asks clarifying question | `"Customer wants to cancel an existing order"` |
| Variable extractors | `intent_registry.variable_extractors` | Per intent | `rules_code` | Code runs against message before LLM | Pull variable values from message without LLM | No match → LLM asks customer | `order_number: \b(PM-?\d{4,8})\b` |
| Connected platforms | `merchant_credentials` | Merchant (all conversations) | `rules_code` | Prompt as platform options | Tell AI which platforms merchant uses | Empty → AI can't call platform tools, escalates | `["bigcommerce", "shopee"]` |

**Scope distinction:** Action rules and variable overrides are narrow — they apply to one action for one merchant ("this merchant's cancel_order has these limits"). Behavioral rules, brand voice, and connected platforms are broad — they apply to every conversation for that merchant regardless of which action is running.

#### Level 3 — Runtime rules (technical, computed by system)

Standard technical safeguards computed at execution time. Not configured — the system handles these automatically:
- **Idempotency** — event log check prevents the same destructive action executing twice
- **Rate limiting** — execution count check protects platform APIs from excessive calls
- **Platform health** — cron-updated health status avoids calling APIs that are down

All return `{ blocked: true, message }` if triggered. The AI reads the message, tells the customer, and either retries later or escalates to a human agent.

### How `rules_code` verification works — rule_type_registry

Rule keys like `requires_confirmation` and `max_amount` are not hardcoded in the handler. They come from a central **rule_type_registry** that defines what rule keys exist, what values they accept, and how to verify them. The handler, the admin UI, and the rule-creation functions all read from this single source of truth.

```
rule_type_registry  ──read by──▶  Admin UI (shows available rule keys + value schemas)
                    ──read by──▶  Rule creation function (validates JSON before saving)
                    ──read by──▶  Handler/verifier (knows how to check each key at runtime)
```

**Seed data:**

| rule_key | pattern | value_schema | verify_against | verify_field | verify_operator | applicable_levels | error_template |
|---|---|---|---|---|---|---|---|
| `requires_confirmation` | boolean_flag | `boolean` | param | `customer_confirmed` | `equals` | [category, action] | "Customer confirmation required" |
| `requires_lookup_first` | boolean_flag | `boolean` | prior_actions | category='read', same entity | `exists` | [category] | "Must lookup {entity} before modifying" |
| `requires_amount_validation` | boolean_flag | `boolean` | param | `amount` | `exists` | [action] | "Amount is required for this action" |
| `max_amount` | threshold | `number` | param | `amount` | `lte` | [caller] | "Amount {value} exceeds limit ({threshold})" |
| `blocked_statuses` | blocklist | `string[]` | context | `entity_status` | `not_in` | [caller] | "Cannot perform on {entity} with status: {status}" |
| `allowed_platforms` | allowlist | `string[]` | param | `platform` | `in` | [caller] | "Platform {value} not available for this merchant" |

**Rule patterns:** Each rule key follows one of four patterns. The handler only needs to know these patterns — not every individual rule key.

| Pattern | Key shape | Value shape | What the handler does | Example |
|---|---|---|---|---|
| `boolean_flag` | `requires_X` | `true`/`false` | Check if a precondition was met | `requires_confirmation: true` → check `params.customer_confirmed` |
| `threshold` | `max_X` / `min_X` | `number` | Compare action param against the limit | `max_amount: 5000` → check `params.amount <= 5000` |
| `blocklist` | `blocked_X` | `string[]` | Check entity state is NOT in the forbidden list | `blocked_statuses: ["shipped"]` → check `context.status not in list` |
| `allowlist` | `allowed_X` | `string[]` | Check param value IS in the permitted list | `allowed_platforms: ["bigcommerce"]` → check `params.platform in list` |

**Adding a new rule:**
- If the pattern already exists (e.g., a new threshold rule) → insert a row in `rule_type_registry`. No code change.
- If a genuinely new pattern is needed → add the operator to the handler + insert the row. Rare — most rules fit the four patterns above.

### Two checkpoints — same `rule_type_registry` source of truth

| Checkpoint | Function | When | What it does |
|---|---|---|---|
| **Save-time** (upstream) | `fn_validate_rules_code(p_rules_code, p_level)` | Admin creates/edits `rules_code` via BFF | Validates every key in JSON: exists in registry? value matches `value_schema`? key valid at `p_level` (via `applicable_levels`)? Unknown keys → rejected. |
| **Runtime** (downstream) | `fn_verify_action_rules` (DB) / `rule-verifier.ts` (Render) | Tool execution — before dispatch | Merges `rules_code` from category + action + caller (each level can only narrow). Verifies each key against params/context using the 4 patterns. Blocked → `{blocked, rule_key, message}`. |

Save-time ensures only valid rules can be stored. Runtime ensures valid rules are actually enforced. Both read the same `rule_type_registry` rows — one source of truth for what keys exist, what values they accept, and how to check them.

### Enforcement order

| Step | What's Checked | Level | If Blocked |
|---|---|---|---|
| 1 | Param validation (`applicable_variables` schema) | 1 — System | LLM retries with correct params |
| 2 | Category rules (`requires_confirmation`, `requires_lookup_first`) | 1 — System | AI asks customer for confirmation / does lookup first |
| 3 | Action-specific rules (`requires_amount_validation`) | 1 — System | AI collects missing info, retries |
| 4 | Action rules (`max_amount`, `blocked_statuses`) | 2 — Caller | AI tells customer, escalates to supervisor |
| 5 | Technical runtime checks (idempotency, rate limit, health) | 3 — Runtime | AI tells customer, retries later or escalates |
| 6 | **DISPATCH** → adapter → platform API | — | — |

Each level can only narrow. No level can override a restriction set above it.

---

## 5. Five-Layer Execution Architecture

```
┌─────────────────────────────────────────────────────────────┐
│ LAYER 1: CALLERS                                             │
│  CS AI    AMP AI    CS Human    AMP Rules    Admin    Partner│
└──────────────────────────┬──────────────────────────────────┘
                           ▼
┌─────────────────────────────────────────────────────────────┐
│ LAYER 2: INTERFACE (generated from registries)               │
│  createTool()    MCP tools    UI palette    Workflow nodes   │
│  Actions + macros both exposed as tools at the same level    │
└──────────────────────────┬──────────────────────────────────┘
                           ▼
┌─────────────────────────────────────────────────────────────┐
│ LAYER 3: RULES ENFORCEMENT                                   │
│  System rules (from action_category + action_registry)       │
│  Caller rules (from action_caller_config)                    │
│  Runtime checks (budget, cooldown, rate limit, balance)      │
│  Returns: { allowed: true } or { blocked: true, reason }     │
└──────────────────────────┬──────────────────────────────────┘
                           ▼
┌─────────────────────────────────────────────────────────────┐
│ LAYER 4: DISPATCHER — fn_execute_action                      │
│  Universal. Routes action to domain handler.                 │
│  For macros: fn_execute_macro loops fn_execute_action.        │
└──────────────────────────┬──────────────────────────────────┘
                           ▼
┌─────────────────────────────────────────────────────────────┐
│ LAYER 5: DOMAIN HANDLERS                                     │
│  Loyalty (wallet, tags, personas, earn factors, audiences)   │
│  CS (conversations, tickets, platform adapters, knowledge)   │
│  Content (resources, templates)                              │
│  System (API calls, notifications, webhooks)                 │
└─────────────────────────────────────────────────────────────┘
```

---

## 6. Intent Classification

Intent classification determines what the customer wants. This drives which procedure loads, which actions are suggested, and how the AI reasons.

### Classification method: fast LLM (both voice and chat)

Both voice and chat use LLM classification. Keyword matching was rejected — it doesn't understand context, negation, or compound sentences. The fast LLM (Haiku/mini) call adds ~300ms but provides accurate, contextual classification.

```
Fast LLM receives:

  "Classify this message into one of these intents, or null:

   System intents:
   - cancel_order: Customer wants to cancel an existing order
   - return_request: Customer wants to return or get a refund
   - order_tracking: Customer wants to know where their order is
   ...

   Merchant intents:
   - blind_box_complaint: Customer upset about duplicate blind box figures

   Message: 'I'm not looking for a refund, just want to track my order'
   
   Return: { intent, confidence }"

  → { intent: "order_tracking", confidence: 0.95 }
```

**Confidence thresholds:**
- `> 0.8` — proceed with this intent
- `0.5 - 0.8` — proceed but AI should verify with customer
- `< 0.5` — no match, AI asks clarifying question

**What the classifier looks at:**
- All system intents (from `intent_registry WHERE merchant_id IS NULL`)
- This merchant's custom intents (from `intent_registry WHERE merchant_id = :mid`)
- Each intent's `description` and `example_messages`

**After classification:**
1. Intent matched → look up merchant's AOP for this intent
2. AOP found → load procedure, AI follows it
3. No AOP → use intent's `typical_actions` + action category thinking
4. No intent matched → AI runs freeform with available tools

### Variable extraction (separate from intent classification)

Variable extraction runs in code (regex, no LLM) to pull variable values from the message:
- Order numbers: `\b(PM-?\d{4,8}|\d{5,8})\b`
- Platform names: keyword match for "shopee", "bigcommerce", "ช้อปปี้", etc.
- Product names: keyword match from merchant catalog

This is fast (0ms) and runs alongside or before intent classification. The extracted variables feed into the AI context regardless of which intent matched.

### Future: faster classification methods

The ~300ms LLM call may be too slow for voice as latency requirements tighten. Future options:

| Method | Latency | Accuracy | How it works |
|---|---|---|---|
| Fast LLM (current) | ~300ms | High — understands context and negation | API call to Haiku/mini |
| Pre-computed embeddings | ~100ms | Good — semantic similarity | Embed all intent examples once, compare at runtime using cosine similarity (pgvector). Doesn't handle negation well. |
| Local model | ~10-50ms | Good for classification | Small model running on same server, no network hop. Less smart but fast. |

The intent_registry design supports all three methods — descriptions and example_messages can be used by LLM, embedded for similarity search, or used as training data for a local model.

---

## 7. Upstream AI Guidance — how the prompt is built

The system prompt is short and general (~15 lines). Domain-specific thinking comes from registries at runtime.

```
STATIC (system-prompt.ts):
  "You are a CS agent. Use tools via function calling.
   Follow the active procedure if loaded.
   Don't fabricate data — only state facts from tool results.
   When a tool returns blocked, explain to the customer and follow the guidance.
   Call tools FIRST, then respond with JSON after results."

DYNAMIC (built at runtime from registries):

  From action_category table (rules_prompt):
    "READ actions: call directly, present results."
    "DESTRUCTIVE actions: lookup state → verify → confirm → execute."
    "CREATIVE actions: collect info → summarize → confirm → execute."
    (Only categories relevant to this merchant's enabled actions are included)

  From intent_registry (if no merchant AOP for detected intent):
    Default procedure for the intent

  From merchant config:
    Brand voice, language, verification requirements

  From merchant guardrails:
    Topic boundaries, forbidden phrases, escalation triggers

  From merchant_credentials:
    Connected platforms list

  From cs_procedures (if merchant AOP matched):
    The procedure's raw_content
```

---

## 8. CS AI Message Pipeline — Target Architecture

### Infrastructure (verified from code)

| Component | Runs on | Code |
|---|---|---|
| Webhook receivers | Supabase Edge Functions | `webhook-line`, `webhook-twilio-sms`, `webhook-shopee`, `webhook-elevenlabs`, `webhook-twilio-voice` |
| Pipeline orchestrator | Supabase Edge Function + Inngest | `inngest-cs-serve` (event: `cs/message.received`) |
| AI agent | Render (Docker) | `cs-ai-service` (event: `cs/agent.decide` via `/api/inngest`) |
| Memory extraction | Render (Docker) | `cs-ai-service` (event: `cs/agent.extract-memory`) |
| Message delivery | Render | `messaging-service` |
| MCP tool server | Render (Docker) | `cs-ai-service` (`/mcp` endpoint) |
| Voice LLM | Render (Docker) | `cs-ai-service` (`/api/cs-voice-turn`) |

### Pipeline steps

```
Customer sends message via channel (LINE / web / SMS / voice)
│
├─ WEBHOOK (Supabase Edge Function: webhook-line / webhook-twilio-sms / etc.)
│    → resolve or create customer + conversation
│    → save to cs_messages
│    → inngest.send("cs/message.received")
│
╔══ INNGEST PIPELINE (inngest-cs-serve on Supabase) ══════════════════════
║
║ STEP 1: "auto-resolve" — try to resolve without AI (Supabase, parallel)
║    Three DB calls run simultaneously (Promise.all):
║    ├─ cs_fn_load_conversation_context → basic context
║    │    (customer profile, convo history, memory, active ticket)
║    ├─ cs_fn_match_custom_answer → FAQ/keyword match
║    └─ cs_fn_evaluate_rules → AMP workflow engine (domain='cs')
║         (auto-tag, auto-prioritize, auto-reply, route to human)
║
║    Check results in priority order:
║    ├─ Custom answer matched? → save + deliver → DONE (skip AI)
║    ├─ Rules auto-reply?      → save + deliver → DONE (skip AI)
║    └─ Neither?               → continue to Step 2
║
║ STEP 2: "ai-prep" — load AI-specific data (Supabase, parallel)
║    Only runs if Step 1 didn't resolve. Context from Step 1 is reused.
║    ├─ cs_fn_load_merchant_ai_config → brand voice, guardrails,
║    │    category thinking, connected platforms
║    ├─ cs_fn_search_knowledge → vector search on message
║    ├─ cs_fn_load_available_resources → templates for delivery
║    └─ cs_fn_load_action_config → action_registry +
║         action_caller_config + rule_type_registry
║
║ STEP 3: "understand" — classify + prepare tools (Render, cs-ai-service)
║    ① Variable extraction (regex on message)
║       → order_number, platform
║    ② Intent classification (fast LLM)
║       → cancel_order (confidence: 0.95)
║    ③ Tool generation from action_registry + action_caller_config
║       → filtered tools with variable overrides for this merchant
║
║ STEP 4: AOP matching (Render)
║    Intent matched → load merchant's procedure for this intent
║    No AOP? → AI uses category thinking + typical_actions
║
║ STEP 5: "agent-decide" (Render, cs-ai-service, AgentKit)
║    Prompt built from: AOP + rules(prompt) + context + knowledge
║                       + variables + available resources
║    Tools: generated from registries (not hardcoded)
║
║    AgentKit loop:
║    ├─ LLM thinks (follows AOP steps + respects rules)
║    │    ├── call tool → TOOL HANDLER:
║    │    │    1. rules_code check (rule_type_registry verifier)
║    │    │       ① param schema ② category rules ③ action rules
║    │    │       ④ caller rules ⑤ runtime checks
║    │    │    2. credential resolver (merchant_credentials)
║    │    │    3. platform adapter (BigCommerce/Shopee/Shopify/LINE)
║    │    │    4. result back to LLM
║    │    ├── plain text reply → to channel
║    │    └── escalate → hand to human
║    └─ (loops until done)
║
║    Returns: { reply, actions_taken, next_step, resolved, procedure_state }
║
║ STEP 6: "save-deliver" (Supabase)
║    Save reply to cs_messages
║    Deliver via messaging-service (Render) to channel
║    Save procedure_state
║    If resolved → cs_fn_resolve_conversation
║
║ STEP 7: "post-processing" (separate Inngest function)
║    Triggered by cs/conversation.resolved
║    → memory extraction via cs-ai-service on Render
║    → CSAT survey
║
╚═════════════════════════════════════════════════════════════════════════
```

### Current vs target

| Step | Current state | Target state |
|---|---|---|
| Step 1 auto-resolve | ✅ Live — `prepare-context` with 3 parallel calls | Split: basic context only (no AI data loaded here) |
| Step 2 ai-prep | ❌ Doesn't exist — AI data loaded in Step 1 | New step: load rules, knowledge, resources, action config only if needed |
| Step 3 understand | ❌ Doesn't exist — no intent classifier or variable extractor | New step: variable extraction + fast LLM classifier + tool generation |
| Step 4 AOP | ⚠️ Partial — procedure loaded inside context, not based on classified intent | Load AOP based on classified intent from Step 3 |
| Step 5 agent-decide | ✅ Live — fires `cs/agent.decide` to Render | Add: dynamic tool generation, rule_type_registry enforcement |
| Step 6 save-deliver | ✅ Live | No change |
| Step 7 post-processing | ✅ Live — memory extraction | No change |

---

## 9. Platform Adapter Pattern

```
Tool call: cancel_order(platform="bigcommerce", order_id="250")
  → credential resolver: merchant_credentials WHERE service_name = 'bigcommerce'
  → adapter router: adapters["bigcommerce"]
  → BigCommerce adapter: PUT /v2/orders/250 { status_id: 5 }
  → result returned to AI
```

| Platform | Auth | Cancel | Refund | Create Order | Products | Promos |
|---|---|---|---|---|---|---|
| BigCommerce | Long-lived token | ✅ PUT status_id:5 | ✅ V3 refunds | ✅ POST /v2/orders | ✅ V3 catalog | ✅ V3 promos + V2 coupons |
| Shopify | Long-lived token | ✅ POST cancel | ✅ 2-step calculate+create | ✅ POST /orders.json | ✅ REST/GraphQL | ✅ price_rules |
| Shopee | HMAC + token refresh | ✅ cancel API | ❌ marketplace | ❌ | ✅ item API | ✅ vouchers |
| TikTok | HMAC + token refresh | ✅ cancel API | ❌ marketplace | ❌ | ✅ product API | Limited |
| Lazada | HMAC + country URLs | ✅ per-item | ❌ marketplace | ❌ | ✅ product API | ✅ seller promos |
| WooCommerce | Basic auth | ✅ PUT status | ✅ refunds API | ✅ POST /orders | ✅ products API | ✅ coupons API |

---

## 10. Table Design

### Renames

| Current | Proposed | Why |
|---|---|---|
| `workflow_action_type_config` | `action_registry` | Universal, not workflow-specific |
| `cs_action_config` + `amp_agent_action` | `action_caller_config` | Unified caller config for all modules |
| `fn_execute_amp_action` | `fn_execute_action` | Universal dispatcher |

### action_registry (renamed from workflow_action_type_config)

```sql
action              text PK
domain              text            -- 'cs', 'loyalty', 'shared'
target_entity       text            -- 'order', 'product', 'wallet', ...
action_category     text FK         -- → action_category.category
rules_code          jsonb           -- action-specific code enforcement, keys must exist in rule_type_registry
applicable_variables jsonb          -- parameter schemas
applicable_rules    jsonb           -- which rule_type_registry keys caller config can override
supported_platforms text[]          -- null = platform-independent
```

### rule_type_registry

```sql
rule_key            text PK         -- 'requires_confirmation', 'max_amount', 'blocked_statuses'
pattern             text            -- 'boolean_flag', 'threshold', 'blocklist', 'allowlist'
value_schema        jsonb           -- JSON schema for the value (boolean, number, string[])
verify_against      text            -- 'param', 'context', 'prior_actions'
verify_field        text            -- 'customer_confirmed', 'amount', 'entity_status'
verify_operator     text            -- 'equals', 'lte', 'gte', 'not_in', 'in', 'exists'
error_template      text            -- "Amount {value} exceeds limit ({threshold})"
applicable_levels   text[]          -- ['category', 'action', 'caller']
description         text
```

### action_category

```sql
category            text PK         -- 'read', 'destructive', 'mutative', 'creative', 'delivery', 'internal'
rules_prompt        text            -- upstream thinking pattern (consumed by AI / LLM)
rules_code          jsonb           -- downstream enforcement flags (consumed by code), keys must exist in rule_type_registry
description         text
```

### action_caller_config (replaces cs_action_config + amp_agent_action)

```sql
id                  uuid PK
caller_type         text            -- 'merchant_cs', 'amp_agent', 'admin', 'partner'
caller_id           uuid            -- merchant_id OR agent_id OR role_id
action              text FK         -- → action_registry.action
is_enabled          boolean
variable_config     jsonb           -- defaults/overrides for params
rules_code          jsonb           -- code enforcement, keys must exist in rule_type_registry with applicable_levels containing 'caller'
sort_order          int
```

### intent_registry

```sql
intent              text
merchant_id         uuid            -- null = system intent, value = merchant-specific
description         text            -- "Customer wants to cancel an existing order" (for LLM classifier)
example_messages    text[]          -- sample messages (for LLM classifier + future embedding)
typical_actions     text[]          -- which actions this intent usually needs
variable_extractors jsonb           -- regex/keyword patterns to pre-extract variable values from messages
default_procedure   text            -- system-level default AOP (for system intents without merchant AOP)

UNIQUE (intent, COALESCE(merchant_id, '00000000-0000-0000-0000-000000000000'))
```

### entity_type

```sql
entity              text PK         -- 'order', 'product', 'customer', ...
platform_dependent  boolean
read_actions        text[]
write_actions       text[]
description         text
```

### macro_registry

```sql
id                  uuid PK
macro_name          text UNIQUE
description         text
action_sequence     jsonb           -- [{action, default_params}]
variable_definitions jsonb          -- injectable params with types
domain              text
is_active           boolean
```

---

## 11. Implementation Status (updated 2026-04-07)

### Tables

| Table | Status | Where |
|---|---|---|
| `action_registry` (renamed from `workflow_action_type_config`) | ✅ Live | Supabase — 32 actions, added: action_category, rules_code, target_entity, supported_platforms |
| `action_category` | ✅ Live | Supabase — 6 categories seeded (read, destructive, mutative, creative, delivery, internal) |
| `rule_type_registry` | ✅ Live | Supabase — 6 rule types seeded |
| `action_caller_config` | ✅ Live | Supabase — unified caller config (replaced cs_action_config + amp_agent_action, both dropped) |
| `intent_registry` | ✅ Live | Supabase — 7 system intents seeded |
| `entity_registry` | ✅ Live | Supabase — 14 entities seeded |
| `action_macro` | ✅ Updated | Supabase — merchant_id now nullable (system-level macros), domain column added, 5 system macros seeded |

### Functions

| Function | Status | Where |
|---|---|---|
| `cs_fn_load_conversation_context` | ✅ Live | Supabase — loads context + brand config + guardrails + procedure in one call |
| `cs_fn_match_custom_answer` | ✅ Live | Supabase — FAQ/keyword match |
| `cs_fn_evaluate_rules` | ✅ Live | Supabase — AMP workflow engine, domain='cs' |
| `cs_fn_search_knowledge` | ✅ Live | Supabase — vector search |
| `cs_fn_search_resources` | ✅ Live | Supabase — resource search |
| `fn_execute_amp_action` | ✅ Live | Supabase — loyalty action dispatcher (kept, called by fn_execute_action for loyalty domain) |
| `fn_execute_macro` | ✅ Live | Supabase — macro executor |
| `fn_execute_action` | ✅ Live | Supabase — universal dispatcher, routes by domain |
| `fn_verify_action_rules` | ✅ Live | Supabase — runtime rules_code enforcement using rule_type_registry patterns |
| `fn_validate_rules_code` | ✅ Live | Supabase — save-time validation of rules_code JSON |
| `fn_get_action_registry_cached` | ✅ Live | Supabase — replaces fn_get_action_type_config_cached |
| `cs_fn_load_merchant_ai_config` | ✅ Live | Supabase — load brand voice + guardrails + category thinking + platforms |
| `cs_fn_load_action_config` | ✅ Live | Supabase — load registries for dynamic tool generation |
| `cs_fn_load_available_resources` | ✅ Live | Supabase — load resources filtered by merchant + channel |
| `bff_upsert_action_caller_config` | ✅ Live | Supabase — admin CRUD with rules_code validation |
| `bff_upsert_action_category` | ✅ Live | Supabase — admin CRUD with rules_code validation |
| `bff_list_rule_types` | ✅ Live | Supabase — admin UI helper |
| `bff_upsert_intent` | ✅ Live | Supabase — intent CRUD |
| `bff_list_intents` | ✅ Live | Supabase — list system + merchant intents |

### Services

| Component | Status | Where |
|---|---|---|
| Webhook receivers | ✅ Live | Supabase Edge Functions: `webhook-line`, `webhook-twilio-sms`, `webhook-shopee` |
| Pipeline orchestrator (`inngest-cs-serve`) | ✅ Live | Supabase Edge Function — 5 Inngest functions |
| AI agent (`cs-ai-service`) | ✅ Live | Render — AgentKit, MCP server |
| Voice agent | ✅ Live | Render — `cs-ai-service` `/api/cs-voice-turn` |
| Messaging service | ✅ Live | Render — `messaging-service` |
| Platform adapters | ⚠️ BigCommerce only | cs-ai-service — Shopify/Shopee/TikTok/Lazada pending |
| Dynamic tool generation | ✅ Code ready | `src/tool-generator.ts` — generates tools from registries at runtime |
| Dynamic prompt builder | ✅ Code ready | `src/system-prompt.ts` — static core + `buildDynamicPrompt()` |
| Intent LLM classifier | ✅ Code ready | `src/intent-classifier.ts` — fast LLM (Haiku) reading intent_registry |
| Variable extractors | ✅ Code ready | `src/variable-extractor.ts` — generalized regex/keyword extraction |
| Generic rules_code verifier | ✅ Code ready | `src/rule-verifier.ts` — 4-pattern verifier from rule_type_registry |

### Remaining work

| Item | What's needed |
|---|---|
| Wire `agent.ts` to use `tool-generator.ts` | Replace 14 hardcoded tools with `generateTools()` call at conversation start |
| Wire `index.ts` pipeline to use `intent-classifier.ts` + `variable-extractor.ts` | Add Step 3 (understand) before agent.decide |
| Split `inngest-cs-serve` pipeline | Step 1 (auto-resolve) vs Step 2 (AI prep) using new load functions |
| Platform adapters | Shopify, Shopee, TikTok, Lazada, WooCommerce — each needs API doc study |
