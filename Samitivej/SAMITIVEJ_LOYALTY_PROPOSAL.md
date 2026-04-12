# Samitivej Loyalty Program — Requirement Analysis & Feature Mapping

## Table of Contents

1. [Glossary of Concepts](#1-glossary-of-concepts)
2. [Concept Unification — Same Object, Different Names](#2-concept-unification)
3. [Phase 1 Requirements](#3-phase-1-requirements)
4. [Phase 2 Requirements](#4-phase-2-requirements)
5. [Phase 3 Requirements](#5-phase-3-requirements)
6. [Feature Mapping Summary](#6-feature-mapping-summary)
7. [User System — Pages & Mockup Scope](#7-user-system-pages--mockup-scope)
8. [Pitching Day — Required Demo Scenarios](#8-pitching-day--required-demo-scenarios)
9. [Data Architecture — Source of Truth Map](#9-data-architecture--source-of-truth-map)
10. [High-Level Weekly Project Plan](#10-high-level-weekly-project-plan)

---

## Important Note: TOR vs Our Additional Features

The Samitivej CSV has two distinct columns: **"TOR Items Mapping"** (what Samitivej actually asked for) and **"Additional CRM Features Beyond TOR"** (extras we offer on top). Throughout this document, we distinguish between the two. Items marked as "beyond TOR" or "our extra" are capabilities we can offer to strengthen the proposal but were NOT requested by Samitivej.

Key items that are **our extras, NOT in the TOR:**
- Tickets (multiple currency types) — TOR only asks for Coins
- Delayed award (24h hold before wallet credit)
- Milestone missions (multi-level) — TOR asks for missions generically
- AI Decisioning — TOR explicitly marks this as "Not specified"
- Advanced reversal/cancellation mechanics

---

## 1. Glossary of Concepts

### Samitivej-Specific Terms

| Term | Definition |
|------|-----------|
| **Coin** | Loyalty points earned from purchases, behaviors, or activities. Used to redeem rewards. Equivalent to "points" in standard loyalty programs. |
| **eCoupon** | A digital coupon representing a right — can be a discount coupon, a service voucher, or a multi-use package pass. Issued automatically (post-service), manually (by staff), or redeemed via coins. |
| **Package (Health Package)** | A purchasable bundle of hospital services (e.g. annual health checkup, 5-session physiotherapy). Sold through the Well app or e-commerce. On purchase, the system issues entitlements/eCoupons to the buyer. |
| **Entitlement** | A usage-tracked right attached to a package or membership. Has a fixed number of uses (e.g. "5 treatments") that are decremented one at a time. Shows remaining balance and expiry. |
| **Privilege** | A special benefit from the hospital or a partner — could be a discount deal, exclusive access, or a physical gift. Displayed in the reward catalog and redeemable with coins or given by tier. |
| **Reward Catalog** | The storefront where members browse and redeem privileges/rewards using coins. |
| **Tier** | Membership level (e.g. Silver → Gold → Platinum) determined by spending, visit frequency, or engagement. Higher tiers unlock better benefits and earn rates. |
| **Star (VIP)** | A special membership classification for pre-agreed VIP entitlement holders (e.g. Connex, Cheva BDMS). Not earned through spending — assigned by contract. |
| **Paid Member** | A member who purchased a membership plan (e.g. Divine Elite). Gets a fixed set of mandatory + elective coupons for the plan duration. |
| **Corporate Member** | A member linked to a company contract. Benefits determined by contract level (Executive / General). Roster imported in batch. |
| **Insurance Member** | A member linked to an insurance partner contract (e.g. AIA, Allianz). Benefits by policy tier. |
| **Exclusive Partner** | A member linked to a strategic partner program with dedicated landing pages and exclusive deals. |
| **Wallet** | The container displaying a member's coin balance, eCoupons, and tier status across all channels. |
| **Mission** | A gamification task with defined conditions (e.g. "visit 3 departments") that awards coins or coupons on completion. |
| **Journey** | An automated marketing flow triggered by events or lifecycle stages (e.g. welcome series, post-visit follow-up, birthday reward). |
| **Single Customer View (SCV)** | A unified profile aggregating data from all channels (Well app, LINE, website, HIS, e-commerce) for one patient. |
| **Lifestage** | A patient's current phase in their healthcare journey (e.g. pre-appointment, post-discharge). Used for hyper-personalized campaigns. |
| **Mandatory Coupon** | A coupon automatically included in a package/membership — the member must receive it (e.g. 2x blood test coupons in a health plan). |
| **Elective Coupon** | A coupon the member can choose from a predefined set within their package allowance (e.g. pick 3 out of 10 wellness options). |
| **Seasonal Coupon** | A coupon issued based on calendar events — birthday, birth month, hospital anniversary milestones (48th, 49th, 50th year). |
| **Coin Transfer** | Converting points from external platforms (Shopee Coins, The One Card, M Card, K Point) into Samitivej Coins. One-way inbound only. |
| **Maker-Checker** | An approval workflow where one person creates/adjusts and another approves — required for high-impact actions like bulk point adjustments. |
| **Well by Samitivej** | The hospital's super-app — the primary consumer touchpoint with full-loop loyalty capabilities. |

---

## 2. Concept Unification

Many Samitivej concepts are **the same underlying object** in development, just configured differently.

### eCoupon / Privilege / Entitlement / Seasonal Coupon = **Two Distinct Patterns**

Samitivej's entitlement system has **two fundamentally different patterns** (the TOR explicitly defines these in C1 notes):

**Pattern A: Consumable items → Our Reward**

These are items that get "used up" — single-use coupons, multi-use packages with a count, one-time vouchers.

| Samitivej Concept | Our Reward Configuration |
|---|---|
| **eCoupon (single-use)** | Reward with `fulfillment = digital`, quantity = 1, promo code attached |
| **eCoupon (multi-use / Entitlement)** | Reward with `multi_qty` enabled (e.g. qty = 5), usage tracked per redemption |
| **Mandatory Coupon** | Reward with `visibility = admin`, auto-issued on package purchase via API |
| **Elective Coupon** | Reward with `visibility = campaign`, shown only to eligible package holders |
| **Seasonal Coupon** | Reward with `visibility = campaign`, trigger = birthday/anniversary, `expiry = absolute_date` |
| **Flash Reward** | Reward with `expiry_type = relative_mins` |
| **Partner Reward** | Reward with promo codes bulk-imported, `partner_merchant` attribution |
| **Physical Gift** | Reward with `fulfillment = shipping`, fulfillment status tracking |

**Pattern B: Standing benefits → New concept (Benefit Rules)**

These are ongoing membership benefits that NEVER get consumed — they apply every time the member uses a service, for the entire validity period. The TOR (C1 note) calls these: "สิทธิ์ที่ได้รับโดยมีระยะเวลา start-end date โดยไม่ได้จำกัดว่าจะใช้กี่ครั้ง."

| Samitivej Concept | What It Means |
|---|---|
| **Period-based discount** | "VIP members get 30% off all OPD services, valid Jan–Dec 2027" — applies at every visit, never consumed |
| **Privilege / Discount Deal** | Catalog item redeemable with coins (Pattern A) OR a standing discount entitlement (Pattern B) depending on context |
| **Unlimited-use Discount** | "Paid member gets 10% off all pharmacy purchases during membership" — not a coupon, it's a benefit flag |

**How precedence works (the VIP 30% vs Insurance 20% example):** When a user has multiple standing benefits for the same service category (e.g. OPD discount), the system picks the highest value. This is NOT two coupons that can both be used — it's one discount slot where the best benefit wins automatically. HIS queries our Eligibility API → we evaluate all active benefit rules → return the best applicable discount.

**How it works at the hospital counter:**
1. Patient checks in at hospital reception
2. Hospital billing system (HIS) calls our Eligibility API: "What benefits does patient HN-12345 have?"
3. Our system returns all active standing benefits (e.g. `[{category: "OPD", discount: 30%, source: "VIP_Connex"}, {category: "OPD", discount: 20%, source: "Insurance_AIA"}]`)
4. HIS applies the highest: 30% on the OPD bill
5. No coupon consumed — the benefit stays active for next visit

**In dev terms:** Pattern B cannot be modeled as our current reward. It needs a **benefit_rule** config attached to contract/persona levels: `{ persona_level: "VIP_Connex", benefit_category: "OPD", discount_percent: 30, type: "period_based", valid_from, valid_to }`. This is new development.

### Coin = **Our Currency (Points)**

- Samitivej's "Coin" maps directly to our `user_wallet` points balance
- Earn/burn/expire flows use `wallet_ledger`
- Coin expiry = our configurable TTL / fiscal period / fixed date expiry

### Coin Transfer = **Our Credit Ticket Type** (partial) + Custom API

- Inbound transfers from Shopee/Lazada map to our marketplace earn channel
- Partner transfers (The One, M Card) require custom API with conversion rates

### Tier = **Our Tier System**

- Samitivej's spending tiers map 1:1 to our `tier_master` with conditions on sales/points/orders
- Supports multiple window types, burn rates per tier, non-adjacent progression

### Star (VIP) / Corporate / Insurance / Partner = **Our Persona System (enhanced)**

These are all **persona groups with additional governance.** The architecture maps directly:

| Samitivej Concept | Our System | What It Is |
|---|---|---|
| "Company ABC" / "AIA" / "Marriott" | `persona_group_master` | A group — with added contract metadata (company name, contact, dates, status) |
| "Executive / General" / "Premium / Standard" | `persona_master` | Personas within the group |
| "200 employees assigned to Executive" | `user_personas` | Users assigned to personas — with added effective dates per assignment |
| "Executives get 25% off + 5 parking coupons" | Reward eligibility by `persona_id` | Single-use coupons = our rewards. Standing discounts = new Pattern B. |

The core architecture (persona group → persona → user → reward eligibility) already handles ~40% of the requirement. The enhancements needed:

| Enhancement | What | Effort |
|---|---|---|
| **Persona metadata** | Add contract fields to persona_group (company name, contact, dates, status) | Small |
| **Assignment lifecycle** | Add effective_date/expiry per user_persona + auto-deactivation | Medium |
| **Batch roster** | Import 200 users with levels from CSV, with validation | Medium |
| **Group-level reporting** | Reports by persona_group (company/insurer), not just by user | Medium |
| **Standing benefits (Pattern B)** | New entity: period-based discounts per persona level, never consumed, queried by HIS | **New concept** |
| **Stackability rules** | Per health package: which benefit types can combine | **New concept** |
| **Eligibility API** | HIS queries "what benefits does this patient have?" → resolved precedence | **New concept** |

**Key differences between the 4 types** (all using the same persona structure, different configurations):
- **VIP (Star):** Hospital assigns directly. Benefits include both single-use coupons AND standing discounts. Precedence rule: if VIP and another type give the same benefit, pick the highest.
- **Corporate:** Company HR provides roster (batch import). Different employee levels get different benefit packages.
- **Insurance:** Eligibility verified via HIS or insurer API (not roster import). Adds **stackability rules** (can this insurance discount combine with coins? depends on the health package).
- **Exclusive Partner:** Partner provides member list. Activity events from partner (e.g. "completed 5 hotel stays") can upgrade the user's persona level and unlock additional deals.

### Paid Member = **Purchase + Auto-Issue Benefits (new commerce feature)**

- Paid membership is NOT just a persona label — it requires actual purchase flow
- The TOR explicitly says: "ใช้ payment gateway ฝั่ง Rocket ทั้งหมด end to end" — purchase happens in our system with Rocket payment gateway
- On purchase, system auto-issues: mandatory coupons (fixed set) + elective coupon rights (choose from pool) + period-based standing discounts
- Cumulative spend across paid packages determines tier within the Paid program
- If a user buys 2 packages that include the same coupon → they get it twice (one per package, explicitly stated in TOR)

### Mission = **Our Mission System**

- Standard missions (single goal) and milestone missions (multi-level) both supported
- Condition sources: purchase, wallet, form, referral — all match Samitivej needs

### Health Package Store = **New Feature (Custom Dev)**

- Product catalog, cart, checkout, payment, and auto-issuance of entitlements
- Not in current platform — requires custom development

### Journey Automation = **New Feature (Custom Dev)**

- Trigger-based multi-channel messaging (LINE, SMS, email, push)
- Branching logic, delay nodes, A/B testing
- Not in current platform — requires custom development

### SCV / Dynamic Segmentation = **Our Tag + Persona + User Profile** (partial)

- Basic segmentation via tags/personas exists
- Advanced dynamic segmentation with auto-updating segments needs enhancement

---

## 3. Phase 1 Requirements

### 3.1 Registration & Login (SSO/OTP)

**What Samitivej Needs:**
- Register/login via LINE and phone OTP
- SSO with Well by Samitivej app
- Profile completion check after login
- 15+ configurable profile fields with validation (name, phone, email, national ID, address)
- Fields shown conditionally by member type (e.g. Corporate members see company field)

**How SSO with Well App Works:**

"SSO" in this context does NOT mean we implement authentication from scratch. Well by Samitivej is an existing native app (built on AWS by DailiTech) with its own authentication system. The SSO integration works as follows:

1. User logs into Well app using Well's own auth (hospital credentials, phone, etc.)
2. User taps a loyalty feature (wallet, redeem, etc.) inside Well app
3. Well app opens our CRM webview/API and passes an authenticated token (OAuth2 token or signed JWT)
4. Our system validates the token against Well's auth service → identifies or creates the user in our CRM
5. User is now seamlessly logged into loyalty features without a second login

In short: **Well authenticates the user; we accept Well's session.** We provide an SSO callback/verification endpoint. For LINE and website channels, we handle auth directly (LINE OAuth + phone OTP).

**What about users who sign up on our system first?**

Well is a patient-facing layer on top of HIS. Users appear in Well when they have a HIS record (HN = hospital number). We don't push-create users into Well — there's no API for that.

| Scenario | What Happens |
|---|---|
| **Patient uses Well first (most common)** | Already has HN in HIS → already in Well → taps loyalty features → Well SSO to our CRM → we CREATE the CRM user, linked to HN |
| **User registers on our LINE/website first** | We create CRM user → they later open Well → Well has them via HIS (if they're a patient) → systems link by phone or HN |
| **Brand new person (e.g. corporate employee, not yet a patient)** | Exists in our CRM only → not in Well or HIS → first hospital visit creates HN → HIS record appears → Well picks them up → our CRM links |
| **Our web user opens Well app** | Deep link with auth context → Well must accept on their side → co-design needed with Well's team |

**Bottom line:** We don't create users in Well. Well draws from HIS. The link between our CRM and Well/HIS happens by matching phone number or HN. User creation is always unidirectional — into our CRM (from any channel).

**Can users register without HIS data?**

Yes. HIS data is NOT required for registration. Our system handles registration independently — user provides phone number or LINE login, fills profile fields, becomes a loyalty member immediately. HN (hospital number) gets linked later when the user actually visits the hospital and HIS creates their patient record.

Users who might register without HIS data:
- Corporate employees whose company signed a deal but they've never visited Samitivej
- Friends referred through the referral program who aren't patients yet
- Anyone who signs up for loyalty before ever visiting the hospital

If Samitivej wants to auto-detect insurance status or verify existing patient records during registration, that's an optional HIS lookup — not a prerequisite.

**Customer Journey:**
1. User opens Well app (already logged in via Well's auth) → taps "Loyalty" or "My Wallet"
2. Well passes token to our CRM → user session established
3. System checks profile completeness → routes to profile form if incomplete
4. User fills required fields → becomes active loyalty member (no HIS record needed)
5. System assigns default tier and persona
6. On LINE: user opens LINE OA → LIFF launches → authenticates via LINE OAuth → same CRM user matched
7. When user later visits hospital → HN created in HIS → our CRM links to HN for cross-system identity

**Our Platform Mapping:** SUPPORTED
- `bff-auth-complete` handles LINE + OTP flow with `next_step` routing
- `merchant_master.auth_methods` configures allowed auth methods
- `user_field_config` + `form_templates` handle dynamic profile fields
- Persona-based field visibility via `persona_ids` on form fields
- Profile completion check built into auth flow
- **Enhancement needed:** SSO token verification endpoint for Well app integration (accept Well's JWT/OAuth token)

### 3.2 Coin Wallet & Balance

**What the TOR Specifies:**
- Display current coin balance
- Full earn/burn/expire history
- Omni-channel wallet (same balance on Well app, LINE, website)
- Flexible expiry (the TOR mentions expiry but does not specify methods)
- The TOR references Coins only — no mention of "Tickets" or multiple currency types

**Additional Capabilities We Offer (beyond TOR):**
- Multiple currency types: Coins (fungible) + Tickets (typed, e.g. ticket for special event access or campaign entry) — tickets are a separate balance type useful if Samitivej later wants campaign-specific tokens
- Advanced expiry options: days-after-earn, fixed date, end-of-month, end-of-year, custom rules
- Reversal/cancellation for refunds
- Delayed award (e.g. coins held 24h after service before entering wallet — prevents earning coins on services that get cancelled same day)

**Customer Journey:**
1. Patient visits hospital → pays for OPD consultation (3,000 THB)
2. HIS records the payment → sends purchase event to our CRM via API
3. Earn rule calculates: 3,000 THB × earn rate (1 coin per 100 THB) = 30 coins
4. Coins credited to wallet (immediately, or with optional delay)
5. User checks balance on Well app / LINE / website — all show same value (single wallet, multiple frontends)
6. Coins auto-expire per policy (e.g. all coins expire on December 31 each year)

**Our Platform Mapping:** SUPPORTED
- `user_wallet` + `wallet_ledger` for balance and full history
- Points (Coins) supported natively; ticket types available as extension
- Expiry via daily cron job with configurable TTL, fiscal period, or fixed date
- Delayed award via Inngest scheduled functions (beyond TOR, our extra)
- Reversals via debit entries with original calculation metadata (beyond TOR, our extra)
- Omni-channel via API — all frontends read same wallet

### 3.3 Earn Coins from Behavior (Content/Social)

**What the TOR Specifies:**
- Earn coins from: reading articles, likes, shares, hospital e-commerce purchases
- Track activities across all Samitivej channels (online and offline)
- Send events to CRM to award coins per rules

**Additional Capabilities We Offer (beyond TOR):**
- 15+ earn channel types
- Configurable earn rate (spend X THB → get Y coins) + multiplier (2x for new branch launch)
- Service-level earn rules (per package, department, service type)
- Threshold & cap (min/max coins per transaction)

**How Article Tracking Works (Read / Like / Share):**

The user **must be logged in** on the Samitivej website for tracking to work. Here's the technical flow:

- **Read:** User is logged in on samitivejhospitals.com → opens a health article → the website's JavaScript fires an `article_read` event to our CRM API with the user's `user_id` + article URL. The website knows the user because they authenticated (LINE or OTP login). CRM earn rule matches → awards coins (e.g. 5 coins per article).
- **Like:** User clicks a "Like" button on the article page → website sends `article_like` event to CRM API with `user_id`. This is a like button on Samitivej's own website, not Facebook's like.
- **Share:** User clicks a "Share to Facebook/LINE" button on the article → **before** the share dialog opens, the website sends `article_share` event to CRM API with `user_id` → coins awarded. Then the external share dialog opens. **Important: Facebook's Share Dialog no longer returns `post_id` (Meta privacy changes), so it is technically impossible to confirm the share actually posted.** Industry standard is to award based on the share button click (intent), not completion. LINE's share API has slightly better callback support but still limited.

**Limitation — anonymous users:** If a user reads an article without logging in, no coins can be awarded because we have no `user_id`. The website must prompt login before enabling coin-earning actions.

**Customer Journey:**
1. User logs into Samitivej website (via LINE or OTP)
2. Reads health article "10 Signs You Need a Heart Checkup" → `article_read` event → 5 coins
3. Clicks "Like" button → `article_like` event → 2 coins
4. Clicks "Share on LINE" → `article_share` event → 10 coins → LINE share dialog opens
5. Coins appear in wallet across all channels

**Our Platform Mapping:** SUPPORTED
- `earn_factor` + `earn_factor_group` with rate/multiplier configuration
- `earn_conditions` for product, category, brand, store, tier, persona filtering
- Activity-based earning via `activity_master` for behavior events
- Multiplier stacking control (stackable or not)
- Threshold/cap via `transaction_limits`
- Per-department rules via store attribute sets mapped to hospital departments
- **Note on Facebook share:** We track the click, not the completion — this is an industry-wide limitation, not specific to our platform
- **LINE share is better:** LINE's LIFF `shareTargetPicker()` API opens a share dialog → user selects friends/groups → on success the Promise resolves with confirmation → we can accurately award coins for completed shares. Unlike Facebook, LINE confirms the share actually happened.

### 3.4 Mission & Gamification

**What the TOR Specifies:**
- Missions for online gamification and on-site gamification (e.g. complete tasks at specific departments)
- The TOR mentions missions generically — does NOT specifically request milestone (multi-level) missions

**Additional Capabilities We Offer (beyond TOR):**
- **Standard missions:** Single goal, repeatable, AND conditions, per-condition progress tracking
- **Milestone missions (our extra):** Multi-level (e.g. checkup 3x → 5x → 10x) with overflow waterfall — if user completes 6 checkups, level 1 (3) completes and 3 overflow to level 2 (5), so they're already at 3/5
- Auto-evaluate on events (purchase, wallet, form, referral)
- Auto-reward on completion
- Check-in at hospital locations
- Referral: invite friends → both get rewards

**Customer Journey (Mission):**
1. User sees "Visit 3 departments" mission on Well app
2. Each hospital visit event (from HIS) updates progress (1/3 → 2/3 → 3/3)
3. On completion → system auto-awards 500 coins + bonus eCoupon
4. (Our extra) Milestone variant: "Health checkup champion" — 3 checkups → 100 coins, 5 → 300 coins, 10 → 1000 coins + premium coupon

**Customer Journey (Referral):**
1. User shares referral code with friend
2. Friend registers → invitee gets 100 welcome coins
3. Friend makes first hospital visit → inviter gets 200 referral coins

**Our Platform Mapping:** SUPPORTED
- Standard missions fully supported; milestone missions available as our additional capability
- CDC → Kafka → Mission consumer for real-time evaluation
- Referral system with `referral_codes`, `referral_ledger`
- Referral outcomes: points, tickets, rewards for invitee; missions for inviter
- Check-in: supported via activity upload or form submission (can extend)

### 3.5 Reward Catalog — Redeem Coins for eCoupon/Privilege

**What Samitivej Needs:**
- Browse catalog of rewards redeemable with coins
- See conditions, expiry, remaining stock
- Get code (QR/Barcode/Serial) after redemption
- Two-layer architecture: eligibility (who can redeem) + pricing (how many coins)
- Multi-dimensional matching: tier × member type × persona × tags
- Dynamic coin pricing (Platinum uses fewer coins than Silver)
- 4 fulfillment methods: digital, shipping, pickup, printed
- 3 visibility levels: public, admin-only, campaign-specific
- Bulk promo code import with partner attribution

**Customer Journey:**
1. User opens "Rewards" tab on Well app
2. Sees rewards filtered by their tier and member type
3. Selects a Starbucks voucher → sees cost: 200 coins (Platinum) / 300 coins (Silver)
4. Confirms redemption → coins deducted → receives unique promo code
5. Shows QR code at Starbucks → redeemed

**Our Platform Mapping:** SUPPORTED
- `reward_master` with eligibility layer + points pricing layer
- `reward_points_conditions` for tier, persona, tag-based dynamic pricing
- Multi-quantity support (1–1000 per redemption)
- Promo code system with bulk import, partner attribution via `partner_merchant`
- 4 fulfillment methods: digital, shipping, pickup, printed
- 3 visibility modes: user, admin, campaign
- Real-time stock management
- Fulfillment status tracking for physical rewards

### 3.6 Coin/Point Transfer (E-commerce & Partners)

**What the TOR Specifies:**
- Transfer coins from Shopee, Lazada, LINE MyShop into Samitivej coins
- Transfer from partner loyalty programs (The One, M Card, K Point) into Samitivej coins
- One-way inbound only (cannot transfer out)
- **Important TOR note:** "Transfer coin เฉพาะกับแพลตฟอร์ม shopee, lazada เท่านั้น" — Transfer is specifically for Shopee/Lazada only, inbound only

**Reality Check — Platform Coin Transfer APIs:**

After researching the actual APIs of each platform:

- **Shopee Coins:** No public API exists for transferring Shopee Coins to external loyalty programs. Shopee Coins can only transfer between Shopee accounts or be used at checkout as discount. A direct coin transfer would require a **B2B commercial partnership** with Shopee (custom API integration, not public).
- **Lazada:** Has a wallet transfer endpoint in their Open Platform, but it appears to be for internal wallet operations. No documented external partner transfer API. Also requires **BD partnership.**
- **LINE MyShop:** No point transfer API found. LINE Shopping API currently only supports order/product management, not loyalty point exchange.
- **The1 (Central Group):** Does support partner point exchange — The1 has an active partnership with Bumrungrad Hospital (earn/redeem The1 points at hospital). This works via a **B2B commercial agreement** with custom API, not a public endpoint.
- **M Card / K Point:** Same model — B2B partnership agreements required per partner.

**What This Means for Samitivej:**

The coin transfer feature is **technically straightforward** on our side (accept inbound credit, apply conversion rate, credit wallet). The blocker is **commercial** — each marketplace/partner requires a business development deal. The TOR's coin transfer requirement is realistically a "nice to have" that depends on Samitivej's ability to sign partnership agreements with Shopee/Lazada/The1/etc.

**Alternative for Shopee/Lazada (what actually works today):**

Instead of coin transfer, the more practical approach (and what the TOR also describes in section E4) is: customer purchases on Shopee/Lazada → our system receives the order data → earns Samitivej coins based on purchase amount. This achieves the same goal (rewarding marketplace activity) without requiring a coin transfer API.

**Customer Journey (Realistic):**
1. User buys a Samitivej health product on Shopee for 2,000 THB
2. Shopee sends order webhook → our system processes
3. Earn rule: marketplace purchases earn 1 coin per 200 THB → 10 Samitivej coins credited
4. User sees coins in their Samitivej wallet on Well app

**Our Platform Mapping:** PARTIAL
- Marketplace earn channel exists for Shopee order-based earning (coins from purchases — works today)
- Conversion rate configuration per source available
- **Commercially dependent:** Direct coin transfer from Shopee/Lazada/The1/MCard requires BD partnerships that Samitivej must negotiate — the technology is ready on our side but the partnerships are not ours to sign
- **Custom dev needed:** Partner transfer API endpoints (for when partnerships are signed), conversion rate management UI

### 3.7 eCoupon System (Single / Bundle / Seasonal)

**What Samitivej Needs:**
- **Single coupons:** Discount for hospital restaurants, service discounts
- **Bundle coupons:** Set of coupons from a health package (e.g. checkup package gives 5 restaurant coupons + 1 parking coupon)
- **Mandatory vs elective coupons** in a package
- **Seasonal coupons:** Birthday, birth month, hospital anniversary milestones
- **Unlimited-use discount coupons** valid during membership period
- Admin-only coupons (VIP gifts from patient relations)
- Campaign-specific coupons (Platinum members only)
- Flash rewards with minute-level expiry
- Relative-days and absolute-date expiry

**Customer Journey (Package Bundle):**
1. Patient purchases "Premium Health Checkup" package
2. System auto-issues bundle: 3 mandatory coupons (blood test, X-ray, doctor consult) + right to choose 2 elective coupons from a pool of 8 wellness options
3. User sees all coupons in "My Coupons" with expiry dates
4. At each visit, presents coupon → staff scans QR → coupon consumed

**Customer Journey (Seasonal):**
1. System detects user's birthday is this month
2. Journey automation triggers → issues birthday eCoupon (20% off spa)
3. Coupon expires end of birth month (absolute_date expiry)

**Our Platform Mapping:** MOSTLY SUPPORTED
- Single/bundle coupons: rewards with admin/campaign/user visibility
- Flash rewards: `expiry_type = relative_mins`
- Seasonal: campaign-triggered rewards with absolute date expiry
- Admin-only and campaign-specific visibility modes
- **Enhancement needed:** Bundle creation (issuing multiple rewards as one package) — can be orchestrated via API but needs dedicated "bundle template" UI

### 3.8 Package Entitlement (Multi-Use, Deduct Per Use)

**What Samitivej Needs:**
- Package with N uses (e.g. "5 physiotherapy sessions")
- Deduct one use at a time (prevent double-use / over-use)
- Show remaining uses + expiry
- Handle edge cases: branch transfer, concurrent use at 2 locations, package change
- Track status: claimed vs actually used at hospital
- Full audit trail per use

**Who Deducts — HIS or Our Admin?**

The TOR explicitly states (B3.4): "การเข้าใช้บริการ 'แพ็กเกจหลายครั้ง/คูปองชุด' และการสร้าง/ตัดอัตโนมัติ หลัง ซื้อ/เข้ารับบริการ" — **auto-create and auto-deduct after purchase/service via HIS API.** So the primary flow is:

1. Patient arrives at hospital for treatment session
2. Hospital frontline staff records the visit in **HIS** (the hospital's own medical system)
3. HIS sends a "service_used" API event to our CRM
4. Our CRM **auto-deducts** 1 use from the entitlement (9/10 remaining)
5. Patient and staff see updated balance

Our admin panel is a **secondary/fallback** channel — for manual adjustments (e.g. admin reversal if HIS event was wrong, extending expiry, or handling edge cases). The hospital's frontline staff do NOT routinely use our admin system — they use their own HIS.

**What Happens if Package Details Change?**

Since we're the source of truth for entitlements, **ALL changes flow through our system.** HIS never directly modifies our data — it sends us events, and we process them.

| Change Type | How It Happens |
|---|---|
| **Service used → deduct 1 use** | Hospital staff records visit in HIS → HIS sends "service_delivered" event → our system deducts |
| **Doctor grants bonus sessions** | Clinical decision → staff enters in HIS → HIS sends "entitlement_adjustment" event → our system adds uses |
| **Admin extends expiry** | CRM admin directly adjusts in our back office |
| **Package swap** | Staff uses our admin OR hospital billing sends event → our system cancels old, issues new |
| **Branch transfer** | Staff updates in our admin → entitlement follows patient |

**HIS is NOT a frontend to our system.** HIS is a separate system that tells us about hospital events (service delivered, doctor decisions) via API. We process those events and update our records accordingly. The entitlement record always lives in and is modified by our system.

**Edge cases from TOR:** Branch transfer (patient moves from Sukhumvit to Srinakarin — entitlement must follow), concurrent use at 2 locations (must prevent via real-time locking), package swap (cancel old, issue new with prorated balance).

**Customer Journey:**
1. Patient buys "10-session rehab package" (via Well app or at hospital counter)
2. Purchase recorded in HIS → HIS sends event to CRM → CRM issues entitlement: 10 uses, valid 1 year
3. On each visit: hospital staff records treatment in HIS → HIS sends event → CRM auto-deducts 1 use
4. Patient sees updated balance in Well app: "9 sessions remaining, expires Dec 2026"
5. If patient uses at different branch → HIS sends event with branch code → CRM validates cross-branch rules → deducts if allowed

**Our Platform Mapping:** SUPPORTED
- Reward with `multi_qty` enabled (e.g. qty = 10)
- Per-use redemption tracked in `reward_redemptions_ledger`
- Real-time stock per user
- Anti-double-spend protection
- Audit trail on every deduction
- API endpoint for external systems (HIS) to trigger deductions
- **Enhancement needed:** Cross-branch usage rules, concurrent access locking, package swap/transfer workflow

### 3.9 Back Office — Coupon Management

**What Samitivej Needs:**
- Auto-create coupons after patient receives service (via HIS API)
- Manual creation (single or bundle) with editable conditions
- Central team creates master coupons/packages
- Department-level staff (50+ departments) can pick from master pool and issue to patients
- Template-based creation

**What "Auto-Create Coupons After Service" Actually Means:**

This is one of Samitivej's most important requirements. The TOR says (B2.1): "สร้างคูปองอัตโนมัติหลังคนไข้เข้ารับบริการ (แบบเดี่ยว/แบบชุดคูปอง) + sync Data Center-HIS (API)." Here's what this means with concrete examples:

- **Example 1 — Package Purchase Triggers Coupon Bundle:** Patient buys "Executive Health Checkup" at the hospital counter for 15,000 THB. HIS records the purchase → sends event to our CRM → CRM rule: "Executive Checkup purchase → auto-issue coupon bundle: 1x blood test voucher + 1x chest X-ray voucher + 1x specialist consultation voucher + 3x hospital café 100 THB vouchers." These coupons are the services included in the package — the patient uses them across multiple visits.

- **Example 2 — Post-Visit Retention Coupon:** Patient completes an OPD (outpatient) visit. HIS sends "visit_completed" event → CRM rule: "after any OPD visit → issue 50 THB hospital café coupon." This is a goodwill/retention gesture — rewarding the patient for visiting.

- **Example 3 — Department-Specific Coupon:** Patient visits the dermatology department. HIS sends department-specific event → CRM rule: "after dermatology visit → issue 10% discount coupon for next dermatology follow-up within 30 days." This drives repeat visits.

- **Example 4 — Bundle on Multi-Use Package:** Patient buys "5-session physiotherapy package." HIS event → CRM issues: 5x physiotherapy session entitlements + 5x parking coupons (one per session) + 1x café voucher bundle. All auto-issued in one operation.

**Who triggers it?** The Hospital Information System (HIS) is always the trigger. When a patient completes registration, makes a payment, completes a visit, or undergoes a procedure, HIS records it and sends an API event to our CRM. Our CRM has pre-configured rules that determine what coupons/entitlements to auto-issue per event type.

**Manual creation** is for ad-hoc situations: the patient relations team wants to issue a VIP apology coupon, or a department head creates a promotional coupon for a specific campaign.

**Our Platform Mapping:** SUPPORTED
- Admin creates rewards with various visibility/eligibility
- Reward templates via cloning existing rewards
- API endpoints for external systems (HIS) to trigger coupon issuance
- Department access via admin roles/permissions
- Visibility controls: user, admin, campaign
- **Enhancement needed:** Formal department-scoped admin roles (currently merchant-level), coupon bundle template system, HIS event-to-action rule configuration UI

### 3.10 Coins Rule Engine

**What Samitivej Needs:**
- Earn rate / bonus / expiry / limits / frequency caps
- Separate rates by service type (OPD vs IPD can differ)
- Special earn rates by time period, segment, or individual
- Maker-checker approval for point adjustments
- Stacking control (multipliers stack or not)
- Per-department/branch rules
- Delayed award (e.g. 7 days hold)
- Exclusions (e.g. don't count service X)
- Auto-multiplier by tier (Platinum = 2x)

**Our Platform Mapping:** SUPPORTED
- `earn_factor` + `earn_factor_group` with full configuration
- `earn_conditions` for product, category, brand, store, tier, persona
- `earn_factor_user` for personalized/individual rates
- Stacking control via group settings
- Store attribute sets for department/branch rules
- Delayed award via Inngest scheduled functions
- Tier-based multiplier via tier conditions on earn factors
- **Enhancement needed:** Maker-checker workflow for high-impact point adjustments

### 3.11 Back Office — Reports & Analytics

**What Samitivej Needs:**
- Coupon usage by department/store/package/individual
- Daily/monthly/yearly with auto-generation
- 5 report groups: Member & Engagement, Coin Economy, Campaign & Redemption, Action-to-Value Attribution, Operations
- Drill-down from overview to individual
- Compare multiple campaigns
- Sharable dashboards by role
- Export to Excel/CSV

**Our Platform Mapping:** PARTIAL — analytics layer needs development
- Basic transaction data available for reporting
- Wallet ledger and redemption ledger provide raw data
- **Custom dev needed:** Dashboard UI, report generation, scheduled report emails, role-based dashboard sharing

### 3.12 Reward Catalog Management (Back Office)

**What Samitivej Needs:**
- Manage reward catalog (rewards redeemable with coins)
- Multi-dimensional eligibility (tier + member type + tags)
- Dynamic coin pricing by customer dimension
- Bulk promo code import with partner source
- Real-time stock management
- Scheduling (start/end dates)

**Our Platform Mapping:** SUPPORTED
- Full reward management in admin
- Eligibility + pricing layers
- Promo code import via `code_import_system`
- Stock tracking per reward
- Date scheduling

### 3.13 Role/Permission/MFA (Back Office)

**What Samitivej Needs:**
- Role-based access control
- Granular permissions: view / create / edit / approve
- MFA for admin users
- Audit log for all actions
- Maker-checker for high-impact actions
- Superadmin for platform-level management

**Our Platform Mapping:** PARTIAL
- Admin users with Supabase Auth (email/password)
- Superadmin functions exist
- Audit logging on data mutations
- **Enhancement needed:** Granular role/permission system, MFA, maker-checker workflow

### 3.14 Well by Samitivej Integration (Super App — Full Loop)

**What Samitivej Needs:**
- Full loyalty loop: register, wallet, earn, redeem, tier, coupons, packages
- Push notifications from journeys
- Consent & preference management
- Personalized content by tier/member type/segment
- Multi-language (Thai, English, Chinese, Japanese)
- Fast loading with caching

**User Identity — How Do We Match Users Across Well and Our System?**

The TOR does NOT explicitly specify a primary key for user matching. In the Thai hospital context, the most likely approach:
- **HN (Hospital Number):** Every Samitivej patient has one. Well app already connects to HIS (which uses HN). This is the strongest candidate for cross-system identity.
- **Phone number:** Both systems would have this — works as a secondary match key
- **SSO linking:** During first access, Well passes its user token + HN → our system creates a mapping → future calls use the mapped identity

This should be clarified with Samitivej's tech team during technical design. We need to agree on: which identifier is the primary key, how the SSO token exchange works, and what happens if a user exists in Well but not in our CRM (or vice versa).

**Our Platform Mapping:** SUPPORTED via API
- All core loyalty features exposed via API/BFF endpoints
- Translation system with Thai, English, Chinese, Japanese
- Redis caching for fast reads
- **Custom dev needed:** SSO token validation endpoint for Well, push notification integration, consent management UI, deep link handling
- **To clarify with Samitivej:** Primary key for user matching (HN vs phone), Well's auth token format (JWT/OAuth), bi-directional user creation flow

### 3.15 Data Center-HIS Integration

**What Samitivej Needs:**
- Real-time events from Hospital Information System
- Triggers: patient visit → auto-issue coupon, purchase package → issue entitlement
- Bi-directional API (read patient data + write benefit status back)
- Reliable delivery with retry
- Event-to-action mapping (HIS event → coupon/entitlement/tier update)

**Our Platform Mapping:** SUPPORTED via architecture
- Event-driven architecture: CDC → Kafka → consumers → Inngest
- Purchase processing pipeline handles inbound events
- **Custom dev needed:** HIS-specific API adapter, bi-directional sync, event mapping configuration

### 3.16 E-commerce Integration (Shopee/Lazada/LINE MyShop)

**What Samitivej Needs:**
- Earn coins from e-commerce purchases across all channels
- Redeem eCoupons on e-commerce (use coupon as discount on next purchase)
- Tier benefits apply to e-commerce (e.g. Platinum gets exclusive marketplace discounts)
- Count e-commerce spending toward tier qualification
- Transfer coins from marketplace platforms (see section 3.6 — commercially dependent)

**How Marketplace Packages Work — With CRM Integration:**

The TOR (E1.5) says "ซื้อ/รับ eCoupon จาก e-commerce" and (E1.6) says users should see package entitlements and remaining uses in the app. This means marketplace-purchased items should **appear in the loyalty wallet immediately**, not require email vouchers.

**Target flow (with our CRM):**
1. User buys "Health Checkup Package" on Shopee for 5,990 THB
2. Shopee sends order webhook → our system receives order data
3. Our system matches buyer to CRM user (by phone number from the order)
4. CRM issues coupon/entitlement immediately → **appears in user's loyalty wallet** (Well/LINE/web)
5. User goes to hospital → shows loyalty app coupon (not an email voucher) → staff validates via HIS
6. CRM awards loyalty coins for the purchase

**Fallback (user not on loyalty program yet):**
- Order data stored as pending → user later registers → system retroactively matches and issues entitlements
- OR user falls back to the email voucher from Shopee → redeems at hospital → HIS records → CRM picks up then

**Current flow (without CRM — how it works today):**
User buys on Lazada → receives email voucher → calls to book → brings voucher to hospital. Our system replaces this manual flow with automatic coupon issuance into the loyalty wallet.

**Our Platform Mapping:** PARTIAL
- Shopee integration exists (webhook → Kafka → Inngest → database)
- Order ingestion and coin earning from marketplace purchases
- Marketplace purchases can count toward tier evaluation
- **Custom dev needed:** Lazada adapter, LINE MyShop adapter, coupon redemption on external platforms, tier benefit sync to e-commerce, reconciliation for marketplace orders that don't come through HIS

### 3.17 Single Customer View & Dynamic Segmentation

**What Samitivej Needs:**
- Unified view from: Well app, website, LINE, e-commerce, HIS
- Static segments (manual import)
- Dynamic segments (auto-update based on marketing conditions)
- Segment by: VIP status, chronic patient, annual checkup group, high coin balance
- Customer attributes: tier + member type + tags
- Auto-update when attributes change
- Export segments to external systems

**Our Platform Mapping:** PARTIAL
- User profile + persona + tags provide basic segmentation
- `persona_group_master` + `persona_master` for hierarchical grouping
- `tag_master` + `user_tags` for flexible tagging
- **Enhancement needed:** Dynamic segment builder with auto-refresh, segment export API, SCV dashboard UI

### 3.18 Journey Automation & Multi-channel Messaging

**What Samitivej Needs:**
- Trigger-based journeys: welcome, upsell, win-back, remind
- Channels: SMS, LINE, Email, App Push, Web Push with personalization
- Campaign performance tracking per funnel
- Frequency capping (max 3 messages/week)
- Suppression lists
- A/B testing
- Branching logic (if/else)
- Delay nodes and wait conditions
- Dynamic content personalization

**Our Platform Mapping:** NOT YET BUILT — future development
- No journey automation engine currently
- SMS sending capability exists (per-message cost)
- **Full custom dev needed:** Journey builder, multi-channel orchestration, branching logic, A/B testing, frequency capping

### 3.19 Lifestage / Hyperpersonalization (Optional)

**What Samitivej Needs:**
- Lifestage rules linked to HIS (upsell before appointment, follow-up after discharge)
- Auto-segments by patient journey stage
- Auto-campaigns by lifecycle event

**Our Platform Mapping:** NOT YET BUILT — future development
- Requires journey automation + HIS integration + segment builder
- Can be built on top of event-driven architecture once journey engine exists

### 3.20 AI Decisioning (Optional) — NOT IN TOR

**Important: This is NOT a Samitivej TOR requirement.** The CSV column "Specified in TOR" explicitly says **"No"** for this item. This is entirely our optional product offering — an upsell beyond what Samitivej asked for.

**What We Offer (our optional add-on):**
- Real-time AI review of customer profile on every event
- Next-best-offer recommendations based on patient history
- Predictive churn scoring (identify members likely to disengage)
- Behavioral pattern recognition (e.g. annual checkup regulars vs occasional visitors)
- Smart send-time optimization (send messages when each individual is most likely to read)
- Configurable guardrails (budget, frequency, channel limits)

**Our Platform Mapping:** NOT YET BUILT — future development
- Event-driven architecture provides the data pipeline foundation
- **Full custom dev needed:** ML models, recommendation engine, scoring system
- Position this as a Phase 2/3 enhancement in the proposal, not a Phase 1 commitment

### 3.21 Campaign & Privilege Management Console

**What Samitivej Needs:**
- Create/edit campaigns, privileges, eCoupons
- Set rules for coins, privileges, eCoupons
- Visibility conditions by tier/segment/time/campaign
- Mission template library
- Form builder for surveys
- Multi-language display settings
- Content block styling for branding

**Our Platform Mapping:** MOSTLY SUPPORTED
- Reward/campaign creation and management
- Earn rule configuration
- Eligibility conditions
- Form builder (`form_templates`, `form_fields`)
- Translation system (Thai, English, Chinese, Japanese)
- Display settings with block styles
- **Enhancement needed:** Mission template library, content block editor

### 3.22 Multi-Language Support

**What Samitivej Needs:**
- Thai, English, Chinese, Japanese, Arabic
- Covers: consumer pages, eCoupons, rewards, campaigns, notifications
- Marketing team manages translations from back office

**Our Platform Mapping:** SUPPORTED
- Translation system with `translations` table (entity-based)
- `ui_translations` for consumer-facing, `ui_translation_admin` for admin
- Fallback chain: requested → merchant default → English
- Currently supports: en, th, ja, zh
- **Enhancement needed:** Arabic language support

### 3.23 Health Package Purchase via Well App

**Where Does Purchase Happen? And Where is the Package Master?**

The TOR says two things that must be read together:
- **F3:** "ซื้อ Health Package ของ Samitivej เองได้ทันที ผ่าน Well by Samitivej **(ระบบหลังบ้านใช้ของ Vendor)**" — our system is the backend for Well app purchases
- **A2.6:** "ทำงานร่วมกับ CDP Hospital ได้: อย่างน้อยต้อง **consume master product/price** และใช้กับ offering/discount/journey/privilege" — we must consume the hospital's master product/price data

**This means the data has two layers:**

| Data | Source of Truth | Who Manages |
|---|---|---|
| **Medical service catalog** (what services exist, what types — e.g. "MRI scan", "blood test", "OPD consult") | **CDP Hospital** | Hospital team. We consume the CATALOG so marketing knows what services are available when building packages. |
| **Health Packages** (bundles of services + OUR pricing + conditions + eligibility + campaign rules) | **Our system** | Marketing team in our back office (F3.2). **We determine the package price.** |
| **Entitlement records** (who owns what, remaining uses) | **Our system** | Auto-issued on purchase. ALL changes (deductions, adjustments, extensions) flow through our system. |

**We determine the price.** CDP gives us the catalog (what services exist). Marketing builds packages from that catalog and sets the price. Example: CDP has "MRI, blood test, consult" as services → Marketing creates "Executive Checkup" bundling all three for 7,500 THB → Platinum gets 10% off → 6,750 THB. We control all pricing.

**Do we need base service prices from CDP?** Not strictly. We mainly need the **product catalog** (what services exist and their types) for: (1) building packages, (2) configuring earn rules per service type, (3) optionally showing "included services" in package details. We do NOT depend on CDP prices for our pricing — we set prices independently.

This is separate from packages sold on Shopee/Lazada (see section 3.16). The TOR wants BOTH channels:
1. **Our system (via Well app):** Full end-to-end purchase — browse packages we created, pay via Rocket, auto-issue entitlements
2. **Marketplace (Shopee/Lazada):** Customer buys there → order webhook → our system issues coupon to loyalty wallet → user brings loyalty app to hospital

**How Marketplace Package Purchase Works (Shopee/Lazada):**

Based on how Samitivej already operates on Lazada today:
1. Customer buys "Health Checkup Package" on Lazada for 5,990 THB
2. Lazada processes payment and sends customer an **email with a voucher/coupon code**
3. Customer calls Samitivej Contact Center or uses LINE to book appointment
4. Customer presents voucher code at hospital reception
5. Hospital validates in HIS → HIS sends event to our CRM
6. Our CRM issues ongoing entitlements (if multi-use) and awards loyalty coins

The initial voucher delivery is from Lazada (email). Our CRM picks it up once HIS records it. From that point, all entitlement tracking, coin earning, and loyalty features are in our system.

**What Samitivej Needs (for Well app direct purchase):**
- **Consumer:** Browse/search/filter health packages, view details (services, conditions, duration, locations), pay with money + coins, order confirmation, auto-issue entitlements, purchase history, usage tracking, post-purchase notifications
- **Back office:** Create/edit/publish packages, pricing/conditions/scheduling/quota, campaign pricing by journey/segment/tier, order management (confirm/cancel/refund), auto-issue entitlements + audit log, sales reports

**Our Platform Mapping:** PARTIAL — significant custom dev needed
- Reward catalog provides partial foundation (browse, redeem, stock management)
- Entitlement tracking via multi-qty rewards
- **Custom dev needed:** Product catalog (non-reward items for sale), shopping cart, payment gateway integration (Rocket — specified by Samitivej), order management, auto-issuance workflow, purchase history UI

### 3.24 Reward Pool / Pay-per-use

**What Samitivej Needs:**
- Central privilege pool with diverse rewards for members to choose from
- Pay-per-use model: Samitivej pays only when member actually redeems
- Includes fulfillment/shipping for physical rewards
- 2,000+ SKU reward pool (restaurant vouchers, gift cards, lifestyle products, partner privileges)

**Our Platform Mapping:** SUPPORTED
- Reward catalog with promo code import from multiple partners
- Partner attribution tracking
- Physical reward fulfillment status tracking
- Pay-per-use is a commercial model (not a system feature)
- Reward sourcing service is operational (our existing partner network)

### 3.25 Data Strategy & Infrastructure

**Our Platform Mapping:** SUPPORTED
- Event-driven architecture (CDC → Kafka → consumers → Inngest)
- Redis caching for high-speed reads
- Supabase PostgreSQL with real-time capabilities
- Auto-enrichment pipeline (purchase → currency → tier → segment)

### 3.26 Security / PDPA / Audit / Anti-fraud

**Our Platform Mapping:** MOSTLY SUPPORTED
- Tenant-level data isolation
- Supabase RLS (Row Level Security)
- PDPA consent management (basic)
- Audit logging on all mutations
- Anti-double-spend on coin/coupon
- Rate limiting on APIs
- Encryption at rest (Supabase) and in transit (TLS)
- **Enhancement needed:** Formal PDPA consent management UI, abuse detection system

---

## 4. Phase 2 Requirements

### 4.1 6 Member Types & Multi-Membership

**What Samitivej Needs:**
- 6 distinct membership types that can co-exist on one person:
  1. **Star with Entitlement (VIP)** — contracted VIP benefits
  2. **Paid** — purchased membership plan
  3. **Engagement/Tier** — earned through activity/spending
  4. **Corporate** — company contract benefits
  5. **Insurance** — insurance partner benefits
  6. **Exclusive Partner** — strategic partner benefits
- One person can hold multiple types simultaneously
- SCV must show all membership associations
- Cross-type precedence rules (show best benefit when overlapping)

**Customer Journey:**
1. A patient is a Corporate member (company contract) AND a Gold tier (spending)
2. Both types give them eCoupons — but different ones
3. The same discount exists in both programs at different rates (Corporate: 20%, Gold: 15%)
4. System automatically shows the higher value: 20% Corporate discount
5. In SCV, admin sees both membership types and all associated benefits

**Our Platform Mapping:** SUPPORTED with architecture
- `persona_group_master` for each membership type (6 groups)
- `persona_master` for sub-levels within each group
- `user_tags` for additional segmentation
- One user can have multiple personas (one per group) + unlimited tags
- Reward eligibility conditions can match across all dimensions
- **Enhancement needed:** Precedence/stackability rule engine for overlapping benefits, multi-membership SCV view

### 4.2 VIP Membership (Star with Entitlement)

**What Samitivej Needs:**
- Create Star levels via API or back office (e.g. Connex, Cheva/BDMS, VIP Insurance — these are real Samitivej VIP programs)
- Assign entitlements per Star level
- Two entitlement types (TOR explicitly defines these):
  1. **Single-use:** e.g. 5 free parking coupons — consumed one at a time
  2. **Period-based:** e.g. 30% off OPD — applies every visit, never consumed, valid for membership period
- When benefits overlap with other membership types, system picks highest value (TOR gives example: "Star VIP 30% vs Insurance 20% → แสดง 30%")
- Separate VIP segments with distinct benefit packages

**Customer Journey:**
1. Hospital assigns patient as "Connex VIP" via admin portal or API (e.g. after patient signs a VIP contract)
2. System auto-issues TWO types of entitlements:
   - **Pattern A (consumable):** 5 free parking coupons, 3 welcome spa vouchers → tracked in our reward system, decremented on use
   - **Pattern B (standing benefit):** 30% off all OPD, priority booking access → stored as benefit rules, checked by HIS at every visit
3. Patient visits hospital → HIS queries our Eligibility API → gets "30% off OPD" → applies automatically at billing
4. Patient uses parking coupon → 4/5 remaining
5. Patient also has Insurance membership (20% off OPD) → system already resolved precedence → 30% VIP wins

**Our Platform Mapping:** PARTIAL
- Persona group "VIP" with personas per Star level — SUPPORTED
- Single-use coupons via reward system — SUPPORTED
- **New development needed:**
  - Period-based benefit rules (standing discounts that never consume)
  - Eligibility API for HIS to query active benefits
  - Precedence engine (when multiple memberships give same benefit, return highest)
  - Auto-issuance workflow triggered by persona/VIP assignment

### 4.3 Paid Membership + Payment Gateway

**Is this in our system? Yes — and there are two purchase channels.**

The TOR says (C2): "ซื้อ Membership หรือ Subsciption Plan เช่น Divine Elite" and "ใช้ payment gateway ฝั่ง Rocket ทั้งหมด end to end."

| Purchase Channel | How It Works |
|---|---|
| **Well app (self-service)** | User taps "Buy Membership" in Well → Well opens our **CRM webview** (embedded web page inside the app, like LIFF in LINE) → our webview shows plan catalog → checkout → redirects to Rocket payment (in webview or Rocket SDK) → Rocket callback to our backend → membership activated + benefits issued → user returns to Well native UI |
| **Hospital counter (staff-assisted)** | Patient walks in → staff processes payment (hospital billing / Rocket) → HIS sends "membership_purchased" event → our system activates membership + auto-issues benefits |

Both channels result in **our system** activating the membership and issuing benefits. The difference is who initiates the payment. For the Well app flow, we fully control end-to-end. For the counter flow, we receive an event and process it.

**What Samitivej Needs:**
- Purchase membership plans (e.g. Divine Elite) — our system is the backend, Well app is frontend
- 3 benefit types per plan:
  1. **Mandatory coupons (คูปองบังคับ):** Auto-issued, fixed set — e.g. 12 monthly wellness check coupons
  2. **Elective coupons (คูปองเลือก):** User picks from a pool — e.g. choose 5 out of 20 wellness options
  3. **Standing discounts (ส่วนลดใช้ได้ไม่จำกัด):** Period-based, unlimited use — e.g. 10% off pharmacy during membership
- Tier within Paid program: cumulative spend across purchased plans determines tier
- **Duplicate rule:** If user buys 2 plans that include the same coupon, they get it twice (one per plan) — TOR explicitly states this
- Renewal management and expiry notifications

**Customer Journey:**
1. User opens Well app → browses membership plans → selects "Divine Elite 1-Year" for 50,000 THB
2. Well app calls our API → our system creates order → redirects to Rocket payment gateway
3. Payment succeeds → Rocket callback → our system activates membership
4. System auto-issues benefits:
   - 12 mandatory monthly wellness coupons (Pattern A — consumable rewards)
   - Access to elective pool: user picks 5 out of 20 options in the app (Pattern A)
   - 10% pharmacy discount for 1 year (Pattern B — standing benefit rule)
5. User later buys add-on "Dental Package" for 15,000 THB → gets dental coupons even if some overlap with Divine Elite's coupons (2 copies)
6. Cumulative spend (50k + 15k = 65k) → tier auto-upgrades within Paid program

**Our Platform Mapping:** PARTIAL — significant custom dev needed
- Reward system handles mandatory + elective coupons (Pattern A)
- Tier system tracks spending for progression
- **New development needed:**
  - Payment gateway integration (Rocket) with order flow
  - Membership plan catalog (browse, select, purchase)
  - Elective coupon selection UI (pick N from pool)
  - Duplicate coupon logic (one per plan purchased)
  - Standing benefit rules (Pattern B)
  - Subscription renewal and expiry notification workflow

### 4.4 Engagement / Tier-Based Membership

**What Samitivej Needs:**
- Multi-level tiers (e.g. Silver → Gold → Platinum)
- Benefits per tier
- Upgrade/downgrade/expiry criteria
- Tier calculation from: spending, visit count, behavioral data, years as customer
- Multi-site support (initially 2 branches)
- E-commerce spending counts toward tier
- 5 window types: rolling, fixed_period, anniversary, calendar_month, calendar_quarter
- Non-adjacent progression (can skip tiers)
- Burn rate per tier (Platinum: 1 coin = 0.50 THB, Silver: 1 coin = 0.25 THB)
- Immediate upgrade + scheduled maintenance checks

**Our Platform Mapping:** SUPPORTED
- `tier_master` with full condition configuration
- 5 window types supported
- Non-adjacent progression (skip tiers)
- Multi-path qualification (points OR sales OR orders)
- Burn rate per tier for coin-to-discount conversion
- Upgrade timing: immediate, end_of_month, fixed_date, rolling_days
- Per-branch via store attribute sets
- Marketplace purchase counting via e-commerce integration

### 4.5 Corporate Membership

**What is a Corporate Contract, conceptually?**

This is NOT about individual users buying something. It's a **B2B agreement** between Samitivej and a company. The concept:

- Samitivej's sales team signs a deal with Company ABC: "Your 200 employees get healthcare benefits at our hospital"
- The contract defines **levels** (Executive, General, Other) with different benefit packages per level
- Company HR sends an **employee roster** (list of names + levels) to Samitivej
- Those employees are imported into our system and auto-assigned their benefits
- Benefits include: standing discounts (Pattern B), single-use coupons (Pattern A), and access to specific reward catalog items

It's essentially a **3-layer configuration:** Contract → Level → Roster → Benefits auto-applied.

**What Samitivej Needs (from TOR C4):**
- Create corporate contracts/plans in back office (C4.1)
- Multi-level rights within one contract — e.g. Executive / General / Other (C4.2)
- Batch roster import via file and/or API (C4.3)
- Link each member to: company + level + effective period + status (C4.4)
- Display corporate status/benefits on all channels (C4.5)
- Benefit mapping per level — eCoupon, Privilege, discounts per the agreement (C4.6)
- Reports per company/contract/level and usage tracking for contract management (C4.7)

**Customer Journey:**
1. Samitivej signs contract with Company ABC for 200 employees (offline business deal)
2. Admin creates "Company ABC" corporate contract in back office with 3 levels: Executive, General, Other
3. Admin configures benefits per level:
   - Executive: 25% off OPD (standing discount) + 5 executive lounge passes (consumable) + priority booking
   - General: 10% off OPD (standing discount) + 2 café vouchers (consumable)
4. Company HR sends employee list → admin imports roster: 50 Executives, 150 General, each with effective date
5. Employee opens Well app → sees "Corporate Member: Company ABC — Executive"
6. Employee visits hospital → HIS queries our API → gets "25% off OPD" → applies at billing
7. At year end, admin exports usage report: "Company ABC used 320 OPD visits, 45 lounge passes redeemed"

**Our Platform Mapping:** PARTIAL — persona + reward covers the core structure, enhancements needed for governance and new benefit types.

**What our existing system covers (~40%):**
- Persona group "Corporate" with personas per level → architecture correct ✓
- Single-use coupon eligibility by persona → reward system ✓
- Bulk user import → basic capability exists ✓

**Enhancements to existing system:**
- Add contract metadata to persona_group (company name, contact, effective dates, status)
- Add effective date / expiry per user_persona assignment + auto-deactivation
- Batch roster import UI with validation (import CSV of 200 employees with levels)
- Reporting grouped by persona_group (company dimension)

**Genuinely new development:**
- **Standing benefit rules (Pattern B)** — period-based discounts per persona level, queried by HIS via Eligibility API
- **Eligibility API** for HIS to query "what benefits does patient X have?" with precedence resolution

### 4.6 Insurance Membership

**Is this the same structure as Corporate? Yes, with 2 key differences.**

Insurance Membership follows the exact same 3-layer pattern (Contract → Level → Roster → Benefits). The differences:

1. **Eligibility source:** Corporate gets roster from company HR (batch file). Insurance eligibility comes from **HIS** (hospital already has patient insurance data from registration) or **insurer API**. The TOR says (C5.3): "Eligibility Verification ได้ทั้งแบบ batch และ/หรือ API ตามความพร้อมของคู่สัญญา และ/หรือ Data Center-HIS."

2. **Stackability rules:** The TOR specifically adds (C5.6): "การใช้สิทธิ์ร่วม/ไม่ร่วม กับ Coins/eCoupon/ส่วนลดอื่น (stackability / precedence)." This means: some health packages allow insurance discount + coin discount together, others don't. Example: Package A (basic checkup) — insurance 30% + coins OK. Package B (premium surgery) — insurance discount only, no stacking. This per-package stackability rule is unique to Insurance.

**What Samitivej Needs (from TOR C5):**
- Create insurance partner contracts in back office — AIA, Allianz, Cheva/BDMS (C5.1)
- Multi-level rights per insurer — Premium / Standard / Other (C5.2)
- Eligibility verification via batch, API, or HIS data (C5.3)
- Link members to: insurer + level + effective period + status (active/suspended/expired) (C5.4)
- Display insurance status/benefits on all channels (C5.5)
- **Stackability rules per health package** — configurable (C5.6)
- Usage reports per insurer/level (C5.7)

**Customer Journey:**
1. Patient registers at Samitivej → hospital checks HIS → finds AIA Premium insurance linked
2. Our CRM receives insurance data → auto-assigns "Insurance: AIA Premium" persona
3. Patient browses health packages on Well app:
   - Package A (Annual Checkup, 8,000 THB): Insurance gives 30% off → 5,600 THB. Can also use 200 coins for additional 200 THB off → **5,400 THB** (stackable)
   - Package B (Premium Surgery, 150,000 THB): Insurance gives 20% off → 120,000 THB. **Cannot** combine with coins or other discounts (non-stackable per package rule)
4. System displays the correct combined/non-combined pricing at checkout based on stackability config
5. Insurance policy expires → our system auto-updates status → benefits deactivated → patient sees "Insurance: Expired" in app

**Our Platform Mapping:** PARTIAL — same persona structure as Corporate, with 2 unique additions.

**Same as Corporate (persona + reward):**
- Persona group "Insurance" → persona per insurer level → user assignment ✓
- Coupon eligibility by persona ✓

**Same enhancements as Corporate:**
- Contract metadata, assignment lifecycle, group-level reporting

**Insurance-unique new development:**
- **HIS-based auto-assignment** — instead of roster import, insurance status comes from HIS. When HIS says "patient has AIA Premium" → our system auto-assigns the persona. This is an event-driven persona assignment, not batch import.
- **Stackability rule engine** — per health package, which benefit types can combine. "Package A: insurance + coins OK. Package B: insurance only." This is genuinely new — no equivalent in our system.
- **Status lifecycle** — insurance policies expire/suspend/reactivate. Must auto-deactivate benefits when assignment expires. Enhancement to user_persona (effective dates + status).

### 4.7 Exclusive Partner Membership

**How does this work? Users don't "sign up" from a landing page.**

The flow is B2B-initiated, not consumer-initiated:

1. **Samitivej signs a partnership deal** with Partner A (e.g. Marriott hotels, a luxury airline, etc.)
2. **Partner sends their member list** to Samitivej (batch file or API) — these are Partner A's existing loyal customers
3. Members are imported into our system, tagged with "Partner A" + level (High / General)
4. When a tagged user accesses Samitivej's landing page, we check their partner status → show appropriate exclusive deals

**What are activity events for?** The TOR (F2 Back 2) says: "รองรับ API-based จาก partner ส่ง activity context เข้ามา." This is about **qualifying users for additional benefits** based on what they do with the partner. Example:
- User is tagged as "Marriott General" → sees basic health deals on landing page
- Marriott sends API event: "User completed 10+ stays this quarter" → our system upgrades to "Marriott Premium"
- User revisits landing page → now sees premium exclusive deals (30% off executive checkup instead of 15%)
- The TOR also says (F2 Back 3): partner can query our API to check "what does this user qualify for?" so the partner can show Samitivej benefits in their own app

**How do we verify/match users?** During roster import, users are matched by shared identifiers (phone number, email, or partner member ID). When the user later accesses our system (authenticated via Well/LINE/web), we look up their partner membership and show matching deals.

**What Samitivej Needs (from TOR C6 + F2):**
- Create partner contracts in back office (C6.1)
- Multi-level rights per partner (C6.2)
- Roster import (batch/API) (C6.3)
- Benefit mapping + visibility/redeemability per level (C6.4)
- Display partner status on all channels (C6.5)
- **Exclusive landing page per partner** (F2) — Samitivej controls content independently from partner
- Partner activity events via API → update user qualification (F2 Back 2)
- Match API: User ↔ Partner ↔ Activity Status for partner-side display (F2 Back 3)
- Partner-specific reporting (C6.7)

**Customer Journey:**
1. Marriott sends roster: 1,000 loyalty members (500 Gold, 500 Platinum)
2. Admin imports into our system → users tagged "Marriott Gold" / "Marriott Platinum"
3. Marriott Gold member opens Samitivej landing page (via link in Marriott app):
   - Sees: "Marriott Gold Health Benefit: 15% off annual checkup"
4. Later, Marriott sends API event: "User upgraded to Platinum"
5. User revisits landing page → now sees: "Marriott Platinum Health Benefit: 30% off executive checkup + complimentary wellness consultation"
6. Samitivej marketing team can change the deals anytime without Marriott's involvement (F2 Front 3: "สิทธิ์เปลี่ยนตามบริบท โดยฝั่งสมิติเวชเป็นคนกำหนด")

**Our Platform Mapping:** PARTIAL
- Persona group "Partner" with personas per level — user tagging works
- Reward eligibility for partner-specific deals — SUPPORTED
- **New development needed:**
  - Contract entity (same structure as Corporate/Insurance)
  - Partner landing page builder/CMS (content per partner, controlled by Samitivej)
  - Activity event API (receive events from partners, update user attributes)
  - Match/eligibility API (partner queries what benefits a user qualifies for)
  - Partner-specific reporting

### 4.8 Cross-Type Rules (Precedence/Stackability)

**What Samitivej Needs:**
- When one person has multiple membership types, determine which benefit wins
- Precedence: auto-select highest value benefit
- Stackability: define which benefits can combine
- Full audit trail for who changed rules
- Maker-checker for rule changes
- Single source of truth across all channels
- Export eligibility status via API

**Our Platform Mapping:** PARTIAL
- Current reward system handles multi-dimensional eligibility
- Specificity scoring (4→3→2→1 dimensions) with customer-favorable tiebreaking
- **Enhancement needed:** Explicit stackability rule configuration, precedence override management, cross-type benefit comparison engine

### 4.9 Exclusive Partner Landing Page

**What Samitivej Needs:**
- Dedicated landing page per partner (not mixed with mass campaigns)
- Dynamic conditions: show different deals based on user context
- Marketing team configures rules and picks privileges from central pool
- Partner sends activity context via API
- Match: User ↔ Partner ↔ Activity Status for eligibility

**Our Platform Mapping:** PARTIAL
- Campaign visibility conditions exist
- Reward eligibility by persona/tag
- **Custom dev needed:** Landing page builder/CMS, partner activity API, dynamic content rendering

---

## 5. Phase 3 Requirements

### 5.1 Samitivej Website (Starting with 2 Branches)

**Scope: Loyalty features only, NOT the full hospital website.**

The TOR (E2, lines 182-192) specifies exactly what the website must support. We don't build appointment booking, doctor profiles, or hospital content pages — those already exist on samitivejhospitals.com. We build **loyalty-specific pages/widgets** that integrate into or sit alongside the existing hospital website.

**What Samitivej Needs (from TOR E2):**
- Member profile, register/login
- Patient history display (from HIS — we display it, HIS provides data via API)
- Check coins, redeem coins
- View eCoupons
- Track content activities (read/like/share on existing hospital articles) → earn coins
- Send activity events to CRM for coin earning
- Consent & preference management

**How Article Tracking Integrates with Existing Website:**
The hospital already has health articles on their website. We add JavaScript tracking snippets to those pages. When a logged-in user reads/likes/shares → the snippet fires events to our CRM API. We don't rebuild the article pages — we instrument them.

**Our Platform Mapping:** SUPPORTED via API
- All BFF endpoints available for web integration
- Auth flow (LINE + OTP) works on web
- Wallet, rewards, tier data via API
- **Custom dev needed:** Loyalty page frontend (2 branches), JS tracking integration for existing content pages, embedded wallet/tier widgets

### 5.2 Additional Branch Websites (Optional, 5 More)

**Our Platform Mapping:** Same architecture, per-branch deployment
- Multi-site supported — shared CRM backend
- Per-branch earn rules and campaigns via store attributes

### 5.3 LINE OA per Branch (Starting with 2 Branches)

**What Samitivej Needs:**
- Register/login via LIFF/Webview
- Check coins/tier/eCoupons
- Burn coins / redeem coupons (redirect to CRM webview)
- Optional: trigger notifications from journey

**Our Platform Mapping:** SUPPORTED
- LINE OAuth authentication built-in
- LIFF web app framework support
- Rich menu webhook integration
- All wallet/reward operations via CRM webview
- **Custom dev needed:** LIFF frontend per branch, rich menu configuration

### 5.4 Additional Branch LINE OAs (Optional, 5 More)

**Our Platform Mapping:** Same architecture, per-branch LINE OA setup

---

## 6. Feature Mapping Summary

### Fully Supported (Core Platform)

| # | Feature | Platform Component |
|---|---------|-------------------|
| 1 | Registration/Login (LINE + OTP) | Auth system, `bff-auth-complete` |
| 2 | Coin Wallet & Balance | `user_wallet`, `wallet_ledger`, currency system |
| 3 | Earn Coins (Purchase/Behavior) | `earn_factor`, `earn_conditions`, activity system |
| 4 | Missions & Gamification | `mission`, milestone/standard types |
| 5 | Referral Program | `referral_codes`, `referral_ledger` |
| 6 | Reward Catalog & Redemption | `reward_master`, eligibility + pricing layers |
| 7 | eCoupon (Single/Multi-use) | Reward with digital fulfillment, promo codes |
| 8 | Package Entitlement (Multi-use) | Reward with `multi_qty`, per-use tracking |
| 9 | Tier System | `tier_master`, 5 window types, burn rates |
| 10 | Reward Pool / Partner Rewards | Promo code import, partner attribution |
| 11 | Multi-Language | Translation system (TH/EN/JA/ZH) |
| 12 | Coins Rule Engine | Earn factors, groups, conditions, multipliers |
| 13 | Reward Catalog Management | Admin reward CRUD, stock, scheduling |
| 14 | Store/Branch Classification | Store attribute sets for departments |
| 15 | Form Builder | `form_templates`, `form_fields`, conditional logic |
| 16 | Event-Driven Architecture | CDC → Kafka → consumers → Inngest |
| 17 | Basic Security & Audit | RLS, audit logging, anti-double-spend |
| 18 | E-commerce (Shopee) | Marketplace integration v2.0 |

### Partially Supported (Needs Enhancement)

| # | Feature | What Exists | What's Needed |
|---|---------|------------|---------------|
| 1 | 6 Member Types | Persona groups + tags | Multi-membership SCV view, precedence engine |
| 2 | VIP Membership | Persona assignment | Standing benefit rules (Pattern B), Eligibility API, precedence engine |
| 3 | Corporate/Insurance/Partner | Persona groups + reward eligibility | Persona metadata + lifecycle, batch roster, group reporting, stackability rules (Insurance) |
| 4 | Coupon Bundles | Individual rewards | Bundle template, multi-reward issuance |
| 5 | Coin Transfer | Marketplace earn | Partner transfer APIs, conversion rate management |
| 6 | Dynamic Segmentation | Tags + personas | Segment builder with auto-refresh |
| 7 | Reports & Analytics | Raw data in ledgers | Dashboard UI, scheduled reports, drill-down |
| 8 | Role/Permission | Basic admin roles | Granular permissions, MFA, maker-checker |
| 9 | HIS Integration | Event pipeline | HIS-specific adapter, bi-directional sync |
| 10 | Cross-Type Rules | Specificity scoring | Stackability configuration, explicit precedence |
| 11 | E-commerce (Lazada/LINE) | Shopee adapter | Platform adapters for Lazada, LINE MyShop |

### Requires New Development

| # | Feature | Description | In TOR? |
|---|---------|-------------|---------|
| 1 | **Standing Benefit Rules (Pattern B)** | Period-based entitlements that never consume, precedence logic, Eligibility API for HIS | Yes |
| 2 | **Stackability Engine** | Per-package rules for which benefits can combine (e.g. insurance + coins) | Yes |
| 4 | **Journey Automation** | Multi-channel marketing automation with triggers, branching, A/B testing | Yes |
| 5 | **Health Package Store** | Product catalog, cart, checkout, payment gateway, auto-issuance (our backend, Well frontend) | Yes |
| 6 | **Payment Gateway (Rocket)** | End-to-end payment integration for memberships and packages | Yes |
| 7 | **Paid Membership Management** | Subscription plans, renewal, elective coupon selection | Yes |
| 8 | **Partner Landing Pages** | Dynamic landing page builder per partner with activity-based dynamic deals | Yes |
| 9 | **Lifestage Rules** | HIS-linked patient journey stage automation | Yes (optional) |
| 10 | **Website Frontend** | Consumer website per branch (2 + 5 optional) | Yes |
| 11 | **LINE LIFF Frontend** | LIFF web app per branch LINE OA | Yes |
| 12 | **Push Notification System** | App push + web push integration | Yes |
| 13 | **Consent Management** | PDPA consent UI with per-channel, per-purpose granularity | Yes |
| 14 | **Advanced Analytics Dashboard** | 5-group reporting, drill-down, campaign comparison | Yes |
| 15 | **AI Decisioning** | Next-best-offer, churn prediction, behavioral analysis | **No — our optional upsell** |

---

## 7. User System — Pages & Mockup Scope

### Consumer App Pages (Well by Samitivej / Web / LINE LIFF)

| # | Page | Key Elements | Priority |
|---|------|-------------|----------|
| 1 | **Splash / Welcome** | Branding, language selector, login CTA | P1 |
| 2 | **Login / Register** | LINE button, phone OTP input, terms acceptance | P1 |
| 3 | **Profile Completion** | Dynamic form fields, conditional fields by member type, save | P1 |
| 4 | **Home Dashboard** | Coin balance widget, tier badge, quick actions (redeem, missions, coupons), personalized offers | P1 |
| 5 | **Wallet — Coins** | Current balance, earn/burn/expire history list with filters | P1 |
| 6 | **Wallet — My eCoupons** | Active coupons list (with status: available/used/expired), tap to view detail | P1 |
| 7 | **eCoupon Detail** | QR/Barcode/Serial code display, conditions, expiry, use button | P1 |
| 8 | **Wallet — Entitlements** | Package entitlements with remaining uses (e.g. "3/5 sessions used"), expiry | P1 |
| 9 | **Reward Catalog** | Browse rewards by category, coin price shown (dynamic by tier), stock indicator | P1 |
| 10 | **Reward Detail** | Full description, conditions, tier-specific pricing, redeem CTA | P1 |
| 11 | **Redemption Confirmation** | Coin deduction summary, confirm/cancel | P1 |
| 12 | **Tier / Membership Status** | Current tier, progress bar to next tier, benefit list per tier | P1 |
| 13 | **Membership Overview** | All membership types held (VIP, Corporate, Insurance, etc.) with benefits per type | P2 |
| 14 | **Missions** | Active missions list with progress bars, rewards shown | P1 |
| 15 | **Mission Detail** | Conditions breakdown, progress per condition, claim button | P1 |
| 16 | **Health Package Store** | Browse/search/filter packages, category tabs | P2 |
| 17 | **Package Detail** | Service details, pricing (money + optional coin discount), buy CTA | P2 |
| 18 | **Checkout / Payment** | Order summary, payment method (card + coins), confirm | P2 |
| 19 | **Order History** | Past purchases, status (paid/issued/used), tap for detail | P2 |
| 20 | **Referral** | Personal referral code/link, share buttons, referral count & rewards earned | P1 |
| 21 | **Notifications** | Journey messages, reward alerts, expiry reminders | P2 |
| 22 | **Profile / Settings** | Edit personal info, language preference, notification preferences, consent management | P1 |
| 23 | **Partner Landing Page** | Exclusive deals per partner, dynamic content by eligibility | P2 |
| 24 | **Transaction History** | Unified history: coins earned, redeemed, coupons used, packages purchased | P1 |

### Page Flow Summary

```
LOGIN FLOW:
Splash → Login (LINE/OTP) → Profile Completion → Home Dashboard

MAIN NAVIGATION (Bottom Tab):
Home | Wallet | Rewards | Missions | Profile

HOME DASHBOARD FLOW:
Home → [Coin Widget → Wallet]
     → [Tier Badge → Tier Status]
     → [Offers → Reward Detail → Redeem]
     → [Missions → Mission Detail → Claim]

WALLET FLOW:
Wallet → Coins Tab (balance + history)
       → eCoupons Tab → Coupon Detail (QR code)
       → Entitlements Tab → Entitlement Detail (remaining uses)

REWARD FLOW:
Reward Catalog → Reward Detail → Confirm Redemption → Success + Coupon Added

PACKAGE PURCHASE FLOW:
Package Store → Package Detail → Checkout → Payment → Order Confirmation → Entitlement Issued

MEMBERSHIP FLOW:
Profile → Membership Overview → [VIP Benefits | Corporate Benefits | Insurance Benefits]
        → Tier Status → Progress & Benefits

REFERRAL FLOW:
Profile → Referral → Share Code → Track Referrals
```

### Minimum Viable Mockup Set (Recommended)

For the proposal, prioritize these **12 key screens** that demonstrate the full customer journey:

1. **Login** — Shows LINE + OTP auth
2. **Home Dashboard** — The "wow" screen with wallet, tier, personalized offers
3. **Wallet (Coins + History)** — Core loyalty mechanic
4. **My eCoupons List** — Shows coupon portfolio
5. **eCoupon Detail with QR** — The "use at hospital" moment
6. **Entitlement (Package Usage)** — Key differentiator: "3/5 sessions remaining"
7. **Reward Catalog** — Browse & redeem experience
8. **Tier Status** — Progress visualization + benefit comparison
9. **Mission List** — Gamification engagement
10. **Health Package Store** — Purchase flow entry
11. **Referral Page** — Viral growth mechanic
12. **Profile / Membership Overview** — Shows multi-membership types

---

## 8. Pitching Day — Required Demo Scenarios

The TOR (Section H from CSV 2) specifies **6 demo scenarios** that must be presented during the pitch, plus evaluation criteria.

### Required Scenarios

| # | Scenario | What to Demonstrate |
|---|----------|-------------------|
| **A** | **Earn coins from web** | User visits website → login/register → reads article → clicks Like/Share → coins increase + history shows reason/time |
| **B** | **Redeem coins for eCoupon** | Open Well app or LINE webview → browse catalog → select privilege → confirm → receive code (QR/Barcode/Serial) + conditions + expiry → show redemption in back office report |
| **C** | **Package 5 uses (entitlement)** | Create package entitlement (via HIS event or simulated) → system issues 5 coupons → use 1 → shows 4 remaining (prevent double-use) |
| **D** | **Membership Tier** | Set tier rule → update spending data (simulated from data center) → tier changes → benefits visible on app/web/LINE change accordingly |
| **E** | **Partner Exclusive Landing Page** | Partner sends activity context via API → system matches user/partner/status → shows landing page with deal specific to that partner → marketing sets rules in back office |
| **F** | **Marketing Automation Soft Launch** | Create dynamic segment → set up 1 trigger journey (welcome/upsell/winback) → send via 2 channels + show report + guardrails (frequency cap/suppression) |

### Evaluation Criteria

| Weight | Criteria |
|--------|---------|
| **70%** | Fit with hospital needs (most important — demonstrate understanding of hospital workflows) |
| **20%** | Support team and service (pre and post-sales) |
| **10%** | Credibility and expertise |

**Evaluation committee:** CFO & Board of Innovation, Marketing Director (Samitivej Group), Managing Director (Well) & Board of Innovation, Assistant Hospital Director, CTO (Well) or IT Director

### Key Implication for Mockup

The 12-screen mockup from Section 7 should be designed to support all 6 demo scenarios. Scenario F (Marketing Automation) requires at minimum a journey builder concept, even if simplified for the pitch.

---

## 9. Data Architecture — Source of Truth Map

### Where Does Each Type of Data Live?

| Data Type | Source of Truth | Who Creates | Who Reads | Notes |
|-----------|----------------|-------------|-----------|-------|
| **Medical service catalog** (what services exist, types) | CDP Hospital | Hospital team | Our system consumes catalog for package building + earn rules | TOR A2.6: "consume master product/price" — we mainly need the CATALOG, not necessarily real-time prices |
| **Health Packages** (bundles, pricing, conditions) | Our system | Marketing team in our back office | Well app, website, LINE, HIS | F3.2: we manage catalog, **we determine price** |
| **User identity** | Our CRM (for loyalty), Well (for app), HIS (for medical) | Linked via phone/HN | All channels | Matching key TBD with Samitivej |
| **Membership status** (all 6 types) | Our system | Admin, API, HIS events | All channels, HIS (via Eligibility API) | Single Source of Truth per TOR |
| **Entitlement records** (remaining uses, expiry) | Our system | Auto-issued on purchase | Patient (app), staff (admin), HIS (via API) | ALL changes flow through our system — HIS sends events, we process |
| **Entitlement change triggers** | HIS sends events | Hospital staff actions (visit, doctor decision) | Our system receives and processes | HIS never directly modifies our data |
| **Coin wallet** (balance, history) | Our system | Earn rules, admin, HIS events | All channels | Single wallet, multiple frontends |
| **Standing benefits** (period-based discounts) | Our system (benefit rules) | Admin configures per contract/persona level | HIS queries via Eligibility API | New concept (Pattern B) |
| **Corporate/Insurance/Partner contracts** | Our system | Admin creates contracts | Admin, reporting | Contract → Level → Roster → Benefits |
| **Patient medical history** | HIS | Hospital | Our system displays (read-only) | E2.3: "Patient History (display from Internal)" |
| **Marketplace orders** | Shopee/Lazada | Customer purchases | Our system receives webhooks | Matched to CRM user by phone number |
| **Content engagement** (article read/like/share) | Our system | Website JS tracking captures | Earn rules process | User must be logged in on website |

### Integration Points Summary

```
CDP Hospital ──(master product/price)──→ Our System
                                            ↑
HIS ──────(service events, patient data)────┤
                                            ↓
Our System ──(eligibility API)──→ HIS (for billing)
                                            ↑
Shopee/Lazada ──(order webhooks)────────────┤
                                            ↓
Our System ──(loyalty features API)──→ Well App / Website / LINE LIFF
                                            ↑
Well App ──────(SSO token)──────────────────┘
```

### Open Questions for Technical Design (To Clarify with Samitivej)

1. **User matching key:** HN (hospital number) vs phone number vs both for cross-system identity
2. **Well SSO token format:** JWT? OAuth2? What claims does it contain?
3. **CDP product API:** What format? REST? How often does the catalog update? Do we poll or receive push? Do we need base prices or just the catalog (service names + types)?
4. **HIS event format:** What events does HIS emit? What payload structure? Real-time or batch? What event types (visit, payment, doctor decision, membership purchase)?
5. **Marketplace user matching:** Does Shopee order data include phone number in a format we can match?
6. **Bidirectional user creation:** If user registers on our system, do we need to notify Well/HIS? Or is linking sufficient?

---

## 10. High-Level Weekly Project Plan

**Timeline:** Mid-April 2026 → End of June 2026 (11 weeks)

- **Go-Live #1 (Phase 1):** ~Jun 9 — eCoupon & Coins Management + Basic Membership Management
- **Go-Live #2 (Phase 2):** ~Jun 23 — Advanced Membership & Marketing Automation

### Week Reference

| Week | W1 | W2 | W3 | W4 | W5 | W6 | W7 | W8 | W9 | W10 | W11 |
|------|----|----|----|----|----|----|----|----|----|----|-----|
| **Date** | Apr 14 | Apr 21 | Apr 28 | May 5 | May 12 | May 19 | May 26 | Jun 2 | Jun 9 | Jun 16 | Jun 23 |

---

### Phase 1 — eCoupon & Coins Management + Basic Membership (Go-Live: W9)

| Activity | W1 | W2 | W3 | W4 | W5 | W6 | W7 | W8 | W9 | W10 | W11 |
|----------|:--:|:--:|:--:|:--:|:--:|:--:|:--:|:--:|:--:|:---:|:---:|
| **KICKOFF / DISCOVERY / ALIGNMENT** | | | | | | | | | | | |
| Requirements workshop & scope confirmation | ██ | ██ | | | | | | | | | |
| User journey mapping (Well, LINE, Web) | ██ | ██ | | | | | | | | | |
| Data architecture & integration design (HIS, Well, e-commerce) | ██ | ██ | | | | | | | | | |
| User matching strategy (HN vs phone vs both) | ██ | ██ | | | | | | | | | |
| | | | | | | | | | | | |
| **LICENSE / SETUP INITIATION** | | | | | | | | | | | |
| Environment provisioning (Supabase, Redis, Kafka) | ██ | ██ | | | | | | | | | |
| Tenant & merchant configuration | ██ | ██ | | | | | | | | | |
| Auth method setup (LINE OAuth, OTP, Well SSO config) | | ██ | ██ | | | | | | | | |
| Multi-language base setup (TH, EN, JA, ZH) | | ██ | ██ | | | | | | | | |
| | | | | | | | | | | | |
| **API FLOW DETAILS (P1)** | | | | | | | | | | | |
| Well SSO token exchange flow | | ██ | ██ | | | | | | | | |
| HIS → CRM event mapping (purchase, visit, service) | | ██ | ██ | | | | | | | | |
| Coin earn / burn / expire API contracts | | ██ | ██ | | | | | | | | |
| eCoupon issuance & redemption API contracts | | | ██ | | | | | | | | |
| Reward catalog & promo code API contracts | | | ██ | | | | | | | | |
| | | | | | | | | | | | |
| **UI DESIGN (P1)** | | | | | | | | | | | |
| Consumer: wallet (coins, eCoupons, tier status) | | ██ | ██ | | | | | | | | |
| Consumer: reward catalog & redemption flow | | | ██ | ██ | | | | | | | |
| Consumer: registration & profile completion | | ██ | ██ | | | | | | | | |
| Back office: coupon management & earn rules | | | ██ | ██ | | | | | | | |
| Back office: reports & analytics dashboards | | | | ██ | | | | | | | |
| | | | | | | | | | | | |
| **CUSTOM DEVELOPMENT (P1)** | | | | | | | | | | | |
| Well SSO verification endpoint | | | | ██ | | | | | | | |
| Coin wallet & ledger (earn / burn / expire / history) | | | | ██ | ██ | | | | | | |
| Earn rule engine (purchase-based + behavior-based) | | | | ██ | ██ | | | | | | |
| eCoupon system (single / bundle / seasonal / mandatory / elective) | | | | | ██ | ██ | | | | | |
| Package entitlement (multi-use, per-use deduct, cross-branch) | | | | | ██ | ██ | | | | | |
| Reward catalog (eligibility + dynamic coin pricing + stock) | | | | ██ | ██ | | | | | | |
| Mission & gamification engine | | | | | ██ | ██ | | | | | |
| Referral system (invite code, dual-reward) | | | | | | ██ | | | | | |
| Coins rule engine (rates, multipliers, caps, delayed award) | | | | ██ | ██ | | | | | | |
| Back office: coupon CRUD, earn rule config, reward catalog mgmt | | | | | ██ | ██ | ██ | | | | |
| Reports & analytics (basic dashboards, export) | | | | | | ██ | ██ | | | | |
| Role / permission (basic RBAC + audit logging) | | | | | | ██ | ██ | | | | |
| Security: PDPA consent, anti-fraud, rate limiting | | | | | | | ██ | | | | |
| | | | | | | | | | | | |
| **INTEGRATION DEV — MIDDLEWARE (P1)** | | | | | | | | | | | |
| HIS event adapter (receive visit / payment / service events) | | | | | ██ | ██ | ██ | | | | |
| HIS → CRM auto-coupon issuance pipeline | | | | | | ██ | ██ | | | | |
| Shopee marketplace webhook integration | | | | | ██ | ██ | | | | | |
| Well app SSO handshake integration | | | | | ██ | | | | | | |
| | | | | | | | | | | | |
| **INTEGRATION DEV — ADJUST / ADD OPEN APIs (P1)** | | | | | | | | | | | |
| BFF endpoints for Well app (wallet, rewards, coupons, tier) | | | | | ██ | ██ | ██ | | | | |
| LINE LIFF endpoints (auth, wallet, redeem) | | | | | | ██ | ██ | | | | |
| Article tracking JS SDK (read / like / share events) | | | | | | ██ | | | | | |
| Admin API (coupon CRUD, earn rule config, promo code import) | | | | | ██ | ██ | ██ | | | | |
| | | | | | | | | | | | |
| **SIT / TESTING (P1)** | | | | | | | | | | | |
| End-to-end earn → burn → redeem flow | | | | | | | ██ | ██ | | | |
| HIS event → auto-coupon issuance | | | | | | | ██ | ██ | | | |
| Multi-channel wallet consistency (Well + LINE + Web) | | | | | | | | ██ | | | |
| Promo code import & redemption | | | | | | | ██ | | | | |
| Mission completion & reward auto-issuance | | | | | | | | ██ | | | |
| | | | | | | | | | | | |
| **UAT (P1)** | | | | | | | | | | | |
| Client testing with real hospital scenarios | | | | | | | | ██ | ██ | | |
| Well app integration testing with Samitivej team | | | | | | | | ██ | ██ | | |
| LINE channel testing | | | | | | | | | ██ | | |
| HIS live event testing (if sandbox available) | | | | | | | | ██ | ██ | | |
| Bug fixes & stabilization | | | | | | | | ██ | ██ | | |
| | | | | | | | | | | | |
| **🟢 GO-LIVE #1** | | | | | | | | | **GO** | | |

---

### Phase 2 — Advanced Membership & Marketing Automation (Go-Live: W11)

| Activity | W1 | W2 | W3 | W4 | W5 | W6 | W7 | W8 | W9 | W10 | W11 |
|----------|:--:|:--:|:--:|:--:|:--:|:--:|:--:|:--:|:--:|:---:|:---:|
| **API FLOW DETAILS (P2)** | | | | | | | | | | | |
| Eligibility API design (HIS queries active benefits) | | | ██ | ██ | | | | | | | |
| Standing benefit rules (Pattern B) contracts | | | ██ | ██ | | | | | | | |
| Paid membership purchase + Rocket payment flow | | | ██ | ██ | | | | | | | |
| Corporate / Insurance roster import API | | | | ██ | | | | | | | |
| Cross-type precedence & stackability rules | | | | ██ | | | | | | | |
| | | | | | | | | | | | |
| **UI DESIGN (P2)** | | | | | | | | | | | |
| Consumer: membership plan catalog & purchase flow | | | | ██ | ██ | | | | | | |
| Consumer: elective coupon selection (pick N from pool) | | | | ██ | ██ | | | | | | |
| Back office: corporate / insurance contract management | | | | | ██ | ██ | | | | | |
| Back office: partner landing page template | | | | | ██ | ██ | | | | | |
| Back office: advanced SCV dashboard | | | | | | ██ | | | | | |
| | | | | | | | | | | | |
| **CUSTOM DEVELOPMENT (P2)** | | | | | | | | | | | |
| Standing benefit rules engine (Pattern B — period-based, non-consumable) | | | | | ██ | ██ | ██ | | | | |
| Eligibility API for HIS (query active benefits + precedence resolution) | | | | | ██ | ██ | ██ | | | | |
| Paid membership purchase flow + order management | | | | | ██ | ██ | ██ | | | | |
| Elective coupon selection (pick N from pool, duplicate rule) | | | | | | ██ | ██ | | | | |
| Corporate contract management (contract → level → roster → benefits) | | | | | | ██ | ██ | ██ | | | |
| Insurance membership (HIS-based auto-assign, stackability rules) | | | | | | | ██ | ██ | | | |
| Exclusive partner membership (landing page, activity events) | | | | | | | ██ | ██ | | | |
| Cross-type precedence & stackability engine | | | | | | ██ | ██ | ██ | | | |
| Dynamic segmentation builder (auto-refresh segments) | | | | | | | ██ | ██ | | | |
| Journey automation (welcome, post-visit, birthday triggers) | | | | | | | ██ | ██ | ██ | | |
| Maker-checker workflow (high-impact actions) | | | | | | | | ██ | | | |
| Subscription renewal & expiry notifications | | | | | | | | ██ | ██ | | |
| | | | | | | | | | | | |
| **INTEGRATION DEV — MIDDLEWARE (P2)** | | | | | | | | | | | |
| Rocket payment gateway integration (end-to-end) | | | | | | ██ | ██ | ██ | | | |
| HIS Eligibility API (bidirectional — query & respond) | | | | | | ██ | ██ | ██ | | | |
| Insurance eligibility verification (HIS / insurer API) | | | | | | | ██ | ██ | ██ | | |
| Partner activity event ingestion API | | | | | | | ██ | ██ | | | |
| Lazada / LINE MyShop marketplace adapters | | | | | | | | ██ | ██ | | |
| | | | | | | | | | | | |
| **INTEGRATION DEV — ADJUST / ADD OPEN APIs (P2)** | | | | | | | | | | | |
| Membership purchase endpoints (for Well app checkout) | | | | | | ██ | ██ | ██ | | | |
| Corporate / Insurance roster import endpoints | | | | | | | ██ | ██ | | | |
| Eligibility query API (for HIS billing system) | | | | | | ██ | ██ | ██ | | | |
| Partner match API (partner queries user benefits) | | | | | | | ██ | ██ | ██ | | |
| Advanced reporting & export APIs | | | | | | | | ██ | ██ | | |
| | | | | | | | | | | | |
| **SIT / TESTING (P2)** | | | | | | | | | | | |
| End-to-end membership purchase with Rocket payment | | | | | | | | | ██ | ██ | |
| Eligibility API with HIS (bidirectional) | | | | | | | | | ██ | ██ | |
| Corporate / Insurance benefit auto-assignment | | | | | | | | | ██ | ██ | |
| Cross-type precedence resolution testing | | | | | | | | | | ██ | |
| Journey trigger & multi-channel notification testing | | | | | | | | | | ██ | |
| | | | | | | | | | | | |
| **UAT (P2)** | | | | | | | | | | | |
| Client testing: paid membership purchase flow | | | | | | | | | | ██ | ██ |
| Corporate roster import with real company data | | | | | | | | | | ██ | ██ |
| Insurance eligibility with HIS live data | | | | | | | | | | ██ | ██ |
| Partner landing page review & approval | | | | | | | | | | | ██ |
| Marketing automation scenario testing | | | | | | | | | | | ██ |
| Bug fixes & stabilization | | | | | | | | | | ██ | ██ |
| | | | | | | | | | | | |
| **🟢 GO-LIVE #2** | | | | | | | | | | | **GO** |

---

### Key Assumptions

1. **Parallel execution** — Phase 2 design work begins in W3 while Phase 1 development is underway, maximizing the compressed timeline.
2. **Kickoff covers both phases** — A single discovery/alignment period in W1–W2 scopes requirements for both phases.
3. **License & environment setup** starts immediately at kickoff (W1) so infrastructure is ready before development begins.
4. **Phase 1 Go-Live (W9, ~Jun 9)** delivers: Coin wallet, earn rules, eCoupon system, reward catalog, missions, referral, basic membership, basic reports, LINE + Well integration.
5. **Phase 2 Go-Live (W11, ~Jun 23)** delivers: Standing benefits (Pattern B), Eligibility API, paid membership + Rocket payment, corporate/insurance/partner membership, cross-type precedence, dynamic segments, journey automation.
6. **SIT overlaps with late development** — integration testing begins as features are completed, not after all development finishes.
7. **UAT requires client participation** — Samitivej team availability during UAT weeks is critical to hitting go-live dates.
8. **HIS sandbox availability** — Testing of HIS integration in SIT/UAT depends on Samitivej providing a test environment or sandbox API.
9. **Rocket payment sandbox** — Payment gateway testing requires Rocket sandbox credentials from Samitivej.

---

*Document generated for Samitivej loyalty program proposal. All feature assessments based on current platform capabilities as of March 2026.*
