## 5.1 Create investors, import lists, and keep one clean master

สกพอ. cannot run an Investment Journey if every bureau keeps a private spreadsheet of “the same” company under a slightly different name. Officers therefore create and match organizations and people before opening a case, import roadshow lists through validation, and use a **Customer 360** that remains usable after staff rotation.

## Investor and master-data records

| Object | What it is | Why it matters |
|---|---|---|
| **Organization** | Juristic investor or stakeholder entity (legal name, Tax ID, industry, country) | The company สกพอ. is promoting or coordinating with |
| **Person** | Natural person stored once | Avoids cloning the same contact when they represent several companies |
| **Org–contact link** | Relationship between a person and an organization (role, primary flag) | Supports one person ↔ many organizations without duplicate person rows |
| **Channel source** | Tag for how the lead arrived (LINE OA, Facebook Messenger, email, call center, …) | Keeps provenance on the record, not in a private inbox |
| **Lead score** | Priority signal on a person or organization | Helps teams decide who needs attention next |
| **Master data row** | Reference value (e.g. target industry, country) | Stops free-text drift in reports and filters |
| **Consent record** | PDPA consent event (purpose, evidence, time, withdrawal) | Proves lawful basis before sensitive use of personal data |

Investment **cases**, **activities**, and **pipeline stages** are owned in Sections 5.2–5.3; they link to the organizations and people created here.

## Investor intake and data-quality controls

| Feature | What the officer or admin does | Includes (sub-capabilities) |
|---|---|---|
| Create / match organization | The officer searches before creating so the same juristic investor is not entered twice under a slightly different name. | Search by Tax ID and legal name; fuzzy near-match list with open-existing action; create only after confirm; industry, country, and status fields; inactive flag; field-level change history. |
| Create / match person | The officer stores a natural person once and links them as a contact on one or many organizations, instead of cloning the same person per company. | Name and identifiers agreed in BA; role and primary-contact flag on the org–contact link; merge-candidate warning when a similar person already exists. |
| Channel-tagged intake | The officer (or intake path) records how interest arrived so provenance is on the record, not only in a private inbox. | Channels include LINE OA, Facebook Messenger, email, call center, and others agreed in BRD; channel label and timestamp stored on the interaction or lead. |
| Bulk CSV / Excel import | The officer uploads a roadshow or bureau list, maps columns, and commits only after row-level validation passes. | Column mapping UI; required-field and format checks; error grid by row/field; Tax ID and legal-name duplicate warnings; reject or fix rows before commit so production stays clean. |
| Bulk export | The officer downloads a working set for offline prep when needed, without bypassing access rules. | Export respects current filters; sensitive columns follow RBAC (Section 5.6); audit of export events where policy requires. |
| Customer 360 | The officer opens one assembled view of the investor so identity, links, consent, and priority are visible without opening multiple spreadsheets. | Identity header; linked organizations (1:N); consent status; lead score; summary timeline; navigation into live investment cases (Section 5.3). |
| Master data admin | An administrator maintains reference lists so reports and filters do not drift into free-text variants. | Industry, country, and other BRD lists; add/edit/deactivate; used-by count; only active values offered on create/edit forms. |
| Lead scoring | The officer or rules raise or lower priority so the team knows which investors need attention next. | Manual adjust with reason; optional rule-based hints from BRD; score visible on Customer 360 and work queues. |
| Auto dedupe assist | During create and import, the system flags likely collisions so officers resolve them before polluting the master. | Exact Tax ID match; legal-name similarity; block or warn per policy; path into guided merge (recommended enhancement below). |
| Consent capture | Before sensitive use of personal data, the officer records consent so lawful basis is provable later. | Purpose, evidence/channel, and timestamp; withdrawals append to history rather than erasing prior consent events. |

Configurable CRM product features cover standard create/match, masters, scoring, and dedupe. Channel adapters and สกพอ.-specific consent wording are implemented in the custom layer where the BRD requires it.

### Recommended enhancement (beyond TOR minimum)

**Guided duplicate-merge workspace.** When Tax ID or legal-name collisions appear, officers open a side-by-side review (field-by-field keep/discard) before merge. This reduces the risk of silent data loss during consolidation.

## From intake to a trusted Customer 360

**Create or match.** An officer pastes a Tax ID or legal name. The system searches existing organizations and shows near-matches before creating a new row. The same pattern applies to persons (name + other identifiers agreed in BA). When a person already exists as the representative of Company A, linking them to Company B adds an **org–contact** row — it does not clone the person.

**Channel intake.** For LINE OA, Facebook Messenger, email, or call center, the intake path stores the channel on the interaction or lead record so later reporting can answer “where did this interest come from?” Exact adapter behavior for each channel is confirmed in the BRD; the CRM always retains the channel tag and timestamp.

**Bulk import.** Roadshow or bureau Excel files land in a validation grid: required fields, format checks, and duplicate warnings (Tax ID / name) appear **before** commit. Officers correct or reject invalid rows before production records are created. Ongoing imports use the same validation rules as migration staging, while historical cutover remains a separate controlled process.

**Customer 360.** Opening an organization or person assembles identity, linked companies, consent status, lead score, and a summary timeline. Full activity/task/ticket history for a live promotion effort is completed on the **investment case** (Section 5.3), which links back to these master records.

**Consent.** Before using personal data beyond the agreed purpose, officers record consent (purpose, evidence, time). Withdrawals append to history rather than erasing the audit of what was held when.

{{mockup:M04}}

{{mockup:M03}}

{{mockup:M05}}

{{mockup:M06}}

Reference: TOR 5.5.1, 5.5.2.
