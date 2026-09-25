# Product Feature Catalog Maintenance

## Goal

Create one executable maintenance workflow for:

1. The canonical Supabase feature catalog.
2. The derived sales Product Narrative.
3. A weekly Cursor Automation that reconciles both from requirements evidence.

## Architecture

- Product/engineering work updates `requirements/**/*.md` through documentation closeout.
- The existing doc-knowledge reconcile job derives CRM Knowledge chunks from requirements; it maintains the index, not the source documents.
- Supabase `internal_product_*` is canonical for feature identity, hierarchy, sales summary, examples, status, and package inclusion.
- `docs/PRODUCT_NARRATIVE.md` is derived customer-facing explanation for sales, proposals, and future sales-agent answers.
- CRM Knowledge remains the detailed evidence layer and continues indexing only `requirements/**/*.md`.
- Consumers:
  - Eng agent: CRM Knowledge plus live code/Supabase.
  - Sales agent: catalog + Product Narrative + CRM Knowledge.
  - Proposal workflow: the same three inputs; proposals are outputs.

## Source precedence

1. Catalog controls whether a feature exists, where it belongs, its status, and package inclusion.
2. Requirements/CRM Knowledge control how the feature behaves.
3. Product Narrative controls customer-facing explanation only.
4. A conflict stops the affected update and is reported; narrative never updates the catalog in reverse.

## Deliverable 1 — Workflow reference

Create `workflows/product-feature-catalog/REFERENCE.md` first and review it before catalog writes.

It must contain:

1. Purpose and audience.
2. Source-of-truth contract.
3. Catalog schema.
4. Feature row granularity rules.
5. Three-module taxonomy.
6. Feature Catalog Writing Guide.
7. Product Narrative Writing Guide.
8. Evidence/status/package rules.
9. Transactional maintenance procedure.
10. Quality checklist and run-summary format.

### Feature Catalog Writing Guide

- Exactly three levels: Module → Feature group → Feature.
- A row represents a distinct end-user capability that can be recognized, compared, or sold.
- Package membership never creates the taxonomy.
- Preserve stable keys; labels and group placement may change.
- Summary: one or two plain sentences describing actor → behavior → outcome.
- Thai columns: `name_th` + `summary_th` on `internal_product_feature`. Localize from English using `Writing Principles/TRANSLATION_PHILOSOPHY.md`, `TRANSLATION_PRINCIPLES.md`, and slide §6 English-term policy — do not word-for-word translate; keep market-standard technical terms in English. Full rules live in `workflows/product-feature-catalog/REFERENCE.md` §6.1.
- `includes`: only a clarifier/example that materially prevents misunderstanding.
- Split basic/advanced when they are distinct comparable capabilities.
- Use `ga`, `beta`, `planned`, or `deprecated`; stale copy is a verification condition, not product status.
- No implementation jargon, generic superlatives, unsupported numbers, or invented package placement.

### Product Narrative Writing Guide

Audience: marketer, salesperson, proposal writer, or buyer asking what a feature does and why it matters.

Each module gets a short introduction covering its promise, operating journey, and how its groups work together.

Each feature gets one `###` section mapped to its stable feature key:

1. **What it enables** — buyer-facing what + why.
2. **How it works** — admin/customer journey in operating order.
3. **What differentiates it** — concrete behavior or flexibility.
4. **Key controls** — customer-relevant choices, not schemas/functions/exhaustive enums.
5. **Example** — optional and only when it materially clarifies the mechanism.

Voice is consultative, specific, outcome-led, and proposal-ready. Planned/beta status must be explicit. Every material claim traces to the canonical row or requirement evidence.

## Deliverable 2 — Canonical catalog rework

Use exactly three active public modules:

### Loyalty

Capability groups cover:

- Foundation and acquisition.
- Points and earn channels.
- Rewards and burn.
- Tiers.
- Campaigns.
- Lifecycle automations.
- Customer profile and Customer 360.
- Segmentation and RFM.
- Analytics and reports.
- Admin, data operations, and integrations.

Explain the overall journey as acquisition → engagement → campaigns → analysis → activation without using those outcomes as overlapping feature rows.

Required corrections:

- Fold current App foundation rows into Loyalty while preserving stable feature keys.
- Keep Campaigns inside Loyalty.
- Rename Lifecycle outcomes to lifecycle automation language.
- Explain advanced earn rates with different rates by channel.
- Explain multipliers with double points for selected products/categories.
- Include Customer 360, segmentation/RFM, and reporting categories.
- Use “30+ reports” only if the current inventory verifies it.

### Marketing Automation

Three primary groups:

1. Deterministic multi-step workflow automation.
2. AI decisioning agents.
3. AI analysis and recommendations.

Workflows may condition on customer data and execute messages plus loyalty actions. AI decisioning receives goals, allowed actions, outcomes, and constraints, then reviews customer context and chooses ACT, WAIT, or SKIP.

### Customer Service

Capability groups cover:

- Omnichannel inbox and connectivity.
- Chat and voice.
- Agent productivity, quick replies, and knowledge search.
- Routing and chatbot workflows.
- Service analytics.
- AI service agent.
- AOPs, knowledge, and customer actions.
- Supervisor AI and quality scoring for human and AI cases.

## Deliverable 3 — Product Narrative transition

- Rename `docs/PRODUCT_FEATURE_CATALOG.md` to `docs/PRODUCT_NARRATIVE.md`.
- Preserve feature anchors.
- Update references in `workflows/proposal-generator/REFERENCE.md` and its scaffolds/resources.
- Recontract the document as derived sales copy, not a competing source of truth.
- Update only sections affected by changed/overdue catalog rows; never rewrite the full document on every weekly run.
- Narrative changes are reviewable Git diffs before they become proposal fuel.

## Deliverable 4 — Provenance and audit controls

- Add `source_refs` and `last_verified_at` to feature rows.
- Add one append-only catalog change log for module, group, feature, and package changes.
- Store run identifier, entity key/type, change type, before/after snapshots, source references, and timestamp.
- Apply each catalog run transactionally.
- Never delete a formerly valid feature; deprecate it with evidence.

## Deliverable 5 — Weekly Cursor Automation

Run in `Rocket-CRM/supabase-crm` and read the committed `workflows/product-feature-catalog/REFERENCE.md` first.

Run order:

1. Inspect recent requirement changes plus catalog rows overdue for verification.
2. Gather targeted CRM Knowledge evidence; use scoped requirement reads only when needed.
3. Classify each candidate as add, update, move, deprecate, or no change.
4. Update the Supabase catalog and audit log transactionally.
5. Synchronize only affected Product Narrative sections.
6. Validate hierarchy, statuses, packages, source references, narrative anchors, and proposal references.
7. Report changed/skipped/conflicting rows and the narrative Git diff.

Before creating the Automation:

- Commit and push `REFERENCE.md` after explicit user approval.
- Verify CRM Knowledge and Supabase connections are eligible and authenticated.
- Confirm schedule and model.
- Show the Automation draft table for approval.
- Open the Automations editor for final save.

## Next-thread execution order

1. Work only in `/Users/rangwan/Documents/rocket/supabase-crm`.
2. Inspect repo status and stop if unrelated local changes overlap target files.
3. Author and present `REFERENCE.md`.
4. After approval, rename/recontract Product Narrative and update proposal references.
5. Apply provenance/audit migration.
6. Rework/seed the three-module catalog in one transaction.
7. Synchronize affected narrative sections.
8. Validate all acceptance criteria.
9. Return the complete canonical table and narrative-change summary in chat.
10. Ask for explicit commit/push approval before wiring the Automation.

## Acceptance criteria

- Exactly three active public modules: Loyalty, Marketing Automation, Customer Service.
- Every active feature has one group, stable key, clear summary, valid status, source reference, and verification time.
- Package assignments are structured and evidence-backed.
- Loyalty contains the requested lifecycle, customer intelligence, analytics, and configurable-program distinctions.
- Marketing Automation cleanly separates workflows, AI decisioning, and AI analysis.
- Customer Service cleanly separates non-AI operations, AI service/AOP actions, and supervisor scoring.
- Product Narrative maps to canonical feature keys and contains no unsupported status/package claims.
- Product Narrative is not indexed into CRM Knowledge.
- Proposal workflow resolves the renamed narrative path.
- Automation logs all direct catalog changes and produces reviewable narrative diffs.
