# Customer 360 Dashboard Component

## Prerequisites: Clean Slate

**Before building anything**, strip this project of any previous component code, patterns, or idiosyncrasies from prior implementations. We are rebuilding this component from scratch using:
- **Polaris Styles NPM Package** — for all design tokens, utility classes, and base styles
- **Polaris Component Structure Guidelines** (`.md` in GitHub) — for component patterns, file structure, and interaction conventions

Study the Polaris style package and structure guide `.md` in GitHub properly and decide the structure and design of the component to be consistent with Polaris style.

## Prerequisites: Backend Initialization

**Before building any UI**, you MUST understand the backend thoroughly:

1. **Init Supabase via MCP** — connect to the Supabase project and inspect the live schema
2. **Inspect these 4 functions** via Supabase MCP — pull their full SQL definitions to understand exact return shapes:
   - `bff_admin_get_member_360` — the central function (new, documented below)
   - `bff_admin_get_user_packages` — existing, returns packages with entitlements
   - `bff_admin_get_user_benefits` — existing, returns active + all benefits
   - `bff_get_user_missions` — existing, returns missions with progress

---

## Overview

Build a **Customer 360 Dashboard** — a single-page admin view that shows everything about a loyalty program member at a glance. This is the "member profile" page an admin sees when they click on a user.

The layout is inspired by Microsoft Dynamics 365 Customer Insights (reference image provided), but adapted for a **loyalty CRM** with points, tiers, packages, redemptions, missions, and referrals.

This is for use in a WeWeb project, styled using the **Polaris Styles NPM Package** and following **Polaris Component Structure Guidelines**.

---

## Architecture: 4 Parallel API Calls

The dashboard loads data from **4 parallel RPC calls** on page load. All fire simultaneously — no waterfall.

### API Connection

**Base URL:** `https://wkevmsedchftztoolkmi.supabase.co`

**API Key (anon key):** `eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6IndrZXZtc2VkY2hmdHp0b29sa21pIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NTA1MTM2OTgsImV4cCI6MjA2NjA4OTY5OH0.bd8ELGtX8ACmk_WCxR_tIFljwyHgD3YD4PdBDpD-kSM`

**Authorization:** Bearer `{user_access_token}` — bind as a prop from auth context.

### The 4 Calls

| # | Endpoint | Method | Params | Returns |
|---|----------|--------|--------|---------|
| 1 | `POST /rest/v1/rpc/bff_admin_get_member_360` | RPC | `{ "p_user_id": "<uuid>" }` | Central data: profile, tier, wallet, charts, referral, timeline, checkin |
| 2 | `POST /rest/v1/rpc/bff_admin_get_user_packages` | RPC | `{ "p_user_id": "<uuid>" }` | Packages with entitlement items & utilization |
| 3 | `POST /rest/v1/rpc/bff_admin_get_user_benefits` | RPC | `{ "p_user_id": "<uuid>" }` | Standing benefits (persona + marketing + admin) |
| 4 | `POST /rest/v1/rpc/bff_get_user_missions` | RPC | `{ "p_user_id": "<uuid>" }` | Missions with progress, completion %, button state |

All calls include headers:
```
apikey: <anon_key>
Authorization: Bearer <user_access_token>
Content-Type: application/json
```

The component receives `p_user_id` as a **prop** (the admin navigates to this page from a user list).

---

## CALL 1: `bff_admin_get_member_360` — Response Shape

This is the central function. Response envelope: `{ success: boolean, data: { ... } }`

### `data.profile`

```json
{
  "user_id": "uuid",
  "fullname": "Siriporn Thongsuk",
  "firstname": "Siriporn",
  "lastname": "Thongsuk",
  "email": "siriporn.t@samitivej-test.com",
  "tel": "+66812345001",
  "line_id": null,
  "image": null,
  "user_type": "buyer",
  "user_stage": "customer",
  "birth_date": null,
  "gender": null,
  "external_user_id": null,
  "created_at": "2026-03-19T06:52:19.066445+00:00",
  "tier_id": "uuid",
  "tier_name": "Silver",
  "tier_color": "#9E9E9E",
  "tier_icon": "🥈",
  "tier_ranking": 1,
  "persona_id": "uuid",
  "persona_name": "Connex",
  "persona_group_name": "VIP Star",
  "contract_type": "vip",
  "company_name": "Samitivej Hospital Group",
  "contract_status": "active",
  "tags": [
    { "id": "uuid", "tag_name": "VIP" },
    { "id": "uuid", "tag_name": "High Spender" }
  ]
}
```

### `data.tier_progress`

```json
{
  "current_tier_id": "uuid",
  "current_tier_name": "Silver",
  "next_tier_id": "uuid",
  "next_tier_name": "Gold",
  "upgrade_progress_percent": 72.0,
  "upgrade_metric_needed": "spend",
  "upgrade_deadline": "2026-12-31",
  "maintain_progress": 85.0,
  "maintain_metric_needed": "spend",
  "maintain_deadline": "2026-06-30"
}
```

*Note: Fields may be null if there's no next tier or no conditions configured.*

### `data.tier_history`

```json
[
  {
    "id": "uuid",
    "change_type": "upgrade",
    "change_reason": "Met spend requirement",
    "created_at": "2026-01-15T00:00:00Z",
    "from_tier_name": "Bronze",
    "from_tier_color": "#CD7F32",
    "to_tier_name": "Silver",
    "to_tier_color": "#9E9E9E"
  },
  {
    "id": "uuid",
    "change_type": "initial",
    "change_reason": "New user signup",
    "created_at": "2025-06-01T00:00:00Z",
    "from_tier_name": null,
    "from_tier_color": null,
    "to_tier_name": "Bronze",
    "to_tier_color": "#CD7F32"
  }
]
```

### `data.wallet`

```json
{
  "points_balance": 12450,
  "ticket_balances": [
    { "ticket_type_id": "uuid", "ticket_code": "PARKING", "name": "Parking Ticket", "balance": 3 },
    { "ticket_type_id": "uuid", "ticket_code": "RAFFLE", "name": "Raffle Ticket", "balance": 12 }
  ],
  "lifetime_earned": 84200,
  "lifetime_burned": 71750,
  "expiring_soon_amount": 1200,
  "expiring_soon_date": "2026-03-31"
}
```

### `data.points_monthly` — Area Chart

```json
[
  { "month": "2025-04-01", "earned": 5200, "burned": 3100 },
  { "month": "2025-05-01", "earned": 6800, "burned": 4500 },
  { "month": "2025-06-01", "earned": 4100, "burned": 2200 }
]
```

### `data.points_by_source` — Donut Chart

```json
[
  { "source_type": "purchase", "total_earned": 52200 },
  { "source_type": "mission", "total_earned": 15100 },
  { "source_type": "referral", "total_earned": 6700 },
  { "source_type": "campaign", "total_earned": 5900 },
  { "source_type": "activity", "total_earned": 4300 }
]
```

### `data.redemption_summary`

```json
{
  "total_count": 32,
  "total_points_spent": 24600,
  "total_qty": 35
}
```

### `data.redemptions_by_reward` — Horizontal Bar Chart

```json
[
  { "reward_name": "Airport Lounge Pass", "reward_image": ["url"], "count": 12, "points_spent": 6000 },
  { "reward_name": "Spa Session", "reward_image": ["url"], "count": 8, "points_spent": 8000 },
  { "reward_name": "Dining Voucher ฿500", "reward_image": null, "count": 6, "points_spent": 3000 }
]
```

### `data.redemptions_monthly` — Line Chart

```json
[
  { "month": "2025-04-01", "count": 3, "points_spent": 2100 },
  { "month": "2025-05-01", "count": 5, "points_spent": 3500 }
]
```

### `data.purchase_summary`

```json
{
  "lifetime_spend": 245000,
  "order_count": 38,
  "avg_order_value": 6447.37,
  "last_purchase_at": "2026-03-18T14:30:00Z"
}
```

### `data.purchases_monthly` — Bar + Line Combo Chart

```json
[
  { "month": "2025-04-01", "spend": 18500, "orders": 3 },
  { "month": "2025-05-01", "spend": 22000, "orders": 4 }
]
```

### `data.referral`

```json
{
  "invite_code": "ABC12345",
  "invites_sent": 12,
  "signed_up": 7,
  "first_purchase": 4,
  "points_from_referrals": 3500
}
```

### `data.checkin`

```json
{
  "total_checkins": 45,
  "current_streak": 7,
  "longest_streak": 14,
  "last_checkin_date": "2026-03-19"
}
```

### `data.activity_stream` — Timeline

```json
[
  {
    "event_type": "purchase",
    "event_id": "uuid",
    "title": "Purchase #TXN-00482",
    "description": "Siam Paragon",
    "amount": 2500,
    "currency_name": null,
    "timestamp": "2026-03-18T14:30:00Z"
  },
  {
    "event_type": "points_earn",
    "event_id": "uuid",
    "title": "+250 points",
    "description": "purchase",
    "amount": 250,
    "currency_name": "points",
    "timestamp": "2026-03-18T14:30:05Z"
  },
  {
    "event_type": "redemption",
    "event_id": "uuid",
    "title": "Airport Lounge Pass",
    "description": "-500 points",
    "amount": 500,
    "currency_name": null,
    "timestamp": "2026-03-15T10:00:00Z"
  },
  {
    "event_type": "tier_change",
    "event_id": "uuid",
    "title": "upgrade: Gold",
    "description": "From Silver",
    "amount": null,
    "currency_name": null,
    "timestamp": "2026-02-28T00:00:00Z"
  },
  {
    "event_type": "package_assigned",
    "event_id": "uuid",
    "title": "VIP Welcome Pack",
    "description": "Source: persona_assignment",
    "amount": null,
    "currency_name": null,
    "timestamp": "2026-02-28T00:00:00Z"
  },
  {
    "event_type": "referral",
    "event_id": "uuid",
    "title": "Referral: John Doe",
    "description": "Completed first purchase",
    "amount": null,
    "currency_name": null,
    "timestamp": "2026-02-20T00:00:00Z"
  },
  {
    "event_type": "mission_complete",
    "event_id": "uuid",
    "title": "Weekly Spender Mission",
    "description": "Completion #1",
    "amount": null,
    "currency_name": null,
    "timestamp": "2026-02-15T00:00:00Z"
  },
  {
    "event_type": "checkin",
    "event_id": "uuid",
    "title": "Check-in Day 7",
    "description": "",
    "amount": 10,
    "currency_name": null,
    "timestamp": "2026-02-10T09:00:00Z"
  }
]
```

### `data.activity_counts` — For Filter Tab Badges

```json
{
  "purchase": 42,
  "points": 38,
  "redemption": 15,
  "tier_change": 4,
  "package": 3,
  "referral": 3,
  "mission_complete": 12,
  "checkin": 2
}
```

---

## CALL 2: `bff_admin_get_user_packages` — Response Shape

Envelope: `{ success: boolean, data: { user_id, packages: [...] } }`

```json
{
  "packages": [
    {
      "assignment_id": "uuid",
      "source_type": "persona_assignment",
      "status": "active",
      "effective_from": "2026-01-01T00:00:00Z",
      "effective_to": "2027-01-01T00:00:00Z",
      "created_at": "2026-01-01T00:00:00Z",
      "assigned_by": "system",
      "package_id": "uuid",
      "package_name": "VIP Welcome Pack",
      "package_description": "Welcome package for VIP members",
      "entitlements": [
        {
          "redemption_id": "uuid",
          "reward_id": "uuid",
          "reward_name": "Spa Session",
          "reward_image": "url",
          "qty": 4,
          "used_qty": 2,
          "remaining": 2,
          "use_expire_date": "2027-01-01T00:00:00Z",
          "used_status": false
        },
        {
          "redemption_id": "uuid",
          "reward_id": "uuid",
          "reward_name": "Airport Lounge Pass",
          "reward_image": "url",
          "qty": 6,
          "used_qty": 6,
          "remaining": 0,
          "use_expire_date": "2027-01-01T00:00:00Z",
          "used_status": true
        }
      ]
    }
  ]
}
```

---

## CALL 3: `bff_admin_get_user_benefits` — Response Shape

Envelope: `{ success: boolean, data: { user_id, active_benefits: [...], all_benefits: [...] } }`

```json
{
  "active_benefits": [
    {
      "id": "uuid",
      "category": "opd",
      "benefit_type": "discount_percent",
      "value": 25,
      "source_mode": "persona",
      "source_name": "Connex VIP",
      "persona_name": "Connex"
    },
    {
      "id": "uuid",
      "category": "parking",
      "benefit_type": "free_access",
      "value": 1,
      "source_mode": "persona",
      "source_name": "Connex VIP",
      "persona_name": "Connex"
    }
  ],
  "all_benefits": [...]
}
```

---

## CALL 4: `bff_get_user_missions` — Response Shape

Envelope: `{ success: boolean, data: { user_id, missions: [...], total_count } }`

```json
{
  "missions": [
    {
      "mission_id": "uuid",
      "mission_code": "WEEKLY_SPEND",
      "mission_name": "Spend ฿10,000 this month",
      "mission_description": "Complete a purchase of ฿10,000 within the month",
      "mission_type": "standard",
      "images": ["url"],
      "activation_type": "auto",
      "claim_type": "auto_claim",
      "is_active": true,
      "start_date": "2026-03-01T00:00:00Z",
      "end_date": "2026-03-31T23:59:59Z",
      "has_progress": true,
      "is_accepted": true,
      "current_progress": 6500,
      "lifetime_completions": 0,
      "unclaimed_completions": 0,
      "last_progress_at": "2026-03-18T14:30:00Z",
      "total_target": 10000,
      "completion_percentage": 65.0,
      "conditions_completed": 0,
      "total_conditions": 1,
      "can_accept": false,
      "can_claim": false,
      "levels_completed": null,
      "total_levels": null,
      "button_action": "view_progress"
    }
  ],
  "total_count": 3
}
```

---

## UI Layout — 12 Blocks

### Grid Structure

```
┌─────────────────────┬──────────────────────┬──────────────────────────┐
│  1. PROFILE HEADER  │  2. TIER PROGRESS    │                          │
│                     │                      │  12. ACTIVITY STREAM     │
├─────────────────────┼──────────────────────┤                          │
│  3. POINTS &        │  4. POINTS SOURCE    │                          │
│  CURRENCY           │                      │                          │
├─────────────────────┼──────────────────────┤                          │
│  5. REDEMPTIONS     │  6. REDEMPTIONS      │                          │
│  BREAKDOWN          │  TREND               │                          │
├─────────────────────┼──────────────────────┤                          │
│  7. PURCHASE SPEND  │  8. PACKAGE          │                          │
│                     │  UTILIZATION         │                          │
├─────────────────────┼──────────────────────┤                          │
│  9. BENEFITS        │  10. MISSIONS        │                          │
├─────────────────────┼──────────────────────┤                          │
│  11. REFERRAL       │                      │                          │
│  FUNNEL             │                      │                          │
└─────────────────────┴──────────────────────┴──────────────────────────┘
```

The left 2/3 is a 2-column grid. The right 1/3 is the activity stream (full-height scrollable panel).

---

## Block 1: Profile Header

**Data source:** `data.profile` from Call 1

**Visual:** Card with avatar area on the left (use `profile.image` or fallback to initials circle colored by `tier_color`). Tier badge as a colored pill using `tier_color` and `tier_icon` + `tier_name`. Persona shown as a subtitle: "{persona_name} @ {persona_group_name}".

**Display fields:**
- `fullname` — primary heading
- `tier_icon` + `tier_name` — colored badge pill (background = `tier_color`)
- `persona_name` + `persona_group_name` — subtitle (e.g., "Executive @ Corporate")
- `company_name` — if contract persona, show company
- `contract_type` — small label (corporate, vip, partner, insurance)
- `email`, `tel`, `line_id` — contact info row with icons
- `user_type` — small badge (buyer/seller)
- `tags` — array of colored pill chips, map over `tags[].tag_name`
- `created_at` — "Member since Mar 2025" format
- `user_stage` — small status indicator

**Empty state:** Always has data (user must exist to reach this page).

---

## Block 2: Tier Progress — Gauge Chart

**Data source:** `data.tier_progress` + `data.tier_history` from Call 1

**Visual: Semi-circle gauge (speedometer style).** The gauge fills from 0% to 100% based on `upgrade_progress_percent`. Left label = `current_tier_name`, right label = `next_tier_name`.

- Center of gauge: big number showing `upgrade_progress_percent` + "%" (e.g., "72%")
- Below gauge: text showing metric — derive from `upgrade_metric_needed`: if "spend" → "฿14,400 / ฿20,000 to {next_tier_name}"
- Below that: `maintain_deadline` formatted as "Maintain by: Jun 30, 2026"
- Below that: **tier history timeline** — horizontal row of dots/chips from `tier_history[]`:
  - Each chip: `to_tier_name` colored by `to_tier_color`, with date below
  - Connected by a line/arrow showing progression

**Empty state:** If `next_tier_name` is null, show "Top tier reached" with a crown/star icon. If `upgrade_progress_percent` is null, show "No tier conditions configured".

---

## Block 3: Points & Currency — Area Chart with Summary

**Data source:** `data.wallet` + `data.points_monthly` from Call 1

**Visual:** Card with big number and area chart below.

- **Big number:** `wallet.points_balance` formatted with comma separators (e.g., "12,450 pts")
- **Sub-numbers row:** 
  - "Earned: {lifetime_earned}" with green color
  - "Burned: {lifetime_burned}" with red/orange color
- **Warning badge:** If `expiring_soon_amount > 0`, show amber alert: "{expiring_soon_amount} pts expiring {expiring_soon_date formatted}"
- **Ticket pills:** If `ticket_balances` is not empty, show small pills: "{name}: {balance}" for each
- **Area chart:** Plot `points_monthly[]` — X-axis = month (formatted "Apr", "May", etc.), two areas:
  - Green area (above) = `earned`
  - Red/orange area (below) = `burned`
  - Use a mirror/butterfly chart style if possible, otherwise stacked

**Chart library:** Use Chart.js or ApexCharts (whatever's consistent with Polaris). The chart should be responsive and fit within the card.

**Empty state:** If `points_monthly` is empty array, show "No points activity yet" with a muted chart placeholder.

---

## Block 4: Points Source — Donut Chart

**Data source:** `data.points_by_source` from Call 1

**Visual: Donut/ring chart** with center number showing total.

- Each segment = one `source_type` from the array
- Color mapping for source types:
  - `purchase` → green
  - `mission` → blue
  - `referral` → purple
  - `campaign` → orange
  - `activity` → teal
  - `manual` → gray
  - any other → default gray
- Legend below the donut showing source name + percentage
- Center of donut: total lifetime earned (sum of all `total_earned`)
- Calculate percentage client-side: `(item.total_earned / sum_all) * 100`

**Empty state:** If array is empty, show "No earning history" with a muted donut outline.

---

## Block 5: Redemptions Breakdown — Horizontal Bar Chart

**Data source:** `data.redemptions_by_reward` + `data.redemption_summary` from Call 1

**Visual:** Card with summary numbers at top and horizontal bar chart below.

- **Summary row:**
  - "Total: {redemption_summary.total_count} redemptions"
  - "Points spent: {redemption_summary.total_points_spent}"
- **Horizontal bar chart:** Each bar = one reward from `redemptions_by_reward[]`
  - Y-axis = `reward_name` (text labels)
  - X-axis = `count` (number of times redeemed)
  - Bar color: use brand color or vary by index
  - Show `count` value at end of each bar
  - Max 10 bars (data is already limited to 10)

**Empty state:** If array is empty, show "No redemptions yet".

---

## Block 6: Redemptions Trend — Line Chart

**Data source:** `data.redemptions_monthly` from Call 1

**Visual: Line chart with optional dual axis.**

- X-axis = month (from `month` field, formatted "Apr", "May")
- Primary line = `count` (redemptions per month)
- Optional secondary line = `points_spent` (on right axis, if using dual axis)
- Area fill under the primary line for visual weight

**Empty state:** If array is empty, show "No redemption trend data".

---

## Block 7: Purchase Spending — Bar + Line Combo Chart

**Data source:** `data.purchase_summary` + `data.purchases_monthly` from Call 1

**Visual:** Card with summary numbers and combo chart.

- **Summary row (4 mini stats):**
  - "฿{lifetime_spend}" — total spend, formatted with comma separators
  - "{order_count} orders"
  - "AOV ฿{avg_order_value}" — average order value
  - "Last: {last_purchase_at}" — relative time (e.g., "2 days ago")
- **Combo chart:**
  - Bars = `spend` per month (left Y-axis, currency formatted)
  - Line with dots = `orders` per month (right Y-axis, integer)
  - X-axis = month labels

**Empty state:** If `purchases_monthly` is empty, show "No purchase history".

---

## Block 8: Package Utilization — Stacked Progress Bars

**Data source:** Call 2 response (`bff_admin_get_user_packages`)

**Visual:** For each package in `packages[]`, show a card/section:

- **Package header:** `package_name` + `source_type` badge + validity dates
  - Calculate days remaining: `effective_to - now()`
  - Show red warning if < 30 days remaining and utilization < 50%
- **Overall utilization bar:** Calculate from entitlements:
  - `total_used = sum(entitlements[].used_qty)`
  - `total_granted = sum(entitlements[].qty)`
  - `utilization_pct = total_used / total_granted * 100`
  - Show as a wide progress bar with percentage label
- **Per-item progress bars:** For each item in `entitlements[]`:
  - `reward_name` label
  - Progress bar: green portion = `used_qty`, gray = `remaining`
  - Text: "{used_qty}/{qty} ({used_qty/qty*100}%)"
  - If `used_status` is true, show checkmark (fully consumed)

**Empty state:** If `packages` array is empty, show "No packages assigned".

---

## Block 9: Benefits — Icon Badge Grid

**Data source:** Call 3 response (`bff_admin_get_user_benefits`), use `active_benefits[]`

**Visual: Grid of small icon cards** (not a table). Each benefit is a mini card:

- **Icon:** Based on `category`:
  - `opd` → stethoscope icon
  - `pharmacy` → pill/medicine icon
  - `parking` → car/parking icon
  - `dental` → tooth icon
  - `dining` → utensils icon
  - default → star icon
- **Text:** Format based on `benefit_type`:
  - `discount_percent` → "{value}% {category} Discount"
  - `discount_fixed` → "฿{value} {category} Discount"
  - `free_access` → "Free {category} Access"
  - `priority` → "Priority {category}"
- **Source badge:** Small text: "via {persona_name}" or "via {source_name}"
- **Style:** Cards should look like achievement badges — compact, visual

**Empty state:** If `active_benefits` is empty, show "No active benefits".

---

## Block 10: Mission Progress — Radial Progress Rings

**Data source:** Call 4 response (`bff_get_user_missions`), use `missions[]`

**Visual: Grid of circular progress indicators.** Each mission gets a ring:

- **Circular progress ring:** Fill to `completion_percentage`%
  - Green if > 75%, amber if > 25%, gray if 0%
  - Center number: `completion_percentage`% (e.g., "65%")
- **Below ring:**
  - `mission_name` (max 2 lines, truncate)
  - Progress text: e.g., "{current_progress}/{total_target}" if numeric
  - Mission dates: "Ends: {end_date formatted}"
- **Status indicator:**
  - If `button_action` = "claim_outcome", show pulsing green "Claim" badge
  - If `lifetime_completions > 0`, show "Completed ×{lifetime_completions}" badge
- For milestone missions (`mission_type` = "milestone"):
  - Show "Level {levels_completed}/{total_levels}" instead of percentage

**Empty state:** If `missions` is empty, show "No active missions".

---

## Block 11: Referral Funnel — Funnel Chart

**Data source:** `data.referral` from Call 1

**Visual: Horizontal funnel/bar visualization.**

Three bars of decreasing width:
1. "Invited" → `invites_sent` (widest bar)
2. "Signed Up" → `signed_up` (medium bar)
3. "First Purchase" → `first_purchase` (narrowest bar)

Each bar shows count and conversion rate (e.g., "7 (58%)" where 58% = 7/12).

Below the funnel:
- "Invite Code: {invite_code}" — with copy button
- "Points earned from referrals: {points_from_referrals}"

**Empty state:** If `invites_sent` = 0 and `invite_code` is null, show "No referral activity". If they have an invite code but no referrals, still show the code with "0 referrals sent".

---

## Block 12: Activity Stream — Vertical Timeline (Right Panel)

**Data source:** `data.activity_stream` + `data.activity_counts` from Call 1

**Visual: Full-height scrollable panel** on the right side of the layout (takes ~1/3 width). Inspired by the "Timeline" panel in the reference image.

### Filter Tabs

At the top of the panel, show filter tabs with count badges:
- **All** ({sum of all activity_counts})
- **Purchase** ({activity_counts.purchase})
- **Points** ({activity_counts.points})
- **Redemptions** ({activity_counts.redemption})
- **Missions** ({activity_counts.mission_complete})
- **Others** ({tier_change + package + referral + checkin})

When a tab is selected, filter `activity_stream[]` by matching `event_type`.

### Timeline Entries

Each entry in `activity_stream[]` renders as a timeline item:

- **Colored circle icon** (left side) based on `event_type`:
  - `purchase` → green circle, shopping cart icon
  - `points_earn` → blue circle, plus/arrow-up icon
  - `points_burn` → orange circle, minus/arrow-down icon
  - `redemption` → purple circle, gift icon
  - `tier_change` → gold circle, trophy/crown icon
  - `package_assigned` → teal circle, package/box icon
  - `referral` → pink circle, people/share icon
  - `mission_complete` → yellow circle, star/flag icon
  - `checkin` → green circle, check/calendar icon
- **Title:** `title` field (bold)
- **Description:** `description` field (muted color, smaller)
- **Amount:** If `amount` is not null, show formatted (e.g., "฿2,500" for purchases, "+250" for points)
- **Timestamp:** Relative time (e.g., "2 hours ago", "3 days ago", "Mar 15")
- **Connecting line:** Vertical line connecting all entries (timeline style)

The entries are already sorted by `timestamp DESC` from the server.

### Scroll Behavior

The panel is scrollable. On initial load, show the first `p_activity_limit` (50) entries. If the user needs more, you can re-call the function with a higher limit, but 50 is sufficient for most cases.

---

## Responsive Behavior

- **Desktop (>1200px):** 3-column layout (2 grid columns + timeline panel)
- **Tablet (768–1200px):** 2-column layout, timeline moves below the grid
- **Mobile (<768px):** Single column, all blocks stack vertically, timeline at the bottom

---

## Loading States

Each of the 4 calls resolves independently. Show:
- **Skeleton loaders** for each block while its data is loading
- **Blocks from Call 1** all appear together when Call 1 resolves
- **Blocks 8, 9, 10** appear as their respective calls (2, 3, 4) resolve
- If a call fails, show an error state for that block only — don't break the whole page

---

## Empty State Handling

The data may have empty arrays or zero values for any section. Each block has an empty state defined above. The key principle:
- **Never show broken/empty charts** — always show a meaningful "No data yet" message
- **Keep the layout stable** — empty blocks should still take up their grid space so the layout doesn't shift

---

## Number Formatting

- Currency amounts: Use ฿ prefix with comma separators (e.g., "฿245,000")
- Points: Comma separators + "pts" suffix (e.g., "12,450 pts")
- Percentages: 1 decimal place (e.g., "72.0%"), 0 decimal if whole number
- Dates: "Mar 20, 2026" for absolute, "2 hours ago" for relative (within 7 days)
- Months on charts: "Apr", "May", "Jun" (3-letter abbreviation)

---

## Color Palette for Charts

Use consistent colors across all charts:

```
Purchase / Spend:  #22C55E (green)
Points Earn:       #3B82F6 (blue)
Points Burn:       #F97316 (orange)
Redemption:        #8B5CF6 (purple)
Mission:           #EAB308 (yellow)
Referral:          #EC4899 (pink)
Campaign:          #06B6D4 (teal)
Activity:          #14B8A6 (teal-green)
Tier Change:       #F59E0B (amber/gold)
Package:           #6366F1 (indigo)
Check-in:          #10B981 (emerald)
Manual:            #9CA3AF (gray)
```

---

## Styling & Component Gap Tracking

This component depends on two shared packages:
1. **Polaris Styles NPM Package** — shared design tokens, utility classes, and base styles
2. **Polaris Component Structure Guidelines** (`.md` in GitHub) — component patterns, states, and interaction guidelines

### Rules

- **Always use** existing styles/components from Polaris first. Do not reinvent what already exists.
- **When a pattern is needed but not covered**, implement it locally but **log it as a gap**.
- At the end of the build, produce two lists:

#### 1. Polaris Styles NPM Package — Items to Add
#### 2. Polaris Component Structure Guidelines — Items to Add

### Format for Each Gap Entry
```
- **What:** [name/description of the missing pattern]
- **Where used:** [which part of this component uses it]
- **Suggested addition:** [what should be added to the package/guidelines]
```

---

## Deployment

When the component is complete:
1. **Create a new GitHub repository** in the `rocket-crm` organization called `customer-360`
2. **Push all code** to the repo
3. Ensure the repo has a proper `README.md`, `package.json`, and is ready for other developers to clone and run
