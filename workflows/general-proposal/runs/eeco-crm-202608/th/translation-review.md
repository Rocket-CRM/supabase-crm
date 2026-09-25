# Translation and anti-AI review — `th/` (EECO CRM)

**Reviewed against:** `TRANSLATION_PRINCIPLES.md`, `CORE_WRITING_PRINCIPLES.md`, general-proposal `SCAFFOLDS.md`, and the anti-slop proposal patterns  
**Files reviewed:** `th/proposal.md`, `th/comparison-matrix.md`  
**English backup:** run root + `en/`

## Changes completed

- Rewrote literal English constructions into formal Thai proposal language, especially Escalation, reporting, integration, security, migration, delivery, and support passages.
- Kept established technical nouns in English where appropriate, while replacing English words used as Thai verbs.
- Reduced the proposal from 1,111 to approximately 900 lines by removing repeated object tables, duplicate diagrams, repeated schedule narration, and back-to-back mockup galleries. Total visuals changed from 34 in the frozen English version to 22 in Thai (21→13 images, 12→8 Mermaid diagrams, with the executive diagram retained).
- Retained detailed object and journey treatment only in ข้อ 5.3, where Investment Journey is the central operating model.
- Replaced repeated `รวมถึง (ความสามารถย่อย)` headers with subject-specific table headings.
- Localized `Reference:` to `อ้างอิง:` and corrected heading hierarchy.
- Rewrote proposal-owned matrix cells as specific commitments and removed the duplicated list of enhancements at the end of the matrix.

## Coverage-preservation check

The Thai rewrite is an authorized structural divergence from the frozen English backup, so it was checked by meaning rather than line-for-line layout parity.

| Domain | Result |
|---|---|
| Architecture and system design | Preserved: logical layers, background jobs, deployment ownership, environments, infrastructure minima, availability, backup/DR, and logging |
| Database design | Preserved: PostgreSQL model, ERD, integrity rules, history, and transactional/reporting separation |
| Security | Preserved: SSO, RBAC, need-to-know, dynamic watermark, audit, OWASP, SSL, and production responsibility boundaries |
| Integration | Preserved: SSO/OSS adapters, REST/SOAP, freshness/error handling, and the Phase 1 API Interface contract |
| Migration, delivery, and operations | Preserved: staging, mapping, deduplication, reconciliation, rollback, milestones, UAT/security gates, cutover, training, warranty SLAs, escalation, and change control |

Eight interface mockups and four Mermaid diagrams were removed because their functionality or sequence already remained in the surviving tables, prose, mockups, ERD, and integrated schedule. The removed visuals were M05, M06, M07, M09, M11, M14, M15, M16; the removed diagrams were the separate detailed Stage state model, Journey-object relationship view, three-phase delivery summary, and support-triage summary.

The parity review found three details that had become less explicit and restored them:

1. Operational CSV/Excel imports share validation rules with migration staging, while historical cutover remains a separate controlled process.
2. The surviving Stage model now names the reverse routes and reasons: reclassification, incomplete information, and failed readiness.
3. The API Interface commitment now explicitly includes Authentication, Endpoint, fields, errors, scope, and non-goals.

## Cold-reader evidence

| Position | Passage | Result |
|---|---|---|
| Beginning | Company introduction and executive summary | Opens with bidder credentials, operating outcomes, and delivery commitments; no document choreography or unsupported ranking claim |
| Middle | Core features, especially ข้อ 5.1–5.6 | Chapter structures now vary by subject; supporting modules use one main table while ข้อ 5.3 retains the deeper journey, worked path, and Stage model |
| End | Delivery, warranty, POC, and enhancements | Dates, SLA commitments, responsibilities, and POC results are stated as Rocket commitments rather than TOR commentary |

## Final checks

| Check | Result |
|---|---|
| Arabic numerals for quantities | Pass |
| Banned metaphor calques | Pass |
| Thai noun marker + English verb glue | Pass |
| Proposal voice and structural anti-slop | Pass after targeted cold-read; lexical detector also returns 0/100 |
| English root and frozen backup retained | Pass |
| Commitments, dates, personnel names, and TOR references retained | Pass |
| Architecture, database, security, system design, integration, migration, delivery, and operations depth | Pass after coverage-preservation review |
| Removed visuals accounted for and unique semantics retained | Pass after restoring three specificity gaps |
| Matrix column 1 matches the available source extraction | Pass |

## Source limitation

The repository contains `sources/eastern-seaboard-crm-documents-combined.md` but not the original binary `Attach_TOR_1.pdf`. Matrix column 1 therefore remains verbatim from the available extraction, including OCR forms such as `จานวน`, `กาหนด`, and `ดาเนินการ`. Visual verification and correction against the original PDF remains required before final packing.

## Verdict

The Thai proposal and proposal-owned matrix text pass the final language and anti-AI review. The only remaining submission gate is visual verification of protected TOR wording against the original PDF, followed by human approval to refresh the submission pack from `th/`.
