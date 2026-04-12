# Samitivej CRM Center — Loyalty Platform Proposal

---

## Executive Summary

**Four pillars transforming Samitivej's patient loyalty — from fragmented systems to a unified, intelligent platform.**

| Objectives | Current State | Future State | Business Impact |
|---|---|---|---|
| **Unified Member Types** | Managed across HIS, insurers, HR — no automated benefit resolution when types overlap | 6 types on one profile; HIS queries platform → best benefit auto-selected | One API call resolves right discount at every visit |
| **Unified Privileges & Packages** | eCoupons, entitlements, packages follow different workflows per channel; no single patient wallet | All privileges in one wallet with QR. Package purchase auto-issues all included items | Buy → receive → use → track, digitally, across every channel |
| **Omni-Channel Coin Economy** | Hospital visits, marketplace, online engagement disconnected — no shared currency | Single coin balance from all channels: hospital, Shopee, E-Commerce, content, behavior | Every interaction measurable and rewardable |
| **Intelligent Marketing** | Campaigns manual, limited personalization at scale | Rule-based journeys + AI Decisioning — a personal marketing expert per patient | Periodic manual → continuous intelligent engagement |

---

## Platform Differentiation

| Deep Functionality | Hospital-Scale Architecture | AI Decisioning |
|---|---|---|
| **85% TOR** covered by standard modules — coin, wallet, privileges, tiers, member types, missions, referrals, forms, automation, multi-language | **99.9% uptime** guaranteed | First globally deployed AI for **mass retention marketing** in loyalty |
| **15%** = integration adapters (HIS, Well SSO, Payment) + Samitivej config | **10,000+ concurrent users** | AI evaluates each patient individually — not segment rules |
| Faster time-to-market, lower risk — **not a one-off custom build** | **< 50ms** wallet/eligibility queries | Learns from outcomes: which actions drive return visits, which offers convert |
| Continuous product improvements — platform evolves after delivery | **< 1 second** earn end-to-end | Guardrails: budget caps, frequency limits, action whitelist, human override |
| | **10,000+** flash reward concurrency | Transforms marketing from campaign planning to **continuous per-patient engagement** |

---

## Technical Architecture

**Event-driven, real-time, durable — built for hospital scale. Two-layer separation ensures reporting never impacts transactions.**

| External Systems → | API Gateway → | Core Services → | Event Processing → | Data Layer → | Analytics Layer |
|---|---|---|---|---|---|
| HIS / Data Center | Load Balancer | Wallet Service | Apache Kafka | PostgreSQL | Analytics Database |
| Well App | WAF | Tier Engine | CDC (Debezium) | Redis Cache | Dashboard Engine |
| LINE | Rate Limiting | Privilege Service | Temporal (Durable) | Object Storage | Report Generator |
| Shopee / Lazada | TLS 1.3 | Auth Service | Scheduled Jobs | | |
| Website | | Marketing Automation | | | |
| Payment Gateway | | | | | |

**Why this matters:** Kafka streams every change in real time (coins before patient leaves counter). Temporal guarantees workflow completion even through restarts. Redis delivers sub-50ms eligibility answers to HIS. Analytics runs independently — never impacts real-time operations.

---

## Omni-Channel Coin Earning

**Patients earn coins from every interaction with Samitivej — all crediting one wallet, regardless of channel.**

| Channel | How Coins Are Earned | Example |
|---|---|---|
| **Hospital visit** | HIS sends purchase event after payment → earning engine applies rules | OPD 3,000 THB → 45 coins (Gold: 1.5× per 100 THB) |
| **Shopee / Lazada** | Order matched via phone, OrderSet code, or patient self-claim | Health package 5,990 THB → 60 coins |
| **Hospital E-Commerce** | Purchase event via API → coins credited on confirmation | Supplement order 1,200 THB → 12 coins |
| **Well App** | Package purchased via Rocket backend → coins credited immediately | Executive Checkup 14,500 THB → 217 coins (Platinum) |
| **LINE MyShop** | Webhook triggers earn calculation | Product 800 THB → 8 coins |

**Configuration rules — who earns what:**

| Rule | Who Qualifies | What They Receive |
|---|---|---|
| Base earn rate | All members | 1 coin per 100 THB spent |
| Higher-tier bonus | Gold, Platinum | Multiplied rate (1.5× or 2×) |
| Department special | Visiting a specific department | Bonus multiplier for that visit |
| Weekend promo | Any member on Sat–Sun | 2× bonus during campaign dates |
| New branch launch | Members at a specific branch | 3× bonus for launch period |

**Stacking:** Compound or highest-only — single toggle per campaign. **Caps:** Max coins/transaction, min amount, frequency limits. **Delayed award:** Optional hold period (e.g. 24h) to prevent earn-then-cancel.

---

## Behavioral & Content Earning

**Beyond purchases — patients earn coins from health content engagement and activities, driving loyalty between hospital visits.**

| Activity | How It Works | Coins |
|---|---|---|
| **Read health article** | Logged-in patient scrolls past 75% of article on website | 5 |
| **Share on LINE** | Share via LINE dialog — confirmed delivery via LIFF API | 10 |
| **Complete survey** | Post-visit NPS, rating, open text. Responses auto-enrich profile and trigger follow-up journeys (low NPS → service recovery) | 50 |
| **Complete health assessment** | Pre-visit questionnaire or lifestyle assessment form | 30 |
| **First purchase** | Complete first package purchase through any channel | 100 |
| **Invite a friend** | Referral code shared → friend registers | 200 |
| **On-site gamification** | Complete department-specific tasks (visit 3 depts, attend wellness workshop) | 500 |

Patient must be logged in for attribution. Anonymous activity cannot be tracked.

---

## Coin Wallet, Expiry & Transfer

**One wallet, one balance — visible across Well App, LINE, and website in real time.**

**What the wallet displays:**
- Current coin balance (real-time, cached in Redis for < 50ms reads)
- Full transaction history with source: "45 coins from OPD visit on 15 Mar," "200 coins used for Starbucks privilege"
- Upcoming expirations with countdown
- Burn rate context: "Your coins are worth 0.50 THB each (Gold tier)"

**Three expiry modes:**

| Mode | Example |
|---|---|
| Days after earn | Each batch expires 365 days after earning |
| Fixed calendar date | All coins expire 31 December each year |
| End of period | Coins earned in Q1 expire 31 March |

Advance notifications: 30, 7, and 1 day before (configurable per channel). Daily scheduled expiry processing.

**Coin transfer / partner points:** Purchase-based earning from Shopee/Lazada ready immediately. Direct transfer endpoints (The1, M Card, K Point) technology-ready — activated when partnerships signed. Per-partner conversion rates configurable.

---

## [MOCKUP] Wallet Screens

**Wallet — Coin History, Balance, and Quick Actions**

[MOCKUP PLACEHOLDER — insert 2-3 wallet screen mockups: (1) Coin History with multi-channel earn events, (2) Wallet Main with balance, burn rate, quick actions, (3) Wallet with expiry countdown]

---

## Privilege System — Unified Engine

**Every type of benefit a patient receives — earned, purchased, auto-issued, or gifted — runs through one privilege engine. Any new type is configured, not developed.**

| Samitivej Term | Platform Mode | Category |
|---|---|---|
| eCoupon (single-use) | Single-use privilege | Consumable |
| eCoupon (multi-use / Entitlement) | Multi-use with per-use deduction | Consumable |
| Package mandatory coupon (คูปองบังคับ) | Auto-issued via package bundle | Consumable |
| Package elective coupon (คูปองเลือก) | Patient-selected from package pool | Consumable |
| Seasonal coupon (birthday, anniversary) | Triggered by marketing journey | Consumable |
| Reward from coin redemption | Redeemed from catalog | Consumable |
| Partner reward (Starbucks, etc.) | Partner code pool | Consumable |
| Physical gift | Shipping fulfillment | Consumable |
| Flash reward (Dyson, wellness retreats) | Time-limited, stock-limited | Consumable |
| **Standing discount (ส่วนลดใช้ไม่จำกัด)** | **Standing Benefit — never depleted, queried by HIS** | **Non-consumable** |

**Why unified matters:** Shared eligibility resolution, dynamic pricing, stock management, and audit trail across all types. Future privilege types are configuration — zero development.

---

## Privilege Lifecycle — Eligibility & Pricing

**Every privilege has two independent layers: WHO can receive it, and HOW MANY coins it costs.**

**Lifecycle stages:**

| Stage | What Happens |
|---|---|
| **Trigger** | Coin redemption, HIS event (post-visit), package purchase (bundle), marketing journey (birthday), or admin manual issuance (VIP gesture) |
| **Catalog** | Privilege definition with type, conditions, stock, scheduling |
| **Eligibility** | WHO — conditions based on tier, member type, tags, segment. Can restrict to Gold+ or Corporate Executive only |
| **Pricing** | HOW MANY coins — dynamic by same dimensions. Starbucks voucher: 400 coins (Silver), 250 coins (Platinum). System applies most favorable price |
| **Issuance** | Privilege appears in patient wallet with QR code, conditions, and expiry |
| **Usage** | Single-use: one redemption. Multi-use: per-use deduction with remaining counter |

**Visibility modes:** Public (patient browses and redeems), Admin-only (staff issues, patient sees after), Campaign (only matching patients see it).

---

## Multi-Use Entitlements & Auto-Issuance

**Multi-use entitlements are critical for hospital services — physiotherapy sessions, recurring treatments, package inclusions.**

**How a 5-session physiotherapy entitlement works:**
1. Patient arrives for session #3 → staff records in HIS
2. HIS sends `service_delivered` event → platform validates: exists? not expired? uses remaining? no concurrent use?
3. Database-level row lock acquired → one use deducted → remaining: 2/5
4. Patient sees: "เหลือ 2/5 ครั้ง ●●●○○"

| Edge Case | Handling |
|---|---|
| Branch transfer | Entitlement follows patient across branches |
| Concurrent use at 2 locations | Row locking — second request fails, must retry |
| Doctor grants bonus sessions | HIS sends adjustment event → uses added |
| Package swap | Old cancelled (remaining logged), new issued with adjusted balance. Full audit trail |
| Expiry extension | Admin extends with reason. Approval required for > 30 days |

**Auto-issuance rules — configured once, execute automatically:**

| HIS Event | Privileges Auto-Issued |
|---|---|
| Executive Checkup purchased | 1× blood test + 1× X-ray + 1× consultation + 3× café 100 THB |
| OPD visit completed | 1× café 50 THB voucher (retention) |
| Dermatology visit | 1× 10% off next dermatology within 30 days |
| Post-surgical discharge | 1× follow-up + 5× pharmacy discount + 3× parking |

---

## Flash Rewards — Limited Drops

**Premium items released in small quantities create anticipation, excitement, and virality. Proven at scale with Pop Mart — 10,000+ concurrent users competing for limited stock.**

- **Mechanism:** Pre-loaded limited stock → countdown timer → first-come-first-served with fairness guarantee
- **Concurrency:** Platform handles 10,000+ simultaneous users without degradation
- **Anti-fraud:** Rate limiting, one-per-user rules, velocity checks
- **For Samitivej:** Exclusive checkup packages, premium wellness retreats, Dyson hair dryers, Apple products, luxury partner items
- **Impact:** Drives app engagement, creates buzz, generates LINE/social sharing

---

## [MOCKUP] Privilege Screens

**Privilege Wallet, Detail, Catalog & Flash Rewards**

[MOCKUP PLACEHOLDER — insert 3-4 privilege mockups: (1) Coupons & Entitlements tab with progress bars, (2) Privilege Detail with QR code and 3/5 counter, (3) Redeem Catalog with tier-specific pricing, (4) Flash Reward countdown page]

---

## Health Package Layer & Online Store

**Packages are bundles built on top of the privilege system. A purchase triggers automatic issuance of all included items.**

**Three benefit categories per package:**

| Category | What Happens | Example (Executive Checkup) |
|---|---|---|
| **Mandatory** | Auto-issued to wallet on purchase | Blood test + X-ray + consultation + 3× café vouchers |
| **Elective** | Patient picks N from pool: "เลือกสิทธิ์ 3 จาก 8" | Choose from: Spa, dental, eye exam, massage, derma, nutrition, physio, pharmacy |
| **Standing benefits** | Unlimited-use discounts activated for contract period | 15% off OPD, 10% off pharmacy for 1 year |

**5 purchase channels with different earn rates to incentivize preferred channels:**

| Channel | Flow | Earn Rate |
|---|---|---|
| **Well App** | Browse → pay via Rocket backend → auto-issue | Higher (e.g. 2 coins / 100 THB) |
| **Hospital E-Commerce** | Website purchase → API → issue | Higher (lowest GP for hospital) |
| **Shopee / Lazada** | Buy → email voucher → hospital verification → issue | Standard (1 coin / 100 THB) |
| **Hospital Counter** | HIS processes → event → auto-issue | Standard |
| **LINE** | Staff sends E-Commerce link → patient buys | Same as E-Commerce |

**Online store features:** Category filters, gender/age/price/branch filters, promo badges, coin discount toggle with live net-price calculation, payment gateway, instant confirmation with privileges issued + coins earned.

---

## [MOCKUP] Package Screens

**Package List, Detail, Checkout & Purchase Success**

[MOCKUP PLACEHOLDER — insert 4 package flow mockups: (1) Package List with category filters and promo badges, (2) Package Detail with service breakdown and coin discount slider, (3) Checkout with order summary, (4) Purchase Success with privileges issued]

---

## 6 Member Types — One Patient Profile

**Six distinct member types coexist. Each has its own tier structure with independent rules. Precedence engine auto-resolves the best benefit at every hospital visit.**

| Member Type | Tier Structure | Tier Basis | How Assigned |
|---|---|---|---|
| **VIP (Star)** | Connex / Cheva / VIP Insurance | Hospital assigns by contract | Admin assignment |
| **Paid** | Based on cumulative package spend | 50k / 100k / 200k THB | Purchase triggers |
| **Engagement** | Silver / Gold / Platinum | Spending + visits + behavior | Auto-evaluated |
| **Corporate** | Executive / General / Other | Per company contract | HR roster import |
| **Insurance** | Premium / Standard / Basic | Insurer's policy tier | Auto from HIS |
| **Exclusive Partner** | Gold / Platinum (per partner) | Partner's own criteria | Partner API |

**Precedence example — Patient คุณสมชาย holds 5 types:**

| Member Type | Level | OPD Discount |
|---|---|---|
| VIP (Star) | Connex | 30% |
| Corporate | CRC Executive | 25% |
| Insurance | AIA Premium | 20% |
| Paid | Divine Elite | 15% |
| Engagement | Gold | 5% |

**→ Precedence engine returns: 30% (VIP Connex). Applied automatically. Every decision audit-logged.**

---

## Engagement Tiers — Rewarding Loyal Patients

**Spending from ALL channels counts — hospital, marketplace, and E-Commerce. Tiers unlock better earn rates, lower privilege costs, and exclusive benefits.**

| Tier | Qualification | Earn Rate | Burn Rate | Key Benefits |
|---|---|---|---|---|
| Silver | Default | 1 coin / 100 THB | 0.25 THB/coin | Base catalog access |
| Gold | 50,000 THB / 12 months | 1.5 coins / 100 THB | 0.50 THB/coin | 5% OPD, reduced privilege pricing |
| Platinum | 150,000 THB / 12 months | 2 coins / 100 THB | 1.00 THB/coin | 10% OPD, priority booking, exclusive privileges |

**Tier evaluation:** 5 windows — rolling, fixed period, anniversary, calendar month, calendar quarter. Immediate upgrade on qualification. Non-adjacent progression (skip tiers possible). Multi-site — all branches count toward qualification.

---

## VIP & Paid Membership

**VIP (Star):** Contractual benefits — assigned by the hospital, not earned. Each VIP level (Connex, Cheva/BDMS, VIP Insurance) has distinct benefit packages. On assignment, system auto-issues consumable privileges AND activates standing benefit rules. At billing, HIS queries Eligibility API → receives all active standing benefits → applies highest.

**Paid (Divine Elite):** Patients purchase plans via Rocket backend. Three benefit categories:

| Category | Divine Elite 1-Year Example |
|---|---|
| **Mandatory** | 12× monthly restaurant coupons, 2× parking, 1× annual checkup |
| **Elective** | Choose 3 from 8: Spa, dental, eye exam, massage, derma, nutrition, physio, pharmacy |
| **Standing** | 15% off OPD, 10% off pharmacy, 10% off dental — unlimited for 1 year |

**Paid tier:** Cumulative spend across plans determines level (50k → 100k → 200k) with escalating benefits. Duplicate rule: two plans with same privilege → patient receives two copies.

---

## Corporate & Insurance Membership

**Corporate:** B2B agreements where company employees receive healthcare benefits by employment level.

| Step | What Happens |
|---|---|
| 1. Contract setup | Admin creates company → defines levels (C-Level / Executive / General / Other) |
| 2. Roster import | HR sends CSV or API → batch import with validation |
| 3. Auto-assignment | Employees see "Corporate Member: Company ABC — Executive" in app |
| 4. Benefits per level | Consumable privileges + standing discounts per level |
| 5. Governance | Approval flow for roster changes > 50 employees |
| 6. Reporting | Usage per company, contract, level — supports renewal conversations |

**Insurance:** Same structure as Corporate, plus two unique features:
- **Auto-assignment:** HIS records insurance → system auto-assigns insurance member type (no manual roster)
- **Stackability rules per package:** Annual Checkup = Insurance + Coins stackable (30% + coins). Premium Surgery = Insurance only, non-stackable (coins blocked).

---

## Standing Benefits & Cross-Type Rules

**Standing benefits are unlimited-use, period-based discounts. They are NOT consumed on use. They apply at every visit for the entire validity period.**

| | Consumable Privilege | Standing Benefit |
|---|---|---|
| **Usage** | Depletes on use (single or multi-use) | Never depletes |
| **Tracking** | Uses remaining, usage history | Active/inactive status only |
| **Duration** | Until used or expired | For the membership/contract period |
| **Example** | "5 parking passes" — 4 remaining | "25% off OPD" — every visit for 1 year |
| **Queried by** | Patient (shows in wallet) | HIS (at billing counter) |

**Precedence:** Multiple types grant OPD discount → highest wins. VIP 30% vs Corporate 25% vs Insurance 20% → **30% applied.**

**Stackability:** Configured per health package — which benefit types combine. Approval flow required for changes.

**Audit:** Every precedence decision logged: benefits evaluated, which selected, why.

---

## [MOCKUP] Membership & Tier Screens

**Membership Landing, Tier Status, Elective Selection & Partner Page**

[MOCKUP PLACEHOLDER — insert 4 membership mockups: (1) Divine Elite landing with mandatory/elective/standing, (2) Elective Selection "เลือกสิทธิ์ 3 จาก 8 รายการ", (3) Tier Status with progress bar and benefit comparison, (4) Marriott × Samitivej partner landing]

---

## Single Customer View & Segmentation

**The SCV aggregates data from every touchpoint into one patient profile. Dynamic segments update in real time.**

| Source | How Data Arrives | What We Store |
|---|---|---|
| **HIS / Data Center** | HIS pushes events via API | Transactions, visit history, department usage, insurance status |
| **Well App** | Our platform IS the backend — we own this data | Feature usage, login, purchase history |
| **Website** | JavaScript tracker sends events | Article reads, likes, shares, page visits |
| **LINE** | LINE OAuth + LIFF events | Registration, message engagement |
| **E-commerce** | Marketplace webhooks | Order history, product preferences |
| **CDP Hospital** | API or batch | Service catalog, product/price master |

**Segmentation modes:**
- **Static:** Admin imports patient list (CSV of 500 VIP patients for special campaign)
- **Dynamic:** Auto-populates in real time. Example: "Gold tier + visited dermatology in last 90 days + coin balance > 500" — patients enter/exit as data changes

---

## Journey Automation

**Visual drag-and-drop journey builder for automated lifecycle campaigns across LINE, SMS, Email, and Push.**

**Node types:** Trigger → Condition (branch on attributes) → Wait (duration or event) → Message (multi-channel) → Action (coins, privileges, tags)

**Pre-built journeys for Samitivej:**

| Journey | Trigger | Flow |
|---|---|---|
| **Welcome** | Registration | Day 0: Welcome + 100 coins → Day 3: Complete profile → Day 7: Missions |
| **Post-visit** | OPD visit (HIS) | 1hr: Café coupon → Day 3: Package offer (tier-branched) → Day 14: Expiry reminder |
| **Birthday** | Birth month | Day 1: Birthday privilege → Day 15: Reminder → End of month: Last chance |
| **Win-back** | No visit 180 days | Day 0: 200 coins → Day 7: 30% off checkup → Day 14: Final offer |
| **Post-surgery** | IPD discharge | Day 1: Care instructions → Day 7: Follow-up → Day 30: Recovery offer |
| **Chronic care** | Medication due | 7 days before: Refill reminder + pharmacy discount |
| **Tier maintenance** | 30 days before eval | Progress reminder → spend countdown messages |
| **Prenatal** | Pregnancy recorded | Trimester-appropriate: checkup packages, nutrition, delivery prep |

**Governance:** Frequency capping (max N messages/week), suppression lists, consent enforcement, A/B testing, gradual rollout (10% → 100%).

---

## AI Decisioning

**The first globally deployed AI system for mass retention marketing in a loyalty platform. An AI agent that evaluates each patient individually — as if every patient had their own dedicated marketing expert.**

| | Rule-Based | AI Decisioning |
|---|---|---|
| Decision maker | Marketing defines if-then rules | AI evaluates full patient context |
| Personalization | Segment-level (same for all Gold) | Individual-level (different per patient) |
| Timing | Fixed (send on Day 3) | Optimized per patient's engagement pattern |
| Discovery | Only finds opportunities rules define | Discovers cross-signal patterns rules would miss |

**The Observe → Deliberate → Act/Wait/Skip loop:**
- **Observe:** Visit history, departments, coin balance, privileges, engagement, member types, recent messages
- **Deliberate:** What action is most effective? Is now the right time?
- **Act (~15-20%):** Send message, issue privilege, award coins — only when confidence is high
- **Wait (~60-70%):** "Patient just visited — wait 48h, check if they book follow-up before upselling"
- **Skip (~10-20%):** "3 active privileges + message yesterday — additional contact would feel spammy"

**Guardrails:** Budget cap per patient/month, frequency cap per week, channel consent, action whitelist, monthly spend ceiling, human override at any time. Two enforcement layers: AI self-regulates AND system blocks violations regardless.

---

## [MOCKUP] Marketing & Admin Screens

**Journey Builder, Campaign Management & AI Assistant**

[MOCKUP PLACEHOLDER — insert 3 admin mockups: (1) Campaign creation with journey builder, (2) Approval queue, (3) Rocket MCP AI data assistant]

---

## Omni-Channel Experience

**Four channel types — all reading from the same backend. One wallet, one tier, one set of benefits.**

| Capability | Well App | Website | LINE | E-Commerce |
|---|---|---|---|---|
| Register / Login | Well SSO | LINE OAuth + OTP | LINE OAuth | — |
| View coins & tier | ✓ Full | ✓ Full | ✓ Webview | — |
| Earn coins | ✓ | ✓ (article tracking) | ✓ | ✓ (webhooks) |
| Redeem privileges | ✓ Full | ✓ Full | ✓ Webview | Codes |
| Buy packages | ✓ Full commerce | ✓ Redirect to E-Commerce | ✓ Staff sends link | ✓ Marketplace |
| Missions & referral | ✓ | ✓ | ✓ Webview | — |
| Notifications | App Push | Web Push | LINE message | — |
| Multi-language | TH, EN, JA, ZH | TH, EN, JA, ZH | TH, EN, JA, ZH | — |

**Identity architecture:** Primary keys = National ID / Passport + Phone (OTP). HN is unique ID once hospital visit occurs. Well ID interim for pre-visit patients. LINE ID stored for linking. Sukhumvit and Srinakarin share HN; other branches separate.

---

## [MOCKUP] Consumer Screens

**Home Dashboard, Corporate Variant & Member QR**

[MOCKUP PLACEHOLDER — insert 3 consumer screen mockups: (1) Home Dashboard with coin balance, tier badge, package offer, privilege carousel, (2) Corporate Member variant with company badge and standing benefits, (3) My QR for staff scanning]

---

## Operations Console

**Central hub for configuring all loyalty operations. Every write operation that impacts patients or coin economy includes an approval flow.**

| Function | Details | Approval |
|---|---|---|
| **Campaign CRUD** | Create, schedule, pause, archive with eligibility conditions and associated privileges | Campaign launch: manager |
| **Coin rules** | Visual earn rate/multiplier builder, department-specific, caps, exclusions | Rule changes: maker-checker |
| **Privilege management** | Create, edit, stock, scheduling, bulk promo code import with partner attribution | Creation: manager |
| **Mission management** | Standard (single goal, AND conditions) + milestone (multi-level with overflow) | Launch: manager |
| **Form builder** | Surveys with conditional logic, NPS, ratings, open text — responses feed automation | — |
| **Referral program** | Invitee: 100 coins on registration. Inviter: 200 coins on first hospital visit. Period-based limits. | — |
| **Partner landing pages** | Dedicated page per partner with dynamic conditions by level (Gold vs Platinum) | New page: manager |
| **Approval queue** | Pending dashboard with approve/reject and comments | — |
| **Role/permission/MFA** | Superadmin, Marketing Manager, Department Admin, Viewer. MFA for admin accounts. | — |
| **Audit trail** | Every action logged: who, when, what, why, before/after state | — |

---

## Dashboards & Analytics

**10 standard dashboards + up to 20 custom dashboards — included at no additional charge.**

| # | Dashboard | Key Metrics |
|---|---|---|
| 1 | **Member Overview** | Total members, active/inactive, registration by channel, member type distribution |
| 2 | **Coin Economy** | Earned/burned/expired, net circulation, earn by channel, burn by category |
| 3 | **Privilege & Redemption** | Top redeemed, by tier/member type, stock levels, partner performance |
| 4 | **Package Sales** | By type/branch/channel, conversion funnel, revenue trend, average order value |
| 5 | **Tier Movement** | Upgrades/downgrades, tier distribution, at-risk members |
| 6 | **Campaign Performance** | Reach, open, click, conversion per campaign, A/B results |
| 7 | **Department Usage** | Cross-department flow, cross-sell paths, coupon usage by dept |
| 8 | **Corporate & Insurance** | Usage per company/insurer/level, utilization rate, renewal indicators |
| 9 | **Entitlement Tracking** | Active entitlements, avg usage rate, approaching expiry |
| 10 | **Marketing Automation** | Journey completion/drop-off, delivery/open/click by channel |

**Samitivej-specific examples:** "Of 5,000 checkup patients this quarter, 23% also used dental, 15% dermatology — top cross-sell path: Checkup → Dental → Dermatology." All dashboards: date filters, drill-down, scheduled auto-generation, CSV/Excel export.

**Rocket MCP — AI Data Assistant:** Natural-language queries for executives. "Which department has the highest cross-sell rate?" → instant answer. No SQL, no report building.

---

## [MOCKUP] Dashboard & Analytics Screens

**Coin Economy Dashboard, Department Cross-Sell Flow & AI Data Assistant**

[MOCKUP PLACEHOLDER — insert 3 dashboard mockups: (1) Coin Economy with earn/burn charts and channel breakdown, (2) Department cross-sell Sankey diagram, (3) Rocket MCP AI assistant interface]

---

## Integration Scenarios

**Key flows between Samitivej systems and the loyalty platform:**

**Scenario 1 — Hospital Visit → Coins in < 1 second:**
Patient pays 3,000 THB → HIS sends purchase event → Kafka → Earn engine evaluates (base × tier multiplier) → 45 coins credited → Patient sees in app

**Scenario 2 — Eligibility at Billing Counter (< 50ms):**
HIS queries platform → Redis cache returns all benefits (VIP 30%, Corporate 25%, Insurance 20%, Tier 5%) → Precedence resolves → 30% returned to HIS

**Scenario 3 — Entitlement Mark-Use (Staff scans QR):**
Staff scans patient QR → POST /entitlements/{id}/use → Row lock acquired → 1 use deducted (2/5 remaining) → Staff sees confirmation

**Scenario 4 — Package Purchase on Well App:**
Patient selects package → applies coin discount → payment gateway → on success: coin deduction confirmed + mandatory privileges issued + standing benefits activated + coins earned from purchase

**Scenario 5 — Marketplace → Hospital Verification:**
Patient buys on Shopee → email voucher → visits hospital → staff verifies OrderSet + national ID → patient linked → privileges issued to wallet

---

## Integration Map & Security

| System | Direction | Data |
|---|---|---|
| **HIS** | Bidirectional | In: purchases, visits, services, insurance. Out: eligibility, entitlements, status |
| **Well App** | Bidirectional | In: SSO token. Out: all loyalty data via API + webview |
| **LINE** | Bidirectional | In: auth, events. Out: messages, webview |
| **Shopee / Lazada** | Inbound | Order data via webhooks |
| **Payment Gateway** | Bidirectional | Payment requests + callbacks |
| **Partners** | Bidirectional | Activity events in; eligibility out |
| **CDP Hospital** | Inbound | Service catalog, product/price master |

| Security Layer | Protection |
|---|---|
| Network | WAF, DDoS, TLS 1.3 |
| Auth | JWT, OAuth 2.0, MFA for admin |
| Authorization | Row-Level Security, RBAC, API key scoping |
| Data | AES-256 at rest, TLS in transit, PII hashing |
| Fraud | Idempotency keys, anti-double-spend, rate limiting, velocity checks |
| Audit | All mutations: actor, timestamp, action, before/after |
| PDPA | Per-channel consent, data subject access, right to erasure |

---

## Implementation Timeline

| Phase | Duration | Key Activities |
|---|---|---|
| **Discovery & Design** | 3–4 weeks | HIS event schema, identity mapping, earn rules, privilege templates, department classification |
| **Core Configuration** | 3–4 weeks | Tiers, member types, earn rules, privileges, packages, translations (TH/EN/JA/ZH) |
| **Integration Dev** | 4–6 weeks | HIS adapter (events + eligibility), Well SSO, Rocket payment, Shopee/Lazada webhooks |
| **Frontend Dev** | 6–8 weeks | Well webview (wallet, catalog, store, missions), website loyalty pages (2 branches), LINE LIFF (2 OAs) |
| **Marketing Setup** | 2–3 weeks | Journey templates, segment definitions, communication templates per channel |
| **SIT + UAT** | 6 weeks | Module integration, API validation, all 6 member types tested, bug resolution |
| **Security + Performance** | 2 weeks | Penetration testing, 10k concurrent load test, PDPA audit |
| **Pilot** | 2–4 weeks | 1 branch, real transactions, daily review. Monitor earn/burn accuracy, HIS stability |

---

## Support & SLA

| Severity | Definition | Response | Resolution |
|---|---|---|---|
| **P1 — Critical** | Platform down, loyalty unusable, HIS integration failed | 15 min | 4 hours |
| **P2 — High** | Major feature broken, workaround exists | 30 min | 8 hours |
| **P3 — Medium** | Minor issue, limited impact | 2 hours | 24 hours |
| **P4 — Low** | Cosmetic, enhancement | 8 hours | 72 hours |

**Support coverage:** L1 Technical (Mon–Sat, 8:00–20:00) + L2 Engineering (Mon–Fri, on-call P1). War room protocol for critical incidents. Root cause analysis within 48 hours.

**Campaign turnaround:** 3-day cycle — Day 1: receive brief + configure → Day 2: test + review → Day 3: deploy + monitor. Recurring campaigns (birthday, welcome, post-visit) configured once, run automatically.

---

## Reward Sourcing — 2,000+ SKUs

**Pay only when redeemed. Hospital-owned privileges = zero procurement cost.**

| Category | Examples | Coins | Source |
|---|---|---|---|
| Hospital services | Consultation, specialist, pharmacy, lab | 500–5,000 | Samitivej-owned |
| Hospital amenities | Parking, cafeteria, lounge | 100–500 | Samitivej-owned |
| Wellness | Spa, fitness, IV drip, massage | 500–3,000 | Samitivej + partners |
| Dining | Starbucks, After You, Café Amazon, MK, S&P | 200–1,000 | Partner network |
| Lifestyle | Grab, Shopee gift cards, cinema, beauty | 500–3,000 | Partner network |
| Health products | Supplements, skincare, health devices | 1,000–5,000 | Partner network |
| Premium / Flash | Dyson, Apple, luxury wellness retreats | 10,000–50,000 | Partner network |

**Fulfillment:** Digital e-vouchers = instant. Physical = 2–5 business days with tracking. 100+ partner network curated for hospital demographic. New partners onboarded in 5 business days. Monthly reconciliation per partner — billing on redeemed only.

---

## TOR Coverage Summary

**Over 150 functional requirements. ~85% standard modules. ~15% integration + configuration.**

| Area | TOR Items | Status |
|---|---|---|
| Coin Economy & Privileges | B1.1–B1.6, B2.1–B2.7, F3 | ✓ All covered |
| Membership Management | C1–C6 + Shared scope | ✓ All 6 types + precedence |
| Marketing Automation | D1.1–D1.2, D2 | ✓ Journeys + Lifestage |
| Omni-Channel | E1–E4 | ✓ Well, Web, LINE, E-Commerce |
| Operations Console | F1–F4 | ✓ Full admin + approval flows |
| Technical & Security | G1–G3 | ✓ Architecture + PDPA + SLA |

**Beyond TOR:** AI Decisioning (per-patient, observe-wait-act), Flash Rewards (10k+ concurrency), Milestone Missions, 20 Custom Dashboards, Open API (50+ endpoints), Rocket MCP AI Assistant, Durable Execution (Temporal), 2,000+ Reward SKUs (pay-per-use), Stream Processing for real-time segments

---

## Why Rocket for Samitivej

| | |
|---|---|
| **Production-Ready** | 85% TOR from standard modules — not a custom build that freezes at delivery |
| **Hospital-Grade** | 99.9% uptime, < 50ms eligibility, 10k+ flash reward concurrency |
| **6 Member Types, One Profile** | Precedence engine resolves best benefit automatically at every visit |
| **AI Decisioning** | First globally deployed AI for mass retention marketing — a personal expert per patient |
| **Omni-Channel Day One** | Well App, Website, LINE, Shopee, Lazada, Hospital E-Commerce — one wallet everywhere |
| **2,000+ Rewards** | Pay-per-use, zero upfront cost for hospital-owned privileges |
| **Continuous Evolution** | Platform improves continuously — Samitivej benefits from every product update |

[MOCKUP PLACEHOLDER — insert hero mockup: Home Dashboard showing the complete patient experience — coin balance, tier badge, package offer, privilege carousel]
