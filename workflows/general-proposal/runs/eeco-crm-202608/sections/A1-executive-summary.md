# 1. Executive summary

Rocket Innovation Co., Ltd. will deliver สกพอ.’s **CRM & Database Management System** so promotion officers can conduct an **Investment Journey** in one place: create and match investors, record fieldwork, move cases through **pre-incentive stages**, escalate SLA breaches, protect LOI/NDA/financials, and view **EEC OSS** status without side spreadsheets.

The delivery model is **hybrid**: a configurable CRM product core (accounts, activities, tasks, tickets, pipelines, roles, audit) plus **custom development** for สกพอ.-specific journey rules, bureau escalation, SSO EECO, EEC OSS adapters, watermarking, and Excel migration.

## From today to the proposed CRM

{{diagram:executive-overview}}

### Investment Journey

**Current state.** Contact history and case notes sit in bureau Excel files and with individual officers. When staff rotate, the trail of who met whom and what was promised is hard to reconstruct. Pre-incentive progress is not a shared stage model.

**Future state.** Officers open one **investment case**, record activities and documents against it, and move configurable **pre-incentive** stages when exit evidence is complete. The same case carries sensitive files and OSS status.

**Impact.** Promotion history survives staff change; the next action on each case is visible; handoff toward **EEC OSS** does not require rebuilding the story from side spreadsheets.

### Executive visibility

**Current state.** Executives cannot reliably see which cases are delayed, which service levels are at risk, or which bureau owns the blocker until a weekly meeting.

**Future state.** A **heat map**, stage and ticket **SLA**, and escalation paths surface aging work. Dashboards filter by พ.ศ. and fiscal year from the same live cases.

**Impact.** Leaders intervene before breach; bureau ownership is explicit; board packs come from the CRM rather than offline status trackers.

### Integration and master data

**Current state.** The same company appears under near-duplicate names across spreadsheets. Officers re-key one-stop service status. There is no single named-user directory designed for ≥100 expandable accounts with strong remote access.

**Future state.** **SSO EECO** authenticates named users; **EEC OSS** status is pulled onto the case; migration produces a structured clean database with 1:N contacts.

**Impact.** One identity path for officers; no parallel password store; handover data is structured and deduplicated for ongoing use.

**Application stack:** Next.js · Node.js · PostgreSQL. **Production hosting** is arranged by สกพอ. with a cloud provider (for example GDCC). Rocket Innovation Co., Ltd. prepares the **vendor-agnostic minimum infrastructure specification**, then installs and configures the system on the hosts สกพอ. provides. Production edge protection and monitoring remain with สกพอ. (or its cloud MSP); Rocket emits application and audit logs for Authority use. **Development, test, and proof-of-concept** environments are Rocket-managed.

Officers receive form-based, mobile-friendly tools for at least **100 named users**. Rocket completes delivery within **210 days**, with major packages at days **60**, **180**, and **210** (Section 6), plus perpetual license, source code, train-the-trainer courses, and a one-year warranty with 24×7 intake (Section 7).

The proposed system keeps investor identity, promotion activity, stage progress, documents, and management reporting on the same case record. Rocket also proposes five practical enhancements beyond the minimum scope: guided duplicate merging, offline-tolerant field capture, configurable bureau escalation, reusable journey templates, and scheduled executive digests.
