# CS Analytics

Operational dashboards, **AI performance**, customer insights, **CSAT**, and QA workflows for CS leadership — via deployed `cs_bff_get_analytics_*` BFFs.

Owner surfaces: loyalty-admin **CS Analytics**, **CS Supervisor**, **CS Case Logs**

## Concept

**Operational metric** — Volume, handle time, queue depth, SLA compliance.

**AI metric** — Autonomous resolution rate, latency, action success, intent breakdown.

**CSAT** — Post-resolution score on conversation/ticket; capture via BFF + message triggers.

**QA / Watchtower** — Automated scoring and NL monitors `(mostly planned narrative)`.

## Rules

- **Deployed aggregates** — `cs_bff_get_analytics_overview`, `_timeseries`, `_by_agent`, `_by_team`, `cs_bff_list_analytics_cases`.
- **CSAT** — `cs_bff_submit_csat`; trigger capture via message/flow rules — idempotent per conversation policy (verify BFF).
- **Menu** — `bff_get_analytics_menu` exposes CS entries when entitled.
- **Watchtower, 100% auto-QA, predicted CSAT** — not in registry as standalone services — treat as roadmap unless shipped in FE.
- Loyalty **BigQuery** dashboards remain **`Analytics.md`** — separate from CS Postgres BFFs.

## Journeys

### Admin journey

| Knob | Effect |
| --- | --- |
| Date range | All CS analytics BFFs |
| CSAT settings | When/how survey fires `(workflow + product)` |

| Page | Owning repo | BFF |
| --- | --- | --- |
| **CS Analytics** | loyalty-admin | `cs_bff_get_analytics_*` |
| **CS Supervisor** | loyalty-admin | Team views `(verify components)` |
| **CS Case Logs** | loyalty-admin | Case/event oriented lists |

1. Open overview → filter channel/team/date.
2. Drill agent or team breakdown.
3. Review case list for QA sampling.
4. Feed unresolved themes into **CS Knowledge** articles.

### Member journey

CSAT prompt after resolve when channel supports it (stars/thumbs — channel-specific).

## System

### Functions

| BFF | Role |
| --- | --- |
| `cs_bff_get_analytics_overview` | Headline KPIs |
| `cs_bff_get_analytics_timeseries` | Trends |
| `cs_bff_get_analytics_by_agent` / `_by_team` | Breakdowns |
| `cs_bff_list_analytics_cases` | Case-level drill |
| `cs_bff_submit_csat` | Record score/comment |

Sources: `cs_conversations`, `cs_messages`, `cs_conversation_events`, `cs_tickets`, SLA columns, CSAT fields.

### Planned metrics (legacy §7 — not verified deployed)

- Unresolved question clustering with one-click article create.
- Full Watchtower NL monitors with Slack/LINE alerting.
- Auto-QA scorecards on 100% of conversations.
- AI-predicted CSAT without survey.

Track in product backlog; do not sell as live without FE + backend proof.

### Known gaps

- BQ export path for CS may be partial vs loyalty `analytics-query` edge.
- Supervisor real-time shadow mode — inbox product, not analytics BFF.

## Related

- **CS_SLA.md** — Compliance inputs.
- **CS_Knowledge_Base.md** — Close gaps from unresolved reports.
- **CS_AI_Pipeline.md** — AI resolution and cost metrics source events.
- **Analytics.md** — Loyalty warehouse reports.
