begin;

with input_items as (
  select *
  from jsonb_to_recordset($seed_json$[]$seed_json$::jsonb) as x(
    id uuid,
    parent_slug text,
    slug text,
    name text,
    item_type text,
    description text,
    sort_order integer,
    metadata jsonb,
    aliases text[],
    is_active boolean
  )
),
resolved_items as (
  select
    i.id,
    p.id as parent_id,
    i.slug,
    i.name,
    i.item_type::internal_knowledge_item_type as item_type,
    nullif(i.description, '') as description,
    i.sort_order,
    i.metadata,
    coalesce(i.aliases, '{}'::text[]) as aliases,
    coalesce(i.is_active, true) as is_active
  from input_items i
  left join public.internal_knowledge_feature_items p on lower(p.slug) = lower(i.parent_slug)
)
insert into public.internal_knowledge_feature_items (
  id, parent_id, slug, name, item_type, description, sort_order, metadata, aliases, is_active, updated_at
)
select id, parent_id, slug, name, item_type, description, sort_order, metadata, aliases, is_active, now()
from resolved_items
on conflict (id) do update set
  parent_id = excluded.parent_id,
  slug = excluded.slug,
  name = excluded.name,
  item_type = excluded.item_type,
  description = excluded.description,
  sort_order = excluded.sort_order,
  metadata = public.internal_knowledge_feature_items.metadata || excluded.metadata,
  aliases = excluded.aliases,
  is_active = excluded.is_active,
  updated_at = now();

with input_blocks as (
  select *
  from jsonb_to_recordset($seed_json$[{"id": "aa593046-43b9-5eaa-9dae-724b45b904ca", "feature_slug": "web-page-copy", "title": "About this document", "content": "Single source of truth for **Rocket web content** — product landing pages, SEO blog/knowledge articles, on-page SEO signals, and internal link architecture.\n\n**Read first:** `CORE_WRITING_PRINCIPLES.md` for pyramid structure, MECE, same-level grouping, and specificity rules that apply across all formats.\n\n**Localization:** Non-Thai markets → `TRANSLATION_PHILOSOPHY.md` (separate doc).", "content_format": "markdown", "knowledge_type": "overview", "perspectives": ["general", "marketing"], "output_uses": ["agent_context", "marketing_content", "proposal_content", "slide_generation"], "scope": "general", "source_ref": "Writing Principles/WEB_PAGE_COPY_PRINCIPLES.md#about-this-document", "metadata": {"genre": "web", "source_file": "WEB_PAGE_COPY_PRINCIPLES.md", "section_anchor": "about-this-document", "feature_slug": "web-page-copy", "generation_batch": "writing_principles_seed_20260530T011413Z", "content_sha256": "6b6776e070b4161c8df697c06096399fa961fecbb925e5fffeedc6ebc827d0dd", "truncated": false}, "is_active": true}, {"id": "329c68a8-c090-5b4b-a92b-0b4f4b72e711", "feature_slug": "web-page-copy", "title": "Web Page Copy — Overview", "content": "**When to use:** Routing parent only — read Which part to use before fetching a part slug. Do not load all four parts at once.\n**Source:** `WEB_PAGE_COPY_PRINCIPLES.md`\n**Genre:** `web`\n\nLanding pages, blog articles, SEO, and internal linking", "content_format": "markdown", "knowledge_type": "overview", "perspectives": ["general", "marketing"], "output_uses": ["agent_context", "marketing_content", "proposal_content", "slide_generation"], "scope": "general", "source_ref": "Writing Principles/WEB_PAGE_COPY_PRINCIPLES.md", "metadata": {"genre": "web", "source_file": "WEB_PAGE_COPY_PRINCIPLES.md", "section_anchor": "overview", "feature_slug": "web-page-copy", "generation_batch": "writing_principles_seed_20260530T011413Z", "content_sha256": "63145af38cdbda2a2fc2769f820d4e39eb715cc1d6380dff8a70bc34f91229d3", "truncated": false}, "is_active": true}, {"id": "541ddee2-05ff-5933-a43d-4bb5c39a5a0e", "feature_slug": "web-page-copy", "title": "Which part to use", "content": "| Page type | Primary part | Also read |\n|-----------|--------------|-----------|\n| Product landing page | **Part 1** — Landing Page Copy | Part 3 (SEO signals), Part 4 (links in/out) |\n| Blog / knowledge article | **Part 2** — Blog & Knowledge Articles | Part 3, Part 4 |\n| SEO planning / on-page audit | **Part 3** — SEO Strategy | Part 1 or 2 depending on page type |\n| Link architecture / new article workflow | **Part 4** — Internal Linking | Part 3 (clusters, intent tiers) |\n\n---", "content_format": "markdown", "knowledge_type": "overview", "perspectives": ["general", "marketing"], "output_uses": ["agent_context", "marketing_content", "proposal_content", "slide_generation"], "scope": "general", "source_ref": "Writing Principles/WEB_PAGE_COPY_PRINCIPLES.md#which-part-to-use", "metadata": {"genre": "web", "source_file": "WEB_PAGE_COPY_PRINCIPLES.md", "section_anchor": "which-part-to-use", "feature_slug": "web-page-copy", "generation_batch": "writing_principles_seed_20260530T011413Z", "content_sha256": "b8b5104129c8fd1b94ae60f4585ea649e3f08cd194730149e1b8f0df60f6d145", "truncated": false}, "is_active": true}]$seed_json$::jsonb) as x(
    id uuid,
    feature_slug text,
    title text,
    content text,
    content_format text,
    knowledge_type text,
    perspectives text[],
    output_uses text[],
    scope text,
    source_ref text,
    metadata jsonb,
    is_active boolean
  )
),
resolved_blocks as (
  select
    b.id,
    f.id as feature_item_id,
    b.title,
    b.content,
    b.content_format,
    b.knowledge_type::internal_knowledge_type as knowledge_type,
    b.perspectives::internal_knowledge_perspective[] as perspectives,
    b.output_uses::internal_knowledge_output_use[] as output_uses,
    b.scope::internal_knowledge_scope as scope,
    b.source_ref,
    b.metadata,
    coalesce(b.is_active, true) as is_active
  from input_blocks b
  join public.internal_knowledge_feature_items f on lower(f.slug) = lower(b.feature_slug)
)
insert into public.internal_knowledge_blocks (
  id, feature_item_id, title, content, content_format, knowledge_type,
  perspectives, output_uses, scope, source_ref, metadata, is_active, updated_at
)
select
  id, feature_item_id, title, content, content_format, knowledge_type,
  perspectives, output_uses, scope, source_ref, metadata, is_active, now()
from resolved_blocks
on conflict (id) do update set
  feature_item_id = excluded.feature_item_id,
  title = excluded.title,
  content = excluded.content,
  content_format = excluded.content_format,
  knowledge_type = excluded.knowledge_type,
  perspectives = excluded.perspectives,
  output_uses = excluded.output_uses,
  scope = excluded.scope,
  source_ref = excluded.source_ref,
  metadata = public.internal_knowledge_blocks.metadata || excluded.metadata,
  is_active = excluded.is_active,
  updated_at = now();

commit;
