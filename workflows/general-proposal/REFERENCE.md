# General proposal workflow — REFERENCE

Thin Cursor workflow for **custom / government / non-productized** project proposals. One interactive thread, one run folder. Stages are a recommended order — not a phase machine, not a form validator.

For Rocket CRM loyalty proposals, use `workflows/proposal-generator/` instead.

## Purpose

Turn whatever bid materials a salesperson already has (TOR, e-bidding pack, notes, answers) into a **submission package plan** and the **customer-facing documents this workflow can draft**. The run folder is the only state — any fresh thread pointed at the same folder can resume.

There is **no product knowledge base**. Facts come from `sources/` and human answers. Writing craft comes from `Writing Principles/` (or the Writing Principles MCP). Schema/function conventions in this repo may inform *how* to describe a proposed design when the TOR asks for that depth — they are not a catalogue of claimable product features.

**One workflow.** Document groups, asset libraries, plan, produce, pack assemble, review, and optional Thai convert are stages of this file — not a separate meta-workflow on top of EECO.

## The four objects

1. **Input** — run-specific material (TOR extracts, notes, clarification answers, review corrections). Never shared across customers.
2. **Resource** — durable shared guidance and **canonical asset libraries** under `resources/` (see Resources table). Read; do not invent a parallel schema.
3. **Output** — what this run writes: `submission-plan.md`, `manual-requests.md`, `dossier.md`, `outline.md`, `sections/`, compiled customer docs (English at run root), optional `th/` after a manual Thai convert, optional `mockup-prompts.md`, `submission-pack/`.
4. **Review** — human gate. Accept, correct, or redirect. Corrections become new Inputs.

## Design stance

- Prefer judgment and Review gates over checklists that force false precision.
- Classification labels and section types are **vocabularies**, not validators.
- Document groups are a **flexible catalog** — include, omit, or add per bid (`resources/document-groups-catalog.md`).
- Worked examples (e.g. EECO-style Part 1/2) illustrate; they are not the only legal package shape.
- Depth is a **judgment note** in the dossier, with TOR citations — not a closed enum that gates writers.
- Outline fields in SCAFFOLDS are useful headings, not a required schema.
- Visual rules are defaults; skip visuals when prose is enough. A visual that carries unique branching, ownership, interface, data-relation, or timing semantics is **content**, not decoration, and cannot be removed without preserving that meaning elsewhere.
- For custom/government runs, this REFERENCE and SCAFFOLDS take precedence over loyalty-oriented examples in `PROPOSAL_WRITING_PRINCIPLES.md`. Identical module scaffolds, SCQA section narration, and per-module closing matrices are out unless this bid’s content benefits from them.

## Intake (deliberately lax)

No required fields. Any material in any format is a valid start.

1. **Read everything first** — `sources/`, pasted messages, Resources. No question before this.
2. **Judge sufficiency** — can you plan the submission and draft the generated docs seriously?
3. **Ask in Clarify** (see stages) — ranked, few, impact-ordered. Prefer either/or.
4. **Never invent.** Unanswered items become `[GAP: …]` or stated assumptions after the human defers or says proceed.

### Project context chain (no hidden MCP)

General-proposal project context is retrieved through three run artifacts:

1. **`sources/`** — authoritative TOR, pack extracts, and human answers.
2. **`dossier.md`** — agent-written index into those sources with exact locations, depth judgment, decisions, and gaps; it does not replace the source.
3. **`outline.md` `reads`** — per-section pointers that tell writers which source locations to reopen before drafting.

There is no general-proposal project-context MCP or automatic TOR-to-context object. If `dossier.md` or an outline `reads` entry is absent, build it from `sources/`; do not infer context from a prior proposal or product knowledge base.

## Run folder

`workflows/general-proposal/runs/<customer-or-project>-<yyyymm>/`

```
sources/              # Inputs, verbatim — never edited in place
submission-plan.md    # Document groups + docs + classification (plan artifact)
manual-requests.md    # Staff-facing list of manual / library pulls needed
dossier.md            # Index over sources + depth judgment + decisions
questions.md          # Optional log of Clarify rounds / answers summary
outline.md            # Plan proposal writing — section / visual / evidence plan
sections/             # One file per section (or per doc/section) — English
proposal.md           # Compiled main technical/approach narrative (English) — name may vary
comparison-matrix.md  # When the bid requires a requirement comparison table (English)
pricing-breakdown.md  # When pricing group is included (English)
en/                   # Optional frozen English snapshot taken at first Thai convert
th/                   # Thai localize output (only after manual trigger) — see Language
  proposal.md         # Thai compiled narrative (and other customer docs as needed)
  sections/           # Optional Thai section files
  translation-review.md
mockup-registry.json  # Mockup ids → loyalty-admin paths + briefs (see MOCKUPS.md)
loyalty-admin-handoff-prompt.md  # Generated paste prompt for one admin thread
preview/              # HTML preview with live iframes (mockups:preview)
diagrams/             # React / HTML conceptual diagrams (executive-overview required)
  executive-overview/ # PillarMatrix: Current → Future → Impact (every run)
assets/               # Captured PNGs (mockups:capture)
submission-pack/      # Assembled upload folders + CHECKLIST.md
principles-review.md  # Proposal review findings
```

File names may adapt to the bid. The folder is the audit trail and resume point. **English at the run root is the review source of truth and the backup after Thai convert — never overwrite it with Thai.**

## Stages (recommended order)

Skip or merge when a run is thin. Re-enter **Clarify** whenever new material gaps appear.

| # | Stage | Typical output | Human gate |
|---|---|---|---|
| 1 | Document categories + classify | `submission-plan.md` — groups → docs → class | **Review A** |
| 2 | Understand | `dossier.md` — index + depth judgment | — |
| 3 | **Clarify** | Ranked questions; answers → `sources/` / dossier | **Before Plan / Write** |
| 4 | Manual request list | `manual-requests.md` — one staff-facing MD | — |
| 5 | **Plan proposal writing** | `outline.md` (+ visual / evidence / personnel / pricing plans) | **Review 2** |
| 6 | Produce (parallel) | AI: `generate` / `hybrid` shells · Humans: manuals + library pulls | — |
| 7 | Visuals | Mermaid / React; mockups; exec overview | (overlaps 6) |
| 8 | Combine into pack | `submission-pack/` layout + CHECKLIST | — |
| 9 | Late AI | Covers / forms that needed manuals or library picks first | — |
| 10 | **Principles / proposal review** | `principles-review.md` → adjust → polish | **Review 3** |
| 11 | **Thai convert + translation review** | `th/` + `th/translation-review.md` | **Manual trigger only** |

### 1. Document categories and classify

Use `resources/document-groups-catalog.md` as the standard catalog. For this bid: **include / omit / add** groups, list docs in each group, tag each row:

| Class | Meaning |
|---|---|
| `manual` | Human/ops/legal/bank must produce a **new** instrument; workflow does not draft it |
| `library` | Pull from canonical asset library (`resources/personnel/`, `project-proofs/`, `company-docs/`); face-check / copy into pack |
| `generate` | Workflow drafts customer-facing prose/tables |
| `hybrid` | Workflow drafts structure or shell; humans supply facts, signatures, or final assets (often after a `library` pull) |
| `out_of_band` | Not a written chapter (e.g. live POC); optional prep notes only |

**Review A** confirms inventory completeness and classification before heavy Clarify / Plan.

Past-work certificates and company registration PDFs that already exist in the library are typically `library` (not `manual`). Brand-new bank letters or wet signatures remain `manual`.

### 2. Understand (dossier)

The dossier is an **index over `sources/`**, not a compressed rewrite of the TOR.

- Point at source locations for requirement detail; do not paraphrase away substance.
- Extract verbatim vocabulary and boundary decisions the prose will need.
- Record a short **depth judgment**: how low-level this TOR expects writers to go (process narrative, architecture, data model, interface contracts, etc.), with clause citations. Individual clauses may demand more depth than the run average.
- Record **hosting / environment** from the pack (who procures prod hosts; on-prem vs cloud; vendor-agnostic min specs; what bidder may run only for non-prod/POC).
- Record **technical-practices context** (required before architecture/security Write): hosting model H1, ops ownership H2, async needs H3, reporting load H4, domain H5 — codes and pull list in `resources/standard-technical-practices.md`. Persist a short **Practices pull** (IDs in / IDs out / reason). Do **not** default to Rocket SaaS / Kafka / SIEM-SOC shapes on buyer-install bids.
- Record **operations-support context** (before ops Write): O1–O4 + **Ops pull** (S-IDs) from `resources/standard-operations-support.md`. Prefer a **separate** `operations_and_support` section when warranty/SLAs exist; keep **Support operations** vs **Technical operations** distinct.
- Record **timeline / migration context** (before delivery Write): T1–T4 + **Timeline pull** (D-IDs) from `resources/standard-delivery-timeline-migration.md`. Paste **verbatim TOR delivery dates**. Payment % may be noted in the dossier for writers — **do not** put Pay columns in customer prose. Migration code (`none` / `batch_file` / …) decides whether methodology is pulled.
- Record the **company-profile pull** before writing the introduction: approved company facts, exact evidence available, project-relevant differentiators selected, and claims excluded. Use `resources/standard-company-profile.md`; do not let company positioning imply a capability, hosting model, or implementation scope that the run does not propose.
- Record whether **beyond-minimum / “better” features** are allowed (comparison-table columns, scoring rubric). Note if there are true bonus points vs only qualitative upside inside existing factors. If used: **embed in feature subsections** + short end summary; scoring analysis stays in the dossier, never in customer prose.
- Prefer a **Core features** parent with subsections when the TOR clusters modules; feature tables carry an **Includes / sub-capabilities** column on the spine.
- Note which catalog groups are in/out for this run (pointer to `submission-plan.md`).
- Proposal length is independent of dossier length. Padding the dossier helps nothing.

### 3. Clarify (before Plan and Write)

Resolve high-impact unknowns **before Plan proposal writing** and Write.

- Do not ask what the pack already answers.
- One round of few ranked questions; each states why it matters for a specific doc or section. Prefer either/or.
- A second round is fine; a third is a smell — convert leftovers to `[GAP: …]` / assumptions once the human defers or says proceed.
- **Do not start Plan or Write** until the human has answered, deferred, or explicitly said proceed with gaps.
- Re-enter Clarify mid-write if a section is blocked on a material fact.
- Persist answers as Inputs (`sources/answers-….md` or dossier decision bullets).
- Typical Clarify topics: past-work set + stretch framing, personnel role map, pricing inputs, hosting ownership, extras allowed, which optional groups to include.

### 4. Manual request list

Write **one** staff-facing markdown file: `manual-requests.md`.

- Shape: `resources/manual-request-template.md`.
- List every `manual` item and every `library` item that still needs a human to locate, refresh, or face-check.
- Include enough bid context that staff understand *why* (e.g. evidence must be stretchable into this category of work).
- Finalize after Clarify so stretch/context is accurate; a stub after stage 1 is fine.

### 5. Plan proposal writing (Review 2)

**Plan and Write are separate stages.** This stage does not draft customer prose.

Produce `outline.md` covering (see SCAFFOLDS “Plan proposal writing SOP”):

| Plan artifact | Decides |
|---|---|
| Section plan | Chapters for included Proposal (+ Pricing) groups; TOR order vs regroup |
| Depth map | Light / normal / deep per section |
| Resource pulls | Company profile, tech practices, ops, timeline — IDs in/out |
| Visual plan | Exec overview (mandatory); mockups `Mxx`; mermaid vs React |
| Evidence plan | Project-proof picks + stretch framings (`resources/project-proof-stretch.md`) |
| Personnel plan | Role ↔ person from `resources/personnel/roster.csv` (`personnel-role-fit.md`) |
| Pricing plan | Whether / how to write pricing breakdown (`pricing-breakdown.md` resource) |
| Write order | Section sequence; executive summary **last** |
| Open gaps | `[GAP]` that block Write vs hybrid leftovers |

**Review 2** accepts the plan before Produce.

### 6–7. Produce (parallel) and Visuals

**AI track** — draft every `generate` item and `hybrid` shells that do not wait on manuals:

- Prefer the **TOR’s own section/subsection order** for capability chapters when it helps evaluators **find** coverage — but write each chapter as **features and journeys** (SCAFFOLDS “Requirements covered by features”).
- **Exact TOR text** in matrix / in-body requirement presentation — verbatim from `sources/`.
- **No target length.** Customer-facing only in compiled outputs.
- **Draft language: English first.** Thai is stage 11 only.
- Prefer one section per turn for large documents.
- Before writing a section, open its source locations — not the dossier summary alone.
- **Architecture / security:** `resources/standard-technical-practices.md` (practice IDs in outline `reads`).
- **Delivery timeline:** `resources/standard-delivery-timeline-migration.md`. TOR **delivery** dates sovereign. **No payment %** in technical narrative.
- **Operations & support:** `resources/standard-operations-support.md`.
- **Company introduction:** `resources/standard-company-profile.md`.
- **Pricing breakdown** (when group included): `resources/pricing-breakdown.md`; facts from Clarify / human — do not invent commercial numbers.
- **Voice:** SCAFFOLDS owner-facing voice test.

**Human / library track** — fulfill `manual-requests.md`; copy `library` assets into `submission-pack/`.

**Visuals** (overlap with Produce):

| Need | Default |
|---|---|
| Conceptual / non-technical | React under `diagrams/` |
| **Executive overview** (mandatory) | Current → Future → Impact + `PillarMatrix` at `diagrams/executive-overview/` via `{{diagram:executive-overview}}` **immediately under** the section heading (before theme prose). Mermaid timelines: A4-safe `TB` / phase subgraphs. Thai delivery-team names from Appendix B / personnel canon. |
| Technical sequence / process | Mermaid |
| UI mockup | `{{mockup:Mxx}}` + registry + handoff (`MOCKUPS.md`) |
| Company intro visual | Optional one proof visual from approved sources |

Skip visuals when prose is enough. Government packs: real agency logo in registry `branding` before FE handoff.

### 8. Combine into pack

Assemble `submission-pack/` folders per `submission-plan.md`. Update `CHECKLIST.md` (Have / Remaining / N/A). Viewer / combined HTML uses **official document titles only** — no writer kickers (“pending”, “working roster”, etc.).

### 9. Late AI

Generate artifacts that **required** manuals or library selections first, for example:

- Project-evidence **cover summary** (amounts + stretchable scopes) after proof set is locked
- Personnel appendix forms after role map is locked
- Pricing narrative after commercial inputs arrive
- Any hybrid shell that was waiting on signatures-ready facts

Then re-combine affected pack folders.

### 10. Principles / proposal review and polish

After compile (or large rewrite) — or after late AI that changed customer prose:

1. Write `principles-review.md` (SCAFFOLDS prompts + Writing Principles + anti-slop).
2. Timeline alignment mandatory (`standard-delivery-timeline-migration.md`).
3. Proposal voice mandatory (propose to buyer; no TOR-echo / document choreography).
4. For any cut/merge/anti-slop rewrite, run a **coverage-preservation check**: compare before/after commitments, technical domains, TOR references, and visual inventory. Duplicate presentation may be removed; unique semantics may not.
5. Technical proposals must retain the accepted depth for architecture, system design, database design, security, integration, migration, operations, and delivery. Record any intentionally removed visual and where its meaning now lives.
6. Adjust sections; recompile.
7. Human **Review 3** on English customer docs → polish still in English.

### 11. Thai convert + translation review (manual trigger only)

Triggered only by explicit ask (“localize to Thai”, “Thai convert”, “run Thai localization”, “produce the Thai version”).

1. Read `Writing Principles/TRANSLATION_PRINCIPLES.md` (and `TRANSLATION_PHILOSOPHY.md` if needed).
2. Keep run-root English intact as backup.
3. Optionally snapshot English into `en/` on first convert.
4. Write localized customer docs under `th/`.
5. Write `th/translation-review.md` (findings + fixes). Human accepts Thai for submission packs.
6. Pack government submissions from `th/` unless told otherwise.

Do not mix English review text and Thai submission text in the same file.
Thai localization may rewrite sentences for natural Thai, but it must preserve accepted commitments, technical specificity, headings, tables, and semantic visuals. If the Thai review reveals structural slop that requires deleting or merging content, fix the English review source first and then re-localize the affected Thai sections. A human-authorized Thai-only structural change must be documented as a divergence and pass the same coverage-preservation check.

## Review junctures

| Gate | Reviews | Pass | Fail |
|---|---|---|---|
| Review A | `submission-plan.md` (groups + class) | Understand / Clarify may continue | Fix inventory or reclassify |
| Clarify | Questions answered or deferred | Plan may start | Wait / re-ask |
| Review 2 | `outline.md` (plan) | Produce may start | Restructure plan |
| Principles review | `principles-review.md` + adjusted sections | Ready for human Review 3 | Selective deepen / cut; recompile |
| Review 3 | Compiled **English** customer docs | Sendable English / ready for optional Thai | Polish affected English sections |
| Thai convert + translation review | `th/` + `th/translation-review.md` | Submission-ready Thai; English remains at root | Re-localize failed passages |

## Resources (craft + assets)

| Path | Role |
|---|---|
| `workflows/general-proposal/SCAFFOLDS.md` | Soft section grammar, plan SOP, visuals defaults, self-check |
| `workflows/general-proposal/resources/document-groups-catalog.md` | Standard document groups; include/omit/add per run |
| `workflows/general-proposal/resources/manual-request-template.md` | Staff-facing manual request MD shape |
| `workflows/general-proposal/resources/personnel-role-fit.md` | TOR role floors → roster match → controlled stretch |
| `workflows/general-proposal/resources/personnel/roster.csv` | Canonical team roster |
| `workflows/general-proposal/resources/personnel/README.md` | How to use the roster |
| `workflows/general-proposal/resources/project-proof-stretch.md` | Assess / stretch / cover-writing rules for past work |
| `workflows/general-proposal/resources/project-proofs/INDEX.md` | Canonical proof metadata + PDF paths |
| `workflows/general-proposal/resources/pricing-breakdown.md` | Pricing structure/summary scaffold when group included |
| `workflows/general-proposal/resources/company-docs/INDEX.md` | Canonical company standard docs index |
| `workflows/general-proposal/resources/standard-technical-practices.md` | Stack security + design patterns (P01–P15); context-gated |
| `workflows/general-proposal/resources/standard-operations-support.md` | Support ops vs technical ops (S01–S14) |
| `workflows/general-proposal/resources/standard-delivery-timeline-migration.md` | Milestones, migration, combined timeline + buffers (D01–D10) |
| `workflows/general-proposal/resources/standard-company-profile.md` | Approved Rocket facts, differentiation library, claim controls |
| `Writing Principles/CORE_WRITING_PRINCIPLES.md` | Pyramid, MECE, concepts-first |
| `Writing Principles/PROPOSAL_WRITING_PRINCIPLES.md` | Reading TOR, structuring, section writing |
| `Writing Principles/TRANSLATION_PRINCIPLES.md` | Proposal Thai localize craft + English backup / `th/` procedure |
| `Writing Principles/TRANSLATION_PHILOSOPHY.md` | Universal localize / English-term policy |
| Writing Principles MCP (`19-writing-principles-mcp.mdc`) | Same craft via MCP when available |
| `.agents/skills/anti-slop/SKILL.md` | When drafting or reviewing prose |

Do **not** use CRM Knowledge MCP or `docs/PRODUCT_NARRATIVE.md` as fact sources for this workflow.

Caltex (or other loyalty) architecture / ops / timeline PDFs are **illustrative provenance** for craft Resources — not Inputs to paste into a government run unless that bid’s sources explicitly include them.

## Hard limits

- No product KB / Rocket capability claims from CRM Knowledge.
- No inventing TOR coverage or commercial claims.
- No inventing past work; only library proofs + human-supplied evidence.
- No customer-facing internal or AI-process language.
- No whole-document single-pass dump for large proposals.
- Clarify before first Plan/Write unless the human says proceed.
- English first for draft / review / Polish. Thai only on manual convert into `th/`; never overwrite English root backups.
- Flag gaps with `[GAP: what is missing — who can answer]`.
- Do not paste Rocket SaaS / Kafka / SIEM-SOC / multi-tenant platform architecture into buyer-install government bids without dossier H1–H5 justification.
- Delivery timelines must pass `resources/standard-delivery-timeline-migration.md` alignment checks before Review 3.
- Do not paste loyalty end-customer CS / contact-centre suites into officer-warranty-only government bids.
- Do not put **payment percentages** or TOR-echo in the technical proposal voice.
- Do not treat anti-slop as permission to shorten blindly. Never delete a unique requirement, commitment, branch, reverse transition, interface field, security control, data relationship, ownership boundary, or delivery dependency merely because its table or diagram resembles another section.
- Do not use company positioning as proof of legal eligibility, qualifying past work, or personnel compliance; point to the required evidence.
- Personnel role stretch must not invent degrees or years (`personnel-role-fit.md`).
- Project-proof cover scopes may stretch framing but must not state false facts (`project-proof-stretch.md`).
