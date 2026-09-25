# Standard operations & support practices (general proposals)

Durable **Resource** for custom / government / non-productized bids. Distilled from Rocket’s Caltex **Part IX — Operations & Support Framework** and generalized. Writers pull only practices justified by dossier context — never paste a loyalty contact-centre SaaS model into a government install bid.

**Hard rule:** Prefer a **separate customer-facing section** for operations & support when the TOR scores warranty, maintenance, incident SLAs, or post-go-live support (typical in Thai government packs). Embed a short pointer only when the bid is thin and warranty is a single clause inside delivery.

Companion: `REFERENCE.md`, `SCAFFOLDS.md`, `standard-delivery-timeline-migration.md` (delivery calendar is **not** this file).

---

## Two responsibilities (keep conceptually distinct)

| Plane | Who it serves | Typical content |
|---|---|---|
| **Support operations** | End users of the *product* (consumers, officers, agents) and/or the **client’s business users** raising how-to / access / data issues | Intake channels, tiers/layers, task authority, CSAT — **only if in scope** |
| **Technical operations** | Keeping the *system* healthy: incidents, severity SLAs, change control, releases, on-call, knowledge base | P1–P4 (or TOR severity), escalation to engineering, CAB |

Do **not** merge “customer chatbot for members” with “warranty fix for CRM core functions” into one undifferentiated “support” blob. The distinction must be clear, but it does not require two headings, two workflows, or two tables when one concise customer journey can explain both.

A third plane appears **during the project only**:

| Plane | Role |
|---|---|
| **Project governance** (delivery-time) | Steering / PMO / working groups, status cadence, risk & change *during build* — may live in delivery methodology **or** open the ops section; do not duplicate at length |

---

## Context dimensions (dossier before Write)

### O1 — Support surface

| Code | Meaning | Typical |
|---|---|---|
| `officer_warranty_only` | Named internal users; warranty intake for defects (gov CRM) | EECO |
| `client_admin_support` | Buyer admins + campaign/config help (B2B platform) | Some SaaS |
| `end_customer_cs` | Consumer CS (chat/voice/LINE) for members | Caltex loyalty |
| `hybrid_cs_and_warranty` | Both consumer CS and technical warranty | Full loyalty ops |

### O2 — Who operates production tech ops

| Code | Meaning |
|---|---|
| `bidder_warranty_tech` | Rocket runs warranty incident/response for the app; buyer runs hosts |
| `bidder_full_ops` | Rocket operates platform 24/7 (SaaS) |
| `buyer_ops_bidder_assist` | Buyer IT/SOC owns infra; Rocket assists on application defects only |
| `shared_raci` | Written RACI per control |

### O3 — Contact / ticket tooling

| Code | Use when |
|---|---|
| `tor_channels_only` | TOR names phone / email / app — do not invent Freshworks |
| `named_cc_suite` | Bid explicitly includes contact-centre product |
| `buyer_itil` | Buyer already has ServiceNow/etc.; Rocket integrates or follows their process |

### O4 — Continuous improvement / marketing ops

| Code | Gate |
|---|---|
| `include_ci` | Monthly/quarterly improvement reviews in warranty or AMS |
| `loyalty_campaign_ops` | Campaign setup cycles, marketing reports — **loyalty only** |
| `omit` | Not in TOR |

---

## Practice catalog

### S01 — Project governance (delivery-time)

| | |
|---|---|
| **Idea** | Steering (strategic), PMO (milestones), working groups (daily execution); clear escalation. |
| **Apply when** | Scored methodology / project management. |
| **Do not apply** | Inventing Agile/Scrum ceremony the TOR forbids; inventing FTE counts not in answers/CVs. |
| **Lands in** | `delivery_plan` open or `operations_and_support` intro; keep short if Section 3 already covers methodology. |
| **Shape** | Gov: formal committee language. SaaS: Agile/sprint OK if agreed. |

### S02 — Support operations — end-customer / multi-layer CS

| | |
|---|---|
| **Idea** | Layered CS (bot → L1 → L2), hours, headcount, task×authority×SLA matrix. |
| **Apply when** | O1 = `end_customer_cs` or `hybrid_cs_and_warranty`. |
| **Do not apply** | **Government internal CRM** with no public members (EECO). |
| **Lands in** | `operations_and_support` — clearly labeled **Support operations**. |
| **Source note** | Caltex Part 1 Customer Service — loyalty-gated. |

### S03 — Support operations — client / officer / admin helpdesk

| | |
|---|---|
| **Idea** | How buyer staff get help: how-to, access, data questions — distinct from P1 outage. |
| **Apply when** | O1 includes officer or client admin support beyond pure defect warranty. |
| **Do not apply** | Inventing 9 FTE CS teams on a thin warranty clause. |
| **Lands in** | `operations_and_support` — **Support operations**. |
| **Shape for EECO** | Optional thin “officer guidance during warranty” via same intake as warranty; no AI bot claim unless agreed. |

### S04 — Technical operations — severity & SLAs

| | |
|---|---|
| **Idea** | Severity table: definition, examples, response time, resolution time; response ≠ resolution. |
| **Apply when** | TOR warranty / maintenance / SLA clauses exist. |
| **Do not apply** | Overwriting TOR numbers with Caltex P1=5min/2h. **TOR wins.** |
| **Lands in** | `operations_and_support` — **Technical operations** (primary). May cross-ref payment/warranty clause in delivery section. |
| **Shape** | Map TOR severity language 1:1 (e.g. EECO critical core ≤4h, non-core ≤24h/48h, acknowledge ≤30 min, 24×7 intake). |

### S05 — Technical operations — escalation path

| | |
|---|---|
| **Idea** | L1 → L2 → L3/engineering → vendor; timeboxes. |
| **Apply when** | S04 applies. |
| **Do not apply** | Claiming 24/7 on-call engineering on buyer hosts unless O2 and commercial model support it. |
| **Lands in** | `operations_and_support`. |
| **Shape** | `buyer_ops_bidder_assist`: Rocket app escalation; infra/host escalates to buyer MSP. |

### S06 — Incident management SOP

| | |
|---|---|
| **Idea** | DETECT → TRIAGE → NOTIFY → RESOLVE → VERIFY → CLOSE; before/during/after phases. |
| **Apply when** | Warranty or scored ops. |
| **Lands in** | `operations_and_support` (+ mermaid). |
| **Shape** | Keep process; drop Caltex marketing/POS examples. |

### S07 — Change request management

| | |
|---|---|
| **Idea** | Request → scope/estimate → impact (L/M/H) → authority (PM vs CAB). |
| **Apply when** | Post-go-live changes or warranty-period enhancements process. |
| **Do not apply** | As a substitute for TOR variation-order / contract change clauses — align language with contract. |
| **Lands in** | `operations_and_support` or delivery risk subsection. |

### S08 — Communications matrix

| | |
|---|---|
| **Idea** | Kick-off, status, incident comms — deliverable, channel, frequency, owner, audience. |
| **Apply when** | Scored PM or ops. |
| **Lands in** | `operations_and_support` or `delivery_plan`. |
| **Shape** | Gov: formal email + meeting; do not assume Slack unless buyer uses it. |

### S09 — Case / ticket workflow

| | |
|---|---|
| **Idea** | Create → triage → resolve → verify → close; knowledge-base update. |
| **Apply when** | S03 or S04. |
| **Lands in** | `operations_and_support`. |

### S10 — Contact-centre platform

| | |
|---|---|
| **Idea** | Named CC suite (omnichannel, voice, AI). |
| **Apply when** | O3 = `named_cc_suite`. |
| **Do not apply** | Default Freshworks on government CRM warranty. |
| **Lands in** | `operations_and_support` only if in scope. |

### S11 — Risk & crisis management (ops)

| | |
|---|---|
| **Idea** | Categories (delay, resource, requirements change); crisis before/during/after. |
| **Apply when** | Methodology or ops scored. |
| **Lands in** | Short table in ops or delivery; avoid duplicating Phase-1 risk note. |

### S12 — Continuous improvement cadence

| | |
|---|---|
| **Idea** | Weekly / monthly / quarterly improvement loops. |
| **Apply when** | O4 = `include_ci` or AMS. |
| **Do not apply** | Padding warranty-only bids with unused KPI theatre. |

### S13 — Loyalty campaign / marketing ops

| | |
|---|---|
| **Idea** | Campaign setup week, content approvals, monthly loyalty reports. |
| **Apply when** | O4 = `loyalty_campaign_ops`. |
| **Do not apply** | Government CRM. |

### S14 — Warranty / AMS commercial frame

| | |
|---|---|
| **Idea** | Duration start trigger, what’s in/out (app vs hardware vs external systems), workaround rules. |
| **Apply when** | TOR warranty clause. |
| **Lands in** | `operations_and_support` (detail) + one-line in delivery gates. |
| **Shape** | Copy TOR boundaries (e.g. hardware/external = investigate & report, not app defect). |

---

## Pull matrix (cheat sheet)

| Practice | Gov CRM warranty (`officer_warranty_only`) | Loyalty full ops | SaaS bidder_full_ops |
|---|---|---|---|
| S01 Governance | Thin | Yes | Yes |
| S02 End-customer CS | **No** | **Yes** | If product has CS |
| S03 Officer/admin help | Thin / optional | Yes | Yes |
| S04 Severity/SLA | **Yes — TOR numbers** | Yes | Yes |
| S05 Escalation | **Yes** | Yes | Yes |
| S06 Incident SOP | **Yes** | Yes | Yes |
| S07 Change | Yes (align contract) | Yes | Yes |
| S08 Comms | Yes | Yes | Yes |
| S09 Ticket workflow | Yes | Yes | Yes |
| S10 CC platform | **No** unless TOR | Often | Optional |
| S11 Risk/crisis | Short | Yes | Yes |
| S12 CI | Optional | Yes | Yes |
| S13 Campaign ops | **No** | **Yes** | If loyalty |
| S14 Warranty frame | **Yes** | If contracted | AMS |

---

## Where it lands

| Situation | Customer shape |
|---|---|
When the TOR has warranty + delivery calendar | **Separate** `operations_and_support` section **after** delivery timeline; delivery section keeps **delivery** milestones + training; ops owns SLA/incident/change detail |
| TOR only mentions warranty in one paragraph | Still prefer separate short section so technical ops ≠ training schedule |
| Loyalty RFP with CS + tech support | One ops chapter with **two labeled parts** (Support ops / Technical ops) |
| No post-go-live support in scope | Omit section; dossier notes out |

Section type vocabulary: `operations_and_support` (add to SCAFFOLDS).

---

## Writer procedure (before Write — dossier/outline gate)

1. Dossier: O1–O4 + **Ops pull** (S-IDs in/out).
2. Outline: separate section unless Explicitly thin; `reads` cite this file + TOR warranty clauses.
3. Write: TOR SLA numbers override catalog defaults; attribute infra incidents per hosting model (`standard-technical-practices.md` H2). Combine thin practices into a small number of buyer-facing sections (for example warranty commitments, incident handling, and responsibilities) instead of publishing one subsection per S-ID.
4. Self-check: no Freshworks/AI-bot/campaign-ops on gov CRM; officer guidance and technical incidents are distinguishable; no duplicate full SLA table in delivery **and** ops; no one-line workflow or optional cadence added only because it exists in this catalog.

**Customer prose rule:** Translate selected practices into the buyer’s support journey. Do not expose S-IDs, pull matrices, catalog language, or loyalty/contact-centre comparisons that are out of scope.

---

## Worked example — EECO

| Dimension | Value |
|---|---|
| O1 | `officer_warranty_only` |
| O2 | `buyer_ops_bidder_assist` + `bidder_warranty_tech` for application defects |
| O3 | `tor_channels_only` (24×7 phone / email / app) |
| O4 | `omit` campaign ops; light CI optional |

| Pull | Shape |
|---|---|
| S01 | Short pointer to delivery governance |
| S04, S05, S06, S09, S14 | TOR §14 numbers; incident flow; ticket workflow |
| S07, S08 | Change + status/incident comms during warranty |
| S03 | Thin — same intake for officer how-to during warranty |
| **Out** | S02, S10, S13, Caltex FTE CS org, Freshworks, 99.9% uptime claims unless TOR |

---

## Provenance

Caltex Part IX — Operations & Support Framework (confidential). Internal Resource only — do not cite Caltex in customer docs.
