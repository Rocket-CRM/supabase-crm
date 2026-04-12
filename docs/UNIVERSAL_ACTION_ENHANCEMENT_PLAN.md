# Universal Action System — Enhancement Plan

> **Status:** Comprehensive gap analysis complete. Ready for session-by-session execution.
> **Pre-launch:** CS and AMP features have NOT launched — no data migration needed. Hard-cut old tables.

---

## Source Context

| Doc | What it covers |
|---|---|
| `docs/universal_action_system.md` | Architecture: entities, actions, categories, rules (3 types × 3 levels), macros, intents, callers, pipeline |
| `.cursor/plans/cs_ai_feature_spec_45a47ba9.plan.md` | Full CS AI feature spec: channels, inbox, SLA, rules engine, AI agent, actions, schema, pipeline |
| GitHub: `Rocket-CRM/cs-ai-service` (main) | Live Render service: 8 source files + 7 voice files |

---

## A. Existing Inventory — What's Live

### Supabase Tables (22 relevant)

| Group | Tables | Status |
|---|---|---|
| CS Core (19) | `cs_contacts`, `cs_platform_identities`, `cs_customer_memory`, `cs_conversations`, `cs_messages`, `cs_conversation_events`, `cs_tickets`, `cs_ticket_events`, `cs_sla_policies`, `cs_business_hours`, `cs_knowledge_sources`, `cs_knowledge_articles`, `cs_knowledge_embeddings`, `cs_procedures`, `cs_voice_calls`, `cs_phone_numbers`, `cs_merchant_config`, `cs_merchant_guardrails`, `cs_action_config` | All live, schemas match plan |
| Shared Action (4) | `workflow_action_type_config` (29 actions), `action_macro`, `action_macro_context`, `amp_agent_action` | Live, pre-universal naming |
| Content (2) | `resource_content`, `resource_content_category` | Live |

**Shared table modifications already done:**
- `admin_users` — `cs_online_status`, `cs_max_concurrent`, `cs_skills` ✅
- `admin_teams` — `domain`, `business_hours_id` ✅
- `merchant_credentials` — `scope` (text[]), `channel_config` (jsonb) ✅

### Supabase Functions (60+)

**CS BFF (42):** Full CRUD for conversations, tickets, contacts, knowledge, procedures, guardrails, channels, voice, resources.

**CS Internal (22):** `cs_fn_load_conversation_context`, `cs_fn_evaluate_rules`, `cs_fn_search_knowledge`, `cs_fn_match_resource`, `cs_fn_compile_procedure`, `cs_fn_resolve_contact`, `cs_fn_insert_message`, `cs_fn_create_ticket`, `cs_fn_auto_assign`, `cs_fn_assign_sla`, etc.

**Shared Action (7):** `fn_execute_amp_action`, `fn_execute_macro`, `fn_get_action_type_config_cached`, `fn_validate_agent_action_scope`, `fn_get_eligible_agent_actions`, `fn_check_macro_approval`, `fn_validate_macro_variables`, `fn_resolve_resource_for_delivery`.

### workflow_action_type_config — 29 Actions Seeded

| Domain | Actions |
|---|---|
| CS (18) | `lookup_order`, `cancel_order`, `process_refund`, `get_recent_orders`, `get_order_shipping`, `search_products`, `check_product_stock`, `get_product_price`, `check_promotion`, `apply_coupon`, `create_order`, `update_order`, `create_voucher`, `get_customer_profile`, `create_ticket`, `close_conversation`, `trigger_csat_survey`, `recommend_products` |
| Loyalty (11) | `award_points`, `award_tickets`, `assign_tag`, `remove_tag`, `assign_persona`, `assign_earn_factor`, `send_line_message`, `send_sms`, `submit_form`, `add_to_audience`, `remove_from_audience` |

**Missing CS actions (not registered):** `search_knowledge`, `send_message`, `escalate_to_human`

### Render: cs-ai-service (GitHub: `Rocket-CRM/cs-ai-service`)

| File | Size | What it does |
|---|---|---|
| `src/agent.ts` | 14.5KB | **14 hardcoded `createTool()` calls**, csNetwork (AgentKit), memoryNetwork |
| `src/system-prompt.ts` | 7.7KB | **Hardcoded system prompt** (~120 lines), memory extraction prompt |
| `src/index.ts` | 11KB | Express server, 2 Inngest functions (`cs/agent.decide`, `cs/agent.extract-memory`), `/api/cs-voice-turn`, `/mcp` endpoint |
| `src/mcp-server.ts` | 16KB | MCP tool server (human-agent tools) |
| `src/supabase.ts` | 369B | Supabase client init |
| `src/adapters/bigcommerce.ts` | 12.8KB | **Only implemented adapter** — full: lookupOrder, cancelOrder, processRefund, etc. |
| `src/adapters/index.ts` | 854B | Registry — BigCommerce live, 5 others stub `notImplemented()` |
| `src/adapters/types.ts` | 3.3KB | PlatformAdapter interface (13 methods) |
| `src/adapters/not-implemented.ts` | 1.3KB | Stub that returns error for unimplemented platforms |
| `src/cs-voice/graph-executor.ts` | 10.9KB | Voice turn executor (deterministic AOP walker + LLM) |
| `src/cs-voice/aop-walker.ts` | 4.4KB | Step-through compiled procedure steps |
| `src/cs-voice/prompt-builder.ts` | 4.7KB | Voice-specific prompt construction |
| `src/cs-voice/prefetcher.ts` | 4KB | Deterministic data fetch from compiled_steps.data_needs |
| `src/cs-voice/action-executor.ts` | 1.9KB | Voice action dispatch |
| `src/cs-voice/entity-extractor.ts` | 796B | Regex entity extraction for voice |
| `src/cs-voice/types.ts` | 1.7KB | Voice types |

---

## B. Gap Analysis

### B1. New Tables (5)

| # | Table | Purpose | Columns |
|---|---|---|---|
| 1 | **`action_category`** | Behavioral patterns: AI guidance + code enforcement | `category` text PK, `rules_prompt` text, `rules_code` jsonb, `description` text, `created_at`, `updated_at` |
| 2 | **`rule_type_registry`** | Central vocabulary of rule keys + verification patterns | `rule_key` text PK, `pattern` text, `value_schema` jsonb, `verify_against` text, `verify_field` text, `verify_operator` text, `error_template` text, `applicable_levels` text[], `description` text |
| 3 | **`action_caller_config`** | Unified caller config (replaces `cs_action_config` + `amp_agent_action`) | `id` uuid PK, `merchant_id` uuid, `caller_type` text, `caller_id` uuid, `action` text FK→action_registry, `is_enabled` boolean, `variable_config` jsonb, `rules_code` jsonb, `sort_order` int, `created_at`, `updated_at` |
| 4 | **`intent_registry`** | System + merchant intents for LLM classifier | `intent` text, `merchant_id` uuid (NULL=system), `description` text, `example_messages` text[], `typical_actions` text[], `variable_extractors` jsonb, `default_procedure` text, UNIQUE(intent, coalesce(merchant_id,...)) |
| 5 | **`entity_type`** | Entity definitions — what things exist | `entity` text PK, `platform_dependent` boolean, `read_actions` text[], `write_actions` text[], `description` text |

### B1b. `action_macro` — Add System-Level Support (not new table)

Instead of a separate `macro_registry` table, modify the existing `action_macro`:

| Change | Current | Target |
|---|---|---|
| `merchant_id` | NOT NULL | **Nullable** — NULL = system-level template, value = merchant-specific |
| ADD column | — | `domain` text DEFAULT 'shared' |
| RLS | merchant_id = current | merchant_id = current OR merchant_id IS NULL (read system macros) |

System-level macros (merchant_id IS NULL) are platform templates. Merchant-level macros are customized versions. Same table, column distinguishes. 7 functions already reference `action_macro` — they work unchanged since they filter by merchant_id anyway, and system macros are read-only for merchants.

### B2. Table Rename + Column Additions (1)

**`workflow_action_type_config` → `action_registry`**

| Change | Detail |
|---|---|
| RENAME TABLE | `workflow_action_type_config` → `action_registry` |
| RENAME column | `action_type` → `action` |
| RENAME column | `applicable_guardrails` → `applicable_rules` |
| ADD column | `action_category` text FK → `action_category.category` |
| ADD column | `rules_code` jsonb DEFAULT '{}' |
| ADD column | `target_entity` text |
| ADD column | `supported_platforms` text[] |
| BACKFILL | Populate `action_category` + `target_entity` for all 29 rows |

### B3. Tables to Drop (after `action_caller_config` replaces them)

| Table | Replaced by | Functions to update |
|---|---|---|
| `cs_action_config` | `action_caller_config` WHERE caller_type='merchant_cs' | 3: `cs_bff_get_available_actions`, `cs_fn_compile_procedure`, `cs_fn_seed_action_config` |
| `amp_agent_action` | `action_caller_config` WHERE caller_type='amp_agent' | 6: `bff_delete_agent`, `bff_get_agent_full`, `bff_upsert_agent_with_children`, `fn_get_agent_config_cached`, `fn_get_eligible_agent_actions`, `fn_validate_agent_action_scope` |

No migration — hard-cut. Recreate data in new table.

### B4. Functions That Reference Old Table Names

**References `workflow_action_type_config` (3 functions — all must update to `action_registry`):**

| Function | What it does | Change needed |
|---|---|---|
| `fn_get_action_type_config_cached` | Reads all actions + caches in Redis | Rename to `fn_get_action_registry_cached`, read from `action_registry` with new columns |
| `cs_fn_seed_action_config` | Seeds `cs_action_config` from registry | Rewrite: seed `action_caller_config` from `action_registry` |
| `cs_fn_compile_procedure` | Resolves tools from both `cs_action_config` + `workflow_action_type_config` | Update table references + column names |

**References `cs_action_config` (3 functions):**

| Function | Change needed |
|---|---|
| `cs_bff_get_available_actions` | Read from `action_caller_config` WHERE caller_type='merchant_cs' |
| `cs_fn_compile_procedure` | Read from `action_caller_config` + `action_registry` |
| `cs_fn_seed_action_config` | Rewrite to seed `action_caller_config` |

**References `amp_agent_action` (6 functions):**

| Function | Change needed |
|---|---|
| `bff_delete_agent` | Reference `action_caller_config` for child deletion |
| `bff_get_agent_full` | Read actions from `action_caller_config` WHERE caller_type='amp_agent' |
| `bff_upsert_agent_with_children` | Write to `action_caller_config` instead |
| `fn_get_agent_config_cached` | Read from `action_caller_config` |
| `fn_get_eligible_agent_actions` | Read from `action_caller_config` |
| `fn_validate_agent_action_scope` | Read from `action_caller_config` |

### B5. Rules Column Naming Convention

Column names use suffixes to indicate **who consumes the rule**:

| Suffix | Consumed by | Data shape | Example |
|---|---|---|---|
| `rules_prompt` | LLM only | Natural language text | "Lookup state → verify → confirm → execute" |
| `rules_code` | Code only | Structured JSON flags (keys from `rule_type_registry`) | `{ requires_confirmation: true, max_amount: 5000 }` |
| `rules` (no suffix) | Both LLM + Code | Text injected into prompt AND code-level keyword enforcement | "Never discuss competitors" |

**New tables — consistent naming:**

| Table | Column | Suffix | Consumed by |
|---|---|---|---|
| `action_category` | `rules_prompt` (text) | `_prompt` | LLM only |
| `action_category` | `rules_code` (jsonb) | `_code` | Code only |
| `action_registry` | `rules_code` (jsonb) | `_code` | Code only |
| `action_caller_config` | `rules_code` (jsonb) | `_code` | Code only |

**Existing tables — predating this convention (acceptable as-is):**

| Table | Column | Effective type | Note |
|---|---|---|---|
| `cs_merchant_guardrails` | `rule_content` + `rule_config` | Both | Text goes to LLM, config goes to code |
| `cs_procedures` | `raw_content` | `rules_prompt` | Procedure content, not a "rule" column per se |
| `cs_procedures` | `guardrails` | `rules_code` | Predates convention |
| `cs_merchant_config` | `guidance_rules` | `rules_prompt` | Brand voice / tone |

### B6. New Supabase Functions Needed

| # | Function | Type | Purpose |
|---|---|---|---|
| 1 | `cs_fn_load_merchant_ai_config` | Internal | Load brand voice + guardrails + `action_category.rules_prompt` + connected platforms. Separate from `cs_fn_load_conversation_context`. |
| 2 | `cs_fn_load_action_config` | Internal | Load `action_registry` + `action_caller_config` + `rule_type_registry` for dynamic tool generation |
| 3 | `cs_fn_load_available_resources` | Internal | Load available resources filtered by merchant + channel for delivery actions |
| 4 | `fn_execute_action` | Internal | Universal dispatcher — replaces `fn_execute_amp_action`. Routes by domain to correct handler. |
| 5 | `fn_verify_action_rules` | Internal | **Runtime (downstream):** merges category + action + caller `rules_code`, verifies each key against `rule_type_registry` patterns, returns `{allowed}` or `{blocked, rule_key, message}` |
| 6 | `fn_validate_rules_code` | Internal | **Save-time (upstream):** validates a `rules_code` jsonb blob against `rule_type_registry` — rejects unknown keys, wrong value types, keys not applicable at the target level. Called by every BFF that writes `rules_code`. |
| 7 | `fn_get_action_registry_cached` | Internal | Replaces `fn_get_action_type_config_cached` — reads new columns |
| 8 | `bff_upsert_action_category` | BFF | Admin CRUD for action categories — calls `fn_validate_rules_code('category')` |
| 9 | `bff_upsert_action_caller_config` | BFF | Admin CRUD — calls `fn_validate_rules_code('caller')` |
| 10 | `bff_list_rule_types` | BFF | List available rule keys for a given level — admin UI uses to build forms/dropdowns |
| 11 | `bff_upsert_intent` | BFF | Admin CRUD for intent_registry |
| 12 | `bff_list_intents` | BFF | List system + merchant intents |

### B7. Render Service Gaps (cs-ai-service)

| # | Component | Current (from repo) | Target | Files affected |
|---|---|---|---|---|
| 1 | **Dynamic tool generation** | 14 hardcoded `createTool()` in `agent.ts` | Generate from `action_registry` + `action_caller_config` at conversation start. Each tool: name from registry, params from `applicable_variables`, handler routes through `fn_execute_action` or adapter. | `agent.ts` (rewrite) |
| 2 | **Dynamic prompt builder** | Hardcoded `CS_SYSTEM_INSTRUCTION` in `system-prompt.ts` (~120 lines) | Static core (~15 lines) + dynamic injection: `action_category.rules_prompt`, merchant config, guardrails, connected platforms. | `system-prompt.ts` (rewrite), `index.ts` (`buildCSPrompt` updated) |
| 3 | **Intent LLM classifier** | Does not exist | New module: fast LLM (Haiku/mini) reads `intent_registry` descriptions + examples. Returns `{intent, confidence}`. Both voice + chat. | New file: `src/intent-classifier.ts` |
| 4 | **Variable extractors** | `cs-voice/entity-extractor.ts` exists for voice only | Generalize for both voice + chat. Read `intent_registry.variable_extractors` for merchant-specific patterns. | `src/cs-voice/entity-extractor.ts` → extract to shared `src/variable-extractor.ts` |
| 5 | **Generic rules_code verifier** | Hardcoded `customer_confirmed` check in `cancelOrder`/`processRefund` handlers | Read `rule_type_registry` at startup, verify each rule key at execution time using 4 patterns: boolean_flag, threshold, blocklist, allowlist | New file: `src/rule-verifier.ts` |
| 6 | **Pipeline split** | `index.ts` fires `cs/agent.decide` with full context from Supabase edge function | Supabase side: split Step 1 (auto-resolve) from Step 2 (AI prep). Service side: add Step 3 (understand: classify + extract + generate tools) before Step 5 (agent decide). | `index.ts` (add step), Supabase edge function `inngest-cs-serve` (split steps) |
| 7 | **Platform adapters** | BigCommerce only. Shopify/Shopee/TikTok/Lazada/WooCommerce = `notImplemented()` stubs | Implement each adapter against `PlatformAdapter` interface (13 methods each) | New files: `src/adapters/shopify.ts`, `src/adapters/shopee.ts`, etc. |
| 8 | **Missing CS action tools** | `search_knowledge` hardcoded in agent.ts, `escalate_to_human` hardcoded, `send_message` not a tool | Register in `action_registry` + generate dynamically with the rest | `action_registry` seed + tool generation |

### B8. Missing Action Registrations (3)

Add to `action_registry` (will be registered during Session 1 seed):

| Action | Entity | Category | Domain |
|---|---|---|---|
| `search_knowledge` | knowledge | read | cs |
| `send_message` | conversation | delivery | cs |
| `escalate_to_human` | conversation | internal | cs |

---

## C. Build Order (8 Sessions)

### Session 1: DB Foundation — Tables + Seeds + Validation

**Supabase MCP:**
1. CREATE `action_category` table + seed 6 rows (read, destructive, mutative, creative, delivery, internal) with `rules_prompt` and `rules_code`
2. CREATE `rule_type_registry` table + seed 6 rows (requires_confirmation, requires_lookup_first, requires_amount_validation, max_amount, blocked_statuses, allowed_platforms)
3. CREATE `entity_type` table + seed 14 rows
4. CREATE `intent_registry` table + seed 7 system intents
5. RENAME `workflow_action_type_config` → `action_registry`, rename columns, add new columns, backfill all 29 rows with action_category + target_entity
6. ADD 3 missing CS actions: search_knowledge, send_message, escalate_to_human
7. ALTER `action_macro` — make merchant_id nullable, add domain column
8. CREATE `fn_validate_rules_code(p_rules_code jsonb, p_level text)` — shared save-time validator
9. CREATE `bff_list_rule_types(p_level text)` — admin UI helper

**`fn_validate_rules_code` — Save-time validator (called by all BFFs writing `rules_code`):**
```
fn_validate_rules_code(p_rules_code jsonb, p_level text) → jsonb
  p_level: 'category' | 'action' | 'caller'

  For each key in p_rules_code:
    1. Lookup key in rule_type_registry → not found? → error "Unknown rule key: X"
    2. Check p_level is in applicable_levels → not applicable? → error "Key X not valid at level Y"
    3. Check value matches value_schema → wrong type? → error "Key X expects Z, got W"
  All pass → { valid: true }
  Any fail → { valid: false, errors: [{rule_key, message}] }
```

**`bff_list_rule_types` — Admin UI form builder:**
```
bff_list_rule_types(p_level text DEFAULT NULL) → jsonb
  Returns: rule_key, pattern, value_schema, description, applicable_levels
  Filtered by: applicable_levels @> ARRAY[p_level] (or all if NULL)
```

**Update 3 functions that reference old table name:**
- `fn_get_action_type_config_cached` → `fn_get_action_registry_cached`
- `cs_fn_seed_action_config` (update table reference)
- `cs_fn_compile_procedure` (update table reference)

### Session 2: Unified Caller Config

**Supabase MCP:**
1. CREATE `action_caller_config` table
2. Rewrite `cs_fn_seed_action_config` → seed `action_caller_config` from `action_registry`
3. Rewrite `cs_bff_get_available_actions` → read from `action_caller_config`
4. Rewrite `cs_fn_compile_procedure` → read from `action_caller_config` + `action_registry`
5. Update 6 AMP agent functions to read/write `action_caller_config`:
   - `bff_delete_agent`, `bff_get_agent_full`, `bff_upsert_agent_with_children`
   - `fn_get_agent_config_cached`, `fn_get_eligible_agent_actions`, `fn_validate_agent_action_scope`
6. New BFF CRUD:
   - `bff_upsert_action_caller_config` — calls `fn_validate_rules_code(p_rules_code, 'caller')` before saving
   - `bff_upsert_action_category` — calls `fn_validate_rules_code(p_rules_code, 'category')` before saving
   - `bff_upsert_intent`, `bff_list_intents`
7. DROP `cs_action_config` and `amp_agent_action`
8. Seed system macros (merchant_id=NULL) in `action_macro`: full_cancel_and_refund, goodwill_gesture, etc.

### Session 3: AI Pipeline Functions

**Supabase MCP:**
1. Create `cs_fn_load_merchant_ai_config` — returns brand voice, guardrails, action_category.rules_prompt for categories in use, connected platforms
2. Create `cs_fn_load_action_config` — returns action_registry + action_caller_config + rule_type_registry for dynamic tool generation
3. Create `cs_fn_load_available_resources` — returns resources filtered by merchant + channel

### Session 4: Dynamic Prompt Builder (Render)

**GitHub: `Rocket-CRM/cs-ai-service`**
1. Rewrite `src/system-prompt.ts` — static core (~15 lines) + `buildDynamicPrompt(aiConfig)` function
2. Update `src/index.ts` `buildCSPrompt()` — inject `action_category.rules_prompt`, merchant config, guardrails dynamically from Step 2 AI prep data
3. Update `src/cs-voice/prompt-builder.ts` — same dynamic injection

### Session 5: Intent Classifier + Variable Extractors (Render)

**GitHub: `Rocket-CRM/cs-ai-service`**
1. New `src/intent-classifier.ts` — fast LLM call, reads intent_registry descriptions + examples, returns {intent, confidence}
2. New `src/variable-extractor.ts` — generalized from `cs-voice/entity-extractor.ts`, reads `intent_registry.variable_extractors`
3. Integrate into `index.ts` — add Step 3 ("understand") before agent.decide
4. Update `src/cs-voice/graph-executor.ts` — use shared intent classifier + variable extractor

### Session 6: Dynamic Tool Generation (Render)

**GitHub: `Rocket-CRM/cs-ai-service`**
1. New `src/tool-generator.ts` — reads action_registry + action_caller_config → generates `createTool()` definitions at runtime
2. Rewrite `src/agent.ts` — remove 14 hardcoded tools, use generated tools
3. Tool handler routes through: rule verifier → credential resolver → platform adapter
4. Update MCP server (`src/mcp-server.ts`) to expose dynamically generated tools

### Session 7: Runtime Rule Verifier + Universal Dispatcher

**Render:** New `src/rule-verifier.ts` — runtime (downstream) enforcement:
```
At startup: load rule_type_registry into memory (pattern, verify_against, verify_field, verify_operator)
At tool execution:
  1. Merge rules_code from: action_category + action_registry + action_caller_config (each level can only narrow)
  2. For each rule_key in merged rules_code:
     - Lookup pattern in rule_type_registry
     - boolean_flag: check param[verify_field] equals value
     - threshold: check param[verify_field] <= (or >=) value
     - blocklist: check context[verify_field] NOT IN value[]
     - allowlist: check param[verify_field] IN value[]
  3. Any fail → { blocked: true, rule_key, message from error_template }
  4. All pass → { allowed: true } → dispatch to adapter
```

**Supabase MCP:**
1. Create `fn_execute_action` — universal dispatcher. CASE on domain: 'loyalty' → existing award/tag/persona logic from fn_execute_amp_action; 'cs' → route to Render adapter or internal DB operation; 'shared' → common operations
2. Create `fn_verify_action_rules` — DB-side runtime verification (same logic as Render verifier, for direct RPC callers that bypass the service layer)
3. Update `fn_execute_macro` to call `fn_execute_action` instead of `fn_execute_amp_action`
4. Deprecate `fn_execute_amp_action` (or alias)

**Two verification points, same `rule_type_registry` source of truth:**

| Checkpoint | Where | When | Who calls |
|---|---|---|---|
| Save-time (`fn_validate_rules_code`) | Supabase | Admin creates/edits rules_code | BFF upsert functions |
| Runtime (`fn_verify_action_rules` / `rule-verifier.ts`) | Supabase + Render | Tool execution | Dispatcher / tool handler |

### Session 8+: Platform Adapters (Render)

Each platform needs API doc study, HMAC auth implementation, adapter code:

| Platform | Auth Pattern | Priority |
|---|---|---|
| Shopify | Long-lived token | High (many merchants) |
| Shopee | HMAC + token refresh | High (SEA market) |
| WooCommerce | Basic auth | Medium |
| TikTok Shop | HMAC + token refresh | Medium |
| Lazada | HMAC + country URLs | Lower |

Each adapter implements the `PlatformAdapter` interface (13 methods):
`lookupOrder`, `getRecentOrders`, `getOrderShipping`, `searchProducts`, `checkProductStock`, `getProductPrice`, `checkPromotion`, `cancelOrder`, `processRefund`, `createOrder`, `updateOrder`, `applyCoupon`, `createVoucher`

---

## D. Documentation Updates (per 06-update-docs.mdc)

After each session, update:
- `requirements/INDEX_FUNCTION.md` — add new functions with type + purpose
- `requirements/INDEX_DOMAIN.md` — add Action System as shared domain, update CS sections
- `docs/universal_action_system.md` — update Implementation Status section
- Domain requirement docs as tables/functions are created

---

## E. File Inventory — cs-ai-service Repo

```
Rocket-CRM/cs-ai-service (main)
├── .env.example
├── .gitignore
├── Dockerfile
├── README.md
├── package.json
├── tsconfig.json
└── src/
    ├── index.ts              ← Express + Inngest (cs/agent.decide, cs/agent.extract-memory) + /mcp + /api/cs-voice-turn
    ├── agent.ts              ← 14 hardcoded createTool(), csNetwork, memoryNetwork
    ├── system-prompt.ts      ← Hardcoded CS_SYSTEM_INSTRUCTION + MEMORY_EXTRACTION_INSTRUCTION
    ├── mcp-server.ts         ← MCP tool server for human agent
    ├── supabase.ts           ← Supabase client
    ├── adapters/
    │   ├── index.ts          ← Registry: bigcommerce live, 5 stubs
    │   ├── types.ts          ← PlatformAdapter interface (13 methods)
    │   ├── bigcommerce.ts    ← Full implementation (12.8KB)
    │   └── not-implemented.ts ← Stub for unimplemented platforms
    └── cs-voice/
        ├── graph-executor.ts  ← Voice turn executor (10.9KB)
        ├── aop-walker.ts      ← Procedure step walker
        ├── prompt-builder.ts  ← Voice prompt construction
        ├── prefetcher.ts      ← Deterministic data fetch from compiled_steps
        ├── action-executor.ts ← Voice action dispatch
        ├── entity-extractor.ts ← Regex entity extraction (voice-only)
        └── types.ts           ← Voice types
```

**New files to create (Sessions 4-7):**
```
    ├── intent-classifier.ts     ← Session 5: fast LLM intent classification
    ├── variable-extractor.ts    ← Session 5: shared regex extraction (generalized from cs-voice)
    ├── tool-generator.ts        ← Session 6: dynamic createTool() from registries
    ├── rule-verifier.ts         ← Session 7: rule_type_registry pattern verifier
    └── dynamic-prompt.ts        ← Session 4: dynamic prompt builder from registries
```
