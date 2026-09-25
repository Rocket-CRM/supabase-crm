# Dossier — EECO CRM (index over sources)

**Run:** `eeco-crm-202608`  
**Role of this file:** Index + depth judgment + decisions. Not a compressed rewrite of the TOR.  
**Primary source:** `sources/eastern-seaboard-crm-documents-combined.md`

---

## Source map

| Pack section | Combined file heading | Approx. lines | Use for |
|---|---|---|---|
| Mid-price / staffing cost model | `## pB0 2.pdf` | ~30–120 | Budget, role months, training cost assumptions |
| Bid announcement | `## annoudoc_…` | ~124–168 | Dates, mid-price, e-GP links |
| e-bidding document ๐๑๘/๒๕๖๙ | `## doc_2502000000_…` | ~172–656 | Quals, Part1/2 list, award criteria, payment, bonds |
| **TOR (authoritative scope)** | `## Attach_TOR_1.pdf` | ~661–2075 | Objectives, modules, architecture, security, migration, training, personnel, deliverables, scoring appendices |
| Contract template | `## contract_24.pdf` | ~2076–2430 | Post-award legal |
| Bonds / forms | Retention / Performance / Advance / Bid Bond / quotation | ~2431–end | Manual instruments |
| Work plan example | `## action_plan.xlsx` | ~2494–2670 | Post-award plan shape |
| Domestic materials | `## Domestic material use plan.pdf` | ~2674+ | Post-award |
| Part 1/2 checklists | `## Document Part1/Part2.pdf` | ~2822–2938 | Upload inventory |
| Definitions | `## definition_1/2.pdf` | ~2944–2998 | Conflict of interest / unfair competition |
| Company + personnel answers | `sources/company-and-personnel-answers-20260805.md` | full file | Approved Rocket profile, selected differentiators, visual sources, named roster |

---

## Bid facts (verbatim anchors)

- **Buyer unit:** สำนักยุทธศาสตร์การส่งเสริมและชักชวนการลงทุน (PSD), สกพอ.
- **System purpose:** Internal CRM + central DB for investor relationship / investment journey (pre-incentive focus), activity-centric (not investor-silo), link toward EEC OSS; task heat map / SLA / escalation for executives.
- **Users:** Named users ≥100, expandable; mobile/tablet friendly; external internet / overseas access with high security.
- **Delivery:** ≤210 calendar days; 3 payment milestones 20% / 50% / 30% at 60 / 180 / 210 days (TOR §7–8).
- **IP / handover:** Perpetual license + source code; structured clean DB; BI licenses (if any) paid by contractor for all users; cloud licenses cover ≥3 years no extra annual fee in years 1–3 (TOR §7.3).
- **Hosting:** Contractor designs **vendor-agnostic** min infra; สกพอ. coordinates Cloud (e.g. GDCC) for production hosts (TOR 5.3.7). Bidder-managed env = non-prod/POC only.
- **Warranty:** ≥1 year; 24×7 intake; reply ≤30 min; severity SLAs 4h / 24h / 48h (TOR §14).

---

## TOR capability index (writers open these sections — do not paraphrase away)

| Clause cluster | Topic | Source anchor |
|---|---|---|
| §1–2 | Rationale / objectives (Investment Journey, Task Mgmt, Daily Activity → insight) | TOR start |
| §3 | Internal use, ≥100 named users, mobile | |
| §4 / §4.13–4.14 | Bidder quals + past CRM/task work + personnel duty | |
| §5.1–5.2 | Project plan; BA → BRD + workflow (Centralized Intelligence) | |
| §5.3 | System design: schema collect, SDD, ERD (or SaaS equiv), UI/UX, env, EEC OSS API doc, infra mins for GDCC | |
| §5.4 | Risk / impact for EECO systems incl. EEC OSS | |
| §5.5.1–5.5.6 | Core modules: Data Capture, Data Mgmt (SSOT, master, lead scoring, dedupe, consent), Relationship & Activity, Pipeline/Workflow+SLA, Reporting, Integration (SSO EECO, EEC OSS, Open API) | |
| §5.6 | Dashboard / Heat Map; Buddhist + fiscal year filters; optional BI licenses | |
| §5.7 | API integration: SSO + EEC OSS pull status | |
| §5.8 | PDPA, RBAC need-to-know (LOI/NDA/financials), dynamic watermark, audit trail | |
| §5.9 | Migrate from scattered Excel; staging/cleanse/dedupe by Tax ID or legal name; 1:N contacts; logs ≥180d; backup/DR | |
| §5.10 | UAT; OWASP; SSL of EECO | |
| §5.11 | Admin TTT ×1 (≥8 pax); User TTT ×2 (≥30 total); meals; manuals | |
| §5.12 | 7 roles / headcount / degree / years | |
| §6–8 | Timeline, deliverables per phase, payment | |
| §9–10 | Scoring gate + Part1/2 document list + comparison table columns | |
| §14 | Warranty / incident SLAs | |
| §17 | IP assignment to EECO | |
| ภาคผนวก ก | Full scoring rubrics + POC scenarios | ~1432–1770 |
| ภาคผนวก ข | Personnel form | ~1776+ |
| ภาคผนวก ง | Past-work detail form | (in TOR appendices) |
| ภาคผนวก จ | POC timing/procedure | referenced from ก 3.4 |

---

## Vocabulary the prose must keep (buyer terms)

Centralized Intelligence · Activity / project as center · Investment Journey · Pre-incentive · EEC OSS · SSO EECO · Pipeline / Workflow · SLA Tracking · Escalation · Heat Map · Single Source of Truth · Lead Scoring · Consent (PDPA) · Dynamic Watermark · Named Users · Train The Trainer · Perpetual License · Source Code · GDCC (example cloud)

---

## Depth judgment

**Overall:** This TOR expects **process + architecture + integration contract depth**, not a thin marketing brochure.

| Area | Expected depth | Citation |
|---|---|---|
| Concept / methodology (scored 2.1) | Clear stages of work, system workflow, architecture diagram-level narrative, named tool stack | TOR §10.2(4), ภาคผนวก ก 2.1 |
| Core CRM modules | Module-level behavior matching §5.5 subsections; scenario language for EECO officers | TOR §5.5 |
| Integrations | Explicit SSO + EEC OSS pull; API interface document as deliverable — describe approach and endpoint scoping process, do not invent EECO API schemas | TOR §5.3.6, §5.7 |
| Data model | ERD (or SaaS-equivalent relationship doc) as **contract deliverable**; proposal should show conceptual entities (Investor/Org, Contact 1:N, Activity, Ticket, Pipeline Stage, Consent, Document classification) without inventing field-level schemas beyond TOR | TOR §5.3.3, §5.9.2 |
| Security | RBAC, watermark, audit, PDPA, OWASP — concrete controls, not slogans | TOR §5.8, §5.10 |
| Migration | Staging → cleanse → Tax ID/name dedupe → structured DB — method chapter | TOR §5.9 |
| UI | Form-based GUI, mobile-friendly; mockups optional hybrid | TOR §5.3.4 |
| Comparison matrix | **Every** in-scope TOR requirement row with equal/better + document ref | TOR §10.2(6) |
| POC | Live demo; proposal may include prep/checklist only | ภาคผนวก ก §3 |

**Do not invent:** EECO endpoint field lists, fake past contracts, named staff bios, company history, BI product choice unless humans decide, hosting SKUs beyond “min specs for GDCC coordination.”

---

## Boundary decisions (for writers)

1. **No CRM Knowledge claims.** Run facts come from this pack + human answers. Approved company positioning may be selected from `resources/standard-company-profile.md` only where the run source confirms it.
2. **Custom government CRM** for investor promotion — not a loyalty product proposal.
3. **English draft first**; Thai localize only on request.
4. **Company intro** = filled from `sources/company-and-personnel-answers-20260805.md`; evidence still required for the MarTech ranking, client count, and technical headcount.
5. **POC** is the largest technical score (40% of tech); written proposal cannot replace it — still must support 2.1 narrative and matrix completeness.
6. **SaaS vs custom build** is an open Clarify item — TOR allows SaaS-equivalent ERD language (§5.3.3) but also demands source code + perpetual license (§7.3.2).

---

## Open decisions / gaps

See `questions.md`. Persist answers under `sources/answers-….md` or Decision bullets below when received.

### Decisions (filled after Clarify — 2026-08-04)

1. **Bidder:** Rocket Innovation Co., Ltd., single company (not JV).
2. **Delivery model:** Hybrid configurable product + custom build for EECO-specific modules/integrations.
3. **Stack:** PostgreSQL · Node.js API · Next.js frontend.
4. **Hosting:** TOR 5.3.7 — **สกพอ. procures** production hosts via Cloud (example: GDCC). Bidder delivers **vendor-agnostic minimum infrastructure specification** + install/config on the environment สกพอ. provides. Non-production/POC may use a **bidder-managed** environment for build/demo only — must not read as production hosting. Example vendor names (GDCC, AWS) are illustrative unless TOR makes them exclusive.
4a. **Extras / “better”:** Comparison table TOR 10.2(6) allows **ดีกว่าหรือเทียบเท่า**. No separate bonus-point line in ก (dossier-only note). **Customer docs:** embed each extra in the relevant Core features subsection + short end summary; matrix Better; never explain the rubric to the buyer.
4b. **Technical practices context** (from `resources/standard-technical-practices.md`):
   - H1 `buyer_cloud_install` · H2 `buyer_ops` · H3 `db_native_queue` · H4 `oltp_embedded` · H5 `gov_crm`
   - **Pull in:** P01, P02, P03 (jobs only), P04, P05, P06, P07–P12 (ownership-split)
   - **Out:** P13 fraud matrix, P14 multi-channel consumer FE, P15 SaaS tenancy, Kafka/external broker, Rocket SIEM/SOC
4c. **Ops context** (`standard-operations-support.md`): O1 `officer_warranty_only` · O2 `buyer_ops_bidder_assist` + bidder app warranty · O3 `tor_channels_only` · O4 omit campaign ops. **Pull:** S04–S09, S14 (+ thin S01/S03/S08). **Out:** S02, S10, S13. **Separate Section 7.**
4d. **Timeline context** (`standard-delivery-timeline-migration.md`): T1 `tor_fixed_gates` (15/45/60/180/210) · T2 `batch_file` · T3 `tor_uat_scan` · T4 `ttt_tor`. **Pull:** D01–D06, D08–D10. **Out:** D07 CDC; **Pay % customer-facing** (20/50/30 dossier-only for alignment). One integrated schedule with buffers; proposal voice = Rocket delivers.
5. **Personnel / CVs:** Hybrid — named summary and Appendix B forms drafted; humans must provide degree/experience evidence, missing dates, and wet signatures.
6. **Project plan:** Included inside generated technical proposal (phases/milestones vs TOR §5.1, §6–8); post-award Excel plan remains separate hybrid.
7. **Narrative lead:** Tick TOR by feature/journey detail (not compliance paraphrase). Spine = Journey + fieldwork ops + SSO/security. TOR order organizes chapters; bodies use Key features / worked paths.
8. **Past works:** Assembled 2026-08-05 — ภาคผนวก ง cover + certificate + 6 contracts in `submission-pack/01-part1-qualification/06-past-work-qualifying/` (combined PDF) and Part 2 scoring folders. Lead: Syngenta 7.17M, Future Park 4.03M. POP MART image value corrected to certificate 6,219,041.52.
9. **POC:** `[GAP]` on ownership — no full prep chapter unless asked; scoring note only in outline.
10. **Agency logo for mockups:** registry `branding.logo.runAsset` = `assets/agency-logo.png` — **`[GAP: place official สกพอ./EECO logo file there before FE regenerate]`**.

### Company-profile pull — 2026-08-05

- **In:** one of Thailand's leading CRM specialists; 2025 MarTech Report top-three recognition across multiple relevant categories; 100+ corporate/enterprise clients; 30+ technical staff; CRM, B2C/B2B customer service, loyalty, and marketing automation.
- **Differentiation in:** configurable product foundation + project-specific build; maintainable composition of CRM objects/rules/workflows; layered and integration-ready architecture adapted to buyer-provided cloud.
- **Out:** unqualified “number one CRM” claim; loyalty-specific earning/redemption detail; AI implementation or architecture claim.
- **Visual in:** industry-leadership/presentation montage supplied by the user.
- **Evidence gaps:** exact MarTech report title/categories/pages; approved client-count and technical-headcount evidence; source/caption record for the event images.

### Personnel qualification review — action required before submission

The named proposal table and Appendix B forms summarize the supplied roster, but the current mapping does **not yet demonstrate full TOR 5.12 compliance**:

| Current proposed role | Evidence issue |
|---|---|
| Project Manager — Varapong Techapanichgul | MFA Digital and Technology is borderline for IT/computer/related; listed development history is roughly seven years and does not yet show a named information-system development PM project. |
| Business Analyst — Ekasit Jatupornwattana | Long systems-analysis experience is strong, but TOR 5.12 #2 requires a master's degree in IT/computer/related and the supplied form shows a bachelor's degree only. |
| Senior System Analyst — Thitawan Hirunurann | ICT bachelor's degree and UX/UI experience are a strong match for the TOR's design-oriented senior analyst role; confirm total web/interface-design years on Appendix B. |
| Project Coordinator — Assadavoot Anukool | Computer Engineering bachelor's degree and IT experience meet the coordinator threshold on current evidence. |

Additional roles are not scored TOR slots: Prakan Pojpienlert (Programme Coordinator), Teerakarn Boriboonsub (Support BA), Warinthon Aekjeen (operations coordinator), and Niraphat Rakphong (coordinator assistant). Remaining compliance work: align Appendix B forms with this mapping and strengthen PM/BA evidence before submission. Do not change signed-role forms without human approval.
