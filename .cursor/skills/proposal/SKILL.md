---
name: proposal
description: Write a customer proposal in one Cursor thread — Rocket CRM deals from the requirement docs, or custom / government bids from the tender pack — and publish it to the rocket-deck proposal viewer with live mockups and brand-style diagrams. Use when the user asks for a proposal, TOR / RFP / e-bidding response, or to continue a run under workflows/proposal/runs/.
---

# Proposal

One thread writes one proposal. This thread (the parent) holds the picture of the deal, talks to the user, makes the structural decisions, and runs the gates. Sub-agents do the reading-heavy and writing-heavy work. The run folder is the only state — a fresh thread pointed at it can resume. The deliverable is a page on the proposal viewer, not a markdown file.

**Principles, not quotas.** This skill, `SCAFFOLDS.md`, and the sub-agents describe what good looks like and why. None of them counts things — journey mentions, diagrams, mockups, examples, words per section. When a principle and the customer's material pull apart, use judgment and say so at the next gate.

## Who does what

| Agent | Model | Job |
|---|---|---|
| Parent (this thread) | Opus 5.5 High | Understand the deal, clarify, plan the outline, route work, run the gates |
| `proposal-researcher` | Sonnet 5.5 High | Read a pile (the customer's sources, or the product docs) and return an index with locations |
| `proposal-writer` | Opus 5.5 High | Write one section — or translate one — in customer-ready prose |
| `proposal-diagram-planner` | Opus 5.5 High | Read the whole draft; decide which diagram placeholders earn a diagram, what each shows, and where one is missing |
| `proposal-diagrammer` | Opus 5.5 High | Draw one section's planned diagrams (`flow` or Mermaid sequence) |
| `proposal-reviewer` | Opus 5.5 High | Read the draft cold as the evaluator; write findings with fixes |
| `proposal-publisher` | Sonnet 5.5 High | Compile the sections and publish to the viewer |

Launch each with its model (the `model` in its frontmatter; pass it explicitly when launching). Sonnet where the job is faithful extraction or mechanics; Opus wherever judgment or customer-facing expression decides quality.

**Why this split.** Every parent turn carries the parent's whole context forward. A sub-agent starts empty, reads only what its job needs, and returns a short result — so the bulk (tender packs, requirement docs, the full draft) never enters the parent. Delegate when a step reads a lot and returns a little; do small steps inline, since a sub-agent re-reads its own inputs and costs more than an inline step. Launch sub-agents in one message whenever their inputs don't depend on each other.

## Modes

Set at intake; record it in the dossier.

| Mode | When | Product facts from |
|---|---|---|
| **Catalog** | A Rocket CRM deal (loyalty, marketing automation, CS) | `requirements/` docs, framed by `docs/PRODUCT_NARRATIVE.md` and `docs/PRODUCT_MESSAGING.md` |
| **Sources-only** | Custom, government, or non-productized bids | `sources/` and human answers only. Requirement docs may inform how to describe a design the tender asks for; they are not a list of claimable features |

## Resources

| Path | Use |
|---|---|
| `docs/PRODUCT_NARRATIVE.md` | **Summary layer** (`.cursor/skills/proposal/narrative-overview.sh`: module intros + each capability's Overview and Purpose) — the whole product at a glance, read by the parent before planning. **Full sections** — customer-facing framing per capability, read by writers through their reads |
| `docs/PRODUCT_MESSAGING.md` | The story, the retention journey, and the internal lens. Informs emphasis; never quoted as a framework |
| `requirements/domains/_index.md` → `requirements/<Domain>.md` | What the product actually does. Concept and Journeys closely; Rules for constraints; System only when a section needs it |
| `.cursor/skills/proposal/SCAFFOLDS.md` | Structure (journey default, tender adaptation), section kinds, reading map, visuals, sources-only notes |
| `Writing Principles/CORE_WRITING_PRINCIPLES.md` | Pyramid, vertical/horizontal logic, MECE, abstraction levels, Why/What before How |
| `Writing Principles/PROPOSAL_WRITING_PRINCIPLES.md` | Reading (R1–R4), interpreting (U1–U4), structuring (S1–S7), writing (W1–W14) |
| `Writing Principles/THAILAND_CONTEXT.md`, `TRANSLATION_PRINCIPLES.md`, `TRANSLATION_PHILOSOPHY.md` | Thai market and Thai versions |
| rocket-deck slide library | Live mockups — fetched once into `slides.json` |

## Run folder

`workflows/proposal/runs/<customer>-<yyyymm>/` — committed; the audit trail and the resume point.

```
sources/        Inputs, verbatim, never edited (brief, TOR, notes, answers, review feedback)
research/       sources.md (customer index), product.md (fit map), assets.md (uploaded screenshots)
slides.json     Slide catalogue for this deal (pitch or library)
dossier.md      The parent's decisions: mode, pitch, scope, angle, brief checklist, open questions
gaps.md         Internal only: open facts, why they matter, who answers — never in the body
outline.md      The section plan
sections/       One file per section, numbered in document order
diagrams.md     The diagram plan
review.md       Reviewer findings and what was done about them
proposal.md     Compiled from sections/ — what gets published
viewer.json     { run_id, viewer_slug, url }
th/             Thai version, only when asked
```

## Steps

### 1. Understand

In one message, in parallel:

- **`proposal-researcher`, brief `sources`** → `research/sources.md`: every requirement with its location and their wording, the tender's own structure, their vocabulary, quotable pains, boundaries and constraints, ambiguities.
- **Slides** — the pitch's slides if the deal has one, else the library. **Assume there is a pitch** and find its slug before falling back: ask the user, or try the customer's name in the usual shapes (`<customer>-loyalty-crm`, …) — an unknown slug returns `Unknown pitch`. The pitch carries the customer's own uploaded images; the library shows generic ones.

  ```bash
  curl -s -H "x-internal-proposal-token: $ROCKET_PROPOSAL_TOKEN" \
    "https://workspace.rocketcrm.io/api/internal-proposal/slide-library?pitch=<pitch-slug>" \
    > workflows/proposal/runs/<run>/slides.json
  ```

  Drop `?pitch=` for the library. If `ROCKET_PROPOSAL_TOKEN` is unset, ask the user for it once.
- **The parent reads the product at a glance:** `bash .cursor/skills/proposal/narrative-overview.sh` and `docs/PRODUCT_MESSAGING.md`. This is what lets the parent judge scope, spot what the customer didn't ask for but will need (Proposal U4), and plan a structure that places every capability — without reading the full narrative.

Then, catalog mode: **`proposal-researcher`, brief `product`**, given `research/sources.md` and `slides.json` → `research/product.md`: per requirement, the capability that answers it, fit, the requirement doc and heading that back it, constraints, journey stage, candidate mockups.

Also in catalog mode, once the scope is known: **capture the pitch's slides** as whole-slide screenshots (SCAFFOLDS § Visuals), upload them, and list them in `research/assets-slides.md` (asset id, caption, what it shows, best section). One background agent can do this while the parent writes the dossier. Admin screens are **not** captured — writers embed the live demo-merchant portal (`loyalty.admin.*` mockups), so no section ever waits on a capture. If a background agent errors, treat its output as missing and re-plan; never report it as still running.

The parent reads both research files — open a source location directly when something needs checking — and writes `dossier.md`: mode, pitch, scope decisions, the **angle** (from `PRODUCT_MESSAGING.md` § Adapting to the customer: which parts of the story matter for this customer's channel mix and goals, and how the channel tension is framed or dropped), and questions. It also carries the **brief checklist**: every headline point the user named in their brief (differentiators, framings, quotes, comparisons, emphasis), each with the section that must carry it. The reviewer checks it every round (Proposal V8). The dossier records decisions; the research files hold the detail. Open facts go to `gaps.md` (what, why it matters, who answers) — never into customer prose.

### 2. Clarify → Gate 1

One round of the questions that most change the proposal, ranked, each saying why it matters; either/or where possible. A second round is fine; a third means convert the rest to entries in `gaps.md` and assumptions the prose can state in sendable form. Answers go into `sources/answers-<n>.md`; if they change the requirement picture, rerun the researcher that owns it.

**Gate 1:** the user accepts the dossier (scope, angle, gaps) or corrects it. Corrections are new sources.

### 3. Plan → Gate 2

Write `outline.md`. First decide the structure of the features part — journey default or the tender's own, and how (SCAFFOLDS § Structure). Then one entry per section:

- **Title** — the heading as it will appear, their term first when the tender has one.
- **Kind** — from SCAFFOLDS.
- **Scope** — what it owns and what it leaves to siblings (the MECE boundary).
- **Reads** — exact source locations, requirement doc headings, narrative anchors, and candidate mockup ids, taken from the research files.
- **Visual hints** — optional: a flow you expect to need drawing, a screen worth showing.
- **Depth** — primary deliverable or supporting.

**Gate 2:** the user accepts the plan. This is the cheapest place to change anything — restructuring an outline costs a minute; restructuring a finished draft costs an hour.

### 4. Write

Launch one `proposal-writer` per body section, all in one message, each with a handoff:

```
## Section handoff
Run: workflows/proposal/runs/<run>/
Section: sections/<nn>-<slug>.md
Mode: catalog | sources-only
Language: en
Outline entry: <verbatim from outline.md>
Siblings: <titles + one-line scopes of neighbouring sections>
Angle: <from the dossier>
Pitch: <slug or none>
```

Writers place mockups directly and leave **diagram placeholders** rather than drawing (SCAFFOLDS § Visuals). When the body is done, launch one more writer for the **executive summary** (`sections/00-executive-summary.md` — first in the document, written last), with the finished sections as its reads. The parent doesn't read the sections; it acts on what writers return (gaps, unsourced claims, notes for siblings).

Each outline entry carries **Opens from** and **Hands to** — the thread this section picks up and the one it passes on — so parallel writers can join up.

**Then one editor pass** (`proposal-writer`, `Mode: edit`): one writer reads every section in order and edits across files for flow only — opening and closing sentences, cross-references that say what they point to, ideas explained twice, slogan cadence (Proposal V9, V12). It does not change facts, scope, markers or diagrams. Parallel writing is fast; without this pass the document reads as separate leaflets.

### 5. Check

Compile without reading: `cat sections/*.md > proposal.md` in the run folder. Then, in one message:

- **`proposal-reviewer`** → `review.md`: findings per section, each with the writer correction that fixes it.
- **`proposal-diagram-planner`** → `diagrams.md`: for every placeholder keep, change, or drop; additions where a flow is being forced through prose; one set of actor names across the document.

### 6. Fix, then draw

1. Rerun writers for `review.md` findings and for any meaning `diagrams.md` asks to fold into prose — in parallel, one per affected section, each with its named corrections. Writers keep placeholders they weren't told to remove.
2. Then launch one `proposal-diagrammer` per section with planned diagrams, in parallel.

Fixes go first so the diagrammers draw into settled prose.

### 7. Publish → Gate 3

Launch `proposal-publisher` with the run path. It compiles, publishes, and returns the viewer link.

Before Gate 3, **look at the page**: open the viewer with Playwright (internal proposal password), scroll the whole document, and check every visual — error boxes, unknown markers, cropped or zoomed mockups, diagrams too wide for an A4 page. Fix those before handing over.

**Gate 3:** the user reviews the viewer page. Feedback goes into `sources/review-<n>.md`. When feedback carries a general lesson (voice, structure, visuals), fold it into `Writing Principles/` or `SCAFFOLDS.md` in the same round, so the next run doesn't repeat it.

### 8. Polish

Route each piece of feedback to its owner — prose to writers, diagrams to the diagrammer (through the planner if the change is about which diagrams exist), structure back to the outline first. Rerun only affected sections, then the publisher. Same link.

### 9. Only when asked

- **Thai:** writers rerun per section with `Language: th` into `th/sections/` (diagram labels included), following `TRANSLATION_PRINCIPLES.md` and `THAILAND_CONTEXT.md`; the publisher publishes `th/` as its own viewer entry (`<viewer_slug>-th`). English stays the source of truth — structural changes go into English first.
- **Submission pack** (bids): assemble the documents listed in the dossier; the workflow drafts only what it can write truthfully.

## Viewer

`https://workspace.rocketcrm.io/proposal-viewer/<viewer_slug>` (viewer code: the rocket-deck repo, `~/rocket-deck`, `src/components/internal-proposal/`; rendering fixes go there, not into the prose) — `viewer_slug` is the run folder name; internal proposal password; PDF export on the page. Mockups render live from rocket-deck, so a changed slide mockup shows on the next page load; prose drawn from a slide does not — rerun that section.

## Guardrails

These are the few hard lines; everything else is judgment.

- Never claim a capability, metric, date, integration, or past project the requirement docs or sources don't support. Unsupported → `gaps.md`, a sendable commitment the user approved, or scope it out.
- The body is sendable as-is: no gap markers, open questions, or notes to ourselves in customer prose (Proposal V6).
- "We" is Rocket; the customer is named in the third person ("KCG's members", "the KCG team"), never "you" / "your" — and never a briefing about their own situation (Proposal V1–V3).
- Customer prose never names internal tables, functions, or architecture — except a sources-only bid whose tender asks for system design.
- The messaging lens (StoryBrand roles, villain, framework names) never appears in customer prose.
- Diagrams are `flow` rocket-graphics (node diagrams) or Mermaid `sequenceDiagram` (messages over time) only.
- Never write the whole document in one pass; every section gets its own writer with its own reads.
- Gaps stay visible in `gaps.md` until a human closes them.
