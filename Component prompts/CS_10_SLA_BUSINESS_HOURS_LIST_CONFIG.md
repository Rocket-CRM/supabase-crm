# CS SLA Policies + Business Hours — List + Config

## What This Is

Two related configuration pages:

- **SLA Policies** — Define response time and resolution time targets for different conversation/ticket types
- **Business Hours** — Define when the brand's support is available (SLA timers only count during business hours)

These are tightly coupled: SLA timers use business hours to calculate deadlines. Managed as a combined settings area.

The AI in this project should use its own judgment for what UI layout produces the best UX for **configuring service level agreements and business hours schedules**. Study how Zendesk, Freshdesk, or Intercom handle SLA configuration — then decide the best structure.

---

## FE Project Context

| Layer | Tech |
|---|---|
| Framework | Next.js 16 (App Router, React 19) |
| UI | Shopify Polaris v13 (the only component library) |
| Backend | All data via `supabase.rpc()` |
| Auth | Supabase Auth, JWT carries merchant context |
| Forms | `react-hook-form` + `zod` |

### Routes

```
src/app/(admin)/cs-sla/                     → SLA policies list + business hours
src/app/(admin)/cs-sla/policies/[id]/       → SLA policy config (create/edit)
src/app/(admin)/cs-sla/business-hours/[id]/ → Business hours config (create/edit)
```

The AI should decide whether SLA policies and business hours are tabs on one page, sections, or separate sub-routes.

---

## Backend Connection — Tables & RPCs

### Core Tables

**`cs_sla_policies`**

| Column | Type | Notes |
|---|---|---|
| `id` | uuid PK | |
| `merchant_id` | uuid FK | |
| `name` | text | "VIP 1-hour response", "Standard 4-hour" |
| `response_target_minutes` | int | 60, 240 |
| `resolution_target_minutes` | int | 1440 (24h), 4320 (72h) |
| `conditions` | jsonb | When this SLA applies: `{priority: ["urgent","high"], channel: ["shopee"], customer_tier: ["VIP"]}` |
| `is_active` | boolean | |
| `created_at` | timestamptz | |
| `updated_at` | timestamptz | |

**`cs_business_hours`**

| Column | Type | Notes |
|---|---|---|
| `id` | uuid PK | |
| `merchant_id` | uuid FK | |
| `name` | text | "Bangkok Office Hours", "24/7 Support" |
| `timezone` | text | "Asia/Bangkok" |
| `schedule` | jsonb | `{mon: {start: "09:00", end: "18:00"}, sat: null, ...}` (null = closed) |
| `holidays` | jsonb | `[{date: "2026-04-13", name: "Songkran"}, ...]` |
| `is_default` | boolean | Merchant-level fallback schedule |
| `created_at` | timestamptz | |
| `updated_at` | timestamptz | |

### RPCs — SLA Policies

| RPC | Purpose | Notes |
|---|---|---|
| `cs_bff_get_sla_policies` | List all SLA policies | Returns: id, name, response/resolution targets, conditions summary, is_active, usage count (how many tickets currently using this SLA) |
| `cs_bff_get_sla_policy` | Get policy for edit | Params: policy_id or null (for new) |
| `cs_bff_upsert_sla_policy` | Create/update policy | Params: name, response_target_minutes, resolution_target_minutes, conditions, is_active |
| `cs_bff_delete_sla_policy` | Delete policy | Params: policy_id. Fails if currently assigned to open tickets. |

### RPCs — Business Hours

| RPC | Purpose | Notes |
|---|---|---|
| `cs_bff_get_business_hours` | List all schedules | Returns: id, name, timezone, brief schedule summary, is_default, linked team count |
| `cs_bff_get_business_hours_detail` | Get schedule for edit | Params: schedule_id or null (for new) |
| `cs_bff_upsert_business_hours` | Create/update schedule | Params: name, timezone, schedule (per-day hours), holidays, is_default |
| `cs_bff_delete_business_hours` | Delete schedule | Params: schedule_id. Fails if linked to active teams. |

---

## Key Domain Concepts the UI Must Support

### 1. SLA Policy Configuration

Each SLA policy defines:
- **Response time target** — How quickly the brand should first respond (in minutes)
- **Resolution time target** — How quickly the issue should be resolved (in minutes)
- **Conditions** — When this SLA applies. Condition builder with:
  - Priority: urgent, high, normal, low
  - Channel: shopee, lazada, tiktok, line, whatsapp, etc.
  - Customer tier: VIP, Gold, Standard (from CRM bridge)
  - Ticket type: refund, complaint, product_inquiry, etc.

Multiple SLA policies can exist. The most specific matching policy applies to each ticket.

**Display format:** Show targets in human-readable form: "Respond within 1 hour, resolve within 24 hours" rather than raw minutes.

### 2. Business Hours Schedule

Each schedule defines:
- **Timezone** — Which timezone the hours apply in (e.g., Asia/Bangkok)
- **Weekly schedule** — Per day: start time, end time, or closed. E.g., Mon-Fri 09:00-18:00, Sat 09:00-12:00, Sun closed.
- **Holidays** — Specific dates when support is closed. SLA timers pause on holidays.

Visual schedule builder: a weekly grid where the admin sets hours per day. Holiday calendar for adding exception dates.

### 3. SLA Timer Behavior

How the SLA timer works (for context — the FE displays, backend calculates):
- Timer starts when ticket/conversation is created
- Timer ONLY counts during business hours (nights/weekends/holidays don't count)
- Timer PAUSES when status = "waiting on customer" (brand replied, waiting for response)
- Timer RESUMES when customer responds
- Warning alert at configurable threshold (e.g., 10 min before deadline)
- Breach when deadline passes

### 4. Linking Business Hours to Teams

Business hours schedules are assigned to teams (via `admin_teams.business_hours_id`). Show which teams use each schedule. A default schedule applies when no team-specific one is set.

---

## Key UX Requirements

1. SLA policy conditions should use a visual condition builder (dropdowns, multi-select) — not raw JSON editing.

2. Business hours should have a visual weekly grid. Easy to set the same hours for Mon-Fri and different for weekends.

3. Holiday management: calendar picker for adding holidays. Show upcoming holidays clearly.

4. Show which teams/how many tickets are affected by each SLA policy and business hours schedule.

---

## What NOT to Build (Backend Handles These)

- SLA timer calculation (accounting for business hours, timezone, pauses) — backend computes
- SLA assignment to tickets (matching conditions) — backend assigns on ticket creation
- SLA breach detection and alerting — backend cron job checks every 5 minutes
- Time zone conversions — backend handles all timezone math
