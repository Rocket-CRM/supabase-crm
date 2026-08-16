# Core Writing Principles

## Purpose

These principles govern structured writing across Rocket materials: proposals, sales decks, feature explanations, internal docs, and agent responses.

Use this document when the task requires clear reasoning, hierarchy, grouping, or explanation. Use the format-specific documents only after this foundation:

- `PROPOSAL_WRITING_PRINCIPLES.md` for B2B SaaS proposals, RFPs, and long-form platform walkthroughs.
- `SALES_PRESENTATION_SLIDE_PRINCIPLES.md` for Rocket CRM sales and marketing slides.
- `SALES_FEATURE_COPY_PRINCIPLES.md` for catalog names and summaries.
- `CANONICAL_VIEW_COPY_PRINCIPLES.md` for pricing-sheet and features-summary shorthand (the jump from catalog → views).

Good structured writing lets the reader answer four questions quickly:

1. What is the main point?
2. How are the supporting ideas organized?
3. What belongs together, and what does not?
4. How much detail do I need to read before I understand the answer?

---

## 1. Lead With The Core Concept

Use pyramid structure: start with the controlling idea, then unfold the supporting detail below it.

The top idea changes by format:

| Format | Core concept |
|---|---|
| Proposal | What the platform does and how the reader's operation would work on it |
| Sales deck | The buyer problem, better approach, Rocket solution, or specific decision point |
| Feature explanation | The feature's purpose, contract, behavior, and limits |
| Sales feature copy (catalog) | The capability a merchant would buy, in 1–2 complete sales sentences |
| Canonical views (pricing / features summary) | The same intent, in one-breath sales shorthand |
| Technical explanation | The module responsibility, inputs, outputs, invariants, and failure modes |

Bad:

> The platform includes rewards, tiers, campaigns, customer profiles, dashboards, and AI.

Better:

> Rocket turns purchase activity into a customer profile, then uses that profile to run loyalty, rewards, segmentation, and automated next actions.

The better version gives the reader the frame first. The list can come later as proof.

This rule is recursive. Every section, subsection, paragraph, and bullet group should open with its answer or claim before evidence. A reader who skims only the opening lines should still know what each part is saying.

Bad — conclusion buried at the end:

> Many CRMs require separate tools for points, campaigns, and analytics. Operators end up reconciling data across systems. Customer profiles fragment across channels. Reporting takes days instead of minutes. Rocket consolidates these into a single platform so operators run loyalty, marketing, and analytics from one customer profile.

Better — answer first:

> Rocket runs loyalty, marketing, and analytics from a single customer profile. This removes the typical CRM problem: separate tools for points, campaigns, and analytics, fragmented profiles across channels, and reporting that takes days instead of minutes.

The "better" version lets a busy reader stop after the first sentence and still leave with the main point. The detail is there for readers who want it.

Quick test for any section: read only the first sentence of every paragraph. If the reader still understands the argument, the openers are doing their job.

For customer-facing proposals, the first sentence must state behavior, a deliverable, a decision, or an operating outcome. An opener such as “This section explains…” describes the document rather than answering the buyer and fails this test.

---

## 2. Preserve Vertical Logic

Every child point must directly explain, prove, decompose, or qualify its parent.

If a detail does not answer the parent's implied question, it belongs elsewhere or should be cut.

Example:

```
Parent: Omnichannel point collection
    Child: POS purchase earn
    Child: Online store earn
    Child: Marketplace claim flow
    Child: Receipt upload flow
```

Each child is a point-collection channel. The hierarchy is clean.

Mixed:

```
Parent: Omnichannel point collection
    Child: POS purchase earn
    Child: Marketing dashboard
    Child: AI recommendation
    Child: Customer retention
```

The children no longer elaborate the parent. They mix channel, interface, capability, and outcome.

---

## 3. Preserve Horizontal Logic

Peer items must be grouped by one dimension at a time.

Valid grouping dimensions include:

- By channel: POS, online store, marketplace, receipt upload, QR scan.
- By lifecycle phase: setup, earn, burn, reporting.
- By capability: points, tiers, rewards, missions, referrals.
- By audience: customer, marketer, operator, finance, IT.
- By system layer: channel, loyalty engine, profile, workflow, analytics.

Do not mix dimensions in one flat list.

Mixed dimensions:

```
1. Fuel stations (touchpoint)
2. Security (cross-cutting concern)
3. Merchant On-us (touchpoint)
4. Mobile app (channel)
```

Grouped by touchpoint:

```
1. Fuel stations
2. Merchant On-us
3. Merchant NFR
4. Online store
5. Rewards
```

Security can be handled inside each touchpoint, then summarized in a separate cross-cutting table.

---

## 4. Use MECE As A Structure Test

MECE means mutually exclusive and collectively exhaustive.

- Mutually exclusive: each idea belongs in one primary place. The reader should not feel the same point is being fully explained twice.
- Collectively exhaustive: the set covers the full scope promised by the parent. The reader should not finish the section asking about an obvious missing case.

MECE is a test, not a visual style. It applies to outlines, slide sections, feature lists, comparison tables, workflows, and checklists.

Good Rocket grouping:

> Convert -> Engage -> Activate

Each stage has a clear role:

- Convert: registration, point collection, unified profile, first-party data capture.
- Engage: tiers, rewards, missions, referrals, gamified campaigns.
- Activate: segmentation, churn prediction, personalized offers, automated campaigns.

Failure modes:

Overlapping (not mutually exclusive):

> Loyalty program / Points / Rewards / Tier benefits

"Loyalty program" contains the other three. The reader cannot tell whether to expect distinct topics or nested explanations of the same thing. Fix by either dropping the parent (`Points / Rewards / Tiers`) or making the parent a heading and the others its children.

Subtler overlap:

> Customer profile / First-party data / Purchase history / Channel preferences

"Customer profile" is the container; the rest are fields inside it. Same problem as above, just less visible.

Missing case (not collectively exhaustive):

> Earn channels: POS, online store

If the platform also supports marketplace, receipt upload, and QR scan, this list reads as a complete capability claim and undersells the product. The reader either takes it at face value or notices the gap and loses trust. Either list the full set, or scope the heading honestly: "Earn channels in scope for phase 1: POS, online store."

---

## 5. Cross-Reference Instead Of Duplicating

MECE does not mean topics cannot depend on each other.

If one section depends on another, name the dependency and point the reader to the full explanation. Do not repeat the full walkthrough in two places.

Cross-reference only when the dependency is non-obvious and long enough to justify the interruption. Do not use pointers to avoid explaining the primary operational story in the section where the buyer expects to find it.

Good:

> The earn and burn flows in this section depend on the Merchant Portal for partner registration, reward management, and transaction review. The Merchant Portal is covered in the next section.

This orients the reader without breaking structure.

### Compression safety: preserve unique meaning

Removing repetition is not the same as removing content. Two passages or visuals may look similar while carrying different semantics.

Before cutting or merging, identify whether each surface uniquely carries a requirement, commitment, branch, reverse path, actor, ownership boundary, interface field, data relation, control, date, or dependency. Remove the duplicate surface only when every unique item remains explicit in the survivor.

In technical documents, diagrams are content when they encode relationships or behavior. A prose summary is not automatically equivalent to a state diagram, ERD, sequence, or integrated timeline.

---

## 6. Keep Peer Items At The Same Abstraction Level

Flat lists should not mix category, feature, channel, outcome, UI detail, and implementation detail.

Mixed:

> Loyalty CRM / Points / AI / LINE / Increase retention / Dashboard

This mixes category, feature, technology, channel, outcome, and interface.

Same level by capability:

> Points / Tiers / Rewards / Missions / Referrals

Same level by outcome:

> Convert customers / Engage members / Activate data

Same level by channel:

> POS / Online store / Marketplace / Receipt upload / QR scan

Quick test: can the group be labeled with one noun phrase? If the label needs "and" or "miscellaneous," the list probably mixes abstraction levels.

Side-by-side rewrite. Take the mixed example:

> Loyalty CRM / Points / AI / LINE / Increase retention / Dashboard

The same items, re-sorted into valid groupings:

| Dimension | Items |
|---|---|
| Capability | Points, tiers, rewards, missions, referrals |
| Channel | LINE, SMS, email, push, in-app |
| Technology | AI segmentation, AI churn prediction, AI offer ranking |
| Interface | Operator dashboard, customer app, merchant portal |
| Outcome | Increase retention, lift basket size, recover churned customers |

Each row passes the noun-phrase test. Mixing rows back into one bullet list breaks it again.

Subtler mix:

> POS / Online store / Mobile app / Marketplace / Receipt upload

This looks like channels, but "Mobile app" is an interface that spans several of them — a customer can earn points in the app from an online order, a marketplace claim, or a receipt upload. The mix is invisible until a reader asks "where does the mobile app fit?" Fix by separating the dimensions:

> Channels: POS, online store, marketplace, receipt upload, QR scan
>
> Interfaces: customer mobile app, customer web, operator dashboard, merchant portal

The drift that's easiest to miss is usually one item that looks like a peer but actually cuts across the others.

**Do not “compress” a list by concatenating names.** Joining catalog or config labels with commas and semicolons (`Tier ladder, upgrade conditions, maintain mode`) is not sparse writing — it is a mixed-altitude dump. Compress by rewriting one sales sentence per buyer-recognizable capability. See `CANONICAL_VIEW_COPY_PRINCIPLES.md`.

---

## 7. Use Parallel Structure For Peer Points

Peer points should carry similar conceptual weight and grammar.

Weak:

```
1. Points can be earned at POS
2. Rewards
3. Customers receive LINE notifications
4. Dashboard analytics
```

Parallel by customer journey:

```
1. Customer earns points at POS
2. Customer redeems rewards in the app
3. Customer receives LINE notifications
4. Customer tracks tier progress
```

Parallel by operator capability:

```
1. Configure earn rules
2. Configure reward inventory
3. Configure LINE messages
4. Review campaign performance
```

The rule is not that every line must sound identical. The rule is that peers should be comparable.

---

## 8. Mix Levels Only When The Relationship Is Explicit

Do not mix abstraction levels in a flat list.

You may mix levels in a hierarchy, journey, matrix, architecture diagram, or system flow when the layout makes the relationship clear.

Allowed:

- Hierarchy: `Convert -> Engage -> Activate`, with example features under each stage.
- Journey: `Customer buys on Shopee -> claims points -> joins tier -> receives AI offer`.
- System diagram: `Purchase channel -> loyalty engine -> customer profile -> AMP workflow -> LINE message`.
- Matrix: online/offline rows against brand-owned/third-party columns.

The structure must show why the levels are different and how they relate.

---

## 9. Use Layered Depth

Write so different readers can stop at the right depth.

Common depth pattern:

```
Level 1: Overview or core concept
Level 2: Main parts, stages, or options
Level 3: Flow, examples, or evidence
Level 4: Edge cases, limits, configuration, or implementation detail
Level 5: Summary matrix or checklist
```

Executives should be able to read the overview and summary. Technical or operational readers should be able to find the deeper detail without guessing where it lives.

---

## 10. Avoid Fake Balance

Good structure does not require equal length.

If one topic is complex and another is simple, give the complex topic more space. Do not pad simple sections to make the outline look symmetrical.

Fake balance makes writing feel machine-generated because real systems have uneven complexity.

---

## 11. Specificity Creates Credibility

Replace vague claims with observable behavior, concrete scope, examples, numbers, or explicit limits.

| Vague | Specific |
|---|---|
| Supports multiple channels | Supports POS, online store, marketplace, receipt upload, and QR scan point collection |
| Real-time processing | Points calculate and return to the POS before the receipt prints |
| Flexible campaign management | Campaigns combine actions, conditions, and outcomes without code |
| Comprehensive reporting | Reports show points issued, rewards redeemed, transaction history, and campaign performance |
| Secure transaction processing | Staff-initiated transactions require OTP verification and duplicate checks |

Do not call something comprehensive if the scope can be listed. List the scope.

---

## 12. State Limits When They Were Raised

A limitation is only worth writing when one of these two conditions is true:

1. **The customer explicitly raised the constraint** — in their TOR, Q&A, brief, or email. The constraint is real and the reader expects it to be addressed.
2. **The constraint is operationally critical** to delivering the feature — e.g. "POS integration depends on the merchant's POS exposing a REST event webhook." Omitting it would mislead the customer about what's needed to go live.

In all other cases, omit. A list of limitations the customer never asked about reads as a liability register, not as consulting. It makes the proposal feel AI-generated and erodes confidence in the claims that matter.

**Never write a limitation to fill a coverage slot.** The old rule "state limits honestly" led to every section ending with a Limitations block. Strict polarity replaces it: no limitation unless the customer raised it or it's operationally critical.

**Unsupported claims are omitted, not demoted.** If you cannot support a capability claim with evidence, remove it or rephrase as a scope statement ("This proposal does not cover …"). Do not convert it to a limitation — that is still an assertion about the product, just a negative one.

---

## Core Checklist

Checking every box does not make a draft sendable. For general proposals, pair this checklist with the excerpt-based cold-reader review in `workflows/general-proposal/SCAFFOLDS.md`.

### Core Concept

- [ ] Does the section lead with the controlling idea before detail?
- [ ] Does every subsection and paragraph open with its answer or claim, not bury it at the end?
- [ ] Can the reader understand the point from the headings and paragraph openers alone?

### Vertical Logic

- [ ] Does every child point directly explain, prove, decompose, or qualify its parent?
- [ ] Are misplaced details moved or cut?

### Horizontal Logic

- [ ] Are peer items grouped by one dimension at a time?
- [ ] Can each group be labeled with one clear noun phrase?

### MECE

- [ ] Is each major idea explained in one primary place?
- [ ] Are obvious gaps covered?
- [ ] Are dependencies handled with cross-references instead of duplicated walkthroughs?
- [ ] For every cut or merge, do all unique commitments, controls, relations, branches, and dependencies survive?

### Abstraction Level

- [ ] Do flat lists keep peer items at the same abstraction level?
- [ ] Are mixed levels only used in hierarchies, journeys, matrices, or diagrams where the relationship is explicit?
- [ ] Do peer bullets use parallel grammar and conceptual weight?

### Depth And Credibility

- [ ] Does the structure support both scanning and deeper reading?
- [ ] Does real complexity determine section length?
- [ ] Are vague claims replaced with concrete behavior, scope, examples, numbers, or limits?

## Sources

- Barbara Minto, *The Minto Pyramid Principle* — top-down structure, vertical logic, horizontal logic, and MECE grouping.
- Internal proposal and slide principles — Rocket-specific applications of structured writing, same-level grouping, journey walkthroughs, concrete system behavior, and explicit limitations.
