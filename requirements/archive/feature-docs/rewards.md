# Feature Guide: Rewards

## 1. Overview

Rewards are redeemable items in the loyalty marketplace — the primary way members spend the points they've earned. A merchant creates rewards (vouchers, physical products, digital codes, experiences) and assigns a points cost. Members browse the catalog, pick a reward, and exchange their points for it. This is the "spend" side of the earn-and-burn loop that keeps members engaged.

For merchants, rewards solve a core retention problem: giving customers a tangible reason to stay loyal. Instead of flat discounts, merchants can offer personalized pricing — a Gold-tier member might pay 60 points for a reward that costs a Silver member 80 points. Eligibility filters let merchants target specific segments (tiers, personas, birth months), and stock control prevents over-redemption. The system handles the full lifecycle from catalog display through redemption to fulfillment tracking, including multi-channel distribution to external storefronts like Shopify.

Key differentiators: (1) **dynamic points pricing** — a multi-dimensional matching engine finds the most favorable price per member; (2) **async redemption** — immediate acknowledgment while the backend processes atomically, enabling high-concurrency flash campaigns; (3) **multi-quantity redemption** — bulk redemption with intelligent promo code pool management; (4) **marketplace distribution** — rewards published to external e-commerce platforms alongside the native app.

## 2. Key Concepts

**Reward** — A redeemable item defined by a merchant with a name, points cost, eligibility rules, and fulfillment method. Example: "Free Coffee Voucher — 50 points."

**Redemption** — The act of a member exchanging points for a reward. Creates a ledger record with a unique code (e.g., RWD000123). Each redemption tracks two independent statuses: `redeemed_status` (points deducted, reward claimed) and `used_status` (reward actually consumed at store/online). A redemption can be redeemed but not yet used. Example: Member spends 50 points → `redeemed_status=true, used_status=false` → presents voucher at store → `used_status=true`.

**Eligibility** — The first layer of the two-layer system: a binary check determining WHO can see and redeem a reward. Controlled by allowed tiers, personas, user types, tags, and birth months. Empty filter = everyone allowed.

**Dynamic Points** — The second layer: determines HOW MANY points a specific member pays. A matching engine evaluates conditions across four dimensions (tier, user type, persona, tags) and picks the most specific match. Example: A condition "Gold + Student = 40 pts" beats "Gold = 60 pts" because it matches more dimensions.

**Specificity Scoring** — How the dynamic points engine ranks conditions. Each matched dimension adds to the score (tier: +1000, user_type: +100, persona: +10, tags: +1). Highest total specificity wins. Ties broken by priority, then lowest points (customer-favorable).

**Visibility** — Controls who can start a catalog redemption, and whether the reward appears in the member browse list. `user` = member catalog **and** Front Line (User and admin). `user_only` = member catalog only — staff cannot spend points or gift it on Front Line (they can still mark a claimed voucher used). `admin` = Front Line only. `campaign` = push-only, never in the browse catalog; delivered through AMP, missions, claim links, or admin push — members see them only in "my redemptions" after receiving.

**Fulfillment Method** — How the reward is delivered: `digital` (codes/vouchers), `shipping` (physical delivery), `pickup` (collect at store), `printed` (Lucky Draw thermal slip on Frontline redeem; slip title/body = `physical_draw_name` / `physical_draw_description`).

**Stock Control** — When enabled, limits the total number of redemptions available. When disabled, the reward is unlimited.

**Promo Code** — A unique code from a pre-uploaded pool, assigned to the member upon redemption. When enabled, each redemption pulls one code from the pool. Example: Partner discount code "NIKE-ABC123."

**Redemption Window** — Optional start/end dates during which redemption is allowed. Outside this window, the reward is visible but not redeemable.

**Transaction Limits** — Rules capping how many times a reward can be redeemed. Scoped by `per_user`, `per_merchant`, or `per_transaction`, and by time unit (`day`, `week`, `month`, `year`, `lifetime`).

**Multi-Quantity Redemption** — Redeeming N units in one transaction. With promo codes: creates N separate ledger records (one code each). Without promo codes: creates 1 record with qty=N. Range: 1–1000.

**Online Store Distribution** — A free-text array (`online_store[]`) tagging which external storefronts display this reward (e.g., `shopify`, `lazada`). Enables the marketplace integration.

**Burn Rate** — Points spent on this reward (from the Currency domain perspective). See Currency guide.

**Reward Category** — Merchant-defined grouping for organizing the catalog (e.g., "Food & Beverage", "Electronics").

**Fallback Points** — Default points cost when no dynamic condition matches the member and `require_points_match` is off. If `require_points_match` is on and no condition matches, redemption is blocked and fallback is ignored.

**Fulfillment Status** — Tracks physical delivery progress independently of redeemed/used: `pending` → `shipped` → `delivered` → `completed` (or `cancelled`/`reject`). See Section 6c for full status model.

**Expiration Modes** — How redeemed rewards expire: `relative_days` (X days after redemption), `relative_mins` (flash rewards with countdown timer for immediate in-store use), `absolute_date` (fixed date for all).

## 3. Configuration Reference

### Basic Info


| Setting               | What it controls                           | Example               | Default          |
| --------------------- | ------------------------------------------ | --------------------- | ---------------- |
| Name                  | Reward display name                        | "Free Coffee Voucher" | Required         |
| Category              | Organizational grouping                    | "Food & Beverage"     | None             |
| Redemption start date | Earliest date members can redeem           | 2025-01-01            | No restriction   |
| Redemption end date   | Latest date members can redeem             | 2025-12-31            | No restriction   |
| Expire mode           | How redeemed rewards expire                | `relative_days`       | None (no expiry) |
| Expire TTL            | Days/minutes until expiry (relative modes) | 30                    | —                |
| Expire date           | Fixed expiry date (absolute mode)          | 2025-06-30            | —                |


### Eligibility Conditions


| Setting              | What it controls                 | Example              | Default            |
| -------------------- | -------------------------------- | -------------------- | ------------------ |
| Allowed tiers        | Which tier members can redeem    | [Gold, Platinum]     | Empty = all tiers  |
| Allowed personas     | Which persona members can redeem | [Student, Corporate] | Empty = all        |
| Allowed birth months | Birthday-reward targeting        | [1, 12] (Jan, Dec)   | Empty = all months |


### Points Pricing


| Setting                  | What it controls                                 | Example                      | Default                      |
| ------------------------ | ------------------------------------------------ | ---------------------------- | ---------------------------- |
| Require points match     | If true, unmatched members cannot redeem (fallback ignored) | true                         | false                        |
| Fallback points          | Points cost when no condition matches and require match is off | 100                          | null (free if no conditions) |
| Points conditions        | Rows of tier/persona/type/tags → points mappings | Gold: 60 pts, Silver: 80 pts | Empty                        |
| Priority (per condition) | Tiebreaker when specificity is equal             | 150                          | 100                          |


### Transaction Limits


| Setting          | What it controls               | Example    | Default   |
| ---------------- | ------------------------------ | ---------- | --------- |
| Scope            | Who the limit applies to       | `per_user` | —         |
| Time unit        | Period of the limit            | `month`    | —         |
| Count            | Maximum redemptions in period  | 3          | —         |
| Window start/end | Optional date range for limit  | 2025-Q1    | No window |
| Active status    | Enable/disable this limit rule | true       | true      |


### Display Settings


| Setting              | What it controls                           | Example                             | Default |
| -------------------- | ------------------------------------------ | ----------------------------------- | ------- |
| Description headline | Short title shown on reward detail         | "Exclusive Coffee Offer"            | Empty   |
| Image                | Reward image (single URL, stored as array) | PNG/JPG/WEBP, max 5MB               | None    |
| Description body     | Rich HTML description                      | Full reward details                 | Empty   |
| Terms & conditions   | Rich HTML T&C                              | Redemption rules, restrictions      | Empty   |
| Redemption slip      | Rich HTML slip text                        | Instructions shown after redemption | Empty   |
| Physical draw name   | Lucky Draw thermal slip title (when `printed`) | "Future Happiness Draw 2026"     | Empty   |
| Physical draw description | Lucky Draw thermal slip body          | Event / box instructions            | Empty   |


### Sidebar Controls


| Setting            | What it controls                         | Example         | Default |
| ------------------ | ---------------------------------------- | --------------- | ------- |
| Visibility         | Who can start a catalog redemption       | `user` (user and admin) | `admin` |
| Assign promo code  | Pull unique codes from pool on redeem    | true            | false   |
| Stock control      | Enable finite inventory                  | true            | false   |
| Fulfillment method | Delivery type; `printed` = also print Lucky Draw slip on Frontline | `digital` | None |


### Marketplace Distribution


| Setting                   | What it controls                    | Example                | Default |
| ------------------------- | ----------------------------------- | ---------------------- | ------- |
| Ecommerce platform toggle | Link reward to external storefronts | true                   | false   |
| Platforms                 | Which storefronts (multi-select)    | [shopify, bigcommerce] | —       |
| Shopify discount code     | Bind to a specific Shopify discount | "SUMMER2025"           | None    |


## 4. Admin Journey

**Repo:** `Rocket-CRM/loyalty-admin`

**Route map** (update here if routes change — steps below reference page names only):

| Page name | Current route | BFF / data source |
|---|---|---|
| Reward List | `/reward-list` | `api_get_rewards_full_cached()`, `admin_delete_reward()` |
| Reward Settings (create) | `/reward-settings/new` | `bff_get_reward_details(mode='new')` |
| Reward Settings (edit) | `/reward-settings/{id}` | `bff_get_reward_details(mode='edit', id)` |
| Marketplace Settings | `/marketplace-settings` | `fetchMarketplaceChannels()` |
| Frontline — Push reward / Claim QR | Frontline member detail (new tab) | `bff_admin_search_members`, `bff_list_rewards`, `bff_admin_push_reward`, `bff_admin_upsert_reward_claim_link`, `bff_admin_list_reward_claim_links`, `bff_admin_set_reward_claim_link_active` |

### 4a. Create a New Reward

1. From **Reward List**, click **"Add reward"** button
2. **Reward Settings** opens in create mode — empty form
3. Fill in Basic Info card: name (required), category, dates, expiry rules
4. Set eligibility conditions: select allowed tiers, personas, birth months (leave empty for unrestricted)
5. Configure points pricing: toggle `require_points_match`, set fallback points, add tier-specific rows via **"Add tier"** button
6. Add transaction limits via **"Add scope"** button: set scope, time unit, count
7. Fill display settings: headline, image upload, body/T&C/slip rich text editors
8. Configure sidebar: visibility, promo code toggle, stock control + fulfillment method
9. Optionally enable ecommerce platform → select platforms → bind Shopify discount
10. Click **"Save"** (keeps current visibility) or **"Save and Publish"** (forces visibility to `user`)
11. On success: toast "Reward saved", redirect to Reward List. On failure: error banner displayed.

### 4b. Edit an Existing Reward

1. From **Reward List**, click any reward row or the edit icon
2. **Reward Settings** opens in edit mode — form pre-populated
3. Modify any fields — all sections are editable
4. Save or Save and Publish (same behavior as create)

### 4c. Manage the Reward List

1. **Reward List** displays an IndexTable with columns: Name, Visibility (badge), Status (Active/Inactive badge), Redemption window, Points (dynamic/fallback/—), Stock (limited/unlimited), Actions
2. **Pin**: pin icon in Actions — click to pin/unpin (saves immediately). Pinned rewards sort to the top of the admin list and appear first on the member catalog as Special Reward (`reward_master.is_featured`)
3. **Active/Inactive**: Activate/Deactivate in Actions writes `reward_master.active_status` immediately (`bff_set_reward_active`). List includes inactive rows (`bff_list_rewards(p_include_inactive:=true)`). Activate is disabled at the plan cap.
4. **Filter/sort**: by status, category, name
5. **Delete**: click delete icon → confirmation modal ("Are you sure? Cannot be undone")
6. Empty state shows CTA to create first reward

### 4d. Configure Marketplace Settings

1. **Marketplace Settings** — tabbed page: "Order Claims" | "Marketplace Connections"
2. **Marketplace Connections tab**: add channels (Shopify, Lazada, Shopee, TikTok), manage OAuth connections
3. **Order Claims tab**: configure how marketplace orders link to loyalty accounts
4. **Dashboard & History** button opens analytics modal

### 4e. Common Admin Mistakes

- Setting `require_points_match = true` with no conditions → no one can redeem
- Enabling promo codes but not uploading any codes → redemptions fail with "insufficient codes"
- Setting redemption window end date in the past → reward visible but unredeemable
- Leaving visibility as `admin` and wondering why members can't see the reward
- Adding eligibility filters that exclude all current members → zero redemptions
- Enabling stock control but not setting fulfillment method → confusing UX

### 4f. Push reward 1-to-1 & claim QR (frontline)

1. Search member → open member detail → **Push reward** tab (new CRM term; old CRM called this “coupon”)
2. Pick an active reward → **Push** → `bff_admin_push_reward` issues into wallet (unused; 0 points). Not `admin_redeem_and_use` (that marks used).
3. Optionally create a claim link for the reward → `bff_admin_upsert_reward_claim_link` returns `claim_url` / token → show QR + download; deactivate via `bff_admin_set_reward_claim_link_active`

## 5. Member Experience

**Repo:** `Rocket-CRM/loyalty-user`

**Route map:**

| Page / Component | Current route | Data source |
|---|---|---|
| Rewards catalog | `/rewards` | `api_get_rewards_full_cached(p_language, p_persona_id?)` |
| Reward detail drawer | Bottom-sheet on `/rewards` | Same cached data + eligibility info |
| Redemption slip drawer | Bottom-sheet on `/rewards` | Realtime INSERT payload |
| History drawer | Bottom-sheet from Homepage/Profile | `bff_get_reward_history(p_filter, p_limit, p_offset, p_language)` |
| Claim link landing | `?page=claim&token=` | `bff_get_reward_claim_preview`, `bff_claim_reward_via_link` |

### 5a. Browse Rewards

1. Member opens the reward catalog — 2-column card grid layout
2. **Pinned / featured** rewards (`is_featured`) appear first as **Special Reward**
3. **Category filter bar** at top: horizontal chips ("All", "Discount", "Voucher", etc.) from `reward_category`
4. Each card shows: reward image, name, points required (`points.fallback`), availability
5. Tapping a category chip filters the grid instantly (client-side)

### 5b. View Reward Detail

1. Member taps a reward card → **bottom-sheet drawer** slides up
2. Drawer shows: hero image (full-width, 220px with gradient overlay), reward name, headline, redemption window dates, points required, eligibility chips (tier colors, persona names), description body, terms & conditions
3. Footer: error message area + **"Redeem"** CTA button
4. If ineligible: reason displayed, CTA disabled

### 5c. Redeem a Reward

1. Member taps "Redeem" → **confirmation popup** ("Redeem Reward Now?") with Cancel / Confirm
   - **Shipping rewards** (`fulfillment_method = shipping`): an **address form** opens first — prefilled from the member's saved address (`bff_get_user_address`), blank if none. Member confirms/edits and saves (`bff_save_user_address`; requires address line 1 + postcode), then the redeem call fires. The backend stamps the saved address onto the redemption (`delivery_address` snapshot, `fulfillment_status = pending`) and rejects with "Shipping address required" if none is on file.
2. On Confirm: app POSTs to Render API → receives 200 (queued, not completed)
3. Detail drawer closes → **loading overlay with spinner** appears (state: `pending`)
4. App listens on Supabase Realtime channel `redemption:{userId}` (subscribed on page mount, not per-redemption)
5. **On success** (Realtime INSERT on `reward_redemptions_ledger`): success toast + **"Use Now" confirm drawer** opens with two options: "Use now" or "See wallet"
6. **On failure** (Realtime broadcast `redemption_failed`): error toast with title + description from backend
7. **On timeout** (15 seconds, no event): "Processing" toast — check rewards history

### 5d. Use a Redeemed Reward

1. From "Use Now" drawer or History: **Redemption Slip drawer** opens
2. Slip shows: reward image (circular), reward name, status badge ("Not yet used" / "Used"), redemption date, and code in three formats via tabbed display: **Code** (text) / **Barcode** / **QR Code**
3. Code source: `promo_code` if assigned, otherwise system-generated redemption code
4. If `use_expire_mode = relative_mins`: live **countdown timer** displayed (flash reward)
5. Member presents code to staff or enters at checkout → `api_mark_redemption_used` marks `used_status = true`

### 5e. View Redemption History

1. Member opens **History drawer** (from Homepage or Profile) → selects **Reward** tab
2. Sub-filter chips: "My Reward" (redeemed, not yet used) / "Used" / "Expired"
3. Each row shows: reward image, name, redemption code, date, points spent, status
4. Redeemed-but-not-used items show a **"Use" action button** → opens Redemption Slip drawer
5. Infinite scroll pagination

### 5f. Claim via QR / link

1. Open `?page=claim&token=…` → `bff_get_reward_claim_preview` → show reward summary + **Claim**
2. If not signed in → existing auth bottom sheet; retain token and resume claim after login
3. If `fulfillment_method = shipping` → delivery-address drawer first (same as catalog redeem: confirm saved address or save via `bff_save_user_address`). Claim is rejected with `ADDRESS_REQUIRED` until a usable address is on file.
4. On Claim (signed in, address ok) → `bff_claim_reward_via_link` → catalog points engine (`calc`): deducts the reward’s cost (0 if the brand set 0); success toast; reward appears in wallet
5. Respect `can_claim` / `block_reason` from preview (`already_claimed`, `sold_out`, `expired`, etc.)

## 6. Perspectives

### 6a. For Customer Success / Support

**Elevator pitch**: "Rewards let your members spend their earned points on items you choose — vouchers, products, experiences. You control who can redeem (by tier, persona, or birthday), how many points it costs (even different prices for different member segments), and how many can be claimed."

**Top 5 support questions:**


| Question                               | Answer                                                                                                                             |
| -------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------- |
| "Members can't see the reward"         | Check visibility (must be `user`), eligibility filters (are their tiers/personas included?), and redemption window dates           |
| "Redemption says 'insufficient codes'" | Promo code pool is exhausted — upload more codes or disable promo code assignment                                                  |
| "Member was charged wrong points"      | Dynamic pricing matched a different condition than expected — check the points conditions table and the member's tier/persona/tags |
| "Reward shows 0 points required"       | No conditions matched AND `require_points_match` is false AND `fallback_points` is null — this means free redemption by design     |
| "Redemption stuck on pending"          | Async processing may be delayed — check if the event was processed; if fulfillment_status is pending, it's awaiting staff action   |


**Config mistakes → fix:**


| Mistake                                      | Symptom                         | Fix                                                      |
| -------------------------------------------- | ------------------------------- | -------------------------------------------------------- |
| `require_points_match` = true, no conditions | Redemption blocked for everyone | Add at least one condition or set to false with fallback |
| Promo codes enabled, pool empty              | "Insufficient codes" error      | Upload codes or disable promo code assignment            |
| Window end date in past                      | Visible but unredeemable        | Update end date or remove window                         |
| Visibility = `admin`                         | Members can't see it            | Change to `user` or use "Save and Publish"               |
| All eligibility filters too narrow           | Zero redemptions                | Widen filters or leave empty for unrestricted            |


**Bug vs misconfiguration**: If the reward appears correctly in admin but members report issues → likely misconfiguration (check eligibility, visibility, window, stock). If the reward doesn't appear in admin or saves fail → likely a bug (check error messages, contact engineering).

### 6b. For Marketing

**Value proposition**: Rewards transform passive point balances into active engagement. Members earn points through purchases and activities, then redeem them for meaningful benefits — creating a cycle that drives repeat visits. The dynamic pricing engine lets merchants offer VIP-level personalization ("Gold members pay fewer points") without manual management.

**Use-case stories:**

1. **Café chain** — Creates "Free Coffee" (50 pts), "Birthday Cake Slice" (birthday month only, 30 pts), and "VIP Tasting Event" (Platinum tier only, 200 pts). Birthday rewards drive a 40% visit increase in members' birth months.

2. **Fashion retailer** — Lists rewards across tiers: Bronze gets 10% vouchers (100 pts), Gold gets early-access sale passes (80 pts), Platinum gets personal styling sessions (500 pts). Tier-gated exclusivity motivates upgrades.

3. **Flash sale campaign** — Merchant creates a limited-stock reward with `relative_mins` expiry (30-minute countdown timer on the redemption slip). The async architecture handles thousands of simultaneous redemptions without timeouts — members get instant confirmation while the backend processes atomically. Creates urgency to use the reward immediately in-store.

4. **B2B distributor** — Uses persona-based pricing: "Corporate" persona pays 60 pts for bulk samples, "SME" persona pays 40 pts. Promo codes tied to partner discount codes on Shopify, distributed automatically through marketplace integration.

**Metrics merchants care about**: Redemption rate (% of members who redeem), average points spent per redemption, reward popularity ranking, stock depletion rate, promo code utilization rate, time-to-use (redeemed → used duration).

**Differentiators to highlight:**
- **Dynamic per-segment pricing** — different members see different points costs based on their profile, not a flat rate
- **Flash campaign ready** — async event-driven architecture handles high concurrency without timeouts, enabling limited-time high-demand promotions
- **Multi-channel distribution** — same reward published to native app + Shopify + Lazada + BigCommerce simultaneously
- **Multi-quantity in single transaction** — bulk redemption with atomic promo code assignment
- **Birthday and persona targeting** — rewards that only appear for the right members at the right time
- **Real-time confirmation** — members see results within seconds via Realtime push, not polling

### 6c. For Testers

**Config → expected behavior:**


| Config                                                                  | Expected behavior                                        |
| ----------------------------------------------------------------------- | -------------------------------------------------------- |
| `visibility = admin`                                                    | Reward absent from member catalog, visible in admin list |
| `visibility = user` + `allowed_tier = [Gold]`                           | Only Gold-tier members see and can redeem                |
| `require_points_match = true`, no conditions                            | All redemptions fail with match error                    |
| `require_points_match = true`, fallback set, no matching row            | Redemption blocked (fallback ignored)                    |
| `require_points_match = false`, `fallback_points = null`, no conditions | Redemption succeeds with 0 points                        |
| `stock_control = true`, stock = 0                                       | Redemption fails (out of stock)                          |
| `assign_promocode = true`, pool empty                                   | Redemption fails ("insufficient codes")                  |
| `redeem_window_end` in past                                             | Reward visible, redemption blocked                       |
| Transaction limit: per_user, 2/month, user already redeemed 2           | Third redemption blocked                                 |
| Multi-qty = 5, promo pool has 3 codes                                   | Entire transaction fails (all-or-nothing)                |
| Multi-qty = 5, no promo codes                                           | 1 ledger record with qty=5                               |
| Multi-qty = 5, promo codes available                                    | 5 ledger records with qty=1 each, unique codes           |


**Business rules as assertions:**

- ASSERT: When member redeems, points deducted = calculated points × quantity
- ASSERT: Dynamic pricing selects condition with highest specificity score
- ASSERT: When specificity ties, higher priority wins; when priority ties, lowest points wins
- ASSERT: Promo code redemption creates exactly N ledger records for qty=N
- ASSERT: Non-promo redemption creates exactly 1 ledger record regardless of qty
- ASSERT: Redemption within window succeeds; outside window fails
- ASSERT: After successful redemption, `redeemed_status = true`, `used_status = false`
- ASSERT: After mark-as-used, `used_status = true`
- ASSERT: "Save and Publish" sets visibility to `user` regardless of dropdown value

**Status model (two independent tracks):**

| Track | Field | Values | Meaning |
|---|---|---|---|
| Claim | `redeemed_status` | `false` → `true` | Points deducted, reward claimed |
| Usage | `used_status` | `false` → `true` | Reward consumed (voucher used at store, code entered) |
| Fulfillment | `fulfillment_status` | `pending` → `shipped` → `delivered` → `completed` | Physical delivery progress |
| Fulfillment (alt) | `fulfillment_status` | `pending` → `cancelled` or `reject` | Failure paths |

- A reward can be `redeemed_status=true, used_status=false` indefinitely (claimed but not yet used)
- `used_status` can only become `true` after `redeemed_status=true`
- `fulfillment_status` is independent — a `delivered` reward can still be `used_status=false`

**Member-facing UI states** (History drawer sub-filters):
- "My Reward" = `redeemed_status=true, used_status=false, not expired`
- "Used" = `used_status=true`
- "Expired" = `use_expire_date` has passed and `used_status=false`

**Error states and cross-feature scenarios to test:**

- Insufficient points balance; insufficient promo codes in pool; stock depleted
- Transaction limit exceeded (per_user and per_merchant scopes)
- Ineligible tier/persona/tags/birth month; outside redemption window
- No matching condition when `require_points_match = true`
- Concurrent race condition (two members, one stock item — exactly one succeeds)
- Realtime timeout (15s, no event) → "Processing" toast shown
- Tier upgrade → points cost changes on same reward
- Persona change → eligibility and dynamic pricing both update
- Redemption deducts from correct currency wallet, balance updates in real-time
- Reward with `online_store = ['shopify']` bound to discount code → appears on Shopify

## 7. Business Rules

**Rule:** Eligibility is evaluated before points — a member must pass all eligibility filters before the system calculates cost.
**Example:** Member is Silver tier, reward allows only Gold+ → blocked before points are even checked.

**Rule:** Dynamic pricing uses specificity-first matching. A condition matching 3 dimensions always beats one matching 2, regardless of priority values.
**Example:** "Gold + Student + VIP = 30 pts" (specificity 3) beats "Gold + Student = 40 pts" (specificity 2) even if the latter has higher priority.

**Rule:** When multiple conditions have identical specificity and priority, the system selects the lowest points cost (customer-favorable).
**Example:** Two conditions both match Gold tier at priority 100: one says 60 pts, one says 80 pts → member pays 60.

**Rule:** Fallback points apply only when zero conditions match the member. If at least one condition matches, fallback is ignored.
**Example:** Reward has Gold=60pts, fallback=100pts. Silver member (no match) → pays 100. Gold member → pays 60.

**Rule:** Redemptions are all-or-nothing for multi-quantity with promo codes. If the pool has fewer codes than requested, the entire transaction fails — no partial redemption.
**Example:** Member requests qty=10, only 7 codes available → error, zero codes assigned, zero points deducted.

**Rule:** Redemption is async. The API returns an `event_id` immediately; the actual transaction is processed by an event consumer. The frontend subscribes to Realtime for the result.
**Example:** Member clicks "Redeem" → sees spinner → Realtime pushes success with redemption details → UI updates.

**Rule:** "Save and Publish" overrides visibility to `user`, regardless of the visibility dropdown value at save time.
**Example:** Admin sets visibility to `campaign`, clicks "Save and Publish" → reward becomes `user` (public).

**Rule:** Empty eligibility arrays mean unrestricted. `allowed_tier = []` means all tiers qualify, not zero tiers.
**Example:** Reward with no tier filter → Bronze through Diamond can all redeem.

**Rule:** Transaction limits are cumulative. A new redemption's quantity is added to previous redemptions in the window before checking the cap.
**Example:** Limit = 5/month, member already redeemed 3 this month, requests qty=3 → blocked (3+3=6 > 5).

**Rule:** Promo codes are reserved atomically using `FOR UPDATE SKIP LOCKED` to prevent race conditions between concurrent redemptions.
**Example:** Two members redeem simultaneously, 1 code left → exactly one succeeds, the other gets "insufficient codes."

**Rule:** Expiration is calculated at redemption time based on the expire mode. `relative_days = 30` means the expiry is set to 30 days from the moment of redemption, not from reward creation.
**Example:** Reward created Jan 1, member redeems Mar 15 → expires Apr 14.

**Rule:** The user-facing catalog (`api_get_rewards_full_cached`) returns only `visibility = 'user'` rewards. `admin` and `campaign` rewards are excluded.
**Example:** Admin creates a reward with `visibility = 'campaign'` → members never see it in the browse catalog. It can only reach members through AMP push or admin assignment.

**Rule:** Cached reward catalog has a 5-minute TTL. Changes to rewards, stock, or promo codes trigger cache invalidation, but there may be up to 5 minutes of stale data in normal operation.
**Example:** Admin adds stock → members may see old stock count for up to 5 minutes.

## 8. Related Features


| Feature          | Connection to Rewards                                                                                                                                            |
| ---------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Currency         | Points are deducted from the member's wallet upon redemption. See `Currency.md`.                                                                                 |
| Tier             | Eligibility can be tier-gated; dynamic pricing can vary by tier. See `Tier.md`.                                                                                  |
| Tag & Persona    | Eligibility and dynamic pricing dimensions. Persona-aware field filtering affects eligibility checks. See `Tag_and_Persona.md`.                                  |
| Mission          | Missions can grant rewards as completion prizes. Mission-only rewards use `campaign` visibility. See `Mission.md`.                                               |
| AMP Workflows    | Campaign-visibility rewards are distributed to members through AMP rule-based or AI-driven workflows. See `AMP - Rule Based.md`.                                 |
| Translation      | Reward display content supports multi-language via the translation system. See `Translation_System.md`.                                                          |
| Marketplace      | Rewards can be distributed to external storefronts (Shopify, Lazada, etc.) via `online_store[]` and marketplace channel connections. See `MARKETPLACE_SETUP.md`. |
| Forms            | Profile completion (form fields) can be a prerequisite for eligibility when persona-aware filtering is active. See `Forms.md`.                                   |
| Activity/Earning | Members earn points through activities, which they then spend on rewards — the earn-and-burn loop. See `Activity_Based_Earning.md`.                              |
| Reward sourcing (curated) | Partner-catalog and pay-on-redeem **positioning** for proposals and MCP knowledge — distinct from in-app reward configuration. See `feature-docs/reward-sourcing-services.md`. |
