# Principles review — `eeco-crm-202608`

**Date:** 2026-08-05  
**Trigger:** Cold-reader review after customer feedback that the proposal still sounded AI-written and writer-facing; updated after approved company and personnel inputs were added.

## Verdict

The earlier review was not strong enough. It correctly removed the screenshot examples (“contract hard stops,” payment percentages, and “this section owns”), but it declared the voice fixed without testing structural repetition or reading representative passages as a customer.

The anti-slop script also returned `0/100` while obvious document choreography remained. Lexical detection is therefore a supplement only; it cannot pass proposal voice.

## Cold-reader evidence

| Position | Passage reviewed | Finding | Action |
|---|---|---|---|
| Beginning | Executive summary | Final paragraph explained Section 5, the comparison table, repeated placement, and “Better” labels | Replaced with a direct summary of the shared case model and the five proposed enhancements |
| Middle | Architecture and Core features | “This section is the technical backbone”; six chapters repeated “Objects in this chapter / Key features / How it works / Compliance anchor” | Removed architecture meta and the redundant API index; replaced generic headings with subject-specific headings; removed duplicate TOR paraphrases and decorative examples |
| End | Delivery, operations, enhancements | Delivery repeated the same calendar in a milestone table, phase table, working schedule, combined table, and second flowchart; operations repeated SLA and ticket flows | Kept one milestone view, one delivery sequence, and one integrated schedule; consolidated incident handling; removed the duplicate severity table, second incident flow, one-line ticket workflow, and optional cadence padding |

## Workflow changes

- `REFERENCE.md`: bidder-to-buyer sentence test, invisible protocol rule, structural fingerprint review, and evidence requirement.
- `SCAFFOLDS.md`: capability texture changed from a seven-slot default template to a judgment-based menu; duplicate traceability and visible scaffold labels now fail review.
- `PROPOSAL_WRITING_PRINCIPLES.md`: identical peer scaffolds, journey walkthroughs, SCQA, and closing matrices are now conditional rather than default.
- `CORE_WRITING_PRINCIPLES.md`: proposal openers must state behavior or a commitment; cross-references cannot replace the primary operational story.
- Writing-principles routing now separates Rocket product proposals from custom/government runs, which use run sources rather than CRM Knowledge for facts.
- Anti-slop reference: added proposal-specific structural patterns, including TOR echo, document routing, duplicate compliance treatment, and repeated generic headings.
- Timeline resource: three information needs may be combined; duplicate schedule artefacts now fail review.
- Operations resource: support and technical responsibilities must stay distinct conceptually, but no longer require one published subsection per practice ID.

## Final checks

- No payment percentages or “contract hard stops” remain in `proposal.md`.
- No “Objects in this chapter” or “Compliance anchor” headings remain.
- TOR dates remain aligned at days 15, 45, 60, 180, and 210, with buffers before the Phase 2 and Phase 3 commitments.
- Architecture now states the selected background-job model directly without naming unrelated broker products or repeating SOC disclaimers.
- The comparison matrix no longer prints payment percentages, its enhancement references point to Section 9, and its PDF-assembly instruction has been removed.
- The POC now states the demonstration environment, representative-data boundary, and observable result for each scenario.
- Section source files have been synchronized with the compiled proposal edits.
- Company introduction now uses the human-approved Rocket profile, project-relevant configurable-depth and architecture differentiators, and an evidence map. Loyalty-specific detail and AI implementation claims were excluded because they do not serve this TOR.
- “Top CRM in Thailand” was narrowed to “one of Thailand's leading CRM specialists” because the supplied evidence claim is top-three recognition, not a documented number-one ranking.
- The 2025 MarTech Report claim remains conditional on attaching the exact report extract/categories/pages; client-count and technical-headcount evidence also remain assembly gaps.
- Delivery Section 6 now names the core team and additional specialists while leaving Appendix B forms and supporting evidence as the formal proof.
- Personnel compliance is not asserted in customer prose. The dossier flags remaining evidence gaps for Project Manager (Varapong) and Business Analyst (Ekasit) before submission; Appendix B forms still need remapping to match Section 6.

## Thai final coverage addendum — 2026-08-07

The final Thai anti-AI pass is a condensed structural version of the frozen English backup. Visuals changed from 34 to 22: images 21→13, Mermaid diagrams 12→8, and the executive diagram remained. The removed mockups and diagrams were checked against surviving prose, tables, ERD, flows, mockups, and schedule rather than assumed decorative.

Coverage remains complete at the accepted depth for architecture, system design, database design, security, integration, migration, delivery, and operations. The parity check found and restored three details that had become less explicit:

1. Operational CSV/Excel imports share validation rules with migration staging, while historical cutover remains a separate controlled process.
2. The surviving Stage model includes reverse transitions for reclassification, incomplete information, and failed readiness.
3. The Phase 1 API Interface contract explicitly includes Authentication, Endpoint, fields, errors, scope, and non-goals.

The workflow now requires a before/after coverage and visual inventory for large rewrites. `REFERENCE.md`, `SCAFFOLDS.md`, `runs/README.md`, the general-proposal Cursor rule, `CORE_WRITING_PRINCIPLES.md`, `TRANSLATION_PRINCIPLES.md`, and the anti-slop text reference all state that duplicate presentation may be cut but unique commitments and technical semantics may not.
