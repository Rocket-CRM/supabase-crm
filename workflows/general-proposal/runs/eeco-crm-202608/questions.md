# Clarify — EECO CRM (`eeco-crm-202608`)

**Gate:** Answer, defer, or say “proceed with gaps” before Outline/Write.  
**Rule:** Prefer either/or. Do not ask what the pack already answers.

---

## Round 1 — ranked (answer these first)

### 1. Bidder entity (blocks Part 1 + company shell + JV docs)

Who is submitting?

- **A)** Single Thai company (name: ______)
- **B)** Joint venture / consortium (list parties + who is principal)

Why it matters: Part 1 entity pack, conflict checks, whose past works count under §4.10 / §4.13.

---

### 2. Delivery model (blocks architecture chapter + matrix “what we propose”)

How should the technical proposal position the system?

- **A)** Custom-built application for EECO (source code + perpetual license as primary story)
- **B)** Configurable product / platform configured for EECO (still meeting source-code + perpetual / IP clauses)
- **C)** Undecided — draft as custom with `[GAP]` on product name/stack

Why it matters: TOR §5.3.3 allows SaaS-equivalent docs, but §7.3.2 requires perpetual license + source code. Writers must not invent a stack.

---

### 3. Technology stack (blocks ภาคผนวก ก 2.1 “เครื่องมือ”)

Name the intended stack for proposal scoring, or defer:

| Layer | Your answer or `defer` |
|---|---|
| Application / framework | |
| Database | |
| Auth integration approach to SSO EECO | |
| BI (if any; who pays licenses) | |
| Hosting assumption for design docs (GDCC-oriented min specs only?) | |

Why it matters: Scored explicitly under ภาคผนวก ก 2.1 item (3) tools.

---

### 4. Past works to claim (blocks scored 1.1 / 1.2 — human documents, but proposal may reference)

List contracts you will attach (or say “ops will fill; don’t mention names in narrative”):

For each: client · title · value · completion year · CRM vs task-tracking · public/private.

Minimum for eligibility: **≥1** CRM/task contract ≥2M completed ≤5 years.  
Scoring: more ≥2M contracts → higher 1.1; single highest value → 1.2 (≥8M = top band).

---

### 5. Named personnel (blocks hybrid CV pack + scored 2.2)

Will you provide the 8 named people (PM, BA, Senior SA, Senior Dev, Dev, 2× QA, Coordinator) matching TOR §5.12 **before** we draft the personnel section?

- **A)** Yes — paste names/roles (or attach CVs) now
- **B)** Draft empty ภาคผนวก ข shells only; humans fill later
- **C)** Partial — list which roles are filled

---

### 6. Scope emphasis for the written narrative (blocks outline MECE)

Which story should lead the technical approach? (pick one primary)

- **A)** Activity-centric CRM + investor pipeline (Investment Journey / pre-incentive)
- **B)** Executive task / SLA / heat-map / escalation operations tool
- **C)** Balanced A+B with integration (SSO + EEC OSS) as the third pillar

Pack supports all three; choice only sets chapter order and page emphasis.

---

### 7. POC ownership (blocks whether we write a prep note)

Who owns the live POC demo build?

- **A)** Same team as proposal writers — include a short prep checklist in the run
- **B)** Separate eng team — proposal workflow ignores POC except scoring note
- **C)** Unknown

---

## Lower priority (defer freely)

8. Exact bid price strategy vs ราคากลาง — **manual / commercial; out of scope for prose.**  
9. Whether to attach UI mockups in Part 2 vs POC-only screens — affects `mockup-prompts.md` only.  
10. Thai localization timing — default English until you ask.

---

## Answer log

| # | Answer | Date | Persisted to |
|---|---|---|---|
| 1 | Rocket Innovation, single company | 2026-08-04 | `sources/answers-20260804.md` |
| 2 | Hybrid configurable product + custom build | 2026-08-04 | same |
| 3 | Postgres + Node.js + Next.js; hosting per dossier (GDCC prod / AWS TH non-prod) | 2026-08-04 | same + dossier |
| 4 | Past works still GAP | 2026-08-04 | dossier |
| 5 | Personnel/CVs manual — later | 2026-08-04 | submission-plan reclass |
| 6 | Narrative lead = agent (three pillars) | 2026-08-04 | outline.md |
| 7 | Project plan inside proposal (generate) | 2026-08-04 | submission-plan + outline A12 |
| 8 | Company profile + differentiation approved; personnel roster supplied; evidence accompanies forms | 2026-08-05 | `sources/company-and-personnel-answers-20260805.md`, A0, A12, dossier |
