# Prompt 2: loyalty-admin — Add CS Module (FE + AI Service)

> **What this is:** Instructions for adding CS customer service features to the existing loyalty-admin Next.js project, plus the CS AI service (Render).  
> **Where to run:** In the `loyalty-admin` Cursor workspace.  
> **Prerequisite:** Run Prompt 1 (`CRM_PROJECT_CS_ADJUSTMENTS.md`) in the Supabase CRM workspace first — it creates the requirement docs and indexes that this project references.  
> **Current state:** loyalty-admin is a Next.js app with route groups `(admin)` for loyalty admin pages and `(standalone)` for public pages. API wrappers in `src/lib/api/`. Supabase client in `src/lib/supabase/`.

---

## Part 1: Project Structure Changes

### 1.1 Add CS route group

CS pages go in a new route group alongside `(admin)`. The `(admin)` layout (sidebar, auth, merchant context) applies to CS pages too — same admin panel, same login, same navigation.

```
src/app/
├── (admin)/
│   ├── layout.tsx                  ← Shared admin layout (sidebar, auth)
│   ├── tier/                       ← Existing loyalty pages
│   ├── reward/
│   ├── workflow-list/
│   ├── ...
│   ├── cs-inbox/                   ← NEW: CS conversation inbox
│   ├── cs-knowledge/               ← NEW: Knowledge base management
│   ├── cs-procedures/              ← NEW: AOP/procedure editor
│   ├── cs-channels/                ← NEW: Channel connections
│   ├── cs-brand-config/            ← NEW: Brand AI configuration
│   ├── cs-customers/               ← NEW: CS customer profiles
│   ├── cs-teams/                   ← NEW: Team management
│   └── cs-analytics/               ← NEW: CS analytics dashboards
├── (standalone)/
│   └── ...
```

CS pages live INSIDE `(admin)` — they share the same layout, auth guard, and merchant context. They're prefixed with `cs-` to sort together and be visually distinct from loyalty pages.

### 1.2 Add CS API wrappers

```
src/lib/api/
├── admin-menu.ts                   ← Existing
├── entity-options.ts               ← Existing
└── cs/                             ← NEW: All CS API wrappers
    ├── conversations.ts            ← cs_bff_get_conversations, cs_bff_send_message, etc.
    ├── knowledge.ts                ← cs_bff_get_knowledge_articles, cs_bff_upsert_knowledge_article
    ├── procedures.ts               ← cs_bff_get_procedures, cs_bff_upsert_procedure
    ├── channels.ts                 ← cs_bff_get_channels, cs_bff_upsert_channel
    ├── customers.ts                ← cs_bff_get_customer_detail
    ├── brand-config.ts             ← cs_bff_get_brand_config, cs_bff_upsert_brand_config
    ├── teams.ts                    ← cs_bff_get_teams, cs_bff_upsert_team
    └── ai-service.ts               ← HTTP calls to cs-ai-service on Render
```

Each wrapper follows the existing pattern in `src/lib/api/`:
```typescript
// src/lib/api/cs/conversations.ts
import { createClient } from '@/lib/supabase/server'

export async function getConversations(filters: ConversationFilters) {
  const supabase = await createClient()
  const { data, error } = await supabase.rpc('cs_bff_get_conversations', {
    p_filters: filters
  })
  // ... error handling
  return data
}
```

### 1.3 Add CS types

```
src/lib/types/
├── ... (existing loyalty types)
└── cs/                             ← NEW
    ├── conversations.ts            ← Conversation, Message, ConversationEvent types
    ├── knowledge.ts                ← KnowledgeArticle, KnowledgeEmbedding types
    ├── procedures.ts               ← Procedure, CompiledStep types
    ├── channels.ts                 ← Channel, Customer, PlatformIdentity types
    ├── brand-config.ts             ← BrandConfig, Guardrails, ModelConfig types
    └── ai-service.ts               ← Request/response types for AI service API
```

### 1.4 Add CS AI service

The CS AI service is a Node.js app deployed to Render. It lives in this repo but has its own package.json and build pipeline.

```
services/
└── cs-ai-service/
    ├── src/
    │   ├── agent/                  ← AI agent reasoning (AgentKit + LLM)
    │   ├── mcp/                    ← MCP server: CS action tools
    │   ├── inngest/                ← Inngest function definitions
    │   │   ├── conversation-process.ts
    │   │   ├── procedure-execute.ts
    │   │   ├── sla-check.ts
    │   │   └── knowledge-sync.ts
    │   ├── routes/                 ← HTTP API routes
    │   └── index.ts                ← Entry point
    ├── package.json
    ├── tsconfig.json
    └── Dockerfile
```

This is a separate Node.js project within the repo. It does NOT share Next.js config. It has its own dependencies (openai, @anthropic-ai/sdk, inngest, etc.).

---

## Part 2: Update Cursor Rules

### 2.1 Update requirement-docs.mdc

The existing `requirement-docs.mdc` has domain line ranges for loyalty only. Add CS domains.

**Append to the domain line ranges table:**

```markdown
| CS Conversations | TBD | 
| CS Knowledge Base | TBD |
| CS Procedures | TBD |
| CS Channels & Customers | TBD |
| CS Brand Config | TBD |
```

Note: Line ranges will be populated after Prompt 1 adds CS sections to INDEX_DOMAIN.md. Update these once the CRM project changes are applied.

Also add to the "Typical Workflows" section:

```markdown
**CS inbox feature** (e.g., display conversation list):
1. Layer 1: Read CS Conversations domain in INDEX_DOMAIN → get `cs_bff_get_conversations` + business rules
2. Layer 2: MCP query for function signature → get params and return type
3. Build the page in `src/app/(admin)/cs-inbox/`

**CS + Loyalty cross-domain** (e.g., show loyalty tier in conversation sidebar):
1. Layer 1: Read CS Conversations for conversation data
2. Layer 1: Read Tier domain for tier display logic
3. Layer 2: MCP for both function signatures
4. Build component that calls both domains' BFFs
```

### 2.2 Update sidebar navigation

The admin sidebar (`layout.tsx` in `(admin)`) needs CS navigation items. Add a "Customer Service" section:

```
Sidebar:
├── Dashboard
├── Loyalty
│   ├── Tier
│   ├── Rewards
│   ├── Missions
│   ├── Currency
│   └── ...
├── Marketing
│   ├── Workflows
│   ├── Audiences
│   └── Agent Builder
├── Customer Service          ← NEW section
│   ├── Inbox                 → /cs-inbox
│   ├── Knowledge Base        → /cs-knowledge
│   ├── Procedures            → /cs-procedures
│   ├── Channels              → /cs-channels
│   ├── Teams                 → /cs-teams
│   ├── Brand Config          → /cs-brand-config
│   ├── Customers             → /cs-customers
│   └── Analytics             → /cs-analytics
└── Settings
    ├── ...
```

### 2.3 Add CS-specific FE rules

**Create** `.cursor/rules/cs-frontend.mdc`:

```markdown
---
description: Patterns for CS frontend pages. Use when building pages in src/app/(admin)/cs-*
globs: "src/app/(admin)/cs-*/**/*.tsx,src/app/(admin)/cs-*/**/*.ts"
alwaysApply: false
---

## CS Frontend Patterns

### API Wrappers
All CS API calls go through `src/lib/api/cs/`. Never call `supabase.rpc()` directly from components.

### Types
All CS types in `src/lib/types/cs/`. Import from there, not inline.

### Real-Time
CS inbox uses Supabase Realtime for live message updates:
```typescript
supabase.channel('cs-conversations')
  .on('postgres_changes', { event: 'INSERT', schema: 'public', table: 'cs_messages' }, handler)
  .subscribe()
```

### AI Service Calls
Calls to the CS AI service (Render) go through `src/lib/api/cs/ai-service.ts`.
Base URL configured via environment variable `NEXT_PUBLIC_CS_AI_SERVICE_URL`.

### CS pages follow the same patterns as loyalty pages:
- Server Components for data fetching
- Client Components for interactivity
- Same design system, same component library
- Same error handling, same loading states
```

### 2.4 Add AI service rules

**Create** `.cursor/rules/cs-ai-service.mdc`:

```markdown
---
description: Patterns for the CS AI service (Render). Use when working in services/cs-ai-service/
globs: "services/cs-ai-service/**/*.ts"
alwaysApply: false
---

## CS AI Service Patterns

### Architecture
- Node.js + TypeScript on Render
- AgentKit + LLM (OpenAI / Anthropic) for AI reasoning
- MCP server exposing CS action tools
- Inngest for durable execution (conversation processing, procedure execution)
- Supabase client with service_role key for DB access

### Supabase Access
Uses service_role (not user JWT). Always include merchant_id in queries.
```typescript
const { data } = await supabase
  .from('cs_conversations')
  .select('*')
  .eq('merchant_id', merchantId)
```

### Inngest Functions
Registered via the cs-inngest-serve edge function. Pattern:
```typescript
export const processConversation = inngest.createFunction(
  { id: 'cs/conversation.process' },
  { event: 'cs/message.received' },
  async ({ event, step }) => {
    // step.run, step.waitForEvent, step.sleep patterns
  }
)
```

### MCP Tools
Each tool validates brand scope before executing. Pattern:
```typescript
{
  name: 'cancel_order',
  description: 'Cancel an unfulfilled order',
  parameters: { order_id: 'string' },
  execute: async ({ order_id }, context) => {
    // Validate merchant owns this order
    // Call marketplace API
    // Return result
  }
}
```

### Environment Variables
```
SUPABASE_URL=
SUPABASE_SERVICE_ROLE_KEY=
OPENAI_API_KEY=
ANTHROPIC_API_KEY=
INNGEST_EVENT_KEY=
INNGEST_SIGNING_KEY=
```
```

---

## Part 3: Symlink Requirements (if not already done)

```bash
cd ~/loyalty-admin
ln -s "/Users/rangwan/Documents/Supabase CRM/requirements" requirements
```

Verify: `ls ~/loyalty-admin/requirements/INDEX_DOMAIN.md` should exist.

This gives the FE workspace access to all requirement docs (loyalty + CS) for the `requirement-docs.mdc` layered lookup.

---

## Part 4: Execution Order

| Step | What | Effort |
|---|---|---|
| 1 | Symlink requirements (if not done) | 1 min |
| 2 | Create `src/app/(admin)/cs-inbox/` stub page | 10 min |
| 3 | Create `src/lib/api/cs/` directory with stub files | 15 min |
| 4 | Create `src/lib/types/cs/` directory with type definitions | 20 min |
| 5 | Create `services/cs-ai-service/` with package.json + src/index.ts | 15 min |
| 6 | Create `.cursor/rules/cs-frontend.mdc` | 5 min |
| 7 | Create `.cursor/rules/cs-ai-service.mdc` | 5 min |
| 8 | Update `requirement-docs.mdc` with CS domains | 10 min |
| 9 | Add CS section to sidebar navigation | 15 min |

**Note:** Steps 2-5 create stubs only. Actual implementation of inbox, knowledge editor, procedure editor etc. comes after the Supabase backend has the cs_ tables and functions deployed (via Prompt 1 in the CRM workspace).

---

## Part 5: Verify Checklist

- [ ] `requirements/` symlink works (can read INDEX_DOMAIN.md)
- [ ] `src/app/(admin)/cs-inbox/page.tsx` exists (stub)
- [ ] `src/lib/api/cs/` directory exists with stub files
- [ ] `src/lib/types/cs/` directory exists with type files
- [ ] `services/cs-ai-service/package.json` exists
- [ ] `.cursor/rules/cs-frontend.mdc` exists
- [ ] `.cursor/rules/cs-ai-service.mdc` exists
- [ ] Sidebar has "Customer Service" section
- [ ] `requirement-docs.mdc` has CS domain line ranges
