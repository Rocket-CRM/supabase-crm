# Proposal generator — REFERENCE

Thin Cursor workflow: one interactive thread, one run folder, four objects. No phase machine, no DB blackboard, no `project_briefs` row.

## Purpose

Produce a customer-ready proposal from whatever material a salesperson already has. The run folder is the only state — any fresh thread pointed at the same folder can resume.

## The four objects

1. **Input** — run-specific knowledge about this deal (brief, TOR, notes, answers, review corrections). Never shared across customers. Example: a pasted email thread dropped into `runs/bigc-202607/sources/`.
2. **Resource** — durable shared material, always readable: the section grammar, writing principles, the capability catalogue, live product facts. Example: `workflows/proposal-generator/SCAFFOLDS.md`.
3. **Output** — what this run writes: `dossier.md` (internal understanding), `outline.md` (the section contract), `sections/*.md`, and the compiled `proposal.md`. Example: `runs/bigc-202607/proposal.md`.
4. **Review** — human gate. Accept, correct, or redirect. Corrections become new Inputs. Example: “cut pricing, deepen integration” after Review 2.

## Resources

### In this repo (read, never copy)

| Path | Role |
|---|---|
| `workflows/proposal-generator/SCAFFOLDS.md` | **The section grammar** — types, required slots, word floors, per-section reading list. Non-negotiable |
| `Writing Principles/PROPOSAL_WRITING_PRINCIPLES.md` | How to read requirements and write the proposal (R/U/S/W) |
| `Writing Principles/CORE_WRITING_PRINCIPLES.md` | Structure: vertical/horizontal logic, MECE, layered depth |
| `docs/PRODUCT_NARRATIVE.md` | Derived sales Product Narrative — the fuel for every section. `###` anchors mapped in SCAFFOLDS.md |

`Writing Principles/` is this repo's git source of truth (see `19-writing-principles-mcp.mdc`); the `writing-principles` MCP serves the same content. Do **not** vendor further copies.

**Open item:** `resources/` still holds copies pulled from `rocket-deck` on 2026-07-27, and they **differ** from `Writing Principles/` (34,611 B vs 34,596 B) — the two repos have drifted. Read `Writing Principles/` until someone decides which is authoritative, then delete `resources/` and `resources/SOURCE.md`.

### Product facts (tables win)

CRM project `wkevmsedchftztoolkmi`. Primary access: CRM Knowledge MCP (`get_feature_context`, `resolve_feature_term` for customer vocabulary, `search_semantic`).

| Table | Role |
|---|---|
| `internal_knowledge_feature_items` | Feature tree (`slug`, `name`, `parent_id`, `aliases`, `is_active`) |
| `internal_knowledge_blocks` | Claimable prose (`content`, `knowledge_type`, `is_active`, `source_ref`) |

**Verified 2026-07-27:** MCP and SQL fallback both work. Rows with `is_active = false` are not claimable. Never invent a capability. Prefer the catalogue for section fuel and the MCP for specific claims.

## Intake (deliberately lax)

No required fields. No schema. No form. Any material in any format is a valid start — including a few pasted paragraphs.

1. **Read everything first** — `sources/`, pasted messages, Resources. No question before this.
2. **Judge sufficiency, do not validate fields.** Can you write a proposal a customer would take seriously? Use `project-brief-contract.md` privately to notice gaps; never quote its field names at the user.
3. **Ask in rounds, ranked by impact.** One round of at most 5–7 questions; each states why it matters. Prefer either/or. A second round is allowed; a third is a smell.
4. **Never block.** Unanswered items become `[GAP: …]` markers and stated assumptions. Always produce a Reviewable dossier.

## Run folder

`workflows/proposal-generator/runs/<customer>-<yyyymm>/`

```
sources/       # Injected Inputs, verbatim, never edited
dossier.md     # Output of Understand → Review 1
outline.md     # Output of Plan → Review 2 (the section contract)
sections/      # One file per section, written one at a time
proposal.md    # Compiled from sections/ → Review 3
```

Runs are committed. That folder is the audit trail and the resume point. `sections/` exists so a section can be rewritten without touching the rest, and so a fresh thread can pick up mid-draft.

## Stages

**Four stages, because depth comes from the two that were missing.** Writing the whole document in one pass is what produced a 3.2k-word coverage memo where the production pipeline produces ~10k.

1. **Understand** — read Inputs + Resources → sufficiency → gap questions → write `dossier.md` → **Review 1**
2. **Plan** — write `outline.md`: every section with its `section_type`, scope note, word floor, reading list, and primary-deliverable flag → **Review 2** (cheapest gate in the workflow — fixing an outline costs a minute, fixing a finished document costs an hour)
3. **Write** — **one section per turn**, in the phase order from SCAFFOLDS.md. Before each section: open its reading list. After each section: check its slots and floor. Then compile `proposal.md` and run the self-check.
4. **Polish** — review feedback Inputs → rewrite affected `sections/` files → recompile → **Review 3**

### Why one section per turn

The old system's `foundation → body_a → body_b → summaries` batching was never about queues. Its function was to put the model's whole attention on **one section type at a time**, with only that section's context loaded. An interactive thread gets the same effect for free by writing one section per turn. That is the entire port — no orchestrator, no queue, no checkpoint table.

## The dossier is an index, not a summary

**Proposal length is independent of dossier length.** It is a function of how many capabilities are in scope, the per-section floors in SCAFFOLDS.md, and how much the catalogue says about each. The dossier decides *what is in scope, in whose vocabulary, against which requirements* — it does not supply volume. There is no word floor on it, and padding it helps nothing.

What went wrong in `yuanta-202607` was the opposite of thinness. `sources/dossier-brief.md` is **4,519 words** — client background, goals, ~100 lines of functional requirements, per-system integration constraints, ops and migration context. The run's `dossier.md` is **633 words**. The Understand stage compressed the brief into a summary, and the Write stage then drafted from the summary. Roughly 86% of the supplied context was discarded before a single section was written.

So the rule is about **information preservation, not length**:

- `dossier.md` **never replaces `sources/`.** It is a working index over them: what is in scope, which source section covers each requirement, what was decided, what is still open.
- **Point, don't paraphrase.** For requirement detail, cite the source location (`sources/dossier-brief.md` § Requirements → Functional) instead of restating it in compressed form. Detail that only exists in paraphrase has been lost.
- **Extract verbatim what the prose will need**: the customer's own vocabulary, quotable operational pains ("elderly members cannot self-redeem"), and boundary decisions (who calculates earn today, who owns identity, which system is master).
- **Every section's `reads` list points at the brief, not at the dossier.** Writers open the source material for requirement detail and the catalogue for platform detail. The dossier tells them *where to look*, not *what it said*.

If the sources genuinely lack something a section needs, that is a `[GAP: …]` — not a reason to stall, and not something to fill by inventing.

## Review junctures

| Gate | Reviews | Pass | Fail |
|---|---|---|---|
| Review 1 | `dossier.md` | Plan may start | Corrections → revise dossier |
| Review 2 | `outline.md` | Writing may start | Sections merged, missing, or mistyped → re-plan |
| Review 3 | `proposal.md` + self-check | Sendable | Corrections → Polish affected sections, loop |

Mark every unresolved item as `[GAP: what is missing — who can answer it]`. Gaps stay visible until a human removes them. Never close a gap by inventing a claim.

## Outline node fields

One entry per section in `outline.md`. Six fields, all plain markdown — no schema, no validator.

| Field | Purpose |
|---|---|
| `title` | The H2 as it will appear |
| `section_type` | From SCAFFOLDS.md — determines the required slots |
| `phase` | foundation / body_a / body_b / summaries — determines write order |
| `scope_note` | What this section owns, and explicitly what it does **not** (the MECE boundary against its siblings) |
| `reads` | What to open **before** writing: catalogue anchors **and** the source-brief sections that carry this section's requirements. Never "the dossier" alone |
| `target_length` | Soft floor from SCAFFOLDS.md, adjusted up for the primary deliverable. A floor, never a budget — total document length is emergent, not targeted |

Mark the primary-deliverable sections. They get more depth than siblings; everything else is calibrated against them.

## Hard limits

- Hold the proposal voice from `Writing Principles/`.
- **Never write the whole document in one pass.** One section per turn, reading list opened first.
- **One `feature_module` per capability, not per domain.** Collapsing earn + tiers + redemption into one section is the known failure mode.
- Invent no capabilities, metrics, dates, or integrations.
- Never cite an inactive knowledge block.
- Customer-ready prose in Outputs; internal reasoning stays in `dossier.md`.
- Flag gaps with `[GAP: …]`.
- Output language: English first for review unless the brief already requires Thai-only. Platform terms stay English inside Thai prose. For a manual Thai convert after English review, follow `Writing Principles/TRANSLATION_PRINCIPLES.md` and keep English as backup (e.g. run-root or `en/`, Thai under `th/`).
- Existing Inngest / `project_briefs` pipeline is untouched.
