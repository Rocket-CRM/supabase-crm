begin;

with input_items as (
  select *
  from jsonb_to_recordset($seed_json$[{"id": "0ff28b74-0100-5680-9f13-cd27fa53a74c", "parent_slug": null, "slug": "writing-principles", "name": "Writing Principles", "item_type": "domain", "description": "Consolidated writing craft playbooks for proposals, slides, web copy, localization, and feature guides.", "sort_order": 5, "metadata": {"knowledge_domain": "writing", "generation_batch": "writing_principles_seed_20260530T011413Z"}, "aliases": ["writing principles", "writing playbook", "copy principles"], "is_active": true}]$seed_json$::jsonb) as x(
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
