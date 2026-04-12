# CS Knowledge Base — List + Config

## What This Is

Two-level management for the AI agent's knowledge:

- **Knowledge Sources** — Where knowledge comes from (uploaded documents, crawled URLs, product catalog syncs, manual entries)
- **Knowledge Articles** — Individual pieces of content the AI searches when answering questions
- **Custom Answers** — Admin-defined exact answers that override AI-generated responses for specific question patterns

The AI in this project should use its own judgment for what UI structure, navigation hierarchy, and content editing experience produce the best UX for **managing an AI knowledge base used for customer service**. Study how Intercom's Fin knowledge management, Zendesk Guide, or Notion's content management approach this — then decide the best structure.

---

## FE Project Context

| Layer | Tech |
|---|---|
| Framework | Next.js 16 (App Router, React 19) |
| UI | Shopify Polaris v13 (the only component library) |
| Rich text | TipTap (for article content editing) |
| Backend | Complex operations via `supabase.rpc()`. Simple reads/writes via `supabase.from()` (RLS handles merchant scoping). |
| Auth | Supabase Auth, JWT carries merchant context |
| Forms | `react-hook-form` + `zod` |

### Routes

```
src/app/(admin)/cs-knowledge/                    → Main knowledge management page
src/app/(admin)/cs-knowledge/sources/             → Knowledge sources list
src/app/(admin)/cs-knowledge/sources/[id]/        → Source config (sync settings)
src/app/(admin)/cs-knowledge/articles/[id]/       → Article create/edit
src/app/(admin)/cs-knowledge/custom-answers/      → Custom answers list
src/app/(admin)/cs-knowledge/custom-answers/[id]/ → Custom answer create/edit
```

The AI should decide whether these are separate routes or sections within a single page — whatever produces the best content management experience.

---

## Backend Connection — Tables & RPCs

### Core Tables

**`cs_knowledge_sources`** — Source lifecycle tracking

| Column | Type | Notes |
|---|---|---|
| `id` | uuid PK | |
| `merchant_id` | uuid FK | |
| `source_type` | text | `document`, `url`, `catalog`, `api`, `manual` |
| `name` | text | "Product Catalog", "Return Policy PDF" |
| `config` | jsonb | URL, file path, API endpoint, sync schedule, auth |
| `sync_status` | text | `synced`, `syncing`, `failed`, `pending` |
| `last_synced_at` | timestamptz | |
| `article_count` | int | Number of articles generated from this source |
| `is_active` | boolean | |
| `created_at` | timestamptz | |
| `updated_at` | timestamptz | |

**`cs_knowledge_articles`** — Content + custom answers

| Column | Type | Notes |
|---|---|---|
| `id` | uuid PK | |
| `merchant_id` | uuid FK | |
| `title` | text | |
| `content` | text | Full article body |
| `category` | text | `products`, `policies`, `shipping`, `returns`, `faq` |
| `language` | text | |
| `source_id` | uuid FK → cs_knowledge_sources | Nullable — manual articles have no source |
| `source_type` | text | `document`, `url`, `catalog`, `manual` |
| `source_url` | text | Nullable |
| `status` | text | `active`, `draft`, `archived` |
| `is_custom_answer` | boolean | If true, overrides AI responses for matching questions |
| `question_patterns` | text[] | For custom answers — trigger phrases (10+ example variations) |
| `priority` | int | Higher = checked first |
| `created_at` | timestamptz | |
| `updated_at` | timestamptz | |

**`cs_knowledge_embeddings`** — Auto-generated, never manually managed

Embeddings are generated automatically by a Supabase pipeline when articles are inserted/updated. The FE never reads or writes this table directly.

### RPCs — Knowledge Sources

| RPC | Purpose | Notes |
|---|---|---|
| `cs_bff_get_knowledge_sources` | List all sources | Returns source list with sync_status, article_count, last_synced_at |
| `cs_bff_get_knowledge_source` | Get source detail | Params: source_id. Returns full config for edit. |
| `cs_bff_upsert_knowledge_source` | Create/update source | Params: source payload (type, name, config, is_active) |
| `cs_bff_trigger_source_sync` | Manually trigger sync | Params: source_id. Kicks off background sync job. |
| `cs_bff_delete_knowledge_source` | Delete source + articles | Params: source_id. Cascades to articles and embeddings. |

### RPCs — Knowledge Articles

| RPC | Purpose | Notes |
|---|---|---|
| `cs_bff_get_knowledge_articles` | List articles | Supports: search by title/content, filter by category, filter by source, filter by status, pagination |
| `cs_bff_get_knowledge_article` | Get article for edit | Params: article_id or null (for new). Returns full content. |
| `cs_bff_upsert_knowledge_article` | Create/update article | Params: article payload. Backend auto-triggers embedding regeneration. |
| `cs_bff_bulk_update_articles` | Bulk status change | Params: article_ids[], new_status. For bulk archive/activate. |
| `cs_bff_get_knowledge_categories` | List categories | Returns available categories for filtering/assignment |

### RPCs — Custom Answers

| RPC | Purpose | Notes |
|---|---|---|
| `cs_bff_get_custom_answers` | List custom answers | Returns articles where is_custom_answer=true, with question_patterns |
| `cs_bff_upsert_custom_answer` | Create/update custom answer | Params: answer content + question_patterns (list of trigger phrases) + conditions (optional: by customer segment, platform, language) |

**Direct CRUD (use `supabase.from()`):**
- Knowledge sources: all CRUD via `supabase.from('cs_knowledge_sources')`
- List articles: `supabase.from('cs_knowledge_articles').select('*').eq('merchant_id', merchantId)` with filters
- Get single article: `supabase.from('cs_knowledge_articles').select('*').eq('id', articleId).single()`
- Delete article: `supabase.from('cs_knowledge_articles').delete().eq('id', articleId)`
- Bulk status update: `supabase.from('cs_knowledge_articles').update({ status: newStatus }).in('id', articleIds)`
- List custom answers: `supabase.from('cs_knowledge_articles').select('*').eq('is_custom_answer', true)`
- Categories: `supabase.from('cs_knowledge_articles').select('category').neq('category', null)` then deduplicate client-side

**RPCs (use `supabase.rpc()`):**
- `cs_bff_upsert_knowledge_article` — validates custom answer patterns

---

## Key Domain Concepts the UI Must Support

### 1. Knowledge Sources

Sources feed articles into the knowledge base:
- **Document upload** — PDF, DOCX, TXT, CSV. Uploaded file is parsed, chunked into articles, and embedded.
- **Website URL** — Crawled periodically. Pages become articles.
- **Product catalog sync** — Imports from marketplace (product descriptions become articles). Syncs on schedule.
- **Manual entries** — Admin writes articles directly.
- **API connector** — Pulls from external CMS.

Each source has a sync lifecycle: pending → syncing → synced/failed. Show sync status, last synced time, article count per source.

### 2. Articles

Standard content management: title, body (rich text), category, language, status (active/draft/archived). Articles from synced sources are read-only or editable depending on source type.

Categories organize articles: Products, Policies, Shipping, Returns, FAQ, plus merchant-custom categories.

### 3. Custom Answers (Override AI)

For specific questions, admin writes an exact answer. These have HIGHER priority than AI-generated responses. When a customer asks a matching question, the custom answer is used verbatim instead of AI generation.

Key fields:
- **Question patterns** — 10+ example phrasings of the question ("What is your return policy?", "How do I return something?", "Can I get a refund?", etc.)
- **Answer content** — Rich text with images, links, buttons
- **Conditions** — Optional: different answer by customer segment, platform, or language
- **Priority** — When multiple custom answers match, highest priority wins

### 4. Knowledge Gap Detection

The analytics/AI surfaces questions the AI couldn't answer (from conversation data). The UI should provide a path from "unanswered question" → "create article" or "create custom answer" with the question pre-filled.

---

## Key UX Requirements

1. The main page should give a clear overview: how many sources, articles, custom answers. Health indicators (any sources failing sync? stale content?).

2. Article editor should feel like writing in a CMS — rich text, images, categorization. For custom answers, the question patterns editor is critical (easily add/remove example phrasings).

3. Source management should clearly show sync status and make it easy to trigger manual re-sync.

4. Bulk operations: select multiple articles to archive, change category, change status.

---

## What NOT to Build (Backend Handles These)

- Embedding generation — automatic pipeline triggered on article insert/update
- Semantic search execution — backend handles pgvector similarity search at query time
- Content chunking — backend chunks long articles into embedding-sized pieces
- Source crawling/scraping — backend job handles URL crawling and document parsing
