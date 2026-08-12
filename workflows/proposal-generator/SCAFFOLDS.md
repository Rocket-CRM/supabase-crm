# Scaffolds — the section grammar

The proposal is not "write a proposal." It is **a list of typed sections, each with required slots, a word floor, and its own reading list.** Omission is a failure, not a style choice. This file is the only thing standing between a 3k-word coverage memo and a 10k-word proposal.

Ported from the production writer at `rocket-internal/src/proposal/v2/knowledge/guidance/structure.md`. That file stays authoritative; this is the interactive-thread condensation.

## Granularity — the highest-leverage rule

**One `feature_module` per capability, not per domain.** A single "Loyalty programme — earn, tiers, redeem" H2 is the failure mode: it produces ~650 words for the entire loyalty story. Earn/wallet, rewards catalogue, reward sourcing, tiers, and member identity are **separate H2 sections**, each with its own journey, feature anchors, and fit table.

If a capability is in scope and has a functional requirement, it gets its own section. If it is licensed but not configured for go-live, it goes in `additional_features` — never silently dropped.

## Phase order

Write in this order; compile in document order afterwards.

1. **Foundation** — `glossary`, optional `concept_unification`
2. **Body A** — `feature_module` (member-facing), `data_ownership`, `reward_sourcing`
3. **Body B** — `feature_module` (ops/admin), `operations_support`, `admin_portal_and_reports`, `additional_features`, `phase_summary`, `integration_architecture` (**always last**)
4. **Summaries** — `executive_summary`, `implementation_matrix`, `clause_coverage_matrix` (when a TOR exists)

The executive summary is written **last** and compiled **first**. It summarises; it never introduces new claims.

## Section types and required slots

Slots are ordered and mandatory. A section missing a slot is not done.

### `feature_module` — member-facing (earn, rewards, redemption, tiers, identity)

1. **Journey walkthrough** — channel, persona, realistic steps in member/guest/agent vocabulary
2. **Core concept** — one sentence, stated as the **configuration model** (not an anecdote)
3. **Rocket CRM features in this section** — bulleted list of real CRM feature names
4. **What it does** — operator and configuration detail
5. **`### Fit summary`** — table: Requirement (plain language, no FR/NFR codes) | Coverage (Supported / Partial / New development) | Notes

**Floor: 700–1,200 words.** Primary-deliverable sections take more depth than siblings.

Type-specific requirements:

- **Earn** — describe earn conditions (rule types, property dimensions, grouping) **before** rate examples. If the customer calculates earn outside Rocket today, use the **dual-path scaffold**: Path A = customer-operated pre-calculated posting, Path B = Rocket Earn Engine native rules — **equal structural weight**, not a single headroom bullet.
- **Rewards catalogue** — per-reward limits and **reward groups** (bundle limits, Max Distinct, Group Quantity) belong inside this section, not a sibling.
- **Tiers** — qualification, upgrade/downgrade, and review mechanics **before** any UI example.
- **Earn + purchase MECE** — one earn/wallet section owns the member narrative; purchase ledger and marketplace ingestion are `###` subsections or cross-refs.

### `feature_module` — customer service (inbox, ticketing, AI agent, KB, voice)

Same five slots, but slot 1 is a **service interaction** — a realistic contact scenario for this customer, using contact-centre intents from the dossier, not a loyalty journey. AI sections must include **named AOP examples** with tool/action steps and escalation branches.

**Floor: 700–1,200 words.**

### `glossary` (Foundation)

Two columns: Customer concept (their word) | Rocket CRM construct (what we configure). Add **`### Concept splits`** when one customer word hides two platform patterns — Pattern A / Pattern B with a short table.

### `data_ownership` (Body A)

One table, one per proposal: Data domain | Master | Consumers | Sync direction | Notes. Use real customer system names.

### `reward_sourcing` (Body A, when rewards are in scope)

Open with **Reward Strategy** — how the mix fits this customer's member lifestyle and programme utility. Then: feature anchors → **inventory model** (pay-per-use catalogue vs merchant-owned privileges) → **fulfilment channels** (digital vs physical) → **geographic coverage and timelines** (label as commercial targets, not platform guarantees) → **redemption and fulfilment flow** → **exceptions** (damaged/wrong item, case window, replacement) → Fit summary.

No supplier/subcontractor/network language. Never conflate inventory with fulfilment. **Floor: 700–1,000 words.**

### `admin_portal_and_reports` (Body B)

Open with a **Scope note** (2–3 sentences): this is a **catalogue**, not configuration walkthroughs; invite a live demo for depth. Then:

1. **`### Admin configuration areas in scope`** — grouped bullets, one brief line per area
2. **`### Reports in scope`** — a `####` heading per in-scope domain, then **every in-scope report named** (Report | What it shows | Typical use)

Never list a domain label without its named reports. **Floor: 800–1,200 words** when loyalty reporting is in scope.

### `additional_features` (Body B)

Scope note: licensed on the platform but **not configured for go-live** here; included to show breadth. Include in-scope capabilities with no go-live functional requirement and no deep section of their own. **300–600 words**, with `###` subsections for flagship items (especially Display Settings). Not shipping this phase does not mean shallow copy.

### `integration_architecture` (Body B, always last)

Intro → integration table (System | Role | Direction | Data | Mechanism | Notes) → one `###` per integration domain that has a **real external contract**. Omit domains with no customer integration — Rocket-operated reward fulfilment gets at most one sentence in the intro. Wire-level detail lives **only** here.

### `operations_support` (Body B)

Merge canonical operations content with this run's operational nuances. Preserve SLA/severity/governance. Weave nuances in; no appended "project-specific" tail.

### `phase_summary` (Body B)

Summarisation only, no new content: phase outcome → scope → deliverables → dependencies, cross-referencing body sections.

### `executive_summary` (Summaries, written last)

**Current state → New state → Impact on this customer's named pains** — the pains must be specific and traceable to the dossier (e.g. "elderly members cannot self-redeem", "call centre chases shipment status manually"), never generic transformation language. Primary themes ~250–400 words; Why Rocket ~400–550; **≤1,100 words total.**

### `implementation_matrix` / `clause_coverage_matrix` (Summaries)

Compressed tables. The clause matrix exists only when a TOR or numbered requirement list was supplied, and then **every clause** gets a row.

## Per-section reading list (the excerpt step)

The old system programmatically injected a `feature_excerpt` into every write call. Here the agent reads it directly — **before** writing each section, open two things:

1. The matching anchors in `docs/PRODUCT_NARRATIVE.md` (`###` capability anchors) — platform detail.
2. The **source-brief sections** carrying this section's requirements — customer detail, in their words.

Writing from memory of an earlier MCP pull, or from the dossier's summary of the brief, is the single most common cause of thin prose. Word floors are floors, not budgets: total document length is whatever the in-scope capabilities and their evidence justify.

| Section topic | Catalog anchor(s) — `### ` headings |
|---|---|
| Rewards catalogue, redemption | `Rewards` · `Packages` · `Stored Value Cards` |
| Earn, wallet, currency | `Currency` · `Activity-Based Earning` · `Purchase Transactions` |
| Tiers | `Tiers` |
| Member identity, consent, access | `Authentication & Signup` · `PDPA Consent` · `Persona Entitlements` · `Tags & Personas` |
| Campaigns, engagement mechanics | `Missions` · `Spin Wheel` · `Mass Lucky Draw` · `Referral` · `Check-in` |
| Marketing automation, AI decisioning | `AMP Workflows` · `AMP AI Decisioning` |
| CS digital, voice, routing | `Connectivity` · `Agent Workspace` · `Ticket Management` · `Rules-Based Automation` |
| CS AI agent, AOPs, KB | `CS AI` · `Knowledge Base` · `Actions & Integrations` |
| CS quality and reporting | `CSAT & Customer Feedback` · `Analytics & Logs` |
| Partner and store classification | `Store & Partner Classification` |
| Forms and surveys | `Forms` |
| Localization | `Translation System` |
| Admin and reports | `Admin Portal — Configuration Surfaces` · `Reports — What the Brand Sees Back` |

Locate anchors with `rg -n "^### Rewards" docs/PRODUCT_NARRATIVE.md` and read the range to the next `###`. Do not trust remembered line numbers — the narrative moves.

For facts not in the catalog, use the CRM Knowledge MCP (`get_feature_context`, `resolve_feature_term` for customer vocabulary). `is_active = false` blocks are retired and never claimable.

## Self-check before Review

Run this against the compiled draft and report the result in chat. It replaces the old system's lint job; it is a checklist, not code.

- Every in-scope capability either has its own section or a line in `additional_features`.
- Every `feature_module` has all five slots, including a named-feature list and a `### Fit summary` table.
- No section is below its floor, unless the dossier genuinely lacks the evidence — then say which and why.
- Earn describes conditions before rates; tiers describe qualification before UI; rewards cover group limits.
- The executive summary names this customer's specific pains, and introduces no claim absent from the body.
- Every capability claim traces to the catalog or an active knowledge block.
- Wire-level detail appears only in `integration_architecture`.

Report shortfalls as `[GAP: …]`. A thin section flagged honestly is Reviewable; a thin section presented as complete is the failure this file exists to prevent.
