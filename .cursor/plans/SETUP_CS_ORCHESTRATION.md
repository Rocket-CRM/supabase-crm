# SETUP — CS Orchestration Hub (paste into `/Users/rangwan/CS Module`)

You are setting up a **CS coordination hub** for Rocket CRM Customer Service. This hub is the Cursor workspace root for threads that touch CS frontend + backend + Render services together.

**Hub path (fixed):** `/Users/rangwan/CS Module`  
Open this folder as the Cursor project, then paste/run this file.

**Pattern:** same as `shopify-loyalty` (`/Users/rangwan/shopify-loyalty`) and `futurepark-upload-receipt` (`~/Documents/rocket/futurepark-upload-receipt`) — thin hub with docs + always-on cross-repo rules. Application code stays in sibling clones. Supabase backend is edited via **Supabase MCP only**.

**Supabase project ID:** `wkevmsedchftztoolkmi` — use for ALL Supabase MCP calls. Never call `list_projects`.

Execute every section below in order. Do not stop for approval between steps unless a path is missing or a copy fails. When finished, print a short setup report.

---

## 0) Confirm workspace

1. Confirm the current workspace root is exactly:
   ```bash
   pwd
   # must be: /Users/rangwan/CS Module
   ```
   If not, stop and tell the user to open `/Users/rangwan/CS Module` in Cursor.
2. All “this hub” paths in rules/docs = `/Users/rangwan/CS Module`.
3. Repo already has `.git` — do not re-init. Do **not** push or create a GitHub remote unless the user asks.
4. Create directories:

```bash
cd "/Users/rangwan/CS Module"
mkdir -p docs/backend docs/frontend docs/architecture .cursor/rules
```

---

## 1) Canonicalize sibling paths (do this before writing rules)

| Surface | Canonical path | GitHub | Notes |
|---------|----------------|--------|-------|
| This hub | `/Users/rangwan/CS Module` | `Rocket-CRM/cs-orchestration` (create later if needed) | Docs + rules only — **no** vendored Render `src/` |
| Admin FE | `~/Documents/rocket/loyalty-admin` | `Rocket-CRM/loyalty-admin` | Shared with CRM/Shopify. Never use `~/Documents/rocket/loyalty-admin` |
| CS AI service | `~/Documents/rocket/cs-ai-service` | `Rocket-CRM/cs-ai-service` | CS-primary Render service |
| Messaging (shared) | `~/Documents/rocket/messaging-service` | `Rocket-CRM/messaging-service` | Shared CS + CRM outbound |
| Supabase CRM backend | MCP only | project `wkevmsedchftztoolkmi` | No git source of truth |

### 1a) CS AI clone

If `~/Documents/rocket/cs-ai-service` does **not** exist:

```bash
# Prefer renaming the existing tmp clone if it tracks Rocket-CRM/cs-ai-service
# Otherwise clone fresh:
git clone git@github.com:Rocket-CRM/cs-ai-service.git ~/Documents/rocket/cs-ai-service
```

If only `~/Documents/rocket/cs-ai-service` exists:

1. Check its remote: `cd ~/Documents/rocket/cs-ai-service && git remote -v && git status`
2. If it is a clean clone of `Rocket-CRM/cs-ai-service`, move/rename it to `~/Documents/rocket/cs-ai-service` (or clone fresh to that path and leave tmp alone).
3. **All hub rules must point at `~/Documents/rocket/cs-ai-service`**, never `cs-ai-service-tmp`.

### 1b) Verify siblings exist

```bash
test -d ~/Documents/rocket/loyalty-admin && echo OK_loyalty_admin
test -d ~/Documents/rocket/cs-ai-service && echo OK_cs_ai
test -d ~/Documents/rocket/messaging-service && echo OK_messaging
test -d "~/Documents/rocket/supabase-crm/requirements" && echo OK_requirements
```

If any check fails, stop and tell the user which path is missing.

---

## 2) Copy requirement / feature docs into this hub

Copy files (do not symlink). Preserve filenames. Skip `* 2.md` duplicates.

### 2a) Backend requirements → `docs/backend/`

```bash
SRC_REQ="~/Documents/rocket/supabase-crm/requirements"
DEST_BE="$(pwd)/docs/backend"
cp "$SRC_REQ"/CS_*.md "$DEST_BE/"
ls "$DEST_BE" | wc -l   # expect 18
```

Files expected:

- `CS_AI_Pipeline.md`
- `CS_AI_System.md`
- `CS_Actions.md`
- `CS_Analytics.md`
- `CS_Channel_Connectors.md`
- `CS_Channels.md`
- `CS_Conversations.md`
- `CS_Feature_Spec.md`
- `CS_Knowledge_Base.md`
- `CS_Live_Assist.md`
- `CS_Phone_Number_Purchasing.md`
- `CS_Platform_Features.md`
- `CS_Procedures.md`
- `CS_Rules_Engine.md`
- `CS_SLA.md`
- `CS_Unified_Inbox.md`
- `CS_Voice.md`

### 2b) Frontend docs → `docs/frontend/`

```bash
SRC_FE="~/Documents/rocket/loyalty-admin/ProjectDocs"
DEST_FE="$(pwd)/docs/frontend"
cp "$SRC_FE/LOYALTY_ADMIN_CS_ADDITIONS.md" "$DEST_FE/"
cp "$SRC_FE/FE_docs/CsChannels.md" "$DEST_FE/"
cp "$SRC_FE/FE_docs/CheckIn_CS.md" "$DEST_FE/"
cp "$SRC_FE/FE_docs/LazadaCsIntegration.md" "$DEST_FE/"
cp "$SRC_FE/FE_docs/TicketTypes.md" "$DEST_FE/"
# Optional related FE docs if present:
for f in InternalKnowledge.md Translation.md; do
  [ -f "$SRC_FE/FE_docs/$f" ] && cp "$SRC_FE/FE_docs/$f" "$DEST_FE/"
done
```

### 2c) Architecture notes → `docs/architecture/`

```bash
SRC_DOCS="~/Documents/rocket/supabase-crm/docs"
DEST_ARCH="$(pwd)/docs/architecture"
for f in \
  CS_AI_Partner_Product_Design.md \
  CS_FUNCTION_PLAN.md \
  cs_ai_message_journey.md \
  cs_ai_pipeline_steps.md \
  cs_graph_executor_implementation.md \
  cs_platform_adapters_plan.md \
  cs_voice_architecture.md \
  cs_voice_poc_status.md
do
  [ -f "$SRC_DOCS/$f" ] && cp "$SRC_DOCS/$f" "$DEST_ARCH/"
done
```

### 2d) Truth boundary (write into docs later; obey now)

- Hub `docs/` = **working feature context** for agent threads (planning, FE/BE contracts, journeys).
- Live schema / RPC bodies / Edge Function bundles = **Supabase MCP** (verify before production changes).
- FE app code = `~/Documents/rocket/loyalty-admin` (never copy app `src/` into the hub).
- Render service code = sibling repos (never vendor into the hub).

Do **not** modify the source files under Supabase CRM or loyalty-admin in this setup pass (no pointer stubs unless the user asks later).

---

## 3) Write `docs/INDEX.md`

Create `docs/INDEX.md` with this content (adjust only if a copied file is missing):

```markdown
# CS Hub — Doc Index

Working feature docs for this orchestration hub. Live DB/Edge truth = Supabase MCP `wkevmsedchftztoolkmi`.

## Start here

1. [../AGENTS.md](../AGENTS.md) — agent entry
2. [../MONOREPO.md](../MONOREPO.md) — paths + permissions
3. [../FEATURES.md](../FEATURES.md) — ownership map
4. This index — pick the feature doc for the task

## Backend (copied from Supabase CRM `requirements/CS_*.md`)

| Topic | Doc |
|-------|-----|
| Feature overview / spec | [backend/CS_Feature_Spec.md](backend/CS_Feature_Spec.md) |
| Platform features | [backend/CS_Platform_Features.md](backend/CS_Platform_Features.md) |
| Unified inbox | [backend/CS_Unified_Inbox.md](backend/CS_Unified_Inbox.md) |
| Conversations | [backend/CS_Conversations.md](backend/CS_Conversations.md) |
| Channels | [backend/CS_Channels.md](backend/CS_Channels.md) |
| Channel connectors | [backend/CS_Channel_Connectors.md](backend/CS_Channel_Connectors.md) |
| Procedures (AOP) | [backend/CS_Procedures.md](backend/CS_Procedures.md) |
| Knowledge base | [backend/CS_Knowledge_Base.md](backend/CS_Knowledge_Base.md) |
| AI system | [backend/CS_AI_System.md](backend/CS_AI_System.md) |
| AI pipeline | [backend/CS_AI_Pipeline.md](backend/CS_AI_Pipeline.md) |
| Actions | [backend/CS_Actions.md](backend/CS_Actions.md) |
| Live assist | [backend/CS_Live_Assist.md](backend/CS_Live_Assist.md) |
| Voice | [backend/CS_Voice.md](backend/CS_Voice.md) |
| Phone numbers | [backend/CS_Phone_Number_Purchasing.md](backend/CS_Phone_Number_Purchasing.md) |
| Analytics | [backend/CS_Analytics.md](backend/CS_Analytics.md) |
| Rules engine | [backend/CS_Rules_Engine.md](backend/CS_Rules_Engine.md) |
| SLA | [backend/CS_SLA.md](backend/CS_SLA.md) |

## Frontend (copied from loyalty-admin ProjectDocs)

| Topic | Doc |
|-------|-----|
| CS admin additions | [frontend/LOYALTY_ADMIN_CS_ADDITIONS.md](frontend/LOYALTY_ADMIN_CS_ADDITIONS.md) |
| Channels UI | [frontend/CsChannels.md](frontend/CsChannels.md) |
| Check-in CS | [frontend/CheckIn_CS.md](frontend/CheckIn_CS.md) |
| Lazada CS | [frontend/LazadaCsIntegration.md](frontend/LazadaCsIntegration.md) |
| Ticket types | [frontend/TicketTypes.md](frontend/TicketTypes.md) |

## Architecture notes

| Topic | Doc |
|-------|-----|
| AI message journey | [architecture/cs_ai_message_journey.md](architecture/cs_ai_message_journey.md) |
| AI pipeline steps | [architecture/cs_ai_pipeline_steps.md](architecture/cs_ai_pipeline_steps.md) |
| Voice architecture | [architecture/cs_voice_architecture.md](architecture/cs_voice_architecture.md) |
| Function plan | [architecture/CS_FUNCTION_PLAN.md](architecture/CS_FUNCTION_PLAN.md) |
| Graph executor | [architecture/cs_graph_executor_implementation.md](architecture/cs_graph_executor_implementation.md) |
| Platform adapters | [architecture/cs_platform_adapters_plan.md](architecture/cs_platform_adapters_plan.md) |
| Partner product design | [architecture/CS_AI_Partner_Product_Design.md](architecture/CS_AI_Partner_Product_Design.md) |

## Code surfaces (not in docs/)

| Surface | Path |
|---------|------|
| Admin UI routes | `~/Documents/rocket/loyalty-admin/src/app/(admin)/cs-*` |
| CS AI Render service | `~/Documents/rocket/cs-ai-service` |
| Messaging (shared) | `~/Documents/rocket/messaging-service` |
| Supabase | MCP project `wkevmsedchftztoolkmi` |
```

---

## 4) Write hub entry docs

### 4a) `AGENTS.md`

```markdown
# CS Orchestration — Agent Entry Point

Coordination hub for Rocket CRM **Customer Service** (inbox, channels, procedures, knowledge, AI agent, voice, messaging) — same multi-repo orchestration pattern as:
- FuturePark: `~/Documents/rocket/futurepark-upload-receipt`
- Shopify: `/Users/rangwan/shopify-loyalty`

**Supabase project ID:** `wkevmsedchftztoolkmi` — use for ALL Supabase MCP calls. Never call `list_projects`.

## First read (new thread)

1. [MONOREPO.md](MONOREPO.md) — platform map, canonical paths, agent permissions
2. [FEATURES.md](FEATURES.md) — what this hub coordinates vs sibling repos
3. [docs/INDEX.md](docs/INDEX.md) — feature doc router
4. Task-specific doc under `docs/backend/`, `docs/frontend/`, or `docs/architecture/`

## You may edit these repos

| Surface | Path | Remote | Shared? |
|---------|------|--------|---------|
| **This hub** | `/Users/rangwan/CS Module` | `Rocket-CRM/cs-orchestration` | — |
| **Admin app (CS UI)** | `~/Documents/rocket/loyalty-admin` | `Rocket-CRM/loyalty-admin` | Yes |
| **CS AI service** | `~/Documents/rocket/cs-ai-service` | `Rocket-CRM/cs-ai-service` | CS-primary |
| **Messaging service** | `~/Documents/rocket/messaging-service` | `Rocket-CRM/messaging-service` | Yes (CS + CRM) |
| **CRM backend** | Supabase MCP only | `wkevmsedchftztoolkmi` | Yes |

Do **not** use `~/Documents/rocket/loyalty-admin` — use `~/Documents/rocket/loyalty-admin` only.
Do **not** vendor Render service `src/` into this hub.
Do **not** use `~/Documents/rocket/cs-ai-service` — canonical is `~/Documents/rocket/cs-ai-service`.

Before editing sibling repos: `git fetch origin` and `git status` (pull if behind and clean). See MONOREPO.md.

## Backend = Supabase MCP (required)

Deployed Edge Functions and RPCs live in Supabase CRM. This hub has **no** local Edge source of truth.

Workflow: read MCP tool schema → `get_edge_function` / `execute_sql` → edit → `deploy_edge_function` / `apply_migration` → verify.  
**Edge Functions use `deploy_edge_function` only — not SQL.**

- Edge Function workflow: `.cursor/rules/06-edge-function-mcp-workflow.mdc`
- JWT policy: `.cursor/rules/04-edge-function-jwt.mdc`
- Cross-repo routing: `.cursor/rules/05-cross-repo.mdc`

## Always-on Cursor rules

| Rule | Purpose |
|------|---------|
| `00-core.mdc` | Hub context, Supabase CRM, startup |
| `01-communication.mdc` | Output style |
| `04-edge-function-jwt.mdc` | verify_jwt on deploy |
| `05-cross-repo.mdc` | Task → repo routing; sibling edit permissions |
| `06-edge-function-mcp-workflow.mdc` | MCP Edge deploy (not SQL) |

## Deploy (only when user asks)

| Layer | How |
|-------|-----|
| Hub docs/rules | Push this repo (does **not** deploy FE or Render) |
| loyalty-admin FE | Push `Rocket-CRM/loyalty-admin` `main` from `~/Documents/rocket/loyalty-admin` |
| CS AI Render | Push `Rocket-CRM/cs-ai-service` `main` from `~/Documents/rocket/cs-ai-service` |
| Messaging Render | Push `Rocket-CRM/messaging-service` `main` from `~/Documents/rocket/messaging-service` |
| CRM backend | Supabase MCP `apply_migration` / `deploy_edge_function` (state impact + approval) |

## Study vs build

When the user says "study" or "research", analyze only and stop for approval before implementing.
```

### 4b) `MONOREPO.md`

```markdown
# Rocket CRM — Multi-Repo Platform Map (CS hub)

This project is a **coordination hub** for Customer Service — same pattern as FuturePark (`futurepark-upload-receipt`) and Shopify (`shopify-loyalty`). Application code lives in sibling repos; live Supabase CRM backend is edited via **Supabase MCP**.

## Agent permissions

Agents **may and should**:

- Edit **loyalty-admin** at `~/Documents/rocket/loyalty-admin` for CS admin UI (`cs-inbox`, `cs-channels`, `cs-procedures`, `cs-knowledge`, `cs-brand-config`, `cs-customers`, `cs-teams`, `cs-analytics`, `cs-call-logs`).
- Edit **cs-ai-service** at `~/Documents/rocket/cs-ai-service` for conversation agent, MCP tools, voice runtime.
- Edit **messaging-service** at `~/Documents/rocket/messaging-service` when send/delivery/adapters are in scope (label: **shared** with CRM).
- Edit **this hub** (`docs/`, rules, FEATURES) for CS feature context and coordination.
- Use **Supabase MCP** on `wkevmsedchftztoolkmi` for `cs_*` tables, `cs_bff_*` / `cs_fn_*`, and CS-related Edge Functions.

Agents must **not**:

- Copy or vendor Render service source into this hub.
- Stop at imagined local `supabase/functions/**` without deploying via Supabase MCP for production Edge changes.
- Use `~/Documents/rocket/loyalty-admin` or `cs-ai-service-tmp`.
- Push to any GitHub remote without explicit user request.
- Claim exclusive ownership of `messaging-service` or `loyalty-admin`.

## Ownership table

| Layer | GitHub | Canonical local path | How agents edit |
|-------|--------|----------------------|-----------------|
| **This hub** (CS docs + rules) | `Rocket-CRM/cs-orchestration` | `/Users/rangwan/CS Module` | Edit here |
| **Admin app** | `Rocket-CRM/loyalty-admin` | `~/Documents/rocket/loyalty-admin` | Edit files directly |
| **CS AI service** | `Rocket-CRM/cs-ai-service` | `~/Documents/rocket/cs-ai-service` | Edit files directly; Render deploys on push |
| **Messaging (shared)** | `Rocket-CRM/messaging-service` | `~/Documents/rocket/messaging-service` | Edit when task needs send path |
| **CRM backend** | Supabase `wkevmsedchftztoolkmi` | No git source of truth | **Supabase MCP only** |

## Sync before editing sibling repos

```bash
cd ~/Documents/rocket/loyalty-admin   # or cs-ai-service / messaging-service
git fetch origin
git status
# If behind origin/main and clean: git pull origin main
```

If local changes block pull, tell the user before overwriting.

**Git pull does not deploy Supabase.** After backend edits, use Supabase MCP.

## Task → where to edit

| Task touches | Edit here |
|--------------|-----------|
| Inbox, channels, procedures, knowledge, brand, teams, customers, analytics, call-logs UI | `~/Documents/rocket/loyalty-admin` — `src/app/(admin)/cs-*` |
| `cs_bff_*`, `cs_fn_*`, `cs_*` tables, CS Edge Functions | Supabase MCP `wkevmsedchftztoolkmi` |
| Conversation agent, CS MCP tools, voice agent runtime | `~/Documents/rocket/cs-ai-service` |
| LINE/SMS/email send adapters, `/send` API | `~/Documents/rocket/messaging-service` |
| CS feature docs, hub rules, backlog | This hub `docs/` + root md |

## MCP checklist

| MCP server | Use for |
|------------|---------|
| **user-supabase** | `execute_sql`, `apply_migration`, `deploy_edge_function`, `get_edge_function`, `list_edge_functions` — project `wkevmsedchftztoolkmi` only |
| **user-github** | Read/push sibling remotes when user asks |
| **user-crm-knowledge** | Product/feature narrative when helpful (still verify live schema via Supabase MCP) |

## Deploy workflow

| Layer | Action |
|-------|--------|
| **Hub** | Commit + push this repo — docs/rules only |
| **loyalty-admin FE** | Commit + push `main` on `Rocket-CRM/loyalty-admin` |
| **CS AI** | Commit + push `main` on `Rocket-CRM/cs-ai-service` (Render auto-deploy) |
| **Messaging** | Commit + push `main` on `Rocket-CRM/messaging-service` (Render auto-deploy) |
| **CRM backend** | `deploy_edge_function` / `apply_migration` via Supabase MCP — state impact; get explicit approval |

Hub push ≠ FE/Render/Supabase deploy.

## Symptom → fix

| Symptom | Fix |
|---------|-----|
| "I can't edit loyalty-admin from this workspace" | Edit `~/Documents/rocket/loyalty-admin` directly — permitted by `05-cross-repo.mdc` |
| Edited something under hub expecting Render to update | Push the **service** repo, not the hub |
| Used wrong loyalty-admin folder | Use `~/Documents/rocket/loyalty-admin`, not `Documents/rocket/loyalty-admin` |
| Used `cs-ai-service-tmp` | Use `~/Documents/rocket/cs-ai-service` |
| Edge Function "deployed" via SQL | Use `deploy_edge_function` — see `06-edge-function-mcp-workflow.mdc` |
| `401 UNAUTHORIZED_NO_AUTH_HEADER` after Edge redeploy | Redeploy with correct `verify_jwt` — see `04-edge-function-jwt.mdc` |
```

### 4c) `FEATURES.md`

```markdown
# CS Orchestration — Feature Map

Use this as the fast orientation page before deeper CS work. Paths: [MONOREPO.md](MONOREPO.md). Docs: [docs/INDEX.md](docs/INDEX.md).

## Platform ecosystem

| Layer | GitHub | Canonical local path | Edit from this hub? |
|-------|--------|----------------------|---------------------|
| **This hub** | `Rocket-CRM/cs-orchestration` | `/Users/rangwan/CS Module` | Yes — docs + rules |
| **Admin app** | `Rocket-CRM/loyalty-admin` | `~/Documents/rocket/loyalty-admin` | Yes |
| **CS AI service** | `Rocket-CRM/cs-ai-service` | `~/Documents/rocket/cs-ai-service` | Yes |
| **Messaging (shared)** | `Rocket-CRM/messaging-service` | `~/Documents/rocket/messaging-service` | Yes when send path in scope |
| **CRM backend** | Supabase `wkevmsedchftztoolkmi` | Live CRM only | Yes — via Supabase MCP |

## What this hub owns

- Working copies of CS feature docs under `docs/` (seeded from Supabase CRM + loyalty-admin ProjectDocs).
- Agent routing rules (`.cursor/rules/`).
- Feature ownership map (this file) and backlog/status notes you add later.

## What this hub does not own

- loyalty-admin application source — edit the clone directly.
- `cs-ai-service` / `messaging-service` source — edit those clones; do not vendor here.
- Deployed Supabase objects — Supabase MCP only.
- Exclusive ownership of shared `messaging-service` or `loyalty-admin`.

## Feature → surface

| Feature | Primary docs | Code / system |
|---------|--------------|---------------|
| Unified inbox | `docs/backend/CS_Unified_Inbox.md`, `CS_Conversations.md` | loyalty-admin `cs-inbox` + Supabase `cs_*` |
| Channels / connectors | `CS_Channels.md`, `CsChannels.md` | loyalty-admin `cs-channels` + connectors |
| Procedures | `CS_Procedures.md` | loyalty-admin `cs-procedures` + Supabase |
| Knowledge | `CS_Knowledge_Base.md` | loyalty-admin `cs-knowledge` + Supabase |
| Brand / AI config | `CS_AI_System.md` | loyalty-admin `cs-brand-config` |
| CS AI agent | `CS_AI_Pipeline.md`, `cs_ai_*` architecture docs | `~/Documents/rocket/cs-ai-service` + Inngest |
| Voice | `CS_Voice.md`, `cs_voice_architecture.md` | cs-ai-service voice + Supabase voice tables/edge |
| Outbound send | messaging README + channel docs | `~/Documents/rocket/messaging-service` (**shared**) |
| Analytics | `CS_Analytics.md` | loyalty-admin `cs-analytics` |
| Teams / customers | platform + FE routes | loyalty-admin `cs-teams`, `cs-customers` |

## Admin FE route inventory (loyalty-admin)

Under `~/Documents/rocket/loyalty-admin/src/app/(admin)/`:

- `cs-inbox`
- `cs-channels`
- `cs-procedures`
- `cs-knowledge`
- `cs-brand-config`
- `cs-customers`
- `cs-teams`
- `cs-analytics`
- `cs-call-logs`

## Source of truth

| Concern | Where |
|---------|-------|
| CS feature docs for threads | This hub `docs/` |
| Embedded admin FE code | `~/Documents/rocket/loyalty-admin` |
| CS AI / messaging runtime | Sibling service repos |
| CRM backend (tables, RPCs, Edge) | Supabase MCP `wkevmsedchftztoolkmi` |
```

### 4d) `README.md`

```markdown
# CS Orchestration Hub

Cursor coordination project for Rocket CRM **Customer Service** (frontend + backend + CS AI + messaging).

Open **this folder** as the Cursor workspace when a thread needs to change CS UI and backend together.

## Quick start

1. Open this project in Cursor.
2. New agent thread — it should read `AGENTS.md` → `MONOREPO.md` → `FEATURES.md` → `docs/INDEX.md`.
3. Ask for CS work as usual. The agent may edit sibling repos at the paths in `MONOREPO.md`.

## What lives here

- `docs/` — working CS feature docs (copied at setup)
- `.cursor/rules/` — cross-repo + Supabase MCP deploy rules
- No application `src/` for Render services (by design)

## Related hubs

- FuturePark receipts: `~/Documents/rocket/futurepark-upload-receipt`
- Shopify loyalty: `/Users/rangwan/shopify-loyalty`
- Supabase CRM backend docs home: `~/Documents/rocket/supabase-crm`
```

---

## 5) Write `.cursor/rules/` (alwaysApply) — including MCP workflow

Create each file exactly.

### 5a) `.cursor/rules/00-core.mdc`

```markdown
---
description: CS orchestration hub — routing and source-of-truth rules
alwaysApply: true
---

# CS Orchestration Coordination Hub

Supabase project ID: `wkevmsedchftztoolkmi` — use for every MCP call; never `list_projects`.

## New-thread startup

1. Read `AGENTS.md` and `MONOREPO.md` for paths and permissions.
2. Read `FEATURES.md` for ownership map.
3. Read `docs/INDEX.md`, then the relevant `docs/backend|frontend|architecture` file before diagnosing or coding.

## Frontend

- Local path: `~/Documents/rocket/loyalty-admin`
- Production remote: `Rocket-CRM/loyalty-admin`
- Do not duplicate loyalty-admin source into this hub.

## Render services (siblings — do not vendor)

- CS AI: `~/Documents/rocket/cs-ai-service` → `Rocket-CRM/cs-ai-service`
- Messaging (shared): `~/Documents/rocket/messaging-service` → `Rocket-CRM/messaging-service`

## Backend

- Verify live signatures via Supabase MCP before writing RPC/migration/Edge code.
- Follow `06-edge-function-mcp-workflow.mdc` and `04-edge-function-jwt.mdc`.
- Do not apply migrations or deploy Edge Functions without stating impact and getting explicit user approval.

## Deploy

| Layer | How |
|-------|-----|
| Hub | Push this repo (docs/rules only) |
| Admin FE | Push `Rocket-CRM/loyalty-admin` from `~/Documents/rocket/loyalty-admin` |
| CS AI | Push `Rocket-CRM/cs-ai-service` |
| Messaging | Push `Rocket-CRM/messaging-service` |
| Supabase | MCP migrate / `deploy_edge_function` |

Push only when the user explicitly asks. Hub push does not deploy siblings.

## Study vs build

When the user says "study" or "research", analyze only and stop for approval.
```

### 5b) `.cursor/rules/01-communication.mdc`

```markdown
---
description: Output style — simple first, then drill down
alwaysApply: true
---

# Output Style

Explain like a Principal Engineer briefing a non-technical stakeholder. The reader should understand **what happens**, **when**, and **why**.

**Tone:** precise and operational — not marketing fluff and not jargon dumps. Name real objects when they matter, but explain their role in business terms first.

**Do not lead with code.** Keep snippets minimal and narrate above them.

## Simple first, then drill down

1. Plain story
2. How the pieces relate
3. Only then: technical names, tables, file paths

## Answer shape (explain / analyze / propose / diagnose / plan)

1. Verdict in 1–2 sentences
2. Frame + types (plain language before ownership tables)
3. Process steps with actor labels
4. Edge cases that change the outcome
5. Identifiers / files last
```

### 5c) `.cursor/rules/05-cross-repo.mdc`

```markdown
---
description: Multi-repo CS platform routing — edit loyalty-admin, cs-ai-service, messaging-service, and Supabase from this hub
alwaysApply: true
---

# Cross-Repo Platform (CS)

Read `MONOREPO.md` for the full map.

Supabase project ID: `wkevmsedchftztoolkmi` — every Supabase MCP call; never `list_projects`.

## Agent permissions

You **may and should** edit these when the task requires it:

| Surface | Canonical path | GitHub | Shared? |
|---------|----------------|--------|---------|
| Admin CS UI | `~/Documents/rocket/loyalty-admin` | `Rocket-CRM/loyalty-admin` | Yes |
| CS AI runtime | `~/Documents/rocket/cs-ai-service` | `Rocket-CRM/cs-ai-service` | CS-primary |
| Messaging | `~/Documents/rocket/messaging-service` | `Rocket-CRM/messaging-service` | Yes |
| CRM backend | Supabase MCP only | `wkevmsedchftztoolkmi` | Yes |
| Hub docs/rules | This repo | `Rocket-CRM/cs-orchestration` | — |

Do **not** tell the user you cannot edit loyalty-admin, cs-ai-service, or messaging-service. Edit the canonical local clone directly.

Do **not** use `~/Documents/rocket/loyalty-admin` or `cs-ai-service-tmp`.

Do **not** copy Render service trees into this hub.

## Sync before sibling edits

```bash
cd ~/Documents/rocket/loyalty-admin   # or cs-ai / messaging
git fetch origin && git status
```

If behind `origin/main` and clean: `git pull origin main`. If pull would conflict, tell the user.

## Task routing

| Task | Where to work |
|------|---------------|
| `cs-inbox`, channels, procedures, knowledge, brand, teams, customers, analytics, call-logs UI | `~/Documents/rocket/loyalty-admin` |
| `cs_bff_*`, `cs_fn_*`, `cs_*` tables, CS Edge Functions | Supabase MCP |
| Conversation agent, tools, voice runtime | `~/Documents/rocket/cs-ai-service` |
| Outbound LINE/SMS/email `/send` | `~/Documents/rocket/messaging-service` |
| Feature docs / hub rules | This repo |

## Backend workflow

Follow `.cursor/rules/06-edge-function-mcp-workflow.mdc` for Edge Functions. Postgres via `execute_sql` / `apply_migration`. State impact + approval before production.

## Push policy

- Push only when the user explicitly asks
- Push the repo that owns the change (hub push ≠ Render/FE/Supabase deploy)
- loyalty-admin → `Rocket-CRM/loyalty-admin` `main`
- cs-ai-service → `Rocket-CRM/cs-ai-service` `main`
- messaging-service → `Rocket-CRM/messaging-service` `main`
```

### 5d) `.cursor/rules/06-edge-function-mcp-workflow.mdc`  ← MCP workflow baked in

```markdown
---
description: Supabase Edge Function edits — MCP-only workflow for CRM project wkevmsedchftztoolkmi
alwaysApply: true
---

# Edge Function MCP Workflow (CRM Backend)

**Project:** `wkevmsedchftztoolkmi` only. Never `list_projects`.

## SQL vs Edge Functions — different MCP tools

| Change type | MCP tool | Example |
|-------------|----------|---------|
| Postgres tables, RPCs, triggers | `execute_sql` or `apply_migration` | `cs_bff_*`, `cs_fn_*` |
| Edge Function TypeScript | **`deploy_edge_function`** | voice / webhook / custom-llm edges |

**Edge Function code cannot be changed via SQL.**

## Correct workflow (production source of truth = deployed CRM)

1. Read MCP tool schema (`get_edge_function`, `deploy_edge_function`).
2. **`get_edge_function`** for the target slug — live bundle; do not assume any local mirror matches production.
3. Edit only the file(s) that need changes. Keep other bundled files from step 2 unless intentionally updating them.
4. **`deploy_edge_function`** with:
   - `project_id`: `wkevmsedchftztoolkmi`
   - `name`: function slug
   - `entrypoint_path`: copy from `get_edge_function` response
   - `verify_jwt`: per `04-edge-function-jwt.mdc`
   - `files`: **every file** returned by `get_edge_function`, with edits applied
5. **`list_edge_functions`** — confirm version incremented and `verify_jwt` correct.

## Anti-patterns — do NOT do these

| Wrong | Why it fails |
|-------|----------------|
| `execute_sql` / `apply_migration` for Edge TS | SQL never updates Edge bundles |
| Edit a local mirror first, never `get_edge_function` | Local may be stale |
| Deploy only `index.ts` | Missing `_shared` imports → runtime errors |
| Temp JSON / Python API scripts / Task subagents for deploy | One direct `CallMcpTool` deploy is enough |
| Assume hub push deploys Supabase | Hub git ≠ Supabase |

Get user approval before production deploy.
```

### 5e) `.cursor/rules/04-edge-function-jwt.mdc`

```markdown
---
description: verify_jwt policy for CS-related and shared CRM Edge Function deploys
alwaysApply: true
---

# Edge Function JWT Policy (verify_jwt)

Supabase redeploys often default `verify_jwt` to **true**. Public webhooks, custom token callers, and some service-to-service edges break with `401 UNAUTHORIZED_NO_AUTH_HEADER` if JWT is flipped on.

## Deploy rule

When deploying an Edge Function via Supabase MCP `deploy_edge_function`:

1. **Inspect current `verify_jwt`** with `list_edge_functions` / prior `get_edge_function` metadata before changing it.
2. **Preserve the existing `verify_jwt` value** unless the user explicitly asks to change auth mode.
3. For known public/custom-auth CS entrypoints (webhooks, voice custom-llm, unauthenticated channel callbacks), deploy with `verify_jwt: false` and verify after deploy.
4. For admin-session BFFs that rely on Supabase JWT, keep `verify_jwt: true` (or platform default) — do **not** blanket-disable JWT project-wide.
5. After every deploy: confirm `verify_jwt` with `list_edge_functions`.

## Symptom → fix

| Symptom | Likely cause |
|---------|----------------|
| `401 UNAUTHORIZED_NO_AUTH_HEADER` right after redeploy | `verify_jwt` flipped to true on a custom-auth/public function |
| Suddenly open endpoint that should require auth | Accidental `verify_jwt: false` on a JWT-protected function |

When unsure, redeploy with the **pre-change** `verify_jwt` value — do not invent a new auth model mid-fix.
```

---

## 6) Optional: seed `.gitignore`

```gitignore
.DS_Store
node_modules/
.env
.env.*
*.log
.cursor/*.log
```

---

## 7) Verification checklist (run and report)

1. List hub root — must include `AGENTS.md`, `MONOREPO.md`, `FEATURES.md`, `README.md`, `docs/`, `.cursor/rules/`.
2. Count `docs/backend/CS_*.md` — expect **18**.
3. Confirm `docs/frontend/` has at least `LOYALTY_ADMIN_CS_ADDITIONS.md` and `CsChannels.md`.
4. Confirm rules exist: `00-core`, `01-communication`, `04-edge-function-jwt`, `05-cross-repo`, `06-edge-function-mcp-workflow`.
5. Confirm siblings: `loyalty-admin`, `cs-ai-service`, `messaging-service` paths exist.
6. Confirm **no** vendored `cs-ai-service/src` or `messaging-service/src` inside the hub.
7. Quick smoke (read-only): `ls ~/Documents/rocket/loyalty-admin/src/app/(admin)/cs-inbox` and `test -f ~/Documents/rocket/cs-ai-service/README.md`.

Print a setup report:

- Hub path
- Files created
- Doc counts (backend / frontend / architecture)
- Sibling path status
- Anything skipped / failed
- Remind user: open a **fresh thread** in this hub for real CS work; this setup thread can end.

---

## 8) Stop

Do not invent backlog features. Do not push remotes. Do not apply Supabase migrations. Setup only.

---

## How you (human) use this file

1. Open `/Users/rangwan/CS Module` as a Cursor project (File → Open Folder).
2. Start a new Agent chat.
3. Paste **this entire file** as the first message (or attach it and say “execute this setup”).
4. When the agent finishes, start a **fresh thread** in that project for real CS work.
