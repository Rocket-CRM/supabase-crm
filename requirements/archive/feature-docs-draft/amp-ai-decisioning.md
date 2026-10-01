# Feature Guide: AMP AI Decisioning

## 1. Overview

AMP AI Decisioning replaces static if/then marketing automation with an AI agent that makes per-user decisions in real time. Instead of a marketer building a rule that says "if inactive 30 days, send 100 points," the marketer defines an objective ("re-engage lapsed customers"), configures which actions the AI may use (award points, send LINE messages, assign tags), and sets constraints (budget, frequency limits). The AI then decides — for each individual user — whether to act, what to do, and when.

The system's default posture is observational. When a workflow trigger fires, the AI assesses the user's context (purchase history, point balance, recent activity), checks constraint headroom, and usually decides to **wait**. Over multiple deliberation cycles — spaced days apart — the AI re-evaluates with fresh data until the timing is right. Expected distribution across all triggers: 15-20% act, 60-70% wait (then eventually act or skip), 10-20% skip immediately.

Agents are reusable entities, independent of any single workflow. One agent can be referenced by multiple campaigns. Performance data (conversion rates, action effectiveness) aggregates across all workflows using that agent — so the AI learns from every campaign it participates in.

## 2. Key Concepts

**Agent** — A reusable AI configuration that defines how the AI reasons about a specific marketing goal. Contains an objective, tone, allowed actions, constraints, and deliberation settings. Created in the Agent Builder and referenced by workflow agent nodes. Example: "Win-Back VIPs" agent with objective `re_engage`, 3 allowed actions, max 500 points/month budget.

**Agent Action** — A specific action the AI is permitted to use, configured per-agent. Each action has a type (e.g., `award_points`), variable ranges the AI can choose within (e.g., 50–500 points), per-action constraints, and eligibility conditions. The AI only sees the actions explicitly configured — not the merchant's full catalog.

**Objective** — The strategic approach the AI takes when reasoning. Values: `re_engage`, `drive_purchase`, `redeem_points`, `tier_upgrade`, `win_back`, `upsell`. Shapes the AI's reasoning style — two agents with the same outcome but different objectives reason differently.

**Tone** — Communication style for AI-generated messages. Values: `urgent`, `friendly`, `exclusive`, `celebratory`.

**Context Hint** — Free-text guidance from the marketer to the AI. Example: "These are lapsed VIP customers who haven't purchased in 90 days." Included in the AI prompt alongside user data.

**Deliberation** — The observe-wait-act loop. On each cycle, the AI fetches fresh user data and decides: ACT (execute actions), WAIT (sleep and reassess later), or SKIP (user doesn't fit). Multiple cycles are spaced days apart, controlled by deliberation settings.

**Constraint** — A limit on agent behavior. Format: "No more than [limit] [metric] per [scope] per [time_window]." Metrics: `actions`, `points`, `tickets`, `messages`, `cost`. Scopes: `per_user`, `per_agent`. Windows: `per_day`, `per_week`, `per_month`. Enforced at two layers — the AI reads constraints and self-regulates, then MCP action tools enforce as a hard stop.

**Action Constraint** — Per-action limits on a single execution. Example: max 500 points per execution, 1,000 points budget per month. Distinct from agent-level constraints.

**Outcome** — A measurable event that defines success or failure for the agent. Each outcome has an event type (e.g., `purchase_completed`), a classification (`best` through `worst`), an attribution window, and optionally a weight column. One outcome per agent is marked primary — the main KPI.

**Attribution** — The process of linking an outcome event back to the agent action that likely caused it. If a user was actioned by the agent and then completed a purchase within the attribution window (e.g., 7 days), that purchase is attributed to the agent.

**Cost Normalization** — Converts action units to a normalized monetary value (THB). Points = 0.10 THB each, LINE message = 0.30 THB, SMS = 0.80 THB. Used for budget constraints and performance tracking.

**Scheduling Controls** — Time-based restrictions: cooldown hours (minimum gap between actions per user), quiet hours (suppress actions during off-hours), blackout dates (no actions on specific dates).

## 3. Configuration Reference

### Configuration Tab — Basic Info

| Setting | What it controls | Example | Default |
|---|---|---|---|
| Name | Agent display name | "Win-Back VIPs" | Required |
| Description | Internal description | "Re-engage customers inactive 90+ days" | Empty |
| Objective | AI reasoning approach | `re_engage` | None (select required) |
| Tone | Message style | `friendly` | None (select required) |
| Context Hint | Free-text AI guidance | "Lapsed VIP customers" | Empty |
| Max Actions Per Execution | Actions per user per cycle | 3 | 3 |

### Configuration Tab — Deliberation Settings (collapsible)

| Setting | What it controls | Example | Default |
|---|---|---|---|
| Max Cycles | Observe-wait-decide iterations | 5 | 3 |
| Default Wait | Sleep duration if AI doesn't specify | `2d` | `2d` |
| Max Wait | Cap on any single wait | `7d` | `7d` |
| Total Timeout | Maximum time from first to last cycle | `14d` | `14d` |

### Actions Tab

Each agent action row:

| Setting | What it controls | Example | Default |
|---|---|---|---|
| Action Type | Which MCP tool to use | `award_points` | Required (select) |
| Name | Display label | "Welcome bonus points" | Auto from type |
| Variable Config | Ranges the AI picks from | `amount: {min: 50, max: 500}` | Per action type |
| Action Constraints | Per-action execution limits | `max_amount_per_execution: 500` | None |
| Eligibility Conditions | User must meet these to receive this action | `points_balance < 1000` | None (all eligible) |
| Enabled | Toggle without deleting | true | true |

Available action types: `award_points`, `award_tickets`, `assign_tag`, `remove_tag`, `assign_persona`, `assign_earn_factor`, `submit_form`, `send_line_message`, `send_sms`, `add_to_audience`, `remove_from_audience`.

### Outcomes Tab

Each outcome row:

| Setting | What it controls | Example | Default |
|---|---|---|---|
| Event Type | What event to track | `purchase_completed` | Required (dropdown from seed table) |
| Classification | Success/failure ranking | `best` | From seed table default |
| Weight Column | Numeric column for value weighting | `final_amount` | None |
| Attribution Window | Hours after action to attribute | 168 (7 days) | From seed table |
| Counting Method | `cumulative` (every event) or `binary` (once) | `cumulative` | From seed table |
| Is Primary | Main KPI — one per agent | true | false |
| Target Conversion Rate | Goal rate for primary outcome | 0.20 (20%) | None |
| Event Filter | Optional condition on event properties | `amount > 500` | None |

### Scheduling & Guardrails Tab

| Setting | What it controls | Example | Default |
|---|---|---|---|
| Cooldown Hours | Min gap between actions per user | 24 | None (no cooldown) |
| Quiet Hours Enabled | Suppress actions during off-hours | true | false |
| Quiet Hours Start/End | Time window | 22:00–08:00 | 22:00–08:00 |
| Quiet Hours Timezone | Which timezone | Asia/Bangkok | Asia/Bangkok |
| Blackout Dates | Specific no-action dates | 2025-12-25 | Empty |

Agent-level constraint rows (natural-language builder):

| Component | Options | Example |
|---|---|---|
| Metric | actions, points, tickets, messages, cost | `points` |
| Limit | Numeric | `500` |
| Scope | per user, total | `per user` |
| Window | per execution, per day, per week, per month | `per month` |

Reads as: "No more than 500 points per user per month."

## 4. Admin Journey

**Repo:** `Rocket-CRM/loyalty-admin`

**Route map:**

| Page Name | Current Route | BFF / Data Source |
|---|---|---|
| Agent Builder (list) | `/agent-builder` | `bff_list_agents` |
| Agent Builder (editor) | `/agent-builder` (SPA view switch) | `bff_get_agent_full`, `bff_upsert_agent_with_children` |
| AMP Analytics | `/amp-analytics` | `bff_amp_analytics_overview`, `bff_amp_analytics_agent`, `bff_amp_analytics_user_timeline` |
| Workflow List | `/workflow-list` | (Workflow builder references agent by ID) |

### 4a. Create a New Agent

1. From **Agent Builder** list, click **"Create Agent"**
2. Editor opens with 4 tabs: **Configuration**, **Actions**, **Outcomes**, **Scheduling & Guardrails**
3. **Configuration tab**: fill name (required), description, select objective and tone, add context hint, set max actions per execution. Optionally expand Deliberation Settings to adjust cycle count and wait durations
4. **Actions tab**: click **"+ Add Action"** to add action rows. For each: select action type, set variable ranges (e.g., points min/max), configure action constraints, add eligibility conditions
5. **Outcomes tab**: click **"+ Add Outcome"** to add outcome rows. Select event type from dropdown (pre-populates classification, attribution window, counting method from seed table). Set one outcome as primary with a target conversion rate
6. **Scheduling & Guardrails tab**: set cooldown hours, enable quiet hours with time window, add blackout dates. Add agent-level constraints using the natural-language builder ("No more than X metric per scope per window")
7. Click **"Save"** — calls `bff_upsert_agent_with_children` to save agent + actions + outcomes atomically
8. Return to agent list

### 4b. Edit an Existing Agent

1. From **Agent Builder** list, click any agent row
2. Editor opens pre-populated — all 4 tabs editable
3. Modify, then **"Save"**. **"Discard"** reverts to last saved state

### 4c. Manage Agent List

1. **Agent Builder** list shows: Name, Objective, Tone, Active badge, Action count, Outcome count, Created date
2. Toggle active/inactive directly from list

### 4d. Use Agent in a Workflow

1. From **Workflow List**, open or create a workflow
2. Add an agent node to the workflow graph
3. In the agent node sidebar, select an existing agent by name (stores `agent_config_id` reference)
4. Workflow routes on agent output: action taken → true handle, no action → false handle

### 4e. View Agent Performance

1. From **AMP Analytics**, click an agent row in the Agent Performance table
2. **Agent Detail** view shows: Users Actioned, Conversion Rate vs Target, Total Value, Average Hours to Conversion, Negative Outcome Rate
3. Charts: Conversion Gauge, Outcome Breakdown, Action Effectiveness, Deliberation Decision Distribution, Daily Activity, Cost Breakdown
4. Constraint usage cards with progress bars
5. Recent Decisions table — click any row to see **User Timeline**

### 4f. Common Admin Mistakes

- Creating an agent with no actions configured — AI has nothing to do, always skips
- Setting constraints too tight (e.g., 1 action per user per month) — agent rarely acts
- Not setting a primary outcome — performance tracking has no main KPI to optimize against
- Setting max deliberation cycles to 1 — eliminates the observe-wait pattern, agent becomes single-shot
- Forgetting to mark agent as active — workflow agent node silently skips

## 5. Member Experience

**Repo:** `Rocket-CRM/loyalty-user`

**Route map:**

| Page / Component | Current Route | Data Source |
|---|---|---|
| N/A — no direct member UI | — | — |

Members do not interact with AI Decisioning directly. There is no "AI agent" screen in the member app. Instead, members experience the *results* of AI decisions:

- **Points awarded** — appears in wallet balance and transaction history
- **LINE messages received** — personalized message in LINE chat
- **SMS received** — text message to phone
- **Tag assigned** — affects eligibility for rewards, missions, or campaigns
- **Persona changed** — alters catalog visibility and pricing
- **Earn factor assigned** — modifies points earning rate
- **Added to audience** — included in targeted campaign segments

The member sees the same UI as any other platform action — the only difference is that the AI chose the action, timing, and parameters rather than a static rule.

## 6. Perspectives

### 6a. For Customer Success / Support

**Elevator pitch:** "AI Decisioning lets the system decide what to send each customer and when, instead of one-size-fits-all rules. The marketer sets the goal and guardrails — the AI picks the right action for each person."

**Top 5 support questions:**

| Question | Answer |
|---|---|
| "Why did this member get 200 points instead of 100?" | The AI chose the amount within the configured range based on user context. Check the agent's action variable config for the allowed range, and the AMP Analytics User Timeline for the reasoning. |
| "A member says they got a message at 2 AM" | Check quiet hours settings on the agent — either quiet hours is disabled or the timezone is wrong. |
| "Why hasn't a member received anything from the campaign?" | The AI may have decided to WAIT or SKIP. Check AMP Analytics → User Timeline for deliberation history. The AI skips ~10-20% of users who don't fit. |
| "The agent isn't doing anything for anyone" | Check: is the agent active? Does it have actions configured? Are constraints too tight? Are eligibility conditions too narrow? |
| "A member received the same message twice" | Check cooldown_hours setting — if null, no gap is enforced. Check per_user constraints. |

### 6b. For Marketing

**Value proposition:** AI Decisioning shifts marketing from "blast everyone the same thing" to "let the AI figure out the right action for each person." A marketer defines the goal (re-engage, drive purchase, upsell), sets the budget and constraints, and the AI handles per-user personalization — choosing between awarding points, sending a message, adjusting earn factors, or doing nothing.

**Use-case stories:**

1. **Win-back campaign** — Agent objective: `win_back`. Allowed actions: award 50–500 points, send LINE message. AI sees a user hasn't purchased in 90 days → cycle 1: waits 3 days watching for organic return → cycle 2: user still inactive, awards 200 points + sends a LINE message with friendly tone. Constraint: max 500 points per user per month.

2. **Tier upgrade push** — Agent objective: `tier_upgrade`. Allowed actions: assign earn factor (2x multiplier), send LINE message. AI targets users close to the next tier threshold, nudging with a temporary earn boost at the right moment.

3. **Cross-sell personalization** — Agent objective: `upsell`. Actions: tag assignment, LINE message. AI identifies purchase patterns and assigns interest-based tags, then sends targeted product recommendations. Primary outcome: purchase within 7 days.

**Differentiators:**
- **Per-user decisioning** — each member gets individually assessed, not batch-processed
- **Observe-wait-act** — the AI watches and waits for the right moment rather than firing immediately
- **Budget-aware** — constraints prevent overspending; cost normalization tracks real monetary impact
- **Self-improving** — outcome attribution and performance tracking mean the AI learns which actions drive results

### 6c. For Testers

**Config → expected behavior:**

| Config | Expected behavior |
|---|---|
| Agent with 0 actions | AI always returns SKIP |
| Agent with constraints: 0 actions per_user per_day | All action attempts rejected by enforcement layer |
| Agent with max_deliberation_cycles = 1 | Single assessment, no wait cycles — act or skip immediately |
| Cooldown 24h, user actioned 1h ago | AI reads cooldown from constraints, skips or waits |
| Quiet hours 22:00–08:00 Bangkok, trigger at 23:00 Bangkok | Action suppressed until 08:00 |
| Blackout date = today | All actions suppressed for the day |
| Action with eligibility: points_balance < 1000, user has 1500 | That action excluded from AI's available options |
| Action variable_config: amount min=50 max=500, AI awards 600 | Rejected by action constraint enforcement |
| Primary outcome target = 0.20, actual = 0.12 | Performance summary shows "below target" |
| Agent used in 3 workflows | Performance aggregates across all 3 workflows |

**Business rules as assertions:**

- ASSERT: AI decision is one of `act`, `wait`, or `skip` — no other values
- ASSERT: When AI decides `wait`, a `wait_duration` and `watching_for` are returned
- ASSERT: When AI decides `act`, executed actions stay within variable_config ranges
- ASSERT: Constraint enforcement rejects any action that would exceed a limit, even if the AI chose it
- ASSERT: After max_deliberation_cycles reached without action, status = `exhausted`, routes false
- ASSERT: Deliberation timeout exceeded → deliberation stops, routes false
- ASSERT: Agent-level constraint and action-level constraint both apply — stricter one wins
- ASSERT: Outcome attribution only counts events within attribution_window_hours of the action
- ASSERT: Only one outcome per agent can have `is_primary = true`
- ASSERT: Cost is tracked per action: points = 1/point, LINE = 1/message, SMS = 2/message, tags/personas = 0

**Decision status model:**

| Status | Event Type | When |
|---|---|---|
| `acted` | `agent_decided_act` | AI executed one or more actions |
| `waiting` | `agent_decided_wait` | AI deferred, will reassess after sleep |
| `skipped` | `agent_decided_skip` | AI determined user doesn't fit |
| `exhausted` | `agent_decided_skip` | Max cycles reached with no action |

Each log entry includes: cycle number, decision, reasoning, watching_for (if wait), wait_duration (if wait), actions_taken (if act).

**Deliberation timeline test:** Verify in `amp_workflow_log` — filter by `event_type LIKE 'agent_decided_%'` for a specific user + workflow, ordered by `created_at`. Should show sequential cycles with increasing cycle numbers.

## 7. Business Rules

**Rule:** The AI's default posture is observational — most triggers result in WAIT, not ACT.
**Example:** 100 users enter a win-back workflow → ~15 get immediate action, ~65 enter deliberation (wait-and-reassess), ~20 are skipped.

**Rule:** Constraints are enforced at two layers — AI self-regulation and MCP hard stop. Both use the same usage data.
**Example:** AI reads "3 actions remaining this week" → picks one action. If the AI somehow requests 4, the MCP tool rejects the 4th.

**Rule:** The AI only sees actions explicitly configured for the agent. Ineligible actions (by user eligibility) are structurally removed before the AI reasons.
**Example:** Agent has "award_points" with eligibility "balance < 1000". User has 1500 balance → the AI never sees the points action in its tool list.

**Rule:** Agent performance aggregates across all workflows referencing that agent.
**Example:** "Win-Back VIPs" agent used in 3 campaigns → performance summary reflects all 3 campaigns' outcomes combined.

**Rule:** Outcome attribution uses a per-outcome window. Different outcomes can have different windows.
**Example:** Purchase attribution = 168 hours (7 days). Email click attribution = 2 hours. Both tracked for the same agent.

**Rule:** One primary outcome per agent, enforced by partial unique index.
**Example:** Attempt to set two outcomes as primary → database rejects the second.

**Rule:** Deliberation history is passed to the AI in each cycle. The AI compares "what I was watching for" against fresh user data.
**Example:** Cycle 0: AI says "wait 3 days, watching for a purchase." Cycle 1: AI sees no purchase occurred → decides to act with 200 points.

**Rule:** Cost normalization converts action units to THB. Points = 0.10 THB/point, LINE = 0.30 THB/message, SMS = 0.80 THB/message.
**Example:** Awarding 200 points costs 20 THB normalized. A "cost < 1000 per agent per month" constraint tracks against this normalized value.

**Rule:** Agent scheduling controls override workflow-level scheduling for agent nodes.
**Example:** Workflow has cooldown 12h, agent has cooldown 24h → agent's 24h cooldown applies.

**Rule:** Constraint usage is pre-computed every 10 minutes via pg_cron, cached in Redis (10-min TTL). Usage data can be up to ~20 minutes stale — conservative (never over-counts).
**Example:** Agent awarded points 5 minutes ago → constraint cache may not reflect it yet, but enforcement layer prevents double-spend.

## 8. Related Features

| Feature | Connection to AMP AI Decisioning |
|---|---|
| AMP Workflows (Rule-Based) | AI Decisioning agents are placed as nodes within AMP workflows. Rule-based and AI nodes can coexist in the same workflow. See `AMP - Rule Based.md`. |
| Currency | `award_points` and `award_tickets` actions deduct from / add to member wallets. See `Currency.md`. |
| Rewards | AI can influence redemption behavior through point awards and persona changes that affect eligibility and pricing. See `Reward.md`. |
| Tags & Personas | `assign_tag`, `remove_tag`, and `assign_persona` actions modify member profiles. See `Tag_and_Persona.md`. |
| Activity/Earning | `assign_earn_factor` action modifies the member's points earning multiplier. See `Activity_Based_Earning.md`. |
| Forms | `submit_form` action can trigger form-related workflows. See `Forms.md`. |
| Audiences | `add_to_audience` and `remove_from_audience` actions manage segment membership. |
