# Project Context Structure

How agents (and humans) should retrieve context in this repo — which layer to use, in what order, and when to stop.

**Principle:** Each layer is cheaper and more stable than the one below it. Descend only when the layer above cannot answer the question. Discovery that does not converge burns tokens on every subsequent turn via cache replay.

---

## Context layers (top → bottom)

```
┌─────────────────────────────────────────────────────────────┐
│  Layer 0 — Cursor rules (.cursor/rules/)                    │
│  Hard laws, routing, stop conditions, conventions           │
└──────────────────────────┬──────────────────────────────────┘
                           │ route by task type
┌──────────────────────────▼──────────────────────────────────┐
│  Layer 1 — Registries (grep only)                           │
│  requirements/REGISTRY_SUPABASE.md  — tables, functions, T  │
│  requirements/REGISTRY_RENDER.md    — edge fns, queues, C   │
│  requirements/domains/_index.md     — domain slug → doc     │
└──────────────────────────┬──────────────────────────────────┘
                           │ names + locations
┌──────────────────────────▼──────────────────────────────────┐
│  Layer 2 — CRM Knowledge MCP (requirements doc-index)       │
│  search_docs → get_section (chunks of requirements/*.md)    │
└──────────────────────────┬──────────────────────────────────┘
                           │ cited excerpts; deepen if needed
┌──────────────────────────▼──────────────────────────────────┐
│  Layer 3 — Requirement docs (grep + scoped read)            │
│  requirements/<Domain>.md — same corpus; use when MCP miss  │
│  Never full-read files >30KB — see 12-doc-search.mdc        │
└──────────────────────────┬──────────────────────────────────┘
                           │ implementation detail
┌──────────────────────────▼──────────────────────────────────┐
│  Layer 4 — Live Supabase MCP (schema / deployed truth)      │
│  information_schema, pg_proc signatures, apply_migration      │
│  Function bodies (pg_get_functiondef) — build/fix only      │
└─────────────────────────────────────────────────────────────┘
```

### Layer 1 — Registries

| File | Contents | Access |
|---|---|---|
| `REGISTRY_SUPABASE.md` | Tables (`T:`), functions (`F:`), triggers (`X:`) by domain | `rg` / Grep — never Read whole file |
| `REGISTRY_RENDER.md` | Edge functions (`E:`), crons (`C:`), queues (`Q:`), Render (`R:`) | Grep |
| `domains/_index.md` | Domain keyword → slug → authoritative doc | Grep |

Regenerated: `REGISTRY_SUPABASE.md` via `.cursor/skills/registry-regenerate/SKILL.md` after schema/function changes.

### Layer 2 — CRM Knowledge MCP

Product and feature questions default here **before** full-reading requirement docs or function bodies. Corpus = chunked `requirements/**/*.md`.

| Tool | When |
|---|---|
| `search_docs` | Default hybrid FTS + semantic search over chunks |
| `get_section` | Expand a known path/heading (+ neighbors) |

**Not a retrieval surface:** `generated/internal-knowledge/**` (obsolete seed artifacts). Writing craft = `Writing Principles/` files / agent plugins, not this MCP.

### Layer 3 — Requirement docs

Authoritative business rules and contracts. Domain docs follow the four-section spine (`13-requirements-writing.mdc`); address subsections as `H2 > H3` via `get_section`. **Enrichment program:** `workflows/requirements-doc-enrichment/REFERENCE.md` (one domain per thread; prompts in `DOMAIN_THREADS.md`). Access protocol:

1. Grep headings / keywords (`12-doc-search.mdc`)
2. Read with `offset` + `limit` (typically 30–80 lines)
3. Stop at next H2

Hook-enforced ban on full-read: `INDEX_FUNCTION.md`, large `<Domain>.md` files, `REGISTRY_SUPABASE.md`.

### Layer 4 — Live Supabase MCP

Project ID: `wkevmsedchftztoolkmi`.

| Need | Query type |
|---|---|
| Column exists / type | `information_schema.columns` with `table_name` + optional `column_name` filter |
| Function exists / args | `pg_get_function_arguments` — not full body |
| Deploy schema change | `apply_migration` |
| Function logic | `pg_get_functiondef` — **only** when editing that function or a bug pins it after Layer 3 |

---

## Task types and retrieval budgets

| Task type | Layers typically needed | Max discovery turns | Rule |
|---|---|---|---|
| Product Q&A ("Do we have X?") | 1 → 2 → optional 4 (one column check) | 2 | `20-discovery-discipline.mdc` |
| Explain / analyze | 1 → 2 → 3 → optional 4 (signature) | 3 | `08-context-lookup.mdc` |
| Schema-only ("add column for now") | 4 (`apply_migration` + verify) | 1 | `20-discovery-discipline.mdc`, `09-db-conventions.mdc` |
| Build / fix / modify | Full 1–4 per `08-context-lookup.mdc` | 3 before checkpoint | `08-context-lookup.mdc` |

**Turn budget:** After the max turns for the task class, stop and present — do not run a forensic audit to confirm absence.

---

## Skip-read and forbidden paths

Never use as automatic retrieval (unless user names the path or task is scoped to it):

| Path | Why |
|---|---|
| `requirements/INDEX_FUNCTION.md` | Deprecated ~100KB artifact |
| `requirements/INDEX_DOMAIN.md` | Deprecated monolith |
| `generated/internal-knowledge/**` | CRM Knowledge write artifacts — use MCP |
| `docs/PRODUCT_NARRATIVE.md` | Derived sales narrative; canonical feature identity lives in Supabase `internal_product_*` |
| `.cursor/plans/*.plan.md` | Scratchpads |
| `Component prompts/**`, `exports/**`, client proposals | One-offs |

See full list: `08-context-lookup.mdc` § Skip-Read List.

---

## Cursor rules map

| Rule | Role |
|---|---|
| `00-core.mdc` | Hard laws, discovery imperatives, routing map |
| `08-context-lookup.mdc` | 4-step procedure, SQL templates, workflows |
| `12-doc-search.mdc` | Grep-first access to large requirement docs |
| `13-requirements-writing.mdc` | Canonical domain-doc spine (Concept → Rules → Journeys → System) |
| `15-crm-knowledge-mcp.mdc` | CRM Knowledge retrieval order |
| `16-tool-batching.mdc` | Parallel tools, MCP result hygiene |
| `17-thread-checkpoint.mdc` | Long-thread handoff at 15 turns / 80 tool calls |
| `20-discovery-discipline.mdc` | Task classification, stop conditions, forbidden discovery |

Always-applied: `00`, `12`, `14`, `15`, `16`, `17`, `18`, `20`.

Requestable (load when task matches): `08`, `09`, `10`, `11`, `06`, etc. — see routing table in `00-core.mdc`.

---

## Thread phase separation

Discovery and implementation should not share a long context window.

| Phase | Typical tools | Risk if mixed |
|---|---|---|
| Discovery / Q&A | CRM Knowledge, registry grep, light SQL | Large MCP dumps accumulate |
| Implementation | `apply_migration`, targeted function edits | Replays all discovery dumps every turn |

**Recommendation:** After a heavy discovery phase (>5 tool calls or any `pg_get_functiondef`), start a **fresh thread** for implementation. Attach a short handoff (answer + decision + next step) or a checkpoint file from `17-thread-checkpoint.mdc`.

---

## Case study — traffic source Q&A (what not to do)

A thread asked: *"Do we have traffic source URL param capture on signup?"* then *"Add acquisition_source column."*

| What happened | Cost driver |
|---|---|
| 19 discovery turns before answering Q1 | Each turn replayed prior MCP results |
| 10× `pg_get_functiondef` | Full bodies in cache for rest of thread |
| Grep on `seed.json` (1.4 MB) | Wrong layer — CRM Knowledge MCP suffices |
| `get_feature_tree` + grep dump | Should use `resolve_feature_term` |
| Q2 auto-wired chokepoint + 4 functions | User asked for column only ("for now") |

**Correct path:** Turn 1 — CRM Knowledge + registry grep. Turn 2 — `user_accounts` column check. Answer. Q2 — single `apply_migration`. ~5–8 tool calls total.

---

## Related docs

- `docs/CRM_KNOWLEDGE_MCP_ARCHITECTURE.md` — MCP server design
- `docs/CRM_PROJECT_CS_ADJUSTMENTS.md` — historical workflow upgrade spec (superseded in part by current rules)
- `requirements/CHANGELOG.md` — post-change audit trail
