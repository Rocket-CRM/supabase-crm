# CS Watchtower — List + Config + Dashboard

## What This Is

Watchtower is a continuous monitoring system that reviews every conversation (AI and human) against custom natural-language criteria. It surfaces what matters without manual QA overhead — compliance violations, sales opportunities, product feedback, churn signals, and more.

Three views:
- **List page** — Browse configured Watchtower monitors, create new ones
- **Config page** — Define monitoring criteria, scoring rubric, alert thresholds
- **Dashboard** — Real-time trends, flagged conversations, category clusters, drill-down

The AI in this project should use its own judgment for what UI layout produces the best UX for **configuring and viewing always-on conversation monitoring with natural-language criteria**. Study how Decagon's Watchtower product works — then decide the best structure.

---

## FE Project Context

| Layer | Tech |
|---|---|
| Framework | Next.js 16 (App Router, React 19) |
| UI | Shopify Polaris v13 (the only component library) |
| Charts | **ECharts** (for trend visualizations) |
| Backend | All data via `supabase.rpc()` |
| Auth | Supabase Auth, JWT carries merchant context |
| Forms | `react-hook-form` + `zod` |

### Routes

```
src/app/(admin)/cs-watchtower/                → Watchtower list + dashboard
src/app/(admin)/cs-watchtower/[id]/           → Monitor config (create/edit)
src/app/(admin)/cs-watchtower/[id]/results/   → Monitor results + drill-down
```

---

## Backend Connection — Tables & RPCs

### Core Table

There is no dedicated Watchtower table in the Phase 1 schema yet. The Watchtower configuration would be stored in a table like:

**`cs_watchtower_configs`** (to be created)

| Column | Type | Notes |
|---|---|---|
| `id` | uuid PK | |
| `merchant_id` | uuid FK | |
| `name` | text | "Compliance Monitor", "Sales Signal Detector" |
| `criteria` | jsonb | Natural language descriptions of what to flag: `["Customer expresses frustration", "Agent promises refund outside policy", "Customer mentions competitor"]` |
| `scope_filters` | jsonb | `{channels: [], agent_types: ["ai","human"], time_range: "last_7d", customer_tiers: []}` |
| `scoring_rubric` | jsonb | `{fields: [{name: "accuracy", scale: "1-5"}, {name: "policy_compliance", scale: "pass_fail"}]}` |
| `alert_config` | jsonb | `{notify_channel: "slack", notify_on: "critical", threshold: 5, escalate_to_supervisor: true}` |
| `is_active` | boolean | |
| `mode` | text | `continuous` (new conversations) or `historical` (scan past conversations) |
| `created_at` | timestamptz | |
| `updated_at` | timestamptz | |

**`cs_watchtower_flags`** (to be created) — Flagged conversations

| Column | Type | Notes |
|---|---|---|
| `id` | uuid PK | |
| `watchtower_id` | uuid FK | |
| `conversation_id` | uuid FK → cs_conversations | |
| `criteria_matched` | text | Which criteria triggered the flag |
| `category` | text | AI-generated category cluster |
| `scores` | jsonb | Rubric scores for this conversation |
| `severity` | text | `critical`, `warning`, `info` |
| `explanation` | text | AI explanation of why this was flagged |
| `created_at` | timestamptz | |

### RPCs

| RPC | Purpose | Notes |
|---|---|---|
| `cs_bff_get_watchtower_monitors` | List all monitors | Returns: name, criteria summary, is_active, flag count, last scan time |
| `cs_bff_get_watchtower_monitor` | Get monitor for config | Params: monitor_id or null (new) |
| `cs_bff_upsert_watchtower_monitor` | Create/update monitor | Params: name, criteria, scope_filters, scoring_rubric, alert_config, is_active, mode |
| `cs_bff_delete_watchtower_monitor` | Delete monitor | Params: monitor_id |
| `cs_bff_get_watchtower_dashboard` | Dashboard summary | Params: monitor_id (optional — all monitors if null), date_range. Returns: flag volume over time, category breakdown, severity distribution, top flagged conversations. |
| `cs_bff_get_watchtower_flags` | Flagged conversations | Params: monitor_id, category, severity, date_range, pagination. Returns flagged conversations with criteria matched, scores, explanation. Drill-down to conversation. |
| `cs_bff_get_watchtower_categories` | Category clusters | Params: monitor_id, date_range. Returns AI-generated category groupings with counts. |
| `cs_bff_get_watchtower_trends` | Trend data for charts | Params: monitor_id, date_range, granularity. Returns time-series flag counts for charting. |

---

## Key Domain Concepts the UI Must Support

### 1. Natural Language Monitoring Criteria

Monitors define what to watch for in plain language — NOT keyword matching:

| Example Criteria |
|---|
| "Customer expresses frustration or anger" |
| "Agent promises a refund or discount outside of policy" |
| "Customer mentions a competitor product" |
| "Conversation involves a data privacy or legal concern" |
| "Customer signals purchase intent or upsell opportunity" |
| "AI hallucinated or gave incorrect product information" |
| "Customer has contacted more than 3 times about the same issue" |

The system uses LLM-based evaluation to interpret these contextually, not keyword matching.

### 2. Scope Filters

Each monitor can be filtered to specific subsets:
- **Channels** — Only monitor Shopee conversations, or all channels
- **Agent type** — AI conversations only, human only, or both
- **Customer tier** — VIP customers only
- **Time range** — Continuous (new conversations going forward) or historical (scan past N days)

### 3. Scoring Rubric

Each monitor can define scoring fields:
- Accuracy: 1-5 scale
- Empathy: 1-5 scale
- Policy compliance: pass/fail
- Custom fields

Flagged conversations receive scores on each rubric field. Scores track over time — per agent, per AI, per team.

### 4. Alert Configuration

- **Notify on severity** — Only alert on "critical" flags, or all flags
- **Notification channel** — Slack, LINE Notify, email
- **Threshold** — "If more than 5 critical flags in one hour, alert"
- **Escalation** — Auto-assign flagged conversations to supervisor for review

### 5. Category Clusters

Flagged conversations are automatically grouped into meaningful clusters by AI:
- "Data privacy violations"
- "Purchase intent signals"
- "Product defect reports"
- "Shipping complaints"
- "Competitor mentions"

Categories are AI-generated from the flagged content — not predefined.

### 6. Dashboard

Real-time monitoring dashboard:
- **Flag volume trend** — Line chart over time, by severity
- **Category breakdown** — Donut/bar chart of flag categories
- **Top flagged conversations** — Ranked by severity, clickable to drill into conversation
- **Score trends** — If rubric scoring enabled, show average scores over time
- **Cross-reference** — "Do flagged conversations correlate with low CSAT?"

### 7. Drill-Down

From any flag → click into the full conversation transcript with the flag highlighted:
- Why was this flagged (criteria matched + AI explanation)
- Rubric scores
- Full conversation context
- One-click: assign to supervisor, create training material, create knowledge article

---

## Key UX Requirements

1. Criteria authoring should feel natural — text input where admins describe what to watch for in their own words. Not a form with dropdowns.

2. The dashboard should feel like a real-time monitoring center — at a glance, see if anything needs attention.

3. Drill-down flow: dashboard → category → flagged conversations → individual conversation should be smooth and fast.

4. Rubric scoring configuration should be optional and simple to set up.

---

## What NOT to Build (Backend Handles These)

- LLM evaluation of conversations against criteria — backend Inngest cron job handles
- Category clustering — backend AI generates categories from flagged content
- Alert delivery (Slack, LINE Notify, email) — backend notification system
- Scoring calculation — backend AI evaluates conversations against rubric
- Historical scanning — backend processes past conversations in batch
