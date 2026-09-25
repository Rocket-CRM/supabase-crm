# Scaffolds — soft grammar for custom-project proposals

Guidance for documents and sections this workflow generates. Use what fits the bid. Omission of a type is fine when the package does not need it. Nothing here is a validator.

Companion: `REFERENCE.md`.

## Document classes (vocabulary)

| Class | Meaning |
|---|---|
| `manual` | Outside the workflow — **new** instrument (legal, bank, e-GP price entry, wet signatures) |
| `library` | Pull from canonical assets under `resources/` (company docs, project proofs, roster); face-check into pack |
| `generate` | Workflow drafts the customer-facing artifact |
| `hybrid` | Workflow drafts structure/shell; humans supply facts, signatures, or final assets |
| `out_of_band` | Not delivered as a written chapter (e.g. live POC) |

Standard **document groups** (include / omit / add per run): `resources/document-groups-catalog.md`.

### Example — EECO-style e-bidding pack

Illustrative only. Rebuild from each bid’s own clauses.

| Item | Typical class | Notes |
|---|---|---|
| Part 1 entity / registration docs | `library` | From `resources/company-docs/` when on file; else `manual` |
| Bid / performance / advance / retention bonds | `manual` | Templates may exist; bank fills |
| Power of attorney | `manual` | |
| Past-work contracts + certificates | `library` + `hybrid` cover | PDFs from `resources/project-proofs/`; cover AI after pick |
| Personnel roster + appendix forms | `hybrid` | Roster from `resources/personnel/`; facts + signatures human |
| Technical approach (concept, methodology, workflow, architecture, tools) | `generate` | Main scored narrative when the bid asks for it |
| Requirement comparison table | `generate` | Mirror the buyer’s required columns |
| Pricing breakdown / summary | `hybrid` | When group included — `resources/pricing-breakdown.md` |
| Project plan / schedule | `hybrid` | Structure + milestones draftable; dates/names human |
| Company / bidder introduction | `hybrid` | `resources/standard-company-profile.md`; evidence assets run-specific |
| Catalog / UI mockups | `hybrid` | Placeholders + `mockup-prompts.md` first |
| Live POC | `out_of_band` | Prep checklist optional; not a proposal chapter |
| e-GP price quotation | `manual` | System entry — distinct from pricing breakdown narrative |

## Generated document shapes

Names adapt per run. Common pair:

1. **Main proposal / technical approach** — concept, how we work, capability chapters, architecture, security, delivery.
2. **Requirement comparison matrix** — when the TOR mandates a clause-by-clause table.

### Main proposal — suggested section types

Use a subset. Order: prefer TOR order for capability/implementation chapters; otherwise concepts-first grouping.

| Type | Role |
|---|---|
| `company_introduction` | Compact bidder profile, project suitability, selected differentiation, and evidence pointers. Pull from human-approved sources + `resources/standard-company-profile.md`; never substitute positioning for qualification proof |
| `glossary` | Customer term ↔ our construct (when vocabulary will confuse) |
| `executive_summary` | Written **last**. **Required on every run:** Current state → Future state → Impact themes (2–4) plus one React **pillar-matrix** diagram under `diagrams/executive-overview/` (see “Executive overview”). No new claims |
| `pricing_breakdown` | Optional document/group — structure, line items, assumptions. Facts from human Clarify; scaffold `resources/pricing-breakdown.md`. Not a substitute for e-GP price entry when that is required separately |
| `capability_module` | One cluster of related TOR capabilities — not one giant “the system” chapter |
| `architecture_and_integration` | System shape, integrations, tools — wire-level detail only as deep as the depth judgment allows. **Pull** from `resources/standard-technical-practices.md` only the practice IDs justified by dossier H1–H5 (layered stack, unified API, DB philosophy, OLTP vs reporting, proportionate scale). Do not paste SaaS/Kafka/SIEM platform diagrams onto buyer-install bids. |
| `security_and_compliance` | Access, audit, privacy, related TOR security clauses. **Pull** app-facing practices (RBAC, audit, data protection, OWASP). Attribute perimeter/SIEM/SOC to **buyer ops** when H2 = `buyer_ops`. |
| `delivery_plan` | Phases, deliverables, training, **detailed timeline with buffers**, pre-go-live — hybrid with schedule facts. Pull D01–D10 from `resources/standard-delivery-timeline-migration.md` as gated. TOR gates sovereign. |
| `operations_and_support` | **Separate section by default** when warranty/SLAs exist. Two planes: Support operations vs Technical operations. Pull S01–S14 from `resources/standard-operations-support.md` as gated; TOR SLA numbers win. |
| `requirement_comparison_matrix` | Often a **separate file**; sometimes an appendix |

### `capability_module` — useful slots (not a forced template)

When writing a capability chapter, these moves usually help. **Skip any that would be empty or decorative.** Do not rename them into customer-facing headings like “Frame” or “Scenario.”

1. Open with the **object or process** the chapter is about (one clear idea).
2. If an officer story clarifies the clause, weave a short **customer-context path** into the prose — only when it teaches something the bullet list cannot.
3. State **behavior and operating model** at the depth the dossier judged for that clause.
4. Keep TOR mapping short in-body; put exhaustive rows in the comparison matrix.
5. End with a plain **Reference: TOR …** line (no section-sign character; no internal “Covers:” meta). Clause IDs on that line must match the TOR numbering in `sources/`.

Do not pad to a word count. Stop when the clause is covered at the right depth.

## Executive overview (mandatory — every project)

Every compiled proposal includes an **executive overview** inside (or immediately under) the executive summary. Pattern matches Rocket Deck / loyalty proposals (`pillar_matrix`): show how the buyer works today, what Rocket proposes, and what changes for the Authority.

### Prose

Write **2–4 themes** drawn from the bid spine (dossier depth judgment). Under each theme heading, three labelled blocks:

| Label | Content |
|---|---|
| **Current state** | How the buyer operates today on this dimension (named pains from sources — not generic transformation language) |
| **Future state** | What Rocket proposes to deliver (conditional / proposal voice) |
| **Impact** | Outcome for officers, executives, or the Authority |

Keep each block short (about 40–80 words). No SCQA labels. No new claims absent from the body.

### Diagram (React)

| Artefact | Path / shortcode |
|---|---|
| React source | `runs/<slug>/diagrams/executive-overview/PillarMatrix.tsx` |
| Locale data | `data.en.json` · `data.th.json` (2–4 pillars; ≤3 bullets per cell; ≤12 words/bullet) |
| Viewer HTML | `index.html` (self-contained render; `?lang=en\|th`) |
| Embed in markdown | `{{diagram:executive-overview}}` |

Columns: **Objectives** · **Current state** · → · **Future state** · **Impact**. Place the shortcode **immediately under the section heading** (before theme prose) so the matrix leads the “from today to proposed” story. Thai convert uses the same shortcode; the viewer resolves Thai data when `lang=th`.

Do **not** skip this section because the bid is government or “technical only.” Every project needs the overview.

## Exact TOR text (when we reference a clause)

Whenever customer-facing text **presents what the buyer required** — matrix buyer-requirement column, an in-body quotation of a TOR duty, a glossary of buyer-coined terms, or any other place that stands in for the clause — use the **exact wording from the run’s TOR source** in `sources/` (for EECO: `eastern-seaboard-crm-documents-combined.md` or the pack file that holds that clause). Do **not** substitute our own paraphrase, summary, or “cleaned” English rewrite as if it were the requirement.

| Surface | Rule |
|---|---|
| **Comparison matrix — buyer requirement column** | Paste **verbatim** TOR text for that clause (keep Thai script if the TOR is Thai). Truncate only with `…` if the cell would be unreadable; never rewrite meaning. |
| **In-body quote of a buyer duty / coined term** | Quote verbatim from `sources/`, then interpret or propose **beside** it — not instead of it. |
| **`Reference: TOR …` audit line** | Clause **IDs only** (and appendix labels). IDs must match the source. This line does not replace the verbatim surfaces above. |
| **What we propose / Equal-better / journey prose** | Our words — feature and operating narrative. Must still be faithful to the cited clause; do not invent duties the TOR did not state. |

**Procedure (every Write / matrix edit / Thai convert that touches a cited clause):**

1. Open the exact location in `sources/` for that clause ID (outline `reads` or dossier pointer — not memory, not the dossier paraphrase alone).
2. Copy the buyer-requirement text from that location when the surface requires it.
3. If OCR/extraction in `sources/` is garbled, fix against the best available extract or flag `[GAP: TOR text for §x.x — verify against PDF]`; do not invent fluent substitute wording.
4. English proposals may add a short English gloss **after** a Thai TOR quote when it helps reviewers — the Thai quote remains the authority.
5. Thai localize: **copy** TOR Thai from `sources/` into `th/` for those surfaces. Never translate our English paraphrase of the TOR back into Thai and call it the requirement.

This does **not** mean every capability chapter must open with a TOR paste. Feature/journey prose stays the spine; exact TOR text appears where we claim to show the buyer’s requirement.

## Requirements covered by features (not XOR)

**Requirement-led** and **feature/journey-led** are not alternatives. The proposal ticks buyer requirements **by detailing features and journeys** — operator verbs, stage behavior, screens, and flows — with TOR references as audit tags, not as the prose spine.

| Do | Do not |
|---|---|
| Lead capability chapters with what users/officers **do** in the system | Lead with “We comply with TOR 5.5.x” or a paraphrase of the clause |
| Use TOR subsection order when it helps evaluators **find** coverage | Use TOR order as an excuse to write checklist prose without operating detail |
| Put exhaustive tick-off in the **comparison matrix**, pointed at feature sections | Duplicate a dry requirements restatement in every chapter body |
| On the bid spine, write Caltex-style journeys / key functions where they teach behavior | Write a free-form product brochure that drops clause traceability |

Structure may still mirror the TOR. Substance inside each chapter is feature and journey detail that makes the clause true.

### Company introduction and bidder suitability

The introduction should help an evaluator answer two different questions without confusing them:

1. **Why is this bidder relevant to this project?** Summarize the specialist category, delivery capacity, and only the differentiators that fit the project.
2. **Where is formal proof?** Point to the required legal, past-work, recognition, and personnel documents.

Keep this compact. A useful shape is company profile → suitability for the engagement → relevant differentiation → evidence map. Do not repeat contract values, CV histories, or legal declarations already carried by mandatory forms.

For the named delivery team, a proposal table may summarize each person's proposed role and project responsibility. The signed Appendix B form, degree certificate, and experience evidence remain the scored proof. If the source evidence does not clearly meet a TOR threshold, record the risk in the dossier and do not write "compliant" in customer prose.

**Thai customer documents:** use **Thai personal names** from the canonical personnel source (Appendix B forms / roster Thai-name field), not English transliteration alone, in the delivery-team table and similar owner-facing lists.

AI is conditional: include a specific implementation use case only when the project asks for it. Otherwise it may appear once as company breadth, or be omitted.

**Capability chapter texture is a menu, not a published template.** A chapter normally needs an operational opening and enough evidence to make the behavior credible. Choose the rest according to what the subject requires:

- Define **objects / concepts** only when the reader needs them to understand later behavior. Use a subject-specific heading such as “Investment Journey records,” not “Objects in this chapter.”
- Use a **feature table** when several comparable actions benefit from scanning. Write full sentences for what the officer does and concrete controls in the Includes column. Do not add a table merely to satisfy a slot.
- Add a **flow, decision rule, or worked path** when sequence or branching matters. Do not repeat the same behavior in prose, a table, and a diagram.
- Keep TOR mapping to one short `Reference:` line or a genuinely useful compliance sentence. Do not create a recurring “Compliance anchor” section that paraphrases the clauses already cited.
- Add **mockups** only where seeing the interface changes understanding.
- Use **cross-references** only for real dependencies. Do not explain which section “owns” content or how the document was assembled.

On the bid spine, keyword-only table cells are a fail. Peripheral hygiene modules may stay shorter. Adjacent chapters may share a broad logic, but repeated generic headings and identical paragraph sequences make the proposal look machine-produced; published headings should describe the customer subject.

Tables add density; they do not replace prose. Thin architecture “API function group” tables may **index** Core features subsections rather than duplicate them.

**Compression safety:** remove duplicate presentation, not unique meaning. Before deleting a table, diagram, mockup, or repeated-looking passage, state what it uniquely carries: commitment, branch/reverse path, ownership boundary, interface contract, data relationship, security control, or timeline dependency. If any item is unique, retain it or move that meaning explicitly to the surviving surface.

### Core features grouping

When the TOR clusters many modules (e.g. 5.5.1–5.5.6 + adjacent security/migration), prefer **one parent section “Core features”** with **numbered subsections** (5.1, 5.2, …) over many peer top-level chapters that look like a product catalog. Architecture, delivery model, and project plan stay outside that parent. Outline and matrix references use the subsection numbers.

## Depth and examples (judgment — not a per-section rule)

Uneven depth is correct. Mirror the TOR’s and scoring rubric’s center of gravity, not a template that expands every module equally.

| Add deeper operating detail / a worked example when… | Skip or keep thin when… |
|---|---|
| The clause is central to award or to the buyer’s stated outcomes (e.g. Investment Journey, scored workflow narrative) | The clause is supporting hygiene (master lists, bulk import, training logistics) already clear at bullet depth |
| An evaluator would otherwise guess *how officers actually use it* | Another section already owns that story (avoid duplicate journeys) |
| A customer-domain example removes ambiguity (place, persona, artifact types from the TOR) | The example would invent integrations, APIs, metrics, or past work not in sources |
| Sub-capabilities matter to stage exits, SLA, or security (name them in the flow) | Listing “sub-features” would be a parallel feature catalog with no new decision |

**Hard rules**

- No deterministic “every capability chapter gets an example.”
- No deterministic “every stage gets a sub-feature checklist.”
- No headings that sound like writing-process scaffolding in customer docs (`Frame`, `Scenario`, `What we propose`, `Sub-feature hooks`).
- Prefer one strong worked path through the **spine** of the bid over shallow examples everywhere.
- Principles review (REFERENCE stage 9) is where you catch under-depth on the spine and over-depth on the periphery.

### Requirement comparison matrix

When required, follow the buyer’s column layout. For EECO-like bids that is typically:

| Buyer requirement (**verbatim from TOR source**) | What we propose | Equal / better / note | Document reference |

- Column 1 = **exact TOR text** from `sources/` for that clause ID (see “Exact TOR text” above). Not an English summary of the clause.
- Column 2 = our proposal wording (may be English or Thai per language stage).
- Every in-scope TOR requirement row should appear somewhere (matrix and/or body with clause tags). Do not silently drop clauses.

## Plan proposal writing SOP (stage 5 — before Produce)

Plan and Write are separate. Persist the plan in `outline.md` (and short dossier bullets where useful). **Do not draft customer prose in this stage.**

### Plan checklist

1. **Groups in scope** — from `submission-plan.md` / `document-groups-catalog.md` (include / omit / add).
2. **Section plan** — chapter list for Proposal (+ Pricing if included); TOR order vs regroup; MECE between siblings.
3. **Depth map** — light / normal / deep per section (from dossier judgment + clause cites).
4. **Resource pulls** — company profile facts; practices P-IDs; ops S-IDs; timeline D-IDs — in/out with reason.
5. **Visual plan** — executive overview required; mockup ids; mermaid vs React; agency logo gap?
6. **Evidence plan** — assess `resources/project-proofs/INDEX.md` via `project-proof-stretch.md`; list picks + stretch framings + insufficiencies.
7. **Personnel plan** — TOR role floors → `personnel/roster.csv` via `personnel-role-fit.md`; compliance vs scoring stretch; dossier gaps.
8. **Pricing plan** — if group included: what commercial facts exist; what stays `[GAP]`.
9. **Write order** — section sequence; `executive_summary` last; late-AI items marked (wait on manuals).
10. **Open gaps** — block Write vs proceed-as-hybrid.

### Per-section notes (useful, not a schema)

- `title` — published heading
- `section_type` — from the vocabulary above (or a run-specific label)
- `tor_clauses` — what this section is accountable for
- `scope_note` — what it owns vs siblings
- `reads` — exact locations in `sources/` (never “the dossier” alone)
- `visuals` — none / mermaid / react / mockup placeholder (only if useful)
- `late_ai` — yes if this artifact waits on manuals / library picks

No `target_length`.

## Structure principles

1. **Objects and concepts before detail** — reader gets the frame, then the drill-down.
2. **TOR tick-off** — where sensible, mirror TOR subsection order; always keep clause tags.
3. **Regroup when clearer** — if TOR order produces a confusing story, regroup; say so in the outline scope notes.
4. **Depth from sources** — if the TOR asks for ERD, API contracts, or field-level design, go there for those clauses; if it asks for process and architecture, do not invent database trivia.
5. **MECE between siblings** — overlapping chapters are a planning failure, fixed at Outline cheaply.
6. **Customer-facing voice** — for government / e-bidding packs: formal, official Thai-agency English (or Thai when localizing); systems-architect clarity; no sales fluff; no internal process language; no AI-brochure metaphors (“spine”, “pile of cards”, “built for X”).
7. **Anti-slop** — specific to this customer and this TOR; cut generic transformation prose.

## Hosting and environments (from the bid pack)

Do **not** invent a hosting model. Derive it from TOR / dossier:

| Question | What to document |
|---|---|
| Who procures production hosts? | Buyer / bidder / shared — quote the clause |
| On-prem vs cloud vs vendor-agnostic | Exact TOR language; if buyer names an example cloud (e.g. GDCC), treat as example unless exclusive |
| What the bidder must deliver | Min specs, install/config, DR docs, etc. |
| Bidder-owned environments | Only for non-production / POC if the bid allows or is silent — label clearly as **bidder-managed non-production**, not as production hosting |

If production is buyer-arranged cloud: lead with **minimum infrastructure specification (vendor-agnostic)** and install on the environment the buyer provides. Do not write as if the bidder hosts production on AWS (or any vendor) unless the TOR says so.

### Standard technical practices (context-gated)

Resource: `resources/standard-technical-practices.md`.

| Rule | Detail |
|---|---|
| Select, don’t paste | Dossier **Practices pull** lists P-IDs in/out before architecture/security Write |
| Shape follows hosting | Buyer-install shared infra ≠ Rocket SaaS stack (no default Kafka cluster, Redis platform tier, or multi-tenant control plane) |
| Ops ownership | Observability / WAF / SIEM claims follow H2 — `buyer_ops` gets log handoff language, not Rocket 24/7 SOC |
| Outline `reads` | Cite `standard-technical-practices.md (Pxx, …)` on architecture and security rows |
| Domain gate | Fraud matrices and multi-channel consumer front ends stay loyalty-only unless TOR requires them |

See the Resource’s EECO worked example for a full pull list on `buyer_cloud_install` + `gov_crm`.

### Operations & support (separate section by default)

Resource: `resources/standard-operations-support.md`.

| Rule | Detail |
|---|---|
| Separate section | When TOR has warranty / maintenance / incident SLAs, use `operations_and_support` — do not bury only inside training |
| Two planes | Label **Support operations** vs **Technical operations**; do not merge consumer CS with app warranty |
| TOR SLAs win | Catalog severity tables are templates; replace with TOR numbers |
| Hosting-aware | Infra/SOC ownership follows technical-practices H2; Rocket warranty covers application defects |
| Loyalty gates | End-customer CS, Freshworks, campaign ops only if O1/O4 say so |

### Delivery timeline & migration calendar

Resource: `resources/standard-delivery-timeline-migration.md`.

| Rule | Detail |
|---|---|
| Three artefacts | (A) milestone process flow (B) migration methodology when relevant (C) **combined timeline** |
| TOR delivery dates sovereign | No planned date after a TOR delivery package date; overall duration ≤ TOR |
| **No Pay % in proposal** | Payment percentages are commercial/TOR — dossier-only unless the pack requires them in the technical volume |
| **Proposal voice** | “What Rocket delivers” / our schedule — not “what the buyer receives” TOR restatement |
| Buffer | Explicit buffer before each hard delivery date; finer milestones under packages |
| Migration split | Methodology detail in migration capability chapter; **dates** on combined timeline |
| Review gate | Principles review + self-check must run timeline alignment **and** proposal-voice checks — fail = not sendable |

## Extra / beyond-minimum features

During Understand, assess from the pack (dossier only — not customer prose):

1. Does scoring or the comparison table allow **equal / better** (or similar)?
2. Is there a **separate bonus-point** line for extras, or only qualitative benefit inside an existing scored factor?
3. Would extras create scope/price risk if the buyer treats them as mandatory?

**If allowed and useful:**

1. **Embed** each enhancement in the relevant Core features subsection, under a short heading such as **Recommended enhancement (beyond TOR minimum)** — state what it does and why it benefits the Authority, in owner-facing voice.
2. **Summarize** the same items once at the end (short table + pointers to subsections). Do not use the end section as the only place extras appear.
3. Matrix rows marked **Better** (or the buyer’s word), never mixed into Equal as if required.

**If not allowed or risky:** dossier only; no matrix Better rows.

Do not invent a “bonus points” score the TOR does not have. Do **not** explain the scoring rubric or “why we may add extras” to the buyer in the proposal body — that analysis stays in `dossier.md`.

## Owner-facing voice (customer documents)

Compiled proposal and matrix speak **to the project owner / evaluation committee**, never as notes to the writing team, and never as a paraphrase of the TOR explaining the buyer’s own clauses back to them.

| Keep out of customer prose | Put in dossier / chat instead |
|---|---|
| “The rubric does not add bonus points…” | Extras scoring assessment |
| “This chapter is a scoring note only…” | POC prep checklist |
| “Accounts for 40% of the technical score” as coaching | Brief POC commitment citing ภาคผนวก ก without meta |
| “AI / agent / we should…” process talk | Principles review file |
| Explaining TOR table mechanics to ourselves | Matrix column already shows Equal/Better |
| **“What สกพอ./the buyer receives” as a TOR restatement** | Delivery table: **“What Rocket delivers”** / our commitment |
| **Payment % (20/50/30) and “payment gates”** in the technical narrative | Dossier alignment note; commercial terms stay in TOR/contract unless the pack requires them in the technical volume |
| **Writer meta:** “this section owns…”, “contract hard stops”, “TOR wins”, “for scoring” | Outline / dossier / principles-review |
| **Document choreography:** “this section describes…”, “below…”, “the matrix records…”, “items appear again at the end” | Delete, or retain only when the navigation materially helps the buyer |
| **Visible scaffold labels:** repeated “Objects in this chapter”, “How it works”, “Compliance anchor” | Subject-specific headings or continuous prose |
| **Pack / viewer assembler meta:** “Combined pack”, “Full narrative with mockups”, “working roster”, “Have / remaining”, “audit map”, “feature detail lives in…” | Official Part 1 / Part 2 document titles only; internal trackers stay in `CHECKLIST.md` / dossier, never in customer HTML |
| Opening a chapter by re-teaching the TOR clause | Open with what we will do / how officers will work |

**Proposal voice test (fail = rewrite):** Could a non-writer reading only this paragraph tell it was written *to* the Authority as our offer — or does it sound like an analyst explaining the RFP to a colleague? Prefer the former.

| Bad (TOR echo / meta) | Good (bidder proposal) |
|---|---|
| “These dates are contract hard stops. What สกพอ. receives… Pay 20%.” | “Within 60 days of signature, Rocket submits the BRD, design pack, and risk note.” |
| “This section owns the calendar…” | “The schedule below is Rocket’s delivery plan for the 210-day programme.” |
| “TOR 6 requires payment acceptances at…” | “Rocket completes delivery within 210 days, with major packages at days 60, 180, and 210.” |

POC and extras chapters: state what Rocket **will demonstrate / will provide**, with TOR citations — not why the committee scores it.

Craft sources: `Writing Principles/CORE_WRITING_PRINCIPLES.md`, `PROPOSAL_WRITING_PRINCIPLES.md`, anti-slop skill.

## Visuals (defaults)

| Need | Default approach |
|---|---|
| Non-technical concept | React diagram under `diagrams/`; reference from the section |
| Executive overview (Current → Future → Impact) | **Required:** React `PillarMatrix` under `diagrams/executive-overview/` + `{{diagram:executive-overview}}` (see “Executive overview”) |
| Sequence / technical flow | Mermaid; keep readable on **A4**. Prefer `flowchart TB` (or phase **subgraphs**) over a long `flowchart LR` that forces unreadably small type in print/PDF. Merge minor steps; no fixed node count. |
| Section breaks | Prefer spacing + heading hierarchy. Avoid `---` immediately before `##` / `###` (stacks with heading rules and looks template/AI). Viewer CSS uses a single soft rule; do not add a second visual rule. |
| UI | Placeholder + registry entry; FE handoff via `MOCKUPS.md` / `mockups:handoff` |
| Company intro art | At most one relevant recognition/industry-leadership proof visual, sourced and captioned; omit decorative company art |

Mockup prompt / registry entries should state: screen purpose, primary user, key regions/actions, TOR clauses illustrated, and any must-avoid (no fake data that contradicts the bid).

Visuals are not interchangeable. A diagram that shows branching, reverse transitions, actor ownership, system boundaries, interface calls, entity relations, or date dependencies carries technical content. Anti-slop review may remove a visual only when the same semantics remain clearly in another named surface; record the removal and destination in `principles-review.md`.

**Government / agency branding:** `mockup-registry.json` must include a `branding` block with the buyer’s **real official logo** (`logo.runAsset` under the run `assets/` and/or `logo.url`). The loyalty-admin handoff prompt (generated by `scripts/generate-handoff.mjs`) requires that logo in app chrome and print/PDF headers. Do **not** invent a crest, use a generic seal, or put Rocket’s logo in place of the agency mark. If the file is missing, record `[GAP: official agency logo]` and obtain it before FE generation.

## Principles review prompts (stage 10)

Write answers in `principles-review.md`. Then edit — do not treat the prompts as a force-fill form.

1. What is this bid’s **spine** (1–3 outcomes/modules)? Is that spine deeper than peripheral chapters?
2. Do capability chapters **tick TOR clauses by feature/journey detail**, or do they still open as compliance paraphrase?
3. Where would a **worked customer-context example** change understanding? Where would it only decorate?
4. Where is operating detail still abstract on a scored or outcome-critical clause?
5. Where did we invent or over-specify beyond sources / dossier depth judgment?
6. Voice: any “buyer asked for…”, template headings, section-sign clutter, scoring-rubric coaching, **TOR-echo** (“what the client receives”, payment %), or internal meta (“this section owns…”) left in customer prose?
7. Visuals/mockups: enough for POC- and journey-critical screens — not one box per bullet? Government packs: real agency logo in FE chrome (registry `branding`), not invented crest? **Executive overview pillar matrix present?**
8. Key features tables: spine modules have full-sentence **What happens** plus substantive **Includes** (not semicolon keyword dumps)?
9. Extras: embedded in feature subsections **and** summarized at the end — owner-facing, not rubric essay?
10. Technical practices: does architecture/security match dossier H1–H5 (no SaaS/Kafka/SIEM-SOC paste on buyer-install)?
11. **Timeline alignment (mandatory):** D02/D08 cover every TOR **delivery** date; no overrun; explicit buffers; migration dates consistent — see `standard-delivery-timeline-migration.md` checklist? **No Pay % column** in customer timeline?
12. **Operations:** separate ops section (or documented thin exception); Support vs Technical planes; TOR warranty SLAs; no loyalty CS paste on officer-only bids?
13. **Proposal voice (mandatory):** delivery/ops/architecture read as Rocket proposing to the Authority — not as an explanation of the TOR to ourselves?
14. **Structural fingerprint:** do adjacent chapters repeat the same generic headings, table-prose-example-compliance sequence, or opening syntax? Keep repeated structure only where it genuinely improves comparison.
15. **Cold-reader evidence:** which opening, middle passage, and closing passage were read in full, and what changed? A phrase search or anti-slop score alone cannot pass this review.
16. **Coverage preservation:** for every large cut or merge, what commitment or technical meaning existed before, and where does it live now? Check architecture, system design, database, security, integration, migration, operations, and delivery separately.
17. **Visual inventory:** which diagrams/mockups were added, retained, merged, or removed? Did any removed visual carry a unique branch, reverse transition, relationship, ownership boundary, or dependency?

## Self-check before Review 3

Light checklist — report shortfalls as `[GAP: …]` rather than padding.

- Every `generate` / relevant `hybrid` item in `submission-plan.md` has a drafted artifact or an explicit gap.
- Every `library` item is copied into the pack or flagged Remaining in CHECKLIST; project-evidence cover exists when that group is in scope.
- Pricing breakdown present if the group was included; e-GP price entry still tracked separately when required.
- In-scope TOR capabilities appear in a body section and/or the comparison matrix.
- Clause tags (or matrix rows) make coverage auditable; matrix buyer-requirement cells and in-body TOR quotes are **verbatim from `sources/`**, not writer paraphrases.
- No section invents depth the dossier said the TOR does not ask for — unless a specific clause demands it.
- Executive summary includes Current → Future → Impact themes (2–4) and `{{diagram:executive-overview}}` (or equivalent pillar matrix).
- Executive summary (if any) introduces no claim absent from the body.
- Compiled docs contain no internal next-steps, AI meta, or review scaffolding.
- Company introduction uses human-approved facts, is tailored to bidder criteria, and points to supporting evidence; it does not invent or overstate rankings.
- Mockup placeholders have matching prompts when placeholders remain.
- Government mockups: registry `branding.logo` points at a real agency mark on disk (or URL); handoff forbids invented crests.
- Language is English at the run root unless a manual Thai convert produced `th/` (and English backup remains).
- If `th/` exists: Thai self-check against `Writing Principles/TRANSLATION_PRINCIPLES.md` (numerals, no calqued metaphors, no `การ + English verb`, spoken-Thai test).
- `principles-review.md` exists for this compile and listed actions are done or explicitly deferred.
- Architecture/security: dossier has H1–H5 + Practices pull; customer prose does not claim Rocket-operated Kafka/SIEM/SOC/SaaS tenancy on buyer-install runs without justification.
- Timeline: combined timeline + buffers present; passes alignment checklist; **no payment % in customer delivery tables**.
- Operations: if TOR warranty exists, `operations_and_support` section present (unless thin exception noted in dossier); TOR SLA numbers; Support vs Technical labeled.
- Voice: no TOR-echo / writer-meta in customer prose (SCAFFOLDS owner-facing voice test).
- Structure: no repeated generic scaffold headings across capability chapters unless the repetition has a clear reader benefit.
- Review evidence: `principles-review.md` cites representative passages from the beginning, middle, and end of the compiled document; it does not rely only on lexical detection.
- Coverage: before/after review confirms no unique requirement, bidder commitment, technical control, interface detail, data relation, or delivery dependency disappeared during anti-slop cleanup.
- Technical parity: architecture, system design, database design, security, integration, migration, operations, and delivery remain at the depth accepted in the outline/dossier.
- Visual parity: `principles-review.md` records removed diagrams/mockups and where each unique meaning survives; decorative duplication may be cut, semantic visuals may not.
- Matrix proposal column uses complete bidder/system commitments, not keyword strings joined by `/`, `+`, arrows, or semicolons.
- If Thai structure differs from accepted English, the change was first applied to English and re-localized, or the authorized divergence is recorded with a coverage-preservation check.

## Language

- **First draft / review / Polish / Review 3:** English at the run root (`sections/`, `proposal.md`, …).
- **Thai convert:** only when the human manually triggers it. Follow `Writing Principles/TRANSLATION_PRINCIPLES.md`.
- **Layout:** write Thai under `th/`; **do not overwrite** English root files. Optional frozen snapshot under `en/` on first convert.
- **Submission:** Thai government packs usually pack from `th/` after convert; do not mix “review English” and “submission Thai” in the same file.
- **Voice when Thai:** formal agency Thai; keep market-standard technical terms in English when Thai would be awkward (see translation principles).
