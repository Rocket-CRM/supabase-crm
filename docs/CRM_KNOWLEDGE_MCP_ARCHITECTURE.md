# CRM Knowledge MCP Architecture (v2)

> Layer 2 in [`PROJECT_CONTEXT_STRUCTURE.md`](./PROJECT_CONTEXT_STRUCTURE.md). Product truth is git `requirements/**/*.md`; this service indexes and retrieves chunks.

## Purpose

Shared retrieval for Cursor agents and downstream tools over **canonical requirement docs** — not hand-maintained typed packs.

## Corpus

| Item | Value |
|------|--------|
| Source | `/requirements/**/*.md` (search + get_section). Also `docs/PRODUCT_NARRATIVE.md` for **get_section only** |
| Excluded | `REGISTRY_*`, `CHANGELOG.md`, `INDEX_FUNCTION.md`, `INDEX_DOMAIN.md`, `archive/**`, tiny pointer stubs |
| Chunking | Prefer `SECTION:` headings; else `##` / `###`; split ~4000 chars |
| Table | `public.doc_knowledge_chunks` |

## MCP tools

Hosted at `https://crm-knowledge.onrender.com/mcp` (repo `Rocket-CRM/crm-knowledge`).

- `get_my_context`
- `search_docs` — hybrid FTS (`doc_knowledge_search_fts`) + semantic (`doc_knowledge_search_semantic`) merged with RRF. **Default corpus is `requirements/` only** (null `path_prefix`). Narrative is not in this pile.
- `get_section` — `doc_knowledge_get_section`. Use path `docs/PRODUCT_NARRATIVE.md` + a heading for sales journey/explain. Also works on requirement paths.

Auth: `fn_validate_mcp_access_token`; scope `knowledge:read`.

## Embeddings

- Model: OpenAI `text-embedding-3-large` @ 1536
- Queue: `internal_knowledge_embedding_jobs` (shared name; jobs carry `table`)
- Worker: Edge Function `embed-jobs` → `doc_knowledge_finalize_embedding_job`
- Query embed: Edge Function `embed-text`
- Vault secret RPC: `internal_knowledge_runtime_secret` (name retained)

Cron `process-internal-knowledge-embeddings` runs `util.process_embeddings()` every 10s when **active**. Disable if OpenAI credits are exhausted to avoid 429 spam; re-enable after topping up.

## Reconcile (daily / manual)

```bash
cd scripts
# needs SUPABASE_URL + SUPABASE_SERVICE_ROLE_KEY
node doc-knowledge-reconcile.mjs
```

Hash-skip: unchanged `content_hash` rows are left alone (no re-embed). Removed sections are `is_active = false`.

Note: this repo’s `.gitignore` currently ignores most of `requirements/*` from GitHub. Until that changes, run reconcile from a machine that has the local requirements tree (not the stock GitHub Action alone).

## Retired (v1)

Typed packs in `internal_knowledge_blocks` / feature tree / authoring tools / Writing Principles domain in the same tables — removed. Writing craft lives under `Writing Principles/` and agent plugins.
