begin;

with input_items as (
  select *
  from jsonb_to_recordset($seed_json$[{"id": "87b752db-5a56-5940-a160-dc9a5b88bcfa", "parent_slug": "writing-principles", "slug": "core-writing", "name": "Core Writing Principles", "item_type": "feature", "description": "Every structured writing task — proposals, slides, web copy, feature guides, emails. Pyramid logic, MECE, vertical/horizontal logic, specificity, limits.", "sort_order": 10, "metadata": {"knowledge_domain": "writing", "source_file": "CORE_WRITING_PRINCIPLES.md", "genre": "foundation", "universal": true, "cross_cutting": false, "generation_batch": "writing_principles_seed_20260530T011413Z"}, "aliases": ["core principles", "pyramid principle", "MECE", "structured writing", "writing foundation"], "is_active": true}, {"id": "a3a7fb20-40e1-50bb-b02f-a6e0a05c8ea1", "parent_slug": "writing-principles", "slug": "proposal-writing", "name": "Proposal Writing", "item_type": "feature", "description": "B2B proposals, RFP responses, SOWs. R/U/S/W framework: read requirements, understand context, structure, write sections.", "sort_order": 20, "metadata": {"knowledge_domain": "writing", "source_file": "PROPOSAL_WRITING_PRINCIPLES.md", "genre": "proposal", "universal": false, "cross_cutting": false, "generation_batch": "writing_principles_seed_20260530T011413Z"}, "aliases": ["proposal", "RFP", "RFP response", "SOW", "bid response", "requirement mapping"], "is_active": true}, {"id": "063c6fd9-de7c-544f-8a02-b54c8bb08699", "parent_slug": "writing-principles", "slug": "sales-slides", "name": "Sales Presentation Slides", "item_type": "feature", "description": "Sales decks, marketing presentations, buyer-facing slide narratives. One message per slide, decision story, proof, objections.", "sort_order": 30, "metadata": {"knowledge_domain": "writing", "source_file": "SALES_PRESENTATION_SLIDE_PRINCIPLES.md", "genre": "slides", "universal": false, "cross_cutting": false, "generation_batch": "writing_principles_seed_20260530T011413Z"}, "aliases": ["sales deck", "presentation", "pitch deck", "slides", "marketing deck"], "is_active": true}, {"id": "50e2f1ba-4124-54ed-b98a-a1a8ef10f785", "parent_slug": "writing-principles", "slug": "web-page-copy", "name": "Web Page Copy", "item_type": "feature", "description": "Routing parent only — read Which part to use before fetching a part slug. Do not load all four parts at once.", "sort_order": 40, "metadata": {"knowledge_domain": "writing", "source_file": "WEB_PAGE_COPY_PRINCIPLES.md", "genre": "web", "universal": false, "cross_cutting": false, "generation_batch": "writing_principles_seed_20260530T011413Z"}, "aliases": ["web copy", "website copy", "marketing site"], "is_active": true}, {"id": "91a9c890-e4ef-59f1-b613-d905a9159fe4", "parent_slug": "web-page-copy", "slug": "web-landing-copy", "name": "Web — Landing Page Copy", "item_type": "sub_feature", "description": "Product landing pages, homepage hero, feature LPs. 5-second clarity, customer-as-hero, CTAs, Thai/English voice.", "sort_order": 41, "metadata": {"knowledge_domain": "writing", "source_file": "WEB_PAGE_COPY_PRINCIPLES.md", "genre": "landing", "universal": false, "cross_cutting": false, "generation_batch": "writing_principles_seed_20260530T011413Z", "part": 1, "part_title": "Landing Page Copy"}, "aliases": ["landing page", "LP", "homepage", "hero section", "product page"], "is_active": true}, {"id": "9f8dc556-c6de-5773-ac93-5681044f690d", "parent_slug": "web-page-copy", "slug": "web-article-copy", "name": "Web — Blog & Articles", "item_type": "sub_feature", "description": "Blog posts, knowledge articles, thought leadership. Search journey, macro structure, E-E-A-T, consultant voice.", "sort_order": 42, "metadata": {"knowledge_domain": "writing", "source_file": "WEB_PAGE_COPY_PRINCIPLES.md", "genre": "article", "universal": false, "cross_cutting": false, "generation_batch": "writing_principles_seed_20260530T011413Z", "part": 2, "part_title": "Blog & Knowledge Articles"}, "aliases": ["blog", "article", "knowledge article", "thought leadership", "content marketing"], "is_active": true}, {"id": "77ae4d9e-d196-51d5-b39b-35774e1ec942", "parent_slug": "web-page-copy", "slug": "web-seo-strategy", "name": "Web — SEO Strategy", "item_type": "sub_feature", "description": "SEO strategy for landing and knowledge pages. Intent tiers T1–T7, on-page signals, technical SEO, flywheel.", "sort_order": 43, "metadata": {"knowledge_domain": "writing", "source_file": "WEB_PAGE_COPY_PRINCIPLES.md", "genre": "seo", "universal": false, "cross_cutting": false, "generation_batch": "writing_principles_seed_20260530T011413Z", "part": 3, "part_title": "SEO Strategy & On-Page Signals"}, "aliases": ["SEO", "on-page SEO", "keyword strategy", "search intent", "technical SEO"], "is_active": true}, {"id": "c8d9ef09-0322-530c-95ff-1493543537d4", "parent_slug": "web-page-copy", "slug": "web-internal-linking", "name": "Web — Internal Linking", "item_type": "sub_feature", "description": "Pillar-cluster architecture, LP target tiers, AI linking workflow, cross-language link rules.", "sort_order": 44, "metadata": {"knowledge_domain": "writing", "source_file": "WEB_PAGE_COPY_PRINCIPLES.md", "genre": "linking", "universal": false, "cross_cutting": false, "generation_batch": "writing_principles_seed_20260530T011413Z", "part": 4, "part_title": "Internal Linking"}, "aliases": ["internal linking", "pillar cluster", "link architecture", "site structure"], "is_active": true}, {"id": "4aca1897-2b21-59f8-950a-5e8c7a180045", "parent_slug": "writing-principles", "slug": "translation", "name": "Translation & Localization", "item_type": "feature", "description": "Add after genre playbook when output is Thai, JP, TW, or mixed EN/local. Localize-don't-translate, term policy, tone calibration.", "sort_order": 50, "metadata": {"knowledge_domain": "writing", "source_file": "TRANSLATION_PHILOSOPHY.md", "genre": "translation", "universal": false, "cross_cutting": true, "generation_batch": "writing_principles_seed_20260530T011413Z"}, "aliases": ["translation", "localization", "Thai copy", "Japanese copy", "Taiwanese copy", "localize"], "is_active": true}, {"id": "18eed625-1995-5832-bd9b-553347e1c00c", "parent_slug": "writing-principles", "slug": "feature-guide-writing", "name": "Feature Guide Writing", "item_type": "feature", "description": "CRM feature guides in requirements/feature-docs. 8-section template, multi-audience, route maps, status models.", "sort_order": 60, "metadata": {"knowledge_domain": "writing", "source_file": "FEATURE_GUIDE_WRITING_PRINCIPLES.md", "genre": "feature_guide", "universal": false, "cross_cutting": false, "generation_batch": "writing_principles_seed_20260530T011413Z"}, "aliases": ["feature guide", "product documentation", "help doc", "feature spec writing"], "is_active": true}]$seed_json$::jsonb) as x(
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
  from jsonb_to_recordset($seed_json$[]$seed_json$::jsonb) as x(
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
