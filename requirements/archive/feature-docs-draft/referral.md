# Feature Guide: Referral

## 1. Overview

Referral is a word-of-mouth acquisition channel. Existing members (inviters) share a personal invite code; new users (invitees) enter that code during signup. Both sides receive rewards — invitees get direct benefits (points, tickets, or reward items), while inviters earn progress toward referral missions. This two-sided incentive structure drives member-led growth.

The merchant controls a single activation trigger that determines when rewards fire: either at signup (immediate gratification, higher volume) or at first purchase (higher-quality leads). Invite codes are permanent — one code per member per merchant, generated on first request and reused forever. Inviter limits prevent abuse by capping referrals per day, week, month, year, and lifetime, differentiated by user type (buyer vs seller).

Invitee rewards are distributed directly through the wallet and reward redemption systems. Inviter rewards are handled entirely by the mission system — merchants create missions with `referral_signup` or `referral_purchase` conditions, enabling milestone-based progressive rewards without any referral-specific reward logic.

> **Frontend status:** The admin configuration UI and member-facing referral screens are not yet built. The backend (tables, functions, triggers) is fully deployed. Sections 4 and 5 describe the planned journeys based on backend capabilities.

## 2. Key Concepts

**Inviter** — An existing member who shares their invite code to recruit new users. Receives rewards indirectly through the mission system. Example: Alice shares code "XK7M2NP1" with friends.

**Invitee** — A new user who signs up using an invite code. Receives direct rewards (points, tickets, or reward items) upon activation. Each invitee can only be referred once per merchant. Example: Bob enters Alice's code during registration.

**Invite Code** — A unique 8-character alphanumeric string assigned permanently to one member per merchant. Generated lazily on first request using MD5 hash with collision detection. Once created, it never changes. Example: "XK7M2NP1".

**Activation Trigger** — Merchant-level setting that determines when referral rewards are distributed. Two values: `signup` (rewards fire when invitee registers) or `first_purchase` (rewards fire when invitee completes their first transaction). Applies to both invitee rewards and inviter mission progress.

**Invitee Outcome** — A configured reward that invitees receive upon activation. Three types: `points` (credited to wallet), `tickets` (credited to wallet), or `reward` (creates a redemption ledger record, always qty 1). Multiple outcomes can be configured — all are distributed in a single pass.

**Inviter Reward** — Not a separate system. Inviters earn rewards through missions configured with `referral_signup` or `referral_purchase` conditions. The mission system counts qualifying referral_ledger records to evaluate progress.

**Referral Limit** — Per-user-type caps on how many referrals an inviter can generate. Five periods: daily, weekly, monthly, yearly, lifetime. Limits are checked when the invitee signs up, not when the code is shared. Null values mean no restriction for that period.

**User Type** — Either `buyer` or `seller`. Determines which set of referral limits applies. Resolved from `user_accounts` during signup processing. Sellers typically get higher limits than buyers.

**Referral Ledger** — Central tracking record linking inviter, invitee, invite code, signup timestamp, and first purchase timestamp. The `first_purchase_at` field is null until the invitee makes a purchase — this is what the purchase trigger checks.

## 3. Configuration Reference

### Merchant-Level Settings (on `merchant_master`)

| Setting | What it controls | Values | Default |
|---|---|---|---|
| `referral_active` | Master on/off switch for the referral program | `true` / `false` | `false` |
| `referral_activation_trigger` | When rewards fire for both parties | `signup` / `first_purchase` | — |

### Inviter Limits (per user_type row in `referral_inviter_limits`)

| Setting | What it controls | Example | Default |
|---|---|---|---|
| User type | Which members this limit row applies to | `buyer` | Required |
| Max per day | Referrals allowed per calendar day | 2 | Null (unlimited) |
| Max per week | Referrals allowed per Sun–Sat week | 5 | Null (unlimited) |
| Max per month | Referrals allowed per calendar month | 10 | Null (unlimited) |
| Max per year | Referrals allowed per calendar year | 50 | Null (unlimited) |
| Max lifetime | Total referrals ever | 100 | Null (unlimited) |
| Priority | Tiebreaker when user matches multiple types | 0 | 0 |

### Invitee Outcomes (rows in `referral_invitee_outcomes`)

| Setting | What it controls | Example | Default |
|---|---|---|---|
| Outcome type | Kind of reward | `points`, `tickets`, or `reward` | Required |
| Amount | Quantity for points/tickets (null for rewards) | 100 | Null |
| Entity ID | `ticket_type_id` for tickets, `reward_id` for rewards, null for points | UUID | Null |
| Valid for days | Expiry period after activation | 30 | Null (no expiry) |

### Inviter Mission Conditions (configured in mission system)

| Condition type | What it counts | Example mission |
|---|---|---|
| `referral_signup` | Referral ledger records where `signed_up_at IS NOT NULL` | "Invite 3 friends to join" |
| `referral_purchase` | Referral ledger records where `first_purchase_at IS NOT NULL` | "Get 5 friends to make first purchase" |

## 4. Admin Journey

**Repo:** `Rocket-CRM/loyalty-admin` — **Frontend not yet built.** Routes below are planned.

**Route map:**

| Page name | Planned route | Data source |
|---|---|---|
| Referral Settings | `/referral-settings` | `merchant_master` (referral fields), `referral_inviter_limits`, `referral_invitee_outcomes` |
| Referral Ledger | `/referral-ledger` | `referral_ledger` joined with user data |
| Mission Settings | `/mission-settings/{id}` | Existing mission UI — add `referral_signup` / `referral_purchase` conditions |

### 4a. Enable the Referral Program

1. From **Referral Settings**, toggle `referral_active` to on
2. Select activation trigger: "On Signup" or "On First Purchase"
3. Save merchant settings

### 4b. Configure Inviter Limits

1. From **Referral Settings**, open the Limits section
2. Add a row per user type (buyer, seller) with period caps
3. Leave a period field empty to allow unlimited referrals for that window
4. Save — limits take effect immediately on new referral signups

### 4c. Configure Invitee Outcomes

1. From **Referral Settings**, open the Outcomes section
2. Add one or more outcome rows: select type (points/tickets/reward), set amount, optionally set validity period
3. For ticket outcomes, select the ticket type; for reward outcomes, select the reward item
4. Save — outcomes apply to the next activated referral

### 4d. Configure Inviter Missions

1. From **Mission Settings**, create or edit a mission
2. Add a condition of type `referral_signup` or `referral_purchase` with a target count
3. For milestone missions, set multiple levels with increasing targets
4. Configure mission rewards (points, tickets, etc.) per the standard mission system

### 4e. View the Referral Ledger

1. From **Referral Ledger**, view all referral relationships
2. Each row shows: inviter name, invitee name, invite code, signup date, first purchase date (if any)
3. Filter by date range, activation status

### 4f. Common Admin Mistakes

- Setting `referral_active = true` without configuring any invitee outcomes — invitees get no reward
- Setting activation trigger to `first_purchase` but expecting immediate inviter mission progress — missions only advance after purchase
- Configuring limits for `buyer` only when sellers also refer — sellers have no limits applied (unlimited)
- Creating invitee outcomes but no inviter missions — inviters have no incentive

## 5. Member Experience

**Repo:** `Rocket-CRM/loyalty-user` — **Frontend not yet built.** Steps below describe the backend-supported flow.

**Route map:**

| Page / Component | Planned route | Data source |
|---|---|---|
| Referral / Invite page | `/referral` or Homepage section | `fn_get_or_create_invite_code()` |
| Signup Drawer | Bottom-sheet (existing) | `fn_process_referral_signup()` via `bff-auth-complete` |
| Share sheet | Native OS share | Invite code + deep link |

### 5a. Get and Share Invite Code

1. Member navigates to referral page or taps "Invite Friends"
2. System calls `fn_get_or_create_invite_code(user_id, merchant_id)` — returns existing code or generates a new one
3. Member sees their permanent 8-character code with a share button
4. Tapping share opens the native OS share sheet with the code and/or a deep link
5. Code is the same every time — no regeneration

### 5b. Invitee Signs Up with Code

1. New user receives an invite code (via message, social media, etc.)
2. During signup, the invite code field is pre-filled from the deep link or entered manually
3. On registration completion, `fn_process_referral_signup` runs: validates code, checks inviter limits, creates ledger record
4. If activation trigger is `signup`: invitee rewards are distributed immediately, inviter mission evaluation is queued
5. If activation trigger is `first_purchase`: ledger record is created but rewards are deferred

### 5c. Purchase-Triggered Activation

1. Invitee makes their first purchase (any completed transaction)
2. `trg_referral_purchase` trigger fires on `purchase_ledger` insert/update
3. Trigger finds the invitee's pending referral, updates `first_purchase_at`
4. If merchant uses `first_purchase` trigger: invitee rewards distribute, inviter mission evaluation queues
5. Invitee and inviter both receive their rewards after this point

## 6. Perspectives

### 6a. For Customer Success / Support

**Elevator pitch:** "When your members share their invite code and someone signs up with it, both sides get rewarded. The person sharing gets progress toward referral missions. The new member gets welcome benefits like bonus points or tickets."

**Top support questions:**

| Question | Answer |
|---|---|
| "My invite code doesn't work" | Verify `referral_active = true` on the merchant. Check if the inviter has hit their referral limit for the current period. |
| "I referred someone but didn't get rewards" | Inviter rewards come from missions. Verify a mission with `referral_signup` or `referral_purchase` condition exists. Check if the activation trigger has been met (signup vs first purchase). |
| "My friend signed up but I can't see them" | Check `referral_ledger` — the record should exist if the code was entered during signup. If missing, the invitee may not have entered the code. |
| "The invitee didn't receive points" | Verify invitee outcomes are configured. Check if the activation trigger has been met. If trigger is `first_purchase`, rewards won't appear until the invitee buys something. |
| "Can I get a new invite code?" | No — one permanent code per member. The same code works indefinitely. |

### 6b. For Marketing

**Value proposition:** Referral turns existing members into an acquisition channel. Two-sided rewards ensure both the sharer and the new member have incentive. The activation trigger choice lets merchants optimize for volume (signup-based) or quality (purchase-based).

**Campaign ideas:**

1. **Growth sprint** — Set activation to `signup`, configure generous invitee points (e.g., 200 points), create a milestone mission ("Bronze Referrer: 1 signup → 200 pts, Silver: 3 → 500 pts, Gold: 5 → 1000 pts"). High limits for sellers who have large networks.

2. **Quality acquisition** — Set activation to `first_purchase`, offer a reward item (e.g., free product) as the invitee outcome. Inviter missions require `referral_purchase` conditions. Every referred user is a proven buyer.

3. **Seasonal push** — Temporarily increase referral limits and invitee reward amounts for holiday periods. Limit periods (daily/weekly caps) prevent a single user from gaming the system even during promotions.

**Metrics to track:** Invite codes generated (adoption), referral ledger entries (conversion), signup-to-purchase ratio (quality), limit utilization by user type (capacity), mission completion rates (inviter engagement).

### 6c. For Testers

**Config → expected behavior:**

| Config | Expected behavior |
|---|---|
| `referral_active = false` | Invite code generation fails, signup with code is rejected |
| `referral_active = true`, no outcomes configured | Referral ledger records are created but invitee receives nothing |
| Activation trigger = `signup` | Invitee rewards distributed at registration, inviter mission queued |
| Activation trigger = `first_purchase` | Invitee rewards deferred until first completed purchase |
| Inviter at daily limit (e.g., 2/day, already has 2 today) | Next invitee signup with that inviter's code is rejected |
| Invitee already referred by another inviter | Signup with second invite code is rejected (one referral per invitee) |
| Same invitee tries to use same code twice | Rejected — `UNIQUE(invitee_user_id, merchant_id)` constraint |
| Invitee outcome = `reward`, entity_id = valid reward_id | Redemption ledger record created (qty 1), no points deducted |
| Invitee outcome = `points`, amount = 100 | wallet_ledger entry: currency=points, component=bonus, source_type=referral |
| Invitee outcome = `tickets`, entity_id = ticket_type_id | wallet_ledger entry: currency=ticket, component=base, source_type=referral |
| Multiple outcomes configured | All outcomes distributed in single pass on activation |

**Business rules as assertions:**

- ASSERT: Each user has exactly one invite code per merchant (or none if never requested)
- ASSERT: Each invitee can appear in referral_ledger at most once per merchant
- ASSERT: Limit check counts referral_ledger records per inviter within the period window
- ASSERT: `fn_process_referral_signup` validates code exists, invitee not already referred, inviter within limits — in that order
- ASSERT: Purchase trigger only fires for `status = 'completed'` transactions
- ASSERT: Purchase trigger only processes invitees with `first_purchase_at IS NULL`
- ASSERT: Invitee rewards have `source_type = 'referral'` and `source_id = referral_ledger.id` in wallet_ledger
- ASSERT: Mission evaluation queue receives event_type `referral_signup` or `referral_purchase` on activation
- ASSERT: Invite code generation is idempotent — calling twice returns the same code

**Error states to test:**

- Referral program disabled (`referral_active = false`) — clear error returned
- Invalid invite code — error with "code not found" messaging
- Inviter limit exceeded — error specifying which period limit was hit
- Invitee already referred — error indicating duplicate referral
- Reward outcome with invalid entity_id — distribution fails for that outcome
- Purchase trigger on non-completed transaction status — no processing occurs

## 7. Business Rules

**Rule:** One invite code per member per merchant. Codes are generated lazily on first request and permanent — no regeneration, no expiry.
**Example:** Alice requests her code → "XK7M2NP1" created. She requests again next month → same "XK7M2NP1" returned.

**Rule:** One referral per invitee per merchant. An invitee cannot be referred by multiple inviters or use different codes.
**Example:** Bob signs up with Alice's code → referral recorded. Bob cannot later be credited to Charlie's code.

**Rule:** Limits are checked at signup time against the inviter's referral_ledger count for each period. All configured periods must pass — failing any one blocks the referral.
**Example:** Inviter has daily=2, monthly=10. They've sent 1 today but 10 this month → blocked by monthly limit.

**Rule:** Period windows use PostgreSQL date truncation. Daily = midnight-to-midnight, weekly = Sunday-to-Saturday (`date_trunc('week')`), monthly = 1st-to-last, yearly = Jan 1-to-Dec 31.
**Example:** Referral on Saturday at 11pm counts toward this week. A referral on Sunday at 1am starts a new weekly window.

**Rule:** Activation trigger applies to both parties simultaneously. With `signup`, invitee rewards and inviter mission evaluation both happen at registration. With `first_purchase`, both are deferred to the first completed purchase.
**Example:** Trigger = `first_purchase`. Bob signs up with Alice's code → ledger created, no rewards yet. Bob buys a product → invitee rewards distributed, Alice's referral mission advances.

**Rule:** Invitee outcomes are distributed through existing ledger systems. Points/tickets go to `wallet_ledger` with `source_type = 'referral'`. Rewards go to `reward_redemptions_ledger` with `source_type = 'referral'`. Both reference the `referral_ledger.id` for traceability.
**Example:** Configured outcomes: 100 points + 50 tickets → two wallet_ledger inserts, one with component=bonus (points), one with component=base (tickets).

**Rule:** Inviter rewards are managed entirely by the mission system. No referral-specific reward distribution for inviters exists — the system queues a mission evaluation event, and the mission engine counts qualifying referral_ledger records.
**Example:** Mission "Referral Champion" with milestone at 3 signups. After Alice's 3rd successful referral, the mission evaluator counts 3 records where `signed_up_at IS NOT NULL` → milestone met → mission reward distributed.

**Rule:** Duplicate prevention operates at multiple layers: unique constraint on `(invitee_user_id, merchant_id)` in referral_ledger, unique constraint on invite_code in referral_codes, and existing-distribution checks before wallet_ledger inserts.
**Example:** Race condition — two requests process Bob's signup simultaneously → constraint violation on the second, only one succeeds.

## 8. Related Features

| Feature | Connection to Referral |
|---|---|
| Currency | Invitee point and ticket rewards are distributed through `wallet_ledger`. See `Currency.md`. |
| Mission | Inviter rewards are delivered via missions with `referral_signup` or `referral_purchase` conditions. See `Mission.md`. |
| Rewards | Invitee reward-type outcomes create records in `reward_redemptions_ledger`. See `Reward.md`. |
| Signup | Invite code entry happens during the registration flow. See Signup Drawer in `loyalty-user`. |
| Purchase | The `first_purchase` activation trigger fires via a trigger on `purchase_ledger`. See `Purchase_Transaction.md`. |
