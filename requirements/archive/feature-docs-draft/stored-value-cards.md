# Feature Guide: Stored Value Cards

## 1. Overview

Stored Value Cards are prepaid monetary cards that merchants issue to members. Unlike points (which are earned through activities), stored value cards carry a cash-equivalent balance loaded at creation time. A merchant defines card types (e.g., "Gift Card ฿500", "VIP Prepaid ฿2,000"), imports batches of uniquely numbered cards, and distributes them to members. Members spend the balance at participating locations until the card is depleted or expires.

For merchants, stored value cards solve two problems: (1) upfront revenue capture — the member pays for the card value before spending it, improving cash flow; (2) controlled distribution — physical or digital cards with unique numbers and security codes enable gift-giving, corporate bulk purchases, and promotional giveaways. The system tracks every transaction (assignment, redemption, top-up, expiry) in an immutable ledger, giving merchants full auditability.

Key differentiators: (1) **three assignment methods** — automatic (system picks from pool), manual with security code (member self-activates), and manual without code (admin assigns directly); (2) **concurrent-safe assignment** — `FOR UPDATE SKIP LOCKED` prevents two members from receiving the same card; (3) **top-up support** — depleted cards can be recharged without creating a new card; (4) **batch import with validation** — cards are imported in bulk with duplicate detection and format validation (16-digit card numbers, 8-digit security codes).

## 2. Key Concepts

**Card Type** — A template defining the card's properties: name, face value, price, expiry rules, and availability window. All cards of a given type share the same initial value. Example: "Birthday Gift Card" with card_value=500, expiry_mode=ttl, ttl_months=12.

**Card** — An individual prepaid instrument with a unique 16-digit card number and 8-digit security code. Each card belongs to a card type and tracks its own `current_balance`. Cards start in `available` status and move through a lifecycle. Example: Card number 1234567890123456 with security code 12345678, initial value ฿500.

**Card Assignment** — The act of linking a card to a member. Creates an assignment record with an expiry date (calculated from the card type's expiry rules). A card can only have one active assignment at a time. Example: Card auto-assigned to member → assignment created with expires_at = 12 months from now.

**Assignment Method** — How a card gets linked to a member. Three methods:
- `automatic` — System picks the oldest available card from the pool (FIFO). Used by loyalty program integrations.
- `manual_with_code` — Member enters card number + security code to self-activate. Used for physical gift cards.
- `manual_without_code` — Admin assigns by card number only (no security code required). Requires `assigned_by` (admin ID). Used for in-store staff distribution.

**Card Status** — The lifecycle state of a card: `available` (in pool, unassigned), `assigned` (linked to a member with balance > 0), `depleted` (balance = 0), `expired` (past expiry date). See Section 6c for full status model.

**Expiry Mode** — How card expiration is calculated:
- `ttl` — Relative: card expires X months after assignment. Example: ttl_months=12, assigned Jan 1 → expires Jan 1 next year.
- Fixed — Absolute: all cards of this type expire on a specific date regardless of assignment date. Example: fixed_expiry_date = 2026-12-31.

**Availability Window** — Optional date range (`window_start` / `window_end`) during which cards of this type can be assigned. Outside this window, assignment is blocked even if cards are available. Example: Holiday gift cards assignable only Nov 1 – Dec 31.

**Card Value vs. Price** — `card_value` is the monetary balance loaded onto the card. `price` is what the member pays to acquire the card. A ฿500 card sold for ฿450 creates a discount incentive. Price defaults to 0 (free distribution).

**Transaction Ledger** — Immutable log of every balance change: assignment (initial load), redemption (spend), top-up (reload), expiry (forfeiture). Each entry records balance_before, balance_after, and amount.

**Import Batch** — A group of cards imported together. Tracks total, successful, and failed card counts with error details. Cards within a batch must have unique 16-digit numbers and 8-digit security codes.

## 3. Configuration Reference

### Card Type Settings

| Setting | What it controls | Example | Default |
|---|---|---|---|
| Name | Display name of the card type | "Birthday Gift Card" | Required |
| Description | Card type description | "A special gift for your birthday" | None |
| Terms & Conditions | Usage terms text | "Valid at all participating stores" | None |
| Card value | Monetary balance loaded on each card | 500.00 | Required |
| Price | Purchase price (what member pays) | 450.00 | 0.00 |
| Expiry mode | How expiry is calculated | `ttl` or fixed | Required |
| TTL months | Months until expiry (ttl mode only) | 12 | — |
| Fixed expiry date | Exact expiry date (fixed mode only) | 2026-12-31 | — |
| Window start | Earliest date cards can be assigned | 2026-11-01 | No restriction |
| Window end | Latest date cards can be assigned | 2026-12-31 | No restriction |
| Is active | Whether this card type is available | true | true |

### Card Properties (per imported card)

| Property | Format | Example |
|---|---|---|
| Card number | Exactly 16 digits | 1234567890123456 |
| Security code | Exactly 8 digits | 12345678 |
| Initial value | Inherited from card type | 500.00 |
| Status | System-managed | `available` |

## 4. Admin Journey

**Repo:** `Rocket-CRM/loyalty-admin`

> **Note:** No dedicated admin UI pages exist yet. The operations below are available as database functions and would be called through a future admin interface or direct API integration.

**Route map:**

| Page name | Current route | BFF / data source |
|---|---|---|
| Card Type Management | _Not yet built_ | Direct table: `card_types` |
| Card Import | _Not yet built_ | `import_cards()`, `import_cards_bulk()` |
| Card List / Inventory | _Not yet built_ | Direct table: `cards` |
| Card Assignment | _Not yet built_ | `assign_card_manual_without_code()` |

### 4a. Create a Card Type

1. Admin defines card type: name (required), description, terms & conditions, card_value (required), price, expiry_mode (required)
2. For TTL mode: set ttl_months. For fixed mode: set fixed_expiry_date
3. Optionally set availability window (window_start, window_end)
4. Save → card type created with is_active = true

### 4b. Import Cards

1. Prepare card data: each card needs a unique 16-digit card_number and 8-digit security_code
2. Import via `import_cards` (JSON array) or `import_cards_bulk` (CSV text)
3. System validates: card number format (16 digits), security code format (8 digits), no duplicates against existing cards
4. If any card fails validation → entire batch fails, no cards imported, error details stored in batch record
5. On success: all cards created with status `available`, initial_value and current_balance set to card_type.card_value

### 4c. Assign Cards to Members (Admin-initiated)

1. Admin selects a card by card_number
2. System calls `assign_card_manual_without_code` with the member's user_id and admin's ID as assigned_by
3. Validates: card exists, status is `available`, within assignment window
4. Creates assignment record with calculated expiry date
5. Creates `assignment` transaction in ledger (balance_before=0, balance_after=initial_value)
6. Card status changes from `available` to `assigned`

### 4d. Common Admin Mistakes

- Importing cards with non-16-digit numbers or non-8-digit security codes → entire batch rejected
- Setting window_end in the past → no cards can be assigned
- Deactivating a card type (is_active=false) → automatic assignment fails, but manually assigned cards remain active
- Importing duplicate card numbers → batch rejected with duplicate list in error_details

## 5. Member Experience

**Repo:** `Rocket-CRM/loyalty-user`

> **Note:** No dedicated member UI pages exist yet. The operations below are available as database functions and would be accessed through a future member app interface or API integration.

**Route map:**

| Page / Component | Current route | Data source |
|---|---|---|
| My Cards | _Not yet built_ | `get_user_cards(p_user_id)` |
| Card Activation | _Not yet built_ | `assign_card_manual_with_code()` |
| Card Balance Check | _Not yet built_ | `check_card_balance()` |
| Card Transaction History | _Not yet built_ | `get_card_transactions(p_card_id)` |

### 5a. Activate a Card (Self-Service)

1. Member enters 16-digit card number and 8-digit security code (printed on physical card or received digitally)
2. System calls `assign_card_manual_with_code`
3. Validates: card exists, security code matches, status is `available`, within assignment window
4. If wrong security code → "Invalid security code". If card already assigned → "Card is not available for assignment"
5. On success: card assigned, expiry calculated, initial balance available immediately

### 5b. Receive a Card (Automatic)

1. Triggered by loyalty program action (e.g., mission completion, tier upgrade, campaign)
2. System calls `assign_card_automatic` with member's user_id and card_type_id
3. System picks the oldest available card (FIFO) using `FOR UPDATE SKIP LOCKED`
4. If no cards available → error "No available cards of this type"
5. On success: member receives card with number, security code, expiry date, and balance

### 5c. Use Card Balance

1. Member presents card at point of sale (or uses online)
2. System calls `redeem_card` with card_id and amount
3. Validates: card status is `assigned`, not expired, sufficient balance, within usage window (window_start)
4. On success: balance deducted, transaction recorded in ledger
5. If balance reaches 0 → card status changes to `depleted`

### 5d. Top Up a Card

1. Member or admin requests top-up for an existing card
2. System calls `topup_card` with card_id and amount
3. Validates: card status is `assigned` or `depleted`, not expired, amount > 0
4. On success: balance increased, transaction recorded. If card was `depleted`, status returns to `assigned`

### 5e. View Cards and History

1. Member views their cards via `get_user_cards` — shows all active, non-expired cards (optionally includes expired)
2. Each card displays: card_number, card_type name, current_balance, initial_value, assigned_at, expires_at, is_expired, status
3. Member views transaction history via `get_card_transactions` — paginated list (default 50 per page)
4. Each transaction shows: type, amount, balance_before, balance_after, description, created_at

## 6. Perspectives

### 6a. For Customer Success / Support

**Elevator pitch**: "Stored value cards let you issue prepaid cards to members — like gift cards. You set the value, import the card numbers, and distribute them. Members activate and spend the balance at your locations. Every transaction is tracked."

**Top 5 support questions:**

| Question | Answer |
|---|---|
| "Member can't activate their card" | Check: card_number is exactly 16 digits, security_code is exactly 8 digits, card status is `available` (not already assigned), assignment window hasn't passed |
| "Card shows zero balance but member hasn't used it" | Check if card expired — `expire_cards` job zeros the balance when expiry passes. Look at card_transactions_ledger for an `expiry` transaction |
| "Member wants to top up a card" | Card must be `assigned` or `depleted` status and not expired. Use `topup_card`. Expired cards cannot be topped up |
| "Two members got the same card" | Not possible — `FOR UPDATE SKIP LOCKED` ensures atomic assignment. If reported, one member likely has a different card number |
| "Card balance doesn't match expected" | Check `get_card_transactions` — the ledger shows every balance change with before/after amounts. Look for unexpected redemptions or expiry |

**Config mistakes → fix:**

| Mistake | Symptom | Fix |
|---|---|---|
| Window end in the past | "Card assignment window has ended" | Update window_end or remove it |
| Card type is_active = false | Automatic assignment fails | Set is_active = true |
| Imported wrong card_value | Cards have wrong balance | Cannot change after import — import new batch with correct value |
| Duplicate card numbers in batch | Entire batch rejected | Remove duplicates and re-import |

### 6b. For Marketing

**Value proposition**: Stored value cards add a prepaid spending mechanism alongside points. Members receive cards through campaigns, tier upgrades, or direct purchase — creating immediate perceived value. Unlike points that accumulate gradually, a ฿500 gift card is instantly understood and motivating.

**Use-case stories:**

1. **Birthday campaign** — Members receive a ฿200 birthday gift card (automatic assignment via mission completion). Card expires in 3 months, creating urgency to visit. Cost to merchant: only realized when member spends.

2. **Corporate bulk purchase** — Company buys 500 gift cards at ฿450 each (price) with ฿500 face value (card_value). Cards imported in one batch, distributed physically to employees. Each employee self-activates with card number + security code.

3. **New member welcome** — Sign-up flow triggers automatic card assignment. New member immediately has ฿100 to spend, driving first purchase within the TTL window.

4. **Top-up loyalty** — Members who deplete their card can top up, maintaining engagement. A depleted card becomes active again without needing a new card number.

**Metrics merchants care about**: Cards issued vs. activated, average balance utilization (spent / initial_value), top-up rate, expiry forfeiture rate (balance lost to expiry), time-to-first-use.

### 6c. For Testers

**Config → expected behavior:**

| Config | Expected behavior |
|---|---|
| Card with status `available` | Can be assigned (any method). Cannot be redeemed or topped up |
| Card with status `assigned` | Can be redeemed and topped up. Cannot be re-assigned |
| Card with status `depleted` | Can be topped up (returns to `assigned`). Cannot be redeemed |
| Card with status `expired` | Cannot be assigned, redeemed, or topped up |
| Assignment within window | Succeeds |
| Assignment outside window (before start or after end) | Fails with window error |
| Redeem amount > current_balance | Fails "Insufficient balance" with current_balance and requested_amount |
| Redeem when expired | Fails, card status updated to `expired` |
| Redeem before window_start | Fails "Card cannot be used before [date]" |
| Top-up on expired card | Fails (status not in assigned/depleted) |
| Top-up on depleted card | Succeeds, status returns to `assigned` |
| Manual with wrong security code | Fails "Invalid security code" |
| Manual with already-assigned card | Fails "Card is not available for assignment" |
| Automatic when pool is empty | Fails "No available cards of this type" |
| Import with duplicate card number | Entire batch rejected |
| Import with 15-digit card number | Rejected "invalid format" |
| Import with 7-digit security code | Rejected "invalid security code" |

**Business rules as assertions:**

- ASSERT: Automatic assignment picks the oldest imported card (FIFO by imported_at)
- ASSERT: `FOR UPDATE SKIP LOCKED` prevents duplicate assignment under concurrency
- ASSERT: Every balance change creates a ledger entry with correct balance_before and balance_after
- ASSERT: balance_after = balance_before - amount (for redemption)
- ASSERT: balance_after = balance_before + amount (for top-up)
- ASSERT: Card status = `depleted` when current_balance reaches exactly 0 after redemption
- ASSERT: Top-up on depleted card sets status back to `assigned`
- ASSERT: `expire_cards` sets balance to 0, status to `expired`, assignment is_active to false
- ASSERT: TTL expiry = assigned_at + ttl_months. Fixed expiry = card_type.fixed_expiry_date
- ASSERT: Failed import batch stores duplicate/invalid card numbers in error_details JSONB

**Status model (single track with transitions):**

| From | To | Trigger |
|---|---|---|
| `available` | `assigned` | Any assignment method |
| `assigned` | `depleted` | Redemption reduces balance to 0 |
| `assigned` | `expired` | `expire_cards` job or redemption attempt on expired card |
| `depleted` | `assigned` | Top-up adds balance |
| `depleted` | `expired` | `expire_cards` job |

Invalid transitions: `expired` → any state. `available` → `depleted`/`expired` directly.

**Assignment deactivation states:**

| is_active | deactivation_reason | Meaning |
|---|---|---|
| true | null | Active assignment |
| false | `expired` | Card expired via `expire_cards` job |

**Transaction types in ledger:**

| Type | Amount meaning | When created |
|---|---|---|
| `assignment` | Initial value loaded | Card assigned to member |
| `redemption` | Amount spent | Member uses balance |
| `topup` | Amount added | Balance recharged |
| `expiry` | Remaining balance forfeited | `expire_cards` job runs |

**Error states to test:**

- Concurrent automatic assignment (two requests, one card left → exactly one succeeds)
- Top-up with amount = 0 or negative → "Amount must be positive"
- Redeem with amount = 0 or negative → "Amount must be positive"
- Check balance with wrong security code → "Card not found or invalid credentials"
- Check balance without security code → returns card info (less secure path)
- Assignment when card_type.is_active = false → "Card type not found or inactive"
- Import batch with mix of valid and invalid cards → entire batch fails (all-or-nothing)

## 7. Business Rules

**Rule:** Card assignment uses FIFO ordering — the oldest imported card (by `imported_at`) is assigned first during automatic assignment.
**Example:** 100 cards imported on Jan 1, 50 more on Feb 1. Automatic assignments pull from the Jan 1 batch first.

**Rule:** Concurrent assignment safety uses `FOR UPDATE SKIP LOCKED`. If two assignment requests race for the last card, exactly one succeeds — the other receives "No available cards."
**Example:** Two members activate simultaneously, 1 card left → one gets the card, the other sees an error.

**Rule:** Card import is all-or-nothing. If any card in a batch has an invalid format or duplicate number, zero cards are imported.
**Example:** Batch of 100 cards where card #47 has a 15-digit number → entire batch rejected, 0 cards created.

**Rule:** Card numbers must be exactly 16 digits, security codes exactly 8 digits. Both numeric only.
**Example:** Card "123456789012345" (15 digits) → rejected. Card "1234567890123456" → accepted.

**Rule:** Expiry calculation depends on mode. TTL: `assigned_at + ttl_months`. Fixed: `card_type.fixed_expiry_date` regardless of when assigned.
**Example:** TTL 6 months, assigned June 15 → expires Dec 15. Fixed Dec 31, assigned any date → expires Dec 31.

**Rule:** Top-up is allowed on `assigned` and `depleted` cards but not `expired`. A depleted card that receives a top-up returns to `assigned` status.
**Example:** Card balance hits 0 (depleted) → admin tops up ฿200 → card is `assigned` with ฿200 balance.

**Rule:** The `expire_cards` batch job zeros remaining balance and logs an `expiry` transaction. The assignment is deactivated (is_active=false, deactivation_reason='expired').
**Example:** Card with ฿150 remaining expires → ledger shows expiry transaction (balance_before=150, balance_after=0), card status=expired.

**Rule:** Redemption that reduces balance to exactly 0 changes card status to `depleted`, not `expired`.
**Example:** Card with ฿100 balance, member redeems ฿100 → status = `depleted` (not expired — card can still be topped up).

**Rule:** Manual assignment without security code requires an `assigned_by` admin ID. This prevents unauthorized card distribution.
**Example:** Staff at store assigns card to walk-in customer → `assigned_by` = staff's admin UUID.

**Rule:** Availability window restricts assignment timing, not usage. A card assigned within the window can be used after window_end.
**Example:** Window closes Dec 31. Card assigned Dec 30. Member can still redeem the card in January (until the card's own expiry date).

## 8. Related Features

| Feature | Connection to Stored Value Cards |
|---|---|
| Currency | Cards use monetary value (not points). Both systems track balances but operate independently. See `Currency.md`. |
| Rewards | Rewards consume points; cards consume monetary balance. Different spend mechanisms in the same loyalty program. See `Reward.md`. |
| Mission | Missions can trigger automatic card assignment as a completion prize. See `Mission.md`. |
| Tier | Tier upgrades can trigger card assignment. Card types could be tier-gated in future. See `Tier.md`. |
| Activity/Earning | Activities earn points; card distribution is a separate value channel. See `Activity_Based_Earning.md`. |
