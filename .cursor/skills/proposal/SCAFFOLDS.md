# Proposal scaffolds

A vocabulary for planning and writing sections — what good sections of each kind usually carry, and the lessons earlier runs paid for. **Guidance, not a form.** Nothing here is a quota: no required count of journey references, diagrams, mockups, examples, or words per section. Use a pattern when it helps this customer understand; skip it when it doesn't, and say why at Gate 2 if the skip is surprising.

## Structure of the features part

### Default: the retention journey

Organise member-facing features by the journey in `docs/PRODUCT_MESSAGING.md`: **Join → Earn → Burn → Grow → Campaign → Analyze & Activate → Convert.** Stages are the grouping level; each in-scope capability is its own section (or subsection) inside its stage. Skip stages the deal doesn't touch.

Why: a reader who knows which stage they are in can place every feature, and complex capabilities (automation, AI decisioning) land in context instead of floating. Place the journey once where the features begin, then let the structure carry it — a heading hierarchy that says "Earn" doesn't need every paragraph to repeat it.

Outside the journey, after it: customer service (its own group when in scope), admin portal and reports infrastructure, data ownership, integration, operations and support, delivery.

The journey fits loyalty and CRM scope. For a custom build that isn't a loyalty programme, derive the structure from the tender and Core principles instead.

### When the tender has its own structure

Evaluators score against their own structure, so respect it — but a proposal is also our chance to show clearer thinking. Decide once at Plan and explain the choice at Gate 2:

- **Their structure is clear and well grouped** → follow it. Inside their sections, order content along the journey where it reads naturally.
- **Same shape, different words** → use their term, ours in brackets, in headings and at first mention: "Member registration (Join)". After that, their term alone — brackets on every mention are noise.
- **A flat list, or items mixed across levels** → group their items into journey stages (Core §6–8). Keep each item findable: their wording as a subsection or table row, with its clause ID.
- **Their structure groups on a different axis** (by department, by system) → keep their top level; use the journey within each part where it helps.

Whenever we regroup their items, include a clause coverage matrix (clause → where it's answered) so an evaluator can find anything in seconds.

## Depth

Depth comes from three things: every in-scope capability getting its own treatment, writers opening their reading list before writing, and the dossier pointing at sources instead of summarising them. It does not come from word targets.

The failure this protects against: an earlier run wrote the whole proposal in one pass from a 633-word dossier summary of a 4,519-word brief, and produced a 3.2k-word coverage memo where ~10k was warranted. Collapsing "earn, tiers, redemption" into one section is the same failure at section level.

Primary-deliverable sections go deeper than siblings; the rest is calibrated against them. A thin section flagged honestly (`[GAP: …]`) is reviewable; a thin section presented as complete is not.

## Section kinds

### Feature section

What a strong one usually does:

- **Why first** — what this capability is for, in the customer's terms (Core §13).
- **The journey or scenario** when sequence is the evidence (Proposal W2): a realistic member, staff, or agent walkthrough in the customer's vocabulary. A diagram placeholder when a flow has branches or actors prose can't carry.
- **What it is** — the configuration model as groups of settings (display, price, eligibility…), not click steps.
- **The Rocket features involved**, by their real names.
- **A mockup** where seeing the screen answers a question faster than prose — member (phone) or admin (tablet).
- **Fit** against their requirements when the tender enumerates them (Proposal S6).

Lessons that still hold:

- **Earn** — conditions (rule types, dimensions, grouping) before rate examples. If the customer calculates earn outside Rocket today, give both paths equal weight: customer-posted pre-calculated points, and Rocket's native earn rules.
- **Rewards** — per-reward limits and reward groups belong in the rewards section, not a sibling.
- **Tiers** — qualification, upgrade/downgrade, and review before any UI.
- **One owner per story** — one earn section owns the member earn narrative; purchase ledger and marketplace ingestion are subsections or cross-references.
- **Customer service** — the walkthrough is a realistic contact scenario for this customer; AI sections show concrete procedures with tool steps and escalation.

### Other kinds

- **Vocabulary alignment** (early; Proposal S1, U1–U2): their term → what we configure. Call out when one of their words hides two platform patterns.
- **Data ownership**: one place — each data domain, its master system, consumers, sync direction — with the customer's real system names. Referenced elsewhere, not repeated (Proposal S4).
- **Reward sourcing** (when rewards are in scope): the reward strategy for this customer's members first; then inventory model vs fulfilment channel (never conflated), coverage and timelines as commercial targets, and exception handling.
- **Admin portal and reports**: a catalogue of configuration areas and named reports in scope — not walkthroughs. A domain without its named reports says nothing.
- **Additional features**: licensed but not configured for go-live — breadth, so nothing in scope is silently dropped.
- **Integration**: the only home for wire-level detail — systems, direction, data, mechanism — with a subsection per real external contract.
- **Operations and support**: SLA, severity, and governance, with this customer's operational specifics woven in, not appended.
- **Delivery and timeline**: phases, dependencies, and milestones. Tender delivery dates are sovereign.
- **Executive summary** (written last, compiled first): current state → new state → impact on this customer's named pains, traceable to the dossier. Pillars from `PRODUCT_MESSAGING.md` and the narrative's module intros fit here when they fit the customer. It summarises; it introduces nothing new.
- **Clause coverage matrix**: when a tender or numbered requirement list exists — every clause, verbatim, with where it is answered.

## Reading map

Writers open these **before** drafting. The outline's `reads` narrows them to exact headings.

**Requirement docs.** Grep `requirements/domains/_index.md` for the customer's terms to find the authoritative `requirements/<Domain>.md` (if the index is absent, list `requirements/*.md`). Read **Concept** and **Journeys** closely, **Rules** for the constraints a claim depends on, **System** only when the section needs it (integration, data, security). Requirement docs name tables and functions; use them to confirm behaviour, never repeat them to the customer.

**Narrative** (`docs/PRODUCT_NARRATIVE.md`) for customer-facing framing. Two layers:

- **Summary layer** — each `##` module's intro and each capability's **Overview** and **Purpose** (newer sections: **What it enables**). `bash .cursor/skills/proposal/narrative-overview.sh` prints all of it (~6k words). The parent reads it whole before planning; writers read the module intro and their own capabilities' summaries first, since that's where a section's opening idea usually comes from.
- **Full sections** — journeys, configuration, edge cases. Locate with `rg -n "^### <Anchor>"`, read to the next `###`. Configuration tables carry field and enum names; use them to understand, never repeat them to the customer.

Anchors by stage:

| Stage / area | Narrative anchors |
|---|---|
| Join | `Authentication & Signup` · `Forms` · `PDPA Consent` · `Tags & Personas` |
| Earn | `Currency` · `Purchase Transactions` · `Activity-Based Earning` · `Store & Partner Classification` |
| Burn | `Rewards` · `Packages` · `Stored Value Cards` |
| Grow | `Tiers` · `Persona Entitlements` |
| Campaign | `Missions` · `Spin Wheel` · `Mass Lucky Draw` · `Referral` · `Check-in` |
| Analyze & Activate | `Reports — What the Brand Sees Back` · `AMP Workflows` · `AMP AI Decisioning` · `AMP AI Analysis & Recommendations` |
| Customer service | `Connectivity` · `Agent Workspace` · `Ticket Management` · `Rules-Based Automation` · `CS AI` · `Knowledge Base` · `Actions & Integrations` · `CSAT & Customer Feedback` · `Analytics & Logs` |
| Admin, localisation | `Admin Portal — Configuration Surfaces` · `Translation System` |

Convert (Shopify, unified points) is framed in `PRODUCT_MESSAGING.md`; facts in the Shopify requirement doc.

## Visuals

- **Diagrams: Mermaid only, `sequenceDiagram` or `flowchart` only.** Worth one when a journey, a logic branch, or a process across actors is clearer drawn than written. Keep node counts low; label in the customer's vocabulary. A diagram that carries unique meaning (a branch, an ownership boundary) is content — never cut it without moving that meaning into prose.

  Diagrams are decided and drawn after the prose, by agents that see the whole document. Writers mark where one would help, on its own line:

  `[DIAGRAM: <what it must show — actors, steps, branches> | <why a drawing beats prose here>]`

  The diagram planner then keeps, changes, or drops each placeholder and adds any that are missing; the diagrammer draws the survivors. Writers never draw Mermaid themselves, and prose around a placeholder should read fine whether or not a diagram ends up there.
- **Mockups: live from rocket-deck slides.** Pick from the run's `slides.json` (the pitch's slides when the deal has one, else the library — skip `bucket: archive` slides, which are other clients' demos). Embed a mockup id, not an image:

  `[asset:mockup;id=<mockupId>;pitch=<pitchSlug>;title=<caption>]`

  `pitch=` shows that pitch's uploaded customer images; omit it for library defaults. URL-encode caption spaces as `+`. Take the slide's copy as input and re-express it for this section — don't paste slide text.
- **Diagram slides**: `[asset:fixed_diagram;slide=<slideId>]` embeds a slide's diagram without its slide chrome.

## Sources-only mode (custom and government bids)

Facts come only from `sources/` and human answers — no product catalogue claims beyond what the bid needs. In addition to the above:

- Depth follows the tender's spine — uneven on purpose (Proposal W13b). Official voice for government packs (W13c): propose to the buyer; no echoing the TOR back, no document choreography.
- Tender text appears verbatim in matrices and in-body requirement quotes.
- Hosting, environment, operations ownership, and delivery dates come from the pack. Don't impose Rocket's SaaS architecture on a buyer-installed system without a reason recorded in the dossier.
- Architecture, system design, and data models are fine — required, even — when the tender asks for them.
- Payment percentages stay out of technical prose.
- Submission documents the workflow doesn't write (bank letters, signed forms, certificates) are listed with an owner in the dossier, not drafted.
