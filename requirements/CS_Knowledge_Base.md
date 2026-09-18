# CS Knowledge Base

Merchant articles and chunks for **RAG retrieval** before AI replies, plus **custom answers** that override generation for matched phrasings.

Owner surfaces: loyalty-admin **CS Knowledge**, `cs-ai-service` (`search_knowledge`), inbox content panel search

## Concept

**Knowledge source** — Synced or manual origin (URL, document, catalog) that can feed articles.

**Article** — Title, body, category, language, status, optional link to source.

**Embedding chunk** — System-generated slice with vector row for semantic search.

**Custom answer** — Article flagged to short-circuit the LLM when `question_patterns` match inbound text.

## Rules

- **Embeddings** — Never hand-written; regenerated on article create/update (old chunks removed first).
- **Custom answers** — Evaluated before LLM generation; higher `priority` wins; patterns required when `is_custom_answer` is true (BFF validation).
- **Retrieval** — Active articles only; `merchant_id` RLS isolates brands.
- **Transactional data** — Order/stock answers must use tools, not articles (`CS_AI_System.md`).
- **Status** — `draft` excluded from production retrieval; `archived` retained for audit only.

## Journeys

### Admin journey

| Knob | Effect |
| --- | --- |
| Source sync | Pulls external content into articles (`cs_bff_trigger_source_sync`) |
| Article status | Draft / active / archived in library and retrieval |
| Custom answer + patterns | Deterministic replies without LLM |
| Category / language | Filters for admin list and retrieval |

| Page | Owning repo | BFF / RPC |
| --- | --- | --- |
| **CS Knowledge** | loyalty-admin | `cs_bff_get_knowledge_*`, `cs_bff_upsert_knowledge_article`, `cs_bff_upsert_knowledge_source`, `cs_bff_bulk_update_articles`, deletes |
| **CS Inbox** content panel | loyalty-admin | `cs_bff_search_conversation_knowledge` |

1. Add **source** (optional) or create **article** manually.
2. Set **active** when ready; mark **custom answer** with example phrasings for top FAQs.
3. Trigger source sync when connector supports it.
4. Archive obsolete content (embeddings cascade delete).

### Member journey

1. Member asks question on channel.
2. Pipeline matches custom answer or retrieves chunks → reply in chat (member does not open admin library).
3. Public self-service KB `(planned)` — **`CS_Platform_Features.md`**.

## System

### Data model

| Table | Role |
| --- | --- |
| `cs_knowledge_sources` | `source_type`, sync status, config, article counts |
| `cs_knowledge_articles` | Content, category, language, `is_custom_answer`, `question_patterns`, `priority`, `status`, optional `source_id` |
| `cs_knowledge_embeddings` | `article_id`, chunk text, `embedding` vector(1536) |

### Functions

| Function | Role |
| --- | --- |
| `cs_fn_search_knowledge` | Vector similarity (precomputed embedding) |
| `cs_fn_search_knowledge_articles` | Text search fallback / admin |
| `cs_fn_match_custom_answer` | Pattern match on inbound message |
| `cs_bff_*` | CRUD, overview, categories, bulk status, source sync |
| `cs_bff_search_conversation_knowledge` | Agent assist search in inbox |

### Flows

**Embed pipeline** — Article write → queue (pgmq) → cron/edge (`embed-knowledge` pattern) → chunk ~500 tokens → OpenAI embed → insert rows.

**Runtime retrieval** — Embed question (or use text search) → top-K chunks → if custom answer hit, return fixed content; else inject chunks into LLM prompt (`CS_AI_Pipeline.md` prepare-context).

### External services

- OpenAI embeddings API (platform credential on Render/edge workers).
- MCP tool `search_knowledge` on `cs-ai-service`.

### Known gaps

- Exact edge function slug for embed job — confirm `REGISTRY_RENDER.md` / deploy list when wiring ops runbooks.
- Segment/platform-conditioned custom answers in JSONB — verify UI vs spec-only.

## Related

- **CS_AI_Pipeline.md** — prepare-context retrieval stage.
- **CS_Live_Assist.md** — Copilot search in thread.
- **CS_Analytics.md** — Knowledge gaps / unresolved questions.
- **CS_Procedures.md** — Step-level `data_needs` knowledge hints.
