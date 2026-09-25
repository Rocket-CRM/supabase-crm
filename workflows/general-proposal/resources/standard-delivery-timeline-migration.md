# Standard delivery timeline, pre-go-live & migration (general proposals)

Durable **Resource** for custom / government / non-productized bids. Distilled from Rocket’s Caltex **Part VIII — Pre-Go-Live, Migration Process & Timeline** and generalized.

**Hard rules**

1. **TOR delivery calendar is sovereign for alignment.** Every milestone and combined timeline must **finish on or before** TOR delivery / acceptance dates. Writers may break work into **finer milestones** for confidence and must leave **explicit buffer** before each hard delivery date — never invent a longer overall duration than the TOR allows.
2. **Customer prose proposes Rocket’s plan** — what we will deliver, by when, how we sequence work. It is **not** a restatement of TOR payment clauses, not a tutorial of “what the Authority asked for,” and not writer meta (“this section owns…”, “contract hard stops”).
3. **Payment percentages stay out of the technical proposal** unless the bid pack explicitly requires the technical narrative to restate commercial payment terms. Dossier may record 20%/50%/30% for alignment checks; customer tables use **delivery milestones** and **deliverables**, not a Pay column.
4. **Three information needs, not three mandatory artefacts:** the buyer must be able to find (A) contractual milestones and Rocket’s sequence, (B) migration method when data cutover exists, and (C) one integrated calendar covering build, test, migrate, train, go-live, and buffers. Combine these into the fewest tables/diagrams that stay readable; do not repeat the same schedule as a milestone table, phase table, Gantt, and flowchart.
5. Never paste Caltex load numbers (100k tx/h, 1.3M members, zero-downtime CDC night) into a government Excel-migration CRM.

Companion: `REFERENCE.md`, `SCAFFOLDS.md`, `standard-operations-support.md` (warranty ops ≠ this calendar).

---

## Context dimensions (dossier before Write)

### T1 — Calendar source

| Code | Meaning |
|---|---|
| `tor_fixed_gates` | Hard days from contract signature (e.g. EECO 15 / 45 / 60 / 180 / 210) |
| `tor_months` | Duration in months; derive week plan |
| `agreed_custom` | Human-supplied schedule in answers |

### T2 — Migration relevance

| Code | Meaning |
|---|---|
| `none` | Greenfield; no legacy cutover chapter |
| `batch_file` | Excel/CSV/staging → cleanse → load (typical gov) |
| `system_cutover` | Legacy system → new platform; may need dual-run / delta |
| `zero_downtime_cdc` | High-volume live cutover with CDC — only if scale + Clarify justify |

### T3 — Pre-go-live depth

| Code | Meaning |
|---|---|
| `tor_uat_scan` | Joint UAT + system test + security scan (EECO-like) |
| `full_sit_uat_sec_perf_pilot` | Caltex-depth suite — only if TOR/scale requires |
| `minimal` | Thin acceptance only |

### T4 — Training / pilot

| Code | Gate |
|---|---|
| `ttt_tor` | Train-the-trainer volumes from TOR |
| `pilot_limited` | Limited pilot before full go-live |
| `no_pilot` | Straight to go-live after UAT |

---

## Practice catalog

### D01 — Key milestones & phase process flow

| | |
|---|---|
| **Idea** | Ordered phases from plan → BA/design → build → pre-go-live → migrate → train → go-live, each with **includes** (artefacts / activities). A diagram is optional when it explains dependencies better than the integrated calendar. |
| **Apply when** | Any scored delivery / methodology / project plan. |
| **Do not apply** | Phases that contradict TOR payment packages. |
| **Lands in** | `delivery_plan` (primary). |
| **Shape** | Map each phase to TOR delivery package dates (not payment %). |

### D02 — Delivery milestone table (TOR-aligned dates)

| | |
|---|---|
| **Idea** | One table: Milestone · By when · What Rocket delivers — dates match TOR delivery packages. |
| **Apply when** | TOR has phased delivery / acceptance packages. |
| **Do not apply** | A **Pay %** column, “what the buyer receives” restating TOR § payment, or “contract hard stops” coaching. Payment terms live in the TOR/contract; dossier may note them for internal alignment only. |
| **Lands in** | `delivery_plan` — delivery commitment table written as our plan. |
| **Shape** | Column headers like “Milestone | Calendar | Rocket delivers”. Voice: “we submit / we complete / we hand over.” |

### D03 — Detailed working schedule with buffer

| | |
|---|---|
| **Idea** | Week- or day-banded plan **under** each TOR gate showing internal milestones; **buffer rows** before each hard gate (e.g. UAT sign-off target several days before day-180 package lodge). |
| **Apply when** | When the TOR package dates alone do not show enough execution detail or buffer. It may be the integrated calendar rather than a second schedule. |
| **Do not apply** | Schedules that consume 100% of calendar with zero buffer, or that push a TOR deliverable past its gate. |
| **Lands in** | `delivery_plan`. |
| **Review criterion** | See **Final review — timeline alignment** below. |

### D04 — Pre-go-live testing & validation flow

| | |
|---|---|
| **Idea** | Testing chain with dependencies: SIT (if integrations) → UAT → security → performance (if required) → training → pilot (if required) → go/no-go. Checklist: technical + business. |
| **Apply when** | T3 ≠ `minimal`. |
| **Do not apply** | Caltex performance targets unless this bid’s numbers exist. |
| **Lands in** | `delivery_plan` (pre-go-live subsection). |
| **Shape for EECO** | Joint UAT with สกพอ.; system testing report; security scan; SSL; training — per TOR 5.10–5.11. No 25k concurrent-user claim. |

### D05 — Go-live checklist & deliverables ownership

| | |
|---|---|
| **Idea** | Technical and business checklist; deliverable×owner table (SIT report, UAT sign-off, scan, training completion, go/no-go). |
| **Apply when** | D04. |
| **Lands in** | `delivery_plan`. |

### D06 — Migration methodology (batch / file)

| | |
|---|---|
| **Idea** | Staging → map → cleanse → dedupe → reconcile → load → preserve controls; reports; rollback. |
| **Apply when** | T2 = `batch_file`. |
| **Lands in** | Capability `migration` module **and** summarized on combined timeline (when migration runs vs TOR gates). |
| **Shape** | EECO: Excel by bureau; Tax ID / legal name; 1:N persons — detail in Core features migration subsection. |

### D07 — Migration methodology (system cutover / delta)

| | |
|---|---|
| **Idea** | Discovery → scripts → test migrate → delta/CDC → cutover window → validate. |
| **Apply when** | T2 = `system_cutover` or `zero_downtime_cdc` **and** human/Clarify confirms. |
| **Do not apply** | Default on gov Excel CRM. |
| **Lands in** | Migration chapter + timeline. |

### D08 — Combined timeline (single view)

| | |
|---|---|
| **Idea** | One Gantt-style or phase×week table that **combines** build, pre-go-live tests, migration, training, go-live, warranty start — with TOR gates marked and buffers visible. |
| **Apply when** | Required as information, but it may absorb D02/D03 into one table. Do not add a second “combined timeline” if the working schedule already combines all tracks and gates. |
| **Lands in** | `delivery_plan` — closing artefact of the section. |
| **Requirement** | Every TOR-dated deliverable appears on this view on or before its gate. |

### D09 — Migration / go-live risk matrix

| | |
|---|---|
| **Idea** | Risk · impact · mitigation for cutover and readiness. |
| **Apply when** | Migration or complex go-live. |
| **Lands in** | `delivery_plan` or migration subsection (once). |

### D10 — Training & handover on the timeline

| | |
|---|---|
| **Idea** | Place TTT / manuals on the calendar so they complete before or at final gate per TOR. |
| **Apply when** | T4 / TOR training clauses. |
| **Lands in** | `delivery_plan` + training table. |

---

## Pull matrix

| Practice | EECO-like gov (fixed gates + Excel migrate) | Loyalty zero-downtime | Greenfield no migrate |
|---|---|---|---|
| D01 Milestones flow | **Yes** | Yes | Yes |
| D02 TOR gates | **Yes** | If TOR gates | If TOR gates |
| D03 Detail + buffer | **Yes** | Yes | Yes |
| D04 Pre-go-live | **Yes** (`tor_uat_scan`) | Full suite | As TOR |
| D05 Checklist | **Yes** | Yes | Yes |
| D06 Batch migration | **Yes** | If also files | No |
| D07 CDC cutover | **No** | **Yes** if scoped | No |
| D08 Combined timeline | **Yes** | Yes | Yes |
| D09 Risks | **Yes** | Yes | Light |
| D10 Training | **Yes** | Yes | If TOR |

---

## Where it lands vs migration capability chapter

| Content | Owner section |
|---|---|
| TOR payment/acceptance **dates** (for alignment), week plan, buffers, pre-go-live flow, combined timeline — **without** Pay % in customer prose | `delivery_plan` |
| How Excel/legacy rows become clean CRM (steps, dedupe rules, staging) | `capability_module` migration (e.g. EECO §5.7) |
| When migration prep vs clean DB land on calendar | **Both** — methodology in §5.7; **dates** on combined timeline in delivery |
| Warranty SLAs after go-live | `operations_and_support` — not a substitute for timeline |

---

## Writer procedure (before Write — dossier/outline gate)

1. Dossier: T1–T4; paste **verbatim TOR delivery dates** (payment % only in dossier if useful for writers — **not** for customer tables); **Timeline pull** (D-IDs); migration code.
2. Outline: `delivery_plan` reads this file + TOR **delivery** clauses; migration capability reads D06/D07 as relevant.
3. Draft the **integrated calendar first**. Add a short milestone table or dependency flow only if it answers a different reader question. Place migration detail in its capability chapter and only its timing in the calendar.
4. Cross-check: every TOR-dated **deliverable** ≤ gate; buffers ≥ non-zero before hard dates; migration clean-DB timing matches TOR; **no payment % / “what buyer receives” TOR paraphrase** in customer prose; no duplicate schedule views carrying the same information.

**Customer prose rule:** Translate selected practices into Rocket’s delivery commitments. Do not expose D-IDs, pull matrices, writer checks, or internal schedule vocabulary in compiled documents.

---

## Final review — timeline alignment (mandatory criterion)

At **Principles review** and before **Review 3**, verify:

| Check | Pass condition |
|---|---|
| TOR coverage | Every TOR-dated **delivery** obligation appears in D02 and D08 |
| No overrun | No planned completion after its TOR delivery date |
| Buffer | Each hard date has explicit buffer in D03/D08 |
| Finer detail | Working schedule more granular than TOR packages |
| Migration sync | If T2 ≠ `none`, methodology and timeline dates agree |
| Hosting sync | Go-live on buyer infra only after required install steps |
| Ops handoff | Warranty start = TOR trigger; ops section does not invent a different start |
| **Proposal voice** | No Pay % column; no “what the client asked for” restatement; no writer meta (“this section owns…”) |
| **Commercial boundary** | Payment percentages / commercial payment terms not in technical proposal unless pack explicitly requires |
| **No schedule theatre** | Each table or diagram answers a distinct question; redundant phase/schedule views are combined or removed |

Fail → fix timeline before treating the proposal as sendable.

---

## Worked example — EECO

| Dimension | Value |
|---|---|
| T1 | `tor_fixed_gates`: plan ≤15d; BRD/design ≤45d; Phase1 package ≤60d; Phase2 ≤180d; Phase3 ≤210d (**payment % dossier-only**) |
| T2 | `batch_file` (Excel) |
| T3 | `tor_uat_scan` |
| T4 | `ttt_tor`; `no_pilot` unless Clarify adds pilot |

| Pull | Shape |
|---|---|
| D01–D05, D08–D10 | Section 6 expanded |
| D06 | Detail in §5.7; dates on combined timeline (migration prep → Phase 2; clean DB → Phase 3) |
| **Out** | D07 CDC, Caltex performance/pilot-at-scale |

Illustrative buffer pattern (writers refine; must still hit TOR):

| Band | Working intent | TOR delivery date |
|---|---|---|
| D1–15 | Detailed plan | Plan lodge ≤15 |
| D16–40 | BRD/workflows; design drafts | — |
| D41–45 | Design package freeze | BRD+design ≤45 |
| D46–55 | Risk note; buffer | — |
| D56–60 | Phase 1 package | ≤60 |
| D61–150 | Build + configure + custom | — |
| D120–165 | Migration prep (staging/map/cleanse dry-runs) | — |
| D151–170 | UAT + security scan (target finish ~D170) | — |
| D171–180 | Buffer + Phase 2 lodge | ≤180 |
| D181–200 | Clean DB load; install on buyer cloud; training | — |
| D201–210 | Buffer + go-live + Phase 3 lodge | ≤210 |

---

## Provenance

Caltex Part VIII — Pre-Go-Live, Migration Process & Timeline (confidential). Internal Resource only.
