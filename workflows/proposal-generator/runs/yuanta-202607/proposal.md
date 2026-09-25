# Yuanta Securities Thailand — CRM, Loyalty & Customer Service Platform Proposal

**Prepared for:** Yuanta Securities (Thailand)  
**Prepared by:** Rocket  
**Go-live target:** 2Q 2026  
**Languages:** Thai and English (member-facing)  
**Compliance frame:** Thailand PDPA  
**Status:** Draft for Review 2 — open items marked `[GAP: …]`

---

## 1. What this proposal covers

Yuanta Thailand runs three disconnected capability stacks today: a loyalty UI inside the mobile app without an independent points and rewards engine; a Cisco-based contact centre with unreliable cloud-to-hardware routing; and HubSpot Marketing Hub with limited Thai-channel reach (LINE OA, local SMS) and shallow trading-aware segmentation.

Rocket proposes a single cloud-hosted CRM platform that:

1. Calculates and stores loyalty currency from trading activity, with tiers and a reward marketplace fulfilled through Buzzebees.
2. Runs trading-contextual campaigns and lifecycle automation on LINE, SMS, and email — replacing HubSpot for those journeys.
3. Consolidates digital customer service and modernises voice, with an AI agent grounded in Yuanta’s knowledge base.

The Yuanta mobile app remains the member shell. Rocket provides the loyalty web view, the admin surfaces, the CS agent workspace, and the automation engines.

---

## 2. Glossary — shared vocabulary

| Yuanta term | Meaning in this engagement | Rocket construct |
|---|---|---|
| Points / loyalty currency | Balance members earn from trading activity and campaigns | **Currency** — points (fungible) and optional **tickets** (typed balances) |
| Tier (Silver / Gold / Platinum) | Status ladder on a rolling window | **Tiers** — upgrade, maintain, progress, configurable windows |
| Commission earn | Points from trading commissions / activity | **Purchase Transactions** ingest + **earn factors** (amount → currency) |
| Reward catalogue / redeem | Browse and spend points on rewards | **Rewards** marketplace + redemption ledger |
| Buzzebees supply | Mandated partner for voucher / reward fulfilment | **Reward Sourcing & Partner Fulfillment** (partner-network path); Buzzebees as designated partner |
| Web view loyalty UI | In-app hosted redemption experience | Rocket-hosted member web view opened from Yuanta app |
| Trading-target / top-trader campaigns | Time-bound trading challenges and recognition | **Missions**, tags/personas; leaderboard UX noted where custom |
| Spin / lucky draw / check-in / referral | Engagement mechanics | **Campaigns** — Spin Wheel, Mass Lucky Draw, Check-in, Referral |
| Marketing automation / HubSpot replacement | Lifecycle messaging and segmentation | **AMP Workflows** (+ **AMP AI Decisioning** for personalised next action) |
| Omnichannel inbox | One agent view across chat channels | **Unified Inbox** + **Channel Connectors** |
| Contact centre / IVR | Phone routing and agent voice | **IVR Flows**, **Voice Console**, Twilio SIP + speech stack |
| AI CS agent | Autonomous / assisted answers | **CS AI** + **Knowledge Base** + **AOPs** + **Watchtower** + **Live Assist** |
| Consent | PDPA opt-in and channel preferences | **PDPA Consent** on member profile |

---

## 3. Systems and data ownership

| Data / capability | Source of truth | Creates | Reads / consumes |
|---|---|---|---|
| Trades, commissions, account master | Yuanta trading back-office | Yuanta | Rocket (earn feed) |
| Member identity in app session | Yuanta mobile app | Yuanta | Rocket web view (handoff token) |
| Loyalty member profile, consent, wallet, tier | Rocket | Rocket (+ migration from existing loyalty) | Yuanta app web view; CS agent workspace |
| Reward catalogue exposed to members | Rocket (partner SKUs + merchant privileges) | Rocket ops / Buzzebees sync | Members via web view |
| Reward fulfilment (partner vouchers) | Buzzebees | Buzzebees via Rocket redeem path | Members; Rocket ledger |
| CS conversations, tickets, call logs | Rocket | Channels → Rocket | Agents; analytics |
| Knowledge articles for AI / agents | Rocket KB (seeded from Yuanta content) | Yuanta + Rocket | CS AI, Live Assist |
| Marketing journeys & sends | Rocket AMP | Rocket | LINE / SMS / email providers |
| Historical HubSpot contacts / segments | HubSpot (export) then Rocket | Migration workstream | Rocket audiences |

Integration detail for each interface is in §8. Feature sections reference this map rather than restating ownership.

---

## 4. Loyalty programme — earn, tiers, redeem

### 4.1 Core concepts

Rocket becomes the system of record for loyalty balances and tier status. Yuanta’s trading system remains the system of record for trades and commissions. Members experience redeem and progress inside a Rocket-hosted web view opened from the Yuanta app.

### 4.2 Earn from trading activity

**Journey**

1. A retail investor completes a trade; Yuanta’s back-office records commission (or agreed activity metrics).
2. Yuanta pushes a REST transaction payload to Rocket (real-time and/or end-of-day batch — both patterns are supported; exact contract is open).
3. Rocket records an immutable purchase/earn event, runs earn-factor calculation, and posts wallet currency through the ledger chokepoint.
4. Tier evaluation updates from the same activity window.
5. The member sees updated balance and tier progress in the web view on next open (and via optional AMP notification).

**Configuration Yuanta controls**

- Earn factor groups and rates (e.g. commission THB → points).
- Multi-currency: points for general rewards; tickets if Yuanta wants typed balances (draw entries, partner conversion units).
- Store/channel classification if multiple activity types must earn differently.
- Point expiry model (calendar, rolling from earn, or none) — configurable.

`[GAP: Trading REST field schema (raw commission vs net vs pre-calculated points), push frequency, and auth — Yuanta trading IT + Rocket solution-design]`  
`[GAP: Point expiry model — Yuanta programme owners]`

### 4.3 Tiers — Silver / Gold / Platinum

**Journey**

1. Yuanta configures three tiers with upgrade and maintain conditions on a **rolling** window (platform supports rolling and calendar windows).
2. As commission (or agreed metric) accumulates, members progress toward the next tier; the member card shows current tier, next tier, and progress.
3. At maintain deadlines, the daily evaluation keeps or downgrades status per configured grace / maintain rules.

Threshold values and the exact qualifying metric (commission amount primary candidate) are programme decisions, not platform limits.

`[GAP: Tier thresholds, qualifying metric, and downgrade grace — Yuanta programme owners]`

### 4.4 Redemption web view and Buzzebees fulfilment

**Journey**

1. Member taps Loyalty in the Yuanta app.
2. App opens Rocket’s hosted web view with a **secure session handoff** (recommended: signed, short-lived token — not a bare member ID in the query string).
3. Member browses eligible rewards (translations Thai/English), confirms redeem; Rocket burns points and creates the redemption ledger row.
4. Partner-network rewards route to **Buzzebees** for issuance/fulfilment; digital codes typically land in-wallet near real time; physical items follow partner logistics with tracking where supported.
5. Merchant-owned privileges (fee waivers, service vouchers) can sit alongside partner SKUs without third-party procurement.

**Constraints honored**

- Direct voucher issuance by Rocket outside the Buzzebees path is out of scope for partner-supply rewards.
- Reward groups, catalogue management, and promo codes are available in admin.

`[GAP: Web-view token type and IdP ownership — Yuanta app + Rocket]`  
`[GAP: Buzzebees API contract and commercial account ownership — Yuanta / Rocket Reward Strategy]`

### 4.5 Profile, consent, admin

- Custom profile fields for trading-relevant attributes.
- PDPA consent capture and channel/topic preferences on the unified profile save path.
- Stored-value card constructs available if reward-wallet mechanics require them.
- Admin panel for programme configuration, member management, and operational oversight (English admin UI by default).

`[GAP: Thai admin UI requirement — Yuanta ops]`

### 4.6 Loyalty implementation matrix

| Area | Method | Real-time option | Phase 1 |
|---|---|---|---|
| Earn feed | REST from trading BO | Yes and/or EOD batch | Yes — contract in solution-design |
| Wallet / expiry | Currency engine | Post on award path | Yes |
| Tiers | Configurable ladder, rolling window | Near-real-time eval + daily maintain | Yes |
| Redeem UI | Hosted web view in Yuanta app | Session handoff | Yes |
| Partner rewards | Buzzebees via Reward Sourcing | Digital near-instant target | Yes |
| Member migration | Import balances / tiers / consent | Cutover plan | Yes — effort after data assessment |

---

## 5. Campaigns and engagement

Same scaffold for each mechanic: concept → member journey → Yuanta configuration → trading context.

### 5.1 Trading-target missions

Members complete defined actions (e.g. reach a commission or volume threshold in a window) and receive bonus points or rewards. Admin configures action + condition + result; progress updates from the same earn/transaction stream as core loyalty.

### 5.2 Top-trader recognition

Threshold-based recognition and cohort tagging are supported through missions, tags, and personas. A dedicated live leaderboard UI is **not** claimed as a standard product module in this draft.

`[GAP: Confirm whether top-trader means mission thresholds + recognition rewards, or a custom leaderboard surface — Yuanta marketing]`

### 5.3 Referral

Existing members share invite codes; new account holders enter codes at signup; both sides receive configured benefits after qualifying activity. Qualification can be tied to trading milestones once those events land in Rocket.

### 5.4 Check-in, spin wheel, mass lucky draw

- **Check-in:** periodic attendance streaks with milestone rewards.  
- **Spin wheel:** randomised prizes funded by points/tickets with configurable prize tiers.  
- **Mass lucky draw:** members spend currency to enter; draw can be executed offline from an exported participant list when Yuanta wants a public ceremony.

Forms support campaign entry and profile enrichment; tags and personas target cohorts.

---

## 6. Marketing automation and AI decisioning

### 6.1 Why this replaces HubSpot for Yuanta’s channel mix

AMP Workflows are event-driven graphs: triggers on CRM events (trade/earn recorded, tier change, inactivity, audience entry), conditions, waits, branches, and actions (LINE, SMS, email, award currency, tag, webhook). Segmentation uses trading activity, tier, balances, tags, and personas — the depth HubSpot lacked for Thai channels.

### 6.2 Marketer journey

1. Connect LINE OA and SMS/email senders.  
2. Build a workflow (e.g. “first trade → educate → if no second trade in 7 days → SMS nudge”).  
3. Activate; execution logs show each member’s path.  
4. Use **AMP AI Decisioning** where Yuanta wants an objective (“re-engage lapsed traders”) and allowed actions instead of hand-building every segment branch.

### 6.3 HubSpot transition

No ongoing HubSpot integration after cutover. Export contacts/segments as needed; run parallel or hard cutover per marketing preference.

`[GAP: Parallel-run duration and historical campaign retention — Yuanta marketing]`  
`[GAP: Thai SMS gateway provider — Yuanta existing contract or Rocket default]`

### 6.4 Marketing implementation matrix

| Capability | Channel | Phase 1 |
|---|---|---|
| Lifecycle workflows | LINE, SMS, email | Yes |
| Audience / segment filters | Trading + loyalty attributes | Yes |
| AI next-best action | AMP AI Decisioning | Yes |
| Thai / English content | Translation system | Yes |
| HubSpot decommission | Export + cutover | Yes — plan in solution-design |

---

## 7. Customer service — digital, voice, AI

### 7.1 Omnichannel digital

**Channels at go-live:** LINE OA, Facebook Messenger, Instagram DM, web chat, in-app chat, email.

**Journey**

1. Admin connects each channel (credentials, webhook validation).  
2. Inbound messages resolve to a **unified customer identity** (optionally linked to the loyalty member).  
3. Agents work one **Unified Inbox** with routing by skill, queue, tier, or rules.  
4. Chatbot flows deflect common FAQs before human or AI handoff.  
5. Tickets track issues that outlive a single chat thread; analytics and insert-only logs support QA and audit.

### 7.2 Voice — options and recommendation

Yuanta’s current pain is unreliable cloud-to-hardware routing on Cisco.

| Option | What changes | Reliability | Ops impact | Best when |
|---|---|---|---|---|
| **A. Cloud voice replacement (recommended)** | Inbound numbers on Rocket voice (Twilio SIP trunk); IVR + AI + Voice Console in one workspace | Removes the failing cloud→Cisco hop | Agents use Rocket voice console; Cisco PSTN role ends or shrinks | Primary goal is routing reliability and unified agent UX |
| **B. Hybrid — retain Cisco, upstream IVR/AI** | SIP from Cisco toward Rocket IVR/AI; Cisco may still terminate some calls | Improves upstream intelligence; still depends on Cisco path quality | Dual stack to operate and monitor | Hardware investment must be preserved short-term |

**Recommendation:** Option A for phase 1. It directly addresses the stated failure mode and puts voice on the same conversation model as chat (live transcript, recording with PDPA disclosure, warm transfer, disposition). Option B remains available if solution-design proves Cisco retention is mandatory; it requires Cisco model and SIP details Yuanta has not yet provided.

`[GAP: Cisco hardware model and SIP trunk config if Option B is chosen — Yuanta contact centre]`

**IVR example:** language select (Thai / English) → department → AI voice agent or human queue; after-7 hours fallback to AI or voicemail transcribed into the inbox.

### 7.3 AI customer service agent

- **Brand AI configuration** — tone, languages, guardrails, escalation triggers for a securities context.  
- **Agent Operating Procedures (AOPs)** — step playbooks for intents (e.g. “where are my points”, “how to upgrade tier”) with when to escalate to a human.  
- **Knowledge Base** — articles chunked and retrieved semantically; Yuanta seeds FAQs, product copy, and approved disclosures.  
- **Watchtower** — monitors conversations against natural-language compliance criteria.  
- **Live Assist** — draft replies, summaries, KB sidebar, translation for human agents.  
- **Actions** — shared action library for AI and humans (account lookup patterns via agreed Yuanta APIs).  
- **CSAT** — post-resolution feedback collection.

`[GAP: Knowledge base source formats and volume — Yuanta CS]`  
`[GAP: Back-office action APIs the AI/agent may call — Yuanta IT]`

### 7.4 CS implementation matrix

| Surface | Channels / stack | Phase 1 |
|---|---|---|
| Unified inbox | LINE, Messenger, IG DM, web, in-app, email | Yes |
| Voice | Cloud IVR + console (rec. Option A) | Yes |
| Ticketing | From any channel | Yes |
| AI agent + KB + Watchtower + Live Assist | Chat + voice | Yes |
| Replace current chat platform | Parallel/cutover TBD | Yes |

---

## 8. Integration architecture

### 8.1 Yuanta app → Rocket web view

- **Direction:** App opens Rocket URL with session proof.  
- **Recommendation:** Signed short-lived JWT (or one-time token) minted by an agreed party; Rocket validates and establishes the member session.  
- Plain member ID in query string is not recommended for a brokerage context.

### 8.2 Yuanta trading back-office → Rocket earn feed

- **Direction:** Yuanta → Rocket REST.  
- **Patterns:** (1) per-trade or near-real-time push; (2) end-of-day batch; (3) both for different event classes.  
- **Payload shape (illustrative):** member external ID, trade/commission reference, amount, timestamp, activity type, idempotency key. Final schema in solution-design.  
- Rocket maps amounts through earn factors; does not require Yuanta to pre-calculate points unless Yuanta prefers that model.

### 8.3 Rocket ↔ Buzzebees

- Redeem request and catalogue/inventory sync as a required phase-1 workstream under Reward Sourcing.  
- Commercial ownership (Yuanta vs Rocket contract) and API specifics deferred — does not remove the workstream from scope.

### 8.4 Channel connectors

- LINE Messaging API, Meta Messenger/Instagram, email, web widget, in-app chat embed, SMS gateway.  
- Webhook signature validation mandatory on inbound adapters.

### 8.5 Voice

- Recommended: platform-managed numbers / SIP via Twilio into Rocket IVR and Voice Console.  
- Hybrid Cisco path only if Option B is selected after SIP discovery.

---

## 9. Non-functional commitments

| Topic | Proposal stance |
|---|---|
| Compliance | PDPA consent, audit-friendly conversation/call logs, consent-aware messaging. Data subject rights processes aligned in solution-design with Yuanta legal. |
| Hosting | Rocket-managed cloud. No on-premise deploy. |
| Data residency | PDPA-compliant region; Thailand-only vs broader compliant region to confirm. `[GAP: residency — Yuanta legal]` |
| Languages | Member surfaces Thai + English via Translation System. Admin English default. |
| Availability | Design for SET trading hours visibility of earn/balance; specific uptime SLA in contract schedule. |
| Security | Encryption in transit/at rest, RBAC admin, audit of admin and CS events. No named certification claimed unless contracted. |
| Scale | Mid-market launch configuration; platform scales with programme growth. |

---

## 10. Implementation plan — path to 2Q 2026

Phased as one go-live package unless Yuanta elects a controlled early loyalty pilot.

| Workstream | Major deliverables | Dependencies |
|---|---|---|
| Programme design | Earn rules, tiers, expiry, reward mix with Buzzebees | Yuanta workshop decisions |
| Earn integration | REST contract, auth, UAT with sample trades | Yuanta trading IT |
| Web view + SSO handoff | Hosted redeem UI, token validation | Yuanta app release |
| Reward sourcing | Buzzebees commercial + technical onboarding | Account ownership decision |
| Member migration | Identity, balances, tiers, consent | Data extract quality |
| Campaigns | Missions, referral, check-in, spin/draw as prioritised | Earn feed live |
| AMP + HubSpot exit | Workflows, LINE/SMS/email, cutover | Channel accounts |
| CS digital | Six channels, inbox, routing, bots | Channel ownership / Meta assets |
| Voice | Option A (or B) IVR + console | Numbering / SIP |
| CS AI | Brand config, AOPs, KB seed, Watchtower | Content from Yuanta |
| UAT & go-live | End-to-end earn → redeem → CS → messaging | All above |

**Migration (confirmed in scope):** existing loyalty members, point balances, tier status, and consent records. Volume and cleansing effort estimated after data assessment — not pretended as a fixed person-week number here.

`[GAP: Migration volume, format, cleanliness — solution-design assessment]`

**Support (proposed baseline until SLA schedule signed):** Thai + English business-hours coverage; escalation path during SET hours for earn/balance incidents.

---

## 11. Requirement coverage (compressed)

| Requirement theme | Coverage | Notes |
|---|---|---|
| Backend points on trading activity | Supported | Via earn feed + currency engine |
| Three tiers, rolling 12 months | Supported | Thresholds configurable |
| Multi-currency / tickets | Supported | |
| Web-view redeem in Yuanta app | Supported | Handoff mechanism open |
| Buzzebees-only partner supply | Supported as workstream | No direct Rocket voucher path for partner SKUs |
| Missions, referral, check-in, spin, lucky draw | Supported | |
| Top-trader leaderboard | Partial | Mission/tag pattern; custom UI unconfirmed |
| AMP + LINE/SMS/email + AI decisioning | Supported | HubSpot replace path |
| CS six digital channels + tickets + analytics | Supported | |
| Voice IVR + agent console | Supported | Cloud recommended |
| AI agent, KB, Watchtower, live assist, CSAT | Supported | Content seeding open |
| PDPA consent | Supported | |
| Thai + English member UX | Supported | |
| Loyalty data migration | Supported (workstream) | Effort after assessment |
| Cisco hybrid voice | Partial / optional | Depends on SIP discovery |

---

## 12. What happens next

1. **Review 2** — Yuanta / Rocket sales confirm this draft (especially voice Option A, Buzzebees workstream, and HubSpot exit).  
2. Solution-design workshops close the `[GAP: …]` items that change build sequence (earn contract, web-view token, Buzzebees account).  
3. Commercial proposal / SOW attaches effort and SLA once those gaps shrink.

Unresolved gaps remain visible until a human removes them. No capability, metric, date, or integration was invented beyond the platform behaviours described above and the assumptions stated in the project dossier.
