#!/usr/bin/env python3
"""Generate reviewable seed data for the internal feature knowledge database.

The script reads feature-guide markdown plus requirement/domain docs and emits:
- seed.json: deterministic feature_items and knowledge_blocks records
- load.sql: transactional upsert SQL for Supabase MCP execute_sql
- audit.md: source coverage, counts, and review notes
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


PROJECT_UUID_NAMESPACE = uuid.UUID("97e58110-d75c-5c76-bb49-36e4c15858bd")

KNOWLEDGE_TYPES = {
    "overview",
    "key_concepts",
    "value_proposition",
    "configuration_reference",
    "admin_journey",
    "user_experience",
    "business_rules",
    "related_features",
    "limitations",
    "testing_guidance",
    "technical_overview",
    "implementation_objects",
    "technical_flow",
    "implementation_constraints",
}

PERSPECTIVES = {
    "general",
    "product",
    "marketing",
    "sales",
    "customer_success",
    "frontend",
    "technical",
    "testing",
    "implementation",
}

OUTPUT_USES = {
    "agent_context",
    "slide_generation",
    "proposal_content",
    "marketing_content",
    "frontend_context",
    "product_docs",
    "help_center",
    "training_material",
    "implementation_brief",
    "technical_docs",
    "qa_testing",
}

SCOPES = {"general", "admin_fe", "user_fe", "be", "integration"}


DOMAIN_ITEMS = [
    ("platform", "Platform", "Core product context, admin surfaces, authentication, signup, display settings, translation, and internal agent knowledge."),
    ("loyalty", "Loyalty", "Points, tiers, rewards, missions, referrals, purchase transactions, activity earning, forms, and customer classification."),
    ("amp", "AMP", "Marketing automation workflows, rule-based automation, and AI decisioning."),
    ("customer-service", "Customer Service", "Omnichannel conversations, channels, procedures, knowledge base, AI assistance, voice, SLA, rules, and analytics."),
    ("ai", "AI", "Cross-module AI capabilities used by AMP and Customer Service."),
    ("shared-integration", "Shared & Integration", "Shared action systems, resource content, marketplace connectors, event processing, and integration flows."),
]


FEATURE_DOC_OVERRIDES = {
    "Event_Order_Consumer_Changes": ("event-order-consumers", "Event Order Consumers", "shared-integration", "implementation_note"),
    "Event_Promo_Engine": ("event-promo-engine", "Event Promo Engine", "shared-integration", "domain_reference"),
    "activity-based-earning": ("activity-based-earning", "Activity-Based Earning", "loyalty", "feature_guide"),
    "amp-ai-decisioning": ("amp-ai-decisioning", "AMP AI Decisioning", "ai", "feature_guide"),
    "amp-workflows": ("amp-workflows", "AMP Workflows", "amp", "feature_guide"),
    "authentication-and-signup": ("authentication-and-signup", "Authentication & Signup", "platform", "feature_guide"),
    "checkin": ("checkin", "Check-in", "loyalty", "feature_guide"),
    "cs-channels": ("cs-channels", "CS Channels", "customer-service", "feature_guide"),
    "cs-conversations": ("cs-conversations", "CS Conversations", "customer-service", "feature_guide"),
    "cs-knowledge-base": ("cs-knowledge-base", "CS Knowledge Base", "customer-service", "feature_guide"),
    "currency": ("currency", "Currency", "loyalty", "feature_guide"),
    "forms": ("forms", "Forms", "loyalty", "feature_guide"),
    "marketplace-integration": ("marketplace-integration", "Marketplace Integration", "shared-integration", "feature_guide"),
    "missions": ("missions", "Missions", "loyalty", "feature_guide"),
    "platform-overview": ("platform-overview", "Platform Overview", "platform", "platform_overview"),
    "purchase-transactions": ("purchase-transactions", "Purchase Transactions", "loyalty", "feature_guide"),
    "referral": ("referral", "Referral", "loyalty", "feature_guide"),
    "reward-groups": ("reward-groups", "Reward Groups & Max Distinct Reward", "loyalty", "feature_guide"),
    "rewards": ("rewards", "Rewards", "loyalty", "feature_guide"),
    "store-classification": ("store-classification", "Store & Partner Classification", "loyalty", "feature_guide"),
    "stored-value-cards": ("stored-value-cards", "Stored Value Cards", "loyalty", "feature_guide"),
    "tags-and-personas": ("tags-and-personas", "Tags & Personas", "loyalty", "feature_guide"),
    "tiers": ("tiers", "Tiers", "loyalty", "feature_guide"),
    "translation-system": ("translation-system", "Translation System", "platform", "feature_guide"),
}


DOMAIN_PARENT_OVERRIDES = {
    "action-macro-shared": "shared-integration",
    "admin-panel": "platform",
    "authentication": "platform",
    "cs-actions-feature-spec": "customer-service",
    "cs-ai-system-feature-spec": "ai",
    "cs-analytics-qa-feature-spec": "customer-service",
    "cs-brand-configuration": "customer-service",
    "cs-channel-connectors-feature-spec": "customer-service",
    "cs-channels-customers": "customer-service",
    "cs-competitor-matrix": "customer-service",
    "cs-conversations": "customer-service",
    "cs-knowledge-base": "customer-service",
    "cs-live-assist-feature-spec": "ai",
    "cs-phone-number-purchasing": "customer-service",
    "cs-platform-features-feature-spec": "customer-service",
    "cs-procedures-aops": "customer-service",
    "cs-rules-engine-feature-spec": "customer-service",
    "cs-sla-management-feature-spec": "customer-service",
    "cs-teams-agent-profiles": "customer-service",
    "cs-unified-inbox-feature-spec": "customer-service",
    "cs-voice": "customer-service",
    "display-settings": "platform",
    "forms-user-profile": "loyalty",
    "internal-knowledge": "platform",
    "resource-content-shared": "shared-integration",
    "signup-login": "platform",
    "universal-action-system-shared": "shared-integration",
}


DOMAIN_TO_FEATURE_SLUG = {
    "activity-earning": "activity-based-earning",
    "authentication": "authentication-and-signup",
    "currency": "currency",
    "forms-user-profile": "forms",
    "mission": "missions",
    "purchase-transaction": "purchase-transactions",
    "referral": "referral",
    "reward": "rewards",
    "store-classification": "store-classification",
    "tag-persona": "tags-and-personas",
    "tier": "tiers",
    "translation": "translation-system",
}


SUB_FEATURES = {
    "rewards": [
        ("reward-redemption", "Reward Redemption"),
        ("dynamic-reward-points", "Dynamic Reward Points"),
        ("promo-code-management", "Promo Code Management"),
        ("reward-fulfillment", "Reward Fulfillment"),
        ("reward-marketplace-distribution", "Reward Marketplace Distribution"),
        ("reward-sourcing-services", "Reward Sourcing & Partner Fulfillment"),
    ],
    "reward-groups": [("reward-group-limits", "Reward Group Limits"), ("max-distinct-reward", "Max Distinct Reward")],
    "currency": [("earn-rules", "Earn Rules"), ("wallet-ledger", "Wallet Ledger"), ("currency-expiry", "Currency Expiry")],
    "purchase-transactions": [("purchase-ledger", "Purchase Ledger"), ("receipt-upload-earning", "Receipt Upload Earning")],
    "missions": [("mission-conditions", "Mission Conditions"), ("mission-outcomes", "Mission Outcomes"), ("mission-progress", "Mission Progress")],
    "tiers": [("tier-upgrade", "Tier Upgrade"), ("tier-maintenance", "Tier Maintenance"), ("tier-progress", "Tier Progress")],
    "activity-based-earning": [("activity-upload-review", "Activity Upload Review"), ("activity-currency-matrix", "Activity Currency Matrix")],
    "referral": [("inviter-limits", "Inviter Limits"), ("invitee-outcomes", "Invitee Outcomes")],
    "forms": [("default-fields", "Default Fields"), ("custom-fields", "Custom Fields"), ("pdpa-consent", "PDPA Consent")],
    "store-classification": [("store-master", "Store Master"), ("store-attribute-sets", "Store Attribute Sets")],
    "tags-and-personas": [("personas", "Personas"), ("tags", "Tags")],
    "amp-workflows": [("workflow-builder", "Workflow Builder"), ("workflow-nodes", "Workflow Nodes"), ("workflow-analytics", "Workflow Analytics")],
    "amp-ai-decisioning": [("ai-agent-configuration", "AI Agent Configuration"), ("deliberation-settings", "Deliberation Settings")],
    "cs-conversations": [("unified-inbox", "Unified Inbox"), ("conversation-assignment", "Conversation Assignment"), ("conversation-status", "Conversation Status")],
    "cs-channels": [("channel-connectors", "Channel Connectors"), ("phone-number-management", "Phone Number Management")],
    "cs-knowledge-base": [("knowledge-articles", "Knowledge Articles"), ("custom-answers", "Custom Answers"), ("semantic-search", "Semantic Search")],
    "marketplace-integration": [("marketplace-connectors", "Marketplace Connectors"), ("marketplace-order-sync", "Marketplace Order Sync")],
    "event-promo-engine": [("event-promo-rules", "Event Promo Rules"), ("event-promo-claims", "Event Promo Claims")],
    "event-order-consumers": [("currency-event-consumer", "Currency Event Consumer"), ("amp-event-consumer", "AMP Event Consumer")],
}


STANDARD_SECTION_MAP = [
    (re.compile(r"^1\.\s+overview", re.I), ("overview", ["general", "product", "marketing"], ["agent_context", "slide_generation", "product_docs"], "general")),
    (re.compile(r"^2\.\s+key concepts", re.I), ("key_concepts", ["general", "product", "customer_success", "testing"], ["agent_context", "product_docs", "training_material"], "general")),
    (re.compile(r"^3\.\s+configuration", re.I), ("configuration_reference", ["frontend", "testing", "customer_success"], ["frontend_context", "qa_testing", "training_material"], "admin_fe")),
    (re.compile(r"^4\.\s+(admin|agent)", re.I), ("admin_journey", ["frontend", "testing", "customer_success"], ["frontend_context", "qa_testing", "training_material"], "admin_fe")),
    (re.compile(r"^5\.\s+(member|user|customer|agent)", re.I), ("user_experience", ["frontend", "testing", "marketing"], ["frontend_context", "qa_testing", "marketing_content"], "user_fe")),
    (re.compile(r"^7\.\s+business rules", re.I), ("business_rules", ["product", "technical", "testing", "customer_success"], ["agent_context", "product_docs", "qa_testing"], "general")),
    (re.compile(r"^8\.\s+related", re.I), ("related_features", ["general", "product"], ["agent_context", "product_docs"], "general")),
]


@dataclass(frozen=True)
class Section:
    level: int
    title: str
    content: str
    start_line: int


def slugify(value: str) -> str:
    value = value.lower().strip()
    value = value.replace("&", " and ")
    value = re.sub(r"[^a-z0-9]+", "-", value)
    return re.sub(r"-+", "-", value).strip("-")


def stable_uuid(kind: str, key: str) -> str:
    return str(uuid.uuid5(PROJECT_UUID_NAMESPACE, f"{kind}:{key}"))


def read_text(path: Path) -> str:
    return path.read_text(encoding="utf-8", errors="replace")


def title_from_doc(text: str, fallback: str) -> str:
    for line in text.splitlines():
        if line.startswith("# "):
            return re.sub(r"^Feature Guide:\s*", "", line[2:].strip())
    return fallback


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


def first_paragraph(markdown: str, limit: int = 280) -> str:
    cleaned = re.sub(r"```.*?```", "", markdown, flags=re.S)
    for para in re.split(r"\n\s*\n", cleaned):
        para = re.sub(r"[*_`>#|]", "", para).strip()
        para = re.sub(r"\s+", " ", para)
        if len(para) > 40 and not para.lower().startswith("table of contents"):
            return para[:limit].rstrip()
    return ""


def clamp_content(content: str, limit: int = 7000) -> tuple[str, bool]:
    content = content.strip()
    if len(content) <= limit:
        return content, False
    truncated = content[:limit].rsplit("\n", 1)[0].rstrip()
    return truncated + "\n\n_Source section truncated in seed output; consult `source_ref` for the full text._", True


def section_type_for_standard(title: str) -> tuple[str, list[str], list[str], str] | None:
    normalized = title.strip()
    for pattern, mapping in STANDARD_SECTION_MAP:
        if pattern.search(normalized):
            return mapping
    return None


def perspective_block_mapping(title: str) -> tuple[str, list[str], list[str], str] | None:
    if re.match(r"^6a\.\s+for customer success", title, re.I):
        return ("overview", ["customer_success"], ["help_center", "training_material", "agent_context"], "general")
    if re.match(r"^6b\.\s+for marketing", title, re.I):
        return ("value_proposition", ["marketing", "sales"], ["slide_generation", "proposal_content", "marketing_content"], "general")
    if re.match(r"^6c\.\s+for testers", title, re.I):
        return ("testing_guidance", ["testing"], ["qa_testing", "agent_context"], "general")
    return None


def nonstandard_mapping(title: str, doc_type: str) -> tuple[str, list[str], list[str], str]:
    lower = title.lower()
    if "overview" in lower or "executive summary" in lower:
        return ("overview", ["general", "product"], ["agent_context", "product_docs"], "general")
    if "concept" in lower or "glossary" in lower:
        return ("key_concepts", ["general", "product"], ["agent_context", "product_docs"], "general")
    if any(word in lower for word in ["structure", "column", "schema", "config", "setting"]):
        return ("configuration_reference", ["technical", "implementation"], ["technical_docs", "implementation_brief"], "be")
    if any(word in lower for word in ["condition", "business rule", "rule", "limit", "status", "state"]):
        return ("business_rules", ["product", "technical", "testing"], ["agent_context", "qa_testing", "technical_docs"], "general")
    if any(word in lower for word in ["consumer", "pipeline", "flow", "processing", "integration", "sync", "event", "webhook"]):
        return ("technical_flow", ["technical", "implementation"], ["technical_docs", "implementation_brief", "agent_context"], "integration")
    if any(word in lower for word in ["file", "function", "api", "rpc", "table", "object"]):
        return ("implementation_objects", ["technical", "implementation"], ["technical_docs", "implementation_brief", "agent_context"], "be")
    if any(word in lower for word in ["safe", "constraint", "caveat", "error", "risk", "idempot"]):
        return ("implementation_constraints", ["technical", "implementation", "testing"], ["technical_docs", "implementation_brief", "qa_testing"], "be")
    if "test" in lower or "example" in lower:
        return ("testing_guidance", ["testing", "technical"], ["qa_testing", "agent_context"], "general")
    if doc_type == "implementation_note":
        return ("technical_overview", ["technical", "implementation"], ["technical_docs", "implementation_brief"], "integration")
    return ("technical_overview", ["technical", "product"], ["agent_context", "technical_docs"], "general")


def source_ref(path: Path, root: Path, section: Section | None = None) -> str:
    rel = path.relative_to(root).as_posix()
    if section:
        return f"{rel}#L{section.start_line} {section.title}"
    return rel


class SeedBuilder:
    def __init__(self, root: Path, batch: str):
        self.root = root
        self.batch = batch
        self.items: dict[str, dict] = {}
        self.blocks: dict[str, dict] = {}
        self.source_inventory: list[dict] = []
        self.review_notes: list[str] = []

    def add_item(
        self,
        slug: str,
        name: str,
        item_type: str,
        parent_slug: str | None,
        description: str,
        sort_order: int,
        metadata: dict,
    ) -> None:
        if slug in self.items:
            existing = self.items[slug]
            existing["metadata"].update({k: v for k, v in metadata.items() if k not in existing["metadata"]})
            if description and not existing.get("description"):
                existing["description"] = description
            return
        self.items[slug] = {
            "id": stable_uuid("feature_item", slug),
            "parent_slug": parent_slug,
            "slug": slug,
            "name": name,
            "item_type": item_type,
            "description": description,
            "sort_order": sort_order,
            "metadata": metadata,
            "is_active": True,
        }

    def add_block(
        self,
        feature_slug: str,
        title: str,
        content: str,
        knowledge_type: str,
        perspectives: list[str],
        output_uses: list[str],
        scope: str,
        source: str,
        metadata: dict,
    ) -> None:
        content, truncated = clamp_content(content)
        if not content.strip() or knowledge_type not in KNOWLEDGE_TYPES:
            return
        perspectives = sorted(set(p for p in perspectives if p in PERSPECTIVES)) or ["general"]
        output_uses = sorted(set(o for o in output_uses if o in OUTPUT_USES)) or ["agent_context"]
        scope = scope if scope in SCOPES else "general"
        metadata = dict(metadata)
        metadata.update(
            {
                "feature_slug": feature_slug,
                "generation_batch": self.batch,
                "content_sha256": hashlib.sha256(content.encode("utf-8")).hexdigest(),
                "truncated": truncated,
            }
        )
        block_key = "|".join([feature_slug, knowledge_type, scope, source, title])
        block_id = stable_uuid("knowledge_block", block_key)
        self.blocks[block_id] = {
            "id": block_id,
            "feature_slug": feature_slug,
            "title": title.strip()[:180],
            "content": content,
            "content_format": "markdown",
            "knowledge_type": knowledge_type,
            "perspectives": perspectives,
            "output_uses": output_uses,
            "scope": scope,
            "source_ref": source,
            "metadata": metadata,
            "is_active": True,
        }

    def add_domains(self) -> None:
        for order, (slug, name, description) in enumerate(DOMAIN_ITEMS, start=10):
            self.add_item(
                slug=slug,
                name=name,
                item_type="domain",
                parent_slug=None,
                description=description,
                sort_order=order,
                metadata={"source_doc_type": "curated_hierarchy", "generation_batch": self.batch},
            )

    def add_feature_doc(self, path: Path, sort_order: int) -> None:
        text = read_text(path)
        stem = path.stem
        feature_slug, name, parent_slug, doc_type = FEATURE_DOC_OVERRIDES.get(
            stem,
            (slugify(stem), title_from_doc(text, stem.replace("-", " ").title()), "platform", "feature_guide"),
        )
        sections = parse_sections(text, levels=(2,))
        description = ""
        for section in sections:
            if re.search(r"overview", section.title, re.I):
                description = first_paragraph(section.content)
                break
        self.add_item(
            feature_slug,
            name,
            "feature",
            parent_slug,
            description,
            sort_order,
            {"source_doc_type": doc_type, "source_path": path.relative_to(self.root).as_posix(), "generation_batch": self.batch},
        )
        for sub_order, (sub_slug, sub_name) in enumerate(SUB_FEATURES.get(feature_slug, []), start=1):
            self.add_item(
                sub_slug,
                sub_name,
                "sub_feature",
                feature_slug,
                "",
                sort_order * 100 + sub_order,
                {"source_doc_type": "curated_sub_feature", "generation_batch": self.batch},
            )

        self.source_inventory.append(
            {
                "path": path.relative_to(self.root).as_posix(),
                "kind": doc_type,
                "feature_slug": feature_slug,
                "sections": len(sections),
            }
        )

        for section in sections:
            if not section.content.strip():
                continue
            mapping = section_type_for_standard(section.title)
            if re.match(r"^6\.\s+perspectives", section.title, re.I):
                sub_sections = parse_sections(section.content, levels=(3,))
                for sub in sub_sections:
                    sub_mapping = perspective_block_mapping(sub.title)
                    if sub_mapping and sub.content.strip():
                        knowledge_type, perspectives, output_uses, scope = sub_mapping
                        self.add_block(
                            feature_slug,
                            sub.title,
                            sub.content,
                            knowledge_type,
                            perspectives,
                            output_uses,
                            scope,
                            f"{source_ref(path, self.root, section)} / {sub.title}",
                            {"source_doc_type": doc_type, "source_priority": "feature_guide", "review_status": "generated"},
                        )
                continue
            if mapping is None:
                mapping = nonstandard_mapping(section.title, doc_type)
            knowledge_type, perspectives, output_uses, scope = mapping
            self.add_block(
                feature_slug,
                section.title,
                section.content,
                knowledge_type,
                perspectives,
                output_uses,
                scope,
                source_ref(path, self.root, section),
                {"source_doc_type": doc_type, "source_priority": "feature_guide", "review_status": "generated"},
            )

    def add_domain_doc(self, path: Path, sort_order: int) -> None:
        text = read_text(path)
        if path.name == "_index.md":
            return
        domain_slug = path.stem
        title = title_from_doc(text, domain_slug.replace("-", " ").title())
        feature_slug = DOMAIN_TO_FEATURE_SLUG.get(domain_slug, domain_slug)
        parent_slug = DOMAIN_PARENT_OVERRIDES.get(domain_slug, infer_parent_for_domain(domain_slug))
        source_path = extract_source_path(text)

        self.add_item(
            feature_slug,
            title.replace(" (Feature Spec)", ""),
            "feature",
            parent_slug,
            first_paragraph(text),
            1000 + sort_order,
            {
                "source_doc_type": "domain_reference",
                "source_path": path.relative_to(self.root).as_posix(),
                "deep_source_path": source_path,
                "generation_batch": self.batch,
            },
        )
        self.source_inventory.append(
            {
                "path": path.relative_to(self.root).as_posix(),
                "kind": "domain_reference",
                "feature_slug": feature_slug,
                "sections": len(parse_sections(text, levels=(2,))),
                "deep_source_path": source_path,
            }
        )

        self.add_block(
            feature_slug,
            f"{title} Domain Reference",
            compact_domain_reference(text),
            "technical_overview",
            ["technical", "product", "implementation"],
            ["agent_context", "technical_docs", "implementation_brief"],
            "be",
            source_ref(path, self.root),
            {"source_doc_type": "domain_reference", "source_priority": "domain_pointer", "review_status": "generated"},
        )

        deep_path = resolve_source_path(self.root, source_path)
        if deep_path and deep_path.exists() and deep_path != path:
            self.add_deep_requirement_doc(deep_path, feature_slug)
        elif source_path:
            self.review_notes.append(f"Missing deep source for {path.relative_to(self.root).as_posix()}: {source_path}")

    def add_deep_requirement_doc(self, path: Path, feature_slug: str) -> None:
        text = read_text(path)
        sections = parse_sections(text, levels=(2,))
        selected = select_deep_sections(sections)
        self.source_inventory.append(
            {
                "path": path.relative_to(self.root).as_posix(),
                "kind": "requirement_deep_source",
                "feature_slug": feature_slug,
                "sections": len(sections),
                "selected_sections": len(selected),
            }
        )
        for section, mapping_reason in selected:
            knowledge_type, perspectives, output_uses, scope = nonstandard_mapping(section.title, "requirement_deep_source")
            if mapping_reason == "objects":
                knowledge_type, perspectives, output_uses, scope = (
                    "implementation_objects",
                    ["technical", "implementation"],
                    ["technical_docs", "implementation_brief", "agent_context"],
                    "be",
                )
            elif mapping_reason == "flow":
                knowledge_type, perspectives, output_uses, scope = (
                    "technical_flow",
                    ["technical", "implementation"],
                    ["technical_docs", "implementation_brief", "agent_context"],
                    "integration",
                )
            elif mapping_reason == "rules":
                knowledge_type, perspectives, output_uses, scope = (
                    "business_rules",
                    ["product", "technical", "testing"],
                    ["agent_context", "product_docs", "qa_testing"],
                    "general",
                )
            elif mapping_reason == "constraints":
                knowledge_type, perspectives, output_uses, scope = (
                    "implementation_constraints",
                    ["technical", "implementation", "testing"],
                    ["technical_docs", "implementation_brief", "qa_testing"],
                    "be",
                )
            self.add_block(
                feature_slug,
                section.title,
                section.content,
                knowledge_type,
                perspectives,
                output_uses,
                scope,
                source_ref(path, self.root, section),
                {
                    "source_doc_type": "requirement_deep_source",
                    "source_priority": "requirement_doc",
                    "review_status": "generated",
                    "selection_reason": mapping_reason,
                },
            )

    def write_outputs(self, out_dir: Path) -> None:
        out_dir.mkdir(parents=True, exist_ok=True)
        seed = {
            "generation_batch": self.batch,
            "generated_at": datetime.now(timezone.utc).isoformat(),
            "feature_items": sorted(self.items.values(), key=lambda item: (item["parent_slug"] or "", item["sort_order"], item["slug"])),
            "knowledge_blocks": sorted(self.blocks.values(), key=lambda block: (block["feature_slug"], block["knowledge_type"], block["source_ref"], block["title"])),
            "source_inventory": sorted(self.source_inventory, key=lambda row: row["path"]),
            "review_notes": sorted(set(self.review_notes)),
        }
        (out_dir / "seed.json").write_text(json.dumps(seed, indent=2, ensure_ascii=False), encoding="utf-8")
        (out_dir / "load.sql").write_text(render_load_sql(seed), encoding="utf-8")
        write_load_chunks(seed, out_dir / "load-chunks")
        (out_dir / "audit.md").write_text(render_audit(seed), encoding="utf-8")


def infer_parent_for_domain(slug: str) -> str:
    if slug.startswith("cs-"):
        return "customer-service"
    if slug.startswith("amp"):
        return "amp"
    if slug in {"reward", "currency", "activity-earning", "purchase-transaction", "mission", "referral", "store-classification", "tag-persona", "tier"}:
        return "loyalty"
    return "platform"


def extract_source_path(text: str) -> str:
    match = re.search(r"\*\*Source:\*\*\s*`([^`]+)`", text)
    return match.group(1).strip() if match else ""


def resolve_source_path(root: Path, source: str) -> Path | None:
    if not source:
        return None
    source = source.split(",", 1)[0].strip()
    source = re.sub(r"\s*\(.*?\)\s*$", "", source).strip()
    candidates = []
    raw = Path(source)
    if raw.is_absolute():
        candidates.append(raw)
    else:
        candidates.extend([root / source, root / "requirements" / source, root / "docs" / source])
    for candidate in candidates:
        if candidate.exists():
            return candidate
    return candidates[0] if candidates else None


def compact_domain_reference(text: str) -> str:
    keep: list[str] = []
    capture = False
    for line in text.splitlines():
        if line.startswith("**Keywords:**") or line.startswith("**Source:**") or line.startswith("**Tables:**"):
            keep.append(line)
        elif line.startswith("| Function |") or line.startswith("|---|---|") or re.match(r"^\| `", line):
            keep.append(line)
        elif line.startswith("**Key Business Rules"):
            capture = True
            keep.append(line)
        elif capture:
            if line.strip() == "---":
                capture = False
            else:
                keep.append(line)
    return "\n".join(keep).strip() or text.strip()


def select_deep_sections(sections: list[Section]) -> list[tuple[Section, str]]:
    selected: list[tuple[Section, str]] = []
    patterns = [
        ("objects", re.compile(r"(database schema|schema|tables?|functions?|rpc|api integration|edge function|implementation object|source files?)", re.I)),
        ("flow", re.compile(r"(architecture|flow|pipeline|processing|consumer|event|integration|sync|webhook|sequence)", re.I)),
        ("rules", re.compile(r"(business rules?|rules?|status|state|eligibility|limits?|conditions?|calculation|pricing)", re.I)),
        ("constraints", re.compile(r"(constraint|limitation|caveat|error|race|idempot|permission|security|monitoring)", re.I)),
    ]
    for section in sections:
        for reason, pattern in patterns:
            if pattern.search(section.title):
                selected.append((section, reason))
                break
    if not selected and sections:
        selected.append((sections[0], "overview"))
    return selected[:12]


def sql_literal(value: object) -> str:
    text = json.dumps(value, ensure_ascii=False)
    return "'" + text.replace("'", "''") + "'::jsonb"


def render_load_sql(seed: dict) -> str:
    items_json = sql_literal(seed["feature_items"])
    blocks_json = sql_literal(seed["knowledge_blocks"])
    return f"""-- Generated by scripts/generate_internal_knowledge_seed.py
-- Batch: {seed['generation_batch']}
-- This script upserts deterministic records and does not delete manual rows.

begin;

with input_items as (
  select *
  from jsonb_to_recordset({items_json}) as x(
    id uuid,
    parent_slug text,
    slug text,
    name text,
    item_type text,
    description text,
    sort_order integer,
    metadata jsonb,
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
    coalesce(i.is_active, true) as is_active
  from input_items i
  left join public.internal_knowledge_feature_items p on lower(p.slug) = lower(i.parent_slug)
)
insert into public.internal_knowledge_feature_items (
  id, parent_id, slug, name, item_type, description, sort_order, metadata, is_active, updated_at
)
select id, parent_id, slug, name, item_type, description, sort_order, metadata, is_active, now()
from resolved_items
on conflict (id) do update set
  parent_id = excluded.parent_id,
  slug = excluded.slug,
  name = excluded.name,
  item_type = excluded.item_type,
  description = excluded.description,
  sort_order = excluded.sort_order,
  metadata = public.internal_knowledge_feature_items.metadata || excluded.metadata,
  is_active = excluded.is_active,
  updated_at = now();

with input_blocks as (
  select *
  from jsonb_to_recordset({blocks_json}) as x(
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
  id,
  feature_item_id,
  title,
  content,
  content_format,
  knowledge_type,
  perspectives,
  output_uses,
  scope,
  source_ref,
  metadata,
  is_active,
  now()
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

    items_seed = {**seed, "knowledge_blocks": []}
    (chunks_dir / "000_items.sql").write_text(render_load_sql(items_seed), encoding="utf-8")

    blocks = seed["knowledge_blocks"]
    for index in range(0, len(blocks), block_chunk_size):
        chunk_seed = {**seed, "feature_items": [], "knowledge_blocks": blocks[index : index + block_chunk_size]}
        (chunks_dir / f"{index // block_chunk_size + 1:03d}_blocks.sql").write_text(render_load_sql(chunk_seed), encoding="utf-8")


def render_audit(seed: dict) -> str:
    items = seed["feature_items"]
    blocks = seed["knowledge_blocks"]
    by_domain: dict[str, int] = {}
    by_type: dict[str, int] = {}
    by_scope: dict[str, int] = {}
    for item in items:
        by_domain[item["parent_slug"] or "root"] = by_domain.get(item["parent_slug"] or "root", 0) + 1
    for block in blocks:
        by_type[block["knowledge_type"]] = by_type.get(block["knowledge_type"], 0) + 1
        by_scope[block["scope"]] = by_scope.get(block["scope"], 0) + 1

    def table(mapping: dict[str, int]) -> str:
        rows = ["| Key | Count |", "|---|---:|"]
        for key, count in sorted(mapping.items()):
            rows.append(f"| `{key}` | {count} |")
        return "\n".join(rows)

    inventory_rows = ["| Source | Kind | Feature | Sections | Selected |", "|---|---|---|---:|---:|"]
    for row in seed["source_inventory"]:
        inventory_rows.append(
            f"| `{row['path']}` | {row['kind']} | `{row.get('feature_slug', '')}` | {row.get('sections', 0)} | {row.get('selected_sections', '')} |"
        )

    notes = "\n".join(f"- {note}" for note in seed["review_notes"]) or "- None"
    return f"""# Internal Knowledge Seed Audit

Generated at: `{seed['generated_at']}`

Generation batch: `{seed['generation_batch']}`

## Summary
- Feature items: {len(items)}
- Knowledge blocks: {len(blocks)}
- Source files inventoried: {len(seed['source_inventory'])}

## Feature Items By Parent
{table(by_domain)}

## Blocks By Knowledge Type
{table(by_type)}

## Blocks By Scope
{table(by_scope)}

## Source Inventory
{chr(10).join(inventory_rows)}

## Review Notes
{notes}
"""


def add_reward_sourcing_services_knowledge(builder: SeedBuilder, root: Path) -> None:
    """Curated blocks for sub_feature `reward-sourcing-services` (fed by standalone MD, skipped in main feature-doc loop)."""
    path = root / "requirements" / "feature-docs" / "reward-sourcing-services.md"
    if not path.exists():
        builder.review_notes.append("Missing reward-sourcing-services.md — no curated sourcing blocks emitted")
        return
    text = read_text(path)
    sections = parse_sections(text, levels=(2,))
    for section in sections:
        if not section.content.strip():
            continue
        mapping = section_type_for_standard(section.title)
        if mapping is None:
            mapping = nonstandard_mapping(section.title, "feature_guide")
        knowledge_type, perspectives, output_uses, scope = mapping
        builder.add_block(
            "reward-sourcing-services",
            section.title,
            section.content,
            knowledge_type,
            perspectives,
            output_uses,
            scope,
            source_ref(path, root, section),
            {
                "source_doc_type": "curated_sub_feature_knowledge",
                "source_priority": "curated",
                "review_status": "editorial",
            },
        )


def build_seed(root: Path, batch: str) -> SeedBuilder:
    builder = SeedBuilder(root, batch)
    builder.add_domains()

    feature_dir = root / "requirements" / "feature-docs"
    for order, path in enumerate(sorted(feature_dir.glob("*.md")), start=1):
        if path.name == "INDEX.md":
            continue
        if path.name == "reward-sourcing-services.md":
            continue
        builder.add_feature_doc(path, order)

    add_reward_sourcing_services_knowledge(builder, root)

    domain_dir = root / "requirements" / "domains"
    for order, path in enumerate(sorted(domain_dir.glob("*.md")), start=1):
        builder.add_domain_doc(path, order)

    return builder


def main() -> None:
    parser = argparse.ArgumentParser(description="Generate internal feature knowledge seed artifacts.")
    parser.add_argument("--root", type=Path, default=Path.cwd(), help="Workspace root")
    parser.add_argument("--out", type=Path, default=Path("generated/internal-knowledge"), help="Output directory")
    parser.add_argument("--batch", default=datetime.now(timezone.utc).strftime("feature_knowledge_seed_%Y%m%dT%H%M%SZ"))
    args = parser.parse_args()

    root = args.root.resolve()
    out_dir = args.out if args.out.is_absolute() else root / args.out
    builder = build_seed(root, args.batch)
    builder.write_outputs(out_dir)
    print(f"Wrote {len(builder.items)} feature items and {len(builder.blocks)} blocks to {out_dir}")


if __name__ == "__main__":
    main()
