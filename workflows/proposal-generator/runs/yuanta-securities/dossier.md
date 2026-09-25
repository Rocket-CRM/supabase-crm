# Yuanta Securities — CRM / Loyalty / CS Platform Dossier

---

## Client Background

Yuanta Securities is a retail stock brokerage operating in Thailand, part of the broader Yuanta Financial Group (Taiwan-headquartered). The Thailand entity operates as an online retail securities trading business, serving retail investors who trade equities and related instruments through the Yuanta mobile application. The client already has a functioning mobile app with its own loyalty flow, a contact centre running on Cisco telephony hardware, and a current marketing automation stack built on HubSpot Marketing Hub.

The engagement is a greenfield deployment of a unified CRM, loyalty, and customer service platform to sit alongside — and partially replace — existing tooling. The client's member base is in the range that warrants a mid-market platform configuration; exact member count is not material to the proposal scope.

**Note on source artifact conflict:** The uploaded requirements document (yuanta-test-requirements.md) describes a Taiwan-domiciled programme with Traditional Chinese and English language requirements, PIPA compliance, and a Q4 2026 go-live. The project brief payload specifies Thailand as the sole market, PDPA as the compliance regime, and a 2Q 2026 go-live target. The gap Q&A surfaced this conflict (Q8) and the answer was deferred to solution-design. For the purposes of this dossier, the project brief payload is treated as authoritative: **Thailand domicile, PDPA compliance, Thai and English languages, 2Q 2026 go-live target.** Any content from the requirements document that contradicts these parameters is noted but not adopted.

---

## Business Problem & Goals

### Presenting Need

Yuanta Thailand currently operates three disconnected capability stacks:

1. A proprietary loyalty flow embedded in the Yuanta mobile app that handles member-facing presentation but has no independent points calculation engine, reward catalogue, or fulfilment infrastructure.
2. A contact centre built on Cisco hardware with a cloud-to-hardware routing layer that the client has identified as unreliable.
3. HubSpot Marketing Hub for outbound marketing, which the client acknowledges overlaps with what a replacement platform could provide. The client's stated concern with HubSpot is insufficient connectivity to local Thai communication channels (LINE OA, local SMS providers) and limited customer segmentation depth.

### Underlying Goals

- **Loyalty:** Establish a points-and-tiers programme tied to trading activity — primarily trading commissions — that rewards retail traders for sustained engagement. The programme should be calculable on the back end (Rocket handles points arithmetic) while the member-facing redemption experience is surfaced through the existing Yuanta mobile app via a hosted web view. Reward sourcing and fulfilment operations are to be handled by the platform, working through Buzzebees as the reward supply partner.
- **Customer Engagement Campaigns:** Run structured campaigns — trading-target missions, top-trader campaigns, referral programmes, and periodic engagement mechanics (spin wheel, lucky draw, check-in) — contextualised to securities trading behaviour rather than retail spend.
- **Marketing Automation:** Replace or augment HubSpot with a lifecycle workflow engine that connects natively to Thai communication channels, supports low-cost SMS, and enables fine-grained customer segmentation. The client is open to full replacement if the alternative is demonstrably better for their channel mix.
- **AI-Driven Personalisation:** Apply AI decisioning to marketing interactions so that each customer receives contextually appropriate communications without manual campaign configuration for every segment.
- **Customer Service Consolidation:** Consolidate inbound customer service across digital channels (LINE OA, Facebook Messenger, Instagram DM, web chat, email, in-app chat) into a single agent workspace with a unified inbox, routing, and automation.
- **Voice / Contact Centre Modernisation:** Address the unreliable cloud-to-hardware routing in the current Cisco-based contact centre. The client is open to either a full cloud voice replacement or a hybrid model where the Cisco hardware is retained and calls are routed upstream to a cloud IVR and AI layer. A recommended architecture is required.
- **AI Customer Service Agent:** Introduce an AI agent layer that can handle customer queries autonomously or assist human agents in real time, drawing from a structured knowledge base seeded with Yuanta's product and service content.

### Success Criteria

No quantified KPIs were stated in the brief or source artifacts. The following are the closest proxies available:

- Loyalty programme live and processing trading-commission-based point accruals at go-live (2Q 2026).
- Reward redemption functional end-to-end through the Yuanta mobile app web view, with Buzzebees fulfilment operational.
- All confirmed digital CS channels (LINE OA, Facebook Messenger, Instagram DM, web chat, email, in-app chat) consolidated into a single agent inbox at go-live.
- Voice routing reliability issue resolved — either by migrating to cloud voice or by stabilising the upstream routing layer.
- Marketing automation workflows operational with Thai-channel connectivity (LINE, local SMS) and HubSpot either replaced or decommissioned in parallel.

---

## Systems Landscape

| System | Role | Integration Direction | Notes |
|---|---|---|---|
| Yuanta Mobile App | Primary member-facing application; hosts the loyalty UI entry point via web view; source of member identity | Source (member ID / session token passed to Rocket web view) | Yuanta-owned. Web view handoff mechanism (JWT, one-time token, or plain member ID) to be confirmed in solution-design. |
| Yuanta Back-Office / Trading System | Core transactional system of record for trades, commissions, and account data | Source → Rocket (transaction data for point calculation) | REST integration already specced per requirements doc. Field-level schema (raw commission, net settlement, or pre-calculated points), frequency (real-time per trade vs. end-of-day batch), and auth model to be confirmed in solution-design. |
| Buzzebees | Reward supply and point-conversion partner | Sink ← Rocket (redemption requests, point conversion); Source → Rocket (reward inventory / catalogue) | Direct voucher issuance by Rocket is not permitted under current rules; Buzzebees is the mandated reward sourcing route. API contract existence and account ownership (Yuanta or Rocket) to be confirmed in solution-design. |
| HubSpot Marketing Hub | Current marketing automation and email platform | To be replaced or decommissioned; no ongoing integration anticipated | Client will replace if the new platform is demonstrably superior for Thai channel connectivity and segmentation. Transition plan to be scoped. |
| Cisco Hardware (telephony) | Physical contact centre telephony infrastructure | Integration direction depends on chosen voice architecture (see Open Questions) | Current cloud-to-hardware routing is unreliable. Cisco hardware model and SIP trunk configuration not yet provided. |
| Current CS Platform (chat) | Existing omnichannel chat solution (vendor not named) | To be replaced | Handles email, LINE, Facebook, Instagram, in-app chat currently. Being replaced by the new CS module. |
| LINE OA | Customer communication channel — messaging | Sink ← Rocket (outbound marketing and CS messages); Source → Rocket (inbound CS messages) | Confirmed in scope for both CS and marketing automation. |
| Facebook Messenger | Customer communication channel — messaging | Sink ← Rocket; Source → Rocket | Confirmed in scope for CS at go-live per gap Q&A Q6. |
| Instagram DM | Customer communication channel — messaging | Sink ← Rocket; Source → Rocket | Confirmed in scope for CS at go-live per gap Q&A Q6. |
| Web Chat | Customer communication channel — browser-based | Sink ← Rocket; Source → Rocket | In scope for CS. |
| In-App Chat | Customer communication channel — within Yuanta mobile app | Sink ← Rocket; Source → Rocket | In scope for CS. |
| Email | Customer communication channel | Sink ← Rocket (outbound marketing and CS); Source → Rocket (inbound CS) | In scope for both CS and marketing automation. |
| SMS (local Thai providers) | Outbound marketing communication channel | Sink ← Rocket | Low-cost local SMS is a stated priority for marketing automation. Specific SMS gateway provider not named. |

---

## Requirements

### Functional

**Loyalty — Core Programme**

- Calculate loyalty points on the back end based on trading activity data received from Yuanta's trading system; Rocket is the system of record for point balances.
- Support a three-tier structure (Silver / Gold / Platinum) with threshold-based qualification; specific threshold values and qualifying metric (commission amount, trade count, portfolio value, or combination) to be confirmed in solution-design.
- Evaluate tier upgrades and downgrades on a rolling 12-month window; downgrade rules and grace-period configuration to be confirmed.
- Define and enforce point expiry rules; expiry model (fixed calendar, rolling from earn date, or none) to be confirmed in solution-design.
- Support multiple point currencies to accommodate trading commission conversion and Buzzebees point-conversion requirements.
- Maintain tier progress visibility for members.
- Support custom member profile fields to capture trading-relevant attributes.
- Collect and record PDPA consent at member registration and at consent-change events.
- Support stored-value card constructs if required for reward wallet mechanics.
- Provide an admin panel for programme configuration, member management, and operational oversight.

**Loyalty — Reward Redemption**

- Surface a Rocket-hosted web view that opens from within the Yuanta mobile app; the web view receives a customer identifier passed from the app and authenticates the session.
- Allow members to browse and redeem rewards within the web view.
- Handle reward fulfilment operations end-to-end, including sourcing through Buzzebees.
- Support reward groups and reward catalogue management.
- Support promo code management for reward-linked promotions.
- No direct voucher issuance by Rocket; all reward supply must route through Buzzebees.

**Loyalty — Earning Integration**

- Ingest transactional data from Yuanta's trading back-office via API (REST); the data contract (fields, frequency, auth) to be confirmed in solution-design.
- Map trading commission data (and potentially other trading activity signals) to point accrual rules.
- Support store/channel classification to distinguish earning contexts if multiple trading activity types are integrated.
- Support additional earning triggers beyond commissions (e.g., account funding events, app engagement actions) as the programme evolves.

**Loyalty — Campaigns and Engagement**

- Trading-target missions: members earn bonus points or rewards for reaching defined trading volume or commission thresholds within a campaign window.
- Top-trader campaigns: leaderboard or threshold-based recognition for highest-activity traders within a period, contextualised to Yuanta's trading metrics.
- Referral programme: members refer new account holders; both referrer and referee receive programme benefits upon qualifying activity.
- Check-in mechanics: periodic engagement actions that award points or entries.
- Spin-wheel mechanics: randomised reward allocation tied to campaign participation.
- Mass lucky draw: bulk entry and draw execution for periodic prize campaigns.
- Forms: data-capture forms for campaign entry, profile enrichment, or survey purposes.
- Tags and personas: member segmentation labels to target campaigns at defined cohorts.

**Marketing Automation**

- Rules-based lifecycle workflow engine: trigger communications and actions based on member events (trade executed, tier change, point balance milestone, inactivity threshold, etc.).
- Segment-based audience targeting with fine-grained filter criteria drawn from trading activity, tier, point balance, and behavioural data.
- Native connectivity to Thai communication channels: LINE OA, local Thai SMS providers, email.
- Support for low-cost SMS as a primary outbound channel alongside email.
- Action macros: reusable action sequences that can be embedded in multiple workflows.
- Universal action system: standardised action execution layer shared across workflow triggers.
- AI decisioning layer: automated, personalised next-best-action or next-best-message selection for each member interaction without requiring manual segment-by-segment campaign configuration.
- Admin panel and display configuration for marketing operations team.
- Translation system to support Thai and English content variants within the same workflow.

**Customer Service — Omnichannel Chat**

- Unified inbox aggregating inbound messages from: LINE OA, Facebook Messenger, Instagram DM, web chat, in-app chat, and email.
- Unified customer identity: link inbound contacts across channels to a single member profile.
- Agent workspace: interface for CS agents to handle conversations, view member context, and take actions.
- Routing and assignment: rule-based routing of conversations to queues or individual agents based on channel, topic, or member attributes.
- Rules-based automation: auto-responses, SLA timers, escalation triggers.
- Chatbot flows: scripted bot handling for common query types before or instead of agent handoff.
- Rules and triggers: event-driven automation within the CS workflow.
- Actions and integrations: ability to trigger external actions (e.g., look up account status, initiate a transaction query) from within the agent workspace.
- Analytics and logs: conversation volume, resolution time, channel breakdown, agent performance reporting; full conversation logs for audit and QA.

**Customer Service — Voice / Phone Support**

- Phone number management: allocation and configuration of inbound numbers.
- Voice console: agent interface for handling inbound and outbound calls.
- IVR flows: configurable interactive voice response trees for call routing and self-service.
- Rules-based automation and routing: skill-based or queue-based call routing.
- Connectivity: integration with existing Cisco telephony hardware or replacement cloud voice stack (architecture to be confirmed).
- Agent workspace: unified view for agents handling voice alongside digital channels.
- Call logs: full call records for audit, QA, and compliance.
- Analytics: call volume, wait time, handle time, abandonment rate reporting.

**Customer Service — Ticketing and Case Management**

- Ticket creation from any inbound channel (chat, voice, email).
- Routing and assignment of tickets to agents or teams.
- Case lifecycle management: open, in-progress, pending, resolved, closed states.
- Analytics and logs: ticket volume, resolution time, SLA adherence reporting; full ticket audit trail.

**Customer Service — AI Agent**

- AI customer service agent capable of handling member queries autonomously across digital channels.
- Brand and tone configuration: AI agent behaviour aligned to Yuanta's brand voice and regulatory communication standards.
- Agent operating procedures: structured rules governing when the AI escalates to a human agent.
- Watchtower / oversight: monitoring layer for AI agent behaviour, flagging anomalous or non-compliant responses.
- Knowledge base: structured repository of Yuanta product information, FAQs, regulatory disclosures, and agent scripts; seeded from existing Yuanta content (format and volume to be confirmed in solution-design).
- Live assist: AI-assisted suggestions surfaced to human agents during live conversations.
- Actions and integrations: AI agent ability to execute defined actions (account lookup, balance query, etc.) via integration with Yuanta back-office.
- CSAT and feedback: post-interaction satisfaction collection and reporting.
- Analytics and logs: AI agent resolution rate, escalation rate, topic distribution, and full interaction logs.

---

### Non-functional

- **Compliance:** Thailand PDPA. Consent capture, consent audit trail, data subject rights handling (access, deletion, portability) must be supported. All personal data processed must be within PDPA-compliant infrastructure.
- **Hosting:** Cloud-hosted (Rocket-managed). No on-premise deployment.
- **Languages:** Thai and English. All member-facing surfaces (web view, chatbot, IVR, email/SMS templates) must support both languages. Admin panel in English is acceptable; Thai admin panel support to be confirmed.
- **Go-live target:** 2Q 2026. This is a hard target stated in the brief; the requirements document's Q4 2026 date is superseded.
- **Availability:** No explicit SLA stated by the client. Given the financial services context and trading-hours dependency, high availability during Thai market hours (SET: 10:00–12:30 and 14:00–16:30 ICT, Monday–Friday) is operationally critical. Specific uptime SLA to be proposed.
- **Performance:** No explicit latency targets stated. Point calculation triggered by trading events should complete within a timeframe that does not create member-visible delays in balance updates; specific targets to be agreed in solution-design.
- **Capacity:** Member base in the range that does not require hyperscale architecture at launch; platform must be configurable to scale as the programme grows.
- **Accessibility:** No specific accessibility standard stated.
- **Security:** Financial services context implies standard requirements for data encryption in transit and at rest, role-based access control in the admin panel, and audit logging of administrative actions. No specific security certification requirement stated.

---

## Integration Constraints

### Yuanta Mobile App → Rocket (Web View Handoff)

- **Direction:** Yuanta Mobile App → Rocket-hosted web view (inbound session initiation)
- **Mechanism:** To be confirmed in solution-design. The brief states the app "sends a customer ID" when opening the web view. The gap Q&A (Q1) confirmed this is in scope for phase 1 but deferred the token type (signed JWT, one-time token, or plain member ID in query parameter) and IdP ownership to solution-design.
- **Owner:** Yuanta owns the mobile app; Rocket owns the web view. IdP ownership undecided.
- **Constraints:** The authentication mechanism must be secure enough for a financial services context. Plain member ID in a query parameter without signing is unlikely to be acceptable; this should be flagged in solution-design.

### Yuanta Trading Back-Office → Rocket (Transaction Data for Point Calculation)

- **Direction:** Yuanta Trading System → Rocket (source to sink)
- **Mechanism:** REST API. The requirements document states the integration is "already specced" via REST, but the field-level data contract has not been shared.
- **Owner:** Yuanta owns the trading back-office. Integration contract ownership to be confirmed.
- **Constraints:**
  - Data fields: whether Rocket receives raw commission amounts, net settlement values, or pre-calculated point figures is unconfirmed (gap Q&A Q3, deferred).
  - Frequency: real-time per-trade push, end-of-day batch, or both — unconfirmed (gap Q&A Q3, deferred).
  - Auth model: not specified.
  - The proposal should describe the integration pattern for both real-time and batch scenarios and note that the data contract will be finalised in solution-design.

### Rocket → Buzzebees (Reward Sourcing and Point Conversion)

- **Direction:** Rocket → Buzzebees (redemption requests, point conversion instructions); Buzzebees → Rocket (reward catalogue / inventory data)
- **Mechanism:** Undecided. No API specification has been shared.
- **Owner:** Account ownership (whether Yuanta holds the Buzzebees contract or Rocket does) is unconfirmed (gap Q&A Q2, deferred).
- **Constraints:**
  - Direct voucher issuance by Rocket is not permitted; all reward supply must route through Buzzebees.
  - Point conversion rules (Rocket points to Buzzebees currency) are unspecified.
  - The proposal must describe the Buzzebees integration as a required workstream and flag that the commercial and technical details will be resolved in solution-design.

### Cisco Hardware (Telephony)

- **Direction:** Bidirectional (inbound call routing from PSTN through Cisco hardware; potential upstream routing to Rocket cloud IVR/AI)
- **Mechanism:** SIP trunk (assumed, based on standard Cisco contact centre architecture). Specific hardware model and SIP configuration not provided.
- **Owner:** Yuanta owns the Cisco hardware.
- **Constraints:**
  - The client has identified that cloud-to-hardware routing in the current setup is unreliable.
  - Two architectures are possible: (a) full replacement of the Cisco stack with Rocket cloud voice, or (b) retain Cisco hardware and route calls upstream to Rocket's IVR and AI layer via SIP.
  - The gap Q&A (Q5) confirmed both options are in scope for phase 1 consideration but deferred the architecture decision to solution-design.
  - The proposal should present a recommended architecture with a rationale, and note the alternative.

### LINE OA

- **Direction:** Bidirectional (Rocket sends outbound messages; LINE OA delivers inbound messages to Rocket)
- **Mechanism:** LINE Messaging API (standard)
- **Owner:** Yuanta owns the LINE OA account.
- **Constraints:** LINE OA account must be connected to Rocket via the LINE Messaging API channel connector. Verified LINE OA status assumed given financial services context.

### Facebook Messenger

- **Direction:** Bidirectional
- **Mechanism:** Facebook Graph API / Messenger Platform (standard)
- **Owner:** Yuanta owns the Facebook Page.
- **Constraints:** Confirmed in scope for CS at go-live (gap Q&A Q6).

### Instagram DM

- **Direction:** Bidirectional
- **Mechanism:** Instagram Messaging API via Meta Business Suite (standard)
- **Owner:** Yuanta owns the Instagram account.
- **Constraints:** Confirmed in scope for CS at go-live (gap Q&A Q6). Instagram DM API requires the account to be a Business or Creator account connected to a Facebook Page.

### Email

- **Direction:** Bidirectional (outbound marketing and CS; inbound CS)
- **Mechanism:** SMTP / IMAP or API-based (e.g., SendGrid, Mailgun) for outbound; inbound email parsing for CS ticket creation.
- **Owner:** Yuanta owns the email domain. Outbound sending infrastructure provider not specified.
- **Constraints:** Deliverability configuration (SPF, DKIM, DMARC) for Yuanta's domain required.

### SMS (Thai Local Providers)

- **Direction:** Outbound only (Rocket → member)
- **Mechanism:** API-based SMS gateway. Specific Thai SMS provider not named.
- **Owner:** To be confirmed. Rocket may provide a default SMS gateway or Yuanta may have an existing provider contract.
- **Constraints:** Low-cost local Thai SMS is a stated priority. Provider selection and cost structure to be confirmed in solution-design.

### HubSpot Marketing Hub

- **Direction:** No ongoing integration anticipated post-migration. Data export from HubSpot (contact lists, segment definitions, historical campaign data) may be required for transition.
- **Mechanism:** HubSpot API or CSV export for data migration.
- **Owner:** Yuanta owns the HubSpot account.
- **Constraints:** Transition plan (parallel run vs. hard cutover) to be scoped. Historical campaign data retention requirements not stated.

---

## Operations & Support Context

### Support Hours and Languages

No explicit support SLA or hours have been stated by the client. Given the Thailand market and financial services context, the following are operationally implied:

- Business hours support in Thai and English during Thai business hours (09:00–18:00 ICT, Monday–Friday) as a minimum.
- Escalation path for platform incidents during SET trading hours (10:00–12:30 and 14:00–16:30 ICT, Monday–Friday) should be defined, as loyalty point calculation failures during trading hours would be directly visible to members.
- On-call requirements for after-hours incidents not stated; to be agreed in the SLA schedule.

### Migration Scope

The gap Q&A (Q7) confirmed that migration of existing loyalty member data, point balances, and tier status from the current Yuanta mobile app loyalty flow is in scope for phase 1. The specific volume, data format, and cleanliness of the existing member data are unknown and will be assessed in solution-design. The migration workstream should be treated as a confirmed but unscoped item in the proposal.

Key migration considerations:

- Member identity records (member IDs, profile data, PDPA consent records).
- Point balances as of migration cutover date.
- Tier status and tier qualification history (if the rolling 12-month window requires historical transaction data to be carried over).
- Voucher or reward inventory already issued but not yet redeemed (if any).

### Go-Live Target

2Q 2026 (April–June 2026). This is a firm target from the project brief. The requirements document's Q4 2026 date is not adopted. The implementation plan must be structured to deliver all phase 1 scope within this window.

### Hosting and Infrastructure

Cloud-hosted, managed by Rocket. No on-premise or hybrid hosting requirement stated. Data residency within Thailand or a PDPA-compliant jurisdiction should be confirmed in solution-design.

### Existing CS Platform Transition

The current omnichannel chat platform (vendor unnamed) is being replaced. Transition scope — whether there is a parallel-run period, historical conversation data to be migrated, or agent retraining required — is not specified and should be addressed in the implementation plan.

---

## Open Questions & Assumptions

**Q1: Web view session handoff mechanism and IdP ownership.**
A: Pending. Confirmed in scope for phase 1; specific token type (signed JWT, one-time token, or plain member ID) and identity provider ownership to be confirmed in solution-design post-kickoff.
*Assumption for proposal: The proposal will describe the integration as a secure token-based handoff and note that the exact mechanism will be finalised in solution-design. A signed, short-lived token (e.g., JWT) is the recommended approach given the financial services context.*

**Q2: Buzzebees commercial and technical relationship.**
A: Pending. Confirmed in scope for phase 1; API contract existence and account ownership (Yuanta or Rocket) to be confirmed in solution-design.
*Assumption for proposal: The proposal will describe Buzzebees as the mandated reward sourcing partner and include the integration as a required workstream, with commercial and technical details deferred.*

**Q3: Transactional data contract (fields, frequency, auth) from Yuanta trading back-office.**
A: Pending. Confirmed in scope for phase 1; data contract to be confirmed in solution-design.
*Assumption for proposal: The proposal will describe the integration as a REST API earning feed and note that the data contract (field schema, push frequency, auth model) will be agreed during solution-design. Both real-time and batch patterns will be described as options.*

**Q4: Tier threshold values and qualifying metric.**
A: Pending. Confirmed in scope for phase 1; specific thresholds and metric definition to be confirmed in solution-design.
*Assumption for proposal: Three tiers (Silver / Gold / Platinum) on a rolling 12-month window. Qualifying metric is trading commission amount (primary candidate) or a composite metric. Thresholds are configurable and will be set by Yuanta during programme configuration.*

**Q5: Voice architecture — full cloud replacement vs. Cisco hardware retention with upstream routing.**
A: Pending. Both options confirmed in scope for phase 1 consideration; architecture decision deferred to solution-design.
*Assumption for proposal: The proposal will present a recommended architecture (cloud voice replacement) with a rationale addressing the stated routing reliability issue, and will describe the hybrid option as an alternative with its constraints.*

**Q6: Digital CS channel scope at go-live.**
A: Confirmed in scope for phase 1: LINE OA, Facebook Messenger, Instagram DM, web chat, in-app chat, and email. All six channels are included in the proposal scope.

**Q7: Loyalty member data migration scope.**
A: Confirmed in scope for phase 1; volume, format, and data quality to be assessed in solution-design.
*Assumption for proposal: A data migration workstream is included in the implementation plan as a confirmed but unscoped item. Effort will be estimated after data assessment.*

**Q8: Market, language, and compliance regime — Thailand/PDPA/Thai+English vs. Taiwan/PIPA/zh-tw+en.**
A: Deferred to solution-design. The project brief payload is treated as authoritative: Thailand, PDPA, Thai and English.
*Assumption for proposal: All compliance references are to Thailand PDPA. Language support is Thai and English. The requirements document's Taiwan/PIPA/zh-tw parameters are not adopted.*

**Q9: Knowledge base content for AI Customer Service Agent.**
A: Pending. Confirmed in scope for phase 1; content sources (FAQ documents, agent scripts, product brochures, regulatory disclosures), format (structured vs. free-form PDF), and volume to be confirmed in solution-design.
*Assumption for proposal: A knowledge base seeding workstream is included in the implementation plan. Yuanta will provide source content; format and ingestion effort to be scoped in solution-design.*

**Q10: Point expiry model and tier downgrade rules.**
A: Pending. Confirmed in scope for phase 1; expiry model (fixed calendar, rolling from earn date, or none) and downgrade grace-period configuration to be confirmed in solution-design.
*Assumption for proposal: Point expiry and tier downgrade rules are configurable parameters. The proposal will describe the configuration options available and note that Yuanta will define the specific rules during programme design.*

**Q11: SMS gateway provider for Thai outbound SMS.**
A: Not addressed in gap Q&A. Provider not named in brief or source artifacts.
*Assumption for proposal: Rocket will propose a default Thai SMS gateway integration. If Yuanta has an existing provider contract, the integration will be adapted accordingly.*

**Q12: HubSpot transition plan (parallel run vs. hard cutover; historical data retention).**
A: Not addressed in gap Q&A. No transition plan specified.
*Assumption for proposal: A HubSpot decommission workstream is included in the implementation plan. The transition approach (parallel run duration, data export scope) will be agreed during solution-design.*

**Q13: Data residency requirement for PDPA compliance.**
A: Not explicitly stated. Cloud hosting confirmed; jurisdiction not specified.
*Assumption for proposal: Data will be hosted in a PDPA-compliant cloud region. Specific data residency requirements (Thailand-only vs. ASEAN region) to be confirmed with Yuanta's legal/compliance team during solution-design.*

**Q14: Admin panel language requirement.**
A: Not stated. Member-facing Thai and English confirmed; admin panel language not specified.
*Assumption for proposal: Admin panel is provided in English. Thai admin panel support to be confirmed if required.*

---

*Dossier prepared from: project brief payload (authoritative), yuanta-test-requirements.md (supplementary, superseded on market/language/compliance/go-live parameters), and gap Q&A responses (all deferred to solution-design). Last updated: 2026-05-15.*