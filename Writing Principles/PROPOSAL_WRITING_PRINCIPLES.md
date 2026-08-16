# Proposal Writing Principles

### Reading, Understanding, Structuring, And Writing For B2B SaaS Platform Proposals

---

## Purpose

These principles govern B2B SaaS platform proposals: how to read customer requirements, how to interpret them against the platform, how to organize the response, and how to write each section so it sounds like someone who has actually built the platform.

Use `CORE_WRITING_PRINCIPLES.md` first for the shared structural rules:

- Pyramid structure.
- Vertical logic.
- Horizontal logic.
- MECE grouping.
- Same-level abstraction.
- Parallel peer points.
- Layered depth.
- Specificity and explicit limitations.

This document explains how those principles apply specifically to proposals, plus proposal-only practices for reading source material, understanding what was asked, structuring the response, and writing each section.

> **Scope note — custom and government proposals:** Under `workflows/general-proposal/`, its `REFERENCE.md` and `SCAFFOLDS.md` take precedence for official voice, uneven depth, TOR placement, and chapter texture. CRM Knowledge verification applies only to Rocket product claims; general-proposal facts come from the run’s `sources/` and human answers. Identical peer scaffolds, SCQA-style section narration, and per-module closing matrices are optional techniques, not defaults.

A proposal succeeds when:

1. The reader sees exactly how their operation works on the platform.
2. Every section shows a distinct part of the system, with no overlaps or obvious gaps.
3. The writing sounds like an experienced systems architect walking through a whiteboard, not a salesperson reciting benefits.

The four sections below run in the order the work happens: read the source, interpret it, organize the response, then write each section.

---

# Section 1 — Reading Customer Requirements

**Conditional.** Apply only when the proposal responds to a written requirements document (TOR, RFP, requirements CSV, scope letter, or similar). Skip this section when the proposal is unsolicited, opportunity-driven, or working from a verbal brief.

The reading discipline below shapes how trustworthy the rest of the document feels. Buyers can tell within a few pages whether you read their document or skimmed it.

## R1. Cite Source Clauses By ID When You Answer Them

When a section answers a specific clause in the requirements document, cite the clause ID. This lets the buyer trace your interpretation back to their words and verify coverage section by section.

Example:

> The TOR explicitly states (B3.4): "การเข้าใช้บริการ 'แพ็กเกจหลายครั้ง/คูปองชุด' และการสร้าง/ตัดอัตโนมัติ หลัง ซื้อ/เข้ารับบริการ" — auto-create and auto-deduct after purchase/service via HIS API.

> The TOR says (C2): "ซื้อ Membership หรือ Subsciption Plan เช่น Divine Elite" and "ใช้ payment gateway ฝั่ง Rocket ทั้งหมด end to end."

## R2. Quote Source Language Verbatim When Intent Matters

Paraphrase flattens nuance the customer chose deliberately, especially in non-English source documents where translation choices change meaning. Quote verbatim, then translate or interpret next to it.

Example:

> The TOR (C5.6): "การใช้สิทธิ์ร่วม/ไม่ร่วม กับ Coins/eCoupon/ส่วนลดอื่น (stackability / precedence)." This means: some health packages allow insurance discount + coin discount together, others don't.

## R3. Distinguish Explicit Statements From Implied Or Assumed Requirements

Implied requirements are interpretations and should be marked as such. Stating an assumption gives the customer a chance to confirm or correct before the assumption is baked into a delivery plan.

Example:

> The TOR mentions missions generically — does NOT specifically request milestone (multi-level) missions.

> The TOR does NOT explicitly specify a primary key for user matching. In the Thai hospital context, the most likely approach... This should be clarified with Samitivej's tech team during technical design.

## R4. Note Where The Source Is Silent, Ambiguous, Or Self-Contradictory

Silent and contradictory areas are scope risks. Identifying them up front is the difference between a thoughtful response and a default-yes response that explodes during execution.

Example:

> The TOR references Coins only — no mention of "Tickets" or multiple currency types.

> The TOR says two things that must be read together: F3 ... and A2.6 ... This means the data has two layers.

---

# Section 2 — Understanding And Contextualizing Requirements

This section is about interpretation: bridging the customer's vocabulary to the platform's, recognizing where one customer concept hides multiple platform patterns, reality-checking what is feasible, and labeling what was asked vs what you are offering on top.

These principles apply to every proposal, regardless of whether the source is a written requirements document or a verbal brief.

## U1. Build A Vocabulary Bridge Between Customer Terms And Platform Terms

When the customer uses terms that overlap with but do not exactly match the platform's terms, build an explicit mapping early. Do not silently swap one term for the other. Do not force the platform to adopt the customer's word without saying so.

Pattern:

```
Glossary of customer terms (definition in their framing; Rocket note only when needed)
    -> Optional Concept splits subsection when one customer word hides multiple platform patterns
        -> Body uses customer terms throughout; Rocket names in integration + notes only
```

Example (glossary Rocket CRM note when rename is needed):

| Customer term | Definition | Rocket CRM note |
|---|---|---|
| eVoucher (TOR) | Digital benefit delivered by code | Configured as digital reward with promo code pool |

Example (legacy separate concept table — use only for large splits, not 1:1 duplicates):

| Samitivej Concept | Our Reward Configuration |
|---|---|
| eCoupon (single-use) | Reward with `fulfillment = digital`, quantity = 1, promo code attached |
| Mandatory Coupon | Reward with `visibility = admin`, auto-issued on package purchase via API |
| Seasonal Coupon | Reward with `visibility = campaign`, trigger = birthday/anniversary |

Example (naming clarification stated explicitly):

> The RFP uses "eVoucher" terminology, but we refer to this as "stored value card" to distinguish from reward vouchers that may also be electronic.

## U2. Recognize When One Customer Term Hides Multiple Platform Patterns

Customers often bundle distinct concepts under one word. When you spot this, split the concept and name each pattern separately. Map each pattern to its own platform construct.

Collapsing two patterns into one mapping hides a real architectural decision and usually leads to under-scoping the new development or building the wrong thing.

Example:

> Samitivej's entitlement system has two fundamentally different patterns:
>
> Pattern A: Consumable items → Our Reward
> These are items that get "used up" — single-use coupons, multi-use packages with a count, one-time vouchers.
>
> Pattern B: Standing benefits → New concept (Benefit Rules)
> These are ongoing membership benefits that NEVER get consumed — they apply every time the member uses a service, for the entire validity period.

## U3. Reality-Check Customer Assumptions Before Agreeing They Are Feasible

When a request rests on an assumption that may not hold (a public API exists, a partner will integrate, a workflow is industry-standard, the platform supports something), pause and verify. State the finding. Then offer a realistic alternative.

For the general-proposal workflow, verify against the run’s `sources/`, external primary documentation, and human answers only. Do not use CRM Knowledge as a substitute for evidence in a custom or government bid.

Verification checklist:

| Assumption type | How to verify |
|---|---|
| Platform capability claim (ours) | Query the CRM Knowledge MCP per `.cursor/rules/15-crm-knowledge.mdc` and verify against the local repo. Do not promise a capability that has not been validated this way. |
| External API or integration | Read the actual API documentation. Check whether the endpoint is public, partner-only, or requires a B2B agreement. |
| Partner cooperation | Identify whether the partner has a known program for this integration, or whether a new commercial agreement is required. |
| Regulatory or compliance requirement | Identify the specific regulation (PDPA, e-money, AML) and whether it affects feasibility or timeline. |
| Workflow assumption | Name the assumption and ask whether it holds in the customer's specific environment. |

Pattern:

```
Reality Check — X
    -> findings on each component
        -> What This Means for [Customer]
            -> realistic alternative path
```

Example:

> Reality Check — Platform Coin Transfer APIs:
> - Shopee Coins: No public API exists for transferring Shopee Coins to external loyalty programs ... A direct coin transfer would require a B2B commercial partnership.
> - The1 (Central Group): Does support partner point exchange ... but works via a B2B commercial agreement, not a public endpoint.
>
> What This Means for Samitivej:
> The coin transfer feature is technically straightforward on our side ... The blocker is commercial — each marketplace/partner requires a business development deal.

## U4. Distinguish What The Customer Asked For From What You Are Offering Beyond

Label requested capabilities and bonus capabilities differently at the section level. Make the distinction visible per requirement, not just in a final scope table.

Buyers comparing vendors need to verify scope coverage without filtering out your bonus features. Mixing the two inflates perceived complexity and makes apples-to-apples comparison hard.

Example (repeated per requirement section):

> What the TOR Specifies:
> - Display current coin balance
> - Full earn/burn/expire history
> - Omni-channel wallet
>
> Additional Capabilities We Offer (beyond TOR):
> - Multiple currency types (Coins + Tickets)
> - Delayed award (24h hold before wallet credit)
> - Reversal/cancellation for refunds

A top-of-document note that lists the major "our extras, NOT in the source requirements" also helps buyers know what to discount when comparing scope across vendors.

---

# Section 3 — Structuring The Proposal

This section is about document organization: where each kind of content lives, what comes first, what gets a dedicated section, and how peer modules align.

## S1. Lead With Vocabulary Alignment Before Any Feature Walkthrough

Place a **customer-primary glossary** at the front of the document, before any feature or journey content. Without this front-load, the reader fights vocabulary mismatch through every later section. A separate concept-unification chapter is **optional** and only for 1:many splits that do not fit inside the glossary.

Example document order:

```
Glossary of terms (customer definitions + optional Rocket notes)
    -> [Optional] Concept splits only when one customer term maps to multiple constructs
        -> Phase 1 requirements (body uses customer vocabulary)
            -> Phase 2 requirements
                -> Feature mapping summary
                    -> Pages, demo scenarios, data architecture, timeline
```

## S2. Make Peer Modules Comparable Without Publishing A Template

When the proposal walks through peer items, cover comparable questions where they matter, but do not force identical headings or an identical paragraph sequence. Repeated structure helps scanning only when the underlying modules are genuinely comparable; otherwise it creates fake balance and a visible AI/template fingerprint.

Use a shared planning scaffold internally:

```
a) Core Concepts & Definitions
b) Full Capabilities
c) Marketer View
d) Technical View
e) Implementation Examples (Customer-specific)
```

For published prose, keep the dimensions the reader will compare and let subject-specific headings carry the differences. A thin module may need one paragraph and a table; a complex journey may need stages, decisions, and a worked path.

Example planning dimensions for touchpoints:

```
Integration architecture
    -> Customer journey
        -> Options when multiple paths exist
            -> Security and fraud risk
                -> Recommended path with reasoning
```

## S3. Use A Compressed Implementation Matrix When It Adds A New View

Use a matrix when it lets executives compare several items across consistent dimensions after the detailed walkthrough.

Do not add a closing matrix when it repeats the preceding feature table, timeline, or comparison matrix. One-screen compression is useful only when it answers a different question.

Example:

| Touchpoint | Method | Integration Type | Security Level | Real-time | Fraud Risk | Strategic Requirements |
|---|---|---|---|---|---|---|
| Fuel Stations | POS/EDC Direct Integration | Existing API (Enhancing) | High | Yes | Low | System upgrade in progress |
| Merchant On-us | Acquirer Integration (EDC) | Caltex MID Terminal | Very High | Yes | None | Acquirer partnership, device deployment |
| Merchant On-us | Caltex POS System | Full POS replacement | Medium | Yes | Medium | Strategic POS rollout decision |

## S4. Place Data Ownership And Integration Architecture In One Section, Then Reference

For integration-heavy proposals, put the source-of-truth map and integration diagram in one dedicated section. Reference it from feature sections instead of restating ownership inside each feature walkthrough.

Without a single map, downstream sections drift between systems and the buyer cannot tell who owns each record. Repeating the ownership story per feature also bloats the document.

Example (one source-of-truth table referenced throughout):

| Data Type | Source of Truth | Who Creates | Who Reads | Notes |
|---|---|---|---|---|
| Medical service catalog | CDP Hospital | Hospital team | Our system consumes catalog | We mainly need the catalog, not necessarily real-time prices |
| Health Packages | Our system | Marketing team in our back office | Well app, website, LINE, HIS | We determine price |
| Entitlement records | Our system | Auto-issued on purchase | Patient (app), staff (admin), HIS (via API) | All changes flow through our system |

## S5. Sequence Features By Delivery Phase When Capabilities Ship In Stages

When some capabilities ship at launch and others ship later, sequence the proposal by phase rather than mixing phases inside feature sections. Make each phase's go-live deliverable clear.

Phase-based sequencing matches how the buyer's program governance, budget release, and acceptance testing actually work. It also keeps "we will build this someday" language out of the day-one scope.

Example structure:

```
Section 3 — Phase 1 Requirements
Section 4 — Phase 2 Requirements
Section 5 — Phase 3 Requirements
Section 6 — Consolidated Mapping Summary Across All Phases
Section 7+ — Project plan with Go-Live #1 and Go-Live #2 dates
```

## S6. Tag Each Requirement With A Fit Status — Conditional

**Conditional.** Apply when the proposal walks the customer's enumerated requirements one by one (TOR-response, RFP-response, requirements-CSV-response).

For each requirement, give a one-word fit status — **Supported**, **Partial**, or **Not Yet Built / New Development** — followed by what exists, what needs enhancement, and what is brand new.

Buyers reading a long requirements-mapped proposal need to scan for risk. Fit status lets them locate the unsupported and partially supported areas without inferring scope from feature descriptions.

Example (fully supported) — customer-facing; no schema or requirement codes:

> | Requirement | Coverage | Notes |
> |---|---|---|
> | Member wallet balance and full earn/burn history | Supported | Points and tickets; delayed earn when rules require it |
> | Tier-based earn multipliers | Supported | Configured in admin; evaluated on each qualifying purchase |

Example (not built):

> | Requirement | Coverage | Notes |
> |---|---|---|
> | Multi-step journey automation with A/B branches | New development | SMS channel exists; journey builder not in current product |

---

# Section 4 — Writing

This section is about how each part of the proposal sounds and reads. The first eleven principles are the original proposal-writing rules; the last two are additions drawn from the Samitivej and Caltex proposals.

## W1. Show The Platform, Do Not Argue For It

The proposal's job is to make the platform visible: how data moves, how users interact, how systems connect, what operators control, and where the limits are.

It is not a pitch deck. It should not lean on ROI claims, industry benchmarks, or generic arguments that loyalty programs are valuable. In an RFP or serious platform evaluation, the reader already accepts the category. They need to understand what the system will do.

Weak:

> Tiered loyalty programs increase customer lifetime value.

Stronger:

> The platform supports three tier levels. Each tier has configurable earn rates, benefit packages, and auto-upgrade rules based on spend thresholds.

Weak:

> Real-time processing improves customer satisfaction.

Stronger:

> Points calculate and return in under one second. The EDC prints the earned points on the receipt before the customer leaves the counter.

Test: if the sentence still works after replacing Rocket with a competitor name, it is probably a claim. Rewrite it as specific system behavior.

## W2. Use Journey Walkthroughs When Sequence Is The Evidence

Use a journey walkthrough when the buyer needs to see how a user, transaction, operator, or data object moves through the system. For static controls, reference data, infrastructure minima, or simple commitments, direct prose or a compact table is usually better.

Pattern:

```
1. Name the touchpoint or feature.
2. Describe the starting state: who, where, what they are doing.
3. Walk through each step: what the user does, what the system does.
4. Show the end state: what the user sees, what the system recorded.
5. Add a diagram or flow that mirrors the walkthrough.
```

Example:

```
Customer arrives at the fuel station.
Staff enters the transaction on the POS.
The POS sends the transaction to Rocket through middleware.
Rocket checks member identity, earn rules, and duplicate-prevention rules.
Rocket returns the points result to the POS.
The EDC receipt prints the earned points before the customer leaves.
```

The text and diagram should tell the same story from different angles. Text gives the walkthrough; the diagram makes the sequence scannable.

## W3. Present Options With Honest Trade-Offs, Then Recommend

When multiple implementation approaches exist, show the options and compare them across dimensions the reader actually cares about.

Then make a recommendation.

Pattern:

```
Options table -> recommendation -> reasoning that references the table dimensions
```

Example dimensions:

| Option | Security | Complexity | Customer Journey | Best For |
|---|---|---|---|---|
| Portal entry | Low | Low | Works with any payment method | Backup scenarios |
| POS integration | Medium | High | Instant points with OTP | Full-service stations |
| Sub-merchant EDC | High | High | Card-only | High-volume merchants |

Good recommendation:

> For Merchant On-us, we recommend leveraging existing payment infrastructure through acquirer integration. It has higher setup complexity, but it reduces manual transaction-entry risk and gives the cleanest audit trail.

Do not hide the recommendation in a footnote. A proposal should show the option space, then demonstrate judgment.

Use option tables only when the choice is real: security tolerance, technical capacity, rollout complexity, operational process, or budget. Do not create a comparison table for every minor decision.

## W4. Adapt Pyramid Structure To Platform Proposals

In proposals, the pyramid is not only "recommendation first, evidence below." It is:

> What the platform does first, then how each part works.

Example:

```
Overview: The platform supports earn and burn across five touchpoints
    Touchpoint 1: Fuel stations
        Integration architecture
        Customer journey - staff-assisted
        Customer journey - app-initiated
        Security and duplicate prevention
    Touchpoint 2: Merchant On-us
        Portal-entry option
        POS-integration option
        Sub-merchant EDC option
        Recommended path and trade-offs
    Touchpoint 3: Merchant NFR
    Touchpoint 4: Online store
    Touchpoint 5: Rewards
    Summary: implementation matrix
```

The shared rule from `CORE_WRITING_PRINCIPLES.md` still applies: every child section must directly elaborate its parent, and every peer section must be grouped by the same dimension.

## W5. Use SCQA As An Introduction Diagnostic

SCQA can help diagnose whether a section introduction has a clear reason to exist. It is not a four-sentence template, and the published paragraph should not narrate the document.

| Element | In a proposal section |
|---|---|
| Situation | What part of the system this section covers |
| Complication | What makes this part complex or worth detailing |
| Question | What the reader needs to understand |
| Answer | What this section will walk through |

Example:

> This section covers the core earn and burn flows across fuel stations, merchant transactions, online purchases, and rewards. These flows require different integration paths, security checks, and customer journeys, so the section maps each touchpoint separately before summarizing the recommended implementation model.

No broad market preamble or generic value claim. Lead with the operational point. If the situation and answer fit in one sentence, stop there; do not add complication or “this section will…” language merely to complete SCQA.

## W6. Apply MECE To Proposal Scope

Use `CORE_WRITING_PRINCIPLES.md` for the general MECE rule. In proposals, stress-test MECE against the operational scope the reader expects.

Common proposal CE checks:

| Level | Proposal-specific test |
|---|---|
| Ecosystem overview | Does the overview cover every touchpoint where a customer interacts with the platform? |
| Each touchpoint | Does it cover architecture, customer journey, operational flow, and options if multiple approaches exist? |
| Earn and burn | Are both directions mapped for every relevant touchpoint? |
| Operations | Can the reader see who configures, monitors, reviews, and fixes the flow after launch? |

The most common proposal failure is covering the happy path while skipping edge cases and unsupported scenarios.

**Constraints the customer raised must be addressed somewhere.** If the customer's TOR or Q&A asks about a constraint (channel limitation, SLA, data residency), address it. The appropriate place is wherever that constraint affects the customer's decision — not in a generic Limitations block. A constraint that lives in a relevant subsection is far more credible than a list at the end.

Do not add a limitations block as a default coverage item. See `CORE_WRITING_PRINCIPLES.md §12` for the updated rule on when limitations are appropriate.

## W7. Cross-Reference Dependencies Without Repeating Them

Platform features depend on each other. A proposal should make those dependencies visible without duplicating entire walkthroughs.

Good:

> Many earn and burn flows depend on the Merchant Portal for partner registration, reward management, and transaction review. The Merchant Portal is covered in the next section.

Use cross-references for:

- Shared portals or admin tools.
- Shared customer profiles.
- Shared security controls.
- Shared integration middleware.
- Shared reporting or reconciliation flows.

Do not re-explain the same feature in full under every section that touches it.

## W8. Use Layered Proposal Depth

A proposal should let different readers stop at different depths.

Proposal depth pattern:

```
Level 1: Overview table or ecosystem diagram
Level 2: Architecture diagram per major component
Level 3: Sequence diagram or journey walkthrough per flow
Level 4: Configuration, edge cases, security, and operational detail
Level 5: Summary matrix across components, options, or touchpoints
```

Executives should be able to read the overview and summary tables. Technical and operational readers should be able to find implementation detail without wading through positioning copy.

## W9. Follow The Reader's Natural Question Flow

A platform proposal should follow the evaluation sequence of someone trying to understand a system:

```
Executive summary: what does this platform do?
    -> Core journeys: how do customers interact with it?
        -> Portal and tools: how do operators manage it?
            -> Technical architecture: how is it built?
                -> Integrations: how does it connect to our systems?
                    -> Migration: how do we get from here to there?
                        -> Operations and support: what happens after launch?
```

Every section should answer the reader's next natural question. If a section jumps from high-level benefit to implementation detail and back again, the reader has to rebuild the structure themselves.

## W10. Write In A Systems Architect Voice

The default proposal voice is someone who has built the system, deployed it, and watched real users interact with it.

| Trait | What it sounds like |
|---|---|
| Shows the system | Describes user actions, data flows, system responses, and operator controls |
| Knows edge cases | Names what does not work, what is rare, and what needs a workaround |
| Gives honest assessments | States security risk, setup complexity, operational burden, and trade-offs |
| Uses grounded evidence | Cites field research, existing infrastructure, actual flow constraints, or implementation facts |
| Recommends with reasoning | Chooses an option and explains why using the comparison dimensions |

Avoid proposal voice that sounds like a generic vendor:

| Weak | Stronger |
|---|---|
| Our platform enables a seamless customer experience | The customer sees earned points on the receipt before leaving the counter |
| Comprehensive reporting gives visibility | The portal shows points issued, rewards redeemed, transaction history, and campaign performance by date and location |
| Robust integration with existing systems | The POS sends transactions through RabbitMQ middleware to Rocket's earn API |
| Flexible campaign management | Marketers build campaigns by combining actions, conditions, and outcomes without developer support |

## W11. Let Structure Signal Authenticity

Proposal structure itself tells the reader whether the writer understands the system.

Authentic proposal structure:

- Section lengths vary based on real system complexity.
- "Not available" and "not recommended" scenarios appear where relevant.
- Comparison tables show uneven options when one option is clearly better.
- Notes and caveats clarify likely reader confusion.
- Numbers are specific when known and qualified when uncertain.
- Constraints sit next to capabilities instead of being hidden later.

Avoid artificial balance. Real systems are uneven.

## W12. Headings: Descriptive Noun Phrase by Default, Question When It's a Decision

The default heading style for a proposal subsection is a **descriptive noun phrase** that names the topic — this reads as a professional consulting document.

Examples of correct default style:

- Earn process: division of responsibility
- Reward catalogue: inventory sources and availability
- Admin portal: what the operator sees day-to-day
- Currency engine: scope and headroom

Use a **question heading only when** the subheading marks a genuine decision-point the reader has come to the document to resolve — ownership disputes, conditional branching, configuration options with real trade-offs:

- Who Deducts — HIS or Our Admin?
- What Happens if Package Details Change?
- Where Does the Purchase Happen?
- Which earn channels need middleware vs direct API?

Question headings are not decorative. "What can the points engine do?" is not a decision-point — the reader isn't choosing whether to use the engine, they're reading to understand it. Use "Points engine: scope and headroom" instead.

**Section-level colon subtitles:** a colon subtitle is useful only when it meaningfully sharpens the contract. "Tier Programme: member-facing mechanics" works. "Integration Architecture: Connecting {Customer}'s Back-End to Rocket CRM" should be simplified to either "Integration Architecture" or "Back-End Integration: key flows". Customer and vendor names belong in the body, not in section titles — they add noise to the TOC without adding information.

## W13. Anchor Flexibility Claims With A Worked Example In The Customer's Context

When describing a configurable or composable system **and the claim is otherwise hard to verify**, show one concrete trip through it: real customer context, real artifacts, real outcomes. The example must use the customer's domain — their products, places, personas, venues, or (for custom/government bids) their stated journeys and offices — not a generic placeholder.

"Flexible" is a low-evidence claim. A worked example proves the system can resolve a realistic input to a clear, explainable output. Using the customer's own context proves you have thought about how their real work would land on the system.

**Judgment, not a template rule:** do not add a worked example to every section because a checklist said so. Add one when it removes ambiguity on a central or scored claim. Skip when bullets already make the behavior obvious, or when another section already carries the story. For custom/government proposals, see also `workflows/general-proposal/SCAFFOLDS.md` → “Depth and examples.”

Example (Caltex multi-currency earn — uses Caltex products, stations, tiers):

> Transaction: Gold member buys 40L Power D at Highway station, 7 AM Monday, pays with Starcash
>
> Applicable Earn Factors:
> 1. Base Rate: 1L = 1 point
> 2. Gold Tier Factor: 1.5x
> 3. Power D Premium: 1.2x
> 4. Highway Bonus: 1.3x
> 5. Morning Rush: 1.4x
> 6. Starcash Payment: +10 fixed points
>
> Calculation (multiplicative stacking):
> - Base: 40 points
> - With factors: 40 × 1.5 × 1.2 × 1.3 × 1.4 = 131 points
> - Plus fixed: 131 + 10 = 141 total points

A generic "Customer X buys product Y" example would not have done the same work.

---

## W13a. Cover Requirements By Detailing Features

When a proposal answers a written TOR or RFP, structure may follow the buyer’s clause order so evaluators can find coverage. The **body** of each capability section should still be feature and journey detail — what users do, what the system does, how a case moves — that makes those clauses true.

Do not treat “requirement-led” and “feature-led” as a choice. Tick the requirement *through* the feature narrative. Put exhaustive clause-by-clause audit in a comparison matrix or end-of-section references, not as the opening voice of every chapter.

For custom/government runs, see `workflows/general-proposal/SCAFFOLDS.md` → “Requirements covered by features.”

## W13b. Depth Follows The Bid Spine — Uneven On Purpose

Match depth to what the buyer and scoring rubric care about. The spine of the bid (primary outcomes, scored technical narrative, journey the TOR names) deserves operating detail and, when useful, a worked path. Peripheral hygiene modules stay shorter.

Do **not**:

- Expand every capability chapter to the same length.
- Add “sub-feature” inventories by default under every heading.
- Use writing-process labels as customer headings (`Frame`, `Scenario`, `Sub-feature hooks`).

Do:

- After a full draft, re-read against principles and deepen or cut selectively (general-proposal workflow: Principles review → `principles-review.md`).
- Prefer one strong spine example over many shallow ones.

## W13c. Official Voice For Government And E-Bidding Packs

Write as a formal submission to a public agency, not as product marketing or AI brochure copy.

Do **not**:

- Lead with metaphors (“spine”, “pile of cards”, “built for X”).
- Sound like a pitch deck (“seamless”, “unlock”, “empower”).
- Imply the bidder hosts production when the TOR assigns hosting to the buyer.

Do:

- Use the buyer’s own terms (e.g. Centralized Intelligence) as defined policy language, then state what the system does in plain operational English or Thai.
- Derive hosting, environments, and optional “better than TOR” extras from the pack (see general-proposal SCAFFOLDS).
- Address the project owner. Never explain scoring mechanics, “bonus points,” or writing-process rationale in the submission body.
- Keep document choreography invisible: do not tell the buyer what “this section describes,” which chapter owns a topic, what appears again later, or how the comparison matrix records it unless that navigation is necessary to understand a dependency.
- Check adjacent chapters for a structural fingerprint. Repeated generic headings such as “Objects,” “Key features,” “How it works,” and “Compliance anchor” should be replaced with subject-specific headings or removed.
- In feature tables, put sub-capabilities in an Includes (or equivalent) column — especially on the bid spine. Write full sentences for what the officer does; write Includes as concrete controls and rules, not keyword lists.
- Treat anti-AI cleanup as a presentation edit, not a scope edit. Before deleting a repeated-looking diagram, table, or passage, identify any unique commitment, branch, relation, interface term, security control, ownership boundary, or date and preserve it explicitly.

---

## W14. Section Titles: Describe the Business Outcome

A section title describes what the customer is buying for their business in the fewest words that remain specific.

**Rules:**
- Name the business outcome, not the product catalog category. "Trading-linked loyalty earning" beats "API Earning". "Member reward redemption" beats "Burning".
- Colon subtitles are fine when they sharpen the contract. "Tier Programme: member-facing mechanics" is appropriate. "Integration Architecture: Connecting {Customer}'s Back-End to Rocket CRM" should be trimmed — it combines two ideas; pick the specific one.
- Customer names and vendor names belong in the body, not in section titles. They add noise to the TOC without adding information to a reader scanning for what's covered.
- Avoid long verb phrases as titles. "How Rocket CRM handles earn-rate calculation" is a heading for a wiki article, not a proposal section — use "Earn-rate calculation: how it works" or simply "Earn-rate calculation".

---

## Proposal Quality Checklist

### Reading (when responding to a written requirements document)

- [ ] Are clauses cited by ID when answered?
- [ ] Is source language quoted verbatim where intent matters?
- [ ] Are explicit statements distinguished from implied or assumed requirements?
- [ ] Are silent, ambiguous, or self-contradictory areas of the source flagged?

### Understanding And Contextualization

- [ ] Is there a customer-primary glossary (definitions first; Rocket notes only where needed)?
- [ ] Where one customer term hides multiple platform patterns, are splits in glossary (or rare concept_unification), not duplicated 1:1 mappings?
- [ ] Where one customer term hides multiple platform patterns, are the patterns split and named?
- [ ] Are platform capability claims verified against the CRM Knowledge MCP and the local repo?
- [ ] Are external dependencies (APIs, partners, regulations) reality-checked before being promised?
- [ ] Are "asked for" and "offered beyond" capabilities clearly distinguished?

### Structuring

- [ ] Does vocabulary alignment lead the document, before any feature walkthrough?
- [ ] For every large cut or merge, do all unique commitments and technical semantics survive?
- [ ] Were semantic diagrams and mockups inventoried before/after rather than removed by appearance alone?
- [ ] Are peer modules comparable without forcing identical published headings or depth?
- [ ] Do compressed implementation matrices appear only where they add a new comparison view?
- [ ] Is data ownership and integration architecture placed in a single section and referenced?
- [ ] Where capabilities ship in stages, is the proposal sequenced by delivery phase?
- [ ] For requirements-driven proposals, does each requirement carry a fit status (Supported / Partial / New Development)?

### Writing — Core Structure

- [ ] Did you apply `CORE_WRITING_PRINCIPLES.md` before drafting?
- [ ] Does each section lead with an overview before detail?
- [ ] Are peer sections grouped by one dimension?
- [ ] Are sections MECE for the scope promised?
- [ ] Are flat lists kept at the same abstraction level?

### Writing — Platform Visibility

- [ ] Does every section describe what the system does, not only what it enables?
- [ ] Are sequence-dependent features presented through journey walkthroughs, without forcing journeys onto static controls or simple commitments?
- [ ] Are claims replaced with specific behavior, scope, examples, numbers, or limits?
- [ ] Do diagrams mirror the text instead of adding a second, disconnected story?

### Writing — Options And Trade-Offs

- [ ] Are real implementation choices shown as options?
- [ ] Are trade-off dimensions relevant to the buyer?
- [ ] Is the recommendation stated clearly?
- [ ] Does the reasoning reference the trade-off table?

### Writing — Proposal Scope

- [ ] Are all touchpoints, flows, channels, and operational roles covered?
- [ ] Are cross-cutting concerns handled across every relevant channel?
- [ ] Are dependencies cross-referenced instead of duplicated?
- [ ] Are unsupported, rare, risky, or fallback scenarios stated?

### Writing — Voice And Authenticity

- [ ] Does the writing sound like a systems architect, not a salesperson?
- [ ] Are filler phrases removed?
- [ ] Are section lengths allowed to vary based on real complexity?
- [ ] Are headings phrased as the reader's natural question where it helps orientation?
- [ ] Where flexibility or journey claims are central/scored, are they anchored with a customer-context worked path — without forcing an example into every section?
- [ ] Is the writing protocol invisible—no document choreography, recurring scaffold labels, or review/scoring mechanics in customer prose?
- [ ] Do adjacent chapters avoid an identical template fingerprint unless comparison genuinely benefits from it?
- [ ] Would a technical evaluator think "they have actually built this"?

## Sources

- `CORE_WRITING_PRINCIPLES.md` — pyramid structure, vertical logic, horizontal logic, MECE, same-level abstraction, layered depth, specificity, and explicit limitations.
- `.cursor/rules/15-crm-knowledge.mdc` — CRM Knowledge MCP retrieval workflow used by U3 to verify platform capability claims.
- Barbara Minto, *The Minto Pyramid Principle* — top-down structure, SCQA, vertical logic, horizontal logic, and MECE grouping.
- Style reference: Caltex Thailand Loyalty Platform Proposal — journey walkthrough pattern, options with trade-offs, layered depth, explicit limitations, systems architect voice, repeated subsection scaffold, closing implementation matrix, and worked-example anchoring.
- Style reference: Samitivej Loyalty Program Requirement Analysis — source clause citation, verbatim quoting of source language, vocabulary bridge and concept unification, pattern splitting (Pattern A vs Pattern B), reality-checking external APIs and commercial dependencies, fit-status tagging per requirement, source-of-truth data map, phase-based sequencing, and reader-question headings.
