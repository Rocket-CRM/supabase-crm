# AI agent knowledge system

**What this is:** The deliberate structure we built so Cursor agents (and other tools) can answer product and implementation questions **accurately** without full-repo reads, hallucinated features, or 100KB doc dumps every turn.

**Status (2026):** Production retrieval is **CRM Knowledge MCP v2** — chunked `requirements/**/*.md` in Postgres with hybrid FTS + semantic search. Earlier **typed Postgres blocks** (`internal_knowledge_*`) were the v1 experiment; v2 makes **git requirements the source of truth** and indexes them automatically.

---

## Purpose

| Problem | What we built |
|--------|----------------|
| Requirements live in large Markdown files; agents full-read them | **Chunk index** + grep-first / MCP search with citations (`path#heading`) |
| Product questions need framing before SQL | **Layered context** — routers → MCP excerpts → scoped doc read → live Supabase |
| Marketing/sales copy must not invent features | **Truth boundary** — CRM Knowledge = product narrative from requirements; live schema/RPCs verified separately |
| Writing quality is separate from product facts | **Writing Principles** — parallel MCP/files for tone, genre playbooks, localization (not stored in CRM Knowledge tables) |
| Token burn from discovery loops | **Turn budgets**, batching, thread checkpoints (see agent context architecture) |

---

## Architecture at a glance

```
Layer 0  Cursor rules (laws, routing, stop conditions)
    ↓
Layer 1  Registries + domain index (grep only — names & locations)
    ↓
Layer 2  CRM Knowledge MCP — search_docs + get_section (requirements chunks)
    ↓
Layer 3  Requirement docs — scoped read when MCP is not enough
    ↓
Layer 4  Live Supabase / code — authoritative for schema, signatures, deployed behavior
```

Full layer model, task budgets, and pitfalls: [`PROJECT_CONTEXT_STRUCTURE.md`](./PROJECT_CONTEXT_STRUCTURE.md) and [`requirements/AGENT_CONTEXT_ARCHITECTURE.md`](../requirements/AGENT_CONTEXT_ARCHITECTURE.md).

MCP implementation detail: [`CRM_KNOWLEDGE_MCP_ARCHITECTURE.md`](./CRM_KNOWLEDGE_MCP_ARCHITECTURE.md).

---

## Design decisions (why it looks like this)

### 1. Small chunks, not monoliths

**Decision:** Split knowledge at **section headings** (~4k chars), store `path`, `heading_path`, `content_hash`, FTS vector, and embedding per chunk.

**Why:** Retrieval returns 3–10 relevant excerpts with citations. Agents answer from excerpts and call `get_section` to expand — not from a single 80KB domain file.

**Chunking rules:** Prefer `SECTION:` headings; else `##` / `###` paths. Exclude registry stubs, changelogs, archives, and tiny pointer files (see MCP architecture doc).

### 2. Hybrid search (keyword + semantic)

**Decision:** Merge **full-text** and **vector** results with RRF (reciprocal rank fusion).

**Why:** Exact symbols (`bff_upsert_package`, table names) need FTS; conceptual questions (“how does receipt earn work?”) need embeddings. One pipeline serves both.

**Embeddings:** OpenAI `text-embedding-3-large` @ 1536; jobs queued and processed by Edge `embed-jobs` + cron (see MCP architecture).

### 3. Git is canonical for product truth (v2)

**Decision:** Author and review in `requirements/**/*.md`; run **reconcile** to sync `doc_knowledge_chunks`.

**Why:** Typed blocks in Postgres duplicated content and drifted from requirements. v2 removes hand-maintained “packs” as a second source of truth.

**Reconcile:** `scripts/doc-knowledge-reconcile.mjs` — hash-skip unchanged sections, deactivate removed sections, enqueue embed jobs for new/changed chunks.

### 4. Truth boundary

**Decision:** CRM Knowledge answers **what the product is supposed to do** from requirements. It does **not** replace:

- Live Supabase introspection (columns, RPC signatures, migrations)
- Application code in repos

Agents must cite MCP excerpts, then verify implementation details before changing code.

### 5. v1 typed blocks — what we learned (historical)

We first designed a **feature tree** + **typed Markdown blocks** in Postgres:

- Tables: `internal_knowledge_feature_items`, `internal_knowledge_blocks`, `internal_knowledge_type_templates`
- Metadata: `knowledge_type`, `perspectives[]`, `output_uses[]`, `scope`
- Later **consolidated** many types into four agent-facing types: `overview`, `rules`, `frontend_journey`, `technical_reference`

Original schema rationale and block-type catalog: [`FEATURE_KNOWLEDGE_DATABASE_PLAN.md`](./FEATURE_KNOWLEDGE_DATABASE_PLAN.md).

**Why we moved on:** Maintaining parallel curated blocks alongside requirements duplicated effort. v2 indexes the same narrative where engineers already write it. Some RPC names and legacy seeds may still exist in DB; **retrieval for agents is doc-index based** per [`CRM_KNOWLEDGE_MCP_ARCHITECTURE.md`](./CRM_KNOWLEDGE_MCP_ARCHITECTURE.md) (“Retired (v1)”).

**Principles that survived v1 → v2:**

- Put detail on the **narrowest feature** that stays accurate; parent items are positioning, not aggregations of every child.
- Store **intent, rules, journeys, constraints, pointers** — not full schemas (verify live).
- Filter by audience/use **before** generating decks, FE context, or implementation briefs (in v1 via enums; in v2 via doc structure + search).

### 6. Writing Principles (sibling system)

**Decision:** Copy craft lives in `Writing Principles/` + **Writing Principles MCP** (`writing_get_core_principles`, genre playbooks, `translation`).

**Why:** Product truth and writing style are different concerns. Content repos (e.g. `saalyn-web`) pair **CRM Knowledge** (facts) with **Writing Principles** (how to phrase) — never substitute one for the other.

### 7. Token economy

**Decision:** Promote **grep registry**, **grep-before-read**, and **batch independent tools** into always-applied rules; keep MCP write workflows requestable.

**Why:** Measured ~41% drop in read-burned tokens after registry + grep-first; sequential discovery replays entire prior context each turn.

---

## How agents should use it

| Question type | Start here |
|---------------|------------|
| “Do we have X?” / “How does Y work?” | `search_docs` → `get_section` on best hit |
| Sales journey / narrative color | `get_section` on `docs/PRODUCT_NARRATIVE.md` (not in default search corpus) |
| Table/RPC exists? | Grep `REGISTRY_SUPABASE.md` → Supabase MCP |
| Implement or fix | MCP excerpts + scoped requirement read + `pg_get_functiondef` only when editing |
| Marketing copy for website | CRM Knowledge + Writing Principles MCP + repo content workflow |

**MCP endpoint:** `https://crm-knowledge.onrender.com/mcp` (repo `Rocket-CRM/crm-knowledge`). Tools: `get_my_context`, `search_docs`, `get_section`.

---

## How humans maintain it

1. **Change product behavior** → edit authoritative `requirements/<Domain>.md` (four-section spine per `13-requirements-writing.mdc`).
2. **Update index** → run doc-knowledge reconcile (local tree with requirements; note gitignore caveats in MCP architecture).
3. **Schema/function changes** → migration + update domain doc + `CHANGELOG.md` + registry regenerate skill.
4. **Do not** treat `generated/internal-knowledge/**` or deprecated monolith indexes as retrieval surfaces.

---

## Related documents

| Doc | Role |
|-----|------|
| [`PROJECT_CONTEXT_STRUCTURE.md`](./PROJECT_CONTEXT_STRUCTURE.md) | Layer cake for this repo; skip-read list |
| [`CRM_KNOWLEDGE_MCP_ARCHITECTURE.md`](./CRM_KNOWLEDGE_MCP_ARCHITECTURE.md) | v2 corpus, tools, embeddings, reconcile |
| [`FEATURE_KNOWLEDGE_DATABASE_PLAN.md`](./FEATURE_KNOWLEDGE_DATABASE_PLAN.md) | v1 Postgres block schema (historical design reference) |
| [`requirements/AGENT_CONTEXT_ARCHITECTURE.md`](../requirements/AGENT_CONTEXT_ARCHITECTURE.md) | Portable 7-layer model + Supabase CRM mapping |
| [`requirements/domains/internal-knowledge.md`](../requirements/domains/internal-knowledge.md) | Domain reference for legacy `internal_knowledge_*` RPCs |

---

## Consumer repos

| Repo | Integration |
|------|-------------|
| **supabase-crm** | Canonical requirements + MCP index + Layer 0–4 rules |
| **saalyn-web** | `.cursor/rules/crm-knowledge-mcp.mdc`, content workflow — product facts via MCP; copy via Writing Principles |
| **crm-knowledge** | MCP server + reconcile workers |

When consumer rules mention `get_feature_context` / `search_semantic`, treat that as **v1**; align rules with v2 `search_docs` / `get_section` when updating agent config.
