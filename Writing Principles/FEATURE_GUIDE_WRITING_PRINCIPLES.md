# Feature Guide Writing Principles

### Structured product docs for testers, marketing, CS, and product

---

## Purpose

These principles govern **Feature Guides** in `requirements/feature-docs/`. They sit between deep technical requirement specs (`requirements/*.md`) and the codebase. They are not for engineers building the feature — those use the requirement docs.

For universal structure, clarity, and voice rules, read `CORE_WRITING_PRINCIPLES.md` first. This document adds format-specific rules only.

---

## Audiences (all four, in every section)

1. **AI Testing Agents** — config→behavior mappings, assertions, edge cases
2. **Marketing / Design** — value propositions, use-case stories, plain-language descriptions
3. **Customer Success** — onboarding scripts, FAQ answers, troubleshooting
4. **Product** — capability inventory, feature connections, quick reference

---

## Template — 8 Sections

Every guide follows this exact structure:

| # | Section | Tone | Primary consumers |
|---|---|---|---|
| 1 | Overview | Natural prose, 2-3 paragraphs | Marketing, Product, CS |
| 2 | Key Concepts | Term → definition → example | All (glossary) |
| 3 | Configuration Reference | Tables grouped by admin UI sections | Testers, CS |
| 4 | Admin Journey | Numbered steps with route map | Testers, CS |
| 5 | Member Experience | Numbered steps with route map | Testers, Marketing |
| 6 | Perspectives (CS / Marketing / Testers) | Audience-specific language | One subsection per audience |
| 7 | Business Rules | Rule + Example format | Testers, CS, Product |
| 8 | Related Features | Table: feature → one-sentence connection | All |

---

## Gathering Information — Three Sources

Before writing, gather from all three:

1. **Local requirement docs** (`requirements/*.md`) — business rules, concepts, schemas, API specs
2. **GitHub MCP → `Rocket-CRM/loyalty-admin`** — admin journey (routes, form fields, buttons, validation)
3. **GitHub MCP → `Rocket-CRM/loyalty-user`** — member journey (screens, drawers, navigation, states)

Read `ProjectDocs/FE_docs/` in both repos for page-level documentation. Read actual component files for details not covered in docs.

---

## Writing Principles (Feature Guide Specific)

### Progressive Disclosure

Sections 1-2 are human-readable with natural prose — they orient the reader. Sections 3-8 are dense and structured (tables, bullets, numbered steps). Minimize prose in later sections.

### Concrete Logic Over Fluffy Statements

Default to describing specific system behavior — what triggers, what matches, what the user sees. Reserve broad statements for the Marketing perspective (6b) where positioning language is the point.

| Fluffy | Concrete |
|---|---|
| "Powerful dynamic pricing engine" | "Matching engine evaluates 4 dimensions (tier, user type, persona, tags) and picks the highest-specificity match" |
| "Seamless real-time redemption experience" | "Member taps Redeem → gets event_id immediately → result arrives via Realtime subscription within seconds" |

### Specificity Over Vagueness

Every vague phrase can be replaced with a specific one. The specific version always wins.

| Vague | Specific |
|---|---|
| "Supports multiple fulfillment methods" | "Four methods: digital, shipping, pickup, printed" |
| "Flexible pricing" | "Points cost varies by tier, persona, and tags via 4-dimension matching" |
| "Real-time processing" | "Async: member gets event_id immediately, result arrives via Realtime within seconds" |

### Anti-AI Voice

No filler words or phrases: "comprehensive," "robust," "seamless," "cutting-edge," "it's important to note that," "in order to," "leverage." If a sentence still communicates value after removing the modifier, the modifier was filler.

---

## Context Efficiency Rules

There will be ~20 feature guides. Multiple may load simultaneously. Every wasted line is multiplied.

### No Redundancy Within a Doc

- Define a term ONCE in Key Concepts. Other sections use it without re-explaining.
- State a business rule ONCE in Business Rules. Journeys reference the rule by its effect.
- Configuration is described ONCE in Configuration Reference. Admin Journey says "fill in the eligibility conditions" not "set the allowed tiers, personas, and birth month filters."

### No Redundancy Across Docs

Each guide owns its domain. Other domains get one-line references in Related Features.

- Do NOT explain how points work in the Rewards guide — that's Currency's job.
- Do NOT explain tier logic in the Rewards guide — just reference eligibility can be tier-gated.

### No Boilerplate

- No "In this section we will discuss..." introductions
- No "As mentioned above..." cross-references within the same doc
- No generic loyalty program explanations — the Feature Index provides platform context
- Jump straight into content

---

## Route Map Pattern

Do NOT hardcode route paths in journey steps — routes change and silently break the doc. Instead:

1. Place a **route map table** at the top of each journey section (Admin Journey, Member Experience)
2. The table maps: Page Name → Current Route → Data Source / BFF
3. Steps reference **page names only** ("From **Reward List**, click...")
4. When a route changes, update one row in the table — not every step

Also note the **repo** at the top of each journey section (`Rocket-CRM/loyalty-admin` or `Rocket-CRM/loyalty-user`).

---

## Status Models

When a feature has multiple status tracks (e.g., redeemed vs. used vs. fulfillment), enumerate all values and their relationships explicitly. Don't just say "status changes from X to Y" — show:

- All possible values for each status field
- Which transitions are valid
- How the statuses are independent or dependent
- What member-facing UI labels map to which status combinations

---

## Line Budget

**Target: 250–400 lines.** If you exceed 400 lines, you are being redundant. Cut repeated information, not coverage.

---

## Quality Checklist

Before finishing a feature guide:

- [ ] All 8 sections present with correct structure
- [ ] Key Concepts defines every term used in later sections
- [ ] Config Reference matches the actual admin UI form (verified from loyalty-admin repo)
- [ ] Route map tables present in Sections 4 and 5 — no hardcoded paths in steps
- [ ] Status model fully enumerated (all values, transitions, independence)
- [ ] No term re-explained after Key Concepts
- [ ] No business rule restated after Business Rules
- [ ] No cross-domain knowledge duplicated (one-line + link only)
- [ ] 6a/6b/6c don't overlap with each other or with earlier sections
- [ ] Under 400 lines
- [ ] No AI filler words (comprehensive, robust, seamless, leverage, cutting-edge)
- [ ] Feature Index updated

---

## Source

Adapted from `.cursor/rules/13-feature-guide-writing.mdc` in the Supabase CRM repo. Universal pyramid / MECE / same-level rules live in `CORE_WRITING_PRINCIPLES.md` — not duplicated here.
