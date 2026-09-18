# Feature Guide: Currency (Points & Wallets)

## 1. Overview

Currency is the "earn" side of the loyalty loop — the mechanism that converts member activity into tangible value they can later spend on rewards. When a member makes a purchase, completes a mission, or refers a friend, the system calculates how much currency to award based on merchant-configured earn rules, then records it to the member's wallet. This is the engine that makes every other loyalty feature meaningful: tiers need points to track progress, rewards need points to redeem, and campaigns need points to incentivize.

The platform supports two currency types with fundamentally different behaviors. Points are fungible — all points are interchangeable and stored as a single balance. Tickets are non-fungible — each ticket type (raffle entries, VIP passes, parking passes) maintains an independent balance, and tickets cannot be exchanged between types. A single purchase can award both points and multiple ticket types simultaneously, each calculated and tracked separately.

Merchants control earning through a layered rule system: rate factors set the base conversion (e.g., "spend 100 THB = 1 point"), multiplier factors boost earnings for specific conditions (e.g., "3x on weekends for Gold members"), and expiry rules manage liability by expiring unused currency after configurable periods. The system processes awards through a durable execution pipeline — purchases flow through CDC, calculation, and Inngest workflows — supporting delayed awards, automatic cancellation on refunds, and four-level idempotency guarantees.

## 2. Key Concepts

**Points** — Fungible loyalty currency. All points are interchangeable, stored as a single balance per member. Used for reward redemption and tier progression. Example: Member has 500 points → redeems 200 → balance is 300.

**Tickets** — Non-fungible currency where each type is distinct. Each ticket type (e.g., "Christmas Raffle", "VIP Access") has its own independent balance. Cannot be exchanged between types. Example: Member has 5 raffle tickets and 2 VIP passes — these are separate, unrelated balances.

**Earn Factor** — A rule determining how members earn currency. Two types: *rate factors* convert spend to currency ("100 THB = 1 point"), and *multiplier factors* boost earnings by a multiplication factor ("3x on shoes"). Each factor can target points or a specific ticket type.

**Earn Factor Group** — A container bundling related earn factors with shared properties: validity window, stacking behavior, and activation status. Individual factors inherit group settings unless explicitly overridden.

**Earn Conditions** — Qualifying criteria for an earn factor: tier level, product SKU/brand/category, store attributes, or persona. An `exclude` flag can invert a condition to remove specific items from eligibility. Empty conditions = applies to entire transaction.

**Stackable** — A group-level setting controlling multiplier interaction. When true, multipliers combine additively (2x + 1.5x = 3.5x total). When false, only the best multiplier per scope applies — though one product-specific and one transaction-wide multiplier can coexist since they operate on mutually exclusive portions of the transaction amount.

**Multiplier Calculation Mode** — Merchant-level setting (`multiplier_additive`). *Total Rate mode* (default): 5x multiplier on 10 base = 50 total (5 times base). *Additive mode*: 5x on 10 base = 60 total (base + 5 times base).

**Components** — How currency is categorized in the wallet: `base` (from rate conversion), `bonus` (from multipliers), `adjustment` (admin corrections), `reversal` (refund deductions).

**Signed Amount** — Directional value on ledger entries. Positive for earning, negative for burns and reversals. The `amount` field is always the absolute value.

**Source Types** — Origin of a wallet transaction: `purchase` (buying products), `referral` (referral bonuses), `mission` (task completion), `campaign` (bulk awards), `manual` (admin adjustments).

**Personalized Offers** — Private earn factors assigned to specific members via `earn_factor_user`. Evaluated alongside public rules; the better value applies. Example: Birthday month 5x multiplier assigned only to the birthday member.

**Expiry Modes** — Three ways currency can expire: *TTL* (X months after earning), *Fixed Frequency* (at fiscal period boundaries — monthly, quarterly, semi-annual, annual), *Absolute Date* (tickets only, all expire on a specific date).

**Minimum Period Protection** — Prevents recently earned currency from immediate expiry in fixed frequency mode. Example: Points earned in November with quarterly expiry and 6-month minimum won't expire until the following May.

**Deductible Balance** — The remaining usable portion of a currency award that is subject to expiry. Original amount minus any redemptions already made against it.

**Credit Ticket Type** — A ticket type where `is_credit = true`. Redemption triggers an external platform credit API call (e.g., Shopify store credit) instead of a standard wallet burn. One credit ticket type per platform per merchant.

**Ticket Codes** — Unique printable codes (e.g., `SYN-A7X3B2`) assigned to individual ticket earnings, used for raffles and event campaigns. Codes are pre-generated into a pool and assigned atomically using `FOR UPDATE SKIP LOCKED`.

## 3. Configuration Reference

### Earn Rate (Basic Mode)

| Setting | What it controls | Example | Default |
|---|---|---|---|
| Target currency | Points or a specific ticket type | `points` | Required |
| Different rate per tier | Toggle tier-specific rates | true | false |
| Single rate | Spend amount per 1 currency unit (when uniform) | 30 (THB per point) | — |
| Per-tier rates | Rate per tier (when differentiated) | Gold=35, Silver=30, Platinum=25 | — |
| Excluded products | Products/SKUs/brands/categories excluded from earning | [gift cards, sale items] | None |

### Multipliers (Basic Mode)

| Setting | What it controls | Example | Default |
|---|---|---|---|
| Allow stacking | Whether multipliers combine or best-only | true | true |
| Multiplier rate | Multiplication factor | 3 (= 3x) | — |
| Active status | Enable/disable this multiplier | true | true |
| Window start/end | Validity period | Jun 1 – Jun 30 | No restriction |
| Timing | Day-of-week and hour constraints | Weekend (Sat, Sun) | All times |
| Tiers | Which tiers qualify | [Gold, Platinum] | All tiers |
| Include products | Products eligible for this multiplier | [shoes, accessories] | All products |

### Expiry Settings

| Setting | What it controls | Example | Default |
|---|---|---|---|
| Expiry enabled | Whether currency expires | true | false |
| Expiry mode | TTL, fixed_frequency, or absolute | `ttl` | — |
| TTL months | Months until expiry (TTL mode) | 12 | — |
| Frequency | Period boundary (fixed mode) | `quarterly` | — |
| Fiscal year end month | Fiscal calendar alignment | 6 (June) | 12 (December) |
| Minimum period months | Earliest expiry protection | 3 | — |
| Absolute expiry date | Fixed date (tickets only) | 2025-12-31 | — |

### Award Timing

| Setting | What it controls | Example | Default |
|---|---|---|---|
| Delay days | Calendar days before awarding | 1 | 0 (immediate) |
| Delay minutes | Rolling minutes before awarding | 120 | 0 |
| Award time | Specific time of day to award | 08:00 | — |
| Award timezone | Timezone for time interpretation | Asia/Bangkok | — |

## 4. Admin Journey

**Repo:** `Rocket-CRM/loyalty-admin`

**Route map:**

| Page name | Current route | BFF / data source |
|---|---|---|
| Basic Currency Config | `/merchant-currency-settings/basic` | `bff_get_basic_currency_config()`, `bff_upsert_basic_currency_config()` |
| Currency Settings | `/merchant-currency-settings` | `bff_get_currency_config()`, `bff_upsert_currency_config()` |
| Earn Studio (advanced) | `/earn-studio` | `bff_get_earn_studio_config()`, `bff_upsert_earn_studio()` |

### 4a. Configure Basic Earn Rate

1. Open **Basic Currency Config** — select target currency (points or ticket type)
2. Toggle "Different rate per tier" — off for a single rate, on for per-tier rates
3. If single rate: enter the spend amount per 1 currency unit (e.g., 30 = spend 30 THB for 1 point)
4. If per-tier: a row appears for each tier — enter rate per tier (lower number = better rate for that tier)
5. Optionally add excluded products via pill selector (SKU, product, brand, or category)
6. Click **Save** — toast confirms success

### 4b. Add Multipliers

1. On **Basic Currency Config**, scroll to the Multipliers section
2. Toggle "Allow Stacking" to control whether multipliers combine
3. Click **"+ Add Multiplier"** to create a multiplier card
4. Configure: multiplier rate, active toggle, window dates, timing (weekend/weekday/custom), eligible tiers, and included products
5. Repeat for additional multipliers — each appears as a separate card
6. Delete a multiplier via the trash icon on its card
7. Click **Save** — backend handles creation, update, and deletion of factors automatically

### 4c. Configure Expiry and Award Timing

1. Open **Currency Settings** — two sections: Points Expiry and Currency Award Timing
2. Points Expiry: enable checkbox, select mode (TTL, fixed frequency), configure mode-specific fields
3. Award Timing: select delay type (immediate, delayed by days/minutes, or scheduled time), configure accordingly
4. Click **Save** — COALESCE-based upsert safely merges with existing config

### 4d. Advanced Earn Rules (Earn Studio)

1. Open **Earn Studio** — displays all earn factor groups in a sidebar
2. Select a group to view its factors and conditions in the main panel
3. Configure factor-level settings: type (rate/multiplier), target currency, conditions, thresholds, operators
4. This page handles complex scenarios that exceed basic mode: multi-entity conditions, threshold rules, personalized offers, and shared condition groups
5. If basic mode detects configuration too complex for its UI, it redirects to Earn Studio with a `mode: "not_basic"` indicator

## 5. Member Experience

**Repo:** `Rocket-CRM/loyalty-user`

**Route map:**

| Page / Component | Current route | Data source |
|---|---|---|
| Homepage Profile Card | `/` | `bff_get_display_blocks_cached(p_page: 'homepage')` |
| Wallet Drawer | Bottom-sheet from Homepage | `bff_get_reward_history()`, `bff_get_currency_history()` |
| History Drawer | Bottom-sheet from Homepage/Profile | `bff_get_currency_history()`, `bff_get_user_history_menu()` |
| Earn Drawer | Bottom-sheet from navigation | `bff_get_earn_channels()` |

### 5a. View Points Balance

1. Member opens the app — **Homepage** displays a Profile Card block
2. Profile Card shows: tier name (gradient text), current points balance (large number with star icon), progress to next tier, and persona badge
3. Points balance updates after each earn/burn event

### 5b. View Wallet and History

1. Member taps the History link on the points card → **Wallet Drawer** opens as a bottom-sheet
2. Wallet header shows: tier card, points balance card, and a "Redeem" button
3. Tabs: My Rewards, Packages, Benefits — each with filtered lists
4. Tapping "History" opens a full-screen overlay with tabs: Point, Reward, Package, Campaign, Expired
5. Currency history shows each transaction as a row: title, source, date, and signed amount badges (+/- with color coding)
6. Sub-filters on Currency tab: Points, Tickets (dynamically generated per ticket type)

### 5c. Earn Points via Channels

1. Member taps an earn navigation item → **Earn Drawer** opens
2. Tabs show available earn methods: receipt upload, marketplace order claim, QR code scan, referral, external links
3. Each method has its own screen within the drawer
4. On successful earn: success popup displays with points/tickets awarded

## 6. Perspectives

### 6a. For Customer Success / Support

**Elevator pitch**: "Members earn points and tickets automatically when they shop or complete activities. The system calculates how much to award based on the rules you've set up — earn rates, multipliers, and bonus campaigns. Members see their balance on the app homepage and can check full history in the wallet."

**Top 5 support questions:**

| Question | Answer |
|---|---|
| "Member didn't receive points after purchase" | Check award timing config — merchant may have delayed awards (next day at 8 AM). Also verify the transaction completed successfully in purchase ledger. |
| "Points amount seems wrong" | Check which earn rate and multipliers applied. The system always picks the best rate for the member. Review the transaction in currency history for applied factors. |
| "Points expired unexpectedly" | Check expiry mode (TTL, quarterly, etc.) and minimum period protection. Expiry runs daily at 2 AM. Only the unused portion expires — any redeemed amount is protected. |
| "Member has tickets but can't see them" | Tickets display separately from points. Check the Currency tab in History — tickets appear under their own sub-filter. Verify the ticket type is still active. |
| "Refund processed but points not reversed" | Reversals are proportional to refund amount and use the original earn rate (not current rates). Check if the reversal workflow completed in the system. |

### 6b. For Marketing

**Value proposition**: Currency turns every purchase into a reason to return. Members earn points at rates the merchant controls — from simple flat rates to multi-dimensional rules that reward specific products, tiers, time windows, and personas differently. The multiplier system enables promotional campaigns ("Double Points Weekend") without changing base program economics.

**Use-case stories:**

1. **Café chain** — Sets base rate at 25 THB per point. Gold members earn at 20 THB per point (better rate). Weekend multiplier of 2x drives Saturday traffic. Birthday members get personalized 5x offers.

2. **B2B distributor** — Uses quantity thresholds: "Buy 50+ bags of cement → 5x points." Secondary UOM thresholds handle bulk: "Buy 2+ tonnes → 10x." Product-specific multipliers promote high-margin items without inflating points on commodities.

3. **Event venue** — Awards both points and event-specific tickets simultaneously from a single purchase. Raffle tickets (non-fungible, code-assigned) for prize draws, parking passes for convenience, and points for the general rewards catalog.

**Differentiators:**
- **Dual currency model** — fungible points and non-fungible tickets from the same transaction
- **Multi-dimensional earn rules** — tier, product, store, persona, and time conditions compose freely
- **Delayed award support** — merchants can hold points for 24 hours, enabling refund-window protection before awarding
- **Durable execution** — four-level idempotency guarantees exactly-once processing at any scale

### 6c. For Testers

**Config → expected behavior:**

| Config | Expected behavior |
|---|---|
| Rate = 100 THB/pt, purchase 500 THB | 5 points awarded (base component) |
| Rate = 100, multiplier = 3x, stackable = true | Base 5 + bonus 10 = 15 points |
| Two multipliers (2x, 3x), stackable = false | Best multiplier (3x) wins → base 5 + bonus 10 |
| Non-stackable, product multiplier 3x on shoes (200 THB), transaction multiplier 5x | Shoes: 2 × 3 = 6 pts. Remainder (300 THB): 3 × 5 = 15 pts. Total: 21 |
| `multiplier_additive = false`, 5x on 10 base | 50 total (5 × base) |
| `multiplier_additive = true`, 5x on 10 base | 60 total (base + 5 × base) |
| Delay days = 1, award time = 08:00 | Points appear next day at 8 AM, not immediately |
| Refund 50% of purchase | 50% of original points reversed (using historical rate) |
| Expiry mode = TTL, 6 months, earned Jan 15 | Expires Jul 15. Only unused portion expires. |
| Expiry mode = fixed_frequency quarterly, min 3 months, earned May 15 | Expires Sep 30 (next quarter, respects minimum) |
| Ticket type with absolute expiry Dec 31 | All tickets of this type expire Dec 31 regardless of earn date |
| Purchase earns both points and tickets | Separate ledger entries with correct `target_entity_id` (null for points, UUID for tickets) |

**Business rules as assertions:**

- ASSERT: Only one rate factor per currency type applies — the best rate (lowest spend per unit) wins
- ASSERT: Product-specific multipliers consume their portion; transaction-wide multipliers apply to remainder only
- ASSERT: Reversals use historical calculation data from `wallet_ledger.metadata`, not current earn factors
- ASSERT: Reversal amount = original amount × (refund amount / purchase amount)
- ASSERT: Points `target_entity_id` is always NULL; tickets always have a `ticket_type.id`
- ASSERT: Each ticket type balance is independent — earning raffle tickets does not affect parking passes
- ASSERT: Expiry processes only the deductible balance (original minus redeemed)
- ASSERT: Minimum period protection overrides fiscal period end dates
- ASSERT: Four-level idempotency prevents duplicate awards (Kafka offset → Redis dedup → Inngest event ID → DB unique constraint)
- ASSERT: `cancelOn` matches `source_type + source_id` precisely — cancelling one refund does not affect other pending awards

**Transaction type model:**

| Field | Values | Meaning |
|---|---|---|
| `transaction_type` | `earn`, `burn` | Direction of currency flow |
| `component` | `base`, `bonus`, `adjustment`, `reversal` | Category of transaction |
| `signed_amount` | Positive (earn) / Negative (burn, reversal) | Directional ledger value |
| `currency` | `points`, `tickets` | Currency type |
| `target_entity_id` | NULL (points) / UUID (tickets) | Ticket type linkage |

## 7. Business Rules

**Rule:** Only one rate factor per currency type applies per transaction. When multiple rates qualify, the best rate (lowest spend-per-unit) wins.
**Example:** Rates of 100 THB/pt and 50 THB/pt both qualify → member gets the 50 THB rate (more points per baht).

**Rule:** Product-specific and transaction-wide multipliers can coexist in non-stackable groups because they operate on mutually exclusive portions of the transaction amount.
**Example:** Shoes (300 THB) at 3x + birthday 5x on remainder (700 THB) = 9 + 35 = 44 points. No amount is multiplied twice.

**Rule:** Reversals use historical calculation data preserved in `wallet_ledger.metadata` — never current earn factors.
**Example:** Member earned 500 points during a 5x New Year promo. Promo ended. 50% refund reverses 250 points (not 50, which current 1x rate would yield).

**Rule:** Expiry dates are immutable once set. Only the deductible balance (original minus redemptions) expires.
**Example:** Member earned 100 points (expiry Jul 15), redeemed 60. On Jul 15, only 40 points expire.

**Rule:** Minimum period protection overrides fiscal period boundaries.
**Example:** Points earned Nov 1 with quarterly expiry and 6-month minimum → expires May, not Dec 31.

**Rule:** Factor settings inherit from parent group unless explicitly overridden. NULL values at factor level fall through to group values.
**Example:** Group window is Apr 1 – Jun 30. Factor with no window dates inherits Apr 1 – Jun 30. Factor with explicit dates uses its own.

**Rule:** Personalized offers evaluate alongside public rules. The member receives whichever combination yields better value.
**Example:** Public 2x for Gold members vs. personalized 5x birthday offer → system applies the 5x.

**Rule:** Delayed awards can be cancelled by refund events before processing. The Inngest workflow state is the pending state — no database pending table exists.
**Example:** Merchant configures 24-hour delay. Member purchases, then refunds 2 hours later → `currency/cancelled` event cancels the sleeping workflow before any points are awarded.

**Rule:** Points transactions always have `target_entity_id = NULL`. Ticket transactions always have `target_entity_id = ticket_type.id`. This separation is enforced at the database constraint level.
**Example:** Single purchase awarding both → two separate ledger entries with different `target_entity_id` values.

## 8. Related Features

| Feature | Connection to Currency |
|---|---|
| Rewards | Points are deducted from the member's wallet upon redemption (the "burn" side of earn-and-burn). See `Reward.md`. |
| Tier | Tier determines eligible earn rates and multipliers. Points earned contribute to tier progression. See `Tier.md`. |
| Purchase | Purchase transactions are the primary source triggering currency calculation. See `Purchase_Transaction.md`. |
| Activity/Earning | Activity-based earning (receipt upload, marketplace claims, QR scans) awards currency through the same pipeline. See `Activity_Based_Earning.md`. |
| Mission | Mission completion awards currency via `source_type = 'mission'`. See `Mission.md`. |
| Referral | Referral bonuses award currency via `source_type = 'referral'` to both inviter and invitee. See `Referral.md`. |
| Tag & Persona | Personas and tags are earn condition dimensions — multipliers and rates can target specific segments. See `Tag_and_Persona.md`. |
| Store Classification | Store attributes act as earn condition dimensions for location-based multipliers. See `Store_Attribute_Classification.md`. |
