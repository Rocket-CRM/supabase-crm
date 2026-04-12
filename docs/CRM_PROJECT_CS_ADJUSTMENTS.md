# Prompt 1: Supabase Backend Project — Workflow Improvements + CS Module

> **What this is:** Instructions for upgrading this Supabase backend project. Two goals: (1) fix the project's own AI workflow so it auto-looks-up context instead of guessing, (2) add CS module support (requirement docs, indexes, table naming).  
> **Where to run:** In the `Supabase CRM` Cursor workspace.  
> **Important:** This project has NO local code files. All DB work happens via Supabase MCP (`execute_sql`, `apply_migration`, `deploy_edge_function`). Rules use `alwaysApply: true` because there are no file edits to glob against.  
> **Project ID:** `wkevmsedchftztoolkmi`  
> **Companion doc:** After running this, run Prompt 2 (`LOYALTY_ADMIN_CS_ADDITIONS.md`) in the loyalty-admin workspace.

---

## Part 1: Fix the Project's AI Workflow

The FE project (loyalty-admin) has layered context lookup, schema verification, and study-before-build rituals. This backend project has none — the AI guesses instead of looking things up. Fix that first.

### 1.1 Replace 00-overview.mdc

Replace `.cursor/rules/00-overview.mdc` entirely with the content below. Key changes: adds a 5-step Context Lookup Procedure that the AI follows on EVERY task, adds CS domains to the study map, reframes the project as CX Platform (not just CRM).

```markdown
---
alwaysApply: true
---

# CX Platform — Supabase Backend

This is the Supabase backend for a **CX Platform** with two modules:
- **Loyalty** — points, tiers, rewards, missions, marketing automation
- **CS (Customer Service)** — conversations, knowledge base, AI procedures, omnichannel support

Both modules share this Supabase project. Requirement docs are in `/requirements/`. CS docs are prefixed with `CS_`.

## Supabase Project

- **Project ID:** `wkevmsedchftztoolkmi`
- NEVER call `list_projects` — use this ID directly.
- All DB work via MCP: `execute_sql`, `apply_migration`, `deploy_edge_function`
- Do NOT write local code files — deploy directly via MCP.

## Context Lookup Procedure

When the user gives you ANY task (bug, feature, question, analysis), follow these steps BEFORE writing code or proposing solutions.

### Step 1 — Identify the domain

Match keywords from the user's message to a domain:

**Loyalty Domains:**

| Feature | Requirement Docs | DB Patterns |
|---------|-----------------|-------------|
| Missions | `Mission.md` | `mission_*`, `fn_*mission*` |
| Rewards | `Reward.md` | `reward_*`, `redemption_*`, `promo_code_*` |
| Currency | `Currency.md` | `wallet_*`, `points_*`, `tickets_*` |
| Tier | `Tier.md` | `tier_*`, `user_tier_*` |
| Tag/Persona | `Tag_and_Persona.md` | `persona_*`, `tag_*`, `user_personas`, `user_tags` |
| Referral | `Referral.md` | `referral_*` |
| Forms | `Forms.md` | `form_*`, `form_submissions` |
| Checkin | `Checkin.md` | `checkin_*` |
| Stored Value Card | `Stored_Value_Card.md` | `svc_*`, `stored_value_*` |
| Store Classification | `Store_Attribute_Classification.md` | `store_*`, `location_*`, `partner_*` |
| Activity/Earning | `Activity_Based_Earning.md` | `activity_*`, `earn_*` |
| Purchase | `Purchase_Transaction.md` | `purchase_*`, `transaction_*` |
| AMP Workflows | `AMP - Rule Based.md` | `workflow_master`, `workflow_node` |
| AMP AI Agent | `AMP - AI Decisioning.md` | `amp_agent`, `amp_agent_action` |

**CS Domains:**

| Feature | Requirement Docs | DB Patterns |
|---------|-----------------|-------------|
| CS Overview | `CS_Feature_Spec.md` | `cs_*` |
| Conversations | `CS_Conversations.md` | `cs_conversations`, `cs_messages`, `cs_conversation_events` |
| Knowledge Base | `CS_Knowledge_Base.md` | `cs_knowledge_articles`, `cs_knowledge_embeddings` |
| Procedures/AOPs | `CS_Procedures.md` | `cs_procedures` |
| CS Channels | `CS_Channels.md` | `cs_channels`, `cs_platform_identities` |
| CS Customers | `CS_Customers.md` | `cs_customers`, `cs_customer_memory` |

If you can't match keywords, read the keyword cross-reference section in `requirements/INDEX_DOMAIN.md`.

### Step 2 — Read the domain index entry

Read ONLY the relevant domain section from `requirements/INDEX_DOMAIN.md` using offset + limit. NEVER read the full file.

Extract: key business rules, function names + types, table names.

### Step 3 — Verify schema via Supabase MCP

Before writing ANY code, verify the live state:

Table columns:
```sql
SELECT column_name, data_type, is_nullable, column_default
FROM information_schema.columns
WHERE table_schema = 'public' AND table_name = '<table>'
ORDER BY ordinal_position;
```

Existing functions in the domain:
```sql
SELECT proname, pg_get_function_arguments(oid)
FROM pg_proc p JOIN pg_namespace n ON p.pronamespace = n.oid
WHERE n.nspname = 'public' AND p.proname LIKE '%<domain_keyword>%';
```

Full function body (when you need logic details):
```sql
SELECT pg_get_functiondef(p.oid)
FROM pg_proc p JOIN pg_namespace n ON p.pronamespace = n.oid
WHERE n.nspname = 'public' AND p.proname = '<function_name>';
```

### Step 4 — Read requirement doc sections (only if needed)

Only when Steps 1-3 don't give enough context (complex business rules, state machines, edge cases). Use offset + limit, never the full doc.

### Step 5 — Present findings, then wait

Present: relevant tables, functions, business rules, proposed approach. WAIT for approval before making any changes.

## Workflow

1. Follow the Context Lookup Procedure (Steps 1-5)
2. Present findings and proposal
3. Creation work follows only after explicit human approval
```

### 1.2 Create 07-verify-before-coding.mdc

**Create** `.cursor/rules/07-verify-before-coding.mdc`:

```markdown
---
description: Verify actual database schema via Supabase MCP before writing any function, migration, or query.
alwaysApply: true
---

## Verify Schema Before Coding

Before writing ANY function, migration, or query that touches a table, verify the live schema via Supabase MCP (`execute_sql` with project_id `wkevmsedchftztoolkmi`).

### Required checks:

1. **Table columns:**
```sql
SELECT column_name, data_type, is_nullable, column_default
FROM information_schema.columns
WHERE table_schema = 'public' AND table_name = '<table>'
ORDER BY ordinal_position;
```

2. **Existing functions in same domain:**
```sql
SELECT proname, pg_get_function_arguments(oid)
FROM pg_proc p JOIN pg_namespace n ON p.pronamespace = n.oid
WHERE n.nspname = 'public' AND p.proname LIKE '<prefix>%<domain>%';
```

3. **Full body of a related function (to match patterns):**
```sql
SELECT pg_get_functiondef(p.oid)
FROM pg_proc p JOIN pg_namespace n ON p.pronamespace = n.oid
WHERE n.nspname = 'public' AND p.proname = '<similar_function>';
```

### NEVER:
- Guess column names from memory, spec docs, or similar tables
- Assume data types without checking
- Assume a column exists because a requirement doc mentions it (docs can be stale)
- Copy column lists between tables without verifying each

### ALWAYS:
- Run check #1 before writing any new function
- Run check #2 before creating a function (to avoid duplicating existing ones)
- Run check #3 when you need to match the coding style of existing functions
```

### 1.3 Create 08-context-lookup.mdc

**Create** `.cursor/rules/08-context-lookup.mdc`:

```markdown
---
description: How to look up domain context, business rules, and function signatures from indexes and MCP. Detailed 3-layer procedure.
alwaysApply: false
---

## 3-Layer Context Lookup

Follow these layers in order. Stop at the layer that gives enough context.

### Layer 1 — Domain Index (always start here)

Read ONLY your domain's section from `requirements/INDEX_DOMAIN.md` using offset + limit. NEVER read the full file.

Extract:
- **Keywords** — confirm you're in the right domain
- **Tables** — which tables this domain uses
- **Functions** — which exist, their types (BFF/Backend/Trigger)
- **Business rules** — key rules summarized inline

This layer alone is often enough for simple tasks.

### Layer 2 — Supabase MCP (for live schema and function details)

Project ID: `wkevmsedchftztoolkmi`

Function signature:
```sql
SELECT proname, pg_get_function_arguments(oid), pg_get_function_result(oid)
FROM pg_proc p JOIN pg_namespace n ON p.pronamespace = n.oid
WHERE n.nspname = 'public' AND p.proname = 'FUNCTION_NAME';
```

Full function body:
```sql
SELECT pg_get_functiondef(p.oid)
FROM pg_proc p JOIN pg_namespace n ON p.pronamespace = n.oid
WHERE n.nspname = 'public' AND p.proname = 'FUNCTION_NAME';
```

Table schema:
```sql
SELECT column_name, data_type, is_nullable
FROM information_schema.columns
WHERE table_schema = 'public' AND table_name = 'TABLE_NAME'
ORDER BY ordinal_position;
```

Prefer MCP over doc reading for schema/function details — MCP is always current.

### Layer 3 — Requirement Doc Sections (complex business rules only)

Only read the source doc when Layers 1-2 don't cover detailed business rules, state machines, or edge cases. NEVER read a full doc — use offset + limit.

### Function Index — When to Use

Read `requirements/INDEX_FUNCTION.md` (specific domain section only) when you need to:
- Find ALL functions in a domain
- Understand function types: BFF, Backend, Trigger, Edge, Inngest
- Check if a function already exists before creating a new one

### Typical Workflows

**Bug fix** (e.g., "wallet balance is wrong"):
1. Layer 1: Read Currency domain in INDEX_DOMAIN → tables, functions, rules
2. Layer 2: MCP — read the relevant function body → find the bug
3. Fix the function

**New function** (e.g., "add a BFF to get CS conversations"):
1. Layer 1: Read CS Conversations in INDEX_DOMAIN → existing functions, tables
2. Layer 2: MCP — check table schema, check if function exists, read a similar BFF to match patterns
3. Write the function

**Analysis** (e.g., "how does tier evaluation work?"):
1. Layer 1: Read Tier domain in INDEX_DOMAIN → business rules summary
2. Layer 3: Read Tier.md specific sections for detail
3. Layer 2: MCP — read function body
4. Present findings
```

### 1.4 Existing rules — confirm 06-update-docs.mdc

Already created with `alwaysApply: true`. Verify it exists and covers all code locations (Supabase, Render, Inngest, FE).

### 1.5 Final rules inventory

```
.cursor/rules/
├── 00-overview.mdc              ← alwaysApply: true — project identity + context lookup procedure
├── 02-functions-queues-triggers.mdc  ← alwaysApply: false — component analysis guidelines (existing)
├── 04-guardrails.mdc            ← alwaysApply: true — read-only default, approval required (existing)
├── 05-function-database-implementation.mdc  ← alwaysApply: false — naming, RLS, column conventions (existing)
├── 06-update-docs.mdc           ← alwaysApply: true — doc sync on every change
├── 07-verify-before-coding.mdc  ← alwaysApply: true — schema verification via MCP
└── 08-context-lookup.mdc        ← alwaysApply: false — 3-layer lookup (detailed reference)
```

---

## Part 2: Add CS Module

### 2.1 Create CS Requirement Docs

**`requirements/CS_Feature_Spec.md`**

Copy the "DATABASE SCHEMA DESIGN — CS Module" section from `.cursor/plans/cs_ai_feature_spec_45a47ba9.plan.md` (lines ~3019–3697). This is the canonical CS reference: conceptual framework, multi-model pipeline, table schemas (all 13 cs_ tables), naming conventions, shared table usage.

**`requirements/CS_Conversations.md`**

```markdown
# CS Conversations & Messages

## Core Tables

### cs_conversations
[Copy table definition from CS_Feature_Spec.md §4.5]

### cs_messages
[Copy from §4.6]

### cs_conversation_events
[Copy from §4.7]

## Business Logic

### Conversation Session Logic
- Marketplace channels: follow platform's threading (1:1 to their conversation_id)
- Owned channels: configurable threading_interval and session_timeout per channel
[Copy threading rules from plan doc §2.0]

### Conversation Lifecycle
open → pending → snoozed → resolved → closed (can reopen)

### Message Types
text, image, product_card, order_card, voice_transcript, file, note (internal)

## Functions

| Function | Type | Purpose |
|---|---|---|
| `cs_bff_get_conversations` | BFF | List conversations for inbox |
| `cs_bff_get_conversation_detail` | BFF | Single conversation with messages |
| `cs_bff_send_message` | BFF | Agent sends reply |
| `cs_bff_assign_conversation` | BFF | Assign to agent/team |
| `cs_bff_update_conversation_status` | BFF | Change status |
| `cs_fn_upsert_conversation` | Backend | Create/update from webhook |
| `cs_fn_insert_message` | Backend | Insert message |
| `cs_fn_log_event` | Backend | Log conversation event |
```

**`requirements/CS_Knowledge_Base.md`**

```markdown
# CS Knowledge Base

## Core Tables

### cs_knowledge_articles
[Copy from §4.10]

### cs_knowledge_embeddings
[Copy from §4.11]

## Business Logic

### Embedding Pipeline (automatic)
Article insert/update → DB trigger → pgmq → pg_cron → Edge Function → OpenAI embedding → chunks + vectors

### Custom Answers
is_custom_answer = true → checked before AI-generated responses. Priority ordering.

### Retrieval Flow
Question → embed → pgvector cosine similarity → top K chunks → inject into AI prompt

## Functions

| Function | Type | Purpose |
|---|---|---|
| `cs_bff_get_knowledge_articles` | BFF | List articles |
| `cs_bff_upsert_knowledge_article` | BFF | Create/update article |
| `cs_fn_search_knowledge` | Backend | Semantic search via pgvector |
| `cs_fn_generate_embeddings` | Backend | Chunk + embed (trigger-called) |
```

**`requirements/CS_Procedures.md`**

```markdown
# CS Procedures (Agent Operating Procedures)

## Core Tables

### cs_procedures
[Copy from §4.12]

## Business Logic

### AOP Format
Natural language steps with @Tool references, {{variables}}, branching.
See plan doc §4.6 for full format specification.

### Flexibility: strict / guided / agentic
### config.tone_override: overrides brand voice per intent
### Versioning: new row per edit, is_active toggle

## Functions

| Function | Type | Purpose |
|---|---|---|
| `cs_bff_get_procedures` | BFF | List procedures |
| `cs_bff_upsert_procedure` | BFF | Create/update |
| `cs_fn_match_procedure` | Backend | Match intent → active procedure |
| `cs_fn_compile_procedure` | Backend | Parse raw → compiled_steps |
```

**`requirements/CS_Channels.md`**

```markdown
# CS Channels, Customers & Memory

## Core Tables

### cs_channels
[Copy from §4.2]

### cs_customers
[Copy from §4.3]

### cs_platform_identities
[Copy from §4.4]

### cs_customer_memory
[Copy from §4.13]

## Business Logic

### Identity Resolution
platform_user_id → cs_platform_identities → cs_customers. If not found, create both.

### Cross-Platform Linking
Matched by phone, email, or manual agent linking.

### Customer Memory
Extracted async post-resolution. LLM distills facts. Injected into next conversation prompt.
Categories: health, preference, interest, logistics, issue, feedback, communication.

## Functions

| Function | Type | Purpose |
|---|---|---|
| `cs_bff_get_channels` | BFF | List connected channels |
| `cs_bff_upsert_channel` | BFF | Configure channel |
| `cs_bff_get_customer_detail` | BFF | Customer + identities + memory |
| `cs_fn_resolve_customer` | Backend | Find/create from platform ID |
| `cs_fn_link_identities` | Backend | Link platform identities |
```

### 2.2 Update INDEX_DOMAIN.md

Append CS domain sections to `requirements/INDEX_DOMAIN.md`. Each section has: Keywords, Source, Tables, Functions, Key Business Rules. Add sections for:
- CS Conversations
- CS Knowledge Base
- CS Procedures (AOPs)
- CS Channels & Customers
- CS Brand Configuration
- CS Teams & Agent Profiles

### 2.3 Update INDEX_FUNCTION.md

Append CS function sections to `requirements/INDEX_FUNCTION.md`:
- CS Conversations (BFF + Backend)
- CS Knowledge Base
- CS Procedures
- CS Channels & Customers
- CS Brand Config & Teams
- CS Edge Functions (cs-webhook-*, cs-inngest-serve)
- CS Inngest Functions (cs/conversation.process, cs/procedure.execute, etc.)

Note: These functions don't exist yet. Listed as planned inventory. Update with actual signatures as implemented (enforced by 06-update-docs.mdc).

### 2.4 Rename workflow tables via MCP

Execute via Supabase MCP `execute_sql`:

```sql
ALTER TABLE amp_workflow RENAME TO workflow_master;
ALTER TABLE amp_workflow_node RENAME TO workflow_node;
ALTER TABLE amp_workflow_edge RENAME TO workflow_edge;
ALTER TABLE amp_workflow_trigger RENAME TO workflow_trigger;
ALTER TABLE amp_workflow_log RENAME TO workflow_log;
ALTER TABLE amp_action_type_config RENAME TO workflow_action_type_config;

ALTER TABLE workflow_master ADD COLUMN IF NOT EXISTS domain TEXT NOT NULL DEFAULT 'loyalty';
ALTER TABLE workflow_trigger ADD COLUMN IF NOT EXISTS domain TEXT NOT NULL DEFAULT 'loyalty';
ALTER TABLE workflow_action_type_config ADD COLUMN IF NOT EXISTS domain TEXT NOT NULL DEFAULT 'loyalty';
```

Update references in INDEX_FUNCTION.md and INDEX_DOMAIN.md.

### 2.5 Add CS-specific patterns to 05-function-database-implementation.mdc

Append to the existing rule:

```markdown
## CS Table Naming
Pattern: `cs_<entity>` or `cs_<domain>_<type>`
Examples: `cs_conversations`, `cs_brand_config`, `cs_conversation_events`

## CS Function Naming
| Prefix | Type | Auth context |
|---|---|---|
| `cs_bff_*` | CS backend-for-frontend | JWT — merchant from token via get_current_merchant_id() |
| `cs_fn_*` | CS internal/backend | Service role or called by other functions |
| `cs_api_*` | CS external API | JWT or API key |

## CS RLS Pattern
Every cs_ table:
ALTER TABLE cs_<table> ENABLE ROW LEVEL SECURITY;
CREATE POLICY "merchant_isolation" ON cs_<table>
  FOR ALL USING (merchant_id = get_current_merchant_id());

## Cross-Domain Access
When CS functions need loyalty data (user tier, points, tags):
- Read via existing loyalty functions — look them up in INDEX_FUNCTION.md
- NEVER write to loyalty tables directly from CS functions
- For writes: use bridge functions that route through existing loyalty logic
```

---

## Part 3: Execution Order

| Step | What | Effort |
|---|---|---|
| 1 | Replace `00-overview.mdc` | 5 min |
| 2 | Create `07-verify-before-coding.mdc` | 5 min |
| 3 | Create `08-context-lookup.mdc` | 5 min |
| 4 | Create `CS_Feature_Spec.md` (copy from plan doc) | 15 min |
| 5 | Create CS_Conversations.md, CS_Knowledge_Base.md, CS_Procedures.md, CS_Channels.md | 30 min |
| 6 | Update INDEX_DOMAIN.md with CS sections | 20 min |
| 7 | Update INDEX_FUNCTION.md with CS sections | 15 min |
| 8 | Update 05-function-database-implementation.mdc with CS patterns | 5 min |
| 9 | Rename workflow tables via MCP | 10 min |
| 10 | Test: prompt "how does tier evaluation work?" → verify AI follows lookup procedure | 5 min |

---

## Part 4: Verify Checklist

**Project workflow:**
- [ ] `00-overview.mdc` has 5-step Context Lookup Procedure
- [ ] `07-verify-before-coding.mdc` exists (alwaysApply: true)
- [ ] `08-context-lookup.mdc` exists (3-layer lookup)
- [ ] `06-update-docs.mdc` exists (alwaysApply: true)
- [ ] Test: paste a bug → AI auto-looks up domain, reads index, verifies via MCP

**CS module:**
- [ ] `requirements/CS_Feature_Spec.md` exists
- [ ] `requirements/CS_Conversations.md` exists
- [ ] `requirements/CS_Knowledge_Base.md` exists
- [ ] `requirements/CS_Procedures.md` exists
- [ ] `requirements/CS_Channels.md` exists
- [ ] `requirements/INDEX_DOMAIN.md` has CS sections
- [ ] `requirements/INDEX_FUNCTION.md` has CS sections
- [ ] `05-function-database-implementation.mdc` has CS patterns
- [ ] Workflow tables renamed

**After this, run Prompt 2 in loyalty-admin workspace.**
