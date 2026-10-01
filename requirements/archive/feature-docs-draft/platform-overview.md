# B2C CRM — Platform Overview

Three modules. One customer profile. One action system. One data layer.

| Module | What It Does |
|---|---|
| **Loyalty** | Convert customers into members, engage them with points/tiers/missions/rewards, collect data from every purchase channel |
| **Marketing Automation (AMP)** | Automate campaigns with rule-based workflows and AI agents that decide what to send, to whom, and when |
| **Customer Service (CS)** | Handle customer conversations across 11 channel types with AI agents, rules automation, and human agents |

A purchase triggers loyalty earning, an AMP workflow, and becomes queryable by CS when the customer asks about it. A CS conversation can award loyalty points and inform AMP to suppress promotions for unhappy customers. AMP workflows execute loyalty actions and deliver content through CS channels. The modules share the same customer identity, the same action catalog, and the same content library.

---

## 1. The Customer Lifecycle

Each stage maps to a module. A customer progresses through all four:

| Stage | Module | What Happens |
|---|---|---|
| **Convert** | Loyalty | Register via LINE or phone OTP. Build unified profile. Earn points from any channel — POS, e-commerce, marketplace, receipt upload, QR scan. |
| **Engage** | Loyalty + AMP | Tier progression, missions, referrals, check-in streaks. AMP sends automated welcome series, birthday offers, re-engagement campaigns. |
| **Activate** | AMP + AI | AI agent inside workflows evaluates full customer context (tier, purchases, sentiment, conversations). Decides: act (send offer), wait (wrong timing), or skip (no intervention needed). |
| **Support** | CS | Customer asks a question on any channel. AI resolves autonomously or escalates to a human agent with full context. Resolution can trigger loyalty actions (bonus points, voucher). |

---

## 2. How the Modules Connect

### Data Flows

| From → To | What Flows | Example |
|---|---|---|
| **Loyalty → AMP** | Events: purchase, tier upgrade, mission complete, inactivity | Purchase event triggers a post-purchase follow-up workflow |
| **AMP → CS** | Campaign context on conversations | Customer asks about an offer they received; CS agent sees the campaign details |
| **CS → Loyalty** | Loyalty actions from within conversations | AI agent awards 500 courtesy points after resolving a shipping complaint |
| **CS → AMP** | Sentiment and resolution data | AMP condition: "skip if customer had a negative CS interaction in the last 7 days" |
| **AMP → Loyalty** | CRM actions executed by workflows | Workflow assigns "VIP Event Attendee" tag after purchase threshold met |

### Shared Capabilities

Five capabilities span multiple modules. Each is configured once and available everywhere it applies.

| Capability | What It Is | Modules |
|---|---|---|
| **Action catalog** | Single registry of actions: award points, send messages, create vouchers, assign tags. Register once, use across CS AI, AMP AI, and rule-based workflows. | All |
| **Content library** | Quick replies, media, links, rich content. Same content used in CS responses and AMP messages. | CS, AMP |
| **Action macros** | Multi-step action templates with three-layer guardrails (system ceiling → caller constraints → runtime limits). | CS, AMP |
| **Channel connections** | One credential (LINE OA, Shopee, etc.) can serve AMP messaging and CS conversations simultaneously. Scope array controls which modules access which credential. | CS, AMP |
| **Translation system** | Four languages (EN, TH, JA, ZH). Fallback chain: requested → merchant default → English. Covers member-facing content and UI text. See [translation-system.md](translation-system.md). | All |
| **Admin role UI config** | Per-role settings beyond permissions: custom default landing page (redirect on login), sidebar visibility toggle, hidden menu module categories, and a configurable floating bottom navigation bar (icon + label + route per button). Enables purpose-built admin UIs — e.g. a frontline field role that sees only a floating shortcut bar with no sidebar. Configured in `admin_roles.config`. | All |

### Customer Identity

| Context | Identity | How It Works |
|---|---|---|
| Loyalty | Member account | Authenticated via LINE or phone OTP during registration |
| CS | Contact record | Resolved from platform identity — LINE user ID, phone number, email, Shopee chat ID |
| Bridge | CS contact → Loyalty member | Nullable link. When set, CS AI can query tier, points balance, purchase history, tags, personas. When unset, CS operates with channel data only. |

---

## 3. Loyalty

Turn every customer into a known, engaged, rewarded member — regardless of where they buy.

Most loyalty platforms cover one purchase channel. This one covers online stores, physical POS, marketplaces (Shopee, Lazada, TikTok Shop), and distributor channels (receipt upload, QR scan). The 2×2 matrix: online/offline × 1st party/3rd party — no customer is invisible.

| Feature | What It Does | Guide |
|---|---|---|
| Points & Wallet | Double-entry ledger. Points (fungible) and tickets (non-fungible per type). Earn factors, multipliers, expiry, reversals at original rates. | [currency.md](currency.md) |
| Tiers | Ranking with skip-level upgrades, multi-path qualification (points OR spend OR orders), maintain-or-downgrade deadlines, five window types, burn rate conversion, persona-based structures. | [tiers.md](tiers.md) |
| Rewards | Catalog with 4-dimension dynamic pricing (tier × persona × user type × tags). Always picks the customer-favorable price. Promo code distribution, stock control, four fulfillment methods, Shopify discount sync. | [rewards.md](rewards.md) |
| Missions | Standard (all conditions in parallel, AND logic) and milestone (sequential levels with waterfall carry-over). Condition types: purchase, points, referral, form. Auto/manual join and claim. Reset frequency. | [missions.md](missions.md) |
| Tags & Personas | Two-layer classification. Persona = one per customer (business identity). Tags = unlimited (behavioral attributes). Both feed eligibility, pricing, campaign targeting. | [tags-and-personas.md](tags-and-personas.md) |
| Referral | Dual rewards (inviter + invitee). Trigger on signup or first purchase. Configurable limits per period per user type. Referrals count toward mission progress. | [referral.md](referral.md) |
| Activity-Based Earning | Image upload → admin review → currency via 2D matrix (activity type × category). Custom field definitions. Frequency limits. | [activity-based-earning.md](activity-based-earning.md) |
| Purchase Transactions | Append-only ledger (refunds create new records, never modify originals). Currency award triggers. E-commerce multi-status mapping. | [purchase-transactions.md](purchase-transactions.md) |
| Check-in | Daily check-in with streak-based escalating rewards. | [checkin.md](checkin.md) |
| Stored Value Cards | Prepaid card balance management. | [stored-value-cards.md](stored-value-cards.md) |
| Forms & Profile | Default + custom fields, conditional visibility, PDPA consent, address management. | [forms.md](forms.md) |
| Store Classification | Three-tier hierarchy (category → attribute → sub-attribute). Attribute sets group stores for business rule targeting. | [store-classification.md](store-classification.md) |
| Marketplace Integration | Shopify, Lazada, Shopee, TikTok Shop. Order sync, order claim, reward distribution. | [marketplace-integration.md](marketplace-integration.md) |
| Authentication | LINE Login + phone OTP. Multi-method auth per merchant. Progressive profiling. Custom JWT. | [authentication-and-signup.md](authentication-and-signup.md) |

---

## 4. Marketing Automation (AMP)

Two engines on the same workflow canvas: rule-based (if X then Y) and AI agent (given a goal, decide per customer).

### Rule-Based Workflows

| Aspect | Details |
|---|---|
| **Triggers** | Purchase, tier upgrade, mission complete, signup, tag change, birthday, inactivity, audience entry/exit, form submission. Auto-derived from workflow conditions. |
| **Nodes** | Condition (branch on customer data), Wait (duration or time), Message (LINE/SMS/Email), Action (CRM operations), Agent (AI decision) |
| **Conditions** | AND/OR groups across purchases, wallet, tiers, tags, forms, custom fields. Time-aware. True/false branching. |
| **Execution** | Per-customer journeys. Immutable event log. Delivery funnel: sent → delivered → opened. Duplicate prevention. Exit conditions. |

### AI Agent Node

| Aspect | Details |
|---|---|
| **Input** | Full customer context pre-fetched: profile, purchases, tier, tags, past campaigns, constraints |
| **Decision** | ACT (select and execute an action), WAIT (defer to better timing), or SKIP (no intervention needed) |
| **Goals** | What to optimize: repurchase rate, churn reduction, AOV increase. Multiple goals with weights. |
| **Constraints** | Budget limits, frequency caps, per-action guardrails |
| **Measurement** | Attributes business outcomes (purchases, tier upgrades) to agent actions |

### Supporting Capabilities

| Capability | Details |
|---|---|
| **Audiences** | Dynamic (condition-based, auto-updating) and manual (explicit lists). Trigger workflows on entry/exit. Use as condition filters. |
| **Actions** | Award points/tickets, create vouchers, assign/remove tags, change persona, adjust earn factors, send LINE/SMS/Email, manage audience membership |
| **Messaging** | Unified delivery across LINE, SMS, Email. Templates with dynamic variables. Delivery tracking. Rate limiting. |
| **Analytics** | Workflow funnels, message delivery rates, AI agent ACT/WAIT/SKIP distribution, outcome attribution, A/B comparison |

→ Guides: [amp-workflows.md](amp-workflows.md), [amp-ai-decisioning.md](amp-ai-decisioning.md)

---

## 5. Customer Service (CS)

Three operational levels work simultaneously on every conversation:

| Level | What It Does | When It Applies |
|---|---|---|
| **AI Agent** | Autonomous resolution: intent detection → procedure execution → marketplace/loyalty actions → response in brand voice | Every conversation. Resolves the majority without human involvement. |
| **Rules Engine** | Deterministic if/then: auto-reply, auto-assign, auto-tag, auto-escalate based on keyword/intent/sentiment triggers | Runs alongside AI and human agents for predictable automations. |
| **Human Agent** | Complex/sensitive cases. AI-augmented: draft replies, conversation summaries, knowledge copilot, action suggestions, real-time translation. | Escalated from AI or assigned via rules/routing. |

### Two Modalities

**Chat** — 10 channel types: LINE, WhatsApp, Facebook Messenger, Instagram DM, Shopee Chat, Lazada Chat, TikTok Chat, Email, Web Widget, SMS.

**Voice** — Phone calls with real-time AI: speech-to-text → reasoning → text-to-speech. Same knowledge base, procedures, and actions as chat. Inbound + outbound.

### AI Agent Capabilities

| Capability | Details |
|---|---|
| **Intent** | Automatic detection, entity extraction (order numbers, platform, product names), multi-turn tracking, topic change recognition |
| **Knowledge** | Semantic search across uploaded docs, website crawls, product catalogs. Gap detection surfaces unanswered questions. Custom answers override AI for specific queries. |
| **Procedures (AOPs)** | Per-intent playbooks. Three flexibility modes: strict (compliance — follow exactly), guided (standard — adapt order/wording), agentic (advisory only). Automatic versioning. |
| **Marketplace actions** | Order lookup, cancel, refund, stock check, price check, product search, promotion check, shipping status — across Shopee, Lazada, TikTok, Shopify |
| **Loyalty actions** | Award points, create vouchers, check status, assign tags, update persona — via CRM bridge |
| **Brand voice** | Tone/formality/terminology config. Forbidden topics. Escalation triggers. Per-procedure overrides. Per-action constraints. Hallucination verification step. |
| **Customer memory** | Auto-extracted after resolution. Persists across sessions. Categories: preferences, issues, outcomes. Expiration and erasure per PDPA. |

### Human Agent Workspace

| Capability | Details |
|---|---|
| **Unified inbox** | All channels in one view. Filters: status, channel, assignee, team, priority, tags. Routing: round-robin, least-busy, skill-based. Collision detection. |
| **AI live assist** | Draft replies (edit/approve/discard), escalation summaries, knowledge copilot sidebar (natural language questions → sourced answers), action suggestions, real-time translation |
| **Tickets & SLA** | Lifecycle: New → Open → In Progress → Waiting → Resolved → Closed. Response/resolution targets. Business hours. Breach escalation. Multi-conversation tickets. |
| **Teams** | Team structure, skill-based routing, agent status (online/away/offline), concurrent conversation limits, supervisor view |
| **Quality** | Auto-QA scorecards. Watchtower: always-on monitoring with natural language criteria. CSAT surveys. Intent/sentiment analytics. AI confidence tracking. |

→ Guides: [cs-conversations.md](cs-conversations.md), [cs-knowledge-base.md](cs-knowledge-base.md), [cs-channels.md](cs-channels.md)

### Planned Guides

| Feature | Covers |
|---|---|
| CS AI System | Knowledge library, customer context, memory, reasoning, guardrails, procedures, copilot |
| CS Actions | Marketplace actions, CRM bridge, custom API builder, action governance |
| CS Unified Inbox | Ticket lifecycle, views/filters, agent workspace, supervisor, collision detection |
| CS SLA Management | SLA policies, business hours, breach escalation |
| CS Rules Engine | Deterministic if/then automation |
| CS Live Assist | Draft replies, summaries, knowledge copilot, translation |
| CS Analytics & QA | Metrics, Watchtower, auto-QA, CSAT |
| CS Voice | Voice AI, STT/TTS, inbound/outbound, recording, transfer |
| Resource Content | Shared content library: quick replies, media, links, rich content |
| Action Macros | Multi-step action templates with three-layer guardrails |

---

## 6. AI Across the Platform

AI is a capability layer, not a module. It runs through all three modules with shared infrastructure.

| Where | What It Does |
|---|---|
| CS autonomous agent | Handles conversations end-to-end: intent → knowledge → procedure → actions → response |
| CS voice agent | Same reasoning as chat. Different orchestration for sub-second voice latency. |
| CS live assist | Augments human agents: drafts, summaries, copilot, suggestions, translation |
| CS quality | Post-resolution: auto-QA scoring, sentiment, gap detection, Watchtower monitoring |
| AMP decisioning | Per-customer marketing decisions inside workflows: act/wait/skip with goal optimization |
| Loyalty pricing | 4-dimension matching (tier × user type × persona × tags) for dynamic reward point costs |

CS and AMP AI share the same action catalog, content library, and customer context. A CS conversation that reveals frustration feeds into AMP's decision context — the AI agent in a workflow can account for recent service interactions when choosing whether to send a promotion.

---

## 7. Audience Entry Points

Each audience should start reading from a different place. The platform overview (this doc) orients everyone; the feature guides go deep.

| Audience | Start Here | Then Read |
|---|---|---|
| **Marketing** | This doc: Sections 1-2 (lifecycle + connections) for positioning. Section 3-5 prose intros for module value props. | Individual guides: Section 1 (Overview) and Section 6b (For Marketing) in each. |
| **Customer Success** | This doc: Section 2 (connections) for FAQ answers. Module sections for feature inventory. | Individual guides: Section 6a (For Customer Success) for onboarding scripts and troubleshooting. |
| **Product** | This doc: Section 2 (connections + shared capabilities) for dependency mapping. Section 6 (AI) for cross-module capabilities. | Individual guides: Section 1 (Overview) for orientation, Section 8 (Related Features) for dependencies, Section 3 for config inventory. |
| **Testing** | This doc: Section 2 (data flows) for cross-module test scenarios. | Individual guides: Section 6c (For Testers) for config→behavior mappings, Section 7 (Business Rules) for assertions. |

### Cross-Module Test Scenarios

| Scenario | Verify |
|---|---|
| Purchase → Loyalty → AMP | Points earned → tier evaluated → workflow triggered → message sent |
| CS → Loyalty bridge | AI queries tier/points → awards courtesy points → wallet updated |
| AMP → content library | Workflow sends shared resource → channel-specific formatting applied |
| Identity linking | CS contact linked to loyalty member → AI sees full loyalty context |
| Action catalog consistency | New action registered → available in CS AI, AMP AI, macros |
| Voice ↔ chat parity | Same procedure via chat and voice → same resolution, same actions |

### Onboarding Sequence

1. **Loyalty first** — tiers, earning rules, reward catalog. Members need something to earn before automation or service add value.
2. **Connect channels** — LINE OA, marketplace shops, Shopify. Connections serve both AMP and CS.
3. **Enable AMP** — First workflows: welcome series, post-purchase follow-up, birthday campaign.
4. **Enable CS** — Knowledge base articles, procedures for top intents, brand voice. Turn on AI per channel.

### Common Questions

| Question | Answer |
|---|---|
| CS without Loyalty? | Yes. Identity bridge is nullable. AI resolves with channel data + knowledge base. No CRM bridge errors. |
| Loyalty without CS? | Yes. Members interact through the loyalty app. No CS dependencies. |
| Loyalty without AMP? | Yes. Loyalty events don't fail when no workflows exist. |
| AMP without Loyalty? | No. AMP triggers on loyalty events and executes loyalty actions. |
| AMP without CS? | Yes. Messages deliver independently of CS inbox configuration. |
| How does AI know the customer? | CS: queries loyalty via CRM bridge when identity is linked. AMP: full customer profile pre-fetched from data layer. |
| Multiple channels, same customer? | One profile. LINE, phone, Shopee Chat — same conversation history and context. |
