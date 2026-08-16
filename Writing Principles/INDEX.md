# Writing Principles — Consolidated Index

Canonical writing-principles library compiled from Rocket Deck, Rocket CRM marketing content, and Supabase CRM. Use this folder as the source of truth for a future Writing Principles MCP.

**Last compiled:** 2026-05-30

---

## Thread principles → document map

| Principle (from review threads) | Primary home | Also in |
|--------------------------------|--------------|---------|
| Customer as hero, not the brand | `WEB_PAGE_COPY_PRINCIPLES.md` Part 1 §2 | — |
| 5-second clarity & identity (skip obvious category outcomes) | Part 1 §1, §5 | Part 3 §4 (hero SEO) |
| Abstraction as container, not crutch | Part 1 §4 | `CORE_WRITING_PRINCIPLES.md` §6 (peer abstraction) |
| Sales explanation, not config inventory | `SALES_FEATURE_COPY_PRINCIPLES.md` | Catalog `name` / `summary` |
| Canonical-view shorthand (cluster, don’t photocopy) | sales pack `commercial/COPY_PRINCIPLES.md` | Pointer: this file’s stub |
| Strategic value + operational utility (heading/description pair) | Part 1 §10 | — |
| Frame AI as augmentation; AI as grammatical subject | Part 1 §10 | `TRANSLATION_PHILOSOPHY.md` § AI & Technology |
| MECE / same level in feature grids (bento boxes) | Part 1 §7 | `CORE_WRITING_PRINCIPLES.md` §4–7 |
| Localize, don't translate | `TRANSLATION_PHILOSOPHY.md` (core) | `TRANSLATION_PRINCIPLES.md` (proposals) |
| Keep standard tech terms in English | `TRANSLATION_PHILOSOPHY.md` | Part 1 §21 (Thai pages); `TRANSLATION_PRINCIPLES.md` |
| Tone calibration by market (e.g. Thai B2B/SME direct) | `TRANSLATION_PHILOSOPHY.md` | `THAILAND_CONTEXT.md` §1 (register by surface) |
| Canonical Thai product vocabulary | `THAILAND_CONTEXT.md` §2 | — |
| Proposal Thai smoothness / English backup | `TRANSLATION_PRINCIPLES.md` | general-proposal REFERENCE stage 11 |
| Structure fidelity (title vs description roles) | `TRANSLATION_PHILOSOPHY.md` | — |
| Name the decision, not the tech | `TRANSLATION_PHILOSOPHY.md` | Part 1 §10 |

---

## How to use

1. Start with **`CORE_WRITING_PRINCIPLES.md`** for any structured writing task.
2. Add the format-specific doc for your output type (see table below).
3. For Rocket product facts, compose with CRM Knowledge MCP — not these docs.
4. Grep headings first; scoped-read only the sections you need.

---

## Documents in this folder

| File | Content type | When to use |
|------|--------------|-------------|
| [CORE_WRITING_PRINCIPLES.md](./CORE_WRITING_PRINCIPLES.md) | All structured writing | Foundation: pyramid, vertical/horizontal logic, MECE, same-level grouping, layered depth, specificity, limitations |
| [PROPOSAL_WRITING_PRINCIPLES.md](./PROPOSAL_WRITING_PRINCIPLES.md) | B2B proposals / RFPs | Requirement reading (R1–R4), interpretation (U1–U4), structure (S1–S6), section writing (W1–W14), quality checklist |
| [SALES_PRESENTATION_SLIDE_PRINCIPLES.md](./SALES_PRESENTATION_SLIDE_PRINCIPLES.md) | Sales / marketing decks | Buyer-first slides, one message per slide, decision story, proof, objections, Thai term discipline |
| [SALES_FEATURE_COPY_PRINCIPLES.md](./SALES_FEATURE_COPY_PRINCIPLES.md) | Product Feature Catalog | Sales names and 1–2-sentence summaries — not config objects |
| [CANONICAL_VIEW_COPY_PRINCIPLES.md](./CANONICAL_VIEW_COPY_PRINCIPLES.md) | **Moved** — pointer only | Author in `rocket-sales/commercial/COPY_PRINCIPLES.md` |
| [SALES_AGENT_OUTPUT_PRINCIPLES.md](./SALES_AGENT_OUTPUT_PRINCIPLES.md) | Sales agent consult | Client-ready paste, then a short briefing; lighter than engineering output |
| [WEB_PAGE_COPY_PRINCIPLES.md](./WEB_PAGE_COPY_PRINCIPLES.md) | Web content (LP, blog, SEO, links) | **Part 1** landing copy · **Part 2** blog/articles · **Part 3** SEO strategy · **Part 4** internal linking |
| [TRANSLATION_PHILOSOPHY.md](./TRANSLATION_PHILOSOPHY.md) | Localization | Localize-don't-translate, English term policy, complexity spectrum, market-specific overrides |
| [TRANSLATION_PRINCIPLES.md](./TRANSLATION_PRINCIPLES.md) | Proposal Thai | Formal proposal localize craft, smoothness rules, English-first + `th/` convert with English backup |
| [THAILAND_CONTEXT.md](./THAILAND_CONTEXT.md) | Thai market context | Canonical Thai vocabulary for Rocket product terms, register by surface, recurring calque traps |
| [FEATURE_GUIDE_WRITING_PRINCIPLES.md](./FEATURE_GUIDE_WRITING_PRINCIPLES.md) | CRM feature guides | 8-section template, multi-audience, route maps, status models, line budget |

---

## `WEB_PAGE_COPY_PRINCIPLES.md` — part map

| Part | Page type | Key topics |
|------|-----------|------------|
| **Part 1** | Product landing pages | 5-second clarity, customer-as-hero, mental validation, persuasion, CTAs, Thai/English voice |
| **Part 2** | Blog & knowledge articles | Search journey stages, macro structure, E-E-A-T, earned CTA, consultant voice |
| **Part 3** | SEO (both page types) | Two-page model, intent tiers T1–T7, on-page signals, technical SEO, flywheel |
| **Part 4** | Internal linking | Pillar-cluster model, target tiers, AI workflow, cross-language rules |

---

## Source projects and selection rationale

### Rocket Deck (`Rocket-CRM/rocket-deck`)

| Chosen from Deck | Also existed in marketing | Why Deck version |
|------------------|---------------------------|------------------|
| `CORE_WRITING_PRINCIPLES.md` | — | Only canonical foundation doc |
| `PROPOSAL_WRITING_PRINCIPLES.md` | Shorter copy (376 lines) | Richer R/U/S/W framework (663 lines) |
| `SALES_PRESENTATION_SLIDE_PRINCIPLES.md` | Shorter copy (385 lines) | Richer slide patterns (580 lines) |

### Rocket CRM — marketing content

| Merged into | Original files |
|-------------|----------------|
| `WEB_PAGE_COPY_PRINCIPLES.md` | `LANDING_PAGE_COPY_PRINCIPLES.md`, `ARTICLE_PRINCIPLES.md`, `SEO_PRINCIPLES.md`, `INTERNAL_LINKING_PRINCIPLES.md` |
| `TRANSLATION_PHILOSOPHY.md` | Kept separate (cross-cutting localization, not page-type copy) |

### Supabase CRM (this repo)

| Chosen | Notes |
|--------|-------|
| `FEATURE_GUIDE_WRITING_PRINCIPLES.md` | Adapted from `.cursor/rules/13-feature-guide-writing.mdc`; pyramid/MECE deferred to CORE |

---

## Overlap handling

| Overlapping topic | Canonical home |
|-------------------|----------------|
| Pyramid / MECE / same-level grouping | `CORE_WRITING_PRINCIPLES.md` |
| Landing page copy craft | `WEB_PAGE_COPY_PRINCIPLES.md` Part 1 |
| Blog/article structure & voice | `WEB_PAGE_COPY_PRINCIPLES.md` Part 2 |
| SEO strategy & on-page signals | `WEB_PAGE_COPY_PRINCIPLES.md` Part 3 |
| Internal link architecture | `WEB_PAGE_COPY_PRINCIPLES.md` Part 4 |
| Localization (universal) | `TRANSLATION_PHILOSOPHY.md` |
| Proposal Thai convert | `TRANSLATION_PRINCIPLES.md` |
| Journey walkthroughs (proposals) | `PROPOSAL_WRITING_PRINCIPLES.md` |

Some topics appear in multiple parts by design (e.g. 5-second hero rule in Part 1 and Part 3) — each part is self-contained for its page type.

---

## External references (not in this folder)

- `ROCKET_PRODUCT_MESSAGING.md` — marketing content / product marketing folder
- `platform-overview.md` — product marketing
- CRM feature truth — CRM Knowledge MCP

---

## MCP retrieval protocol

Hosted as **`writing-principles`** MCP (same infra as CRM Knowledge, separate token). Git in this folder remains canonical; DB blocks are regenerated from markdown.

### Universal foundation

**`core-writing` applies to every task.** Always fetch core principles before a genre playbook — proposals, slides, web copy, feature guides, and localized copy all inherit pyramid logic, MECE, and specificity rules from `CORE_WRITING_PRINCIPLES.md`.

### Truth boundary

| MCP | Role |
|-----|------|
| **Writing Principles** | Craft — structure, voice, checklists, persuasion |
| **CRM Knowledge** | Product facts — capabilities, limits, feature behavior |

Compose both for Rocket proposals, decks, and feature guides that mention platform capabilities.

### Default tool sequence

1. `writing_get_my_context` — scopes, allowed genres, this protocol
2. `writing_get_core_principles` — universal anchor (cheap)
3. `writing_resolve_genre` — if genre unclear ("RFP", "landing page", "SEO blog")
4. `writing_search_guidance` — natural-language question across writing blocks
5. `writing_get_playbook_context` — deterministic blocks for one slug (+ `part` for web)

### Task → playbook composition

| Task | Playbooks (in order) | Also call |
|------|----------------------|-----------|
| Cold email, blog, landing, SEO page | `core-writing` → genre slug → `translation` (if localized) | — |
| B2B proposal / RFP | `core-writing` → `proposal-writing` | CRM `search_semantic` for feature facts |
| Custom / government proposal Thai | `core-writing` → `proposal-writing` → `TRANSLATION_PRINCIPLES.md` (manual convert) | general-proposal workflow; no CRM Knowledge facts |
| Sales / marketing deck | `core-writing` → `sales-slides` | CRM `get_feature_context` if feature-specific |
| Catalog names / summaries | `core-writing` → `SALES_FEATURE_COPY_PRINCIPLES.md` | CRM Knowledge; live catalog |
| Pricing sheet / features summary | Open `rocket-sales` pack → `commercial/COPY_PRINCIPLES.md` | Live catalog (required); Product Narrative optional color |
| Thai / JP / TW copy | `core-writing` → genre → `translation` → market context doc | Thai: `THAILAND_CONTEXT.md` for vocabulary. Proposals: prefer `TRANSLATION_PRINCIPLES.md` over web tone |
| CRM feature guide | `core-writing` → `feature-guide-writing` | CRM `get_feature_context` for the feature |
| Web content | `core-writing` → `web-page-copy` (routing) → one part slug | See part map below |

**Web routing:** call `writing_get_playbook_context(web-page-copy)` for "Which part to use", then exactly one of `web-landing-copy`, `web-article-copy`, `web-seo-strategy`, or `web-internal-linking`. Do not load all four parts at once.

### Regenerate DB seed

```bash
python3 scripts/generate_writing_principles_seed.py
# Review generated/writing-principles/audit.md — load requires approval
```

Feature tree metadata: `generated/writing-principles/feature-tree.json`

## Suggested MCP tool mapping

| Tool | Returns |
|------|---------|
| `writing_get_core_principles` | All blocks on `core-writing` |
| `writing_get_playbook_context(slug)` | Deterministic blocks for one playbook |
| `writing_search_guidance(query)` | Vector search scoped to writing slugs |
| `writing_resolve_genre(term)` | Maps "RFP", "landing page", etc. → slug |
| `writing_get_playbook_tree` | Feature tree under `writing-principles` |
