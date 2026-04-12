# CS Analytics Dashboard

## What This Is

A comprehensive analytics page for CS operations. Covers operational metrics, AI performance, customer insights, quality assurance, and CSAT. This is a read-only dashboard with drill-down capabilities — managers and supervisors use it to understand how the CS operation is performing.

The AI in this project should use its own judgment for what dashboard layout, chart types, metric groupings, and drill-down patterns produce the best UX for **monitoring a customer service operation with AI and human agents**. Study how Intercom's reporting, Zendesk Explore, or Freshdesk Analytics approach this — then decide the best structure.

---

## FE Project Context

| Layer | Tech |
|---|---|
| Framework | Next.js 16 (App Router, React 19) |
| UI | Shopify Polaris v13 (the only component library) |
| Charts | **ECharts** (available in the project) |
| Backend | All data via `supabase.rpc()` |
| Auth | Supabase Auth, JWT carries merchant context |

### Route

```
src/app/(admin)/cs-analytics/
```

The AI should decide whether this is one page with sections/tabs or multiple sub-routes — whatever works best for the volume of data.

---

## Backend Connection — RPCs

All analytics data is pre-aggregated by backend. The FE calls RPCs with date range and optional filters, receives ready-to-display data.

### RPCs — Operational Metrics

| RPC | Purpose | Returns |
|---|---|---|
| `cs_bff_get_operational_metrics` | Core operational KPIs | Total conversations, avg first response time, avg resolution time, AI resolution rate, human escalation rate, SLA compliance rate, conversations per agent. All with period comparison (vs previous period). |
| `cs_bff_get_conversation_volume` | Volume over time | Time series: conversation count by hour/day/week. Breakdowns: by channel, by status, by priority. For line/bar charts. |
| `cs_bff_get_busiest_hours` | Heatmap data | Conversation volume by day-of-week × hour-of-day. For heatmap visualization. |
| `cs_bff_get_queue_metrics` | Queue health | Current: unassigned conversations, avg wait time, oldest unanswered. Trend over selected period. |

### RPCs — AI Performance

| RPC | Purpose | Returns |
|---|---|---|
| `cs_bff_get_ai_performance` | AI agent KPIs | AI resolution rate (overall + by intent type), confidence score distribution, hallucination rate (from QA), action success/failure rates, avg AI response time (latency), cost per resolution (token cost estimate). |
| `cs_bff_get_unresolved_questions` | Knowledge gap report | Auto-grouped unresolved questions by topic (AI-generated topic names), volume per topic, trend, breakdown: AI didn't know vs customer requested human vs conversation abandoned. One-click path to create knowledge article. |
| `cs_bff_get_ai_vs_human` | Comparison | Side-by-side: AI resolution rate vs human, AI response time vs human, AI CSAT vs human CSAT. |

### RPCs — Customer Insights

| RPC | Purpose | Returns |
|---|---|---|
| `cs_bff_get_top_intents` | What customers ask about | Top intents by volume, trend over time, resolution rate per intent. |
| `cs_bff_get_sentiment_trend` | Sentiment over time | Positive/neutral/negative sentiment breakdown over time. |
| `cs_bff_get_repeat_contacts` | Repeat contact analysis | % of customers who contact again within 7/14/30 days about the same issue. |

### RPCs — Quality Assurance

| RPC | Purpose | Returns |
|---|---|---|
| `cs_bff_get_qa_scores` | QA scorecard summary | Overall score, per-criteria breakdown (accuracy, tone, policy compliance, resolution quality), trend over time. Per-agent and per-AI breakdown. |
| `cs_bff_get_flagged_conversations` | Needs review | Conversations flagged for: low confidence, negative sentiment, policy deviation, low QA score. Drill down to conversation. |

### RPCs — CSAT

| RPC | Purpose | Returns |
|---|---|---|
| `cs_bff_get_csat_metrics` | CSAT overview | Average rating, response rate, distribution (1-5 stars), trend over time. Breakdown by channel, agent, AI vs human, intent type. |
| `cs_bff_get_csat_feedback` | Verbatim feedback | Recent CSAT responses with text feedback, linked to conversation. |

### RPCs — Agent Performance

| RPC | Purpose | Returns |
|---|---|---|
| `cs_bff_get_agent_performance` | Per-agent metrics | For each agent: conversation count, avg response time, avg resolution time, CSAT score, SLA compliance, QA score. Sortable leaderboard. |
| `cs_bff_get_agent_activity` | Agent activity log | For a specific agent: conversations handled, actions taken, status timeline (online/away/offline), utilization rate. |

### Common Parameters

All analytics RPCs accept:
- `p_date_from` / `p_date_to` — date range
- `p_channel` — optional channel filter
- `p_team_id` — optional team filter
- `p_agent_id` — optional agent filter
- `p_granularity` — `hour`, `day`, `week`, `month` (for time series)

---

## Key Domain Concepts the UI Must Support

### 1. Executive Summary

Top-level KPI cards showing the most important numbers:
- Total conversations (period)
- AI resolution rate
- Average first response time
- SLA compliance rate
- CSAT score
- Each with trend indicator (up/down vs previous period)

### 2. AI Performance Section

The unique value prop — how well is the AI performing:
- Resolution rate by intent (refund: 85%, product question: 92%, complaint: 40%)
- Unresolved questions report (knowledge gaps — which topics need content)
- AI vs Human comparison (side-by-side metrics)
- Cost per resolution (LLM costs)

### 3. Procedure Analytics

Per-procedure metrics:
- Resolution rate, escalation rate, avg handle time per procedure
- Step-level analytics: where do customers drop off or escalate?
- Branch analysis: which decision paths are most common?

### 4. SLA Dashboard

- Overall compliance rate
- Breach count and trend
- Approaching breaches (need attention now)
- Per-channel and per-team SLA performance

### 5. Agent Leaderboard

Per-agent metrics in a sortable table. Coaching insights: identify agents who need improvement with specific examples.

---

## Key UX Requirements

1. Date range picker is global (applies to all sections). Common presets: Today, Last 7 days, Last 30 days, Custom range.

2. Drill-down from any metric to the underlying conversations. Clicking "85% AI resolution for refunds" should show those conversations.

3. Charts should use ECharts. The AI should choose appropriate chart types per metric (line for trends, bar for comparisons, heatmap for busy hours, donut for distributions).

4. Export capability — download report data as CSV.

---

## What NOT to Build (Backend Handles These)

- Metric aggregation — backend pre-computes hourly/daily rollups
- QA scoring — backend AI evaluates 100% of conversations
- Sentiment analysis — backend classifies during conversation processing
- CSAT prediction — backend ML model predicts from conversation content
