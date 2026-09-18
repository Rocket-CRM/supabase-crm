# CS Knowledge Base

> Per-domain reference. Read ONLY when working on this domain. For the keyword → file map, see `_index.md`.

**Keywords:** knowledge, article, embedding, faq, semantic_search, rag, vector, pgvector, chunk, cs_knowledge_articles, cs_knowledge_embeddings, source_type, search_knowledge_articles

**Source:** `CS_Knowledge_Base.md`

**Tables:** `cs_knowledge_articles`, `cs_knowledge_embeddings`

| Function | Type | Purpose |
|---|---|---|
| `cs_bff_get_knowledge_articles` | BFF | List articles with filtering (admin) |
| `cs_bff_upsert_knowledge_article` | BFF | Create or update article (triggers re-embedding) |
| `cs_bff_get_knowledge_article` | BFF | Get single article |
| `cs_bff_get_knowledge_categories` | BFF | List distinct categories |
| `cs_bff_get_knowledge_overview` | BFF | Dashboard summary stats |
| `cs_bff_get_knowledge_sources` | BFF | List knowledge sources |
| `cs_bff_upsert_knowledge_source` | BFF | Create/update knowledge source |
| `cs_bff_delete_knowledge_article` | BFF | Delete article |
| `cs_bff_delete_knowledge_source` | BFF | Delete knowledge source |
| `cs_fn_search_knowledge` | Backend | pgvector semantic search for AI — accepts embedding vector, returns top K chunks |
| `cs_fn_search_knowledge_articles` | Backend | Text-based search for human agents during conversations — title/content/category matching |
| `cs_fn_match_custom_answer` | Backend | **Deprecated** — replaced by `cs_fn_match_resource` on `resource_content` |

**Key Business Rules (summary):**
- Knowledge = reference material for both AI and human agents (never sent directly to customer)
- Custom answers migrated to `resource_content` as quick_replies (see Resource Content domain)
- `cs_fn_match_custom_answer` deprecated — use `cs_fn_match_resource` instead
- AI uses `cs_fn_search_knowledge` (embedding-based semantic search)
- Human agents use `cs_fn_search_knowledge_articles` (text-based search during conversations)
- Embedding pipeline: article change → trigger → pgmq → edge function → OpenAI → pgvector
- Only `status = 'active'` articles are searchable
- Article updates trigger automatic re-embedding (old chunks deleted, new created)

---
