# Outline — EECO CRM technical proposal + comparison matrix

**Run:** `eeco-crm-202608`  
**Bidder:** Rocket Innovation Co., Ltd.  
**Status:** Review 2 accepted · Write complete · ready for **Review 3** (compiled docs)  
**Language:** English first  
**Narrative lead (agent):** Three pillars — activity CRM + Investment Journey · executive ops (task/SLA/heat map) · integration & migration — then TOR §5.5 module order for tick-off.

---

## Document A — `proposal.md` (Part 2 technical narrative)

| # | title | section_type | tor_clauses | scope_note | reads | visuals |
|---|---|---|---|---|---|---|
| A0 | Company introduction | `company_introduction` | §4.13–4.14 context; evidence remains in bid appendices | Official company profile; project-specific suitability; configurable-depth + architecture differentiators; evidence map. AI omitted from implementation scope. | `sources/company-and-personnel-answers-20260805.md`; `resources/standard-company-profile.md` | industry-leadership proof visual |
| A1 | 1. Executive summary | `executive_summary` | §1–2, §3 | Written **last**. Current→Future→Impact themes (Journey / exec visibility / integration) + `{{diagram:executive-overview}}` pillar matrix. No new claims. | dossier decisions; body after write | `diagrams/executive-overview/` |
| A2 | Understanding EECO’s operating problem | `glossary` + frame | §1, §2, §3 | Buyer vocabulary: Centralized Intelligence, Investment Journey (pre-incentive), Activity center, Named Users ≥100, mobile. Not a product brochure. | TOR §1–3 (~672–717) | none or simple concept mermaid |
| A3 | Delivery model & methodology | `architecture_and_integration` (approach) | §5.1–5.4, §10.2(4), ก 2.1 | **Hybrid:** configurable product core + custom build for EECO modules/integrations. Stages: plan → BA/BRD → design → build → migrate → UAT/secure → train/go-live. Tools: PostgreSQL, Node.js API, Next.js. | TOR §5.1–5.4; answers-20260804 | mermaid flowchart (methodology) |
| A4 | System architecture & environment | `architecture_and_integration` | §5.3, §5.3.5–5.3.7, §5.7, §5.10 | Layers: Next.js · Node.js API · PostgreSQL. Auth via SSO EECO. Production: **สกพอ.-provided cloud** + **vendor-agnostic min infra specs**. Practices pull: P01–P06, P07/P09/P11 placement (no Kafka, no SaaS tenancy, no Rocket SOC). | TOR §5.3, §5.7; answers; `resources/standard-technical-practices.md` (P01–P06, P07/P09/P11) | mermaid architecture |
| A5-intro | Core features (parent) | grouping | §5.5 cluster | Short intro; subsections 5.1–5.7 hold detail | — | none |
| A5 | 5.1 Data capture & master data | `capability_module` | §5.5.1–2 | Key features **with Includes column**; embed guided merge as beyond-min | TOR §5.5.1–5.5.2 | mockups |
| A6 | 5.2 Fieldwork / tickets | `capability_module` | §5.5.3 | Includes column; embed offline queue + escalation matrix UI | TOR §5.5.3 | mockups |
| A7 | 5.3 Investment Journey | `capability_module` | §5.5.4, §2.1 | Includes column; embed journey template library | TOR §5.5.4, §2.1 | mermaid |
| A8 | 5.4 Dashboard / heat map | `capability_module` | §5.5.5, §5.6 | Includes column; embed scheduled digests | TOR §5.5.5, §5.6 | mockup |
| A9 | 5.5 SSO & EEC OSS | `architecture_and_integration` | §5.5.6, §5.7, §5.3.6, §5.4 | Includes column; no invented endpoints | TOR as listed | sequenceDiagram |
| A10 | 5.6 Security & audit | `security_and_compliance` | §5.8, §5.10 | Includes column; practices P08–P12 app-facing; P11 as log handoff not Rocket SOC; cross-ref §4.4 for stack placement | TOR §5.8, §5.10; `resources/standard-technical-practices.md` (P08–P12) | mockups |
| A11 | 5.7 Migration | `capability_module` | §5.9 | Methodology D06; dates on Section 6 timeline | TOR §5.9; `standard-delivery-timeline-migration.md` (D06) | mermaid |
| A12 | 6 Delivery plan & integrated timeline | `delivery_plan` | §5.1, §5.11–12, §6–8, §17 | Named core team + additional specialists; Appendix B remains formal proof. TOR **delivery** dates + one integrated schedule with buffers; migration/testing/training placed on the same calendar; **no Pay %**; proposal voice | TOR delivery clauses; `sources/company-and-personnel-answers-20260805.md`; Appendix B forms; `standard-delivery-timeline-migration.md` | mermaid |
| A15 | 7 Operations & support | `operations_and_support` | §14 | Separate section; S04–S09, S14; Support vs Technical; TOR SLA numbers; no end-customer CS | TOR §14; `standard-operations-support.md` | mermaid |
| A13 | 8 Proof of Concept | note | ก §3 | Owner-facing commitment; no scoring coaching | ภาคผนวก ก §3 | none |
| A14 | 9 Enhancements summary | note | 10.2(6) | Short summary only — detail embedded in 5.x | TOR 10.2(6) | table |

**MECE notes:** A5–A8 own product behavior; A9 owns external systems; A10 owns controls; A11 owns migration methodology; A12 owns the integrated delivery calendar and acceptance readiness; A15 owns warranty/ops; A13 POC; A14 extras summary.

---

## Document B — `comparison-matrix.md`

| # | title | section_type | tor_clauses | scope_note | reads | visuals |
|---|---|---|---|---|---|---|
| B1 | Requirement comparison table | `requirement_comparison_matrix` | §5 (all in-scope), §3, §6–8, §14, §17 as needed | Columns exactly: (1) Buyer requirement (copy TOR) (2) What we propose (3) Equal / better / note (4) Document reference → section of proposal.md. One row per atomic TOR requirement under §5.x; do not drop clauses. | TOR §10.2(6) columns (~1270–1282); full §5 | table only |

---

## Supporting (not customer chapters)

| Item | Action |
|---|---|
| `mockup-prompts.md` | Prompts for A6 activity form, A8 heat map / dashboard, login + customer 360 (POC-aligned screens) |
| Personnel / ภาคผนวก ข | **Hybrid** — named proposal summary + drafted forms; humans add evidence, missing dates, and signatures |
| Past-work narrative | **Skip inventing** — `[GAP]` attach PDFs |
| Company intro body | Filled from approved human source + standard company-profile resource; evidence gaps remain in dossier |

---

## Write order (after Review 2)

1. A2 → A3 → A4 (frame + architecture)  
2. A5 → A6 → A7 → A8 (capabilities, TOR order)  
3. A9 → A10 → A11  
4. A12 (plan)  
5. B1 matrix (while clause tags fresh)  
6. A13 note · A0 shell · A1 executive summary last  
7. Compile + self-check  

Prefer **one section per turn** for A3–A12.

---

## Review 2 checkpoint

Confirm or correct:

1. Project plan lives in **A12 inside proposal** (not a separate bid PDF) — OK?  
2. Hosting split: **production = EECO/GDCC coordination**; **non-prod/POC = AWS Thailand** — OK?  
3. No personnel chapter / no invented past works — OK?  
4. Three-pillar narrative then §5.5 module chapters — OK?  
5. Native reporting default (no BI product named) unless you specify a BI tool?
