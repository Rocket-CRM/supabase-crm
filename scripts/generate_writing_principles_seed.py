#!/usr/bin/env python3
"""Generate reviewable seed data for Writing Principles in internal_knowledge_* tables.

Reads markdown from Writing Principles/ and emits:
- seed.json: deterministic feature_items and knowledge_blocks
- load.sql + load-chunks/: transactional upsert SQL for approved Supabase load
- audit.md: source coverage, counts, and review notes

Git source of truth: Writing Principles/*.md
Separate UUID namespace from CRM feature knowledge seed.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import re
import textwrap
import uuid
from dataclasses import dataclass
from datetime import datetime, timezone
from pathlib import Path
from typing import Iterable


WRITING_UUID_NAMESPACE = uuid.UUID("a3f8c2e1-9b4d-5a7e-8c1f-2d6e9a0b3c4f")

WRITING_DIR = "Writing Principles"
FEATURE_TREE_REL = "generated/writing-principles/feature-tree.json"

KNOWLEDGE_TYPES = {"overview", "rules"}
PERSPECTIVES = {"general", "marketing", "sales", "product", "customer_success"}
OUTPUT_USES = {
    "agent_context",
    "slide_generation",
    "proposal_content",
    "marketing_content",
}
SCOPES = {"general"}

WEB_PART_PATTERN = re.compile(r"^# Part (\d+) — (.+)$", re.M)
PROPOSAL_SECTION_PATTERN = re.compile(r"^# Section \d+ — ", re.M)

DEFAULT_OUTPUT_USES = sorted(OUTPUT_USES)
DEFAULT_PERSPECTIVES = ["general", "marketing", "sales"]


@dataclass(frozen=True)
class Section:
    level: int
    title: str
    content: str
    start_line: int


@dataclass(frozen=True)
class FeatureSpec:
    slug: str
    name: str
    item_type: str
    parent_slug: str | None
    sort_order: int
    source_file: str
    genre: str
    when_to_use: str
    aliases: list[str]
    universal: bool = False
    cross_cutting: bool = False
    source_part: int | None = None
    source_part_title: str | None = None


def stable_uuid(kind: str, key: str) -> str:
    return str(uuid.uuid5(WRITING_UUID_NAMESPACE, f"{kind}:{key}"))


def read_text(path: Path) -> str:
    return path.read_text(encoding="utf-8", errors="replace")


def load_feature_tree(path: Path) -> tuple[dict, list[FeatureSpec]]:
    raw = json.loads(path.read_text(encoding="utf-8"))
    specs: list[FeatureSpec] = []
    for item in raw["items"]:
        specs.append(
            FeatureSpec(
                slug=item["slug"],
                name=item["name"],
                item_type=item["item_type"],
                parent_slug=item.get("parent_slug"),
                sort_order=item["sort_order"],
                source_file=item["source_file"],
                genre=item["genre"],
                when_to_use=item["when_to_use"],
                aliases=list(item.get("aliases", [])),
                universal=bool(item.get("universal")),
                cross_cutting=bool(item.get("cross_cutting")),
                source_part=item.get("source_part"),
                source_part_title=item.get("source_part_title"),
            )
        )
    return raw, specs


def parse_sections(text: str, levels: Iterable[int] = (2,)) -> list[Section]:
    wanted = set(levels)
    lines = text.splitlines()
    matches: list[tuple[int, int, str]] = []
    for index, line in enumerate(lines):
        match = re.match(r"^(#{1,6})\s+(.+?)\s*$", line)
        if match and len(match.group(1)) in wanted:
            matches.append((index, len(match.group(1)), match.group(2).strip()))

    sections: list[Section] = []
    for pos, (start, level, title) in enumerate(matches):
        end = matches[pos + 1][0] if pos + 1 < len(matches) else len(lines)
        content = "\n".join(lines[start + 1 : end]).strip()
        sections.append(Section(level=level, title=title, content=content, start_line=start + 1))
    return sections


def split_web_parts(text: str) -> dict[int, str]:
    matches = list(WEB_PART_PATTERN.finditer(text))
    if not matches:
        return {}
    parts: dict[int, str] = {}
    for index, match in enumerate(matches):
        part_num = int(match.group(1))
        start = match.start()
        end = matches[index + 1].start() if index + 1 < len(matches) else len(text)
        parts[part_num] = text[start:end].strip()
    return parts


def split_proposal_sections(text: str) -> list[tuple[str, str]]:
    """Return (section_title, section_body) for each # Section N block."""
    lines = text.splitlines()
    section_starts: list[tuple[int, str]] = []
    for index, line in enumerate(lines):
        if PROPOSAL_SECTION_PATTERN.match(line):
            section_starts.append((index, line.lstrip("# ").strip()))

    chunks: list[tuple[str, str]] = []
    for pos, (start, title) in enumerate(section_starts):
        end = section_starts[pos + 1][0] if pos + 1 < len(section_starts) else len(lines)
        body = "\n".join(lines[start:end]).strip()
        chunks.append((title, body))
    return chunks


def first_paragraph(markdown: str, limit: int = 320) -> str:
    cleaned = re.sub(r"```.*?```", "", markdown, flags=re.S)
    for para in re.split(r"\n\s*\n", cleaned):
        para = re.sub(r"[*_`>#|]", "", para).strip()
        para = re.sub(r"\s+", " ", para)
        if len(para) > 40:
            return para[:limit].rstrip()
    return ""


def clamp_content(content: str, limit: int = 7000) -> tuple[str, bool]:
    content = content.strip()
    if len(content) <= limit:
        return content, False
    truncated = content[:limit].rsplit("\n", 1)[0].rstrip()
    return truncated + "\n\n_Source section truncated in seed; see `source_ref` for full text._", True


def anchor_slug(title: str) -> str:
    value = title.lower().strip()
    value = re.sub(r"[^a-z0-9]+", "-", value)
    return re.sub(r"-+", "-", value).strip("-")


def source_ref(rel_path: str, section: Section | None = None) -> str:
    if section:
        return f"{rel_path}#{anchor_slug(section.title)}"
    return rel_path


def genre_perspectives(genre: str) -> list[str]:
    if genre in {"proposal"}:
        return ["general", "sales"]
    if genre in {"slides"}:
        return ["general", "marketing", "sales"]
    if genre in {"landing", "article", "seo", "linking", "web"}:
        return ["general", "marketing"]
    if genre in {"translation"}:
        return ["general", "marketing"]
    if genre in {"feature_guide"}:
        return ["general", "product", "customer_success"]
    return DEFAULT_PERSPECTIVES


def block_mapping(title: str, is_intro: bool = False) -> str:
    lower = title.lower()
    if is_intro or "purpose" in lower or "about this document" in lower or "which part" in lower:
        return "overview"
    return "rules"


class SeedBuilder:
    def __init__(self, root: Path, batch: str, tree_meta: dict):
        self.root = root
        self.batch = batch
        self.tree_meta = tree_meta
        self.items: dict[str, dict] = {}
        self.blocks: dict[str, dict] = {}
        self.source_inventory: list[dict] = []
        self.review_notes: list[str] = []

    def add_item(self, spec: FeatureSpec) -> None:
        metadata = {
            "knowledge_domain": self.tree_meta.get("knowledge_domain", "writing"),
            "source_file": spec.source_file,
            "genre": spec.genre,
            "universal": spec.universal,
            "cross_cutting": spec.cross_cutting,
            "generation_batch": self.batch,
        }
        if spec.source_part is not None:
            metadata["part"] = spec.source_part
            metadata["part_title"] = spec.source_part_title

        self.items[spec.slug] = {
            "id": stable_uuid("feature_item", spec.slug),
            "parent_slug": spec.parent_slug,
            "slug": spec.slug,
            "name": spec.name,
            "item_type": spec.item_type,
            "description": spec.when_to_use,
            "sort_order": spec.sort_order,
            "metadata": metadata,
            "aliases": spec.aliases,
            "is_active": True,
        }

    def add_block(
        self,
        feature_slug: str,
        title: str,
        content: str,
        knowledge_type: str,
        perspectives: list[str],
        source: str,
        metadata: dict,
    ) -> None:
        content, truncated = clamp_content(content)
        if not content.strip() or knowledge_type not in KNOWLEDGE_TYPES:
            return

        perspectives = sorted(set(p for p in perspectives if p in PERSPECTIVES)) or ["general"]
        block_metadata = {
            **metadata,
            "feature_slug": feature_slug,
            "generation_batch": self.batch,
            "content_sha256": hashlib.sha256(content.encode("utf-8")).hexdigest(),
            "truncated": truncated,
        }
        block_key = "|".join([feature_slug, knowledge_type, source, title])
        block_id = stable_uuid("knowledge_block", block_key)
        self.blocks[block_id] = {
            "id": block_id,
            "feature_slug": feature_slug,
            "title": title.strip()[:180],
            "content": content,
            "content_format": "markdown",
            "knowledge_type": knowledge_type,
            "perspectives": perspectives,
            "output_uses": DEFAULT_OUTPUT_USES,
            "scope": "general",
            "source_ref": source,
            "metadata": block_metadata,
            "is_active": True,
        }

    def add_domain_and_protocol(self) -> None:
        domain_slug = self.tree_meta["domain_slug"]
        protocol = self.tree_meta.get("retrieval_protocol", {})
        protocol_md = self._render_retrieval_protocol(protocol)

        self.items[domain_slug] = {
            "id": stable_uuid("feature_item", domain_slug),
            "parent_slug": None,
            "slug": domain_slug,
            "name": self.tree_meta["domain_name"],
            "item_type": "domain",
            "description": "Consolidated writing craft playbooks for proposals, slides, web copy, localization, and feature guides.",
            "sort_order": 5,
            "metadata": {
                "knowledge_domain": "writing",
                "generation_batch": self.batch,
            },
            "aliases": ["writing principles", "writing playbook", "copy principles"],
            "is_active": True,
        }

        self.add_block(
            domain_slug,
            "Writing Principles MCP — How To Use",
            protocol_md,
            "overview",
            ["general", "marketing", "sales"],
            f"{WRITING_DIR}/INDEX.md#mcp-retrieval-protocol",
            {"section_anchor": "mcp-retrieval-protocol", "doc_role": "mcp_onboarding"},
        )

    def _render_retrieval_protocol(self, protocol: dict) -> str:
        lines = [
            "## Universal foundation",
            "",
            protocol.get("universal_first", ""),
            "",
            "## Truth boundary",
            "",
            protocol.get("product_facts_boundary", ""),
            "",
            "## Default tool sequence",
            "",
        ]
        for index, step in enumerate(protocol.get("default_sequence", []), start=1):
            lines.append(f"{index}. `{step}`")
        lines.extend(["", "## Task → playbook composition", ""])
        for row in protocol.get("task_composition", []):
            lines.append(f"### {row['task']}")
            lines.append(f"- **Playbooks:** {' → '.join(row['sequence'])}")
            lines.append(f"- **Tools:** {', '.join(row['tools'])}")
            lines.append("")
        return "\n".join(lines).strip()

    def add_feature_overview(self, spec: FeatureSpec, intro_text: str) -> None:
        universal_note = (
            "\n\n**Universal:** Apply alongside every other playbook."
            if spec.universal
            else ""
        )
        cross_note = (
            "\n\n**Cross-cutting:** Add after the genre playbook when localizing."
            if spec.cross_cutting
            else ""
        )
        content = textwrap.dedent(
            f"""\
            **When to use:** {spec.when_to_use}
            **Source:** `{spec.source_file}`{f" (Part {spec.source_part})" if spec.source_part else ""}
            **Genre:** `{spec.genre}`{universal_note}{cross_note}

            {first_paragraph(intro_text) or spec.when_to_use}
            """
        ).strip()
        self.add_block(
            spec.slug,
            f"{spec.name} — Overview",
            content,
            "overview",
            genre_perspectives(spec.genre),
            source_ref(f"{WRITING_DIR}/{spec.source_file}"),
            {
                "genre": spec.genre,
                "source_file": spec.source_file,
                "section_anchor": "overview",
                **({"part": spec.source_part} if spec.source_part else {}),
            },
        )

    def ingest_standard_doc(self, spec: FeatureSpec, path: Path, heading_levels: Iterable[int] = (2,)) -> None:
        text = read_text(path)
        rel = f"{WRITING_DIR}/{path.name}"
        sections = parse_sections(text, levels=heading_levels)
        selected = 0

        self.add_feature_overview(spec, text)

        for section in sections:
            if not section.content.strip():
                continue
            if section.title.lower() in {"sources", "source"}:
                continue
            knowledge_type = block_mapping(section.title)
            self.add_block(
                spec.slug,
                section.title,
                section.content,
                knowledge_type,
                genre_perspectives(spec.genre),
                source_ref(rel, section),
                {
                    "genre": spec.genre,
                    "source_file": spec.source_file,
                    "section_anchor": anchor_slug(section.title),
                },
            )
            selected += 1

        self.source_inventory.append(
            {
                "path": rel,
                "kind": "standard",
                "feature_slug": spec.slug,
                "sections": len(sections),
                "selected_sections": selected + 1,
            }
        )

    def ingest_proposal_doc(self, spec: FeatureSpec, path: Path) -> None:
        text = read_text(path)
        rel = f"{WRITING_DIR}/{path.name}"
        selected = 0
        self.add_feature_overview(spec, text)

        preamble_end = text.find("# Section 1")
        if preamble_end > 0:
            preamble = text[:preamble_end].strip()
            purpose_sections = parse_sections(preamble, levels=(2,))
            for section in purpose_sections:
                if not section.content.strip():
                    continue
                self.add_block(
                    spec.slug,
                    section.title,
                    section.content,
                    block_mapping(section.title, is_intro=True),
                    genre_perspectives(spec.genre),
                    source_ref(rel, section),
                    {"genre": spec.genre, "source_file": spec.source_file, "section_anchor": anchor_slug(section.title)},
                )
                selected += 1

        for section_title, section_body in split_proposal_sections(text):
            subsections = parse_sections(section_body, levels=(2,))
            if not subsections:
                self.add_block(
                    spec.slug,
                    section_title,
                    section_body,
                    "rules",
                    genre_perspectives(spec.genre),
                    source_ref(rel),
                    {"genre": spec.genre, "source_file": spec.source_file, "section_anchor": anchor_slug(section_title)},
                )
                selected += 1
                continue
            for subsection in subsections:
                if not subsection.content.strip():
                    continue
                self.add_block(
                    spec.slug,
                    subsection.title,
                    subsection.content,
                    "rules",
                    genre_perspectives(spec.genre),
                    source_ref(rel, subsection),
                    {
                        "genre": spec.genre,
                        "source_file": spec.source_file,
                        "section_anchor": anchor_slug(subsection.title),
                        "parent_section": section_title,
                    },
                )
                selected += 1

        self.source_inventory.append(
            {
                "path": rel,
                "kind": "proposal_rusw",
                "feature_slug": spec.slug,
                "sections": len(split_proposal_sections(text)),
                "selected_sections": selected + 1,
            }
        )

    def ingest_web_doc(self, specs: list[FeatureSpec], path: Path) -> None:
        text = read_text(path)
        rel = f"{WRITING_DIR}/{path.name}"
        parts = split_web_parts(text)
        if not parts:
            self.review_notes.append(f"WEB_PAGE_COPY_PRINCIPLES.md: no Part splits found — check heading format")
            return

        parent_spec = next(s for s in specs if s.slug == "web-page-copy")
        preamble = text[: text.find("# Part 1")].strip()
        self.add_feature_overview(parent_spec, preamble)

        for section in parse_sections(preamble, levels=(2,)):
            if not section.content.strip():
                continue
            self.add_block(
                parent_spec.slug,
                section.title,
                section.content,
                block_mapping(section.title, is_intro=True),
                genre_perspectives(parent_spec.genre),
                source_ref(rel, section),
                {"genre": "web", "source_file": path.name, "section_anchor": anchor_slug(section.title)},
            )

        part_specs = [s for s in specs if s.source_part is not None]
        for spec in part_specs:
            part_text = parts.get(spec.source_part or -1, "")
            if not part_text:
                self.review_notes.append(f"Missing Part {spec.source_part} for slug {spec.slug}")
                continue

            self.add_feature_overview(spec, part_text)
            selected = 0
            for section in parse_sections(part_text, levels=(2,)):
                if not section.content.strip():
                    continue
                if section.title.lower() in {"sources and influences", "document map"}:
                    continue
                self.add_block(
                    spec.slug,
                    section.title,
                    section.content,
                    "rules",
                    genre_perspectives(spec.genre),
                    source_ref(rel, section),
                    {
                        "genre": spec.genre,
                        "source_file": spec.source_file,
                        "section_anchor": anchor_slug(section.title),
                        "part": spec.source_part,
                    },
                )
                selected += 1

            self.source_inventory.append(
                {
                    "path": rel,
                    "kind": f"web_part_{spec.source_part}",
                    "feature_slug": spec.slug,
                    "sections": selected + 1,
                    "selected_sections": selected + 1,
                }
            )


def build_seed(root: Path, batch: str) -> SeedBuilder:
    tree_path = root / FEATURE_TREE_REL
    tree_meta, specs = load_feature_tree(tree_path)
    builder = SeedBuilder(root, batch, tree_meta)
    builder.add_domain_and_protocol()

    web_specs: list[FeatureSpec] = []
    writing_root = root / WRITING_DIR

    for spec in sorted(specs, key=lambda s: s.sort_order):
        builder.add_item(spec)
        path = writing_root / spec.source_file

        if spec.slug == "web-page-copy" or spec.source_part is not None:
            if spec.slug == "web-page-copy" or spec.source_part == 1:
                web_specs = [s for s in specs if s.source_file == "WEB_PAGE_COPY_PRINCIPLES.md"]
            continue

        if not path.exists():
            builder.review_notes.append(f"Missing source file: {path}")
            continue

        if spec.slug == "proposal-writing":
            builder.ingest_proposal_doc(spec, path)
        else:
            levels = (2, 3) if spec.slug == "sales-slides" else (2,)
            builder.ingest_standard_doc(spec, path, heading_levels=levels)

    web_path = writing_root / "WEB_PAGE_COPY_PRINCIPLES.md"
    if web_path.exists() and web_specs:
        builder.ingest_web_doc(web_specs, web_path)

    return builder


def sql_json_literal(value) -> str:
    payload = json.dumps(value, ensure_ascii=False)
    tag = "seed_json"
    while f"${tag}$" in payload:
        tag += "_x"
    return f"${tag}${payload}${tag}$"


def render_load_sql(seed: dict) -> str:
    items_json = sql_json_literal(seed["feature_items"])
    blocks_json = sql_json_literal(seed["knowledge_blocks"])
    return f"""begin;

with input_items as (
  select *
  from jsonb_to_recordset({items_json}::jsonb) as x(
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
    coalesce(i.aliases, '{{}}'::text[]) as aliases,
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
  from jsonb_to_recordset({blocks_json}::jsonb) as x(
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
"""


def write_load_chunks(seed: dict, chunks_dir: Path, block_chunk_size: int = 25) -> None:
    chunks_dir.mkdir(parents=True, exist_ok=True)
    for stale in chunks_dir.glob("*.sql"):
        stale.unlink()

    domain_items = [i for i in seed["feature_items"] if i.get("parent_slug") is None]
    child_items = [i for i in seed["feature_items"] if i.get("parent_slug") is not None]

    domain_seed = {**seed, "feature_items": domain_items, "knowledge_blocks": []}
    (chunks_dir / "000_domain_items.sql").write_text(render_load_sql(domain_seed), encoding="utf-8")

    if child_items:
        child_seed = {**seed, "feature_items": child_items, "knowledge_blocks": []}
        (chunks_dir / "001_child_items.sql").write_text(render_load_sql(child_seed), encoding="utf-8")

    blocks = seed["knowledge_blocks"]
    for index in range(0, len(blocks), block_chunk_size):
        chunk_seed = {**seed, "feature_items": [], "knowledge_blocks": blocks[index : index + block_chunk_size]}
        (chunks_dir / f"{index // block_chunk_size + 2:03d}_blocks.sql").write_text(
            render_load_sql(chunk_seed), encoding="utf-8"
        )


def render_audit(seed: dict) -> str:
    items = seed["feature_items"]
    blocks = seed["knowledge_blocks"]
    by_slug: dict[str, int] = {}
    by_type: dict[str, int] = {}
    for block in blocks:
        by_slug[block["feature_slug"]] = by_slug.get(block["feature_slug"], 0) + 1
        by_type[block["knowledge_type"]] = by_type.get(block["knowledge_type"], 0) + 1

    def table(mapping: dict[str, int]) -> str:
        rows = ["| Key | Count |", "|---|---:|"]
        for key, count in sorted(mapping.items()):
            rows.append(f"| `{key}` | {count} |")
        return "\n".join(rows)

    inventory_rows = ["| Source | Kind | Feature | Blocks |", "|---|---|---|---:|"]
    for row in seed["source_inventory"]:
        inventory_rows.append(
            f"| `{row['path']}` | {row['kind']} | `{row.get('feature_slug', '')}` | {row.get('selected_sections', 0)} |"
        )

    notes = "\n".join(f"- {note}" for note in seed["review_notes"]) or "- None"
    return f"""# Writing Principles Seed Audit

Generated at: `{seed['generated_at']}`

Generation batch: `{seed['generation_batch']}`

## Summary
- Feature items: {len(items)} (domain + features + web sub-features)
- Knowledge blocks: {len(blocks)}
- Source files inventoried: {len(seed['source_inventory'])}

## Blocks By Feature Slug
{table(by_slug)}

## Blocks By Knowledge Type
{table(by_type)}

## Source Inventory
{chr(10).join(inventory_rows)}

## Review Notes
{notes}

## Approval gate
Do **not** load until reviewed. After approval, apply via Supabase MCP using `generated/writing-principles/load-chunks/*.sql` or a single migration wrapping the same SQL.
"""


def write_outputs(builder: SeedBuilder, out_dir: Path) -> None:
    out_dir.mkdir(parents=True, exist_ok=True)
    seed = {
        "generated_at": datetime.now(timezone.utc).isoformat(),
        "generation_batch": builder.batch,
        "feature_items": sorted(builder.items.values(), key=lambda x: x["sort_order"]),
        "knowledge_blocks": sorted(builder.blocks.values(), key=lambda x: (x["feature_slug"], x["title"])),
        "source_inventory": builder.source_inventory,
        "review_notes": builder.review_notes,
    }
    (out_dir / "seed.json").write_text(json.dumps(seed, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
    (out_dir / "load.sql").write_text(render_load_sql(seed), encoding="utf-8")
    write_load_chunks(seed, out_dir / "load-chunks")
    (out_dir / "audit.md").write_text(render_audit(seed), encoding="utf-8")


def main() -> None:
    parser = argparse.ArgumentParser(description="Generate Writing Principles internal knowledge seed artifacts.")
    parser.add_argument("--root", type=Path, default=Path.cwd(), help="Workspace root")
    parser.add_argument(
        "--out",
        type=Path,
        default=Path("generated/writing-principles"),
        help="Output directory",
    )
    parser.add_argument(
        "--batch",
        default=datetime.now(timezone.utc).strftime("writing_principles_seed_%Y%m%dT%H%M%SZ"),
    )
    args = parser.parse_args()

    root = args.root.resolve()
    out_dir = args.out if args.out.is_absolute() else root / args.out
    builder = build_seed(root, args.batch)
    write_outputs(builder, out_dir)
    print(f"Wrote {len(builder.items)} feature items and {len(builder.blocks)} blocks to {out_dir}")


if __name__ == "__main__":
    main()
